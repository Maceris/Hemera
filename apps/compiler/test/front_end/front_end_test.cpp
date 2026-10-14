#include <filesystem>
#include <fstream>
#include <regex>
#include <set>
#include <string>
#include <vector>

#include "gtest/gtest.h"

#include "hemera_errors.h"
#include "cmd_line/options.h"
#include "error/reporting.h"
#include "front_end/front_end.h"
#include "front_end/info.h"
#include "front_end/mlir_generation.h"
#include "front_end/names.h"
#include "hmir/hmir_dialect.h"
#include "lexer/lexer.h"
#include "parser/parser.h"
#include "../string_cache_guard.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/BuiltinDialect.h"
#include "mlir/IR/Verifier.h"

using hemera::Allocator;
using hemera::MyVector;
using hemera::Token;

// The reported errors' codes, like "E4002 E4005", for failure messages.
static std::string codes(const std::vector<hemera::ErrorCode>& errors) {
	std::string result;
	for (hemera::ErrorCode code : errors) {
		result += hemera::error_info_map->find(code)->second.string_value;
		result += " ";
	}
	return result;
}

static std::filesystem::path scenario(std::string_view name) {
	return std::filesystem::path(__FILE__).remove_filename() / "scenarios" / name;
}

/*
 * An MLIR context, builder and module with the dialects the front end emits,
 * and the ProgramInfo built on them.
 */
struct FrontEndFixture {
	mlir::MLIRContext context;
	mlir::OpBuilder builder;
	mlir::ModuleOp module;
	hemera::ProgramInfo* program_info;

	FrontEndFixture()
		: context{}
		, builder{ &context }
		, module{}
		, program_info{ nullptr }
	{
		context.loadDialect<mlir::BuiltinDialect>();
		context.loadDialect<mlir::func::FuncDialect>();
		context.loadDialect<hmir::HemeraDialect>();
		module = mlir::ModuleOp::create(builder, builder.getUnknownLoc(), "test");
		program_info = new hemera::ProgramInfo(&context, &builder, &module);
	}

	~FrontEndFixture() {
		delete program_info;
		module.erase();
	}

	FrontEndFixture(const FrontEndFixture&) = delete;
	FrontEndFixture(FrontEndFixture&&) = delete;
	FrontEndFixture& operator=(const FrontEndFixture&) = delete;
	FrontEndFixture& operator=(FrontEndFixture&&) = delete;
};

/*
 * Runs the front end on a package, with std at std_path if given.
 * Returns the errors it reported.
 */
static std::vector<hemera::ErrorCode> process_package(FrontEndFixture& fixture,
	const std::filesystem::path& package, const std::filesystem::path& std_path = {}) {

	hemera::reset_reporting_storage();

	hemera::Options options;
	options.input = std::filesystem::canonical(package);
	if (!std_path.empty()) {
		options.builtin_paths[hemera::BuiltinPackage::STD] = std::filesystem::canonical(std_path);
	}

	hemera::kick_off_processing(fixture.program_info, &options);

	return *hemera::error_list();
}

TEST(FrontEnd, FollowsImports)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture,
		scenario("imports/main"), scenario("imports/fake_std"));

	EXPECT_TRUE(errors.empty()) << codes(errors);
	// main, neighbor, fake_io and deep, each once even though main is imported back and fake_io twice
	EXPECT_EQ(fixture.program_info->packages.size(), 4);
}

TEST(FrontEnd, ReportsMissingImport)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("missing_import"));

	ASSERT_EQ(errors.size(), 1) << codes(errors);
	EXPECT_EQ(errors[0], hemera::ErrorCode::E4005);
}

TEST(FrontEnd, AcceptsIfChain)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("if_chain"));

	EXPECT_TRUE(errors.empty()) << codes(errors);
}

TEST(FrontEnd, ReportsElseWithoutIf)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("stray_else"));

	ASSERT_EQ(errors.size(), 1) << codes(errors);
	EXPECT_EQ(errors[0], hemera::ErrorCode::E4002);
}

TEST(FrontEnd, GeneratesValidFunctions)
{
	hemera::reset_reporting_storage();
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::string file_path = (scenario("functions") / "functions.hsc").generic_string();
	std::ifstream file(file_path);
	ASSERT_TRUE(file.is_open());

	Allocator<> token_alloc;
	MyVector<Token> tokens;
	hemera::lexer::lex(file, tokens, token_alloc, file_path);
	hemera::ast::Node* ast = hemera::parser::file(file_path, tokens,
		fixture.program_info->node_alloc);
	ASSERT_NE(ast, nullptr);
	ASSERT_EQ(hemera::error_count(), 0);

	hemera::FileInfo file_info;
	file_info.full_path = hemera::intern(file_path);

	std::vector<hemera::FunctionInfo*> functions;
	for (hemera::ast::Node* child : ast->children) {
		if (hemera::ast::NodeType::DEFINITION != child->node_type) {
			continue;
		}
		hemera::FunctionInfo* function = new hemera::FunctionInfo();
		function->node = child;
		function->file = &file_info;
		functions.push_back(function);

		EXPECT_TRUE(hemera::mlir_process_function(fixture.program_info, function));
	}

	EXPECT_TRUE(mlir::succeeded(mlir::verify(fixture.module)));

	mlir::func::FuncOp answer = fixture.module.lookupSymbol<mlir::func::FuncOp>("answer");
	ASSERT_TRUE(answer);
	EXPECT_FALSE(answer.isExternal());

	mlir::func::FuncOp values = fixture.module.lookupSymbol<mlir::func::FuncOp>("values");
	EXPECT_TRUE(values);

	mlir::func::FuncOp trap = fixture.module.lookupSymbol<mlir::func::FuncOp>("trap");
	ASSERT_TRUE(trap);
	EXPECT_TRUE(trap.isExternal());

	for (hemera::FunctionInfo* function : functions) {
		delete function;
	}
}

static hemera::Declaration* find_declaration(FrontEndFixture& fixture,
	const std::filesystem::path& package, std::string_view name) {

	hemera::InternedString package_path = hemera::intern(std::filesystem::canonical(package).string());
	hemera::InternedString interned = hemera::intern(std::string(name));
	auto& declarations = fixture.program_info->names.declarations;
	auto iter = declarations.find(std::make_pair(package_path, interned));
	return iter == declarations.end() ? nullptr : iter->second;
}

TEST(FrontEnd, ResolvesNames)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("names_ok"));

	EXPECT_TRUE(errors.empty()) << codes(errors);
	for (std::string_view name : { "LIMIT", "Node", "Pair", "use", "COUNT", "Item", "Shape", "Mode", "LIB_VALUE" }) {
		hemera::Declaration* declaration = find_declaration(fixture, scenario("names_ok"), name);
		ASSERT_NE(declaration, nullptr) << name;
		EXPECT_TRUE(declaration->resolved) << name;
	}
}

TEST(FrontEnd, ReportsUndeclaredName)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("undeclared"));

	ASSERT_EQ(errors.size(), 1) << codes(errors);
	EXPECT_EQ(errors[0], hemera::ErrorCode::E4008);
}

TEST(FrontEnd, ReportsConstantCycle)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("constant_cycle"));

	ASSERT_EQ(errors.size(), 1) << codes(errors);
	EXPECT_EQ(errors[0], hemera::ErrorCode::E4007);
}

TEST(FrontEnd, ReportsStructCycle)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("struct_cycle"));

	ASSERT_EQ(errors.size(), 1) << codes(errors);
	EXPECT_EQ(errors[0], hemera::ErrorCode::E4007);
}

TEST(FrontEnd, ReportsDuplicateDeclaration)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("duplicate"));

	ASSERT_EQ(errors.size(), 1) << codes(errors);
	EXPECT_EQ(errors[0], hemera::ErrorCode::E4009);
}

TEST(FrontEnd, EvaluatesIfConditions)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("if_constants"));

	EXPECT_TRUE(errors.empty()) << codes(errors);
	EXPECT_NE(find_declaration(fixture, scenario("if_constants"), "IN_KERNEL"), nullptr);
	EXPECT_EQ(find_declaration(fixture, scenario("if_constants"), "ONLY_LINUX"), nullptr);
}

TEST(FrontEnd, ReportsIfNeedingItsOwnDeclaration)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("if_needs_own_declaration"));

	ASSERT_EQ(errors.size(), 1) << codes(errors);
	EXPECT_EQ(errors[0], hemera::ErrorCode::E4007);
}

TEST(FrontEnd, ReportsIfConditionThatIsNotBoolean)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("if_not_bool"));

	ASSERT_EQ(errors.size(), 1) << codes(errors);
	EXPECT_EQ(errors[0], hemera::ErrorCode::E4010);
}

static std::filesystem::path hemera_root() {
	// apps/compiler/test/front_end/front_end_test.cpp
	return std::filesystem::path(__FILE__).parent_path().parent_path().parent_path()
		.parent_path().parent_path();
}

/*
 * Base is the interface to what the compiler provides, so the compiler doesn't read it.
 * This checks the names the compiler provides without an import against base/builtin.
 */
TEST(FrontEnd, BuiltinNamesMatchBase)
{
	std::set<std::string> in_base;
	const std::regex declaration(R"(^([A-Za-z_][A-Za-z0-9_]*)\s*(\[[^\]]*\])?\s*:)");
	for (const auto& entry : std::filesystem::directory_iterator(hemera_root() / "base" / "builtin")) {
		if (entry.path().extension() != ".hsc") {
			continue;
		}
		std::ifstream file(entry.path());
		std::string line;
		while (std::getline(file, line)) {
			std::smatch match;
			if (std::regex_search(line, match, declaration)) {
				in_base.insert(match[1].str());
			}
		}
	}
	ASSERT_FALSE(in_base.empty());

	std::set<std::string> in_compiler;
	for (std::string_view name : hemera::builtin_names()) {
		// The implicit context isn't declared in base
		if (name != "context") {
			in_compiler.insert(std::string(name));
		}
	}

	for (const std::string& name : in_base) {
		EXPECT_TRUE(in_compiler.contains(name)) << name << " is in base/builtin but not the compiler";
	}
	for (const std::string& name : in_compiler) {
		EXPECT_TRUE(in_base.contains(name)) << name << " is in the compiler but not base/builtin";
	}
}

/*
 * Every std package loads, with its imports, and every name its declarations use is declared,
 * with nothing stalled.
 */
TEST(FrontEnd, ResolvesStd)
{
	hemera::disable_reporting_printing();
	const std::filesystem::path std_path = hemera_root() / "std";

	for (const auto& entry : std::filesystem::recursive_directory_iterator(std_path)) {
		if (!entry.is_directory()) {
			continue;
		}
		bool has_source = false;
		for (const auto& file : std::filesystem::directory_iterator(entry.path())) {
			if (file.path().extension() == ".hsc") {
				has_source = true;
			}
		}
		if (!has_source) {
			continue;
		}
		StringCacheGuard string_cache;
		FrontEndFixture fixture;
		std::vector<hemera::ErrorCode> errors = process_package(fixture, entry.path(), std_path);
		EXPECT_TRUE(errors.empty()) << entry.path().string() << ": " << codes(errors);
	}
}

TEST(FrontEnd, ReportsDuplicateFunction)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("duplicate_function"));

	ASSERT_EQ(errors.size(), 1) << codes(errors);
	EXPECT_EQ(errors[0], hemera::ErrorCode::E4009);
}

/*
 * docs/packages.md, Name Collision: the package's own name wins over its imports', a name only one
 * import declares can be used unqualified, and qualified names pick an import's.
 */
TEST(FrontEnd, ResolvesNameCollisions)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("collision_ok"));

	EXPECT_TRUE(errors.empty()) << codes(errors);
	for (std::string_view name : { "USES_OWN", "USES_A", "QUALIFIED", "SHARED" }) {
		hemera::Declaration* declaration = find_declaration(fixture, scenario("collision_ok"), name);
		ASSERT_NE(declaration, nullptr) << name;
		EXPECT_TRUE(declaration->resolved) << name;
	}
}

TEST(FrontEnd, ReportsAmbiguousName)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("collision_ambiguous"));

	ASSERT_EQ(errors.size(), 1) << codes(errors);
	EXPECT_EQ(errors[0], hemera::ErrorCode::E4012);
}

TEST(FrontEnd, EvaluatesIfConditionWithImportedName)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("if_uses_import"));

	EXPECT_TRUE(errors.empty()) << codes(errors);
	EXPECT_NE(find_declaration(fixture, scenario("if_uses_import"), "PICKED"), nullptr);
}

TEST(FrontEnd, ReportsIfDeclaringItsConditionsName)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("if_declares_used_import"));

	ASSERT_EQ(errors.size(), 1) << codes(errors);
	EXPECT_EQ(errors[0], hemera::ErrorCode::E4007);
}

TEST(FrontEnd, ResolvesPackageNameOverBuiltin)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("builtin_shadow"));

	EXPECT_TRUE(errors.empty()) << codes(errors);
	for (std::string_view name : { "Result", "convert", "WIDTH" }) {
		hemera::Declaration* declaration = find_declaration(fixture, scenario("builtin_shadow"), name);
		ASSERT_NE(declaration, nullptr) << name;
		EXPECT_TRUE(declaration->resolved) << name;
	}
}

TEST(FrontEnd, ReportsBuiltinNameDeclaredByAnImport)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("builtin_ambiguous"));

	ASSERT_EQ(errors.size(), 1) << codes(errors);
	EXPECT_EQ(errors[0], hemera::ErrorCode::E4012);
}

// docs/packages.md, Names and #if: an #if waits only for the #if chains that may provide its names
TEST(FrontEnd, DecidesIfChainsInDependencyOrder)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("if_chains_ok"));

	EXPECT_TRUE(errors.empty()) << codes(errors);
	EXPECT_NE(find_declaration(fixture, scenario("if_chains_ok"), "PICKED"), nullptr);
	EXPECT_EQ(find_declaration(fixture, scenario("if_chains_ok"), "BAT"), nullptr);
}

TEST(FrontEnd, ReportsIfChainsThatNeedEachOther)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("if_chains_cycle"));

	ASSERT_EQ(errors.size(), 1) << codes(errors);
	EXPECT_EQ(errors[0], hemera::ErrorCode::E4007);
}

TEST(FrontEnd, FindsNamesWithoutWaitingForUnrelatedImports)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("if_kernel"));

	EXPECT_TRUE(errors.empty()) << codes(errors);
	EXPECT_NE(find_declaration(fixture, scenario("if_kernel"), "HOSTED"), nullptr);
}

TEST(FrontEnd, ReportsNameMadeAmbiguousByAnIfImport)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("if_late_ambiguous"));

	ASSERT_EQ(errors.size(), 1) << codes(errors);
	EXPECT_EQ(errors[0], hemera::ErrorCode::E4012);
}

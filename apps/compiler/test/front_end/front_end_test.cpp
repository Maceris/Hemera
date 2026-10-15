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
	size_t loaded = 0;
	for (const auto& [path, package] : fixture.program_info->packages) {
		if (!hemera::is_base_package(path)) {
			++loaded;
		}
	}
	EXPECT_EQ(loaded, 4u);
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
/*
 * Every declaration resolved to its type information: a type is laid out, and a function that
 * isn't generic has its signature. Constants' types may wait for type checking.
 */
static bool is_generic_function(const hemera::Declaration& declaration) {
	for (const hemera::ast::Node* child : declaration.node->children) {
		if (hemera::ast::NodeType::FUNCTION != child->node_type) {
			continue;
		}
		for (const hemera::ast::Node* part : child->children) {
			if (hemera::ast::NodeType::GENERIC_TAG == part->node_type) {
				return true;
			}
		}
	}
	return false;
}

static void expect_typed(FrontEndFixture& fixture, std::string_view where) {
	size_t types = 0;
	for (const hemera::Declaration& declaration : fixture.program_info->names.storage) {
		const std::string name(std::string_view(*declaration.name));
		EXPECT_TRUE(declaration.resolved) << where << ": " << name;
		if (hemera::DeclarationKind::TYPE == declaration.kind) {
			++types;
			ASSERT_NE(declaration.type_value, nullptr) << where << ": " << name;
			EXPECT_TRUE(declaration.type_value->complete) << where << ": " << name;
		}
		if (hemera::DeclarationKind::FUNCTION == declaration.kind && !is_generic_function(declaration)) {
			EXPECT_NE(declaration.value_type, nullptr) << where << ": " << name;
		}
	}
	EXPECT_GT(types, 0u) << where;
}

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
		expect_typed(fixture, entry.path().string());
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

// Base is built into the compiler, and every package of it resolves
TEST(FrontEnd, ResolvesBase)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("base_all"));

	EXPECT_TRUE(errors.empty()) << codes(errors);
	expect_typed(fixture, "base");
	size_t from_base = 0;
	for (const hemera::Declaration& declaration : fixture.program_info->names.storage) {
		if (hemera::is_base_package(declaration.package_path)) {
			EXPECT_TRUE(declaration.resolved) << std::string_view(*declaration.name);
			++from_base;
		}
	}
	EXPECT_GT(from_base, 100u);
}

// The type a type declaration in the "types" scenario is.
static hemera::TypeInfo* declared_type(FrontEndFixture& fixture, std::string_view name) {
	hemera::Declaration* declaration = find_declaration(fixture, scenario("types"), name);
	return declaration != nullptr ? declaration->type_value : nullptr;
}

static hemera::TypeInfoStruct* declared_struct(FrontEndFixture& fixture, std::string_view name) {
	hemera::TypeInfo* type = declared_type(fixture, name);
	return type != nullptr && hemera::TypeInfoVariant::STRUCT == type->variant
		? static_cast<hemera::TypeInfoStruct*>(type) : nullptr;
}

static std::vector<size_t> offsets(const hemera::TypeInfoStruct* type) {
	std::vector<size_t> result;
	for (const hemera::StructMember& member : type->members) {
		result.push_back(member.offset);
	}
	return result;
}

// docs/types.md, Memory Layout, and the layout rules for structs, unions and enums
TEST(FrontEnd, LaysOutTypes)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("types"));
	ASSERT_TRUE(errors.empty()) << codes(errors);

	struct Expected {
		std::string_view name;
		size_t size;
		size_t alignment;
		std::vector<size_t> offsets;
	};
	for (const Expected& expected : std::vector<Expected>{
		{ "Mixed", 24, 8, { 0, 4, 8, 16 } },
		{ "Packed", 5, 1, { 0, 1 } },
		{ "Aligned", 16, 16, { 0 } },
		{ "PackedAligned", 8, 4, { 0, 1 } },
		{ "Floats", 8, 1, { 0, 4 } },
		{ "MoreComplex", 8, 8, { 0, 0, 0, 0, 0 } },
		{ "MyVec3", 12, 4, { 0, 8 } },
		{ "Node", 32, 8, { 0, 8, 16 } },
		{ "UsesPair", 32, 8, { 0, 16 } },
		{ "Strings", 120, 8, { 0, 16, 24, 40, 80, 96, 112 } },
		{ "Layouts", 72, 8, { 0, 16, 32 } },
	}) {
		hemera::TypeInfoStruct* type = declared_struct(fixture, expected.name);
		ASSERT_NE(type, nullptr) << expected.name;
		EXPECT_TRUE(type->complete) << expected.name;
		EXPECT_EQ(type->size, expected.size) << expected.name;
		EXPECT_EQ(type->alignment, expected.alignment) << expected.name;
		EXPECT_EQ(offsets(type), expected.offsets) << expected.name;
	}

	// The layouts runtime describes are the builtins'
	hemera::TypeInfoStruct* layouts = declared_struct(fixture, "Layouts");
	ASSERT_NE(layouts, nullptr);
	EXPECT_EQ(layouts->members[0].member_type->size, hemera::BUILTIN_string->size);
	EXPECT_EQ(layouts->members[1].member_type->size, 16u);
	EXPECT_EQ(offsets(static_cast<hemera::TypeInfoStruct*>(layouts->members[2].member_type)),
		(std::vector<size_t>{ 0, 8, 16, 24 }));
	hemera::TypeInfoStruct* strings = declared_struct(fixture, "Strings");
	ASSERT_NE(strings, nullptr);
	EXPECT_EQ(strings->members[3].member_type->size, layouts->members[2].member_type->size);
	EXPECT_EQ(hemera::BUILTIN_any->size, 16u);

	// Enums
	auto suit = static_cast<hemera::TypeInfoEnum*>(declared_type(fixture, "Suit"));
	ASSERT_NE(suit, nullptr);
	EXPECT_EQ(suit->size, 1u);
	EXPECT_EQ(suit->backing_type, hemera::BUILTIN_u8);
	auto level = static_cast<hemera::TypeInfoEnum*>(declared_type(fixture, "LogLevel"));
	ASSERT_NE(level, nullptr);
	EXPECT_EQ(level->size, 8u);
	EXPECT_EQ(level->values, (std::vector<uint64_t>{ 0, 10, 20, 21 }));

	// Unions: the tag, then each variant's values
	auto shape = static_cast<hemera::TypeInfoUnion*>(declared_type(fixture, "Shape"));
	ASSERT_NE(shape, nullptr);
	EXPECT_EQ(shape->tag_type, hemera::BUILTIN_u8);
	EXPECT_EQ(shape->size, 16u);
	EXPECT_EQ(shape->alignment, 8u);
	ASSERT_EQ(shape->variants.size(), 3u);
	EXPECT_EQ(shape->variants[0].offsets, (std::vector<size_t>{ 4 }));
	EXPECT_EQ(shape->variants[1].offsets, (std::vector<size_t>{ 1, 8 }));
	EXPECT_TRUE(shape->variants[2].offsets.empty());

	// Optional values are instances of base/builtin's Optional
	const hemera::TypeInfo* maybe_int = hemera::get_base_type(declared_type(fixture, "MaybeInt"));
	ASSERT_NE(maybe_int, nullptr);
	EXPECT_EQ(maybe_int->variant, hemera::TypeInfoVariant::UNION);
	EXPECT_EQ(maybe_int->size, 16u);
	EXPECT_EQ(hemera::to_string(maybe_int), "Optional[int]");

	// Aliases
	EXPECT_TRUE(hemera::same_type(declared_type(fixture, "index"), hemera::BUILTIN_int));
	EXPECT_FALSE(hemera::same_type(declared_type(fixture, "counter"), hemera::BUILTIN_int));
	EXPECT_EQ(declared_type(fixture, "my_int")->size, 4u);
}

TEST(FrontEnd, TypesFunctionsAndConstants)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("types"));
	ASSERT_TRUE(errors.empty()) << codes(errors);

	auto handler = static_cast<hemera::TypeInfoFunction*>(declared_type(fixture, "Handler"));
	ASSERT_NE(handler, nullptr);
	EXPECT_EQ(hemera::to_string(handler), "fn(int, string) -> bool");

	hemera::Declaration* handle = find_declaration(fixture, scenario("types"), "handle");
	ASSERT_NE(handle, nullptr);
	auto function = static_cast<hemera::TypeInfoFunction*>(handle->value_type);
	ASSERT_NE(function, nullptr);
	ASSERT_EQ(function->input.size(), 3u);
	EXPECT_TRUE(function->input[1].is_escaping);
	EXPECT_TRUE(function->input[2].is_varargs);
	ASSERT_EQ(function->output.size(), 2u);
	EXPECT_EQ(std::string_view(*function->output[1].name), "count");
	EXPECT_EQ(function->output[1].type, hemera::BUILTIN_usize);
	EXPECT_TRUE(function->never_returns);

	auto value_type = [&](std::string_view name) {
		hemera::Declaration* declaration = find_declaration(fixture, scenario("types"), name);
		return declaration != nullptr ? declaration->value_type : nullptr;
	};
	EXPECT_EQ(hemera::to_string(value_type("intrinsic")), "fn(int) -> int");
	EXPECT_EQ(value_type("COUNT"), hemera::BUILTIN_u8);
	EXPECT_EQ(value_type("UNTYPED"), nullptr);
	EXPECT_EQ(value_type("SAME_AS_COUNT"), hemera::BUILTIN_u8);
	EXPECT_EQ(value_type("SUIT"), declared_type(fixture, "Suit"));
	EXPECT_EQ(hemera::to_string(value_type("BYTES")), "u8[3]");
}

// docs/directives.md, #externally_initialized and #section
TEST(FrontEnd, RecordsExternallyInitializedConstants)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("external_ok"));
	ASSERT_TRUE(errors.empty()) << codes(errors);

	hemera::Declaration* start = find_declaration(fixture, scenario("external_ok"), "START");
	ASSERT_NE(start, nullptr);
	EXPECT_TRUE(start->externally_initialized);
	ASSERT_NE(start->section, nullptr);
	EXPECT_EQ(std::string_view(*start->section), ".requests_start");
	EXPECT_EQ(hemera::to_string(start->value_type), "Marker");
	hemera::Declaration* plain = find_declaration(fixture, scenario("external_ok"), "PLAIN");
	ASSERT_NE(plain, nullptr);
	EXPECT_TRUE(plain->externally_initialized);
	EXPECT_EQ(plain->section, nullptr);
}

TEST(FrontEnd, ReportsSectionWithoutExternallyInitialized)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("section_alone"));

	ASSERT_EQ(errors.size(), 1) << codes(errors);
	EXPECT_EQ(errors[0], hemera::ErrorCode::E4014);
}

TEST(FrontEnd, ReportsReadingExternallyInitializedAtCompileTime)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("external_in_if"));

	ASSERT_EQ(errors.size(), 1) << codes(errors);
	EXPECT_EQ(errors[0], hemera::ErrorCode::E4010);
}

TEST(FrontEnd, ReportsTypeErrors)
{
	hemera::disable_reporting_printing();
	for (const auto& [name, expected] : std::vector<std::pair<std::string_view, hemera::ErrorCode>>{
		{ "not_a_type", hemera::ErrorCode::E4013 },
		{ "signed_enum", hemera::ErrorCode::E4014 },
		{ "generic_arguments", hemera::ErrorCode::E4014 },
	}) {
		StringCacheGuard string_cache;
		FrontEndFixture fixture;
		std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario(name));
		ASSERT_EQ(errors.size(), 1) << name << ": " << codes(errors);
		EXPECT_EQ(errors[0], expected) << name;
	}
}

// One error each, for the rules of docs/operators.md, docs/control_flow.md and docs/functions.md
TEST(FrontEnd, ReportsBodyErrors)
{
	hemera::disable_reporting_printing();
	for (const auto& [name, expected] : std::vector<std::pair<std::string_view, hemera::ErrorCode>>{
		{ "assign_constant", hemera::ErrorCode::E4016 },
		{ "assign_through_pointer", hemera::ErrorCode::E4016 },
		{ "assign_context", hemera::ErrorCode::E4016 },
		{ "mutable_pointer_into_context", hemera::ErrorCode::E4015 },
		{ "missing_return", hemera::ErrorCode::E4019 },
		{ "never_returns_finishes", hemera::ErrorCode::E4019 },
		{ "unreachable", hemera::ErrorCode::E4025 },
		{ "match_not_exhaustive", hemera::ErrorCode::E4026 },
		{ "wrong_arguments", hemera::ErrorCode::E4018 },
		{ "break_outside_loop", hemera::ErrorCode::E4022 },
		{ "type_mismatch", hemera::ErrorCode::E4015 },
		{ "unknown_member", hemera::ErrorCode::E4017 },
		{ "not_callable", hemera::ErrorCode::E4021 },
		{ "unbound_generic", hemera::ErrorCode::E4023 },
		{ "return_count", hemera::ErrorCode::E4004 },
		{ "no_context", hemera::ErrorCode::E4027 },
		{ "operator_types", hemera::ErrorCode::E4015 },
		{ "match_assigned", hemera::ErrorCode::E4020 },
		{ "call_without_context", hemera::ErrorCode::E4027 }
	}) {
		StringCacheGuard string_cache;
		FrontEndFixture fixture;
		std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("body_errors") / name);
		ASSERT_EQ(errors.size(), 1) << name << ": " << codes(errors);
		EXPECT_EQ(errors[0], expected) << name;
	}
}

TEST(FrontEnd, ChecksBodies)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("bodies_ok"));

	EXPECT_TRUE(errors.empty()) << codes(errors);
}

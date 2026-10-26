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

// The reported errors' codes and their messages, one to a line, for failure messages that say what went wrong.
static std::string reported(const std::vector<hemera::ErrorCode>& errors) {
	std::string result = codes(errors);
	for (const std::string& message : *hemera::error_messages()) {
		result += "\n" + message;
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

// docs/compilation.md, The Top Level: a name the package's own #insert declares wins over an import's, once it's run
TEST(FrontEnd, ResolvesInsertedNameOverImport)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("insert_shadows_import"));

	EXPECT_TRUE(errors.empty()) << codes(errors);
	hemera::Declaration* declaration = find_declaration(fixture, scenario("insert_shadows_import"), "USES_OWN");
	ASSERT_NE(declaration, nullptr);
	EXPECT_TRUE(declaration->resolved);
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
		{ "for_directive", hemera::ErrorCode::E4020 },
		{ "type_mismatch", hemera::ErrorCode::E4015 },
		{ "unknown_member", hemera::ErrorCode::E4017 },
		{ "not_callable", hemera::ErrorCode::E4021 },
		{ "unbound_generic", hemera::ErrorCode::E4023 },
		{ "return_count", hemera::ErrorCode::E4004 },
		{ "no_context", hemera::ErrorCode::E4027 },
		{ "no_context_generic", hemera::ErrorCode::E4027 },
		{ "operator_types", hemera::ErrorCode::E4015 },
		{ "match_assigned", hemera::ErrorCode::E4020 },
		{ "call_without_context", hemera::ErrorCode::E4027 },
		{ "break_too_far", hemera::ErrorCode::E4022 },
		{ "assert_false", hemera::ErrorCode::E4010 },
		{ "compile_time_variable", hemera::ErrorCode::E4010 },
		{ "compile_time_cycle", hemera::ErrorCode::E4007 },
		{ "compile_time_assert", hemera::ErrorCode::E4010 },
		{ "compile_time_calls_error", hemera::ErrorCode::E4015 },
		{ "compile_time_assertion", hemera::ErrorCode::E4029 },
		{ "compile_time_trap", hemera::ErrorCode::E4029 },
		{ "file_data_missing", hemera::ErrorCode::E4028 },
		{ "file_data_not_string", hemera::ErrorCode::E4014 },
		{ "null_pointer", hemera::ErrorCode::E4015 },
		{ "default_mismatch", hemera::ErrorCode::E4015 },
		{ "foreign_with_body", hemera::ErrorCode::E4014 },
		{ "foreign_not_library", hemera::ErrorCode::E4014 },
		{ "foreign_convention", hemera::ErrorCode::E4014 },
		{ "link_name_alone", hemera::ErrorCode::E4014 },
		{ "stack_return_local", hemera::ErrorCode::E4030 },
		{ "stack_outlives_block", hemera::ErrorCode::E4030 },
		{ "stack_pointer_to_holder", hemera::ErrorCode::E4030 },
		{ "stack_escaping_argument", hemera::ErrorCode::E4030 },
		{ "stack_keeps_parameter", hemera::ErrorCode::E4030 },
		{ "stack_parameter_address", hemera::ErrorCode::E4030 },
		{ "stack_named_result", hemera::ErrorCode::E4030 },
		{ "stack_view_of_holders", hemera::ErrorCode::E4030 },
		{ "stack_unrestricted", hemera::ErrorCode::E4030 },
		{ "stack_scoped_store", hemera::ErrorCode::E4030 },
		{ "stack_scoped_and_unrestricted", hemera::ErrorCode::E4014 },
		{ "stack_scoped_field", hemera::ErrorCode::E4014 },
		{ "field_default_mismatch", hemera::ErrorCode::E4014 },
		{ "complex_ordered", hemera::ErrorCode::E4020 },
		// docs/types.md, Equality
		{ "equality_of_view", hemera::ErrorCode::E4020 },
		{ "quaternion_as_complex", hemera::ErrorCode::E4015 },
		{ "jmag_of_complex", hemera::ErrorCode::E4015 },
		// docs/functions.md, Variable Arguments
		{ "variadic_then_float", hemera::ErrorCode::E4014 },
		{ "variadic_groups_overlap", hemera::ErrorCode::E4014 },
		{ "variadic_between", hemera::ErrorCode::E4014 },
		{ "variadic_default_positional", hemera::ErrorCode::E4015 },
		// docs/operators.md: ~ of an untyped constant
		{ "complement_out_of_range", hemera::ErrorCode::E4015 },
		// docs/functions.md, Several Names in One Declaration
		{ "several_names_counts", hemera::ErrorCode::E4018 },
		// docs/types.md, Mutability: a pointer to a mut view
		{ "mut_view_pointer_read_only", hemera::ErrorCode::E4016 },
		// docs/types.md, Types Declared in Functions
		{ "local_type_outside_block", hemera::ErrorCode::E4008 },
		{ "local_type_generic", hemera::ErrorCode::E4024 },
		{ "stack_scoped_in_array_field", hemera::ErrorCode::E4014 },
		// Known before the struct's body is, which a slow #insert holds back
		{ "scoped_known_before_body", hemera::ErrorCode::E4014 },
		{ "owned_known_before_body", hemera::ErrorCode::E4035 },
		{ "fall_through_last", hemera::ErrorCode::E4002 },
		{ "stack_escaping_function", hemera::ErrorCode::E4015 },
		{ "stack_unrestricted_result", hemera::ErrorCode::E4030 },
		{ "stack_return_variant_shorthand", hemera::ErrorCode::E4030 },
		{ "stack_unrestricted_all_results", hemera::ErrorCode::E4030 },
		{ "constraint_unknown", hemera::ErrorCode::E4014 },
		{ "derived_cycle", hemera::ErrorCode::E4007 },
		{ "alias_argument_count", hemera::ErrorCode::E4014 },
		{ "function_argument_wrong", hemera::ErrorCode::E4014 },
		{ "using_not_struct", hemera::ErrorCode::E4014 },
		{ "using_read_only", hemera::ErrorCode::E4016 },
		{ "mut_argument_read_only", hemera::ErrorCode::E4016 },
		{ "read_only_held", hemera::ErrorCode::E4015 },
		{ "owned_not_marked", hemera::ErrorCode::E4035 },
		{ "stack_unrestricted_result_function", hemera::ErrorCode::E4015 },
		{ "bounds_unchecked", hemera::ErrorCode::E4031 },
		{ "bounds_past_static", hemera::ErrorCode::E4031 },
		{ "bounds_wraps", hemera::ErrorCode::E4031 },
		{ "bounds_slice_backwards", hemera::ErrorCode::E4031 },
		{ "bounds_runaway", hemera::ErrorCode::E4031 },
		{ "bounds_scaled_past", hemera::ErrorCode::E4031 },
		{ "bounds_last_of_empty", hemera::ErrorCode::E4031 },
		{ "bounds_field_grown", hemera::ErrorCode::E4031 },
		{ "bounds_field_aliased", hemera::ErrorCode::E4031 },
		{ "bounds_index_changed", hemera::ErrorCode::E4031 },
		{ "bounds_element_changed", hemera::ErrorCode::E4031 },
		{ "bounds_difference_wraps", hemera::ErrorCode::E4031 },
		{ "bounds_signed_modulus", hemera::ErrorCode::E4031 },
		{ "bounds_after_or_break", hemera::ErrorCode::E4031 },
		{ "generic_value_variable", hemera::ErrorCode::E4010 },
		{ "generic_value_given_type", hemera::ErrorCode::E4010 },
		{ "generic_value_kind", hemera::ErrorCode::E4014 },
		// docs/compilation.md, Code Values
		{ "quote_unspliceable", hemera::ErrorCode::E4014 },
		{ "insert_not_code", hemera::ErrorCode::E4015 },
		{ "insert_statements_as_expression", hemera::ErrorCode::E4014 },
		{ "insert_undeclared_in_code", hemera::ErrorCode::E4008 },
		{ "insert_top_level_expression", hemera::ErrorCode::E4014 },
		{ "insert_wrong_members", hemera::ErrorCode::E4014 },
		{ "insert_in_generic_type", hemera::ErrorCode::E4024 },
		{ "insert_needs_itself", hemera::ErrorCode::E4007 },
		{ "insert_shadows_builtin", hemera::ErrorCode::E4012 },
		{ "name_not_identifier", hemera::ErrorCode::E4029 },
		// docs/compilation.md, Macros
		{ "macro_call_not_macro", hemera::ErrorCode::E4039 },
		{ "macro_expands_forever", hemera::ErrorCode::E4039 },
		{ "macro_local_hidden", hemera::ErrorCode::E4008 },
		// docs/functions.md, Nesting Functions
		{ "nested_uses_outer_local", hemera::ErrorCode::E4008 },
		{ "nested_generic", hemera::ErrorCode::E4024 },
		// docs/types.md, Mutability
		{ "view_read_only", hemera::ErrorCode::E4016 },
		{ "view_from_read_only", hemera::ErrorCode::E4016 },
		{ "view_loses_read_only", hemera::ErrorCode::E4016 },
		{ "mut_changes_nothing", hemera::ErrorCode::E4014 },
		{ "dynamic_array_parameter", hemera::ErrorCode::E4016 },
		{ "rawptr_read_only", hemera::ErrorCode::E4015 },
		// docs/types.md, Relative Pointers and Endian-Specific Types
		{ "relative_copied", hemera::ErrorCode::E4040 },
		{ "relative_parameter", hemera::ErrorCode::E4040 },
		{ "relative_assigned_whole", hemera::ErrorCode::E4040 },
		{ "relative_to_stack", hemera::ErrorCode::E4030 },
		{ "endian_compound", hemera::ErrorCode::E4020 },
		{ "endian_from_native", hemera::ErrorCode::E4015 },
		// docs/memory.md, Scoped Structs
		{ "scoped_dynamic_local", hemera::ErrorCode::E4014 }
	}) {
		StringCacheGuard string_cache;
		FrontEndFixture fixture;
		std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("body_errors") / name);
		ASSERT_EQ(errors.size(), 1) << name << ": " << codes(errors);
		EXPECT_EQ(errors[0], expected) << name;
	}
}

// docs/types.md, Bounds Checking: what's proven
TEST(FrontEnd, ProvesIndexesInBounds)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("bounds_ok"));

	EXPECT_TRUE(errors.empty()) << codes(errors);
}

// docs/memory.md, Pointers to the Stack: what's allowed
TEST(FrontEnd, AllowsStackPointersThatDontEscape)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("stack_pointers_ok"));

	EXPECT_TRUE(errors.empty()) << codes(errors);
}

// docs/types.md, Constraints: generics used with what they need
TEST(FrontEnd, AllowsSatisfiedConstraints)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("constraints_ok"));

	EXPECT_TRUE(errors.empty()) << codes(errors);
}

/*
 * Each use of a generic its constraints don't allow, reported where it's used, with why: what each
 * requirement found, the alternatives of an || or require_any, only the first part of an && that failed,
 * and a generic alias's own where clause.
 */
TEST(FrontEnd, ReportsUnsatisfiedConstraints)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("constraints_unsatisfied"));
	ASSERT_EQ(errors.size(), 7) << codes(errors);
	for (hemera::ErrorCode error : errors) {
		EXPECT_EQ(error, hemera::ErrorCode::E4032);
	}
	std::string all;
	for (const std::string& message : *hemera::error_messages()) {
		all += message + "\n";
	}
	for (std::string_view expected : {
		"count_of[Point] can't be made\n    T = Point isn't HasCount\n        HasCount: Point is a struct without a field count; give Point a count: usize",
		"largest[char] can't be made\n    T = char isn't compiler.Ordered && (compiler.Integer || compiler.Float)\n"
			"        Integer: char is a character, not an integer\n        Float: char is a character, not a float",
		"Buffer[int, 0] can't be made\n    where compiler.AtLeastOne(capacity) && compiler.PowerOfTwo(capacity) isn't satisfied\n"
			"        AtLeastOne: 0 holds nothing; it needs to be at least 1\n",
		"Buffer[int, 6] can't be made\n    where compiler.AtLeastOne(capacity) && compiler.PowerOfTwo(capacity) isn't satisfied\n"
			"        PowerOfTwo: 6 isn't a power of two",
		"Buffer[Point, 4] can't be made\n    T = Point isn't compiler.Equatable\n        Equatable: Point is a struct, which has no ==",
		"show[Point] can't be made\n    T = Point isn't Formattable\n        Formattable: none of these holds: Point is a struct, not an integer, "
			"or Point is a struct, not a float, or Point isn't a character",
		"SmallBuffer[int, 128] can't be made\n    where Small(capacity) isn't satisfied\n        Small: 128 is more than a SmallBuffer holds",
	}) {
		EXPECT_NE(all.find(expected), std::string::npos) << expected << "\n\nin:\n" << all;
	}
}

// docs/types.md, Checked Bodies: constrained generics' bodies, checked once with what their constraints promise
TEST(FrontEnd, AllowsBodiesUsingWhatsPromised)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("checked_bodies_ok"));

	EXPECT_TRUE(errors.empty()) << codes(errors);
}

/*
 * Each use of what a constrained generic's constraints don't promise, reported in its body whether
 * anything calls it or not, with what would promise it: an operator, a field, a loop, and a call to a
 * generic whose constraints the caller's don't cover.
 */
TEST(FrontEnd, ReportsWhatsNotPromised)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("checked_bodies_unpromised"));
	ASSERT_EQ(errors.size(), 8) << codes(errors);
	for (hemera::ErrorCode error : errors) {
		EXPECT_EQ(error, hemera::ErrorCode::E4033);
	}
	std::string all;
	for (const std::string& message : *hemera::error_messages()) {
		all += message + "\n";
	}
	for (std::string_view expected : {
		"arithmetic on T, which total's constraints don't promise; constrain T with compiler.Numeric",
		"ordering on T, which smaller's constraints don't promise; constrain T with compiler.Ordered",
		"an integer operator on T, which odd's constraints don't promise; constrain T with compiler.Integer",
		".count on T, which count_of's constraints don't promise; promise it with compiler.require_field(T, \"count\", ...) in a constraint",
		"a for loop on C, which each's constraints don't promise; constrain it with compiler.ViewOf(C, ...)",
		"largest[T] needs what pick's constraints don't promise\n    T needs Integer(T)\n    T needs Float(T)",
		"writing through a pointer on T, which overwrite's constraints don't promise; constrain T with compiler.Mutable",
		"scaled[factor] needs what other's constraints don't promise\n    its where clause needs PowerOfTwo(factor)",
	}) {
		EXPECT_NE(all.find(expected), std::string::npos) << expected << "\n\nin:\n" << all;
	}
}

/*
 * Format strings written in place, checked against their values (docs/format_strings.md): a placeholder
 * without a value, %0, options that aren't well formed, and options the value's type can't take.
 */
TEST(FrontEnd, ChecksFormatStrings)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("format_unfit"));
	ASSERT_EQ(errors.size(), 7) << codes(errors);
	for (hemera::ErrorCode error : errors) {
		EXPECT_EQ(error, hemera::ErrorCode::E4034);
	}
	std::string all;
	for (const std::string& message : *hemera::error_messages()) {
		all += message + "\n";
	}
	for (std::string_view expected : {
		"% is for value 2, but there is only 1",
		"%{08q} has options that aren't well formed",
		"%0 names no value: values are numbered from %1",
		"%{x} is written as a number in base 16, which string isn't",
		"%{+} gives a number a sign or zeros, but string isn't one",
		"%{#} has # for a 0x, 0b or 0o prefix, which needs x, X, b or o",
		"%{.2} has a precision, which is for floats and strings, not int",
	}) {
		EXPECT_NE(all.find(expected), std::string::npos) << expected << "\n\nin:\n" << all;
	}
}

/*
 * Owners that aren't released or moved on every path, or are used once they were (docs/memory.md, Owned
 * Types): each reported where it's found, with what to do about it.
 */
TEST(FrontEnd, ChecksOwners)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("owned_errors"));
	ASSERT_EQ(errors.size(), 12) << reported(errors);
	for (hemera::ErrorCode error : errors) {
		EXPECT_EQ(error, hemera::ErrorCode::E4035);
	}
	std::string all;
	for (const std::string& message : *hemera::error_messages()) {
		all += message + "\n";
	}
	for (std::string_view expected : {
		"a still owns its value where its scope ends, at line 28: release it, like defer compiler.release(a), mark it #release, or move it",
		"a is used after it was moved or released, at line 34",
		"this gives an owned value that nothing keeps: keep it, or release it",
		"a still owns its value on one path to here, but not on another: move or release it on both",
		"a is moved or released each time around this loop, so the next time around it has nothing",
		"a still owns its value: release or move it before giving it another",
		"a is #release, so it's released where its scope ends and can't be moved",
		"this moves an owned value out of what holds it, which still would: take it out with compiler.take(&...)",
		"file is part of what it came from, only borrowed here",
		"files still owns its value where its scope ends, at line 77: release its elements and it with runtime.array_release(files, ...)",
		"a still owns its value on one path to here, but not on another: move or release it on both",
		"a is used after it was moved or released, at line 88",
	}) {
		EXPECT_NE(all.find(expected), std::string::npos) << expected << "\n\nin:\n" << all;
	}
}

/*
 * A function that states its type gets the type's defaults and can't change them (docs/functions.md,
 * Defaults in Function Types): one repeating the type's default and one inheriting it are fine; one
 * changing it, one adding a default the type lacks, and one changing a type written out aren't.
 */
TEST(FrontEnd, KeepsStatedTypesDefaults)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("stated_type_defaults"));
	ASSERT_EQ(errors.size(), 3) << codes(errors);
	for (hemera::ErrorCode error : errors) {
		EXPECT_EQ(error, hemera::ErrorCode::E4038);
	}
	std::string all;
	for (const std::string& message : *hemera::error_messages()) {
		all += message + "\n";
	}
	for (std::string_view expected : {
		"different's default for b isn't its stated type's: leave it out to use the type's, or leave out the type",
		"extra gives b a default its stated type doesn't: leave out the type to give it one",
		"written_out's default for b isn't its stated type's",
	}) {
		EXPECT_NE(all.find(expected), std::string::npos) << expected << "\n\nin:\n" << all;
	}
}

/*
 * A declared function type's defaults are checked against their parameters where the type is declared, once,
 * however many calls leave them out, and whether any does (docs/functions.md, Defaults in Function Types).
 */
TEST(FrontEnd, ChecksFunctionTypesDefaults)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("type_default_unfit"));
	ASSERT_EQ(errors.size(), 2) << codes(errors);
	for (hemera::ErrorCode error : errors) {
		EXPECT_EQ(error, hemera::ErrorCode::E4015);
	}
	std::string all;
	for (const std::string& message : *hemera::error_messages()) {
		all += message + "\n";
	}
	EXPECT_NE(all.find("this default needs int, not a string"), std::string::npos) << all;
	EXPECT_NE(all.find("this default needs bool"), std::string::npos) << all;
}

/*
 * Values that can't leave their thread given to what sends them to another (docs/multitasking.md, Values
 * That Stay on Their Thread): a type marked #thread_bound, one bound by its argument, one reached through
 * a pointer, and one given to a #crosses_threads parameter of the program's own. One not bound can go.
 */
TEST(FrontEnd, KeepsThreadBoundValues)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("thread_bound"));
	ASSERT_EQ(errors.size(), 4) << codes(errors);
	for (hemera::ErrorCode error : errors) {
		EXPECT_EQ(error, hemera::ErrorCode::E4036);
	}
	std::string all;
	for (const std::string& message : *hemera::error_messages()) {
		all += message + "\n";
	}
	for (std::string_view expected : {
		"ptr[mut Count] reaches Count, which is #thread_bound, so it can't be given to data, which goes to another thread",
		"ptr[mut Shared[false]] reaches Shared[false], which is #thread_bound, so it can't be given to data",
		"ptr[mut Holder] reaches Count, which is #thread_bound, so it can't be given to data",
		"ptr[mut Count] reaches Count, which is #thread_bound, so it can't be given to value, which goes to another thread",
	}) {
		EXPECT_NE(all.find(expected), std::string::npos) << expected << "\n\nin:\n" << all;
	}
}

/*
 * Integer literals out of range of the type they become (docs/types.md, Number Formats): one given a
 * type, a negative given to an unsigned one, one defaulting to int, a range's bound, an argument, a
 * result, a field, an operand beside a typed one, and one too large for any integer. Operators on known
 * integers and named constants are worked out and checked the same way, and dividing by a known zero
 * is an error. Those in range aren't, even when their parts aren't.
 */
TEST(FrontEnd, ChecksIntegerRanges)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("integer_ranges"));
	ASSERT_EQ(errors.size(), 21) << codes(errors);
	for (hemera::ErrorCode error : errors) {
		EXPECT_EQ(error, hemera::ErrorCode::E4015);
	}
	std::string all;
	for (const std::string& message : *hemera::error_messages()) {
		all += message + "\n";
	}
	for (std::string_view expected : {
		"128 is out of i8's range, -128 to 127",
		"300 is out of u8's range, 0 to 255",
		"-1 is out of u32's range, 0 to 4294967295",
		"-129 is out of i8's range, -128 to 127",
		"18446744073709551615 is out of int's range, -9223372036854775808 to 9223372036854775807",
		"0x1_0000_0000_0000_0000 is too large for any integer",
		"256 is out of u8's range, 0 to 255",
		"300 is out of u8's range, 0 to 255",
		"200 is out of i8's range, -128 to 127",
		"-300 is out of i8's range, -128 to 127",
		"this is too large for any integer",
		"dividing by zero, which is known here",
	}) {
		EXPECT_NE(all.find(expected), std::string::npos) << expected << "\n\nin:\n" << all;
	}
}

/*
 * Vectors used wrongly (docs/types.md, Vectors): lanes, counts, a lane chosen at run time or out of
 * range, operators that don't apply, intrinsics given what they can't take, an x86_64 immediate that
 * isn't a constant, and #target_features with a +.
 */
TEST(FrontEnd, ChecksVectors)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("vector_errors"));
	ASSERT_EQ(errors.size(), 15) << codes(errors);
	std::string all;
	for (const std::string& message : *hemera::error_messages()) {
		all += message + "\n";
	}
	for (std::string_view expected : {
		"#target_features names the features to add",
		"a vector's lanes are integers or floats of up to 64 bits, or bools, not string",
		"a vector has a power of two lanes, at most 64 bytes in all, not 3 of u32",
		"not 16 of u64",
		"a lane of Words is chosen by a constant from 0 to 3",
		"Words and vector[u32, 8] don't go together",
		"since integer division isn't on vectors yet",
		"v128 only takes &, | and ~",
		"Words takes all 4 lanes, not 2",
		"intrinsics.rotate_lanes takes a constant count, from 0 to 3",
		"intrinsics.reduce_add takes a vector of integers, not vector[f32, 4]",
		"intrinsics.byte_swap takes an integer of 2 bytes or more",
		"aes_key_assist's round constant is part of the instruction, so it's a constant",
		"4294967296 is out of u32's range",
	}) {
		EXPECT_NE(all.find(expected), std::string::npos) << expected << "\n\nin:\n" << all;
	}
}

/*
 * Secrets where they could leak (docs/memory.md, Secrets): a branch, a loop's count, an index, a division,
 * &&'s right side, a match, a parameter, an assignment, a pointer and a result that aren't #secret, a
 * function taking one without #constant_time, and #secret on an alias that isn't distinct. What's allowed
 * isn't reported, and #constant_time without a secret is warned about.
 */
TEST(FrontEnd, ChecksSecrets)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	FrontEndFixture fixture;

	std::vector<hemera::ErrorCode> errors = process_package(fixture, scenario("secret_errors"));
	ASSERT_EQ(errors.size(), 14) << codes(errors);
	std::string all;
	for (const std::string& message : *hemera::error_messages()) {
		all += message + "\n";
	}
	for (std::string_view expected : {
		"only a distinct alias is #secret",
		"a secret can't decide if's condition",
		"a secret can't decide how many times a loop runs",
		"a secret can't decide which element is read",
		"a secret can't be divided or divide",
		"a secret can't decide whether the right side runs",
		"a secret can't decide which arm of a match runs",
		"value isn't a #secret type, so a secret can't go there",
		"what's assigned to isn't a #secret type",
		"a pointer to u8[4] would lose that this is a secret",
		"a cast from ptr[Key] to ptr[u8] would read a secret as public",
		"the result isn't a #secret type",
		"unmarked takes or gives a secret, so it's marked #constant_time",
	}) {
		EXPECT_NE(all.find(expected), std::string::npos) << expected << "\n\nin:\n" << all;
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

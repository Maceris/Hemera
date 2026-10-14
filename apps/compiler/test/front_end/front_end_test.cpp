#include <filesystem>
#include <fstream>
#include <vector>

#include "gtest/gtest.h"

#include "hemera_errors.h"
#include "cmd_line/options.h"
#include "error/reporting.h"
#include "front_end/front_end.h"
#include "front_end/info.h"
#include "front_end/mlir_generation.h"
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

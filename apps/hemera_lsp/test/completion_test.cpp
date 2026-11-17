#include <algorithm>
#include <filesystem>
#include <map>
#include <memory>
#include <set>
#include <string>
#include <vector>

#include "gtest/gtest.h"

#include "completion.h"
#include "parsing.h"
#include "uri.h"

using hemera::lsp::completion_items;
using hemera::lsp::CompletionRequest;
using hemera::lsp::CompletionTables;
using hemera::lsp::IndexedDeclaration;
using hemera::lsp::IndexedImport;
using hemera::lsp::LoadedIndex;

namespace {

	const std::string SHAPES = "D:/q/shapes/shapes.hsc";
	const std::string SHAPES_TEXT =
		"package shapes\n"
		"\n"
		"/** A point. */\n"
		"Point :: struct {\n"
		"    x : int,\n"
		"    y : int,\n"
		"}\n"
		"\n"
		"moved :: fn(point : Point) -> Point {\n"
		"    return point\n"
		"}\n";
	const std::string MAIN = "D:/q/main/main.hsc";
	const std::string MAIN_TEXT =
		"package main\n"
		"\n"
		"import shapes from \"../shapes\"\n"
		"\n"
		"LIMIT :: 3\n"
		"\n"
		"main :: fn() -> int {\n"
		"    start := shapes.Point.{ x = 1 }\n"
		"    return start.x\n"
		"}\n";

	IndexedDeclaration declared(const std::string& file, const std::string& text, const std::string& name, const std::string& kind,
		size_t from = 0) {
		IndexedDeclaration declaration;
		declaration.file = file;
		declaration.name_offset = static_cast<uint32_t>(text.find(name, from));
		declaration.name_length = static_cast<uint32_t>(name.size());
		declaration.start = declaration.name_offset;
		declaration.end = declaration.name_offset + declaration.name_length;
		declaration.kind = kind;
		return declaration;
	}

	// The index a check of main would give: shapes' Point, its fields and moved, and main's constant, function and local
	std::shared_ptr<const LoadedIndex> index_of_main() {
		auto index = std::make_shared<LoadedIndex>();
		index->declarations = {
			declared(SHAPES, SHAPES_TEXT, "Point", "type"),
			declared(SHAPES, SHAPES_TEXT, "x", "field", SHAPES_TEXT.find("    x")),
			declared(SHAPES, SHAPES_TEXT, "y", "field", SHAPES_TEXT.find("    y")),
			declared(SHAPES, SHAPES_TEXT, "moved", "function"),
			declared(MAIN, MAIN_TEXT, "LIMIT", "constant"),
			declared(MAIN, MAIN_TEXT, "main ::", "function"),
			declared(MAIN, MAIN_TEXT, "start", "local"),
		};
		index->declarations[0].brief = "A point.";
		index->declarations[1].in = 0;
		index->declarations[1].type = "int";
		index->declarations[2].in = 0;
		index->declarations[3].of = 0;
		index->declarations[5].name_length = 4;
		index->declarations[6].of = 0;
		for (size_t i = 0; i < index->declarations.size(); ++i) {
			index->declared[hemera::lsp::path_key(index->declarations[i].file)].push_back(i);
		}
		index->imports[hemera::lsp::path_key(MAIN)] = { IndexedImport{ static_cast<uint32_t>(MAIN_TEXT.find("shapes")), 6, "D:/q/shapes" } };
		return index;
	}

	// The labels completion gives at the end of before, in main.hsc as text is now, after a check that read checked
	std::set<std::string> labels_at(const std::string& text, const std::string& before, const std::string& checked = MAIN_TEXT,
		const std::string& file = MAIN, const std::string& base_folder = "") {
		hemera::lsp::prepare_parsing();
		const auto parsed = hemera::lsp::parse_document(text, 1, file);
		CompletionTables tables(index_of_main(), [](const std::string& path) {
			return hemera::lsp::path_key(path) == hemera::lsp::path_key(SHAPES) ? SHAPES_TEXT : MAIN_TEXT;
		});
		CompletionRequest request;
		request.file = file;
		request.text = text;
		request.checked_text = checked;
		request.offset = text.find(before) + before.size();
		request.parsed = parsed.get();
		request.base_folder = base_folder;
		std::set<std::string> labels;
		for (const llvm::json::Value& item : completion_items(request, &tables)) {
			labels.insert(item.getAsObject()->getString("label")->str());
		}
		return labels;
	}

	// main.hsc with line put after start's
	std::string with_line(const std::string& line) {
		std::string text = MAIN_TEXT;
		text.insert(text.find("    return"), line + "\n");
		return text;
	}
}

TEST(Completion, AValuesMembersFollowItsDot) {
	const std::string text = with_line("    start.");
	EXPECT_EQ((std::set<std::string>{ "x", "y" }), labels_at(text, "start."));
}

TEST(Completion, APackagesDeclarationsFollowItsImportsName) {
	const std::string text = with_line("    shapes.");
	EXPECT_EQ((std::set<std::string>{ "Point", "moved" }), labels_at(text, "shapes."));
}

TEST(Completion, ACallsResultAndAPackagesTypeAreFollowed) {
	const std::string text = with_line("    shapes.moved(start).");
	EXPECT_EQ((std::set<std::string>{ "x", "y" }), labels_at(text, "shapes.moved(start)."));
	const std::string typed = with_line("    shapes.Point.");
	EXPECT_EQ((std::set<std::string>{ "x", "y" }), labels_at(typed, "shapes.Point."));
}

TEST(Completion, AMemberTheIndexDoesNotKnowGivesNothing) {
	const std::string text = with_line("    start.z.");
	EXPECT_TRUE(labels_at(text, "start.z.").empty());
	const std::string number = with_line("    x := 1.");
	EXPECT_TRUE(labels_at(number, "1.").empty());
}

TEST(Completion, NamesInScopeIncludeLocalsDeclaredSinceTheCheck) {
	const std::string text = with_line("    fresh := 2\n    st");
	const std::set<std::string> labels = labels_at(text, "fresh := 2\n    st");
	for (const std::string expected : { "start", "fresh", "LIMIT", "main", "shapes", "int", "return" }) {
		EXPECT_TRUE(labels.contains(expected)) << expected;
	}
	// Not another type's fields, nor another package's declarations
	EXPECT_FALSE(labels.contains("x"));
	EXPECT_FALSE(labels.contains("moved"));
}

TEST(Completion, NothingInAStringOrComment) {
	const std::string text = with_line("    word := \"st\" // st");
	EXPECT_TRUE(labels_at(text, "\"st").empty());
	EXPECT_TRUE(labels_at(text, "// st").empty());
}

TEST(Completion, AnImportsPathGoesOnToItsFolders) {
	const std::filesystem::path root = std::filesystem::temp_directory_path() / "hemera_lsp_test" / "completion";
	std::filesystem::remove_all(root);
	for (const char* folder : { "main", "shapes", "base/runtime", "std/collections", "std/strings" }) {
		std::filesystem::create_directories(root / folder);
	}
	const std::string file = (root / "main" / "main.hsc").generic_string();
	const std::string base = (root / "base").generic_string();
	const std::string text = "package main\n\nimport shapes from \"../\n";
	EXPECT_EQ((std::set<std::string>{ "base", "main", "shapes", "std" }), labels_at(text, "\"../", text, file, base));
	const std::string library = "package main\n\nimport strings from \"std:st\n";
	EXPECT_EQ((std::set<std::string>{ "collections", "strings" }), labels_at(library, "std:st", library, file, base));
	const std::string started = "package main\n\nimport strings from \"\n";
	const std::set<std::string> labels = labels_at(started, "from \"", started, file, base);
	EXPECT_TRUE(labels.contains("std:"));
	EXPECT_EQ(3u, labels.size()) << "std:, vendor: and base:, as main.hsc's folder has none";
}

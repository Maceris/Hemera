#include <cctype>
#include <format>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "gtest/gtest.h"

#include "assist.h"
#include "documents.h"
#include "index.h"
#include "parsing.h"

using hemera::lsp::AssistRequest;
using hemera::lsp::CompletionTables;
using hemera::lsp::Encoding;
using hemera::lsp::LineIndex;
using hemera::lsp::LoadedIndex;
using llvm::json::Array;
using llvm::json::Object;
using llvm::json::Value;

namespace {

	const std::string MAIN = "D:/q/main/main.hsc";
	const std::string LONG_TYPE = "Result[ptr[mut HashMap[u64, ptr[mut Node]]], FrameError]";
	const std::string MAIN_TEXT =
		"package main\n"
		"\n"
		"/**\n"
		" * Scales a value.\n"
		" *\n"
		" * @param value What's scaled.\n"
		" * @param factor By how much.\n"
		" */\n"
		"scale :: fn(value : int, factor := 3) -> int {\n"
		"    return value * factor\n"
		"}\n"
		"\n"
		"Handler :: struct {\n"
		"    run : fn(int, string) -> bool,\n"
		"}\n"
		"\n"
		"main :: fn() -> int {\n"
		"    h := Handler.{}\n"
		"    total := scale(1, factor = 2)\n"
		"    words : int = 4\n"
		"    for item in 0..<3 {\n"
		"    }\n"
		"    ok := h.run(total, \"x\")\n"
		"    return scale(scale(total, 2), words)\n"
		"}\n";

	// The byte offset of the nth (from 0) place word is in text
	size_t at(const std::string& text, const std::string& word, int nth = 0) {
		size_t found = text.find(word);
		for (; nth > 0 && found != std::string::npos; --nth) {
			found = text.find(word, found + 1);
		}
		return found;
	}

	// The index a check of MAIN_TEXT would write
	LoadedIndex index_of(const std::string& text) {
		const auto declaration = [&](const std::string& word, int nth, const std::string& rest) {
			return std::format("{{\"file\":0,\"name\":[{},{}],\"span\":[{},{}]{}}}", at(text, word, nth), word.size(), at(text, word, nth),
				at(text, word, nth) + word.size(), rest);
		};
		const auto use = [&](const std::string& word, int nth, int number) {
			return std::format("[0,{},{},{}]", at(text, word, nth), word.size(), number);
		};
		const std::string json = std::format(
			"{{\"version\":1,\"files\":[\"{}\"],\"declarations\":[\n"
			"{},\n{},\n{},\n{},\n{},\n{},\n{},\n{},\n{}],\n"
			"\"uses\":[{},{},{},{},{},{}]}}",
			MAIN,
			declaration("scale", 0, std::format(",\"kind\":\"function\",\"type\":\"fn(int, int) -> int\",\"brief\":\"Scales a value.\","
				"\"tags\":[[\"param\",\"value\",\"What's scaled.\"],[\"param\",\"factor\",\"By how much.\"]],"
				"\"parameters\":[{{\"name\":\"value\",\"type\":\"int\"}},{{\"name\":\"factor\",\"type\":\"int\",\"default\":[{},1]}}]",
				at(text, "3) ->"))),
			declaration("Handler", 0, ",\"kind\":\"type\",\"is\":\"struct\""),
			declaration("run", 0, ",\"kind\":\"field\",\"type\":\"fn(int, string) -> bool\",\"in\":1"),
			declaration("main", 1, ",\"kind\":\"function\",\"type\":\"fn() -> int\""),
			std::format("{{\"file\":0,\"name\":[{},1],\"span\":[{},{}],\"kind\":\"local\",\"type\":\"Handler\"}}", at(text, "h :="),
				at(text, "h :="), at(text, "h :=") + 1),
			declaration("total", 0, ",\"kind\":\"local\",\"type\":\"int\""),
			declaration("words", 0, ",\"kind\":\"local\",\"type\":\"int\""),
			declaration("item", 0, ",\"kind\":\"local\",\"type\":\"int\""),
			declaration("ok", 0, std::format(",\"kind\":\"local\",\"type\":\"{}\"", LONG_TYPE)),
			use("scale", 1, 0), use("scale", 2, 0), use("scale", 3, 0), use("run", 1, 2), use("total", 1, 5), use("words", 1, 6));
		std::optional<LoadedIndex> index = hemera::lsp::read_index(json, "");
		EXPECT_TRUE(index.has_value());
		return index.value_or(LoadedIndex{});
	}

	// What signature help, inlay hints and workspace symbols are answered from, for text, which the check read as checked
	struct Assisted {
		std::shared_ptr<const LoadedIndex> index;
		std::string checked;
		std::string text;
		std::unique_ptr<hemera::lsp::ParsedDocument> parsed;
		std::unique_ptr<CompletionTables> tables;

		Assisted(const std::string& text_now, const std::string& checked_text = MAIN_TEXT)
			: index(std::make_shared<const LoadedIndex>(index_of(checked_text))), checked(checked_text), text(text_now) {
			hemera::lsp::prepare_parsing();
			parsed = hemera::lsp::parse_document(text, 1, MAIN);
			const std::string read = checked;
			tables = std::make_unique<CompletionTables>(index, [read](const std::string&) { return read; });
		}

		AssistRequest request(size_t offset, size_t end = 0) const {
			AssistRequest made;
			made.file = MAIN;
			made.text = text;
			made.checked_text = checked;
			made.parsed = parsed.get();
			made.encoding = Encoding::UTF8;
			made.offset = offset;
			made.end = end;
			return made;
		}

		/*
		 * Signature help at offset, as "label | active parameter's label | its documentation", or "none"; the active
		 * parameter read back from the label by its range
		 */
		std::string signature_at(size_t offset) const {
			const Value help = hemera::lsp::signature_help(request(offset), tables.get());
			const Object* object = help.getAsObject();
			if (object == nullptr) {
				return "none";
			}
			const Object& signature = *(*object->getArray("signatures"))[0].getAsObject();
			const std::string label = signature.getString("label")->str();
			const int64_t active = *object->getInteger("activeParameter");
			const Array& parameters = *signature.getArray("parameters");
			if (active < 0 || static_cast<size_t>(active) >= parameters.size()) {
				return label + " | -";
			}
			const Object& parameter = *parameters[static_cast<size_t>(active)].getAsObject();
			const Array& range = *parameter.getArray("label");
			const std::string named = label.substr(static_cast<size_t>(*range[0].getAsInteger()),
				static_cast<size_t>(*range[1].getAsInteger() - *range[0].getAsInteger()));
			const Object* documentation = parameter.getObject("documentation");
			return label + " | " + named + (documentation != nullptr ? " | " + documentation->getString("value")->str() : "");
		}
	};
}

// A call's signature, from the index, with the argument the cursor's in: by position, or by name.
TEST(SignatureHelp, ShowsTheParameterBeingGiven) {
	const Assisted assisted(MAIN_TEXT);
	const std::string scale = "scale(value : int, factor : int = 3) -> int";
	EXPECT_EQ(scale + " | value : int | What's scaled.", assisted.signature_at(at(MAIN_TEXT, "1, factor")));
	EXPECT_EQ(scale + " | factor : int = 3 | By how much.", assisted.signature_at(at(MAIN_TEXT, "2)")));
	// The inner call of two, then the outer one
	EXPECT_EQ(scale + " | factor : int = 3 | By how much.", assisted.signature_at(at(MAIN_TEXT, "2), words")));
	EXPECT_EQ(scale + " | factor : int = 3 | By how much.", assisted.signature_at(at(MAIN_TEXT, "words)")));
	// Not in a call
	EXPECT_EQ("none", assisted.signature_at(at(MAIN_TEXT, "words :")));
}

// A field of function type has its type's parameters, which have no names.
TEST(SignatureHelp, ShowsAFunctionTypesParameters) {
	const Assisted assisted(MAIN_TEXT);
	EXPECT_EQ("run(int, string) -> bool | string", assisted.signature_at(at(MAIN_TEXT, "\"x\"")));
}

// A call being typed, which doesn't parse and isn't in the index, by its name in the package.
TEST(SignatureHelp, FindsACallBeingTyped) {
	const std::string typing = MAIN_TEXT + "\nlater :: fn() {\n    scale(4, ";
	const Assisted assisted(typing);
	EXPECT_EQ("scale(value : int, factor : int = 3) -> int | factor : int = 3 | By how much.", assisted.signature_at(typing.size()));
}

// Each local without a written type has its type after its name; a long one is cut, with the whole in its tooltip.
TEST(InlayHints, ShowLocalsTypesWhereTheyArentWritten) {
	const Assisted assisted(MAIN_TEXT);
	const Array hints = hemera::lsp::inlay_hints(assisted.request(0, MAIN_TEXT.size()), *assisted.index);
	const LineIndex lines(MAIN_TEXT);
	std::vector<std::string> found;
	for (const Value& hint : hints) {
		const Object& object = *hint.getAsObject();
		const Object& position = *object.getObject("position");
		const size_t offset = lines.offset_of(static_cast<uint32_t>(*position.getInteger("line")),
			static_cast<uint32_t>(*position.getInteger("character")), Encoding::UTF8);
		size_t start = offset;
		while (start > 0 && (std::isalnum(static_cast<unsigned char>(MAIN_TEXT[start - 1])) || MAIN_TEXT[start - 1] == '_')) {
			--start;
		}
		const std::optional<llvm::StringRef> tooltip = object.getString("tooltip");
		found.push_back(MAIN_TEXT.substr(start, offset - start) + object.getString("label")->str()
			+ (tooltip.has_value() ? " (" + tooltip->str() + ")" : ""));
	}
	const std::vector<std::string> expected{
		"h: Handler",
		"total: int",
		"item: int",
		"ok: " + LONG_TYPE.substr(0, 39) + "\xE2\x80\xA6 (" + LONG_TYPE + ")",
	};
	EXPECT_EQ(expected, found);
}

// Edits since the check move the hints with their names; only those in the range asked for are given.
TEST(InlayHints, MoveWithEditsAndKeepToTheirRange) {
	std::string moved = MAIN_TEXT;
	moved.insert(at(moved, "main ::"), "// a line\n");
	const Assisted assisted(moved);
	const size_t start = at(moved, "    total");
	const Array hints = hemera::lsp::inlay_hints(assisted.request(start, at(moved, "    words")), *assisted.index);
	ASSERT_EQ(1u, hints.size());
	const Object& position = *(*hints.begin()).getAsObject()->getObject("position");
	const LineIndex lines(moved);
	EXPECT_EQ(at(moved, "total") + 5, lines.offset_of(static_cast<uint32_t>(*position.getInteger("line")),
		static_cast<uint32_t>(*position.getInteger("character")), Encoding::UTF8));
}

// Workspace symbols: names with the query's letters in order, those starting with it first, then the shortest.
TEST(WorkspaceSymbols, MatchAndOrderNames) {
	const Assisted assisted(MAIN_TEXT);
	const auto names = [&](std::string_view query, size_t limit) {
		std::vector<std::string> found;
		for (const Value& symbol : hemera::lsp::workspace_symbols(query, { assisted.tables.get() }, { "D:/q/main" }, Encoding::UTF8, limit)) {
			const Object& object = *symbol.getAsObject();
			const std::optional<llvm::StringRef> container = object.getString("containerName");
			found.push_back(object.getString("name")->str() + (container.has_value() ? " in " + container->str() : ""));
		}
		return found;
	};
	EXPECT_EQ((std::vector<std::string>{ "scale" }), names("s", 500));
	EXPECT_EQ((std::vector<std::string>{ "run in Handler", "main", "Handler" }), names("n", 500));
	// Ignoring case
	EXPECT_EQ((std::vector<std::string>{ "Handler" }), names("hN", 500));
	EXPECT_EQ((std::vector<std::string>{ "run in Handler", "main" }), names("n", 2));
	// Locals aren't symbols
	EXPECT_TRUE(names("total", 500).empty());
}

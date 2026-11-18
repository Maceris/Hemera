#include <cctype>
#include <format>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "gtest/gtest.h"

#include "documents.h"
#include "index.h"
#include "parsing.h"
#include "tokens.h"
#include "uri.h"

using hemera::lsp::Encoding;
using hemera::lsp::LineIndex;
using hemera::lsp::LoadedIndex;
using hemera::lsp::TokensRequest;
using llvm::json::Array;
using llvm::json::Object;

namespace {

	const std::string MAIN = "D:/q/main/main.hsc";
	const std::string SHAPES = "D:/q/shapes/shapes.hsc";
	const std::string BASE = "D:/q/hemera/base";
	const std::string MAIN_TEXT =
		"package main\n"
		"\n"
		"import shapes from \"../shapes\"\n"
		"\n"
		"LIMIT :: 3\n"
		"\n"
		"Point :: struct {\n"
		"    x : int,\n"
		"}\n"
		"\n"
		"twice :: fn(by : int) -> int {\n"
		"    total := by + LIMIT\n"
		"    return shapes.area(\"\xC3\xA9\", total)\n"
		"}\n";

	// The byte offset of the nth (from 0) place word is in text, as a whole word
	size_t at(const std::string& text, const std::string& word, int nth = 0) {
		size_t found = std::string::npos;
		for (size_t from = 0; nth >= 0; --nth, from = found + 1) {
			found = text.find(word, from);
			while (found != std::string::npos && ((found > 0 && (std::isalnum(static_cast<unsigned char>(text[found - 1])) || text[found - 1] == '_'))
				|| (found + word.size() < text.size() && (std::isalnum(static_cast<unsigned char>(text[found + word.size()])) || text[found + word.size()] == '_')))) {
				found = text.find(word, found + 1);
			}
		}
		return found;
	}

	/*
	 * The index a check of MAIN_TEXT would write: its declarations of each kind, their uses, its import, and a function
	 * in another package; area is deprecated, and Old is base's
	 */
	LoadedIndex index_of(const std::string& text) {
		const auto declaration = [&](const std::string& word, int nth, const std::string& rest) {
			return std::format("{{\"file\":0,\"name\":[{},{}],\"span\":[{},{}]{}}}", at(text, word, nth), word.size(), at(text, word, nth),
				at(text, word, nth) + word.size(), rest);
		};
		const auto use = [&](const std::string& word, int nth, int declaration_number) {
			return std::format("[0,{},{},{}]", at(text, word, nth), word.size(), declaration_number);
		};
		const std::string json = std::format(
			"{{\"version\":1,\"files\":[\"{}\",\"{}\",\"<base>/old/old.hsc\"],\"declarations\":[\n"
			"{},\n{},\n{},\n{},\n{},\n{},\n"
			"{{\"file\":1,\"name\":[40,4],\"span\":[40,90],\"kind\":\"function\",\"tags\":[[\"deprecated\",\"\",\"Use size.\"]]}},\n"
			"{{\"file\":2,\"name\":[20,3],\"span\":[20,40],\"kind\":\"type\",\"is\":\"enum\"}}],\n"
			"\"uses\":[{},{},{},{}],\n"
			"\"imports\":[[0,{},6,\"D:/q/shapes\"]]}}",
			MAIN, SHAPES,
			declaration("LIMIT", 0, ",\"kind\":\"constant\""),
			declaration("Point", 0, ",\"kind\":\"type\",\"is\":\"struct\""),
			declaration("x", 0, ",\"kind\":\"field\""),
			declaration("twice", 0, ",\"kind\":\"function\""),
			declaration("by", 0, ",\"kind\":\"parameter\",\"readonly\":true"),
			declaration("total", 0, ",\"kind\":\"local\""),
			use("by", 1, 4), use("LIMIT", 1, 0), use("area", 0, 6), use("total", 1, 5),
			at(text, "shapes", 0));
		std::optional<LoadedIndex> index = hemera::lsp::read_index(json, BASE);
		EXPECT_TRUE(index.has_value());
		return index.value_or(LoadedIndex{});
	}

	/*
	 * A response's tokens, each as "word type modifiers..." in order, read back through the legend, with the word
	 * found in text by its position in encoding
	 */
	std::vector<std::string> decoded(const Object& response, const std::string& text, Encoding encoding) {
		const Object legend = hemera::lsp::semantic_tokens_legend();
		const Array& types = *legend.getArray("tokenTypes");
		const Array& modifiers = *legend.getArray("tokenModifiers");
		const Array& data = *response.getArray("data");
		const LineIndex lines(text);
		std::vector<std::string> found;
		uint32_t line = 0;
		uint32_t start = 0;
		for (size_t i = 0; i + 4 < data.size(); i += 5) {
			const uint32_t delta_line = static_cast<uint32_t>(*data[i].getAsInteger());
			start = delta_line == 0 ? start + static_cast<uint32_t>(*data[i + 1].getAsInteger()) : static_cast<uint32_t>(*data[i + 1].getAsInteger());
			line += delta_line;
			const uint32_t length = static_cast<uint32_t>(*data[i + 2].getAsInteger());
			const size_t from = lines.offset_of(line, start, encoding);
			const size_t to = lines.offset_of(line, start + length, encoding);
			std::string made = text.substr(from, to - from) + " " + types[static_cast<size_t>(*data[i + 3].getAsInteger())].getAsString()->str();
			const int64_t bits = *data[i + 4].getAsInteger();
			for (size_t bit = 0; bit < modifiers.size(); ++bit) {
				if ((bits >> bit) & 1) {
					made += " " + modifiers[bit].getAsString()->str();
				}
			}
			found.push_back(made);
		}
		return found;
	}

	// The tokens of text, which the check read as checked_text, with index, in encoding
	std::vector<std::string> tokens_of(const std::string& text, const std::string& checked_text, const LoadedIndex* index,
		Encoding encoding = Encoding::UTF8, std::optional<size_t> start = std::nullopt, std::optional<size_t> end = std::nullopt) {
		hemera::lsp::prepare_parsing();
		const std::unique_ptr<hemera::lsp::ParsedDocument> parsed = hemera::lsp::parse_document(text, 1, MAIN);
		TokensRequest request;
		request.file = MAIN;
		request.text = text;
		request.checked_text = checked_text;
		request.parsed = parsed.get();
		request.base_folder = BASE;
		request.std_folder = "D:/q/hemera/std";
		request.encoding = encoding;
		request.start = start;
		request.end = end;
		return decoded(hemera::lsp::semantic_tokens(request, index), text, encoding);
	}

	const std::vector<std::string> EXPECTED{
		"shapes namespace declaration",
		"LIMIT variable declaration readonly",
		"Point struct declaration",
		"x property declaration",
		"twice function declaration",
		"by parameter declaration readonly",
		"total variable declaration",
		"by parameter readonly",
		"LIMIT variable readonly",
		"shapes namespace",
		"area function deprecated",
		"total variable",
	};
}

// Each name is colored by what it names, from the index: its kind, and readonly, declaration and deprecated.
TEST(SemanticTokens, NameWhatEachNameIs) {
	const LoadedIndex index = index_of(MAIN_TEXT);
	EXPECT_EQ(EXPECTED, tokens_of(MAIN_TEXT, MAIN_TEXT, &index));
}

// A token after a non-ASCII character starts where the encoding counts it.
TEST(SemanticTokens, CountUtf16Units) {
	const LoadedIndex index = index_of(MAIN_TEXT);
	EXPECT_EQ(EXPECTED, tokens_of(MAIN_TEXT, MAIN_TEXT, &index, Encoding::UTF16));
}

// A range's tokens are those in it.
TEST(SemanticTokens, ARangeHasItsOwn) {
	const LoadedIndex index = index_of(MAIN_TEXT);
	const size_t line_start = MAIN_TEXT.find("    total :=");
	const size_t line_end = MAIN_TEXT.find('\n', line_start);
	const std::vector<std::string> expected{ "total variable declaration", "by parameter readonly", "LIMIT variable readonly" };
	EXPECT_EQ(expected, tokens_of(MAIN_TEXT, MAIN_TEXT, &index, Encoding::UTF8, line_start, line_end));
}

/*
 * Edits since the check move the tokens with their names; a name the edit changed has none, as the grammar colors it
 * until the next check.
 */
TEST(SemanticTokens, MoveWithEditsSinceTheCheck) {
	const LoadedIndex index = index_of(MAIN_TEXT);
	std::string moved = MAIN_TEXT;
	moved.insert(moved.find("\n") + 1, "// a line\n");
	EXPECT_EQ(EXPECTED, tokens_of(moved, MAIN_TEXT, &index));

	std::string renamed = MAIN_TEXT;
	renamed.insert(at(renamed, "LIMIT") + 5, "S");
	std::vector<std::string> expected = EXPECTED;
	expected.erase(expected.begin() + 1);
	EXPECT_EQ(expected, tokens_of(renamed, MAIN_TEXT, &index));
}

// A declaration in base is defaultLibrary.
TEST(SemanticTokens, BaseIsTheDefaultLibrary) {
	const std::string text = MAIN_TEXT + "\nkept :: Old.a\n";
	LoadedIndex index = index_of(text);
	index.uses[hemera::lsp::path_key(MAIN)].push_back(hemera::lsp::IndexedUse{ static_cast<uint32_t>(at(text, "Old")), 3, 7 });
	const std::vector<std::string> found = tokens_of(text, text, &index);
	EXPECT_EQ("Old enum defaultLibrary", found.back());
}

// A file the index doesn't have: its own declarations and its package names, from its parse.
TEST(SemanticTokens, AFileTheIndexLacksIsColoredFromItsParse) {
	const std::vector<std::string> expected{
		"shapes namespace declaration",
		"LIMIT variable declaration readonly",
		"Point struct declaration",
		"x property declaration",
		"twice function declaration",
		"shapes namespace",
	};
	EXPECT_EQ(expected, tokens_of(MAIN_TEXT, MAIN_TEXT, nullptr));
}

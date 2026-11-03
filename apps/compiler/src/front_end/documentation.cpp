#include "front_end/documentation.h"

#include <algorithm>
#include <filesystem>
#include <format>
#include <map>
#include <mutex>
#include <set>
#include <tuple>
#include <utility>

#include "error/reporting.h"

namespace hemera {

	namespace {

		// A documentation comment kept: its text, and where it starts.
		struct Kept {
			std::string text;
			uint32_t line = 0;
			uint16_t column = 0;
		};

		/*
		 * A file's documentation comments: those before a declaration, by where the token after them is, and those after a
		 * field, parameter or member, by the line of the token before them.
		 */
		struct FileDocumentation {
			std::map<std::pair<uint32_t, uint16_t>, Kept> leading;
			std::map<uint32_t, Kept> trailing;
		};

		std::mutex files_mutex;

		std::map<std::string, FileDocumentation>& files() {
			// Kept for the process, never destroyed, as compile-time code may read them until it ends
			static auto* kept = new std::map<std::string, FileDocumentation>();
			return *kept;
		}

		// A file's path as the documentation is kept by, however it was written.
		std::string key_of(std::string_view path) {
			return std::filesystem::path(std::string(path)).lexically_normal().generic_string();
		}

		constexpr std::string_view TAGS[] = { "brief", "param", "tparam", "return", "returns", "error", "note", "see", "example",
			"deprecated", "since" };

		// The tags that name what they document first.
		bool names_one(std::string_view tag) {
			return tag == "param" || tag == "tparam" || tag == "error";
		}

		bool is_space(char c) {
			return c == ' ' || c == '\t' || c == '\r';
		}

		std::string_view trimmed(std::string_view text) {
			while (!text.empty() && (is_space(text.front()) || text.front() == '\n')) {
				text.remove_prefix(1);
			}
			while (!text.empty() && (is_space(text.back()) || text.back() == '\n')) {
				text.remove_suffix(1);
			}
			return text;
		}

		bool is_tag_letter(char c) {
			return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
		}

		// The first word of text, and what's after it.
		std::pair<std::string_view, std::string_view> first_word(std::string_view text) {
			text = trimmed(text);
			size_t end = 0;
			while (end < text.size() && !is_space(text[end])) {
				end += 1;
			}
			return { text.substr(0, end), trimmed(text.substr(end)) };
		}

		/*
		 * A paragraph's first sentence, and the rest: up to a full stop followed by a space or the end, or the whole
		 * paragraph.
		 */
		std::pair<std::string, std::string> first_sentence(std::string_view paragraph) {
			for (size_t i = 0; i < paragraph.size(); ++i) {
				if (paragraph[i] == '.' && (i + 1 == paragraph.size() || is_space(paragraph[i + 1]) || paragraph[i + 1] == '\n')) {
					return { std::string(trimmed(paragraph.substr(0, i + 1))), std::string(trimmed(paragraph.substr(i + 1))) };
				}
			}
			return { std::string(trimmed(paragraph)), std::string() };
		}

		void problem(std::vector<DocumentationTag>* problems, uint32_t line, uint16_t column, std::string text) {
			if (problems != nullptr) {
				problems->push_back(DocumentationTag{ std::string(), std::string(), std::move(text), line, column });
			}
		}
	}

	const DocumentationTag* Documentation::tag_named(std::string_view tag, std::string_view name) const {
		for (const DocumentationTag& each : tags) {
			if (each.tag == tag && (name.empty() || each.name == name)) {
				return &each;
			}
		}
		return nullptr;
	}

	bool is_documentation(std::string_view comment) {
		return comment.size() > 4 && comment.starts_with("/**") && comment[3] != '*' && comment[3] != '/';
	}

	Documentation parse_documentation(std::string_view text, uint32_t line, uint16_t column, std::vector<DocumentationTag>* problems) {
		Documentation result;
		result.line = line;
		result.column = column;
		std::string_view body = text;
		if (body.starts_with("/**")) {
			body.remove_prefix(3);
		}
		if (body.starts_with("<")) {
			body.remove_prefix(1);
		}
		const size_t end = body.rfind("*/");
		if (end != std::string_view::npos) {
			body = body.substr(0, end);
		}
		// Each line without its margin: the spaces, and a * and the space after it
		std::vector<std::pair<std::string, uint32_t>> lines;
		size_t start = 0;
		uint32_t at_line = line;
		while (start <= body.size()) {
			size_t stop = body.find('\n', start);
			if (stop == std::string_view::npos) {
				stop = body.size();
			}
			std::string_view part = body.substr(start, stop - start);
			while (!part.empty() && is_space(part.front())) {
				part.remove_prefix(1);
			}
			if (part.starts_with("*")) {
				part.remove_prefix(1);
				if (part.starts_with(" ")) {
					part.remove_prefix(1);
				}
			}
			while (!part.empty() && is_space(part.back())) {
				part.remove_suffix(1);
			}
			lines.emplace_back(std::string(part), at_line);
			at_line += 1;
			start = stop + 1;
		}
		// The prose before the tags, and each tag with the lines after it
		std::string prose;
		DocumentationTag* current = nullptr;
		for (const auto& [content, number] : lines) {
			std::string_view each = content;
			if (each.size() > 1 && each.front() == '@' && is_tag_letter(each[1])) {
				size_t word_end = 1;
				while (word_end < each.size() && is_tag_letter(each[word_end])) {
					word_end += 1;
				}
				std::string tag(each.substr(1, word_end - 1));
				std::string_view rest = trimmed(each.substr(word_end));
				bool known = false;
				for (std::string_view name : TAGS) {
					known = known || name == tag;
				}
				if (!known) {
					problem(problems, number, column, std::format("@{} isn't a documentation tag", tag));
					current = nullptr;
					continue;
				}
				if (tag == "returns") {
					tag = "return";
				}
				DocumentationTag made{ tag, std::string(), std::string(), number, column };
				if (names_one(tag)) {
					auto [name, after] = first_word(rest);
					if (name.empty()) {
						problem(problems, number, column, std::format("@{} needs the name of what it documents", tag));
					}
					made.name = std::string(name);
					rest = after;
				}
				made.text = std::string(rest);
				for (const DocumentationTag& before : result.tags) {
					if (before.tag == made.tag && before.name == made.name
						&& (!made.name.empty() || tag == "brief" || tag == "deprecated" || tag == "since")) {
						problem(problems, number, column, made.name.empty() ? std::format("@{} is given twice", tag)
							: std::format("@{} {} is given twice", tag, made.name));
					}
				}
				result.tags.push_back(std::move(made));
				current = &result.tags.back();
				continue;
			}
			if (current != nullptr) {
				// An example keeps its lines; any other tag's text is a paragraph
				if (current->tag == "example") {
					current->text += current->text.empty() ? content : "\n" + content;
				}
				else if (each.empty()) {
					current->text += "\n";
				}
				else {
					const std::string line_text(trimmed(each));
					current->text += current->text.empty() || current->text.ends_with("\n") ? line_text : " " + line_text;
				}
				continue;
			}
			prose += prose.empty() && each.empty() ? std::string() : (prose.empty() ? content : "\n" + content);
		}
		for (DocumentationTag& tag : result.tags) {
			tag.text = std::string(trimmed(tag.text));
		}
		// The summary: @brief's, or the first paragraph's first sentence
		std::string_view all = trimmed(prose);
		const DocumentationTag* brief = result.tag_named("brief");
		if (brief != nullptr) {
			result.brief = brief->text;
			result.details = std::string(all);
		}
		else {
			const size_t paragraph_end = all.find("\n\n");
			std::string first(all.substr(0, paragraph_end));
			for (char& c : first) {
				if (c == '\n') {
					c = ' ';
				}
			}
			auto [sentence, rest] = first_sentence(first);
			result.brief = sentence;
			std::string details = rest;
			if (paragraph_end != std::string_view::npos) {
				details += (details.empty() ? "" : "\n\n") + std::string(trimmed(all.substr(paragraph_end)));
			}
			result.details = std::string(trimmed(details));
		}
		std::erase_if(result.tags, [](const DocumentationTag& tag) { return tag.tag == "brief"; });
		return result;
	}

	void keep_documentation(std::string_view file_path, MyVector<Token>& tokens, bool check) {
		FileDocumentation kept;
		MyVector<Token> without;
		without.reserve(tokens.size());
		for (size_t i = 0; i < tokens.size(); ++i) {
			const Token& token = tokens[i];
			if (TokenType::COMMENT_BLOCK != token.type && TokenType::COMMENT_LINE != token.type) {
				without.push_back(token);
				continue;
			}
			if (TokenType::COMMENT_BLOCK != token.type || token.value == nullptr || !is_documentation(*token.value)) {
				continue;
			}
			std::string_view text = *token.value;
			std::vector<DocumentationTag> problems;
			parse_documentation(text, token.line_number, token.column_number, &problems);
			if (check) {
				for (const DocumentationTag& each : problems) {
					report_error(ErrorCode::E3034, file_path, each.line, each.column, each.text);
				}
			}
			if (text.starts_with("/**<")) {
				// After what it documents, on its line
				if (without.empty()) {
					if (check) {
						report_error(ErrorCode::E3034, file_path, token.line_number, token.column_number,
							"/**< documents what's before it on its line, and nothing is");
					}
					continue;
				}
				kept.trailing[without.back().line_number] = Kept{ std::string(text), token.line_number, token.column_number };
				continue;
			}
			// Before what it documents: the next token that isn't a comment, a name
			size_t next = i + 1;
			while (next < tokens.size() && (TokenType::COMMENT_BLOCK == tokens[next].type || TokenType::COMMENT_LINE == tokens[next].type)) {
				next += 1;
			}
			if (next >= tokens.size() || TokenType::IDENTIFIER != tokens[next].type) {
				if (check) {
					report_error(ErrorCode::E3034, file_path, token.line_number, token.column_number,
						"a documentation comment goes directly before what it documents, and nothing's declared after this one");
				}
				continue;
			}
			const auto key = std::make_pair(tokens[next].line_number, tokens[next].column_number);
			if (kept.leading.contains(key)) {
				if (check) {
					report_error(ErrorCode::E3034, file_path, token.line_number, token.column_number,
						"this documents what another documentation comment before it already does");
				}
				continue;
			}
			kept.leading[key] = Kept{ std::string(text), token.line_number, token.column_number };
		}
		tokens = std::move(without);
		std::scoped_lock<std::mutex> lock(files_mutex);
		files()[key_of(file_path)] = std::move(kept);
	}

	std::vector<std::string> result_documentation(const Documentation& documentation, const std::vector<std::string>& names) {
		std::vector<std::string> result(names.size());
		const bool named = !names.empty() && std::all_of(names.begin(), names.end(), [](const std::string& name) { return !name.empty(); });
		size_t position = 0;
		for (const DocumentationTag& tag : documentation.tags) {
			if (tag.tag != "return") {
				continue;
			}
			if (named) {
				auto [first, rest] = first_word(tag.text);
				for (size_t i = 0; i < names.size(); ++i) {
					if (names[i] == first) {
						result[i] = std::string(rest);
					}
				}
			}
			else if (position < result.size()) {
				result[position] = tag.text;
			}
			position += 1;
		}
		return result;
	}

	bool first_documentation_check(std::string_view file_path, uint32_t line, uint16_t column) {
		static std::mutex checked_mutex;
		static auto* checked = new std::set<std::tuple<std::string, uint32_t, uint16_t>>();
		std::scoped_lock<std::mutex> lock(checked_mutex);
		return checked->insert({ key_of(file_path), line, column }).second;
	}

	std::optional<Documentation> documentation_at(std::string_view file_path, uint32_t line, uint16_t column) {
		std::scoped_lock<std::mutex> lock(files_mutex);
		auto file = files().find(key_of(file_path));
		if (file == files().end()) {
			return std::nullopt;
		}
		auto leading = file->second.leading.find(std::make_pair(line, column));
		if (leading != file->second.leading.end()) {
			return parse_documentation(leading->second.text, leading->second.line, leading->second.column, nullptr);
		}
		auto trailing = file->second.trailing.find(line);
		if (trailing != file->second.trailing.end()) {
			return parse_documentation(trailing->second.text, trailing->second.line, trailing->second.column, nullptr);
		}
		return std::nullopt;
	}
}

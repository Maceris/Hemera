#include "front_end/fixes.h"

#include <algorithm>
#include <filesystem>
#include <format>
#include <fstream>
#include <iterator>
#include <sstream>
#include <tuple>

#include "cmd_line/options.h"
#include "front_end/base_sources.h"
#include "front_end/info.h"
#include "front_end/names.h"
#include "lexer/lexer.h"

namespace hemera {

	namespace {

		// Where line (counting from 1) starts in text, or empty past its last line
		std::optional<size_t> line_start(std::string_view text, uint32_t line) {
			size_t at = 0;
			for (uint32_t i = 1; i < line; ++i) {
				at = text.find('\n', at);
				if (at == std::string_view::npos) {
					return std::nullopt;
				}
				++at;
			}
			return at;
		}

		// The start of the line offset is on
		size_t start_of_line(std::string_view text, size_t offset) {
			const size_t newline = text.rfind('\n', offset == 0 ? 0 : offset - 1);
			return offset == 0 || newline == std::string_view::npos ? 0 : newline + 1;
		}

		// The end of the line offset is on: its \r\n or \n, or the text's end
		size_t end_of_line(std::string_view text, size_t offset) {
			size_t end = text.find('\n', offset);
			if (end == std::string_view::npos) {
				return text.size();
			}
			return end > 0 && text[end - 1] == '\r' ? end - 1 : end;
		}

		// The text's line ending, \r\n when it uses it
		std::string_view newline_of(std::string_view text) {
			const size_t newline = text.find('\n');
			return newline != std::string_view::npos && newline > 0 && text[newline - 1] == '\r' ? "\r\n" : "\n";
		}

		// The spaces and tabs a line starts with
		std::string_view indent_at(std::string_view text, size_t line_start) {
			size_t end = line_start;
			while (end < text.size() && (text[end] == ' ' || text[end] == '\t')) {
				++end;
			}
			return text.substr(line_start, end - line_start);
		}

		// text's tokens, lexed again quietly: what lexing reports, it reported when the file was first read
		MyVector<Token> tokens_of(const std::string& text, const std::string& file_path) {
			ReportScope quiet;
			ReportScope* outer = report_scope();
			set_report_scope(&quiet);
			MyVector<Token> tokens;
			std::istringstream stream{ text };
			lexer::lex(stream, tokens, Allocator<>{}, file_path, false);
			set_report_scope(outer);
			return tokens;
		}

		// An import's place among others, as the style rules sort them (D2): by location, then its path, then its name
		std::tuple<int, std::string, std::string> import_order(std::string_view location, std::string_view name) {
			int kind = 4;
			for (const auto& [prefix, order] : { std::pair{ "base:", 0 }, std::pair{ "std:", 1 }, std::pair{ "user:", 2 }, std::pair{ "vendor:", 3 } }) {
				if (location.starts_with(prefix)) {
					kind = order;
				}
			}
			return { kind, std::string(location), std::string(name) };
		}

		// An import's from text without its quotes, as the token keeps them
		std::string_view unquoted(InternedString literal) {
			std::string_view text = literal != nullptr ? std::string_view(*literal) : std::string_view();
			if (text.size() >= 2 && text.front() == '"' && text.back() == '"') {
				text = text.substr(1, text.size() - 2);
			}
			return text;
		}

		bool is_folder(const std::filesystem::path& path) {
			std::error_code error;
			return std::filesystem::is_directory(path, error);
		}
	}

	// The names in scope this thread's checker offers (NamesInScope), or null
	static thread_local const std::function<std::vector<std::string>()>* names_in_scope = nullptr;

	NamesInScope::NamesInScope(std::function<std::vector<std::string>()> given) : names(std::move(given)), outer(names_in_scope) {
		names_in_scope = &names;
	}

	NamesInScope::~NamesInScope() {
		names_in_scope = outer;
	}

	std::optional<std::string> source_text(const Options* options, const std::string& file_path) {
		const std::string* overlay = options != nullptr ? find_overlay(*options, file_path) : nullptr;
		std::ifstream file(overlay != nullptr ? *overlay : file_path, std::ios::binary);
		if (!file.is_open()) {
			return std::nullopt;
		}
		return std::string(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
	}

	std::vector<DiagnosticFix> missing_arm_fixes(const Options* options, const std::string& file_path, const ast::Node* match_node,
		const std::vector<std::string>& arms) {

		const ast::Node* cases = nullptr;
		for (const ast::Node* child : match_node->children) {
			if (ast::NodeType::LIST == child->node_type) {
				cases = child;
			}
		}
		const std::optional<std::string> text = source_text(options, file_path);
		if (cases == nullptr || cases->value.offset == Token::NO_SPAN || !text.has_value()) {
			return {};
		}
		// The match's { and its }, and its first arm's case
		const MyVector<Token> tokens = tokens_of(*text, file_path);
		size_t open = tokens.size();
		for (size_t i = 0; i < tokens.size(); ++i) {
			if (tokens[i].offset == cases->value.offset && TokenType::SYM_LBRACE == tokens[i].type) {
				open = i;
			}
		}
		std::optional<size_t> close;
		std::optional<size_t> first_case;
		int depth = 0;
		for (size_t i = open; i < tokens.size() && !close.has_value(); ++i) {
			if (TokenType::SYM_LBRACE == tokens[i].type) {
				++depth;
			}
			else if (TokenType::SYM_RBRACE == tokens[i].type && --depth == 0) {
				close = tokens[i].offset;
			}
			else if (depth == 1 && TokenType::KEYWORD_CASE == tokens[i].type && !first_case.has_value()) {
				first_case = tokens[i].offset;
			}
		}
		if (!close.has_value()) {
			return {};
		}
		const std::string_view source = *text;
		const std::string_view newline = newline_of(source);
		const size_t close_line = start_of_line(source, *close);
		const bool on_own_line = indent_at(source, close_line).size() == *close - close_line;
		const std::string indent = first_case.has_value() ? std::string(indent_at(source, start_of_line(source, *first_case)))
			: std::string(indent_at(source, close_line)) + "    ";
		const auto adding = [&](const std::vector<std::string>& patterns) {
			std::string added;
			for (const std::string& pattern : patterns) {
				added += on_own_line ? std::format("{}case {} => {{}}{}", indent, pattern, newline) : std::format(" case {} => {{}}", pattern);
			}
			if (!on_own_line) {
				added += " ";
			}
			return DiagnosticEdit{ static_cast<uint32_t>(on_own_line ? close_line : *close), 0, added };
		};
		std::vector<DiagnosticFix> fixes;
		if (!arms.empty()) {
			fixes.push_back(DiagnosticFix{ arms.size() == 1 ? std::format("Add case {}", arms[0]) : "Add the missing cases", { adding(arms) } });
		}
		fixes.push_back(DiagnosticFix{ "Add case _", { adding({ "_" }) } });
		return fixes;
	}

	std::vector<DiagnosticFix> param_tag_fixes(const Options* options, const std::string& file_path, uint32_t line, uint16_t column,
		std::string_view name, const std::optional<std::string>& rename_to) {

		const std::optional<std::string> text = source_text(options, file_path);
		const std::optional<size_t> start = text.has_value() ? line_start(*text, line) : std::nullopt;
		if (!start.has_value()) {
			return {};
		}
		const std::string_view source = *text;
		const size_t end = end_of_line(source, *start);
		const std::string_view written = source.substr(*start, end - *start);
		// The tag, at its column or else the first on its line
		size_t tag = written.find("@param", std::min<size_t>(column, written.size()));
		if (tag == std::string_view::npos) {
			tag = written.find("@param");
		}
		if (tag == std::string_view::npos) {
			return {};
		}
		size_t at = tag + std::string_view("@param").size();
		while (at < written.size() && (written[at] == ' ' || written[at] == '\t')) {
			++at;
		}
		if (written.substr(at, name.size()) != name) {
			return {};
		}
		std::vector<DiagnosticFix> fixes;
		if (rename_to.has_value()) {
			fixes.push_back(DiagnosticFix{ std::format("Change to @param {}", *rename_to),
				{ DiagnosticEdit{ static_cast<uint32_t>(*start + at), static_cast<uint32_t>(name.size()), *rename_to } } });
		}
		// Its line, and each after it that goes on with its text, indented past the tag, up to a blank one or another tag
		size_t removed_end = end;
		for (size_t next = end < source.size() ? source.find('\n', end) : std::string_view::npos; next != std::string_view::npos;) {
			const size_t next_start = next + 1;
			const size_t next_end = end_of_line(source, next_start);
			const std::string_view following = source.substr(next_start, next_end - next_start);
			const size_t star = following.find_first_not_of(" \t");
			if (star == std::string_view::npos || following[star] != '*' || following.substr(star).starts_with("*/")) {
				break;
			}
			const size_t content = following.find_first_not_of(" \t", star + 1);
			if (content == std::string_view::npos || following[content] == '@' || content <= tag) {
				break;
			}
			removed_end = next_end;
			next = next_end < source.size() ? source.find('\n', next_end) : std::string_view::npos;
		}
		// With its line end, so no empty line is left
		const size_t line_end = source.find('\n', removed_end);
		const size_t through = line_end == std::string_view::npos ? removed_end : line_end + 1;
		fixes.push_back(DiagnosticFix{ std::format("Remove @param {}", name),
			{ DiagnosticEdit{ static_cast<uint32_t>(*start), static_cast<uint32_t>(through - *start), "" } } });
		return fixes;
	}

	size_t edit_distance(std::string_view a, std::string_view b) {
		std::vector<std::vector<size_t>> d(a.size() + 1, std::vector<size_t>(b.size() + 1));
		for (size_t i = 0; i <= a.size(); ++i) {
			d[i][0] = i;
		}
		for (size_t j = 0; j <= b.size(); ++j) {
			d[0][j] = j;
		}
		for (size_t i = 1; i <= a.size(); ++i) {
			for (size_t j = 1; j <= b.size(); ++j) {
				const size_t changed = a[i - 1] == b[j - 1] ? 0 : 1;
				d[i][j] = std::min({ d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + changed });
				if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
					d[i][j] = std::min(d[i][j], d[i - 2][j - 2] + 1);
				}
			}
		}
		return d[a.size()][b.size()];
	}

	std::vector<DiagnosticFix> spelling_fixes(const ast::Node* where, std::string_view name, const std::vector<std::string>& candidates) {
		if (where == nullptr || where->value.offset == Token::NO_SPAN || where->value.length != name.size()) {
			return {};
		}
		const size_t most = std::min<size_t>(2, name.size() / 3);
		std::vector<std::pair<size_t, std::string>> near;
		for (const std::string& candidate : candidates) {
			if (candidate == name || candidate.empty()) {
				continue;
			}
			// Far apart in length can't be near
			const size_t apart = candidate.size() > name.size() ? candidate.size() - name.size() : name.size() - candidate.size();
			if (apart > most) {
				continue;
			}
			if (const size_t distance = edit_distance(name, candidate); distance <= most) {
				near.emplace_back(distance, candidate);
			}
		}
		std::sort(near.begin(), near.end());
		near.erase(std::unique(near.begin(), near.end()), near.end());
		std::vector<DiagnosticFix> fixes;
		for (size_t i = 0; i < near.size() && fixes.size() < 3; ++i) {
			fixes.push_back(DiagnosticFix{ std::format("Change to {}", near[i].second),
				{ DiagnosticEdit{ where->value.offset, where->value.length, near[i].second } } });
		}
		return fixes;
	}

	std::vector<DiagnosticFix> undeclared_name_fixes(const Options* options, ProgramInfo& program, FileInfo* file,
		const std::string& file_path, std::string_view package_path, const ast::Node* where, std::string_view name,
		std::vector<std::string> candidates, bool names_held) {

		if (where == nullptr || where->value.offset == Token::NO_SPAN) {
			return {};
		}
		std::vector<DiagnosticFix> fixes;
		const std::optional<std::string> text = source_text(options, file_path);
		const size_t after = static_cast<size_t>(where->value.offset) + where->value.length;
		// A package's name, before a .: one of base's, std's or vendor's, or one the package's other files import
		if (text.has_value() && after < text->size() && (*text)[after] == '.' && file != nullptr) {
			std::optional<std::string> location;
			if (auto package = program.packages.find(intern(std::string(package_path))); package != program.packages.end()) {
				std::scoped_lock<std::mutex> lock(package->second->files_mutex);
				for (const auto& [file_name, other] : package->second->files) {
					std::scoped_lock<std::mutex> imports_lock(other->imports_mutex);
					for (ImportInfo* import : other->imports) {
						const InternedString local = import->alias != nullptr ? import->alias : import->name;
						if (!location.has_value() && local != nullptr && std::string_view(*local) == name && import->location != nullptr) {
							location = std::string(unquoted(import->location));
						}
					}
				}
			}
			if (!location.has_value()) {
				for (const EmbeddedFile& embedded : embedded_base_files()) {
					if (embedded.folder == name) {
						location = std::format("base:{}", name);
					}
				}
			}
			for (const auto& [builtin, prefix] : { std::pair{ BuiltinPackage::STD, "std" }, std::pair{ BuiltinPackage::VENDOR, "vendor" } }) {
				auto folder = options != nullptr ? options->builtin_paths.find(builtin) : decltype(options->builtin_paths.end()){};
				if (!location.has_value() && options != nullptr && folder != options->builtin_paths.end()
					&& is_folder(folder->second / std::string(name))) {
					location = std::format("{}:{}", prefix, name);
				}
			}
			if (location.has_value()) {
				const std::string_view source = *text;
				const std::string_view newline = newline_of(source);
				const std::string line = std::format("import {} from \"{}\"", name, *location);
				// Where it sorts among the file's imports, by their places in it
				std::vector<std::pair<size_t, std::tuple<int, std::string, std::string>>> imports;
				{
					std::scoped_lock<std::mutex> lock(file->imports_mutex);
					for (ImportInfo* import : file->imports) {
						if (import->node != nullptr && import->node->value.offset != Token::NO_SPAN) {
							const InternedString local = import->alias != nullptr ? import->alias : import->name;
							imports.emplace_back(import->node->value.offset, import_order(unquoted(import->location),
								local != nullptr ? std::string_view(*local) : ""));
						}
					}
				}
				std::sort(imports.begin(), imports.end());
				const auto order = import_order(*location, name);
				DiagnosticEdit edit;
				const auto before = std::find_if(imports.begin(), imports.end(), [&](const auto& import) { return order < import.second; });
				if (before != imports.end()) {
					edit = DiagnosticEdit{ static_cast<uint32_t>(start_of_line(source, before->first)), 0, line + std::string(newline) };
				}
				else if (!imports.empty()) {
					edit = DiagnosticEdit{ static_cast<uint32_t>(end_of_line(source, imports.back().first)), 0, std::string(newline) + line };
				}
				else {
					// After the package statement, with the blank line the style rules put between them
					size_t package_line = 0;
					for (size_t at = 0; at < source.size(); at = end_of_line(source, at) + 1) {
						if (source.substr(at).starts_with("package ")) {
							package_line = at;
							break;
						}
						if (end_of_line(source, at) >= source.size()) {
							break;
						}
					}
					edit = DiagnosticEdit{ static_cast<uint32_t>(end_of_line(source, package_line)), 0,
						std::string(newline) + std::string(newline) + line };
				}
				fixes.push_back(DiagnosticFix{ std::format("Import {} from \"{}\"", name, *location), { edit } });
			}
		}
		// Names spelled almost the same: the package's own, and the file's imports
		{
			NameRegistry& names = program.names;
			std::unique_lock<std::mutex> lock(names.mutex, std::defer_lock);
			if (!names_held) {
				lock.lock();
			}
			for (const auto& [key, declaration] : names.declarations) {
				if (key.first != nullptr && std::string_view(*key.first) == package_path && key.second != nullptr) {
					candidates.emplace_back(*key.second);
				}
			}
		}
		if (file != nullptr) {
			std::scoped_lock<std::mutex> lock(file->imports_mutex);
			for (ImportInfo* import : file->imports) {
				const InternedString local = import->alias != nullptr ? import->alias : import->name;
				if (local != nullptr) {
					candidates.emplace_back(*local);
				}
			}
		}
		if (names_in_scope != nullptr) {
			for (std::string& each : (*names_in_scope)()) {
				candidates.push_back(std::move(each));
			}
		}
		for (DiagnosticFix& fix : spelling_fixes(where, name, candidates)) {
			fixes.push_back(std::move(fix));
		}
		return fixes;
	}
}

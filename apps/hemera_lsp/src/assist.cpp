#include "assist.h"

#include <algorithm>
#include <cctype>
#include <format>
#include <tuple>

#include "features.h"
#include "uri.h"

using llvm::json::Array;
using llvm::json::Object;
using llvm::json::Value;

namespace hemera::lsp {

	namespace {

		// Whether path is folder or inside it, both with / throughout
		bool within(std::string_view path, std::string_view folder) {
			return !folder.empty() && path.starts_with(folder) && (path.size() == folder.size() || path[folder.size()] == '/');
		}

		// The folder a path with / throughout is in
		std::string folder_of(std::string_view path) {
			const size_t slash = path.rfind('/');
			return std::string(slash == std::string_view::npos ? std::string_view() : path.substr(0, slash));
		}

		// Whether name has query's characters in order, ignoring ASCII case
		bool matches(std::string_view name, std::string_view query) {
			size_t at = 0;
			for (const char c : name) {
				if (at < query.size() && std::tolower(static_cast<unsigned char>(c)) == std::tolower(static_cast<unsigned char>(query[at]))) {
					++at;
				}
			}
			return at == query.size();
		}

		bool starts_with_ignoring_case(std::string_view name, std::string_view query) {
			return name.size() >= query.size() && std::equal(query.begin(), query.end(), name.begin(), [](char a, char b) {
				return std::tolower(static_cast<unsigned char>(a)) == std::tolower(static_cast<unsigned char>(b));
			});
		}

		// SymbolKind's values (the Language Server Protocol)
		int64_t symbol_kind(const IndexedDeclaration& declaration) {
			if (declaration.kind == "function") {
				return 12;
			}
			if (declaration.kind == "type") {
				return declaration.is == "enum" ? 10 : declaration.is == "struct" || declaration.is == "union" ? 23 : 26;
			}
			if (declaration.kind == "field") {
				return 8;
			}
			if (declaration.kind == "member" || declaration.kind == "variant") {
				return 22;
			}
			return 14;
		}

		// How many UTF-16 code units text takes, as a signature's label's offsets count
		uint32_t utf16_length(std::string_view text) {
			uint32_t units = 0;
			for (size_t i = 0; i < text.size(); ++i) {
				const auto byte = static_cast<unsigned char>(text[i]);
				// A character's first byte counts, and one of four bytes takes two units
				if ((byte & 0xC0) != 0x80) {
					units += byte >= 0xF0 ? 2 : 1;
				}
			}
			return units;
		}

		// What follows the top-level ) of a function type, like " -> int" in fn(int) -> int; empty when nothing does
		std::string_view result_of(std::string_view type) {
			int depth = 0;
			for (size_t i = 0; i < type.size(); ++i) {
				if (type[i] == '(' || type[i] == '[') {
					++depth;
				}
				else if ((type[i] == ')' || type[i] == ']') && --depth == 0 && type[i] == ')') {
					return type.substr(i + 1);
				}
			}
			return {};
		}

		// A function type's parameter types, like int and string in fn(int, string) -> int, split at top-level commas
		std::vector<std::string> parameter_types(std::string_view type) {
			std::vector<std::string> found;
			const size_t open = type.find('(');
			if (!type.starts_with("fn") || open == std::string_view::npos) {
				return found;
			}
			int depth = 0;
			size_t start = open + 1;
			for (size_t i = open; i < type.size(); ++i) {
				const char c = type[i];
				if (c == '(' || c == '[') {
					++depth;
				}
				else if (c == ')' || c == ']') {
					if (--depth == 0) {
						if (i > start) {
							found.emplace_back(type.substr(start, i - start));
						}
						break;
					}
				}
				else if (c == ',' && depth == 1) {
					found.emplace_back(type.substr(start, i - start));
					start = i + 2 <= type.size() && type[i + 1] == ' ' ? i + 2 : i + 1;
				}
			}
			return found;
		}

		// The call around the cursor, from the tokens: its ( and the argument the cursor's in, by position or name
		struct OpenCall {
			size_t paren = 0;
			size_t argument = 0;
			std::string named;
		};

		std::optional<OpenCall> open_call(const ParsedDocument& parsed, size_t cursor) {
			const MyVector<Token>& tokens = parsed.tokens;
			size_t last = 0;
			while (last < tokens.size() && tokens[last].offset != Token::NO_SPAN && tokens[last].offset < cursor
				&& TokenType::END_OF_FILE != tokens[last].type) {
				++last;
			}
			int depth = 0;
			size_t commas = 0;
			// The nearest comma before the cursor at the call's own depth, after which its argument starts
			std::optional<size_t> nearest_comma;
			for (size_t i = last; i-- > 0;) {
				const TokenType type = tokens[i].type;
				if (TokenType::SYM_RPAREN == type || TokenType::SYM_RBRACK == type || TokenType::SYM_RBRACE == type) {
					++depth;
					continue;
				}
				if (TokenType::SYM_LBRACE == type) {
					if (depth == 0) {
						return std::nullopt;
					}
					--depth;
					continue;
				}
				if (TokenType::SYM_LBRACK == type) {
					if (depth == 0) {
						return std::nullopt;
					}
					--depth;
					continue;
				}
				if (TokenType::SYM_LPAREN == type) {
					if (depth > 0) {
						--depth;
						continue;
					}
					OpenCall call{ i, commas, {} };
					// name = at the argument's start names its parameter
					const size_t argument_start = nearest_comma.has_value() ? *nearest_comma + 1 : i + 1;
					if (argument_start + 1 < last && TokenType::IDENTIFIER == tokens[argument_start].type
						&& TokenType::OPERATOR_ASSIGN == tokens[argument_start + 1].type && tokens[argument_start].value != nullptr) {
						call.named = std::string(*tokens[argument_start].value);
					}
					return call;
				}
				if (depth == 0 && TokenType::SYM_COMMA == type) {
					if (!nearest_comma.has_value()) {
						nearest_comma = i;
					}
					++commas;
				}
			}
			return std::nullopt;
		}

		// The name a call calls, before its ( and a macro's !, and any generic arguments in [ ]; its token's index
		std::optional<size_t> callee_token(const ParsedDocument& parsed, size_t paren) {
			const MyVector<Token>& tokens = parsed.tokens;
			size_t i = paren;
			if (i > 0 && TokenType::OPERATOR_NOT == tokens[i - 1].type) {
				--i;
			}
			if (i > 0 && TokenType::SYM_RBRACK == tokens[i - 1].type) {
				int depth = 0;
				while (i-- > 0) {
					if (TokenType::SYM_RBRACK == tokens[i].type) {
						++depth;
					}
					else if (TokenType::SYM_LBRACK == tokens[i].type && --depth == 0) {
						break;
					}
				}
			}
			if (i == 0 || TokenType::IDENTIFIER != tokens[i - 1].type || tokens[i - 1].offset == Token::NO_SPAN) {
				return std::nullopt;
			}
			return i - 1;
		}

		/*
		 * The declaration a call's name names: what the index says is there, or, typed since the check, a top-level one
		 * of that name in the file's package, or in the package before a . by its import
		 */
		std::optional<size_t> called(const AssistRequest& request, CompletionTables& tables, size_t token) {
			const LoadedIndex& index = tables.index();
			const MyVector<Token>& tokens = request.parsed->tokens;
			const Token& name = tokens[token];
			const std::string key = path_key(request.file);
			const Moved moved(request.checked_text, request.text);
			if (const std::optional<size_t> then = moved.back(name.offset)) {
				if (const std::optional<LoadedIndex::NameAt> found = index.name_at(key, *then); found.has_value() && found->offset == *then) {
					return found->declaration;
				}
			}
			std::string folder = path_key(folder_of(request.file));
			if (token >= 2 && TokenType::SYM_DOT == tokens[token - 1].type && TokenType::IDENTIFIER == tokens[token - 2].type
				&& tokens[token - 2].value != nullptr) {
				folder.clear();
				if (auto imports = index.imports.find(key); imports != index.imports.end()) {
					for (const IndexedImport& import : imports->second) {
						if (request.checked_text.substr(import.offset, import.length) == std::string_view(*tokens[token - 2].value)) {
							folder = path_key(import.folder);
						}
					}
				}
			}
			for (const size_t number : tables.top_level_in(folder)) {
				if (tables.name_of(number) == std::string_view(*name.value)) {
					return number;
				}
			}
			return std::nullopt;
		}
	}

	Array workspace_symbols(std::string_view query, const std::vector<CompletionTables*>& tables,
		const std::vector<std::string>& workspace_folders, Encoding encoding, size_t limit) {

		struct Found {
			bool not_prefix;
			bool not_ours;
			size_t length;
			std::string_view name;
			CompletionTables* tables;
			size_t number;
		};
		std::vector<Found> found;
		for (CompletionTables* of : tables) {
			const LoadedIndex& index = of->index();
			for (const auto& [number, name] : of->symbols()) {
				if (!matches(name, query)) {
					continue;
				}
				const IndexedDeclaration& declaration = index.declarations[number];
				const bool ours = std::any_of(workspace_folders.begin(), workspace_folders.end(),
					[&](const std::string& folder) { return within(declaration.file, folder); });
				found.push_back(Found{ !starts_with_ignoring_case(name, query), !ours, name.size(), name, of, number });
			}
		}
		std::sort(found.begin(), found.end(), [](const Found& a, const Found& b) {
			return std::tie(a.not_prefix, a.not_ours, a.length, a.name) < std::tie(b.not_prefix, b.not_ours, b.length, b.name);
		});
		// The same declaration in several roots' indexes, once
		Array symbols;
		std::set<std::tuple<std::string, uint32_t>> seen;
		for (const Found& each : found) {
			if (symbols.size() >= limit) {
				break;
			}
			const IndexedDeclaration& declaration = each.tables->index().declarations[each.number];
			if (!seen.emplace(path_key(declaration.file), declaration.name_offset).second) {
				continue;
			}
			const LineIndex lines(each.tables->text_of(declaration.file));
			Object symbol{
				{ "name", std::string(each.name) },
				{ "kind", symbol_kind(declaration) },
				{ "location", Object{ { "uri", uri_from_path(declaration.file) },
					{ "range", Object{ { "start", position_at(lines, declaration.name_offset, encoding) },
						{ "end", position_at(lines, static_cast<size_t>(declaration.name_offset) + declaration.name_length, encoding) } } } } },
			};
			if (declaration.in.has_value()) {
				symbol["containerName"] = std::string(each.tables->name_of(*declaration.in));
			}
			symbols.push_back(std::move(symbol));
		}
		return symbols;
	}

	Value signature_help(const AssistRequest& request, CompletionTables* tables) {
		if (tables == nullptr || request.parsed == nullptr || !request.parsed->lexed || request.parsed->text != request.text) {
			return nullptr;
		}
		const std::optional<OpenCall> call = open_call(*request.parsed, request.offset);
		const std::optional<size_t> token = call.has_value() ? callee_token(*request.parsed, call->paren) : std::nullopt;
		const std::optional<size_t> number = token.has_value() ? called(request, *tables, *token) : std::nullopt;
		if (!number.has_value()) {
			return nullptr;
		}
		const IndexedDeclaration& declaration = tables->index().declarations[*number];
		const std::string name(tables->name_of(*number));
		std::string label = name + "(";
		Array parameters;
		size_t active = call->argument;
		const auto add = [&](const std::string& text, const std::string& documentation) {
			if (parameters.size() > 0) {
				label += ", ";
			}
			const uint32_t start = utf16_length(label);
			label += text;
			Object parameter{ { "label", Array{ start, utf16_length(label) } } };
			if (!documentation.empty()) {
				parameter["documentation"] = Object{ { "kind", "markdown" }, { "value", documentation } };
			}
			parameters.push_back(std::move(parameter));
		};
		if (declaration.kind == "function") {
			const std::string_view text = tables->text_of(declaration.file);
			for (size_t i = 0; i < declaration.parameters.size(); ++i) {
				const IndexedDeclaration::Parameter& parameter = declaration.parameters[i];
				std::string written = parameter.name;
				if (!parameter.type.empty()) {
					written += (written.empty() ? "" : " : ") + parameter.type + (parameter.variadic ? "..." : "");
				}
				if (parameter.default_span.has_value() && parameter.default_span->first + parameter.default_span->second <= text.size()) {
					written += (parameter.type.empty() ? " := " : " = ")
						+ std::string(text.substr(parameter.default_span->first, parameter.default_span->second));
				}
				std::string documentation;
				for (const IndexedDeclaration::Tag& tag : declaration.tags) {
					if (tag.tag == "param" && tag.name == parameter.name) {
						documentation = tag.text;
					}
				}
				add(written, documentation);
				if (!call->named.empty() && parameter.name == call->named) {
					active = i;
				}
			}
		}
		else if (declaration.type.starts_with("fn")) {
			// A value of function type: its type's parameters, which have no names
			for (const std::string& type : parameter_types(declaration.type)) {
				add(type, "");
			}
		}
		else {
			return nullptr;
		}
		label += ")";
		label += std::string(result_of(declaration.type));
		// A variadic last parameter takes every argument after it
		if (!parameters.empty() && active >= parameters.size() && declaration.kind == "function"
			&& !declaration.parameters.empty() && declaration.parameters.back().variadic) {
			active = parameters.size() - 1;
		}
		Object signature{ { "label", label }, { "parameters", std::move(parameters) } };
		if (!declaration.brief.empty()) {
			signature["documentation"] = Object{ { "kind", "markdown" }, { "value", declaration.brief } };
		}
		return Object{ { "signatures", Array{ std::move(signature) } }, { "activeSignature", 0 },
			{ "activeParameter", static_cast<int64_t>(active) } };
	}

	Array inlay_hints(const AssistRequest& request, const LoadedIndex& index) {
		Array hints;
		const std::string key = path_key(request.file);
		auto declared = index.declared.find(key);
		if (declared == index.declared.end()) {
			return hints;
		}
		const Moved moved(request.checked_text, request.text);
		const LineIndex lines(request.text);
		for (const size_t number : declared->second) {
			const IndexedDeclaration& declaration = index.declarations[number];
			if (declaration.kind != "local" || declaration.type.empty() || !declaration.text.empty()) {
				continue;
			}
			const std::optional<size_t> start = moved.forward(declaration.name_offset);
			const std::optional<size_t> end = moved.forward(static_cast<size_t>(declaration.name_offset) + declaration.name_length);
			if (!start.has_value() || !end.has_value() || *end - *start != declaration.name_length || *end > request.text.size()
				|| *end < request.offset || *start > request.end) {
				continue;
			}
			// Its type written, like x : int = 0, which : followed by neither : nor = says
			size_t after = *end;
			while (after < request.text.size() && (request.text[after] == ' ' || request.text[after] == '\t')) {
				++after;
			}
			if (after + 1 < request.text.size() && request.text[after] == ':' && request.text[after + 1] != ':' && request.text[after + 1] != '=') {
				continue;
			}
			constexpr size_t LONGEST = 40;
			std::string shown = declaration.type;
			if (shown.size() > LONGEST) {
				// Cut before a character, not inside one
				size_t cut = LONGEST - 1;
				while (cut > 0 && (static_cast<unsigned char>(shown[cut]) & 0xC0) == 0x80) {
					--cut;
				}
				shown = shown.substr(0, cut) + "\xE2\x80\xA6";
			}
			Object hint{ { "position", position_at(lines, *end, request.encoding) }, { "label", ": " + shown }, { "kind", 1 } };
			if (shown != declaration.type) {
				hint["tooltip"] = declaration.type;
			}
			hints.push_back(std::move(hint));
		}
		return hints;
	}
}

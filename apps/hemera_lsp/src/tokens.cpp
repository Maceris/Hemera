#include "tokens.h"

#include <algorithm>
#include <cstdint>
#include <set>
#include <vector>

#include "features.h"
#include "uri.h"

namespace hemera::lsp {

	using llvm::json::Array;
	using llvm::json::Object;

	namespace {

		// The token types, in the legend's order
		enum TokenKind : uint32_t {
			NAMESPACE,
			TYPE,
			STRUCT,
			ENUM,
			PARAMETER,
			VARIABLE,
			PROPERTY,
			ENUM_MEMBER,
			FUNCTION,
			MACRO,
		};
		constexpr const char* TYPE_NAMES[] = { "namespace", "type", "struct", "enum", "parameter", "variable", "property",
			"enumMember", "function", "macro" };

		// The modifiers, as bits, in the legend's order
		constexpr uint32_t DECLARATION = 1u << 0;
		constexpr uint32_t READONLY = 1u << 1;
		constexpr uint32_t DEPRECATED = 1u << 2;
		constexpr uint32_t DEFAULT_LIBRARY = 1u << 3;
		constexpr const char* MODIFIER_NAMES[] = { "declaration", "readonly", "deprecated", "defaultLibrary" };

		// A token, by its byte offset and length in the text now
		struct Made {
			size_t offset = 0;
			size_t length = 0;
			uint32_t type = 0;
			uint32_t modifiers = 0;
			// Whether it's from the index, which wins over one from the parse at the same place
			bool indexed = false;
		};

		// Whether path is folder or inside it, both with / throughout
		bool within(std::string_view path, std::string_view folder) {
			return !folder.empty() && path.starts_with(folder) && (path.size() == folder.size() || path[folder.size()] == '/');
		}

		// A declaration's token type and the modifiers it always has
		std::pair<uint32_t, uint32_t> kind_of(const IndexedDeclaration& declaration, const TokensRequest& request) {
			uint32_t type = VARIABLE;
			uint32_t modifiers = 0;
			if (declaration.kind == "function") {
				type = declaration.macro ? MACRO : FUNCTION;
			}
			else if (declaration.kind == "type") {
				type = declaration.is == "struct" ? STRUCT : declaration.is == "enum" ? ENUM : TYPE;
			}
			else if (declaration.kind == "constant") {
				modifiers |= READONLY;
			}
			else if (declaration.kind == "field") {
				type = PROPERTY;
			}
			else if (declaration.kind == "member" || declaration.kind == "variant") {
				type = ENUM_MEMBER;
			}
			else if (declaration.kind == "parameter" || declaration.kind == "local") {
				type = declaration.kind == "parameter" ? PARAMETER : VARIABLE;
				modifiers |= declaration.readonly ? READONLY : 0;
			}
			if (within(declaration.file, request.base_folder) || within(declaration.file, request.std_folder)) {
				modifiers |= DEFAULT_LIBRARY;
			}
			if (std::any_of(declaration.tags.begin(), declaration.tags.end(), [](const IndexedDeclaration::Tag& tag) { return tag.tag == "deprecated"; })) {
				modifiers |= DEPRECATED;
			}
			return { type, modifiers };
		}

		// What the index says of the file: each use and each declaration's own name, and each import's name
		void from_index(const TokensRequest& request, const LoadedIndex& index, std::vector<Made>& made) {
			const std::string key = path_key(request.file);
			const Moved moved(request.checked_text, request.text);
			const auto add = [&](size_t offset, size_t length, uint32_t type, uint32_t modifiers) {
				const std::optional<size_t> start = moved.forward(offset);
				const std::optional<size_t> end = moved.forward(offset + length);
				// One in what changed since the check, or spread by it, has none: the grammar's color shows there
				if (start.has_value() && end.has_value() && *end - *start == length && *end <= request.text.size()) {
					made.push_back(Made{ *start, length, type, modifiers, true });
				}
			};
			if (auto uses = index.uses.find(key); uses != index.uses.end()) {
				for (const IndexedUse& use : uses->second) {
					if (use.declaration < index.declarations.size()) {
						const auto [type, modifiers] = kind_of(index.declarations[use.declaration], request);
						add(use.offset, use.length, type, modifiers);
					}
				}
			}
			if (auto declared = index.declared.find(key); declared != index.declared.end()) {
				for (const size_t number : declared->second) {
					const IndexedDeclaration& declaration = index.declarations[number];
					// One inserted code made is named at its #insert, which isn't its name
					if (!declaration.text.empty()) {
						continue;
					}
					const auto [type, modifiers] = kind_of(declaration, request);
					add(declaration.name_offset, declaration.name_length, type, modifiers | DECLARATION);
				}
			}
			if (auto imports = index.imports.find(key); imports != index.imports.end()) {
				for (const IndexedImport& import : imports->second) {
					add(import.offset, import.length, NAMESPACE, DECLARATION);
				}
			}
		}

		// Whether token is a name, written as text
		bool is_name(const Token& token, std::string_view text) {
			return TokenType::IDENTIFIER == token.type && token.value != nullptr && std::string_view(*token.value) == text
				&& token.offset != Token::NO_SPAN;
		}

		/*
		 * What the parse says: each import's name, and each package name used before a ., like compiler in
		 * compiler.report, unless a . comes before it too
		 */
		void namespaces(const ParsedDocument& parsed, std::vector<Made>& made) {
			const MyVector<Token>& tokens = parsed.tokens;
			std::set<std::string_view> packages;
			for (size_t i = 0; i + 1 < tokens.size(); ++i) {
				// import name, or import name as alias, at a line's start
				if (tokens[i].column_number != 0 || !is_name(tokens[i], "import") || TokenType::IDENTIFIER != tokens[i + 1].type
					|| tokens[i + 1].value == nullptr) {
					continue;
				}
				const bool aliased = i + 3 < tokens.size() && is_name(tokens[i + 2], "as") && TokenType::IDENTIFIER == tokens[i + 3].type
					&& tokens[i + 3].value != nullptr;
				const Token& name = aliased ? tokens[i + 3] : tokens[i + 1];
				packages.insert(std::string_view(*name.value));
				if (name.offset != Token::NO_SPAN) {
					made.push_back(Made{ name.offset, name.length, NAMESPACE, DECLARATION, false });
				}
			}
			for (size_t i = 0; i + 1 < tokens.size(); ++i) {
				const Token& token = tokens[i];
				if (TokenType::IDENTIFIER != token.type || token.value == nullptr || token.offset == Token::NO_SPAN
					|| TokenType::SYM_DOT != tokens[i + 1].type || (i > 0 && TokenType::SYM_DOT == tokens[i - 1].type)
					|| !packages.contains(std::string_view(*token.value))) {
					continue;
				}
				made.push_back(Made{ token.offset, token.length, NAMESPACE, 0, false });
			}
		}

		// A name's token, from the parse: its node's span
		void add_name(const ast::Node* name, uint32_t type, uint32_t modifiers, std::vector<Made>& made) {
			if (name != nullptr && ast::NodeType::IDENTIFIER == name->node_type && name->value.offset != Token::NO_SPAN) {
				made.push_back(Made{ name->value.offset, name->value.length, type, modifiers, false });
			}
		}

		/*
		 * A file the index doesn't have: its top-level declarations from its parse, as the outline finds them, with a
		 * struct's fields, an enum's members and a union's variants
		 */
		void declarations(const ParsedDocument& parsed, std::vector<Made>& made) {
			if (parsed.recovered == nullptr) {
				return;
			}
			std::vector<const ast::Node*> top;
			for (const ast::Node* child : parsed.recovered->children) {
				if (ast::NodeType::ERROR == child->node_type) {
					top.insert(top.end(), child->children.begin(), child->children.end());
				}
				else {
					top.push_back(child);
				}
			}
			for (const ast::Node* declaration : top) {
				if (ast::NodeType::DEFINITION != declaration->node_type || declaration->children.empty()) {
					continue;
				}
				uint32_t type = VARIABLE;
				uint32_t modifiers = DECLARATION | READONLY;
				const ast::Node* body = nullptr;
				for (size_t j = 1; j < declaration->children.size(); ++j) {
					const ast::NodeType value = declaration->children[j]->node_type;
					if (ast::NodeType::FUNCTION == value) {
						type = FUNCTION;
					}
					else if (ast::NodeType::STRUCT == value || ast::NodeType::ENUM == value || ast::NodeType::UNION == value) {
						type = ast::NodeType::STRUCT == value ? STRUCT : ast::NodeType::ENUM == value ? ENUM : TYPE;
						body = declaration->children[j];
					}
					else if (ast::NodeType::KEYWORD_ALIAS == value || ast::NodeType::KEYWORD_DISTINCT == value) {
						type = TYPE;
					}
					else {
						continue;
					}
					modifiers = DECLARATION;
					break;
				}
				add_name(declaration->children[0], type, modifiers, made);
				if (body == nullptr) {
					continue;
				}
				for (const ast::Node* member : body->children) {
					if (ast::NodeType::STRUCT == body->node_type) {
						if (ast::NodeType::DEFINITION == member->node_type && !member->children.empty()) {
							add_name(member->children[0], PROPERTY, DECLARATION, made);
						}
					}
					else {
						add_name(member, ENUM_MEMBER, DECLARATION, made);
					}
				}
			}
		}
	}

	Object semantic_tokens_legend() {
		Array types;
		for (const char* name : TYPE_NAMES) {
			types.push_back(name);
		}
		Array modifiers;
		for (const char* name : MODIFIER_NAMES) {
			modifiers.push_back(name);
		}
		return Object{ { "tokenTypes", std::move(types) }, { "tokenModifiers", std::move(modifiers) } };
	}

	Object semantic_tokens(const TokensRequest& request, const LoadedIndex* index) {
		std::vector<Made> made;
		const std::string key = path_key(request.file);
		const bool indexed = index != nullptr && (index->uses.contains(key) || index->declared.contains(key));
		if (indexed) {
			from_index(request, *index, made);
		}
		if (request.parsed != nullptr && request.parsed->text == request.text) {
			namespaces(*request.parsed, made);
			if (!indexed) {
				declarations(*request.parsed, made);
			}
		}
		// In order, and one at a place: the index's over the parse's
		std::sort(made.begin(), made.end(), [](const Made& a, const Made& b) {
			return a.offset != b.offset ? a.offset < b.offset : a.indexed > b.indexed;
		});
		const LineIndex lines(request.text);
		Array data;
		uint32_t previous_line = 0;
		uint32_t previous_start = 0;
		size_t covered = 0;
		for (const Made& token : made) {
			// Overlapping one before, like a second at the same place
			if (token.offset < covered || token.length == 0) {
				continue;
			}
			if ((request.start.has_value() && token.offset + token.length <= *request.start)
				|| (request.end.has_value() && token.offset >= *request.end)) {
				continue;
			}
			covered = token.offset + token.length;
			const auto [line, byte] = lines.line_and_byte(token.offset);
			const uint32_t start = lines.character(line, byte, request.encoding);
			const uint32_t end = lines.character(line, byte + static_cast<uint32_t>(token.length), request.encoding);
			if (end <= start) {
				continue;
			}
			data.push_back(static_cast<int64_t>(line - previous_line));
			data.push_back(static_cast<int64_t>(line == previous_line ? start - previous_start : start));
			data.push_back(static_cast<int64_t>(end - start));
			data.push_back(static_cast<int64_t>(token.type));
			data.push_back(static_cast<int64_t>(token.modifiers));
			previous_line = line;
			previous_start = start;
		}
		return Object{ { "data", std::move(data) } };
	}
}

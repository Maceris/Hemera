#include "completion.h"

#include <algorithm>
#include <filesystem>
#include <set>

#include "features.h"
#include "uri.h"

using llvm::json::Array;
using llvm::json::Object;
using llvm::json::Value;

namespace hemera::lsp {

	namespace {

		// The folder a path with / throughout is in
		std::string folder_of(std::string_view path) {
			const size_t slash = path.rfind('/');
			return std::string(slash == std::string_view::npos ? std::string_view() : path.substr(0, slash));
		}

		// Whether a byte can be in a name: a letter, a digit, _, or any byte of a character outside ASCII
		bool in_name(char c) {
			const auto byte = static_cast<unsigned char>(c);
			return std::isalnum(byte) != 0 || c == '_' || byte >= 0x80;
		}

		// CompletionItemKind's values (the Language Server Protocol)
		namespace item_kinds {
			constexpr int64_t FUNCTION = 3;
			constexpr int64_t FIELD = 5;
			constexpr int64_t VARIABLE = 6;
			constexpr int64_t MODULE = 9;
			constexpr int64_t KEYWORD = 14;
			constexpr int64_t FOLDER = 19;
			constexpr int64_t ENUM_MEMBER = 20;
			constexpr int64_t CONSTANT = 21;
			constexpr int64_t STRUCT = 22;
		}

		constexpr std::string_view KEYWORDS[] = { "auto_cast", "bit_cast", "break", "case", "cast", "compute", "continue", "defer",
			"distinct", "else", "enum", "false", "fn", "for", "give", "if", "is_error", "is_none", "is_ok", "is_some", "loop", "match",
			"mut", "null", "or_break", "or_continue", "or_else", "or_return", "push_context", "return", "struct", "switch", "true",
			"union", "using", "void", "while", "with" };

		constexpr std::string_view BUILTIN_TYPES[] = { "any", "bool", "char", "cstring", "f16", "f32", "f64", "i8", "i16", "i32",
			"i64", "i128", "int", "rawptr", "string", "type", "u8", "u16", "u32", "u64", "u128", "uint", "uintptr", "usize", "void" };

		int64_t item_kind(const IndexedDeclaration& declaration) {
			if (declaration.kind == "function") {
				return item_kinds::FUNCTION;
			}
			if (declaration.kind == "type") {
				return item_kinds::STRUCT;
			}
			if (declaration.kind == "field") {
				return item_kinds::FIELD;
			}
			if (declaration.kind == "member" || declaration.kind == "variant") {
				return item_kinds::ENUM_MEMBER;
			}
			if (declaration.is_local()) {
				return item_kinds::VARIABLE;
			}
			return item_kinds::CONSTANT;
		}

		// The items made so far, each label once: the first one made wins
		struct Items {
			Array array;
			std::set<std::string> labels;

			void add(std::string label, int64_t kind, std::string_view group, std::string detail = {}, std::string documentation = {}) {
				if (label.empty() || !labels.insert(label).second) {
					return;
				}
				Object item{ { "label", label }, { "kind", kind }, { "sortText", std::string(group) + label } };
				if (!detail.empty()) {
					item["detail"] = std::move(detail);
				}
				if (!documentation.empty()) {
					item["documentation"] = Object{ { "kind", "markdown" }, { "value", std::move(documentation) } };
				}
				array.push_back(std::move(item));
			}

			void add(CompletionTables& tables, size_t number, std::string_view group) {
				const IndexedDeclaration& declaration = tables.index().declarations[number];
				std::string documentation = declaration.brief;
				if (!declaration.details.empty()) {
					documentation += (documentation.empty() ? "" : "\n\n") + declaration.details;
				}
				add(std::string(tables.name_of(number)), item_kind(declaration), group, declaration.type, std::move(documentation));
			}
		};

		// The imports written in the document now: each name it's used by, and the path it's from, as written
		std::vector<std::pair<std::string, std::string>> written_imports(const CompletionRequest& request) {
			std::vector<std::pair<std::string, std::string>> found;
			if (request.parsed == nullptr) {
				return found;
			}
			const MyVector<Token>& tokens = request.parsed->tokens;
			const auto word = [&](size_t i) {
				return i < tokens.size() && TokenType::IDENTIFIER == tokens[i].type && tokens[i].value != nullptr
					? std::string_view(*tokens[i].value) : std::string_view();
			};
			for (size_t i = 0; i < tokens.size(); ++i) {
				if (word(i) != "import" || tokens[i].column_number != 0) {
					continue;
				}
				size_t at = i + 1;
				std::string name(word(at));
				if (word(at + 1) == "as") {
					at += 2;
					name = std::string(word(at));
				}
				const size_t from = at + 1;
				if (name.empty() || word(from) != "from" || from + 1 >= tokens.size() || TokenType::LITERAL_STRING != tokens[from + 1].type
					|| tokens[from + 1].offset == Token::NO_SPAN) {
					continue;
				}
				std::string_view written = std::string_view(request.text).substr(tokens[from + 1].offset, tokens[from + 1].length);
				if (written.size() >= 2 && written.front() == '"' && written.back() == '"') {
					written = written.substr(1, written.size() - 2);
				}
				found.emplace_back(std::move(name), std::string(written));
			}
			return found;
		}

		// The folders beside base's, holding std's and vendor's packages, by the prefix an import names them with
		std::string library_folder(const CompletionRequest& request, std::string_view prefix) {
			if (request.base_folder.empty()) {
				return {};
			}
			if (prefix == "base") {
				return request.base_folder;
			}
			return folder_of(request.base_folder) + "/" + std::string(prefix);
		}

		// The folder of the package an import's path names, as written, from the document's folder; empty if it can't tell
		std::string import_folder(const CompletionRequest& request, std::string_view path) {
			const size_t colon = path.find(':');
			std::string folder;
			if (colon != std::string_view::npos) {
				const std::string library = library_folder(request, path.substr(0, colon));
				if (library.empty()) {
					return {};
				}
				folder = library + "/" + std::string(path.substr(colon + 1));
			}
			else {
				folder = folder_of(request.file) + "/" + std::string(path);
			}
			return path_key(folder);
		}

		/*
		 * In an import's string, still open at the cursor: the folders its path can go on to. Empty when the cursor
		 * isn't in one.
		 */
		std::optional<Array> import_items(const CompletionRequest& request) {
			const std::string_view text = request.text;
			const size_t at = std::min(request.offset, text.size());
			const size_t line_start = at == 0 ? 0 : text.rfind('\n', at - 1) + 1;
			std::string_view line = text.substr(line_start, at - line_start);
			if (!line.starts_with("import ") || std::count(line.begin(), line.end(), '"') != 1) {
				return std::nullopt;
			}
			const std::string_view typed = line.substr(line.find('"') + 1);
			std::string root;
			std::string_view rest = typed;
			Items items;
			if (const size_t colon = typed.find(':'); colon != std::string_view::npos) {
				root = library_folder(request, typed.substr(0, colon));
				rest = typed.substr(colon + 1);
			}
			else {
				root = folder_of(request.file);
				if (!typed.starts_with(".") && typed.find('/') == std::string_view::npos && !request.base_folder.empty()) {
					for (const std::string_view library : { "std", "vendor", "base" }) {
						items.add(std::string(library) + ":", item_kinds::MODULE, "1");
					}
				}
			}
			const size_t slash = rest.rfind('/');
			const std::string_view within = slash == std::string_view::npos ? std::string_view() : rest.substr(0, slash + 1);
			const std::string_view segment = slash == std::string_view::npos ? rest : rest.substr(slash + 1);
			if (!root.empty()) {
				std::error_code error;
				std::vector<std::string> folders;
				for (const auto& entry : std::filesystem::directory_iterator(std::filesystem::path(root + "/" + std::string(within)), error)) {
					std::error_code is_error;
					const std::string name = entry.path().filename().string();
					if (entry.is_directory(is_error) && !name.starts_with(".")) {
						folders.push_back(name);
					}
				}
				std::sort(folders.begin(), folders.end());
				for (const std::string& folder : folders) {
					items.add(folder, item_kinds::FOLDER, "0");
				}
			}
			// Each replaces what's typed of the path's last part
			const LineIndex lines(text);
			const Value range = Object{ { "start", position_at(lines, at - segment.size(), request.encoding) },
				{ "end", position_at(lines, at, request.encoding) } };
			for (Value& item : items.array) {
				Object& object = *item.getAsObject();
				object["textEdit"] = Object{ { "range", range }, { "newText", *object.getString("label") } };
			}
			return std::move(items.array);
		}

		// Whether the cursor is in a string or a comment, where nothing's completed
		bool in_string_or_comment(const CompletionRequest& request) {
			if (request.parsed == nullptr || !request.parsed->lexed) {
				return false;
			}
			const auto inside = [&](const Token& token) {
				return token.offset != Token::NO_SPAN && token.offset < request.offset && request.offset < static_cast<size_t>(token.offset) + token.length;
			};
			for (const Token& comment : request.parsed->comments) {
				if (inside(comment) || (TokenType::COMMENT_LINE == comment.type && comment.offset < request.offset
					&& request.offset == static_cast<size_t>(comment.offset) + comment.length)) {
					return true;
				}
			}
			return std::any_of(request.parsed->tokens.begin(), request.parsed->tokens.end(),
				[&](const Token& token) { return TokenType::LITERAL_STRING == token.type && inside(token); });
		}


		// A name in a chain before a ., like a and b in a.b().c: where it starts now, and whether a call's () follows it
		struct Link {
			std::string name;
			size_t offset = 0;
			bool called = false;
		};

		// The chain before the . at dot, first name first; empty when what's before isn't names and calls
		std::vector<Link> chain_before(std::string_view text, size_t dot) {
			std::vector<Link> chain;
			size_t at = dot;
			for (;;) {
				bool called = false;
				if (at > 0 && text[at - 1] == ')') {
					// Back to its (, over what's between
					size_t depth = 0;
					size_t open = at - 1;
					for (;; --open) {
						depth += text[open] == ')' ? 1 : 0;
						depth -= text[open] == '(' ? 1 : 0;
						if (depth == 0 || open == 0) {
							break;
						}
					}
					if (depth != 0) {
						return {};
					}
					at = open;
					called = true;
				}
				size_t start = at;
				while (start > 0 && in_name(text[start - 1])) {
					--start;
				}
				if (start == at || std::isdigit(static_cast<unsigned char>(text[start])) != 0) {
					return {};
				}
				chain.insert(chain.begin(), Link{ std::string(text.substr(start, at - start)), start, called });
				if (start == 0 || text[start - 1] != '.') {
					return chain;
				}
				at = start - 1;
			}
		}

		// What a . can follow: a type's members, or a package's top-level declarations, by the folder's path_key
		struct Before {
			std::optional<size_t> type;
			std::string package;
		};

		// Where a declaration's members are: a type's own, or a value's type's
		Before members_after(const IndexedDeclaration& declaration, size_t number) {
			return Before{ declaration.kind == "type" ? std::optional<size_t>(number) : declaration.of, {} };
		}

		// The first link of a chain: what the index says is there, or, typed since the check, what a name like it is
		Before head_of(const CompletionRequest& request, CompletionTables& tables, const Link& head) {
			const LoadedIndex& index = tables.index();
			const std::string key = path_key(request.file);
			auto imports = index.imports.find(key);
			const Moved moved(request.checked_text, request.text);
			/*
			 * Where it was when checked, if it was: the same name there, as a change's ends are where the texts stop
			 * being the same, which can be inside a name like it
			 */
			std::optional<size_t> then = moved.back(head.offset);
			if (then.has_value() && (request.checked_text.substr(*then, head.name.size()) != head.name
				|| (*then + head.name.size() < request.checked_text.size() && in_name(request.checked_text[*then + head.name.size()])))) {
				then.reset();
			}
			if (then.has_value()) {
				if (imports != index.imports.end()) {
					for (const IndexedImport& import : imports->second) {
						if (import.offset == *then) {
							return Before{ std::nullopt, path_key(import.folder) };
						}
					}
				}
				if (const std::optional<LoadedIndex::NameAt> named = index.name_at(key, *then); named.has_value() && named->offset == *then) {
					return members_after(index.declarations[named->declaration], named->declaration);
				}
			}
			// By its name: an import, a local declared before it, or one of the package's
			if (imports != index.imports.end()) {
				for (const IndexedImport& import : imports->second) {
					if (request.checked_text.substr(import.offset, import.length) == head.name) {
						return Before{ std::nullopt, path_key(import.folder) };
					}
				}
			}
			for (const auto& [name, path] : written_imports(request)) {
				if (name == head.name) {
					return Before{ std::nullopt, import_folder(request, path) };
				}
			}
			std::optional<size_t> local;
			if (auto declared = index.declared.find(key); declared != index.declared.end()) {
				for (const size_t number : declared->second) {
					const IndexedDeclaration& declaration = index.declarations[number];
					if (!declaration.is_local()) {
						continue;
					}
					const std::optional<size_t> now = moved.forward(declaration.name_offset);
					if (now.has_value() && *now < head.offset && tables.name_of(number) == head.name) {
						local = number;
					}
				}
			}
			if (local.has_value()) {
				return members_after(index.declarations[*local], *local);
			}
			for (const size_t number : tables.top_level_in(path_key(folder_of(request.file)))) {
				if (tables.name_of(number) == head.name) {
					return members_after(index.declarations[number], number);
				}
			}
			return Before{};
		}

		Array member_items(const CompletionRequest& request, CompletionTables* tables, size_t dot) {
			const std::vector<Link> chain = chain_before(request.text, dot);
			if (chain.empty() || tables == nullptr) {
				return {};
			}
			Before before = head_of(request, *tables, chain[0]);
			for (size_t i = 1; i < chain.size(); ++i) {
				std::optional<size_t> next;
				const std::vector<size_t>& candidates = before.type.has_value() ? tables->members_of(*before.type)
					: !before.package.empty() ? tables->top_level_in(before.package) : std::vector<size_t>{};
				for (const size_t number : candidates) {
					if (tables->name_of(number) == chain[i].name) {
						next = number;
						break;
					}
				}
				if (!next.has_value()) {
					return {};
				}
				before = members_after(tables->index().declarations[*next], *next);
			}
			Items items;
			if (before.type.has_value()) {
				for (const size_t number : tables->members_of(*before.type)) {
					items.add(*tables, number, "0");
				}
			}
			else if (!before.package.empty()) {
				for (const size_t number : tables->top_level_in(before.package)) {
					items.add(*tables, number, "0");
				}
			}
			return std::move(items.array);
		}

		// The first byte of each of the file's top-level items, in order, from its recovered tree
		std::vector<size_t> top_level_starts(const CompletionRequest& request) {
			std::vector<size_t> starts;
			if (request.parsed == nullptr || request.parsed->recovered == nullptr) {
				return starts;
			}
			const auto first_byte = [](const ast::Node* node, const auto& self) -> size_t {
				size_t first = node->value.offset != Token::NO_SPAN ? node->value.offset : SIZE_MAX;
				for (const ast::Node* child : node->children) {
					first = std::min(first, self(child, self));
				}
				return first;
			};
			for (const ast::Node* child : request.parsed->recovered->children) {
				const size_t first = first_byte(child, first_byte);
				if (first != SIZE_MAX) {
					starts.push_back(first);
				}
			}
			std::sort(starts.begin(), starts.end());
			return starts;
		}

		Array scope_items(const CompletionRequest& request, CompletionTables* tables, size_t start) {
			Items items;
			// The top-level item the cursor is in, from its first byte to the next one's
			const std::vector<size_t> starts = top_level_starts(request);
			size_t from = 0;
			size_t to = 0;
			for (size_t i = 0; i < starts.size() && starts[i] <= start; ++i) {
				from = starts[i];
				to = i + 1 < starts.size() ? starts[i + 1] : request.text.size();
			}
			const bool in_declaration = to > from;
			// Locals the check found, declared before the cursor in the same declaration
			const std::string key = path_key(request.file);
			if (tables != nullptr && in_declaration) {
				const LoadedIndex& index = tables->index();
				const Moved moved(request.checked_text, request.text);
				if (auto declared = index.declared.find(key); declared != index.declared.end()) {
					for (auto number = declared->second.rbegin(); number != declared->second.rend(); ++number) {
						const IndexedDeclaration& declaration = index.declarations[*number];
						if (!declaration.is_local()) {
							continue;
						}
						const std::optional<size_t> now = moved.forward(declaration.name_offset);
						if (now.has_value() && *now >= from && *now < start) {
							items.add(*tables, *number, "0");
						}
					}
				}
			}
			// And those declared since: a name before a : in the declaration, before the cursor, like x := or a : int
			if (in_declaration && request.parsed != nullptr) {
				const MyVector<Token>& tokens = request.parsed->tokens;
				for (size_t i = 0; i + 1 < tokens.size(); ++i) {
					const Token& token = tokens[i];
					if (token.offset == Token::NO_SPAN || token.offset < from || token.offset >= start) {
						continue;
					}
					if (TokenType::IDENTIFIER == token.type && TokenType::SYM_COLON == tokens[i + 1].type && token.value != nullptr
						&& token.offset != from) {
						items.add(std::string(*token.value), item_kinds::VARIABLE, "0");
					}
				}
			}
			// The package's top-level declarations, the file's imports, then the builtin types and the keywords
			if (tables != nullptr) {
				for (const size_t number : tables->top_level_in(path_key(folder_of(request.file)))) {
					items.add(*tables, number, "1");
				}
				const LoadedIndex& index = tables->index();
				if (auto imports = index.imports.find(key); imports != index.imports.end()) {
					for (const IndexedImport& import : imports->second) {
						items.add(std::string(request.checked_text.substr(import.offset, import.length)), item_kinds::MODULE, "2",
							import.folder);
					}
				}
			}
			for (const auto& [name, path] : written_imports(request)) {
				items.add(name, item_kinds::MODULE, "2", path);
			}
			for (const std::string_view type : BUILTIN_TYPES) {
				items.add(std::string(type), item_kinds::STRUCT, "3");
			}
			for (const std::string_view keyword : KEYWORDS) {
				items.add(std::string(keyword), item_kinds::KEYWORD, "4");
			}
			return std::move(items.array);
		}
	}

	CompletionTables::CompletionTables(std::shared_ptr<const LoadedIndex> index, std::function<std::string(const std::string&)> text_of)
		: loaded(std::move(index)), read(std::move(text_of)) {
		for (size_t i = 0; i < loaded->declarations.size(); ++i) {
			const IndexedDeclaration& declaration = loaded->declarations[i];
			if (declaration.file.empty()) {
				continue;
			}
			if (declaration.in.has_value()) {
				members[*declaration.in].push_back(i);
			}
			else if (declaration.kind == "function" || declaration.kind == "type" || declaration.kind == "constant") {
				top_level[path_key(folder_of(declaration.file))].push_back(i);
			}
		}
		// In the order they're declared
		for (auto& [type, of_type] : members) {
			std::sort(of_type.begin(), of_type.end(), [&](size_t a, size_t b) {
				return loaded->declarations[a].name_offset < loaded->declarations[b].name_offset;
			});
		}
	}

	const std::vector<size_t>& CompletionTables::members_of(size_t type) const {
		auto found = members.find(type);
		return found != members.end() ? found->second : none;
	}

	const std::vector<size_t>& CompletionTables::top_level_in(const std::string& folder) const {
		auto found = top_level.find(folder);
		return found != top_level.end() ? found->second : none;
	}

	std::string_view CompletionTables::text_of(const std::string& file) {
		const std::string key = path_key(file);
		auto found = texts.find(key);
		if (found == texts.end()) {
			found = texts.emplace(key, read(file)).first;
		}
		return found->second;
	}

	std::string_view CompletionTables::name_of(size_t declaration) {
		const IndexedDeclaration& named = loaded->declarations[declaration];
		if (!named.text.empty()) {
			return named.text;
		}
		const std::string_view text = text_of(named.file);
		if (named.name_offset >= text.size()) {
			return {};
		}
		return text.substr(named.name_offset, named.name_length);
	}

	const std::vector<std::pair<size_t, std::string_view>>& CompletionTables::symbols() {
		if (!named_symbols.has_value()) {
			named_symbols.emplace();
			for (size_t number = 0; number < loaded->declarations.size(); ++number) {
				const IndexedDeclaration& declaration = loaded->declarations[number];
				if (declaration.file.empty() || declaration.is_local() || !declaration.text.empty()) {
					continue;
				}
				if (const std::string_view name = name_of(number); !name.empty()) {
					named_symbols->emplace_back(number, name);
				}
			}
		}
		return *named_symbols;
	}

	Array completion_items(const CompletionRequest& request, CompletionTables* tables) {
		if (std::optional<Array> imports = import_items(request)) {
			return std::move(*imports);
		}
		const size_t at = std::min(request.offset, request.text.size());
		if (in_string_or_comment(request)) {
			return {};
		}
		size_t start = at;
		while (start > 0 && in_name(request.text[start - 1])) {
			--start;
		}
		if (start > 0 && request.text[start - 1] == '.') {
			return member_items(request, tables, start - 1);
		}
		return scope_items(request, tables, start);
	}
}

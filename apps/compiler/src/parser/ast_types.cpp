#include "parser/ast_types.h"

#include <format>

namespace hemera::ast {

	Node::Node(NodeType node_type, Token value)
		: value{ value }
		, parent{ nullptr }
		, children{}
		, type { nullptr }
		, node_type{ node_type }
	{
	}
	Node::~Node() = default;

	std::string_view name_of(NodeType type) {
		if (NodeType::ANNOTATION == type) { return "ANNOTATION"; }
		if (NodeType::ARRAY_DIMENSION == type) { return "ARRAY_DIMENSION"; }
		if (NodeType::ARRAY_LITERAL == type) { return "ARRAY_LITERAL"; }
		if (NodeType::BINARY_OPERATOR == type) { return "BINARY_OPERATOR"; }
		if (NodeType::BLOCK == type) { return "BLOCK"; }
		if (NodeType::BREAK == type) { return "BREAK"; }
		if (NodeType::CAST == type) { return "CAST"; }
		if (NodeType::COLON == type) { return "COLON"; }
		if (NodeType::CONTINUE == type) { return "CONTINUE"; }
		if (NodeType::DEFER == type) { return "DEFER"; }
		if (NodeType::DEFINITION == type) { return "DEFINITION"; }
		if (NodeType::DIRECTIVE == type) { return "DIRECTIVE"; }
		if (NodeType::DERIVED_PARAMETER == type) { return "DERIVED_PARAMETER"; }
		if (NodeType::DOT_ACCESS == type) { return "DOT_ACCESS"; }
		if (NodeType::ELLIIPSIS == type) { return "ELLIIPSIS"; }
		if (NodeType::ELSE == type) { return "ELSE"; }
		if (NodeType::ENUM == type) { return "ENUM"; }
		if (NodeType::ENUM_SHORTHAND == type) { return "ENUM_SHORTHAND"; }
		if (NodeType::FILE == type) { return "FILE"; }
		if (NodeType::FOR_LOOP == type) { return "FOR_LOOP"; }
		if (NodeType::FUNCTION == type) { return "FUNCTION"; }
		if (NodeType::GENERIC_TAG == type) { return "GENERIC_TAG"; }
		if (NodeType::IDENTIFIER == type) { return "IDENTIFIER"; }
		if (NodeType::IF == type) { return "IF"; }
		if (NodeType::IN == type) { return "IN"; }
		if (NodeType::IMPORT == type) { return "IMPORT"; }
		if (NodeType::KEYWORD_ALIAS == type) { return "KEYWORD_ALIAS"; }
		if (NodeType::KEYWORD_ALL == type) { return "KEYWORD_ALL"; }
		if (NodeType::KEYWORD_AS == type) { return "KEYWORD_AS"; }
		if (NodeType::KEYWORD_DISTINCT == type) { return "KEYWORD_DISTINCT"; }
		if (NodeType::KEYWORD_FROM == type) { return "KEYWORD_FROM"; }
		if (NodeType::KEYWORD_IS_NONE == type) { return "KEYWORD_IS_NONE"; }
		if (NodeType::KEYWORD_IS_SOME == type) { return "KEYWORD_IS_SOME"; }
		if (NodeType::KEYWORD_OR_BREAK == type) { return "KEYWORD_OR_BREAK"; }
		if (NodeType::KEYWORD_OR_CONTINUE == type) { return "KEYWORD_OR_CONTINUE"; }
		if (NodeType::KEYWORD_OR_ELSE == type) { return "KEYWORD_OR_ELSE"; }
		if (NodeType::KEYWORD_OR_RETURN == type) { return "KEYWORD_OR_RETURN"; }
		if (NodeType::LIST == type) { return "LIST"; }
		if (NodeType::LITERAL == type) { return "LITERAL"; }
		if (NodeType::LOOP == type) { return "LOOP"; }
		if (NodeType::MATCH == type) { return "MATCH"; }
		if (NodeType::MATCH_CASE == type) { return "MATCH_CASE"; }
		if (NodeType::MUTABLE == type) { return "MUTABLE"; }
		if (NodeType::PACKAGE == type) { return "PACKAGE"; }
		if (NodeType::PAREN_GROUP == type) { return "PAREN_GROUP"; }
		if (NodeType::PIPE_REORDER_IDENTIFIER == type) { return "PIPE_REORDER_IDENTIFIER"; }
		if (NodeType::PUSH_CONTEXT == type) { return "PUSH_CONTEXT"; }
		if (NodeType::RANGE_ARRAY == type) { return "RANGE_ARRAY"; }
		if (NodeType::RETURN == type) { return "RETURN"; }
		if (NodeType::STRUCT == type) { return "STRUCT"; }
		if (NodeType::STRUCT_LITERAL == type) { return "STRUCT_LITERAL"; }
		if (NodeType::SWITCH == type) { return "SWITCH"; }
		if (NodeType::SWITCH_CASE == type) { return "SWITCH_CASE"; }
		if (NodeType::SWITCH_ENTRY == type) { return "SWITCH_ENTRY"; }
		if (NodeType::TYPE == type) { return "TYPE"; }
		if (NodeType::UNARY_OPERATOR == type) { return "UNARY_OPERATOR"; }
		if (NodeType::UNDERSCORE == type) { return "UNDERSCORE"; }
		if (NodeType::UNINITIALIZED == type) { return "UNINITIALIZED"; }
		if (NodeType::UNION == type) { return "UNION"; }
		if (NodeType::USING == type) { return "USING"; }
		if (NodeType::VOID == type) { return "VOID"; }
		if (NodeType::WHERE_CLAUSE == type) { return "WHERE_CLAUSE"; }
		if (NodeType::WHILE_CLAUSE == type) { return "WHILE_CLAUSE"; }
		if (NodeType::WITH_CLAUSE == type) { return "WITH_CLAUSE"; }
		return "?";
	}

	static void dump(const Node* node, size_t depth, std::string& out) {
		out.append(depth * 2, ' ');
		out += name_of(node->node_type);
		if (node->value.value != nullptr) {
			out += std::format(" '{}'", std::string_view(*node->value.value));
		}
		out += std::format(" [{}]\n", static_cast<int>(node->value.type));
		for (const Node* child : node->children) {
			dump(child, depth + 1, out);
		}
	}

	/*
	 * A quoted string's text, with its escapes, or a multiline string's lines (docs/types.md, Strings):
	 * each line's text after its \\, as it is, joined by newlines, with no newline after the last.
	 */
	std::string string_value(const Node* literal) {
		const std::string_view first = literal->value.value != nullptr ? std::string_view(*literal->value.value) : std::string_view();
		if (first.starts_with("\\\\")) {
			std::string result;
			auto add_line = [&](std::string_view line) {
				line.remove_prefix(2);
				while (!line.empty() && (line.back() == '\n' || line.back() == '\r')) {
					line.remove_suffix(1);
				}
				result += line;
			};
			add_line(first);
			for (const Node* line : literal->children) {
				result += '\n';
				add_line(line->value.value != nullptr ? std::string_view(*line->value.value) : std::string_view("\\\\"));
			}
			return result;
		}
		std::string_view text = first;
		if (text.size() >= 2 && text.front() == '"') {
			text = text.substr(1, text.size() - 2);
		}
		std::string result;
		for (size_t i = 0; i < text.size(); ++i) {
			if (text[i] != '\\' || i + 1 >= text.size()) {
				result += text[i];
				continue;
			}
			const char escaped = text[++i];
			result += escaped == 'n' ? '\n' : escaped == 't' ? '\t' : escaped == 'r' ? '\r' : escaped == '0' ? '\0' : escaped;
		}
		return result;
	}

	std::string dump(const Node* node) {
		std::string out;
		dump(node, 0, out);
		return out;
	}

	void QuoteTable::set(const Node* quote, const Node* tree, std::string_view file, bool from_caller) {
		std::scoped_lock<std::mutex> lock(mutex);
		trees[quote] = Quoted{ tree, std::string(file), from_caller };
	}

	bool QuoteTable::from_caller(const Node* quote) const {
		std::scoped_lock<std::mutex> lock(mutex);
		auto iter = trees.find(quote);
		return iter != trees.end() && iter->second.from_caller;
	}

	const Node* QuoteTable::get(const Node* quote) const {
		std::scoped_lock<std::mutex> lock(mutex);
		auto iter = trees.find(quote);
		return iter != trees.end() ? iter->second.tree : nullptr;
	}

	std::string QuoteTable::file_of(const Node* quote) const {
		std::scoped_lock<std::mutex> lock(mutex);
		auto iter = trees.find(quote);
		return iter != trees.end() ? iter->second.file : std::string();
	}

	Node* NodeStore::make(NodeType type, Token value) {
		nodes.push_back(std::make_unique<Node>(type, value));
		return nodes.back().get();
	}

	std::unique_lock<std::mutex> NodeStore::hold() {
		return std::unique_lock<std::mutex>(mutex);
	}

	void NodeStore::set_origin(const Node* node, std::shared_ptr<const Origin> origin) {
		std::scoped_lock<std::mutex> lock(origins_mutex);
		origins[node] = std::move(origin);
	}

	std::shared_ptr<const Origin> NodeStore::origin(const Node* node) const {
		std::scoped_lock<std::mutex> lock(origins_mutex);
		auto iter = origins.find(node);
		return iter != origins.end() ? iter->second : nullptr;
	}

	uint32_t NodeStore::mark_of(const Node* node) const {
		std::scoped_lock<std::mutex> lock(origins_mutex);
		if (origins.empty()) {
			return 0;
		}
		auto iter = origins.find(node);
		return iter != origins.end() && iter->second != nullptr ? iter->second->mark : 0;
	}

	uint32_t NodeStore::new_mark() {
		return marks.fetch_add(1) + 1;
	}

}

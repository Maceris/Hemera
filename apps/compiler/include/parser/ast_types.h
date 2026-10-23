#pragma once

#include <memory>
#include <mutex>
#include <memory>
#include <mutex>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>
#include <unordered_map>
#include <vector>

#include <cstdint>

#include "front_end/type.h"
#include "lexer/token.h"
#include "memory/allocator.h"

namespace hemera::ast {
	enum class NodeType {
		ANNOTATION,
		ARRAY_DIMENSION,
		ARRAY_LITERAL,
		BINARY_OPERATOR,
		BLOCK,
		BREAK,
		CAST,
		COLON,
		CONTINUE,
		DEFER,
		DEFINITION,
		// A generic parameter the generic works out from the others, like E = element_of(C): the
		// name is its token, and its child the expression (docs/types.md, Derived Parameters)
		DERIVED_PARAMETER,
		DIRECTIVE,
		DOT_ACCESS,
		ELLIIPSIS,
		ELSE,
		ENUM,
		ENUM_SHORTHAND,
		FILE,
		FOR_LOOP,
		FUNCTION,
		GENERIC_TAG,
		IDENTIFIER,
		IF,
		IN,
		IMPORT,
		KEYWORD_ALIAS,
		KEYWORD_ALL,
		KEYWORD_AS,
		KEYWORD_DISTINCT,
		KEYWORD_FROM,
		KEYWORD_IS_NONE,
		KEYWORD_IS_SOME,
		KEYWORD_OR_BREAK,
		KEYWORD_OR_CONTINUE,
		KEYWORD_OR_ELSE,
		KEYWORD_OR_RETURN,
		LIST,
		LITERAL,
		LOOP,
		MATCH,
		MATCH_CASE,
		MUTABLE,
		PACKAGE,
		PAREN_GROUP,
		PIPE_REORDER_IDENTIFIER,
		PUSH_CONTEXT,
		RANGE_ARRAY,
		RETURN,
		STRUCT,
		STRUCT_LITERAL,
		SWITCH,
		SWITCH_CASE,
		SWITCH_ENTRY,
		TYPE,
		UNARY_OPERATOR,
		UNDERSCORE,
		UNINITIALIZED,
		UNION,
		USING,
		VOID,
		// A generic's where clause: its constraint expression (docs/types.md, Constraints)
		WHERE_CLAUSE,
		WHILE_CLAUSE,
		WITH_CLAUSE,
	};

	using offset = int64_t;

	struct Node {
		Token value;
		Node* parent;
		MyVector<Node*> children;
		TypeInfo* type;
		NodeType node_type;
		const char padding[4] = { 0 };

		Node(NodeType type, Token value);
		Node(const Node&) = delete;
		Node(Node&&) = delete;
		Node& operator=(const Node&) = delete;
		Node& operator=(Node&&) = delete;
		~Node();
	};

	std::string_view name_of(NodeType type);

	/// <summary>
	/// The tree under node, one node to a line, for debugging and tests.
	/// </summary>
	std::string dump(const Node* node);

	/// <summary>
	/// The trees #code quotes, by their #code nodes: kept apart from the #code node, whose children are only
	/// the expressions spliced into it, so passes over a body see the quote as those expressions and never
	/// its tree (docs/compilation.md, Code Values). Each #insert in a tree is left with no children; they're
	/// filled in, in order, when the quote is evaluated. A program has one, which lasts as long as its trees.
	/// </summary>
	class QuoteTable {
	public:
		void set(const Node* quote, const Node* tree);
		/// <summary>
		/// The tree a #code node quotes, or null.
		/// </summary>
		const Node* get(const Node* quote) const;

	private:
		mutable std::mutex mutex;
		std::unordered_map<const Node*, const Node*> trees;
	};

	/// <summary>
	/// Nodes made while compiling rather than parsed, like the copies compile-time code's quotes make. A
	/// program has one, which frees them with it.
	/// </summary>
	class NodeStore {
	public:
		/// <summary>
		/// A new node, which lasts as long as the store. Called with hold's lock held.
		/// </summary>
		Node* make(NodeType type, Token value);

		/// <summary>
		/// The store's lock, held while making nodes.
		/// </summary>
		std::unique_lock<std::mutex> hold();

	private:
		std::mutex mutex;
		std::vector<std::unique_ptr<Node>> nodes;
	};

}

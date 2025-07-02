#pragma once

#include <cstdint>

#include "lexer/token.h"
#include "memory/allocator.h"

namespace hemera::ast {
	enum class NodeType {
		ARRAY_DIMENSION,
		BINARY_OPERATOR,
		BLOCK,
		BREAK,
		CAST,
		CONTINUE,
		DEFER,
		DEFINITION,
		DIRECTIVE,
		DOT_ACCESS,
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
		KEYWORD_ALL,
		LEAF,
		LIST,
		LITERAL,
		LOOP,
		MATCH,
		MATCH_CASE,
		MUTABLE,
		PACKAGE,
		PAREN_GROUP,
		PUSH_CONTEXT,
		RETURN,
		STRUCT,
		STRUCT_LITERAL,
		SWITCH,
		SWITCH_CASE,
		SWITCH_ENTRY,
		TYPE,
		UNARY_OPERATOR,
		UNDERSCORE,
		UNION,
		USING,
		WHILE_CLAUSE,
		WITH_CLAUSE,
	};

	using offset = int64_t;

	struct Node {
		Token value;
		Node* parent;
		MyVector<Node*> children;
		NodeType type;
		const char padding[4] = { 0 };

		Node(NodeType type, Token value);
		Node(const Node&) = delete;
		Node(Node&&) = delete;
		Node& operator=(const Node&) = delete;
		Node& operator=(Node&&) = delete;
		~Node();
	};

	struct FlatNode {
		Token value;
		offset parent;
		offset total_children;
		NodeType type;
		const char padding[4] = { 0 };
		FlatNode(NodeType type, Token value);
		FlatNode(const FlatNode&);
		FlatNode(FlatNode&&);
		FlatNode& operator=(const FlatNode&) = delete;
		FlatNode& operator=(FlatNode&&) = delete;
		~FlatNode();
	};
}
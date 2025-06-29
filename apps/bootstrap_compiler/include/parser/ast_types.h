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
		ELSE,
		ENUM,
		FILE,
		FUNCTION,
		GENERIC_TAG,
		IDENTIFIER,
		IF,
		IMPORT,
		KEYWORD_ALL,
		LEAF,
		LIST,
		LITERAL,
		PACKAGE,
		PAREN_GROUP,
		RETURN,
		STRUCT,
		TYPE,
		UNARY_OPERATOR,
		UNION,
		USING,
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
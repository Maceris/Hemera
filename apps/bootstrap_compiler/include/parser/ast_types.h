#pragma once

#include <cstdint>

#include "front_end/type.h"
#include "lexer/token.h"
#include "memory/allocator.h"

namespace hemera::ast {
	enum class NodeType {
		ARRAY_DIMENSION,
		BINARY_OPERATOR,
		BLOCK,
		BREAK,
		CAST,
		COLON,
		CONTINUE,
		DEFER,
		DEFINITION,
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
		UNION,
		USING,
		VOID,
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

}
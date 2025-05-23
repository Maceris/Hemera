#pragma once

#include <cstdint>

#include "lexer/token.h"
#include "memory/allocator.h"

namespace hemera::ast {
	enum class NodeType {
		DEFINITION,
		FILE,
		FUNCTION,
		GENERIC_TAG,
		IMPORT,
		LEAF,
		LIST,
		PACKAGE,
		TYPE,
	};

	using offset = int64_t;

	struct Node {
		Token value;
		offset parent;
		offset total_children;
		NodeType type;
		const char padding[4] = { 0 };
		Node(NodeType type, Token value);
		Node(const Node&);
		Node(Node&&);
		Node& operator=(const Node&) = delete;
		Node& operator=(Node&&) = delete;
		~Node();
	};
}
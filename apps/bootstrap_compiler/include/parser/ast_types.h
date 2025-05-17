#pragma once

#include <cstdint>

#include "lexer/token.h"
#include "memory/allocator.h"

namespace hemera::ast {
	enum class NodeType {
		DEFINITION,
		FILE,
		IMPORT,
		LEAF,
		PACKAGE,
	};

	using offset = int64_t;

	struct Node {
		MyVector<offset> children;
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
#include "parser/ast_types.h"

namespace hemera::ast {
	Node::Node(NodeType type, Token value)
		: children{}
		, value{ value }
		, parent{ 0 }
		, total_children{ 0 }
		, type{ type }
	{}
	Node::Node(const Node&) = default;
	Node::Node(Node&&) = default;
	Node::~Node() = default;
}
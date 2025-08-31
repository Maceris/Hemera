#include "parser/ast_types.h"

namespace hemera::ast {

	Node::Node(NodeType type, Token value)
		: value{ value }
		, parent{ nullptr }
		, children{}
		, type{ type }
	{
	}
	Node::~Node() = default;

}
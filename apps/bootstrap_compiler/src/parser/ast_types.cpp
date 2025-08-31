#include "parser/ast_types.h"

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

}
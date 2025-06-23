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

	FlatNode::FlatNode(NodeType type, Token value)
		: value{ value }
		, parent{ 0 }
		, total_children{ 0 }
		, type{ type }
	{}
	FlatNode::FlatNode(const FlatNode&) = default;
	FlatNode::FlatNode(FlatNode&&) = default;
	FlatNode::~FlatNode() = default;
}
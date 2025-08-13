#include <format>
#include <type_traits>
#include <utility>

#include "front_end/hlir.h"
#include "util/logger.h"

namespace hemera::hlir {

	BasicBlock::BasicBlock(Allocator<>& allocator)
		: allocator{ allocator }
		, instructions{ allocator }
	{}

	BasicBlock::~BasicBlock() = default;

	Function::Function(Allocator<>& allocator)
		: allocator{ allocator }
		, basic_blocks{ allocator }
	{}

	Function::~Function() = default;

}
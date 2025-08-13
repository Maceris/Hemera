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

	BasicBlock* Function::create_basic_block() {
		BasicBlock* result = allocator.allocate_object<BasicBlock>();
		allocator.construct<BasicBlock>(result, allocator);
		basic_blocks.emplace_back(result);
		return result;
	}

}
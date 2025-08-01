#include <format>

#include "gtest/gtest.h"

#include "front_end/hlir.h"

using hemera::hlir::Instruction;
using hemera::hlir::InstructionMnemonic;
using hemera::hlir::InstrSpec;

TEST(HLIRTests, AllInstructionsHaveSpecs)
{
	using BaseType = std::underlying_type_t<InstructionMnemonic>;
	const BaseType end = static_cast<BaseType>(InstructionMnemonic::_COUNT);
	for (BaseType v = 0; v < end; ++v) {
		InstructionMnemonic type = static_cast<InstructionMnemonic>(v);
		ASSERT_TRUE(hemera::hlir::instructions.contains(type))
			<< std::format("HLIR_Instructions does not contain instruction with index {}", v);
	}
}

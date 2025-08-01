#include <format>

#include "gtest/gtest.h"

#include "front_end/hlir.h"

using hemera::HLInstruction;
using hemera::HLInstrType;
using hemera::HLInstrSpec;

TEST(HLIRTests, AllInstructionsHaveSpecs)
{
	using BaseType = std::underlying_type_t<HLInstrType>;
	const BaseType end = static_cast<BaseType>(HLInstrType::_COUNT);
	for (BaseType v = 0; v < end; ++v) {
		HLInstrType type = static_cast<HLInstrType>(v);
		ASSERT_TRUE(hemera::HLIR_instructions.contains(type));
	}
}

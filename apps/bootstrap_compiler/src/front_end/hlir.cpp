#include <format>
#include <type_traits>
#include <utility>

#include "front_end/hlir.h"
#include "util/logger.h"

namespace hemera {

	HLInstrSpec::HLInstrSpec(HLInstrType type, const char* name, int source_count,
		bool has_target)
		: type{ type }
		, name{ name }
		, source_count{ source_count }
		, has_target{ has_target }
	{}

	HLInstrSpec::~HLInstrSpec() = default;
	HLInstrSpec::HLInstrSpec(const HLInstrSpec&) = default;
	HLInstrSpec::HLInstrSpec(HLInstrSpec&&) = default;

#ifdef HLIR_INSTR
	static_assert(false && "We are breaking some macro by defining HLIR_INSTR");
#endif
#define HLIR_INSTR(type, source_count, has_target) {HLInstrType::type, HLInstrSpec{HLInstrType::type, #type, source_count, has_target}}

	std::map<HLInstrType, HLInstrSpec> HLIR_instructions = {
		HLIR_INSTR(ADD, 2, true),
		HLIR_INSTR(AND, 2, true),
		HLIR_INSTR(DIV, 2, true),
		HLIR_INSTR(EQ, 2, true),
		HLIR_INSTR(GT, 2, true),
		HLIR_INSTR(JEQ, 2, false),
		HLIR_INSTR(JMP, 1, false),
		HLIR_INSTR(JNE, 2, false),
		HLIR_INSTR(LT, 2, false),
		HLIR_INSTR(MOD, 2, true),
		HLIR_INSTR(MOV, 1, true),
		HLIR_INSTR(MUL, 2, true),
		HLIR_INSTR(NE, 2, true),
		HLIR_INSTR(REMAINDER, 2, true),
		HLIR_INSTR(SUB, 2, true),
	};
#undef HLIR_INSTR

}
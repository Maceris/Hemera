#include <format>
#include <type_traits>
#include <utility>

#include "front_end/hlir.h"
#include "util/logger.h"

namespace hemera::hlir {

	InstrSpec::InstrSpec(InstructionMnemonic type, const char* name, int source_count,
		bool has_target)
		: type{ type }
		, name{ name }
		, source_count{ source_count }
		, has_target{ has_target }
	{}

	InstrSpec::~InstrSpec() = default;
	InstrSpec::InstrSpec(const InstrSpec&) = default;
	InstrSpec::InstrSpec(InstrSpec&&) = default;

#ifdef HLIR_INSTR
	static_assert(false && "We are breaking some macro by defining HLIR_INSTR");
#endif
#define HLIR_INSTR(type, source_count, has_target) {InstructionMnemonic::type, InstrSpec{InstructionMnemonic::type, #type, source_count, has_target}}

	std::map<InstructionMnemonic, InstrSpec> instructions = {
		HLIR_INSTR(ADD, 2, true),
		HLIR_INSTR(AND, 2, true),
		HLIR_INSTR(ANDL, 2, true),
		HLIR_INSTR(CALL, 1, false),
		HLIR_INSTR(DIV, 2, true),
		HLIR_INSTR(EQ, 2, true),
		HLIR_INSTR(GT, 2, true),
		HLIR_INSTR(GTE, 2, true),
		HLIR_INSTR(JEQ, 2, false),
		HLIR_INSTR(JMP, 1, false),
		HLIR_INSTR(JNE, 2, false),
		HLIR_INSTR(LT, 2, false),
		HLIR_INSTR(LTE, 2, false),
		HLIR_INSTR(MOD, 2, true),
		HLIR_INSTR(MOV, 1, true),
		HLIR_INSTR(MUL, 2, true),
		HLIR_INSTR(NE, 2, true),
		HLIR_INSTR(NEG, 1, true),
		HLIR_INSTR(NOT, 1, true),
		HLIR_INSTR(OR, 2, true),
		HLIR_INSTR(ORL, 2, true),
		HLIR_INSTR(REMAINDER, 2, true),
		HLIR_INSTR(RET, 1, false),
		HLIR_INSTR(SAR, 2, true),
		HLIR_INSTR(SHL, 2, true),
		HLIR_INSTR(SHR, 2, true),
		HLIR_INSTR(SUB, 2, true),
		HLIR_INSTR(XOR, 2, true),
	};
#undef HLIR_INSTR

}
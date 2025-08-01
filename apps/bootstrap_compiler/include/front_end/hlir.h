#pragma once

#include <cstdint>
#include <map>

#include "type_id.h"

namespace hemera {
	
	enum class HLInstrType : uint64_t {
		ADD,
		AND,
		/// <summary>
		/// Logical AND, only for boolean values.
		/// </summary>
		ANDL,
		DIV,
		EQ,
		GT,
		GTE,
		JEQ,
		JMP,
		JNE,
		LT,
		LTE,
		MOD,
		MOV,
		MUL,
		NE,
		/// <summary>
		/// Negate, replacing a value iwth it's two's complement.
		/// </summary>
		NEG,
		NOT,
		OR,
		/// <summary>
		/// Logical OR, only for boolean values.
		/// </summary>
		ORL,
		REMAINDER,
		/// <summary>
		/// Shift right (arithmetic).
		/// </summary>
		SAR,
		/// <summary>
		/// Shift left.
		/// </summary>
		SHL,
		/// <summary>
		/// Shift right (logical).
		/// </summary>
		SHR,
		SUB,
		XOR,
		/// <summary>
		/// Not used, only for iterating.
		/// </summary>
		_COUNT,
	};
	
	struct HLInstruction {
		HLInstrType type;
		ValueID target;
		ValueID source1;
		ValueID source2;
	};

	struct HLInstrSpec {
		const HLInstrType type;
		const char* name;
		const int source_count;
		const bool has_target;
		const char _padding[3] = { 0 };

		HLInstrSpec(HLInstrType type, const char* name, int source_count,
			bool has_target);
		~HLInstrSpec();
		HLInstrSpec(const HLInstrSpec&);
		HLInstrSpec(HLInstrSpec&&);
		HLInstrSpec& operator=(const HLInstrSpec&) = delete;
		HLInstrSpec& operator=(HLInstrSpec&&) = delete;
	};

	extern std::map<HLInstrType, HLInstrSpec> HLIR_instructions;

}
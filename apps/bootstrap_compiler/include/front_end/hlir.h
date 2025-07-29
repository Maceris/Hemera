#pragma once

#include <map>

#include "type_id.h"

namespace hemera {
	
	enum class HLInstrType {

	};
	
	struct HLInstruction {
		HLInstrType type;
		ValueID target;
		ValueID source1;
		ValueID source2;
	};

	struct HLInstrSpec {
		HLInstrType type;
		char* name;
		bool has_target;
		int source_count;
	};

	extern std::map<HLInstrType, HLInstrSpec> instructions;
}
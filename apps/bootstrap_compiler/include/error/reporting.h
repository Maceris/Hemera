#pragma once

#include <cstdint>
#include <string_view>

#include "error/error.h"
#include "error/warning.h"

namespace hemera {
	void report_error(ErrorCode error, std::string_view file,
		uint32_t line_number, uint16_t column_number);

	void report_warning(WarningCode warning, std::string_view file,
		uint32_t line_number, uint16_t column_number);
}
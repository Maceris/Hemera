#pragma once

#include <cstdint>
#include <string_view>

#include "errors.h"
#include "warnings.h"

namespace hemera {

	/// <summary>
	/// Used for testing, turns off error reporting globally.
	/// </summary>
	void disable_reporting();

	/// <summary>
	/// Enables error reporting globally, which is on by default.
	/// </summary>
	void enable_reporting();

	/// <summary>
	/// When constructed, turns off error reporting globally. Re-enables
	/// reporting globally when destructed.
	/// </summary>
	struct DisableReportingForBlock {
		DisableReportingForBlock();

		DisableReportingForBlock(const DisableReportingForBlock&) = delete;
		DisableReportingForBlock(DisableReportingForBlock&&) = delete;
		DisableReportingForBlock& operator=(const DisableReportingForBlock&) = delete;
		DisableReportingForBlock& operator=(DisableReportingForBlock&&) = delete;

		~DisableReportingForBlock();
	};

	void report_error(ErrorCode error, std::string_view file,
		uint32_t line_number, uint16_t column_number);

	void report_warning(WarningCode warning, std::string_view file,
		uint32_t line_number, uint16_t column_number);
}
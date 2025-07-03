#include <atomic>
#include <format>
#include <iostream>
#include <mutex>
#include <string>

#include "error/reporting.h"

namespace hemera {

	static std::mutex cout_mutex;
	static bool reporting_enabled = true;
	static std::atomic_uint32_t total_error_count = { 0 };
	static std::atomic_uint32_t total_warning_count = { 0 };

	DisableReportingForBlock::DisableReportingForBlock() {
		disable_reporting();
	}

	DisableReportingForBlock::~DisableReportingForBlock() {
		enable_reporting();
	}

	void disable_reporting() {
		reporting_enabled = false;
	}

	void enable_reporting() {
		reporting_enabled = true;
	}

	void reset_reporting_counts() {
		total_error_count = 0;
		total_warning_count = 0;
	}

	void report_error(ErrorCode error, std::string_view file,
		uint32_t line_number, uint16_t column_number) {

		if (!reporting_enabled) {
			return;
		}

		++total_error_count;

		auto it = ErrorInfoMap.find(error);

		ErrorInfo info = (it != ErrorInfoMap.end())
			? info = it->second 
			: ErrorInfo("E0000", "Unknown error");
		
		std::string result = std::format("{}({},{}): {} {}: {}", file, 
			line_number, column_number, "error", info.string_value,
			info.message);

		std::lock_guard<std::mutex> lock(cout_mutex);
		std::cout << result << std::endl;
	}

	void report_warning(WarningCode warning, std::string_view file,
		uint32_t line_number, uint16_t column_number) {

		if (!reporting_enabled) {
			return;
		}

		++total_warning_count;

		auto it = WarningInfoMap.find(warning);

		WarningInfo info = (it != WarningInfoMap.end())
			? info = it->second
			: WarningInfo("W0000", "Unknown warning");

		std::string result = std::format("{}({},{}): {} {}: {}", file,
			line_number, column_number, "warning", info.string_value, 
			info.message);

		std::lock_guard<std::mutex> lock(cout_mutex);
		std::cout << result << std::endl;
	}

	uint32_t error_count() {
		return total_error_count;
	}

	uint32_t warning_count() {
		return total_warning_count;
	}
}
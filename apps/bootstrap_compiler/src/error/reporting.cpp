
#include <format>
#include <iostream>
#include <mutex>
#include <string>

#include "error/reporting.h"

namespace hemera {

	static std::mutex cout_mutex;

	void report_error(ErrorCode error, std::string_view file,
		uint32_t line_number, uint16_t column_number) {

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
}
#include <atomic>
#include <format>
#include <iostream>
#include <mutex>
#include <string>

#include "error/reporting.h"

namespace hemera {

	static std::mutex cout_mutex;
	static std::mutex storage_mutex;
	static bool reporting_enabled = true;
	static bool printing_enabled = true;
	static std::vector<ErrorCode> error_list_storage{};
	static std::vector<WarningCode> warning_list_storage{};

	DisableReportingForBlock::DisableReportingForBlock() {
		disable_reporting();
	}

	DisableReportingForBlock::~DisableReportingForBlock() {
		enable_reporting();
	}

	void disable_reporting() {
		std::lock_guard<std::mutex> lock(cout_mutex);
		reporting_enabled = false;
	}

	void disable_reporting_printing() {
		std::lock_guard<std::mutex> lock(cout_mutex);
		printing_enabled = false;
	}

	void enable_reporting() {
		std::lock_guard<std::mutex> lock(cout_mutex);
		reporting_enabled = true;
	}

	void enable_reporting_printing() {
		std::lock_guard<std::mutex> lock(cout_mutex);
		printing_enabled = true;
	}

	void reset_reporting_storage() {
		std::lock_guard<std::mutex> lock(cout_mutex);

		error_list_storage.clear();
		warning_list_storage.clear();
	}

	void report_error(ErrorCode error, std::string_view file,
		uint32_t line_number, uint16_t column_number) {

		if (!reporting_enabled) {
			return;
		}

		{
			std::lock_guard<std::mutex> lock(storage_mutex);
			error_list_storage.push_back(error);
		}

		auto it = ErrorInfoMap.find(error);

		ErrorInfo info = (it != ErrorInfoMap.end())
			? info = it->second 
			: ErrorInfo("E0000", "Unknown error");
		
		std::string result = std::format("{}({},{}): {} {}: {}", file, 
			line_number, column_number, "error", info.string_value,
			info.message);

		std::lock_guard<std::mutex> lock(cout_mutex);

		if (!printing_enabled) {
			return;
		}

		std::cout << result << std::endl;
	}

	void report_warning(WarningCode warning, std::string_view file,
		uint32_t line_number, uint16_t column_number) {

		if (!reporting_enabled) {
			return;
		}

		{
			std::lock_guard<std::mutex> lock(storage_mutex);
			warning_list_storage.push_back(warning);
		}

		auto it = WarningInfoMap.find(warning);

		WarningInfo info = (it != WarningInfoMap.end())
			? info = it->second
			: WarningInfo("W0000", "Unknown warning");

		std::string result = std::format("{}({},{}): {} {}: {}", file,
			line_number, column_number, "warning", info.string_value, 
			info.message);

		std::lock_guard<std::mutex> lock(cout_mutex);

		if (!printing_enabled) {
			return;
		}

		std::cout << result << std::endl;
	}

	size_t error_count() {
		std::lock_guard<std::mutex> lock(storage_mutex);
		return error_list_storage.size();
	}
	
	std::vector<ErrorCode> error_list() {
		std::lock_guard<std::mutex> lock(storage_mutex);
		return error_list_storage;
	}

	size_t warning_count() {
		std::lock_guard<std::mutex> lock(storage_mutex);
		return warning_list_storage.size();
	}

	std::vector<WarningCode> warning_list() {
		std::lock_guard<std::mutex> lock(storage_mutex);
		return warning_list_storage;
	}

}
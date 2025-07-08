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

	static void log_error(ErrorCode error) {
		std::lock_guard<std::mutex> lock(storage_mutex);
		error_list_storage.push_back(error);
	}

	static void print_error(ErrorCode error, std::string_view file,
		uint32_t line_number, uint16_t column_number,
		std::string_view additional_info) {

		auto it = ErrorInfoMap.find(error);

		ErrorInfo info = (it != ErrorInfoMap.end())
			? info = it->second
			: ErrorInfo("E0000", "Unknown error");

		std::string extension = "";

		if (!additional_info.empty()) {
			extension = std::format(". {}", additional_info);
		}

		std::string result = std::format("{}({},{}): {} {}: {}{}", file,
			line_number, column_number, "error", info.string_value,
			info.message, extension);

		std::cout << result << std::endl;
	}

	void report_error(ErrorCode error, std::string_view file,
		uint32_t line_number, uint16_t column_number) {

		if (!reporting_enabled) {
			return;
		}
		
		log_error(error);

		std::lock_guard<std::mutex> lock(cout_mutex);

		if (printing_enabled) {
			print_error(error, file, line_number, column_number, "");
		}
	}

	void report_error(ErrorCode error, std::string_view file,
		uint32_t line_number, uint16_t column_number,
		std::string_view additional_info) {

		if (!reporting_enabled) {
			return;
		}

		log_error(error);

		std::lock_guard<std::mutex> lock(cout_mutex);

		if (printing_enabled) {
			print_error(error, file, line_number, column_number,
				additional_info);
		}
	}

	static void log_warning(WarningCode warning) {
		std::lock_guard<std::mutex> lock(storage_mutex);
		warning_list_storage.push_back(warning);
	}

	static void print_warning(WarningCode warning, std::string_view file,
		uint32_t line_number, uint16_t column_number,
		std::string_view additional_info) {

		auto it = WarningInfoMap.find(warning);

		WarningInfo info = (it != WarningInfoMap.end())
			? info = it->second
			: WarningInfo("W0000", "Unknown warning");

		std::string extension = "";

		if (!additional_info.empty()) {
			extension = std::format(". {}", additional_info);
		}

		std::string result = std::format("{}({},{}): {} {}: {}{}", file,
			line_number, column_number, "warning", info.string_value,
			info.message, extension);

		std::cout << result << std::endl;
	}

	void report_warning(WarningCode warning, std::string_view file,
		uint32_t line_number, uint16_t column_number) {

		if (!reporting_enabled) {
			return;
		}
		log_warning(warning);

		std::lock_guard<std::mutex> lock(cout_mutex);

		if (printing_enabled) {
			print_warning(warning, file, line_number, column_number, "");
		}
	}

	void report_warning(WarningCode warning, std::string_view file,
		uint32_t line_number, uint16_t column_number,
		std::string_view additional_info) {

		if (!reporting_enabled) {
			return;
		}
		log_warning(warning);

		std::lock_guard<std::mutex> lock(cout_mutex);

		if (printing_enabled) {
			print_warning(warning, file, line_number, column_number,
				additional_info);
		}
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
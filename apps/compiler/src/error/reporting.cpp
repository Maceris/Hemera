#include <format>
#include <iostream>
#include <mutex>
#include <set>
#include <string>

#include "error/reporting.h"

namespace hemera {

	static std::mutex cout_mutex;
	static std::mutex storage_mutex;
	static bool reporting_enabled = true;
	static bool printing_enabled = true;
	static std::vector<ErrorCode>* error_list_storage;
	static std::vector<WarningCode>* warning_list_storage;
	/*
	 * Every error reported so far, so the same one isn't reported twice. Work that waits for
	 * something starts over when woken, and reports again what it found before.
	 */
	static std::set<std::string>* reported_storage;

	DisableReportingForBlock::DisableReportingForBlock() {
		disable_reporting();
	}

	DisableReportingForBlock::~DisableReportingForBlock() {
		enable_reporting();
	}

	void destroy_reporting_storage() {
		std::lock_guard<std::mutex> lock(storage_mutex);

		if (error_list_storage != nullptr) {
			error_list_storage->clear();
			delete error_list_storage;
			error_list_storage = nullptr;
		}
		if (warning_list_storage != nullptr) {
			warning_list_storage->clear();
			delete warning_list_storage;
			warning_list_storage = nullptr;
		}
		delete reported_storage;
		reported_storage = nullptr;
		destroy_error_info_map();
		destroy_warning_info_map();
	}

	void disable_reporting() {
		std::lock_guard<std::mutex> lock(storage_mutex);
		reporting_enabled = false;
	}

	void disable_reporting_printing() {
		std::lock_guard<std::mutex> lock(cout_mutex);
		printing_enabled = false;
	}

	void enable_reporting() {
		std::lock_guard<std::mutex> lock(storage_mutex);
		reporting_enabled = true;
	}

	void enable_reporting_printing() {
		std::lock_guard<std::mutex> lock(cout_mutex);
		printing_enabled = true;
	}
	
	void initialize_reporting_storage() {
		std::lock_guard<std::mutex> lock(storage_mutex);
		
		initialize_error_info_map();
		initialize_warning_info_map();

		if (error_list_storage == nullptr) {
			error_list_storage = new std::vector<ErrorCode>();
		}
		if (warning_list_storage == nullptr) {
			warning_list_storage = new std::vector<WarningCode>();
		}
		if (reported_storage == nullptr) {
			reported_storage = new std::set<std::string>();
		}
	}

	void reset_reporting_storage() {
		std::lock_guard<std::mutex> lock(storage_mutex);

		if (error_list_storage != nullptr) {
			error_list_storage->clear();
		}
		if (warning_list_storage != nullptr) {
			warning_list_storage->clear();
		}
		if (reported_storage != nullptr) {
			reported_storage->clear();
		}
	}

	// Whether this exact report is new, recording it if so.
	static bool first_report(std::string_view kind, int code, std::string_view file,
		uint32_t line_number, uint16_t column_number, std::string_view additional_info) {

		std::lock_guard<std::mutex> lock(storage_mutex);
		if (reported_storage == nullptr) {
			return true;
		}
		return reported_storage->insert(std::format("{} {} {}({},{}) {}", kind, code, file, line_number,
			column_number, additional_info)).second;
	}

	static void log_error(ErrorCode error) {
		std::lock_guard<std::mutex> lock(storage_mutex);

		if (error_list_storage != nullptr) {
			error_list_storage->push_back(error);
		}
	}

	static void print_error(ErrorCode error, std::string_view file,
		uint32_t line_number, uint16_t column_number,
		std::string_view additional_info) {

		auto it = error_info_map->find(error);

		ErrorInfo info = (it != error_info_map->end())
			? it->second
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

	// Errors reported on each thread, including ones already reported elsewhere.
	static thread_local size_t errors_on_this_thread = 0;

	size_t thread_error_count() {
		return errors_on_this_thread;
	}

	void report_error(ErrorCode error, std::string_view file,
		uint32_t line_number, uint16_t column_number) {

		++errors_on_this_thread;
		if (!reporting_enabled
			|| !first_report("error", static_cast<int>(error), file, line_number, column_number, "")) {
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

		++errors_on_this_thread;
		if (!reporting_enabled || !first_report("error", static_cast<int>(error), file, line_number,
			column_number, additional_info)) {
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

		if (warning_list_storage != nullptr) {
			warning_list_storage->push_back(warning);
		}
	}

	static void print_warning(WarningCode warning, std::string_view file,
		uint32_t line_number, uint16_t column_number,
		std::string_view additional_info) {

		auto it = warning_info_map->find(warning);

		WarningInfo info = (it != warning_info_map->end())
			? it->second
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

		if (!reporting_enabled
			|| !first_report("warning", static_cast<int>(warning), file, line_number, column_number, "")) {
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

		if (!reporting_enabled || !first_report("warning", static_cast<int>(warning), file, line_number,
			column_number, additional_info)) {
			return;
		}
		log_warning(warning);

		std::lock_guard<std::mutex> lock(cout_mutex);

		if (printing_enabled) {
			print_warning(warning, file, line_number, column_number,
				additional_info);
		}
	}

	void report_message(std::string_view file, uint32_t line_number, uint16_t column_number,
		std::string_view kind, std::string_view text) {

		if (!reporting_enabled) {
			return;
		}
		std::lock_guard<std::mutex> lock(cout_mutex);
		if (printing_enabled) {
			std::cout << std::format("{}({},{}): {}: {}", file, line_number, column_number, kind, text) << std::endl;
		}
	}

	size_t error_count() {
		std::lock_guard<std::mutex> lock(storage_mutex);
		if (error_list_storage == nullptr) {
			return 0;
		}
		return error_list_storage->size();
	}

	std::vector<ErrorCode>* error_list() {
		return error_list_storage;
	}

	size_t warning_count() {
		std::lock_guard<std::mutex> lock(storage_mutex);
		if (warning_list_storage == nullptr) {
			return 0;
		}
		return warning_list_storage->size();
	}

	std::vector<WarningCode>* warning_list() {
		return warning_list_storage;
	}

}

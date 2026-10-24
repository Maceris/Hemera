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
	static std::vector<std::string>* error_message_storage;
	static std::vector<WarningCode>* warning_list_storage;
	/*
	 * Every error reported so far, so the same one isn't reported twice. Work that waits for
	 * something starts over when woken, and reports again what it found before.
	 */
	static std::set<std::string>* reported_storage;
	static thread_local ReportScope* current_scope = nullptr;

	void set_report_scope(ReportScope* scope) {
		current_scope = scope;
	}

	ReportScope* report_scope() {
		return current_scope;
	}

	void print_report_scope(ReportScope& scope) {
		std::string output;
		std::string errors_output;
		{
			std::lock_guard<std::mutex> scope_lock(scope.mutex);
			output.swap(scope.output);
			errors_output.swap(scope.errors_output);
		}
		std::lock_guard<std::mutex> lock(cout_mutex);
		if (printing_enabled && !output.empty()) {
			std::cout << output << std::flush;
		}
		if (!errors_output.empty()) {
			std::cerr << errors_output << std::flush;
		}
	}

	// A line of output, printed, or kept in the thread's scope.
	static void write_line(const std::string& line) {
		if (current_scope != nullptr) {
			std::lock_guard<std::mutex> lock(current_scope->mutex);
			current_scope->output += line;
			current_scope->output += '\n';
			return;
		}
		std::lock_guard<std::mutex> lock(cout_mutex);
		if (printing_enabled) {
			std::cout << line << std::endl;
		}
	}

	void report_to_standard_error(std::string_view line) {
		if (current_scope != nullptr) {
			std::lock_guard<std::mutex> lock(current_scope->mutex);
			current_scope->errors_output += line;
			current_scope->errors_output += '\n';
			return;
		}
		std::lock_guard<std::mutex> lock(cout_mutex);
		std::cerr << line << std::endl;
	}

	void report_text(std::string_view text) {
		if (current_scope != nullptr) {
			std::lock_guard<std::mutex> lock(current_scope->mutex);
			current_scope->output += text;
			return;
		}
		std::lock_guard<std::mutex> lock(cout_mutex);
		if (printing_enabled) {
			std::cout << text << std::flush;
		}
	}

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
		delete error_message_storage;
		error_message_storage = nullptr;
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
		if (error_message_storage == nullptr) {
			error_message_storage = new std::vector<std::string>();
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
		if (error_message_storage != nullptr) {
			error_message_storage->clear();
		}
		if (warning_list_storage != nullptr) {
			warning_list_storage->clear();
		}
		if (reported_storage != nullptr) {
			reported_storage->clear();
		}
	}

	// Whether this exact report is new, in the thread's scope or everywhere, recording it if so.
	static bool first_report(std::string_view kind, int code, std::string_view file,
		uint32_t line_number, uint16_t column_number, std::string_view additional_info) {

		std::string key = std::format("{} {} {}({},{}) {}", kind, code, file, line_number, column_number, additional_info);
		if (current_scope != nullptr) {
			std::lock_guard<std::mutex> lock(current_scope->mutex);
			const bool fresh = current_scope->reported.insert(std::move(key)).second;
			if (fresh && kind == "error") {
				current_scope->errors += 1;
			}
			return fresh;
		}
		std::lock_guard<std::mutex> lock(storage_mutex);
		if (reported_storage == nullptr) {
			return true;
		}
		return reported_storage->insert(std::move(key)).second;
	}

	static void log_error(ErrorCode error, std::string_view details = "") {
		std::lock_guard<std::mutex> lock(storage_mutex);

		if (error_list_storage != nullptr) {
			error_list_storage->push_back(error);
		}
		if (error_message_storage != nullptr) {
			error_message_storage->emplace_back(details);
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

		write_line(std::format("{}({},{}): {} {}: {}{}", file,
			line_number, column_number, "error", info.string_value,
			info.message, extension));
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
		print_error(error, file, line_number, column_number, "");
	}

	void report_error(ErrorCode error, std::string_view file,
		uint32_t line_number, uint16_t column_number,
		std::string_view additional_info) {

		++errors_on_this_thread;
		if (!reporting_enabled || !first_report("error", static_cast<int>(error), file, line_number,
			column_number, additional_info)) {
			return;
		}

		log_error(error, additional_info);
		print_error(error, file, line_number, column_number, additional_info);
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

		write_line(std::format("{}({},{}): {} {}: {}{}", file,
			line_number, column_number, "warning", info.string_value,
			info.message, extension));
	}

	void report_warning(WarningCode warning, std::string_view file,
		uint32_t line_number, uint16_t column_number) {

		if (!reporting_enabled
			|| !first_report("warning", static_cast<int>(warning), file, line_number, column_number, "")) {
			return;
		}
		log_warning(warning);
		print_warning(warning, file, line_number, column_number, "");
	}

	void report_warning(WarningCode warning, std::string_view file,
		uint32_t line_number, uint16_t column_number,
		std::string_view additional_info) {

		if (!reporting_enabled || !first_report("warning", static_cast<int>(warning), file, line_number,
			column_number, additional_info)) {
			return;
		}
		log_warning(warning);
		print_warning(warning, file, line_number, column_number, additional_info);
	}

	void report_message(std::string_view file, uint32_t line_number, uint16_t column_number,
		std::string_view kind, std::string_view text) {

		if (!reporting_enabled) {
			return;
		}
		write_line(std::format("{}({},{}): {}: {}", file, line_number, column_number, kind, text));
	}

	size_t error_count() {
		if (current_scope != nullptr) {
			std::lock_guard<std::mutex> lock(current_scope->mutex);
			return current_scope->errors;
		}
		std::lock_guard<std::mutex> lock(storage_mutex);
		if (error_list_storage == nullptr) {
			return 0;
		}
		return error_list_storage->size();
	}

	std::vector<ErrorCode>* error_list() {
		return error_list_storage;
	}

	std::vector<std::string>* error_messages() {
		return error_message_storage;
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

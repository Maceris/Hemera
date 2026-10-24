#pragma once

#include <cstdint>
#include <mutex>
#include <set>
#include <string>
#include <string_view>
#include <vector>

#include "hemera_errors.h"
#include "hemera_warnings.h"

namespace hemera {

	/// <summary>
	/// Delete the reporting storage.
	/// </summary>
	void destroy_reporting_storage();

	/// <summary>
	/// Used for testing, turns off error reporting globally.
	/// </summary>
	void disable_reporting();

	void disable_reporting_printing();

	/// <summary>
	/// Enables error reporting globally, which is on by default.
	/// </summary>
	void enable_reporting();
	void enable_reporting_printing();

	/// <summary>
	/// Allocate the reporting storage. Must be done before reporting anything.
	/// </summary>
	void initialize_reporting_storage();
	void reset_reporting_storage();

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

	void report_error(ErrorCode error, std::string_view file,
		uint32_t line_number, uint16_t column_number,
		std::string_view additional_info);

	void report_warning(WarningCode warning, std::string_view file,
		uint32_t line_number, uint16_t column_number);

	void report_warning(WarningCode warning, std::string_view file,
		uint32_t line_number, uint16_t column_number,
		std::string_view additional_info);

	/// <summary>
	/// Prints a message that isn't an error or a warning, like what compile-time code logs at the
	/// info level, when printing is on.
	/// </summary>
	void report_message(std::string_view file, uint32_t line_number, uint16_t column_number,
		std::string_view kind, std::string_view text);

	/// <summary>
	/// What's reported while it's a thread's scope (set_report_scope): counted, not repeated, and kept rather
	/// than printed, so work done at the same time, like a build's targets, can report each in one piece and in
	/// order (print_report_scope). Errors still go in error_list too.
	/// </summary>
	struct ReportScope {
		std::mutex mutex;
		std::set<std::string> reported;
		// What would have gone to standard output, then standard error (--time-phases)
		std::string output;
		std::string errors_output;
		size_t errors = 0;
	};

	/// <summary>
	/// The calling thread's scope, or null for none; threads a scope's work starts on take it on (front_end.cpp).
	/// </summary>
	void set_report_scope(ReportScope* scope);
	ReportScope* report_scope();
	/// <summary>
	/// What a scope kept, printed, and then forgotten.
	/// </summary>
	void print_report_scope(ReportScope& scope);
	/// <summary>
	/// A line for standard error, like a phase's time, kept in the thread's scope if it has one.
	/// </summary>
	void report_to_standard_error(std::string_view line);
	/// <summary>
	/// Text for standard output, like code --show-inserted prints, kept in the thread's scope if it has one.
	/// </summary>
	void report_text(std::string_view text);

	/// <summary>
	/// Every error so far, or with a scope, the scope's.
	/// </summary>
	size_t error_count();
	/// <summary>
	/// How many errors this thread has reported, including ones already reported elsewhere: what checking one
	/// thing found, unlike error_count, which other threads' work adds to.
	/// </summary>
	size_t thread_error_count();
	std::vector<ErrorCode>* error_list();
	/// <summary>
	/// Each error's details, in the same order as error_list, empty for one reported without any.
	/// </summary>
	std::vector<std::string>* error_messages();
	size_t warning_count();
	std::vector<WarningCode>* warning_list();
}

#pragma once

#include <cstdint>
#include <cstdio>
#include <mutex>
#include <set>
#include <string>
#include <string_view>
#include <utility>
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

	/*
	 * The prefix the compiler's own codes are printed with, as hemera:E4015 (docs/compilation.md, Diagnostics), which no
	 * package can use or be named.
	 */
	constexpr std::string_view COMPILER_PREFIX = "hemera";

	/*
	 * A diagnostic compile-time code reported with its own code, through compiler.report: printed as prefix:code, like
	 * fonts:W0003, with message after it. An error fails the build. In error_list and warning_list it's E4029 or W4001,
	 * which compile-time code's diagnostics all are there. prefix and code must already be checked.
	 */
	void report_coded(bool error, std::string_view prefix, std::string_view code, std::string_view file,
		uint32_t line_number, uint16_t column_number, std::string_view message);

	/*
	 * Which warnings are shown (docs/compilation.md, Allowing and Denying Warnings), set for each build of a program,
	 * in its scope or for the whole process. A pattern is a warning's prefix:code, like hemera:W2001, a prefix's every
	 * warning, like fonts:*, or every warning, *.
	 */
	struct WarningRules {
		// Not shown, from --allow or BuildOptions.allowed_warnings
		std::vector<std::string> allowed;
		// Errors instead, keeping their codes, from --deny or BuildOptions.denied_warnings
		std::vector<std::string> denied;
		// Each package's folder, with / throughout, and the patterns its ALLOWED_WARNINGS allows in it
		std::vector<std::pair<std::string, std::vector<std::string>>> package_allowed;
		// Folders whose warnings aren't shown, the built-in packages', but for shown_folder, the root package's
		std::vector<std::string> quiet_folders;
		std::string shown_folder;
		// std's folder, with / throughout, for compile-time code's <std>/... names (path_on_disk); empty for none
		std::string std_folder;
		// While the front end reads the packages, whose own lists may come after their warnings, they're held
		bool holding = false;
		// Starts not yet released: a package loaded while compiling (compiler.load_package) starts again, inside
		size_t depth = 0;
		struct Held {
			std::string coded;
			WarningCode code;
			std::string file;
			uint32_t line;
			uint16_t column;
			std::string text;
		};
		std::vector<Held> held;
		std::mutex mutex;
	};

	/*
	 * Whether pattern is one a warning list can hold: *, or a prefix, a name, then : and either * or a warning's code,
	 * W and ASCII letters and digits.
	 */
	bool is_warning_pattern(std::string_view pattern);

	/*
	 * Adds each pattern in text, separated by commas, with any spaces around them, to patterns, like --allow's value.
	 * Returns false, having added none, if one isn't a pattern (is_warning_pattern).
	 */
	bool add_warning_patterns(std::string_view text, std::vector<std::string>& patterns);

	/*
	 * Starts a build's warning rules, in the thread's scope or for the process: what the build allows and denies, the
	 * folders whose warnings aren't shown, and the root package's, which is shown wherever it is. Warnings are held
	 * from here until release_warnings. shown_folder and std_folder (empty for none) are also what path_on_disk
	 * resolves names against.
	 */
	void start_warning_rules(std::vector<std::string> allowed, std::vector<std::string> denied,
		std::vector<std::string> quiet_folders, std::string shown_folder, std::string std_folder = {});

	/*
	 * A file as compile-time code names it (#source_location, docs/compilation.md, Deterministic Output) turned back
	 * into the path on disk that diagnostics give: <std>/... beneath the build's std folder, and a relative path
	 * beneath its root package's folder, from the thread's scope's warning rules or the process's. <base>/... and
	 * absolute paths are returned as they are, as is anything when the build gave no folder for it.
	 */
	std::string path_on_disk(std::string_view name);

	// A package's own ALLOWED_WARNINGS, for warnings in its folder.
	void allow_warnings_in_package(std::string folder, std::vector<std::string> patterns);

	// Reports the warnings held since start_warning_rules, as the rules decide, and stops holding them.
	void release_warnings();

	/// <summary>
	/// Prints a message that isn't an error or a warning, like what compile-time code logs at the
	/// info level, when printing is on.
	/// </summary>
	void report_message(std::string_view file, uint32_t line_number, uint16_t column_number,
		std::string_view kind, std::string_view text);

	// How serious a diagnostic is, as an editor shows it
	enum class Severity {
		ERROR,
		WARNING,
		// What isn't an error or a warning, like what compile-time code logs (report_message)
		INFORMATION,
	};

	/*
	 * A diagnostic as it was reported, kept for tools that read them rather than the printed text, like an editor's.
	 * Every error, warning and message that's printed makes one, in the order they're printed, whether printing is on
	 * or not; a hidden warning (WarningRules) makes none, and a denied one is an error with the warning's own code.
	 */
	// Where an #insert put code a diagnostic is in: the #insert's file, line and column, as a diagnostic's are.
	struct DiagnosticSite {
		std::string file;
		uint32_t line = 0;
		uint16_t column = 0;
	};

	struct Diagnostic {
		Severity severity = Severity::ERROR;
		// Whose code it is, like hemera or fonts; empty for a message, which has no code
		std::string prefix;
		// Like E4015 or W0003; empty for a message
		std::string code;
		// The file as the compiler names it, with its own separators, like <base>/runtime/runtime.hsc for base
		std::string file;
		// Counting from 1; 0 when it's about no line in particular
		uint32_t line = 0;
		// Bytes from the line's start, counting from 0, as the printed text's are; 0 too for no column in particular
		uint16_t column = 0;
		// The text after the code, as printed: an error's title, with what's added to it after ". "
		std::string message;
		// The build package's target whose check found it (ReportScope::target); empty for none, as outside a build
		std::string target;
		// For code compile-time code inserted, each #insert that put it where it is, the first first; empty otherwise
		std::vector<DiagnosticSite> inserted;
	};

	/*
	 * While one is alive, what this thread reports is in code inserted at sites (Diagnostic::inserted): for reporting an
	 * error in inserted code, around the report. Not nested.
	 */
	class InsertedAt {
	public:
		explicit InsertedAt(std::vector<DiagnosticSite> sites);
		~InsertedAt();
		InsertedAt(const InsertedAt&) = delete;
		InsertedAt& operator=(const InsertedAt&) = delete;

	private:
		std::vector<DiagnosticSite> sites;
	};

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
		// The diagnostics in output, which join the process's (diagnostics) when it's printed
		std::vector<Diagnostic> diagnostics;
		// Its diagnostics as JSON lines, in place of their text in output, when they're printed that way
		std::string json_output;
		size_t errors = 0;
		// Which of its warnings are shown
		WarningRules warnings;
		// The build package's target it's the check of, given to each diagnostic reported in it; empty for none
		std::string target;
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
	/*
	 * A copy of every diagnostic printed so far, in the order printed: a scope's join them when it's printed
	 * (print_report_scope), not before. Emptied by reset_reporting_storage.
	 */
	std::vector<Diagnostic> diagnostics();

	/*
	 * A diagnostic as one line of JSON, without its newline (docs/compilation.md, Diagnostics as JSON):
	 * {"severity":"error","code":"hemera:E4015","file":"D:/project/main.hsc","line":12,"column":5,"message":"..."}.
	 * severity is error, warning or information; code is left out for information, which has none; file has / for
	 * \; "target":"name" comes last for a build target's diagnostic, and not otherwise. Text is escaped as JSON needs, and bytes that aren't UTF-8 are passed through as they are.
	 */
	std::string diagnostic_json(const Diagnostic& diagnostic);

	/*
	 * From now on, each diagnostic is written to stream as a line of JSON (diagnostic_json), flushed, in place of
	 * the text it's printed as; null goes back to text. stream isn't owned, and has to stay open until then. Only
	 * diagnostics change: other output, like --time-phases', goes where it did.
	 */
	void print_diagnostics_as_json(std::FILE* stream);

	/*
	 * line, without its end, written to the JSON stream (print_diagnostics_as_json) with an end and flushed, after
	 * any diagnostic before it, as a long-lived compiler says it's done a check (hemera --serve). Nothing without one.
	 */
	void write_protocol_line(std::string_view line);

	/*
	 * A diagnostic reported again as it was, kept and printed as it was the first time, even if this one's been
	 * reported, as a long-lived compiler does for what it kept from an earlier check (hemera --serve). An error
	 * counts as one.
	 */
	void report_again(const Diagnostic& diagnostic);
}

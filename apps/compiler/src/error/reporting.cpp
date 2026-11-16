#include <algorithm>
#include <filesystem>
#include <format>
#include <iostream>
#include <mutex>
#include <set>
#include <string>

#include "error/reporting.h"
#include "lexer/identifiers.h"

namespace hemera {

	static std::mutex cout_mutex;
	static std::mutex storage_mutex;
	static bool reporting_enabled = true;
	static bool printing_enabled = true;
	static std::vector<ErrorCode>* error_list_storage;
	static std::vector<std::string>* error_message_storage;
	static std::vector<WarningCode>* warning_list_storage;
	static std::vector<Diagnostic>* diagnostic_storage;
	/*
	 * Every error reported so far, so the same one isn't reported twice. Work that waits for
	 * something starts over when woken, and reports again what it found before.
	 */
	static std::set<std::string>* reported_storage;
	static thread_local ReportScope* current_scope = nullptr;
	// Where diagnostics go as JSON lines (print_diagnostics_as_json), or null for text; guarded by cout_mutex
	static std::FILE* json_stream = nullptr;

	// Text written to the JSON stream, whole, while printing's on; cout_mutex held
	static void write_json(const std::string& text) {
		if (printing_enabled && json_stream != nullptr && !text.empty()) {
			std::fwrite(text.data(), 1, text.size(), json_stream);
			std::fflush(json_stream);
		}
	}

	void print_diagnostics_as_json(std::FILE* stream) {
		std::lock_guard<std::mutex> lock(cout_mutex);
		json_stream = stream;
	}

	// text as the inside of a JSON string
	static void append_json_string(std::string& out, std::string_view text) {
		for (const char c : text) {
			switch (c) {
			case '"': out += "\\\""; break;
			case '\\': out += "\\\\"; break;
			case '\n': out += "\\n"; break;
			case '\r': out += "\\r"; break;
			case '\t': out += "\\t"; break;
			default:
				if (static_cast<unsigned char>(c) < 0x20) {
					out += std::format("\\u{:04x}", static_cast<unsigned char>(c));
				}
				else {
					out += c;
				}
			}
		}
	}

	std::string diagnostic_json(const Diagnostic& diagnostic) {
		std::string out = "{\"severity\":\"";
		out += Severity::ERROR == diagnostic.severity ? "error" : Severity::WARNING == diagnostic.severity ? "warning" : "information";
		out += '"';
		if (!diagnostic.code.empty()) {
			out += ",\"code\":\"";
			append_json_string(out, diagnostic.prefix);
			out += ':';
			append_json_string(out, diagnostic.code);
			out += '"';
		}
		std::string file = diagnostic.file;
		std::replace(file.begin(), file.end(), '\\', '/');
		out += ",\"file\":\"";
		append_json_string(out, file);
		out += std::format("\",\"line\":{},\"column\":{},\"message\":\"", diagnostic.line, diagnostic.column);
		append_json_string(out, diagnostic.message);
		out += "\"}";
		return out;
	}

	void set_report_scope(ReportScope* scope) {
		current_scope = scope;
	}

	ReportScope* report_scope() {
		return current_scope;
	}

	void print_report_scope(ReportScope& scope) {
		std::string output;
		std::string errors_output;
		std::vector<Diagnostic> kept;
		std::string json_output;
		{
			std::lock_guard<std::mutex> scope_lock(scope.mutex);
			output.swap(scope.output);
			errors_output.swap(scope.errors_output);
			kept.swap(scope.diagnostics);
			json_output.swap(scope.json_output);
		}
		{
			std::lock_guard<std::mutex> storage_lock(storage_mutex);
			if (diagnostic_storage != nullptr) {
				diagnostic_storage->insert(diagnostic_storage->end(), std::make_move_iterator(kept.begin()),
					std::make_move_iterator(kept.end()));
			}
		}
		std::lock_guard<std::mutex> lock(cout_mutex);
		if (printing_enabled && !output.empty()) {
			std::cout << output << std::flush;
		}
		if (!errors_output.empty()) {
			std::cerr << errors_output << std::flush;
		}
		write_json(json_output);
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

	// Whether diagnostics are printed as JSON (print_diagnostics_as_json)
	static bool printing_json() {
		std::lock_guard<std::mutex> lock(cout_mutex);
		return json_stream != nullptr;
	}

	// A diagnostic, kept with the thread's scope's or the process's, and printed as line, or as JSON
	static void emit(Diagnostic diagnostic, const std::string& line) {
		const bool json = printing_json();
		std::string json_line = json ? diagnostic_json(diagnostic) + "\n" : std::string();
		if (current_scope != nullptr) {
			std::lock_guard<std::mutex> lock(current_scope->mutex);
			current_scope->diagnostics.push_back(std::move(diagnostic));
			current_scope->json_output += json_line;
		}
		else {
			{
				std::lock_guard<std::mutex> lock(storage_mutex);
				if (diagnostic_storage != nullptr) {
					diagnostic_storage->push_back(std::move(diagnostic));
				}
			}
			if (json) {
				std::lock_guard<std::mutex> lock(cout_mutex);
				write_json(json_line);
			}
		}
		if (!json) {
			write_line(line);
		}
	}

	// The diagnostic printed as prefix:code, like hemera:E4015, from coded
	static Diagnostic coded_diagnostic(Severity severity, std::string_view coded, std::string_view file,
		uint32_t line_number, uint16_t column_number, std::string_view message) {

		const size_t colon = coded.find(':');
		return Diagnostic{ severity, std::string(coded.substr(0, colon)),
			colon == std::string_view::npos ? std::string() : std::string(coded.substr(colon + 1)), std::string(file),
			line_number, column_number, std::string(message) };
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
		delete diagnostic_storage;
		diagnostic_storage = nullptr;
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
		if (diagnostic_storage == nullptr) {
			diagnostic_storage = new std::vector<Diagnostic>();
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
		if (diagnostic_storage != nullptr) {
			diagnostic_storage->clear();
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

		std::string message(info.message);
		if (!additional_info.empty()) {
			message += std::format(". {}", additional_info);
		}

		std::string line = std::format("{}({},{}): {} {}:{}: {}", file, line_number, column_number, "error",
			COMPILER_PREFIX, info.string_value, message);
		emit(Diagnostic{ Severity::ERROR, std::string(COMPILER_PREFIX), std::string(info.string_value), std::string(file),
			line_number, column_number, std::move(message) }, line);
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

	// The rules of the thread's scope, or the process's
	static WarningRules& warning_rules() {
		// Made once and kept, as the other storage is, so there's nothing to destroy at exit
		static WarningRules* process_warning_rules = new WarningRules();
		return current_scope != nullptr ? current_scope->warnings : *process_warning_rules;
	}

	static std::string with_slashes(std::string_view path) {
		std::string result(path);
		std::replace(result.begin(), result.end(), '\\', '/');
		while (result.size() > 1 && result.back() == '/') {
			result.pop_back();
		}
		return result;
	}

	// Whether path is folder or inside it
	static bool within(std::string_view path, std::string_view folder) {
		return !folder.empty() && path.starts_with(folder) && (path.size() == folder.size() || path[folder.size()] == '/');
	}

	static bool matches(const std::vector<std::string>& patterns, std::string_view coded) {
		const std::string_view prefix = coded.substr(0, coded.find(':'));
		for (const std::string& pattern : patterns) {
			if (pattern == "*" || pattern == coded || (pattern.ends_with(":*") && pattern.substr(0, pattern.size() - 2) == prefix)) {
				return true;
			}
		}
		return false;
	}

	bool is_warning_pattern(std::string_view pattern) {
		if (pattern == "*") {
			return true;
		}
		const size_t colon = pattern.find(':');
		if (colon == std::string_view::npos || !lexer::is_identifier(pattern.substr(0, colon))) {
			return false;
		}
		const std::string_view code = pattern.substr(colon + 1);
		return code == "*" || (code.size() >= 2 && code[0] == 'W' && std::all_of(code.begin(), code.end(),
			[](char c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'); }));
	}

	bool add_warning_patterns(std::string_view text, std::vector<std::string>& patterns) {
		std::vector<std::string> found;
		while (!text.empty()) {
			const size_t comma = text.find(',');
			std::string_view pattern = text.substr(0, comma);
			text = comma == std::string_view::npos ? std::string_view() : text.substr(comma + 1);
			while (!pattern.empty() && pattern.front() == ' ') {
				pattern.remove_prefix(1);
			}
			while (!pattern.empty() && pattern.back() == ' ') {
				pattern.remove_suffix(1);
			}
			if (pattern.empty()) {
				continue;
			}
			if (!is_warning_pattern(pattern)) {
				return false;
			}
			found.emplace_back(pattern);
		}
		patterns.insert(patterns.end(), found.begin(), found.end());
		return true;
	}

	std::string path_on_disk(std::string_view name) {
		constexpr std::string_view STD = "<std>/";
		WarningRules& rules = warning_rules();
		std::lock_guard<std::mutex> lock(rules.mutex);
		if (name.starts_with(STD)) {
			return rules.std_folder.empty() ? std::string(name) : rules.std_folder + "/" + std::string(name.substr(STD.size()));
		}
		if (name.empty() || name.starts_with('<') || rules.shown_folder.empty() || std::filesystem::path(name).is_absolute()) {
			return std::string(name);
		}
		return (std::filesystem::path(rules.shown_folder) / name).lexically_normal().generic_string();
	}

	void start_warning_rules(std::vector<std::string> allowed, std::vector<std::string> denied,
		std::vector<std::string> quiet_folders, std::string shown_folder, std::string std_folder) {

		WarningRules& rules = warning_rules();
		std::lock_guard<std::mutex> lock(rules.mutex);
		// Inside another build's front end, as compiler.load_package's is, whose rules go on
		if (rules.depth++ > 0) {
			return;
		}
		rules.allowed = std::move(allowed);
		rules.denied = std::move(denied);
		rules.package_allowed.clear();
		rules.quiet_folders.clear();
		for (const std::string& folder : quiet_folders) {
			rules.quiet_folders.push_back(with_slashes(folder));
		}
		rules.shown_folder = with_slashes(shown_folder);
		rules.std_folder = with_slashes(std_folder);
		rules.holding = true;
		rules.held.clear();
	}

	void allow_warnings_in_package(std::string folder, std::vector<std::string> patterns) {
		WarningRules& rules = warning_rules();
		std::lock_guard<std::mutex> lock(rules.mutex);
		rules.package_allowed.emplace_back(with_slashes(folder), std::move(patterns));
	}

	enum class WarningFate {
		SHOWN,
		HIDDEN,
		DENIED,
	};

	/*
	 * What becomes of a warning: hidden if its package allows it, if it's in a built-in package that isn't the one being
	 * built, or if the build allows it; otherwise an error if the build denies it, or shown.
	 */
	static WarningFate fate_of(WarningRules& rules, std::string_view coded, std::string_view file) {
		const std::string path = with_slashes(file);
		const std::string folder = path.substr(0, path.rfind('/') == std::string::npos ? 0 : path.rfind('/'));
		for (const auto& [package, patterns] : rules.package_allowed) {
			if (package == folder && matches(patterns, coded)) {
				return WarningFate::HIDDEN;
			}
		}
		if (!within(path, rules.shown_folder)) {
			for (const std::string& quiet : rules.quiet_folders) {
				if (within(path, quiet)) {
					return WarningFate::HIDDEN;
				}
			}
		}
		if (matches(rules.allowed, coded)) {
			return WarningFate::HIDDEN;
		}
		return matches(rules.denied, coded) ? WarningFate::DENIED : WarningFate::SHOWN;
	}

	// A warning decided on: shown, counted in warning_list as code; or denied, an error that keeps coded
	static void decide_warning(WarningRules& rules, const WarningRules::Held& warning) {
		WarningFate fate;
		{
			std::lock_guard<std::mutex> lock(rules.mutex);
			fate = fate_of(rules, warning.coded, warning.file);
		}
		if (WarningFate::HIDDEN == fate) {
			return;
		}
		const bool denied = WarningFate::DENIED == fate;
		if (denied) {
			++errors_on_this_thread;
		}
		if (!first_report(denied ? "error" : "warning", denied ? static_cast<int>(ErrorCode::E4045) : static_cast<int>(warning.code),
			warning.file, warning.line, warning.column, std::format("{} {}", warning.coded, warning.text))) {
			return;
		}
		if (denied) {
			log_error(ErrorCode::E4045, std::format("{}: {}", warning.coded, warning.text));
		}
		else {
			log_warning(warning.code);
		}
		emit(coded_diagnostic(denied ? Severity::ERROR : Severity::WARNING, warning.coded, warning.file, warning.line,
			warning.column, warning.text), std::format("{}({},{}): {} {}: {}", warning.file, warning.line, warning.column,
			denied ? "error" : "warning", warning.coded, warning.text));
	}

	// Every warning, the compiler's and compile-time code's: held while the rules are being gathered, or decided on
	static void emit_warning(std::string coded, WarningCode code, std::string_view file, uint32_t line_number,
		uint16_t column_number, std::string text) {

		if (!reporting_enabled) {
			return;
		}
		WarningRules& rules = warning_rules();
		WarningRules::Held warning{ std::move(coded), code, std::string(file), line_number, column_number, std::move(text) };
		{
			std::lock_guard<std::mutex> lock(rules.mutex);
			if (rules.holding) {
				rules.held.push_back(std::move(warning));
				return;
			}
		}
		decide_warning(rules, warning);
	}

	void release_warnings() {
		WarningRules& rules = warning_rules();
		std::vector<WarningRules::Held> held;
		{
			std::lock_guard<std::mutex> lock(rules.mutex);
			if (rules.depth > 0 && --rules.depth > 0) {
				return;
			}
			rules.holding = false;
			held.swap(rules.held);
		}
		for (const WarningRules::Held& warning : held) {
			decide_warning(rules, warning);
		}
	}

	// A warning of the compiler's own: hemera:W2001, with its title and what's added to it
	static void compiler_warning(WarningCode warning, std::string_view file, uint32_t line_number, uint16_t column_number,
		std::string_view additional_info) {

		auto it = warning_info_map->find(warning);
		const WarningInfo info = it != warning_info_map->end() ? it->second : WarningInfo("W0000", "Unknown warning");
		emit_warning(std::format("{}:{}", COMPILER_PREFIX, info.string_value), warning, file, line_number, column_number,
			additional_info.empty() ? std::string(info.message) : std::format("{}. {}", info.message, additional_info));
	}

	void report_warning(WarningCode warning, std::string_view file,
		uint32_t line_number, uint16_t column_number) {

		compiler_warning(warning, file, line_number, column_number, "");
	}

	void report_warning(WarningCode warning, std::string_view file,
		uint32_t line_number, uint16_t column_number,
		std::string_view additional_info) {

		compiler_warning(warning, file, line_number, column_number, additional_info);
	}

	void report_coded(bool error, std::string_view prefix, std::string_view code, std::string_view file,
		uint32_t line_number, uint16_t column_number, std::string_view message) {

		const std::string coded = std::format("{}:{}", prefix, code);
		if (error) {
			++errors_on_this_thread;
			if (!reporting_enabled || !first_report("error", static_cast<int>(ErrorCode::E4029), file, line_number,
				column_number, std::format("{} {}", coded, message))) {
				return;
			}
			log_error(ErrorCode::E4029, message);
		}
		else {
			emit_warning(coded, WarningCode::W4001, file, line_number, column_number, std::string(message));
			return;
		}
		emit(Diagnostic{ Severity::ERROR, std::string(prefix), std::string(code), std::string(file), line_number,
			column_number, std::string(message) }, std::format("{}({},{}): error {}: {}", file, line_number, column_number,
			coded, message));
	}

	void report_message(std::string_view file, uint32_t line_number, uint16_t column_number,
		std::string_view kind, std::string_view text) {

		if (!reporting_enabled) {
			return;
		}
		emit(Diagnostic{ Severity::INFORMATION, "", "", std::string(file), line_number, column_number, std::string(text) },
			std::format("{}({},{}): {}: {}", file, line_number, column_number, kind, text));
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

	std::vector<Diagnostic> diagnostics() {
		std::lock_guard<std::mutex> lock(storage_mutex);
		return diagnostic_storage != nullptr ? *diagnostic_storage : std::vector<Diagnostic>();
	}

}

#pragma once

#include <functional>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "error/reporting.h"
#include "parser/ast_types.h"

/*
 * Fixes for what checking reports (Diagnostic::fixes, given with WithFixes around the report): each worked out from
 * what the checker knows where it reports the error, and the file's text as it was read.
 */
namespace hemera {

	struct FileInfo;
	struct Options;
	struct ProgramInfo;

	/*
	 * A file's text as checking read it: an overlay's in its place (--overlay), or the file's on disk. Empty for one that
	 * can't be read, like base's, which is built in.
	 */
	std::optional<std::string> source_text(const Options* options, const std::string& file_path);

	/*
	 * For a match at match_node in file_path that leaves arms out, written as their patterns, like .Red, None or Some(_):
	 * adding them, each case pattern => {} on a line of its own before the match's }, indented as its other arms; and
	 * adding case _. Empty when the match's } can't be found.
	 */
	std::vector<DiagnosticFix> missing_arm_fixes(const Options* options, const std::string& file_path, const ast::Node* match_node,
		const std::vector<std::string>& arms);

	/*
	 * For a doc comment's @param tag at line and column (counting from 1 and from 0) in file_path naming no parameter:
	 * renaming it to rename_to, when there's one undocumented parameter to name, and removing it, its line and those
	 * that continue it.
	 */
	std::vector<DiagnosticFix> param_tag_fixes(const Options* options, const std::string& file_path, uint32_t line, uint16_t column,
		std::string_view name, const std::optional<std::string>& rename_to);

	/*
	 * For an undeclared name at where in file (of program, in package_path): importing a package of that name when a .
	 * follows it and base, std or vendor has one, or another file of the package imports one by that name, put where the
	 * style rules sort it; and changing it to a name among candidates spelled almost the same, the package's own
	 * top-level names and the file's imports added to them. names_held says the caller holds program's names' lock.
	 */
	std::vector<DiagnosticFix> undeclared_name_fixes(const Options* options, ProgramInfo& program, FileInfo* file,
		const std::string& file_path, std::string_view package_path, const ast::Node* where, std::string_view name,
		std::vector<std::string> candidates = {}, bool names_held = false);

	/*
	 * Changing a name at where in file_path to each of candidates spelled almost the same: within two edits, and a third
	 * of its length, the nearest first, at most three.
	 */
	std::vector<DiagnosticFix> spelling_fixes(const ast::Node* where, std::string_view name, const std::vector<std::string>& candidates);

	// How many edits apart two names are: characters added, removed, changed, or two next to each other swapped.
	size_t edit_distance(std::string_view a, std::string_view b);

	/*
	 * While one is alive, undeclared_name_fixes on this thread also takes the names it gives as candidates: for a body's
	 * checker, its locals in scope when the name's reported, as looking a name up reports before the checker would.
	 * One made while another is alive, as checking one body can check another, stands in for it until it ends.
	 */
	class NamesInScope {
	public:
		explicit NamesInScope(std::function<std::vector<std::string>()> names);
		~NamesInScope();
		NamesInScope(const NamesInScope&) = delete;
		NamesInScope& operator=(const NamesInScope&) = delete;

	private:
		std::function<std::vector<std::string>()> names;
		const std::function<std::vector<std::string>()>* outer;
	};
}

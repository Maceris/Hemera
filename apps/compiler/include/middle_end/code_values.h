#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "cmd_line/options.h"
#include "front_end/type.h"
#include "parser/ast_types.h"

namespace hemera {

	/*
	 * compiler.Code values (docs/compilation.md, Code Values): trees compile-time code made, never changed
	 * once made. Their nodes belong to the program (ProgramInfo::made_nodes), and are freed with it. A Code
	 * is a handle numbered within the evaluation that made it, so its number doesn't depend on what other
	 * compile-time code ran meanwhile, on other threads, and a build that reads it is the same each time.
	 */

	/// <summary>
	/// What one #insert in a quote puts there: a Code's tree, a type, or a value that becomes a literal.
	/// </summary>
	struct Spliced {
		enum class Kind : uint8_t {
			CODE,
			TYPE,
			INTEGER,
			FLOAT,
			BOOLEAN,
			CHARACTER,
			STRING,
			ENUM_MEMBER,
		};
		Kind kind = Kind::CODE;
		const ast::Node* tree = nullptr;
		TypeInfo const* type = nullptr;
		uint64_t magnitude = 0;
		bool negative = false;
		double floating = 0;
		std::string text;
	};

	/// <summary>
	/// A copy of the tree quote quotes (in quotes), with each #insert in it, in order, replaced by what's
	/// spliced there, its nodes made in nodes; null if quote isn't a quote. A #code in the copy quotes the
	/// same tree, recorded in quotes.
	/// </summary>
	const ast::Node* make_code(ast::NodeStore& nodes, ast::QuoteTable& quotes, const ast::Node* quote,
		const std::vector<Spliced>& spliced);

	/// <summary>
	/// A copy of a Code's tree to put at site, an #insert, its nodes made in nodes, each with its origin
	/// and site after the sites it already had and those at, the site's own origin, had: so each insertion has
	/// nodes of its own, and errors in them say where the code was written and where it was put. Hygienic for a
	/// macro's expansion (docs/compilation.md, Macros).
	/// </summary>
	const ast::Node* copy_to_insert(ast::NodeStore& nodes, ast::QuoteTable& quotes, const ast::Node* tree,
		const ast::InsertionSite& site, const ast::Origin* at, bool hygienic = false);

	/// <summary>
	/// The word a list of code is marked with, a LIST's: inserted, its items go in its place, each as one of
	/// what holds it (compiler.list).
	/// </summary>
	constexpr std::string_view CODE_LIST = "#list";

	/// <summary>
	/// Whether a tree is a list of code, whose items go where it's inserted.
	/// </summary>
	bool is_code_list(const ast::Node* tree);

	/// <summary>
	/// Code made from a value rather than quoted (compiler.name, literal, type_code, list, parameters,
	/// arguments), its nodes made in nodes and coming from file, the code making it, at line.
	/// </summary>
	const ast::Node* make_name(ast::NodeStore& nodes, std::string_view name, const std::string& file, uint32_t line);
	const ast::Node* make_value(ast::NodeStore& nodes, ast::QuoteTable& quotes, const Spliced& value, const std::string& file,
		uint32_t line);
	const ast::Node* make_list(ast::NodeStore& nodes, const std::vector<const ast::Node*>& items, const std::string& file,
		uint32_t line);
	/// <summary>
	/// A function type's parameters, as a list of parameters (name: Type), or their names, as a list of
	/// arguments. A parameter without a name is called p and its place, like p0.
	/// </summary>
	const ast::Node* make_parameters(ast::NodeStore& nodes, TypeInfoFunction const* function, bool as_arguments,
		const std::string& file, uint32_t line);

	/// <summary>
	/// Prints what was inserted at site, if the command line asks to see what's inserted there
	/// (--show-inserted=file:line).
	/// </summary>
	void show_inserted(const Options* options, const ast::InsertionSite& site, const ast::Node* tree,
		const ast::QuoteTable& quotes);

	/// <summary>
	/// Hemera source for a Code's tree, as code_text gives it.
	/// </summary>
	std::string code_source(const ast::Node* tree, const ast::QuoteTable& quotes);

}

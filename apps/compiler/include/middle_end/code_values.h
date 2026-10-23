#pragma once

#include <cstdint>
#include <string>
#include <vector>

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
	/// Hemera source for a Code's tree, as code_text gives it.
	/// </summary>
	std::string code_source(const ast::Node* tree, const ast::QuoteTable& quotes);

}

#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

// Laying a whole source file out to the style rules, as hemera-format does.
namespace hemera::formatting {

	/// <summary>The line width code is laid out within (L2), in code points.</summary>
	inline constexpr size_t LINE_WIDTH = 120;

	/// <summary>What format_source made of a file.</summary>
	struct Result {
		/// <summary>
		/// Whether the file lexed and parsed without errors. If not, the errors were reported the usual way,
		/// and text is empty.
		/// </summary>
		bool parsed = false;
		/// <summary>The file laid out, when parsed is true.</summary>
		std::string text;
		/// <summary>
		/// The byte offsets of comments text leaves out, in order: a file with any isn't safe to write back.
		/// </summary>
		std::vector<uint32_t> lost_comments;
	};

	/// <summary>
	/// The line ending source uses, going by its first one: "\r\n" or "\n", and "\n" for a source with none.
	/// </summary>
	std::string_view newline_of(std::string_view source);

	/// <summary>
	/// source, a whole file's bytes, laid out within width columns with its comments kept and its lines ending
	/// as its first one does. file_path names it in errors only. It must be called with a string cache set up,
	/// as lexing needs, and reports errors the usual way, so a thread's reporting scope gets them.
	/// </summary>
	Result format_source(std::string_view source, std::string_view file_path, size_t width = LINE_WIDTH);

}

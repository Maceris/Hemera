#pragma once

#include <cstdint>
#include <initializer_list>
#include <string>
#include <string_view>
#include <vector>

/*
 * A layout document, after Wadler's "A prettier printer": the printer describes code as text, places a
 * line may break and groups that break as one, and the renderer picks the breaks that keep lines within
 * a width. Nothing is laid out until render.
 */
namespace hemera::layout {

	/// <summary>
	/// A part of a Document: an index into it, valid only in the Document that made it. EMPTY prints
	/// nothing, in any Document.
	/// </summary>
	using Doc = uint32_t;
	inline constexpr Doc EMPTY = 0;

	/// <summary>
	/// How many columns UTF-8 text takes: its code points, each one column (L2), whatever its display
	/// width. Bytes that aren't valid UTF-8 count one column each lead byte.
	/// </summary>
	size_t width_of(std::string_view text);

	/// <summary>
	/// What spaces a line break is followed by: 4 per indent (L1), and how far a run of declarations
	/// pads its names is up to the printer.
	/// </summary>
	inline constexpr size_t INDENT_WIDTH = 4;

	/// <summary>
	/// The parts of one layout, made bottom up: a part is made from parts made before it. Every
	/// function returns a new part except where it says, and none fails. A Document isn't safe to use
	/// from more than one thread at once.
	/// </summary>
	class Document {
	public:
		Document();

		/// <summary>
		/// Text that never breaks, copied. It must hold no line break: a break is a line part. Empty text
		/// is EMPTY.
		/// </summary>
		Doc text(std::string_view text);

		/// <summary>A space where its group is flat, and a line break where it's broken.</summary>
		Doc line();

		/// <summary>Nothing where its group is flat, and a line break where it's broken.</summary>
		Doc soft_line();

		/// <summary>
		/// A line break, whatever its group. It doesn't break the groups around it: a group is flat when
		/// what comes before its first line break fits, so a block can follow a call's ( on one line.
		/// </summary>
		Doc hard_line();

		/// <summary>
		/// A line break that's followed by no indent: for text kept as written, which has its own.
		/// </summary>
		Doc literal_line();

		/// <summary>
		/// Breaks every group around it, out to the nearest isolate: for a line comment, which ends its
		/// line wherever it is. Prints nothing.
		/// </summary>
		Doc break_parent();

		/// <summary>
		/// doc, printed just before the next line break instead of here: a trailing comment, which stays
		/// at the end of its line after what follows it on that line, like a comma. Its width counts
		/// towards the line it ends.
		/// </summary>
		Doc line_suffix(Doc doc);

		/// <summary>The parts one after another; EMPTY ones are left out, and none at all is EMPTY.</summary>
		Doc concat(std::initializer_list<Doc> parts);
		Doc concat(const std::vector<Doc>& parts);

		/// <summary>doc, with the line breaks in it indented INDENT_WIDTH more. EMPTY stays EMPTY.</summary>
		Doc indent(Doc doc);

		/// <summary>
		/// doc, flat if it fits on the rest of the line up to its first line break, and broken if not,
		/// or if a break_parent is in it. Groups in it decide for themselves once it's broken. EMPTY stays
		/// EMPTY.
		/// </summary>
		Doc group(Doc doc);

		/// <summary>broken where the group it's in is broken, and flat where it's flat.</summary>
		Doc if_break(Doc broken, Doc flat = EMPTY);

		/// <summary>
		/// Items packed onto as few lines as fit (B8): parts alternate an item and the separator after
		/// it, item first. A separator is flat, usually a space, where the item after it fits on the line,
		/// and broken where it doesn't or where the item before it holds a break_parent, like a line
		/// comment's. An item is laid out flat unless it can't fit on a line of its own.
		/// </summary>
		Doc fill(const std::vector<Doc>& parts);

		/// <summary>
		/// doc laid out flat wherever it is: the groups in it never break and its lines are spaces, though
		/// hard and literal lines still break. For what reads as one, like a type or a name. EMPTY stays
		/// EMPTY.
		/// </summary>
		Doc flat(Doc doc);

		/// <summary>
		/// doc, keeping the break_parents in it from breaking the groups around it: a block's statements
		/// are lines of their own, whatever comments they hold. EMPTY stays EMPTY.
		/// </summary>
		Doc isolate(Doc doc);

		/// <summary>
		/// Whether doc holds a break_parent that reaches its groups, so a group made of it is broken.
		/// </summary>
		bool breaks(Doc doc) const;

		/// <summary>
		/// The columns doc takes printed flat on one line, or SIZE_MAX if it holds a line break that can't
		/// be flat: a hard or literal line, or a break_parent.
		/// </summary>
		size_t flat_width(Doc doc) const;

		/// <summary>
		/// doc laid out within width columns where it can be, each line break written as newline: lines
		/// that can't fit, like a long name, run over. No line ends in spaces the layout added. width is
		/// SIZE_MAX for no limit, which lays every group out flat.
		/// </summary>
		std::string render(Doc doc, size_t width, std::string_view newline = "\n") const;

	private:
		enum class Kind : uint8_t {
			EMPTY,
			TEXT,
			LINE,
			SOFT_LINE,
			HARD_LINE,
			LITERAL_LINE,
			BREAK_PARENT,
			LINE_SUFFIX,
			CONCAT,
			INDENT,
			GROUP,
			IF_BREAK,
			FILL,
			ISOLATE,
			FLAT,
		};

		/*
		 * A part: TEXT's first and count are a range of text, CONCAT's and FILL's a range of children, and
		 * the others' first (and IF_BREAK's count, its flat part) the parts they hold. breaks says whether
		 * a break_parent in it reaches out of it.
		 */
		struct Part {
			Kind kind;
			bool breaks;
			uint32_t first;
			uint32_t count;
			uint32_t width;
		};

		/*
		 * A part to print or measure: at indent columns, flat or broken as its group is, and for a FILL,
		 * from its from'th child on. forced is for what a flat part holds, which is flat whatever fits.
		 */
		struct Command {
			size_t indent;
			bool flat;
			Doc doc;
			uint32_t from;
			bool forced;

			Command(size_t indent, bool flat, Doc doc, uint32_t from, bool forced = false)
				: indent{ indent }
				, flat{ flat || forced }
				, doc{ doc }
				, from{ from }
				, forced{ forced }
			{}
		};

		Doc add(Part part);
		bool fits(const std::vector<Command>& next, const std::vector<Command>& rest, int64_t width, bool must_be_flat) const;

		std::vector<Part> parts;
		std::vector<Doc> children;
		std::string texts;
	};

}

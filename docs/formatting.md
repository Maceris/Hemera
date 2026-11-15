# Formatting

| Item         | Format               | Examples                        |
|--------------|----------------------|---------------------------------|
| Constant     | SCREAMING_SNAKE_CASE | COMMAND_SIZE, DEFAULT_COLOR     |
| Enum Member  | SCREAMING_SNAKE_CASE | PENDING_REMOVAL, R32G32B32_UINT |
| Function     | snake_case           | feet_to_meters, square_root     |
| Package      | snake_case           | engine, priority_queue          |
| Struct       | PascalCase           | MeshData, SampledSpectrum       |
| Enum         | PascalCase           | ImageFormat, MaterialFlag       |
| Union        | PascalCase           | NodeType, MessageType           |
| Union Member | PascalCase           | ArgumentList, LeafNode          |
| Variable     | snake_case           | first_item, cached_width        |

Identifiers are [UAX #31](https://www.unicode.org/reports/tr31/)'s default identifiers, so they can be in any script:
they start with a letter (a code point with XID_Start, like `a`, `Ж` or `日`), and go on with letters, digits, `_` and
combining marks (XID_Continue, like `1`, `_`, `١` or U+0301). An identifier can't start with a digit or `_`. Default
ignorable code points, which can't be seen, like the zero width joiner, aren't in identifiers at all.

An identifier must already be in Unicode's Normalization Form KC ([UAX #15](https://www.unicode.org/reports/tr15/)),
so every identifier has one spelling, in bytes, and two that look the same are the same: `é` is U+00E9, not `e` and a
combining acute (U+0301), and `fi` is two letters, not the ligature `ﬁ`. One that isn't is an error (E2011) that gives its
NFKC spelling. An ASCII identifier always is.

Identifiers outside ASCII are also checked as [UTS #39](https://www.unicode.org/reports/tr39/) recommends, once a
package is read, with a warning for each identifier, where it's first used. A package that uses scripts this way on
purpose allows the warning in its `package_info.hsc`
([Allowing and Denying Warnings](compilation.md#allowing-and-denying-warnings)):

* **Looks like another (W2000).** Two different identifiers in a package, in one file or two, that look alike: their
  skeletons, with each character replaced by what it's most easily mistaken for, are the same. Like `cop` and `сор`,
  whose letters are Cyrillic. The warning is on the one used later, or the one outside ASCII.
* **Mixes scripts (W2001).** An identifier with letters of more than one script, beyond UTS #39's Highly Restrictive
  level, like `total_итог`, Latin and Cyrillic. One script is fine, as is Latin with Han, Hiragana and Katakana, with Han
  and Bopomofo, or with Han and Hangul; digits, `_` and marks that go with any script count as every script's.
* **Uncommon character (W2002).** An identifier with a character UTS #39 doesn't recommend for identifiers
  (Identifier_Status isn't Allowed), like the obsolete scripts Runic and Ogham, or technical and limited-use ones.

The tables are generated from the Unicode Character Database, of the same version as `std:unicode`'s, by
`std/unicode/_generator/generate_identifiers.py`, and for these checks, with UTS #39's data (confusables and
identifier status), by `std/unicode/_generator/generate_identifier_security.py`.

Identifiers may not be the same as [reserved keywords](keywords.md); [contextual keywords](keywords.md#contextual-keywords) and the names of [builtin types](types.md) can be used, though a builtin type's name hides the type.

## Lists

Commas at the ends of lists (below) are optional. They can be there, or they could be left off.

* structs
* enums
* unions
* struct literals that specify fields by name
* `push_context` field overrides

This is to enable definitions of things to be reordered or modified without having to fiddle with adding or removing commas.

# File Contents

The source files are UTF-8 encoded text files, whatever the system's code page. Bytes that aren't UTF-8 are an error
(E2008): a stray continuation byte, a sequence cut short, an overlong form, a surrogate or a code point past U+10FFFF. A
byte order mark at the start of a file is skipped.

The characters that change the order text is displayed in without being seen (Unicode's bidirectional controls: U+061C,
U+200E, U+200F, U+202A to U+202E and U+2066 to U+2069) are an error anywhere in a file, comments and strings included
(E2009), as they can make code look different from how it compiles. A string that needs one writes it as an escape,
like `"\u{202E}"` ([Strings](types.md#strings)).

There are restrictions on the size of the files, both in terms of line width and number of lines (and consequently, the total size).

These are:

* Lines may not be longer than 65,535 (u16 max) characters
* There may not be more than 4,294,967,295 (u32 max) lines in a single file

Brief rationalizations for these limits:

Most editors and developers have soft line limits at around 80 to 120 characters, so if you have lines longer than 65,000... don't.
Most files should not be longer than a couple thousand lines, but situations might call for a large amount of text in one file so the limits on total lines are higher.

# File Structure

The code file structure as below:

1. Optional beginning comments
2. Package statement (first non-comment non-empty line)
3. Imports
4. Declarations / definitions (all immutable)

For example:

```
/*
 * Copyright notice should go here.
 */

package name_goes_here

import other_package

EXAMPLE_CONSTANT :: 43

example_function :: fn(x : int) -> int {
    return EXAMPLE_CONSTANT + x
}

ExampleStruct :: struct {
    x : f32,
    y : f32,
}
```

# The Formatter

`hemera-format` lays files out the one way Hemera code is written: 4-space indents, lines of at most 120 characters
(code points), and the spacing, line breaks, blank lines and comment layout below. It's built beside the compiler from
the compiler's own lexer, parser and printer, so it never changes what code means: it only parses, without checking,
and a file that doesn't parse is left as it is, with the parser's errors. There's nothing to configure.

```bash
hemera-format path/to/file.hsc
hemera-format --check path/to/folder
hemera-format --write path/to/folder
```

With no path, it formats standard input to standard output. A path is a file or a folder, whose `.hsc` files are all
formatted, folders inside it too, several at once. `--check` writes nothing and lists the files that would change;
`--write` writes them. Without either, one file goes to standard output. `--threads=N` formats N files at once,
rather than one per processor. It exits with 0 when every file was already formatted or was written, 1 when `--check`
found one that would change, and 2 for an error, which leaves that file as it was. A file keeps its line endings, going
by its first one.

What it does:

* A line that doesn't fit breaks at the outermost place it can: an argument, parameter or struct literal list puts an
  item to a line, indented, with the closing bracket on a line of its own; a run of `&&`, `+` and the like breaks before
  each operator, continuing 4 spaces deeper. Lines broken by hand that fit are joined again.
* A struct literal, struct, enum, union or `push_context` list broken over lines has a comma after its last item.
* An array of numbers that doesn't fit packs as many to a line as fit.
* `else` starts a line of its own after the `}`. An `if` whose value is used, with a single expression in each block,
  stays on one line where it fits, as does a `case` with one statement.
* One space each side of `::`, `:=`, `=`, `->`, `=>`, binary operators and the `:` of `name : Type`, parameters
  included; none inside brackets or in ranges.
* 4 or more similar declarations in a row (constants, struct fields, enum members) line up their `:`, `::` and `=`, as
  long as no line is padded by more than 30 spaces. A blank line or a comment on its own line ends a run.
* Imports are sorted by location (`base:`, `std:`, `user:`, `vendor:`, then relative folders), then the location's
  path, then name. There's one blank line between the file's leading comments, its package statement, its imports and
  its declarations; elsewhere, blank lines stay where they were, at most one in a row.
* A line comment has one space after its `//`, and a run of them on lines of their own becomes one `/* */` block. A
  block comment of several lines opens and closes on lines of its own, with a `*` starting each line in between. A
  comment is indented with its code, and its lines that end up past 120 characters are broken, a block tag's
  continuation indented 4 spaces past its `@`; code examples, list items, table rows and URLs aren't. A one-line
  comment on a line of its own that ends up past 120 becomes a block comment, `/**` if it was one, and is broken the
  same way, unless it holds a `/*` or `*/`; one after code on its line stays as it is. Block tags go in the order
  `@tparam`, `@param`, `@return`, `@error`.

The lines between `// hemera-format: off` and `// hemera-format: on` (or the end of the file) are kept exactly as they
were written, for a table laid out by hand.

`compiler.code_text` and `--show-inserted` show code laid out the same way.



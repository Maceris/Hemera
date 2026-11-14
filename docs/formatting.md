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
NFKC spelling. An ASCII identifier always is. The tables are
generated from the Unicode Character Database, of the same version as `std:unicode`'s, by
`std/unicode/_generator/generate_identifiers.py`.
Identifiers may not be the same as [reserved keywords](keywords.md); [contextual keywords](keywords.md#contextual-keywords) and the names of [builtin types](types.md) can be used, though a builtin type's name hides the type.

## Lists

Commas at the ends of lists (below) are optional. They can be there, or they could be left off.

* structs
* enums
* unions
* match expressions
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

example_function :: fn(x: int) -> int {
    return EXAMPLE_CONSTANT + x
}

ExampleStruct :: struct {
    x : f32,
    y : f32,
}
```



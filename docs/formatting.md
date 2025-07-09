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

The only valid characters for identifiers are alphanumeric characters ([a-z], [A-Z], [0-9]) and underscore ('_'), and must start with a letter.
Identifiers may not be the same as [reserved keywords](keywords.md) or [builtin types](types.md).

## Lists

Commas at the ends of lists (below) are optional. They can be there, or they could be left off.

* structs
* enums
* unions
* match expressions
* struct literals that specify fields by name

This is to enable definitions of things to be reordered or modified without having to fiddle with adding or removing commas.

# File Contents

The source files are utf-8 encoded text files. There are restrictions on the size of the files, both in terms of line width and number of lines (and consequently, the total size).

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



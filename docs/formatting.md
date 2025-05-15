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

# File Structure

The official recommended file structure as below:

1. Optional beginning comments
2. Package statement (first non-comment non-empty line)
3. Imports
4. Declarations

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



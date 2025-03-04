# Formatting

| Item                  | Format               | Examples                        | Allowed, unless reserved |
|--------------|----------------------|---------------------------------|--------------------------|
| Constant     | SCREAMING_SNAKE_CASE | COMMAND_SIZE, DEFAULT_COLOR     | `[a-zA-Z0-9_]+`          |
| Enum Member  | SCREAMING_SNAKE_CASE | PENDING_REMOVAL, R32G32B32_UINT | `[a-zA-Z0-9_]+`          |
| Function     | snake_case           | feet_to_meters, square_root     | `[a-zA-Z0-9_]+`          |
| Package      | snake_case           | engine, priority_queue          | `[a-z]+[a-z0-9_]*`       |
| Struct       | PascalCase           | MeshData, SampledSpectrum       | `[a-zA-Z]+[a-zA-Z0-9_]*` |
| Enum         | PascalCase           | ImageFormat, MaterialFlag       | `[a-zA-Z]+[a-zA-Z0-9_]*` |
| Union        | PascalCase           | NodeType, MessageType           | `[a-zA-Z]+[a-zA-Z0-9_]*` |
| Union Member | PascalCase           | ArgumentList, LeafNode          | `[a-zA-Z0-9_]+`          |
| Variable     | snake_case           | first_item, cached_width        | `[a-zA-Z0-9_]+`          |

Names may not be the same as reserved keywords, or builtin types.


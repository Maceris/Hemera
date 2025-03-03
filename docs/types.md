# Types

Hemera has several built in primitive types.


| Type    | Description                                                                                                                                  |
|---------|----------------------------------------------------------------------------------------------------------------------------------------------|
| any     | References a data type, includes a pointer and its typeid                                                                                    |
| b8      | 8-bit boolean                                                                                                                                |
| b16     | 16-bit boolean                                                                                                                               |
| b32     | 32-bit boolean                                                                                                                               |
| b64     | 64-bit boolean                                                                                                                               |
| bool    | Boolean value (true or false), equivalent to b8                                                                                              |
| c16     | 16-bit complex number, composed of 2 i8 values                                                                                               |
| c32     | 32-bit complex number, composed of 2 i16 values                                                                                              |
| c64     | 64-bit complex number, composed of 2 i32 values                                                                                              |
| c128    | 128-bit complex number, composed of 2 i128 values                                                                                            |
| cstring | C-style null-terminated string                                                                                                               |
| f16     | 16-bit (half-precision) IEEE-754 floating point number                                                                                       |
| f32     | 32-bit (single-precision) IEEE-754 floating point number                                                                                     |
| f64     | 64-bit (double-precision) IEEE-754 floating point number                                                                                     |
| i8      | 8-bit signed integer                                                                                                                         |
| i16     | 16-bit signed integer                                                                                                                        |
| i32     | 32-bit signed integer                                                                                                                        |
| i64     | 64-bit signed integer                                                                                                                        |
| int     | Signed integer that is the standard size of a register on the system, guaranteed that size_of(int) >= size_of(uintptr). Same size as uint.   |
| ptr     | A typed pointer                                                                                                                              |
| q32     | 32-bit quaternion, composed of 4 i8 values                                                                                                   |
| q64     | 64-bit quaternion, composed of 4 i16 values                                                                                                  |
| q128    | 128-bit quaternion, composed of 4 i32 values                                                                                                 |
| q256    | 256-bit quaternion, composed of 4 i64 values                                                                                                 |
| rawptr  | Pointer to an arbitrary type, equivalent to C's void *                                                                                       |
| string  | String that includes a length, not null-terminated                                                                                           |
| typeid  | Information about a type                                                                                                                     |
| u8      | 8-bit unsigned integer                                                                                                                       |
| u16     | 16-bit unsigned integer                                                                                                                      |
| u32     | 32-bit unsigned integer                                                                                                                      |
| u64     | 64-bit unsigned integer                                                                                                                      |
| uint    | Unsigned integer that is the standard size of a register on the system, guaranteed that size_of(uint) >= size_of(uintptr). Same size as int. |
| uintptr | Unsigned integer that is large enough to hold the bit pattern of any pointer                                                                 |


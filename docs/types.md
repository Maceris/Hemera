# Types

Hemera has quite a few built-in primitive types.

```
// Boolean types
b8 b16 b32 b64 bool

// Integers
i8 i16 i32 i64 i128 int // Signed
u8 u16 u32 u64 u128 uint uintptr // Unsigned

// Floating point numbers
f16 f32 f64

// Complex numbers
c16 c32 c64 c128

// Quaternions
q32 q64 q128 q256

// Endian specific integers
i16be i32be i64be i128be u16be u32be u64be u128be // big endian
i16le i32le i64le i128le u16le u32le u64le u128le // little endian

// Endian specific floating point numbers
f16be f32be f64be // big endian
f16le f32le f64le // little endian

// Strings
string cstring

// Pointers
ptr rawptr

// Type related
any type
```

More details:

| Type    | Description                                                                                                                                  |
|---------|----------------------------------------------------------------------------------------------------------------------------------------------|
| any     | References a data type, includes a pointer and its type                                                                                      |
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
| f16be   | 16-bit (half-precision) IEEE-754 floating point number, big endian                                                                           |
| f16le   | 16-bit (half-precision) IEEE-754 floating point number, little endian                                                                        |
| f32     | 32-bit (single-precision) IEEE-754 floating point number                                                                                     |
| f32be   | 32-bit (single-precision) IEEE-754 floating point number, big endian                                                                         |
| f32le   | 32-bit (single-precision) IEEE-754 floating point number, little endian                                                                      |
| f64     | 64-bit (double-precision) IEEE-754 floating point number                                                                                     |
| f64be   | 64-bit (double-precision) IEEE-754 floating point number, big endian                                                                         |
| f64le   | 64-bit (double-precision) IEEE-754 floating point number, little endian                                                                      |
| i8      | 8-bit signed integer                                                                                                                         |
| i16     | 16-bit signed integer                                                                                                                        |
| i16be   | 16-bit signed integer, big endian                                                                                                            |
| i16le   | 16-bit signed integer, little endian                                                                                                         |
| i32     | 32-bit signed integer                                                                                                                        |
| i32be   | 32-bit signed integer, big endian                                                                                                            |
| i32le   | 32-bit signed integer, little endian                                                                                                         |
| i64     | 64-bit signed integer                                                                                                                        |
| i64be   | 64-bit signed integer, big endian                                                                                                            |
| i64le   | 64-bit signed integer, little endian                                                                                                         |
| i128    | 128-bit signed integer                                                                                                                       |
| i128be  | 128-bit signed integer, big endian                                                                                                           |
| i128le  | 128-bit signed integer, little endian                                                                                                        |
| int     | Signed integer that is the standard size of a register on the system, guaranteed that size_of(int) >= size_of(uintptr). Same size as uint.   |
| ptr     | A typed pointer                                                                                                                              |
| q32     | 32-bit quaternion, composed of 4 i8 values                                                                                                   |
| q64     | 64-bit quaternion, composed of 4 i16 values                                                                                                  |
| q128    | 128-bit quaternion, composed of 4 i32 values                                                                                                 |
| q256    | 256-bit quaternion, composed of 4 i64 values                                                                                                 |
| rawptr  | Pointer to an arbitrary type, equivalent to C's void *                                                                                       |
| string  | String that includes a length, not null-terminated                                                                                           |
| type    | Information about a type                                                                                                                     |
| u8      | 8-bit unsigned integer                                                                                                                       |
| u16     | 16-bit unsigned integer                                                                                                                      |
| u16be   | 16-bit unsigned integer, big endian                                                                                                          |
| u16le   | 16-bit unsigned integer, little endian                                                                                                       |
| u32     | 32-bit unsigned integer                                                                                                                      |
| u32be   | 32-bit unsigned integer, big endian                                                                                                          |
| u32le   | 32-bit unsigned integer, little endian                                                                                                       |
| u64     | 64-bit unsigned integer                                                                                                                      |
| u64be   | 64-bit unsigned integer, big endian                                                                                                          |
| u64le   | 64-bit unsigned integer, little endian                                                                                                       |
| u128    | 128-bit unsigned integer                                                                                                                     |
| u128be  | 128-bit unsigned integer, big endian                                                                                                         |
| u128le  | 128-bit unsigned integer, little endian                                                                                                      |
| uint    | Unsigned integer that is the standard size of a register on the system, guaranteed that size_of(uint) >= size_of(uintptr). Same size as int. |
| uintptr | Unsigned integer that is large enough to hold the bit pattern of any pointer                                                                 |

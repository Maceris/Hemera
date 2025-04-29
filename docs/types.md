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
relptr8 relptr16 relptr32 relptr64

// Type related
any type
```

More details:

| Type     | Description                                                                                                                                  |
|----------|----------------------------------------------------------------------------------------------------------------------------------------------|
| any      | References a data type, includes a pointer and its type                                                                                      |
| b8       | 8-bit boolean                                                                                                                                |
| b16      | 16-bit boolean                                                                                                                               |
| b32      | 32-bit boolean                                                                                                                               |
| b64      | 64-bit boolean                                                                                                                               |
| bool     | Boolean value (true or false), equivalent to b8                                                                                              |
| c16      | 16-bit complex number, composed of 2 i8 values                                                                                               |
| c32      | 32-bit complex number, composed of 2 i16 values                                                                                              |
| c64      | 64-bit complex number, composed of 2 i32 values                                                                                              |
| c128     | 128-bit complex number, composed of 2 i128 values                                                                                            |
| char     | Single character, in utf-8                                                                                                                   |
| cstring  | C-style null-terminated string                                                                                                               |
| f16      | 16-bit (half-precision) IEEE-754 floating point number                                                                                       |
| f16be    | 16-bit (half-precision) IEEE-754 floating point number, big endian                                                                           |
| f16le    | 16-bit (half-precision) IEEE-754 floating point number, little endian                                                                        |
| f32      | 32-bit (single-precision) IEEE-754 floating point number                                                                                     |
| f32be    | 32-bit (single-precision) IEEE-754 floating point number, big endian                                                                         |
| f32le    | 32-bit (single-precision) IEEE-754 floating point number, little endian                                                                      |
| f64      | 64-bit (double-precision) IEEE-754 floating point number                                                                                     |
| f64be    | 64-bit (double-precision) IEEE-754 floating point number, big endian                                                                         |
| f64le    | 64-bit (double-precision) IEEE-754 floating point number, little endian                                                                      |
| i8       | 8-bit signed integer                                                                                                                         |
| i16      | 16-bit signed integer                                                                                                                        |
| i16be    | 16-bit signed integer, big endian                                                                                                            |
| i16le    | 16-bit signed integer, little endian                                                                                                         |
| i32      | 32-bit signed integer                                                                                                                        |
| i32be    | 32-bit signed integer, big endian                                                                                                            |
| i32le    | 32-bit signed integer, little endian                                                                                                         |
| i64      | 64-bit signed integer                                                                                                                        |
| i64be    | 64-bit signed integer, big endian                                                                                                            |
| i64le    | 64-bit signed integer, little endian                                                                                                         |
| i128     | 128-bit signed integer                                                                                                                       |
| i128be   | 128-bit signed integer, big endian                                                                                                           |
| i128le   | 128-bit signed integer, little endian                                                                                                        |
| int      | Signed integer that is the standard size of a register on the system, guaranteed that size_of(int) >= size_of(uintptr). Same size as uint.   |
| ptr      | A typed pointer                                                                                                                              |
| q32      | 32-bit quaternion, composed of 4 i8 values                                                                                                   |
| q64      | 64-bit quaternion, composed of 4 i16 values                                                                                                  |
| q128     | 128-bit quaternion, composed of 4 i32 values                                                                                                 |
| q256     | 256-bit quaternion, composed of 4 i64 values                                                                                                 |
| rawptr   | Pointer to an arbitrary type, equivalent to C's void *                                                                                       |
| relptr8  | 8-bit pointer which points relative to its own address                                                                                       |
| relptr16 | 16-bit pointer which points relative to its own address                                                                                      |
| relptr32 | 32-bit pointer which points relative to its own address                                                                                      |
| relptr64 | 64-bit pointer which points relative to its own address                                                                                      |
| string   | String that includes a length, not null-terminated, in utf-8                                                                                 |
| type     | Information about a type                                                                                                                     |
| u8       | 8-bit unsigned integer                                                                                                                       |
| u16      | 16-bit unsigned integer                                                                                                                      |
| u16be    | 16-bit unsigned integer, big endian                                                                                                          |
| u16le    | 16-bit unsigned integer, little endian                                                                                                       |
| u32      | 32-bit unsigned integer                                                                                                                      |
| u32be    | 32-bit unsigned integer, big endian                                                                                                          |
| u32le    | 32-bit unsigned integer, little endian                                                                                                       |
| u64      | 64-bit unsigned integer                                                                                                                      |
| u64be    | 64-bit unsigned integer, big endian                                                                                                          |
| u64le    | 64-bit unsigned integer, little endian                                                                                                       |
| u128     | 128-bit unsigned integer                                                                                                                     |
| u128be   | 128-bit unsigned integer, big endian                                                                                                         |
| u128le   | 128-bit unsigned integer, little endian                                                                                                      |
| uint     | Unsigned integer that is the standard size of a register on the system, guaranteed that size_of(uint) >= size_of(uintptr). Same size as int. |
| uintptr  | Unsigned integer that is large enough to hold the bit pattern of any pointer                                                                 |

## Notes On Types

For boolean values, `true` is stored as `1`, and `false` is stored as `0`.

## Number Formats

Integers can be written as 

* Decimal format, using the digits (0, 1, 2, 3, 4, 5, 6, 7, 8, 9)
* Hex format, with the prefix `0x` followed by  one or more hex digits (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, a, A, b, B, c, C, d, D, e, E, f, F)
* Octal format, with the prefix `0o` followed by one or more octal digits (0, 1, 2, 3, 4, 5, 6, 7)
* Binary format, with the prefix `0b` followed by one or more binary digits (0, 1)

Any format can use underscores (`_`) freely between digits, they are ignored.

## Optional Types

Any type can be represented as an optional by appending a `?` to the type name.
This is only equivalent to a nullable type, albeit `null` still exists for `rawptr`'s.

For example `i32?` is a type that either contains an `i32`, or does not.
This works for any built-in or user-defined type.

This is a built-in union type similar to this structure, where `Optional<Foo>` is equivalent to `Foo?`:

```
Optional :: union<T> {
    None,
    Some(T),
}
```

There are a few [operators built in](operators.md#optional-operators) to make life easier when dealing with optional values.

## Pointers

Pointer types (besides `rawptr`) refer to the type they point to in angle brackets. For example, `ptr<int>` is a pointer to an int.

```
ptr<ptr<int>> pointer to a pointer to an int
ptr<int[3]>   pointer to an array of 3 ints
ptr<int>[3]   array of 3 pointers to ints
relptr8<int>  8-bit relative pointer to an int
```

Relative pointers refer to an address relative to their own, and have different sizes.
An 8-bit relative pointer is quite small, but can only refer to things 128 bytes below and 127 bytes above their own address.

## Strings

There are 2 formats for strings. Strings can be enclosed in quotes like `"This is a string"`, or may be multiline strings.

For multiline strings, each line starts with a double-backslash (`\\`)

```
example : string : 
    \\ this is a multiline string
    \\ each line of the string maintains indentation after
    \\ the backslashes, but ignores any indentation before them
    \\ so these won't mess up function indentation
```

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

## Arrays

There are a few types of arrays.

### Static arrays

Static arrays have a fixed size. They are accessed using `[]` subscript syntax.

```
a : int[5]    // Array of 5 ints
b : f64[2]    // Array of 2 f64s
c : i8[10][5] // 2D array of i8s
```

Arrays know their size, and you can access it with `array.count`.

### Dynamic arrays

Dynamic arrays are resizable, allocating more memory as needed. It behaves
similarly to the C++ `std::vector`, but using the current context's allocator.

```
a : int[..]    // Dynamic array of ints
b : string[..] // Dynamic array of strings
```

Dynamic arrays know their size, and also have a capacity that can be accessed with `array.capacity`.

### Array views

Array views represent a view into data stored in an array, or a subsection of one.

```
a : int[]
```

Both static and dynamic arrays will be autocast to array views if 
provided to a function with an array view parameter.

The range operators can be used to grab a view from indexes in an array.

```
a : int[10]
b : int[] : a        // Works fine, view over the whole array
c : int[] : a[2..<5] // View over the indices 2, 3, and 4 (as it excludes 5)
d : int[] : a[2..=4] // View over the indices 2, 3, and 4 (as it includes 4)

e : int[] : a[5..]   // View over the index 5, and everything after
e2: int[] : a[5..<a.count] // Equivalent to e

f : int[] : a[..<5]  // View over everything up to index 5, exclusive
f2 : int[] : a[0..<5]  // Equivalent to f

g : int[] : a[..=5]  // View over everything up to index 5, inclusive
g2 : int[] : a[0..=5]  // Equivalent to g
```

### Bounds checking

When directly indexing into arrays, the index must be proven to be within the bounds of the array.

```
foo :: fn(resizable: i8[..], view: i8[], fixed: i8[5], unknown: u64) {
    known : u64 = 4
    over :: 5
    result : i8

    // invalid
    // result = resizable[known] // Didn't check the bounds
    // result = resizable[unknown] // Unknown bounds, and didn't check
    // result = fixed[over] // Provably outside the bounds
    
    // fine
    if (known <= resizable.count) { // don't know the count
        result = resizable[known] // Checked the bounds
    }
    result = fixed[known] // Provably in bounds
    if (unknown >= fixed.count) {
        return
    }
    result = fixed[unknown] // Can't reach here if it would go out of bounds

    // All automatically fine, loops know the bounds
    for i in resizable {
        print(i)
    }
    for i, index in view {
        print(i)
        print(index)
    }
    for i in fixed {
        print(i)
    }
}
```

When providing bounds for slices, they must not extend outside the bounds of the array, or it is a compile-time error.

```
foo :: fn(resizable: i8[..], fixed: i8[10]) {
    result : i8[]
    a :: 2
    b :: 5

    // invalid
    // result = resizable[2..<5] // Don't know the size

    // fine
    result = resizable[0..<resizable.count] // But same as result = resizable
    result = fixed[2..<5] // Known to be in bounds
    result = fixed[a..=b] // Known to be in bounds

    if (a < resizable.count && b < resizable.count) {
        result = resizable[a..<b] // We checked that it's fine
    }
}
```

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

There is no pointer arithmetic on regular pointers, though raw pointers and relative pointers (being closer to integers) do allow it.

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

## Type Aliases

Any type can be given an alias using the `alias` keyword.
Adding the `distinct` keyword tells the compiler to treat this as an entirely different type.

```
feet   :: distinct alias f32
meters :: distinct alias f32

meters_to_feet :: fn(m: meters) -> feet {
    // this wouldn't compile, cannot convert implicitly
    // example : feet : m

    // But this works fine, compiler knows the backing types
    return auto_cast(m * 3.28084)
}
```

If the type is not distinct, `alias` is not required, for example these are fine:

```
my_int :: i32
more_verbose : type : i32
```

# Types

Hemera has quite a few built-in primitive types.

```
// Boolean types
b8 b16 b32 b64 bool

// Integers
i8 i16 i32 i64 i128 int // Signed
u8 u16 u32 u64 u128 uint uintptr usize // Unsigned

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
| uintptr  | Unsigned integer that is large enough to hold the bit pattern of any pointer, the same size as a standard pointer on that system.            |
| usize    | Unsigned integer that is the same size as uintptr, used for sizes and counts.                                                                |

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

Both static and dynamic arrays will be auto-cast to array views if 
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
foo :: fn(resizable: i8[..], view: i8[], fixed: i8[5], unknown: usize) {
    known : usize = 4
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

## Enums

Enums represent a set of distinct values.

```
Suit :: enum {
    Clubs,
    Hearts,
    Spades,
    Diamonds,
}
```

Enum values can be accessed in an abbreviated way if the type can be inferred, using a syntax like `.EnumValue`. For example, `suit : Suit = .Clubs`.

Enums are backed by a `uint` by default, but `#backed_by(x)` can be used used to specify the backing type, where `x` must be one of the unsigned integer types (u8, u16, u32, u64, u128). For example:

```
Suit :: enum #backed_by(u8) {
    Clubs,
    Hearts,
    Spades,
    Diamonds,
}
```

## Implicit Casting

Some types will implicitly (automatically) cast to each other, without having to manually add in casts.
Generally speaking, widening conversion are fine and narrowing ones are not.

Will implicitly cast:

* i8, i16, i32, i64 will cast up to signed integers of a larger size, or int
* u8, u16, u32, u64 will cast up to unsigned integers of a larger size, or uint
* The endian-specific versions of integers will cast up to larger fixed sizes of the same endianness and signed-ness
* Floating point types will cast to larger versions
* The endian-specific versions of floating point types will cast up to larger versions of the same endianness
* b8, b16, b32, b64 will cast up to booleans of a larger size
* uintptr and usize will cast to uint
* Structs will implicitly cast to any structs included inside with the `using` keyword

Will not implicitly cast:

* i128 won't implicitly cast to int, other than on a hypothetical 128-bit platform
* u128 won't implicitly cast to uint, other than on a hypothetical 128-bit platform
* uintptr will not implicitly cast to or from usize
* Complex numbers will not implicitly cast between sizes
* Quaternions will not implicitly cast between sizes

## Notes On Types

For boolean values, `true` is stored as `1`, and `false` is stored as `0`.

All types are initialized to zero, unless the symbol `---` is used, which indicates that a value should remain uninitialized. For example, `x : ComplicatedType[100] = ---`.

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

This is a built-in union type similar to this structure, where `Optional[Foo]` is equivalent to `Foo?`:

```
Optional :: union[T] {
    Some(T),
    None,
}
```

There are a few [operators built in](operators.md#optional-operators) to make life easier when dealing with optional values.

## Pointers

Pointer types (besides `rawptr`) refer to the type they point to in square brackets. For example, `ptr[int]` is a pointer to an int.

```
ptr[ptr[int]] pointer to a pointer to an int
ptr[int[3]]   pointer to an array of 3 ints
ptr[int][3]   array of 3 pointers to ints
relptr8[int]  8-bit relative pointer to an int
```

Relative pointers refer to an address relative to their own, and have different sizes.
An 8-bit relative pointer is quite small, but can only refer to things 128 bytes below and 127 bytes above their own address.

There is no pointer arithmetic on regular pointers, though raw pointers and relative pointers (being closer to integers) do allow it.

## Result Types

Results are built in, defined like this:

```
Result :: union[T, E] {
    Ok(T),
    Error(E),
}
```

There are a few [operators built in](operators.md#result-operators) to make life easier when dealing with result values.

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

## Structs

Structs are user defined groups of data. Structs cannot have any "private" fields, everything is public. Members are accessed using the `.` operator.

Structs do not have any methods or member functions, though they can store functions as a member since they are first-class entities.

All values are initialized to zero, except where default values are provided for a field.

```
Rectangle :: struct {
	x : int,
	y : int,
	width : uint = 10,
	height : uint = 10,
}
```

Structs can be created on the stack as a literal, or on the heap using `new`. The literal is the struct's type, followed by `.{}`.

```
r: Rectangle
r = Rectangle.{} // Zero/default values
r = Rectangle.{1, 2, 10, 10} // All values must be provided, in order, if any are provided
// Subsets of fields can be used, others are left with their default values
// Order is not important here
r = Rectangle.{y=2, x=1}

r2 : ptr[Rectangle] = new(Rectangle)
r2^ = r
```

Structs can also be included in other structs, including all the fields and allowing implicit casting.

```
MyVec2 :: struct {
    x : f32,
    y : f32,
}

MyVec3 :: struct {
    using MyVec2, // Includes x, and y
    z : f32,
}

vec_length :: fn(v : MyVec2) -> f32 {
    return sqrt(v.x * v.x + v.y * v.y)
}

foo :: fn() {
    vec3 : MyVec3 = Vec3.{1, 2, 3}
    // Works fine, since it contains the vec2 fields explicitly
    vec_length(vec3)
}
```

Anonymous structs can be defined in another struct by defining them with the `_` name/operator:

```
Foo :: struct {
    // x, y, and z are fields of Foo now
    _ : struct { x, y, z : f32 }
    w : f32,
}

// The above is equivalent to this

Bar :: struct {
    x, y, z : f32
}

Foo :: struct {
    using Bar,
    w : f32,
}
```

This is most useful if you want to manipulate things like padding and alignment for just a few fields, or for C-style unions.

To use structs as C-style unions, the `#union` directive can be used.

```
Vector3 :: struct #union {
    _ : struct { x, y, z: f32 },
    _ : struct { r, g, b: f32 },
    _ : struct { s, t, p: f32 },
}

// Vector3 is now the size of one struct containing 3 f32's, but there are 3 different names for each float.

v1 := Vector3.{}
v1.x = 5 // r and s are now also 5, they share the same offset
v1.y = 2 // g and t are now also 2
```

The `using` directive works as well if structs are already defined.

```
Floats :: struct #packed { 
    f1, f2 : f32
}

MoreComplex :: struct #union {
    a : i32,
    _ : struct #packed { b1, b2 : i16 }
    c : Floats,
    using Floats,
    d : u64,
}
```

Below is a breakdown of the locations that each variable would refer to in MoreComplex.

```
|            bits              |
| 0-15 | 16-31 | 32-47 | 48-63 |
|------|-------|-------|-------|
|      a       |======N/A======|
|------|-------|-------|-------|
|  b1  |  b2   |======N/A======|
|------|-------|-------|-------|
|              c               |
|------|-------|-------|-------|
|     f1       |      f2       |
|------|-------|-------|-------|
|              d               |
|------|-------|-------|-------|
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

## Unions

Unions are tagged/discriminated unions. They are be one of a set of values, and know which variant they are. 
These are intended to store values, unlike enums.

For untagged or C-style unions, structs with the `#union` directive can be used instead.

Here are some examples of normal unions:

```
Option :: union[T] {
    None,
    Some(T),
}

Result :: union[T, E] {
    Ok(T),
    Error(E),
}

TechnicallyFine :: union {
    IGuess,
    ThisWorks
}
```


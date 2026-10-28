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
c32 c64 c128

// Quaternions
q64 q128 q256

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
| c32      | 32-bit complex number, composed of 2 f16 values                                                                                              |
| c64      | 64-bit complex number, composed of 2 f32 values                                                                                              |
| c128     | 128-bit complex number, composed of 2 f64 values                                                                                             |
| char     | One byte of utf-8 text (a code unit)                                                                                                         |
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
| q64      | 64-bit quaternion, composed of 4 f16 values                                                                                                  |
| q128     | 128-bit quaternion, composed of 4 f32 values                                                                                                 |
| q256     | 256-bit quaternion, composed of 4 f64 values                                                                                                 |
| rawptr   | Pointer to an arbitrary type, equivalent to C's const void *; `mut rawptr` is C's void *                                                      |
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

## Any

The `any` type is a combination of a type and raw pointer, in the fields `data: rawptr` and `type: type`.
`type_info_of(value.type)` describes what `data` points to.
Any other type can be implicitly cast to an `any`, including stack variables and parameters.
Converting a value to an `any` copies it into the current stack frame, and `data` points at the copy,
so an `any` can't outlive the frame that made it, which the compiler checks,
see [memory.md](memory.md#pointers-to-the-stack).

## Type Values and Type Information

A type can be used as a value of type `type`: `t : type = int`, `type_of(x)`, or an `any`'s `type`.
Two type values are equal when they're the same type, so `value.type == int` checks what an `any` holds.
A plain alias is the type it names; a distinct alias is a type of its own.

```
describe :: fn(value: any) -> string {
    if value.type == string {
        return "text"
    }
    info :: type_info_of(value.type)
    if info.variant == .ENUM {
        return "an enum"
    }
    return "something else"
}
```

At run time, a type value is the address of a read-only description of the type, which
`type_info_of` returns as a `ptr[compiler.TypeInfo]` (`base/compiler/types.hsc`). Its `variant` says
which struct describes the type in full, to cast it to: `TypeInfoEnum` has an enum's member names and
values, `TypeInfoStruct` its members with their types and offsets, `TypeInfoUnion` its variants, and so
on. A type gets a description when a program uses it as a value or puts a value of it in an `any`,
along with every type that description refers to.

`int`, `uint`, `usize` and `uintptr` are described like the fixed-size integers they're laid out as;
comparing type values tells them apart.

### Schemas

`std`'s `schema` package writes a type's description as bytes that are the same in every build, every program and on
every host (`schema.write`), and names the type by their BLAKE3-256 hash (`schema.hash`). It's how a value's type can be
named outside the program, by something that reads the value later or elsewhere. The same code runs in `#run` and at
run time, so a hash worked out when compiling matches one worked out while running.

```
POINT_SCHEMA :: #run schema.hash(type_info_of(Point))

matches :: fn(value: any) -> bool {
    return schema.hash(type_info_of(value.type)) == POINT_SCHEMA
}
```

A schema covers a value's layout and its names: each type's kind and size, the names of structs, unions, enums and
distinct aliases, their members, variants and enum values in order, with their offsets, and the types they hold. It
doesn't cover where a type was declared or its documentation. So two types laid out alike under the same names have
the same schema, and changing a name, a member's order or a member's type changes it. A plain alias has the schema of
the type it names; a distinct alias has its own. `int` has the same schema as `i64`, as it's laid out the same way.

The bytes start with `HSCH` and the format's version, then the number of types, then each type, the one described
first. Each type refers to the others by their place among them, counted in the order they're first reached, so a type
that refers to itself is described once.

## Arrays

There are a few types of arrays.

### Static Arrays

Static arrays have a fixed size. They are accessed using `[]` subscript syntax.

```
a : int[5]    // Array of 5 ints
b : f64[2]    // Array of 2 f64s
c : i8[10][5] // 2D array of i8s
```

A count is any compile-time constant, like `int[CAPACITY * 2]` or `int[#run fib(5)]`, and an array type with several
dimensions is a type wherever a value can be one too: `size_of(i8[10][5])` is 50.

Arrays know their size, and you can access it with `array.count`.

An array literal is the element type, followed by `.[]` holding the elements. Its type is a static array of that many
elements, so it can be used anywhere a static array can, including as an array view.

```
d :: int.[1, 2, 3]          // int[3]
e : f64[2] : f64.[0.5, 1.5]
f : int[] : int.[4, 5, 6]   // A view over an array on the stack
```

### Dynamic Arrays

Dynamic arrays are resizable, allocating more memory as needed. It behaves
similarly to the C++ `std::vector`, but using the current context's allocator.

```
a : int[..]    // Dynamic array of ints
b : string[..] // Dynamic array of strings
```

Dynamic arrays know their size, and also have a capacity that can be accessed with `array.capacity`.

An array starts empty, with no memory and no allocator. The first time it needs memory it takes the context's
allocator, and keeps it, so every block it uses comes from and goes back to that one, even if it's changed later
where the context's allocator is another. It grows by doubling, from 4 elements. Running out of memory calls
`context.assertion_handler`, like `new`.

The functions for them are in `runtime` (`base/runtime/array.hsc`). Those that change an array take a pointer to it,
and those that only read one take a view:

```
names : string[..]
defer runtime.array_free(&names)
runtime.array_add(&names, "first")
runtime.array_add(&names, "second")
last :: runtime.pop(&names)           // "second"
```

| Function | What it does |
|---|---|
| `array_add(&array, value)` | Adds `value` at the end, growing the array if it's full |
| `array_copy(source, &target)` | Adds each of a view's elements at the end, in order |
| `array_reserve(&array, capacity)` | Makes room for at least `capacity` elements |
| `array_remove(&array, position)` | Removes an element, moving the later ones down, so the order is kept |
| `array_remove_fast(&array, position)` | Removes an element by moving the last one into its place |
| `pop(&array)`, `peek(view)` | Removes and gives back, or just gives back, the last element |
| `array_find(view, value)` | Where `value` first is, comparing with `==`, or none |
| `array_reset(&array)` | Empties it, keeping its memory |
| `array_free(&array)` | Gives its memory back, leaving it empty |

Removing past the end, or popping or peeking at an empty array, calls `context.assertion_handler`. What's added is
kept beyond the call, so `value` is `#escaping`, and `array_copy`'s elements are checked the same way (see
[memory.md](memory.md#escaping-parameters)).

### Array Views

Array views represent a view into data stored in an array, or a subsection of one.

```
a : int[]
```

Both static and dynamic arrays will be auto-cast to array views if
provided to a function with an array view parameter. A view refers to the array's own elements, not a copy of
them.

A view only reads its elements. One that can change them is written `mut T[]`, and changing an element through it
changes the array:

```
clear :: fn(values: mut int[]) {
    for &value in values {
        value^ = 0
    }
}

numbers : int[4]
clear(numbers)          // numbers can be changed here, so it can be a mut int[]
```

A `mut T[]` can be given where a `T[]` is wanted, never the other way. An array becomes a `mut T[]` only where it
can be changed itself (see [Mutability](#mutability)), so a parameter's copy of an array, or a constant, can't.
Part of a view, like `values[1..<3]`, can change its elements if the view can.

Arrays on the stack (including fields of structs on the stack) can be passed to functions as,
or cast to, array views. Such a view can't outlive the array, which the compiler checks,
see [memory.md](memory.md#pointers-to-the-stack).

A view of memory that didn't come from a Hemera array, like a table a bootloader or a device wrote, comes from the
builtin `view_of(data: ptr[T], count: usize) -> T[]`: `count` elements of `T` starting at `data`, so
`count × size_of(T)` bytes. `string_of(data: ptr[u8], count: usize) -> string` does the same for text. Neither is
checked, like a cast to a pointer: the caller makes sure the elements are there for as long as the view is used. From a
`ptr[mut T]`, it's a `mut T[]`.

```
regions :: view_of(cast[ptr[MemoryRegion]](address), count)
```

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

### Bounds Checking

When directly indexing into arrays and strings, the index must be proven to be within the bounds, at compile
time. There's no check at run time, so an index the compiler can't prove is an error (E4031).

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
    if known < resizable.count { // don't know the count
        result = resizable[known] // Checked the bounds
    }
    result = fixed[known] // Provably in bounds
    if unknown >= fixed.count {
        return
    }
    result = fixed[unknown] // Can't reach here if it would go out of bounds

    // All automatically fine, loops know the bounds
    for i in resizable {
        print(i)
    }
    for i, index in view {
        print(view[index])
    }
    for i in fixed {
        print(i)
    }
}
```

When providing bounds for slices, they must not extend outside the bounds of the array, or it is a compile-time error:
the start must be at least 0 and at most the end, and the end at most the count.

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

    if a <= b && b <= resizable.count {
        result = resizable[a..<b] // We checked that it's fine
    }
}
```

#### What's Proven

Each function is checked on its own. What the compiler knows at each point is how integers compare: locals, the
counts of local arrays, views and strings, fields reached from locals (`text.count`, `parser.input.count`), including
through an element at a constant or a local's index (`names[2].count`, `items[i].count`), and constants. What's known
about an element's fields is forgotten when its index changes, as well as when the array or memory does. It learns from:

* definitions and assignments: after `j := i + 1`, `j` is one more than `i`, and `i += 1` moves what's known about `i`
* stores to an integer field: `ring.count -= 1` moves what's known about `ring.count`, and `ring.count = 3` (a constant
  or a local) sets it, while what's known about other paths through pointers is forgotten, since they may be the same memory
* conditions, through `&&`, `||` and `!`, in the branch they lead to, and after an `if` whose other branch doesn't
  continue (`return`, `break`, a `#never_returns` call)
* `for` loops over a range or over elements, whose index is in bounds, and the condition of a `while`
* `runtime.assert(condition)`, which ends the program when the condition is false, so after it the condition holds
* types: an unsigned value is at least 0, a `u32` at most 2^32 - 1, an enum value at most its largest member's,
  `x & 15` at most 15 and `x % n` less than `n`. `%` is truncated, so of a signed value that may be negative it may be
  negative too; `x %% 16`, floored, is from 0 to 15 whatever `x` is
* arithmetic on what's bounded: a bounded value times a constant, either way around, like `4 * i` and
  `(round % 10) * 16`, and that plus a constant or another bounded value, like `4 * i + 3` and `16 * b + 4 * j + k`,
  as long as it isn't negative (a loop's name from 0 isn't, even when it's signed)
* a difference compared with a constant, like `data.count - at >= 16`, which says `at + 16 <= data.count`, once `at` is
  known to be at most `data.count` (and, if signed, at least 0), so the difference can't wrap
* a sum of two values compared as it is, like `if at + i < into.count { into[at + i] = 1 }`: what's known of the sum,
  wrapped or not, holds for an index that's the same sum, until either value changes
* the count of a fixed array through a pointer, like `p.count` with `p` a `ptr[u8[8]]`, which is the constant 8

A loop keeps what holds every time around it: a counter that only goes down keeps its upper bound, and one that's
kept below a count keeps that.

Integers wrap, so `x + 1` is only known to be one more than `x` when `x` is already known to be below something, like
a count. `if offset + 4 <= bytes.count` proves nothing about `offset`, since a huge `offset` wraps around;
`if offset < bytes.count && offset + 4 <= bytes.count` does.

#### What Isn't

* What other functions do. A count a function computed and another relies on, or a value one returns, is unknown to
  the caller: check it, or state it with `runtime.assert`, which documents the contract and checks it at run time.
* Memory reached through a pointer, after anything that could write it: a call, or a store through a pointer.
  `info.cpus.count` is forgotten across a call; a copy of the view in a local, `cpus :: info.cpus`, isn't.
* Relations between more than two values that aren't bounded by constants, like `i + j < n`, beyond a sum compared and
  indexed as it is, or products of two variables. Compute the index into a
  local and compare that, or loop with an index that counts the way the code needs.
* Invariants of a data structure, like a struct's array having one entry per frame. Compare against the array's own
  count, rather than a field that's meant to equal it.

## Vectors

A vector holds several values of one type, its lanes, and operators work on every lane at once, which the CPU does with
its vector instructions where it has them. `vector[T, n]` has `n` lanes of `T`, an integer or float of up to 64 bits of
the target's own endianness, or `bool`; `n` is a power of two, and the whole is at most 64 bytes. A vector is aligned
to its size, up to 64 bytes.

```
Words :: vector[u32, 4]

a := Words.{1, 2, 3, 4}         // every lane, in order
zero := Words.{}
b := a + Words.{10, 20, 30, 40} // .{11, 22, 33, 44}
c := a * 2 - 1                  // a literal goes in every lane
d := a << 4                     // shifted by one amount, or by a vector of them
e := b >> Words.{0, 1, 2, 3}
first := a[0]                   // a lane
a[2] = 100
```

* The arithmetic, bitwise and shift operators work lane by lane on two vectors of the same type, or one and a literal,
  which goes in every lane. Integer division and remainder aren't on vectors yet, since a lane of 0 has nothing like
  the panic dividing by 0 gives; floats divide.
* Comparisons compare lane by lane, giving a vector of bools: `a < b` is a `vector[bool, 4]`. `&`, `|`, `~` and the
  unary `~` work on those, and `intrinsics.any_true` and `all_true` ask about them; `&&` and `||` don't.
* A lane is chosen by a constant, `a[2]`, so it's never out of range, and never decided at run time.
* A vector's lanes are laid out in memory like an array's elements, so `bit_cast` between a vector and an array of the
  same size gives the same lanes.
* Running on a target without vector instructions, like a kernel built without SIMD state, a vector's code works
  one lane at a time.

`v128`, `v256` and `v512` are bits of a vector register's size, without lanes of their own. They take `&`, `|` and
`~`, and `bit_cast` to and from any vector or array of their size: they're what instructions like AES's work on,
see `base/intrinsics/x86_64`.

```
bits := bit_cast[v128](vector[u8, 16].{/* ... */})
masked := bits & mask
bytes := bit_cast[vector[u8, 16]](masked)
```

`base/intrinsics` has what the operators don't do, each working out its types from what it's given:

| Function | What it does |
|---|---|
| `splat[V](lane)` | `lane` in every lane of `V` |
| `select(mask, chosen, otherwise)` | Each lane from `chosen` where `mask`'s is true, otherwise from `otherwise`, without a branch |
| `rotate_lanes(vector, count)` | The lanes moved down by a constant `count`, the first ones coming round to the end |
| `reduce_add`, `reduce_and`, `reduce_or`, `reduce_xor` | A vector of integers' lanes combined into one |
| `any_true`, `all_true` | Whether any, or every, lane of a vector of bools is true |
| `rotate_left(value, amount)`, `rotate_right` | An integer's bits rotated, or each lane's |
| `byte_swap(value)` | An integer's bytes in the other order, or each lane's |

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
Where an optional of an enum or union is expected, the shorthand names the enum's or union's own members too:
`trump : Suit? = .Hearts`. A generic function's argument can be a shorthand when another argument or the result decides
its type.

Enums are backed by a `uint` by default, but `#backed_by(x)` can be used used to specify the backing type, where `x` must be one of the unsigned integer types (u8, u16, u32, u64, u128). For example:

```
Suit :: enum #backed_by(u8) {
    Clubs,
    Hearts,
    Spades,
    Diamonds,
}
```

Members count up from 0, unless given a value. A member without a value is one more than the member before it:

```
LogLevel :: enum {
    TRACE = 0,
    DEBUG = 10,
    INFO = 20,
    VERBOSE_INFO,   // 21
}
```

`cast` gets the backing integer of an enum value, converted to the integer type asked for like any integer cast:

```
level : u8 = cast[u8](LogLevel.DEBUG)   // 10
```

The backing type is part of the enum's type info (`TypeInfoEnum.backing_type`), along with each member's name and value.

## Generics

Structs, unions and functions can take generic parameters, listed in square brackets. They're filled in at compile time,
and each distinct set of arguments makes a separate instance, like C++ templates or Jai's polymorphic procedures
(where `fn[T](x: T)` would be written `(x: $T)`).

```
Pair :: struct[A, B] {
    first : A,
    second : B,
}

Maybe :: union[T] {
    Nothing,
    Just(T),
}

swap :: fn[A, B](pair: Pair[A, B]) -> Pair[B, A] {
    return Pair[B, A].{pair.second, pair.first}
}
```

A generic type is always used with its arguments, like `Pair[int, string]` or `Maybe[int]`, including in a struct
literal: `Pair[int, string].{1, "one"}`.

### Binding a Function's Generic Parameters

Each call binds every generic parameter of the function, in one of three ways:

| How | Example | |
|---|---|---|
| Inferred from a parameter's type | `free(pointer)` | `free :: fn[T](pointer: ptr[T], ...)`: `T` is whatever `pointer` points to |
| By the parameter with the same name | `size_of(Foo)` | `size_of :: fn[T](T: type) -> usize`: the parameter `T` is the generic `T` |
| Explicitly, in brackets after the name | `empty[string]()` | For generics nothing else binds, like `empty :: fn[T]() -> T[..]` |

* A generic that can't be bound any of these ways is an error.
* Giving a generic explicitly when it's already bound another way, like `size_of[Foo](Foo)`, is allowed but gives a
  warning, since it says the same thing twice.

### Compile-Time Parameters

A parameter with the same name as a generic parameter is a compile-time parameter, whatever its type. That's how
`size_of(Foo)` takes a type, and it works the same for values:

```
buffer :: fn[count](count: usize) -> u8[count] {
    result : u8[count]
    return result
}

bytes :: buffer(16) // u8[16]
```

* The argument must be known at compile time: a literal, a named constant, an enum member, a function, or the result
  of `#run`.
* Only integers, enums, booleans and functions can be compile-time values, besides types.
* Inside the function, the parameter is a constant, so it can size an array, or be used in `#if` and `#assert`.
* A function with a body gets an instance for each distinct value, as it does for each distinct type.
* A declaration without a body (`---`), like an intrinsic, receives the value at compile time. For example,
  `x86_64.entry_points(handler)` generates code that jumps to `handler`.
* The call looks like any other. Nothing at the call site shows that an argument is compile-time.

### Values in Generic Lists

A generic list can also take values, written `name: type`, for values that aren't a function's parameters,
like a container's capacity:

```
Ring :: struct[T, capacity: usize] {
    items : T[capacity],
    head : usize,
    tail : usize,
}

ring : Ring[u8, 4096]

push :: fn[T, capacity: usize](ring: ptr[mut Ring[T, capacity]], item: T) {/* ... */}
```

They follow the same rules as compile-time parameters, and are bound explicitly, or inferred from a parameter's type,
as `push` binds `capacity` from `ring`. Inside the type or function, a value is a constant of its declared type: it can
size an array, be used in `#if` and `#assert`, and be used like any other constant. A value given explicitly is written
like a type argument, as in `filled[4](byte)`. Two instances with equal values are the same type, so
`Ring[u8, 2 + 2]` is `Ring[u8, 4]`.

An array's size in a type, and a value in a generic list, can be a constant expression:

```
Bits :: struct[size: usize] {
    words : u64[(size + 63) / 64],
}

flags : Bits[130]        // three words
ring : Ring[u8, PAGE_SIZE / 2]
```

A generic type whose only argument is an integer, like `Bits[64]`, means `Bits` with the argument 64 when `Bits` is
generic, and an array of 64 `Bits` otherwise.

A value can be a function, for what a generic needs done to its types. With no overloading, functions are named for
what they take, so the generic is given the one to use rather than finding one by name, like std/maps' `HashMap`:

```
HashMap :: struct[K: compiler.Equatable, V, hash: fn(key: K) -> u64] { ... }

ages : maps.HashMap[string, int, maps.hash_string]
squares : maps.HashMap[int, int, maps.hash_integer[int]]
```

* The function given has to take and give exactly what the parameter says, with the other parameters filled in:
  `HashMap[string, int, hash_wrong]`, for a `hash_wrong` returning `u32`, is an error (E4014), where it's written.
* A generic function is given as one of its instances, named with its arguments, like `hash_integer[int]`.
* In the generic, it's called like any function: `hash(key)`.

### Constraints

A generic says what it needs from its parameters with constraints, in its generic list, a `where` clause after its
signature or generic list, or both:

```
array_find :: fn[T: compiler.Equatable](array: T[], value: T) -> usize?

largest :: fn[T: compiler.Ordered && (compiler.Integer || compiler.Float)](a: T, b: T) -> T

RingBuffer :: struct[T, capacity: usize] where compiler.AtLeastOne(capacity) { ... }
```

A constraint is a function marked `#constraint` (see [directives.md](directives.md#constraint)), taking types as `type`
parameters and values as values, made of **requirements** from `base/compiler`. Each requirement either holds or adds
why it doesn't, and checking goes on, so one error gives everything that's missing:

```
// Something with a count: a struct with a count field, or a view or array
HasCount #constraint :: fn(T: type) {
    compiler.require_field(T, "count", usize)
    compiler.note("give % a count: usize", T)
}
```

| Requirement | Holds when |
|---|---|
| `require_equality(T)` | `==` works on `T`: numbers, characters, booleans, enums, pointers, strings, functions and types |
| `require_ordering(T)` | `<` works on `T`: numbers and characters |
| `require_integer(T)`, `require_signed(T)`, `require_unsigned(T)`, `require_float(T)`, `require_numeric(T)` | `T` is that kind of number |
| `require_field(T, name, type)` | `T` is a struct with that field, or a view or array, whose `count` is a `usize` |
| `require_view(T, element)` | `T` is an array, view or dynamic array of `element`: `for`, indexing and `count` work on it |
| `require_mutable(T)` | `T` was given with `mut` (see [Mutability in Type Arguments](#mutability-in-type-arguments)) |
| `require(condition, message, values...)` | `condition` is true; otherwise `message`, with `%` filled in, says why |
| `note(message, values...)` | Adds to why the last requirement isn't met, like what to do about it |

`base/compiler` has the constraints most generics need: `Equatable`, `Ordered`, `Integer`, `Float`, `Numeric`,
`ViewOf(C, E)`, `Mutable`, and for value parameters, `AtLeastOne` and `PowerOfTwo`.

* **In a generic list,** `T: C` constrains the type parameter `T`, and means `C(T)`. Whether `name: X` is a constrained
  type or a value of type `X` (see [Values in Generic Lists](#values-in-generic-lists)) depends on what `X` is: a
  `#constraint` function, or a type.
* **In a `where` clause,** constraints are called with any of the generic's parameters, types or values, and with types
  or constants written in place: `where Convertible(From, To) && compiler.AtLeastOne(capacity * 2)`. `where` is only a
  word there, so it can still name things elsewhere.
* **Combining** is like short-circuiting booleans: `A && B` stops at the first that isn't satisfied, so `B` can rely on
  `A`, and `A || B` at the first that is. Parentheses group them.
* **Checked where an instance is made,** by running each constraint at compile time with the instance's arguments: at a
  call, or where a generic type is used. Each constraint is run once for the same arguments. The generic list's
  constraints are checked first, then the `where` clause.
* **What isn't satisfied** is an error (E4032) where the instance is made, giving each failed part and why, with the
  reasons for every alternative of an `||`. The instance's body isn't checked, so no error comes from inside it:

```
main.hsc:12:9: error E4032: Constraint not satisfied. largest[char] can't be made
    T = char isn't compiler.Ordered && (compiler.Integer || compiler.Float)
        Integer: char is a character, not an integer
        Float: char is a character, not a float
```

* A generic without constraints is a template, as it always has been: its body is checked for each instance, with
  whatever its arguments support. A constrained generic function's body is also checked once on its own, against what
  its constraints promise (see [Checked Bodies](#checked-bodies)).

`require_any` takes constraints, and holds when any one of them does. It's for a constraint made of alternatives, where
each alternative is itself a constraint, and when none holds, the reasons are each alternative's:

```
// A number formatting can write: an integer, a float, or a character
Formattable #constraint :: fn(T: type) {
    compiler.require_any(compiler.Integer(T), compiler.Float(T), Character(T))
}
```

`compiler.satisfies(...)` asks whether constraints hold, as a compile-time `bool`, without an error when they don't. It
takes the same `&&`, `||` and parentheses, and works in `#assert`, `#if`, and in a generic's body, where each instance
decides for its own arguments:

```
#assert compiler.satisfies(compiler.Equatable(Key) && compiler.Ordered(Key))

describe :: fn[T](value: T) -> string {
    #if compiler.satisfies(compiler.Integer(T)) {
        return "an integer"
    }
    #else {
        return "something else"
    }
}
```

### Checked Bodies

A constrained generic function's body is checked once, before any instance and whether or not anything calls it, with
an **archetype** for each type parameter: a stand-in that has only what the constraints promise. So the body can only
use what every argument its constraints allow will have, and using anything else is an error there (E4033), with what
would promise it:

```
total :: fn[T: compiler.Equatable](a: T, b: T) -> T {
    return a + b
}

main.hsc:2:14: error E4033: Not promised by constraints. arithmetic on T, which total's constraints don't promise;
    constrain T with compiler.Numeric
```

What a constraint promises comes from the requirements it's made of, worked out from how it's written, not by running
it:

| Requirement | Promises the body |
|---|---|
| `require_equality(T)` | `==` and `!=` on `T` |
| `require_ordering(T)` | `<`, `<=`, `>`, `>=`, and `==` |
| `require_numeric(T)` | Arithmetic (`+`, `-`, `*`, `/`), comparisons, number literals, and casts to and from numbers |
| `require_integer(T)`, `require_signed(T)`, `require_unsigned(T)` | A number's, and `%`, bitwise operators and shifts |
| `require_float(T)` | A number's, and float literals |
| `require_field(T, name, type)` | `.name`, of `type` |
| `require_view(T, element)` | `for`, indexing and `count`, with elements of `element` |
| `require_mutable(T)` | Changing what a `ptr[T]` points to |

* **Combining** promises like it checks: `A && B` promises what either does, and `A || B` only what both do, since
  either may be the one that holds. `require_any` is the same as `||`, so `require_any(Integer(T), Float(T))`
  promises arithmetic, but not `%`.
* **Every type** can be declared, assigned, passed, returned and pointed to, so those need nothing promised.
* **`require(condition, ...)`** promises nothing: it's about values, and only an instance knows them.
* **A value parameter** has no known value: it's a value of its type, fine in arithmetic and comparisons. A type it
  sizes, like `T[capacity]`, needs its value, so a generic that has one is only checked at its instances.
* **An `#if`** that decides on a type or value parameter is left to the instances, which check the branch they take.
* **Calling a constrained generic** with an archetype needs the caller's constraints to promise what the callee's
  ask for: the same constraint call, like `where compiler.PowerOfTwo(factor)` on both, or requirements the caller's
  constraints promise. Calling an unconstrained generic, a template, is trusted: its body is checked at the real
  instances, as always.

```
largest :: fn[T: compiler.Ordered && (compiler.Integer || compiler.Float)](a: T, b: T) -> T { ... }

pick :: fn[T: compiler.Ordered](a: T, b: T) -> T {
    return largest(a, b)
}

main.hsc:4:20: error E4033: Not promised by constraints. largest[T] needs what pick's constraints don't promise
    T needs Integer(T)
    T needs Float(T)
```

A body checked this way is still checked at each real instance, which is what's generated; it shouldn't find anything
new, but things like bounds proofs that use a value parameter's value are only made there. A body the early check
found errors in isn't checked again at its instances, so each error is reported once.

### Derived Parameters

A generic parameter can be worked out from the ones before it with `name = expression`, like a default argument. The
expression is compile-time: a type, like `ptr[A]`, a builtin like `size_of(T)`, or a call to a function returning a
`type` or a value. It can use the generic's other parameters, and constraints can use it:

```
// The type of an array or view's elements
element_of :: fn(C: type) -> type { ... }

// The total is the elements' type, unless it's given
sum :: fn[C, E = element_of(C), Total = E](values: C) -> Total
    where compiler.ViewOf(C, E) && compiler.Numeric(E) && compiler.Numeric(Total) { ... }

bits_of :: fn[T, bits = size_of(T) * 8](value: T) -> usize

Linked :: struct[A, B = ptr[A]] { ... }
```

* **Nothing binds it from arguments.** `sum(view)` binds `C` from `view`, then works out `E` and `Total`.
* **Giving it overrides it,** like a default argument: `sum[u8[], u8, u64](view)` totals bytes in a `u64`, so it
  doesn't wrap. The parameters before it are given too, since generic arguments are positional, and that isn't reported as
  giving them twice. `Linked[int]` works out `B` as `ptr[int]`; `Linked[int, usize]` uses `usize`.
* **A parameter worked out from itself,** directly or through others, is an error (E4007).

In the generic's body, a derived type is a type, and a derived value is a constant without a type of its own, like a
literal. When the body is checked before any instance, a derived type is an archetype like any other, with what the
constraints promise about it, so `sum`'s `E` is something `C` is a view of, and a number.

For how `#escaping` applies to generic parameters, see [memory.md](memory.md#escaping-parameters).

## Implicit Casting

Some types will implicitly (automatically) cast to each other, without having to manually add in casts.
Generally speaking, widening conversion are fine and narrowing ones are not.

Will implicitly cast:

* i8, i16, i32, i64 will cast up to signed integers of a larger size, or int
* u8, u16, u32, u64 will cast up to unsigned integers of a larger size, or uint
* The endian-specific versions of integers will cast to their native type (`u32be` to `u32`), or a larger native
  integer of the same signed-ness, swapping their bytes if they must
* Floating point types will cast to larger versions
* The endian-specific versions of floating point types will cast to their native type, or a larger native one
* b8, b16, b32, b64 will cast up to booleans of a larger size
* uintptr and usize will cast to uint
* Structs will implicitly cast to any structs included inside with the `using` keyword

Will not implicitly cast:

* i128 won't implicitly cast to int, other than on a hypothetical 128-bit platform
* u128 won't implicitly cast to uint, other than on a hypothetical 128-bit platform
* uintptr will not implicitly cast to or from usize
* A native integer or float won't implicitly cast to an endian-specific one, so a store that swaps bytes shows as a
  `cast` (see [Endian-Specific Types](#endian-specific-types)); a literal is fine
* Endian-specific types won't implicitly cast to each other
* Complex numbers will not implicitly cast between sizes
* Quaternions will not implicitly cast between sizes

## Memory Layout

Strings, array views and dynamic arrays are small structs pointing at their contents, which code working through
`rawptr` and type info can read as `runtime.StringView`, `ArrayView` and `ResizableArray`:

| Type | Layout |
|---|---|
| `string` | `count: usize` (bytes), `data: rawptr` |
| `T[]` | `count: usize`, `data: rawptr` |
| `T[..]` | `count: usize`, `data: rawptr`, `capacity: usize`, `allocator: Allocator` |
| `any` | `data: rawptr`, `type: type` |

Functions that change a dynamic array take a pointer to it, so the change reaches the caller's array:
`array_add(&names, name)`. Functions that only read one take an array view, which dynamic arrays convert to.

Static arrays are their elements, one after another, with nothing else.

Sizes, on the 64-bit targets Hemera supports:

* `bool`, `b8` and `char` are 1 byte; `b16`, `b32` and `b64` are 2, 4 and 8.
* `int`, `uint`, `uintptr`, `usize`, pointers, `rawptr`, `cstring`, `type` and function values are 8 bytes.
  Relative pointers are their size: `relptr8` is 1 byte, up to `relptr64` at 8.
* Every primitive is aligned to its size, `i128` and `u128` included (16).

Structs lay out their fields in order, each at the next offset its alignment allows. A struct is aligned to its most
aligned field, and its size is rounded up to that, so that arrays of it keep every field aligned.

* `#packed` leaves no padding between fields, and aligns the struct to 1.
* `#align(n)` raises the struct's alignment to `n` bytes when that's more than it would be. It never lowers it; for
  that, combine it with `#packed`, which then gives exactly `n`.
* `#union` puts every field at offset 0, and the struct is as big as its biggest field.
* Fields included with `using`, and anonymous structs (`_ : struct {...}`), are laid out as one field.

```
Mixed :: struct {
    a : u8,  // offset 0
    b : u32, // offset 4
    c : u16, // offset 8
    d : u64, // offset 16
}            // size 24, alignment 8
```

Unions (including optional values and results) start with a tag saying which variant a value is: the smallest
unsigned integer that counts the variants, so `u8` for up to 256 of them. Each variant's values follow the tag like a
struct's fields, all variants overlapping, and the union is as big as its biggest variant, rounded up to its alignment.

```
Shape :: union {
    Circle(f32),          // tag at 0, the f32 at 4
    Rectangle(u8, u64),   // tag at 0, the u8 at 1, the u64 at 8
    Empty,                // just the tag
}                         // size 16, alignment 8; int? is 16 too
```

Enums are the size of their backing type, `uint` unless `#backed_by` gives another.

## Complex Numbers and Quaternions

A complex number is two floats, its real and imaginary parts: `c32` of `f16`s, `c64` of `f32`s, `c128` of `f64`s. A
quaternion is four, a real part and three imaginary ones: `q64`, `q128` and `q256`, of `f16`s, `f32`s and `f64`s. They
are laid out with a complex number's real part first, then its imaginary part, and a quaternion's three
imaginary parts first, then its real part, so a `q128` is a graphics library's `(x, y, z, w)`.

An imaginary number is a number with `i`, `j` or `k` after it: `2i`, `1.5j`, `1e3k`. Arithmetic on numbers and imaginary
numbers is a complex number, or with a `j` or `k`, a quaternion. Like any literal it takes the type it's used as, and
where nothing decides that, a complex number is a `c128` and a quaternion a `q256`. A real number given as one is its
real part.

```
z : c64 = 1 + 2i
q : q128 = 1 + 2i + 3j + 4k
w := 0.5 - 1i           // a c128
```

There are builtins for the parts and the magnitude floats of the parts' type:

* `real(x)`, the real part, and `imag(x)`, the `i` imaginary part
* `jmag(q)` and `kmag(q)`, a quaternion's `j` and `k` imaginary parts
* `conj(x)`, the conjugate, with its imaginary parts negated (of the same type)
* `abs(x)`, the magnitude, the square root of the sum of its parts' squares; of an integer or a float, its absolute
  value

A quaternion's parts are also its fields, which can be set: `x`, `y` and `z`, its imaginary parts, and `w`, its real
part. `xyz` is the vector part, the three imaginary parts as an array of three floats. A complex number has no fields;
one is made from parts by arithmetic, like `re + im * 1i`: a float with an imaginary number is the complex number, or
quaternion, of that float, so with `f64`s that's a `c128`.

Their operators:

* `+` and `-` work part by part, and `-z` negates every part.
* `*` is the complex product, or for quaternions the Hamilton product, so `i * j == k` but `j * i == -k`. `/` multiplies
  by the divisor's conjugate and divides by its norm, the sum of its parts' squares.
* `==` and `!=` compare every part. They have no order, so `<` and the like are errors.
* A real number of the parts' type, or one that converts to it implicitly, takes part in arithmetic as a complex number
  or a quaternion with only a real part: `z * 2.0` and `scale + z`, with `scale` an `f32` and `z` a `c64`.
* `cast` turns one into another size, part by part, and a real number into one.

## Endian-Specific Types

`u16be` to `u128be`, `i16be` to `i128be`, `f16be` to `f64be`, and their `le` versions, are stored in that byte order
in memory, always: a `bit_cast`, a `#packed` struct's field, or a view over a device's buffer sees the bytes that
way. They're for layouts something else decides, like a network header (big-endian), virtio (little-endian), or a
disk format, and mean the same on every target. A `u32le` is its own type even on a little-endian target, laid out
like a `u32` there.

```
Header :: struct #packed {
    kind : u8,
    length : u32be,
}

next_length :: fn(header: ptr[mut Header]) {
    length : u32 = header.length            // read as a u32, swapped
    header.length = cast[u32be](length + 1) // stored with a cast, so the swap shows
}
```

* They have no arithmetic of their own: in an operator, each is its native type (`u32` for `u32be`), so
  `header.length + 1` is a `u32`, and `+=` on one is an error. Comparing two, with `==` or `<`, compares their values.
* One converts implicitly to its native type and to wider native ones, swapping if it must, and a native value
  becomes one only with a `cast`. A literal needs no cast: `length : u32be = 300` stores 300 in big-endian order.
* Given as an `any`, one is its native value, so formatting it shows the number.

Every target Hemera has is little-endian, so it's the `be` types that are swapped, with one instruction.

## Notes On Types

For boolean values, `true` is stored as `1`, and `false` is stored as `0`.

All types are initialized to zero, unless the symbol `---` is used, which indicates that a value should remain uninitialized. For example, `x : ComplicatedType[100] = ---`.

## Equality

`==` and `!=` compare values of the same type:

* Numbers, booleans, characters, enums, pointers and type values by their values; strings by their bytes.
* Fixed arrays element by element: `guid == other`, where both are `u8[16]`.
* Structs member by member. Padding between members isn't compared, so two structs built differently are equal
  when their members are.
* Tagged unions by their variant, then that variant's values: `.Circle(1.5) == .Circle(1.5)`, and any two values of a
  variant that holds nothing are equal.
* Optionals as [Optional Types](#optional-types) says: against `null`, against a value of what they hold, or each
  other.

Views and dynamic arrays can't be compared with `==` (whether two views are equal could mean the same memory or the
same elements), and neither can `any`, `#union` structs, whose members share memory, or a struct, fixed array or union
that holds one of them. Comparing them is an error when the program is checked.

## Number Formats

Integers can be written as 

* Decimal format, using the digits (0, 1, 2, 3, 4, 5, 6, 7, 8, 9)
* Hex format, with the prefix `0x` followed by  one or more hex digits (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, a, A, b, B, c, C, d, D, e, E, f, F)
* Octal format, with the prefix `0o` followed by one or more octal digits (0, 1, 2, 3, 4, 5, 6, 7)
* Binary format, with the prefix `0b` followed by one or more binary digits (0, 1)

Any format can use underscores (`_`) freely between digits, they are ignored.

An integer literal has to fit the type it becomes, whether that's written, like `small : u8 = 300`, or its usual
type `int`, like `big := 0xffff_ffff_ffff_ffff`. Both are errors, as is `-1` given to an unsigned integer, or a
literal larger than a `u64` can hold.

Operators on literals and on constants without a type, like `LARGE :: 300`, are worked out exactly when the
program is compiled, so `255 + 1` as a `u8` is an error too, while `512 / 4` is a `u8`'s 128: only the result has
to fit. A result larger than a `u64` can hold is an error, and so is dividing by a known zero. Bitwise
operators on negative literals depend on the type's size, so those aren't worked out or checked.

## Optional Types

Any type can be represented as an optional by appending a `?` to the type name.
This is Hemera's nullable type: a `ptr[T]`, `cstring` or function value always refers to something, and only a
`rawptr` or an optional can be `null` (where `null` is an optional's `None`).

For example `i32?` is a type that either contains an `i32`, or does not.
This works for any built-in or user-defined type.

This is a built-in union type similar to this structure, where `Optional[Foo]` is equivalent to `Foo?`:

```
Optional :: union[T] {
    None,
    Some(T),
}
```

`None` comes first, so its tag is 0, and an optional that starts zeroed, as every value does (see [Structs](#structs)),
is `None`: a field left out of a struct's literal, an element of an array that's zeroed, or `found : int?` declared
without a value.

There are a few [operators built in](operators.md#optional-operators) to make life easier when dealing with optional values.

An optional compared with `==` or `!=` to a value of the type it holds is equal when it holds that value: `found == 3`
is false when `found` is `None`, and `error != OsError.NotFound` is true when there's no error at all. Two optionals
are equal when both are `None`, or both hold values that are equal.

An optional of a pointer that's never null, `ptr[T]?`, `cstring?` or an optional function, is just the pointer, with
`None` as a null pointer. It has no tag and the same size and layout as the pointer, so it matches a nullable pointer
in C and in other foreign layouts. `rawptr?` keeps its tag, since a `rawptr` can be `null` itself.

```
Node :: struct {
    next : ptr[Node]?,    // 8 bytes, null at the end of the list
    value : int,
}
```

## Pointers

Pointer types (besides `rawptr`) refer to the type they point to in square brackets. For example, `ptr[int]` is a pointer to an int.

```
ptr[ptr[int]] pointer to a pointer to an int
ptr[int[3]]   pointer to an array of 3 ints
ptr[int][3]   array of 3 pointers to ints
relptr8[int]  8-bit relative pointer to an int
```

There is no pointer arithmetic on regular pointers or relative pointers, though raw pointers (being closer to
integers) do allow it.

A `ptr[T]` is never null, so nothing in a program is ever at address 0 through one. On targets where address 0 is
memory, like an embedded vector table, code reaches it through a `rawptr` and the volatile intrinsics, and the target
sets `TargetOptions.address_zero_is_memory`, so those accesses aren't assumed never to happen
(`--address-zero-is-memory` on the command line).

### Relative Pointers

A relative pointer, `relptr8[T]` to `relptr64[T]`, holds where something is as an offset from its own address, in 1 to
8 bytes. It means the same wherever the memory holding it is mapped or copied to, so it's for memory that's shared
between processes, or written to disk: an IPC ring, a file's structures. An 8-bit one reaches 128 bytes below its own
address and 127 above.

```
Node :: struct {
    value : int,
    next : relptr32[Node],
    // None is offset 0, since a relative pointer to itself is never useful
    previous : relptr32[Node]?,
}

link :: fn(node: ptr[mut Node], after: ptr[Node]) {
    node.next = after          // the offset from node.next's address to after's
    node.previous = null
}

following :: fn(node: ptr[Node]) -> ptr[Node] {
    return node.next           // node.next's address, plus its offset
}
```

* **Setting one**: assigning a `ptr[T]` to a relative pointer stores the difference between the address it points to
  and the relative pointer's own address. If that doesn't fit in its bits, or is 0, a pointer to the relative pointer
  itself, the program stops through `context.assertion_handler` (or traps, without a context).
* **Reading one**: a relative pointer is read where it's stored, a field, an element or what a pointer points to, as
  the `ptr[T]` it holds, or for `relptrN[T]?`, a `ptr[T]?`. `&node.next` is a pointer to the relative pointer itself.
* **Never null**, like `ptr[T]`. Its optional, `relptrN[T]?`, is the same size, with offset 0 for `None`.
* **Never a value of its own**: a relative pointer means something only where it's stored, so a variable,
  parameter, result, literal or cast can't be one, or have one in it, and a struct with one in it isn't assigned
  whole: its fields are set where it is. Memory holding them can still be copied as bytes, and the copy's relative
  pointers lead around the copy.
* **Never into the stack**: setting one to a local's address is an error, as storing it through a pointer is (see
  [Pointers to the Stack](memory.md#pointers-to-the-stack)).

### Mutability

Nothing can be changed unless it's given `mut`, or declared where it can be:

* **Locals** declared with `:` or `:=` can be changed; constants (`::`) and parameters, which are copies, can't.
* **Pointers:** `ptr[T]` can only read what it points to, and `ptr[mut T]` can also change it. `rawptr` only reads too,
  and `mut rawptr` can change what it points to; a `ptr[mut T]` can be given as either, and a `ptr[T]` only as a
  `rawptr`.
* **Views:** `T[]` only reads its elements, and `mut T[]` can change them (see [Array Views](#array-views)).
* **Static and dynamic arrays** hold their elements, which can be changed where the array can be: in a local, or
  through a `ptr[mut T]`. A function that changes a dynamic array's elements takes a `mut T[]` view of them, or a
  `ptr[mut T[..]]` to change the array itself.

In `ptr[mut T]` the `mut` is the pointer's, so `ptr[mut u8[]]` can change the view it points to, but the view's
elements only read. A type in parentheses keeps its own `mut`: `ptr[mut (mut u8[])]` can change the view and its
elements, and `ptr[(mut u8[])]` only its elements, not which elements it views.

```
advance :: fn(view: ptr[mut (mut u8[])]) {
    current := view^
    if current.count > 0 {
        current[0] = 0
        view^ = current[1..<current.count]
    }
}
```

`mut` goes on what's reached through a type. On a type whose value is held as itself, like a parameter's `n: mut int`
or a field's `items : mut int[4]`, it would change nothing, so it's an error.

A struct is mutable or immutable as a whole: every field, and everything stored inline in it (nested structs, static
arrays), shares that. What a pointer field points to is different, its own type decides whether it can be changed:

```
Queue :: struct {
    first : ptr[mut Task]?,     // whoever can read the queue can change its tasks
    owner : ptr[Scheduler],     // but never the scheduler, even through a mutable queue
}
```

So a pointer field is `ptr[mut T]` when the code using the struct changes what it points to, and `ptr[T]` when it
only reads it. A view field is the same: `bytes : mut u8[]` can be written through by whoever can read the struct. An immutable struct can't point its fields elsewhere, but can still hand out a `ptr[mut T]`.

`new` returns a `ptr[mut T]`, since a new value has to be filled in. If it can't allocate one, it calls
`context.assertion_handler`; `new_aligned` and `new_array` return the `AllocatorError` instead, for code that handles it. A function that changes something it's given
takes a pointer to it, including dynamic arrays (`array_add(&names, name)`), since a value parameter is a copy.
Iterating through a pointer to an array dereferences it explicitly: `for name in names^`.

### Mutability in Type Arguments

A generic's type argument can be given with `mut`, so the generic can change what it points to:

```
Box :: struct[T] {
    value : ptr[T],
}

changeable : Box[mut Config]     // value is a ptr[mut Config]
read_only : Box[Config]          // value is a ptr[Config]
```

* **Inside the generic,** the parameter is the type wherever it's held by value, and the `mut` applies wherever it's
  pointed to: `ptr[T]` is `ptr[mut Config]`. Given on to another generic, like `Inner[T]`, the `mut` goes with it.
* **They're different instances:** `Box[Config]` and `Box[mut Config]` are two types, with their own functions.
* **Becoming read-only.** An instance given `mut` is accepted where the same one without it is wanted, when the
  parameters that differ are only ever pointed to in the struct's fields, so the two are laid out the same:
  `read_only = changeable` works for `Box`, but not for a struct holding a `T` in place.
* **Constraints** can ask for it: `T: compiler.Mutable` is satisfied by `mut Config`, and in a body checked before any
  instance (see [Checked Bodies](#checked-bodies)), writing through a `ptr[T]` needs it.
* `mut` is written where a type is, like `Box[mut Config]` or `f[mut Config](box)`, including a constraint's argument
  in an expression: `#assert compiler.satisfies(compiler.Mutable(mut Config))`.

## Result Types

Results are built in, defined like this:

```
Result :: union[T, E] {
    Ok(T),
    Error(E),
}
```

A variant can be named with the type's arguments, like `Result[int, string].Error("missing")`, where nothing
says which `Result` is meant.

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

The string is each line's text after its `\\`, exactly as written, with the lines joined by newlines and no newline
after the last. Escapes aren't worked out in them, so `\\a\n` is the three characters `a`, `\` and `n`.

A string literal, or a constant one, has a string's members and bytes: `"abc".count` is 3 and `"abc"[1]` is `'b'`.

## Structs

Structs are user defined groups of data. Structs cannot have any "private" fields, everything is public. Members are accessed using the `.` operator.

Structs do not have any methods or member functions, though they can store functions as a member since they are first-class entities.

All values are initialized to zero, except where default values are provided for a field. A default is a compile-time
constant: a literal, a named constant, arithmetic on integers, or an enum member. A named constant can be of any type
the field takes, a struct's literal included, and a function named is the field's function, so `op : fn(x: int) -> int =
twice` calls `twice` until it's set to something else. A struct that holds another starts that one with its own
defaults too.

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
    // The included struct is one field of the literal
    vec3 : MyVec3 = MyVec3.{MyVec2.{1, 2}, 3}
    // Works fine, since it contains the vec2 fields explicitly
    vec_length(vec3)
}
```

`using` can also name a field, `using name : type`, for a struct held in place or a pointer to one. Its members can
be used as the struct's own, and the field is still there by its name:

```
Handle :: struct[T] {
    using value : ptr[mut T],
    uses : int,
}

handle.width = 30           // handle.value.width
size :: handle.value        // the pointer itself

View :: struct {
    using config : ptr[Config],
}

view.width = 30             // error: Config is reached through a ptr without mut
```

* **Through a pointer,** what's reached can be changed only if the pointer is `ptr[mut T]`, as when it's written out.
* **The struct's own members come first:** a member of the same name in the struct, or included by value, hides one
  reached through a pointer.
* **Only member access** goes through it: a `Handle[Config]` isn't a `ptr[Config]`, so passing one on is written
  `handle.value`.
* A pointer to something without members, like `ptr[int]`, is allowed, and adds nothing, so a generic like `Handle`
  works for any `T`.

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

A literal sets the members it names, in order, over zeros, so a later one overwrites what it overlaps:
`Overlay.{word = 0x01020304}`. The other members' defaults are left out once any member is given, since they'd
overwrite it. A constant's literal works the same way, as long as what it gives is numbers, booleans, enums, or
structs and fixed arrays of them, whose bytes are known before the program is linked.

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

## Types Declared in Functions

A struct, union, enum or alias can be declared inside a function, like one at the top level. It's seen from where
it's declared to the end of its block, by the types and functions declared after it there too, and it hides a type of
the same name from the package while it's seen. Two functions' types with one name are two types.

```
measure :: fn() -> int {
    Point :: struct { x : int, y : int }
    Line :: struct { from : Point, to : Point }   // made of the one above

    length :: fn(line: Line) -> int {               // a function declared after them sees them
        return line.to.x - line.from.x
    }
    return length(Line.{from = Point.{x = 1, y = 0}, to = Point.{x = 4, y = 0}})
}
```

In a generic function, each instance has its own, so they can use its generic parameters, like `T[count]` in
`fn[T, count: usize]`. A type declared inside a function can be generic itself, like `Pair :: struct[U] { ... }`, and
used with its arguments, `Pair[int]`, after it; in a generic function, it can use both its own parameters and the
function's.

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

`alias` is required after `distinct`. If the type is not distinct, `alias` is optional, and shows that the value is
meant to be a type without spelling out `: type`. These are all the same:

```
my_int :: i32
my_int :: alias i32
my_int : type : i32
```

### Alias Equality
The compiler understands the underlying type of an alias. For type checking, like whether a value can be assigned
or passed without a cast, an alias is the same type as what it aliases, but distinct aliases are considered different.

Let's say we have a few aliases for integer:
```
index   :: alias int
ind     :: alias index
counter :: distinct alias index

number :: distinct alias int
num    :: alias number
age    :: distinct alias number
```

As a diagram, they might look like this:
```
            int
           /   \
          /  (distinct)
         /       \
    index         number
    /  \           /  \
   / (distinct)   / (distinct)
  /      \       /      \
ind   counter  num     age

```

This table indicates whether each pair of types would be
considered the "same" type.

|         | int | index |ind | counter | number | num | age |
|---------|-----|-------|----|---------|--------|-----|-----|
| int     | ==  | ==    | == |         |        |     |     |
| index   | ==  | ==    | == |         |        |     |     |
| ind     | ==  | ==    | == |         |        |     |     |
| counter |     |       |    | ==      |        |     |     |
| number  |     |       |    |         | ==     | ==  |     |
| num     |     |       |    |         | ==     | ==  |     |
| age     |     |       |    |         |        |     | ==  |

### Comparing Type Values

Type values (of type `type`) can be compared at compile time, in `#assert` and `#if` too, and at run time. `==` and
`!=` compare them as the table above does: an alias that isn't distinct is the type it names, so `ind == int` is true,
and a distinct one is a type of its own, so `counter == int` is false. `types_are_aliases(a, b)` says the same, for code
that wants to say it's following aliases; it takes type values worked out at run time too.

### Generic Aliases

An alias can have generic parameters of its own, in a list after `alias`, to name the instances of a generic type with
some of its arguments fixed:

```
Pair :: struct[A, B] { first : A, second : B }

Named :: alias[V] Pair[string, V]
Twin :: distinct alias[T] Pair[T, T]

SmallRing :: alias[T, capacity: usize] RingBuffer[T, capacity] where Small(capacity)
```

* `Named[int]` is `Pair[string, int]`, and the same type as it, by the rules above. `Twin[int]` is distinct from
  `Pair[int, int]`.
* An alias takes its own generic arguments, not those of what it names: `Named[int, int]` is an error (E4014).
* An alias can have constraints and a `where` clause, like any generic, checked first. What it names checks its own
  constraints too, so `SmallRing[u8, 0]` isn't made because of `RingBuffer`'s `AtLeastOne`, and `SmallRing[u8, 128]`
  because of `Small`.

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


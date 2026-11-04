package builtin

// Constants
/** The empty value: an optional's None, and a rawptr that points nowhere. A ptr[T] is never null. */
null  :: null
/** The boolean false, stored as 0. */
false :: 0!=0
/** The boolean true, stored as 1. */
true  :: 0==0

// Booleans
/** An 8-bit boolean: 0 is false, 1 is true. */
b8   :: alias b8
/** A 16-bit boolean, for layouts that want a boolean of that size. */
b16  :: alias b16
/** A 32-bit boolean, for layouts that want a boolean of that size. */
b32  :: alias b32
/** A 64-bit boolean, for layouts that want a boolean of that size. */
b64  :: alias b64
/** The usual boolean, true or false: the same type as b8. */
bool :: alias b8

// Signed integers
/** An 8-bit signed integer, -128 to 127. */
i8    :: alias i8
/** A 16-bit signed integer, in the target's byte order. */
i16   :: alias i16
/**
 * A 16-bit signed integer stored big-endian on every target (docs/types.md, Endian-Specific Types). It has no
 * arithmetic of its own: in an operator it's an i16.
 */
i16be :: alias i16be
/**
 * A 16-bit signed integer stored little-endian on every target (docs/types.md, Endian-Specific Types). It has no
 * arithmetic of its own: in an operator it's an i16.
 */
i16le :: alias i16le
/** A 32-bit signed integer, in the target's byte order. */
i32   :: alias i32
/** A 32-bit signed integer stored big-endian on every target (docs/types.md, Endian-Specific Types). */
i32be :: alias i32be
/** A 32-bit signed integer stored little-endian on every target (docs/types.md, Endian-Specific Types). */
i32le :: alias i32le
/** A 64-bit signed integer, in the target's byte order. */
i64   :: alias i64
/** A 64-bit signed integer stored big-endian on every target (docs/types.md, Endian-Specific Types). */
i64be :: alias i64be
/** A 64-bit signed integer stored little-endian on every target (docs/types.md, Endian-Specific Types). */
i64le :: alias i64le
/** A 128-bit signed integer, in the target's byte order. */
i128   :: alias i128
/** A 128-bit signed integer stored big-endian on every target (docs/types.md, Endian-Specific Types). */
i128be :: alias i128be
/** A 128-bit signed integer stored little-endian on every target (docs/types.md, Endian-Specific Types). */
i128le :: alias i128le
/**
 * The usual signed integer, a register's size: at least as large as uintptr, and the same size as uint. A literal
 * with nothing else to decide its type is an int.
 */
int   :: alias int

// Unsigned integers
/** An 8-bit unsigned integer, 0 to 255: a byte. */
u8      :: alias u8
/** A 16-bit unsigned integer, in the target's byte order. */
u16     :: alias u16
/** A 16-bit unsigned integer stored big-endian on every target (docs/types.md, Endian-Specific Types). */
u16be   :: alias u16be
/** A 16-bit unsigned integer stored little-endian on every target (docs/types.md, Endian-Specific Types). */
u16le   :: alias u16le
/** A 32-bit unsigned integer, in the target's byte order. */
u32     :: alias u32
/**
 * A 32-bit unsigned integer stored big-endian on every target, like a network header's length (docs/types.md,
 * Endian-Specific Types).
 */
u32be   :: alias u32be
/** A 32-bit unsigned integer stored little-endian on every target (docs/types.md, Endian-Specific Types). */
u32le   :: alias u32le
/** A 64-bit unsigned integer, in the target's byte order. */
u64     :: alias u64
/** A 64-bit unsigned integer stored big-endian on every target (docs/types.md, Endian-Specific Types). */
u64be   :: alias u64be
/** A 64-bit unsigned integer stored little-endian on every target (docs/types.md, Endian-Specific Types). */
u64le   :: alias u64le
/** A 128-bit unsigned integer, in the target's byte order. */
u128    :: alias u128
/** A 128-bit unsigned integer stored big-endian on every target (docs/types.md, Endian-Specific Types). */
u128be  :: alias u128be
/** A 128-bit unsigned integer stored little-endian on every target (docs/types.md, Endian-Specific Types). */
u128le  :: alias u128le
/** The usual unsigned integer, a register's size: at least as large as uintptr, and the same size as int. */
uint    :: alias uint
/** An unsigned integer large enough to hold any pointer's bits: the size of a pointer on the target. */
uintptr :: alias uintptr
/** An unsigned integer the size of uintptr, for sizes, counts and indexes. */
usize   :: alias usize

// Floating points
/** A 16-bit (half-precision) IEEE-754 floating point number. */
f16   :: alias f16
/** A 16-bit IEEE-754 floating point number stored big-endian on every target. */
f16be :: alias f16be
/** A 16-bit IEEE-754 floating point number stored little-endian on every target. */
f16le :: alias f16le
/** A 32-bit (single-precision) IEEE-754 floating point number. */
f32   :: alias f32
/** A 32-bit IEEE-754 floating point number stored big-endian on every target. */
f32be :: alias f32be
/** A 32-bit IEEE-754 floating point number stored little-endian on every target. */
f32le :: alias f32le
/** A 64-bit (double-precision) IEEE-754 floating point number. */
f64   :: alias f64
/** A 64-bit IEEE-754 floating point number stored big-endian on every target. */
f64be :: alias f64be
/** A 64-bit IEEE-754 floating point number stored little-endian on every target. */
f64le :: alias f64le

// Complex numbers, of two f16s, f32s or f64s
/** A complex number of two f16s, its real part first, then its imaginary part (docs/types.md). */
c32  :: alias c32
/** A complex number of two f32s, its real part first, then its imaginary part (docs/types.md). */
c64  :: alias c64
/**
 * A complex number of two f64s, its real part first, then its imaginary part: what a complex literal is when nothing
 * else decides its type (docs/types.md, Complex Numbers and Quaternions).
 */
c128 :: alias c128

// Quaternions, of four f16s, f32s or f64s
/** A quaternion of four f16s, laid out x, y, z (its imaginary parts), then w (its real part). */
q64  :: alias q64
/** A quaternion of four f32s, laid out x, y, z (its imaginary parts), then w (its real part), like (x, y, z, w). */
q128 :: alias q128
/**
 * A quaternion of four f64s, laid out x, y, z (its imaginary parts), then w (its real part): what a quaternion literal
 * is when nothing else decides its type (docs/types.md, Complex Numbers and Quaternions).
 */
q256 :: alias q256

// Strings
/**
 * Text in UTF-8, as a count of bytes and the address of the first: not null-terminated, and laid out as the count,
 * then the address.
 */
string  :: alias string
/** A C-style string: the address of UTF-8 bytes ending in a 0 byte. Never null; cstring? can be. */
cstring :: alias cstring
/** One byte of UTF-8 text, a code unit, not a whole code point. */
char    :: alias char

// Pointers
/**
 * A pointer to a T, which is never null: ptr[T] only reads what it points to, and ptr[mut T] can change it. ptr[T]?
 * is the nullable pointer, the same size, with None as address 0 (docs/types.md, Pointers).
 *
 * @tparam T What it points to.
 */
ptr[T] :: alias ptr[T]
/**
 * A pointer to anything, like C's const void*; mut rawptr is C's void*. It can be null, and it alone has pointer
 * arithmetic.
 */
rawptr :: alias rawptr
/**
 * A pointer held as an 8-bit offset from its own address, reaching 128 bytes below it and 127 above, so it means the
 * same wherever its memory is mapped or copied (docs/types.md, Relative Pointers). Never null; its optional uses offset
 * 0 for None.
 *
 * @tparam T What it points to.
 */
relptr8[T] :: alias relptr8[T]
/**
 * A pointer held as a 16-bit offset from its own address (docs/types.md, Relative Pointers).
 *
 * @tparam T What it points to.
 */
relptr16[T] :: alias relptr16[T]
/**
 * A pointer held as a 32-bit offset from its own address (docs/types.md, Relative Pointers).
 *
 * @tparam T What it points to.
 */
relptr32[T] :: alias relptr32[T]
/**
 * A pointer held as a 64-bit offset from its own address (docs/types.md, Relative Pointers).
 *
 * @tparam T What it points to.
 */
relptr64[T] :: alias relptr64[T]

// SIMD vectors, and bits of a vector register (docs/types.md, Vectors)
/**
 * Several values of one type, its lanes, which operators work on all at once with the CPU's vector instructions where
 * it has them. Aligned to its size, up to 64 bytes.
 *
 * @tparam T Each lane's type: an integer or float of up to 64 bits in the target's own byte order, or bool.
 * @tparam count How many lanes: a power of two, with the whole at most 64 bytes.
 */
vector[T, count: usize] :: alias vector[T, count]
/** 128 bits of a vector register without lanes of their own: they take &, |, ~ and bit_cast, as AES needs. */
v128 :: alias v128
/** 256 bits of a vector register without lanes of their own: they take &, |, ~ and bit_cast. */
v256 :: alias v256
/** 512 bits of a vector register without lanes of their own: they take &, |, ~ and bit_cast. */
v512 :: alias v512

// Optional values (T? is Optional[T]) and results are in generic_types.hsc

// Type info
/**
 * A value of any type, as its fields data, a rawptr to it, and type, its type. Converting a value to one copies it into
 * the current stack frame, so an any can't outlive the frame that made it (docs/types.md, Any).
 */
any  :: alias any
/**
 * A type as a value: at run time, the address of the type's read-only description, which type_info_of returns. Two are
 * equal when they're the same type, following aliases that aren't distinct.
 */
type :: alias type

// Functions
/**
 * Give the alignment a type's values need, worked out when the program is compiled.
 *
 * @tparam T The type, bound by the argument.
 * @param T The type; it has to be complete, its size known.
 * @return The alignment in bytes, a power of two, at least 1.
 */
align_of : fn[T](T: type) -> usize : ---
/**
 * Give the size of a type's values, worked out when the program is compiled; a static array's is its element's size
 * times its count, so size_of(i8[10][5]) is 50.
 *
 * @tparam T The type, bound by the argument.
 * @param T The type; it has to be complete, its size known.
 * @return The size in bytes, padding included, as an array of them would place them apart.
 */
size_of  : fn[T](T: type) -> usize : ---
/**
 * Give a struct member's offset from the start of the struct, like offset_of(Header, magic), worked out when the
 * program is compiled.
 *
 * @tparam T The struct type, bound by the argument.
 * @param T The struct type; it has to be complete.
 * @param member The member's name, written as it is, not as a string.
 * @return The member's offset in bytes from the struct's first byte.
 */
offset_of : fn[T](T: type, member: expr) -> usize : ---

/**
 * Give the type of an expression, as a type value.
 *
 * @param x The expression, any value at all.
 * @return Its type, as the compiler worked it out.
 */
type_of : fn(x: expr) -> type : ---
/**
 * Give a type's description, the read-only one the compiler builds for every type a program uses as a value.
 *
 * Cast the result to the variant's struct (TypeInfoStruct, TypeInfoEnum, ...) to read its details. int, uint, usize
 * and uintptr are described like the fixed-size integers they're laid out as.
 *
 * @tparam T The type, when it's given as one.
 * @param T The type, written as one or a type value worked out at run time, like an any's type.
 * @return The description, never null, valid for the whole program; its variant says which struct it is.
 */
type_info_of : fn[T](T: type) -> ptr[TypeInfo] : ---
/**
 * Tell whether the compiler treats a and b as the same type, following aliases that aren't distinct, as == on type
 * values does too (docs/types.md, Comparing Type Values).
 *
 * @param a The first type, written as one or a type value worked out at run time.
 * @param b The second type, the same way.
 * @return True when they're the same type, after plain aliases; false when either is a distinct alias of the other.
 */
types_are_aliases : fn(a, b: type) -> bool : ---

/**
 * Tell whether a type's values are secrets (docs/memory.md, Secrets), for a generic that treats them differently, as
 * runtime.free does by wiping them.
 *
 * @param T Any type; one that isn't #secret, nor an array or vector of one, gives false.
 * @return True when it's #secret, or an array or vector of one; false otherwise.
 */
is_secret_type : fn(T: type) -> bool : ---

/**
 * Tell whether a type's values start with something other than zero (docs/types.md, Structs).
 *
 * new and new_array store the defaults, with intrinsics.store_defaults, when it's true; when it's false, the zeroed
 * memory an allocator gives is the whole value.
 *
 * @param T Any type; only a struct, or a static array of one, can give true.
 * @return True for a struct with a field's default, in it or in a struct or static array it holds, or a static array
 *     of such a struct; false otherwise.
 */
has_defaults : fn(T: type) -> bool : ---

/**
 * Give a complex number's or a quaternion's real part (docs/types.md, Complex Numbers and Quaternions).
 *
 * @param x A complex number or quaternion.
 * @return Its real part, a float of its parts' type: f32 for a c64.
 */
real : fn(x: expr) -> any : ---
/**
 * Give a complex number's or a quaternion's i imaginary part.
 *
 * @param x A complex number or quaternion.
 * @return Its i part, a float of its parts' type; a quaternion's x.
 */
imag : fn(x: expr) -> any : ---
/**
 * Give a quaternion's j imaginary part.
 *
 * @param q A quaternion.
 * @return Its j part, a float of its parts' type; its y.
 */
jmag : fn(q: expr) -> any : ---
/**
 * Give a quaternion's k imaginary part.
 *
 * @param q A quaternion.
 * @return Its k part, a float of its parts' type; its z.
 */
kmag : fn(q: expr) -> any : ---
/**
 * Give a complex number's or a quaternion's conjugate.
 *
 * @param x A complex number or quaternion.
 * @return x with its imaginary parts negated, of the same type.
 */
conj : fn(x: expr) -> any : ---
/**
 * Give a number's magnitude.
 *
 * @param x A complex number, quaternion, integer or float.
 * @return For a complex number or quaternion, the square root of the sum of its parts' squares, a float of its parts'
 *     type; for an integer or a float, its absolute value, of its own type.
 */
abs : fn(x: expr) -> any : ---

/**
 * Give the largest value a number type holds, worked out when the program is compiled.
 *
 * @tparam T The type, bound by the argument.
 * @param T An integer, char or float type.
 * @return For an integer or char, its largest value, like 255 for u8; for a float, its largest finite value, not
 *     infinity.
 */
max_value : fn[T](T: type) -> T : ---
/**
 * Give the smallest value a number type holds, worked out when the program is compiled.
 *
 * @tparam T The type, bound by the argument.
 * @param T An integer, char or float type.
 * @return For a signed integer, its most negative value; for an unsigned one or a char, 0; for a float, the most
 *     negative finite value, not negative infinity.
 */
min_value : fn[T](T: type) -> T : ---

/**
 * Mark code still to write, and stop the program if it's reached (docs/functions.md, Functions Still to Write).
 *
 * Reaching it calls context.assertion_handler with message, so it never returns, and a function whose body is todo()
 * needs no return.
 *
 * @param message What's missing, given to the assertion handler.
 * @param location Where todo was called, which the handler reports; the caller's own by default.
 */
todo : fn(message := "not implemented yet", location := #caller_location) #never_returns : ---

package builtin

// Constants
null  :: null
false :: 0!=0
true  :: 0==0

// Booleans
b8   :: alias b8
b16  :: alias b16
b32  :: alias b32
b64  :: alias b64
bool :: alias b8

// Signed integers
i8  :: alias i8
i16 :: alias i16
i32 :: alias i32
i64 :: alias i64
int :: alias int

// Unsigned integers
u8      :: alias u8
u16     :: alias u16
u32     :: alias u32
u64     :: alias u64
uint    :: alias uint
uintptr :: alias uintptr

// Floating points
f16   :: alias f16
f32   :: alias f32
f64   :: alias f64

// Complex numbers
c16  :: alias c16
c32  :: alias c32
c64  :: alias c64
c128 :: alias c128

// Quaternions
q32  :: alias q32
q64  :: alias q64
q128 :: alias q128
q256 :: alias q256

// Strings
string  :: alias string
cstring :: alias cstring

// Pointers
ptr<T> :: alias ptr<T>
rawptr :: alias rawptr

// Type info
any  :: alias any
type :: alias type

// Functions
panic :: fn(str: string) #foreign

align_of :: fn($T: type) -> int #foreign
size_of  :: fn($T: type) -> int #foreign

type_of :: fn(x: expr) -> type #foreign
type_info_of :: fn($T: type) -> TypeInfo #foreign


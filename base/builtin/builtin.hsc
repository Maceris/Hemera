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
i8    :: alias i8
i8be  :: alias i8be
i8le  :: alias i8le
i16   :: alias i16
i16be :: alias i16be
i16le :: alias i16le
i32   :: alias i32
i32be :: alias i32be
i32le :: alias i32le
i64   :: alias i64
i64be :: alias i64be
i64le :: alias i64le
int   :: alias int

// Unsigned integers
u8      :: alias u8
u8be    :: alias u8be
u8le    :: alias u8le
u16     :: alias u16
u16be   :: alias u16be
u16le   :: alias u16le
u32     :: alias u32
u32be   :: alias u32be
u32le   :: alias u32le
u64     :: alias u64
u64be   :: alias u64be
u64le   :: alias u64le
uint    :: alias uint
uintptr :: alias uintptr

// Floating points
f16   :: alias f16
f16be :: alias f16be
f16le :: alias f16le
f32   :: alias f32
f32be :: alias f32be
f32le :: alias f32le
f64   :: alias f64
f64be :: alias f64be
f64le :: alias f64le

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
panic :: fn(str: string) ---

align_of :: fn($T: type) -> int ---
size_of  :: fn($T: type) -> int ---

type_of :: fn(x: expr) -> type ---
type_info_of :: fn($T: type) -> TypeInfo ---

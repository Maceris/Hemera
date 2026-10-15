package types

import runtime from "base"

// Fields in order, each at its alignment; the struct is aligned to its most aligned field
Mixed :: struct {
    a : u8,
    b : u32,
    c : u16,
    d : u64,
}

Packed :: struct #packed {
    a : u8,
    b : u32,
}

// #align only raises the alignment
Aligned :: struct #align(16) {
    a : u8,
}

PackedAligned :: struct #packed #align(4) {
    a : u8,
    b : u32,
}

// docs/types.md, Structs
Floats :: struct #packed {
    f1, f2 : f32,
}

MoreComplex :: struct #union {
    a : i32,
    _ : struct #packed { b1, b2 : i16 },
    c : Floats,
    using Floats,
    d : u64,
}

MyVec2 :: struct {
    x : f32,
    y : f32,
}

MyVec3 :: struct {
    using MyVec2,
    z : f32,
}

// Pointers can refer to a type that isn't laid out yet, including itself
Node :: struct {
    next : ptr[mut Node],
    value : int,
    rest : Node[],
}

Suit :: enum #backed_by(u8) {
    Clubs,
    Hearts,
    Spades,
    Diamonds,
}

LogLevel :: enum {
    TRACE = 0,
    DEBUG = 10,
    INFO = 20,
    VERBOSE_INFO,
}

// A tag, then each variant's values like a struct's fields
Shape :: union {
    Circle(f32),
    Rectangle(u8, u64),
    Empty,
}

Pair :: struct[A, B] {
    first : A,
    second : B,
}

UsesPair :: struct {
    pair : Pair[u8, u64],
    swapped : Pair[u64, u8],
}

MaybeInt :: int?
MaybePointer :: ptr[int]?

index :: alias int
counter :: distinct alias int
my_int :: i32

Strings :: struct {
    view : string,
    raw : cstring,
    some : u8[],
    many : u8[..],
    fixed : u8[4][3],
    anything : any,
    kind : type,
}

Handler :: fn(code: int, name: string) -> bool

handle :: fn(code: int, values #escaping : ptr[u8], rest: int...) -> (ok: bool, count: usize) #never_returns {
}

intrinsic : fn(int) -> int : ---

COUNT : u8 : 5
UNTYPED :: 5
SAME_AS_COUNT :: COUNT
SUIT :: Suit.Hearts
BYTES :: u8.[1, 2, 3]

Layouts :: struct {
    view : runtime.StringView,
    array : runtime.ArrayView,
    resizable : runtime.ResizableArray,
}

package valid_scenarios

Pair :: struct[A, B] {
    first : A,
    second : B,
}

Maybe :: union[T] {
    Nothing,
    Just(T),
}

// Bound by inference from the parameter's type
swap :: fn[A, B](pair: Pair[A, B]) -> Pair[B, A] {
    return Pair[B, A].{pair.second, pair.first}
}

// Bound by the parameter with the same name: a type, or a compile-time value
zeroed :: fn[T](T: type) -> T {
    value : T
    return value
}
buffer :: fn[count](count: usize) -> u8[count] {
    result : u8[count]
    return result
}

// Bound explicitly
empty :: fn[T]() -> T[..] {
    result : T[..]
    return result
}

use_generics :: fn() {
    pair :: Pair[int, string].{1, "one"}
    named :: Pair[int, Maybe[string]].{first = 2, second = .Nothing}
    pairs :: Pair[int, int].[Pair[int, int].{1, 2}, Pair[int, int].{3, 4}]
    context_value :: runtime.Context.{allocator = runtime.FAILING_ALLOCATOR}
    swapped :: swap(pair)
    nothing : Maybe[int] = .Nothing
    zero :: zeroed(int)
    bytes :: buffer(16)
    names :: empty[string]()
}

// Values in generic lists
Ring :: struct[T, capacity: usize] {
    items : T[capacity],
    head : usize,
    tail : usize,
}

Settings :: struct[enabled: bool, mode: Mode] {
    level : int,
}

push :: fn[T, capacity: usize](ring: ptr[mut Ring[T, capacity]], item: T) {
    ring.items[ring.tail] = item
}

use_values :: fn() {
    ring : Ring[u8, 4096]
    settings : Settings[true, .Fast]
    offsets : Offsets[-1, MAX_OFFSET]
    empty_ring :: Ring[u8, 16].{}
    push(&ring, 7)
}

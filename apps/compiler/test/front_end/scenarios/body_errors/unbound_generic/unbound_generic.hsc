package unbound_generic

empty :: fn[T]() -> T[..] {
    result : T[..]
    return result
}

f :: fn() {
    // Nothing says what T is: it needs empty[int]()
    numbers := empty()
}

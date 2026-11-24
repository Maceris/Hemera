package stack_after_undeclared

/*
 * A body with an undeclared name (E4008) isn't checked for pointers into the stack; its callers, which pass it
 * pointers into theirs and keep what it gives back, aren't told those escape, which would bury the one error that
 * matters under one for each
 */

holder :: struct {
    kept : ptr[int],
}

first :: fn(value : ptr[int]) -> ptr[int] {
    return not_declared_anywhere
}

keep :: fn(into : ptr[mut holder]) {
    x := 5
    into.kept = first(&x)
}

hand_back :: fn() -> ptr[int] {
    y := 6
    return first(&y)
}

main :: fn() {
    h := holder.{}
    keep(&h)
    _ = hand_back()
}

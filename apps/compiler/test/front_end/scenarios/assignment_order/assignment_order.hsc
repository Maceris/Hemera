package assignment_order

/*
 * An assignment whose right side calls something given &out, as its left side's call is (W4003), once; and the same
 * written in order, and others like it that aren't, without a warning.
 */

Message :: struct {
    used : u32,
    words : u32[8],
}

Named :: union {
    Nothing,
    Named(u32),
}

begin :: fn(out: ptr[mut Message]) -> ptr[mut Named] {
    out.used = 1
    return cast[ptr[mut Named]](&out.words[0])
}

append :: fn(out: ptr[mut Message], value: u32) -> u32 {
    out.used += 1
    return out.used
}

count :: fn(out: ptr[Message]) -> u32 {
    return out.used
}

main :: fn() -> int {
    out := Message.{}
    other := Message.{}
    // Warned of: append runs before begin
    begin(&out)^ = .Named(append(&out, 3))
    // In order
    message :: begin(&out)
    message^ = .Named(append(&out, 3))
    // Another variable on the right
    begin(&out)^ = .Named(append(&other, 3))
    // Nothing called on the left
    out.used = append(&out, 4)
    return cast[int](count(&out))
}

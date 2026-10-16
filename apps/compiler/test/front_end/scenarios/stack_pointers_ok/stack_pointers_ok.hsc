package stack_pointers_ok

/*
 * What docs/memory.md, Pointers to the Stack, allows: none of this is reported.
 */

sum :: fn(values: int[]) -> int {
    total := 0
    for value in values {
        total += value
    }
    return total
}

count_all :: fn(values: any...) -> usize {
    return values.count
}

// Returning what came from a parameter
trim :: fn(text: string) -> string {
    if text.count == 0 {
        return text
    }
    return text[1..<text.count]
}

first_of :: fn(values: int[]) -> ptr[int] {
    if values.count == 0 {
        todo()
    }
    return &values[0]
}

Holder :: struct { values : int[] }

use_holder :: fn(holder: Holder) -> usize {
    return holder.values.count
}

Parser :: struct #scoped {
    input : u8[],
    line : u32,
}

// Storing back what came through the same #scoped pointer
advance :: fn(parser: ptr[mut Parser]) {
    if parser.input.count == 0 {
        return void
    }
    parser.input = parser.input[1..<parser.input.count]
    parser.line += 1
}

Registry :: struct { first : string }

register :: fn(registry: ptr[mut Registry], name #escaping : string) {
    registry.first = name
}

Shape :: union {
    Circle(f64),
    Label(string),
}

label_length :: fn(shape: ptr[Shape]) -> usize {
    match shape^ {
        case Label(text) => return text.count
        case _ => return 0
    }
}

GREETING :: "hello"

main :: fn(registry: ptr[mut Registry]) -> int {
    buffer : int[16]
    total := sum(buffer)
    count := count_all(total, buffer[0], "text")
    holder := Holder.{ values = buffer }
    length := use_holder(holder)

    bytes : u8[64]
    parser := Parser.{ input = bytes, line = 0 }
    advance(&parser)

    // Pointers within one block, and into an outer block from an inner one
    x := 5
    p := &x
    {
        q := &x
        q^ = 6
    }
    for &element in buffer {
        element^ = 1
    }
    view : int[] = buffer
    trimmed := trim(GREETING)
    first := first_of(buffer)
    register(registry, GREETING)
    label := Shape.Label("text")
    return total + p^ + first^ + cast[int](length + count + view.count + trimmed.count + label_length(&label))
}

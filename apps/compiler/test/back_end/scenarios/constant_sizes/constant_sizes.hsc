/*
 * Constants where types and values meet: #run as an array's count, a multi-dimensional array type in an expression,
 * a string literal's members, and #file_path (docs/compilation.md, docs/types.md, docs/directives.md). main returns
 * 42 if they all held, or the number of the first that didn't.
 */
package constant_sizes

fib :: fn(n: int) -> int {
    return if n < 2 { n } else { fib(n - 1) + fib(n - 2) }
}

Ring :: struct[T, capacity: usize] {
    items : T[capacity],
}

check :: fn(ok: bool, code: int) -> int {
    if ok {
        return 0
    }
    return code
}

ends_with :: fn(text: string, suffix: string) -> bool {
    if suffix.count > text.count {
        return false
    }
    for i in 0..<suffix.count {
        at :: text.count - suffix.count + i
        if at < text.count && text[at] != suffix[i] {
            return false
        }
    }
    return true
}

main :: fn() -> int {
    errors := 0
    numbers : int[#run fib(5)]
    errors += check(numbers.count == 5, 1)
    ring : Ring[u8, #run fib(6)]
    errors += check(ring.items.count == 8, 2)
    errors += check(size_of(i8[10][5]) == 50 && size_of(u16[3][2][2]) == 24, 3)
    errors += check("abc".count == 3 && "abc"[1] == 'b', 4)
    path :: #file_path
    errors += check(ends_with(path, "constant_sizes.hsc"), 5)
    if errors == 0 {
        return 42
    }
    return errors
}

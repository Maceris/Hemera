package local_generic_types

/*
 * Generic types declared in a function (docs/types.md, Types Declared in Functions): a struct and a union with
 * their own parameters, using the generic function's T and a type declared before them, in a nested function's
 * signature, and with a variant without values, Either[u8].Neither, in two instances checked at once. main
 * returns 42 if every instance is laid out and works as its arguments say.
 */

wrapped :: fn[T](value: T, extra: int) -> int {
    Tag :: struct {
        mark : int,
    }
    Both :: struct[U] {
        outer : T,
        inner : U,
        tag : Tag,
    }
    Either :: union[U] {
        Left(U),
        Right(T),
        Neither,
    }
    sum :: fn(both: Both[int]) -> int {
        return both.inner + both.tag.mark
    }
    both := Both[int].{ outer = value, inner = extra, tag = Tag.{ mark = 1 } }
    left : Either[u8] = .Left(cast[u8](2))
    nothing := Either[u8].Neither
    from_left := match left {
        case Left(x) => cast[int](x)
        case Right(_) => 100
        case Neither => 100
    }
    from_nothing := match nothing {
        case Left(_) => 100
        case Right(_) => 100
        case Neither => 3
    }
    return sum(both) + from_left + from_nothing + cast[int](size_of(Both[u8]) > 0)
}

// In a function that isn't generic, a generic type of its own
plain :: fn() -> int {
    Pair :: struct[U] {
        a : U,
        b : U,
    }
    small := Pair[u8].{ a = 1, b = 2 }
    return cast[int](small.a + small.b)
}

main :: fn() -> int {
    // 30 + 1 + 2 + 3 + 1 and 0 + 1 + 2 + 3 + 1, less 5, and plain's 3
    return wrapped(cast[u8](9), 30) + wrapped(true, 0) - 5 + plain()
}

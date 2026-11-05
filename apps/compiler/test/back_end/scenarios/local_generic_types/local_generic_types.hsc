package local_generic_types

import testing from "std"

/*
 * Generic types declared in a function (docs/types.md, Types Declared in Functions): a struct and a union with
 * their own parameters, using the generic function's T and a type declared before them, in a nested function's
 * signature, and with a variant without values, Either[u8].Neither, in two instances checked at once.
 */

/**
 * Build values of generic types declared here, with this function's T, and add up what they hold.
 *
 * @param value Held as the struct's outer, of the instance's T; only its type matters.
 * @param extra Held as the struct's inner, an int.
 * @return extra + 1 (the tag's mark) + 2 (a Left) + 3 (a Neither) + 1 (the struct has a size): extra + 7.
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

/**
 * Build a value of a generic type declared in a function that isn't generic.
 *
 * @return 3, the sum of the pair's two u8s.
 */
plain :: fn() -> int {
    Pair :: struct[U] {
        a : U,
        b : U,
    }
    small := Pair[u8].{ a = 1, b = 2 }
    return cast[int](small.a + small.b)
}

lays_out_each_instances_local_types #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, wrapped(cast[u8](9), 30), 37, "30 + 1 + 2 + 3 + 1, with T a u8")
    testing.expect_eq(t, wrapped(true, 0), 7, "0 + 1 + 2 + 3 + 1, with T a bool: an instance's types are its own")
    return .Ok
}

declares_generic_types_in_plain_functions #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, plain(), 3, "the Pair[u8] holds 1 and 2")
    return .Ok
}

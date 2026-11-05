package generic_type_insertions

import compiler from "base"
import testing from "std"

/*
 * #insert in a generic type (docs/compilation.md, Code Values): each instance inserts into a tree of its own, so
 * a field inserted can use the type's parameter, among a struct's fields and a union's variants. Run with
 * hemera --test.
 */

counted :: fn() -> compiler.Code {
    return #code fields {
        count : int,
    }
}

typed :: fn() -> compiler.Code {
    return #code fields {
        value : T,
    }
}

shapes :: fn() -> compiler.Code {
    return #code variants {
        Empty,
    }
}

Holder :: struct[T] {
    #insert counted(),
    #insert typed(),
}

Maybe :: union[T] {
    Some(T),
    #insert shapes(),
}

inserts_fields_using_the_types_parameter #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    h :: Holder[int].{ count = 4, value = 30 }
    f :: Holder[u8].{ count = 1, value = 7 }
    testing.expect_eq(t, h.count, 4, "the int instance has the inserted count field")
    testing.expect_eq(t, h.value, 30, "the int instance's inserted value field is an int")
    testing.expect_eq(t, f.count, 1, "the u8 instance has its own inserted count field")
    testing.expect_eq(t, f.value, cast[u8](7), "the u8 instance's inserted value field is a u8")
    return .Ok
}

inserts_a_unions_variants #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    m :: Maybe[int].Some(1)
    e :: Maybe[int].Empty
    extra :: match e {
        case Some(x) => x
        case Empty => 0
    }
    some :: match m {
        case Some(x) => x
        case Empty => 50
    }
    testing.expect_eq(t, extra, 0, "the inserted Empty variant is a variant of its own, matched as Empty")
    testing.expect_eq(t, some, 1, "the variant written beside the inserted one is still Some")
    return .Ok
}

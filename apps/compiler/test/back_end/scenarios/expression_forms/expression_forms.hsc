package expression_forms

/*
 * Forms of expression (docs/operators.md, docs/functions.md): a member, an element or what's pointed to,
 * of an expression in parentheses; a generic type's variant, like Result[T, E].Error(e); a shorthand where
 * a generic function's parameter says its type; a shorthand for what an optional holds; a union's variant
 * written in full as an if's value; and functions declared inside functions, called, passed on, and two
 * with the same name. Run with hemera --test.
 */

import testing from "std"

Pair :: struct {
    a : int,
    b : int,
}

Kind :: enum {
    First,
    Second,
}

Problem :: enum {
    Bad,
    Worse,
}

made :: fn(ok: bool) -> Result[Pair, Problem] {
    if !ok {
        return Result[Pair, Problem].Error(.Bad)
    }
    return .Ok(Pair.{a = 1, b = 2})
}

// The value, for any type, and a kind and a pair whose types the parameters give
kept :: fn[T](value: T, kind: Kind, pair: Pair) -> T {
    return if kind == .Second && pair.b == 4 { value } else { value + value }
}

failed :: fn(fail: bool) -> Problem? {
    if fail {
        return .Worse
    }
    return null
}

apply :: fn(f: (fn(x: int) -> int), x: int) -> int {
    return f(x)
}

tripled :: fn(x: int) -> int {
    helper :: fn(y: int) -> int {
        return y * 3
    }
    return helper(x)
}

Outcome :: union {
    Done,
    Empty,
    Missing,
    Failed(u32),
}

picked :: fn(empty: bool) -> Outcome {
    return if empty { Outcome.Empty } else { Outcome.Failed(7) }
}

outcome_tag :: fn(outcome: Outcome) -> int {
    return match outcome {
        case Done => 0
        case Empty => 1
        case Missing => 2
        case Failed(code) => 3
    }
}

reaches_into_parenthesized_expressions #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    values := int.[5, 6, 7]
    pointer := &values[1]
    testing.expect_eq(t, (made(true) or_else Pair.{}).b, 2, "a member of a call in parentheses is the Ok pair's b")
    testing.expect_eq(t, (values)[2], 7, "an element of an array in parentheses is the array's own")
    testing.expect_eq(t, (pointer)^, 6, "what a pointer in parentheses points to is the element it was taken from")
    return .Ok
}

makes_a_generic_types_variant #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_error(t, made(false), Problem.Bad, "Result[Pair, Problem].Error(.Bad) is the error made gives")
    return .Ok
}

takes_shorthands_from_parameter_types #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, kept(10, .Second, .{a = 0, b = 4}), 10,
        "the shorthands are a Kind and a Pair from kept's parameters, so it keeps the value as it is")
    testing.expect_eq(t, failed(true) or_else .Bad, Problem.Worse, "a shorthand for what an optional holds is the optional's type")
    testing.expect_eq(t, failed(false) or_else .Bad, Problem.Bad, "an empty optional gives the shorthand or_else names")
    return .Ok
}

writes_a_unions_variant_as_an_ifs_value #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    positive := 1
    chosen :: if positive > 0 { Outcome.Missing } else { Outcome.Done }
    given : Outcome = if positive > 0 { Outcome.Empty } else { Outcome.Failed(1) }
    testing.expect_eq(t, outcome_tag(chosen), 2, "with no type to go to, the if's value is the variant written")
    testing.expect_eq(t, outcome_tag(given), 1, "with a type to go to, the if's value is the variant written")
    testing.expect_eq(t, outcome_tag(picked(false)), 3, "a variant with a value, returned from an if")
    testing.expect_eq(t, outcome_tag(picked(true)), 1, "a variant without one, returned from an if")
    return .Ok
}

calls_functions_declared_in_functions #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    helper :: fn(x: int) -> int {
        return x + 1
    }
    testing.expect_eq(t, helper(25), 26, "this function's own helper adds one")
    testing.expect_eq(t, tripled(2), 6, "tripled's helper, of the same name, triples")
    testing.expect_eq(t, apply(helper, 9), 10, "a function declared in a function can be passed on and called")
    return .Ok
}

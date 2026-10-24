package expression_forms

/*
 * Forms of expression (docs/operators.md, docs/functions.md): a member, an element or what's pointed to,
 * of an expression in parentheses; a generic type's variant, like Result[T, E].Error(e); a shorthand where
 * a generic function's parameter says its type; a shorthand for what an optional holds; a union's variant
 * written in full as an if's value; and functions
 * declared inside functions, called, passed on, and two with the same name. main returns 42 if they all
 * worked.
 */

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

main :: fn() -> int {
    values := int.[5, 6, 7]
    pointer := &values[1]
    // 2 + 7 + 6
    total := (made(true) or_else Pair.{}).b + (values)[2] + (pointer)^
    match made(false) {
        case Ok(pair) => return 1
        case Error(problem) => {
            if problem != .Bad {
                return 2
            }
        }
    }
    // 15 + 10
    total += kept(10, .Second, .{a = 0, b = 4})
    if (failed(true) or_else .Bad) != .Worse || (failed(false) or_else .Bad) != .Bad {
        return 3
    }
    // A union's variants written in full as an if's value, with or without a type to go to
    chosen :: if total > 0 { Outcome.Missing } else { Outcome.Done }
    given : Outcome = if total > 0 { Outcome.Empty } else { Outcome.Failed(1) }
    if outcome_tag(chosen) != 2 || outcome_tag(given) != 1 || outcome_tag(picked(false)) != 3 || outcome_tag(picked(true)) != 1 {
        return 4
    }
    helper :: fn(x: int) -> int {
        return x + 1
    }
    // 25 + 1, then + 6 by tripled's own helper, + 10 through apply
    total = helper(total)
    total += tripled(2)
    total += apply(helper, 9)
    return total
}

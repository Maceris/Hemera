/*
 * Optional function types written in place (docs/functions.md, First Class Functions): in parentheses, the
 * ? is the function's, (fn(n: int) -> int)?, and without them the result's, fn(n: int) -> int?. main
 * returns 42 if they worked. Results too: functions returned in parentheses, optional or not, alone, listed or named.
 */
package optional_functions_test

double :: fn(n: int) -> int {
    return n * 2
}

Handler :: struct {
    // An optional function with a result, written in place
    on_value : (fn(n: int) -> int)?,
    // The result is optional here
    maybe : fn(n: int) -> int?,
}

call_or :: fn(handler: (fn(n: int) -> int)?, n: int) -> int {
    match handler {
        case Some(function) => return function(n)
        case None => return n
    }
}

halve :: fn(n: int) -> int? {
    return n / 2
}

seven :: fn() -> int { return 7 }
nothing :: fn() {}
pair :: fn() -> (int, int) { return 3, 4 }
maybe_five :: fn() -> int? { return 5 }

returning_pure_fn       :: fn() -> (fn()) { return nothing }
returning_a_fn          :: fn() -> (fn() -> int) { return seven }
ret_a_fn_with_2_returns :: fn() -> (fn() -> (int, int)) { return pair }
returning_int_and_fn    :: fn() -> (int, (fn() -> int)) { return 1, seven }
returning_fn_and_int    :: fn() -> ((fn() -> int), int) { return seven, 2 }
returning_optional_fn   :: fn() -> (fn() -> int)? { return seven }
returning_no_fn         :: fn() -> (fn() -> int)? { return null }
returning_fn_of_opt     :: fn() -> (fn() -> int?) { return maybe_five }
returning_opt_fn_of_opt :: fn() -> (fn() -> int?)? { return maybe_five }
int_and_optional_fn     :: fn() -> (int, (fn() -> int)?) { return 1, seven }
optional_pure_fn        :: fn() -> (fn())? { return nothing }
named_fn                :: fn() -> (f: (fn() -> int)) { return seven }
named_optional_fn       :: fn() -> (f: (fn() -> int)?) { return seven }
named_no_fn             :: fn() -> (f: (fn() -> int)?) { return null }
named_int_and_fn        :: fn() -> (n: int, f: (fn() -> (int, int))) { return 1, pair }
grouped_fns             :: fn() -> (f, g: (fn() -> int)) { return seven, seven }
named_fn_mixed          :: fn() -> (a, b: int, f: (fn() -> int)?) { return 1, 2, seven }

unwrap :: fn(value: int?) -> int {
    match value {
        case Some(n) => return n
        case None => return 0
    }
}

call_or_zero :: fn(handler: (fn() -> int)?) -> int {
    match handler {
        case Some(function) => return function()
        case None => return 0
    }
}

// 56 if every kind of function result worked
returned_functions :: fn() -> int {
    total := 0
    returning_pure_fn()()
    total += returning_a_fn()()                     // 7
    a, b := ret_a_fn_with_2_returns()()
    total += a + b                                  // 14
    n, f := returning_int_and_fn()
    total += n + f()                                // 22
    g, m := returning_fn_and_int()
    total += g() + m                                // 31
    total += call_or_zero(returning_optional_fn())  // 38
    total += call_or_zero(returning_no_fn())        // 38
    total += unwrap(returning_fn_of_opt()())        // 43
    match returning_opt_fn_of_opt() {
        case Some(h) => total += unwrap(h())        // 48
        case None => {}
    }
    k, o := int_and_optional_fn()
    total += k + call_or_zero(o)                    // 56
    match optional_pure_fn() {
        case Some(p) => p()
        case None => total = 0
    }
    return total
}

// 46 if every kind of named function result worked
named_functions :: fn() -> int {
    total := named_fn()()                           // 7
    total += call_or_zero(named_optional_fn())      // 14
    total += call_or_zero(named_no_fn())            // 14
    m, p := named_int_and_fn()
    x, y := p()
    total += m + x + y                              // 22
    g, h := grouped_fns()
    total += g() + h()                              // 36
    a, b, o := named_fn_mixed()
    total += a + b + call_or_zero(o)                // 46
    return total
}

main :: fn() -> int {
    if returned_functions() != 56 || named_functions() != 46 {
        return 1
    }
    handler := Handler.{on_value = double, maybe = halve}
    none : (fn(n: int) -> int)? = null
    return call_or(handler.on_value, 20) + call_or(none, 2)
}

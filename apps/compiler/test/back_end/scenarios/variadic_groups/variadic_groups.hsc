/*
 * Variadic parameters with others after them (docs/functions.md, Variable Arguments): a variadic one takes the values
 * that fit it, and the first that doesn't goes to the next parameter, which a call can always tell since neither type
 * can be taken for the other.
 */
package variadic_groups

import testing from "std"

// A bool after ints: true or false says where the ints end
counted :: fn(fiz: bool, numbers: int..., fuzz: bool) -> int {
    total := 0
    for number in numbers {
        total += number
    }
    return if fuzz { total * 100 + cast[int](numbers.count) } else { -1 }
}

// Several variadic ones, each of a type the others can't be taken for, so any of them can be given nothing
Point :: struct {
    x : int,
    y : int,
}

groups :: fn(names: string..., numbers: int..., flags: bool...) -> int {
    return cast[int](names.count) * 100 + cast[int](numbers.count) * 10 + cast[int](flags.count)
}

// One value between two variadic ones
around :: fn(names: string..., middle: int, points: Point...) -> int {
    total := middle * 1000 + cast[int](names.count) * 100
    for point in points {
        total += point.x + point.y
    }
    return total
}

// The view of a caller's values passed on whole, with the next parameter after it
passed_on :: fn(numbers: int...) -> int {
    return counted(true, numbers, true)
}

ends_a_variadic_at_the_first_value_that_doesnt_fit #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, counted(false, 1, 2, 3, true), 603, "the ints go to numbers, and the bool after them to fuzz")
    testing.expect_eq(t, counted(false, true), 0, "a bool straight after fiz leaves numbers empty")
    testing.expect_eq(t, counted(true, 7, false), -1, "the last bool is fuzz, whatever fiz was")
    testing.expect_eq(t, passed_on(4, 5), 902, "a caller's variadic view passes on whole, with the next parameter after it")
    return .Ok
}

fills_several_variadics #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, groups("a", "b", 1, 2, 3, true), 231, "each type goes to its own variadic, in order")
    testing.expect_eq(t, groups(true, false), 2, "the first two can be given nothing")
    testing.expect_eq(t, groups("a", true), 101, "the middle one can be given nothing")
    testing.expect_eq(t, groups(), 0, "all of them can be given nothing")
    testing.expect_eq(t, groups(1), 10, "an int alone goes to numbers")
    testing.expect_eq(t, groups("a", "b", "c"), 300, "strings alone go to names")
    // A struct literal without its type is the variadic's
    testing.expect_eq(t, around("a", 5, .{x = 1, y = 2}, Point.{x = 3, y = 4}), 5110,
        "the one int is middle, and the points after it, one a literal without its type, are points")
    testing.expect_eq(t, around(7), 7000, "with the variadics on either side empty, the int is middle")
    return .Ok
}

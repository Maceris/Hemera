/*
 * Variadic parameters with others after them (docs/functions.md, Variable Arguments): a variadic one takes the values
 * that fit it, and the first that doesn't goes to the next parameter, which a call can always tell since neither type
 * can be taken for the other. main returns 42 if they all held, or the number of the first that didn't.
 */
package variadic_groups

check :: fn(ok: bool, code: int) -> int {
    if ok {
        return 0
    }
    return code
}

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

main :: fn() -> int {
    errors := 0
    errors += check(counted(false, 1, 2, 3, true) == 603 && counted(false, true) == 0 && counted(true, 7, false) == -1, 1)
    errors += check(groups("a", "b", 1, 2, 3, true) == 231 && groups(true, false) == 2 && groups("a", true) == 101, 2)
    errors += check(groups() == 0 && groups(1) == 10 && groups("a", "b", "c") == 300, 3)
    // A struct literal without its type is the variadic's
    errors += check(around("a", 5, .{x = 1, y = 2}, Point.{x = 3, y = 4}) == 5110 && around(7) == 7000, 4)
    errors += check(passed_on(4, 5) == 902, 5)
    if errors == 0 {
        return 42
    }
    return errors
}

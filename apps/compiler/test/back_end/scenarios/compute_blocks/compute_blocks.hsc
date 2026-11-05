package compute_blocks

import testing from "std"

/*
 * Compute blocks (docs/control_flow.md, Compute Blocks): compute[T] { ... } runs its statements and gives a value of T
 * with give, which leaves it from inside loops and other blocks; break and continue pass through it to their loop;
 * what's deferred in it runs as give leaves; and or_else takes one that leaves the function.
 */

sum_to :: fn(limit: int) -> int {
    return compute[int] {
        total := 0
        for i in 0..<limit {
            total += i
        }
        give total
    }
}

// The first value past a threshold, given from inside the loop
first_over :: fn(values: int[], threshold: int) -> int {
    return compute[int] {
        for value in values {
            if value > threshold {
                give value
            }
        }
        give -1
    }
}

// A compute block inside another, each give leaving only its own
nested :: fn() -> int {
    outer :: compute[int] {
        inner :: compute[int] {
            give 5
        }
        give inner * 2
    }
    return outer
}

// break and continue in a compute block reach the loop around it
counted :: fn() -> int {
    count := 0
    for i in 0..<10 {
        step :: compute[int] {
            if i == 3 {
                continue
            }
            if i == 7 {
                break
            }
            give 1
        }
        count += step
    }
    // 0, 1, 2, 4, 5 and 6
    return count
}

Recorder :: struct {
    deferred : int,
}

// What's deferred in it runs when give leaves
deferring :: fn(recorder: ptr[mut Recorder]) -> int {
    return compute[int] {
        defer recorder.deferred += 1
        give 3
    }
}

maybe :: fn(present: bool) -> int? {
    if present {
        return 9
    }
    return null
}

// or_else with a compute block that leaves the function
or_leave :: fn(present: bool) -> int {
    value :: maybe(present) or_else compute[int] {
        return -1
    }
    return value
}

Shape :: union {
    Circle(int),
    Square(int),
}

// One as a match arm's value
area :: fn(shape: Shape) -> int {
    return match shape {
        case Circle(radius) => compute[int] {
            square :: radius * radius
            give square * 3
        }
        case Square(side) => side * side
    }
}

gives_a_value #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, sum_to(5), 10, "give gives the total the block's loop made: 0 + 1 + 2 + 3 + 4")
    return .Ok
}

gives_from_inside_a_loop #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, first_over(int.[1, 4, 9, 16], 5), 9, "give leaves the loop at the first value past 5")
    testing.expect_eq(t, first_over(int.[1, 2], 5), -1, "with none past it, the loop ends and the give after it gives")
    return .Ok
}

gives_only_from_its_own_block #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, nested(), 10, "the inner give leaves only the inner block, which the outer doubles")
    return .Ok
}

passes_break_and_continue_to_the_loop #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, counted(), 6, "continue skips 3 and break stops at 7, leaving 0 to 6 but 3")
    return .Ok
}

runs_whats_deferred_as_give_leaves #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    recorder := Recorder.{}
    testing.expect_eq(t, deferring(&recorder), 3, "the deferred statement doesn't change what's given")
    testing.expect_eq(t, recorder.deferred, 1, "the deferred statement ran once, as give left")
    return .Ok
}

leaves_the_function_from_or_else #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, or_leave(true), 9, "with a value, or_else's block doesn't run")
    testing.expect_eq(t, or_leave(false), -1, "without one, the block's return leaves the function")
    return .Ok
}

gives_a_match_arms_value #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, area(Shape.Circle(2)), 12, "the arm's block gives 3 times the radius squared")
    testing.expect_eq(t, area(Shape.Square(3)), 9, "the other arm is a plain expression")
    return .Ok
}

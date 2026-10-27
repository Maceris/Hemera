package compute_blocks

/*
 * Compute blocks (docs/control_flow.md, Compute Blocks): compute[T] { ... } runs its statements and gives a value of T
 * with give, which leaves it from inside loops and other blocks; break and continue pass through it to their loop;
 * what's deferred in it runs as give leaves; and or_else takes one that leaves the function. main returns 42 if
 * everything worked.
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

main :: fn() -> int {
    if sum_to(5) != 10 {
        return 1
    }
    if first_over(int.[1, 4, 9, 16], 5) != 9 || first_over(int.[1, 2], 5) != -1 {
        return 2
    }
    if nested() != 10 {
        return 3
    }
    if counted() != 6 {
        return 4
    }
    recorder := Recorder.{}
    if deferring(&recorder) != 3 || recorder.deferred != 1 {
        return 5
    }
    if or_leave(true) != 9 || or_leave(false) != -1 {
        return 6
    }
    if area(Shape.Circle(2)) != 12 || area(Shape.Square(3)) != 9 {
        return 7
    }
    return 42
}

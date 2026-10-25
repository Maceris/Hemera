/*
 * switch with #fall_through (docs/control_flow.md, Switch): a case that falls through runs the next
 * case's statements too, whatever that case's values are, and chains of them; a case that leaves with
 * break doesn't fall through; one that doesn't match falls into nothing; and inside a loop, each
 * switch starts over; and an owner the case after a #fall_through releases is released on every path. main returns 42 if they all went that way, or the number of the first that didn't.
 */
package fall_through

import compiler from "base"

check :: fn(ok: bool, code: int) -> int {
    if ok {
        return 0
    }
    return code
}

// Digits for each case that ran, in order
run :: fn(value: int, stop: bool) -> int {
    ran := 0
    switch value {
        case 1:
            ran = ran * 10 + 1
        #fall_through
        case 2, 3:
            ran = ran * 10 + 2
            if stop {
                break
            }
        #fall_through
        case 4:
            ran = ran * 10 + 3
        case 5:
            ran = ran * 10 + 4
        case _:
            ran = ran * 10 + 5
    }
    return ran
}

Mode :: enum { Off, Low, High }

level :: fn(mode: Mode) -> int {
    result := 0
    switch mode {
        case .High: result += 10
        #fall_through
        case .Low: result += 1
        case .Off: {}
    }
    return result
}

Handle :: struct #owned(close) {
    number : int,
}

close :: fn(handle: Handle) {
    compiler.forget(handle)
}

// The case that falls through leaves handle to the case after it, which closes it: closed on every path
closes_once :: fn(value: int) -> int {
    handle :: Handle.{value}
    result := 0
    switch value {
        case 1:
            result = 1
        #fall_through
        case _:
            result += handle.number
            close(handle)
    }
    return result
}

main :: fn() -> int {
    errors := 0
    errors += check(run(1, false) == 123, 1)    // 1 falls into 2, which falls into 4
    errors += check(run(2, false) == 23, 2)
    errors += check(run(3, true) == 2, 3)       // break leaves before falling through
    errors += check(run(1, true) == 12, 4)
    errors += check(run(4, false) == 3, 5)      // 4 doesn't fall through, so 5 doesn't run
    errors += check(run(5, false) == 4, 6)
    errors += check(run(9, false) == 5, 7)
    errors += check(level(.High) == 11 && level(.Low) == 1 && level(.Off) == 0, 8)

    // Falling through in one time around doesn't carry over to the next
    total := 0
    for i in 0..<4 {
        switch i {
            case 0: total += 100
            #fall_through
            case 1: total += 10
            case _: total += 1
        }
    }
    errors += check(total == 122, 9)
    errors += check(closes_once(1) == 2 && closes_once(5) == 5, 10)
    if errors == 0 {
        return 42
    }
    return errors
}

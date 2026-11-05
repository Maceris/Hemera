/*
 * switch with #fall_through (docs/control_flow.md, Switch): a case that falls through runs the next
 * case's statements too, whatever that case's values are, and chains of them; a case that leaves with
 * break doesn't fall through; one that doesn't match falls into nothing; and inside a loop, each
 * switch starts over; and an owner the case after a #fall_through releases is released on every path.
 * Run with hemera --test.
 */
package fall_through

import compiler from "base"
import testing from "std"

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

runs_the_cases_it_falls_into #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, run(1, false), 123, "1 falls into 2, which falls into 4, whatever their values")
    testing.expect_eq(t, run(2, false), 23, "a case in the middle of the chain falls into the rest of it")
    testing.expect_eq(t, run(4, false), 3, "4 doesn't fall through, so 5's case doesn't run")
    testing.expect_eq(t, run(5, false), 4, "a case without #fall_through runs alone")
    testing.expect_eq(t, run(9, false), 5, "a value no case names goes to case _ and falls into nothing")
    return .Ok
}

stops_falling_through_at_break #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, run(3, true), 2, "break leaves before falling through")
    testing.expect_eq(t, run(1, true), 12, "a case fallen into can still break before falling further")
    return .Ok
}

falls_through_enum_cases #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, level(.High), 11, "High falls into Low")
    testing.expect_eq(t, level(.Low), 1, "Low runs alone")
    testing.expect_eq(t, level(.Off), 0, "Off runs nothing")
    return .Ok
}

starts_each_switch_in_a_loop_over #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    total := 0
    for i in 0..<4 {
        switch i {
            case 0: total += 100
            #fall_through
            case 1: total += 10
            case _: total += 1
        }
    }
    testing.expect_eq(t, total, 122, "falling through in one time around doesn't carry over to the next: 110, 10, 1, 1")
    return .Ok
}

releases_an_owner_on_every_path #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, closes_once(1), 2, "the case that falls through leaves the handle to the one after, which reads it")
    testing.expect_eq(t, closes_once(5), 5, "the case after the #fall_through, reached directly, has the handle too")
    return .Ok
}

/*
 * #insert and macro calls in a generic function's body (docs/compilation.md, Code Values): each instance has a tree of
 * its own, so what's inserted is worked out with its own types and values. Run with hemera --test.
 */
package generic_insertions

import compiler from "base"
import testing from "std"

add #macro :: fn(target: compiler.Code, amount: int) -> compiler.Code {
    return #code {
        #insert target += #insert amount
    }
}

// Code that depends on the type it's given: a float's half, or an integer shifted
halved :: fn(T: type, value: compiler.Code) -> compiler.Code {
    if type_info_of(T).variant == .FLOAT {
        return #code(#insert value / 2)
    }
    return #code(#insert value >> 1)
}

// The same code inserted into each instance, using the instance's T and capacity
filled :: fn[T, capacity: usize](value: T) -> T[capacity] {
    #insert #code {
        result : T[capacity]
        for i in 0..<capacity {
            result[i] = value
        }
    }
    return result
}

// A macro call in a generic body, and code worked out from the instance's T
grown :: fn[T](start: T) -> T {
    total := start
    add!(total, 3)
    return #insert halved(T, #code(total))
}

// A constrained one, checked at its instances rather than once before them, since its body inserts code
bumped :: fn[T](value: T) -> T where compiler.Numeric(T) {
    result := value
    add!(result, 1)
    return result
}

inserts_with_each_instances_types_and_values #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    numbers :: filled[int, 3](7)
    testing.expect_eq(t, numbers.count, 3, "the int instance's array has its capacity, 3")
    testing.expect_eq(t, numbers[0], 7, "the inserted loop filled the int instance's first element")
    testing.expect_eq(t, numbers[2], 7, "the inserted loop filled the int instance's last element")
    words :: filled[string, 2]("hi")
    testing.expect_eq(t, words.count, 2, "the string instance's array has its own capacity, 2")
    testing.expect_eq(t, words[1], "hi", "the inserted loop filled the string instance's elements with strings")
    return .Ok
}

works_out_code_from_the_instances_type #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, grown(5), 4, "for an int, add! makes 8 and halved shifts it: 4")
    testing.expect_eq(t, grown(5.0), 4.0, "for a float, add! makes 8.0 and halved divides it: 4.0")
    testing.expect_eq(t, grown(cast[u8](9)), 6, "for a u8, its own instance: 12 shifted is 6")
    return .Ok
}

checks_a_constrained_function_at_its_instances #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, bumped(41), 42, "the int instance's add! adds 1")
    testing.expect_eq(t, bumped(0.5), 1.5, "the float instance's add! adds 1 to a float")
    return .Ok
}

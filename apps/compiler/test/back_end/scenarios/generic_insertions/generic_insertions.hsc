/*
 * #insert and macro calls in a generic function's body (docs/compilation.md, Code Values): each instance has a tree of
 * its own, so what's inserted is worked out with its own types and values. main returns 42 if they all held, or the
 * number of the first that didn't.
 */
package generic_insertions

import compiler from "base"

check :: fn(ok: bool, code: int) -> int {
    if ok {
        return 0
    }
    return code
}

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

main :: fn() -> int {
    errors := 0
    numbers :: filled[int, 3](7)
    errors += check(numbers.count == 3 && numbers[0] == 7 && numbers[2] == 7, 1)
    words :: filled[string, 2]("hi")
    errors += check(words.count == 2 && words[1] == "hi", 2)
    errors += check(grown(5) == 4 && grown(5.0) == 4.0, 3)
    errors += check(grown(cast[u8](9)) == 6, 4)
    errors += check(bumped(41) == 42 && bumped(0.5) == 1.5, 5)
    if errors == 0 {
        return 42
    }
    return errors
}

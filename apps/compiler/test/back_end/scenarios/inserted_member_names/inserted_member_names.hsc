package inserted_member_names

import compiler from "base"
import runtime from "base"

/*
 * Members named by #insert in a quote (docs/compilation.md, Code Values): an enum's members, with and without
 * a value, a struct's fields, and reaching them with value.#insert name and .#insert name. main returns 42 if
 * the named members work.
 */

// Two members named from text, the first with a value that's inserted too
levels :: fn(first: string, second: string, value: int) -> compiler.Code {
    a := compiler.name(first)
    b := compiler.name(second)
    return #code members {
        #insert a = #insert value,
        #insert b,
    }
}

Level :: enum {
    Low,
    #insert levels("High", "Top", 10),
}

Calls :: struct {
    add : fn(a: int, b: int) -> int,
    negate : fn(value: int) -> int,
}

// A member per call, numbered as the table orders them: a list of quotes of members
call_numbers :: fn() -> compiler.Code {
    info :: cast[ptr[compiler.TypeInfoStruct]](type_info_of(Calls))
    made : compiler.Code[..]
    for member, i in info.members {
        array_add(&made, #code members {
            #insert compiler.name("CALL_", member.name) = #insert i,
        })
    }
    return compiler.list(made)
}

Call :: enum {
    #insert call_numbers(),
}

fields :: fn(name: string) -> compiler.Code {
    field := compiler.name(name)
    return #code fields {
        #insert field : int,
    }
}

Pair :: struct {
    first : int,
    #insert fields("second"),
}

points :: fn(level: Level) -> int {
    return cast[int](level)
}

// A function reaching a field and a member by names given as text
reader :: fn(field_name: string, member_name: string) -> compiler.Code {
    field := compiler.name(field_name)
    member := compiler.name(member_name)
    return #code {
        read :: fn(pair: Pair) -> int {
            return pair.#insert field + points(.#insert member)
        }
    }
}

#insert reader("second", "Top")

expect :: fn(code: compiler.Code, text: string) {
    made :: compiler.code_text(code)
    if made != text {
        runtime.log_error("code came out as [%], not [%]", made, text)
    }
}

printing_works :: fn() -> bool {
    expect(levels("A", "B", 3), "members {\n    A = 3,\n    B,\n}")
    name := compiler.name("x")
    expect(#code(point.#insert name), "point.x")
    expect(#code(.#insert name), ".x")
    // A quote within one prints its own
    expect(#code {
        made :: #code members {
            #insert name = 1,
        }
        reached :: #code(value.#insert name + pick(.#insert name))
    }, "made :: #code members {\n    #insert name = 1,\n}\nreached :: #code(value.#insert name + pick(.#insert name))\n")
    return true
}

PRINTING_WORKS :: printing_works()

main :: fn() -> int {
    pair := Pair.{first = 1, second = 20}
    // 20 + 11
    total := read(pair)
    if cast[int](Level.High) != 10 || Level.Low == Level.Top || cast[int](Call.CALL_negate) != 1 {
        return 1
    }
    match Level.Top {
        case .Top => total += 11
        case _ => return 2
    }
    return if PRINTING_WORKS { total } else { 3 }
}

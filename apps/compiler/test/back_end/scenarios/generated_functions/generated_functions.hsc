package generated_functions

import compiler from "base"
import runtime from "base"

/*
 * Code made from data (docs/compilation.md, Code Values): a function per member of a table of function
 * types, named with compiler.name and given the member's parameters and arguments; and the functions that
 * make and look at code, checked at compile time. main returns 42 if the generated functions work.
 */

Calls :: struct {
    add : fn(a: int, b: int) -> int,
    negate : fn(value: int) -> int,
}

dispatch :: fn(number: int, values: int...) -> int {
    total := number * 100
    for value in values {
        total += value
    }
    return total
}

// A function per call, passing its number and its arguments on to dispatch
stubs :: fn() -> compiler.Code {
    info :: cast[ptr[compiler.TypeInfoStruct]](type_info_of(Calls))
    made : compiler.Code[..]
    for member, i in info.members {
        function :: compiler.described_type(member.member_type)
        array_add(&made, #code {
            #insert compiler.name(member.name) :: fn(#insert compiler.parameters(function)) -> int {
                return dispatch(#insert i, #insert compiler.arguments(function))
            }
        })
    }
    return compiler.list(made)
}

#insert stubs()

Forward :: fn(x: int, y: u8) -> int

// At compile time, an error fails the build
expect :: fn(code: compiler.Code, text: string) {
    made :: compiler.code_text(code)
    if made != text {
        runtime.log_error("code came out as [%], not [%]", made, text)
    }
}

making_code_works :: fn() -> bool {
    count := compiler.name("count")
    expect(count, "count")
    expect(compiler.literal(7), "7")
    expect(compiler.literal("seven"), "\"seven\"")
    expect(compiler.type_code(u16), "u16")
    // A type given with mut keeps it, wherever it's spliced
    element := compiler.type_code(u32)
    expect(#code {
        pointer : ptr[mut #insert element]
    }, "pointer : ptr[mut u32]\n")
    // A function's signature, from its type
    signature := #code {
        #insert compiler.name("forward") :: fn(#insert compiler.parameters(Forward)) -> #insert compiler.type_code(int) {
            return target(#insert compiler.arguments(Forward))
        }
    }
    expect(signature, "forward :: fn(x: int, y: u8) -> int {\n    return target(x, y)\n}\n")
    // Looking at code
    if compiler.code_kind(count) != .Name || compiler.code_kind(signature) != .Statements
        || compiler.code_kind(compiler.literal(1)) != .Literal || compiler.code_kind(#code(a + b)) != .Expression {
        runtime.log_error("a code kind is wrong")
    }
    named :: compiler.identifier_of(count) or_else ""
    if named != "count" || (compiler.identifier_of(#code(a + b)) is_some) {
        runtime.log_error("identifier_of is wrong")
    }
    items := compiler.items_of(#code {
        first()
        second()
    })
    if items.count != 2 {
        runtime.log_error("items_of gave % items, not 2", items.count)
    }
    else {
        expect(items[1], "second()")
    }
    // The line count is made on
    if compiler.location_of(count).line != 53 {
        runtime.log_error("location_of gave line %, not 53", compiler.location_of(count).line)
    }
    return true
}

MAKING_CODE_WORKS :: making_code_works()

main :: fn() -> int {
    // 0 * 100 + 30 + 4, then 1 * 100 - 92
    total := add(30, 4) + negate(-92)
    return if MAKING_CODE_WORKS { total } else { 1 }
}

package generated_functions

import compiler from "base"
import runtime from "base"
import testing from "std"

/*
 * Code made from data (docs/compilation.md, Code Values): a function per member of a table of function
 * types, named with compiler.name and given the member's parameters and arguments; and the functions that
 * make and look at code, checked at compile time. Run with hemera --test.
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
    // A name from parts, joined
    expect(compiler.name("load_", "u64", "_acquire"), "load_u64_acquire")
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
    if compiler.location_of(count).line != 54 {
        runtime.log_error("location_of gave line %, not 54", compiler.location_of(count).line)
    }
    return true
}

MAKING_CODE_WORKS :: making_code_works()

calls_functions_made_from_a_table #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, add(30, 4), 34, "add, Calls' first member, passes 0 and its arguments on: 0 * 100 + 30 + 4")
    testing.expect_eq(t, negate(-92), 8, "negate, Calls' second member, passes 1 and its argument on: 1 * 100 - 92")
    return .Ok
}

makes_and_looks_at_code_at_compile_time #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect(t, MAKING_CODE_WORKS, "making_code_works ran at compile time, where anything wrong fails the build")
    return .Ok
}

package described_when_laid_out

import compiler from "base"

// Compile-time code describing a type waits for what the description holds by value: here Table's call's
// Result, whose Ok holds Pair, which a slow #insert is still making
fields :: fn() -> compiler.Code {
    spin := 0
    for i in 0..<200000 {
        spin = (spin + i) % 7
    }
    return if spin >= 0 { #code fields { first : int, second : int, } } else { #code fields {} }
}

Pair :: struct {
    #insert fields(),
}

Failure :: enum { BROKEN }

Table :: struct {
    make : fn() -> Result[Pair, Failure],
}

// Ten for each of the call's result's variants, and one for each field of what its Ok holds
described :: fn() -> int {
    table :: cast[ptr[compiler.TypeInfoStruct]](type_info_of(Table))
    total := 0
    for member in table.members {
        function :: cast[ptr[compiler.TypeInfoFunction]](member.member_type)
        for output in function.output {
            result :: cast[ptr[compiler.TypeInfoUnion]](output.type)
            total += 10 * cast[int](result.variants.count)
            for variant in result.variants {
                for held in variant.types {
                    if variant.name == "Ok" {
                        total += cast[int](cast[ptr[compiler.TypeInfoStruct]](held).members.count)
                    }
                }
            }
        }
    }
    return total
}

DESCRIBED :: #run described()

main :: fn() -> int {
    // 22: two variants, and Pair's two fields
    return DESCRIBED
}

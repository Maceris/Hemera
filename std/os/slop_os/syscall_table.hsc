package slop_os

import compiler from "base"
import runtime from "base"

#if TARGET_ARCH == .x86_64 {
    import x86_64 from "base/intrinsics"
}

/*
 * What the syscall table (Syscalls, syscalls.hsc) generates, at compile time (the SlopOS repository's
 * knowledge/design/system-abi.md §4, decisions 0057):
 * - SYSCALL_<NAME>, each call's number;
 * - a stub per call, like port_wait(port, packets, deadline) -> Result[u32, PortError], which puts its
 *   arguments in registers, makes the call and turns what comes back into its result. Stubs are
 *   #no_context, so they work before a program has set up its context;
 * - the kernel's dispatch (syscall_dispatch), statements it inserts where a call arrives.
 *
 * A handle, an integer, an enum, a bool or a pointer takes a register; a slice two, its data then its
 * count. A result is 0 or the error's tag in the first register, then T in the next two: a value, or a
 * struct's first two members.
 */

// What a call gives back, in the system ABI's three result registers.
SyscallAnswer :: struct {
    tag : u64,
    first : u64,
    second : u64,
}

// A call by number, with up to six words.
system_call :: fn(number: u64, a: u64 = 0, b: u64 = 0, c: u64 = 0, d: u64 = 0, e: u64 = 0, f: u64 = 0) -> SyscallAnswer #no_context {
    #if TARGET_ARCH == .x86_64 {
        made :: x86_64.system_call(number, a, b, c, d, e, f)
        return SyscallAnswer.{tag = made.rax, first = made.rdx, second = made.r8}
    }
}

// A slice's first element's address, and how many it has, for a stub's registers.
slice_address :: fn[T](items: T[]) -> u64 #no_context {
    return cast[u64](cast[rawptr](items.data))
}

slice_count :: fn[T](items: T[]) -> usize #no_context {
    return items.count
}

// A slice as the kernel gets it: where it is in the caller's memory, and how many elements.
UserBuffer :: struct {
    address : u64,
    count : u64,
}

// The registers a call has for arguments.
SYSCALL_ARGUMENT_WORDS :: 6

// SYSCALL_<NAME> :: number, for each call.
syscall_numbers :: fn() -> compiler.Code {
    made : compiler.Code[..]
    for member, i in table().members {
        upper : u8[64]
        name :: upper_name(member.name, &upper)
        array_add(&made, #code {
            #insert compiler.name("SYSCALL_", name) : u32 : #insert cast[u32](i)
        })
    }
    return compiler.list(made)
}

// A stub for each call.
syscall_stubs :: fn() -> compiler.Code {
    made : compiler.Code[..]
    for member, i in table().members {
        array_add(&made, stub(member, cast[u64](i)))
    }
    return compiler.list(made)
}

/*
 * The kernel's dispatch: for the call whose number is number, its handler sys_<name> called with the
 * caller (thread) and the arguments decoded from registers, and its answer returned. Where it's
 * inserted provides registers, thread and number, and these:
 * - word(registers, index) -> u64, an argument register;
 * - buffer(registers, index) -> slop_os.UserBuffer, a slice from two;
 * - answered(tag, first, second): what the dispatch returns.
 * A handler takes a UserBuffer for a slice and a u64 for a pointer, and gives back Result[T, E]; one that
 * blocks the thread gives back anything, and the kernel writes its result when the wait is over. A call
 * that doesn't return gives back nothing.
 */
syscall_dispatch :: fn() -> compiler.Code {
    made : compiler.Code[..]
    for member, i in table().members {
        array_add(&made, dispatch(member, cast[u64](i)))
    }
    return compiler.list(made)
}

table :: fn() -> ptr[compiler.TypeInfoStruct] {
    return cast[ptr[compiler.TypeInfoStruct]](type_info_of(Syscalls))
}

stub :: fn(member: compiler.StructMember, number: u64) -> compiler.Code {
    function :: cast[ptr[compiler.TypeInfoFunction]](member.member_type)
    signature :: compiler.described_type(member.member_type)
    words :: argument_words(function, member.name)
    if function.never_returns {
        return #code {
            #insert compiler.name(member.name) :: fn() #never_returns #no_context {
                _ = system_call(#insert number, #insert words)
                loop {
                }
            }
        }
    }
    result :: result_of(function)
    ok, error :: result_types(result, member.name)
    return #code {
        #insert compiler.name(member.name) :: fn(#insert compiler.parameters(signature)) -> #insert compiler.type_code(compiler.described_type(result)) #no_context {
            answer :: system_call(#insert number, #insert words)
            if answer.tag != 0 {
                return .Error(#insert value_of(error, #code(answer.tag)))
            }
            #insert ok_result(ok)
        }
    }
}

// The words a call's arguments take, from its parameters' names.
argument_words :: fn(function: ptr[compiler.TypeInfoFunction], call: string) -> compiler.Code {
    made : compiler.Code[..]
    for input in function.input {
        argument :: compiler.name(input.name)
        if is_slice(input.type) {
            array_add(&made, #code(slice_address(#insert argument)))
            array_add(&made, #code(cast[u64](slice_count(#insert argument))))
        }
        else {
            array_add(&made, word_of(input.type, argument))
        }
    }
    if made.count > SYSCALL_ARGUMENT_WORDS {
        compiler.report_error(#caller_location, "% takes more than % registers of arguments", call, SYSCALL_ARGUMENT_WORDS)
    }
    return compiler.list(made)
}

// Return .Ok with the value in answer's first and second registers.
ok_result :: fn(ok: ptr[compiler.TypeInfo]?) -> compiler.Code {
    type :: ok or_return #code {
        return .Ok
    }
    base :: underlying(type)
    if base.variant != .STRUCT {
        return #code {
            return .Ok(#insert value_of(type, #code(answer.first)))
        }
    }
    // A struct's first two members, written where they are in it
    members :: cast[ptr[compiler.TypeInfoStruct]](base).members
    stores : compiler.Code[..]
    for field, i in members {
        if i < 2 {
            field_type :: compiler.type_code(compiler.described_type(field.member_type))
            register := #code(answer.second)
            if i == 0 {
                register = #code(answer.first)
            }
            array_add(&stores, #code {
                cast[ptr[mut #insert field_type]](cast[u64](&value) + #insert cast[u64](field.offset))^ = #insert value_of(field.member_type, register)
            })
        }
    }
    return #code {
        value : #insert compiler.type_code(compiler.described_type(type))
        #insert compiler.list(stores)
        return .Ok(value)
    }
}

dispatch :: fn(member: compiler.StructMember, number: u64) -> compiler.Code {
    function :: cast[ptr[compiler.TypeInfoFunction]](member.member_type)
    arguments : compiler.Code[..]
    index := cast[u64](0)
    for input in function.input {
        if is_slice(input.type) {
            array_add(&arguments, #code(buffer(registers, #insert index)))
            index += 2
        }
        else if underlying(input.type).variant == .POINTER {
            array_add(&arguments, #code(word(registers, #insert index)))
            index += 1
        }
        else {
            array_add(&arguments, value_of(input.type, #code(word(registers, #insert index))))
            index += 1
        }
    }
    handler :: compiler.name("sys_", member.name)
    if function.never_returns {
        return #code {
            if number == #insert number {
                run :: #insert handler
                run(thread, #insert compiler.list(arguments))
                return answered(0, 0, 0)
            }
        }
    }
    ok, error :: result_types(result_of(function), member.name)
    return #code {
        if number == #insert number {
            run :: #insert handler
            match run(thread, #insert compiler.list(arguments)) {
                #insert ok_answer(ok)
                case Error(error) => return answered(#insert word_of(error, #code(error)), 0, 0)
            }
        }
    }
}

// The Ok case of a handler's result, as the answer's registers.
ok_answer :: fn(ok: ptr[compiler.TypeInfo]?) -> compiler.Code {
    type :: ok or_return #code patterns {
        case Ok => return answered(0, 0, 0)
    }
    base :: underlying(type)
    if base.variant != .STRUCT {
        return #code patterns {
            case Ok(value) => return answered(0, #insert word_of(type, #code(value)), 0)
        }
    }
    members :: cast[ptr[compiler.TypeInfoStruct]](base).members
    words : compiler.Code[..]
    for field, i in members {
        if i < 2 {
            field_type :: compiler.type_code(compiler.described_type(field.member_type))
            array_add(&words, word_of(field.member_type, #code(cast[ptr[#insert field_type]](cast[u64](&kept) + #insert cast[u64](field.offset))^)))
        }
    }
    if words.count < 2 {
        array_add(&words, #code(cast[u64](0)))
    }
    return #code patterns {
        case Ok(value) => {
            kept :: value
            return answered(0, #insert compiler.list(words))
        }
    }
}

// A call's result type: its function's last output, which is its only one.
result_of :: fn(function: ptr[compiler.TypeInfoFunction]) -> ptr[compiler.TypeInfo] {
    result := cast[ptr[compiler.TypeInfo]](0)
    for output in function.output {
        result = output.type
    }
    return result
}

// A Result's Ok type, none for void, and its error type, which must be an enum.
result_types :: fn(result: ptr[compiler.TypeInfo], call: string) -> (ok: ptr[compiler.TypeInfo]?, error: ptr[compiler.TypeInfo]) {
    union_info :: cast[ptr[compiler.TypeInfoUnion]](underlying(result))
    ok : ptr[compiler.TypeInfo]? = null
    error := result
    for variant in union_info.variants {
        for type in variant.types {
            if variant.name == "Ok" {
                ok = type
            }
            if variant.name == "Error" {
                error = type
            }
        }
    }
    if underlying(error).variant != .ENUM {
        compiler.report_error(#caller_location, "%'s error isn't an enum", call)
    }
    return ok, error
}

// value, of a register-sized type, as a word.
word_of :: fn(type: ptr[compiler.TypeInfo], value: compiler.Code) -> compiler.Code {
    if type.variant == .ALIAS {
        base :: cast[ptr[compiler.TypeInfoAlias]](type).base_type
        return word_of(base, #code(cast[#insert compiler.type_code(compiler.described_type(base))](#insert value)))
    }
    if type.variant == .ENUM {
        backing :: compiler.type_code(compiler.described_type(cast[ptr[compiler.TypeInfoEnum]](type).backing_type))
        return #code(cast[u64](cast[#insert backing](#insert value)))
    }
    if type.variant == .BOOLEAN {
        return #code(if #insert value { cast[u64](1) } else { cast[u64](0) })
    }
    if type.variant == .POINTER {
        return #code(cast[u64](cast[rawptr](#insert value)))
    }
    if type.variant != .INTEGER || type.size > 8 {
        compiler.report_error(#caller_location, "a call's argument or result doesn't fit a register")
    }
    return #code(cast[u64](#insert value))
}

// A word, as a value of a register-sized type.
value_of :: fn(type: ptr[compiler.TypeInfo], word: compiler.Code) -> compiler.Code {
    made :: compiler.type_code(compiler.described_type(type))
    if type.variant == .ALIAS {
        return #code(cast[#insert made](#insert value_of(cast[ptr[compiler.TypeInfoAlias]](type).base_type, word)))
    }
    if type.variant == .ENUM {
        backing :: compiler.type_code(compiler.described_type(cast[ptr[compiler.TypeInfoEnum]](type).backing_type))
        return #code(cast[#insert made](cast[#insert backing](#insert word)))
    }
    if type.variant == .BOOLEAN {
        return #code(#insert word != 0)
    }
    return #code(cast[#insert made](#insert word))
}

// The type an alias stands for, through every alias.
underlying :: fn(type: ptr[compiler.TypeInfo]) -> ptr[compiler.TypeInfo] {
    current := type
    for depth in 0..<16 {
        if current.variant != .ALIAS {
            break
        }
        current = cast[ptr[compiler.TypeInfoAlias]](current).base_type
    }
    return current
}

is_slice :: fn(type: ptr[compiler.TypeInfo]) -> bool {
    base :: underlying(type)
    if base.variant != .ARRAY {
        return false
    }
    dimensions :: cast[ptr[compiler.TypeInfoArray]](base).dimensions
    return dimensions.count == 1 && dimensions[0].type == .VIEW
}

// name, upper case, in upper's bytes: port_wait becomes PORT_WAIT.
upper_name :: fn(name: string, upper: ptr[mut u8[64]]) -> string {
    count := cast[usize](0)
    for character in name {
        if count < 64 {
            byte :: cast[u8](character)
            // a to z
            upper^[count] = if byte >= 97 && byte <= 122 { byte - 32 } else { byte }
            count += 1
        }
    }
    return string_of(&upper^[0], count)
}

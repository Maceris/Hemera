package slop_os

import compiler from "base"
import intrinsics from "base"
import runtime from "base"

#if TARGET_ARCH == .x86_64 {
    import x86_64 from "base/intrinsics"
}
#else_if TARGET_ARCH == .arm64 {
    import aarch64 from "base/intrinsics"
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

/**
 * What a call gives back, in the system ABI's three result registers (rax, rdx and r8 on x86-64; x0, x1 and x2 on
 * AArch64).
 */
SyscallAnswer :: struct {
    /** 0 when the call succeeded, or else the error's tag: the value of the call's error enum. */
    tag : u64,
    /** The Ok value, or a struct's first member, as a word; meaningless when tag isn't 0 or the call gives nothing. */
    first : u64,
    /** A struct Ok value's second member, as a word; meaningless otherwise. */
    second : u64,
}

/**
 * Make a system call by number, with up to six argument words, and give back what the kernel answered.
 *
 * This is the raw call the generated stubs make; it doesn't check the number or the arguments, which the kernel does.
 * It needs no context, so it works before a program has set one up. On an architecture other than x86-64 and AArch64
 * it traps, since their system call registers come with their user mode.
 *
 * @param number The call's number, a SYSCALL_<NAME> constant; an unknown number is the kernel's to reject.
 * @param a The first argument word, 0 when the call takes fewer.
 * @param b The second argument word, 0 when the call takes fewer.
 * @param c The third argument word, 0 when the call takes fewer.
 * @param d The fourth argument word, 0 when the call takes fewer.
 * @param e The fifth argument word, 0 when the call takes fewer.
 * @param f The sixth argument word, 0 when the call takes fewer.
 * @return The three result registers as the kernel left them. For a call that doesn't return, it never comes back.
 */
system_call :: fn(number: u64, a: u64 = 0, b: u64 = 0, c: u64 = 0, d: u64 = 0, e: u64 = 0, f: u64 = 0) -> SyscallAnswer #no_context {
    #if TARGET_ARCH == .x86_64 {
        made :: x86_64.system_call(number, a, b, c, d, e, f)
        return SyscallAnswer.{tag = made.rax, first = made.rdx, second = made.r8}
    }
    #else_if TARGET_ARCH == .arm64 {
        made :: aarch64.system_call(number, a, b, c, d, e, f)
        return SyscallAnswer.{tag = made.x0, first = made.x1, second = made.x2}
    }
    #else {
        // Only on x86-64 and AArch64 so far: other architectures' system call registers come with their user mode
        intrinsics.trap()
    }
}

/**
 * A slice as the kernel gets it: where it is in the caller's memory, and how many elements.
 *
 * The kernel has to check it lies in the caller's address space before using it; nothing here does.
 */
UserBuffer :: struct {
    /** The address of the first element in the caller's address space, untrusted. */
    address : u64,
    /** How many elements, not bytes; 0 for an empty slice, whose address means nothing. */
    count : u64,
}

/** How many argument registers a call has: six words, a slice taking two of them. */
SYSCALL_ARGUMENT_WORDS :: 6

/**
 * Generate the call numbers: SYSCALL_<NAME> :: number, a u32, for each call.
 *
 * A call's number is its member's index in Syscalls, so calls are only ever appended to the table.
 *
 * @return The constants' declarations, to insert at the top level.
 */
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

/**
 * Generate a stub for each call in Syscalls, named like its member and taking the same parameters.
 *
 * @return The stubs' declarations, to insert at the top level.
 */
syscall_stubs :: fn() -> compiler.Code {
    made : compiler.Code[..]
    for member, i in table().members {
        array_add(&made, stub(member, cast[u64](i)))
    }
    return compiler.list(made)
}

/**
 * Generate the kernel's dispatch: for the call whose number is number, its handler sys_<name> called with the
 * caller (thread) and the arguments decoded from registers, and its answer returned.
 *
 * Where it's inserted provides registers, thread and number, and these:
 * - word(registers, index) -> u64, an argument register;
 * - buffer(registers, index) -> slop_os.UserBuffer, a slice from two;
 * - answered(tag, first, second): what the dispatch returns.
 *
 * A handler takes a UserBuffer for a slice and a u64 for a pointer, and gives back Result[T, E]; one that
 * blocks the thread gives back anything, and the kernel writes its result when the wait is over. A call
 * that doesn't return gives back nothing, and its dispatch answers 0, 0, 0 if the handler ever comes back.
 * A number that matches no call falls through every statement, for the code after them to answer.
 *
 * @return One if statement per call, to insert where a call arrives.
 */
syscall_dispatch :: fn() -> compiler.Code {
    made : compiler.Code[..]
    for member, i in table().members {
        array_add(&made, dispatch(member, cast[u64](i)))
    }
    return compiler.list(made)
}

/**
 * Fetch the syscall table's type information.
 *
 * @return Syscalls' struct information, whose members are the calls in number order; static, never null.
 */
table :: fn() -> ptr[compiler.TypeInfoStruct] {
    return cast[ptr[compiler.TypeInfoStruct]](type_info_of(Syscalls))
}

/**
 * Generate one call's stub: a #no_context function that puts its arguments in registers, makes the call, and turns
 * the answer into its Result. A call that doesn't return gets a #never_returns stub that loops if the kernel ever
 * comes back.
 *
 * @param member The call's member of Syscalls, whose type is the call's function type.
 * @param number The call's number, its member's index.
 * @return Statements code declaring the stub, a function named as the member with its parameters, for syscall_stubs to
 *     gather into the list it inserts at the top level.
 */
stub :: fn(member: compiler.StructMember, number: u64) -> compiler.Code {
    function :: cast[ptr[compiler.TypeInfoFunction]](member.member_type)
    signature :: compiler.described_type(member.member_type)
    words :: argument_words(function, member.name)
    if function.never_returns {
        return #code {
            #insert compiler.name(member.name) :: fn(#insert compiler.parameters(signature)) #never_returns #no_context {
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

/**
 * Generate the argument words a call's stub passes, from its parameters' names: one word for each register-sized
 * parameter, and a slice's data address then its count.
 *
 * Reports a compile error when the arguments need more than SYSCALL_ARGUMENT_WORDS registers.
 *
 * @param function The call's function type, whose input gives the parameters.
 * @param call The call's name, for the error message.
 * @return The words, as a list of expressions to pass after the call's number.
 */
argument_words :: fn(function: ptr[compiler.TypeInfoFunction], call: string) -> compiler.Code {
    made : compiler.Code[..]
    for input in function.input {
        argument :: compiler.name(input.name)
        if is_slice(input.type) {
            array_add(&made, #code(cast[u64](cast[rawptr]((#insert argument).data))))
            array_add(&made, #code(cast[u64]((#insert argument).count)))
        }
        else {
            array_add(&made, word_of(input.type, argument))
        }
    }
    if #is_compile_time && made.count > SYSCALL_ARGUMENT_WORDS {
        compiler.report_error(#caller_location, "% takes more than % registers of arguments", call, SYSCALL_ARGUMENT_WORDS)
    }
    return compiler.list(made)
}

/**
 * Generate a stub's successful return: .Ok with the value in answer's first and second registers.
 *
 * The code refers to answer, the stub's SyscallAnswer. A struct is rebuilt from its first two members, the first from
 * answer.first and the second from answer.second; any other members are left at their defaults.
 *
 * @param ok The Ok type, or None when the call's Ok carries nothing, for a bare .Ok.
 * @return Statements that return the result.
 */
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
    // A struct's first two members
    members :: cast[ptr[compiler.TypeInfoStruct]](base).members
    stores : compiler.Code[..]
    for field, i in members {
        if i < 2 {
            name :: compiler.name(field.name)
            register := #code(answer.second)
            if i == 0 {
                register = #code(answer.first)
            }
            array_add(&stores, #code {
                value.#insert name = #insert value_of(field.member_type, register)
            })
        }
    }
    return #code {
        value : #insert compiler.type_code(compiler.described_type(type))
        #insert compiler.list(stores)
        return .Ok(value)
    }
}

/**
 * Generate one call's dispatch: an if statement that, when number matches, decodes the arguments from registers,
 * calls the handler sys_<name>, and returns its answer through answered.
 *
 * A slice's argument is a UserBuffer from two registers, a pointer's the raw u64 word, and anything else the word cast
 * to the parameter's type. An error answers its tag in the first register and zeros in the others.
 *
 * @param member The call's member of Syscalls, whose type is the call's function type.
 * @param number The call's number, its member's index.
 * @return Code for one if statement, inserted where the kernel dispatches, using the registers, thread and number
 *     there: when number matches, it returns the call's answer from the function it's in; otherwise it does nothing.
 */
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

/**
 * Generate the Ok case of the match on a handler's result, answering tag 0 and the value in the next two registers.
 *
 * A struct takes its first two members' words, the second 0 when it has only one; any other value takes the first
 * register, with the second 0.
 *
 * @param ok The Ok type, or None when the call's Ok carries nothing, which answers 0, 0, 0.
 * @return Code for one case pattern, Ok or Ok(value), to insert in a match on the handler's result; it returns from the
 *     function it's in.
 */
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
            name :: compiler.name(field.name)
            array_add(&words, word_of(field.member_type, #code(value.#insert name)))
        }
    }
    if words.count < 2 {
        array_add(&words, #code(cast[u64](0)))
    }
    return #code patterns {
        case Ok(value) => return answered(0, #insert compiler.list(words))
    }
}

/**
 * Find a call's result type: its function's last output, which is its only one.
 *
 * @param function The call's function type.
 * @return The result's type information, or a null pointer when the function has no outputs.
 */
result_of :: fn(function: ptr[compiler.TypeInfoFunction]) -> ptr[compiler.TypeInfo] {
    result := cast[ptr[compiler.TypeInfo]](0)
    for output in function.output {
        result = output.type
    }
    return result
}

/**
 * Split a call's Result into its Ok type and its error type.
 *
 * Reports a compile error when the error type isn't an enum, since an error's tag has to fit the first register.
 *
 * @param result The call's result type, a Result[T, E] (through any aliases).
 * @param call The call's name, for the error message.
 * @return ok The Ok type, or None when Ok carries nothing.
 * @return error The error type; result itself when the Result has no Error variant.
 */
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
    if #is_compile_time && underlying(error).variant != .ENUM {
        compiler.report_error(#caller_location, "%'s error isn't an enum", call)
    }
    return ok, error
}

/**
 * Generate the conversion of a register-sized value to a u64 word.
 *
 * An alias converts as what it stands for, an enum through its backing type, a bool to 1 or 0, a pointer to its
 * address, and an integer of at most 8 bytes by a cast. Reports a compile error for anything else.
 *
 * @param type The value's type, not null and only read: an alias, enum, bool, pointer, or integer of at most 8 bytes.
 *     Anything else reports a compile error, and value is cast as if it were an integer.
 * @param value The expression to convert.
 * @return An expression of type u64.
 */
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
    if #is_compile_time && (type.variant != .INTEGER || type.size > 8) {
        compiler.report_error(#caller_location, "a call's argument or result doesn't fit a register")
    }
    return #code(cast[u64](#insert value))
}

/**
 * Generate the conversion of a u64 word to a value of a register-sized type, the reverse of word_of.
 *
 * An enum converts through its backing type, unchecked, so a word that's no member gives a value that's none either;
 * a bool is true for any nonzero word.
 *
 * @param type The type to convert to.
 * @param word The u64 expression to convert.
 * @return An expression of the given type.
 */
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

/**
 * Find the type an alias stands for, through every alias.
 *
 * @param type The type, an alias or not.
 * @return The first type that isn't an alias, or type itself when it isn't one. It stops after 16 aliases, giving
 *     the alias it reached.
 */
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

/**
 * Tell whether a type is a slice, a one-dimensional view, which a call passes in two registers.
 *
 * @param type The type, through any aliases.
 * @return True for a slice, false for anything else, fixed-size and growing arrays included.
 */
is_slice :: fn(type: ptr[compiler.TypeInfo]) -> bool {
    base :: underlying(type)
    if base.variant != .ARRAY {
        return false
    }
    dimensions :: cast[ptr[compiler.TypeInfoArray]](base).dimensions
    return dimensions.count == 1 && dimensions[0].type == .VIEW
}

/**
 * Make a name upper case: port_wait becomes PORT_WAIT.
 *
 * Only ASCII a to z change.
 *
 * @param name The name to change.
 * @param upper The bytes the upper-case name is written into. Only 64 fit, so a longer name is cut to 64 bytes.
 * @return The upper-case name, a view of upper's bytes, good as long as upper is and isn't written again.
 */
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

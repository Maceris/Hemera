package runtime

import intrinsics from "base"

/*
 * The process's command-line arguments, the program's name first, as UTF-8. They're worked out the
 * first time they're asked for, from any thread, and kept for the rest of the process, in memory
 * from HOSTED_CONTEXT's allocator, so there's nothing to free:
 *
 *     for argument in runtime.process_arguments() { use(argument) }
 *
 * On Linux they're argv as the entry was given it (docs/compilation.md). On Windows they're
 * GetCommandLineW split the way the C runtime splits it (split_command_line). Elsewhere there are
 * none.
 */
process_arguments :: fn() -> string[] {
    state :: intrinsics.process_state()
    // 0 until someone starts, 1 while they work them out, 2 once they're there
    _, won :: intrinsics.interlocked_compare_exchange_u32_acquire(&state.arguments_state, 1, 0)
    if won {
        state.arguments = os_command_line_arguments(HOSTED_CONTEXT.allocator)
        intrinsics.atomic_store_u32_release(&state.arguments_state, 2)
    }
    loop {
        if intrinsics.atomic_load_u32_acquire(&state.arguments_state) == 2 {
            break
        }
        intrinsics.spin_hint()
    }
    return state.arguments
}

/*
 * The arguments in a Windows command line, as the C runtime splits it, into bytes (at least as
 * many as the command line has) and arguments, giving back how many there are: only what fits is
 * written, so a first call with an empty arguments counts them. The arguments view bytes, so bytes
 * is #escaping.
 *
 * * The program's name is first: up to the next quote if it starts with one, otherwise up to a
 *   space or tab. Backslashes in it are kept as they are.
 * * The others are separated by spaces and tabs outside quotes. A quote starts or ends a quoted
 *   part, and two quotes inside one are a quote.
 * * Backslashes are kept, except before a quote: 2n of them then are n, and the quote does its
 *   usual job, and 2n + 1 are n then a quote.
 */
split_command_line :: fn(line: string, bytes #escaping : mut u8[], arguments: mut string[]) -> usize {
    count : usize = 0
    written : usize = 0
    index : usize = 0
    if line.count == 0 {
        return 0
    }
    // The program's name
    start := written
    if line[0] == '"' {
        index = 1
        loop {
            if index >= line.count || line[index] == '"' {
                break
            }
            written = put_byte(bytes, written, cast[u32](line[index]))
            index += 1
        }
        index += 1
    }
    else {
        loop {
            if index >= line.count || line[index] == ' ' || line[index] == '\t' {
                break
            }
            written = put_byte(bytes, written, cast[u32](line[index]))
            index += 1
        }
    }
    count = finish_argument(bytes, arguments, count, start, written)
    loop {
        loop {
            if index >= line.count || (line[index] != ' ' && line[index] != '\t') {
                break
            }
            index += 1
        }
        if index >= line.count {
            break
        }
        start = written
        quoted := false
        loop {
            if index >= line.count {
                break
            }
            character :: line[index]
            if (character == ' ' || character == '\t') && !quoted {
                break
            }
            if character == '\\' {
                backslashes : usize = 0
                loop {
                    if index >= line.count || line[index] != '\\' {
                        break
                    }
                    backslashes += 1
                    index += 1
                }
                if index < line.count && line[index] == '"' {
                    for i in 0..<(backslashes / 2) {
                        written = put_byte(bytes, written, cast[u32]('\\'))
                    }
                    if backslashes % 2 == 1 {
                        written = put_byte(bytes, written, cast[u32]('"'))
                        index += 1
                    }
                }
                else {
                    for i in 0..<backslashes {
                        written = put_byte(bytes, written, cast[u32]('\\'))
                    }
                }
            }
            else if character == '"' {
                if quoted && index + 1 < line.count && line[index + 1] == '"' {
                    written = put_byte(bytes, written, cast[u32]('"'))
                    index += 2
                }
                else {
                    quoted = !quoted
                    index += 1
                }
            }
            else {
                written = put_byte(bytes, written, cast[u32](character))
                index += 1
            }
        }
        count = finish_argument(bytes, arguments, count, start, written)
    }
    return count
}

// The argument in bytes from start to end as arguments[count], if both fit, giving back the next count.
finish_argument :: fn(bytes #escaping : mut u8[], arguments: mut string[], count: usize, start: usize, end: usize) -> usize {
    if count < arguments.count && end <= bytes.count {
        if end > start && start < bytes.count {
            arguments[count] = string_of(&bytes[start], end - start)
        }
        else {
            arguments[count] = ""
        }
    }
    return count + 1
}

// The longest argument or environment string Linux passes a program, with its 0 (MAX_ARG_STRLEN).
ARGUMENT_TEXT_LIMIT :: 131072

/*
 * Bytes up to the first 0, as a string, without copying, looking at no more than limit of them: None if there's no 0
 * among them, so what isn't text ending where it should isn't read on past where it could end. Empty for null.
 */
cstring_view :: fn(start: rawptr, limit: usize) -> string? {
    if start == null {
        return ""
    }
    length : usize = 0
    loop {
        if length >= limit {
            return null
        }
        if cast[ptr[u8]](start + length)^ == 0 {
            break
        }
        length += 1
    }
    if length == 0 {
        return ""
    }
    return string_of(cast[ptr[u8]](start), length)
}

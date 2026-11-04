package runtime

import intrinsics from "base"

/**
 * Give the process's command-line arguments, the program's name first, as UTF-8.
 *
 * They're worked out the first time they're asked for, from any thread, and kept for the rest of the process, in
 * memory from HOSTED_CONTEXT's allocator, so there's nothing to free. A call made while another thread is working
 * them out waits, spinning, until that one is done, so every caller gets the same arguments.
 *
 * On Linux they're argv as the entry was given it (docs/compilation.md). On Windows they're GetCommandLineW split
 * the way the C runtime splits it (split_command_line). Elsewhere there are none.
 *
 * @return The arguments, viewing memory that stays good, unchanged, for the rest of the process; the caller mustn't
 *     free them. Empty where there are none, or when there wasn't the memory to work them out.
 * @example for argument in runtime.process_arguments() { use(argument) }
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

/**
 * Split a Windows command line into its arguments, as the C runtime splits it.
 *
 * Only what fits is written, so a first call with an empty arguments counts them, and a second, with arguments
 * that long, fills them in. Nothing is allocated.
 *
 * * The program's name is first: up to the next quote if it starts with one (or the line's end, without a closing
 *   quote), otherwise up to a space or tab. Backslashes in it are kept as they are.
 * * The others are separated by spaces and tabs outside quotes. A quote starts or ends a quoted part, and two
 *   quotes inside one are a quote.
 * * Backslashes are kept, except before a quote: 2n of them then are n, and the quote does its usual job, and
 *   2n + 1 are n then a quote.
 *
 * @param line The command line, as UTF-8; it's only read, and the arguments don't view it.
 * @param bytes Where the arguments' text is written, one after another with nothing between them. It needs at least
 *     as many bytes as line has, which is always enough; the arguments view it, so it's #escaping and has to outlive
 *     them. Text past its end is counted but not written.
 * @param arguments Where the arguments go, each viewing bytes. Only the first arguments.count are written, and an
 *     argument whose text didn't all fit in bytes is left as it was. Empty to only count them.
 * @return How many arguments the line has, whether or not they fit: 0 for an empty line, otherwise at least 1, the
 *     program's name, which may be empty.
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

/**
 * Store the argument whose text was just written to bytes as arguments[count], if both fit.
 *
 * @param bytes The text split_command_line is writing, which the argument views; #escaping, as there.
 * @param arguments Where the argument goes. Nothing is stored when count is past its end.
 * @param count The argument's index among them all, counted even when they don't fit.
 * @param start Where its text starts in bytes, in bytes.
 * @param end Where its text ends in bytes, one past its last byte; when it's past bytes' end, the text didn't all fit
 *     and nothing is stored. start equal to end gives an empty argument.
 * @return The next argument's index, count + 1, whether or not this one was stored.
 */
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

/**
 * The longest argument or environment string Linux passes a program, in bytes, with its 0 (MAX_ARG_STRLEN), so a
 * string not ended within it isn't one.
 */
ARGUMENT_TEXT_LIMIT :: 131072

/**
 * View the bytes up to the first 0 as a string, without copying, looking at no more than a limit of them.
 *
 * The limit keeps what isn't text ending where it should from being read on past where it could end.
 *
 * @param start The first byte, or null. The bytes aren't checked as UTF-8.
 * @param limit The most bytes to look at for the 0, the 0 included; 0 finds none.
 * @return The bytes before the 0, viewing the memory at start, so good for as long as it is. Empty for null or when
 *     the first byte is 0, and None when there's no 0 among the first limit bytes.
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

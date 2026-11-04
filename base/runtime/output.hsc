package runtime

import compiler from "base"
import intrinsics from "base"

/**
 * Which of the process's standard streams text goes to, where there are some.
 *
 * Text goes by WriteFile on Windows, the write system call on Linux, and the console under UEFI. Elsewhere, like in
 * a kernel, the text goes nowhere.
 *
 *     runtime.write_output("hello\n")
 *     runtime.write_error("something went wrong\n")
 *
 * Text is written as it's given, in bytes, with nothing added: no newline, and no translation.
 * Each call is one write, for text that fits one (all of it, in practice), so lines from several
 * threads written whole don't mix.
 */
OutputStream :: enum {
    OUTPUT, /**< Standard output, for what the program produces. */
    ERROR, /**< Standard error, for diagnostics, logs and failures. */
}

/**
 * Write text to standard output, as it is, where there is one.
 *
 * A failure to write isn't reported: there's nowhere to report it, so the text is lost.
 *
 * @param text The bytes, with nothing added: no newline, and no translation. Empty writes nothing.
 */
write_output #no_context :: fn(text: string) {
    os_write(.OUTPUT, cast[rawptr](text.data), text.count)
}

/**
 * Write text to standard error, as it is, where there is one.
 *
 * A failure to write isn't reported: there's nowhere to report it, so the text is lost.
 *
 * @param text The bytes, with nothing added: no newline, and no translation. Empty writes nothing.
 */
write_error #no_context :: fn(text: string) {
    os_write(.ERROR, cast[rawptr](text.data), text.count)
}

/** Bytes an OutputBuffer holds before it writes them; small, since a buffer is kept on the stack. */
OUTPUT_BUFFER_SIZE : usize : 512

/**
 * Text built a piece at a time on the stack, then written whole, for the standard logger and the
 * assertion handler, which can't count on an allocator. Writes what it has when it fills up.
 *
 *     buffer :: runtime.output_buffer(.ERROR)
 *     runtime.output_format(&buffer, "% of %\n", done, total)
 *     runtime.output_flush(&buffer)
 */
OutputBuffer :: struct {
    /** The text not yet written; only the first count bytes mean anything. */
    bytes : u8[OUTPUT_BUFFER_SIZE],
    /** How many of bytes hold text, from 0 to OUTPUT_BUFFER_SIZE. */
    count : usize,
    /** Where the text is written when the buffer fills or is flushed. */
    stream : OutputStream,
    /**
     * Whether the buffer keeps what it's given rather than writing it, dropping what doesn't fit, so the text can be
     * padded afterwards; false for a buffer from output_buffer.
     */
    capture : bool,
}

/**
 * Make an empty buffer that writes to a stream.
 *
 * @param stream Where its text is written.
 * @return The buffer, empty and not capturing, to keep on the stack; it holds no memory, so it needs no freeing,
 *     but what's in it is lost unless it's flushed.
 */
output_buffer #no_context :: fn(stream: OutputStream) -> OutputBuffer {
    buffer : OutputBuffer
    buffer.count = 0
    buffer.stream = stream
    return buffer
}

/**
 * Write what a buffer has to its stream, and empty it.
 *
 * @param buffer The buffer; written even when it captures. When it's empty, nothing is written.
 */
output_flush #no_context :: fn(buffer: ptr[mut OutputBuffer]) {
    count :: if buffer.count < OUTPUT_BUFFER_SIZE { buffer.count } else { OUTPUT_BUFFER_SIZE }
    if count > 0 {
        os_write(buffer.stream, cast[rawptr](&buffer.bytes[0]), count)
    }
    buffer.count = 0
}

/**
 * Add a byte to a buffer.
 *
 * @param buffer The buffer, which writes what it holds to its stream when it fills, unless it captures.
 *     A capturing buffer that's full drops the byte.
 * @param byte The byte, as it is.
 */
output_byte #no_context :: fn(buffer: ptr[mut OutputBuffer], byte: u8) {
    if buffer.count >= OUTPUT_BUFFER_SIZE && buffer.capture {
        return void
    }
    if buffer.count >= OUTPUT_BUFFER_SIZE {
        output_flush(buffer)
    }
    index :: buffer.count
    if index < OUTPUT_BUFFER_SIZE {
        buffer.bytes[index] = byte
        buffer.count = index + 1
    }
}

/**
 * Add text to a buffer, as it is.
 *
 * @param buffer The buffer, which writes what it holds to its stream when it fills, unless it captures.
 * @param text The bytes, which may be empty.
 */
output_text #no_context :: fn(buffer: ptr[mut OutputBuffer], text: string) {
    for i in 0..<text.count {
        output_byte(buffer, cast[u8](text[i]))
    }
}

/**
 * Add an unsigned integer to a buffer in decimal.
 *
 * @param buffer The buffer, which writes what it holds to its stream when it fills, unless it captures.
 * @param value The integer, any u64; 0 is written as one digit.
 */
output_unsigned #no_context :: fn(buffer: ptr[mut OutputBuffer], value: u64) {
    digits : u8[20]
    count : usize = 0
    rest := value
    loop #at_least_once {
        if count < 20 {
            digits[count] = cast[u8](rest % 10) + cast[u8]('0')
            count += 1
        }
        rest = rest / 10
    }
    while rest != 0
    loop {
        if count == 0 || count > 20 {
            break
        }
        count -= 1
        output_byte(buffer, digits[count])
    }
}

/**
 * Add a signed integer to a buffer in decimal, with a - when it's negative.
 *
 * @param buffer The buffer, which writes what it holds to its stream when it fills, unless it captures.
 * @param value The integer, any i64, the most negative one included.
 */
output_signed #no_context :: fn(buffer: ptr[mut OutputBuffer], value: i64) {
    if value < 0 {
        output_byte(buffer, cast[u8]('-'))
        // Negated as unsigned, which works for the most negative value too
        output_unsigned(buffer, 0 - cast[u64](value))
    }
    else {
        output_unsigned(buffer, cast[u64](value))
    }
}

/**
 * Add an address to a buffer in hexadecimal, as 0x and at least one digit, in lower case without leading zeros.
 *
 * @param buffer The buffer, which writes what it holds to its stream when it fills, unless it captures.
 * @param value The address, any u64; 0 is written 0x0.
 */
output_address #no_context :: fn(buffer: ptr[mut OutputBuffer], value: u64) {
    output_text(buffer, "0x")
    started := false
    for i in 0..<16 {
        nibble :: cast[u8]((value >> cast[u64](60 - 4 * i)) & 15)
        if nibble != 0 || started || i == 15 {
            started = true
            output_byte(buffer, if nibble < 10 { cast[u8]('0') + nibble } else { cast[u8]('a') + nibble - 10 })
        }
    }
}

/**
 * Add formatted text to a buffer: a smaller version of std's text_buffer.append_format, for base.
 *
 * Each % is replaced by the next value, %1, %2 and so on by that one, and %% by %. Integers are in decimal, booleans,
 * characters and strings as they are, enum members by name, and pointers as addresses; other values
 * only by their kind, like <struct Name>. Each can have options, like %{08x} (docs/format_strings.md).
 * A % without a value left, %0, or one with options that aren't well formed, is written as %!.
 *
 * @param buffer The buffer, which writes what it holds to its stream when it fills, unless it captures.
 * @param format_string The text, with its placeholders; everything else is written as it is.
 * @param values The values the placeholders take, in order; a numbered one doesn't move the next unnumbered one on,
 *     and values no placeholder takes are left out.
 */
output_format :: fn(buffer: ptr[mut OutputBuffer], format_string: string, values: any...) {
    next : usize = 0
    index : usize = 0
    loop {
        if index >= format_string.count {
            break
        }
        character :: format_string[index]
        index += 1
        if character != '%' {
            output_byte(buffer, cast[u8](character))
            continue
        }
        if index < format_string.count && format_string[index] == '%' {
            output_byte(buffer, cast[u8]('%'))
            index += 1
            continue
        }
        // %1, %2...: a value by its number
        number : usize = 0
        numbered := false
        for step in 0..<format_string.count {
            if index >= format_string.count || !is_format_digit(format_string[index]) {
                break
            }
            number = number * 10 + cast[usize](format_string[index]) - cast[usize]('0')
            numbered = true
            index += 1
        }
        spec, after, valid :: parse_format_spec(format_string, index)
        index = after
        chosen := next
        if !numbered {
            next += 1
        }
        else {
            chosen = if number > 0 { number - 1 } else { values.count }
        }
        if !valid || chosen >= values.count {
            output_text(buffer, "%!")
            continue
        }
        output_value_with(buffer, values[chosen], spec)
    }
}

/**
 * Add a byte to an OutputBuffer, as a FormatSink's emit.
 *
 * @param target The OutputBuffer, as a ptr[mut OutputBuffer].
 * @param byte The byte, as output_byte adds it.
 */
output_sink_byte :: fn(target: rawptr, byte: u8) {
    output_byte(cast[ptr[mut OutputBuffer]](target), byte)
}

/**
 * Check whether options change nothing about how a value is written, so it can be written the plain way.
 *
 * @param spec Options as parse_format_spec reads them; only read.
 * @return Whether there's no width, kind, +, # or precision; a fill, alignment or 0 alone change nothing.
 */
is_plain_format :: fn(spec: FormatSpec) -> bool {
    return spec.width == 0 && spec.kind == 0 && !spec.plus && !spec.prefix && !spec.has_precision
}

/**
 * Add a value with options to a buffer: numbers worked out with them, anything else written, then padded.
 *
 * Integers up to 64 bits, and characters, booleans and enums with a kind, are written as numbers with the options;
 * pointers and functions that aren't null as addresses, in hexadecimal with 0x unless a kind is given; strings cut
 * to the precision and padded. Anything else is written as output_value writes it, at most OUTPUT_BUFFER_SIZE bytes
 * of it, then padded.
 *
 * @param buffer The buffer, which writes what it holds to its stream when it fills, unless it captures.
 * @param value The value; its type's aliases are seen through, up to 64 deep.
 * @param spec The options; when they change nothing, the value is written as output_value writes it.
 */
output_value_with :: fn(buffer: ptr[mut OutputBuffer], value: any, spec: FormatSpec) {
    if is_plain_format(spec) {
        output_value(buffer, value)
        return void
    }
    sink :: FormatSink.{target = cast[rawptr](buffer), emit = output_sink_byte}
    given :: type_info_of(value.type)
    info := given
    for step in 0..<64 {
        if cast[rawptr](info) == null || info.variant != .ALIAS {
            break
        }
        info = cast[ptr[compiler.TypeInfoAlias]](info).base_type
    }
    if cast[rawptr](info) != null {
        data :: value.data
        variant :: info.variant
        numeric :: spec.kind != 0 && (variant == .CHAR || variant == .BOOLEAN || variant == .ENUM)
        if variant == .INTEGER && info.size <= 8 && cast[ptr[compiler.TypeInfoInteger]](info).is_signed {
            signed :: read_signed(data, info.size)
            format_integer(sink, spec, signed < 0, if signed < 0 { 0 - cast[u64](signed) } else { cast[u64](signed) })
            return void
        }
        if (variant == .INTEGER && info.size <= 8) || numeric {
            format_integer(sink, spec, false, read_unsigned(data, info.size))
            return void
        }
        if (variant == .POINTER || variant == .FUNCTION) && cast[ptr[u64]](data)^ != 0 {
            // An address: in hexadecimal unless another kind is asked for, with 0x when it's the default
            with_kind := spec
            if with_kind.kind == 0 {
                with_kind.kind = cast[u8]('x')
                with_kind.prefix = true
            }
            format_integer(sink, with_kind, false, cast[ptr[u64]](data)^)
            return void
        }
        if variant == .STRING && !cast[ptr[compiler.TypeInfoString]](info).is_raw {
            format_text(sink, spec, cast[ptr[string]](data)^)
            return void
        }
    }
    // Anything else, written as usual, then padded
    scratch := output_buffer(buffer.stream)
    scratch.capture = true
    output_value(&scratch, value)
    count :: if scratch.count < OUTPUT_BUFFER_SIZE { scratch.count } else { OUTPUT_BUFFER_SIZE }
    text :: if count > 0 { string_of(&scratch.bytes[0], count) } else { "" }
    format_text(sink, spec, text)
}

/**
 * Add a value to a buffer, written as output_format writes it without options.
 *
 * Integers are in decimal, booleans true or false, characters as one byte, strings and cstrings as they are,
 * enum members by name (or the enum's name and the number, like Color(7), for a value that's no member), pointers and
 * functions as addresses or null, and floats of 16, 32 and 64 bits as the shortest text that reads back as the same
 * value. A struct is only <struct Name>, anything else <value>, and a value with no type <nothing>. Integers and enums
 * wider than 64 bits are written by their low 64.
 *
 * @param buffer The buffer, which writes what it holds to its stream when it fills, unless it captures.
 * @param value The value; its type's aliases are seen through.
 */
output_value :: fn(buffer: ptr[mut OutputBuffer], value: any) {
    given :: type_info_of(value.type)
    if cast[rawptr](given) == null {
        output_text(buffer, "<nothing>")
        return void
    }
    info := given
    loop {
        if info.variant != .ALIAS {
            break
        }
        info = cast[ptr[compiler.TypeInfoAlias]](info).base_type
    }
    data :: value.data
    variant :: info.variant
    if variant == .INTEGER {
        if cast[ptr[compiler.TypeInfoInteger]](info).is_signed {
            output_signed(buffer, read_signed(data, info.size))
        }
        else {
            output_unsigned(buffer, read_unsigned(data, info.size))
        }
    }
    else if variant == .BOOLEAN {
        output_text(buffer, if read_unsigned(data, info.size) != 0 { "true" } else { "false" })
    }
    else if variant == .CHAR {
        output_byte(buffer, cast[ptr[u8]](data)^)
    }
    else if variant == .STRING {
        if cast[ptr[compiler.TypeInfoString]](info).is_raw {
            output_cstring(buffer, cast[ptr[rawptr]](data)^)
        }
        else {
            output_text(buffer, cast[ptr[string]](data)^)
        }
    }
    else if variant == .ENUM {
        enum_info :: cast[ptr[compiler.TypeInfoEnum]](info)
        raw :: cast[u128](read_unsigned(data, info.size))
        for member_value, member in enum_info.values {
            if member_value == raw && member < enum_info.members.count {
                output_text(buffer, enum_info.members[member])
                return void
            }
        }
        output_text(buffer, enum_info.name)
        output_byte(buffer, cast[u8]('('))
        output_unsigned(buffer, cast[u64](raw))
        output_byte(buffer, cast[u8](')'))
    }
    else if variant == .POINTER || variant == .FUNCTION {
        address :: cast[ptr[u64]](data)^
        if address == 0 {
            output_text(buffer, "null")
        }
        else {
            output_address(buffer, address)
        }
    }
    else if variant == .FLOAT && (info.size == 2 || info.size == 4 || info.size == 8) {
        // The shortest text that reads back as the same value (format_shortest_float)
        sink :: FormatSink.{target = cast[rawptr](buffer), emit = output_sink_byte}
        bits :: read_unsigned(data, info.size)
        exponent_bits : u64 = if info.size == 2 { 5 } else if info.size == 4 { 8 } else { 11 }
        fraction_bits : u64 = if info.size == 2 { 10 } else if info.size == 4 { 23 } else { 52 }
        format_shortest_float(sink, bits, exponent_bits, fraction_bits)
    }
    else if variant == .STRUCT {
        output_text(buffer, "<struct ")
        output_text(buffer, cast[ptr[compiler.TypeInfoStruct]](info).name)
        output_byte(buffer, cast[u8]('>'))
    }
    else {
        output_text(buffer, "<value>")
    }
}

/**
 * Add a cstring's bytes to a buffer, up to its first 0.
 *
 * @param buffer The buffer, which writes what it holds to its stream when it fills, unless it captures.
 * @param start The cstring's first byte, read up to its 0, which has to be there; null is written as null.
 */
output_cstring #no_context :: fn(buffer: ptr[mut OutputBuffer], start: rawptr) {
    if start == null {
        output_text(buffer, "null")
        return void
    }
    index : usize = 0
    loop {
        byte :: cast[ptr[u8]](start + index)^
        if byte == 0 {
            break
        }
        output_byte(buffer, byte)
        index += 1
    }
}

/**
 * Read an unsigned integer from memory, widened to a u64.
 *
 * @param data Where it is, size bytes that can be read.
 * @param size Its size in bytes: 1, 2 or 4, and anything else is read as 8, so only the low half of a 128-bit one.
 * @return The integer, zero-extended.
 */
read_unsigned #no_context :: fn(data: rawptr, size: usize) -> u64 {
    if size == 1 {
        return cast[u64](cast[ptr[u8]](data)^)
    }
    if size == 2 {
        return cast[u64](cast[ptr[u16]](data)^)
    }
    if size == 4 {
        return cast[u64](cast[ptr[u32]](data)^)
    }
    // Only the low half of a 128-bit one
    return cast[ptr[u64]](data)^
}

/**
 * Read a signed integer from memory, widened to an i64.
 *
 * @param data Where it is, size bytes that can be read.
 * @param size Its size in bytes: 1, 2 or 4, and anything else is read as 8, so only the low half of a 128-bit one.
 * @return The integer, sign-extended.
 */
read_signed #no_context :: fn(data: rawptr, size: usize) -> i64 {
    if size == 1 {
        return cast[i64](cast[ptr[i8]](data)^)
    }
    if size == 2 {
        return cast[i64](cast[ptr[i16]](data)^)
    }
    if size == 4 {
        return cast[i64](cast[ptr[i32]](data)^)
    }
    return cast[ptr[i64]](data)^
}

/**
 * The logger hosted programs start with: each message on a line of its own on standard error, after
 * its level, like
 *
 *     [info] loaded 3 files
 *
 * Messages below context.log_level are dropped. Values are formatted by output_format.
 */
STANDARD_LOGGER :: Logger.{
    data = null,
    trace = standard_log_trace,
    debug = standard_log_debug,
    info = standard_log_info,
    warn = standard_log_warn,
    error = standard_log_error,
    fatal = standard_log_fatal,
    name = "standard",
}

/**
 * Log a message at the trace level, as STANDARD_LOGGER does.
 *
 * @param format_string The message, formatted by output_format.
 * @param params The values its placeholders take.
 * @param location Where the call is; the standard logger doesn't write it.
 */
standard_log_trace : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    standard_log(.TRACE, "trace", format_string, params)
}

/**
 * Log a message at the debug level, as STANDARD_LOGGER does.
 *
 * @param format_string The message, formatted by output_format.
 * @param params The values its placeholders take.
 * @param location Where the call is; the standard logger doesn't write it.
 */
standard_log_debug : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    standard_log(.DEBUG, "debug", format_string, params)
}

/**
 * Log a message at the info level, as STANDARD_LOGGER does.
 *
 * @param format_string The message, formatted by output_format.
 * @param params The values its placeholders take.
 * @param location Where the call is; the standard logger doesn't write it.
 */
standard_log_info : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    standard_log(.INFO, "info", format_string, params)
}

/**
 * Log a message at the warning level, as STANDARD_LOGGER does.
 *
 * @param format_string The message, formatted by output_format.
 * @param params The values its placeholders take.
 * @param location Where the call is; the standard logger doesn't write it.
 */
standard_log_warn : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    standard_log(.WARN, "warn", format_string, params)
}

/**
 * Log a message at the error level, as STANDARD_LOGGER does.
 *
 * @param format_string The message, formatted by output_format.
 * @param params The values its placeholders take.
 * @param location Where the call is; the standard logger doesn't write it.
 */
standard_log_error : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    standard_log(.ERROR, "error", format_string, params)
}

/**
 * Log a message at the fatal level, as STANDARD_LOGGER does; it doesn't end the program.
 *
 * @param format_string The message, formatted by output_format.
 * @param params The values its placeholders take.
 * @param location Where the call is; the standard logger doesn't write it.
 */
standard_log_fatal : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    standard_log(.FATAL, "fatal", format_string, params)
}

/**
 * Write a log message on a line of its own on standard error, after its level, unless it's below context.log_level.
 *
 * The line is built in an OutputBuffer and written in one write when it fits, so lines from several threads don't
 * mix; a longer one is written in pieces of OUTPUT_BUFFER_SIZE bytes.
 *
 * @param level The message's level, compared with context.log_level.
 * @param label What's written in brackets before the message, like info.
 * @param format_string The message, formatted by output_format.
 * @param params The values its placeholders take.
 */
standard_log :: fn(level: LogLevel, label: string, format_string: string, params: any[]) {
    if cast[int](level) < cast[int](context.log_level) {
        return void
    }
    buffer := output_buffer(.ERROR)
    output_byte(&buffer, cast[u8]('['))
    output_text(&buffer, label)
    output_text(&buffer, "] ")
    output_format(&buffer, format_string, params)
    output_byte(&buffer, cast[u8]('\n'))
    output_flush(&buffer)
}

/**
 * The exit code of a program a failed assertion ended, from printing_assertion_handler: 134, what a shell reports
 * for a process ended by SIGABRT.
 */
ASSERTION_EXIT_CODE : u32 : 134

/**
 * Write a failed assertion to standard error, where it was and the stack that led there, then end the process with
 * ASSERTION_EXIT_CODE: the assertion handler hosted programs start with.
 *
 *     assertion failed: count must be positive
 *         at main.hsc:12:5, in check
 *         0x140a  app.main+0x6a
 *         0x155d
 *         (hemera --symbolize=app.exe 0x140a 0x155d for files and lines)
 *
 * The stack is its return addresses, innermost first, starting in assert (or where it was
 * inlined), as offsets into the program's image, which are the same every run. With debug info,
 * each is followed by the Hemera function it's in (function_at), and hemera --symbolize turns
 * them into files and lines, inlined calls included. At most 32 are written.
 *
 * @param location Where the assertion is: its file, line and column, and its function when that's known.
 * @param message What failed, written after "assertion failed: ".
 */
printing_assertion_handler : AssertionHandler : fn(location: SourceCodeLocation, message: string) #never_returns {
    buffer := output_buffer(.ERROR)
    output_text(&buffer, "assertion failed: ")
    output_text(&buffer, message)
    output_text(&buffer, "\n    at ")
    output_text(&buffer, location.file_path)
    output_byte(&buffer, cast[u8](':'))
    output_unsigned(&buffer, cast[u64](location.line))
    output_byte(&buffer, cast[u8](':'))
    output_unsigned(&buffer, cast[u64](location.column))
    if location.function.count > 0 {
        output_text(&buffer, ", in ")
        output_text(&buffer, location.function)
    }
    output_byte(&buffer, cast[u8]('\n'))
    addresses : rawptr[32]
    // From the handler's caller: assert, or what called it where assert was inlined
    count :: intrinsics.capture_stack_trace(addresses)
    for address, index in addresses {
        if index >= count {
            break
        }
        output_text(&buffer, "    ")
        output_address(&buffer, cast[u64](image_offset(address)))
        // A return address may be just past a call that ends its function
        name, offset :: function_at(cast[rawptr](cast[usize](address) - 1))
        if name.count > 0 {
            output_text(&buffer, "  ")
            output_text(&buffer, name)
            output_byte(&buffer, cast[u8]('+'))
            output_address(&buffer, cast[u64](offset + 1))
        }
        output_byte(&buffer, cast[u8]('\n'))
    }
    if count > 0 {
        program := "<program>"
        arguments :: process_arguments()
        if arguments.count > 0 {
            program = arguments[0]
        }
        output_text(&buffer, "    (hemera --symbolize=")
        output_text(&buffer, program)
        for address, index in addresses {
            if index >= count {
                break
            }
            output_byte(&buffer, cast[u8](' '))
            output_address(&buffer, cast[u64](image_offset(address)))
        }
        output_text(&buffer, " for files and lines)\n")
    }
    output_flush(&buffer)
    os_exit_process(ASSERTION_EXIT_CODE)
}

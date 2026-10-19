package runtime

import compiler from "base"
import intrinsics from "base"

/*
 * Text for the process's standard output and standard error, where there are some: WriteFile on
 * Windows, and the write system call on Linux. Elsewhere, like in a kernel, the text goes nowhere.
 *
 *     runtime.write_output("hello\n")
 *     runtime.write_error("something went wrong\n")
 *
 * Text is written as it's given, in bytes, with nothing added: no newline, and no translation.
 * Each call is one write, for text that fits one (all of it, in practice), so lines from several
 * threads written whole don't mix.
 */
OutputStream :: enum {
    OUTPUT,
    ERROR,
}

write_output #no_context :: fn(text: string) {
    os_write(.OUTPUT, cast[rawptr](text.data), text.count)
}

write_error #no_context :: fn(text: string) {
    os_write(.ERROR, cast[rawptr](text.data), text.count)
}

// Bytes an OutputBuffer holds before it writes them.
OUTPUT_BUFFER_SIZE : usize : 512

/*
 * Text built a piece at a time on the stack, then written whole, for the standard logger and the
 * assertion handler, which can't count on an allocator. Writes what it has when it fills up.
 *
 *     buffer :: runtime.output_buffer(.ERROR)
 *     runtime.output_format(&buffer, "% of %\n", done, total)
 *     runtime.output_flush(&buffer)
 */
OutputBuffer :: struct {
    bytes : u8[OUTPUT_BUFFER_SIZE],
    count : usize,
    stream : OutputStream,
    // Keeps what it's given rather than writing it, dropping what doesn't fit, to pad it afterwards
    capture : bool,
}

output_buffer #no_context :: fn(stream: OutputStream) -> OutputBuffer {
    buffer : OutputBuffer
    buffer.count = 0
    buffer.stream = stream
    return buffer
}

// Writes what the buffer has, and empties it.
output_flush #no_context :: fn(buffer: ptr[mut OutputBuffer]) {
    count :: if buffer.count < OUTPUT_BUFFER_SIZE { buffer.count } else { OUTPUT_BUFFER_SIZE }
    if count > 0 {
        os_write(buffer.stream, cast[rawptr](&buffer.bytes[0]), count)
    }
    buffer.count = 0
}

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

output_text #no_context :: fn(buffer: ptr[mut OutputBuffer], text: string) {
    for i in 0..<text.count {
        output_byte(buffer, cast[u8](text[i]))
    }
}

// value in decimal. Once at least, so 0 has its digit.
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

// value in hexadecimal, as 0x and at least one digit.
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

/*
 * format_string with each % replaced by the next value, %1, %2 and so on by that one, and %% by %:
 * a smaller version of std's text_buffer.append_format, for base. Integers are in decimal, booleans,
 * characters and strings as they are, enum members by name, and pointers as addresses; other values
 * only by their kind, like <struct Name>. Each can have options, like %{08x} (docs/format_strings.md).
 * A % without a value left, or with options that aren't well formed, is written as %!.
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

output_sink_byte :: fn(target: rawptr, byte: u8) {
    output_byte(cast[ptr[mut OutputBuffer]](target), byte)
}

// Whether options change anything about how a value is written.
is_plain_format :: fn(spec: FormatSpec) -> bool {
    return spec.width == 0 && spec.kind == 0 && !spec.plus && !spec.prefix && !spec.has_precision
}

// A value with options: numbers worked out with them, anything else written, then padded.
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
    else if variant == .STRUCT {
        output_text(buffer, "<struct ")
        output_text(buffer, cast[ptr[compiler.TypeInfoStruct]](info).name)
        output_byte(buffer, cast[u8]('>'))
    }
    else {
        output_text(buffer, "<value>")
    }
}

// Bytes up to the first 0.
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

// An integer of size bytes at data, up to 8.
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

/*
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

standard_log_trace : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    standard_log(.TRACE, "trace", format_string, params)
}

standard_log_debug : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    standard_log(.DEBUG, "debug", format_string, params)
}

standard_log_info : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    standard_log(.INFO, "info", format_string, params)
}

standard_log_warn : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    standard_log(.WARN, "warn", format_string, params)
}

standard_log_error : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    standard_log(.ERROR, "error", format_string, params)
}

standard_log_fatal : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    standard_log(.FATAL, "fatal", format_string, params)
}

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

// The exit code of a program a failed assertion ended, from printing_assertion_handler.
ASSERTION_EXIT_CODE : u32 : 134

/*
 * The assertion handler hosted programs start with: it writes the failure to standard error, where
 * it was and the stack that led there, then ends the process with ASSERTION_EXIT_CODE.
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
 * them into files and lines, inlined calls included.
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

package io

import runtime from "base"
import text_buffer from "std"

/*
 * Text to standard output, or standard error for the e versions, as runtime.write_output writes it:
 * nowhere where there's none, like in a kernel.
 *
 *     io.println("hello")
 *     io.printf("% of % done\n", done, total)
 *
 * printf formats like text_buffer.append_format, into PRINTF_BUFFER_SIZE bytes on the stack, so it
 * needs no allocator; longer text is cut short. Each call is written whole, so lines from several
 * threads don't mix.
 */
PRINTF_BUFFER_SIZE :: 2048

print :: fn(text: string) {
    runtime.write_output(text)
}

println :: fn(text: string) {
    write_line(.OUTPUT, text)
}

printf :: fn(format_string: string, args: any...) {
    write_formatted(.OUTPUT, format_string, args)
}

eprint :: fn(text: string) {
    runtime.write_error(text)
}

eprintln :: fn(text: string) {
    write_line(.ERROR, text)
}

eprintf :: fn(format_string: string, args: any...) {
    write_formatted(.ERROR, format_string, args)
}

write_line :: fn(stream: runtime.OutputStream, text: string) {
    buffer := runtime.output_buffer(stream)
    runtime.output_text(&buffer, text)
    runtime.output_byte(&buffer, cast[u8]('\n'))
    runtime.output_flush(&buffer)
}

write_formatted :: fn(stream: runtime.OutputStream, format_string: string, args: any[]) {
    storage : u8[PRINTF_BUFFER_SIZE]
    text := text_buffer.make(storage)
    text_buffer.append_format(&text, format_string, args)
    formatted :: text_buffer.as_string(&text)
    if stream == .OUTPUT {
        runtime.write_output(formatted)
    }
    else {
        runtime.write_error(formatted)
    }
}

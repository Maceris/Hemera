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

/** The most bytes printf and eprintf write in one call, formatted on the stack; what's past it is cut off. */
PRINTF_BUFFER_SIZE :: 2048

/**
 * Write text to standard output, as it is, in one write.
 *
 * @param text The text, of any length, with nothing added: no newline, and no translation.
 */
print :: fn(text: string) {
    runtime.write_output(text)
}

/**
 * Write text to standard output, then a newline.
 *
 * @param text The text, without the newline. A line of up to runtime.OUTPUT_BUFFER_SIZE bytes, newline included, is
 *     one write; a longer one is written in pieces, which another thread's output can come between.
 */
println :: fn(text: string) {
    write_line(.OUTPUT, text)
}

/**
 * Format text and write it to standard output, in one write.
 *
 * @param format_string The text, with a % for each of args, as text_buffer.append_format takes it. No newline is
 *     added.
 * @param args The values for the text. What's formatted past PRINTF_BUFFER_SIZE bytes is cut off.
 */
printf :: fn(format_string: string, args: any...) {
    write_formatted(.OUTPUT, format_string, args)
}

/**
 * Write text to standard error, as it is, in one write.
 *
 * @param text The text, of any length, with nothing added: no newline, and no translation.
 */
eprint :: fn(text: string) {
    runtime.write_error(text)
}

/**
 * Write text to standard error, then a newline.
 *
 * @param text The text, without the newline. A line of up to runtime.OUTPUT_BUFFER_SIZE bytes, newline included, is
 *     one write; a longer one is written in pieces.
 */
eprintln :: fn(text: string) {
    write_line(.ERROR, text)
}

/**
 * Format text and write it to standard error, in one write.
 *
 * @param format_string The text, with a % for each of args, as text_buffer.append_format takes it. No newline is
 *     added.
 * @param args The values for the text. What's formatted past PRINTF_BUFFER_SIZE bytes is cut off.
 */
eprintf :: fn(format_string: string, args: any...) {
    write_formatted(.ERROR, format_string, args)
}

/**
 * Write text and a newline to a stream, through a runtime.OutputBuffer on the stack.
 *
 * @param stream Standard output or standard error.
 * @param text The text, without the newline. Up to runtime.OUTPUT_BUFFER_SIZE bytes with the newline is one write;
 *     more is written a buffer at a time.
 */
write_line :: fn(stream: runtime.OutputStream, text: string) {
    buffer := runtime.output_buffer(stream)
    runtime.output_text(&buffer, text)
    runtime.output_byte(&buffer, cast[u8]('\n'))
    runtime.output_flush(&buffer)
}

/**
 * Format text into PRINTF_BUFFER_SIZE bytes on the stack, and write it to a stream in one write.
 *
 * @param stream Standard output or standard error.
 * @param format_string The text, with a % for each of args.
 * @param args The values for the text.
 */
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

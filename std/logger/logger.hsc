package logger

import runtime from "base"
import text_buffer from "std"
import time from "std"

/**
 * What a logger from create puts in front of each message, on a line of its own:
 *
 *     [warn] 14:03:27.412 loader.hsc:88 load_file [thread 2] missing 3 files
 *
 * create makes one, from the allocator, and it's installed with push_context, since a context can't
 * point into the stack:
 *
 *     detailed :: logger.create(logger.Options.{time = true, location = true, function = true, thread = true})
 *     defer logger.destroy(detailed)
 *     push_context verbose (logger = detailed, log_level = .DEBUG) {
 *         runtime.log_debug("% pages free", free)
 *     }
 *
 * Like runtime.STANDARD_LOGGER, messages below context.log_level are dropped, nothing is allocated, and each line is
 * one write, so lines from several threads don't mix. Lines longer than LINE_SIZE bytes are cut short.
 */
Options :: struct {
    /**
     * Whether to write the time of day in UTC, to the millisecond, from context.clock; left out when the clock gives
     * an error.
     */
    time : bool,
    /** Whether to write the file's name (without its folders) and line the message was logged from. */
    location : bool,
    /** Whether to write the name of the function the message was logged from, when it's known. */
    function : bool,
    /** Whether to write the thread's index (runtime.current_thread_index). */
    thread : bool,
    /**
     * Where lines go. Its zero value, which a literal leaving it out gets, is OUTPUT, standard output; DEFAULT_OPTIONS
     * has ERROR, standard error.
     */
    stream : runtime.OutputStream,
}

/**
 * The options used when the context's logger has no options of its own: the time and location, to standard error.
 */
DEFAULT_OPTIONS :: Options.{time = true, location = true, function = false, thread = false, stream = .ERROR}

/**
 * The most bytes one line has, its newline included, formatted on the stack. Past it, the message is cut short, but
 * still ends with its newline.
 */
LINE_SIZE :: 1024

/** A logger and its options, in one block, so the logger's data points at its own copy of the options. */
LoggerBlock :: struct {
    /** The logger, first, so a pointer to it is a pointer to the block. */
    logger : runtime.Logger,
    /** The options, which the logger's data points at. */
    options : Options,
}

/**
 * Make a logger that writes what options ask for in front of each message.
 *
 * @param options What to put in front of each message, and where lines go; copied, so the caller's can change after.
 * @param allocator Where the logger comes from.
 * @return The logger, to install with push_context; the caller's, given back with destroy and the same allocator, once
 *     no context uses it. Never null: if it can't be allocated, context.assertion_handler is called, as runtime.new
 *     does.
 */
create :: fn(options: Options, allocator := context.allocator) -> ptr[mut runtime.Logger] {
    block :: runtime.new(LoggerBlock, allocator)
    block.options = options
    block.logger = runtime.Logger.{
        data = cast[rawptr](&block.options),
        trace = log_trace,
        debug = log_debug,
        info = log_info,
        warn = log_warn,
        error = log_error,
        fatal = log_fatal,
        name = "logger",
    }
    return &block.logger
}

/**
 * Give back a logger from create, to the allocator it came from.
 *
 * @param logger The logger, from create, which no context may still use: it's invalid afterwards.
 * @param allocator The allocator create was given.
 */
destroy :: fn(logger: ptr[runtime.Logger], allocator := context.allocator) {
    runtime.free(cast[ptr[LoggerBlock]](cast[rawptr](logger)), allocator)
}

/**
 * Log a message at the TRACE level: the logger's trace function.
 *
 * @param format_string The message, with a % for each of params, as text_buffer.append_format takes it.
 * @param params The values for the message.
 * @param location Where the message was logged from, for the location and function options.
 */
log_trace : runtime.LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    log_line(.TRACE, "trace", format_string, params, location)
}

/**
 * Log a message at the DEBUG level: the logger's debug function.
 *
 * @param format_string The message, with a % for each of params, as text_buffer.append_format takes it.
 * @param params The values for the message.
 * @param location Where the message was logged from, for the location and function options.
 */
log_debug : runtime.LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    log_line(.DEBUG, "debug", format_string, params, location)
}

/**
 * Log a message at the INFO level: the logger's info function.
 *
 * @param format_string The message, with a % for each of params, as text_buffer.append_format takes it.
 * @param params The values for the message.
 * @param location Where the message was logged from, for the location and function options.
 */
log_info : runtime.LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    log_line(.INFO, "info", format_string, params, location)
}

/**
 * Log a message at the WARN level: the logger's warn function.
 *
 * @param format_string The message, with a % for each of params, as text_buffer.append_format takes it.
 * @param params The values for the message.
 * @param location Where the message was logged from, for the location and function options.
 */
log_warn : runtime.LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    log_line(.WARN, "warn", format_string, params, location)
}

/**
 * Log a message at the ERROR level: the logger's error function.
 *
 * @param format_string The message, with a % for each of params, as text_buffer.append_format takes it.
 * @param params The values for the message.
 * @param location Where the message was logged from, for the location and function options.
 */
log_error : runtime.LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    log_line(.ERROR, "error", format_string, params, location)
}

/**
 * Log a message at the FATAL level: the logger's fatal function.
 *
 * @param format_string The message, with a % for each of params, as text_buffer.append_format takes it.
 * @param params The values for the message.
 * @param location Where the message was logged from, for the location and function options.
 */
log_fatal : runtime.LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    log_line(.FATAL, "fatal", format_string, params, location)
}

/**
 * Take the part of a path after its last folder separator, / or \.
 *
 * @param path The path.
 * @return A view of path's bytes, good while they are: the whole path when it has no separator; "" when it ends with
 *     one.
 */
file_name :: fn(path: string) -> string {
    start : usize = 0
    for character, index in path {
        if character == '/' || character == '\\' {
            start = index + 1
        }
    }
    if start >= path.count {
        return ""
    }
    return string_of(cast[ptr[u8]](cast[rawptr](path.data) + start), path.count - start)
}

/**
 * Write one message as a line, with what the context's logger's options ask for in front of it.
 *
 * @param level The message's level; below context.log_level, nothing is written.
 * @param label The level's name, written in brackets first.
 * @param format_string The message, with a % for each of params.
 * @param params The values for the message.
 * @param location Where the message was logged from.
 */
log_line :: fn(level: runtime.LogLevel, label: string, format_string: string, params: any[], location: runtime.SourceCodeLocation) {
    if cast[int](level) < cast[int](context.log_level) {
        return void
    }
    options := DEFAULT_OPTIONS
    if context.logger.data != null {
        options = cast[ptr[Options]](context.logger.data)^
    }
    storage : u8[LINE_SIZE]
    text := text_buffer.make(storage)
    text_buffer.append_byte(&text, cast[u8]('['))
    text_buffer.append(&text, label)
    text_buffer.append(&text, "] ")
    if options.time {
        match time.now() {
            case Ok(instant) => {
                moment :: time.utc(instant)
                text_buffer.append_unsigned(&text, cast[u64](moment.hour), 10, 2)
                text_buffer.append_byte(&text, cast[u8](':'))
                text_buffer.append_unsigned(&text, cast[u64](moment.minute), 10, 2)
                text_buffer.append_byte(&text, cast[u8](':'))
                text_buffer.append_unsigned(&text, cast[u64](moment.second), 10, 2)
                text_buffer.append_byte(&text, cast[u8]('.'))
                text_buffer.append_unsigned(&text, cast[u64](moment.nanosecond / 1000000), 10, 3)
                text_buffer.append_byte(&text, cast[u8](' '))
            }
            case Error(_) => {}
        }
    }
    if options.location {
        text_buffer.append(&text, file_name(location.file_path))
        text_buffer.append_byte(&text, cast[u8](':'))
        text_buffer.append_unsigned(&text, cast[u64](location.line))
        text_buffer.append_byte(&text, cast[u8](' '))
    }
    if options.function && location.function.count > 0 {
        text_buffer.append(&text, location.function)
        text_buffer.append_byte(&text, cast[u8](' '))
    }
    if options.thread {
        text_buffer.append(&text, "[thread ")
        text_buffer.append_unsigned(&text, cast[u64](runtime.current_thread_index()))
        text_buffer.append(&text, "] ")
    }
    text_buffer.append_format(&text, format_string, params)
    // The newline even when the line was cut short
    if text.count >= text.bytes.count && text.count > 0 {
        text.count -= 1
    }
    text_buffer.append_byte(&text, cast[u8]('\n'))
    line :: text_buffer.as_string(&text)
    if options.stream == .OUTPUT {
        runtime.write_output(line)
    }
    else {
        runtime.write_error(line)
    }
}

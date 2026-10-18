package logger

import runtime from "base"
import text_buffer from "std"
import time from "std"

/*
 * A logger that puts what its options ask for in front of each message, on a line of its own:
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
 * Like runtime.STANDARD_LOGGER, messages below context.log_level are dropped, nothing is
 * allocated, and each line is one write. Lines longer than LINE_SIZE bytes are cut short.
 */
Options :: struct {
    // The time of day in UTC, from context.clock, when it has one
    time : bool,
    // The file's name (without its folders) and line
    location : bool,
    // The function's name
    function : bool,
    // The thread's index (runtime.current_thread_index)
    thread : bool,
    // Where lines go: standard error, unless this says otherwise
    stream : runtime.OutputStream,
}

DEFAULT_OPTIONS :: Options.{time = true, location = true, function = false, thread = false, stream = .ERROR}

LINE_SIZE :: 1024

// A logger and its options, in one block, so the logger's data points at its own copy of the options.
LoggerBlock :: struct {
    // First, so a pointer to it is a pointer to the block
    logger : runtime.Logger,
    options : Options,
}

// A logger with options, from allocator, which destroy gives back.
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

// Gives back a logger from create, to the allocator it came from.
destroy :: fn(logger: ptr[runtime.Logger], allocator := context.allocator) {
    runtime.free(cast[ptr[LoggerBlock]](cast[rawptr](logger)), allocator)
}

log_trace : runtime.LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    log_line(.TRACE, "trace", format_string, params, location)
}

log_debug : runtime.LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    log_line(.DEBUG, "debug", format_string, params, location)
}

log_info : runtime.LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    log_line(.INFO, "info", format_string, params, location)
}

log_warn : runtime.LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    log_line(.WARN, "warn", format_string, params, location)
}

log_error : runtime.LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    log_line(.ERROR, "error", format_string, params, location)
}

log_fatal : runtime.LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    log_line(.FATAL, "fatal", format_string, params, location)
}

// The part of path after its last folder separator, / or \.
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

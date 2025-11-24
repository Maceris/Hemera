package logger

import string from "std"
import time from "std"
import formatting from "std"

create_default_logger :: fn() -> ptr[Logger] {
    result : ptr[Logger] = new(Logger)
    result.name = DEFAULT_LOGGER_NAME

    data : ptr[DefaultLoggerData] = new(DefaultLoggerData)
    data.flags = DEFAULT_LOGGER_FLAG_DEFAULT
    result.data = cast[rawptr](data)

    result.trace = default_log_trace
    result.debug = default_log_debug
    result.info = default_log_info
    result.warn = default_log_warn
    result.error = default_log_error
    result.fatal = default_log_fatal
}

default_log_trace : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    if context.log_level > .TRACE {
        return void
    }
    log_string :: format(format_string, params)
    default_log_print(log_string, .FATAL, location)
}

default_log_debug : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    if context.log_level > .DEBUG {
        return void
    }
    log_string :: format(format_string, params)
    default_log_print(log_string, .FATAL, location)
}

default_log_info : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    if context.log_level > .INFO {
        return void
    }
    log_string :: format(format_string, params)
    default_log_print(log_string, .FATAL, location)
}

default_log_warn : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    if context.log_level > .WARN {
        return void
    }
    log_string :: format(format_string, params)
    default_log_print(log_string, .FATAL, location)
}

default_log_error : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    if context.log_level > .ERROR {
        return void
    }
    log_string :: format(format_string, params)
    default_log_print(log_string, .FATAL, location)
}

default_log_fatal : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    if context.log_level > .FATAL {
        return void
    }
    log_string :: format(format_string, params)
    default_log_print(log_string, .FATAL, location)
}

default_log_formatter :: fn(level : LogLevel, log_string: string, location : SourceCodeLocation) {
    format_string : string : "{}"
}

default_log_print :: fn(log_string: string, level : LogLevel, location : SourceCodeLocation) {
    if context.logger.name != DEFAULT_LOGGER_NAME {
        return void
    }
    data :: cast[ptr[DefaultLoggerData]](context.logger.data)
    flags : DefaultLoggerFlag : data.flags

    log_builder := new(StringBuilder)
    defer delete(log_builder)
    init_string_builder(log_builder)

    current_time := 0

    if flags & (DEFAULT_LOGGER_FLAG_DATE | DEFAULT_LOGGER_FLAG_TIME) != 0 {
        current_time = now()
    }

    if flags & DEFAULT_LOGGER_FLAG_DATE != 0 {
        year, month, day : int : date(current_time)
        append(log_builder, int_to_string(year))
        append(log_builder, '-')
        append(log_builder, int_to_string(month))
        append(log_builder, '-')
        append(log_builder, int_to_string(day))
        append(log_builder, ' ')
    }

    if flags & DEFAULT_LOGGER_FLAG_TIME != 0 {
        hour, minute, second, nanosecond : int : precise_clock(current_time)
        append(log_builder, int_to_string(hour))
        append(log_builder, ':')
        append(log_builder, int_to_string(minute))
        append(log_builder, ':')
        append(log_builder, int_to_string(second))
        append(log_builder, '.')
        append(log_builder, int_to_string(nanosecond))
        append(log_builder, ' ')
    }

    if flags & DEFAULT_LOGGER_FLAG_FILE_NAME != 0 {
        append(log_builder, location.file_path)
        if flags & DEFAULT_LOGGER_FLAG_LINE != 0 {
            append(log_builder, ':')
        }
        else {
            append(log_builder, ' ')
        }
    }

    if flags & DEFAULT_LOGGER_FLAG_LINE != 0 {
        append(log_builder, u32_to_string(location.line))
        append(log_builder, ' ')
    }

    if flags & DEFAULT_LOGGER_FLAG_FUNCTION != 0 {
        append(log_builder, location.function)
        append(log_builder, ' ')
    }

    if flags & DEFAULT_LOGGER_FLAG_THREAD_ID != 0 {
        append(log_builder, '[')
        append(log_builder, usize_to_string(context.thread_index))
        append(log_builder, ']')
        append(log_builder, ' ')
    }

    append(log_builder, log_string)

    log_value := builder_to_string(log_builder)

    //TODO(ches) actually print/write out the log

}

package runtime

Logger :: struct {
    debug: LogFunction,
    info: LogFunction,
    warn: LogFunction,
    error: LogFunction,
    fatal: LogFunction,
}

LogLevel :: enum {
    TRACE,
    DEBUG,
    INFO,
    WARN,
    ERROR,
    FATAL,
}

LogFunction :: alias fn(format_string: string, params: any..., location := #caller_location)

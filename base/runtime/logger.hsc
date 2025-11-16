package runtime

Logger :: struct {
    data: rawptr,
    trace: LogFunction,
    debug: LogFunction,
    info: LogFunction,
    warn: LogFunction,
    error: LogFunction,
    fatal: LogFunction,
    name: string,
}

LogLevel :: enum {
    TRACE = 0,
    DEBUG = 10,
    INFO = 20,
    WARN = 30,
    ERROR = 40,
    FATAL = 50,
}

LogFunction :: alias fn(format_string: string, params: any..., location := #caller_location)

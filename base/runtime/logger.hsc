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

log_trace :: fn(format_string: string, params: any..., location := #caller_location) {
    context.logger.trace(format_string, params, location)
}

log_debug :: fn(format_string: string, params: any..., location := #caller_location) {
    context.logger.debug(format_string, params, location)
}

log_info :: fn(format_string: string, params: any..., location := #caller_location) {
    context.logger.info(format_string, params, location)
}

log_warn :: fn(format_string: string, params: any..., location := #caller_location) {
    context.logger.warn(format_string, params, location)
}

log_error :: fn(format_string: string, params: any..., location := #caller_location) {
    context.logger.error(format_string, params, location)
}

log_fatal :: fn(format_string: string, params: any..., location := #caller_location) {
    context.logger.fatal(format_string, params, location)
}

// A log function that does nothing, for DISCARDING_LOGGER.
discard_log : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
}

// A logger that drops every message, for MINIMAL_CONTEXT.
DISCARDING_LOGGER :: Logger.{
    data = null,
    trace = discard_log,
    debug = discard_log,
    info = discard_log,
    warn = discard_log,
    error = discard_log,
    fatal = discard_log,
    name = "discarding",
}

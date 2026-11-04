package runtime

/**
 * Where log messages go: a function for each level, and the state they share. The context's logger is the one the
 * log_ functions use.
 *
 * Which messages are kept is each logger's own choice; the runtime's compare a message's level with
 * context.log_level and drop those below it, and none of them ends the program on FATAL.
 */
Logger :: struct {
    /** The logger's state, for its functions; null for one that keeps none. */
    data: rawptr,
    /** Logs a message at the TRACE level. */
    trace: LogFunction,
    /** Logs a message at the DEBUG level. */
    debug: LogFunction,
    /** Logs a message at the INFO level. */
    info: LogFunction,
    /** Logs a message at the WARN level. */
    warn: LogFunction,
    /** Logs a message at the ERROR level. */
    error: LogFunction,
    /** Logs a message at the FATAL level. */
    fatal: LogFunction,
    /** The logger's name, for telling loggers apart, like "discarding". */
    name: string,
}

/**
 * How serious a log message is, from TRACE, the least, to FATAL, the most. The values leave room between them,
 * and a logger compares them as numbers, so a level keeps what's at it and above.
 */
LogLevel :: enum {
    /** The finest detail, of what code does step by step. */
    TRACE = 0,
    /** Detail for finding a problem. */
    DEBUG = 10,
    /** What a program is doing, as it goes. */
    INFO = 20,
    /** Something unexpected that the program carries on past. */
    WARN = 30,
    /** Something that failed. */
    ERROR = 40,
    /** Something the program can't carry on past; the runtime's loggers don't end the program for it. */
    FATAL = 50,
}

/**
 * Log one message at the level the function is for.
 *
 * @param format_string The message, with a placeholder for each of params (docs/format_strings.md).
 * @param params The values for the placeholders, in order.
 * @param location Where it was logged, which a logger may report with it; the caller's own by default.
 */
LogFunction :: alias fn(format_string: string, params: any..., location := #caller_location)

/**
 * Log a message at the TRACE level, through the context's logger.
 *
 * @param format_string The message, with a placeholder for each of params (docs/format_strings.md).
 * @param params The values for the placeholders, in order.
 * @param location Where it was logged, which the logger may report with it; the caller's own by default.
 */
log_trace :: fn(format_string: string, params: any..., location := #caller_location) {
    context.logger.trace(format_string, params, location)
}

/**
 * Log a message at the DEBUG level, through the context's logger.
 *
 * @param format_string The message, with a placeholder for each of params (docs/format_strings.md).
 * @param params The values for the placeholders, in order.
 * @param location Where it was logged, which the logger may report with it; the caller's own by default.
 */
log_debug :: fn(format_string: string, params: any..., location := #caller_location) {
    context.logger.debug(format_string, params, location)
}

/**
 * Log a message at the INFO level, through the context's logger.
 *
 * @param format_string The message, with a placeholder for each of params (docs/format_strings.md).
 * @param params The values for the placeholders, in order.
 * @param location Where it was logged, which the logger may report with it; the caller's own by default.
 */
log_info :: fn(format_string: string, params: any..., location := #caller_location) {
    context.logger.info(format_string, params, location)
}

/**
 * Log a message at the WARN level, through the context's logger.
 *
 * @param format_string The message, with a placeholder for each of params (docs/format_strings.md).
 * @param params The values for the placeholders, in order.
 * @param location Where it was logged, which the logger may report with it; the caller's own by default.
 */
log_warn :: fn(format_string: string, params: any..., location := #caller_location) {
    context.logger.warn(format_string, params, location)
}

/**
 * Log a message at the ERROR level, through the context's logger.
 *
 * @param format_string The message, with a placeholder for each of params (docs/format_strings.md).
 * @param params The values for the placeholders, in order.
 * @param location Where it was logged, which the logger may report with it; the caller's own by default.
 */
log_error :: fn(format_string: string, params: any..., location := #caller_location) {
    context.logger.error(format_string, params, location)
}

/**
 * Log a message at the FATAL level, through the context's logger.
 *
 * The runtime's loggers don't end the program for it: code that can't go on has to stop itself.
 *
 * @param format_string The message, with a placeholder for each of params (docs/format_strings.md).
 * @param params The values for the placeholders, in order.
 * @param location Where it was logged, which the logger may report with it; the caller's own by default.
 */
log_fatal :: fn(format_string: string, params: any..., location := #caller_location) {
    context.logger.fatal(format_string, params, location)
}

/**
 * Log nothing: the function behind every level of DISCARDING_LOGGER.
 *
 * @param format_string Unused.
 * @param params Unused, so nothing is formatted.
 * @param location Unused.
 */
discard_log : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
}

/** A logger that drops every message, for MINIMAL_CONTEXT. */
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

package runtime

/**
 * A source of time, as context.clock holds it: a monotonic clock for measuring and a wall clock for the date.
 *
 * Both functions are called with data, and may be called by several threads at once, so a clock whose data changes
 * has to be thread-safe.
 */
Clock :: struct {
    /** The clock's own state, passed to monotonic and wall; null for a clock that needs none. */
    data : mut rawptr,
    /**
     * Nanoseconds since an unspecified start, never going back, for measuring time between two readings. It can't
     * report an error, so a clock that can't read it gives 0.
     */
    monotonic : fn(data: mut rawptr) -> MonotonicTime,
    /**
     * The current date and time in UTC, which can jump when the system's time is set; Unavailable when the clock
     * can't be read, and NotSynchronized when it's readable but not yet set to a real time.
     */
    wall : fn(data: mut rawptr) -> Result[Instant, ClockError],
}

/**
 * A span of time, to the nanosecond, which can be negative.
 *
 * seconds is rounded down, so nanos is never negative: a duration of -0.25 seconds is -1 seconds and 750,000,000
 * nanoseconds.
 */
Duration :: struct {
    /** The whole number of seconds in the duration, rounded down, so negative for a negative duration. */
    seconds: i64,
    /** Fractional part of seconds as nanoseconds, ranging between 0 and 999,999,999. */
    nanos: u32,
}

/** Why a clock's wall time couldn't be read. */
ClockError :: enum {
    /** The clock can't be read at all: there's no time source, or the system refused. */
    Unavailable,
    /** The clock can be read, but its time hasn't been set to a real date yet, or reads as earlier than the epoch. */
    NotSynchronized,
}

/** A point in time in UTC, to the nanosecond, as seconds and nanoseconds since the Unix epoch. */
Instant :: struct {
    /** Seconds since the epoch, 1970-01-01T00:00:00Z; negative before it. */
    seconds : i64,
    /** Fractional part of seconds as nanoseconds, ranging between 0 and 999,999,999. */
    nanos : u32,
}

/**
 * A monotonic clock's reading, in nanoseconds since a start the clock chooses.
 *
 * Only the difference between two readings from the same clock means anything; distinct, so a reading isn't mistaken
 * for a count of nanoseconds. An i64 holds about 292 years of them.
 */
MonotonicTime :: distinct alias i64

/** The number of nanoseconds in a second, for converting between seconds and nanoseconds. */
NANOSECONDS_PER_SECOND :: 1_000_000_000

/**
 * Compute the time from one monotonic reading to another.
 *
 * Like every Duration, seconds is rounded down, so nanos is never negative.
 *
 * @param start The earlier reading, in nanoseconds, from the same clock as end.
 * @param end The later reading, in nanoseconds; when it's earlier than start, the duration is negative.
 * @return The time from start to end, negative if end is earlier. The difference overflows, as i64 subtraction does,
 *     only for readings about 292 years apart.
 */
duration_between :: fn(start, end: MonotonicTime) -> Duration {
    difference := cast[i64](end) - cast[i64](start)
    seconds := difference / NANOSECONDS_PER_SECOND
    nanos := difference % NANOSECONDS_PER_SECOND
    if nanos < 0 {
        seconds -= 1
        nanos += NANOSECONDS_PER_SECOND
    }
    return Duration.{seconds, cast[u32](nanos)}
}

/**
 * A clock with no time source, for MINIMAL_CONTEXT: the wall clock is always unavailable, and
 * monotonic time stays at 0, since it can't report an error.
 */
NO_CLOCK :: Clock.{
    data = null,
    monotonic = no_clock_monotonic,
    wall = no_clock_wall,
}

/**
 * Read NO_CLOCK's monotonic time, which never advances.
 *
 * @param data Ignored; NO_CLOCK has no state.
 * @return Always 0, since a monotonic clock can't report that it has no source.
 */
no_clock_monotonic :: fn(data: mut rawptr) -> MonotonicTime {
    return 0
}

/**
 * Read NO_CLOCK's wall time, which there never is.
 *
 * @param data Ignored; NO_CLOCK has no state.
 * @return Never a time.
 * @error Unavailable Always, since there's no time source.
 */
no_clock_wall :: fn(data: mut rawptr) -> Result[Instant, ClockError] {
    return .Error(.Unavailable)
}

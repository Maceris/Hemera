package runtime

Clock :: struct {
    data : rawptr,
    monotonic : fn(data: mut rawptr) -> MonotonicTime,
    wall : fn(data: mut rawptr) -> Result[Instant, ClockError],
}

Duration :: struct {
    // The whole number of seconds in the duration.
    seconds: i64,
    // Fractional part of seconds as nanoseconds, ranging between 0 and 999,999,999.
    nanos: u32,
}

ClockError :: enum {
    Unavailable,
    NotSynchronized,
}

Instant :: struct {
    // Seconds since the epoch, 1970-01-01T00:00:00Z.
    seconds : i64,
    // Fractional part of seconds as nanoseconds, ranging between 0 and 999,999,999.
    nanos : u32,
}

// Time in nanoseconds
MonotonicTime :: distinct alias i64

NANOSECONDS_PER_SECOND :: 1_000_000_000

/*
 * The time from start to end, negative if end is earlier.
 * Like every Duration, seconds is rounded down, so nanos is never negative.
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

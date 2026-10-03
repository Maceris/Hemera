package runtime

Clock :: struct {
    data : rawptr,
    monotonic : fn(data: mut rawptr) -> MonotonicTime,
    wall : fn(data: mut rawptr) -> Result[Instant, ClockError],
}

Duration :: struct {
    // The whole number of seconds in the duration.
    seconds: u64,
    // Fractional part of seconds as nanoseconds, ranging between 0 and 999,999,999.
    nanos: u32,
}

ClockError :: enum {
    Unavailable,
    NotSynchronized,
}

Instant :: struct {
    // Seconds since the epoch, 1970-01-01T00:00:00Z.
    seconds : u64,
    // Fractional part of seconds as nanoseconds, ranging between 0 and 999,999,999.
    nanos : u32,
}

// Time in nanoseconds
MonotonicTime :: distinct alias i64

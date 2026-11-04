package time

import runtime from "base"

/** A point in time in UTC, as seconds and nanoseconds since 1970-01-01T00:00:00Z: base's runtime.Instant. */
Instant :: runtime.Instant
/** A span of time to the nanosecond, which can be negative: base's runtime.Duration. */
Duration :: runtime.Duration

/**
 * Read the current wall-clock time from context.clock.
 *
 * In a hosted program that's the system's clock; a freestanding program's context has whatever clock it was given.
 * Wall time can jump, forward or back, when the system's time is set, so measure how long something takes with
 * monotonic instead.
 *
 * @return The current time in UTC, to whatever precision the clock has.
 * @error Unavailable The context's clock can't be read at all, as with NO_CLOCK in MINIMAL_CONTEXT.
 * @error NotSynchronized The clock can be read, but hasn't been set to a real time yet, or reads as earlier than the
 *     epoch.
 */
now :: fn() -> Result[Instant, runtime.ClockError] {
    return context.clock.wall(context.clock.data)
}

/**
 * Read a time that only goes forward, for measuring how long things take.
 *
 * The time is in nanoseconds from some point the clock chose, like when the system started, so only the difference
 * between two readings means anything; unlike now, it doesn't jump when the system's time is set.
 *
 *     start :: time.monotonic()
 *     load_everything()
 *     took :: time.since(start)     // took.seconds, took.nanos
 *
 * @return Nanoseconds since the clock's own starting point, never less than an earlier reading's. A clock that can't
 *     be read, like NO_CLOCK, gives 0.
 */
monotonic :: fn() -> runtime.MonotonicTime {
    return context.clock.monotonic(context.clock.data)
}

/**
 * Measure how long it's been since an earlier monotonic reading.
 *
 * @param start A reading of monotonic from earlier, on the same clock: readings of different clocks can't be compared.
 * @return The time from start to now, never negative for a start that really came earlier; its seconds are rounded
 *     down, so its nanos are 0 to 999,999,999.
 */
since :: fn(start: runtime.MonotonicTime) -> Duration {
    return runtime.duration_between(start, monotonic())
}

/**
 * A moment as a calendar date and time of day.
 *
 * Which time scale it's in depends on where it came from: utc gives one in UTC, and local one in a zone's local
 * time. Dates are on the proleptic Gregorian calendar (the Gregorian calendar extended back before it was adopted),
 * with years numbered astronomically, so there's a year 0 and years before it are negative.
 *
 *     moment :: time.utc(instant)
 *     // moment.year, moment.month (1 to 12), moment.day (1 to 31), moment.hour...
 */
DateTime :: struct {
    /** The year: 0 is 1 BC, and earlier years are negative. */
    year : i64,
    /** The month, 1 for January to 12 for December. */
    month : int,
    /** The day of the month, 1 to 28, 29, 30 or 31, as the month has. */
    day : int,
    /** The hour, 0 to 23. */
    hour : int,
    /** The minute, 0 to 59. */
    minute : int,
    /** The second, 0 to 59: leap seconds aren't counted, as in Unix time, so there's never a 60. */
    second : int,
    /** The fraction of the second in nanoseconds, 0 to 999,999,999. */
    nanosecond : int,
}

/** How many seconds a day has, leap seconds not counted, as in Unix time. */
SECONDS_PER_DAY : i64 : 86400

/**
 * Divide, rounding down rather than toward zero.
 *
 * The two only differ for a negative a: -1 / 86400 is -1 here, so a time before the epoch falls on the day before it.
 *
 * @param a The dividend, of any sign.
 * @param b The divisor, which has to be positive; with 0 the division traps.
 * @return The largest integer no greater than a / b.
 */
floor_divide :: fn(a: i64, b: i64) -> i64 {
    quotient :: a / b
    if a % b < 0 {
        return quotient - 1
    }
    return quotient
}

/**
 * Find the date of a day counted from the epoch.
 *
 * From Howard Hinnant's civil_from_days: the year is counted from March, so February's leap day is at its end, and
 * 400-year eras of the proleptic Gregorian calendar repeat exactly.
 *
 * @param days The day, counted from 1970-01-01 as day 0, negative before it.
 * @return year The year, numbered astronomically: 0 is 1 BC, and earlier years are negative.
 * @return month The month, 1 to 12.
 * @return day The day of the month, 1 to 31.
 */
civil_from_days :: fn(days: i64) -> (year: i64, month: int, day: int) {
    shifted :: days + 719468
    era :: floor_divide(shifted, 146097)
    // 0 to 146096
    day_of_era :: shifted - era * 146097
    // 0 to 399
    year_of_era :: (day_of_era - day_of_era / 1460 + day_of_era / 36524 - day_of_era / 146096) / 365
    // 0 to 365, from March 1st
    day_of_year :: day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100)
    // 0 to 11, from March
    month_from_march :: (5 * day_of_year + 2) / 153
    day :: day_of_year - (153 * month_from_march + 2) / 5 + 1
    month := month_from_march + 3
    if month_from_march >= 10 {
        month = month_from_march - 9
    }
    year := year_of_era + era * 400
    if month <= 2 {
        year += 1
    }
    return year, cast[int](month), cast[int](day)
}

/**
 * Count the days from the epoch to a date: civil_from_days the other way.
 *
 * @param year The year on the proleptic Gregorian calendar, numbered astronomically (0 is 1 BC).
 * @param month The month, which has to be 1 to 12: others aren't checked, and don't reliably carry into another year.
 * @param day The day of the month. One out of the month's range carries over: 0 is the last day of the month
 *     before, and 32 of January is February 1st.
 * @return The day, counted from 1970-01-01 as day 0, negative before it.
 */
days_from_civil :: fn(year: i64, month: int, day: int) -> i64 {
    march_year := year
    if month <= 2 {
        march_year -= 1
    }
    era :: floor_divide(march_year, 400)
    year_of_era :: march_year - era * 400
    month_from_march := cast[i64](month) - 3
    if month <= 2 {
        month_from_march = cast[i64](month) + 9
    }
    day_of_year :: (153 * month_from_march + 2) / 5 + cast[i64](day) - 1
    day_of_era :: year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year
    return era * 146097 + day_of_era - 719468
}

/**
 * Convert an instant to a date and time in UTC.
 *
 * @param t The instant, before or after the epoch.
 * @return Its date and time in UTC, every field in its range; the nanosecond is t's.
 */
utc :: fn(t: Instant) -> DateTime {
    days :: floor_divide(t.seconds, SECONDS_PER_DAY)
    of_day :: t.seconds - days * SECONDS_PER_DAY
    year, month, day :: civil_from_days(days)
    return DateTime.{
        year = year,
        month = month,
        day = day,
        hour = cast[int](of_day / 3600),
        minute = cast[int](of_day / 60 % 60),
        second = cast[int](of_day % 60),
        nanosecond = cast[int](t.nanos),
    }
}

/**
 * Convert a date and time in UTC to an instant: utc the other way.
 *
 * @param moment The date and time, in UTC. Fields out of their range carry over, so a second of 60 is the next
 *     minute's first and a negative hour is in the day before, and so does a day past the month's end; but the
 *     month has to be 1 to 12, which isn't checked.
 * @return The instant, its nanos 0 to 999,999,999 after the nanosecond field carries over.
 */
from_utc :: fn(moment: DateTime) -> Instant {
    days :: days_from_civil(moment.year, moment.month, moment.day)
    seconds :: days * SECONDS_PER_DAY + cast[i64](moment.hour) * 3600 + cast[i64](moment.minute) * 60 + cast[i64](moment.second)
    return add(Instant.{seconds, 0}, Duration.{0, 0}, cast[i64](moment.nanosecond))
}

/**
 * Find the date of an instant in UTC.
 *
 * @param t The instant.
 * @return year The year, numbered astronomically: 0 is 1 BC, and earlier years are negative.
 * @return month The month, 1 to 12.
 * @return day The day of the month, 1 to 31.
 */
date :: fn(t: Instant) -> (year: i64, month: int, day: int) {
    moment :: utc(t)
    return moment.year, moment.month, moment.day
}

/**
 * Find the time of day of an instant in UTC, to the second.
 *
 * @param t The instant; the fraction of its second is dropped.
 * @return hour The hour, 0 to 23.
 * @return minute The minute, 0 to 59.
 * @return second The second, 0 to 59: leap seconds aren't counted.
 */
clock :: fn(t: Instant) -> (hour: int, minute: int, second: int) {
    moment :: utc(t)
    return moment.hour, moment.minute, moment.second
}

/**
 * Find the time of day of an instant in UTC, to the nanosecond.
 *
 * @param t The instant.
 * @return hour The hour, 0 to 23.
 * @return minute The minute, 0 to 59.
 * @return second The second, 0 to 59: leap seconds aren't counted.
 * @return nanosecond The fraction of the second in nanoseconds, 0 to 999,999,999.
 */
precise_clock :: fn(t: Instant) -> (hour: int, minute: int, second: int, nanosecond: int) {
    moment :: utc(t)
    return moment.hour, moment.minute, moment.second, moment.nanosecond
}

/** A day of the week, Monday first, as ISO 8601 orders them: MONDAY is 0 and SUNDAY 6. */
Weekday :: enum {
    MONDAY, /**< Monday, 0. */
    TUESDAY, /**< Tuesday, 1. */
    WEDNESDAY, /**< Wednesday, 2. */
    THURSDAY, /**< Thursday, 3. */
    FRIDAY, /**< Friday, 4. */
    SATURDAY, /**< Saturday, 5. */
    SUNDAY, /**< Sunday, 6. */
}

/**
 * Find the day of the week of an instant, in UTC.
 *
 * @param t The instant, before or after the epoch.
 * @return The day of the week its UTC date falls on.
 */
weekday :: fn(t: Instant) -> Weekday {
    // 1970-01-01 was a Thursday
    index :: floor_divide(t.seconds, SECONDS_PER_DAY) + 3
    remainder := index % 7
    if remainder < 0 {
        remainder += 7
    }
    return cast[Weekday](remainder)
}

/**
 * Move an instant by a duration.
 *
 * @param t The instant to move from.
 * @param duration How far to move it: later for a positive duration, earlier for a negative one.
 * @param extra_nanos Nanoseconds to move it by besides, of either sign and any size; whole seconds in it carry over.
 *     0 by default.
 * @return The moved instant, its nanos 0 to 999,999,999. Overflowing its seconds isn't checked.
 */
add :: fn(t: Instant, duration: Duration, extra_nanos: i64 = 0) -> Instant {
    nanos :: cast[i64](t.nanos) + cast[i64](duration.nanos) + extra_nanos
    carry :: floor_divide(nanos, runtime.NANOSECONDS_PER_SECOND)
    return Instant.{t.seconds + duration.seconds + carry, cast[u32](nanos - carry * runtime.NANOSECONDS_PER_SECOND)}
}

/**
 * Measure the time between two instants.
 *
 * @param start The instant to measure from.
 * @param end The instant to measure to, which may be earlier than start.
 * @return The time from start to end, negative if end is earlier. Its seconds are rounded down, so its nanos are 0 to
 *     999,999,999: a quarter second back is -1 seconds and 750,000,000 nanoseconds.
 */
between :: fn(start: Instant, end: Instant) -> Duration {
    nanos :: cast[i64](end.nanos) - cast[i64](start.nanos)
    carry :: floor_divide(nanos, runtime.NANOSECONDS_PER_SECOND)
    return Duration.{end.seconds - start.seconds + carry, cast[u32](nanos - carry * runtime.NANOSECONDS_PER_SECOND)}
}

/**
 * Compare two instants.
 *
 * @param a The instant asked about.
 * @param b The instant it's compared to.
 * @return Whether a is strictly before b, to the nanosecond: false when they're equal.
 */
is_before :: fn(a: Instant, b: Instant) -> bool {
    return a.seconds < b.seconds || (a.seconds == b.seconds && a.nanos < b.nanos)
}

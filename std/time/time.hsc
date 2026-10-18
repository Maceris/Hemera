package time

import runtime from "base"

Instant :: runtime.Instant
Duration :: runtime.Duration

/*
 * The current wall-clock time, from context.clock. Hosted programs have no clock yet, so this is
 * ClockError.Unavailable there, as it is in MINIMAL_CONTEXT.
 */
now :: fn() -> Result[Instant, runtime.ClockError] {
    return context.clock.wall(context.clock.data)
}

/*
 * A moment as a calendar date and time of day, in UTC, on the proleptic Gregorian calendar
 * (the Gregorian calendar extended back before it was adopted, with a year 0).
 *
 *     moment :: time.utc(instant)
 *     // moment.year, moment.month (1 to 12), moment.day (1 to 31), moment.hour...
 */
DateTime :: struct {
    year : i64,
    // 1 to 12
    month : int,
    // 1 to 31
    day : int,
    // 0 to 23
    hour : int,
    // 0 to 59
    minute : int,
    // 0 to 59: leap seconds aren't counted, as in Unix time
    second : int,
    // 0 to 999,999,999
    nanosecond : int,
}

SECONDS_PER_DAY : i64 : 86400

// a / b rounded down, rather than toward zero, for a negative a. b is positive.
floor_divide :: fn(a: i64, b: i64) -> i64 {
    quotient :: a / b
    if a % b < 0 {
        return quotient - 1
    }
    return quotient
}

/*
 * The date of a day, counted from 1970-01-01 (day 0), negative before it. From Howard Hinnant's
 * civil_from_days: the year starts in March, so February's leap day is at its end, and 400-year
 * eras repeat exactly.
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

// The day a date is, counted from 1970-01-01 (day 0): civil_from_days the other way.
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

// The moment t is, as a date and time in UTC.
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

/*
 * The moment a date and time in UTC is: utc the other way. Fields out of their range carry over,
 * like a second of 60 being the next minute, except month and day, which must be a real date.
 */
from_utc :: fn(moment: DateTime) -> Instant {
    days :: days_from_civil(moment.year, moment.month, moment.day)
    seconds :: days * SECONDS_PER_DAY + cast[i64](moment.hour) * 3600 + cast[i64](moment.minute) * 60 + cast[i64](moment.second)
    return add(Instant.{seconds, 0}, Duration.{0, 0}, cast[i64](moment.nanosecond))
}

date :: fn(t: Instant) -> (year: i64, month: int, day: int) {
    moment :: utc(t)
    return moment.year, moment.month, moment.day
}

clock :: fn(t: Instant) -> (hour: int, minute: int, second: int) {
    moment :: utc(t)
    return moment.hour, moment.minute, moment.second
}

precise_clock :: fn(t: Instant) -> (hour: int, minute: int, second: int, nanosecond: int) {
    moment :: utc(t)
    return moment.hour, moment.minute, moment.second, moment.nanosecond
}

Weekday :: enum {
    MONDAY,
    TUESDAY,
    WEDNESDAY,
    THURSDAY,
    FRIDAY,
    SATURDAY,
    SUNDAY,
}

// The day of the week of t, in UTC.
weekday :: fn(t: Instant) -> Weekday {
    // 1970-01-01 was a Thursday
    index :: floor_divide(t.seconds, SECONDS_PER_DAY) + 3
    remainder := index % 7
    if remainder < 0 {
        remainder += 7
    }
    return cast[Weekday](remainder)
}

/*
 * t moved by duration, and extra_nanos more (which may be negative), so later for a positive
 * duration and earlier for a negative one.
 */
add :: fn(t: Instant, duration: Duration, extra_nanos: i64 = 0) -> Instant {
    nanos :: cast[i64](t.nanos) + cast[i64](duration.nanos) + extra_nanos
    carry :: floor_divide(nanos, runtime.NANOSECONDS_PER_SECOND)
    return Instant.{t.seconds + duration.seconds + carry, cast[u32](nanos - carry * runtime.NANOSECONDS_PER_SECOND)}
}

// The time from start to end, negative if end is earlier.
between :: fn(start: Instant, end: Instant) -> Duration {
    nanos :: cast[i64](end.nanos) - cast[i64](start.nanos)
    carry :: floor_divide(nanos, runtime.NANOSECONDS_PER_SECOND)
    return Duration.{end.seconds - start.seconds + carry, cast[u32](nanos - carry * runtime.NANOSECONDS_PER_SECOND)}
}

// Whether a is before b.
is_before :: fn(a: Instant, b: Instant) -> bool {
    return a.seconds < b.seconds || (a.seconds == b.seconds && a.nanos < b.nanos)
}

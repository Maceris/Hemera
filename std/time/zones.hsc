package time

import runtime from "base"

/*
 * Time zones, from TZif data (RFC 8536): the transitions a zone has had, the local time type each one starts, and the
 * POSIX TZ rule in its footer, which says how local time goes after the last transition. parse_zone reads a TZif file's
 * bytes, which whoever has the zone files gives it, and offset_of and local give the offset from UTC at an instant, and
 * the local time there.
 *
 *     zone := time.parse_zone(bytes)?
 *     defer time.free_zone(&zone)
 *     here :: time.local(&zone, time.now()?)       // here.date_time, here.abbreviation, here.offset
 *
 * Only version 2 and later data is read when a file has it (64-bit times); a version 1 file's 32-bit times are read
 * otherwise. Leap seconds are ignored, as POSIX time ignores them.
 */

/** A local time type, one of a zone's: the offset from UTC it has, and how it's named. */
ZoneType :: struct {
    /** The offset from UTC in seconds, east positive: -18000 is five hours behind, as New York's standard time is. */
    offset : i32,
    /** Whether it's daylight saving time. */
    dst : bool,
    /**
     * Where its abbreviation starts in the zone's abbreviations, a byte index; it runs to the next zero byte. Always
     * within the abbreviations, as parse_zone checks.
     */
    abbreviation : u8,
}

/** The three ways a POSIX TZ rule writes the date daylight saving time starts or ends on. */
RuleDateKind :: enum {
    /** Jn: day n of the year, 1 to 365, February 29 never counted, so day 60 is always March 1st. */
    Julian,
    /** n: day n of the year, 0 to 365, February 29 counted in leap years. */
    Zero,
    /** Mm.w.d: weekday d (0 for Sunday) of week w (1 to 5, 5 the last) of month m. */
    MonthWeek,
}

/** The date and time of day in a POSIX TZ rule that daylight saving time starts or ends at, each year. */
RuleDate :: struct {
    /** How the date is written, which says which of the fields below it uses. */
    kind : RuleDateKind,
    /**
     * The day of the year, for Julian (1 to 365) and Zero (0 to 365); unused for MonthWeek. The range isn't checked
     * when it's parsed.
     */
    day : int,
    /** The month, 1 to 12, for MonthWeek; unused otherwise. */
    month : int,
    /** The week of the month, 1 to 5 with 5 its last, for MonthWeek; unused otherwise. */
    week : int,
    /** The day of the week, 0 for Sunday to 6 for Saturday, for MonthWeek; unused otherwise. */
    weekday : int,
    /**
     * When on that day it changes, in seconds from midnight of the local time in effect before it: 7200, 2:00, unless
     * the rule says otherwise. It may be negative, or past a day, as RFC 8536 allows (to 167 hours either way).
     */
    time : i64,
}

/** The most bytes of a rule's time zone name that are kept: a longer name is cut to its first 16. */
NAME_BYTES :: 16

/**
 * A POSIX TZ rule, which says how local time goes each year: standard time's name and offset, and daylight saving
 * time's, if it has any, and when it starts and ends.
 */
Rule :: struct {
    /** Standard time's name, like EST; only its first standard_bytes bytes are used. */
    standard : u8[NAME_BYTES],
    /** How many bytes of standard are its name, 3 to NAME_BYTES. */
    standard_bytes : usize,
    /** Standard time's offset from UTC in seconds, east positive: the rule's text, west positive, negated. */
    standard_offset : i32,
    /** Whether the rule has daylight saving time; if not, the fields after this one are unused. */
    has_dst : bool,
    /** Daylight saving time's name, like EDT; only its first daylight_bytes bytes are used. */
    daylight : u8[NAME_BYTES],
    /** How many bytes of daylight are its name, 3 to NAME_BYTES. */
    daylight_bytes : usize,
    /**
     * Daylight saving time's offset from UTC in seconds, east positive; an hour ahead of standard time when the rule
     * doesn't give one.
     */
    daylight_offset : i32,
    /**
     * When daylight saving time starts, in standard time; the United States' (the second Sunday of March, at 2:00)
     * when the rule gives no dates.
     */
    start : RuleDate,
    /**
     * When daylight saving time ends, in daylight saving time; the United States' (the first Sunday of November, at
     * 2:00) when the rule gives no dates.
     */
    end : RuleDate,
}

/**
 * A time zone, read from TZif data by parse_zone: its history of offsets from UTC, and the rule for after it.
 *
 * Its arrays are allocated with the context's allocator when it's parsed, and freed with free_zone.
 */
Zone :: struct {
    /** Each transition, in seconds since the epoch, oldest first, as the TZif data lists them. */
    transitions : i64[..],
    /** For each transition, the index in types of the local time type it starts; always within types. */
    starts : u8[..],
    /** The zone's local time types, at least one; the first is the one in effect before the first transition. */
    types : ZoneType[..],
    /** The types' abbreviations, each ending with a zero byte, as the TZif data has them. */
    abbreviations : u8[..],
    /** The POSIX TZ rule from the TZif footer, for times after the last transition; only meaningful with has_rule. */
    rule : Rule,
    /** Whether the TZif data had a footer rule that parsed: only version 2 and later data can have one. */
    has_rule : bool,
}

/** Why TZif data couldn't be read as a zone. */
ZoneError :: enum {
    /** Not TZif data: shorter than a header's 44 bytes, or not starting with "TZif". */
    NotTZif,
    /** It ends before what its headers say it has, or before a version 2 file's second header. */
    Truncated,
    /**
     * A transition that starts a type the zone hasn't got, a type whose abbreviation is outside the abbreviations, or
     * no types at all.
     */
    Invalid,
    /**
     * Memory ran out. Not returned at present: running out while the tables are copied fails the context's assertion
     * instead.
     */
    NoMemory,
}

/** What local time is at an instant in a zone. */
LocalTime :: struct {
    /** The local date and time. */
    date_time : DateTime,
    /** The offset from UTC in seconds, east positive: local time is UTC plus this. */
    offset : i32,
    /** Whether it's daylight saving time. */
    dst : bool,
    /**
     * The local time's abbreviation, like CET, or empty if the zone gives none. It's a view of the zone's own memory,
     * good until the zone is freed or moved.
     */
    abbreviation : string,
}

/**
 * Read a time zone from TZif data (RFC 8536).
 *
 * When the data has version 2 or later (64-bit) times, only those are read, and the footer's POSIX TZ rule with them;
 * a version 1 file's 32-bit times are read otherwise. A footer whose rule doesn't parse is left out, not an error.
 * Leap second records are skipped, as POSIX time ignores leap seconds.
 *
 * @param bytes A TZif file's bytes, such as one of the system's zone files, read by the caller. Nothing in the zone
 *     refers to them, so they can be freed once this returns.
 * @return The zone, its tables copied with the context's allocator; the caller owns it and frees it with free_zone.
 * @error NotTZif The bytes are shorter than a TZif header, or don't start with "TZif".
 * @error Truncated The bytes end before the data their headers describe.
 * @error Invalid A transition starts a type that isn't there, a type's abbreviation starts outside the abbreviations,
 *     or there are no types. Nothing is left allocated.
 */
parse_zone :: fn(bytes: u8[]) -> Result[Zone, ZoneError] {
    if bytes.count < 44 || bytes[0] != cast[u8]('T') || bytes[1] != cast[u8]('Z') || bytes[2] != cast[u8]('i') || bytes[3] != cast[u8]('f') {
        return .Error(.NotTZif)
    }
    version :: bytes[4]
    first :: counts_at(bytes, 0) or_return .Error(.Truncated)
    // Version 2 and later repeat the data with 64-bit times after the first, then a footer
    start := cast[usize](44)
    wide := false
    counts := first
    if version >= cast[u8]('2') {
        second_header :: 44 + data_bytes(first, 4)
        counts = counts_at(bytes, second_header) or_return .Error(.Truncated)
        start = second_header + 44
        wide = true
    }
    time_bytes :: if wide { cast[usize](8) } else { cast[usize](4) }
    end :: start + data_bytes(counts, time_bytes)
    if end > bytes.count {
        return .Error(.Truncated)
    }
    zone := Zone.{}
    at := start
    for i in 0..<counts.times {
        moment :: if wide { cast[i64](big_endian(bytes, at, 8)) } else { cast[i64](cast[i32](cast[u32](big_endian(bytes, at, 4)))) }
        runtime.array_add(&zone.transitions, moment)
        at += time_bytes
    }
    for i in 0..<counts.times {
        index :: byte_at(bytes, at)
        if cast[usize](index) >= counts.types {
            free_zone(&zone)
            return .Error(.Invalid)
        }
        runtime.array_add(&zone.starts, index)
        at += 1
    }
    for i in 0..<counts.types {
        offset :: cast[i32](cast[u32](big_endian(bytes, at, 4)))
        made := ZoneType.{offset = offset, dst = byte_at(bytes, at + 4) != 0, abbreviation = byte_at(bytes, at + 5)}
        if cast[usize](made.abbreviation) >= counts.characters {
            free_zone(&zone)
            return .Error(.Invalid)
        }
        runtime.array_add(&zone.types, made)
        at += 6
    }
    for i in 0..<counts.characters {
        runtime.array_add(&zone.abbreviations, byte_at(bytes, at))
        at += 1
    }
    if counts.types == 0 {
        free_zone(&zone)
        return .Error(.Invalid)
    }
    // The footer: a line feed, the TZ rule, a line feed
    if wide && end < bytes.count && bytes[end] == 0x0a {
        footer_start :: end + 1
        footer_end := footer_start
        loop {
            if footer_end >= bytes.count || bytes[footer_end] == 0x0a {
                break
            }
            footer_end += 1
        }
        if footer_end > footer_start && footer_end <= bytes.count {
            match parse_rule(bytes[footer_start..<footer_end]) {
                case Some(rule) => {
                    zone.rule = rule
                    zone.has_rule = true
                }
                case None => {}
            }
        }
    }
    return .Ok(zone)
}

/**
 * Free a zone's tables.
 *
 * @param zone The zone, from parse_zone. Its arrays are freed and left empty, so abbreviations given out from it are
 *     no longer good; its rule, held in the zone itself, still is.
 */
free_zone :: fn(zone: ptr[mut Zone]) {
    runtime.array_free(&zone.transitions)
    runtime.array_free(&zone.starts)
    runtime.array_free(&zone.types)
    runtime.array_free(&zone.abbreviations)
}

/**
 * Find a zone's offset from UTC at an instant, and its local time type there.
 *
 * At or after the last transition, or with none, the footer's rule decides, if the zone has one. Otherwise it's the
 * type the last transition at or before the instant started, or the zone's first type before the first transition or
 * when there are none.
 *
 * @param zone The zone, from parse_zone.
 * @param t The instant; only its whole seconds matter, as transitions are to the second.
 * @return offset The offset from UTC in seconds, east positive: local time is UTC plus this.
 * @return dst Whether it's daylight saving time.
 * @return abbreviation The local time's abbreviation, or empty if the zone gives none: a view of the zone's memory,
 *     good until the zone is freed or moved.
 */
offset_of :: fn(zone: ptr[Zone], t: Instant) -> (offset : i32, dst : bool, abbreviation : string) {
    seconds :: t.seconds
    count :: zone.transitions.count
    newest := cast[i64](0)
    for moment in zone.transitions {
        newest = moment
    }
    if (count == 0 || seconds >= newest) && zone.has_rule {
        return rule_offset(&zone.rule, seconds)
    }
    type_index := cast[usize](0)
    if count > 0 && count <= zone.transitions.count && seconds >= zone.transitions[0 % count] {
        // The last transition at or before seconds, by halving
        low := cast[usize](0)
        high := count
        loop {
            if high - low <= 1 {
                break
            }
            middle :: low + (high - low) / 2
            if middle < count && zone.transitions[middle] <= seconds {
                low = middle
            }
            else {
                high = middle
            }
        }
        if low < zone.starts.count {
            type_index = cast[usize](zone.starts[low])
        }
    }
    if type_index >= zone.types.count {
        return 0, false, "UTC"
    }
    found :: zone.types[type_index]
    return found.offset, found.dst, abbreviation_at(zone, cast[usize](found.abbreviation))
}

/**
 * Find the local time at an instant in a zone.
 *
 * @param zone The zone, from parse_zone.
 * @param t The instant, before or after the epoch.
 * @return The local date and time, its offset, whether it's daylight saving time, and its abbreviation, which is a
 *     view of the zone's memory, good until the zone is freed or moved.
 */
local :: fn(zone: ptr[Zone], t: Instant) -> LocalTime {
    offset, dst, abbreviation :: offset_of(zone, t)
    shifted :: Instant.{seconds = t.seconds + cast[i64](offset), nanos = t.nanos}
    return LocalTime.{date_time = utc(shifted), offset = offset, dst = dst, abbreviation = abbreviation}
}

/**
 * Fetch an abbreviation from a zone's abbreviations.
 *
 * @param zone The zone.
 * @param start The byte index in the zone's abbreviations it starts at.
 * @return The bytes from start to the next zero byte or the abbreviations' end, a view of the zone's array, good
 *     until the zone is freed; empty when start is past the end or at a zero byte.
 */
abbreviation_at :: fn(zone: ptr[Zone], start: usize) -> string {
    end := start
    loop {
        if end >= zone.abbreviations.count || zone.abbreviations[end] == 0 {
            break
        }
        end += 1
    }
    if start >= end || end > zone.abbreviations.count {
        return ""
    }
    return string_of(&zone.abbreviations[start], end - start)
}

/**
 * Find the offset under a POSIX TZ rule at an instant: standard time's, unless it's within the year's daylight saving
 * time.
 *
 * The year is the one it is in standard time. Daylight saving time that ends earlier in the year than it starts, as in
 * the southern hemisphere, runs over the year's end.
 *
 * @param rule The rule.
 * @param seconds The instant, in seconds since the epoch.
 * @return offset The offset from UTC in seconds, east positive.
 * @return dst Whether it's daylight saving time.
 * @return abbreviation Standard or daylight saving time's name: a view of the rule's own arrays, good while the rule
 *     stays where it is.
 */
rule_offset :: fn(rule: ptr[Rule], seconds: i64) -> (offset : i32, dst : bool, abbreviation : string) {
    standard :: string_of(&rule.standard[0], rule.standard_bytes)
    if !rule.has_dst {
        return rule.standard_offset, false, standard
    }
    daylight :: string_of(&rule.daylight[0], rule.daylight_bytes)
    // The year, in standard time
    year, month, day :: civil_from_days(floor_divide(seconds + cast[i64](rule.standard_offset), 86400))
    // Daylight saving time starts at its local standard time, and ends at its local daylight time
    starts :: rule_moment(&rule.start, year) - cast[i64](rule.standard_offset)
    ends :: rule_moment(&rule.end, year) - cast[i64](rule.daylight_offset)
    in_dst :: if starts < ends { seconds >= starts && seconds < ends } else { !(seconds >= ends && seconds < starts) }
    return if in_dst { rule.daylight_offset } else { rule.standard_offset }, in_dst, if in_dst { daylight } else { standard }
}

/**
 * Find when a rule's date and time falls in a year.
 *
 * @param date The rule's date and time of day.
 * @param year The year, on the proleptic Gregorian calendar.
 * @return The moment in local seconds since the epoch: seconds since 1970-01-01T00:00 of the local time in effect
 *     before it, which the caller turns into UTC by subtracting that time's offset.
 */
rule_moment :: fn(date: ptr[RuleDate], year: i64) -> i64 {
    leap :: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    january_first :: days_from_civil(year, 1, 1)
    days := january_first
    if date.kind == .Julian {
        days += cast[i64](date.day - 1) + (if leap && date.day > 59 { cast[i64](1) } else { cast[i64](0) })
    }
    else if date.kind == .Zero {
        days += cast[i64](date.day)
    }
    else {
        first :: days_from_civil(year, date.month, 1)
        // 1970-01-01 was a Thursday
        first_weekday :: cast[int]((first % 7 + 7 + 4) % 7)
        day := 1 + (date.weekday - first_weekday + 7) % 7 + (date.week - 1) * 7
        length :: month_days(year, date.month)
        loop {
            if day <= length {
                break
            }
            day -= 7
        }
        days = days_from_civil(year, date.month, day)
    }
    return days * 86400 + date.time
}

/**
 * Count the days in a month.
 *
 * @param year The year, on the proleptic Gregorian calendar, which decides February's.
 * @param month The month, 1 to 12; any other gives 31.
 * @return The number of days, 28 to 31.
 */
month_days :: fn(year: i64, month: int) -> int {
    leap :: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    return if month == 2 { if leap { 29 } else { 28 } } else if month == 4 || month == 6 || month == 9 || month == 11 { 30 } else { 31 }
}

/**
 * Parse a POSIX TZ rule, as a TZif footer has it: std offset [dst [offset] [,start[/time],end[/time]]].
 *
 * A name is alphabetic or in <angle brackets>, and an offset is hours west of UTC ([+-]hh[:mm[:ss]]). Daylight
 * saving time without an offset is an hour ahead of standard time, and without dates follows the United States'
 * rules. Text after the end date isn't checked.
 *
 * @param text The rule, without the footer's line feeds.
 * @return The rule, its offsets east positive, or None if it's malformed: a name shorter than 3 bytes, a missing
 *     offset, or a date that doesn't parse.
 */
parse_rule :: fn(text: u8[]) -> Rule? {
    rule := Rule.{}
    at := cast[usize](0)
    rule.standard_bytes = name_at(text, &at, &rule.standard) or_return null
    rule.standard_offset = -(offset_at(text, &at) or_return null)
    if at >= text.count {
        return rule
    }
    rule.has_dst = true
    rule.daylight_bytes = name_at(text, &at, &rule.daylight) or_return null
    rule.daylight_offset = rule.standard_offset + 3600
    if at < text.count && text[at] != cast[u8](',') {
        rule.daylight_offset = -(offset_at(text, &at) or_return null)
    }
    if at >= text.count {
        rule.start = RuleDate.{kind = .MonthWeek, month = 3, week = 2, weekday = 0, time = 7200}
        rule.end = RuleDate.{kind = .MonthWeek, month = 11, week = 1, weekday = 0, time = 7200}
        return rule
    }
    if text[at] != cast[u8](',') {
        return null
    }
    at += 1
    rule.start = date_at(text, &at) or_return null
    if at >= text.count || text[at] != cast[u8](',') {
        return null
    }
    at += 1
    rule.end = date_at(text, &at) or_return null
    return rule
}

/**
 * Parse a time zone name in a POSIX TZ rule: letters, or anything but > in <angle brackets>.
 *
 * @param text The rule.
 * @param at Where in text the name starts, in bytes; moved past it, and past the closing bracket of a quoted one.
 * @param name Where the name is copied, without its brackets; bytes past NAME_BYTES are dropped.
 * @return How many bytes were copied into name, 3 to NAME_BYTES, or None if fewer than 3 were, or a quoted name has
 *     no closing bracket.
 */
name_at :: fn(text: u8[], at: ptr[mut usize], name: ptr[mut u8[NAME_BYTES]]) -> usize? {
    count : usize = 0
    if at^ < text.count && byte_at(text, at^) == cast[u8]('<') {
        at^ += 1
        loop {
            if at^ >= text.count {
                return null
            }
            byte :: byte_at(text, at^)
            at^ += 1
            if byte == cast[u8]('>') {
                break
            }
            if count < name.count {
                name^[count] = byte
                count += 1
            }
        }
    }
    else {
        loop {
            if at^ >= text.count {
                break
            }
            byte :: byte_at(text, at^)
            if !((byte >= cast[u8]('A') && byte <= cast[u8]('Z')) || (byte >= cast[u8]('a') && byte <= cast[u8]('z'))) {
                break
            }
            if count < name.count {
                name^[count] = byte
                count += 1
            }
            at^ += 1
        }
    }
    return if count >= 3 { count } else { null }
}

/**
 * Parse an offset in a POSIX TZ rule: [+-]hh[:mm[:ss]].
 *
 * @param text The rule.
 * @param at Where in text the offset starts, in bytes; moved past it.
 * @return The offset in seconds, west of UTC positive, as POSIX writes them, or None if there are no hours.
 */
offset_at :: fn(text: u8[], at: ptr[mut usize]) -> i32? {
    sign := cast[i32](1)
    if at^ < text.count && (byte_at(text, at^) == cast[u8]('+') || byte_at(text, at^) == cast[u8]('-')) {
        sign = if byte_at(text, at^) == cast[u8]('-') { -1 } else { 1 }
        at^ += 1
    }
    seconds :: time_at(text, at) or_return null
    return sign * cast[i32](seconds)
}

/**
 * Parse a time in a POSIX TZ rule: hh[:mm[:ss]], without a sign.
 *
 * @param text The rule.
 * @param at Where in text the time starts, in bytes; moved past it.
 * @return The time in seconds, or None if there are no hours, or a colon has no number after it. No part's range is
 *     checked, so hours may go past 24, up to the 167 a rule's times can have.
 */
time_at :: fn(text: u8[], at: ptr[mut usize]) -> i64? {
    total := cast[i64](0)
    for unit in i64.[3600, 60, 1] {
        if unit != 3600 {
            if at^ >= text.count || byte_at(text, at^) != cast[u8](':') {
                break
            }
            at^ += 1
        }
        value :: number_at(text, at) or_return null
        total += value * unit
    }
    return total
}

/**
 * Parse a date in a POSIX TZ rule: Jn, n or Mm.w.d, then /time if it's there.
 *
 * @param text The rule.
 * @param at Where in text the date starts, in bytes; moved past it and its time.
 * @return The date, at 2:00 when no time is given, or None if it's malformed, or a Mm.w.d date's month isn't 1 to 12,
 *     its week 1 to 5, or its weekday 0 to 6. A Jn or n date's day isn't range-checked.
 */
date_at :: fn(text: u8[], at: ptr[mut usize]) -> RuleDate? {
    date := RuleDate.{time = 7200}
    if at^ < text.count && byte_at(text, at^) == cast[u8]('J') {
        at^ += 1
        date.kind = .Julian
        date.day = cast[int](number_at(text, at) or_return null)
    }
    else if at^ < text.count && byte_at(text, at^) == cast[u8]('M') {
        at^ += 1
        date.kind = .MonthWeek
        date.month = cast[int](number_at(text, at) or_return null)
        if at^ >= text.count || byte_at(text, at^) != cast[u8]('.') {
            return null
        }
        at^ += 1
        date.week = cast[int](number_at(text, at) or_return null)
        if at^ >= text.count || byte_at(text, at^) != cast[u8]('.') {
            return null
        }
        at^ += 1
        date.weekday = cast[int](number_at(text, at) or_return null)
        if date.month < 1 || date.month > 12 || date.week < 1 || date.week > 5 || date.weekday > 6 {
            return null
        }
    }
    else {
        date.kind = .Zero
        date.day = cast[int](number_at(text, at) or_return null)
    }
    if at^ < text.count && byte_at(text, at^) == cast[u8]('/') {
        at^ += 1
        sign := cast[i64](1)
        if at^ < text.count && (byte_at(text, at^) == cast[u8]('+') || byte_at(text, at^) == cast[u8]('-')) {
            sign = if byte_at(text, at^) == cast[u8]('-') { -1 } else { 1 }
            at^ += 1
        }
        date.time = sign * (time_at(text, at) or_return null)
    }
    return date
}

/**
 * Parse an unsigned decimal number.
 *
 * @param text The text.
 * @param at Where in text the number starts, in bytes; moved past its digits, at most 9 of them.
 * @return The number, 0 to 999,999,999, or None if there's no digit at at. Digits past the ninth are left unread.
 */
number_at :: fn(text: u8[], at: ptr[mut usize]) -> i64? {
    value := cast[i64](0)
    digits := 0
    loop {
        if at^ >= text.count || byte_at(text, at^) < cast[u8]('0') || byte_at(text, at^) > cast[u8]('9') || digits >= 9 {
            break
        }
        value = value * 10 + cast[i64](byte_at(text, at^) - cast[u8]('0'))
        at^ += 1
        digits += 1
    }
    return if digits > 0 { value } else { null }
}

/** The six counts a TZif header has, which say how big each table after it is (RFC 8536, section 3.1). */
ZoneCounts :: struct {
    /** isutcnt: how many UT/local indicators there are, one byte each. */
    utc_flags : usize,
    /** isstdcnt: how many standard/wall indicators there are, one byte each. */
    standard_flags : usize,
    /** leapcnt: how many leap second records there are. */
    leaps : usize,
    /** timecnt: how many transitions there are. */
    times : usize,
    /** typecnt: how many local time types there are. */
    types : usize,
    /** charcnt: how many bytes the abbreviations take. */
    characters : usize,
}

/**
 * Read the counts of a TZif header.
 *
 * @param bytes The TZif data.
 * @param start Where in bytes the 44-byte header starts.
 * @return The header's counts, or None if the header doesn't fit in bytes or doesn't start with a T. The rest of its
 *     magic isn't checked.
 */
counts_at :: fn(bytes: u8[], start: usize) -> ZoneCounts? {
    if start + 44 > bytes.count || byte_at(bytes, start) != cast[u8]('T') {
        return null
    }
    return ZoneCounts.{utc_flags = field(bytes, start + 20), standard_flags = field(bytes, start + 24), leaps = field(bytes, start + 28),
        times = field(bytes, start + 32), types = field(bytes, start + 36), characters = field(bytes, start + 40)}
}

/**
 * Read one of a TZif header's counts: a 32-bit big-endian unsigned integer.
 *
 * @param bytes The TZif data.
 * @param at Where in bytes the count starts; bytes past the end read as 0.
 * @return The count.
 */
field :: fn(bytes: u8[], at: usize) -> usize {
    return cast[usize](big_endian(bytes, at, 4))
}

/**
 * Count the bytes of a TZif data block, which follows its header.
 *
 * @param counts The block's header's counts.
 * @param time_bytes How many bytes a time takes in the block: 4 in version 1's, 8 in version 2's and later.
 * @return How many bytes the block has, not counting its header or a footer.
 */
data_bytes :: fn(counts: ZoneCounts, time_bytes: usize) -> usize {
    return counts.times * time_bytes + counts.times + counts.types * 6 + counts.characters + counts.leaps * (time_bytes + 4)
        + counts.standard_flags + counts.utc_flags
}

/**
 * Read a big-endian unsigned integer.
 *
 * @param bytes The data.
 * @param at Where in bytes the integer starts; bytes past the end read as 0.
 * @param count How many bytes it has, 1 to 8.
 * @return The integer, zero-extended; a signed one is cast by the caller.
 */
big_endian :: fn(bytes: u8[], at: usize, count: usize) -> u64 {
    value := cast[u64](0)
    for i in 0..<count {
        value = (value << 8) | cast[u64](byte_at(bytes, at + i))
    }
    return value
}

/**
 * Read a byte without going past the end.
 *
 * @param bytes The data.
 * @param at The byte's index.
 * @return The byte, or 0 if at is past the end.
 */
byte_at :: fn(bytes: u8[], at: usize) -> u8 {
    return if at < bytes.count { bytes[at] } else { 0 }
}

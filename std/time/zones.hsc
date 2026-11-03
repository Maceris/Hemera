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

/**
 * A local time type: its offset from UTC in seconds, east positive, whether it's daylight saving time, and where its
 * abbreviation starts in the zone's abbreviations.
 */
ZoneType :: struct {
    offset : i32,
    dst : bool,
    abbreviation : u8,
}

RuleDateKind :: enum {
    /** Jn: day n of the year, 1 to 365, February 29 never counted */
    Julian,
    /** n: day n of the year, 0 to 365, February 29 counted in leap years */
    Zero,
    /** Mm.w.d: weekday d (0 for Sunday) of week w (1 to 5, 5 the last) of month m */
    MonthWeek,
}

RuleDate :: struct {
    kind : RuleDateKind,
    day : int,
    month : int,
    week : int,
    weekday : int,
    /** When on that day it changes, in seconds from midnight of the local time in effect before it */
    time : i64,
}

NAME_BYTES :: 16

/**
 * A POSIX TZ rule: standard time's name and offset, and daylight saving time's, if it has any, and when it starts and ends.
 */
Rule :: struct {
    standard : u8[NAME_BYTES],
    standard_bytes : usize,
    standard_offset : i32,
    has_dst : bool,
    daylight : u8[NAME_BYTES],
    daylight_bytes : usize,
    daylight_offset : i32,
    start : RuleDate,
    end : RuleDate,
}

Zone :: struct {
    // Each transition, in seconds since the epoch, oldest first, and the type it starts
    transitions : i64[..],
    starts : u8[..],
    types : ZoneType[..],
    abbreviations : u8[..],
    rule : Rule,
    has_rule : bool,
}

ZoneError :: enum {
    /** Not TZif data */
    NotTZif,
    /** It ends before what its header says it has */
    Truncated,
    /** A type or a transition that refers to nothing */
    Invalid,
    NoMemory,
}

/**
 * What local time is at an instant: the date and time, the offset from UTC in seconds, whether it's daylight saving
 * time, and its abbreviation, the zone's.
 */
LocalTime :: struct {
    date_time : DateTime,
    offset : i32,
    dst : bool,
    abbreviation : string,
}

/** A zone from TZif data, its tables copied out with the context's allocator. */
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

free_zone :: fn(zone: ptr[mut Zone]) {
    runtime.array_free(&zone.transitions)
    runtime.array_free(&zone.starts)
    runtime.array_free(&zone.types)
    runtime.array_free(&zone.abbreviations)
}

/**
 * The offset from UTC at an instant, whether it's daylight saving time, and its abbreviation: the type the last
 * transition at or before it started; before the first, the first type; after the last, the footer's rule if there's
 * one.
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

/** Local time at an instant in a zone. */
local :: fn(zone: ptr[Zone], t: Instant) -> LocalTime {
    offset, dst, abbreviation :: offset_of(zone, t)
    shifted :: Instant.{seconds = t.seconds + cast[i64](offset), nanos = t.nanos}
    return LocalTime.{date_time = utc(shifted), offset = offset, dst = dst, abbreviation = abbreviation}
}

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
 * The offset under a POSIX TZ rule at an instant: standard time's, unless it's within the year's daylight saving time.
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

/** When a rule's date and time falls in a year, as local seconds since the epoch. */
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

month_days :: fn(year: i64, month: int) -> int {
    leap :: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    return if month == 2 { if leap { 29 } else { 28 } } else if month == 4 || month == 6 || month == 9 || month == 11 { 30 } else { 31 }
}

/**
 * A POSIX TZ rule, as a TZif footer has it: std offset [dst [offset] [,start[/time],end[/time]]], a name alphabetic or
 * in <angle brackets>, an offset hours west of UTC ([+-]hh[:mm[:ss]]); without dates, the United States' rules.
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

/** A name: letters, or anything but > in <angle brackets>: how many bytes it has, copied into name. */
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

/** [+-]hh[:mm[:ss]], in seconds, west of UTC positive, as POSIX writes them. */
offset_at :: fn(text: u8[], at: ptr[mut usize]) -> i32? {
    sign := cast[i32](1)
    if at^ < text.count && (byte_at(text, at^) == cast[u8]('+') || byte_at(text, at^) == cast[u8]('-')) {
        sign = if byte_at(text, at^) == cast[u8]('-') { -1 } else { 1 }
        at^ += 1
    }
    seconds :: time_at(text, at) or_return null
    return sign * cast[i32](seconds)
}

/** hh[:mm[:ss]], in seconds; hours may be up to 167, as a rule's times can be. */
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

/** Jn, n or Mm.w.d, then /time if it's there (2:00 otherwise). */
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

/** The six counts a TZif header has, at the header starting at start. */
ZoneCounts :: struct {
    utc_flags : usize,
    standard_flags : usize,
    leaps : usize,
    times : usize,
    types : usize,
    characters : usize,
}

counts_at :: fn(bytes: u8[], start: usize) -> ZoneCounts? {
    if start + 44 > bytes.count || byte_at(bytes, start) != cast[u8]('T') {
        return null
    }
    return ZoneCounts.{utc_flags = field(bytes, start + 20), standard_flags = field(bytes, start + 24), leaps = field(bytes, start + 28),
        times = field(bytes, start + 32), types = field(bytes, start + 36), characters = field(bytes, start + 40)}
}

field :: fn(bytes: u8[], at: usize) -> usize {
    return cast[usize](big_endian(bytes, at, 4))
}

/** How many bytes a block of data has after its header, with time_bytes to a time. */
data_bytes :: fn(counts: ZoneCounts, time_bytes: usize) -> usize {
    return counts.times * time_bytes + counts.times + counts.types * 6 + counts.characters + counts.leaps * (time_bytes + 4)
        + counts.standard_flags + counts.utc_flags
}

big_endian :: fn(bytes: u8[], at: usize, count: usize) -> u64 {
    value := cast[u64](0)
    for i in 0..<count {
        value = (value << 8) | cast[u64](byte_at(bytes, at + i))
    }
    return value
}

byte_at :: fn(bytes: u8[], at: usize) -> u8 {
    return if at < bytes.count { bytes[at] } else { 0 }
}

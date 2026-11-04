package locale

import runtime from "base"
import text_buffer from "std"
import time from "std"

/*
 * A locale: how text meant for a person writes numbers, dates and times. It's a context value (a context extension,
 * docs/multitasking.md), set for a scope with push_context, and otherwise the one the process was given
 * (runtime.locale_name), or NEUTRAL. Only these formatters read it: the runtime's logging, text_buffer's formatting and
 * everything machine-facing never change with it, so nothing that parses output sees a locale's marks.
 *
 *     uk :: runtime.new(locale.Locale)                  // a context value can't point into the stack
 *     uk^ = locale.EN_GB
 *     node := runtime.extension_node(uk)
 *     push_context british (extensions = &node) {
 *         locale.append_date(&text, today)            // 31/12/2026
 *     }
 */

/** The order a date's year, month and day are written in. */
DateOrder :: enum {
    /** Year, month, day: 2026-12-31, as ISO 8601 has it. */
    YearMonthDay,
    /** Month, day, year: 12/31/2026, as in the United States. */
    MonthDayYear,
    /** Day, month, year: 31/12/2026, as in the United Kingdom. */
    DayMonthYear,
}

/** The day a week starts on, as a calendar shows it. */
FirstDay :: enum {
    /** Weeks start on Monday, as ISO 8601 has it. */
    Monday,
    /** Weeks start on Sunday. */
    Sunday,
}

/**
 * A locale: how text meant for a person writes numbers, dates and times.
 *
 * It's a context value; its strings are kept by value, so as a context value they have to outlive the scope it's set
 * for, which literals do.
 */
Locale :: struct {
    /** Its name, as "en-GB", a BCP 47 language tag; "" for NEUTRAL. */
    name : string,
    /** What's between a number's whole part and its fraction, like "." or ",". */
    decimal : string,
    /** What's between each group of three digits of a number's whole part, like ","; "" for no groups. */
    grouping : string,
    /** The order a date's year, month and day are written in. */
    date_order : DateOrder,
    /** What's between a date's year, month and day, like "/" or "-". */
    date_separator : string,
    /** True for a 24-hour clock; false for a 12-hour one with " am" and " pm". */
    hours_24 : bool,
    /** The day a week starts on. None of this package's formatters read it; it's for calendars. */
    first_day : FirstDay,
}

/** No locale's own ways: ISO 8601's dates, a point and no groups, and a 24-hour clock. */
NEUTRAL :: Locale.{name = "", decimal = ".", grouping = "", date_order = .YearMonthDay, date_separator = "-", hours_24 = true,
    first_day = .Monday}

/** English as written in the United States: 1,234.5, 12/31/2026, 2:05 pm, weeks from Sunday. */
EN_US :: Locale.{name = "en-US", decimal = ".", grouping = ",", date_order = .MonthDayYear, date_separator = "/", hours_24 = false,
    first_day = .Sunday}

/** English as written in the United Kingdom: 1,234.5, 31/12/2026, 14:05, weeks from Monday. */
EN_GB :: Locale.{name = "en-GB", decimal = ".", grouping = ",", date_order = .DayMonthYear, date_separator = "/", hours_24 = true,
    first_day = .Monday}

/** Every locale there is, which find looks names up in. NEUTRAL isn't among them. */
LOCALES :: Locale.[EN_US, EN_GB]

/**
 * Find a locale by its name.
 *
 * @param name The name, like "en-GB", matched exactly: case and the hyphen matter.
 * @return A copy of the locale; null if none in LOCALES has that name, "" included.
 */
find :: fn(name: string) -> Locale? {
    for each in LOCALES {
        if each.name == name {
            return each
        }
    }
    return null
}

/**
 * Find the locale in effect.
 *
 * @return A copy of the context's locale, if one is set for this scope; otherwise the one the process was given, by
 *     its name (runtime.locale_name); otherwise NEUTRAL, also when the process's name isn't one of LOCALES.
 */
current :: fn() -> Locale {
    match runtime.get_extension(Locale) {
        case Some(found) => return found^
        case None => {}
    }
    return find(runtime.locale_name()) or_else NEUTRAL
}

/**
 * Write an integer in decimal, with the locale's groups: 1,234,567.
 *
 * @param text Where it's written; what doesn't fit is dropped, and the buffer marked truncated.
 * @param value The integer: any i64, the most negative included, with a - before it when negative.
 * @param locale Whose marks to use; the locale in effect (current) unless given.
 */
append_integer :: fn(text: ptr[mut text_buffer.TextBuffer], value: i64, locale := current()) {
    append_fixed(text, value, 0, locale)
}

/**
 * Write a fixed-point number, with the locale's groups and decimal mark.
 *
 * append_fixed(&text, 123456789, 2) writes 1,234,567.89 in en-US. It's an integer scaled, not a float, so cents and
 * the like are written exactly.
 *
 * @param text Where it's written; what doesn't fit is dropped, and the buffer marked truncated.
 * @param value The number times ten to the power places: any i64, with a - before it when negative.
 * @param places How many digits come after the decimal mark, all of them written, zeros included; 0 writes no mark.
 *     At most 19, since ten to the power of more doesn't fit a u64.
 * @param locale Whose marks to use; the locale in effect (current) unless given.
 */
append_fixed :: fn(text: ptr[mut text_buffer.TextBuffer], value: i64, places: u32, locale := current()) {
    magnitude := if value < 0 { cast[u64](-(value + 1)) + 1 } else { cast[u64](value) }
    if value < 0 {
        text_buffer.append_byte(text, cast[u8]('-'))
    }
    scale := cast[u64](1)
    for i in 0..<places {
        scale = scale * 10
    }
    whole :: magnitude / scale
    fraction :: magnitude % scale
    // The whole part's digits, then groups of three from the right
    digits : u8[20]
    count : usize = 0
    remaining := whole
    loop {
        if count < digits.count {
            digits[count] = cast[u8]('0') + cast[u8](remaining % 10)
            count += 1
        }
        remaining = remaining / 10
    }
    while remaining > 0
    for i in 0..<count {
        at :: count - 1 - i
        if i > 0 && (count - i) % 3 == 0 {
            text_buffer.append(text, locale.grouping)
        }
        if at < digits.count {
            text_buffer.append_byte(text, digits[at])
        }
    }
    if places > 0 {
        text_buffer.append(text, locale.decimal)
        text_buffer.append_unsigned(text, fraction, 10, cast[usize](places))
    }
}

/**
 * Write a date in the locale's order: 12/31/2026 in en-US, 31/12/2026 in en-GB, 2026-12-31 in NEUTRAL.
 *
 * The month and day have two digits, and the year at least four.
 *
 * @param text Where it's written; what doesn't fit is dropped, and the buffer marked truncated.
 * @param date The date; its time of day isn't written.
 * @param locale Whose marks to use; the locale in effect (current) unless given.
 */
append_date :: fn(text: ptr[mut text_buffer.TextBuffer], date: time.DateTime, locale := current()) {
    separator :: locale.date_separator
    match locale.date_order {
        case .YearMonthDay => {
            text_buffer.append_signed(text, date.year, 10, 4)
            text_buffer.append(text, separator)
            text_buffer.append_unsigned(text, cast[u64](date.month), 10, 2)
            text_buffer.append(text, separator)
            text_buffer.append_unsigned(text, cast[u64](date.day), 10, 2)
        }
        case .MonthDayYear => {
            text_buffer.append_unsigned(text, cast[u64](date.month), 10, 2)
            text_buffer.append(text, separator)
            text_buffer.append_unsigned(text, cast[u64](date.day), 10, 2)
            text_buffer.append(text, separator)
            text_buffer.append_signed(text, date.year, 10, 4)
        }
        case .DayMonthYear => {
            text_buffer.append_unsigned(text, cast[u64](date.day), 10, 2)
            text_buffer.append(text, separator)
            text_buffer.append_unsigned(text, cast[u64](date.month), 10, 2)
            text_buffer.append(text, separator)
            text_buffer.append_signed(text, date.year, 10, 4)
        }
    }
}

/**
 * Write a time of day to the minute: 14:05 on a 24-hour clock, 2:05 pm on a 12-hour one.
 *
 * On a 24-hour clock the hour has two digits; on a 12-hour one it has no leading zero, and midnight and noon are 12.
 *
 * @param text Where it's written; what doesn't fit is dropped, and the buffer marked truncated.
 * @param date The time; its date, seconds and fraction aren't written.
 * @param locale Whose marks to use; the locale in effect (current) unless given.
 */
append_time :: fn(text: ptr[mut text_buffer.TextBuffer], date: time.DateTime, locale := current()) {
    if locale.hours_24 {
        text_buffer.append_unsigned(text, cast[u64](date.hour), 10, 2)
    }
    else {
        hour :: date.hour % 12
        text_buffer.append_unsigned(text, cast[u64](if hour == 0 { 12 } else { hour }))
    }
    text_buffer.append_byte(text, cast[u8](':'))
    text_buffer.append_unsigned(text, cast[u64](date.minute), 10, 2)
    if !locale.hours_24 {
        text_buffer.append(text, if date.hour < 12 { " am" } else { " pm" })
    }
}

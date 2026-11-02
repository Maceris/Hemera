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

DateOrder :: enum {
    YearMonthDay,
    MonthDayYear,
    DayMonthYear,
}

FirstDay :: enum {
    Monday,
    Sunday,
}

Locale :: struct {
    // Its name, as "en-GB"; "" for NEUTRAL
    name : string,
    // Between a number's whole part and its fraction, and between each group of three digits ("" for no groups)
    decimal : string,
    grouping : string,
    date_order : DateOrder,
    date_separator : string,
    // A 24-hour clock, or a 12-hour one with " am" and " pm"
    hours_24 : bool,
    first_day : FirstDay,
}

// No locale's own ways: ISO 8601's dates, a point and no groups, and a 24-hour clock.
NEUTRAL :: Locale.{name = "", decimal = ".", grouping = "", date_order = .YearMonthDay, date_separator = "-", hours_24 = true,
    first_day = .Monday}

EN_US :: Locale.{name = "en-US", decimal = ".", grouping = ",", date_order = .MonthDayYear, date_separator = "/", hours_24 = false,
    first_day = .Sunday}

EN_GB :: Locale.{name = "en-GB", decimal = ".", grouping = ",", date_order = .DayMonthYear, date_separator = "/", hours_24 = true,
    first_day = .Monday}

// Every locale there is, by name.
LOCALES :: Locale.[EN_US, EN_GB]

// The locale named name, or null.
find :: fn(name: string) -> Locale? {
    for each in LOCALES {
        if each.name == name {
            return each
        }
    }
    return null
}

// The locale in effect: the context's, or the process's, or NEUTRAL.
current :: fn() -> Locale {
    match runtime.get_extension(Locale) {
        case Some(found) => return found^
        case None => {}
    }
    return find(runtime.locale_name()) or_else NEUTRAL
}

// value, with the locale's groups: 1,234,567.
append_integer :: fn(text: ptr[mut text_buffer.TextBuffer], value: i64, locale := current()) {
    append_fixed(text, value, 0, locale)
}

/*
 * value with places digits after the decimal mark, value being that many times ten bigger than the number written:
 * append_fixed(&text, 123456789, 2) writes 1,234,567.89 in en-US.
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

// A date in the locale's order: 12/31/2026 in en-US, 31/12/2026 in en-GB, 2026-12-31 in NEUTRAL.
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

// A time of day to the minute: 14:05 on a 24-hour clock, 2:05 pm on a 12-hour one.
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

/*
 * std/locale: numbers, dates and times written the way each locale writes them, the locale found by name, and the one
 * in effect taken from the context, NEUTRAL without one.
 */
package locale_test

import runtime from "base"
import locale from "std"
import testing from "std"
import text_buffer from "std"
import time from "std"

/**
 * Take what's been written to a text buffer, and empty it for what's written next.
 *
 * @param text The buffer, emptied.
 * @return What it held, a view of its storage, good until the next write to it.
 */
written :: fn(text: ptr[mut text_buffer.TextBuffer]) -> string {
    made :: text_buffer.as_string(text)
    text_buffer.clear(text)
    return made
}

/** The moment the dates and times are written for: 31 December 2026, 14:05. */
MOMENT :: time.DateTime.{year = 2026, month = 12, day = 31, hour = 14, minute = 5}

finds_locales_by_name #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_some(t, locale.find("en-US"), "American English is one of std's locales")
    testing.expect_some(t, locale.find("en-GB"), "British English is one of std's locales")
    testing.expect_none(t, locale.find("de-DE"), "German isn't one of std's locales")
    return .Ok
}

writes_numbers_as_each_locale_does #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    us :: testing.require_some(t, locale.find("en-US"), "American English is one of std's locales")?
    gb :: testing.require_some(t, locale.find("en-GB"), "British English is one of std's locales")?
    storage : u8[64]
    text := text_buffer.make(storage)
    locale.append_integer(&text, 1234567, us)
    testing.expect_eq(t, written(&text), "1,234,567", "English groups digits in threes with commas")
    locale.append_fixed(&text, 123456789, 2, gb)
    testing.expect_eq(t, written(&text), "1,234,567.89", "two digits of fraction after a point")
    locale.append_fixed(&text, -1205, 2, locale.NEUTRAL)
    testing.expect_eq(t, written(&text), "-12.05", "NEUTRAL doesn't group, and keeps the fraction's leading zero")
    locale.append_integer(&text, 999, us)
    testing.expect_eq(t, written(&text), "999", "three digits make only one group")
    return .Ok
}

writes_dates_and_times_as_each_locale_does #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    us :: testing.require_some(t, locale.find("en-US"), "American English is one of std's locales")?
    gb :: testing.require_some(t, locale.find("en-GB"), "British English is one of std's locales")?
    storage : u8[64]
    text := text_buffer.make(storage)
    locale.append_date(&text, MOMENT, us)
    testing.expect_eq(t, written(&text), "12/31/2026", "Americans write the month first")
    locale.append_date(&text, MOMENT, gb)
    testing.expect_eq(t, written(&text), "31/12/2026", "the British write the day first")
    locale.append_date(&text, MOMENT, locale.NEUTRAL)
    testing.expect_eq(t, written(&text), "2026-12-31", "NEUTRAL writes ISO 8601's date")
    locale.append_time(&text, MOMENT, us)
    testing.expect_eq(t, written(&text), "2:05 pm", "Americans use a 12-hour clock")
    locale.append_time(&text, MOMENT, gb)
    testing.expect_eq(t, written(&text), "14:05", "the British use a 24-hour clock")
    midnight :: time.DateTime.{year = 2026, month = 1, day = 2, hour = 0, minute = 30}
    locale.append_time(&text, midnight, us)
    testing.expect_eq(t, written(&text), "12:30 am", "the hour after midnight is 12 on a 12-hour clock")
    return .Ok
}

takes_the_locale_in_effect_from_the_context #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    us :: testing.require_some(t, locale.find("en-US"), "American English is one of std's locales")?
    testing.expect_eq(t, locale.current().name, "", "with no locale given, NEUTRAL is in effect")
    storage : u8[64]
    text := text_buffer.make(storage)
    // The context's data can't point into the stack, the node can
    british :: runtime.new(locale.Locale)
    defer runtime.free(british)
    british^ = locale.EN_GB
    node := runtime.extension_node(british)
    push_context british_scope (extensions = &node) {
        testing.expect_eq(t, locale.current().name, "en-GB", "a locale pushed on the context is the one in effect")
        locale.append_date(&text, MOMENT)
        testing.expect_eq(t, written(&text), "31/12/2026", "a date written with no locale given uses the context's")
    }
    testing.expect_eq(t, locale.current().first_day, .Monday, "NEUTRAL again after the push, whose weeks start on Monday")
    testing.expect_eq(t, us.first_day, .Sunday, "American weeks start on Sunday")
    return .Ok
}

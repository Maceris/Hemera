/*
 * std/locale: numbers, dates and times written the way each locale writes them, the locale found by name, and the one
 * in effect taken from the context, NEUTRAL without one. main returns 42 if everything worked, or the number of the first
 * check that failed.
 */
package locale_test

import runtime from "base"
import locale from "std"
import text_buffer from "std"
import time from "std"

written :: fn(text: ptr[mut text_buffer.TextBuffer]) -> string {
    made :: text_buffer.as_string(text)
    text_buffer.clear(text)
    return made
}

main :: fn() -> int {
    storage : u8[64]
    text := text_buffer.make(storage)
    us :: locale.find("en-US") or_return 1
    gb :: locale.find("en-GB") or_return 2
    if locale.find("de-DE") != null {
        return 3
    }
    // Numbers: groups of three, and the fraction
    locale.append_integer(&text, 1234567, us)
    if written(&text) != "1,234,567" {
        return 4
    }
    locale.append_fixed(&text, 123456789, 2, gb)
    if written(&text) != "1,234,567.89" {
        return 5
    }
    locale.append_fixed(&text, -1205, 2, locale.NEUTRAL)
    if written(&text) != "-12.05" {
        return 6
    }
    locale.append_integer(&text, 999, us)
    if written(&text) != "999" {
        return 7
    }
    // Dates and times
    moment :: time.DateTime.{year = 2026, month = 12, day = 31, hour = 14, minute = 5}
    locale.append_date(&text, moment, us)
    if written(&text) != "12/31/2026" {
        return 8
    }
    locale.append_date(&text, moment, gb)
    if written(&text) != "31/12/2026" {
        return 9
    }
    locale.append_date(&text, moment, locale.NEUTRAL)
    if written(&text) != "2026-12-31" {
        return 10
    }
    locale.append_time(&text, moment, us)
    if written(&text) != "2:05 pm" {
        return 11
    }
    locale.append_time(&text, moment, gb)
    if written(&text) != "14:05" {
        return 12
    }
    midnight :: time.DateTime.{year = 2026, month = 1, day = 2, hour = 0, minute = 30}
    locale.append_time(&text, midnight, us)
    if written(&text) != "12:30 am" {
        return 13
    }
    // The one in effect: NEUTRAL here, with no locale given, and the context's inside a push
    if locale.current().name != "" {
        return 14
    }
    // The context's data can't point into the stack, the node can
    british :: runtime.new(locale.Locale)
    british^ = locale.EN_GB
    node := runtime.extension_node(british)
    push_context british_scope (extensions = &node) {
        if locale.current().name != "en-GB" {
            return 15
        }
        locale.append_date(&text, moment)
        if written(&text) != "31/12/2026" {
            return 16
        }
    }
    if locale.current().first_day != .Monday || us.first_day != .Sunday {
        return 17
    }
    return 42
}

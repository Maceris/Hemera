/*
 * std/regex: patterns compiled and run in linear time, matches leftmost-first, with captures, counted and lazy
 * repetition, classes, anchors, word boundaries, case folding and UTF-8; a pattern that backtracking engines take
 * exponential time on; and patterns that aren't ones refused with why.
 */
package regex_test

import regex from "std"
import testing from "std"
import text_buffer from "std"

/**
 * Find where a pattern first matches text.
 *
 * @param pattern The pattern, compiled with flags and freed before this returns.
 * @param text The text searched.
 * @param flags How the pattern is compiled.
 * @return start The match's first byte offset; -1 when it matches nowhere, -2 when the pattern doesn't compile.
 * @return end The byte offset just past the match; -1 and -2 as start is.
 */
found :: fn(pattern: string, text: string, flags := regex.Flags.{}) -> (start : int, end : int) {
    compiled := match regex.compile(pattern, flags) {
        case Ok(made) => made
        case Error(error) => return -2, -2
    }
    defer regex.free(&compiled)
    match regex.find(&compiled, text) {
        case Some(span) => return cast[int](span.start), cast[int](span.end)
        case None => return -1, -1
    }
}

/**
 * Check that a pattern first matches text where it should, reporting where it did if not.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param pattern The pattern.
 * @param text The text searched.
 * @param start The match's first byte offset; -1 for no match.
 * @param end The byte offset just past it; -1 for no match.
 * @param message Why it should match there, for whoever reads a failure.
 * @param flags How the pattern is compiled.
 * @param location Where the check is; the caller's own.
 * @return True if it matched there; false, the failure recorded, if not.
 */
expect_found :: fn(t: ptr[mut testing.T], pattern: string, text: string, start: int, end: int, message: string,
    flags := regex.Flags.{}, location := #caller_location) -> bool {
    found_start, found_end :: found(pattern, text, flags)
    if found_start == start && found_end == end {
        return true
    }
    storage : u8[testing.TEXT_BYTES]
    detail := text_buffer.make(storage)
    text_buffer.append_format(&detail, "% in %: expected %..%, got %..%", pattern, text, start, end, found_start, found_end)
    testing.record(t, message, text_buffer.as_string(&detail), location)
    return false
}

/**
 * Check that a pattern is refused, for the reason it should be.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param pattern The pattern, which isn't one.
 * @param kind Why it should be refused.
 * @param message Why it isn't a pattern, for whoever reads a failure.
 * @param location Where the check is; the caller's own.
 * @return True if it was refused for kind; false, the failure recorded, if it compiled or was refused otherwise.
 */
expect_refused :: fn(t: ptr[mut testing.T], pattern: string, kind: regex.ErrorKind, message: string,
    location := #caller_location) -> bool {
    match regex.compile(pattern) {
        case Ok(compiled) => {
            made := compiled
            regex.free(&made)
            testing.record(t, message, "it compiled", location)
            return false
        }
        case Error(error) => return testing.expect_eq(t, error.kind, kind, message, location)
    }
}

matches_literals_and_classes #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    expect_found(t, "abc", "xxabcx", 2, 5, "a literal matches where it is in the text")
    expect_found(t, "abc", "xxabx", -1, -1, "a literal that isn't all there matches nowhere")
    expect_found(t, "[a-c]+", "zzabcabz", 2, 7, "a range class takes every letter in it")
    expect_found(t, "[^0-9]+", "123abc456", 3, 6, "a negated class takes what isn't a digit")
    expect_found(t, "\\d+", "order 1234 now", 6, 10, "\\d is a digit")
    expect_found(t, "\\s\\w+", "one two", 3, 7, "\\s is a space and \\w a word's character")
    return .Ok
}

matches_leftmost_first #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // The alternative written first wins at the same start
    expect_found(t, "a|ab", "ab", 0, 1, "a, written first, wins over the longer ab")
    expect_found(t, "ab|a", "ab", 0, 2, "ab, written first, wins")
    expect_found(t, "x|y|z", "--z", 2, 3, "the only alternative that matches wins wherever it is")
    return .Ok
}

repeats_greedily_lazily_and_counted #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    expect_found(t, "a+", "aaa", 0, 3, "+ takes as many as there are")
    expect_found(t, "a+?", "aaa", 0, 1, "+? takes as few as it can")
    expect_found(t, "a.*b", "axbxb", 0, 5, ".* runs to the last b")
    expect_found(t, "a.*?b", "axbxb", 0, 3, ".*? stops at the first b")
    expect_found(t, "a{2,3}", "aaaa", 0, 3, "{2,3} takes at most 3")
    expect_found(t, "x{3}", "xx", -1, -1, "{3} needs all 3")
    expect_found(t, "a{2,}", "aaaaa", 0, 5, "{2,} takes as many as there are")
    expect_found(t, "a{2,3}?", "aaaa", 0, 2, "{2,3}? takes as few as it can, 2")
    expect_found(t, "(a|b)*c", "ababc", 0, 5, "a repeated group takes each alternative in turn")
    expect_found(t, "(?:a*)*b", "aaab", 0, 4, "a repetition of what can be empty still ends")
    return .Ok
}

anchors_at_ends_and_word_boundaries #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    expect_found(t, "^abc$", "abc", 0, 3, "^ and $ are the text's start and end")
    expect_found(t, "^abc$", "abcd", -1, -1, "$ isn't before the d")
    expect_found(t, "c$", "abc", 2, 3, "$ anchors at the text's end")
    expect_found(t, "\\bcat\\b", "concat cat", 7, 10, "the cat in concat has no boundary before it")
    expect_found(t, "\\Bcat", "concat cat", 3, 6, "\\B is inside a word, as concat's cat is")
    expect_found(t, "\\bcat", "concat cat", 7, 10, "\\b alone still skips concat's cat")
    expect_found(t, "a.b", "a\nb", -1, -1, ". isn't a newline")
    return .Ok
}

folds_case #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    expect_found(t, "(?i)hello", "Say HELLO", 4, 9, "(?i) ignores case")
    expect_found(t, "hello", "Say HELLO", 4, 9, "ignore_case does as (?i) does", regex.Flags.{ignore_case = true})
    expect_found(t, "hello", "Say HELLO", -1, -1, "without either, case counts")
    return .Ok
}

matches_code_points_not_bytes #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // é is two bytes
    expect_found(t, "é+", "caféé!", 3, 7, "+ repeats the whole two-byte é")
    expect_found(t, "caf.!", "café!", 0, 6, ". takes the whole two-byte é")
    return .Ok
}

captures_groups #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    compiled :: regex.compile("(\\w+)@(\\w+)\\.com")
    pattern := testing.require_ok(t, compiled, "a pattern with two groups compiles")?
    defer regex.free(&pattern)
    testing.expect_eq(t, regex.group_count(&pattern), 3, "the whole match counts as a group, beside the two written")
    groups : regex.Span[3]
    text :: "mail bob@example.com now"
    testing.require(t, regex.captures(&pattern, text, groups[0..<3]), "the address in the text matches")?
    testing.expect_eq(t, text[groups[0].start..<groups[0].end], "bob@example.com", "group 0 is the whole match")
    testing.expect_eq(t, text[groups[1].start..<groups[1].end], "bob", "group 1 is the first parenthesized one")
    testing.expect_eq(t, text[groups[2].start..<groups[2].end], "example", "group 2 is the second")
    return .Ok
}

runs_in_linear_time #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // Exponential for backtracking: (a?){n}a{n} against n a's
    expect_found(t, "(a?){30}a{30}", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", 0, 30, "every a? gives way to the a{30} after")
    return .Ok
}

refuses_what_isnt_a_pattern #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    expect_refused(t, "(ab", .UnmatchedParenthesis, "the ( is never closed")
    expect_refused(t, "ab)", .UnmatchedParenthesis, "the ) was never opened")
    expect_refused(t, "*a", .NothingToRepeat, "* comes before anything it could repeat")
    expect_refused(t, "[a-", .UnclosedClass, "the [ is never closed")
    expect_refused(t, "a{2,1}", .BadRepeat, "at least 2 and at most 1 can't both be")
    expect_refused(t, "[z-a]", .BadRange, "z comes after a, so the range is backwards")
    expect_refused(t, "a\\", .BadEscape, "the \\ at the end escapes nothing")
    return .Ok
}

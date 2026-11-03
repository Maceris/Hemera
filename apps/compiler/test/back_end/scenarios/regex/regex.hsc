/*
 * std/regex: patterns compiled and run in linear time, matches leftmost-first, with captures, counted and lazy
 * repetition, classes, anchors, word boundaries, case folding and UTF-8; a pattern that backtracking engines take
 * exponential time on; and patterns that aren't ones refused with why. main returns 42 if everything worked, or the
 * number of the first check that failed.
 */
package regex_test

import regex from "std"

// Where pattern first matches text, or -1, -1 for nowhere; any pattern that doesn't compile is -2, -2.
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

is :: fn(pattern: string, text: string, start: int, end: int, flags := regex.Flags.{}) -> bool {
    found_start, found_end :: found(pattern, text, flags)
    return found_start == start && found_end == end
}

refused :: fn(pattern: string, kind: regex.ErrorKind) -> bool {
    match regex.compile(pattern) {
        case Ok(compiled) => {
            made := compiled
            regex.free(&made)
            return false
        }
        case Error(error) => return error.kind == kind
    }
}

main :: fn() -> int {
    if !is("abc", "xxabcx", 2, 5) || !is("abc", "xxabx", -1, -1) {
        return 1
    }
    if !is("[a-c]+", "zzabcabz", 2, 7) || !is("[^0-9]+", "123abc456", 3, 6) {
        return 2
    }
    if !is("\\d+", "order 1234 now", 6, 10) || !is("\\s\\w+", "one two", 3, 7) {
        return 3
    }
    // Leftmost-first: the alternative written first wins at the same start
    if !is("a|ab", "ab", 0, 1) || !is("ab|a", "ab", 0, 2) || !is("x|y|z", "--z", 2, 3) {
        return 4
    }
    // Greedy, and lazy
    if !is("a+", "aaa", 0, 3) || !is("a+?", "aaa", 0, 1) || !is("a.*b", "axbxb", 0, 5) || !is("a.*?b", "axbxb", 0, 3) {
        return 5
    }
    if !is("^abc$", "abc", 0, 3) || !is("^abc$", "abcd", -1, -1) || !is("c$", "abc", 2, 3) {
        return 6
    }
    if !is("a{2,3}", "aaaa", 0, 3) || !is("x{3}", "xx", -1, -1) || !is("a{2,}", "aaaaa", 0, 5) || !is("a{2,3}?", "aaaa", 0, 2) {
        return 7
    }
    if !is("(?i)hello", "Say HELLO", 4, 9) || !is("hello", "Say HELLO", 4, 9, regex.Flags.{ignore_case = true}) || !is("hello", "Say HELLO", -1, -1) {
        return 8
    }
    if !is("\\bcat\\b", "concat cat", 7, 10) || !is("\\Bcat", "concat cat", 3, 6) || !is("\\bcat", "concat cat", 7, 10) {
        return 9
    }
    // Code points, not bytes: é is two
    if !is("é+", "caféé!", 3, 7) || !is("caf.!", "café!", 0, 6) {
        return 10
    }
    if !is("a.b", "a\nb", -1, -1) || !is("(a|b)*c", "ababc", 0, 5) || !is("(?:a*)*b", "aaab", 0, 4) {
        return 11
    }
    // Captures
    pattern := regex.compile("(\\w+)@(\\w+)\\.com") or_return 12
    defer regex.free(&pattern)
    if regex.group_count(&pattern) != 3 {
        return 13
    }
    groups : regex.Span[3]
    text :: "mail bob@example.com now"
    if !regex.captures(&pattern, text, groups[0..<3]) {
        return 14
    }
    if text[groups[0].start..<groups[0].end] != "bob@example.com" || text[groups[1].start..<groups[1].end] != "bob"
        || text[groups[2].start..<groups[2].end] != "example" {
        return 15
    }
    // Exponential for backtracking: (a?){n}a{n} against n a's
    if !is("(a?){30}a{30}", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", 0, 30) {
        return 16
    }
    if !refused("(ab", .UnmatchedParenthesis) || !refused("ab)", .UnmatchedParenthesis) || !refused("*a", .NothingToRepeat) {
        return 17
    }
    if !refused("[a-", .UnclosedClass) || !refused("a{2,1}", .BadRepeat) || !refused("[z-a]", .BadRange) || !refused("a\\", .BadEscape) {
        return 18
    }
    return 42
}

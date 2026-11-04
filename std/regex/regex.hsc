package regex

import runtime from "base"
import unicode from "std"

/*
 * RE2's syntax, but for what can't run in linear time (no backreferences, no lookaround), matching code points of UTF-8
 * text:
 *
 *     x            the code point x; \ before any of \.+*?()|[]{}^$ is that character, \n \t \r as in strings
 *     .            any code point but a line feed
 *     [a-z_] [^0-9] a class, or not one; ranges, and \d \w \s within
 *     \d \w \s     ASCII digits, word characters ([0-9A-Za-z_]) and spaces ([\t\n\f\r ]); \D \W \S what they aren't
 *     ^ $          the text's start and end
 *     \b \B        a word boundary, and not one
 *     (x)          a group, captured; (?:x) not captured
 *     x|y          x, else y
 *     x* x+ x?     repetition; x{n} x{n,} x{n,m} counted, up to 1000; each followed by ? to prefer fewer
 *     (?i)         ignore ASCII case from here, as compile's ignore_case does for all of it
 *
 * Matches are leftmost-first, as Perl's and RE2's are: the earliest start, and at it, the alternative and repetition
 * the pattern prefers.
 *
 *     pattern := regex.compile("(\\w+)@(\\w+)\\.com")?
 *     defer regex.free(&pattern)
 *     found :: regex.find(&pattern, text) or_return ...        // found.start, found.end
 *     groups : regex.Span[3]
 *     regex.captures(&pattern, text, groups[0..<3])            // groups[1], groups[2]
 */

/** The most a counted repetition repeats: n and m in x{n,m} can be 0 to this. */
MAX_REPEAT :: 1000
/**
 * The most instructions a compiled pattern has, which bounds the memory a match takes: counted repetitions copy what
 * they repeat, so (x{1000}){1000} is too big.
 */
MAX_INSTRUCTIONS :: 100_000

/** Where a match, or a group of one, is in the text: byte offsets, start inclusive, end exclusive. */
Span :: struct {
    /** The byte offset of its first byte, at a code point's start. */
    start : usize,
    /** The byte offset just past its last byte; equal to start for an empty match. */
    end : usize,
}

/** Why a pattern doesn't compile. */
ErrorKind :: enum {
    /** A ( without its ), a ) without its (, or (? followed by something other than : or i). */
    UnmatchedParenthesis,
    /** A [ without its ]. */
    UnclosedClass,
    /** *, +, ? or {n,m} with nothing to repeat, like at the pattern's start or after |. */
    NothingToRepeat,
    /** A {n,m} that isn't one, or past MAX_REPEAT, or with m less than n. */
    BadRepeat,
    /** A \ at the end, before what can't be escaped, or \D \W \S inside a class. */
    BadEscape,
    /** A range whose end comes before its start. */
    BadRange,
    /** More instructions than MAX_INSTRUCTIONS. */
    TooBig,
    /** Out of memory; never given yet, since compile calls context.assertion_handler instead. */
    NoMemory,
}

/** Why a pattern doesn't compile, and where. */
RegexError :: struct {
    /** What's wrong. */
    kind : ErrorKind,
    /** The pattern's byte where it was found: for a parenthesis, class or repetition, where it opens. */
    at : usize,
}

/** What an instruction of a compiled pattern does. */
Opcode :: enum {
    /** A code point within one of the class's ranges (or outside all of them, if it's negated). */
    Class,
    /** Any code point but a line feed. */
    Any,
    /** Go on at first, and at second, preferring first. */
    Split,
    /** Go on at first. */
    Jump,
    /** Keep where the text is, in capture slot first: a group's start is slot 2n, its end 2n + 1. */
    Save,
    /** Only where the text starts, at byte 0. */
    AssertStart,
    /** Only where the text ends. */
    AssertEnd,
    /** Only between a word character ([0-9A-Za-z_]) and something else, or the text's start or end. */
    WordBoundary,
    /** Only where there's no word boundary. */
    NotWordBoundary,
    /** The pattern has matched. */
    Match,
}

/** One instruction of a compiled pattern. */
Instruction :: struct {
    /** What it does. */
    opcode : Opcode,
    /** A Split's or Jump's target, the instruction's index, or a Save's slot. */
    first : usize,
    /** A Split's second target, the one it prefers less. */
    second : usize,
    /** Where a Class's ranges start in the pattern's ranges. */
    ranges_start : usize,
    /** How many ranges a Class has. */
    ranges_count : usize,
    /** Whether a Class takes what's outside its ranges instead. */
    negated : bool,
    /** Whether a Class ignores ASCII case. */
    folded : bool,
}

/** A run of code points a class takes, both ends included. */
Range :: struct {
    /** The first code point. */
    low : u32,
    /** The last code point, at least low. */
    high : u32,
}

/** A compiled pattern, from compile; free gives back its memory. Matching only reads it, so threads can share one. */
Regex :: struct {
    /** Its instructions, which a match runs from the first. */
    program : Instruction[..],
    /** Its classes' ranges, which instructions refer to. */
    ranges : Range[..],
    /** Groups, the whole match counted: each has two slots. */
    groups : usize,
}

/** Options for compile. */
Flags :: struct {
    /** Ignore ASCII case in the whole pattern, as (?i) at its start does; other letters still match only themselves. */
    ignore_case : bool,
}

/**
 * Compile a pattern, for matching any number of texts.
 *
 * Its memory comes from context.allocator; without it, calls context.assertion_handler, as array_add does.
 *
 * @param pattern The pattern, in the syntax above, as UTF-8.
 * @param flags Options, none by default.
 * @return The compiled pattern, which free gives back.
 * @error UnmatchedParenthesis A ( without its ), a ) without its (, or (? not followed by : or i).
 * @error UnclosedClass A [ without its ].
 * @error NothingToRepeat A repetition with nothing before it to repeat.
 * @error BadRepeat A {n,m} that isn't one, past MAX_REPEAT, or with m less than n.
 * @error BadEscape A \ at the end, before what can't be escaped, or \D \W \S inside a class.
 * @error BadRange A class's range whose end comes before its start.
 * @error TooBig More instructions than MAX_INSTRUCTIONS, as large counted repetitions make.
 */
compile :: fn(pattern: string, flags := Flags.{}) -> Result[Regex, RegexError] {
    parser := Parser.{text = string_bytes(pattern), fold = flags.ignore_case, groups = 1}
    made := Regex.{groups = 1}
    parser.regex = &made
    // The whole match is group 0
    emit(&parser, Instruction.{opcode = .Save, first = 0})
    alternation(&parser)
    if (parser.error is_none) && parser.at < parser.text.count {
        fail(&parser, .UnmatchedParenthesis)
    }
    emit(&parser, Instruction.{opcode = .Save, first = 1})
    emit(&parser, Instruction.{opcode = .Match})
    match parser.error {
        case Some(error) => {
            free(&made)
            return .Error(error)
        }
        case None => {}
    }
    made.groups = parser.groups
    return .Ok(made)
}

/**
 * Give back a compiled pattern's memory.
 *
 * @param pattern The pattern, from compile; it can't be matched with after.
 */
free :: fn(pattern: ptr[mut Regex]) {
    runtime.array_free(&pattern.program)
    runtime.array_free(&pattern.ranges)
}

/**
 * Tell whether a pattern matches anywhere in a text.
 *
 * @param pattern A pattern from compile, not freed yet; it's only read.
 * @param text The text, as UTF-8; bytes that aren't are taken one at a time.
 * @return True when it matches somewhere, an empty match included.
 */
is_match :: fn(pattern: ptr[Regex], text: string) -> bool {
    return find(pattern, text) is_some
}

/**
 * Find the leftmost-first match in a text.
 *
 * The time it takes grows linearly with the text's length times the pattern's size, whatever the pattern.
 *
 * @param pattern A pattern from compile, not freed yet; it's only read.
 * @param text The text, as UTF-8; bytes that aren't are taken one at a time.
 * @param from The byte offset to search from, at a code point's start; ^ still matches only at 0, not here.
 * @return The match's span, in byte offsets into text; null when there's none, or from is past the text's end.
 */
find :: fn(pattern: ptr[Regex], text: string, from: usize = 0) -> Span? {
    spans : Span[1]
    if !run(pattern, string_bytes(text), from, spans[0..<1]) {
        return null
    }
    return spans[0]
}

/**
 * Find the leftmost-first match in a text, and where each of its groups matched.
 *
 * @param pattern A pattern from compile, not freed yet; it's only read. group_count says how many groups it has.
 * @param text The text, as UTF-8; bytes that aren't are taken one at a time.
 * @param groups Where the groups' spans go, as many as fit: group 0 the whole match, then each ( in the pattern's
 *     order. A group that didn't take part, or one past the pattern's, is an empty span at the text's end. Left as
 *     they were when there's no match.
 * @param from The byte offset to search from, at a code point's start; ^ still matches only at 0, not here.
 * @return True when there was a match.
 */
captures :: fn(pattern: ptr[Regex], text: string, groups: mut Span[], from: usize = 0) -> bool {
    return run(pattern, string_bytes(text), from, groups)
}

/**
 * Give how many groups a pattern has, so captures can be given room for all of them.
 *
 * @param pattern A pattern from compile, not freed yet; it's only read.
 * @return Its captured groups plus 1 for the whole match, so at least 1; (?:x) groups aren't counted.
 */
group_count :: fn(pattern: ptr[Regex]) -> usize {
    return pattern.groups
}

// ---- Parsing, by recursive descent, straight to the program

/** A pattern being compiled: where parsing is, and the program it's emitting into. */
Parser :: struct #scoped {
    /** The pattern's bytes, borrowed from compile's caller. */
    text : u8[],
    /** Where parsing is, a byte offset into text. */
    at : usize,
    /** The pattern being made, on compile's stack. */
    regex : ptr[mut Regex],
    /** Groups numbered so far, the whole match counted, so the next ( is this one. */
    groups : usize,
    /** Whether classes made from here on ignore ASCII case, from Flags.ignore_case or (?i). */
    fold : bool,
    /** The first error found; once it's set, the rest is parsed only as far as it takes to stop. */
    error : RegexError?,
    /** How many groups deep parsing is. */
    depth : usize,
}

/**
 * Note an error at where parsing is, unless one was noted already, so the first is the one reported.
 *
 * @param parser The parser; its at is where the error is reported.
 * @param kind What's wrong.
 */
fail :: fn(parser: ptr[mut Parser], kind: ErrorKind) {
    if (parser.error is_none) {
        parser.error = RegexError.{kind = kind, at = parser.at}
    }
}

/**
 * Add an instruction to the end of the program. Without the memory, calls context.assertion_handler.
 *
 * @param parser The parser. With MAX_INSTRUCTIONS already, nothing is added and it fails with TooBig.
 * @param instruction What to add, copied in as it is: its targets aren't moved.
 * @return Its index, where it went or would have gone.
 */
emit :: fn(parser: ptr[mut Parser], instruction: Instruction) -> usize {
    at :: parser.regex.program.count
    if at >= MAX_INSTRUCTIONS {
        fail(parser, .TooBig)
        return at
    }
    runtime.array_add(&parser.regex.program, instruction)
    return at
}

/**
 * Look at the next byte of the pattern without moving past it.
 *
 * @param parser A parser of a pattern, only read: its at isn't moved.
 * @return The byte at at, or 0 at the end, which nothing in the syntax is.
 */
peek :: fn(parser: ptr[Parser]) -> u8 {
    return if parser.at < parser.text.count { parser.text[parser.at] } else { 0 }
}

/**
 * Look at the byte after the next, without moving.
 *
 * @param parser A parser of a pattern, only read: its at isn't moved.
 * @return The byte at at + 1, or 0 past the end.
 */
peek_after :: fn(parser: ptr[Parser]) -> u8 {
    at :: parser.at + 1
    return if at < parser.text.count { parser.text[at] } else { 0 }
}

/**
 * Parse x|y|..., up to ) or the end: the first alternative with a split before it, to it or past it, and a jump after
 * it past the rest, which is itself an alternation.
 *
 * @param parser The parser, at the alternation's start; left at the ) or the end after it, or where an error was.
 */
alternation :: fn(parser: ptr[mut Parser]) {
    start :: parser.regex.program.count
    sequence(parser)
    if peek(parser) != cast[u8]('|') || (parser.error is_some) {
        return void
    }
    parser.at += 1
    insert(parser, start, Instruction.{opcode = .Split, first = start + 1})
    jump :: emit(parser, Instruction.{opcode = .Jump})
    set_second(parser, start, parser.regex.program.count)
    alternation(parser)
    if jump < parser.regex.program.count {
        parser.regex.program[jump].first = parser.regex.program.count
    }
}

/**
 * Set a split's second target.
 *
 * @param parser A parser whose program has the split; no other instruction changes.
 * @param at The split's index; past the program's end, as after TooBig, nothing is set.
 * @param target The instruction it goes on at.
 */
set_second :: fn(parser: ptr[mut Parser], at: usize, target: usize) {
    if at < parser.regex.program.count {
        parser.regex.program[at].second = target
    }
}

/**
 * Put an instruction in at an index, those after it moved along, and every target past it moved with them, so code
 * already emitted can be wrapped in a split.
 *
 * @param parser The parser. Without the memory, calls context.assertion_handler.
 * @param at Where it goes: it's at this index after, and a target of at from code before it now means it.
 * @param instruction The instruction; its own targets aren't moved.
 */
insert :: fn(parser: ptr[mut Parser], at: usize, instruction: Instruction) {
    regex :: parser.regex
    runtime.array_add(&regex.program, instruction)
    position := regex.program.count - 1
    loop {
        before :: position - 1
        if position <= at || position >= regex.program.count || before >= regex.program.count {
            break
        }
        regex.program[position] = regex.program[before]
        position -= 1
    }
    /*
     * A target past at moves; one at at moves too from code that was at or after it, which meant the instruction now
     * after the new one, but not from code before it, which meant where the code wrapped begins, now the new one.
     */
    for &each, i in regex.program {
        if i == at {
            continue
        }
        if each.opcode == .Split || each.opcode == .Jump {
            if each.first > at || (each.first == at && i > at) {
                each.first += 1
            }
            if each.opcode == .Split && (each.second > at || (each.second == at && i > at)) {
                each.second += 1
            }
        }
    }
    if at < regex.program.count {
        regex.program[at] = instruction
    }
}

/**
 * Parse a sequence of atoms, each maybe repeated, up to | or ) or the end.
 *
 * @param parser The parser; left at the | or ) or the end, or where an error was.
 */
sequence :: fn(parser: ptr[mut Parser]) {
    loop {
        if (parser.error is_some) || parser.at >= parser.text.count {
            return void
        }
        byte :: peek(parser)
        if byte == cast[u8]('|') || byte == cast[u8](')') {
            return void
        }
        repeated(parser)
    }
}

/**
 * Parse an atom, and its repetition if one follows.
 *
 * @param parser The parser, at the atom; it fails with NothingToRepeat if a repetition is there instead.
 */
repeated :: fn(parser: ptr[mut Parser]) {
    byte :: peek(parser)
    if byte == cast[u8]('*') || byte == cast[u8]('+') || byte == cast[u8]('?') || byte == cast[u8]('{') {
        fail(parser, .NothingToRepeat)
        return void
    }
    start :: parser.regex.program.count
    atom(parser)
    if (parser.error is_some) {
        return void
    }
    end :: parser.regex.program.count
    next :: peek(parser)
    if next == cast[u8]('*') || next == cast[u8]('+') || next == cast[u8]('?') {
        parser.at += 1
        lazy :: lazy_follows(parser)
        if next == cast[u8]('*') {
            star(parser, start, lazy)
        }
        else if next == cast[u8]('+') {
            plus(parser, start, lazy)
        }
        else {
            optional(parser, start, lazy)
        }
    }
    else if next == cast[u8]('{') {
        counted(parser, start, end)
    }
}

/**
 * Move past the ? that makes a repetition lazy, if there is one.
 *
 * @param parser The parser, just after the repetition.
 * @return True when there was a ?, so the repetition prefers fewer.
 */
lazy_follows :: fn(parser: ptr[mut Parser]) -> bool {
    if peek(parser) == cast[u8]('?') {
        parser.at += 1
        return true
    }
    return false
}

/**
 * Make the code from start to the program's end repeat any number of times: a split before it, a jump back after.
 *
 * @param parser A parser whose program ends with the code repeated. A split goes in at start, moving that code along by
 *     one, and a jump back is added at the end; without the memory, calls context.assertion_handler.
 * @param start Where the code repeated starts.
 * @param lazy Whether to prefer fewer repetitions.
 */
star :: fn(parser: ptr[mut Parser], start: usize, lazy: bool) {
    insert(parser, start, Instruction.{opcode = .Split})
    emit(parser, Instruction.{opcode = .Jump, first = start})
    after :: parser.regex.program.count
    prefer(parser, start, start + 1, after, lazy)
}

/**
 * Make the code from start to the program's end repeat once, then any number of times: a split after it, back to it.
 *
 * @param parser A parser whose program ends with the code repeated; a split back to it is added at the end. Without the
 *     memory, calls context.assertion_handler.
 * @param start Where the code repeated starts.
 * @param lazy Whether to prefer fewer repetitions.
 */
plus :: fn(parser: ptr[mut Parser], start: usize, lazy: bool) {
    split :: emit(parser, Instruction.{opcode = .Split})
    prefer(parser, split, start, split + 1, lazy)
}

/**
 * Make the code from start to the program's end match once or not at all: a split before it.
 *
 * @param parser A parser whose program ends with the code. A split goes in at start, moving that code along by one;
 *     without the memory, calls context.assertion_handler.
 * @param start Where the code starts, its index in the program.
 * @param lazy Whether to prefer leaving it out.
 */
optional :: fn(parser: ptr[mut Parser], start: usize, lazy: bool) {
    insert(parser, start, Instruction.{opcode = .Split})
    after :: parser.regex.program.count
    prefer(parser, start, start + 1, after, lazy)
}

/**
 * Set a split's two ways, the repeating one first unless it's lazy.
 *
 * @param parser A parser whose program has the split; it's replaced by a Split to repeat and leave, and no other
 *     instruction changes.
 * @param split The split's index; past the program's end, as after TooBig, nothing is set.
 * @param repeat Where the repeated code starts.
 * @param leave Where the code after the repetition starts.
 * @param lazy Whether leaving is preferred.
 */
prefer :: fn(parser: ptr[mut Parser], split: usize, repeat: usize, leave: usize, lazy: bool) {
    if split < parser.regex.program.count {
        parser.regex.program[split] = Instruction.{opcode = .Split, first = if lazy { leave } else { repeat }, second = if lazy { repeat } else { leave }}
    }
}

/**
 * Parse {n}, {n,} or {n,m} after an atom: the atom's code, from start to end, copied n times, then m - n optional ones,
 * or any number for {n,}.
 *
 * A copy of the atom's code is kept on context.allocator while it runs; without the memory, calls
 * context.assertion_handler.
 *
 * @param parser The parser, at the {. Fails with BadRepeat, at the {, for one that isn't a repetition, past
 *     MAX_REPEAT, or with m less than n.
 * @param start Where the atom's code starts.
 * @param end Where it ends, the program's end.
 */
counted :: fn(parser: ptr[mut Parser], start: usize, end: usize) {
    open :: parser.at
    parser.at += 1
    low :: number(parser) or_else MAX_REPEAT + 1
    high := low
    if peek(parser) == cast[u8](',') {
        parser.at += 1
        high = if peek(parser) == cast[u8]('}') { MAX_REPEAT + 2 } else { number(parser) or_else MAX_REPEAT + 1 }
    }
    if peek(parser) != cast[u8]('}') || low > MAX_REPEAT || (high <= MAX_REPEAT + 1 && (high > MAX_REPEAT || high < low)) {
        parser.at = open
        fail(parser, .BadRepeat)
        return void
    }
    parser.at += 1
    lazy :: lazy_follows(parser)
    // The atom's code, kept to copy, then taken out; each copy put back moved to where it goes
    atom_code : Instruction[..]
    defer runtime.array_free(&atom_code)
    for i in start..<end {
        if i < parser.regex.program.count {
            runtime.array_add(&atom_code, parser.regex.program[i])
        }
    }
    runtime.resizable(&parser.regex.program).count = start
    for copy in 0..<low {
        append_copy(parser, atom_code, start)
    }
    if high == MAX_REPEAT + 2 {
        // {n,}: then any number more
        copy_start :: parser.regex.program.count
        append_copy(parser, atom_code, start)
        star(parser, copy_start, lazy)
        return void
    }
    for copy in low..<high {
        copy_start :: parser.regex.program.count
        append_copy(parser, atom_code, start)
        optional(parser, copy_start, lazy)
    }
}

/**
 * Append a copy of code that was at an index, its targets moved to where it is now.
 *
 * @param parser A parser; the copy is emitted at its program's end, and past MAX_INSTRUCTIONS, the rest isn't added and
 *     it fails with TooBig, as emit does.
 * @param code The code, whose targets are all within it.
 * @param from The index it was at.
 */
append_copy :: fn(parser: ptr[mut Parser], code: Instruction[..], from: usize) {
    to :: parser.regex.program.count
    for each in code {
        moved := each
        if moved.opcode == .Split || moved.opcode == .Jump {
            moved.first = moved.first - from + to
            if moved.opcode == .Split {
                moved.second = moved.second - from + to
            }
        }
        emit(parser, moved)
    }
}

/**
 * Parse a repetition's count, in decimal.
 *
 * @param parser The parser, moved past the digits read.
 * @return The number; null when there's no digit. At most 6 digits are read, so it can't overflow, and anything past
 *     MAX_REPEAT is left for counted to refuse.
 */
number :: fn(parser: ptr[mut Parser]) -> usize? {
    value : usize = 0
    digits := 0
    loop {
        byte :: peek(parser)
        if byte < cast[u8]('0') || byte > cast[u8]('9') || digits > 5 {
            break
        }
        value = value * 10 + cast[usize](byte - cast[u8]('0'))
        parser.at += 1
        digits += 1
    }
    return if digits > 0 { value } else { null }
}

/**
 * Parse one atom: a group, a class, ., an anchor, an escape, or a code point.
 *
 * @param parser The parser, at the atom. A byte that isn't UTF-8 is taken as a code point of its own.
 */
atom :: fn(parser: ptr[mut Parser]) {
    byte :: peek(parser)
    if byte == cast[u8]('(') {
        group(parser)
    }
    else if byte == cast[u8]('[') {
        class(parser)
    }
    else if byte == cast[u8]('.') {
        parser.at += 1
        emit(parser, Instruction.{opcode = .Any})
    }
    else if byte == cast[u8]('^') {
        parser.at += 1
        emit(parser, Instruction.{opcode = .AssertStart})
    }
    else if byte == cast[u8]('$') {
        parser.at += 1
        emit(parser, Instruction.{opcode = .AssertEnd})
    }
    else if byte == cast[u8]('\\') {
        escape(parser)
    }
    else {
        point, length :: unicode.decode(parser.text, parser.at)
        parser.at += if length == 0 { cast[usize](1) } else { length }
        single(parser, point)
    }
}

/**
 * Emit a class of one code point, which ignores case if the parser does.
 *
 * @param parser The parser. Without the memory, calls context.assertion_handler.
 * @param point The code point to match, U+0000 to U+10FFFF; atom gives 0 for a byte that isn't UTF-8.
 */
single :: fn(parser: ptr[mut Parser], point: u32) {
    start :: parser.regex.ranges.count
    runtime.array_add(&parser.regex.ranges, Range.{low = point, high = point})
    emit(parser, Instruction.{opcode = .Class, ranges_start = start, ranges_count = 1, folded = parser.fold})
}

/**
 * Parse (x), (?:x), or (?i) on its own, which makes the rest of the pattern ignore ASCII case, past the group it's in.
 *
 * @param parser The parser, at the (. Fails with UnmatchedParenthesis, at the (, when there's no ), or for (? followed
 *     by anything but : or i).
 */
group :: fn(parser: ptr[mut Parser]) {
    open :: parser.at
    parser.at += 1
    captured := true
    if peek(parser) == cast[u8]('?') {
        parser.at += 1
        flag :: peek(parser)
        if flag == cast[u8]('i') && peek_after(parser) == cast[u8](')') {
            parser.at += 2
            parser.fold = true
            return void
        }
        if flag != cast[u8](':') {
            fail(parser, .UnmatchedParenthesis)
            return void
        }
        parser.at += 1
        captured = false
    }
    parser.depth += 1
    index :: parser.groups
    if captured {
        parser.groups += 1
        emit(parser, Instruction.{opcode = .Save, first = index * 2})
    }
    alternation(parser)
    if peek(parser) != cast[u8](')') {
        parser.at = open
        fail(parser, .UnmatchedParenthesis)
        return void
    }
    parser.at += 1
    parser.depth -= 1
    if captured {
        emit(parser, Instruction.{opcode = .Save, first = index * 2 + 1})
    }
}

/**
 * Parse an escape: \d \w \s and their negations, \b \B, and escaped characters.
 *
 * @param parser The parser, at the \. Fails with BadEscape at the end, or before what can't be escaped.
 */
escape :: fn(parser: ptr[mut Parser]) {
    parser.at += 1
    if parser.at >= parser.text.count {
        fail(parser, .BadEscape)
        return void
    }
    byte :: parser.text[parser.at]
    parser.at += 1
    if byte == cast[u8]('b') {
        emit(parser, Instruction.{opcode = .WordBoundary})
        return void
    }
    if byte == cast[u8]('B') {
        emit(parser, Instruction.{opcode = .NotWordBoundary})
        return void
    }
    start :: parser.regex.ranges.count
    match class_escape(parser, byte) {
        case Some(negated) => {
            emit(parser, Instruction.{opcode = .Class, ranges_start = start, ranges_count = parser.regex.ranges.count - start, negated = negated})
            return void
        }
        case None => {}
    }
    point :: escaped_point(byte) or_else 0xffffffff
    if point == 0xffffffff {
        parser.at -= 1
        fail(parser, .BadEscape)
        return void
    }
    single(parser, point)
}

/**
 * Add the ranges of a class escape, \d \w \s, or of \D \W \S, which the class then negates.
 *
 * @param parser The parser, whose pattern the ranges are added to. Without the memory, calls
 *     context.assertion_handler.
 * @param byte The byte after the \.
 * @return Whether the class is negated, true for the capitals; null for another escape, with nothing added.
 */
class_escape :: fn(parser: ptr[mut Parser], byte: u8) -> bool? {
    lower :: if byte >= cast[u8]('A') && byte <= cast[u8]('Z') { byte + 32 } else { byte }
    ranges :: &parser.regex.ranges
    if lower == cast[u8]('d') {
        runtime.array_add(ranges, Range.{low = cast[u32]('0'), high = cast[u32]('9')})
    }
    else if lower == cast[u8]('w') {
        runtime.array_add(ranges, Range.{low = cast[u32]('0'), high = cast[u32]('9')})
        runtime.array_add(ranges, Range.{low = cast[u32]('A'), high = cast[u32]('Z')})
        runtime.array_add(ranges, Range.{low = cast[u32]('_'), high = cast[u32]('_')})
        runtime.array_add(ranges, Range.{low = cast[u32]('a'), high = cast[u32]('z')})
    }
    else if lower == cast[u8]('s') {
        runtime.array_add(ranges, Range.{low = 9, high = 10})
        runtime.array_add(ranges, Range.{low = 12, high = 13})
        runtime.array_add(ranges, Range.{low = cast[u32](' '), high = cast[u32](' ')})
    }
    else {
        return null
    }
    return lower != byte
}

/**
 * Give the code point an escape stands for: \n \t \r, or one of the characters that mean something unescaped.
 *
 * @param byte The byte after the \.
 * @return The code point: 10, 9 or 13 for n, t and r, the byte itself for any of \.+*?()|[]{}^$-/, and null for
 *     anything else.
 */
escaped_point :: fn(byte: u8) -> u32? {
    if byte == cast[u8]('n') {
        return 10
    }
    if byte == cast[u8]('t') {
        return 9
    }
    if byte == cast[u8]('r') {
        return 13
    }
    for special in "\\.+*?()|[]{}^$-/" {
        if byte == cast[u8](special) {
            return cast[u32](byte)
        }
    }
    return null
}

/**
 * Parse [ranges], or [^ranges]: code points, a-b ranges, and \d \w \s within. A ] first is a member, as is a - first
 * or last.
 *
 * @param parser The parser, at the [. Fails with UnclosedClass at the [ without its ], BadEscape for a bad escape or
 *     \D \W \S within, and BadRange for a range whose end comes before its start.
 */
class :: fn(parser: ptr[mut Parser]) {
    open :: parser.at
    parser.at += 1
    negated := false
    if peek(parser) == cast[u8]('^') {
        negated = true
        parser.at += 1
    }
    start :: parser.regex.ranges.count
    first := true
    loop {
        if parser.at >= parser.text.count {
            parser.at = open
            fail(parser, .UnclosedClass)
            return void
        }
        byte :: parser.text[parser.at]
        // A ] first is a member
        if byte == cast[u8](']') && !first {
            parser.at += 1
            break
        }
        first = false
        low := cast[u32](0)
        if byte == cast[u8]('\\') {
            parser.at += 1
            if parser.at >= parser.text.count {
                fail(parser, .BadEscape)
                return void
            }
            escaped :: parser.text[parser.at]
            parser.at += 1
            match class_escape(parser, escaped) {
                case Some(inner_negated) => {
                    if inner_negated {
                        // \D \W \S inside a class: not supported as a part of one
                        fail(parser, .BadEscape)
                        return void
                    }
                    continue
                }
                case None => {}
            }
            low = escaped_point(escaped) or_else 0xffffffff
            if low == 0xffffffff {
                fail(parser, .BadEscape)
                return void
            }
        }
        else {
            point, length :: unicode.decode(parser.text, parser.at)
            parser.at += if length == 0 { cast[usize](1) } else { length }
            low = point
        }
        high := low
        if peek(parser) == cast[u8]('-') && parser.at + 1 < parser.text.count && peek_after(parser) != cast[u8](']') {
            parser.at += 1
            point, length :: unicode.decode(parser.text, parser.at)
            parser.at += if length == 0 { cast[usize](1) } else { length }
            high = point
            if high < low {
                fail(parser, .BadRange)
                return void
            }
        }
        runtime.array_add(&parser.regex.ranges, Range.{low = low, high = high})
    }
    emit(parser, Instruction.{opcode = .Class, ranges_start = start, ranges_count = parser.regex.ranges.count - start, negated = negated,
        folded = parser.fold})
}

// ---- Running: a Pike VM

/** A thread: where it is in the program, and its capture slots, in the VM's slot store. */
Thread :: struct {
    /** The index of the instruction it's at, one that consumes or matches. */
    pc : usize,
    /** Where its block of slots starts in the VM's store. */
    slots : usize,
}

/** The threads at one position, in priority order, each place in the program at most once. */
ThreadList :: struct {
    /** The threads, the most preferred first. */
    threads : Thread[..],
    /** For each place in the program, the generation it was last added in, which makes it there once per step. */
    seen : u64[..],
}

/** What a run reads: the program, its classes' ranges, and the text, all borrowed from run's caller. */
Input :: struct #scoped {
    /** The pattern's instructions. */
    program : Instruction[],
    /** The pattern's classes' ranges. */
    ranges : Range[],
    /** The text, as bytes. */
    text : u8[],
}

/** A run's state, apart from its thread lists: the capture slots and the step it's at. */
VM :: struct {
    /** How many slots a thread has: two for each group. */
    slot_count : usize,
    /** Slots for every thread, slot_count each, handed out and given back. NO_SLOT for one not set. */
    store : usize[..],
    /** Where each block given back starts, to hand out again. */
    free_slots : usize[..],
    /** Which step the run is at, counted up so a ThreadList's seen needn't be cleared. */
    generation : u64,
}

/**
 * Run a pattern on a text: the leftmost-first match from a position on, and its groups' spans.
 *
 * Its threads and slots are kept on context.allocator while it runs, and freed before it returns; without the memory,
 * calls context.assertion_handler.
 *
 * @param pattern A pattern from compile, not freed yet; it's only read. Its group count sets how many slots each thread
 *     has.
 * @param text The text, as UTF-8; bytes that aren't are taken one at a time.
 * @param from The byte offset to search from; past the text's end, there's no match.
 * @param groups Where the groups' spans go, as many as fit; a group that didn't take part, or past the pattern's, is
 *     an empty span at the text's end. Left as they were when there's no match.
 * @return True when there was a match.
 */
run :: fn(pattern: ptr[Regex], text: u8[], from: usize, groups: mut Span[]) -> bool {
    input := Input.{program = pattern.program[0..<pattern.program.count], ranges = pattern.ranges[0..<pattern.ranges.count], text = text}
    vm := VM.{slot_count = pattern.groups * 2}
    defer runtime.array_free(&vm.store)
    defer runtime.array_free(&vm.free_slots)
    current := ThreadList.{}
    next := ThreadList.{}
    defer free_list(&current)
    defer free_list(&next)
    for i in 0..<input.program.count {
        runtime.array_add(&current.seen, cast[u64](0))
        runtime.array_add(&next.seen, cast[u64](0))
    }
    matched := false
    found_slots := new_slots(&vm)
    at := from
    // The generation current's threads were added in; the next list's is one more
    vm.generation = 1
    loop {
        if at > text.count {
            break
        }
        // A new thread from here, after those before it, while nothing's matched yet: the search, unanchored
        if !matched {
            slots :: new_slots(&vm)
            add(&vm, &input, &current, 0, at, slots)
        }
        // Nothing left to follow once something's matched; before that, the search goes on to the next position
        if current.threads.count == 0 && matched {
            break
        }
        point := cast[u32](0)
        length := cast[usize](0)
        if at < text.count {
            decoded, decoded_length :: unicode.decode(text, at)
            point = decoded
            length = decoded_length
        }
        step :: if length == 0 { cast[usize](1) } else { length }
        vm.generation += 1
        for thread, i in current.threads {
            instruction :: input.program[thread.pc % input.program.count]
            if instruction.opcode == .Match {
                // This one wins over every thread after it
                copy_slots(&vm, thread.slots, found_slots)
                matched = true
                for later, j in current.threads {
                    if j > i {
                        release(&vm, later.slots)
                    }
                }
                release(&vm, thread.slots)
                break
            }
            if at < text.count && consumes(&input, instruction, point) {
                add(&vm, &input, &next, thread.pc + 1, at + step, thread.slots)
            }
            else {
                release(&vm, thread.slots)
            }
        }
        runtime.array_reset(&current.threads)
        swap :: current
        current = next
        next = swap
        if at >= text.count {
            break
        }
        at += step
    }
    for thread in current.threads {
        release(&vm, thread.slots)
    }
    if matched {
        for i in 0..<groups.count {
            start :: slot(&vm, found_slots, i * 2)
            end :: slot(&vm, found_slots, i * 2 + 1)
            groups[i] = if i < pattern.groups && start != NO_SLOT && end != NO_SLOT { Span.{start = start, end = end} }
                else { Span.{start = text.count, end = text.count} }
        }
    }
    return matched
}

/** A capture slot not set: the largest usize, never a byte offset into a text. */
NO_SLOT : usize : 0xffffffffffffffff

/**
 * Give back a thread list's memory.
 *
 * @param list The list; its threads' slots aren't given back to the VM, which run does itself.
 */
free_list :: fn(list: ptr[mut ThreadList]) {
    runtime.array_free(&list.threads)
    runtime.array_free(&list.seen)
}

/**
 * Add a thread at pc to a list, at a position, following jumps, splits (the first way first) and saves, and checking
 * assertions, so list holds only threads at instructions that consume or match.
 *
 * Without the memory for the list or slots, calls context.assertion_handler.
 *
 * @param vm The run's state, whose slots are handed out and given back.
 * @param input What the run reads: the program, its ranges and the text, only read.
 * @param list The list it goes in. A place already in it this generation is a less preferred way there, so the thread
 *     is dropped.
 * @param pc The index in the program of the instruction it's at; past the program's end, the thread is dropped and its
 *     slots given back.
 * @param at The byte offset in the text it's at, which saves record and assertions check.
 * @param slots Its block of slots, which this takes over: kept by the thread added, or given back.
 */
add :: fn(vm: ptr[mut VM], input: ptr[Input], list: ptr[mut ThreadList], pc: usize, at: usize, slots: usize) {
    if pc >= input.program.count || pc >= list.seen.count {
        release(vm, slots)
        return void
    }
    if list.seen[pc] == vm.generation {
        release(vm, slots)
        return void
    }
    list.seen[pc] = vm.generation
    instruction :: input.program[pc % input.program.count]
    if instruction.opcode == .Jump {
        add(vm, input, list, instruction.first, at, slots)
    }
    else if instruction.opcode == .Split {
        copy :: new_slots(vm)
        copy_slots(vm, slots, copy)
        add(vm, input, list, instruction.first, at, slots)
        add(vm, input, list, instruction.second, at, copy)
    }
    else if instruction.opcode == .Save {
        copy :: new_slots(vm)
        copy_slots(vm, slots, copy)
        set_slot(vm, copy, instruction.first, at)
        release(vm, slots)
        add(vm, input, list, pc + 1, at, copy)
    }
    else if instruction.opcode == .AssertStart {
        if at == 0 {
            add(vm, input, list, pc + 1, at, slots)
        }
        else {
            release(vm, slots)
        }
    }
    else if instruction.opcode == .AssertEnd {
        if at >= input.text.count {
            add(vm, input, list, pc + 1, at, slots)
        }
        else {
            release(vm, slots)
        }
    }
    else if instruction.opcode == .WordBoundary || instruction.opcode == .NotWordBoundary {
        before :: at > 0 && at - 1 < input.text.count && is_word(input.text[at - 1])
        after :: at < input.text.count && is_word(input.text[at])
        boundary :: before != after
        if boundary == (instruction.opcode == .WordBoundary) {
            add(vm, input, list, pc + 1, at, slots)
        }
        else {
            release(vm, slots)
        }
    }
    else {
        runtime.array_add(&list.threads, Thread.{pc = pc, slots = slots})
    }
}

/**
 * Tell whether an instruction that consumes takes a code point.
 *
 * @param input What the run reads, for the class's ranges.
 * @param instruction The instruction: Any or a Class; any other takes nothing.
 * @param point The code point at the thread's position.
 * @return True when it takes it, so the thread moves on past it.
 */
consumes :: fn(input: ptr[Input], instruction: Instruction, point: u32) -> bool {
    if instruction.opcode == .Any {
        return point != 10
    }
    if instruction.opcode != .Class {
        return false
    }
    inside := in_ranges(input, instruction, point)
    if !inside && instruction.folded {
        // ASCII letters either way round
        if point >= cast[u32]('a') && point <= cast[u32]('z') {
            inside = in_ranges(input, instruction, point - 32)
        }
        else if point >= cast[u32]('A') && point <= cast[u32]('Z') {
            inside = in_ranges(input, instruction, point + 32)
        }
    }
    return inside != instruction.negated
}

/**
 * Tell whether a code point is in one of a class's ranges, without its negation or case folding.
 *
 * @param input What the run reads, for the ranges.
 * @param instruction A Class instruction of the run's program: its ranges_start and ranges_count pick its ranges out of
 *     input's, any past their end skipped.
 * @param point The code point to look for, as it is: it isn't case folded here.
 * @return True when one of its ranges holds it.
 */
in_ranges :: fn(input: ptr[Input], instruction: Instruction, point: u32) -> bool {
    for i in 0..<instruction.ranges_count {
        index :: instruction.ranges_start + i
        if index < input.ranges.count && point >= input.ranges[index].low && point <= input.ranges[index].high {
            return true
        }
    }
    return false
}

/**
 * Tell whether a byte is a word character, for \b and \B: [0-9A-Za-z_], ASCII only.
 *
 * @param byte A byte of the text: any byte of a code point past ASCII is never a word character.
 * @return True for a word character.
 */
is_word :: fn(byte: u8) -> bool {
    return (byte >= cast[u8]('0') && byte <= cast[u8]('9')) || (byte >= cast[u8]('A') && byte <= cast[u8]('Z'))
        || (byte >= cast[u8]('a') && byte <= cast[u8]('z')) || byte == cast[u8]('_')
}

/**
 * Hand out a thread's slots: a block of slot_count in the store, every slot not set yet.
 *
 * @param vm The run's state; a block given back is used again, otherwise the store grows. Without the memory, calls
 *     context.assertion_handler.
 * @return Where the block starts in the store.
 */
new_slots :: fn(vm: ptr[mut VM]) -> usize {
    block := cast[usize](0)
    if vm.free_slots.count > 0 {
        block = runtime.pop(&vm.free_slots)
    }
    else {
        block = vm.store.count
        for i in 0..<vm.slot_count {
            runtime.array_add(&vm.store, NO_SLOT)
        }
    }
    for i in 0..<vm.slot_count {
        if block + i < vm.store.count {
            vm.store[block + i] = NO_SLOT
        }
    }
    return block
}

/**
 * Give back a thread's slots, to be handed out again.
 *
 * @param vm The run's state. Without the memory to note it, calls context.assertion_handler.
 * @param block Where the block starts; it mustn't be used after.
 */
release :: fn(vm: ptr[mut VM], block: usize) {
    runtime.array_add(&vm.free_slots, block)
}

/**
 * Copy one thread's slots over another's.
 *
 * @param vm The run's state, whose store holds both blocks; only the block at to changes, and slots past the store's
 *     end are skipped.
 * @param from Where the block copied starts.
 * @param to Where the block written starts.
 */
copy_slots :: fn(vm: ptr[mut VM], from: usize, to: usize) {
    for i in 0..<vm.slot_count {
        if from + i < vm.store.count && to + i < vm.store.count {
            vm.store[to + i] = vm.store[from + i]
        }
    }
}

/**
 * Set one of a thread's slots.
 *
 * @param vm The run's state, whose store holds the block; only that one slot changes.
 * @param block Where the thread's block starts.
 * @param index Which slot, less than slot_count; one past it is ignored.
 * @param value The byte offset to keep.
 */
set_slot :: fn(vm: ptr[mut VM], block: usize, index: usize, value: usize) {
    if index < vm.slot_count && block + index < vm.store.count {
        vm.store[block + index] = value
    }
}

/**
 * Read one of a thread's slots.
 *
 * @param vm The run's state, only read.
 * @param block Where the thread's block starts.
 * @param index Which slot, from 0: a group's start is slot 2n, its end 2n + 1.
 * @return The byte offset kept there; NO_SLOT if it isn't set, or index is past slot_count.
 */
slot :: fn(vm: ptr[VM], block: usize, index: usize) -> usize {
    return if index < vm.slot_count && block + index < vm.store.count { vm.store[block + index] } else { NO_SLOT }
}

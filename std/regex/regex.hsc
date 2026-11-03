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
 * Matches are leftmost-first, as Perl's and RE2's are: the earliest start, and at it, the alternative and repetition the
 * pattern prefers.
 *
 *     pattern := regex.compile("(\\w+)@(\\w+)\\.com")?
 *     defer regex.free(&pattern)
 *     found :: regex.find(&pattern, text) or_return ...        // found.start, found.end
 *     groups : regex.Span[3]
 *     regex.captures(&pattern, text, groups[0..<3])            // groups[1], groups[2]
 */

// The most a counted repetition repeats, and the most instructions a program has.
MAX_REPEAT :: 1000
MAX_INSTRUCTIONS :: 100_000

Span :: struct {
    start : usize,
    end : usize,
}

ErrorKind :: enum {
    // A ( without its ), or a ) without its (
    UnmatchedParenthesis,
    // A [ without its ]
    UnclosedClass,
    // *, +, ? or {n,m} with nothing to repeat
    NothingToRepeat,
    // A {n,m} that isn't one, or past MAX_REPEAT
    BadRepeat,
    // A \ at the end, or before what can't be escaped
    BadEscape,
    // A range whose end comes before its start
    BadRange,
    // More instructions than MAX_INSTRUCTIONS
    TooBig,
    NoMemory,
}

RegexError :: struct {
    kind : ErrorKind,
    // The pattern's byte where it was found
    at : usize,
}

Opcode :: enum {
    // A code point within one of the class's ranges (or outside all of them, if it's negated)
    Class,
    Any,
    // Go on at first, and at second, preferring first
    Split,
    Jump,
    // Keep where the text is, in a capture slot
    Save,
    AssertStart,
    AssertEnd,
    WordBoundary,
    NotWordBoundary,
    Match,
}

Instruction :: struct {
    opcode : Opcode,
    first : usize,
    second : usize,
    // A class's ranges, in ranges, and whether it's negated and ignores case
    ranges_start : usize,
    ranges_count : usize,
    negated : bool,
    folded : bool,
}

Range :: struct {
    low : u32,
    high : u32,
}

Regex :: struct {
    program : Instruction[..],
    ranges : Range[..],
    // Groups, the whole match counted: each has two slots
    groups : usize,
}

Flags :: struct {
    ignore_case : bool,
}

// A pattern compiled.
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

free :: fn(pattern: ptr[mut Regex]) {
    runtime.array_free(&pattern.program)
    runtime.array_free(&pattern.ranges)
}

// Whether the pattern matches anywhere in text.
is_match :: fn(pattern: ptr[Regex], text: string) -> bool {
    return find(pattern, text) is_some
}

// The leftmost-first match in text, from from on.
find :: fn(pattern: ptr[Regex], text: string, from: usize = 0) -> Span? {
    spans : Span[1]
    if !run(pattern, string_bytes(text), from, spans[0..<1]) {
        return null
    }
    return spans[0]
}

/*
 * The leftmost-first match from from on, and its groups' spans into groups, as many as fit: group 0 the whole match, a
 * group that didn't take part an empty span at the text's end. Whether there was one.
 */
captures :: fn(pattern: ptr[Regex], text: string, groups: mut Span[], from: usize = 0) -> bool {
    return run(pattern, string_bytes(text), from, groups)
}

// How many groups the pattern has, the whole match counted.
group_count :: fn(pattern: ptr[Regex]) -> usize {
    return pattern.groups
}

// ---- Parsing, by recursive descent, straight to the program

Parser :: struct #scoped {
    text : u8[],
    at : usize,
    regex : ptr[mut Regex],
    groups : usize,
    fold : bool,
    error : RegexError?,
    depth : usize,
}

fail :: fn(parser: ptr[mut Parser], kind: ErrorKind) {
    if (parser.error is_none) {
        parser.error = RegexError.{kind = kind, at = parser.at}
    }
}

emit :: fn(parser: ptr[mut Parser], instruction: Instruction) -> usize {
    at :: parser.regex.program.count
    if at >= MAX_INSTRUCTIONS {
        fail(parser, .TooBig)
        return at
    }
    runtime.array_add(&parser.regex.program, instruction)
    return at
}

peek :: fn(parser: ptr[Parser]) -> u8 {
    return if parser.at < parser.text.count { parser.text[parser.at] } else { 0 }
}

// The byte after the next, or 0.
peek_after :: fn(parser: ptr[Parser]) -> u8 {
    at :: parser.at + 1
    return if at < parser.text.count { parser.text[at] } else { 0 }
}

/*
 * x|y|...: the first alternative with a split before it, to it or past it, and a jump after it past the rest, which is
 * itself an alternation.
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

set_second :: fn(parser: ptr[mut Parser], at: usize, target: usize) {
    if at < parser.regex.program.count {
        parser.regex.program[at].second = target
    }
}

// An instruction put in at at, those after it moved along, and every target past it moved with them.
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

// A sequence of repeated atoms, up to | or ) or the end.
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

// An atom, and its repetition if one follows.
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

lazy_follows :: fn(parser: ptr[mut Parser]) -> bool {
    if peek(parser) == cast[u8]('?') {
        parser.at += 1
        return true
    }
    return false
}

// What starts at start, any number of times: a split before it, a jump back after.
star :: fn(parser: ptr[mut Parser], start: usize, lazy: bool) {
    insert(parser, start, Instruction.{opcode = .Split})
    emit(parser, Instruction.{opcode = .Jump, first = start})
    after :: parser.regex.program.count
    prefer(parser, start, start + 1, after, lazy)
}

// Once, then any number of times: a split after it, back to it.
plus :: fn(parser: ptr[mut Parser], start: usize, lazy: bool) {
    split :: emit(parser, Instruction.{opcode = .Split})
    prefer(parser, split, start, split + 1, lazy)
}

// Once or not at all: a split before it.
optional :: fn(parser: ptr[mut Parser], start: usize, lazy: bool) {
    insert(parser, start, Instruction.{opcode = .Split})
    after :: parser.regex.program.count
    prefer(parser, start, start + 1, after, lazy)
}

// A split's two ways, the repeating one first unless it's lazy.
prefer :: fn(parser: ptr[mut Parser], split: usize, repeat: usize, leave: usize, lazy: bool) {
    if split < parser.regex.program.count {
        parser.regex.program[split] = Instruction.{opcode = .Split, first = if lazy { leave } else { repeat }, second = if lazy { repeat } else { leave }}
    }
}

/*
 * {n}, {n,}, {n,m}: the atom's code, from start to end, copied: n times, then m - n optional ones, or any number for
 * {n,}.
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

// A copy of code that was at from appended, its targets moved to where it is now.
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

// One atom: a group, a class, ., an anchor, an escape, or a code point.
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

// A class of one code point.
single :: fn(parser: ptr[mut Parser], point: u32) {
    start :: parser.regex.ranges.count
    runtime.array_add(&parser.regex.ranges, Range.{low = point, high = point})
    emit(parser, Instruction.{opcode = .Class, ranges_start = start, ranges_count = 1, folded = parser.fold})
}

// (x), (?:x), or (?i) on its own.
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

// \d \w \s and their negations, \b \B, and escaped characters.
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

// \d \w \s's ranges added, or \D \W \S's: whether they're negated, or null for another escape.
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

// The code point an escape stands for: \n \t \r, or one of the characters that mean something unescaped.
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

// [ranges], or [^ranges]: code points, a-b ranges, and \d \w \s within.
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

// A thread: where it is in the program, and its capture slots, in the VM's slot store.
Thread :: struct {
    pc : usize,
    slots : usize,
}

// The threads at one position, in priority order, each place in the program at most once.
ThreadList :: struct {
    threads : Thread[..],
    // For each place in the program, the generation it was last added in, which makes it there once per step
    seen : u64[..],
}

// What a run reads: the program, its classes' ranges, and the text.
Input :: struct #scoped {
    program : Instruction[],
    ranges : Range[],
    text : u8[],
}

VM :: struct {
    slot_count : usize,
    // Slots for every thread, slot_count each, handed out and given back
    store : usize[..],
    free_slots : usize[..],
    generation : u64,
}

// The leftmost-first match from from on, its groups' spans into groups: whether there was one.
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

NO_SLOT : usize : 0xffffffffffffffff

free_list :: fn(list: ptr[mut ThreadList]) {
    runtime.array_free(&list.threads)
    runtime.array_free(&list.seen)
}

/*
 * A thread at pc added to list, at position at, following jumps, splits (the first way first) and saves, and checking
 * assertions, so list holds only threads at instructions that consume or match.
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

// Whether an instruction that consumes takes point.
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

in_ranges :: fn(input: ptr[Input], instruction: Instruction, point: u32) -> bool {
    for i in 0..<instruction.ranges_count {
        index :: instruction.ranges_start + i
        if index < input.ranges.count && point >= input.ranges[index].low && point <= input.ranges[index].high {
            return true
        }
    }
    return false
}

is_word :: fn(byte: u8) -> bool {
    return (byte >= cast[u8]('0') && byte <= cast[u8]('9')) || (byte >= cast[u8]('A') && byte <= cast[u8]('Z'))
        || (byte >= cast[u8]('a') && byte <= cast[u8]('z')) || byte == cast[u8]('_')
}

// A thread's slots: a block of slot_count in the store, every slot not set yet.
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

release :: fn(vm: ptr[mut VM], block: usize) {
    runtime.array_add(&vm.free_slots, block)
}

copy_slots :: fn(vm: ptr[mut VM], from: usize, to: usize) {
    for i in 0..<vm.slot_count {
        if from + i < vm.store.count && to + i < vm.store.count {
            vm.store[to + i] = vm.store[from + i]
        }
    }
}

set_slot :: fn(vm: ptr[mut VM], block: usize, index: usize, value: usize) {
    if index < vm.slot_count && block + index < vm.store.count {
        vm.store[block + index] = value
    }
}

slot :: fn(vm: ptr[VM], block: usize, index: usize) -> usize {
    return if index < vm.slot_count && block + index < vm.store.count { vm.store[block + index] } else { NO_SLOT }
}

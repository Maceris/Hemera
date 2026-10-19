package runtime

/*
 * Options in a format string (docs/format_strings.md): % or %2 can be followed by {...}, like
 * %{08x} or %2{>10}. The formatters in base and std, output_format and text_buffer's append_format,
 * read and apply them here, so a format string means the same in each:
 *
 *     %[n]{[[fill]align][+][#][0][width][.precision][kind]}
 *
 * align is < (left), > (right) or ^ (centered); + gives numbers a sign either way; # prefixes 0x, 0b
 * or 0o; 0 pads a number with zeros after its sign and prefix; precision is a float's decimals, or
 * how much of a string to keep; kind is d, x, X, b or o, for integers, characters, enums, booleans
 * and pointers.
 */
FormatSpec :: struct {
    fill : u8,
    // < > or ^, or 0 for the value's own: numbers to the right, everything else to the left
    align : u8,
    plus : bool,
    prefix : bool,
    zeros : bool,
    width : usize,
    has_precision : bool,
    precision : usize,
    // d x X b o, or 0 for the value's own way
    kind : u8,
}

// Where formatted bytes go: a buffer, and a function that adds one byte to it.
FormatSink :: struct {
    target : rawptr,
    emit : fn(target: rawptr, byte: u8),
}

is_format_alignment #no_context :: fn(character: char) -> bool {
    return character == '<' || character == '>' || character == '^'
}

is_format_kind #no_context :: fn(character: char) -> bool {
    return character == 'd' || character == 'x' || character == 'X' || character == 'b' || character == 'o'
}

is_format_digit #no_context :: fn(character: char) -> bool {
    return character >= '0' && character <= '9'
}

/*
 * The options in format at start, just after the placeholder: {...}, or none. Gives them, where the
 * format goes on after them, and whether they were well formed; when they aren't, what follows
 * starts after the closing brace, if there is one.
 */
parse_format_spec #no_context :: fn(format: string, start: usize) -> (FormatSpec, usize, bool) {
    spec : FormatSpec
    spec.fill = cast[u8](' ')
    if start >= format.count || format[start] != '{' {
        return spec, start, true
    }
    index := start + 1
    // A fill and an alignment, or an alignment alone
    if index + 1 < format.count && is_format_alignment(format[index + 1]) {
        spec.fill = cast[u8](format[index])
        spec.align = cast[u8](format[index + 1])
        index += 2
    }
    else if index < format.count && is_format_alignment(format[index]) {
        spec.align = cast[u8](format[index])
        index += 1
    }
    if index < format.count && format[index] == '+' {
        spec.plus = true
        index += 1
    }
    if index < format.count && format[index] == '#' {
        spec.prefix = true
        index += 1
    }
    if index < format.count && format[index] == '0' {
        spec.zeros = true
        index += 1
    }
    for step in 0..<format.count {
        if index >= format.count || !is_format_digit(format[index]) {
            break
        }
        spec.width = spec.width * 10 + cast[usize](format[index]) - cast[usize]('0')
        index += 1
    }
    valid := true
    if index < format.count && format[index] == '.' {
        index += 1
        spec.has_precision = true
        valid = index < format.count && is_format_digit(format[index])
        for step in 0..<format.count {
            if index >= format.count || !is_format_digit(format[index]) {
                break
            }
            spec.precision = spec.precision * 10 + cast[usize](format[index]) - cast[usize]('0')
            index += 1
        }
    }
    if index < format.count && is_format_kind(format[index]) {
        spec.kind = cast[u8](format[index])
        index += 1
    }
    if valid && index < format.count && format[index] == '}' {
        return spec, index + 1, true
    }
    // Not well formed: what follows is after the closing brace
    for step in 0..<format.count {
        if index >= format.count {
            break
        }
        index += 1
        if format[index - 1] == '}' {
            break
        }
    }
    return spec, index, false
}

format_emit_text :: fn(sink: FormatSink, text: string) {
    for character in text {
        sink.emit(sink.target, cast[u8](character))
    }
}

format_emit_repeated :: fn(sink: FormatSink, byte: u8, count: usize) {
    for step in 0..<count {
        sink.emit(sink.target, byte)
    }
}

/*
 * sign, prefix and body, made spec's width: for a number with 0 and no alignment, zeros between its
 * prefix and body; otherwise the fill on the side its alignment says.
 */
format_padded :: fn(sink: FormatSink, spec: FormatSpec, sign: string, prefix: string, body: string, numeric: bool) {
    length :: sign.count + prefix.count + body.count
    padding :: if spec.width > length { spec.width - length } else { 0 }
    if numeric && spec.zeros && spec.align == 0 {
        format_emit_text(sink, sign)
        format_emit_text(sink, prefix)
        format_emit_repeated(sink, cast[u8]('0'), padding)
        format_emit_text(sink, body)
        return void
    }
    align :: if spec.align != 0 { spec.align } else if numeric { cast[u8]('>') } else { cast[u8]('<') }
    before :: if align == cast[u8]('>') { padding } else if align == cast[u8]('^') { padding / 2 } else { 0 }
    format_emit_repeated(sink, spec.fill, before)
    format_emit_text(sink, sign)
    format_emit_text(sink, prefix)
    format_emit_text(sink, body)
    format_emit_repeated(sink, spec.fill, padding - before)
}

// Text, cut to spec's precision when it has one, and padded.
format_text :: fn(sink: FormatSink, spec: FormatSpec, text: string) {
    kept := text
    if spec.has_precision && spec.precision < text.count && text.count > 0 {
        kept = string_of(cast[ptr[u8]](text.data), spec.precision)
    }
    format_padded(sink, spec, "", "", kept, false)
}

FORMAT_DIGITS :: "0123456789abcdef0123456789ABCDEF"

/*
 * An integer, negative or not, of magnitude, in the base spec's kind says (decimal by default),
 * with its sign, prefix and padding.
 */
format_integer :: fn(sink: FormatSink, spec: FormatSpec, negative: bool, magnitude: u64) {
    kind :: spec.kind
    base : u64 = if kind == cast[u8]('x') || kind == cast[u8]('X') { 16 } else if kind == cast[u8]('b') { 2 } else if kind == cast[u8]('o') { 8 } else { 10 }
    upper : usize = if kind == cast[u8]('X') { 16 } else { 0 }
    // Collected lowest first, from the end
    digits : u8[64]
    start : usize = digits.count
    rest := magnitude
    for step in 0..<digits.count {
        if start == 0 {
            break
        }
        start -= 1
        digits[start] = cast[u8](FORMAT_DIGITS[cast[usize](rest % base) % 16 + upper])
        rest /= base
        if rest == 0 {
            break
        }
    }
    sign :: if negative { "-" } else if spec.plus { "+" } else { "" }
    prefix :: if !spec.prefix || base == 10 { "" } else if base == 16 { "0x" } else if base == 2 { "0b" } else { "0o" }
    body :: if start < digits.count { string_of(&digits[start], digits.count - start) } else { "" }
    format_padded(sink, spec, sign, prefix, body, true)
}

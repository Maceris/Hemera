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

/*
 * Unsigned integers of up to 1280 bits, in 32-bit limbs, lowest first: enough for a double's scaled value, its gaps and
 * the power of ten they're measured against, as append_shortest_bits needs them.
 */
FORMAT_WIDE_LIMBS :: 40
FormatWide :: struct {
    limbs : u32[FORMAT_WIDE_LIMBS],
}

format_wide_of :: fn(value: u64) -> FormatWide {
    result : FormatWide
    result.limbs[0] = cast[u32](value & 0xffffffff)
    result.limbs[1] = cast[u32](value >> 32)
    return result
}

// number × factor, a small one like 2 or 10.
format_wide_times :: fn(number: ptr[mut FormatWide], factor: u64) {
    carry : u64 = 0
    for &limb in number.limbs {
        product :: cast[u64](limb^) * factor + carry
        limb^ = cast[u32](product & 0xffffffff)
        carry = product >> 32
    }
    assert(carry == 0, "a float's digits fit in 1280 bits")
}

format_wide_shift :: fn(number: ptr[mut FormatWide], bits: u64) {
    for step in 0..<bits {
        format_wide_times(number, 2)
    }
}

format_wide_add :: fn(a: FormatWide, b: FormatWide) -> FormatWide {
    result : FormatWide
    carry : u64 = 0
    for limb, index in a.limbs {
        sum :: cast[u64](limb) + cast[u64](b.limbs[index]) + carry
        result.limbs[index] = cast[u32](sum & 0xffffffff)
        carry = sum >> 32
    }
    return result
}

// a - b, which a is at least.
format_wide_subtract :: fn(a: ptr[mut FormatWide], b: FormatWide) {
    borrow : u64 = 0
    for &limb, index in a.limbs {
        taken :: cast[u64](b.limbs[index]) + borrow
        if cast[u64](limb^) >= taken {
            limb^ = cast[u32](cast[u64](limb^) - taken)
            borrow = 0
        }
        else {
            limb^ = cast[u32]((cast[u64](limb^) + 0x100000000) - taken)
            borrow = 1
        }
    }
}

// -1, 0 or 1 as a is less than, equal to or more than b.
format_wide_compare :: fn(a: FormatWide, b: FormatWide) -> int {
    for limb, index in a.limbs #reverse {
        if limb != b.limbs[index] {
            return if limb < b.limbs[index] { -1 } else { 1 }
        }
    }
    return 0
}

/*
 * An IEEE 754 binary float's bits as the shortest decimal that reads back as it, rounding to nearest with ties to even:
 * its digits by Steele and White's free-format method, as Dragon4 (a decimal digit at a time from the exact value and
 * the gaps to its neighbours, in wide integers), so no floating-point code is needed. Written as C++'s to_chars writes
 * one: in fixed notation, like 0.001, 1.5 or 123456, unless scientific is shorter, like 1e-04 or 1e+21, with two digits
 * of exponent at least.
 */
//SPEC: Steele and White, "How to Print Floating-Point Numbers Accurately" (PLDI 1990), FPP2
format_shortest_float :: fn(sink: FormatSink, bits: u64, exponent_bits: u64, fraction_bits: u64) {
    one : u64 = 1
    exponent_mask :: (one << exponent_bits) - 1
    biased :: (bits >> fraction_bits) & exponent_mask
    fraction :: bits & ((one << fraction_bits) - 1)
    negative :: (bits >> (exponent_bits + fraction_bits)) & 1 == 1
    if biased == exponent_mask && fraction != 0 {
        format_emit_text(sink, "nan")
        return void
    }
    if negative {
        sink.emit(sink.target, cast[u8]('-'))
    }
    if biased == exponent_mask {
        format_emit_text(sink, "inf")
        return void
    }
    if biased == 0 && fraction == 0 {
        sink.emit(sink.target, cast[u8]('0'))
        return void
    }
    // The value is mantissa × 2^exponent; subnormals have no implicit leading 1
    bias :: cast[i64](exponent_mask >> 1)
    mantissa := fraction
    exponent := 1 - bias - cast[i64](fraction_bits)
    if biased != 0 {
        mantissa |= one << fraction_bits
        exponent = cast[i64](biased) - bias - cast[i64](fraction_bits)
    }
    // Reading back rounds ties to even, so an even mantissa's neighbours' midpoints read back as it too
    even :: mantissa & 1 == 0
    // A power of two's gap below is half its gap above
    unequal :: fraction == 0 && biased > 1
    // value = r / s, and the gaps to its neighbours' midpoints m_plus / s and m_minus / s, all doubled so they're whole
    r := format_wide_of(mantissa)
    s := format_wide_of(1)
    m_plus := format_wide_of(1)
    m_minus := format_wide_of(1)
    doubled : u64 = if unequal { 2 } else { 1 }
    if exponent >= 0 {
        format_wide_shift(&r, cast[u64](exponent) + doubled)
        s = format_wide_of(if unequal { cast[u64](4) } else { cast[u64](2) })
        format_wide_shift(&m_minus, cast[u64](exponent))
        m_plus = m_minus
        if unequal {
            format_wide_shift(&m_plus, 1)
        }
    }
    else {
        format_wide_shift(&r, doubled)
        format_wide_shift(&s, cast[u64](0 - exponent) + doubled)
        if unequal {
            m_plus = format_wide_of(2)
        }
    }
    // The decimal exponent k, value < 10^k, from log10(2) ≈ 1233 / 4096, then fixed up by a power of ten either way
    length : i64 = 0
    with {
        rest := mantissa
    }
    loop {
        rest >>= 1
        length += 1
    }
    while rest != 0
    k := ((exponent + length - 1) * 1233) >> 12
    if k >= 0 {
        for step in 0..<cast[u64](k) {
            format_wide_times(&s, 10)
        }
    }
    else {
        for step in 0..<cast[u64](0 - k) {
            format_wide_times(&r, 10)
            format_wide_times(&m_plus, 10)
            format_wide_times(&m_minus, 10)
        }
    }
    loop {
        high :: format_wide_compare(format_wide_add(r, m_plus), s)
        if high > 0 || (even && high == 0) {
            format_wide_times(&s, 10)
            k += 1
            continue
        }
        break
    }
    // And down, while 10^(k - 1) is already past what reads back as the value
    loop {
        tenfold := format_wide_add(r, m_plus)
        format_wide_times(&tenfold, 10)
        below :: format_wide_compare(tenfold, s)
        if below < 0 || (!even && below == 0) {
            format_wide_times(&r, 10)
            format_wide_times(&m_plus, 10)
            format_wide_times(&m_minus, 10)
            k -= 1
            continue
        }
        break
    }
    // Digits, a decimal one at a time, until what's left is within a gap, then the last rounded
    digits : u8[24]
    count : usize = 0
    loop {
        format_wide_times(&r, 10)
        format_wide_times(&m_plus, 10)
        format_wide_times(&m_minus, 10)
        digit : u8 = 0
        loop {
            format_wide_subtract(&r, s)
            digit += 1
        }
        while format_wide_compare(r, s) >= 0
        low_compared :: format_wide_compare(r, m_minus)
        low :: low_compared < 0 || (even && low_compared == 0)
        high_compared :: format_wide_compare(format_wide_add(r, m_plus), s)
        high :: high_compared > 0 || (even && high_compared == 0)
        if low || high {
            // Within both gaps, the nearer digit, and at a tie, the even one
            twice := r
            format_wide_times(&twice, 2)
            nearer :: format_wide_compare(twice, s)
            if high && (!low || nearer > 0 || (nearer == 0 && digit % 2 == 1)) {
                digit += 1
            }
        }
        if count < digits.count {
            digits[count] = cast[u8]('0') + digit
            count += 1
        }
        if low || high {
            break
        }
    }
    format_digits_shortest(sink, view_of(&digits[0], count), k)
}

/*
 * Decimal digits d1 d2 ... dn, the value 0.d1d2...dn × 10^k, in fixed notation, unless scientific, d1.d2...dne±XX, is
 * shorter, as C++'s to_chars does it.
 */
format_digits_shortest :: fn(sink: FormatSink, digits: u8[], k: i64) {
    count :: cast[i64](digits.count)
    exponent :: k - 1
    magnitude :: if exponent < 0 { 0 - exponent } else { exponent }
    fixed_length :: if k <= 0 { 2 - k + count } else if k >= count { k } else { count + 1 }
    point : i64 = if count > 1 { 1 } else { 0 }
    exponent_digits : i64 = if magnitude >= 100 { 3 } else { 2 }
    scientific_length :: count + point + 2 + exponent_digits
    if fixed_length <= scientific_length {
        if k <= 0 {
            format_emit_text(sink, "0.")
            for zero in 0..<cast[u64](0 - k) {
                sink.emit(sink.target, cast[u8]('0'))
            }
            for digit in digits {
                sink.emit(sink.target, digit)
            }
        }
        else {
            for digit, index in digits {
                if cast[i64](index) == k {
                    sink.emit(sink.target, cast[u8]('.'))
                }
                sink.emit(sink.target, digit)
            }
            for zero in count..<k {
                sink.emit(sink.target, cast[u8]('0'))
            }
        }
        return void
    }
    for digit, index in digits {
        sink.emit(sink.target, digit)
        if index == 0 && digits.count > 1 {
            sink.emit(sink.target, cast[u8]('.'))
        }
    }
    format_emit_text(sink, if exponent < 0 { "e-" } else { "e+" })
    if magnitude >= 100 {
        sink.emit(sink.target, cast[u8]('0') + cast[u8](magnitude / 100))
    }
    sink.emit(sink.target, cast[u8]('0') + cast[u8](magnitude / 10 % 10))
    sink.emit(sink.target, cast[u8]('0') + cast[u8](magnitude % 10))
}

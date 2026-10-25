package text_buffer

import compiler from "base"
import runtime from "base"
import reflection from "std"

/*
 * Formatting values into a TextBuffer, the way loggers format their parameters, without
 * allocating.
 *
 *     append_format(&text, "% of % pages free", free, total)
 */

FORMAT_PLACEHOLDER : char : '%'

/*
 * format_string, with each % replaced by the next value, formatted by append_value. %1, %2 and so on
 * are the first, second... value instead, and %% is a %. Each can have options, like %{08x} or
 * %2{>10} (docs/format_strings.md). A placeholder without a value, or with options that aren't well
 * formed, is written as %!, and values left over are ignored.
 */
append_format :: fn(text: ptr[mut TextBuffer], format_string: string, values: any...) {
    next : usize = 0
    index : usize = 0
    for step in 0..<format_string.count + 1 {
        if index >= format_string.count {
            break
        }
        character :: format_string[index]
        index += 1
        if character != FORMAT_PLACEHOLDER {
            append_byte(text, cast[u8](character))
            continue
        }
        if index < format_string.count && format_string[index] == FORMAT_PLACEHOLDER {
            append_byte(text, cast[u8](FORMAT_PLACEHOLDER))
            index += 1
            continue
        }
        // %1, %2...: a value by its number
        number : usize = 0
        has_number := false
        for digit in 0..<format_string.count {
            if index >= format_string.count || !is_digit(format_string[index]) {
                break
            }
            number = number * 10 + cast[usize](format_string[index]) - cast[usize]('0')
            has_number = true
            index += 1
        }
        spec, after, valid :: runtime.parse_format_spec(format_string, index)
        index = after
        chosen := next
        if !has_number {
            next += 1
        }
        else if number > 0 {
            chosen = number - 1
        }
        else {
            chosen = values.count
        }
        if !valid || chosen >= values.count {
            append(text, "%!")
            continue
        }
        append_value_with(text, values[chosen], spec)
    }
}

text_sink_byte :: fn(target: rawptr, byte: u8) {
    append_byte(cast[ptr[mut TextBuffer]](target), byte)
}

/*
 * A value with options (docs/format_strings.md): integers, and characters, booleans, enums and
 * pointers as numbers, worked out with them; floats with their precision as decimals, or without one, as
 * the shortest text that reads back as the same value; anything else
 * as append_value writes it, then padded.
 */
append_value_with :: fn(text: ptr[mut TextBuffer], value: any, spec: runtime.FormatSpec) {
    if runtime.is_plain_format(spec) {
        append_value(text, value)
        return void
    }
    sink :: runtime.FormatSink.{target = cast[rawptr](text), emit = text_sink_byte}
    given :: type_info_of(value.type)
    if cast[rawptr](given) != null {
        info :: reflection.unaliased(given)
        data :: value.data
        variant :: info.variant
        numeric :: spec.kind != 0 && (variant == .CHAR || variant == .BOOLEAN || variant == .ENUM)
        if variant == .INTEGER && info.size <= 8 && cast[ptr[compiler.TypeInfoInteger]](info).is_signed {
            signed :: runtime.read_signed(data, info.size)
            runtime.format_integer(sink, spec, signed < 0, if signed < 0 { 0 - cast[u64](signed) } else { cast[u64](signed) })
            return void
        }
        if (variant == .INTEGER && info.size <= 8) || numeric {
            runtime.format_integer(sink, spec, false, cast[u64](reflection.read_unsigned(data, info.size)))
            return void
        }
        if (variant == .POINTER || variant == .FUNCTION) && cast[ptr[u64]](data)^ != 0 {
            // An address: in hexadecimal unless another kind is asked for, with 0x when it's the default
            with_kind := spec
            if with_kind.kind == 0 {
                with_kind.kind = cast[u8]('x')
                with_kind.prefix = true
            }
            runtime.format_integer(sink, with_kind, false, cast[ptr[u64]](data)^)
            return void
        }
        if variant == .STRING && !cast[ptr[compiler.TypeInfoString]](info).is_raw {
            runtime.format_text(sink, spec, cast[ptr[string]](data)^)
            return void
        }
        if variant == .FLOAT {
            // Its digits, then the sign split off, so zeros go after it
            storage : u8[64]
            digits := make(storage)
            // The shortest text that reads back as the same value, or a precision's decimals
            if !spec.has_precision {
                append_float_data(&digits, data, info.size)
            }
            else if info.size == 2 {
                append_float_bits(&digits, cast[u64](cast[ptr[u16]](data)^), 5, 10, spec.precision)
            }
            else if info.size == 4 {
                append_float_bits(&digits, cast[u64](cast[ptr[u32]](data)^), 8, 23, spec.precision)
            }
            else {
                append_float_bits(&digits, cast[ptr[u64]](data)^, 11, 52, spec.precision)
            }
            written :: as_string(&digits)
            negative :: written.count > 0 && written[0] == '-'
            sign :: if negative { "-" } else if spec.plus { "+" } else { "" }
            body :: if negative { strings_after(written, 1) } else { written }
            runtime.format_padded(sink, spec, sign, "", body, true)
            return void
        }
    }
    // Anything else, written as usual, then padded
    storage : u8[256]
    scratch := make(storage)
    append_value(&scratch, value)
    runtime.format_text(sink, spec, as_string(&scratch))
}

// text without its first start bytes.
strings_after :: fn(text: string, start: usize) -> string {
    if start >= text.count || text.count == 0 {
        return ""
    }
    return string_of(cast[ptr[u8]](text.data + start), text.count - start)
}

is_digit :: fn(character: char) -> bool {
    return character >= '0' && character <= '9'
}

/*
 * value as text: numbers in decimal, strings and characters as they are, enum members by name,
 * pointers as addresses, structs as Name{member = value, ...}, arrays as [a, b, ...], optionals as
 * their value or none, other unions as Variant(values), and types by name. Pointers aren't
 * followed.
 */
append_value :: fn(text: ptr[mut TextBuffer], value: any) {
    info :: type_info_of(value.type)
    // A zeroed any, with no value
    if cast[rawptr](info) == null {
        append(text, "<nothing>")
        return void
    }
    append_data(text, value.data, info)
}

// The value of the type info describes at data.
append_data :: fn(text: ptr[mut TextBuffer], data: rawptr, type_info: ptr[compiler.TypeInfo]) {
    info :: reflection.unaliased(type_info)
    variant :: info.variant
    if variant == .INTEGER {
        integer_info :: cast[ptr[compiler.TypeInfoInteger]](info)
        append_integer(text, data, info.size, integer_info.is_signed)
    }
    else if variant == .BOOLEAN {
        if reflection.read_unsigned(data, info.size) != 0 {
            append(text, "true")
        }
        else {
            append(text, "false")
        }
    }
    else if variant == .CHAR {
        character :: cast[ptr[u8]](data)
        append_byte(text, character^)
    }
    else if variant == .STRING {
        append_string(text, data, cast[ptr[compiler.TypeInfoString]](info).is_raw)
    }
    else if variant == .ENUM {
        append_enum(text, data, cast[ptr[compiler.TypeInfoEnum]](info))
    }
    else if variant == .FLOAT {
        append_float_data(text, data, info.size)
    }
    else if variant == .POINTER || variant == .FUNCTION {
        address :: cast[ptr[u64]](data)
        if address^ == 0 {
            append(text, "null")
        }
        else {
            append_address(text, address^)
        }
    }
    else if variant == .STRUCT {
        append_struct(text, data, cast[ptr[compiler.TypeInfoStruct]](info))
    }
    else if variant == .ARRAY {
        array_info :: cast[ptr[compiler.TypeInfoArray]](info)
        append_array(text, data, array_info, 0)
    }
    else if variant == .UNION {
        append_union(text, data, cast[ptr[compiler.TypeInfoUnion]](info))
    }
    else if variant == .ANY {
        inner :: cast[ptr[any]](data)
        append_value(text, inner^)
    }
    else if variant == .TYPE {
        described :: cast[ptr[ptr[compiler.TypeInfo]?]](data)
        match described^ {
            case Some(named) => append_type_name(text, named)
            case None => append(text, "null")
        }
    }
    else if variant == .VOID {
        append(text, "void")
    }
    else {
        // Complex numbers and quaternions
        append(text, "<")
        append_type_name(text, info)
        append(text, ">")
    }
}

append_integer :: fn(text: ptr[mut TextBuffer], data: rawptr, size: usize, is_signed: bool) {
    if size == 16 {
        // As two halves in hexadecimal, since there's no 128-bit division here
        low :: cast[ptr[u64]](data)
        high :: cast[ptr[u64]](data + 8)
        append(text, "0x")
        if high^ != 0 {
            append_unsigned(text, high^, 16)
            append_unsigned(text, low^, 16, 16)
        }
        else {
            append_unsigned(text, low^, 16)
        }
        return void
    }
    if !is_signed {
        append_unsigned(text, cast[u64](reflection.read_unsigned(data, size)))
        return void
    }
    signed : i64 = 0
    if size == 1 {
        signed = cast[i64](cast[ptr[i8]](data)^)
    }
    else if size == 2 {
        signed = cast[i64](cast[ptr[i16]](data)^)
    }
    else if size == 4 {
        signed = cast[i64](cast[ptr[i32]](data)^)
    }
    else {
        signed = cast[ptr[i64]](data)^
    }
    append_signed(text, signed)
}

append_string :: fn(text: ptr[mut TextBuffer], data: rawptr, is_raw: bool) {
    if !is_raw {
        view :: cast[ptr[string]](data)
        append(text, view^)
        return void
    }
    // A cstring: bytes up to the first 0
    start :: cast[ptr[rawptr]](data)
    if start^ == null {
        append(text, "null")
        return void
    }
    with {
        index : usize = 0
    }
    loop {
        byte :: cast[ptr[u8]](start^ + index)
        if byte^ == 0 {
            break
        }
        append_byte(text, byte^)
        index += 1
    }
}

// An enum member's name, or the enum's name and the value if it matches no member.
append_enum :: fn(text: ptr[mut TextBuffer], data: rawptr, info: ptr[compiler.TypeInfoEnum]) {
    raw :: reflection.read_unsigned(data, info.size)
    for member_value, index in info.values {
        if member_value == raw && index < info.members.count {
            append(text, info.members[index])
            return void
        }
    }
    append(text, info.name)
    append(text, "(")
    append_unsigned(text, cast[u64](raw))
    append(text, ")")
}

// A float of size bytes at data, as the shortest text that reads back as it (append_shortest_bits).
append_float_data :: fn(text: ptr[mut TextBuffer], data: rawptr, size: usize) {
    if size == 2 {
        append_shortest_bits(text, cast[u64](cast[ptr[u16]](data)^), 5, 10)
    }
    else if size == 4 {
        append_shortest_bits(text, cast[u64](cast[ptr[u32]](data)^), 8, 23)
    }
    else {
        append_shortest_bits(text, cast[ptr[u64]](data)^, 11, 52)
    }
}

DEFAULT_DECIMALS :: 6

/*
 * value with decimals digits after the point (at most 9), rounded. Numbers of more than 20 digits
 * are written as a digit, six more, and an exponent, like 1.500000e+30, cut short rather than
 * rounded.
 *
 * It's worked out from the bits with integer arithmetic only, so it works on targets without
 * floating-point hardware, like kernels built with soft-float.
 */
append_float :: fn(text: ptr[mut TextBuffer], value: f64, decimals: usize = DEFAULT_DECIMALS) {
    append_float_bits(text, bit_cast[u64](value), 11, 52, decimals)
}

// value as the shortest text that reads back as it, like 0.1, 1.5, 100 or 1e+21 (append_shortest_bits).
append_shortest :: fn(text: ptr[mut TextBuffer], value: f64) {
    append_shortest_bits(text, bit_cast[u64](value), 11, 52)
}

// A float's bits as the shortest text that reads back as it, as base's runtime.format_shortest_float writes it.
append_shortest_bits :: fn(text: ptr[mut TextBuffer], bits: u64, exponent_bits: u64, fraction_bits: u64) {
    sink :: runtime.FormatSink.{target = cast[rawptr](text), emit = text_sink_byte}
    runtime.format_shortest_float(sink, bits, exponent_bits, fraction_bits)
}

/*
 * An IEEE 754 binary float's bits: a sign bit, then exponent_bits of exponent, then
 * fraction_bits of fraction.
 */
append_float_bits :: fn(text: ptr[mut TextBuffer], bits: u64, exponent_bits: u64, fraction_bits: u64, decimals: usize) {
    one : u64 = 1
    exponent_mask :: (one << exponent_bits) - 1
    biased :: (bits >> fraction_bits) & exponent_mask
    fraction :: bits & ((one << fraction_bits) - 1)
    negative :: (bits >> (exponent_bits + fraction_bits)) & 1 == 1
    if biased == exponent_mask && fraction != 0 {
        append(text, "nan")
        return void
    }
    if negative {
        append_byte(text, cast[u8]('-'))
    }
    if biased == exponent_mask {
        append(text, "inf")
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
    places :: if decimals < 9 { decimals } else { 9 }
    scale : u64 = 1
    for place in 0..<places {
        scale *= 10
    }
    if exponent >= 0 {
        // A whole number, perhaps far bigger than a u64
        if !append_shifted(text, mantissa, cast[u64](exponent)) {
            append_decimals(text, 0, places)
        }
        return void
    }
    shift := cast[u64](0 - exponent)
    whole : u64 = 0
    rest := mantissa
    if shift < 64 {
        whole = mantissa >> shift
        rest = mantissa & ((one << shift) - 1)
    }
    // Keep rest × scale within 64 bits: dropping bits this far down can't change six decimals
    if shift > 34 {
        drop :: shift - 34
        rest = if drop < 64 { rest >> drop } else { 0 }
        shift = 34
    }
    decimal := (rest * scale + (one << (shift - 1))) >> shift
    if decimal >= scale {
        whole += 1
        decimal -= scale
    }
    append_unsigned(text, whole)
    append_decimals(text, decimal, places)
}

append_decimals :: fn(text: ptr[mut TextBuffer], decimal: u64, places: usize) {
    if places > 0 {
        append_byte(text, cast[u8]('.'))
        append_unsigned(text, decimal, 10, places)
    }
}

/*
 * mantissa × 2^shift, a whole number of up to 1077 bits, in decimal. It's built in 32-bit limbs,
 * lowest first, then divided by 10^9 repeatedly for its digits, nine at a time. Returns whether it
 * was too long, and written with an exponent.
 */
append_shifted :: fn(text: ptr[mut TextBuffer], mantissa: u64, shift: u64) -> bool {
    if shift < 11 {
        append_unsigned(text, mantissa << shift)
        return false
    }
    // A double's mantissa shifted by at most 1074 is at most 1138 bits: 36 limbs, and 40 chunks of nine digits
    limbs : u32[36]
    limbs[0] = cast[u32](mantissa & 0xffffffff)
    limbs[1] = cast[u32](mantissa >> 32)
    used : usize = 2
    with {
        left := shift
    }
    loop {
        runtime.assert(used <= limbs.count, "a double's digits fit in 36 limbs")
        step :: if left < 31 { left } else { 31 }
        carry : u64 = 0
        for index in 0..<used {
            shifted :: (cast[u64](limbs[index]) << step) | carry
            limbs[index] = cast[u32](shifted & 0xffffffff)
            carry = shifted >> 32
        }
        if carry != 0 {
            runtime.assert(used < limbs.count, "a double's digits fit in 36 limbs")
            limbs[used] = cast[u32](carry)
            used += 1
        }
        left -= step
    }
    while left > 0

    // Nine digits at a time, lowest first: each time, every limb divided by 10^9 from the top down
    chunks : u32[40]
    chunk_count : usize = 0
    runtime.assert(used <= limbs.count, "a double's digits fit in 36 limbs")
    loop {
        remainder : u64 = 0
        with {
            index := used
        }
        loop {
            index -= 1
            current :: (remainder << 32) | cast[u64](limbs[index])
            limbs[index] = cast[u32](current / 1000000000)
            remainder = current % 1000000000
        }
        while index > 0
        runtime.assert(chunk_count < chunks.count, "a double's digits fit in 40 chunks")
        chunks[chunk_count] = cast[u32](remainder)
        chunk_count += 1
        loop {
            used -= 1
        }
        while used > 0 && limbs[used - 1] == 0
    }
    while used > 0
    runtime.assert(chunk_count >= 1 && chunk_count <= chunks.count, "a double has from 1 to 40 chunks of digits")

    // Every digit, if there are at most 20
    top :: chunks[chunk_count - 1]
    top_digits := digit_count(cast[u64](top))
    total :: top_digits + (chunk_count - 1) * 9
    if total <= 20 {
        append_unsigned(text, cast[u64](top))
        // The rest, from the one below the top down
        with {
            index := chunk_count - 1
        }
        loop {
            index -= 1
            append_unsigned(text, cast[u64](chunks[index]), 10, 9)
        }
        while index > 0
        return false
    }
    // Otherwise the first seven digits, as d.dddddd, and the exponent: more than 20 digits is at least three chunks
    runtime.assert(chunk_count >= 2, "more than 20 digits are more than two chunks")
    digits : u8[18]
    storage := make(digits)
    append_unsigned(&storage, cast[u64](top))
    append_unsigned(&storage, cast[u64](chunks[chunk_count - 2]), 10, 9)
    append_byte(text, digits[0])
    append_byte(text, cast[u8]('.'))
    for index in 1..<7 {
        append_byte(text, digits[index])
    }
    append(text, "e+")
    append_unsigned(text, cast[u64](total - 1))
    return true
}

digit_count :: fn(value: u64) -> usize {
    count : usize = 1
    with {
        rest := value
    }
    loop {
        rest /= 10
        count += 1
    }
    while rest >= 10
    return count
}

append_struct :: fn(text: ptr[mut TextBuffer], data: rawptr, info: ptr[compiler.TypeInfoStruct]) {
    append(text, info.name)
    append(text, "{")
    for &member, index in info.members {
        if index > 0 {
            append(text, ", ")
        }
        append(text, member.name)
        append(text, " = ")
        append_data(text, data + member.offset, member.member_type)
    }
    append(text, "}")
}

// The array info describes at data, from dimension onwards, as [a, b, ...].
append_array :: fn(text: ptr[mut TextBuffer], data: rawptr, info: ptr[compiler.TypeInfoArray], dimension: usize) {
    if dimension >= info.dimensions.count {
        append_data(text, data, info.base_type)
        return void
    }
    elements := data
    count := info.dimensions[dimension].count
    array_type :: info.dimensions[dimension].type
    if array_type == .VIEW {
        view :: cast[ptr[runtime.ArrayView]](data)
        elements = view.data
        count = view.count
    }
    else if array_type == .DYNAMIC {
        dynamic :: cast[ptr[runtime.ResizableArray]](data)
        elements = dynamic.data
        count = dynamic.count
    }
    element_size :: reflection.dimension_element_size(info, dimension)
    append(text, "[")
    for index in 0..<count {
        if index > 0 {
            append(text, ", ")
        }
        append_array(text, elements + index * element_size, info, dimension + 1)
        if text.truncated {
            break
        }
    }
    append(text, "]")
}

/*
 * An optional as its value or none, a result as its value or Error(error), and other unions as
 * Variant(values).
 */
append_union :: fn(text: ptr[mut TextBuffer], data: rawptr, info: ptr[compiler.TypeInfoUnion]) {
    index : usize = 0
    if info.null_is_none {
        pointer :: cast[ptr[u64]](data)
        if pointer^ == 0 {
            index = 1
        }
    }
    else {
        match info.tag_type {
            case Some(tag) => index = cast[usize](reflection.read_unsigned(data, tag.size))
            case None => {}
        }
    }
    if index >= info.variants.count {
        append(text, info.name)
        append(text, "(<bad tag>)")
        return void
    }
    variant :: &info.variants[index]
    is_optional :: info.variants.count == 2 && info.variants[0].name == "Some" && info.variants[1].name == "None"
    is_result :: info.variants.count == 2 && info.variants[0].name == "Ok" && info.variants[1].name == "Error"
    if is_optional && index == 1 {
        append(text, "none")
        return void
    }
    if (is_optional || is_result) && index == 0 {
        if variant.types.count == 0 {
            append(text, "ok")
        }
        // An offset for each value: a copy of the view, which nothing below changes
        offsets :: variant.offsets
        for value_type, value_index in variant.types {
            if value_index >= offsets.count {
                break
            }
            append_data(text, data + offsets[value_index], value_type)
        }
        return void
    }
    append(text, variant.name)
    if variant.types.count == 0 {
        return void
    }
    append(text, "(")
    offsets :: variant.offsets
    for value_type, value_index in variant.types {
        if value_index >= offsets.count {
            break
        }
        if value_index > 0 {
            append(text, ", ")
        }
        append_data(text, data + offsets[value_index], value_type)
    }
    append(text, ")")
}

// A type's name, the way it's written: int, ptr[mut Point], string[], Color, fn(...).
append_type_name :: fn(text: ptr[mut TextBuffer], type_info: ptr[compiler.TypeInfo]) {
    variant :: type_info.variant
    size :: type_info.size
    if variant == .ALIAS {
        append(text, cast[ptr[compiler.TypeInfoAlias]](type_info).name)
    }
    else if variant == .ENUM {
        append(text, cast[ptr[compiler.TypeInfoEnum]](type_info).name)
    }
    else if variant == .STRUCT {
        append(text, cast[ptr[compiler.TypeInfoStruct]](type_info).name)
    }
    else if variant == .UNION {
        append(text, cast[ptr[compiler.TypeInfoUnion]](type_info).name)
    }
    else if variant == .INTEGER {
        integer_info :: cast[ptr[compiler.TypeInfoInteger]](type_info)
        // The types with the same layout as a fixed-size integer, told apart by their descriptors
        described :: cast[rawptr](type_info)
        if described == cast[rawptr](type_info_of(int)) {
            append(text, "int")
        }
        else if described == cast[rawptr](type_info_of(uint)) {
            append(text, "uint")
        }
        else if described == cast[rawptr](type_info_of(usize)) {
            append(text, "usize")
        }
        else if described == cast[rawptr](type_info_of(uintptr)) {
            append(text, "uintptr")
        }
        else {
            if integer_info.is_signed {
                append(text, "i")
            }
            else {
                append(text, "u")
            }
            append_unsigned(text, cast[u64](size * 8))
            append_endianness(text, integer_info.endianness)
        }
    }
    else if variant == .FLOAT {
        append(text, "f")
        append_unsigned(text, cast[u64](size * 8))
        append_endianness(text, cast[ptr[compiler.TypeInfoFloat]](type_info).endianness)
    }
    else if variant == .BOOLEAN {
        append(text, "bool")
    }
    else if variant == .CHAR {
        append(text, "char")
    }
    else if variant == .STRING {
        if cast[ptr[compiler.TypeInfoString]](type_info).is_raw {
            append(text, "cstring")
        }
        else {
            append(text, "string")
        }
    }
    else if variant == .POINTER {
        pointer_info :: cast[ptr[compiler.TypeInfoPointer]](type_info)
        match pointer_info.base_type {
            case Some(pointed) => {
                append(text, "ptr[")
                if pointer_info.is_mutable {
                    append(text, "mut ")
                }
                append_type_name(text, pointed)
                append(text, "]")
            }
            case None => append(text, "rawptr")
        }
    }
    else if variant == .ARRAY {
        array_info :: cast[ptr[compiler.TypeInfoArray]](type_info)
        append_type_name(text, array_info.base_type)
        for &dimension in array_info.dimensions {
            if dimension.type == .STATIC {
                append(text, "[")
                append_unsigned(text, cast[u64](dimension.count))
                append(text, "]")
            }
            else if dimension.type == .VIEW {
                append(text, "[]")
            }
            else {
                append(text, "[..]")
            }
        }
    }
    else if variant == .FUNCTION {
        append(text, "fn(...)")
    }
    else if variant == .ANY {
        append(text, "any")
    }
    else if variant == .TYPE {
        append(text, "type")
    }
    else if variant == .VOID {
        append(text, "void")
    }
    else if variant == .COMPLEX {
        append(text, "complex")
        append_unsigned(text, cast[u64](size * 8))
    }
    else {
        append(text, "quaternion")
        append_unsigned(text, cast[u64](size * 8))
    }
}

append_endianness :: fn(text: ptr[mut TextBuffer], endianness: compiler.Endianness) {
    if endianness == .BIG {
        append(text, "be")
    }
    else if endianness == .LITTLE {
        append(text, "le")
    }
}

package schema

import runtime from "base"

/*
 * Values written elsewhere (write_value), read back as text by their schemas (write), the way base's output_format
 * writes them where they were: for a log record kept as its format string and its arguments, which is rendered
 * only when it's read. Integers are in decimal, booleans, characters and strings as they are, enum members by name,
 * floats shortest, and other values by their kind, like <struct Name>; options like %{08x} work as they do there. A
 * pointer is written as what it points to, so its address is gone: it's <pointer>, or null. What a schema or a value
 * doesn't hold, because it's cut short or isn't one, is <?>.
 */

/** An argument to render: its schema's bytes, and its value's. */
Argument :: struct {
    /** The argument's type's schema, as schema.write wrote it; borrowed, and only read. */
    schema : u8[],
    /** The argument's value, as write_value wrote it; borrowed, and only read. */
    value : u8[],
}

/**
 * Render a format string with its arguments, as base's formatting would have where they were written.
 *
 * Without the memory, calls context.assertion_handler, as array_add does.
 *
 * @param format_string The text, with each % replaced by the next argument, %1, %2 and so on by that one (which
 *     doesn't move on which is next), and %% by %. Options after one, like %{08x}, work as they do in base's
 *     formatting.
 * @param arguments The arguments, each a schema and a value. A % past the last, %0, or one with options that don't
 *     parse, is written as %!.
 * @param into The array the text is added to, grown with its own allocator; what it held already is left as it is.
 */
render :: fn(format_string: string, arguments: Argument[], into: ptr[mut u8[..]]) {
    next : usize = 0
    index : usize = 0
    loop {
        if index >= format_string.count {
            break
        }
        character :: format_string[index]
        index += 1
        if character != '%' {
            runtime.array_add(into, cast[u8](character))
            continue
        }
        if index < format_string.count && format_string[index] == '%' {
            runtime.array_add(into, cast[u8]('%'))
            index += 1
            continue
        }
        number : usize = 0
        numbered := false
        for step in 0..<format_string.count {
            if index >= format_string.count || !runtime.is_format_digit(format_string[index]) {
                break
            }
            number = number * 10 + cast[usize](format_string[index]) - cast[usize]('0')
            numbered = true
            index += 1
        }
        spec, after, valid :: runtime.parse_format_spec(format_string, index)
        index = after
        chosen := next
        if !numbered {
            next += 1
        }
        else {
            chosen = if number > 0 { number - 1 } else { arguments.count }
        }
        if !valid || chosen >= arguments.count {
            add_text(into, "%!")
            continue
        }
        render_with(into, arguments[chosen], spec)
    }
}

/**
 * Render one argument with options: numbers worked out with them, anything else rendered, then padded.
 *
 * Without the memory, calls context.assertion_handler, as array_add does.
 *
 * @param into The array the text is added to.
 * @param argument The argument's schema and value.
 * @param spec The options, as runtime.parse_format_spec read them; with none, the argument is rendered as it is.
 */
render_with :: fn(into: ptr[mut u8[..]], argument: Argument, spec: runtime.FormatSpec) {
    if spec.width == 0 && spec.kind == 0 && !spec.plus && !spec.prefix && !spec.has_precision {
        render_value(into, argument.schema, first_type(argument.schema), argument.value, 0)
        return void
    }
    sink :: runtime.FormatSink.{target = cast[rawptr](into), emit = sink_byte}
    schema :: argument.schema
    type :: unaliased(schema, first_type(schema))
    if type != NOWHERE {
        kind :: byte_at(schema, type)
        size :: cast[usize](read(schema, type + 1, 8))
        if kind == cast[u8](Kind.Integer) && size <= 8 && fits(argument.value, 0, size) {
            bits :: read(argument.value, 0, size)
            if byte_at(schema, type + 9) != 0 {
                signed :: extend(bits, size)
                runtime.format_integer(sink, spec, signed < 0, if signed < 0 { 0 - cast[u64](signed) } else { cast[u64](signed) })
            }
            else {
                runtime.format_integer(sink, spec, false, bits)
            }
            return void
        }
        numeric :: kind == cast[u8](Kind.Char) || kind == cast[u8](Kind.Boolean) || kind == cast[u8](Kind.Enum)
        if spec.kind != 0 && numeric && size <= 8 && fits(argument.value, 0, size) {
            runtime.format_integer(sink, spec, false, read(argument.value, 0, size))
            return void
        }
        if kind == cast[u8](Kind.String) && byte_at(schema, type + 9) == 0 {
            runtime.format_text(sink, spec, text_of(argument.value, 0))
            return void
        }
    }
    // Anything else, rendered as usual, then padded
    plain : u8[..]
    defer runtime.array_free(&plain)
    render_value(&plain, schema, first_type(schema), argument.value, 0)
    text :: if plain.count > 0 { string_of(cast[ptr[u8]](plain.data), plain.count) } else { "" }
    runtime.format_text(sink, spec, text)
}

/** Where a type's description isn't, or a place that refers to no type: the largest usize, never an offset or place. */
NOWHERE : usize : 0xffffffffffffffff

/** How many aliases deep a type is followed before it's taken as a loop, and as no type. */
ALIAS_LIMIT :: 64

/**
 * Add a byte to an array, as a runtime.FormatSink's emit, for base's formatting to write into.
 *
 * @param target The array, a ptr[mut u8[..]] given as the sink's target; without the memory to grow it, calls
 *     context.assertion_handler.
 * @param byte Any byte, 0 to 255, added as it is.
 */
sink_byte :: fn(target: rawptr, byte: u8) {
    runtime.array_add(cast[ptr[mut u8[..]]](target), byte)
}

/**
 * Add text's bytes to the end of an array. Without the memory, calls context.assertion_handler.
 *
 * @param into The array, grown with its own allocator.
 * @param text The text, copied.
 */
add_text :: fn(into: ptr[mut u8[..]], text: string) {
    for byte in view_of(cast[ptr[u8]](text.data), text.count) {
        runtime.array_add(into, byte)
    }
}

/**
 * Render a value as text, without options, and add it to an array. Without the memory, calls
 * context.assertion_handler.
 *
 * @param into The array the text is added to.
 * @param schema The schema the value was written with, as schema.write wrote it; only read, and not trusted: a type it
 *     doesn't describe whole renders as <?>.
 * @param given Where the value's type is described among them, or NOWHERE; aliases are followed.
 * @param value The written value's bytes, where pointers are distances from its start.
 * @param at Where the value starts in value, in bytes. A type that isn't described, or a value cut short, is <?>.
 */
render_value :: fn(into: ptr[mut u8[..]], schema: u8[], given: usize, value: u8[], at: usize) {
    type :: unaliased(schema, given)
    if type == NOWHERE {
        add_text(into, "<?>")
        return void
    }
    kind :: byte_at(schema, type)
    size :: cast[usize](read(schema, type + 1, 8))
    if !fits(value, at, size) {
        add_text(into, "<?>")
        return void
    }
    if kind == cast[u8](Kind.Integer) && size <= 8 {
        bits :: read(value, at, size)
        if byte_at(schema, type + 9) != 0 {
            signed :: extend(bits, size)
            if signed < 0 {
                runtime.array_add(into, cast[u8]('-'))
            }
            add_unsigned(into, if signed < 0 { 0 - cast[u64](signed) } else { cast[u64](signed) })
        }
        else {
            add_unsigned(into, bits)
        }
    }
    else if kind == cast[u8](Kind.Boolean) {
        add_text(into, if read(value, at, if size <= 8 { size } else { 8 }) != 0 { "true" } else { "false" })
    }
    else if kind == cast[u8](Kind.Char) {
        runtime.array_add(into, byte_at(value, at))
    }
    else if kind == cast[u8](Kind.String) {
        if byte_at(schema, type + 9) != 0 {
            // A distance to its bytes, up to its zero
            distance :: cast[usize](read(value, at, 8))
            if distance == 0 {
                add_text(into, "null")
                return void
            }
            for i in distance..<value.count {
                if byte_at(value, i) == 0 {
                    break
                }
                runtime.array_add(into, byte_at(value, i))
            }
        }
        else {
            add_text(into, text_of(value, at))
        }
    }
    else if kind == cast[u8](Kind.Enum) {
        // Its name, its backing type, then each member's name and value
        name_at :: type + 9
        name_count :: cast[usize](read(schema, name_at, 4))
        members_at :: name_at + 4 + name_count + 4
        member_count :: cast[usize](read(schema, members_at, 4))
        raw :: read(value, at, if size <= 8 { size } else { 8 })
        cursor := members_at + 4
        for member in cast[usize](0)..<member_count {
            count :: cast[usize](read(schema, cursor, 4))
            member_value :: read(schema, cursor + 4 + count, 8)
            if member_value == raw && fits(schema, cursor + 4, count) {
                add_bytes(into, schema, cursor + 4, count)
                return void
            }
            cursor += 4 + count + 16
        }
        if fits(schema, name_at + 4, name_count) {
            add_bytes(into, schema, name_at + 4, name_count)
        }
        runtime.array_add(into, cast[u8]('('))
        add_unsigned(into, raw)
        runtime.array_add(into, cast[u8](')'))
    }
    else if kind == cast[u8](Kind.Pointer) || kind == cast[u8](Kind.Function) {
        add_text(into, if read(value, at, 8) == 0 { "null" } else { "<pointer>" })
    }
    else if kind == cast[u8](Kind.Float) && (size == 2 || size == 4 || size == 8) {
        sink :: runtime.FormatSink.{target = cast[rawptr](into), emit = sink_byte}
        exponent_bits : u64 = if size == 2 { 5 } else if size == 4 { 8 } else { 11 }
        fraction_bits : u64 = if size == 2 { 10 } else if size == 4 { 23 } else { 52 }
        runtime.format_shortest_float(sink, read(value, at, size), exponent_bits, fraction_bits)
    }
    else if kind == cast[u8](Kind.Struct) {
        add_text(into, "<struct ")
        name_count :: cast[usize](read(schema, type + 9, 4))
        if fits(schema, type + 13, name_count) {
            add_bytes(into, schema, type + 13, name_count)
        }
        runtime.array_add(into, cast[u8]('>'))
    }
    else {
        add_text(into, "<value>")
    }
}

/**
 * Read a string written in a value: its count, then the distance to its bytes.
 *
 * @param value The written value's bytes.
 * @param at Where the string is in them, in bytes.
 * @return The text, a view of value's bytes; "" if it's empty or its bytes aren't all there.
 */
text_of :: fn(value: u8[], at: usize) -> string {
    count :: cast[usize](read(value, at, 8))
    distance :: cast[usize](read(value, at + 8, 8))
    if count == 0 || !fits(value, distance, count) || distance >= value.count {
        return ""
    }
    return string_of(&value[distance], count)
}

/**
 * Add a run of bytes to the end of an array. Without the memory, calls context.assertion_handler.
 *
 * @param into The array, grown with its own allocator.
 * @param bytes Where the run is.
 * @param at Where it starts in bytes.
 * @param count How many bytes; any past the end of bytes are added as 0.
 */
add_bytes :: fn(into: ptr[mut u8[..]], bytes: u8[], at: usize, count: usize) {
    for i in at..<at + count {
        runtime.array_add(into, byte_at(bytes, i))
    }
}

/**
 * Add a number's decimal digits to the end of an array. Without the memory, calls context.assertion_handler.
 *
 * @param into The array, grown with its own allocator.
 * @param value The number, written without a sign or leading zeros; 0 is "0".
 */
add_unsigned :: fn(into: ptr[mut u8[..]], value: u64) {
    if value == 0 {
        runtime.array_add(into, cast[u8]('0'))
        return void
    }
    digits : u8[20]
    count : usize = 0
    left := value
    loop {
        digits[count % 20] = cast[u8]('0') + cast[u8](left % 10)
        count += 1
        left /= 10
    }
    while left != 0 && count < 20
    for i in cast[usize](0)..<count {
        runtime.array_add(into, digits[(count - 1 - i) % 20])
    }
}

/**
 * Read one byte, safely past the end.
 *
 * @param bytes Any bytes, empty included; only read.
 * @param at The byte's index in bytes, from 0; any value, as one past the end reads as 0.
 * @return The byte; 0 when at is past the end.
 */
byte_at :: fn(bytes: u8[], at: usize) -> u8 {
    if at >= bytes.count {
        return 0
    }
    return bytes[at]
}

/**
 * Tell whether a run of bytes is all there, without overflowing however large at and count are.
 *
 * @param bytes Any bytes, empty included; only read.
 * @param at The run's first byte's index in bytes, from 0; up to bytes' count fits an empty run.
 * @param count How many bytes it is; 0 fits anywhere up to the end.
 * @return True when every byte of the run is in bytes.
 */
fits :: fn(bytes: u8[], at: usize, count: usize) -> bool {
    return at <= bytes.count && count <= bytes.count - at
}

/**
 * Read a little-endian number.
 *
 * @param bytes Any bytes, empty included; only read.
 * @param at The number's first byte's index in bytes, from 0; any value, as a run past the end reads as 0.
 * @param count How many bytes it is; only the first 8 count toward the result.
 * @return The number; 0 if its bytes aren't all there.
 */
read :: fn(bytes: u8[], at: usize, count: usize) -> u64 {
    if !fits(bytes, at, count) {
        return 0
    }
    result : u64 = 0
    for i in cast[usize](0)..<count {
        if i < 8 {
            result |= cast[u64](byte_at(bytes, at + i)) << (8 * cast[u64](i))
        }
    }
    return result
}

/**
 * Sign-extend a signed number read as bits.
 *
 * @param bits The number's bits, in the low size bytes.
 * @param size How many bytes wide it is. 8 or more, or 0, takes the bits as they are.
 * @return The number, negative when its top bit was set.
 */
extend :: fn(bits: u64, size: usize) -> i64 {
    if size >= 8 || size == 0 {
        return cast[i64](bits)
    }
    shift :: 64 - 8 * cast[u64](size)
    return cast[i64](bits << shift) >> shift
}

/**
 * Find where the first type's description starts: after "HSCH", the version and the count.
 *
 * @param schema The bytes that should be a schema, starting with "HSCH" and this VERSION; any bytes, empty included,
 *     and only read.
 * @return 10; NOWHERE if they don't start with "HSCH" and this VERSION, or are shorter than that.
 */
first_type :: fn(schema: u8[]) -> usize {
    if schema.count < 10 || byte_at(schema, 0) != 0x48 || byte_at(schema, 1) != 0x53 || byte_at(schema, 2) != 0x43 || byte_at(schema, 3) != 0x48
        || read(schema, 4, 2) != cast[u64](VERSION) {
        return NOWHERE
    }
    return 10
}

/**
 * Follow a type's plain and distinct aliases to the type they name.
 *
 * @param schema The schema, as schema.write wrote it; only read, and not trusted: each read is checked against its end.
 * @param at Where a type's description starts, or NOWHERE.
 * @return Where the first type that isn't an alias is described: at itself when it isn't one. NOWHERE for NOWHERE,
 *     a description cut short, or aliases more than ALIAS_LIMIT deep.
 */
unaliased :: fn(schema: u8[], at: usize) -> usize {
    type := at
    for step in 0..<ALIAS_LIMIT {
        if type == NOWHERE || !fits(schema, type, 9) {
            return NOWHERE
        }
        if byte_at(schema, type) != cast[u8](Kind.Alias) {
            return type
        }
        // Its name, then the place of the type it names
        name_count :: cast[usize](read(schema, type + 9, 4))
        type = type_at(schema, cast[usize](read(schema, type + 13 + name_count, 4)))
    }
    return NOWHERE
}

/**
 * Find where the type at a place among the schema's types is described, by going past each before it.
 *
 * @param schema The schema, as schema.write wrote it; only read, and not trusted: each read is checked against its end.
 * @param place The type's place, from 0.
 * @return Where its description starts; NOWHERE for a place past the last type, or bytes that aren't a schema.
 */
type_at :: fn(schema: u8[], place: usize) -> usize {
    count :: cast[usize](read(schema, 6, 4))
    if place >= count {
        return NOWHERE
    }
    at := first_type(schema)
    for i in cast[usize](0)..<place {
        at = after_type(schema, at)
    }
    return at
}

/**
 * Find where the description after one starts.
 *
 * @param schema The schema, as schema.write wrote it; only read, and not trusted: each read is checked against its end.
 * @param at Where a type's description starts, or NOWHERE.
 * @return Where the next one starts; NOWHERE for NOWHERE, or a description cut short.
 */
after_type :: fn(schema: u8[], at: usize) -> usize {
    if at == NOWHERE || !fits(schema, at, 9) {
        return NOWHERE
    }
    kind :: byte_at(schema, at)
    cursor := at + 9
    if kind == cast[u8](Kind.Alias) {
        cursor = skip_name(schema, cursor) + 4
    }
    else if kind == cast[u8](Kind.Array) {
        cursor += 4
        dimensions :: cast[usize](read(schema, cursor, 4))
        cursor += 4 + dimensions * 10
    }
    else if kind == cast[u8](Kind.Enum) {
        cursor = skip_name(schema, cursor) + 4
        members :: cast[usize](read(schema, cursor, 4))
        cursor += 4
        for i in cast[usize](0)..<members {
            cursor = skip_name(schema, cursor) + 16
        }
    }
    else if kind == cast[u8](Kind.Float) {
        cursor += 1
    }
    else if kind == cast[u8](Kind.Function) {
        inputs :: cast[usize](read(schema, cursor, 4))
        cursor += 4
        for i in cast[usize](0)..<inputs {
            cursor = skip_name(schema, cursor) + 6
        }
        outputs :: cast[usize](read(schema, cursor, 4))
        cursor += 4 + outputs * 4 + 1
    }
    else if kind == cast[u8](Kind.Integer) {
        cursor += 2
    }
    else if kind == cast[u8](Kind.Pointer) {
        cursor += if read(schema, cursor, 1) != 0 { cast[usize](5) } else { cast[usize](1) }
        cursor += 2
    }
    else if kind == cast[u8](Kind.String) {
        cursor += 1
    }
    else if kind == cast[u8](Kind.Struct) {
        cursor = skip_name(schema, cursor) + 8 + 2
        members :: cast[usize](read(schema, cursor, 4))
        cursor += 4
        for i in cast[usize](0)..<members {
            cursor = skip_name(schema, cursor) + 4 + 8 + 1
        }
    }
    else if kind == cast[u8](Kind.Union) {
        cursor = skip_name(schema, cursor) + 1
        cursor += if read(schema, cursor, 1) != 0 { cast[usize](5) } else { cast[usize](1) }
        variants :: cast[usize](read(schema, cursor, 4))
        cursor += 4
        for i in cast[usize](0)..<variants {
            cursor = skip_name(schema, cursor)
            held :: cast[usize](read(schema, cursor, 4))
            cursor += 4 + held * 12
        }
    }
    else if kind == cast[u8](Kind.Vector) {
        cursor += 4 + 8 + 1
    }
    if cursor > schema.count {
        return NOWHERE
    }
    return cursor
}

/**
 * Go past a name: its count (u32), then its bytes.
 *
 * @param schema The schema, only read; the name's count is read at at, as 0 when it's cut short.
 * @param at Where the name starts.
 * @return Where its bytes end, which may be past the end of schema when it's cut short.
 */
skip_name :: fn(schema: u8[], at: usize) -> usize {
    return at + 4 + cast[usize](read(schema, at, 4))
}

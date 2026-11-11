package crypto

/*
 * DER (ITU-T X.690's Distinguished Encoding Rules), read strictly, as X.509 certificates, keys and ECDSA
 * signatures are written: one tag byte (numbers 0 to 30, as everything here uses), a definite length in its
 * shortest form, then the contents. Anything BER allows and DER doesn't, an indefinite or padded length, a
 * tag number of 31 or more, is refused, so each value has one encoding and a signature over it means one
 * thing.
 *
 *     sequence := crypto.der_expect(der, crypto.DER_SEQUENCE) or_return ...
 *     first := crypto.der_expect(sequence.contents, crypto.DER_INTEGER) or_return ...
 *     second := crypto.der_expect(first.rest, crypto.DER_INTEGER) or_return ...
 *     // second.rest is empty when the SEQUENCE has nothing more
 *
 * Each element read holds its rest, the bytes after it, where the next one is read from. Everything read
 * is a view of the bytes given; nothing is copied or allocated.
 */

/** BOOLEAN's tag. */
DER_BOOLEAN :: 0x01
/** INTEGER's tag. */
DER_INTEGER :: 0x02
/** BIT STRING's tag. */
DER_BIT_STRING :: 0x03
/** OCTET STRING's tag. */
DER_OCTET_STRING :: 0x04
/** NULL's tag. */
DER_NULL :: 0x05
/** OBJECT IDENTIFIER's tag. */
DER_OID :: 0x06
/** UTF8String's tag. */
DER_UTF8_STRING :: 0x0c
/** PrintableString's tag. */
DER_PRINTABLE_STRING :: 0x13
/** IA5String's tag, ASCII. */
DER_IA5_STRING :: 0x16
/** UTCTime's tag. */
DER_UTC_TIME :: 0x17
/** GeneralizedTime's tag. */
DER_GENERALIZED_TIME :: 0x18
/** SEQUENCE's tag, constructed. */
DER_SEQUENCE :: 0x30
/** SET's tag, constructed. */
DER_SET :: 0x31
/** A context-specific tag's class bits: [n] is 0x80 + n, primitive, or DER_CONSTRUCTED + n. */
DER_CONTEXT :: 0x80
/** A context-specific constructed tag's bits: [n] EXPLICIT, or IMPLICIT of a constructed type, is 0xa0 + n. */
DER_CONSTRUCTED :: 0xa0

/** One DER element read: its tag and contents, and what follows it, each a view of the bytes it was read from. */
DerElement :: struct {
    /** The tag byte: class, constructed bit and a number from 0 to 30. */
    tag: u8,
    /** The contents, after the tag and length; empty for a length of 0. */
    contents: u8[],
    /** The whole element, tag and length included, as a signature covers it. */
    whole: u8[],
    /** The bytes after it, where the next element starts; empty when it was the last. */
    rest: u8[],
}

/**
 * Read the element at the start of some bytes, checking its tag and length are DER's.
 *
 * @param data The bytes, the element first; what follows it is the element's rest.
 * @return The element, its views into data; or null when data is empty, or doesn't start with a DER element: a tag
 *     number of 31 or more, an indefinite length, a length not in its shortest form or of more than four bytes, or
 *     one past the bytes there are.
 */
der_next :: fn(data: u8[]) -> DerElement? {
    if data.count < 2 || (data[0] & 0x1f) == 0x1f {
        return null
    }
    first := data[1]
    length : usize = 0
    header : usize = 2
    if first >= 0x80 {
        count := cast[usize](first & 0x7f)
        // 0x80 is BER's indefinite length; DER's long form needs a length of 128 or more, without leading zeros
        if count == 0 || count > 4 || data.count < 2 + count || data[2] == 0 {
            return null
        }
        for i in 0..<count {
            length = (length << 8) | cast[usize](data[(2 + i) % data.count])
        }
        if length < 0x80 {
            return null
        }
        header = 2 + count
    }
    else {
        length = cast[usize](first)
    }
    end := header + length
    if header > data.count || end > data.count || end < header {
        return null
    }
    return DerElement.{tag = data[0], contents = data[header..<end], whole = data[0..<end], rest = data[end..<data.count]}
}

/**
 * Read the element at the start of some bytes, which has to have the tag given.
 *
 * @param data The bytes, the element first.
 * @param tag The tag it has to have.
 * @return The element; or null when data is empty, the element is malformed, or it has another tag.
 */
der_expect :: fn(data: u8[], tag: u8) -> DerElement? {
    if data.count == 0 || data[0] != tag {
        return null
    }
    return der_next(data)
}

/**
 * Say whether the element at the start of some bytes has a tag, for an OPTIONAL or DEFAULT field, without reading it.
 *
 * @param data The bytes.
 * @param tag The tag the field has.
 * @return Whether data isn't empty and starts with the tag: the field is there, if it's well formed.
 */
der_next_is :: fn(data: u8[], tag: u8) -> bool {
    return data.count > 0 && data[0] == tag
}

/**
 * Check an INTEGER's contents are DER's: at least one byte, and no leading byte that only repeats the sign.
 *
 * @param element The INTEGER.
 * @return Its contents, the two's complement number big-endian; or null when it's empty, padded, or not an INTEGER.
 */
der_integer :: fn(element: DerElement) -> u8[]? {
    contents := element.contents
    if element.tag != DER_INTEGER || contents.count == 0 {
        return null
    }
    if contents.count > 1 && ((contents[0] == 0x00 && contents[1] < 0x80) || (contents[0] == 0xff && contents[1] >= 0x80)) {
        return null
    }
    return contents
}

/**
 * Read an INTEGER that has to be 0 or more, as a key's numbers and a signature's are.
 *
 * @param element The INTEGER.
 * @return Its magnitude, big-endian, without the 0x00 a number with its top bit set is written with; empty for 0.
 *     Null when it's malformed or negative.
 */
der_unsigned :: fn(element: DerElement) -> u8[]? {
    contents := der_integer(element) or_return null
    if contents.count == 0 || contents[0] >= 0x80 {
        return null
    }
    if contents[0] == 0 {
        return contents[1..<contents.count]
    }
    return contents
}

/**
 * Read an INTEGER that fits in 63 bits and is 0 or more, like a version or a path length.
 *
 * @param element The INTEGER.
 * @return Its value; or null when it's malformed, negative, or 2^63 or more.
 */
der_small :: fn(element: DerElement) -> i64? {
    magnitude := der_unsigned(element) or_return null
    if magnitude.count > 8 || (magnitude.count == 8 && magnitude[0] >= 0x80) {
        return null
    }
    value : i64 = 0
    for byte in magnitude {
        value = (value << 8) | cast[i64](byte)
    }
    return value
}

/**
 * Read a BOOLEAN, which DER writes as 0x00 or 0xff.
 *
 * @param element The BOOLEAN.
 * @return Its value; or null when it isn't a BOOLEAN of one byte, 0x00 or 0xff.
 */
der_boolean :: fn(element: DerElement) -> bool? {
    if element.tag != DER_BOOLEAN || element.contents.count != 1 {
        return null
    }
    byte := element.contents[0]
    if byte != 0x00 && byte != 0xff {
        return null
    }
    return byte == 0xff
}

/**
 * Read a BIT STRING of whole bytes, as a key or signature in one is.
 *
 * @param element The BIT STRING.
 * @return Its bytes, after the count of unused bits; or null when it isn't a BIT STRING, or that count isn't 0.
 */
der_bit_string :: fn(element: DerElement) -> u8[]? {
    contents := element.contents
    if element.tag != DER_BIT_STRING || contents.count == 0 || contents[0] != 0 {
        return null
    }
    return contents[1..<contents.count]
}

/**
 * Read a BIT STRING of named bits, like KeyUsage, as DER writes one: no trailing zero bits, and the unused ones 0.
 *
 * @param element The BIT STRING.
 * @return Its first 16 bits, bit 0 (the first named) as the value's top bit, 0x8000; or null when it's malformed:
 *     more than 7 unused bits, unused bits that aren't 0, a last bit that's 0, or bits given with no bytes.
 */
der_named_bits :: fn(element: DerElement) -> u16? {
    contents := element.contents
    if element.tag != DER_BIT_STRING || contents.count == 0 || contents[0] > 7 {
        return null
    }
    unused := contents[0]
    if contents.count == 1 {
        if unused != 0 {
            return null
        }
        return cast[u16](0)
    }
    last := contents[contents.count - 1]
    // The last used bit is 1, and the unused ones below it 0
    if ((last >> unused) & 1) == 0 || (last & ((cast[u8](1) << unused) - 1)) != 0 {
        return null
    }
    value : u16 = 0
    for i in 1..<contents.count {
        if i <= 2 {
            value = value | (cast[u16](contents[i]) << (16 - 8 * cast[u16](i)))
        }
    }
    return value
}

/**
 * Check an OBJECT IDENTIFIER's contents are well formed: at least one byte, each arc's base-128 digits without a
 * leading 0x80, and the last byte ending an arc.
 *
 * @param element The OBJECT IDENTIFIER.
 * @return Its contents, the encoded arcs, to compare with an OID's encoding; or null when it's malformed.
 */
der_oid :: fn(element: DerElement) -> u8[]? {
    contents := element.contents
    if element.tag != DER_OID || contents.count == 0 || (contents[contents.count - 1] & 0x80) != 0 {
        return null
    }
    starting := true
    for byte in contents {
        if starting && byte == 0x80 {
            return null
        }
        starting = (byte & 0x80) == 0
    }
    return contents
}

/**
 * Say whether two byte views hold the same bytes.
 *
 * @param a One view.
 * @param b The other.
 * @return Whether they have the same count and bytes; not in constant time, as it's for public values.
 */
der_same :: fn(a: u8[], b: u8[]) -> bool {
    if a.count != b.count {
        return false
    }
    for byte, i in a {
        if byte != b[i] {
            return false
        }
    }
    return true
}

/**
 * Count the days from 1970-01-01 to a date, proleptic Gregorian (Howard Hinnant's days_from_civil).
 *
 * @param year The year, any from 0 on.
 * @param month The month, 1 to 12.
 * @param day The day of the month, 1 to 31; not checked against the month's length.
 * @return The days, negative before 1970.
 */
der_days_from_civil :: fn(year: i64, month: i64, day: i64) -> i64 {
    y := if month <= 2 { year - 1 } else { year }
    era := (if y >= 0 { y } else { y - 399 }) / 400
    year_of_era := y - era * 400
    shifted_month := if month > 2 { month - 3 } else { month + 9 }
    day_of_year := (153 * shifted_month + 2) / 5 + day - 1
    day_of_era := year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year
    return era * 146097 + day_of_era - 719468
}

/**
 * Read a run of decimal digits as a number.
 *
 * @param text The text.
 * @param start Where the digits start.
 * @param count How many there are, 1 to 4.
 * @return Their value; or null when one isn't a digit or they run past text's end.
 */
der_digits :: fn(text: u8[], start: usize, count: usize) -> i64? {
    if start > text.count || count > text.count - start {
        return null
    }
    value : i64 = 0
    for i in 0..<count {
        if start + i >= text.count {
            return null
        }
        c := text[start + i]
        if c < cast[u8]('0') || c > cast[u8]('9') {
            return null
        }
        value = value * 10 + cast[i64](c - cast[u8]('0'))
    }
    return value
}

/**
 * Read a UTCTime or GeneralizedTime as X.509 writes them (RFC 5280, section 4.1.2.5): YYMMDDHHMMSSZ or
 * YYYYMMDDHHMMSSZ, in UTC, with seconds and no fractions. A UTCTime's year from 50 to 99 is 19YY, and from 00 to 49
 * 20YY.
 *
 * @param element The time.
 * @return The time in seconds since 1970-01-01T00:00:00Z, which may be negative; or null when it's neither form, or
 *     a month, day, hour, minute or second is out of range (a leap second, 60, is refused).
 */
der_time :: fn(element: DerElement) -> i64? {
    text := element.contents
    at : usize = 0
    year : i64 = 0
    if element.tag == DER_UTC_TIME && text.count == 13 {
        short := der_digits(text, 0, 2) or_return null
        year = if short >= 50 { 1900 + short } else { 2000 + short }
        at = 2
    }
    else if element.tag == DER_GENERALIZED_TIME && text.count == 15 {
        year = der_digits(text, 0, 4) or_return null
        at = 4
    }
    else {
        return null
    }
    month := der_digits(text, at, 2) or_return null
    day := der_digits(text, at + 2, 2) or_return null
    hour := der_digits(text, at + 4, 2) or_return null
    minute := der_digits(text, at + 6, 2) or_return null
    second := der_digits(text, at + 8, 2) or_return null
    if text[(at + 10) % text.count] != cast[u8]('Z') || month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59 || second > 59 {
        return null
    }
    days_in := i64.[31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    leap := (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    if day > days_in[(month - 1) %% 12] || (month == 2 && day == 29 && !leap) {
        return null
    }
    return der_days_from_civil(year, month, day) * 86400 + hour * 3600 + minute * 60 + second
}

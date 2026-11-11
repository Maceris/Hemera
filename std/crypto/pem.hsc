package crypto

/*
 * Base64 (RFC 4648, section 4) and PEM (RFC 7468): the text forms keys and certificates are kept in.
 *
 *     -----BEGIN CERTIFICATE-----
 *     MIIBszCCAVmgAwIBAgIU...
 *     -----END CERTIFICATE-----
 *
 * pem_certificates turns a file of them, like a set of trust anchors, into the DER certificates one after
 * another that x509_verify_chain takes:
 *
 *     count := crypto.pem_certificates(file_text, der_buffer) or_else ...
 *     verdict := crypto.x509_verify_chain(chain, der_buffer[0..<count], now, .SERVER)
 *
 * Decoding is strict: only the standard alphabet, padding to whole groups of four, and no bits left over
 * that aren't 0, so a value has one encoding. Whitespace between characters is skipped, as PEM wraps lines.
 */

/** Base64's 64 characters, in order: A to Z, a to z, 0 to 9, + and /. */
BASE64_ALPHABET :: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

/**
 * Say what a base64 character stands for.
 *
 * @param c The character.
 * @return Its value, 0 to 63; 64 for =, padding; 65 for whitespace (space, tab, CR, LF); 66 for anything else.
 */
base64_value :: fn(c: u8) -> u8 {
    if c >= cast[u8]('A') && c <= cast[u8]('Z') {
        return c - cast[u8]('A')
    }
    if c >= cast[u8]('a') && c <= cast[u8]('z') {
        return c - cast[u8]('a') + 26
    }
    if c >= cast[u8]('0') && c <= cast[u8]('9') {
        return c - cast[u8]('0') + 52
    }
    if c == cast[u8]('+') {
        return 62
    }
    if c == cast[u8]('/') {
        return 63
    }
    if c == cast[u8]('=') {
        return 64
    }
    if c == cast[u8](' ') || c == cast[u8]('\t') || c == cast[u8]('\r') || c == cast[u8]('\n') {
        return 65
    }
    return 66
}

/**
 * Decode base64 text (RFC 4648, section 4), strictly.
 *
 * @param text The text: groups of four characters from the standard alphabet, the last padded with = to four;
 *     whitespace anywhere between them is skipped. Empty is allowed, and decodes to nothing.
 * @param output Where the bytes go: 3 for each group of four, less one for each =.
 * @return How many bytes were written, from the start of output; or null when the text isn't base64 (another
 *     character, a group cut short, padding before the end or more than two of it, or left-over bits that aren't 0),
 *     or output is too small, with what was written so far left there.
 */
base64_decode :: fn(text: u8[], output: mut u8[]) -> usize? {
    written : usize = 0
    group : u32 = 0
    filled : usize = 0
    padding : usize = 0
    for c in text {
        value := base64_value(c)
        if value == 65 {
            continue
        }
        if value == 66 || (padding > 0 && value != 64) {
            return null
        }
        if value == 64 {
            // Padding only in a group's last two places
            if filled < 2 {
                return null
            }
            padding += 1
            value = 0
        }
        group = (group << 6) | cast[u32](value)
        filled += 1
        if filled == 4 {
            bytes := 3 - padding
            if padding > 2 || written + bytes > output.count {
                return null
            }
            // Bits the padding leaves over have to be 0
            if (padding == 1 && (group & 0xff) != 0) || (padding == 2 && (group & 0xffff) != 0) {
                return null
            }
            for i in 0..<bytes {
                if written < output.count {
                    output[written] = cast[u8](group >> (16 - 8 * cast[u32](i)))
                    written += 1
                }
            }
            group = 0
            filled = 0
            if padding > 0 {
                // Nothing but whitespace after the padded group
                padding = 3
            }
        }
    }
    if filled != 0 {
        return null
    }
    return written
}

/**
 * Encode bytes as base64 (RFC 4648, section 4), padded, on one line.
 *
 * @param data The bytes, of any number.
 * @param output Where the text goes: 4 characters for each 3 bytes or part of 3.
 * @return How many characters were written, from the start of output; or null when output is too small, with
 *     nothing written.
 */
base64_encode :: fn(data: u8[], output: mut u8[]) -> usize? {
    needed := (data.count + 2) / 3 * 4
    if needed > output.count {
        return null
    }
    written : usize = 0
    at : usize = 0
    loop {
        group : u32 = 0
        present : usize = 0
        for i in cast[usize](0)..<3 {
            group = group << 8
            if at + i < data.count {
                group = group | cast[u32](data[at + i])
                present += 1
            }
        }
        for i in cast[usize](0)..<4 {
            character := cast[u8]('=')
            if i <= present {
                character = cast[u8](BASE64_ALPHABET[(group >> (18 - 6 * cast[u32](i))) & 63])
            }
            if written < output.count {
                output[written] = character
                written += 1
            }
        }
        at += 3
    }
    while at < data.count
    return written
}

/** A PEM block found in text: its label, and its base64 body, views of the text. */
PemBlock :: struct {
    /** The label between BEGIN and the dashes, like CERTIFICATE or PRIVATE KEY. */
    label: u8[],
    /** The base64 text between the BEGIN and END lines, line breaks and all, for base64_decode. */
    body: u8[],
    /** The text after the END line's dashes, where the next block may be. */
    rest: u8[],
}

/**
 * Say whether text has some bytes at a position.
 *
 * @param text The text.
 * @param at The position.
 * @param wanted The bytes.
 * @return Whether text from at starts with wanted.
 */
pem_has :: fn(text: u8[], at: usize, wanted: string) -> bool {
    if at > text.count || wanted.count > text.count - at {
        return false
    }
    for c, i in wanted {
        if at + i >= text.count || text[at + i] != cast[u8](c) {
            return false
        }
    }
    return true
}

/**
 * Find the next PEM block in text (RFC 7468): a -----BEGIN label----- line, base64, then -----END label----- with
 * the same label. Text before the BEGIN line is skipped, as RFC 7468 allows explanations there.
 *
 * @param text The text, of any length.
 * @return The block, its views of text; or null when there's no BEGIN line, or no END line with its label after it.
 */
pem_next :: fn(text: u8[]) -> PemBlock? {
    for begin in 0..<text.count {
        if pem_has(text, begin, "-----BEGIN ") {
            label_start := begin + 11
            label_end := label_start
            loop {
                label_end += 1
            }
            while label_end < text.count && text[label_end] != cast[u8]('-')
            if label_start > label_end || label_end > text.count || !pem_has(text, label_end, "-----") {
                return null
            }
            label := text[label_start..<label_end]
            body_start := label_end + 5
            for end in body_start..<text.count {
                if pem_has(text, end, "-----END ") {
                    after := end + 9
                    label_after := after + label.count
                    if after > text.count || label_after > text.count || label_after < after {
                        return null
                    }
                    if !der_same(text[after..<label_after], label) || !pem_has(text, label_after, "-----") {
                        return null
                    }
                    finish := after + label.count + 5
                    if body_start > end || finish > text.count {
                        return null
                    }
                    return PemBlock.{label = label, body = text[body_start..<end], rest = text[finish..<text.count]}
                }
            }
            return null
        }
    }
    return null
}

/**
 * Decode every CERTIFICATE block in PEM text into DER certificates one after another, as x509_verify_chain takes a
 * chain or a set of anchors.
 *
 * @param text The text, of any length: blocks of other labels, and text between blocks, are skipped.
 * @param output Where the DER goes, each certificate after the one before.
 * @return How many bytes were written, 0 when there's no certificate; or null when a CERTIFICATE block isn't base64,
 *     or output is too small.
 */
pem_certificates :: fn(text: u8[], output: mut u8[]) -> usize? {
    written : usize = 0
    rest := text
    loop {
        block := pem_next(rest) or_return written
        rest = block.rest
        if der_same(block.label, bit_cast[u8[]]("CERTIFICATE")) {
            if written > output.count {
                return null
            }
            count := base64_decode(block.body, output[written % (output.count + 1)..<output.count]) or_return null
            written += count
        }
    }
    while rest.count != 0
    return written
}

package ntp

import tls from "std"

/*
 * NTPv4's packet (RFC 5905 §7.3) and the times it carries. A timestamp is NTP's 64 bits: seconds since 1900 in the high
 * 32, and the fraction of a second in the low 32. Era 0 ends in 2036; times are compared as differences, wrapping, so a
 * difference within 68 years is right across an era's end, as RFC 5905 §6 has it.
 *
 *     t1 :: now_nanoseconds()                        // the client's clock, as the request goes
 *     ... the request sent, the answer read ...
 *     t4 :: now_nanoseconds()                        // as the answer arrives
 *     sample :: ntp.sample_of(t1, reply, t4)         // its offset and delay, in nanoseconds
 */

/** The NTP port, UDP. */
NTP_PORT : u16 : 123
/** An NTP packet's header: what comes before any extension field. */
HEADER_BYTES :: 48
/** Seconds from NTP's epoch, 1900-01-01, to Unix's, 1970-01-01. */
UNIX_EPOCH : i64 : 2208988800
/** Nanoseconds in a second. */
NANOSECONDS : i64 : 1_000_000_000

/** The version spoken: NTPv4. */
VERSION : u8 : 4
/** The modes a client sends and a server answers with. */
MODE_CLIENT : u8 : 3
MODE_SERVER : u8 : 4
/** The leap indicator that says a server's clock isn't synchronized. */
LEAP_UNSYNCHRONIZED : u8 : 3
/** The stratum a kiss-o'-death packet carries (RFC 5905 §7.4); a server's is 1 to 15. */
STRATUM_KISS : u8 : 0
STRATUM_MOST : u8 : 15

/**
 * Turn a time into an NTP timestamp.
 *
 * @param nanoseconds Nanoseconds since 1970 UTC; any, the seconds taken modulo 2^32, as NTP's eras do.
 * @return The timestamp.
 */
timestamp_of :: fn(nanoseconds: i64) -> u64 {
    seconds := nanoseconds / NANOSECONDS
    rest := nanoseconds % NANOSECONDS
    if rest < 0 {
        seconds -= 1
        rest += NANOSECONDS
    }
    high :: cast[u64](seconds + UNIX_EPOCH) & 0xffffffff
    // The fraction: rest / 10^9 of 2^32, rounded down
    fraction :: (cast[u64](rest) << 32) / cast[u64](NANOSECONDS)
    return (high << 32) | fraction
}

/**
 * Give how far apart two timestamps are, b's from a's: b - a, wrapping, so right within 68 years either way.
 *
 * @param a The first.
 * @param b The second.
 * @return Nanoseconds; negative if b is before a.
 */
difference :: fn(a: u64, b: u64) -> i64 {
    d :: cast[i64](b - a)
    // d is seconds in its high 32 bits, signed, and a fraction in its low 32, as d = high * 2^32 + low
    high :: d >> 32
    low :: cast[i64](cast[u64](d) & 0xffffffff)
    return high * NANOSECONDS + ((low * NANOSECONDS) >> 32)
}

/** What a server's answer says, its header read. */
Reply :: struct {
    /** Its leap indicator, 0 to 3. */
    leap : u8,
    stratum : u8,
    /** Its reference identifier, which a kiss-o'-death packet's kiss code is. */
    reference : u32,
    /** When the request arrived at the server, and when the answer left it: t2 and t3. */
    received : u64,
    transmitted : u64,
}

/** An offset and a round-trip delay worked out from an exchange (RFC 5905 §8). */
Sample :: struct {
    /** How far the server's clock is ahead of the client's: add it to the client's to have the server's. */
    offset : i64,
    /** The round trip's delay, less the server's time with it; never negative. */
    delay : i64,
}

/**
 * Write a client's request header: NTPv4, client mode, the rest zero but the transmit timestamp.
 *
 * @param into Where it goes: its first HEADER_BYTES; nothing's written if it has fewer.
 * @param transmit The transmit timestamp, which the answer's origin has to be. Random, rather than the time, keeps the
 *     client's clock from whoever watches (RFC 9109), and makes a reply harder to forge without NTS.
 */
put_header :: fn(into: mut u8[], transmit: u64) {
    if into.count < HEADER_BYTES {
        return void
    }
    for i in 0..<HEADER_BYTES {
        into[i] = 0
    }
    into[0] = (VERSION << 3) | MODE_CLIENT
    put_u64(into, 40, transmit)
}

/**
 * Read a server's answer's header, checking it's an answer to the request whose transmit timestamp was origin.
 *
 * @param packet The answer.
 * @param origin The request's transmit timestamp.
 * @return What it says; null if it's shorter than a header, isn't from a server in NTPv4, or answers another request.
 *     A kiss-o'-death packet, stratum 0, is given, for its caller to read its kiss code.
 */
read_header :: fn(packet: u8[], origin: u64) -> Reply? {
    if packet.count < HEADER_BYTES {
        return null
    }
    first :: packet[0]
    version :: (first >> 3) & 7
    mode :: first & 7
    if version != VERSION || mode != MODE_SERVER || get_u64(packet, 24) != origin {
        return null
    }
    return Reply.{leap = first >> 6, stratum = packet[1], reference = get_u32(packet, 12), received = get_u64(packet, 32),
        transmitted = get_u64(packet, 40)}
}

/**
 * Tell whether an answer's time can be used: synchronized, from a stratum of 1 to 15, and not sent before it arrived.
 *
 * @param reply The answer.
 * @return True if it can.
 */
usable :: fn(reply: ptr[Reply]) -> bool {
    return reply.leap != LEAP_UNSYNCHRONIZED && reply.stratum != STRATUM_KISS && reply.stratum <= STRATUM_MOST
        && reply.transmitted != 0 && difference(reply.received, reply.transmitted) >= 0
}

/**
 * Work out an exchange's offset and delay (RFC 5905 §8).
 *
 * @param sent When the request left, t1, by the client's clock, in nanoseconds since 1970 UTC.
 * @param reply The answer, with t2 and t3.
 * @param arrived When the answer arrived, t4, by the client's clock, in nanoseconds since 1970 UTC.
 * @return The sample; its delay is 0 if the round trip seems to have taken less time than the server held it.
 */
sample_of :: fn(sent: i64, reply: ptr[Reply], arrived: i64) -> Sample {
    t1 :: timestamp_of(sent)
    t4 :: timestamp_of(arrived)
    out :: difference(t1, reply.received)
    back :: difference(t4, reply.transmitted)
    held :: difference(reply.received, reply.transmitted)
    delay :: (arrived - sent) - held
    // Each within 68 years, so their sum fits
    return Sample.{offset = (out + back) / 2, delay = if delay > 0 { delay } else { cast[i64](0) }}
}

// ---- Big-endian numbers at an offset

/** Read a u32 at an offset; 0 if it runs past the bytes. */
get_u32 :: fn(bytes: u8[], at: usize) -> u32 {
    part :: tls.range(bytes, at, at + 4)
    value := cast[u32](0)
    for byte in part {
        value = (value << 8) | cast[u32](byte)
    }
    return value
}

/** Read a u64 at an offset; 0 if it runs past the bytes. */
get_u64 :: fn(bytes: u8[], at: usize) -> u64 {
    part :: tls.range(bytes, at, at + 8)
    value := cast[u64](0)
    for byte in part {
        value = (value << 8) | cast[u64](byte)
    }
    return value
}

/** Write a u64 at an offset; nothing if it runs past the bytes. */
put_u64 :: fn(bytes: mut u8[], at: usize, value: u64) {
    part :: tls.range_mut(bytes, at, at + 8)
    for &byte, i in part {
        byte^ = cast[u8](value >> cast[u64](56 - 8 * i))
    }
}

package net_address

/*
 * The network protocols' addresses (network, tcp_stream, tcp_listener, datagrams), plain data so they cross channels:
 * an IP address of either family, and an endpoint, an address and a port.
 */

/** An Address's family, as its family field says. */
Family :: enum #backed_by(u8) {
    /** No address. */
    None = 0,
    /** IPv4: the first 4 of bytes. */
    V4 = 4,
    /** IPv6: all 16 of bytes. */
    V6 = 6,
}

/** An IP address of either family. */
Address :: struct {
    /** Which family: a Family's value. */
    family : Family,
    /** Its bytes, in the order they're sent: IPv4's in the first 4, the rest 0. */
    bytes : u8[16],
}

/** An address and a port. */
Endpoint :: struct {
    address : Address,
    /** The port, 1 to 65535; 0 for none. */
    port : u16,
}

/**
 * Make an IPv4 address.
 *
 * @param a Its first byte.
 * @param b Its second.
 * @param c Its third.
 * @param d Its fourth.
 * @return The address.
 */
v4 :: fn(a: u8, b: u8, c: u8, d: u8) -> Address {
    address := Address.{family = .V4}
    address.bytes[0] = a
    address.bytes[1] = b
    address.bytes[2] = c
    address.bytes[3] = d
    return address
}

/**
 * Read an IPv4 address in dotted decimal.
 *
 * @param text Four numbers from 0 to 255 with dots between, and nothing else.
 * @return The address; null if text isn't one.
 */
parse_v4 :: fn(text: string) -> Address? {
    address := Address.{family = .V4}
    part := cast[u32](0)
    digits := 0
    index := cast[usize](0)
    for character in text {
        if character == '.' {
            if digits == 0 || index >= 3 {
                return null
            }
            address.bytes[index] = cast[u8](part)
            index += 1
            part = 0
            digits = 0
        }
        else if character >= '0' && character <= '9' {
            part = part * 10 + (cast[u32](character) - cast[u32]('0'))
            digits += 1
            if part > 255 || digits > 3 {
                return null
            }
        }
        else {
            return null
        }
    }
    if digits == 0 || index != 3 {
        return null
    }
    address.bytes[3] = cast[u8](part)
    return address
}

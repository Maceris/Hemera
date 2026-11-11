package network

import text_buffer from "std"
import slop_os from "std/os"
import net_address from "std/os/slop_os"

/*
 * A network connection's policy: what it may connect to, and what it may listen on. A rule allows a transport, TCP or
 * UDP or both, to a range of ports, at an address range: any address, any public address, or a prefix. The service
 * checks each Open, Listen and Udp, and each datagram, against the policy of the connection it came on; Narrow makes
 * a connection with a policy within its own.
 *
 * A public address is any that isn't private, loopback, link-local, shared, multicast or reserved (RFC 6890's special
 * ranges), so a policy of public addresses doesn't reach the local network, as DNS rebinding would want it to.
 */

/** The most rules of each kind a policy has: 16 to connect, and 16 to listen. */
MAX_RULES :: 16
/** A rule's transports bit for TCP. */
TRANSPORT_TCP : u8 : 1
/** A rule's transports bit for UDP. */
TRANSPORT_UDP : u8 : 2

/** A rule's scope covering every public address, of both families. */
SCOPE_PUBLIC : u8 : 0
/** A rule's scope covering every address, of both families, private ones too. */
SCOPE_ANY : u8 : 1
/** A rule's scope covering the addresses sharing the rule's address's first prefix_length bits, of its family. */
SCOPE_RANGE : u8 : 2

/** One rule of a policy: plain data, so it's a Relative's element in a message. */
Rule :: struct {
    /** Which addresses it covers: SCOPE_PUBLIC, SCOPE_ANY or SCOPE_RANGE. */
    scope : u8,
    /** With SCOPE_RANGE: the range's address's family, a net_address.Family's value: 4 or 6. */
    family : u8,
    /** With SCOPE_RANGE: how many of its first bits the range's addresses share: up to 32 for IPv4, 128 for IPv6. */
    prefix_length : u8,
    /** TRANSPORT_TCP, TRANSPORT_UDP, or both. */
    transports : u8,
    /** The ports, from first_port to last_port, both included; a listen rule's are the ports listened on. */
    first_port : u16,
    last_port : u16,
    /** With SCOPE_RANGE: the range's address's bytes, IPv4's in the first 4. */
    address : u8[16],
}

/**
 * Make a rule for one address or a range of them.
 *
 * @param address The address.
 * @param prefix_length How many of its first bits the range shares: its family's whole length for one address.
 * @param transports TRANSPORT_TCP, TRANSPORT_UDP, or both.
 * @param first_port The first port.
 * @param last_port The last port.
 * @return The rule.
 */
range_rule :: fn(address: net_address.Address, prefix_length: u8, transports: u8, first_port: u16, last_port: u16) -> Rule {
    return Rule.{scope = SCOPE_RANGE, family = cast[u8](address.family), prefix_length = prefix_length, transports = transports,
        first_port = first_port, last_port = last_port, address = address.bytes}
}

/**
 * Give a rule's range's address.
 *
 * @param rule The rule, of SCOPE_RANGE.
 * @return Its address; of no family if its family isn't 4 or 6.
 */
rule_address :: fn(rule: ptr[Rule]) -> net_address.Address {
    family :: if rule.family == 4 { net_address.Family.V4 } else if rule.family == 6 { net_address.Family.V6 } else { net_address.Family.None }
    return net_address.Address.{family = family, bytes = rule.address}
}

/** A policy as a Narrow carries it: its rules, in the message. */
PolicyOf :: struct {
    /** What may be connected to, and, by UDP, heard from; at most MAX_RULES. */
    connect : slop_os.Relative[Rule],
    /** What may be listened on; an address in these isn't read; at most MAX_RULES. */
    listen : slop_os.Relative[Rule],
}

/** A policy as the service and the powerbox keep one. */
Policy :: struct {
    connect : Rule[MAX_RULES],
    connect_count : u32,
    listen : Rule[MAX_RULES],
    listen_count : u32,
}

/** The rule allowing everything: any address, any port, both transports. */
EVERYTHING_RULE :: Rule.{scope = SCOPE_ANY, transports = TRANSPORT_TCP | TRANSPORT_UDP, first_port = 0, last_port = 65535}

/**
 * Give the policy allowing everything: a root connection's.
 *
 * @return It.
 */
everything :: fn() -> Policy {
    policy := Policy.{connect_count = 1, listen_count = 1}
    policy.connect[0] = EVERYTHING_RULE
    policy.listen[0] = EVERYTHING_RULE
    return policy
}

/**
 * Give a session's default policy: connecting to any public address, on any port, by either transport, and listening
 * on nothing (decisions/0188).
 *
 * @return It.
 */
public_only :: fn() -> Policy {
    policy := Policy.{connect_count = 1}
    policy.connect[0] = Rule.{scope = SCOPE_PUBLIC, transports = TRANSPORT_TCP | TRANSPORT_UDP, first_port = 0, last_port = 65535}
    return policy
}

/**
 * Tell whether an address is public: not of RFC 6890's special ranges.
 *
 * @param address The address.
 * @return True if it's public; false for no address, or a private, loopback, link-local, shared, multicast, documentation
 *     or reserved one.
 */
is_public :: fn(address: net_address.Address) -> bool {
    b :: address.bytes
    if address.family == .V4 {
        a :: b[0]
        if a == 0 || a == 10 || a == 127 || a >= 224 {
            return false
        }
        // 100.64/10 shared, 169.254/16 link-local, 172.16/12 and 192.168/16 private, 192.0.0/24, the documentation ranges
        if (a == 100 && b[1] >= 64 && b[1] < 128) || (a == 169 && b[1] == 254) || (a == 172 && b[1] >= 16 && b[1] < 32)
            || (a == 192 && b[1] == 168) || (a == 192 && b[1] == 0 && (b[2] == 0 || b[2] == 2))
            || (a == 198 && (b[1] == 18 || b[1] == 19)) || (a == 198 && b[1] == 51 && b[2] == 100)
            || (a == 203 && b[1] == 0 && b[2] == 113) {
            return false
        }
        return true
    }
    if address.family == .V6 {
        // Global unicast only: 2000::/3, past its documentation range 2001:db8::/32
        if b[0] & 0xe0 != 0x20 {
            return false
        }
        if b[0] == 0x20 && b[1] == 0x01 && b[2] == 0x0d && b[3] == 0xb8 {
            return false
        }
        return true
    }
    return false
}

/**
 * Tell whether an address is in a rule's range.
 *
 * @param rule The rule.
 * @param address The address.
 * @return True if the rule covers it.
 */
covers_address :: fn(rule: ptr[Rule], address: net_address.Address) -> bool {
    if rule.scope == SCOPE_ANY {
        return address.family != .None
    }
    if rule.scope == SCOPE_PUBLIC {
        return is_public(address)
    }
    range :: rule_address(rule)
    return rule.scope == SCOPE_RANGE && range.family != .None && range.family == address.family
        && prefix_matches(range, address, rule.prefix_length)
}

/**
 * Tell whether two addresses share a prefix.
 *
 * @param a One.
 * @param b The other, of the same family.
 * @param bits The prefix's length in bits.
 * @return True if their first bits bits are the same.
 */
prefix_matches :: fn(a: net_address.Address, b: net_address.Address, bits: u8) -> bool {
    for i in cast[usize](0)..<16 {
        if i * 8 >= cast[usize](bits) {
            return true
        }
        remaining :: cast[usize](bits) - i * 8
        mask :: if remaining >= 8 { cast[u8](0xff) } else { cast[u8](0xff) << cast[u8](8 - remaining) }
        if a.bytes[i] & mask != b.bytes[i] & mask {
            return false
        }
    }
    return true
}

/**
 * Tell whether a policy allows connecting to an endpoint by a transport.
 *
 * @param policy The policy.
 * @param transport TRANSPORT_TCP or TRANSPORT_UDP.
 * @param to The endpoint.
 * @return True if a connect rule covers it.
 */
allows_connect :: fn(policy: ptr[Policy], transport: u8, to: net_address.Endpoint) -> bool {
    for i in cast[u32](0)..<policy.connect_count {
        if cast[usize](i) >= policy.connect.count {
            break
        }
        rule :: &policy.connect[i]
        if rule.transports & transport != 0 && to.port >= rule.first_port && to.port <= rule.last_port
            && covers_address(rule, to.address) {
            return true
        }
    }
    return false
}

/**
 * Tell whether a policy allows listening on a port by a transport.
 *
 * @param policy The policy.
 * @param transport TRANSPORT_TCP or TRANSPORT_UDP.
 * @param port The port.
 * @return True if a listen rule covers it.
 */
allows_listen :: fn(policy: ptr[Policy], transport: u8, port: u16) -> bool {
    for i in cast[u32](0)..<policy.listen_count {
        if cast[usize](i) >= policy.listen.count {
            break
        }
        rule :: &policy.listen[i]
        if rule.transports & transport != 0 && port >= rule.first_port && port <= rule.last_port {
            return true
        }
    }
    return false
}

/**
 * Tell whether one rule allows no more than another: its transports, ports and addresses within the other's.
 *
 * @param outer The rule that has to cover.
 * @param inner The rule covered.
 * @param addresses Whether addresses count, as a connect rule's do, and a listen rule's don't.
 * @return True if outer covers all of inner.
 */
rule_within :: fn(outer: ptr[Rule], inner: ptr[Rule], addresses: bool) -> bool {
    if inner.transports & ~outer.transports != 0 || inner.first_port < outer.first_port || inner.last_port > outer.last_port {
        return false
    }
    if !addresses || outer.scope == SCOPE_ANY {
        return true
    }
    inner_range :: rule_address(inner)
    if outer.scope == SCOPE_PUBLIC {
        // A range is within public addresses only if it's one public address, or a range of public addresses no
        // special range overlaps: taken here as a prefix of 16 bits or more whose address is public
        return inner.scope == SCOPE_PUBLIC || (inner.scope == SCOPE_RANGE && is_public(inner_range)
            && inner.prefix_length >= (if inner_range.family == .V4 { cast[u8](16) } else { cast[u8](32) }))
    }
    outer_range :: rule_address(outer)
    return outer.scope == SCOPE_RANGE && inner.scope == SCOPE_RANGE && outer_range.family != .None
        && inner_range.family == outer_range.family && inner.prefix_length >= outer.prefix_length
        && prefix_matches(outer_range, inner_range, outer.prefix_length)
}

/**
 * Tell whether a policy allows no more than another: each of its rules within one of the other's.
 *
 * @param outer The policy that has to cover.
 * @param inner The policy covered.
 * @return True if outer covers all of inner.
 */
within :: fn(outer: ptr[Policy], inner: ptr[Policy]) -> bool {
    for i in cast[u32](0)..<inner.connect_count {
        if cast[usize](i) >= inner.connect.count {
            return false
        }
        covered := false
        for j in cast[u32](0)..<outer.connect_count {
            if cast[usize](j) < outer.connect.count && rule_within(&outer.connect[j], &inner.connect[i], true) {
                covered = true
                break
            }
        }
        if !covered {
            return false
        }
    }
    for i in cast[u32](0)..<inner.listen_count {
        if cast[usize](i) >= inner.listen.count {
            return false
        }
        covered := false
        for j in cast[u32](0)..<outer.listen_count {
            if cast[usize](j) < outer.listen.count && rule_within(&outer.listen[j], &inner.listen[i], false) {
                covered = true
                break
            }
        }
        if !covered {
            return false
        }
    }
    return true
}

/**
 * Read a policy from a Narrow's rules.
 *
 * @param connect Its connect rules.
 * @param listen Its listen rules.
 * @return The policy; null if either has more than MAX_RULES.
 */
policy_of :: fn(connect: Rule[], listen: Rule[]) -> Policy? {
    if connect.count > MAX_RULES || listen.count > MAX_RULES {
        return null
    }
    policy := Policy.{connect_count = cast[u32](connect.count), listen_count = cast[u32](listen.count)}
    for rule, i in connect {
        if i < policy.connect.count {
            policy.connect[i] = rule
        }
    }
    for rule, i in listen {
        if i < policy.listen.count {
            policy.listen[i] = rule
        }
    }
    return policy
}

/**
 * Describe a policy, for the user who's asked to allow it: each rule, as "TCP to 10.0.2.2, port 7".
 *
 * @param policy The policy.
 * @param into Where the description's appended.
 */
describe :: fn(policy: ptr[Policy], into: ptr[mut text_buffer.TextBuffer]) {
    first := true
    for i in cast[u32](0)..<policy.connect_count {
        if cast[usize](i) >= policy.connect.count {
            break
        }
        if !first {
            text_buffer.append(into, "; ")
        }
        first = false
        describe_rule(&policy.connect[i], into, false)
    }
    for i in cast[u32](0)..<policy.listen_count {
        if cast[usize](i) >= policy.listen.count {
            break
        }
        if !first {
            text_buffer.append(into, "; ")
        }
        first = false
        describe_rule(&policy.listen[i], into, true)
    }
    if first {
        text_buffer.append(into, "nothing")
    }
}

/**
 * Describe one rule.
 *
 * @param rule The rule.
 * @param into Where it's appended.
 * @param listening Whether it's a listen rule.
 */
describe_rule :: fn(rule: ptr[Rule], into: ptr[mut text_buffer.TextBuffer], listening: bool) {
    text_buffer.append(into, if rule.transports == TRANSPORT_TCP { "TCP" } else if rule.transports == TRANSPORT_UDP { "UDP" } else { "TCP and UDP" })
    if listening {
        text_buffer.append(into, " listening")
    }
    else {
        if rule.scope == SCOPE_ANY {
            text_buffer.append(into, " to any address")
        }
        else if rule.scope == SCOPE_PUBLIC {
            text_buffer.append(into, " to any public address")
        }
        else if rule.family == 4 {
            b :: rule.address
            text_buffer.append_format(into, " to %.%.%.%", b[0], b[1], b[2], b[3])
            if rule.prefix_length < 32 {
                text_buffer.append_format(into, "/%", rule.prefix_length)
            }
        }
        else {
            text_buffer.append(into, " to an IPv6 range")
        }
    }
    if rule.first_port == 0 && rule.last_port == 65535 {
        text_buffer.append(into, ", any port")
    }
    else if rule.first_port == rule.last_port {
        text_buffer.append_format(into, ", port %", rule.first_port)
    }
    else {
        text_buffer.append_format(into, ", ports % to %", rule.first_port, rule.last_port)
    }
}

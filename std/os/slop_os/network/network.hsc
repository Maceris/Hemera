package network

import os from "std"
import slop_os from "std/os"
import net_address from "std/os/slop_os"
import tcp_stream from "std/os/slop_os"
import tcp_listener from "std/os/slop_os"
import datagrams from "std/os/slop_os"

/*
 * A connection to the network service: what a program reaches the network through. Open makes a TCP connection, into
 * memory the program gives for its rings (tcp_stream); Listen listens on a port (tcp_listener); Udp opens a socket
 * (datagrams). Each answers with a channel of its own, which moves to the program. There's no other way out: a program
 * without a connection to the service reaches nothing. Each connection has a policy (policy.hsc), which every Open,
 * Listen and Udp, and each datagram, is checked against; Narrow makes another with less.
 *
 * Names are resolved by the service (decisions/0188, 13e): Resolve gives a name's addresses, and OpenName connects to
 * one, trying its addresses as RFC 8305's Happy Eyeballs does, each checked against the policy as a name's are
 * (allows_named), so a name answered with a local address reaches only what the policy names.
 */

/** The network protocol, for the channels between a program and the network service, and the service's listener. */
Network :: struct {}

/**
 * What the protocol says of itself: its name, which its channels' tag is made from, its major version, and that the
 * program's budget is lent for each of its connections.
 */
PROTOCOL :: slop_os.Protocol.{name = "network", major_version = 1, lending = .PerConnection}

/**
 * The ring every network connection is made with: 8 KiB, so a Narrow with MAX_RULES of each kind, some 3 KiB with their
 * names, fits a message, which is at most half the ring.
 */
RING_BYTES : u32 : 8192

/** A TCP connection to open. */
OpenTo :: struct {
    /** Who to. */
    to : net_address.Endpoint,
    /**
     * The connection's memory, which moves to the service: at least two pages, a whole number of them, two rings of half
     * its size each, as the service finds it.
     */
    memory : slop_os.Memory,
}

/** A host to connect to by name. */
OpenNamed :: struct {
    /** Its name, as text: any case, a final dot or not, at most MAX_NAME bytes. */
    name : slop_os.Relative[u8],
    /** The port, 1 to 65535. */
    port : u16,
    /** The connection's memory, as OpenTo's. */
    memory : slop_os.Memory,
}

/** The longest name Resolve and OpenName take, as text without a final dot. */
MAX_NAME :: 253

/** Which of a name's addresses Resolve wants. */
Kinds :: enum #backed_by(u8) {
    /** Its IPv4 addresses. */
    V4 = 1,
    /** Its IPv6 addresses. */
    V6 = 2,
    /** Both. */
    Both = 3,
}

/** A name to resolve. */
ResolveName :: struct {
    /** The name, as text: any case, a final dot or not, at most MAX_NAME bytes. */
    name : slop_os.Relative[u8],
    kinds : Kinds,
}

/** The most addresses Resolved gives. */
MAX_ADDRESSES :: 8

/** An address as Resolved carries it: plain bytes, as a message's items are. */
ResolvedAddress :: struct {
    /** Its family, a net_address.Family's value: 4 or 6. */
    family : u8,
    /** Its bytes, IPv4's in the first 4. */
    bytes : u8[16],
}

/**
 * Give a resolved address as an address.
 *
 * @param resolved It.
 * @return The address; of no family if its family isn't 4 or 6.
 */
address_of :: fn(resolved: ResolvedAddress) -> net_address.Address {
    family :: if resolved.family == 4 { net_address.Family.V4 } else if resolved.family == 6 { net_address.Family.V6 }
        else { net_address.Family.None }
    return net_address.Address.{family = family, bytes = resolved.bytes}
}

/** Why a request was refused. */
Refusal :: enum #backed_by(u8) {
    /** The connection's policy doesn't allow it. */
    NotAllowed = 0,
    /** The port's listened on, or bound, already. */
    PortTaken = 1,
    /** There's no address to send from, or no route: no interface, or no address of the family. */
    NoRoute = 2,
    /** The service has no room for another connection, listener or socket. */
    NoRoom = 3,
    /** The memory isn't two pages or more, or couldn't be mapped. */
    BadMemory = 4,
    /** The endpoint isn't one: no address, or port 0. */
    BadEndpoint = 5,
    /** The name doesn't exist. */
    NoSuchName = 6,
    /** The name has no address of the kinds asked for. */
    NoAddress = 7,
    /** No DNS server answered, or every one failed: maybe for now. */
    ResolveFailed = 8,
    /** The name isn't one: empty, too long, or with a character or label names don't have. */
    BadName = 9,
}

/** What a program asks of the network service. */
Request :: union {
    /**
     * Open a TCP connection. Answered with Opened at once, its progress then said on its channel, or with Refused.
     */
    Open(OpenTo),
    /** Listen on a TCP port, 1 to 65535. Answered with Listening, or Refused. */
    Listen(u16),
    /** Open a UDP socket on a port, or an ephemeral one for 0. Answered with Bound, or Refused. */
    Udp(u16),
    /**
     * Make another connection, allowed only what the policy given allows, which has to be within this one's (policy.hsc).
     * Answered with Narrowed, or Refused NotAllowed if it isn't within, or has more than MAX_RULES of a kind.
     */
    Narrow(PolicyOf),
    /** Make another connection with this one's policy, to give a program. Answered with Narrowed. */
    Copy,
    /**
     * Give a name's addresses, IPv6 and IPv4 taking turns, IPv6 first. Answered with Resolved once its servers have
     * answered, or Refused: NotAllowed if the policy allows connecting nowhere, or why it wasn't resolved.
     */
    Resolve(ResolveName),
    /**
     * Open a TCP connection to a host by name: its addresses tried as Happy Eyeballs does (RFC 8305), IPv6 first, the
     * next started each 250 ms the last isn't connected, until one is, the others then dropped. Each address is checked
     * against the policy (allows_named), and those it doesn't allow aren't tried. Answered with Opened once the name's
     * resolved, its progress then said on its channel, or with Refused: NotAllowed if the policy allows none of its
     * addresses, or why it wasn't resolved.
     */
    OpenName(OpenNamed),
    /**
     * Have the service serve another client, on the end given, which moves to it. Sent on the listener, and answered
     * with nothing.
     */
    Connect(os.Channel[Network]),
}

/** What the network service answers. */
Response :: union {
    /** Open's answer: the connection's channel. */
    Opened(os.Channel[tcp_stream.TcpStream]),
    /** Listen's answer: the listener's channel. */
    Listening(os.Channel[tcp_listener.TcpListener]),
    /** Udp's answer: the socket's channel. */
    Bound(os.Channel[datagrams.Datagrams]),
    /** Narrow's and Copy's answer: the new connection. */
    Narrowed(os.Channel[Network]),
    /** Resolve's answer: the name's addresses, at most MAX_ADDRESSES, IPv6 first. */
    Resolved(slop_os.Relative[ResolvedAddress]),
    /** An answer refusing Open, Listen, Udp, Narrow, Resolve or OpenName. */
    Refused(Refusal),
    /** The answer to a request the service doesn't know; every protocol has it. */
    Unsupported,
}

/**
 * Tell whether a request may be sent again, after a reconnect, without doing more than sending it once did.
 *
 * @param request The request, which isn't changed.
 * @return False for Open, Listen, Udp, Narrow, Copy and OpenName, each of which makes something new; true for Resolve
 *     and Connect.
 */
is_idempotent :: fn(request: ptr[Request]) -> bool {
    return match request^ {
        case Open(_) => false
        case Listen(_) => false
        case Udp(_) => false
        case Narrow(_) => false
        case Copy => false
        case Resolve(_) => true
        case OpenName(_) => false
        case Connect(_) => true
    }
}

#insert os.protocol_code(Request, Response)

/**
 * Make a new connection to the network service: a channel for the protocol, one end sent to it in a Connect.
 *
 * It doesn't wait: the service takes the end when it next serves its listener.
 *
 * @param end The service's listener, or any connection to it, kept by the caller.
 * @param port A port bound to end, waited on while end's ring is full.
 * @param budget The memory budget that pays for the new channel.
 * @return The caller's end of the new connection, its own to keep and close; null if the channel couldn't be made, or
 *     the Connect couldn't be sent, in which case both its ends are closed.
 */
connect :: fn(end: slop_os.Channel, port: slop_os.Port, budget: slop_os.MemoryBudget) -> os.Channel[Network]? {
    pair :: os.channel_for[Network](budget, RING_BYTES) or_return null
    out := os.Outgoing.{}
    request :: os.begin[Request](&out)
    request^ = .Connect(os.Channel[Network].{end = pair.a})
    match send_request(end, port, &out) {
        case Some(error) => {
            _ = slop_os.handle_close(cast[slop_os.Handle](pair.a))
            _ = slop_os.handle_close(cast[slop_os.Handle](pair.b))
            return null
        }
        case None => return os.Channel[Network].{end = pair.b}
    }
}

/**
 * Make another connection to the network service allowing only what a policy does, and wait for it.
 *
 * @param end A connection to the service, the caller's, with no other answer due before this one's.
 * @param port A port bound to end, waited on.
 * @param policy What the new connection allows: within end's own, MAX_RULES of each kind at most.
 * @return The new connection, the caller's; null if it was refused, as the policy isn't within end's, or the request
 *     couldn't be sent or answered.
 */
narrow :: fn(end: slop_os.Channel, port: slop_os.Port, policy: ptr[Policy]) -> os.Channel[Network]? {
    out := os.Outgoing.{}
    request :: os.begin[Request](&out)
    connect_count :: if cast[usize](policy.connect_count) < policy.connect.count { cast[usize](policy.connect_count) } else { policy.connect.count }
    listen_count :: if cast[usize](policy.listen_count) < policy.listen.count { cast[usize](policy.listen_count) } else { policy.listen.count }
    // Each count is at most its array's, as it's clamped above
    connect :: os.append(&out, view_of(&policy.connect[0], connect_count))
    listen :: os.append(&out, view_of(&policy.listen[0], listen_count))
    request^ = .Narrow(PolicyOf.{connect = connect, listen = listen})
    return made_connection(end, port, &out)
}

/**
 * Make another connection to the network service with the same policy as one's, to give a program, and wait for it.
 *
 * @param end A connection to the service, the caller's, with no other answer due before this one's.
 * @param port A port bound to end, waited on.
 * @return The new connection, the caller's; null if the request couldn't be sent or answered, or the service had no
 *     room.
 */
copy :: fn(end: slop_os.Channel, port: slop_os.Port) -> os.Channel[Network]? {
    out := os.Outgoing.{}
    os.begin[Request](&out)^ = .Copy
    return made_connection(end, port, &out)
}

/**
 * Send Narrow or Copy, and take the connection it's answered with.
 *
 * @param end The connection asked.
 * @param port A port bound to end.
 * @param out The request, built.
 * @return The new connection; null if it wasn't given.
 */
made_connection :: fn(end: slop_os.Channel, port: slop_os.Port, out: ptr[mut os.Outgoing]) -> os.Channel[Network]? {
    if send_request(end, port, out) is_some {
        return null
    }
    into := os.Incoming.{}
    match receive_response(end, port, &into, true) {
        case Received => {}
        case _ => return null
    }
    return match os.message_of[Response](&into)^ {
        case Narrowed(made) => made
        case _ => null
    }
}

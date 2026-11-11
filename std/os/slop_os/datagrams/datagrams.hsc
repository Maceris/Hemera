package datagrams

import os from "std"
import slop_os from "std/os"
import net_address from "std/os/slop_os"

/*
 * A UDP socket's channel, between the network service and the program it's for: datagrams sent and received, each in
 * one message. A Receive is held until a datagram arrives; those arriving with no Receive held wait in the service, a
 * few, and past them are dropped, as UDP allows.
 */

/** The datagrams protocol, for a UDP socket's channel. */
Datagrams :: struct {}

/** What the protocol says of itself. */
PROTOCOL :: slop_os.Protocol.{name = "datagrams", major_version = 1, lending = .PerConnection}

/** The most bytes a datagram carries: an Ethernet MTU less IPv4's and UDP's headers. */
MAX_DATAGRAM :: 1472
/** The ring every socket's channel is made with: 8 KiB, so a datagram's message fits, at most half of it. */
RING_BYTES : u32 : 8192

/** A datagram to send. */
SendTo :: struct {
    to : net_address.Endpoint,
    /** Its payload, at most MAX_DATAGRAM bytes; more is cut off. */
    bytes : slop_os.Relative[u8],
}

/** A datagram that arrived. */
Arrived :: struct {
    from : net_address.Endpoint,
    bytes : slop_os.Relative[u8],
}

/** What the program asks of its socket. */
Request :: union {
    /** Send a datagram. Not answered: one that can't be sent is dropped, as one lost would be. */
    Send(SendTo),
    /** Take the next datagram. Held until one arrives; answered with Datagram. */
    Receive,
    /** Ask the socket's own endpoint. Answered with Described. */
    Describe,
}

/** What the network service answers. */
Response :: union {
    /** Receive's answer. */
    Datagram(Arrived),
    /** Describe's answer: the interface's address, and the socket's port. */
    Described(net_address.Endpoint),
    /** The answer to a request the service doesn't know; every protocol has it. */
    Unsupported,
}

/**
 * Tell whether a request may be sent again, after a reconnect, without doing more than sending it once did.
 *
 * @param request The request, which isn't changed.
 * @return False for Send, whose datagram would go twice; true for the rest.
 */
is_idempotent :: fn(request: ptr[Request]) -> bool {
    return match request^ {
        case Send(_) => false
        case Receive => true
        case Describe => true
    }
}

#insert os.protocol_code(Request, Response)

package tcp_listener

import os from "std"
import slop_os from "std/os"
import net_address from "std/os/slop_os"
import tcp_stream from "std/os/slop_os"

/*
 * A listening TCP port's channel, between the network service and the program listening. Each Accept gives the memory
 * for one connection's rings, as tcp_stream has them, and is held until a connection arrives; one arriving with no
 * Accept held waits a few seconds for one, then is refused.
 */

/**
 * The tcp_listener protocol, for a listening port's channel: the program sends the requests, and the network service
 * answers them.
 */
TcpListener :: struct {}

/** What the protocol says of itself. */
PROTOCOL :: slop_os.Protocol.{name = "tcp_listener", major_version = 1, lending = .PerConnection}

/** A connection accepted. */
Accepted :: struct {
    /** The connection's channel, which moves to the program. */
    stream : os.Channel[tcp_stream.TcpStream],
    /** Who connected. */
    remote : net_address.Endpoint,
}

/** What the program asks of its listener. */
Request :: union {
    /**
     * Take the next connection, into this memory, which moves to the service: at least two pages, a whole number of
     * them, two rings of half its size each. Held until one arrives; answered with Accepted, or Refused.
     */
    Accept(slop_os.Memory),
}

/** Why an Accept was refused. */
Refusal :: enum #backed_by(u8) {
    /** The memory isn't two pages or more, or couldn't be mapped. */
    BadMemory = 0,
    /** Too many Accepts are held already. */
    TooMany = 1,
}

/** What the network service answers. */
Response :: union {
    /** Accept's answer: the connection. */
    Accepted(Accepted),
    /** Accept's answer when its memory won't do. */
    Refused(Refusal),
    /** The answer to a request the service doesn't know; every protocol has it. */
    Unsupported,
}

/**
 * Tell whether a request may be sent again, after a reconnect, without doing more than sending it once did.
 *
 * @param request The request, which isn't changed.
 * @return True.
 */
is_idempotent :: fn(request: ptr[Request]) -> bool {
    return true
}

#insert os.protocol_code(Request, Response)

package tcp_stream

import os from "std"
import slop_os from "std/os"
import net_address from "std/os/slop_os"

/*
 * A TCP connection's channel, between the network service and the program it's for. The program's memory, given when
 * the connection was asked for, holds two rings of bytes, each half of it: the first what the program writes, the
 * second what arrives for it. Both sides map it; neither copies. The program says how far it has written and read, in
 * bytes from the start (Wrote and Read); the service says how far it has delivered into the second ring and had
 * acknowledged from the first (Progress), as a held Watch is answered once anything differs from what it holds.
 *
 * The program writes only into the room past what's acknowledged, and reads only what's delivered. Finish says it's
 * written its last byte; the connection ends once the peer has finished too, every byte acknowledged. Abort resets it.
 * Closing the channel aborts a connection not yet ended.
 */

/**
 * The tcp_stream protocol, for a TCP connection's channel: the program sends the requests, and the network service
 * answers them.
 */
TcpStream :: struct {}

/**
 * What the protocol says of itself: its name, which its channels' tag is made from, its major version, and that the
 * program's budget is lent for each of its connections, which pays for the service's work on it.
 */
PROTOCOL :: slop_os.Protocol.{name = "tcp_stream", major_version = 1, lending = .PerConnection}

/** Why a connection ended. */
Ending :: enum #backed_by(u8) {
    /** It hasn't. */
    None = 0,
    /** Both sides finished, and every byte was acknowledged. */
    Closed = 1,
    /** The peer reset it. */
    Reset = 2,
    /** The peer refused it: nothing listens on its port. */
    Refused = 3,
    /** Nothing answered. */
    TimedOut = 4,
    /** The program, or the service, reset it. */
    Aborted = 5,
}

/** How far a connection has got. */
Progress :: struct {
    /** The bytes delivered into the second ring, from the start; those past what the program has read are waiting. */
    delivered : u64,
    /** The bytes of the first ring the peer has acknowledged, from the start; the room past them is the program's. */
    acknowledged : u64,
    /** Whether it's open: the handshake is done. */
    connected : bool,
    /** Whether the peer has finished: past delivered, nothing more arrives. */
    peer_finished : bool,
    /** Why it ended, None while it hasn't; ended, it changes no more. */
    ending : Ending,
}

/** A connection's ends and rings. */
StreamInfo :: struct {
    /** Its own end: the interface's address and its port. */
    local : net_address.Endpoint,
    /** The peer's. */
    remote : net_address.Endpoint,
    /** The bytes of each ring: half the memory. */
    ring_bytes : u64,
}

/** What the program asks of its connection. */
Request :: union {
    /** Wait for its progress to differ from what's given. Answered with Progress, once it does, maybe at once. */
    Watch(Progress),
    /**
     * Say how far the program has written into the first ring, from the start: no less than before, and at most a
     * ring past what's acknowledged. Not answered.
     */
    Wrote(u64),
    /** Say how far it has read from the second ring, from the start: no more than delivered. Not answered. */
    Read(u64),
    /** Say the program has written its last byte. Not answered. */
    Finish,
    /** Reset the connection. Not answered. */
    Abort,
    /** Ask its ends and rings. Answered with Described. */
    Describe,
}

/** What the network service answers. */
Response :: union {
    /** Watch's answer: the connection's progress. */
    Progress(Progress),
    /** Describe's answer. */
    Described(StreamInfo),
    /** The answer to a request the service doesn't know; every protocol has it. */
    Unsupported,
}

/**
 * Tell whether a request may be sent again, after a reconnect, without doing more than sending it once did.
 *
 * @param request The request, which isn't changed.
 * @return True: each says where things are, rather than what to do once more, but Abort, which can't be undone anyway.
 */
is_idempotent :: fn(request: ptr[Request]) -> bool {
    return true
}

#insert os.protocol_code(Request, Response)

/**
 * Tell whether two progresses are the same.
 *
 * @param a One.
 * @param b The other.
 * @return True if every field is.
 */
same_progress :: fn(a: Progress, b: Progress) -> bool {
    return a.delivered == b.delivered && a.acknowledged == b.acknowledged && a.connected == b.connected
        && a.peer_finished == b.peer_finished && a.ending == b.ending
}

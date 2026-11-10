package grant

import os from "std"
import slop_os from "std/os"
import files from "std/os/slop_os"

/**
 * The grant protocol, for os.Channel[Grant]: a grant (the SlopOS repository's roadmap 8f).
 *
 * A grant is what a directory's Grant gives, to hand to a directory in another volume, whose Link keeps it as a
 * stored link. Its holder can make one link from it; it's good until then, or until it's closed. Only the server
 * keeping the link speaks it: Claim gives what that server takes to the storage service, which has the link issued.
 */
Grant :: struct {}

/**
 * What the protocol says of itself: its name, which its channels' tag is made from, its major version, and that the
 * client's budget pays for the server's work, for each of its connections.
 */
PROTOCOL :: slop_os.Protocol.{name = "grant", major_version = 1, lending = .PerConnection}

/**
 * What a claim gives: the volume the grant is from, by its container and ID, a ticket for its one link, and whether
 * it writes.
 */
Claim :: struct {
    /** The ID of the container the granting volume is in, 16 bytes as the storage service names it. */
    container : u8[16],
    /** The granting volume's ID within its container. */
    volume : u64,
    /** The ticket the storage service takes, once, to issue the grant's one link; opaque to its holder. */
    ticket : u8[32],
    /** Whether the link may write what it leads to, as the directory's Grant asked; false, only read it. */
    write : bool,
}

/** What a holder of a grant asks of it. */
Request :: union {
    /**
     * The grant's claim, for the server that keeps the link to take to the storage service. Answered with Claimed,
     * or Failed once it's been claimed or what it grants is gone.
     */
    Claim,
}

/** What the grant's server answers. */
Response :: union {
    /** Claim's answer: the claim, to take to the storage service; the grant can't be claimed again. */
    Claimed(Claim),
    /** Claim's answer when the grant was claimed already, or what it grants is gone. */
    Failed(files.FileError),
    /** The answer to a request the server doesn't know, as from a newer client; every protocol has it. */
    Unsupported,
}

/**
 * Tell whether a request may be sent again, after a reconnect, without doing more than sending it once did.
 *
 * @param request The request, which isn't changed.
 * @return False always: a grant is claimed once, so a Claim sent again would fail, or claim a second time.
 */
is_idempotent :: fn(request: ptr[Request]) -> bool {
    return false
}

#insert os.protocol_code(Request, Response)

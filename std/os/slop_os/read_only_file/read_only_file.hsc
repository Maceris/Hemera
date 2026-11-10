package read_only_file

import os from "std"
import slop_os from "std/os"
import files from "std/os/slop_os"

/**
 * The read_only_file protocol, for os.Channel[ReadOnlyFile]: a file to read (the SlopOS repository's decisions
 * 0015, 0087), the reading subset of file.
 *
 * The client gives the connection a buffer, a memory object it has mapped, once; Read names where in it. Nothing
 * on such a connection changes the file.
 */
ReadOnlyFile :: struct {}

/**
 * What the protocol says of itself: its name, which its channels' tag is made from, its major version, and that the
 * client's budget pays for the server's work, for each of its connections.
 */
PROTOCOL :: slop_os.Protocol.{name = "read_only_file", major_version = 1, lending = .PerConnection}

/** What a client asks of a file it may only read. */
Request :: union {
    /**
     * The memory Read moves bytes into, from now on, in place of any given before: a handle to a memory object,
     * moved to the server, which maps it. Answered with Done, or Failed(NoBuffer) if it can't be used.
     */
    UseBuffer(slop_os.Memory),
    /**
     * Bytes of the file, from the Transfer's offset, into the buffer at its buffer_offset: at most its count, fewer
     * at the file's end, and none from there on. Answered with Transferred and how many, or Failed: NoBuffer before
     * UseBuffer or for a range past the buffer's end.
     */
    Read(files.Transfer),
    /** What the file is: its kind, size, name and schema. Answered with Described, or Failed. */
    Info,
    /**
     * Serve another client, on the end given, which moves to the server: a new connection to the same file, which
     * also only reads. Not answered.
     */
    Connect(os.Channel[ReadOnlyFile]),
}

/** What a read-only file's server answers. */
Response :: union {
    /** The answer to UseBuffer: the buffer's in use. */
    Done,
    /** The answer to Read: how many bytes moved, from 0 to the Transfer's count, fewer only at the file's end. */
    Transferred(u32),
    /** The answer to Info: what the file is, its name in the message's variable-size data. */
    Described(files.Info),
    /** The answer to a request that failed, and why. */
    Failed(files.FileError),
    /** The answer to a request the server doesn't know, as from a newer client; every protocol has it. */
    Unsupported,
}

/**
 * Tell whether a request may be sent again, after a reconnect, without doing more than sending it once did.
 *
 * @param request The request, which isn't changed.
 * @return True for every request: none of them changes the file.
 */
is_idempotent :: fn(request: ptr[Request]) -> bool {
    return match request^ {
        case UseBuffer(_) => true
        case Read(_) => true
        case Info => true
        case Connect(_) => true
    }
}

#insert os.protocol_code(Request, Response)

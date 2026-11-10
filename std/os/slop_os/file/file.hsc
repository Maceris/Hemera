package file

import os from "std"
import slop_os from "std/os"
import files from "std/os/slop_os"
import read_only_file from "std/os/slop_os"

/**
 * The file protocol, for os.Channel[File]: a file to read and write (the SlopOS repository's decisions 0015, 0046,
 * 0087).
 *
 * The client gives the connection a buffer, a memory object it has mapped, once; Read and Write name where in it.
 * Writing past the end grows the file. A server answers a connection's requests one at a time, in order.
 */
File :: struct {}

/**
 * What the protocol says of itself: its name, which its channels' tag is made from, its major version, and that the
 * client's budget pays for the server's work, for each of its connections.
 */
PROTOCOL :: slop_os.Protocol.{name = "file", major_version = 1, lending = .PerConnection}

/** What a client asks of a file. */
Request :: union {
    /**
     * The memory Read and Write move bytes through, from now on, in place of any given before: a handle to a memory
     * object, moved to the server, which maps it. Answered with Done, or Failed(NoBuffer) if it can't be used.
     */
    UseBuffer(slop_os.Memory),
    /**
     * Bytes of the file, from the Transfer's offset, into the buffer at its buffer_offset: at most its count, fewer
     * at the file's end, and none from there on. Answered with Transferred and how many, or Failed: NoBuffer before
     * UseBuffer or for a range past the buffer's end.
     */
    Read(files.Transfer),
    /**
     * Bytes from the buffer at the Transfer's buffer_offset into the file at its offset, count of them, growing the
     * file if they go past its end. Answered with Transferred and how many were written, or Failed: NoBuffer as for
     * Read, NoSpace, ReadOnly or DeviceError.
     */
    Write(files.Transfer),
    /**
     * The file made this many bytes long: if shorter, cut there; if longer, zeros after its old end. Answered with
     * Done or Failed.
     */
    SetSize(u64),
    /** What the file is: its kind, size, name and schema. Answered with Described, or Failed. */
    Info,
    /**
     * Everything written to the file before it, on stable storage. Answered with Done once it is, or
     * Failed(DeviceError).
     */
    Sync,
    /**
     * A new connection to the same file that only reads. Answered with Narrowed and its end, which the client then
     * owns, or Failed(NoSpace) when the server can't take another connection.
     */
    Narrow,
    /**
     * Serve another client, on the end given, which moves to the server: a new connection to the same file, with a
     * buffer of its own to give. Not answered.
     */
    Connect(os.Channel[File]),
    /**
     * On a connection a directory's Replace gave: this file swapped in for the one at its path, whole, and made
     * durable, so a reader sees the old file or the new one, never a mix. Answered with Done or Failed; Unsupported
     * on a file system without atomic replacement.
     */
    Install,
}

/** What a file's server answers. */
Response :: union {
    /** The answer to UseBuffer, SetSize, Sync and Install: it's done. */
    Done,
    /**
     * The answer to Read and Write: how many bytes moved, from 0 to the Transfer's count. A Read gives fewer only
     * at the file's end.
     */
    Transferred(u32),
    /** The answer to Info: what the file is, its name in the message's variable-size data. */
    Described(files.Info),
    /** The answer to Narrow: the new read-only connection's end, which the client owns and closes. */
    Narrowed(os.Channel[read_only_file.ReadOnlyFile]),
    /** The answer to a request that failed, and why. */
    Failed(files.FileError),
    /** The answer to a request the server doesn't know, as from a newer client; every protocol has it. */
    Unsupported,
}

/**
 * Tell whether a request may be sent again, after a reconnect, without doing more than sending it once did.
 *
 * Writing the same bytes to the same place again, or setting the same size, changes nothing more; an Install sent
 * again would find the replacement already made.
 *
 * @param request The request, which isn't changed.
 * @return True for every request but Install.
 */
is_idempotent :: fn(request: ptr[Request]) -> bool {
    return match request^ {
        case UseBuffer(_) => true
        case Read(_) => true
        case Write(_) => true
        case SetSize(_) => true
        case Info => true
        case Sync => true
        case Narrow => true
        case Connect(_) => true
        case Install => false
    }
}

#insert os.protocol_code(Request, Response)

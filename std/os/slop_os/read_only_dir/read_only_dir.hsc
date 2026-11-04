package read_only_dir

// Only for SlopOS, where std/os has what its generated code needs (base.OS: the #insert could declare an OS of its own)
#if base.OS == .SlopOS {
    import os from "std"
    import slop_os from "std/os"
    import file_set from "std/os/slop_os"
    import files from "std/os/slop_os"
    import read_only_file from "std/os/slop_os"

    /**
     * The read_only_dir protocol, for os.Channel[ReadOnlyDir]: a directory to read (the SlopOS repository's decisions
     * 0015, 0046, 0087).
     *
     * It's the subset of dir that changes nothing, and whose opens give only connections that read, so a directory
     * handed on as one can't be written through. Paths in requests are UTF-8, relative, their components separated by
     * '/', at most PATH_BYTES bytes.
     */
    ReadOnlyDir :: struct {}

    /**
     * What the protocol says of itself: its name, which its channels' tag is made from, its major version, and that the
     * client's budget pays for the server's work, for each of its connections.
     */
    PROTOCOL :: slop_os.Protocol.{name = "read_only_dir", major_version = 1, lending = .PerConnection}

    /** What a client asks of a directory it may only read. */
    Request :: union {
        /** A file, by its path beneath this directory, to read. Answered with OpenedReadOnlyFile, or Failed. */
        OpenReadOnlyFile(slop_os.Relative[u8]),
        /**
         * The directory at a path beneath this one, also only to read; it isn't made if it isn't there. Answered with
         * OpenedDirectory, or Failed.
         */
        OpenDirectory(slop_os.Relative[u8]),
        /**
         * The entry of this directory at or after a cursor: 0 for the first, then each Listed's next. Answered with
         * Listed, End once none is left, or Failed.
         */
        List(u64),
        /** What this directory is: its kind and name. Answered with Described. */
        Info,
        /**
         * The files of this directory whose names match a pattern, UTF-8, as file_set matches them, on a new
         * connection whose OpenFile is refused (ReadOnly). Answered with Selected, or Failed.
         */
        Select(slop_os.Relative[u8]),
        /** What the file system does beyond the protocols' least. Answered with Supports. */
        Features,
        /**
         * Serve another client, on the end given, which moves to the server: the same directory, also only to read.
         * Not answered.
         */
        Connect(os.Channel[ReadOnlyDir]),
        /**
         * The first change beneath this directory at or after a cursor, as dir has it. Answered with Changed, UpToDate,
         * Resync or Failed, as dir's Changes is; Unsupported on a file system without change cursors.
         */
        Changes(u64),
    }

    /** What a read-only directory's server answers. */
    Response :: union {
        /** The answer to OpenReadOnlyFile: the file's new connection, whose end the client owns and closes. */
        OpenedReadOnlyFile(os.Channel[read_only_file.ReadOnlyFile]),
        /** The answer to OpenDirectory: the directory's new read-only connection, whose end the client owns. */
        OpenedDirectory(os.Channel[ReadOnlyDir]),
        /** The answer to List: an entry, and the cursor for the next. */
        Listed(files.Listing),
        /** The answer to List when there's no entry at or after the cursor. */
        End,
        /** The answer to Info: what the directory is, its name in the message's variable-size data. */
        Described(files.Info),
        /** The answer to Select: the set's connection's end, which the client owns and closes. */
        Selected(os.Channel[file_set.FileSet]),
        /** The answer to Features. */
        Supports(files.Features),
        /** The answer to a request that failed, and why. */
        Failed(files.FileError),
        /** The answer to a request the server doesn't know, or that needs a feature its file system hasn't. */
        Unsupported,
        /** The answer to Changes: a change, and the cursor after it. */
        Changed(files.Change),
        /** The answer to Changes when there's no change since the cursor: the cursor to ask from next. */
        UpToDate(u64),
        /** The answer to Changes when the cursor is older than what's kept: list again, and ask from the one given. */
        Resync(u64),
    }

    /**
     * Tell whether a request may be sent again, after a reconnect, without doing more than sending it once did.
     *
     * @param request The request, which isn't changed.
     * @return True for every request: none of them changes anything.
     */
    is_idempotent :: fn(request: ptr[Request]) -> bool {
        return match request^ {
            case OpenReadOnlyFile(_) => true
            case OpenDirectory(_) => true
            case List(_) => true
            case Info => true
            case Select(_) => true
            case Features => true
            case Connect(_) => true
            case Changes(_) => true
        }
    }

    #insert os.protocol_code(Request, Response)

    /**
     * Make a new connection to the directory a connection reaches, the same directory, with a Connect.
     *
     * The Connect isn't answered, so a server that won't take the connection is learned of only when the new end finds
     * its other end closed.
     *
     * @param end A connection to the directory, kept by the caller; only the Connect is sent on it.
     * @param port A port bound to end (port_for), waited on while end's ring is full.
     * @param budget The memory budget that pays for the new channel.
     * @return The new connection's end, which the caller owns and closes; null if the channel couldn't be made or the
     *     Connect couldn't be sent, and then nothing is left open.
     */
    connect :: fn(end: slop_os.Channel, port: slop_os.Port, budget: slop_os.MemoryBudget) -> os.Channel[ReadOnlyDir]? {
        pair :: os.channel_for[ReadOnlyDir](budget, 0) or_return null
        out := os.Outgoing.{}
        request :: os.begin[Request](&out)
        request^ = .Connect(os.Channel[ReadOnlyDir].{end = pair.a})
        match send_request(end, port, &out) {
            case Some(error) => {
                _ = slop_os.handle_close(cast[slop_os.Handle](pair.a))
                _ = slop_os.handle_close(cast[slop_os.Handle](pair.b))
                return null
            }
            case None => return os.Channel[ReadOnlyDir].{end = pair.b}
        }
    }
}

package dir

// Only for SlopOS, where std/os has what its generated code needs (base.OS: the #insert could declare an OS of its own)
#if base.OS == .SlopOS {
    import os from "std"
    import slop_os from "std/os"
    import file from "std/os/slop_os"
    import file_set from "std/os/slop_os"
    import files from "std/os/slop_os"
    import grant from "std/os/slop_os"
    import read_only_dir from "std/os/slop_os"
    import read_only_file from "std/os/slop_os"

    /**
     * The dir protocol, for os.Channel[Dir]: a directory (the SlopOS repository's decisions 0015, 0046, 0087).
     *
     * A directory is a tree beneath it, every path resolved within it, and nothing above it. Opening a file or a
     * directory gives a connection of its own; Narrow gives this directory as a read_only_dir. Paths in requests are
     * UTF-8, relative, their components separated by '/', at most PATH_BYTES bytes.
     */
    Dir :: struct {}

    /**
     * What the protocol says of itself: its name, which its channels' tag is made from, its major version, and that the
     * client's budget pays for the server's work, for each of its connections.
     */
    PROTOCOL :: slop_os.Protocol.{name = "dir", major_version = 1, lending = .PerConnection}

    /** What OpenFile opens: a file at a path, how what's there is treated, and the type it holds. */
    OpenFile :: struct {
        /** The file's path beneath this directory. */
        path : slop_os.Relative[u8],
        /** Whether the file has to be there, has to be new, or either, and whether it's emptied. */
        creation : files.Creation,
        /**
         * A typed file's schema hash (the SlopOS repository's 0046, 0108): one made has it, one there already must have
         * it (WrongType); all zeros asks for neither.
         */
        schema : u8[32],
    }

    /** What OpenDirectory opens: a directory at a path, and whether it's made. */
    OpenDirectory :: struct {
        /** The directory's path beneath this one. */
        path : slop_os.Relative[u8],
        /** Whether it's made, with any missing directory before it, if it isn't there; false, NotFound if it isn't. */
        create : bool,
    }

    /** What Rename moves: what's at one path, to another. */
    Rename :: struct {
        /** The path, beneath this directory, of what's moved; something has to be there (NotFound). */
        from : slop_os.Relative[u8],
        /** The path, beneath this directory, it's moved to; a file there is replaced. */
        to : slop_os.Relative[u8],
    }

    /** What's at a path beneath this directory granted, to write as well as read if write. */
    GrantOf :: struct {
        /** The path, beneath this directory, of the file or directory granted. */
        path : slop_os.Relative[u8],
        /** Whether the link made from the grant may write what it leads to; false, only read it. */
        write : bool,
    }

    /** A grant kept as a stored link at a path beneath this directory. */
    LinkTo :: struct {
        /** Where the link goes, beneath this directory. */
        path : slop_os.Relative[u8],
        /** The grant, from another volume's directory's Grant, moved to the server, which claims it. */
        grant : os.Channel[grant.Grant],
    }

    /**
     * What a client asks of a directory.
     *
     * Stored links (the SlopOS repository's roadmap 8f, design/security.md §8) are made with Grant and Link, listed
     * with Links and revoked with Revoke. A link opens as what it leads to, wherever it's on a path, and Remove and
     * Rename act on the link itself. What was reached through a link can't be granted on, and its links aren't listed
     * or revoked through it (ReadOnly).
     */
    Request :: union {
        /** A file beneath this directory, to read and write. Answered with OpenedFile, or Failed. */
        OpenFile(OpenFile),
        /** A file, by its path beneath this directory, to read. Answered with OpenedReadOnlyFile, or Failed. */
        OpenReadOnlyFile(slop_os.Relative[u8]),
        /** A directory beneath this one, made first if asked. Answered with OpenedDirectory, or Failed. */
        OpenDirectory(OpenDirectory),
        /**
         * The entry of this directory at or after a cursor: 0 for the first, then each Listed's next. Answered with
         * Listed, End once none is left, or Failed.
         */
        List(u64),
        /** What this directory is: its kind and name. Answered with Described. */
        Info,
        /**
         * A file, or an empty directory, at a path beneath this one, removed. Answered with Done, or Failed: NotFound
         * when nothing's there, DirectoryNotEmpty for a directory with entries.
         */
        Remove(slop_os.Relative[u8]),
        /**
         * What's at one path beneath this one moved to another, replacing a file there. Answered with Done, or
         * Failed.
         */
        Rename(Rename),
        /** This directory, only to read, on a new connection. Answered with Narrowed, or Failed. */
        Narrow,
        /**
         * The files of this directory whose names match a pattern, UTF-8, as file_set matches them, on a new
         * connection. Answered with Selected, or Failed.
         */
        Select(slop_os.Relative[u8]),
        /**
         * Everything changed beneath this directory before it, on stable storage. Answered with Done once it is, or
         * Failed(DeviceError).
         */
        Sync,
        /** What the file system does beyond the protocols' least. Answered with Supports. */
        Features,
        /** Serve another client, on the end given, which moves to the server: the same directory. Not answered. */
        Connect(os.Channel[Dir]),
        /**
         * A transaction (the SlopOS repository's decisions 0046, 0089): a connection speaking dir beneath this
         * directory, whose changes are kept, in the memory given, until Commit applies them all at once, or none
         * of them; Abort, or closing it, drops them. Reads on it see the directory as it is, not its own changes
         * before they're committed. The memory's handle moves to the server. Answered with Began, or Failed;
         * Unsupported on a file system without transactions.
         */
        Begin(slop_os.Memory),
        /**
         * On a transaction's connection: its changes applied whole and made durable. Answered with Done, or
         * Failed(Conflict) if anything it read or changed was changed meanwhile, and then none of them is applied.
         */
        Commit,
        /** On a transaction's connection: its changes dropped. Answered with Done. */
        Abort,
        /**
         * A new file to replace the file at a path whole: written through the file connection given, and swapped in
         * with that connection's Install; a reader of the old one keeps reading it until it's done. Answered with
         * OpenedFile, or Failed; Unsupported on a file system without atomic replacement.
         */
        Replace(slop_os.Relative[u8]),
        /**
         * The first change beneath this directory at or after a cursor (decisions/0089). Answered with Changed,
         * UpToDate when there's none yet, Resync when the cursor's older than what's kept, or Failed; Unsupported on a
         * file system without change cursors.
         */
        Changes(u64),
        /**
         * What's at a path beneath this directory granted, for a directory in another volume to keep with Link.
         * Answered with Granted, or Failed.
         */
        Grant(GrantOf),
        /** A grant kept as a stored link at a path beneath this directory. Answered with Done, or Failed. */
        Link(LinkTo),
        /**
         * The first link issued for what's beneath this directory at or after a cursor: 0 for the first, then each
         * Issued's next. Answered with Issued, End once none is left, or Failed.
         */
        Links(u64),
        /** The issued link with this number revoked, so it opens as Revoked. Answered with Done, or Failed. */
        Revoke(u64),
        /** How much room the volume this directory is on has, and how big it is. Answered with Room, or Failed. */
        Room,
        /**
         * A CPU budget lent for this connection's work, and that of what's opened through it, from now on (the SlopOS
         * repository's decisions 0037, 0130): the server runs it on the budget, and serves what's waiting by the
         * budget's priority. The budget's handle moves to the server. Answered with Done; Unsupported by a server that
         * doesn't take loans.
         */
        Lend(slop_os.CpuBudget),
    }

    /** What a directory's server answers. */
    Response :: union {
        /** The answer to Remove, Rename, Sync, Commit, Abort, Link, Revoke and Lend: it's done. */
        Done,
        /** The answer to OpenFile and Replace: the file's new connection, whose end the client owns and closes. */
        OpenedFile(os.Channel[file.File]),
        /** The answer to OpenReadOnlyFile: the file's new connection, whose end the client owns and closes. */
        OpenedReadOnlyFile(os.Channel[read_only_file.ReadOnlyFile]),
        /** The answer to OpenDirectory: the directory's new connection, whose end the client owns and closes. */
        OpenedDirectory(os.Channel[Dir]),
        /** The answer to List: an entry, and the cursor for the next. */
        Listed(files.Listing),
        /** The answer to List, or Links, when there's no entry at or after the cursor. */
        End,
        /** The answer to Info: what the directory is, its name in the message's variable-size data. */
        Described(files.Info),
        /** The answer to Narrow: the read-only connection's end, which the client owns and closes. */
        Narrowed(os.Channel[read_only_dir.ReadOnlyDir]),
        /** The answer to Select: the set's connection's end, which the client owns and closes. */
        Selected(os.Channel[file_set.FileSet]),
        /** The answer to Features. */
        Supports(files.Features),
        /** The answer to a request that failed, and why. */
        Failed(files.FileError),
        /** The answer to a request the server doesn't know, or that needs a feature its file system hasn't. */
        Unsupported,
        /** The answer to Begin: the transaction's connection's end, which the client owns; closing it aborts. */
        Began(os.Channel[Dir]),
        /** The answer to Changes: a change, and the cursor after it. */
        Changed(files.Change),
        /** The answer to Changes when there's no change since the cursor: the cursor to ask from next. */
        UpToDate(u64),
        /** The answer to Changes when the cursor is older than what's kept: list again, and ask from the one given. */
        Resync(u64),
        /** The answer to Grant: the grant's end, which the client owns, to hand to another volume's directory. */
        Granted(os.Channel[grant.Grant]),
        /** The answer to Links: a link, and the cursor for the next. */
        Issued(files.IssuedLink),
        /** The answer to Room. */
        Room(files.Room),
    }

    /**
     * Tell whether a request may be sent again, after a reconnect, without doing more than sending it once did.
     *
     * A rename or a removal done again finds nothing to do, which is reported, so they aren't sent again; nor are those
     * that make something once: a transaction's, Replace, and the link requests that change what's issued.
     *
     * @param request The request, which isn't changed.
     * @return False for Remove, Rename, Begin, Commit, Replace, Grant, Link and Revoke, and an OpenFile of a New file;
     *     true for the rest.
     */
    is_idempotent :: fn(request: ptr[Request]) -> bool {
        return match request^ {
            case OpenFile(open) => open.creation != .New
            case OpenReadOnlyFile(_) => true
            case OpenDirectory(_) => true
            case List(_) => true
            case Lend(_) => true
            case Info => true
            case Remove(_) => false
            case Rename(_) => false
            case Narrow => true
            case Select(_) => true
            case Sync => true
            case Features => true
            case Connect(_) => true
            case Begin(_) => false
            case Commit => false
            case Abort => true
            case Replace(_) => false
            case Changes(_) => true
            case Grant(_) => false
            case Link(_) => false
            case Links(_) => true
            case Revoke(_) => false
            case Room => true
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
    connect :: fn(end: slop_os.Channel, port: slop_os.Port, budget: slop_os.MemoryBudget) -> os.Channel[Dir]? {
        pair :: os.channel_for[Dir](budget, 0) or_return null
        out := os.Outgoing.{}
        request :: os.begin[Request](&out)
        request^ = .Connect(os.Channel[Dir].{end = pair.a})
        match send_request(end, port, &out) {
            case Some(error) => {
                _ = slop_os.handle_close(cast[slop_os.Handle](pair.a))
                _ = slop_os.handle_close(cast[slop_os.Handle](pair.b))
                return null
            }
            case None => return os.Channel[Dir].{end = pair.b}
        }
    }
}

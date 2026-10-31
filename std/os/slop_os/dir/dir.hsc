package dir

// Only for SlopOS, where std/os has what its generated code needs: base.OS, since the #insert in it could declare an OS of its own
#if base.OS == .SlopOS {
    import os from "std"
    import slop_os from "std/os"
    import file from "std/os/slop_os"
    import file_set from "std/os/slop_os"
    import files from "std/os/slop_os"
    import grant from "std/os/slop_os"
    import read_only_dir from "std/os/slop_os"
    import read_only_file from "std/os/slop_os"

    /*
     * A directory (the SlopOS repository's decisions 0015, 0046, 0087): a tree beneath it, every path resolved within
     * it, and nothing above it. Opening a file or a directory gives a connection of its own; Narrow gives this
     * directory as a read_only_dir.
     */
    Dir :: struct {}

    PROTOCOL :: slop_os.Protocol.{name = "dir", major_version = 1, lending = .PerConnection}

    OpenFile :: struct {
        path : slop_os.Relative[u8],
        creation : files.Creation,
        /*
         * A typed file's schema hash (the SlopOS repository's 0046, 0108): one made has it, one there already must have it
         * (WrongType); all zeros asks for neither
         */
        schema : u8[32],
    }

    OpenDirectory :: struct {
        path : slop_os.Relative[u8],
        // Made, with any missing directory before it, if it isn't there
        create : bool,
    }

    Rename :: struct {
        from : slop_os.Relative[u8],
        to : slop_os.Relative[u8],
    }

    // What's at a path beneath this directory granted, to write as well as read if write.
    GrantOf :: struct {
        path : slop_os.Relative[u8],
        write : bool,
    }

    // A grant kept as a stored link at a path beneath this directory.
    LinkTo :: struct {
        path : slop_os.Relative[u8],
        grant : os.Channel[grant.Grant],
    }

    Request :: union {
        OpenFile(OpenFile),
        OpenReadOnlyFile(slop_os.Relative[u8]),
        OpenDirectory(OpenDirectory),
        // The entry at or after a cursor, from 0
        List(u64),
        Info,
        // A file, or an empty directory, at a path beneath this one, removed
        Remove(slop_os.Relative[u8]),
        // What's at one path beneath this one moved to another, replacing a file there
        Rename(Rename),
        // This directory, only to read
        Narrow,
        // The files of this directory whose names match a pattern (file_set)
        Select(slop_os.Relative[u8]),
        // Everything changed beneath it before this, on stable storage
        Sync,
        Features,
        Connect(os.Channel[Dir]),
        /*
         * A transaction (the SlopOS repository's decisions 0046, 0089): a connection speaking dir beneath this
         * directory, whose changes are kept, in the memory given, until Commit applies them all at once, or none
         * of them; Abort, or closing it, drops them. Reads on it see the directory as it is, not its own changes
         * before they're committed.
         */
        Begin(slop_os.Memory),
        // On a transaction's connection: its changes applied whole and made durable, or Conflict if anything it read
        // or changed was changed meanwhile
        Commit,
        Abort,
        // A new file to replace the file at a path whole: written through the file connection given, and swapped in
        // with that connection's Install; a reader of the old one keeps reading it until it's done
        Replace(slop_os.Relative[u8]),
        // The first change beneath this directory at or after a cursor (decisions/0089)
        Changes(u64),
        /*
         * Stored links (the SlopOS repository's roadmap 8f, design/security.md §8): what's at a path granted, for a
         * directory in another volume to keep with Link; a link opens as what it leads to, wherever it's on a path, and
         * Remove and Rename act on the link. The links issued for what's beneath this directory, from a cursor, and one
         * of them revoked by its number. What was reached through a link can't be granted on, and its links aren't
         * listed or revoked through it (ReadOnly).
         */
        Grant(GrantOf),
        Link(LinkTo),
        Links(u64),
        Revoke(u64),
        // How much room the volume this directory is on has, and how big it is
        Room,
    }

    Response :: union {
        Done,
        OpenedFile(os.Channel[file.File]),
        OpenedReadOnlyFile(os.Channel[read_only_file.ReadOnlyFile]),
        OpenedDirectory(os.Channel[Dir]),
        Listed(files.Listing),
        // No entry at or after the cursor
        End,
        Described(files.Info),
        Narrowed(os.Channel[read_only_dir.ReadOnlyDir]),
        Selected(os.Channel[file_set.FileSet]),
        Supports(files.Features),
        Failed(files.FileError),
        Unsupported,
        Began(os.Channel[Dir]),
        Changed(files.Change),
        // No change since the cursor; the cursor to ask from next
        UpToDate(u64),
        // The cursor is older than what's kept: list again, and ask from the cursor given
        Resync(u64),
        Granted(os.Channel[grant.Grant]),
        Issued(files.IssuedLink),
        Room(files.Room),
    }

    // A rename or a removal done again finds nothing to do, which is reported, so they aren't sent again.
    is_idempotent :: fn(request: ptr[Request]) -> bool {
        return match request^ {
            case OpenFile(open) => open.creation != .New
            case OpenReadOnlyFile(_) => true
            case OpenDirectory(_) => true
            case List(_) => true
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

    /*
     * A new connection to the directory end reaches, the same directory: a channel for Dir, one end sent in a
     * Connect, the other given back, or null.
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

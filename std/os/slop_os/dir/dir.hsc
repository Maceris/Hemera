package dir

// Only for SlopOS, where std/os has what its generated code needs: base.OS, since the #insert in it could declare an OS of its own
#if base.OS == .SlopOS {
    import os from "std"
    import slop_os from "std/os"
    import file from "std/os/slop_os"
    import file_set from "std/os/slop_os"
    import files from "std/os/slop_os"
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

package read_only_dir

// Only for SlopOS, where std/os has what its generated code needs: base.OS, since the #insert in it could declare an OS of its own
#if base.OS == .SlopOS {
    import os from "std"
    import slop_os from "std/os"
    import file_set from "std/os/slop_os"
    import files from "std/os/slop_os"
    import read_only_file from "std/os/slop_os"

    /*
     * A directory to read (the SlopOS repository's decisions 0015, 0046, 0087): the subset of dir that changes nothing,
     * and whose opens give only connections that read.
     */
    ReadOnlyDir :: struct {}

    PROTOCOL :: slop_os.Protocol.{name = "read_only_dir", major_version = 1, lending = .PerConnection}

    Request :: union {
        OpenReadOnlyFile(slop_os.Relative[u8]),
        // The directory at a path beneath this one
        OpenDirectory(slop_os.Relative[u8]),
        // The entry at or after a cursor, from 0
        List(u64),
        Info,
        // The files of this directory whose names match a pattern (file_set)
        Select(slop_os.Relative[u8]),
        Features,
        Connect(os.Channel[ReadOnlyDir]),
        // The first change beneath this directory at or after a cursor, as dir has it
        Changes(u64),
    }

    Response :: union {
        OpenedReadOnlyFile(os.Channel[read_only_file.ReadOnlyFile]),
        OpenedDirectory(os.Channel[ReadOnlyDir]),
        Listed(files.Listing),
        // No entry at or after the cursor
        End,
        Described(files.Info),
        Selected(os.Channel[file_set.FileSet]),
        Supports(files.Features),
        Failed(files.FileError),
        Unsupported,
        Changed(files.Change),
        UpToDate(u64),
        Resync(u64),
    }

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

    /*
     * A new connection to the directory end reaches, the same directory: a channel for ReadOnlyDir, one end sent in a
     * Connect, the other given back, or null.
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

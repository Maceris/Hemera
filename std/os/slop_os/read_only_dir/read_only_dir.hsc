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
        }
    }

    #insert os.protocol_code(Request, Response)
}

package read_only_file

// Only for SlopOS, where std/os has what its generated code needs: base.OS, since the #insert in it could declare an OS of its own
#if base.OS == .SlopOS {
    import os from "std"
    import slop_os from "std/os"
    import files from "std/os/slop_os"

    /*
     * A file to read (the SlopOS repository's decisions 0015, 0087): the reading subset of file. The client gives the
     * connection a buffer, a memory object it has mapped, once; Read names where in it.
     */
    ReadOnlyFile :: struct {}

    PROTOCOL :: slop_os.Protocol.{name = "read_only_file", major_version = 1, lending = .PerConnection}

    Request :: union {
        // The memory Read and Write move bytes through, from now on
        UseBuffer(slop_os.Memory),
        // Bytes of the file into the buffer: how many, fewer at its end
        Read(files.Transfer),
        Info,
        // Serve another client, on its end
        Connect(os.Channel[ReadOnlyFile]),
    }

    Response :: union {
        Done,
        Transferred(u32),
        Described(files.Info),
        Failed(files.FileError),
        Unsupported,
    }

    is_idempotent :: fn(request: ptr[Request]) -> bool {
        return match request^ {
            case UseBuffer(_) => true
            case Read(_) => true
            case Info => true
            case Connect(_) => true
        }
    }

    #insert os.protocol_code(Request, Response)
}

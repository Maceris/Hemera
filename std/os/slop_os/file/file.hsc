package file

// Only for SlopOS, where std/os has what its generated code needs: base.OS, since the #insert in it could declare an OS of its own
#if base.OS == .SlopOS {
    import os from "std"
    import slop_os from "std/os"
    import files from "std/os/slop_os"
    import read_only_file from "std/os/slop_os"

    /*
     * A file to read and write (the SlopOS repository's decisions 0015, 0046, 0087). The client gives the connection a
     * buffer, a memory object it has mapped, once; Read and Write name where in it. Writing past the end grows the file.
     */
    File :: struct {}

    PROTOCOL :: slop_os.Protocol.{name = "file", major_version = 1, lending = .PerConnection}

    Request :: union {
        // The memory Read and Write move bytes through, from now on
        UseBuffer(slop_os.Memory),
        // Bytes of the file into the buffer: how many, fewer at its end
        Read(files.Transfer),
        // Bytes from the buffer into the file: how many
        Write(files.Transfer),
        // The file this many bytes long: shorter, cut; longer, zeros after its end
        SetSize(u64),
        Info,
        // Everything written before it, on stable storage
        Sync,
        // A connection to the same file that only reads
        Narrow,
        // Serve another client, on its end
        Connect(os.Channel[File]),
    }

    Response :: union {
        Done,
        Transferred(u32),
        Described(files.Info),
        Narrowed(os.Channel[read_only_file.ReadOnlyFile]),
        Failed(files.FileError),
        Unsupported,
    }

    // Writing the same bytes to the same place again, or setting the same size, changes nothing more.
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
        }
    }

    #insert os.protocol_code(Request, Response)
}

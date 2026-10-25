package files

// Only for SlopOS, where std/os has what its generated code needs: base.OS, since the #insert in it could declare an OS of its own
#if base.OS == .SlopOS {
    import slop_os from "std/os"

    /*
     * What the file protocols share (the SlopOS repository's decisions 0015, 0018, 0046, 0087): file, read_only_file,
     * dir, read_only_dir and file_set. A path is UTF-8, its components separated by '/', and resolved beneath the
     * directory it's given to; "." and ".." aren't components, so nothing leads above it. Bulk data moves through a
     * buffer the client gives a file connection once (UseBuffer), which Read and Write name offsets into.
     */

    // A path or a name, at most, in bytes.
    PATH_BYTES :: 1024

    Kind :: enum #backed_by(u32) {
        File = 1,
        Directory = 2,
    }

    FileError :: enum #backed_by(u32) {
        // Nothing is at the path, or a directory on the way to it is missing
        NotFound = 1,
        // Part of the path should be a directory and isn't
        NotADirectory = 2,
        // The path is a directory, where a file was needed
        IsADirectory = 3,
        AlreadyExists = 4,
        DirectoryNotEmpty = 5,
        // The path can't be used: empty, too long, with "." or "..", or a name the file system can't hold
        InvalidPath = 6,
        NoSpace = 7,
        // The file system, or this connection to it, doesn't allow it
        ReadOnly = 8,
        // The device under it failed
        DeviceError = 9,
        // What's on the device doesn't hold together
        Corrupt = 10,
        // A Read or Write before UseBuffer, or past the buffer's end
        NoBuffer = 11,
    }

    // How OpenFile treats what's at its path.
    Creation :: enum #backed_by(u32) {
        // A file that's there
        Existing = 1,
        // A new file; AlreadyExists if something's there
        New = 2,
        // A file that's there, or a new one
        Either = 3,
        // A file that's there, emptied, or a new one
        Truncate = 4,
    }

    // Bytes of a file from offset, count of them, at buffer_offset in the connection's buffer.
    Transfer :: struct {
        offset : u64,
        count : u32,
        buffer_offset : u32,
    }

    /*
     * What a file or directory is: its kind, its size in bytes (a directory's is 0), and its informational name, the
     * path it was opened as beneath the handle it was opened from, for display only (decisions/0018).
     */
    Info :: struct {
        kind : Kind,
        size : u64,
        name : slop_os.Relative[u8],
    }

    // One entry of a directory, as List gives them, and the cursor to list from next.
    Listing :: struct {
        name : slop_os.Relative[u8],
        kind : Kind,
        size : u64,
        next : u64,
    }

    // What a file system does beyond the protocols' least (decisions/0046): FAT does none of it but ignoring case.
    Features :: struct {
        ignores_case : bool,
        atomic_replace : bool,
        transactions : bool,
        snapshots : bool,
        change_cursors : bool,
    }
}

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
        // A stored link to a file or a directory in another volume (the SlopOS repository's roadmap 8f), opened as either
        Link = 3,
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
        // A transaction's commit found something it read or changed changed by someone else since
        Conflict = 12,
        // A stored link whose grant was revoked
        Revoked = 13,
        // A stored link into a volume that isn't open, or that can't be reached
        Unavailable = 14,
        // A stored link where it isn't followed: inside what another link leads to, or in a transaction
        IsALink = 15,
        // The server hadn't the memory to do it, and changed nothing
        NoMemory = 16,
        // The file's type isn't the one asked for, or the file system keeps no types (the SlopOS repository's 0046, 0108)
        WrongType = 17,
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
        // A typed file's schema hash (0046): its bytes are a value of that type; all zeros for bytes alone
        schema : u8[32],
    }

    // One entry of a directory, as List gives them, and the cursor to list from next.
    Listing :: struct {
        name : slop_os.Relative[u8],
        kind : Kind,
        size : u64,
        next : u64,
    }

    // What a change cursor found (decisions/0089): what happened to a name.
    ChangeKind :: enum #backed_by(u32) {
        Created = 1,
        // A file's bytes or size
        Written = 2,
        Removed = 3,
        // Moved away from the name, or to it
        MovedOut = 4,
        MovedIn = 5,
        // A file's contents swapped for new ones, whole
        Replaced = 6,
    }

    // One change beneath a directory: what happened, to the name (relative to the directory the cursor is on, as far as
    // it's known), and the cursor after it.
    Change :: struct {
        kind : ChangeKind,
        name : slop_os.Relative[u8],
        next : u64,
    }

    // A link a directory's volume issued (Links), the path, beneath that directory, to what it leads to, and the cursor after it.
    IssuedLink :: struct {
        number : u64,
        path : slop_os.Relative[u8],
        write : bool,
        // When it was issued, as its granter's clock said
        created : u64,
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

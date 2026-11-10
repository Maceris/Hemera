package files

import slop_os from "std/os"

/*
 * What the file protocols share (the SlopOS repository's decisions 0015, 0018, 0046, 0087): file, read_only_file,
 * dir, read_only_dir and file_set. A path is UTF-8, its components separated by '/', and resolved beneath the
 * directory it's given to; "." and ".." aren't components, so nothing leads above it. Bulk data moves through a
 * buffer the client gives a file connection once (UseBuffer), which Read and Write name offsets into.
 */

/** The most bytes a path or a name has; a longer one is InvalidPath. */
PATH_BYTES :: 1024

/** What an entry of a directory is. */
Kind :: enum #backed_by(u32) {
    /** A file of bytes, or of a typed value. */
    File = 1,
    /** A directory, which entries are beneath. */
    Directory = 2,
    /**
     * A stored link to a file or a directory in another volume (the SlopOS repository's roadmap 8f), opened as
     * either.
     */
    Link = 3,
}

/** Why a request of a file protocol failed, as its Failed response says. */
FileError :: enum #backed_by(u32) {
    /** Nothing is at the path, or a directory on the way to it is missing. */
    NotFound = 1,
    /** Part of the path should be a directory and isn't. */
    NotADirectory = 2,
    /** The path is a directory, where a file was needed. */
    IsADirectory = 3,
    /** Something is at the path already, where a new file or directory was asked for. */
    AlreadyExists = 4,
    /** A directory to remove still has entries. */
    DirectoryNotEmpty = 5,
    /** The path can't be used: empty, too long, with "." or "..", or a name the file system can't hold. */
    InvalidPath = 6,
    /** The volume has no room left, or the server no room for another connection. */
    NoSpace = 7,
    /** The file system, or this connection to it, doesn't allow it. */
    ReadOnly = 8,
    /** The device under it failed. */
    DeviceError = 9,
    /** What's on the device doesn't hold together. */
    Corrupt = 10,
    /** A Read or Write before UseBuffer, or past the buffer's end; or a buffer that can't be used. */
    NoBuffer = 11,
    /** A transaction's commit found something it read or changed changed by someone else since. */
    Conflict = 12,
    /** A stored link whose grant was revoked. */
    Revoked = 13,
    /** A stored link into a volume that isn't open, or that can't be reached. */
    Unavailable = 14,
    /** A stored link where it isn't followed: inside what another link leads to, or in a transaction. */
    IsALink = 15,
    /** The server hadn't the memory to do it, and changed nothing. */
    NoMemory = 16,
    /**
     * The file's type isn't the one asked for, or the file system keeps no types (the SlopOS repository's 0046,
     * 0108).
     */
    WrongType = 17,
}

/** How OpenFile treats what's at its path. */
Creation :: enum #backed_by(u32) {
    /** A file that's there; NotFound if nothing is. */
    Existing = 1,
    /** A new file; AlreadyExists if something's there. */
    New = 2,
    /** A file that's there, or a new one. */
    Either = 3,
    /** A file that's there, emptied, or a new one. */
    Truncate = 4,
}

/** A Read's or a Write's range: count bytes of a file from offset, at buffer_offset in the connection's buffer. */
Transfer :: struct {
    /** Where in the file the bytes start, in bytes from its start; a Read from its end or past it reads 0. */
    offset : u64,
    /** How many bytes to move, at most; 0 moves none. */
    count : u32,
    /**
     * Where in the connection's buffer the bytes go or come from, in bytes from its start; with count, it has to
     * stay within the buffer (NoBuffer).
     */
    buffer_offset : u32,
}

/** What a file or directory is, as Info answers. */
Info :: struct {
    /** Whether it's a file or a directory. */
    kind : Kind,
    /** Its size in bytes; a directory's is 0. */
    size : u64,
    /**
     * Its informational name, UTF-8: the path it was opened as beneath the handle it was opened from, for display
     * only (decisions/0018); it doesn't open anything.
     */
    name : slop_os.Relative[u8],
    /** A typed file's schema hash (0046), so its bytes are a value of that type; all zeros for bytes alone. */
    schema : u8[32],
}

/** One entry of a directory, as List gives them, and the cursor to list from next. */
Listing :: struct {
    /** The entry's name, UTF-8, without the directory's path. */
    name : slop_os.Relative[u8],
    /** Whether it's a file, a directory or a stored link. */
    kind : Kind,
    /** Its size in bytes; a directory's is 0. */
    size : u64,
    /** The cursor to give the next List, for the entry after this one; opaque, only given back. */
    next : u64,
}

/** What a change cursor found (decisions/0089): what happened to a name. */
ChangeKind :: enum #backed_by(u32) {
    /** A file or a directory was made at the name. */
    Created = 1,
    /** A file's bytes or size changed. */
    Written = 2,
    /** What was at the name was removed. */
    Removed = 3,
    /** What was at the name was moved away from it. */
    MovedOut = 4,
    /** Something was moved to the name. */
    MovedIn = 5,
    /** A file's contents were swapped for new ones, whole. */
    Replaced = 6,
}

/**
 * One change beneath a directory, as Changes answers: what happened, to which name, and the cursor after it.
 */
Change :: struct {
    /** What happened to the name. */
    kind : ChangeKind,
    /** The name, UTF-8, relative to the directory the cursor is on, as far as it's known. */
    name : slop_os.Relative[u8],
    /** The cursor to give the next Changes, for the change after this one; opaque, only given back. */
    next : u64,
}

/**
 * A link a directory's volume issued, as Links answers: its number, the path, beneath that directory, to what it
 * leads to, and the cursor after it.
 */
IssuedLink :: struct {
    /** The link's number, which Revoke takes. */
    number : u64,
    /** The path, UTF-8, beneath the directory asked, to what the link leads to. */
    path : slop_os.Relative[u8],
    /** Whether the link may write what it leads to; false, only read it. */
    write : bool,
    /** When it was issued, as its granter's clock said; its units are the granter's. */
    created : u64,
    /** The cursor to give the next Links, for the link after this one; opaque, only given back. */
    next : u64,
}

/**
 * A snapshot of a directory's volume (the SlopOS repository's decisions 0090, 0179), as Snapshot and Snapshots
 * answer: its name, when it was taken, and the cursor after it.
 */
Snapshot :: struct {
    /** Its name, UTF-8, which OpenSnapshot takes. */
    name : slop_os.Relative[u8],
    /** When it was taken, as its taker's wall clock said, in nanoseconds since 1970. */
    taken : u64,
    /** For Snapshots, the cursor to give the next, for the snapshot after this one; 0 from Snapshot. */
    next : u64,
}

/** A volume's room, as Room answers, in bytes. */
Room :: struct {
    /** The bytes free to write new data in. */
    free : u64,
    /** The volume's whole size. */
    size : u64,
}

/**
 * What a file system does beyond the protocols' least (decisions/0046), as Features answers: FAT does none of it
 * but ignoring case. A request that needs what it doesn't do is Unsupported.
 */
Features :: struct {
    /** Whether names that differ only in case name the same entry. */
    ignores_case : bool,
    /** Whether a directory's Replace and a file's Install swap a file whole. */
    atomic_replace : bool,
    /** Whether a directory's Begin, Commit and Abort make transactions. */
    transactions : bool,
    /** Whether the volume keeps snapshots. */
    snapshots : bool,
    /** Whether a directory's Changes gives what changed beneath it. */
    change_cursors : bool,
}

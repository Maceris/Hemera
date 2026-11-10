package file_set

import os from "std"
import slop_os from "std/os"
import file from "std/os/slop_os"
import files from "std/os/slop_os"
import read_only_file from "std/os/slop_os"

/**
 * The file_set protocol, for os.Channel[FileSet]: a set of files (the SlopOS repository's decision 0018).
 *
 * A set is a directory and a pattern, which List and the opens apply as they're asked, so files made while a
 * program runs match too. The pattern matches a name as a whole: '*' any run of characters, '?' any one, anything
 * else itself, as the directory compares names. A set selected from a read-only directory refuses OpenFile
 * (ReadOnly).
 */
FileSet :: struct {}

/**
 * What the protocol says of itself: its name, which its channels' tag is made from, its major version, and that the
 * client's budget pays for the server's work, for each of its connections.
 */
PROTOCOL :: slop_os.Protocol.{name = "file_set", major_version = 1, lending = .PerConnection}

/** A name in the set, and how OpenFile treats what's there. */
OpenFile :: struct {
    /**
     * The file's name, UTF-8, in the set's directory: one name, not a path. It has to match the set's pattern, or
     * the open fails (NotFound).
     */
    name : slop_os.Relative[u8],
    /** Whether the file has to be there, has to be new, or either, and whether it's emptied. */
    creation : files.Creation,
}

/** What a client asks of a set of files. */
Request :: union {
    /**
     * The first entry of the directory at or after a cursor that matches: 0 for the first, then each Listed's next.
     * Answered with Listed, End once none is left, or Failed.
     */
    List(u64),
    /**
     * A file of the set, to read and write. Answered with OpenedFile, or Failed: ReadOnly for a set selected from a
     * read-only directory, NotFound for a name the pattern doesn't match.
     */
    OpenFile(OpenFile),
    /**
     * A file of the set, by its name, UTF-8, to read. Answered with OpenedReadOnlyFile, or Failed: NotFound for a
     * name the pattern doesn't match or nothing at it.
     */
    OpenReadOnlyFile(slop_os.Relative[u8]),
    /** What the set is: a directory, its name the pattern. Answered with Described. */
    Info,
    /** Serve another client, on the end given, which moves to the server: the same set. Not answered. */
    Connect(os.Channel[FileSet]),
}

/** What a set's server answers. */
Response :: union {
    /** The answer to List: an entry that matches, and the cursor for the next. */
    Listed(files.Listing),
    /** The answer to List when no entry at or after the cursor matches. */
    End,
    /** The answer to OpenFile: the file's new connection, whose end the client owns and closes. */
    OpenedFile(os.Channel[file.File]),
    /** The answer to OpenReadOnlyFile: the file's new connection, whose end the client owns and closes. */
    OpenedReadOnlyFile(os.Channel[read_only_file.ReadOnlyFile]),
    /** The answer to Info: what the set is, its name in the message's variable-size data. */
    Described(files.Info),
    /** The answer to a request that failed, and why. */
    Failed(files.FileError),
    /** The answer to a request the server doesn't know, as from a newer client; every protocol has it. */
    Unsupported,
}

/**
 * Tell whether a request may be sent again, after a reconnect, without doing more than sending it once did.
 *
 * @param request The request, which isn't changed.
 * @return True for every request but an OpenFile of a New file, which sent again would find the file it made
 *     (AlreadyExists).
 */
is_idempotent :: fn(request: ptr[Request]) -> bool {
    return match request^ {
        case List(_) => true
        case OpenFile(open) => open.creation != .New
        case OpenReadOnlyFile(_) => true
        case Info => true
        case Connect(_) => true
    }
}

#insert os.protocol_code(Request, Response)

/**
 * Tell whether a name matches a pattern as a whole, as a set's server matches its directory's names.
 *
 * Matching goes byte by byte, so '?' matches one byte, not one character; a name of more than ASCII is matched
 * as its UTF-8 bytes. Backtracking goes only to the last '*', so it takes time in proportion to the product of the
 * two lengths at most.
 *
 * @param pattern The pattern: '*' matches any run of bytes, empty included, '?' any one byte, and any other byte
 *     what same says is the same. An empty pattern matches only an empty name.
 * @param name The name to match, one name, not a path.
 * @param same Whether a byte of the pattern and one of the name are the same, as the directory compares names:
 *     equality, or equality ignoring case on a file system that ignores it. It's given the pattern's byte first.
 * @return True if the whole name matches the whole pattern; false otherwise.
 */
matches :: fn(pattern: string, name: string, same: (fn(a: u8, b: u8) -> bool)) -> bool {
    // The last '*' seen, and where in name it was tried from, to try again one further
    star := pattern.count
    tried : usize = 0
    p : usize = 0
    n : usize = 0
    loop {
        if n >= name.count {
            break
        }
        if p < pattern.count && pattern[p] == '*' {
            star = p
            tried = n
            p += 1
            continue
        }
        if p < pattern.count && (pattern[p] == '?' || same(cast[u8](pattern[p]), cast[u8](name[n]))) {
            p += 1
            n += 1
            continue
        }
        if star < pattern.count {
            p = star + 1
            tried += 1
            n = tried
            continue
        }
        return false
    }
    loop {
        if p >= pattern.count || pattern[p] != '*' {
            break
        }
        p += 1
    }
    return p >= pattern.count
}

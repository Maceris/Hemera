package file_set

// Only for SlopOS, where std/os has what its generated code needs: base.OS, since the #insert in it could declare an OS of its own
#if base.OS == .SlopOS {
    import os from "std"
    import slop_os from "std/os"
    import file from "std/os/slop_os"
    import files from "std/os/slop_os"
    import read_only_file from "std/os/slop_os"

    /*
     * A set of files (the SlopOS repository's decision 0018): a directory and a pattern, which List and the opens
     * apply, so files made while a program runs match too. The pattern matches a name as a whole: '*' any run of
     * characters, '?' any one, anything else itself, as the directory compares names. A set selected from a
     * read-only directory refuses OpenFile (ReadOnly).
     */
    FileSet :: struct {}

    PROTOCOL :: slop_os.Protocol.{name = "file_set", major_version = 1, lending = .PerConnection}

    // A name in the set, and how OpenFile treats what's there.
    OpenFile :: struct {
        name : slop_os.Relative[u8],
        creation : files.Creation,
    }

    Request :: union {
        // The entry at or after a cursor, from 0, that matches
        List(u64),
        OpenFile(OpenFile),
        OpenReadOnlyFile(slop_os.Relative[u8]),
        Info,
        Connect(os.Channel[FileSet]),
    }

    Response :: union {
        Listed(files.Listing),
        // No entry at or after the cursor matches
        End,
        OpenedFile(os.Channel[file.File]),
        OpenedReadOnlyFile(os.Channel[read_only_file.ReadOnlyFile]),
        Described(files.Info),
        Failed(files.FileError),
        Unsupported,
    }

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

    // Whether name matches pattern: '*' any run of characters, '?' any one, compared as same says.
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
}

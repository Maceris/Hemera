package os

/*
 * SlopOS's side of std/os's files (the SlopOS repository's decisions 0046, 0087): its file protocols, dir, file and
 * read_only_file. A Directory is a connection speaking dir, and a File one speaking file or, opened only to read,
 * read_only_file; each File reads and writes through a buffer of its own, a memory object it gives its server once,
 * and keeps the offset the next read or write is at. Both are held in memory from the context's allocator, which
 * close and close_directory give back. SlopOS has no paths but those beneath a directory, so the path functions, open
 * and the rest, resolve beneath the directory the program was given as its "working_directory" grant, and fail with
 * NotFound without one, or InvalidPath for a path that isn't beneath it.
 */
#if OS == .SlopOS {
    import intrinsics from "base"
    import runtime from "base"
    import slop_os from "std/os"
    import dir from "std/os/slop_os"
    import file from "std/os/slop_os"
    import files from "std/os/slop_os"
    import read_only_file from "std/os/slop_os"

    // Each File's buffer
    FILE_BUFFER_BYTES : u64 : 64 * 1024
    WORKING_DIRECTORY :: "working_directory"

    // What a File is: its connection, whether it writes, its buffer, and where it's at.
    SlopFile :: struct {
        end : slop_os.Channel,
        port : slop_os.Port,
        writes : bool,
        buffer : u64,
        memory : slop_os.Memory,
        offset : u64,
    }

    // What a Directory is: its connection.
    SlopDirectory :: struct {
        end : slop_os.Channel,
        port : slop_os.Port,
    }

    file_of :: fn(handle: File) -> ptr[mut SlopFile] {
        return cast[ptr[mut SlopFile]](handle.handle)
    }

    directory_of :: fn(handle: Directory) -> ptr[mut SlopDirectory] {
        return cast[ptr[mut SlopDirectory]](handle.handle)
    }

    error_of_file :: fn(error: files.FileError) -> OsError {
        return match error {
            case .NotFound => OsError.NotFound
            case .NotADirectory => OsError.NotADirectory
            case .IsADirectory => OsError.IsADirectory
            case .AlreadyExists => OsError.AlreadyExists
            case .DirectoryNotEmpty => OsError.DirectoryNotEmpty
            case .InvalidPath => OsError.InvalidPath
            case .ReadOnly => OsError.AccessDenied
            case .NoSpace => OsError.Other
            case .DeviceError => OsError.Other
            case .Corrupt => OsError.Other
            case .NoBuffer => OsError.Other
            case .Conflict => OsError.Other
        }
    }

    // A connection's end, as a Directory with a port of its own.
    directory_on :: fn(end: slop_os.Channel) -> (directory : Directory, error : OsError?) {
        block :: slop_os.startup_block()
        port :: port_for(block.budget, end) or_else cast[slop_os.Port](slop_os.NO_HANDLE)
        if cast[slop_os.Handle](port) == slop_os.NO_HANDLE {
            _ = slop_os.handle_close(cast[slop_os.Handle](end))
            return Directory.{0}, OsError.OutOfMemory
        }
        state :: runtime.new(SlopDirectory)
        state.end = end
        state.port = port
        return Directory.{cast[u64](state)}, null
    }

    // One request on a directory's connection, sent from out, and its answer, into into; false if the connection's gone.
    ask_directory :: fn(state: ptr[SlopDirectory], out: ptr[mut Outgoing], into: ptr[mut Incoming]) -> bool {
        if dir.send_request(state.end, state.port, out) is_some {
            return false
        }
        loop {
            match dir.receive_response(state.end, state.port, into, true) {
                case Received => return true
                case Failed(error) => return false
                case _ => continue
            }
        }
    }

    // The path's bytes appended to out, as a Relative.
    relative_path :: fn(out: ptr[mut Outgoing], path: string) -> slop_os.Relative[u8] {
        return append(out, view_of(cast[ptr[u8]](path.data), path.count))
    }

    system_working_directory :: fn() -> (directory : Directory, error : OsError?) {
        block :: slop_os.startup_block()
        grant :: slop_os.find_grant(block, WORKING_DIRECTORY, .Channel) or_else slop_os.NO_HANDLE
        if grant == slop_os.NO_HANDLE {
            return Directory.{0}, OsError.NotFound
        }
        // A connection of its own, so closing it leaves the grant
        port :: port_for(block.budget, cast[slop_os.Channel](grant)) or_else cast[slop_os.Port](slop_os.NO_HANDLE)
        connection :: dir.connect(cast[slop_os.Channel](grant), port, block.budget)
        _ = slop_os.handle_close(cast[slop_os.Handle](port))
        match connection {
            case Some(made) => return directory_on(made.end)
            case None => return Directory.{0}, OsError.Other
        }
    }

    system_open_directory :: fn(path: string) -> (directory : Directory, error : OsError?) {
        if !is_beneath(path) {
            return Directory.{0}, OsError.InvalidPath
        }
        working, working_error :: system_working_directory()
        if working_error != null {
            return Directory.{0}, working_error
        }
        defer system_close_directory(working)
        return system_open_directory_in(working, path)
    }

    system_open_directory_in :: fn(directory: Directory, path: string) -> (opened : Directory, error : OsError?) {
        state :: directory_of(directory)
        out := Outgoing.{}
        request :: begin[dir.Request](&out)
        request^ = .OpenDirectory(dir.OpenDirectory.{path = relative_path(&out, path)})
        into := Incoming.{}
        if !ask_directory(state, &out, &into) {
            return Directory.{0}, OsError.Other
        }
        match message_of[dir.Response](&into)^ {
            case OpenedDirectory(made) => return directory_on(made.end)
            case Failed(failure) => return Directory.{0}, error_of_file(failure)
            case _ => return Directory.{0}, OsError.Other
        }
    }

    system_close_directory :: fn(directory: Directory) {
        if directory.handle == 0 {
            return void
        }
        state :: directory_of(directory)
        _ = slop_os.handle_close(cast[slop_os.Handle](state.end))
        _ = slop_os.handle_close(cast[slop_os.Handle](state.port))
        runtime.free(state)
    }

    /*
     * A file connection's end, as a File: a port of its own, and a buffer, made, mapped and given to its server.
     * Closed on failure.
     */
    file_on :: fn(end: slop_os.Channel, writes: bool) -> (file : File, error : OsError?) {
        block :: slop_os.startup_block()
        port :: port_for(block.budget, end) or_else cast[slop_os.Port](slop_os.NO_HANDLE)
        if cast[slop_os.Handle](port) == slop_os.NO_HANDLE {
            _ = slop_os.handle_close(cast[slop_os.Handle](end))
            return File.{0}, OsError.OutOfMemory
        }
        state :: runtime.new(SlopFile)
        state.end = end
        state.port = port
        state.writes = writes
        made :: File.{cast[u64](state)}
        state.memory = slop_os.memory_create(block.budget, FILE_BUFFER_BYTES) or_else cast[slop_os.Memory](slop_os.NO_HANDLE)
        address :: runtime.reserve_addresses(cast[usize](FILE_BUFFER_BYTES)) or_else 0
        read_write :: cast[slop_os.Protection](cast[u32](slop_os.PROTECTION_READ) | cast[u32](slop_os.PROTECTION_WRITE))
        mapped := false
        if cast[slop_os.Handle](state.memory) != slop_os.NO_HANDLE && address != 0 {
            match slop_os.memory_map(state.memory, block.space, address, 0, FILE_BUFFER_BYTES, read_write) {
                case Ok => mapped = true
                case Error(error) => {}
            }
        }
        if !mapped {
            system_close(made)
            return File.{0}, OsError.OutOfMemory
        }
        state.buffer = address
        // A handle of the server's own: what it maps, which it may keep as long as the connection
        rights :: cast[slop_os.Rights](cast[u32](slop_os.RIGHT_MEMORY_READ) | cast[u32](slop_os.RIGHT_MEMORY_WRITE) | cast[u32](slop_os.RIGHT_TRANSFER))
        given :: slop_os.handle_duplicate(cast[slop_os.Handle](state.memory), rights) or_else slop_os.NO_HANDLE
        if given == slop_os.NO_HANDLE {
            system_close(made)
            return File.{0}, OsError.OutOfMemory
        }
        out := Outgoing.{}
        ok := false
        into := Incoming.{}
        if writes {
            request :: begin[file.Request](&out)
            request^ = .UseBuffer(cast[slop_os.Memory](given))
            ok = ask_file(state, &out, &into) && done_file(&into)
        }
        else {
            request :: begin[read_only_file.Request](&out)
            request^ = .UseBuffer(cast[slop_os.Memory](given))
            ok = ask_file(state, &out, &into) && done_read_only(&into)
        }
        if !ok {
            system_close(made)
            return File.{0}, OsError.Other
        }
        return made, null
    }

    // One request on a file's connection, in whichever protocol it speaks, and its answer.
    ask_file :: fn(state: ptr[SlopFile], out: ptr[mut Outgoing], into: ptr[mut Incoming]) -> bool {
        if state.writes {
            if file.send_request(state.end, state.port, out) is_some {
                return false
            }
            loop {
                match file.receive_response(state.end, state.port, into, true) {
                    case Received => return true
                    case Failed(error) => return false
                    case _ => continue
                }
            }
        }
        if read_only_file.send_request(state.end, state.port, out) is_some {
            return false
        }
        loop {
            match read_only_file.receive_response(state.end, state.port, into, true) {
                case Received => return true
                case Failed(error) => return false
                case _ => continue
            }
        }
    }

    done_file :: fn(into: ptr[Incoming]) -> bool {
        return match message_of[file.Response](into)^ {
            case Done => true
            case _ => false
        }
    }

    done_read_only :: fn(into: ptr[Incoming]) -> bool {
        return match message_of[read_only_file.Response](into)^ {
            case Done => true
            case _ => false
        }
    }

    system_open :: fn(path: string, mode: OpenMode) -> (file : File, error : OsError?) {
        if !is_beneath(path) {
            return File.{0}, OsError.InvalidPath
        }
        working, working_error :: system_working_directory()
        if working_error != null {
            return File.{0}, working_error
        }
        defer system_close_directory(working)
        return system_open_in(working, path, mode)
    }

    system_open_in :: fn(directory: Directory, path: string, mode: OpenMode) -> (file : File, error : OsError?) {
        state :: directory_of(directory)
        out := Outgoing.{}
        request :: begin[dir.Request](&out)
        if mode == .READ {
            request^ = .OpenReadOnlyFile(relative_path(&out, path))
        }
        else {
            creation := files.Creation.Existing
            if mode == .WRITE {
                creation = .Truncate
            }
            else if mode == .APPEND {
                creation = .Either
            }
            request^ = .OpenFile(dir.OpenFile.{path = relative_path(&out, path), creation = creation})
        }
        into := Incoming.{}
        if !ask_directory(state, &out, &into) {
            return File.{0}, OsError.Other
        }
        end := cast[slop_os.Channel](slop_os.NO_HANDLE)
        writes := true
        match message_of[dir.Response](&into)^ {
            case OpenedFile(connection) => end = connection.end
            case OpenedReadOnlyFile(connection) => {
                end = connection.end
                writes = false
            }
            case Failed(failure) => return File.{0}, error_of_file(failure)
            case _ => return File.{0}, OsError.Other
        }
        made, made_error :: file_on(end, writes)
        if made_error != null {
            return File.{0}, made_error
        }
        // Appending starts at the end
        if mode == .APPEND {
            size, size_error :: system_file_size(made)
            if size_error == null {
                file_of(made).offset = size
            }
        }
        return made, null
    }

    system_close :: fn(handle: File) {
        if handle.handle == 0 {
            return void
        }
        state :: file_of(handle)
        block :: slop_os.startup_block()
        if state.buffer != 0 {
            _ = slop_os.memory_unmap(block.space, state.buffer)
        }
        for each in slop_os.Handle.[cast[slop_os.Handle](state.memory), cast[slop_os.Handle](state.end), cast[slop_os.Handle](state.port)] {
            if each != slop_os.NO_HANDLE {
                _ = slop_os.handle_close(each)
            }
        }
        runtime.free(state)
    }

    system_read :: fn(handle: File, buffer: mut u8[]) -> (count : usize, error : OsError?) {
        state :: file_of(handle)
        if buffer.count == 0 {
            return 0, null
        }
        asked :: if cast[u64](buffer.count) < FILE_BUFFER_BYTES { cast[u64](buffer.count) } else { FILE_BUFFER_BYTES }
        transfer :: files.Transfer.{offset = state.offset, count = cast[u32](asked), buffer_offset = 0}
        out := Outgoing.{}
        if state.writes {
            request :: begin[file.Request](&out)
            request^ = .Read(transfer)
        }
        else {
            request :: begin[read_only_file.Request](&out)
            request^ = .Read(transfer)
        }
        into := Incoming.{}
        if !ask_file(state, &out, &into) {
            return 0, OsError.Other
        }
        got := cast[u32](0)
        if state.writes {
            match message_of[file.Response](&into)^ {
                case Transferred(count) => got = count
                case Failed(failure) => return 0, error_of_file(failure)
                case _ => return 0, OsError.Other
            }
        }
        else {
            match message_of[read_only_file.Response](&into)^ {
                case Transferred(count) => got = count
                case Failed(failure) => return 0, error_of_file(failure)
                case _ => return 0, OsError.Other
            }
        }
        count :: if cast[u64](got) > asked { asked } else { cast[u64](got) }
        if count > 0 {
            intrinsics.mem_copy_non_overlapping(cast[mut rawptr](buffer.data), cast[rawptr](state.buffer), cast[usize](count))
        }
        state.offset += count
        return cast[usize](count), null
    }

    system_write :: fn(handle: File, bytes: rawptr, count: usize) -> (written : usize, error : OsError?) {
        state :: file_of(handle)
        if !state.writes {
            return 0, OsError.AccessDenied
        }
        now :: if cast[u64](count) < FILE_BUFFER_BYTES { cast[u64](count) } else { FILE_BUFFER_BYTES }
        intrinsics.mem_copy_non_overlapping(cast[mut rawptr](state.buffer), bytes, cast[usize](now))
        out := Outgoing.{}
        request :: begin[file.Request](&out)
        request^ = .Write(files.Transfer.{offset = state.offset, count = cast[u32](now), buffer_offset = 0})
        into := Incoming.{}
        if !ask_file(state, &out, &into) {
            return 0, OsError.Other
        }
        match message_of[file.Response](&into)^ {
            case Transferred(moved) => {
                state.offset += cast[u64](moved)
                return cast[usize](moved), null
            }
            case Failed(failure) => return 0, error_of_file(failure)
            case _ => return 0, OsError.Other
        }
    }

    system_file_size :: fn(handle: File) -> (size : u64, error : OsError?) {
        state :: file_of(handle)
        out := Outgoing.{}
        if state.writes {
            request :: begin[file.Request](&out)
            request^ = .Info
        }
        else {
            request :: begin[read_only_file.Request](&out)
            request^ = .Info
        }
        into := Incoming.{}
        if !ask_file(state, &out, &into) {
            return 0, OsError.Other
        }
        if state.writes {
            match message_of[file.Response](&into)^ {
                case Described(info) => return info.size, null
                case Failed(failure) => return 0, error_of_file(failure)
                case _ => return 0, OsError.Other
            }
        }
        match message_of[read_only_file.Response](&into)^ {
            case Described(info) => return info.size, null
            case Failed(failure) => return 0, error_of_file(failure)
            case _ => return 0, OsError.Other
        }
    }

    // A Remove or Rename's answer, Done or why not.
    finished :: fn(state: ptr[SlopDirectory], out: ptr[mut Outgoing]) -> OsError? {
        into := Incoming.{}
        if !ask_directory(state, out, &into) {
            return OsError.Other
        }
        match message_of[dir.Response](&into)^ {
            case Done => return null
            case Failed(failure) => return error_of_file(failure)
            case _ => return OsError.Other
        }
    }

    system_path_kind_in :: fn(directory: Directory, path: string) -> PathKind {
        opened, error :: system_open_directory_in(directory, path)
        if error == null {
            system_close_directory(opened)
            return .DIRECTORY
        }
        if error == OsError.NotADirectory {
            return .FILE
        }
        state :: directory_of(directory)
        out := Outgoing.{}
        request :: begin[dir.Request](&out)
        request^ = .OpenReadOnlyFile(relative_path(&out, path))
        into := Incoming.{}
        if !ask_directory(state, &out, &into) {
            return .NOTHING
        }
        match message_of[dir.Response](&into)^ {
            case OpenedReadOnlyFile(connection) => {
                _ = slop_os.handle_close(cast[slop_os.Handle](connection.end))
                return .FILE
            }
            case _ => return .NOTHING
        }
    }

    // What's at path, removed: a file only, or a directory only, as directory says.
    remove_in :: fn(directory: Directory, path: string, is_directory: bool) -> OsError? {
        kind :: system_path_kind_in(directory, path)
        if kind == .NOTHING {
            return OsError.NotFound
        }
        if kind == .DIRECTORY && !is_directory {
            return OsError.IsADirectory
        }
        if kind == .FILE && is_directory {
            return OsError.NotADirectory
        }
        state :: directory_of(directory)
        out := Outgoing.{}
        request :: begin[dir.Request](&out)
        request^ = .Remove(relative_path(&out, path))
        return finished(state, &out)
    }

    system_delete_file_in :: fn(directory: Directory, path: string) -> OsError? {
        return remove_in(directory, path, false)
    }

    system_remove_directory_in :: fn(directory: Directory, path: string) -> OsError? {
        return remove_in(directory, path, true)
    }

    system_rename_in :: fn(directory: Directory, from: string, to: string) -> OsError? {
        state :: directory_of(directory)
        out := Outgoing.{}
        request :: begin[dir.Request](&out)
        request^ = .Rename(dir.Rename.{from = relative_path(&out, from), to = relative_path(&out, to)})
        return finished(state, &out)
    }

    // A directory, its parent there already, and nothing at path yet.
    system_make_directory_in :: fn(directory: Directory, path: string) -> OsError? {
        if system_path_kind_in(directory, path) != .NOTHING {
            return OsError.AlreadyExists
        }
        last := path.count
        for character, i in path {
            if character == '/' {
                last = i
            }
        }
        if last < path.count && system_path_kind_in(directory, string_of(cast[ptr[u8]](path.data), last)) != .DIRECTORY {
            return OsError.NotFound
        }
        state :: directory_of(directory)
        out := Outgoing.{}
        request :: begin[dir.Request](&out)
        request^ = .OpenDirectory(dir.OpenDirectory.{path = relative_path(&out, path), create = true})
        into := Incoming.{}
        if !ask_directory(state, &out, &into) {
            return OsError.Other
        }
        match message_of[dir.Response](&into)^ {
            case OpenedDirectory(made) => {
                _ = slop_os.handle_close(cast[slop_os.Handle](made.end))
                return null
            }
            case Failed(failure) => return error_of_file(failure)
            case _ => return OsError.Other
        }
    }

    system_list_directory_in :: fn(directory: Directory, path: string, entries: ptr[mut DirectoryEntry[..]], allocator: runtime.Allocator) -> OsError? {
        if path.count != 0 {
            opened, error :: system_open_directory_in(directory, path)
            if error != null {
                return error
            }
            defer system_close_directory(opened)
            return list_of(opened, entries, allocator)
        }
        return list_of(directory, entries, allocator)
    }

    // Every entry of an open directory, from the start.
    list_of :: fn(listed: Directory, entries: ptr[mut DirectoryEntry[..]], allocator: runtime.Allocator) -> OsError? {
        state :: directory_of(listed)
        cursor := cast[u64](0)
        loop {
            out := Outgoing.{}
            request :: begin[dir.Request](&out)
            request^ = .List(cursor)
            into := Incoming.{}
            if !ask_directory(state, &out, &into) {
                return OsError.Other
            }
            match message_of[dir.Response](&into)^ {
                case Listed(listing) => {
                    name :: items(&into, listing.name)
                    copy, error :: copy_string(if name.count == 0 { "" } else { string_of(&name[0], name.count) }, allocator)
                    if error != null {
                        return error
                    }
                    runtime.array_add(entries, DirectoryEntry.{name = copy, is_directory = listing.kind == .Directory})
                    cursor = listing.next
                }
                case End => return null
                case Failed(failure) => return error_of_file(failure)
                case _ => return OsError.Other
            }
        }
    }

    // The path functions, beneath the working directory

    system_delete_file :: fn(path: string) -> OsError? {
        if !is_beneath(path) {
            return OsError.InvalidPath
        }
        working, error :: system_working_directory()
        if error != null {
            return error
        }
        defer system_close_directory(working)
        return system_delete_file_in(working, path)
    }

    system_rename :: fn(from: string, to: string) -> OsError? {
        if !is_beneath(from) || !is_beneath(to) {
            return OsError.InvalidPath
        }
        working, error :: system_working_directory()
        if error != null {
            return error
        }
        defer system_close_directory(working)
        return system_rename_in(working, from, to)
    }

    system_path_kind :: fn(path: string) -> PathKind {
        if !is_beneath(path) {
            return .NOTHING
        }
        working, error :: system_working_directory()
        if error != null {
            return .NOTHING
        }
        defer system_close_directory(working)
        return system_path_kind_in(working, path)
    }

    system_make_directory :: fn(path: string) -> OsError? {
        if !is_beneath(path) {
            return OsError.InvalidPath
        }
        working, error :: system_working_directory()
        if error != null {
            return error
        }
        defer system_close_directory(working)
        return system_make_directory_in(working, path)
    }

    system_remove_directory :: fn(path: string) -> OsError? {
        if !is_beneath(path) {
            return OsError.InvalidPath
        }
        working, error :: system_working_directory()
        if error != null {
            return error
        }
        defer system_close_directory(working)
        return system_remove_directory_in(working, path)
    }

    system_list_directory :: fn(path: string, entries: ptr[mut DirectoryEntry[..]], allocator: runtime.Allocator) -> OsError? {
        if path.count != 0 && !is_beneath(path) {
            return OsError.InvalidPath
        }
        working, error :: system_working_directory()
        if error != null {
            return error
        }
        defer system_close_directory(working)
        return system_list_directory_in(working, path, entries, allocator)
    }

    // No paths above the working directory, so no current directory to give or change.
    system_current_directory :: fn(allocator: runtime.Allocator) -> (path #unrestricted : string, error : OsError?) {
        return "", OsError.Unsupported
    }

    system_set_current_directory :: fn(path: string) -> OsError? {
        return OsError.Unsupported
    }
}

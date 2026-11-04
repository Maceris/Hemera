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

    /**
     * The size of each File's buffer, in bytes: the most one read or write moves, so a bigger one takes several
     * calls.
     */
    FILE_BUFFER_BYTES : u64 : 64 * 1024
    /** The label of the grant the path functions resolve beneath: a channel speaking dir. */
    WORKING_DIRECTORY :: "working_directory"

    /** What a File is: its connection, whether it writes, its buffer, and where it's at. */
    SlopFile :: struct {
        /** The connection's end, speaking file or read_only_file; owned, closed by system_close. */
        end : slop_os.Channel,
        /** A port bound to end (port_for), owned, closed by system_close. */
        port : slop_os.Port,
        /** Whether the connection speaks file, which writes, rather than read_only_file. */
        writes : bool,
        /** Where the buffer is mapped in the program's address space, or 0 while it isn't. */
        buffer : u64,
        /**
         * The buffer, FILE_BUFFER_BYTES of memory the server was given a handle of its own to; owned, closed by
         * system_close, or NO_HANDLE if it couldn't be made.
         */
        memory : slop_os.Memory,
        /** Where the next read or write starts, in bytes from the file's start. */
        offset : u64,
    }

    /** What a Directory is: its connection. */
    SlopDirectory :: struct {
        /** The connection's end, speaking dir; owned, closed by system_close_directory. */
        end : slop_os.Channel,
        /** A port bound to end (port_for), owned, closed by system_close_directory. */
        port : slop_os.Port,
    }

    /**
     * Find a File's record.
     *
     * @param handle An open File, not the zero one.
     * @return Its record, good until the File is closed.
     */
    file_of :: fn(handle: File) -> ptr[mut SlopFile] {
        return cast[ptr[mut SlopFile]](handle.handle)
    }

    /**
     * Find a Directory's record.
     *
     * @param handle An open Directory, not the zero one.
     * @return Its record, good until the Directory is closed.
     */
    directory_of :: fn(handle: Directory) -> ptr[mut SlopDirectory] {
        return cast[ptr[mut SlopDirectory]](handle.handle)
    }

    /**
     * Translate a file server's error into std's.
     *
     * Errors std has no match for, like NoSpace, DeviceError and Corrupt, become Other; ReadOnly and Revoked become
     * AccessDenied.
     *
     * @param error What the server answered.
     * @return The OsError a caller sees.
     */
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
            case .Revoked => OsError.AccessDenied
            case .Unavailable => OsError.Other
            case .IsALink => OsError.Other
            case .NoMemory => OsError.OutOfMemory
            case .WrongType => OsError.WrongType
        }
    }

    /**
     * Make a Directory of a connection's end, with a port of its own.
     *
     * @param end An end speaking dir, which the Directory takes over, even on failure, when it's closed.
     * @return directory The Directory, which the caller closes with system_close_directory; its record is from the
     *     context's allocator. The zero Directory on failure.
     * @return error OutOfMemory if the port couldn't be made, or null.
     */
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

    /**
     * Send one request on a directory's connection and wait for its answer.
     *
     * @param state The directory's record.
     * @param out The request, built with begin[dir.Request]; its handles are moved out when it's sent.
     * @param into Where the answer goes, for message_of[dir.Response].
     * @return True once the answer is in into; false if sending or receiving failed, as when the connection's gone.
     */
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

    /**
     * Append a path's bytes to a request being built.
     *
     * @param out The request, after begin. A path that doesn't fit MESSAGE_BYTES fails an assertion.
     * @param path The path, copied as it is, not checked.
     * @return Where its bytes are, for the request's Relative field.
     */
    relative_path :: fn(out: ptr[mut Outgoing], path: string) -> slop_os.Relative[u8] {
        return append(out, view_of(cast[ptr[u8]](path.data), path.count))
    }

    /**
     * Open the working directory: a connection of its own to the "working_directory" grant, so closing it leaves the
     * grant for the next.
     *
     * @return directory The working directory, which the caller closes with system_close_directory; the zero
     *     Directory on failure.
     * @return error NotFound if the program wasn't given the grant, OutOfMemory if its port couldn't be made, Other
     *     if the server didn't connect, or null.
     */
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

    /**
     * Open a directory beneath the working directory.
     *
     * @param path The directory's path, beneath the working directory (is_beneath).
     * @return directory The directory, which the caller closes with system_close_directory; the zero Directory on
     *     failure.
     * @return error InvalidPath for a path that isn't beneath, the working directory's error, the server's, or null.
     */
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

    /**
     * Open a directory beneath another, through its server's OpenDirectory.
     *
     * @param directory The open directory path is beneath, which stays the caller's.
     * @param path The path, relative to directory; the server judges it.
     * @return opened The directory, which the caller closes with system_close_directory; the zero Directory on
     *     failure.
     * @return error The server's error (error_of_file), like NotFound or NotADirectory; OutOfMemory if its port
     *     couldn't be made; Other if the connection failed or answered wrongly; or null.
     */
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

    /**
     * Close a directory: its connection and port, and its record, given back to the context's allocator.
     *
     * @param directory The directory, which isn't good afterwards; the zero Directory is ignored.
     */
    system_close_directory :: fn(directory: Directory) {
        if directory.handle == 0 {
            return void
        }
        state :: directory_of(directory)
        _ = slop_os.handle_close(cast[slop_os.Handle](state.end))
        _ = slop_os.handle_close(cast[slop_os.Handle](state.port))
        runtime.free(state)
    }

    /**
     * Make a File of a file connection's end: a port of its own, and a buffer, made, mapped and given to its server.
     *
     * @param end An end speaking file or read_only_file, which the File takes over; on failure, it's closed.
     * @param writes Whether end speaks file (true) or read_only_file (false).
     * @return file The File, which the caller closes with system_close; its record is from the context's allocator.
     *     The zero File on failure, with everything made closed again.
     * @return error OutOfMemory if the port or the buffer couldn't be made, mapped or duplicated; Other if the server
     *     didn't take the buffer; or null.
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

    /**
     * Send one request on a file's connection, in whichever protocol it speaks, and wait for its answer.
     *
     * @param state The file's record, whose writes says the protocol.
     * @param out The request, built with begin of file's or read_only_file's Request, as state.writes says.
     * @param into Where the answer goes, for message_of of the same protocol's Response.
     * @return True once the answer is in into; false if sending or receiving failed, as when the connection's gone.
     */
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

    /**
     * Tell whether a file protocol's answer is Done.
     *
     * @param into An answer received from a connection speaking file.
     * @return True for Done, false for anything else, Failed included.
     */
    done_file :: fn(into: ptr[Incoming]) -> bool {
        return match message_of[file.Response](into)^ {
            case Done => true
            case _ => false
        }
    }

    /**
     * Tell whether a read_only_file protocol's answer is Done.
     *
     * @param into An answer received from a connection speaking read_only_file.
     * @return True for Done, false for anything else, Failed included.
     */
    done_read_only :: fn(into: ptr[Incoming]) -> bool {
        return match message_of[read_only_file.Response](into)^ {
            case Done => true
            case _ => false
        }
    }

    /**
     * Open a file beneath the working directory, as system_open_in does.
     *
     * @param path The file's path, beneath the working directory (is_beneath).
     * @param mode How it's opened (OpenMode).
     * @return file The File, which the caller closes with system_close; the zero File on failure.
     * @return error InvalidPath for a path that isn't beneath, the working directory's error, system_open_in's, or
     *     null.
     */
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

    /**
     * Open a file beneath a directory, untyped: open_with_schema with no schema.
     *
     * @param directory The open directory path is beneath, which stays the caller's.
     * @param path The path, relative to directory.
     * @param mode How it's opened (OpenMode).
     * @return file The File, which the caller closes with system_close; the zero File on failure.
     * @return error As open_with_schema's, or null.
     */
    system_open_in :: fn(directory: Directory, path: string, mode: OpenMode) -> (file : File, error : OsError?) {
        untyped : u8[32]
        return open_with_schema(directory, path, mode, untyped)
    }

    /**
     * Open the file at path beneath directory, with a schema hash: one made has the type, and one there must have it,
     * or it's WrongType (the SlopOS repository's 0046, 0108).
     *
     * READ opens it with read_only_file; the other modes with file, WRITE making or emptying it, APPEND making it if
     * it's missing and starting at its end, and READ_WRITE needing it there.
     *
     * @param directory The open directory path is beneath, which stays the caller's.
     * @param path The path, relative to directory.
     * @param mode How it's opened (OpenMode).
     * @param schema The record type's schema hash, or all zeros for an untyped file, which skips the check. A
     *     read-only open asks for no type, so the type is checked once it's open.
     * @return file The File, which the caller closes with system_close; the zero File on failure, closed again if it
     *     was opened.
     * @return error WrongType when a typed open finds a file of another type; the server's error (error_of_file);
     *     file_on's; Other if the connection failed or answered wrongly; or null.
     */
    open_with_schema :: fn(directory: Directory, path: string, mode: OpenMode, schema: u8[32]) -> (file : File, error : OsError?) {
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
            request^ = .OpenFile(dir.OpenFile.{path = relative_path(&out, path), creation = creation, schema = schema})
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
        // Read-only opens ask for no type, so it's checked once it's open
        if !writes && !all_zero(schema) {
            size, held, info_error :: file_info(made)
            if info_error != null || held != schema {
                system_close(made)
                return File.{0}, if info_error != null { info_error } else { OsError.WrongType }
            }
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

    /**
     * Close a file: its buffer unmapped, its buffer, connection and port closed, and its record given back to the
     * context's allocator.
     *
     * @param handle The file, which isn't good afterwards; the zero File is ignored.
     */
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

    /**
     * Read from a file at its offset, through its buffer, moving the offset past what was read.
     *
     * @param handle The open file.
     * @param buffer Where the bytes go. At most FILE_BUFFER_BYTES are read in one call, however big it is.
     * @return count How many bytes were read: 0 for an empty buffer, or at the file's end; fewer than asked when less
     *     is left. 0 on failure.
     * @return error The server's error (error_of_file); Other if the connection failed or answered wrongly; or null.
     */
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

    /**
     * Write to a file at its offset, through its buffer, moving the offset past what was written.
     *
     * @param handle The open file.
     * @param bytes The bytes to write, count of them, copied into the buffer before the request.
     * @param count How many bytes there are. At most FILE_BUFFER_BYTES are written in one call.
     * @return written How many bytes the server wrote, which can be fewer than count; 0 on failure.
     * @return error AccessDenied for a file opened only to read; the server's error (error_of_file); Other if the
     *     connection failed or answered wrongly; or null.
     */
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

    /**
     * Ask a file's server for the file's size.
     *
     * @param handle The open file.
     * @return size The size in bytes, or 0 on failure.
     * @return error As file_info's, or null.
     */
    system_file_size :: fn(handle: File) -> (size : u64, error : OsError?) {
        size, schema, error :: file_info(handle)
        return size, error
    }

    /**
     * Ask a file's server for the file's size and type, with its protocol's Info.
     *
     * @param handle The open file.
     * @return size The size in bytes, or 0 on failure.
     * @return schema The file's schema hash: all zeros for an untyped one, or on failure.
     * @return error The server's error (error_of_file); Other if the connection failed or answered wrongly; or null.
     */
    file_info :: fn(handle: File) -> (size : u64, schema : u8[32], error : OsError?) {
        none : u8[32]
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
            return 0, none, OsError.Other
        }
        if state.writes {
            match message_of[file.Response](&into)^ {
                case Described(info) => return info.size, info.schema, null
                case Failed(failure) => return 0, none, error_of_file(failure)
                case _ => return 0, none, OsError.Other
            }
        }
        match message_of[read_only_file.Response](&into)^ {
            case Described(info) => return info.size, info.schema, null
            case Failed(failure) => return 0, none, error_of_file(failure)
            case _ => return 0, none, OsError.Other
        }
    }

    /**
     * Tell whether a schema hash is all zeros, the hash of no type.
     *
     * @param bytes The hash.
     * @return True if every byte is 0.
     */
    all_zero :: fn(bytes: u8[32]) -> bool {
        for byte in bytes {
            if byte != 0 {
                return false
            }
        }
        return true
    }

    /**
     * Send a request whose answer is Done or Failed, like Remove or Rename, and wait for it.
     *
     * @param state The directory's record.
     * @param out The request, built with begin[dir.Request].
     * @return Null for Done; the server's error (error_of_file); or Other if the connection failed or answered
     *     wrongly.
     */
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

    /**
     * Find what's at a path beneath a directory, by opening it: first as a directory, then, if that fails for
     * another reason than its being a file, as a file to read.
     *
     * @param directory The open directory path is beneath, which stays the caller's.
     * @param path The path, relative to directory.
     * @return DIRECTORY or FILE, or NOTHING if neither opened, for whatever reason, a failed connection included.
     */
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

    /**
     * Remove what's at a path beneath a directory: a file only, or a directory only, as is_directory says.
     *
     * @param directory The open directory path is beneath, which stays the caller's.
     * @param path The path, relative to directory.
     * @param is_directory Whether what's there has to be a directory (true) or a file (false).
     * @return Null once it's removed; NotFound if nothing's there, IsADirectory or NotADirectory if it's the other
     *     kind, the server's error (like DirectoryNotEmpty), or Other if the connection failed.
     */
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

    /**
     * Delete a file beneath a directory.
     *
     * @param directory The open directory path is beneath, which stays the caller's.
     * @param path The file's path, relative to directory.
     * @return Null once it's deleted, or remove_in's error.
     */
    system_delete_file_in :: fn(directory: Directory, path: string) -> OsError? {
        return remove_in(directory, path, false)
    }

    /**
     * Remove a directory beneath a directory.
     *
     * @param directory The open directory path is beneath, which stays the caller's.
     * @param path The directory's path, relative to directory.
     * @return Null once it's removed, or remove_in's error.
     */
    system_remove_directory_in :: fn(directory: Directory, path: string) -> OsError? {
        return remove_in(directory, path, true)
    }

    /**
     * Rename, or move, what's at a path beneath a directory, through its server's Rename.
     *
     * @param directory The open directory both paths are beneath, which stays the caller's.
     * @param from Where it is, relative to directory.
     * @param to Where it goes, relative to directory.
     * @return Null once it's moved, the server's error (error_of_file), or Other if the connection failed.
     */
    system_rename_in :: fn(directory: Directory, from: string, to: string) -> OsError? {
        state :: directory_of(directory)
        out := Outgoing.{}
        request :: begin[dir.Request](&out)
        request^ = .Rename(dir.Rename.{from = relative_path(&out, from), to = relative_path(&out, to)})
        return finished(state, &out)
    }

    /**
     * Make a directory beneath a directory, its parent there already, and nothing at path yet.
     *
     * @param directory The open directory path is beneath, which stays the caller's.
     * @param path The new directory's path, relative to directory.
     * @return Null once it's made; AlreadyExists if something's at path, NotFound if its parent isn't a directory
     *     that's there, the server's error (error_of_file), or Other if the connection failed.
     */
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

    /**
     * List a directory beneath a directory, or the directory itself.
     *
     * @param directory The open directory, which stays the caller's.
     * @param path The path of the directory to list, relative to directory, or empty for directory itself.
     * @param entries Where the entries are added, after what it holds already; on failure, those listed so far stay.
     * @param allocator Where the entries' names are allocated, which the caller frees.
     * @return Null once every entry is added; system_open_directory_in's error, or list_of's.
     */
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

    /**
     * List every entry of an open directory, from the start, one List request per entry.
     *
     * @param listed The open directory, which stays the caller's.
     * @param entries Where the entries are added, in the server's order; on failure, those listed so far stay.
     * @param allocator Where the entries' names are allocated, which the caller frees.
     * @return Null at the listing's end; OutOfMemory if a name couldn't be copied, the server's error
     *     (error_of_file), or Other if the connection failed or answered wrongly.
     */
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

    /**
     * Delete a file beneath the working directory.
     *
     * @param path The file's path, beneath the working directory (is_beneath).
     * @return Null once it's deleted; InvalidPath for a path that isn't beneath, the working directory's error, or
     *     system_delete_file_in's.
     */
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

    /**
     * Rename, or move, what's at a path beneath the working directory.
     *
     * @param from Where it is, beneath the working directory.
     * @param to Where it goes, beneath the working directory.
     * @return Null once it's moved; InvalidPath if either isn't beneath, the working directory's error, or
     *     system_rename_in's.
     */
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

    /**
     * Find what's at a path beneath the working directory.
     *
     * @param path The path, beneath the working directory.
     * @return As system_path_kind_in's; NOTHING too for a path that isn't beneath, or without a working directory.
     */
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

    /**
     * Make a directory beneath the working directory.
     *
     * @param path The new directory's path, beneath the working directory.
     * @return Null once it's made; InvalidPath for a path that isn't beneath, the working directory's error, or
     *     system_make_directory_in's.
     */
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

    /**
     * Remove a directory beneath the working directory.
     *
     * @param path The directory's path, beneath the working directory.
     * @return Null once it's removed; InvalidPath for a path that isn't beneath, the working directory's error, or
     *     system_remove_directory_in's.
     */
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

    /**
     * List a directory beneath the working directory, or the working directory itself.
     *
     * @param path The directory's path, beneath the working directory, or empty for the working directory.
     * @param entries Where the entries are added, after what it holds already.
     * @param allocator Where the entries' names are allocated, which the caller frees.
     * @return Null once every entry is added; InvalidPath for a path that isn't beneath, the working directory's
     *     error, or system_list_directory_in's.
     */
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

    /**
     * Give the current directory's path, which SlopOS hasn't: there are no paths above the working directory.
     *
     * @param allocator Unused.
     * @return path Always empty.
     * @return error Always Unsupported.
     */
    system_current_directory :: fn(allocator: runtime.Allocator) -> (path #unrestricted : string, error : OsError?) {
        return "", OsError.Unsupported
    }

    /**
     * Change the current directory, which SlopOS hasn't: there are no paths above the working directory.
     *
     * @param path Unused.
     * @return Always Unsupported.
     */
    system_set_current_directory :: fn(path: string) -> OsError? {
        return OsError.Unsupported
    }
}

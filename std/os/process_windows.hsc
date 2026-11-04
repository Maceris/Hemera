package os

import runtime from "base"

/*
 * Windows' run_process: the child's standard output and error go to pipes the parent reads, polling
 * both so a child that fills one while the other is being waited on can't stall, and its command
 * line is quoted the way the C runtime splits it back into arguments.
 */
#if OS == .Windows {
    /**
     * Make an anonymous pipe.
     *
     * @param read Where the reading end's handle is stored, which the caller closes.
     * @param write Where the writing end's handle is stored, which the caller closes.
     * @param attributes A SecurityAttributes saying whether both ends are inherited, or null for neither.
     * @param size A suggested buffer size in bytes, or 0 for the system's default.
     * @return Nonzero once both ends are made; 0 if not, with GetLastError saying why.
     */
    CreatePipe #foreign(KERNEL32) : fn(read: ptr[mut rawptr], write: ptr[mut rawptr], attributes: rawptr, size: u32) -> i32 : ---
    /**
     * Change a handle's flags, like whether a child process inherits it.
     *
     * @param handle The handle.
     * @param mask Which flags change, like HANDLE_FLAG_INHERIT.
     * @param flags Their new values, under mask: 0 to clear them.
     * @return Nonzero once they're changed; 0 if not.
     */
    SetHandleInformation #foreign(KERNEL32) : fn(handle: rawptr, mask: u32, flags: u32) -> i32 : ---
    /**
     * Start a process, with its first thread.
     *
     * @param application The program's path as UTF-16, or null for it to be the command line's first word, looked for
     *     in the folders Windows searches, with ".exe" added when it has no extension.
     * @param command_line The command line as UTF-16 with a terminator, in memory Windows may change while it's called.
     * @param process_attributes Security attributes for the process's handle, or null for the defaults.
     * @param thread_attributes Security attributes for the thread's handle, or null for the defaults.
     * @param inherit_handles Nonzero for the child to inherit the caller's inheritable handles.
     * @param flags How it's made, like CREATE_NO_WINDOW.
     * @param environment The child's environment, or null for the caller's.
     * @param directory The folder it starts in as UTF-16 with a terminator, or null for the caller's current one.
     * @param startup A StartupInfo, like which handles are its standard ones.
     * @param information Where a ProcessInformation is stored, whose handles the caller closes.
     * @return Nonzero once the process is started; 0 if not, with GetLastError saying why.
     */
    CreateProcessW #foreign(KERNEL32) : fn(application: rawptr, command_line: rawptr, process_attributes: rawptr,
        thread_attributes: rawptr, inherit_handles: i32, flags: u32, environment: rawptr, directory: rawptr, startup: rawptr,
        information: rawptr) -> i32 : ---
    /**
     * Look at what's waiting in a pipe without waiting for more.
     *
     * @param pipe The pipe's reading end.
     * @param buffer Where to copy what's waiting without taking it, or null not to.
     * @param size The size of buffer in bytes, or 0.
     * @param read Where how many bytes were copied is stored, or null.
     * @param available Where how many bytes are waiting is stored.
     * @param left Where how many bytes are left of the message is stored, or null.
     * @return Nonzero if it worked; 0 if not, as when the pipe's writers have all closed it (ERROR_BROKEN_PIPE).
     */
    PeekNamedPipe #foreign(KERNEL32) : fn(pipe: rawptr, buffer: rawptr, size: u32, read: rawptr, available: ptr[mut u32],
        left: rawptr) -> i32 : ---
    /**
     * Wait until an object is signaled, like a process ending, or time runs out.
     *
     * @param handle The object, like a process's handle.
     * @param milliseconds How long to wait at most, or INFINITE for as long as it takes.
     * @return 0 (WAIT_OBJECT_0) if it was signaled; another value on a timeout or failure.
     */
    WaitForSingleObject #foreign(KERNEL32) : fn(handle: rawptr, milliseconds: u32) -> u32 : ---
    /**
     * Give a process's exit code.
     *
     * @param process The process's handle.
     * @param code Where the code is stored: what it exited with, or STILL_ACTIVE (259) while it runs.
     * @return Nonzero if it worked; 0 if not, and code is left as it was.
     */
    GetExitCodeProcess #foreign(KERNEL32) : fn(process: rawptr, code: ptr[mut u32]) -> i32 : ---
    /**
     * Suspend the calling thread for a while.
     *
     * @param milliseconds How long, at least; the system's timer may round it up.
     */
    Sleep #foreign(KERNEL32) : fn(milliseconds: u32) : ---

    /** SetHandleInformation's flag for a handle a child process inherits. */
    HANDLE_FLAG_INHERIT : u32 : 1
    /** StartupInfo's flag that its standard handles are to be used. */
    STARTF_USESTDHANDLES : u32 : 0x100
    /** CreateProcessW's flag for a console program to run without a console window of its own. */
    CREATE_NO_WINDOW : u32 : 0x08000000
    /** CreateProcessW's flag that the environment given is UTF-16. */
    CREATE_UNICODE_ENVIRONMENT : u32 : 0x400
    /** WaitForSingleObject's time for waiting as long as it takes. */
    INFINITE : u32 : 0xffffffff

    /** SECURITY_ATTRIBUTES: whether a handle being made is inherited. */
    SecurityAttributes :: struct {
        /** The structure's size in bytes. */
        length : u32,
        /** A security descriptor, or null for the default. */
        descriptor : rawptr,
        /** Nonzero for the handle to be inherited by child processes. */
        inherit_handle : i32,
    }

    /** STARTUPINFOW: how a new process's window and standard handles are set up; zero for every default. */
    StartupInfo :: struct {
        /** The structure's size in bytes. */
        size : u32,
        /** Reserved: null. */
        reserved : rawptr,
        /** The desktop's name, or null for the caller's. */
        desktop : rawptr,
        /** A console window's title, or null for the program's name. */
        title : rawptr,
        /** Where the window goes, across in pixels, when flags says so. */
        x : u32,
        /** Where the window goes, down in pixels, when flags says so. */
        y : u32,
        /** The window's width in pixels, when flags says so. */
        x_size : u32,
        /** The window's height in pixels, when flags says so. */
        y_size : u32,
        /** A console's width in characters, when flags says so. */
        x_count_chars : u32,
        /** A console's height in characters, when flags says so. */
        y_count_chars : u32,
        /** A console's colors, when flags says so. */
        fill_attribute : u32,
        /** Which of the fields are used, like STARTF_USESTDHANDLES. */
        flags : u32,
        /** How the window is shown, when flags says so. */
        show_window : u16,
        /** Reserved: 0. */
        reserved_count : u16,
        /** Reserved: null. */
        reserved_more : rawptr,
        /** The child's standard input, with STARTF_USESTDHANDLES; null for none. */
        standard_input : rawptr,
        /** The child's standard output, with STARTF_USESTDHANDLES, which it has to be able to inherit. */
        standard_output : rawptr,
        /** The child's standard error, with STARTF_USESTDHANDLES, which it has to be able to inherit. */
        standard_error : rawptr,
    }

    /** PROCESS_INFORMATION: what CreateProcessW made. */
    ProcessInformation :: struct {
        /** The new process's handle, which the caller closes. */
        process : rawptr,
        /** Its first thread's handle, which the caller closes. */
        thread : rawptr,
        /** The process's ID. */
        process_id : u32,
        /** The thread's ID. */
        thread_id : u32,
    }

    /**
     * Add one argument to a command line, quoted so the C runtime's splitting gives it back as it is.
     *
     * An argument without spaces, tabs or quotes is added as it is; any other, an empty one too, is put in quotes,
     * with backslashes before a quote doubled and the quote escaped, and those before the closing quote doubled.
     *
     * @param line The command line, as UTF-8, grown with the context's allocator. Nothing goes between arguments
     *     here; the caller adds the space.
     * @param argument The argument, as it should arrive.
     */
    append_argument :: fn(line: ptr[mut u8[..]], argument: string) {
        plain := argument.count > 0
        for character in argument {
            if character == ' ' || character == '\t' || character == '"' {
                plain = false
            }
        }
        if plain {
            for character in argument {
                runtime.array_add(line, cast[u8](character))
            }
            return void
        }
        runtime.array_add(line, cast[u8]('"'))
        backslashes : usize = 0
        for character in argument {
            if character == '\\' {
                backslashes += 1
                continue
            }
            // Backslashes before a quote are doubled, and the quote escaped
            repeat :: if character == '"' { backslashes * 2 + 1 } else { backslashes }
            for i in 0..<repeat {
                runtime.array_add(line, cast[u8]('\\'))
            }
            backslashes = 0
            runtime.array_add(line, cast[u8](character))
        }
        // Before the closing quote, they're doubled so it isn't escaped
        for i in 0..<backslashes * 2 {
            runtime.array_add(line, cast[u8]('\\'))
        }
        runtime.array_add(line, cast[u8]('"'))
    }

    /**
     * Read what's waiting in a pipe, up to 4096 bytes, without waiting for more.
     *
     * @param pipe The pipe's reading end, which stays open.
     * @param buffer Where the bytes are added, grown with the context's allocator.
     * @return read_any Whether any bytes were added.
     * @return finished Whether the pipe is done: its writers have all closed it, or it failed. Once it is, nothing
     *     more will come.
     */
    drain :: fn(pipe: rawptr, buffer: ptr[mut u8[..]]) -> (read_any : bool, finished : bool) {
        available : u32 = 0
        if PeekNamedPipe(pipe, null, 0, null, &available, null) == 0 {
            return false, true
        }
        if available == 0 {
            return false, false
        }
        chunk : u8[4096]
        wanted :: if available < 4096 { available } else { 4096 }
        read : u32 = 0
        if ReadFile(pipe, cast[rawptr](&chunk[0]), wanted, &read, null) == 0 {
            return false, true
        }
        append_bytes(buffer, cast[rawptr](&chunk[0]), cast[usize](read))
        return read > 0, false
    }

    /**
     * Run a program, wait for it to end, and give back its exit code and what it wrote, as run_process does.
     *
     * The child has no standard input and no console window, and inherits the caller's environment. Both pipes are
     * checked in turn, sleeping a millisecond when neither had anything, until both are done; then the process is
     * waited for.
     *
     * @param program The program, the command line's first word: a path, or a name CreateProcessW looks for in the
     *     program's folder, the current folder, the system folders and the PATH, adding ".exe" when it has no
     *     extension.
     * @param arguments The arguments after the program's name, each quoted so the C runtime's splitting gives it back
     *     whole.
     * @param working_directory The folder the child starts in, or null for the caller's current directory.
     * @param allocator Where the output and the error output are allocated from.
     * @return result The exit code, all 32 bits of GetExitCodeProcess's, and the output, owned by the caller and
     *     allocated from allocator; empty, owning nothing, on failure.
     * @return error NotFound when the program or a folder on its path isn't there; FailedToStart when the command
     *     line or the pipes couldn't be made, or CreateProcessW failed otherwise, as for a working_directory that
     *     doesn't exist or a file that isn't a program; or null once the program ran, whatever its exit code.
     */
    system_run_process :: fn(program: string, arguments: string[], working_directory: string?, allocator: runtime.Allocator)
        -> (result #unrestricted : ProcessResult, error : ProcessError?) {

        empty : ProcessResult
        // The command line: the program, then each argument
        line : u8[..]
        defer runtime.array_free(&line)
        append_argument(&line, program)
        for argument in arguments {
            runtime.array_add(&line, cast[u8](' '))
            append_argument(&line, argument)
        }
        command :: wide(as_text(line))
        defer free_wide(command)
        if command.count == 0 {
            return empty, ProcessError.FailedToStart
        }
        directory : u16[]
        match working_directory {
            case Some(path) => directory = wide(path)
            case None => {}
        }
        defer free_wide(directory)

        // Pipes the child writes, which only the parent's reading ends aren't inherited by
        attributes := SecurityAttributes.{length = cast[u32](size_of(SecurityAttributes)), descriptor = null, inherit_handle = 1}
        output_read : rawptr = null
        output_write : rawptr = null
        error_read : rawptr = null
        error_write : rawptr = null
        if CreatePipe(&output_read, &output_write, cast[rawptr](&attributes), 0) == 0 {
            return empty, ProcessError.FailedToStart
        }
        if CreatePipe(&error_read, &error_write, cast[rawptr](&attributes), 0) == 0 {
            _ = CloseHandle(output_read)
            _ = CloseHandle(output_write)
            return empty, ProcessError.FailedToStart
        }
        _ = SetHandleInformation(output_read, HANDLE_FLAG_INHERIT, 0)
        _ = SetHandleInformation(error_read, HANDLE_FLAG_INHERIT, 0)

        startup : StartupInfo
        startup.size = cast[u32](size_of(StartupInfo))
        startup.flags = STARTF_USESTDHANDLES
        startup.standard_output = output_write
        startup.standard_error = error_write
        information : ProcessInformation
        started :: CreateProcessW(null, cast[rawptr](&command[0]), null, null, 1, CREATE_NO_WINDOW, null,
            if directory.count > 0 { cast[rawptr](&directory[0]) } else { null }, cast[rawptr](&startup), cast[rawptr](&information))
        failure :: if started == 0 { GetLastError() } else { 0 }
        // The parent's copies of the writing ends: once the child's are closed too, the pipes end
        _ = CloseHandle(output_write)
        _ = CloseHandle(error_write)
        if started == 0 {
            _ = CloseHandle(output_read)
            _ = CloseHandle(error_read)
            // FILE_NOT_FOUND, PATH_NOT_FOUND
            return empty, if failure == 2 || failure == 3 { ProcessError.NotFound } else { ProcessError.FailedToStart }
        }

        output : u8[..]
        error_output : u8[..]
        push_context with_allocator (allocator = allocator) {
            output_done := false
            error_done := false
            loop {
                if output_done && error_done {
                    break
                }
                any_read := false
                if !output_done {
                    read, finished :: drain(output_read, &output)
                    any_read = any_read || read
                    output_done = finished
                }
                if !error_done {
                    read, finished :: drain(error_read, &error_output)
                    any_read = any_read || read
                    error_done = finished
                }
                if !any_read {
                    Sleep(1)
                }
            }
        }
        _ = WaitForSingleObject(information.process, INFINITE)
        code : u32 = 0
        _ = GetExitCodeProcess(information.process, &code)
        _ = CloseHandle(information.process)
        _ = CloseHandle(information.thread)
        _ = CloseHandle(output_read)
        _ = CloseHandle(error_read)
        result := ProcessResult.{exit_code = cast[int](code), output = as_text(output), error_output = as_text(error_output)}
        return result, null
    }
}

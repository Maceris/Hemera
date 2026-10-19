package os

import runtime from "base"

/*
 * Windows' run_process: the child's standard output and error go to pipes the parent reads, polling
 * both so a child that fills one while the other is being waited on can't stall, and its command
 * line is quoted the way the C runtime splits it back into arguments.
 */
#if OS == .Windows {
    CreatePipe #foreign(KERNEL32) : fn(read: ptr[mut rawptr], write: ptr[mut rawptr], attributes: rawptr, size: u32) -> i32 : ---
    SetHandleInformation #foreign(KERNEL32) : fn(handle: rawptr, mask: u32, flags: u32) -> i32 : ---
    CreateProcessW #foreign(KERNEL32) : fn(application: rawptr, command_line: rawptr, process_attributes: rawptr,
        thread_attributes: rawptr, inherit_handles: i32, flags: u32, environment: rawptr, directory: rawptr, startup: rawptr,
        information: rawptr) -> i32 : ---
    PeekNamedPipe #foreign(KERNEL32) : fn(pipe: rawptr, buffer: rawptr, size: u32, read: rawptr, available: ptr[mut u32],
        left: rawptr) -> i32 : ---
    WaitForSingleObject #foreign(KERNEL32) : fn(handle: rawptr, milliseconds: u32) -> u32 : ---
    GetExitCodeProcess #foreign(KERNEL32) : fn(process: rawptr, code: ptr[mut u32]) -> i32 : ---
    Sleep #foreign(KERNEL32) : fn(milliseconds: u32) : ---

    HANDLE_FLAG_INHERIT : u32 : 1
    STARTF_USESTDHANDLES : u32 : 0x100
    CREATE_NO_WINDOW : u32 : 0x08000000
    CREATE_UNICODE_ENVIRONMENT : u32 : 0x400
    INFINITE : u32 : 0xffffffff

    SecurityAttributes :: struct {
        length : u32,
        descriptor : rawptr,
        inherit_handle : i32,
    }

    StartupInfo :: struct {
        size : u32,
        reserved : rawptr,
        desktop : rawptr,
        title : rawptr,
        x : u32,
        y : u32,
        x_size : u32,
        y_size : u32,
        x_count_chars : u32,
        y_count_chars : u32,
        fill_attribute : u32,
        flags : u32,
        show_window : u16,
        reserved_count : u16,
        reserved_more : rawptr,
        standard_input : rawptr,
        standard_output : rawptr,
        standard_error : rawptr,
    }

    ProcessInformation :: struct {
        process : rawptr,
        thread : rawptr,
        process_id : u32,
        thread_id : u32,
    }

    // One argument, quoted so the C runtime's splitting gives it back as it is.
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

    // What's waiting in a pipe, added to buffer: whether there was any, and whether the pipe is done.
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

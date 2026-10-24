package os

import intrinsics from "base"
import runtime from "base"

/*
 * Linux's run_process, by system calls: the child is forked, points its standard output and error
 * at pipes, and executes the program, looked for on the PATH like execvp. Whether that worked comes
 * back on a third pipe that closes when it does, so a program that isn't there is NotFound rather
 * than an exit code. Everything the child needs is made before it's forked, since a forked child of
 * a threaded process may only make system calls.
 */
#if OS == .Linux && TARGET_ARCH == .x86_64 {
    SYS_POLL : u64 : 7
    SYS_DUP2 : u64 : 33
    SYS_FORK : u64 : 57
    SYS_EXECVE : u64 : 59
    SYS_WAIT4 : u64 : 61
    SYS_EXIT_GROUP : u64 : 231
    SYS_PIPE2 : u64 : 293

    linux_fork :: fn() -> u64 {
        return runtime.linux_syscall(SYS_FORK)
    }

    linux_dup2 :: fn(from: u64, to: u64) -> u64 {
        return runtime.linux_syscall(SYS_DUP2, from, to)
    }

    // Until one of count descriptors at descriptors is ready, however long that takes
    linux_poll :: fn(descriptors: u64, count: u64) -> u64 {
        return runtime.linux_syscall(SYS_POLL, descriptors, count, 0xffff_ffff_ffff_ffff)
    }
}
#else_if OS == .Linux && TARGET_ARCH == .arm64 {
    // The generic table has no fork, dup2 or poll: clone, dup3 and ppoll do what they did
    SYS_DUP3 : u64 : 24
    SYS_PIPE2 : u64 : 59
    SYS_PPOLL : u64 : 73
    SYS_EXIT_GROUP : u64 : 94
    SYS_CLONE : u64 : 220
    SYS_EXECVE : u64 : 221
    SYS_WAIT4 : u64 : 260
    // The signal a child sends its parent when it ends
    SIGCHLD : u64 : 17

    linux_fork :: fn() -> u64 {
        return runtime.linux_syscall(SYS_CLONE, SIGCHLD, 0, 0, 0, 0)
    }

    linux_dup2 :: fn(from: u64, to: u64) -> u64 {
        return runtime.linux_syscall(SYS_DUP3, from, to, 0)
    }

    // Until one of count descriptors at descriptors is ready: no timeout, and no signal mask
    linux_poll :: fn(descriptors: u64, count: u64) -> u64 {
        return runtime.linux_syscall(SYS_PPOLL, descriptors, count, 0, 0, 8)
    }
}

#if OS == .Linux && (TARGET_ARCH == .x86_64 || TARGET_ARCH == .arm64) {

    POLLIN : i16 : 1
    ENOENT : u64 : 2
    EINTR : u64 : 4

    PollDescriptor :: struct {
        descriptor : i32,
        events : i16,
        returned : i16,
    }

    /*
     * first, second and third joined, with a terminator after them, from the context's allocator, as
     * execve takes, kept in made so they're freed together.
     */
    c_copy :: fn(made: ptr[mut u8[..][]], first: string, second: string = "", third: string = "") -> rawptr #unrestricted {
        bytes, error :: runtime.new_array(u8, first.count + second.count + third.count + 1)
        if error != null || bytes.count == 0 {
            return null
        }
        at : usize = 0
        for character in first {
            if at < bytes.count {
                bytes[at] = cast[u8](character)
            }
            at += 1
        }
        for character in second {
            if at < bytes.count {
                bytes[at] = cast[u8](character)
            }
            at += 1
        }
        for character in third {
            if at < bytes.count {
                bytes[at] = cast[u8](character)
            }
            at += 1
        }
        bytes[bytes.count - 1] = 0
        runtime.array_add(made, bytes)
        return cast[rawptr](&bytes[0])
    }

    // Reads what's in a pipe into buffer: whether it's done, at its end or broken.
    read_some :: fn(descriptor: u64, buffer: ptr[mut u8[..]]) -> bool {
        chunk : u8[4096]
        count :: runtime.linux_syscall(SYS_READ, descriptor, cast[u64](&chunk[0]), 4096)
        if failed(count) {
            return 0 - count != EINTR
        }
        if count == 0 {
            return true
        }
        append_bytes(buffer, cast[rawptr](&chunk[0]), cast[usize](count))
        return false
    }

    system_run_process :: fn(program: string, arguments: string[], working_directory: string?, allocator: runtime.Allocator)
        -> (result #unrestricted : ProcessResult, error : ProcessError?) {

        empty : ProcessResult
        made : u8[..][]
        defer {
            for bytes in made {
                runtime.free_array(bytes)
            }
            runtime.array_free(&made)
        }
        // The arguments, the program's name first, and a null after them
        argument_pointers : rawptr[..]
        defer runtime.array_free(&argument_pointers)
        runtime.array_add(&argument_pointers, c_copy(&made, program))
        for argument in arguments {
            runtime.array_add(&argument_pointers, c_copy(&made, argument))
        }
        runtime.array_add(&argument_pointers, null)
        // Where to look for it: as given when it's a path, otherwise each folder on the PATH
        candidates : rawptr[..]
        defer runtime.array_free(&candidates)
        is_path := false
        for character in program {
            is_path = is_path || character == '/'
        }
        if is_path {
            runtime.array_add(&candidates, c_copy(&made, program))
        }
        else {
            search, missing :: system_get_environment("PATH", context.allocator)
            if missing != null {
                runtime.array_add(&candidates, c_copy(&made, "/usr/bin/", program))
            }
            start : usize = 0
            for i in 0..<search.count + 1 {
                if i < search.count && search[i] != ':' {
                    continue
                }
                // An empty entry is the current folder
                folder :: if start < i && i <= search.count { string_of(cast[ptr[u8]](search.data + start), i - start) } else { "." }
                runtime.array_add(&candidates, c_copy(&made, folder, "/", program))
                start = i + 1
            }
            if missing == null {
                runtime.free_array(view_of(cast[ptr[u8]](search.data), search.count))
            }
        }
        directory : rawptr = null
        match working_directory {
            case Some(path) => directory = c_copy(&made, path)
            case None => {}
        }
        environment :: intrinsics.process_state().environment_pointers

        pipes : i32[6]
        if failed(runtime.linux_syscall(SYS_PIPE2, cast[u64](&pipes[0]), O_CLOEXEC)) || failed(runtime.linux_syscall(SYS_PIPE2, cast[u64](&pipes[2]), O_CLOEXEC))
            || failed(runtime.linux_syscall(SYS_PIPE2, cast[u64](&pipes[4]), O_CLOEXEC)) {
            return empty, ProcessError.FailedToStart
        }
        child :: linux_fork()
        if failed(child) {
            return empty, ProcessError.FailedToStart
        }
        if child == 0 {
            // The child: system calls only, then the program, or why it couldn't start on the third pipe
            _ = linux_dup2(cast[u64](pipes[1]), 1)
            _ = linux_dup2(cast[u64](pipes[3]), 2)
            if directory != null {
                _ = runtime.linux_syscall(SYS_CHDIR, cast[u64](directory))
            }
            reason : u64 = ENOENT
            for candidate in candidates {
                attempt :: runtime.linux_syscall(SYS_EXECVE, cast[u64](candidate), cast[u64](argument_pointers.data), cast[u64](environment))
                if 0 - attempt != ENOENT {
                    reason = 0 - attempt
                }
            }
            _ = runtime.linux_syscall(SYS_WRITE, cast[u64](pipes[5]), cast[u64](&reason), 8)
            _ = runtime.linux_syscall(SYS_EXIT_GROUP, 127)
        }
        // The parent keeps the reading ends
        _ = runtime.linux_syscall(SYS_CLOSE, cast[u64](pipes[1]))
        _ = runtime.linux_syscall(SYS_CLOSE, cast[u64](pipes[3]))
        _ = runtime.linux_syscall(SYS_CLOSE, cast[u64](pipes[5]))
        reason : u64 = 0
        reported :: runtime.linux_syscall(SYS_READ, cast[u64](pipes[4]), cast[u64](&reason), 8)
        _ = runtime.linux_syscall(SYS_CLOSE, cast[u64](pipes[4]))
        status : i32 = 0
        if !failed(reported) && reported == 8 {
            _ = runtime.linux_syscall(SYS_WAIT4, child, cast[u64](&status), 0, 0)
            _ = runtime.linux_syscall(SYS_CLOSE, cast[u64](pipes[0]))
            _ = runtime.linux_syscall(SYS_CLOSE, cast[u64](pipes[2]))
            return empty, if reason == ENOENT { ProcessError.NotFound } else { ProcessError.FailedToStart }
        }

        output : u8[..]
        error_output : u8[..]
        push_context with_allocator (allocator = allocator) {
            watched : PollDescriptor[2]
            watched[0] = PollDescriptor.{descriptor = pipes[0], events = POLLIN, returned = 0}
            watched[1] = PollDescriptor.{descriptor = pipes[2], events = POLLIN, returned = 0}
            loop {
                if watched[0].descriptor < 0 && watched[1].descriptor < 0 {
                    break
                }
                ready :: linux_poll(cast[u64](&watched[0]), 2)
                if failed(ready) {
                    if 0 - ready == EINTR {
                        continue
                    }
                    break
                }
                if watched[0].descriptor >= 0 && watched[0].returned != 0 && read_some(cast[u64](watched[0].descriptor), &output) {
                    watched[0].descriptor = -1
                }
                if watched[1].descriptor >= 0 && watched[1].returned != 0 && read_some(cast[u64](watched[1].descriptor), &error_output) {
                    watched[1].descriptor = -1
                }
            }
        }
        _ = runtime.linux_syscall(SYS_CLOSE, cast[u64](pipes[0]))
        _ = runtime.linux_syscall(SYS_CLOSE, cast[u64](pipes[2]))
        _ = runtime.linux_syscall(SYS_WAIT4, child, cast[u64](&status), 0, 0)
        // Exited: the code in the second byte; killed by a signal: 128 and the signal, as shells give
        code :: if status & 0x7f == 0 { (status >> 8) & 0xff } else { 128 + (status & 0x7f) }
        result := ProcessResult.{exit_code = cast[int](code), output = as_text(output), error_output = as_text(error_output)}
        return result, null
    }
}

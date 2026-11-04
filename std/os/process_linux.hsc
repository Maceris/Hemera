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
    /** The system call number of poll on x86-64. */
    SYS_POLL : u64 : 7
    /** The system call number of dup2 on x86-64. */
    SYS_DUP2 : u64 : 33
    /** The system call number of fork on x86-64. */
    SYS_FORK : u64 : 57
    /** The system call number of execve on x86-64. */
    SYS_EXECVE : u64 : 59
    /** The system call number of wait4 on x86-64. */
    SYS_WAIT4 : u64 : 61
    /** The system call number of exit_group on x86-64. */
    SYS_EXIT_GROUP : u64 : 231
    /** The system call number of pipe2 on x86-64. */
    SYS_PIPE2 : u64 : 293

    /**
     * Fork the process, with fork: the child is a copy of it with only the calling thread.
     *
     * @return The child's process ID in the parent; 0 in the child; or -errno, which failed says is an error, when
     *     no child was made.
     */
    linux_fork :: fn() -> u64 {
        return runtime.linux_syscall(SYS_FORK)
    }

    /**
     * Make a descriptor a copy of another, with dup2, closing what it was first.
     *
     * @param from The descriptor copied, which stays open.
     * @param to The descriptor number it's copied to; whatever was open there is closed. The copy is inherited
     *     through execve.
     * @return The descriptor to, once it's done, or -errno, which failed says is an error.
     */
    linux_dup2 :: fn(from: u64, to: u64) -> u64 {
        return runtime.linux_syscall(SYS_DUP2, from, to)
    }

    /**
     * Wait, with poll, until one of some descriptors is ready, however long that takes.
     *
     * @param descriptors The address of count PollDescriptors, whose returned fields are filled in.
     * @param count How many there are.
     * @return How many are ready, at least 1, or -errno, which failed says is an error: EINTR when a signal came
     *     first, and waiting again is worth it.
     */
    linux_poll :: fn(descriptors: u64, count: u64) -> u64 {
        return runtime.linux_syscall(SYS_POLL, descriptors, count, 0xffff_ffff_ffff_ffff)
    }
}
#else_if OS == .Linux && TARGET_ARCH == .arm64 {
    // The generic table has no fork, dup2 or poll: clone, dup3 and ppoll do what they did
    /** The system call number of dup3 in the generic table, which AArch64 uses; it stands in for dup2. */
    SYS_DUP3 : u64 : 24
    /** The system call number of pipe2 in the generic table. */
    SYS_PIPE2 : u64 : 59
    /** The system call number of ppoll in the generic table; it stands in for poll. */
    SYS_PPOLL : u64 : 73
    /** The system call number of exit_group in the generic table. */
    SYS_EXIT_GROUP : u64 : 94
    /** The system call number of clone in the generic table; it stands in for fork. */
    SYS_CLONE : u64 : 220
    /** The system call number of execve in the generic table. */
    SYS_EXECVE : u64 : 221
    /** The system call number of wait4 in the generic table. */
    SYS_WAIT4 : u64 : 260
    /** The signal a child sends its parent when it ends, which clone is told to send, as fork does. */
    SIGCHLD : u64 : 17

    /**
     * Fork the process, with clone given only SIGCHLD, as fork does: the child is a copy of it with only the calling
     * thread.
     *
     * @return The child's process ID in the parent; 0 in the child; or -errno, which failed says is an error, when
     *     no child was made.
     */
    linux_fork :: fn() -> u64 {
        return runtime.linux_syscall(SYS_CLONE, SIGCHLD, 0, 0, 0, 0)
    }

    /**
     * Make a descriptor a copy of another, with dup3 given no flags, closing what it was first.
     *
     * @param from The descriptor copied, which stays open.
     * @param to The descriptor number it's copied to, which has to differ from from: dup3 fails with EINVAL where
     *     dup2 would do nothing. Whatever was open there is closed. The copy is inherited through execve.
     * @return The descriptor to, once it's done, or -errno, which failed says is an error.
     */
    linux_dup2 :: fn(from: u64, to: u64) -> u64 {
        return runtime.linux_syscall(SYS_DUP3, from, to, 0)
    }

    /**
     * Wait, with ppoll given no timeout and no signal mask, until one of some descriptors is ready, however long that
     * takes.
     *
     * @param descriptors The address of count PollDescriptors, whose returned fields are filled in.
     * @param count How many there are.
     * @return How many are ready, at least 1, or -errno, which failed says is an error: EINTR when a signal came
     *     first, and waiting again is worth it.
     */
    linux_poll :: fn(descriptors: u64, count: u64) -> u64 {
        return runtime.linux_syscall(SYS_PPOLL, descriptors, count, 0, 0, 8)
    }
}

#if OS == .Linux && (TARGET_ARCH == .x86_64 || TARGET_ARCH == .arm64) {

    /** The poll event for a descriptor with something to read, or at its end. */
    POLLIN : i16 : 1
    /** The errno for nothing being at a path. */
    ENOENT : u64 : 2
    /** The errno for a system call a signal interrupted, which is worth making again. */
    EINTR : u64 : 4

    /** The C struct pollfd: a descriptor poll watches, and what it found. */
    PollDescriptor :: struct {
        /** The descriptor, or a negative number for poll to skip this one. */
        descriptor : i32,
        /** The events waited for, like POLLIN. */
        events : i16,
        /** The events that happened, filled in by poll: nonzero when the descriptor is ready, ended or broken. */
        returned : i16,
    }

    /**
     * Join up to three strings, with a terminator after them, as execve takes its strings.
     *
     * @param made Where the copy is kept, so every copy is freed together; the caller frees each, then made.
     * @param first What the copy starts with, its bytes copied as they are; it can be empty, and a 0 byte in it ends
     *     the string execve sees early.
     * @param second The second part, or "" for none.
     * @param third The third part, or "" for none.
     * @return The copy's first byte, in memory from the context's allocator that made holds, good until that's
     *     freed. Null if it couldn't be allocated, and then nothing is added to made.
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

    /**
     * Read what's in a pipe, with one read of up to 4096 bytes, into a buffer.
     *
     * @param descriptor The pipe's reading end, which stays open.
     * @param buffer Where the bytes are added, grown with the context's allocator.
     * @return True when the pipe is done: at its end, as when every writer has closed it, or broken, for any error
     *     but EINTR. False when more may come.
     */
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

    /**
     * Run a program, wait for it to end, and give back its exit code and what it wrote, as run_process does.
     *
     * The child shares the caller's standard input and environment. Its exit code is what wait4 gives: the code it
     * exited with, 0 to 255, or 128 plus the signal that killed it.
     *
     * @param program The program: a path if it holds a '/', tried as it is; otherwise a name, tried in each folder of
     *     the PATH in turn (an empty entry being the current folder), or in /usr/bin and then the current folder when
     *     the PATH isn't set. The first that execve can start is run.
     * @param arguments The arguments after the program's name, passed as they are.
     * @param working_directory The folder the child changes to before it starts the program, or null for the
     *     caller's current directory. One the child can't change to is ignored.
     * @param allocator Where the output and the error output are allocated from.
     * @return result The exit code and the output, owned by the caller and allocated from allocator; empty, owning
     *     nothing, on failure.
     * @return error NotFound when no path tried has anything at it; FailedToStart when the pipes or the child couldn't
     *     be made, or what was found couldn't be started, like a file that isn't executable; or null once the
     *     program ran, whatever its exit code.
     */
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

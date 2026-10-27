package runtime

import intrinsics from "base"

/*
 * What the runtime needs from Linux, through system calls rather than a C library: memory, threads,
 * and waiting on an address. On x86-64 and AArch64, which number the calls differently.
 */
#if OS == .Linux && TARGET_ARCH == .x86_64 {
    import x86_64 from "base/intrinsics"

    SYS_WRITE : u64 : 1
    SYS_MMAP : u64 : 9
    SYS_MUNMAP : u64 : 11
    SYS_EXIT : u64 : 60
    SYS_FUTEX : u64 : 202
    SYS_CLOCK_GETTIME : u64 : 228
    SYS_EXIT_GROUP : u64 : 231
    SYS_GETRANDOM : u64 : 318

    linux_syscall #no_context :: fn(number: u64, a: u64 = 0, b: u64 = 0, c: u64 = 0, d: u64 = 0, e: u64 = 0, f: u64 = 0) -> u64 {
        return x86_64.syscall(number, a, b, c, d, e, f)
    }

    linux_clone_thread #no_context :: fn(flags: u64, stack: rawptr, parent_tid: ptr[mut u32], child_tid: ptr[mut u32], entry: rawptr,
        argument: rawptr) -> i64 {
        return x86_64.clone_thread(flags, stack, parent_tid, child_tid, entry, argument)
    }
}
#else_if OS == .Linux && TARGET_ARCH == .arm64 {
    import aarch64 from "base/intrinsics"

    // The generic table's numbers, which AArch64 uses
    SYS_FUTEX : u64 : 98
    SYS_WRITE : u64 : 64
    SYS_EXIT : u64 : 93
    SYS_EXIT_GROUP : u64 : 94
    SYS_CLOCK_GETTIME : u64 : 113
    SYS_MUNMAP : u64 : 215
    SYS_MMAP : u64 : 222
    SYS_GETRANDOM : u64 : 278

    linux_syscall #no_context :: fn(number: u64, a: u64 = 0, b: u64 = 0, c: u64 = 0, d: u64 = 0, e: u64 = 0, f: u64 = 0) -> u64 {
        return aarch64.syscall(number, a, b, c, d, e, f)
    }

    linux_clone_thread #no_context :: fn(flags: u64, stack: rawptr, parent_tid: ptr[mut u32], child_tid: ptr[mut u32], entry: rawptr,
        argument: rawptr) -> i64 {
        return aarch64.clone_thread(flags, stack, parent_tid, child_tid, entry, argument)
    }
}

#if OS == .Linux && (TARGET_ARCH == .x86_64 || TARGET_ARCH == .arm64) {

    PROT_READ_WRITE : u64 : 3
    MAP_PRIVATE_ANONYMOUS : u64 : 0x22
    FUTEX_WAIT : u64 : 0
    FUTEX_WAKE : u64 : 1
    // Only this process's threads wait on it, which lets the kernel skip looking for other processes
    FUTEX_PRIVATE : u64 : 128
    PAGE_SIZE : usize : 4096

    // A system call's result is an error when it's -4095 to -1.
    syscall_failed #no_context :: fn(result: u64) -> bool {
        return result > 0xffff_ffff_ffff_f000
    }

    // Pages of memory, zeroed, or null.
    map_pages #no_context :: fn(size: usize) -> rawptr {
        result :: linux_syscall(SYS_MMAP, 0, cast[u64](size), PROT_READ_WRITE, MAP_PRIVATE_ANONYMOUS, 0xffff_ffff_ffff_ffff, 0)
        if syscall_failed(result) {
            return null
        }
        return cast[rawptr](result)
    }

    unmap_pages #no_context :: fn(address: rawptr, size: usize) {
        linux_syscall(SYS_MUNMAP, cast[u64](address), cast[u64](size))
    }

    /*
     * Bytes to standard output (1) or error (2), a write at a time until they're all written, or
     * one fails. Written directly, so text from C's stdio, which buffers, can come out after it.
     */
    os_write #no_context :: fn(stream: OutputStream, bytes: rawptr, count: usize) {
        descriptor : u64 = 2
        if stream == OutputStream.OUTPUT {
            descriptor = 1
        }
        done : usize = 0
        loop {
            if done >= count {
                break
            }
            result :: linux_syscall(SYS_WRITE, descriptor, cast[u64](bytes + done), cast[u64](count - done))
            // EINTR: again
            if result == ~cast[u64](3) {
                continue
            }
            if syscall_failed(result) || result == 0 {
                return void
            }
            done += cast[usize](result)
        }
    }

    // argv, from the entry, as strings viewing the kernel's copies, which last as long as the process.
    os_command_line_arguments :: fn(allocator: Allocator) -> string[] {
        empty : string[]
        state :: intrinsics.process_state()
        if state.argument_count == 0 || state.argument_pointers == null {
            return empty
        }
        arguments, error :: new_array(string, state.argument_count, allocator)
        if error != null {
            return empty
        }
        for &argument, index in arguments {
            argument^ = cstring_view(cast[ptr[rawptr]](state.argument_pointers + index * 8)^, ARGUMENT_TEXT_LIMIT) or_else ""
        }
        return arguments
    }

    // Ends the process at once, with code, running nothing else: for a failed assertion.
    os_exit_process #no_context :: fn(code: u32) #never_returns {
        linux_syscall(SYS_EXIT_GROUP, cast[u64](code))
        intrinsics.trap()
    }

    // The system's clocks, from clock_gettime: CLOCK_MONOTONIC, and CLOCK_REALTIME for the wall clock.
    SYSTEM_CLOCK :: Clock.{
        data = null,
        monotonic = system_monotonic,
        wall = system_wall,
    }

    CLOCK_REALTIME : u64 : 0
    CLOCK_MONOTONIC : u64 : 1

    // struct timespec
    TimeSpec :: struct {
        seconds : i64,
        nanoseconds : i64,
    }

    system_monotonic :: fn(data: mut rawptr) -> MonotonicTime {
        now : TimeSpec
        if syscall_failed(linux_syscall(SYS_CLOCK_GETTIME, CLOCK_MONOTONIC, cast[u64](&now))) {
            return 0
        }
        return cast[MonotonicTime](now.seconds * NANOSECONDS_PER_SECOND + now.nanoseconds)
    }

    system_wall :: fn(data: mut rawptr) -> Result[Instant, ClockError] {
        now : TimeSpec
        if syscall_failed(linux_syscall(SYS_CLOCK_GETTIME, CLOCK_REALTIME, cast[u64](&now))) {
            return .Error(.Unavailable)
        }
        return .Ok(Instant.{now.seconds, cast[u32](now.nanoseconds)})
    }

    // The system's random numbers, from getrandom, which waits until the kernel's generator is ready.
    SYSTEM_RANDOM :: Random.{
        data = null,
        fill = system_random_fill,
    }

    // Fills bytes, a getrandom at a time; stops the program if it can't, since fill can't report it.
    system_random_fill :: fn(data: mut rawptr, bytes: mut u8[]) {
        done : usize = 0
        loop {
            if done >= bytes.count {
                break
            }
            result :: linux_syscall(SYS_GETRANDOM, cast[u64](cast[rawptr](bytes.data) + done), cast[u64](bytes.count - done), 0)
            // EINTR: again
            if result == ~cast[u64](3) {
                continue
            }
            if syscall_failed(result) || result == 0 {
                intrinsics.trap()
            }
            done += cast[usize](result)
        }
    }

    /*
     * What a hosted program's main starts with: memory from the kernel, the standard logger and
     * assertion handler, and the system's clock and random numbers.
     */
    HOSTED_CONTEXT :: Context.{
        allocator = PAGES_ALLOCATOR,
        logger = &STANDARD_LOGGER,
        log_level = .INFO,
        clock = &SYSTEM_CLOCK,
        random = &SYSTEM_RANDOM,
        assertion_handler = printing_assertion_handler,
        user_data = null,
        extensions = null,
    }

    // Each thread's own stack, which Linux doesn't make for a thread clone starts.
    THREAD_STACK_SIZE : usize : 1048576
    // Room left below stack_limit on a thread's own stack, for code that runs where Hemera's doesn't.
    NATIVE_STACK_RESERVE :: 65536

    ThreadSpecificOS :: struct {
        // The thread's ID, which the kernel clears once it has exited
        tid : u32,
        // Its own stack, THREAD_STACK_SIZE bytes
        stack_memory : rawptr,
        // Linking C: the thread's pthread_t
        pthread : u64,
    }

    /*
     * Linking C (intrinsics.uses_c_library), threads start through pthreads, on the stack the runtime
     * maps, so C sets up its own state for them. These are never called otherwise.
     */
    LIBC :: #library("c")
    pthread_attr_init #foreign(LIBC) : fn(attributes: rawptr) -> i32 : ---
    pthread_attr_setstack #foreign(LIBC) : fn(attributes: rawptr, stack: rawptr, size: usize) -> i32 : ---
    pthread_attr_destroy #foreign(LIBC) : fn(attributes: rawptr) -> i32 : ---
    pthread_create #foreign(LIBC) : fn(thread: ptr[mut u64], attributes: rawptr, start: rawptr, argument: rawptr) -> i32 : ---
    pthread_join #foreign(LIBC) : fn(thread: u64, result: rawptr) -> i32 : ---

    // pthread_attr_t, 56 bytes on x86-64, with room to spare.
    PthreadAttributes :: struct #align(16) {
        bytes : u8[64],
    }

    // Where callbacks from foreign code find a thread's carrier block, linking C (callback_carrier).
    register_carrier #no_context :: fn(carrier: ptr[mut CarrierBlock]) {
        intrinsics.set_thread_carrier(carrier)
    }

    /*
     * The carrier block of a thread a callback from foreign code found none on: a thread Hemera didn't
     * start, which gets one of its own, from the runtime's heap, kept for the rest of its life. Its
     * stack's bounds aren't known, so it has no limit. Callback shims call this with a temporary one
     * loaded, counting a foreign call.
     */
    callback_carrier #no_context :: fn() -> ptr[mut CarrierBlock] {
        memory :: heap_allocate(size_of(CarrierBlock), align_of(CarrierBlock))
        if memory == null {
            intrinsics.trap()
        }
        carrier :: cast[ptr[mut CarrierBlock]](memory)
        carrier.segment_allocator = PAGES_ALLOCATOR
        register_carrier(carrier)
        return carrier
    }

    /*
     * Where a thread starts, on its new stack: its carrier block first, since every prologue reads it,
     * with its stack's limit, then its function with the context it was created with. Started by
     * clone, it ends with the exit system call, which ends only this thread; started by
     * pthread_create, it returns, with the carrier register as pthreads left it.
     */
    linux_thread_entry #calling_convention(.c) #no_context :: fn(parameter: rawptr) -> rawptr {
        // pthreads' value of the carrier register, to give back
        callers :: intrinsics.carrier()
        thread :: cast[ptr[mut Thread]](parameter)
        intrinsics.set_carrier(&thread.carrier)
        register_carrier(&thread.carrier)
        thread.carrier.native_stack_limit = cast[rawptr](cast[usize](thread.stack_memory) + NATIVE_STACK_RESERVE)
        thread.carrier.stack_limit = thread.carrier.native_stack_limit
        thread.carrier.segment_allocator = thread.starting_context.allocator
        data : any
        match thread.data {
            case Some(given) => data = given
            case None => {}
        }
        push_context thread_context from thread.starting_context {
            thread.function(data)
        }
        if intrinsics.uses_c_library() {
            intrinsics.set_carrier(callers)
            return null
        }
        linux_syscall(SYS_EXIT, 0)
        intrinsics.trap()
    }

    // CLONE_VM, FS, FILES, SIGHAND, THREAD, SYSVSEM, PARENT_SETTID and CHILD_CLEARTID: a thread of this process.
    THREAD_CLONE_FLAGS : u64 : 0x350f00

    os_thread_start :: fn(thread #escaping : ptr[mut Thread]) -> bool {
        stack :: map_pages(THREAD_STACK_SIZE)
        if stack == null {
            return false
        }
        thread.stack_memory = stack
        if intrinsics.uses_c_library() {
            attributes : PthreadAttributes
            pthread_attr_init(cast[rawptr](&attributes))
            pthread_attr_setstack(cast[rawptr](&attributes), stack, THREAD_STACK_SIZE)
            created :: pthread_create(&thread.pthread, cast[rawptr](&attributes), cast[rawptr](linux_thread_entry), cast[rawptr](thread))
            pthread_attr_destroy(cast[rawptr](&attributes))
            if created != 0 {
                unmap_pages(stack, THREAD_STACK_SIZE)
                return false
            }
            return true
        }
        top :: cast[rawptr](cast[usize](stack) + THREAD_STACK_SIZE)
        result :: linux_clone_thread(THREAD_CLONE_FLAGS, top, &thread.tid, &thread.tid, cast[rawptr](linux_thread_entry),
            cast[rawptr](thread))
        if result <= 0 {
            unmap_pages(stack, THREAD_STACK_SIZE)
            return false
        }
        return true
    }

    /*
     * Until the kernel has cleared the thread's ID, which it does once the thread has exited, waking
     * this. Not a private futex: the kernel's wake for it isn't.
     */
    os_thread_join :: fn(thread: ptr[mut Thread]) {
        if intrinsics.uses_c_library() {
            pthread_join(thread.pthread, null)
            unmap_pages(thread.stack_memory, THREAD_STACK_SIZE)
            return void
        }
        loop {
            tid :: intrinsics.atomic_load_u32_acquire(&thread.tid)
            if tid == 0 {
                break
            }
            linux_syscall(SYS_FUTEX, cast[u64](cast[rawptr](&thread.tid)), FUTEX_WAIT, cast[u64](tid))
        }
        unmap_pages(thread.stack_memory, THREAD_STACK_SIZE)
    }

    wait_on_value :: fn(address: ptr[u32], expected: u32) {
        linux_syscall(SYS_FUTEX, cast[u64](cast[rawptr](address)), FUTEX_WAIT | FUTEX_PRIVATE, cast[u64](expected))
    }

    wake_one :: fn(address: ptr[u32]) {
        linux_syscall(SYS_FUTEX, cast[u64](cast[rawptr](address)), FUTEX_WAKE | FUTEX_PRIVATE, 1)
    }

    wake_all :: fn(address: ptr[u32]) {
        linux_syscall(SYS_FUTEX, cast[u64](cast[rawptr](address)), FUTEX_WAKE | FUTEX_PRIVATE, 0x7fff_ffff)
    }
}

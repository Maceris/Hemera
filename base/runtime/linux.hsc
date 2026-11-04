package runtime

import intrinsics from "base"

/*
 * What the runtime needs from Linux, through system calls rather than a C library: memory, threads,
 * and waiting on an address. On x86-64 and AArch64, which number the calls differently.
 */
#if OS == .Linux && TARGET_ARCH == .x86_64 {
    import x86_64 from "base/intrinsics"

    /** x86-64's number for write(2). */
    SYS_WRITE : u64 : 1
    /** x86-64's number for mmap(2). */
    SYS_MMAP : u64 : 9
    /** x86-64's number for munmap(2). */
    SYS_MUNMAP : u64 : 11
    /** x86-64's number for exit(2), which ends only the calling thread. */
    SYS_EXIT : u64 : 60
    /** x86-64's number for futex(2). */
    SYS_FUTEX : u64 : 202
    /** x86-64's number for clock_gettime(2). */
    SYS_CLOCK_GETTIME : u64 : 228
    /** x86-64's number for exit_group(2), which ends the whole process. */
    SYS_EXIT_GROUP : u64 : 231
    /** x86-64's number for getrandom(2). */
    SYS_GETRANDOM : u64 : 318

    /**
     * Make a Linux system call, with the arguments the call takes in order and 0 for those it doesn't.
     *
     * @param number The call's number on this architecture, one of the SYS_ constants.
     * @param a The call's first argument, as a word: a pointer or descriptor is cast to u64.
     * @param b The call's second argument, as a word the way a is; 0 when the call takes fewer.
     * @param c The call's third argument, the same way.
     * @param d The call's fourth argument, the same way.
     * @param e The call's fifth argument, the same way.
     * @param f The call's sixth argument, the same way.
     * @return The kernel's result as it gives it: from -4095 to -1, as a u64, is the negated errno of a failure
     *     (syscall_failed tells), and anything else is the call's own result.
     */
    linux_syscall #no_context :: fn(number: u64, a: u64 = 0, b: u64 = 0, c: u64 = 0, d: u64 = 0, e: u64 = 0, f: u64 = 0) -> u64 {
        return x86_64.syscall(number, a, b, c, d, e, f)
    }

    /**
     * Start a thread with clone(2), running entry(argument) on stack.
     *
     * The new thread never returns into the caller's code: entry has to end it with SYS_EXIT.
     *
     * @param flags clone's flags, like THREAD_CLONE_FLAGS.
     * @param stack The top (highest address) of the new thread's stack, which the caller owns and has to keep mapped
     *     until the thread has exited.
     * @param parent_tid Where the kernel stores the new thread's ID in the parent's memory, with CLONE_PARENT_SETTID.
     * @param child_tid Where the kernel clears the thread's ID, and wakes a futex wait on it, once the thread has
     *     exited, with CLONE_CHILD_CLEARTID; it has to stay valid until then.
     * @param entry Where the new thread starts: a function of the C calling convention taking one pointer.
     * @param argument What entry is given.
     * @return The new thread's ID, above 0, in the caller; or a negated errno if the thread wasn't made.
     */
    linux_clone_thread #no_context :: fn(flags: u64, stack: rawptr, parent_tid: ptr[mut u32], child_tid: ptr[mut u32], entry: rawptr,
        argument: rawptr) -> i64 {
        return x86_64.clone_thread(flags, stack, parent_tid, child_tid, entry, argument)
    }
}
#else_if OS == .Linux && TARGET_ARCH == .arm64 {
    import aarch64 from "base/intrinsics"

    // The generic table's numbers, which AArch64 uses
    /** AArch64's number for futex(2). */
    SYS_FUTEX : u64 : 98
    /** AArch64's number for write(2). */
    SYS_WRITE : u64 : 64
    /** AArch64's number for exit(2), which ends only the calling thread. */
    SYS_EXIT : u64 : 93
    /** AArch64's number for exit_group(2), which ends the whole process. */
    SYS_EXIT_GROUP : u64 : 94
    /** AArch64's number for clock_gettime(2). */
    SYS_CLOCK_GETTIME : u64 : 113
    /** AArch64's number for munmap(2). */
    SYS_MUNMAP : u64 : 215
    /** AArch64's number for mmap(2). */
    SYS_MMAP : u64 : 222
    /** AArch64's number for getrandom(2). */
    SYS_GETRANDOM : u64 : 278

    /**
     * Make a Linux system call, with the arguments the call takes in order and 0 for those it doesn't.
     *
     * @param number The call's number on this architecture, one of the SYS_ constants.
     * @param a The call's first argument, as a word: a pointer or descriptor is cast to u64.
     * @param b The call's second argument, as a word the way a is; 0 when the call takes fewer.
     * @param c The call's third argument, the same way.
     * @param d The call's fourth argument, the same way.
     * @param e The call's fifth argument, the same way.
     * @param f The call's sixth argument, the same way.
     * @return The kernel's result as it gives it: from -4095 to -1, as a u64, is the negated errno of a failure
     *     (syscall_failed tells), and anything else is the call's own result.
     */
    linux_syscall #no_context :: fn(number: u64, a: u64 = 0, b: u64 = 0, c: u64 = 0, d: u64 = 0, e: u64 = 0, f: u64 = 0) -> u64 {
        return aarch64.syscall(number, a, b, c, d, e, f)
    }

    /**
     * Start a thread with clone(2), running entry(argument) on stack.
     *
     * The new thread never returns into the caller's code: entry has to end it with SYS_EXIT.
     *
     * @param flags clone's flags, like THREAD_CLONE_FLAGS.
     * @param stack The top (highest address) of the new thread's stack, which the caller owns and has to keep mapped
     *     until the thread has exited.
     * @param parent_tid Where the kernel stores the new thread's ID in the parent's memory, with CLONE_PARENT_SETTID.
     * @param child_tid Where the kernel clears the thread's ID, and wakes a futex wait on it, once the thread has
     *     exited, with CLONE_CHILD_CLEARTID; it has to stay valid until then.
     * @param entry Where the new thread starts: a function of the C calling convention taking one pointer.
     * @param argument What entry is given.
     * @return The new thread's ID, above 0, in the caller; or a negated errno if the thread wasn't made.
     */
    linux_clone_thread #no_context :: fn(flags: u64, stack: rawptr, parent_tid: ptr[mut u32], child_tid: ptr[mut u32], entry: rawptr,
        argument: rawptr) -> i64 {
        return aarch64.clone_thread(flags, stack, parent_tid, child_tid, entry, argument)
    }
}

#if OS == .Linux && (TARGET_ARCH == .x86_64 || TARGET_ARCH == .arm64) {

    /** mmap's protection for memory that can be read and written, not run: PROT_READ | PROT_WRITE. */
    PROT_READ_WRITE : u64 : 3
    /** mmap's flags for memory of the process's own, backed by no file: MAP_PRIVATE | MAP_ANONYMOUS. */
    MAP_PRIVATE_ANONYMOUS : u64 : 0x22
    /** futex's operation that sleeps while a value is the one expected. */
    FUTEX_WAIT : u64 : 0
    /** futex's operation that wakes up to a number of those waiting on a value. */
    FUTEX_WAKE : u64 : 1
    /**
     * futex's flag for a value only this process's threads wait on, which lets the kernel skip looking for other
     * processes.
     */
    FUTEX_PRIVATE : u64 : 128
    /** The size of a page in bytes, which mmap rounds sizes up to. */
    PAGE_SIZE : usize : 4096

    /**
     * Tell whether a system call's result is an error.
     *
     * @param result What linux_syscall returned.
     * @return True when it's from -4095 to -1, as a u64, the negated errno of a failure; false for any other value,
     *     which is the call's result.
     */
    syscall_failed #no_context :: fn(result: u64) -> bool {
        return result > 0xffff_ffff_ffff_f000
    }

    /**
     * Map pages of memory of the process's own, zeroed, readable and writable.
     *
     * @param size How many bytes, rounded up by the kernel to whole pages; above 0.
     * @return The memory's first byte, page-aligned, which the caller owns until it gives it to unmap_pages; or null if
     *     the kernel couldn't map it.
     */
    map_pages #no_context :: fn(size: usize) -> rawptr {
        result :: linux_syscall(SYS_MMAP, 0, cast[u64](size), PROT_READ_WRITE, MAP_PRIVATE_ANONYMOUS, 0xffff_ffff_ffff_ffff, 0)
        if syscall_failed(result) {
            return null
        }
        return cast[rawptr](result)
    }

    /**
     * Unmap pages map_pages gave, after which they mustn't be touched. A failure is ignored.
     *
     * @param address The first byte, as map_pages gave it.
     * @param size The size map_pages was asked for, or a part of it from address: what's unmapped is rounded up to
     *     whole pages.
     */
    unmap_pages #no_context :: fn(address: rawptr, size: usize) {
        linux_syscall(SYS_MUNMAP, cast[u64](address), cast[u64](size))
    }

    /**
     * Write bytes to standard output (descriptor 1) or standard error (2).
     *
     * A write at a time until they're all written, a write interrupted by a signal (EINTR) being tried again; a write
     * that fails otherwise, or writes nothing, ends it there, silently, since there's nowhere left to report it.
     * Written directly, so text from C's stdio, which buffers, can come out after it.
     *
     * @param stream OUTPUT for standard output; anything else for standard error.
     * @param bytes The first byte, which only has to stay valid for the call.
     * @param count How many bytes; 0 writes nothing.
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

    /**
     * Give the program's command line, argv from the entry, the program's name first.
     *
     * @param allocator Where the array of strings comes from; the strings themselves aren't copied.
     * @return The arguments, as strings viewing the kernel's copies, which last as long as the process; the array is
     *     the caller's, from allocator. An argument with no terminating 0 in its first ARGUMENT_TEXT_LIMIT bytes is
     *     empty. Empty if there are none, or if the array couldn't be allocated.
     */
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

    /**
     * End the process at once, every thread of it, running nothing else: for a failed assertion.
     *
     * @param code The exit status; the parent sees only its low 8 bits.
     */
    os_exit_process #no_context :: fn(code: u32) #never_returns {
        linux_syscall(SYS_EXIT_GROUP, cast[u64](code))
        intrinsics.trap()
    }

    /** The system's clocks, from clock_gettime: CLOCK_MONOTONIC, and CLOCK_REALTIME for the wall clock. */
    SYSTEM_CLOCK :: Clock.{
        data = null,
        monotonic = system_monotonic,
        wall = system_wall,
    }

    /** clock_gettime's wall clock, which can jump when the system's time is set. */
    CLOCK_REALTIME : u64 : 0
    /** clock_gettime's clock that only goes forward, from an unspecified start, like the system's boot. */
    CLOCK_MONOTONIC : u64 : 1

    /** A time as clock_gettime gives it, C's struct timespec. */
    TimeSpec :: struct {
        /** Whole seconds since the clock's start. */
        seconds : i64,
        /** Nanoseconds past seconds, from 0 to 999,999,999. */
        nanoseconds : i64,
    }

    /**
     * Read the monotonic clock, CLOCK_MONOTONIC.
     *
     * @param data Unused: the clock has no state.
     * @return Nanoseconds since an unspecified start, which never go back; 0 if the clock couldn't be read, since a
     *     monotonic time can't report an error.
     */
    system_monotonic :: fn(data: mut rawptr) -> MonotonicTime {
        now : TimeSpec
        if syscall_failed(linux_syscall(SYS_CLOCK_GETTIME, CLOCK_MONOTONIC, cast[u64](&now))) {
            return 0
        }
        return cast[MonotonicTime](now.seconds * NANOSECONDS_PER_SECOND + now.nanoseconds)
    }

    /**
     * Read the wall clock, CLOCK_REALTIME.
     *
     * @param data Unused: the clock has no state.
     * @return The time since 1970-01-01T00:00:00Z, as the system has it set.
     * @error Unavailable The clock couldn't be read.
     */
    system_wall :: fn(data: mut rawptr) -> Result[Instant, ClockError] {
        now : TimeSpec
        if syscall_failed(linux_syscall(SYS_CLOCK_GETTIME, CLOCK_REALTIME, cast[u64](&now))) {
            return .Error(.Unavailable)
        }
        return .Ok(Instant.{now.seconds, cast[u32](now.nanoseconds)})
    }

    /** The system's random numbers, from getrandom, which waits until the kernel's generator is ready. */
    SYSTEM_RANDOM :: Random.{
        data = null,
        fill = system_random_fill,
    }

    /**
     * Fill bytes with the system's random numbers, a getrandom at a time, which are suitable for keys.
     *
     * A call interrupted by a signal (EINTR) is tried again. If getrandom fails otherwise, or gives nothing, the
     * program stops with a trap, since fill can't report it and bytes that aren't random mustn't be used as if they
     * were.
     *
     * @param data Unused: the generator has no state of the program's.
     * @param bytes What's filled, all of it; empty fills nothing.
     */
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

    /**
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

    /**
     * Each thread's own stack, in bytes, which Linux doesn't make for a thread clone starts. Every thread gets this
     * much, whatever its Thread's stack asks for.
     */
    THREAD_STACK_SIZE : usize : 1048576
    /** Room in bytes left below stack_limit on a thread's own stack, for code that runs where Hemera's doesn't. */
    NATIVE_STACK_RESERVE :: 65536

    /** What a Thread has on Linux: set by os_thread_start, and given back by os_thread_join. */
    ThreadSpecificOS :: struct {
        /**
         * The thread's ID, which the kernel stores when it's cloned and clears once it has exited, waking a futex wait
         * on it; unused linking C.
         */
        tid : u32,
        /** The lowest address of its own stack, THREAD_STACK_SIZE bytes from map_pages. */
        stack_memory : rawptr,
        /** Linking C, the thread's pthread_t, which pthread_join takes; unused otherwise. */
        pthread : u64,
    }

    /*
     * Linking C (intrinsics.uses_c_library), threads start through pthreads, on the stack the runtime
     * maps, so C sets up its own state for them. These are never called otherwise.
     */
    /** The C library, for pthreads, when the program links it. */
    LIBC :: #library("c")
    /**
     * Set up a pthread_attr_t with the defaults.
     *
     * @param attributes A PthreadAttributes to set up, which pthread_attr_destroy takes when it's done with.
     * @return 0, or an errno.
     */
    pthread_attr_init #foreign(LIBC) : fn(attributes: rawptr) -> i32 : ---
    /**
     * Set the stack a pthread_attr_t's thread runs on, which the caller owns.
     *
     * @param attributes A PthreadAttributes pthread_attr_init set up.
     * @param stack The stack's lowest address, which has to stay mapped until the thread is joined.
     * @param size The stack's size in bytes.
     * @return 0, or an errno.
     */
    pthread_attr_setstack #foreign(LIBC) : fn(attributes: rawptr, stack: rawptr, size: usize) -> i32 : ---
    /**
     * Give back what pthread_attr_init set up; the threads made with it aren't affected.
     *
     * @param attributes A PthreadAttributes pthread_attr_init set up.
     * @return 0, or an errno.
     */
    pthread_attr_destroy #foreign(LIBC) : fn(attributes: rawptr) -> i32 : ---
    /**
     * Start a thread through the C library, calling start(argument) on it.
     *
     * @param thread Where its pthread_t is stored.
     * @param attributes A PthreadAttributes, or null for the defaults.
     * @param start Where the thread starts: a function of the C calling convention taking a pointer and returning one.
     * @param argument What start is given.
     * @return 0 if it started, or an errno.
     */
    pthread_create #foreign(LIBC) : fn(thread: ptr[mut u64], attributes: rawptr, start: rawptr, argument: rawptr) -> i32 : ---
    /**
     * Wait for a thread pthread_create started to end, then give back its pthreads state.
     *
     * @param thread Its pthread_t, joined only once.
     * @param result Where what its start returned is stored, or null not to.
     * @return 0, or an errno.
     */
    pthread_join #foreign(LIBC) : fn(thread: u64, result: rawptr) -> i32 : ---

    /** Room for a pthread_attr_t, which is 56 bytes on x86-64, with room to spare. */
    PthreadAttributes :: struct #align(16) {
        /** The pthread_attr_t's bytes, only the C library reads. */
        bytes : u8[64],
    }

    /**
     * Store a thread's carrier block in its thread-local storage, where callbacks from foreign code find it, linking C
     * (callback_carrier).
     *
     * @param carrier The calling thread's carrier block, which has to last as long as the thread.
     */
    register_carrier #no_context :: fn(carrier: ptr[mut CarrierBlock]) {
        intrinsics.set_thread_carrier(carrier)
    }

    /**
     * Make a carrier block for a thread a callback from foreign code found none on: a thread Hemera didn't start.
     *
     * The block comes from the runtime's heap, zeroed, and is kept for the rest of the thread's life, registered so
     * later callbacks on the thread find it; segments come from PAGES_ALLOCATOR. Its stack's bounds aren't known, so it
     * has no limit. Callback shims call this with a temporary one loaded, counting a foreign call. Without the memory,
     * the program stops with a trap.
     *
     * @return The new carrier block, which the thread keeps; never null.
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

    /**
     * Run a thread, on its new stack: load its carrier block first, since every prologue reads it, with its stack's
     * limit, then call its function with the context it was created with.
     *
     * Started by clone, it ends with the exit system call, which ends only this thread, and never returns; started by
     * pthread_create, it returns, with the carrier register as pthreads left it.
     *
     * @param parameter The thread's Thread, as os_thread_start gave it.
     * @return Null, to pthreads; started by clone, it doesn't return.
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

    /** CLONE_VM, FS, FILES, SIGHAND, THREAD, SYSVSEM, PARENT_SETTID and CHILD_CLEARTID: a thread of this process. */
    THREAD_CLONE_FLAGS : u64 : 0x350f00

    /**
     * Start a thread, on a stack of THREAD_STACK_SIZE bytes mapped for it: through pthreads linking C, else with clone.
     *
     * Its Thread's stack choice isn't looked at; every thread gets the same stack.
     *
     * @param thread The thread to start, from thread_create, which has to stay where it is until it's joined, since
     *     the new thread runs on its carrier block and the kernel clears its tid.
     * @return True if it started; false if its stack couldn't be mapped or the thread wasn't made, and then nothing
     *     is left mapped.
     */
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

    /**
     * Wait for a thread to end, then unmap its stack.
     *
     * Linking C, through pthread_join. Otherwise until the kernel has cleared the thread's ID, which it does once the
     * thread has exited, waking this; not a private futex, since the kernel's wake for it isn't.
     *
     * @param thread A thread os_thread_start started, joined only once; the Thread itself is left for the caller to
     *     free.
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

    /**
     * Sleep until a value isn't the one expected, or spuriously (wait.hsc), with a private futex.
     *
     * Returns at once if the value already differs. Callers loop, checking the value, since a wake can come without a
     * change, or from a signal.
     *
     * @param address The value to wait on, shared only among this process's threads.
     * @param expected The value it had when the caller decided to wait.
     */
    wait_on_value :: fn(address: ptr[u32], expected: u32) {
        linux_syscall(SYS_FUTEX, cast[u64](cast[rawptr](address)), FUTEX_WAIT | FUTEX_PRIVATE, cast[u64](expected))
    }

    /**
     * Wake one thread waiting on a value with wait_on_value, if any is.
     *
     * @param address The value waited on.
     */
    wake_one :: fn(address: ptr[u32]) {
        linux_syscall(SYS_FUTEX, cast[u64](cast[rawptr](address)), FUTEX_WAKE | FUTEX_PRIVATE, 1)
    }

    /**
     * Wake every thread waiting on a value with wait_on_value.
     *
     * @param address The value waited on.
     */
    wake_all :: fn(address: ptr[u32]) {
        linux_syscall(SYS_FUTEX, cast[u64](cast[rawptr](address)), FUTEX_WAKE | FUTEX_PRIVATE, 0x7fff_ffff)
    }
}

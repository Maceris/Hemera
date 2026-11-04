package runtime

import intrinsics from "base"

/*
 * What the runtime needs from Windows: the process heap, threads, waiting on an address, and
 * standard output and error.
 */
#if OS == .Windows {
    /** kernel32, Windows' core: the heap, threads, thread-local storage, files, the process and its clocks. */
    KERNEL32 :: #library("kernel32")
    /** bcrypt, for BCryptGenRandom, the system's random numbers. */
    BCRYPT :: #library("bcrypt")
    /** WaitOnAddress and its wakes, from the API set kernelbase implements. */
    SYNCHRONIZATION :: #library("synchronization")

    /**
     * Give the process's default heap, which every thread can use, and which lasts as long as the process.
     *
     * @return The heap's handle, which isn't closed; null only if Windows can't give it.
     */
    GetProcessHeap #foreign(KERNEL32) : fn() -> rawptr : ---
    /**
     * Allocate a block from a heap.
     *
     * @param heap The heap, like GetProcessHeap's.
     * @param flags HEAP_ZERO_MEMORY for the block zeroed, or 0.
     * @param size The block's size in bytes.
     * @return The block, aligned to 16 bytes on 64-bit Windows, which HeapFree gives back; or null without the memory.
     */
    HeapAlloc #foreign(KERNEL32) : fn(heap: rawptr, flags: u32, size: usize) -> rawptr : ---
    /**
     * Give a block back to the heap it came from.
     *
     * @param heap The heap it came from.
     * @param flags 0.
     * @param memory The block, as HeapAlloc gave it, which mustn't be used after.
     * @return Nonzero if it was freed; 0 if not.
     */
    HeapFree #foreign(KERNEL32) : fn(heap: rawptr, flags: u32, memory: rawptr) -> i32 : ---
    /**
     * Start a thread of this process, calling start(parameter) on its own stack.
     *
     * @param attributes Security attributes, or null for the defaults, with a handle that isn't inherited.
     * @param stack_size The stack's size in bytes to commit at first, or 0 for the executable's default.
     * @param start Where the thread starts: a function of the C calling convention taking a pointer, returning a u32.
     * @param parameter What start is given.
     * @param flags 0 to run at once.
     * @param id Where the thread's ID is stored, or null not to.
     * @return The thread's handle, which CloseHandle closes, or null if it wasn't made.
     */
    CreateThread #foreign(KERNEL32) : fn(
        attributes: rawptr,
        stack_size: usize,
        start: rawptr,
        parameter: rawptr,
        flags: u32,
        id: rawptr,
    ) -> rawptr : ---
    /**
     * End the calling thread, never returning.
     *
     * @param code The thread's exit code, which the runtime doesn't read.
     */
    ExitThread #foreign(KERNEL32) : fn(code: u32) #never_returns : ---
    /**
     * Wait until an object is signaled, like a thread ending, or time runs out.
     *
     * @param handle The object, like a thread's handle.
     * @param milliseconds How long to wait at most, or INFINITE for as long as it takes.
     * @return WAIT_OBJECT_0 (0) if it was signaled; another value on a timeout or failure.
     */
    WaitForSingleObject #foreign(KERNEL32) : fn(handle: rawptr, milliseconds: u32) -> u32 : ---
    /**
     * Close a handle, which mustn't be used after.
     *
     * @param handle The handle.
     * @return Nonzero if it was closed; 0 if not.
     */
    CloseHandle #foreign(KERNEL32) : fn(handle: rawptr) -> i32 : ---
    /**
     * Give the bounds of the calling thread's stack as it's reserved, not just what's committed.
     *
     * @param low Where its lowest address is stored, which it grows down towards.
     * @param high Where the address just past its top is stored.
     */
    GetCurrentThreadStackLimits #foreign(KERNEL32) : fn(low: ptr[mut usize], high: ptr[mut usize]) : ---
    /**
     * Allocate a thread-local storage slot, which every thread has its own value in, starting at null.
     *
     * @return The slot's index, or TLS_OUT_OF_INDEXES (0xffffffff) if none is left.
     */
    TlsAlloc #foreign(KERNEL32) : fn() -> u32 : ---
    /**
     * Read the calling thread's value in a thread-local storage slot.
     *
     * @param slot The slot's index, from TlsAlloc.
     * @return The value, null if the thread never set one.
     */
    TlsGetValue #foreign(KERNEL32) : fn(slot: u32) -> rawptr : ---
    /**
     * Set the calling thread's value in a thread-local storage slot.
     *
     * @param slot The slot's index, from TlsAlloc.
     * @param value The value.
     * @return Nonzero if it was set; 0 if not.
     */
    TlsSetValue #foreign(KERNEL32) : fn(slot: u32, value: rawptr) -> i32 : ---
    /**
     * Give one of the process's standard handles.
     *
     * @param which STD_OUTPUT_HANDLE or STD_ERROR_HANDLE.
     * @return The handle, which isn't to be closed; null if the process has none, or INVALID_HANDLE_VALUE (all bits
     *     set) on a failure.
     */
    GetStdHandle #foreign(KERNEL32) : fn(which: u32) -> rawptr : ---
    /**
     * Write bytes to a file or device, synchronously.
     *
     * @param file The handle written to.
     * @param bytes The first byte.
     * @param count How many bytes, at most 4 GiB less one.
     * @param written Where how many were written is stored, which may be fewer than count.
     * @param overlapped Null, for a synchronous write.
     * @return Nonzero if it succeeded; 0 if not.
     */
    WriteFile #foreign(KERNEL32) : fn(file: rawptr, bytes: rawptr, count: u32, written: ptr[mut u32], overlapped: rawptr) -> i32 : ---
    /**
     * Give a handle that stands for the calling process.
     *
     * @return The pseudo-handle, which needn't be closed.
     */
    GetCurrentProcess #foreign(KERNEL32) : fn() -> rawptr : ---
    /**
     * End a process and all its threads at once, running nothing of its: no cleanup, no DLL detaching.
     *
     * @param process The process, like GetCurrentProcess's.
     * @param code Its exit code.
     * @return Nonzero if it was ended (for the calling process, it doesn't return); 0 if not.
     */
    TerminateProcess #foreign(KERNEL32) : fn(process: rawptr, code: u32) -> i32 : ---
    /**
     * Give the process's command line, as one string.
     *
     * @return Its UTF-16 text, ending in a 0, which Windows owns and keeps for the life of the process.
     */
    GetCommandLineW #foreign(KERNEL32) : fn() -> ptr[u16] : ---
    /**
     * Read the performance counter, a monotonic count at QueryPerformanceFrequency's rate.
     *
     * @param count Where the count is stored.
     * @return Nonzero; it never fails on Windows XP or later.
     */
    QueryPerformanceCounter #foreign(KERNEL32) : fn(count: ptr[mut i64]) -> i32 : ---
    /**
     * Read the performance counter's frequency, fixed while the system runs.
     *
     * @param frequency Where its counts per second are stored.
     * @return Nonzero; it never fails on Windows XP or later.
     */
    QueryPerformanceFrequency #foreign(KERNEL32) : fn(frequency: ptr[mut i64]) -> i32 : ---
    /**
     * Read the system's time, as precisely as it has it.
     *
     * @param time Where it's stored, as a FILETIME: 100 nanosecond ticks since 1601-01-01T00:00:00Z.
     */
    GetSystemTimePreciseAsFileTime #foreign(KERNEL32) : fn(time: ptr[mut u64]) : ---
    /**
     * Fill a buffer with random bytes.
     *
     * @param algorithm An algorithm's handle, or null with BCRYPT_USE_SYSTEM_PREFERRED_RNG in flags.
     * @param buffer Where the bytes go.
     * @param count How many bytes.
     * @param flags BCRYPT_USE_SYSTEM_PREFERRED_RNG, for the system's preferred generator.
     * @return 0 (STATUS_SUCCESS) if it was filled; an NTSTATUS error if not.
     */
    BCryptGenRandom #foreign(BCRYPT) : fn(algorithm: rawptr, buffer: rawptr, count: u32, flags: u32) -> i32 : ---
    /**
     * Sleep while a value is the same as compare's, until woken, time runs out, or spuriously.
     *
     * @param address The value watched.
     * @param compare The value it's compared with, of size bytes.
     * @param size The value's size in bytes: 1, 2, 4 or 8.
     * @param milliseconds How long to wait at most, or INFINITE for as long as it takes.
     * @return Nonzero if woken, or the value differed; 0 on a timeout.
     */
    WaitOnAddress #foreign(SYNCHRONIZATION) : fn(address: rawptr, compare: rawptr, size: usize, milliseconds: u32) -> i32 : ---
    /**
     * Wake one thread waiting on an address with WaitOnAddress, if any is.
     *
     * @param address The address waited on.
     */
    WakeByAddressSingle #foreign(SYNCHRONIZATION) : fn(address: rawptr) : ---
    /**
     * Wake every thread waiting on an address with WaitOnAddress.
     *
     * @param address The address waited on.
     */
    WakeByAddressAll #foreign(SYNCHRONIZATION) : fn(address: rawptr) : ---

    /** A wait's timeout that never comes: wait as long as it takes. */
    INFINITE : u32 : 0xffffffff
    /** GetStdHandle's choice of standard output, (DWORD)-11. */
    STD_OUTPUT_HANDLE : u32 : 0xfffffff5
    /** GetStdHandle's choice of standard error, (DWORD)-12. */
    STD_ERROR_HANDLE : u32 : 0xfffffff4
    /** HeapAlloc's flag for a block zeroed. */
    HEAP_ZERO_MEMORY : u32 : 8

    /**
     * Allocate, resize or free a block of the process heap, as an AllocatorFn, for HEAP_ALLOCATOR.
     *
     * The process heap is one any thread can use. Each block has room in front of it for where HeapAlloc's block
     * starts, so any alignment works and freeing needs only the pointer. Blocks are zeroed; a resized block's bytes
     * past the old size are too.
     *
     * @param allocator_data Unused: the allocator has no state.
     * @param size The new block's size in bytes; 0 for no new block, only freeing old_memory.
     * @param alignment The new block's alignment, a power of two; anything up to 16 gives 16.
     * @param old_memory A block this allocator gave, to copy from and free, or null for none.
     * @param old_size old_memory's size in bytes, of which as many as fit are copied into the new block.
     * @param location Where the allocation was asked for; unused.
     * @return The new block, which the caller owns until it gives it back; empty when size is 0 or on an error.
     * @return An error, or null: OutOfMemory if the heap couldn't give the block, InvalidArgument if alignment isn't a
     *     power of two. On an error, old_memory is left as it was.
     */
    heap_allocator_function : AllocatorFn : fn(
        allocator_data: rawptr,
        size: usize,
        alignment: usize,
        old_memory: rawptr,
        old_size: usize,
        location := #caller_location,
    ) -> (mut u8[], AllocatorError?) {
        empty : mut u8[]
        heap :: GetProcessHeap()
        result := empty
        if size > 0 {
            align :: if alignment > 16 { alignment } else { cast[usize](16) }
            if align & (align - 1) != 0 {
                return empty, AllocatorError.InvalidArgument
            }
            raw :: HeapAlloc(heap, HEAP_ZERO_MEMORY, size + align + 16)
            if raw == null {
                return empty, AllocatorError.OutOfMemory
            }
            // At least 8 bytes in, for the header just in front
            start :: (cast[usize](raw) + 8 + align - 1) & ~(align - 1)
            cast[ptr[mut usize]](cast[rawptr](start - 8))^ = cast[usize](raw)
            result = view_of(cast[ptr[mut u8]](cast[rawptr](start)), size)
        }
        if old_memory != null {
            if size > 0 {
                intrinsics.mem_copy(cast[mut rawptr](result.data), old_memory, if old_size < size { old_size } else { size })
            }
            raw :: cast[ptr[usize]](cast[rawptr](cast[usize](old_memory) - 8))^
            HeapFree(heap, 0, cast[rawptr](raw))
        }
        return result, null
    }

    /** The process heap, as an allocator any thread can use, giving zeroed blocks of any alignment. */
    HEAP_ALLOCATOR :: Allocator.{heap_allocator_function, null}

    /**
     * Write bytes to standard output or standard error.
     *
     * A WriteFile at a time, each of at most 1 GiB, until they're all written; a write that fails, or writes nothing,
     * ends it there, silently, since there's nowhere left to report it. Nothing happens without the stream, like in a
     * program started with it closed.
     *
     * @param stream OUTPUT for standard output; anything else for standard error.
     * @param bytes The first byte, which only has to stay valid for the call.
     * @param count How many bytes; 0 writes nothing.
     */
    os_write #no_context :: fn(stream: OutputStream, bytes: rawptr, count: usize) {
        which := STD_ERROR_HANDLE
        if stream == OutputStream.OUTPUT {
            which = STD_OUTPUT_HANDLE
        }
        handle :: GetStdHandle(which)
        // INVALID_HANDLE_VALUE, or none
        if handle == null || cast[usize](handle) == ~cast[usize](0) {
            return void
        }
        done : usize = 0
        loop {
            if done >= count {
                break
            }
            left :: count - done
            chunk :: if left > 0x40000000 { cast[u32](0x40000000) } else { cast[u32](left) }
            written : u32 = 0
            if WriteFile(handle, bytes + done, chunk, &written, null) == 0 || written == 0 {
                return void
            }
            done += cast[usize](written)
        }
    }

    /**
     * End the process at once, every thread of it, running nothing else: for a failed assertion.
     *
     * @param code The process's exit code.
     */
    os_exit_process #no_context :: fn(code: u32) #never_returns {
        TerminateProcess(GetCurrentProcess(), code)
        intrinsics.trap()
    }

    /**
     * Give the program's command line, GetCommandLineW as UTF-8, split as the C runtime splits it
     * (split_command_line), the program's name first.
     *
     * @param allocator Where the arguments' array and their text come from, which are kept for the rest of the
     *     process: what's allocated isn't given back, even when it ends up unused.
     * @return The arguments, each viewing text from allocator. Empty if the command line is, if memory runs out, or if
     *     it couldn't be converted.
     */
    os_command_line_arguments :: fn(allocator: Allocator) -> string[] {
        empty : string[]
        line :: GetCommandLineW()
        length : usize = 0
        loop {
            if cast[ptr[u16]](cast[rawptr](line) + length * 2)^ == 0 {
                break
            }
            length += 1
        }
        if length == 0 {
            return empty
        }
        capacity :: utf8_capacity_for_utf16(length)
        // The command line as UTF-8, then each argument, which is never longer than it
        text, text_error :: new_array(u8, capacity, allocator)
        split, split_error :: new_array(u8, capacity, allocator)
        if text_error != null || split_error != null || text.count == 0 {
            return empty
        }
        converted :: utf16_to_utf8(view_of(line, length), text)
        if converted == 0 || converted > text.count {
            return empty
        }
        utf8 :: string_of(&text[0], converted)
        none : mut string[]
        count :: split_command_line(utf8, split, none)
        arguments, arguments_error :: new_array(string, count, allocator)
        if arguments_error != null {
            return empty
        }
        split_command_line(utf8, split, arguments)
        return arguments
    }

    /**
     * The system's clocks: the performance counter for monotonic time, which counts at a frequency
     * that's fixed while the system runs, and the precise system time for the wall clock, in 100
     * nanosecond ticks since 1601.
     */
    SYSTEM_CLOCK :: Clock.{
        data = null,
        monotonic = system_monotonic,
        wall = system_wall,
    }

    /**
     * Read the monotonic clock, the performance counter, in nanoseconds.
     *
     * @param data Unused: the clock has no state.
     * @return Nanoseconds since an unspecified start, like the system's boot, which never go back; 0 if the counter's
     *     frequency can't be read, since a monotonic time can't report an error.
     */
    system_monotonic :: fn(data: mut rawptr) -> MonotonicTime {
        count : i64 = 0
        frequency : i64 = 0
        QueryPerformanceCounter(&count)
        QueryPerformanceFrequency(&frequency)
        if frequency <= 0 {
            return 0
        }
        // Seconds and what's left, so the nanoseconds don't overflow
        seconds :: count / frequency
        left :: count % frequency
        return cast[MonotonicTime](seconds * NANOSECONDS_PER_SECOND + left * NANOSECONDS_PER_SECOND / frequency)
    }

    /** The 100 nanosecond ticks from 1601-01-01, a FILETIME's start, to 1970-01-01, an Instant's. */
    FILETIME_TO_UNIX : u64 : 116444736000000000

    /**
     * Read the wall clock, the system's precise time.
     *
     * @param data Unused: the clock has no state.
     * @return The time since 1970-01-01T00:00:00Z, as the system has it set, to 100 nanoseconds.
     * @error NotSynchronized The system's time is before 1970, so it can't have been set.
     */
    system_wall :: fn(data: mut rawptr) -> Result[Instant, ClockError] {
        ticks : u64 = 0
        GetSystemTimePreciseAsFileTime(&ticks)
        if ticks < FILETIME_TO_UNIX {
            return .Error(.NotSynchronized)
        }
        since :: ticks - FILETIME_TO_UNIX
        return .Ok(Instant.{cast[i64](since / 10000000), cast[u32](since % 10000000 * 100)})
    }

    /** The system's random numbers, from its preferred generator, which is suitable for keys. */
    SYSTEM_RANDOM :: Random.{
        data = null,
        fill = system_random_fill,
    }

    /** BCryptGenRandom's flag for the system's preferred generator, with no algorithm handle. */
    BCRYPT_USE_SYSTEM_PREFERRED_RNG : u32 : 2

    /**
     * Fill bytes with the system's random numbers, a BCryptGenRandom of at most 1 GiB at a time.
     *
     * If BCryptGenRandom fails, the program stops with a trap, since fill can't report it and bytes that aren't
     * random mustn't be used as if they were.
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
            left :: bytes.count - done
            chunk :: if left > 0x40000000 { cast[u32](0x40000000) } else { cast[u32](left) }
            if BCryptGenRandom(null, cast[rawptr](bytes.data) + done, chunk, BCRYPT_USE_SYSTEM_PREFERRED_RNG) != 0 {
                intrinsics.trap()
            }
            done += cast[usize](chunk)
        }
    }

    /**
     * What a hosted program's main starts with: the process heap, the standard logger and assertion
     * handler, and the system's clock and random numbers.
     */
    HOSTED_CONTEXT :: Context.{
        allocator = HEAP_ALLOCATOR,
        logger = &STANDARD_LOGGER,
        log_level = .INFO,
        clock = &SYSTEM_CLOCK,
        random = &SYSTEM_RANDOM,
        assertion_handler = printing_assertion_handler,
        user_data = null,
        extensions = null,
    }

    /** Room in bytes left below stack_limit on a thread's own stack, for foreign code and the system. */
    NATIVE_STACK_RESERVE :: 65536

    /** What a Thread has on Windows: set by os_thread_start, and closed by os_thread_join. */
    ThreadSpecificOS :: struct {
        /** The thread's handle, from CreateThread. */
        handle : rawptr,
    }

    /**
     * Run a thread: load its carrier block first, since every prologue reads it, with its own stack's limit, then call
     * its function with the context it was created with.
     *
     * It ends with ExitThread rather than returning, since it doesn't keep the carrier register for its caller.
     *
     * @param parameter The thread's Thread, as os_thread_start gave it.
     * @return Nothing: it never returns.
     */
    windows_thread_entry #calling_convention(.c) #no_context :: fn(parameter: rawptr) -> u32 {
        thread :: cast[ptr[mut Thread]](parameter)
        intrinsics.set_carrier(&thread.carrier)
        register_carrier(&thread.carrier)
        low : usize = 0
        high : usize = 0
        GetCurrentThreadStackLimits(&low, &high)
        thread.carrier.native_stack_limit = cast[rawptr](low + NATIVE_STACK_RESERVE)
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
        ExitThread(0)
    }

    /**
     * Store a thread's carrier block in its thread-local storage, where callbacks from foreign code look for it.
     *
     * The slot is allocated the first time, kept in the process state plus one so 0 means none yet. The program's
     * entry does this for the main thread before any other starts, so the slot's allocation isn't raced. If no slot
     * is left, the carrier block isn't stored where it can be found.
     *
     * @param carrier The calling thread's carrier block, which has to last as long as the thread.
     */
    register_carrier #no_context :: fn(carrier: ptr[mut CarrierBlock]) {
        slot :: &intrinsics.process_state().carrier_slot
        if slot^ == 0 {
            slot^ = TlsAlloc() + 1
        }
        TlsSetValue(slot^ - 1, cast[rawptr](carrier))
    }

    /**
     * Find the carrier block of the thread a callback from foreign code is on, making one if it has none.
     *
     * Callback shims call this with a temporary one loaded (counting a foreign call, so nothing here moves stacks or
     * yields). A thread Hemera didn't start gets one of its own the first time, from the process heap, with its
     * stack's limits and the heap for segments, kept for the rest of the thread's life (it may call back again).
     * Without the memory, the program stops with a trap.
     *
     * @return The thread's carrier block, which lasts as long as the thread; never null.
     */
    callback_carrier #no_context :: fn() -> ptr[mut CarrierBlock] {
        slot :: &intrinsics.process_state().carrier_slot
        if slot^ != 0 {
            found :: TlsGetValue(slot^ - 1)
            if found != null {
                return cast[ptr[mut CarrierBlock]](found)
            }
        }
        raw :: HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, size_of(CarrierBlock) + align_of(CarrierBlock))
        if raw == null {
            intrinsics.trap()
        }
        alignment :: cast[usize](align_of(CarrierBlock))
        carrier :: cast[ptr[mut CarrierBlock]](cast[rawptr]((cast[usize](raw) + alignment - 1) & ~(alignment - 1)))
        low : usize = 0
        high : usize = 0
        GetCurrentThreadStackLimits(&low, &high)
        carrier.native_stack_limit = cast[rawptr](low + NATIVE_STACK_RESERVE)
        carrier.stack_limit = carrier.native_stack_limit
        carrier.segment_allocator = HEAP_ALLOCATOR
        register_carrier(carrier)
        return carrier
    }

    /**
     * Start a thread with CreateThread, on a stack Windows makes for it, of the executable's default size.
     *
     * Its Thread's stack choice isn't looked at yet.
     *
     * @param thread The thread to start, from thread_create, which has to stay where it is until it's joined, since
     *     the new thread runs on its carrier block.
     * @return True if it started; false if Windows wouldn't make it.
     */
    os_thread_start :: fn(thread #escaping : ptr[mut Thread]) -> bool {
        thread.handle = CreateThread(null, 0, cast[rawptr](windows_thread_entry), cast[rawptr](thread), 0, null)
        return thread.handle != null
    }

    /**
     * Wait for a thread to end, then close its handle; Windows gives back its stack.
     *
     * @param thread A thread os_thread_start started, joined only once; the Thread itself is left for the caller to
     *     free.
     */
    os_thread_join :: fn(thread: ptr[mut Thread]) {
        WaitForSingleObject(thread.handle, INFINITE)
        CloseHandle(thread.handle)
    }

    /**
     * Sleep until a value isn't the one expected, or spuriously (wait.hsc), with WaitOnAddress.
     *
     * Returns at once if the value already differs. Callers loop, checking the value, since a wake can come without a
     * change.
     *
     * @param address The value to wait on.
     * @param expected The value it had when the caller decided to wait.
     */
    wait_on_value :: fn(address: ptr[u32], expected: u32) {
        compare := expected
        WaitOnAddress(cast[rawptr](address), cast[rawptr](&compare), 4, INFINITE)
    }

    /**
     * Wake one thread waiting on a value with wait_on_value, if any is.
     *
     * @param address The value waited on.
     */
    wake_one :: fn(address: ptr[u32]) {
        WakeByAddressSingle(cast[rawptr](address))
    }

    /**
     * Wake every thread waiting on a value with wait_on_value.
     *
     * @param address The value waited on.
     */
    wake_all :: fn(address: ptr[u32]) {
        WakeByAddressAll(cast[rawptr](address))
    }
}

package runtime

import intrinsics from "base"

/*
 * Threads on SlopOS: each a kernel thread in the process's address space, on a stack of its own mapped from the startup
 * block's free range, with its carrier block in its Thread, and the program's budget paying for both. Its Hemera code
 * runs on that one stack (a Segmented stack's first segment isn't used yet, so it gets SLOP_OS_THREAD_STACK). Joining
 * waits for the kernel to say the thread ended, then gives its stack back.
 *
 * There's no wait on an address in the kernel yet, so wait_on_value spins once, as without an operating system.
 */
#if OS == .SlopOS && (TARGET_ARCH == .x86_64 || TARGET_ARCH == .arm64) {
    /**
     * A thread's stack, in bytes, when it doesn't ask for a fixed one: a Segmented stack gets this much, since its
     * first segment isn't used yet.
     */
    SLOP_OS_THREAD_STACK : usize : 256 * 1024

    /** The kernel call that ends the calling thread; it doesn't return. */
    SLOP_OS_CALL_THREAD_EXIT : u64 : 3
    /** The kernel call that makes a thread: from a budget, in an address space, at an entry, on a stack, with a word. */
    SLOP_OS_CALL_THREAD_CREATE : u64 : 4
    /** The kernel call that makes a port, paid for from a budget. */
    SLOP_OS_CALL_PORT_CREATE : u64 : 8
    /** The kernel call that queues a User packet for a key on a port, through the port's wake binding for the key. */
    SLOP_OS_CALL_PORT_WAKE : u64 : 10
    /** The kernel call that waits for packets on a port, until a deadline. */
    SLOP_OS_CALL_PORT_WAIT : u64 : 13
    /** The kernel call that reads a message from a channel, failing at once when there's none. */
    SLOP_OS_CALL_CHANNEL_READ : u64 : 19
    /** The kernel call that binds a handle's signals to a port, so they come to it as packets. */
    SLOP_OS_CALL_PORT_BIND : u64 : 23
    /** The signal of a channel with a message to read. */
    SLOP_OS_SIGNAL_READABLE : u64 : 1
    /** The signal of a channel whose other end has closed. */
    SLOP_OS_SIGNAL_PEER_CLOSED : u64 : 4
    /** The signal of a thread that has ended. */
    SLOP_OS_SIGNAL_TERMINATED : u64 : 8
    /** A binding that gives one packet, then is gone. */
    SLOP_OS_BIND_ONCE : u64 : 1
    /** A binding that gives a packet each time its signals are raised, for as long as it lasts. */
    SLOP_OS_BIND_PERSISTENT : u64 : 2
    /** A wait's deadline that never comes: wait as long as it takes. */
    SLOP_OS_NO_DEADLINE : u64 : 0xffffffffffffffff
    /** The words (u64s) of a port packet, as the kernel writes it: its key, kind, and two words. */
    SLOP_OS_PACKET_WORDS :: 4

    /** What a Thread has on SlopOS: set by os_thread_start, and given back by os_thread_join. */
    ThreadSpecificOS :: struct {
        /** The kernel thread's owning handle, which os_thread_join closes. */
        kernel_thread : u64,
        /** The lowest address of the stack the thread runs on, from map_pages. */
        stack_pages : rawptr,
        /** The stack's size in bytes, a whole number of pages. */
        stack_bytes : usize,
    }

    /**
     * Start a thread as a kernel thread of this process, on a stack mapped for it.
     *
     * A Fixed stack's size is rounded up to whole pages; a Segmented stack gets SLOP_OS_THREAD_STACK bytes. The stack
     * and the kernel thread are paid for from the program's budget.
     *
     * @param thread The thread to start, from thread_create, which has to stay where it is until it's joined, since
     *     the new thread runs on its carrier block.
     * @return True if it started; false if its stack couldn't be mapped or the kernel wouldn't make the thread, and
     *     then nothing is left mapped.
     */
    os_thread_start :: fn(thread #escaping : ptr[mut Thread]) -> bool {
        size := SLOP_OS_THREAD_STACK
        match thread.stack {
            case Fixed(bytes) => size = (bytes + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1)
            case Segmented(_) => {}
        }
        stack :: map_pages(size)
        if stack == null {
            return false
        }
        thread.stack_pages = stack
        thread.stack_bytes = size
        handle :: slop_os_start_thread(cast[rawptr](slop_os_thread_entry), stack, size, cast[u64](cast[uintptr](thread)))
        if handle == 0 {
            unmap_pages(stack, size)
            return false
        }
        thread.kernel_thread = handle
        return true
    }

    /**
     * Wait for a thread to end, then close its kernel thread's handle and unmap its stack.
     *
     * @param thread A thread os_thread_start started, joined only once; the Thread itself is left for the caller to
     *     free.
     */
    os_thread_join :: fn(thread: ptr[mut Thread]) {
        slop_os_wait_for_thread(thread.kernel_thread)
        slop_os_call(SLOP_OS_CALL_HANDLE_CLOSE, thread.kernel_thread)
        unmap_pages(thread.stack_pages, thread.stack_bytes)
    }

    /**
     * Make a kernel thread of this process that starts at entry.
     *
     * The thread is paid for from the program's budget. Its stack pointer starts at the stack's top, rounded down to 16
     * bytes, as both architectures' calls want it.
     *
     * @param entry Where the thread starts: a function of the C calling convention taking one u64, which never returns
     *     but ends the thread with SLOP_OS_CALL_THREAD_EXIT.
     * @param stack The lowest address of the thread's stack, which the caller owns and has to keep mapped until the
     *     thread has ended.
     * @param size The stack's size in bytes.
     * @param argument What the thread is given in its first argument register.
     * @return The kernel thread's owning handle, which the caller closes, or 0 if the kernel wouldn't make it.
     */
    slop_os_start_thread #no_context :: fn(entry: rawptr, stack: rawptr, size: usize, argument: u64) -> u64 {
        startup :: cast[ptr[SlopOsStartup]](intrinsics.process_state().startup_block)
        /*
         * The top, 16-byte aligned, as both architectures' calls want it; on x86-64, 8 bytes below, where a call's return
         * address would be, as the entry is a function entered as if called: otherwise its frames are 8 bytes off, and an
         * aligned store to one faults
         */
        aligned :: (cast[u64](cast[uintptr](stack)) + cast[u64](size)) & ~cast[u64](15)
        top :: if TARGET_ARCH == .x86_64 { aligned - 8 } else { aligned }
        made :: slop_os_call(SLOP_OS_CALL_THREAD_CREATE, cast[u64](startup.budget), cast[u64](startup.space), cast[u64](cast[uintptr](entry)),
            top, argument)
        return if made.tag == 0 { made.first } else { cast[u64](0) }
    }

    /**
     * Wait until a kernel thread has ended, on a port made for the wait and closed after it.
     *
     * If the port can't be made, it returns at once without waiting; if it can't be bound to the thread, it closes the
     * port and returns without waiting.
     *
     * @param handle A handle of the kernel thread, which stays open; the caller closes it.
     */
    slop_os_wait_for_thread #no_context :: fn(handle: u64) {
        startup :: cast[ptr[SlopOsStartup]](intrinsics.process_state().startup_block)
        port :: slop_os_call(SLOP_OS_CALL_PORT_CREATE, cast[u64](startup.budget))
        if port.tag != 0 {
            return void
        }
        bound :: slop_os_call(SLOP_OS_CALL_PORT_BIND, port.first, handle, SLOP_OS_SIGNAL_TERMINATED, 0, SLOP_OS_BIND_ONCE)
        if bound.tag == 0 {
            packets : u64[SLOP_OS_PACKET_WORDS]
            slop_os_call(SLOP_OS_CALL_PORT_WAIT, port.first, cast[u64](cast[uintptr](&packets[0])), 1, SLOP_OS_NO_DEADLINE)
        }
        slop_os_call(SLOP_OS_CALL_HANDLE_CLOSE, port.first)
    }

    /**
     * Run a thread: load its carrier block, with its stack's limit, call its function with the context it was made
     * with, then end the kernel thread, since there's nothing to return to.
     *
     * @param argument The address of the thread's Thread, as os_thread_start gave it.
     */
    slop_os_thread_entry #calling_convention(.c) #no_context :: fn(argument: u64) #never_returns {
        thread :: cast[ptr[mut Thread]](cast[rawptr](cast[uintptr](argument)))
        intrinsics.set_carrier(&thread.carrier)
        thread.carrier.native_stack_limit = cast[rawptr](cast[u64](cast[uintptr](thread.stack_pages)) + STACK_RESERVE)
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
        // Its per-thread page given back, if it had one
        if thread.carrier.thread_page != null {
            slop_os_call(SLOP_OS_CALL_THREAD_SET_PAGE, 0, 0)
            unmap_pages(thread.carrier.thread_page, PAGE_SIZE)
        }
        slop_os_call(SLOP_OS_CALL_THREAD_EXIT)
        loop {
            intrinsics.trap()
        }
    }

    /**
     * Write the calling thread's per-thread page (the SlopOS repository's decisions/0041 and 0185): the fiber running
     * and the CPU budget it's bound to. The page is made the first time it's wanted: a page of memory of its own
     * (map_pages), given to the kernel with SLOP_OS_CALL_THREAD_SET_PAGE; if that fails, it isn't tried again on this
     * thread, and nothing is written.
     *
     * @param carrier The calling thread's carrier block, whose thread_page it is.
     * @param fiber The fiber running, its Fiber's address; 0 for none.
     * @param budget The CPU budget's handle; 0 for the process's own.
     * @return True if the page was written; false if there's none.
     */
    slop_os_note_fiber #no_context :: fn(carrier: ptr[mut CarrierBlock], fiber: u64, budget: u64) -> bool {
        if carrier.thread_page == null {
            // Only a thread with a fiber or a budget to note needs one
            if carrier.thread_page_failed || (fiber == 0 && budget == 0) || intrinsics.process_state().startup_block == null {
                return false
            }
            page :: map_pages(PAGE_SIZE)
            if page == null {
                carrier.thread_page_failed = true
                return false
            }
            handle :: cast[ptr[u64]](cast[rawptr](cast[u64](cast[uintptr](page)) - cast[u64](PAGE_SIZE)))^
            if slop_os_call(SLOP_OS_CALL_THREAD_SET_PAGE, handle, cast[u64](PAGE_SIZE)).tag != 0 {
                unmap_pages(page, PAGE_SIZE)
                carrier.thread_page_failed = true
                return false
            }
            carrier.thread_page = page
        }
        written :: cast[ptr[mut SlopOsThreadPage]](carrier.thread_page)
        intrinsics.volatile_store_u64(&written.fiber, fiber)
        intrinsics.volatile_store_u64(&written.budget, budget)
        return true
    }

    /**
     * Wait for a value to change: here, since the kernel has no wait on an address yet, spin once and return, as
     * without an operating system (wait.hsc), so callers loop the same either way.
     *
     * @param address The value to watch, which isn't read here.
     * @param expected The value it had when the caller decided to wait.
     */
    wait_on_value :: fn(address: ptr[u32], expected: u32) {
        deterministic_turn()
        intrinsics.spin_hint()
    }

    /**
     * Tell whether the process runs in the deterministic mode: whether it was given a grant "deterministic", looked
     * up the first time and remembered.
     *
     * @return True in the mode.
     */
    slop_os_deterministic #no_context :: fn() -> bool {
        state :: intrinsics.process_state()
        known :: intrinsics.atomic_load_u32_acquire(&state.deterministic)
        if known != 0 {
            return known == 2
        }
        found :: os_entry_grant("deterministic", "Memory", "", false) != 0
        intrinsics.atomic_store_u32_release(&state.deterministic, if found { 2 } else { 1 })
        return found
    }

    /**
     * Wake one thread waiting on a value: here nothing, since wait_on_value doesn't sleep.
     *
     * @param address The value waited on.
     */
    wake_one :: fn(address: ptr[u32]) {}

    /**
     * Wake every thread waiting on a value: here nothing, since wait_on_value doesn't sleep.
     *
     * @param address The value waited on.
     */
    wake_all :: fn(address: ptr[u32]) {}

    /**
     * Give the program's command line: none on SlopOS, where the kernel's is a grant, for those given it.
     *
     * @param allocator Unused, since nothing is allocated.
     * @return An empty array, always.
     */
    os_command_line_arguments :: fn(allocator: Allocator) -> string[] {
        empty : string[]
        return empty
    }
}

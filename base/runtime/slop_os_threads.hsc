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
    /** A thread's stack when it doesn't ask for a fixed one */
    SLOP_OS_THREAD_STACK : usize : 256 * 1024

    SLOP_OS_CALL_THREAD_EXIT : u64 : 3
    SLOP_OS_CALL_THREAD_CREATE : u64 : 4
    SLOP_OS_CALL_PORT_CREATE : u64 : 8
    SLOP_OS_CALL_PORT_WAKE : u64 : 10
    SLOP_OS_CALL_PORT_WAIT : u64 : 13
    SLOP_OS_CALL_CHANNEL_READ : u64 : 19
    SLOP_OS_CALL_PORT_BIND : u64 : 23
    SLOP_OS_SIGNAL_READABLE : u64 : 1
    SLOP_OS_SIGNAL_PEER_CLOSED : u64 : 4
    SLOP_OS_SIGNAL_TERMINATED : u64 : 8
    SLOP_OS_BIND_ONCE : u64 : 1
    SLOP_OS_BIND_PERSISTENT : u64 : 2
    SLOP_OS_NO_DEADLINE : u64 : 0xffffffffffffffff
    /** A port packet, as the kernel writes it: its key, kind, and two words */
    SLOP_OS_PACKET_WORDS :: 4

    ThreadSpecificOS :: struct {
        // The kernel thread's owning handle, and the stack it runs on
        kernel_thread : u64,
        stack_pages : rawptr,
        stack_bytes : usize,
    }

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

    os_thread_join :: fn(thread: ptr[mut Thread]) {
        slop_os_wait_for_thread(thread.kernel_thread)
        slop_os_call(SLOP_OS_CALL_HANDLE_CLOSE, thread.kernel_thread)
        unmap_pages(thread.stack_pages, thread.stack_bytes)
    }

    /**
     * A kernel thread at entry, on size bytes of stack, given argument in its first argument register: its owning handle,
     * or 0 if it couldn't be made.
     */
    slop_os_start_thread #no_context :: fn(entry: rawptr, stack: rawptr, size: usize, argument: u64) -> u64 {
        startup :: cast[ptr[SlopOsStartup]](intrinsics.process_state().startup_block)
        // The top, 16-byte aligned, as both architectures' calls want it
        top :: (cast[u64](cast[uintptr](stack)) + cast[u64](size)) & ~cast[u64](15)
        made :: slop_os_call(SLOP_OS_CALL_THREAD_CREATE, cast[u64](startup.budget), cast[u64](startup.space), cast[u64](cast[uintptr](entry)),
            top, argument)
        return if made.tag == 0 { made.first } else { cast[u64](0) }
    }

    /** Until the thread whose handle this is has ended. */
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
     * Where a thread starts: its carrier block loaded, with its stack's limit, then its function with the context it was
     * made with; then the kernel thread ends, since there's nothing to return to.
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
        slop_os_call(SLOP_OS_CALL_THREAD_EXIT)
        loop {
            intrinsics.trap()
        }
    }

    wait_on_value :: fn(address: ptr[u32], expected: u32) {
        intrinsics.spin_hint()
    }

    wake_one :: fn(address: ptr[u32]) {}

    wake_all :: fn(address: ptr[u32]) {}

    /** No command line: the kernel's is a grant, for those given it */
    os_command_line_arguments :: fn(allocator: Allocator) -> string[] {
        empty : string[]
        return empty
    }
}

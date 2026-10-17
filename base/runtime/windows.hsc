package runtime

import intrinsics from "base"

/*
 * What the runtime needs from Windows: the process heap, threads, and waiting on an address.
 */
#if OS == .Windows {
    KERNEL32 :: #library("kernel32")
    // WaitOnAddress and its wakes, from the API set kernelbase implements
    SYNCHRONIZATION :: #library("synchronization")

    GetProcessHeap #foreign(KERNEL32) : fn() -> rawptr : ---
    HeapAlloc #foreign(KERNEL32) : fn(heap: rawptr, flags: u32, size: usize) -> rawptr : ---
    HeapFree #foreign(KERNEL32) : fn(heap: rawptr, flags: u32, memory: rawptr) -> i32 : ---
    CreateThread #foreign(KERNEL32) : fn(
        attributes: rawptr,
        stack_size: usize,
        start: rawptr,
        parameter: rawptr,
        flags: u32,
        id: rawptr,
    ) -> rawptr : ---
    ExitThread #foreign(KERNEL32) : fn(code: u32) #never_returns : ---
    WaitForSingleObject #foreign(KERNEL32) : fn(handle: rawptr, milliseconds: u32) -> u32 : ---
    CloseHandle #foreign(KERNEL32) : fn(handle: rawptr) -> i32 : ---
    GetCurrentThreadStackLimits #foreign(KERNEL32) : fn(low: ptr[mut usize], high: ptr[mut usize]) : ---
    WaitOnAddress #foreign(SYNCHRONIZATION) : fn(address: rawptr, compare: rawptr, size: usize, milliseconds: u32) -> i32 : ---
    WakeByAddressSingle #foreign(SYNCHRONIZATION) : fn(address: rawptr) : ---
    WakeByAddressAll #foreign(SYNCHRONIZATION) : fn(address: rawptr) : ---

    INFINITE : u32 : 0xffffffff
    HEAP_ZERO_MEMORY : u32 : 8

    /*
     * The process heap, which any thread can use. Each block has room in front of it for where
     * HeapAlloc's block starts, so any alignment works and freeing needs only the pointer. Blocks
     * are zeroed.
     */
    heap_allocator_function : AllocatorFn : fn(
        allocator_data: rawptr,
        size: usize,
        alignment: usize,
        old_memory: rawptr,
        old_size: usize,
        location := #caller_location,
    ) -> (u8[], AllocatorError?) {
        empty : u8[]
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
                intrinsics.mem_copy(cast[rawptr](result.data), old_memory, if old_size < size { old_size } else { size })
            }
            raw :: cast[ptr[usize]](cast[rawptr](cast[usize](old_memory) - 8))^
            HeapFree(heap, 0, cast[rawptr](raw))
        }
        return result, null
    }

    HEAP_ALLOCATOR :: Allocator.{heap_allocator_function, null}

    /*
     * What a hosted program's main starts with: the process heap, and otherwise MINIMAL_CONTEXT's
     * constants until there's a logger, a clock and random numbers for Windows.
     */
    HOSTED_CONTEXT :: Context.{
        allocator = HEAP_ALLOCATOR,
        logger = &DISCARDING_LOGGER,
        log_level = .FATAL,
        clock = &NO_CLOCK,
        random = &NO_RANDOM,
        assertion_handler = trap_assertion_handler,
        user_data = null,
        extensions = null,
    }

    // Room left below stack_limit on a thread's own stack, for foreign code and the system.
    NATIVE_STACK_RESERVE :: 65536

    ThreadSpecificOS :: struct {
        handle : rawptr,
    }

    /*
     * Where a thread starts: its carrier block first, since every prologue reads it, with its own
     * stack's limit, then its function with the context it was created with. It ends with
     * ExitThread rather than returning, since it doesn't keep the carrier register for its caller.
     */
    windows_thread_entry #calling_convention(.c) #no_context :: fn(parameter: rawptr) -> u32 {
        thread :: cast[ptr[mut Thread]](parameter)
        intrinsics.set_carrier(&thread.carrier)
        low : usize = 0
        high : usize = 0
        GetCurrentThreadStackLimits(&low, &high)
        thread.carrier.native_stack_limit = cast[rawptr](low + NATIVE_STACK_RESERVE)
        thread.carrier.stack_limit = thread.carrier.native_stack_limit
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

    os_thread_start :: fn(thread #escaping : ptr[mut Thread]) -> bool {
        thread.handle = CreateThread(null, 0, cast[rawptr](windows_thread_entry), cast[rawptr](thread), 0, null)
        return thread.handle != null
    }

    os_thread_join :: fn(thread: ptr[mut Thread]) {
        WaitForSingleObject(thread.handle, INFINITE)
        CloseHandle(thread.handle)
    }

    wait_on_value :: fn(address: ptr[u64], expected: u64) {
        compare := expected
        WaitOnAddress(cast[rawptr](address), cast[rawptr](&compare), 8, INFINITE)
    }

    wake_one :: fn(address: ptr[u64]) {
        WakeByAddressSingle(cast[rawptr](address))
    }

    wake_all :: fn(address: ptr[u64]) {
        WakeByAddressAll(cast[rawptr](address))
    }
}

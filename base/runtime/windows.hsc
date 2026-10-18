package runtime

import intrinsics from "base"

/*
 * What the runtime needs from Windows: the process heap, threads, waiting on an address, and
 * standard output and error.
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
    TlsAlloc #foreign(KERNEL32) : fn() -> u32 : ---
    TlsGetValue #foreign(KERNEL32) : fn(slot: u32) -> rawptr : ---
    TlsSetValue #foreign(KERNEL32) : fn(slot: u32, value: rawptr) -> i32 : ---
    GetStdHandle #foreign(KERNEL32) : fn(which: u32) -> rawptr : ---
    WriteFile #foreign(KERNEL32) : fn(file: rawptr, bytes: rawptr, count: u32, written: ptr[mut u32], overlapped: rawptr) -> i32 : ---
    GetCurrentProcess #foreign(KERNEL32) : fn() -> rawptr : ---
    TerminateProcess #foreign(KERNEL32) : fn(process: rawptr, code: u32) -> i32 : ---
    WaitOnAddress #foreign(SYNCHRONIZATION) : fn(address: rawptr, compare: rawptr, size: usize, milliseconds: u32) -> i32 : ---
    WakeByAddressSingle #foreign(SYNCHRONIZATION) : fn(address: rawptr) : ---
    WakeByAddressAll #foreign(SYNCHRONIZATION) : fn(address: rawptr) : ---

    INFINITE : u32 : 0xffffffff
    STD_OUTPUT_HANDLE : u32 : 0xfffffff5
    STD_ERROR_HANDLE : u32 : 0xfffffff4
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
     * Bytes to standard output or error, a WriteFile at a time until they're all written. Nothing
     * happens without one, like in a program started with it closed.
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

    // Ends the process at once, with code, running nothing else: for a failed assertion.
    os_exit_process #no_context :: fn(code: u32) #never_returns {
        TerminateProcess(GetCurrentProcess(), code)
        intrinsics.trap()
    }

    /*
     * What a hosted program's main starts with: the process heap, the standard logger and assertion
     * handler, and otherwise MINIMAL_CONTEXT's constants until there's a clock and random numbers
     * for Windows.
     */
    HOSTED_CONTEXT :: Context.{
        allocator = HEAP_ALLOCATOR,
        logger = &STANDARD_LOGGER,
        log_level = .INFO,
        clock = &NO_CLOCK,
        random = &NO_RANDOM,
        assertion_handler = printing_assertion_handler,
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

    /*
     * Store a thread's carrier block in its thread-local storage, where callbacks from foreign code
     * look for it, allocating the slot the first time. The program's entry does this for the main
     * thread before any other starts.
     */
    register_carrier #no_context :: fn(carrier: ptr[mut CarrierBlock]) {
        slot :: &intrinsics.process_state().carrier_slot
        if slot^ == 0 {
            slot^ = TlsAlloc() + 1
        }
        TlsSetValue(slot^ - 1, cast[rawptr](carrier))
    }

    /*
     * The carrier block of the thread a callback from foreign code is on, which callback shims call
     * with a temporary one loaded (counting a foreign call, so nothing here moves stacks or yields).
     * A thread Hemera didn't start gets one of its own the first time, from the process heap, with
     * its stack's limits and the heap for segments, kept for the rest of the thread's life (it may
     * call back again).
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

    os_thread_start :: fn(thread #escaping : ptr[mut Thread]) -> bool {
        thread.handle = CreateThread(null, 0, cast[rawptr](windows_thread_entry), cast[rawptr](thread), 0, null)
        return thread.handle != null
    }

    os_thread_join :: fn(thread: ptr[mut Thread]) {
        WaitForSingleObject(thread.handle, INFINITE)
        CloseHandle(thread.handle)
    }

    wait_on_value :: fn(address: ptr[u32], expected: u32) {
        compare := expected
        WaitOnAddress(cast[rawptr](address), cast[rawptr](&compare), 4, INFINITE)
    }

    wake_one :: fn(address: ptr[u32]) {
        WakeByAddressSingle(cast[rawptr](address))
    }

    wake_all :: fn(address: ptr[u32]) {
        WakeByAddressAll(cast[rawptr](address))
    }
}

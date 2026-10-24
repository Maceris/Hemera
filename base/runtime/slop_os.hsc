package runtime

import intrinsics from "base"

/*
 * What the runtime needs from SlopOS, through its system calls: memory, the clock, and ending the
 * process. x86-64 only, so far. Threads, and waiting on an address, aren't here yet (wait.hsc).
 */

/*
 * The calls slop_os.hsc makes, by number, and the part of the startup block it reads. SlopOS's ABI
 * package (std/os/slop_os) has them all, and checks these against its own when it's compiled, which is
 * why they're declared for every OS.
 */
SLOP_OS_CALL_HANDLE_CLOSE : u64 : 0
SLOP_OS_CALL_CLOCK_MONOTONIC : u64 : 7
SLOP_OS_CALL_MEMORY_CREATE : u64 : 26
SLOP_OS_CALL_MEMORY_MAP : u64 : 27
SLOP_OS_CALL_MEMORY_UNMAP : u64 : 28
SLOP_OS_CALL_PROCESS_EXIT : u64 : 45
SLOP_OS_PROTECTION_READ_WRITE : u64 : 3

// The start of SlopOS's StartupBlock, which the process's entry is given.
SlopOsStartup :: struct {
    abi_version : u32,
    size : u32,
    // Handles to the process itself, its address space and its memory budget
    process : u32,
    space : u32,
    budget : u32,
    grant_count : u32,
    // Where the runtime maps its own memory: free_size bytes from free_base, which nothing else uses
    free_base : u64,
    free_size : u64,
    // The first thread's stack, stack_size bytes from stack_base
    stack_base : u64,
    stack_size : u64,
}

#if OS == .SlopOS && TARGET_ARCH == .x86_64 {
    import x86_64 from "base/intrinsics"

    PAGE_SIZE : usize : 4096
    // Room left below a thread's stack limit, for what runs before a stack check can, like an interrupted call
    STACK_RESERVE : u64 : 8192

    /*
     * size bytes of the startup block's free range, page-aligned, for the program to map something at:
     * its address, or null once the range is used up. Addresses taken from it aren't given out again.
     */
    reserve_addresses #no_context :: fn(size: usize) -> u64? {
        state :: intrinsics.process_state()
        if state.startup_block == null {
            return null
        }
        startup :: cast[ptr[SlopOsStartup]](state.startup_block)
        total :: cast[u64]((size + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1))
        offset :: intrinsics.interlocked_exchange_add_u64(&state.mapped, total)
        if offset + total > startup.free_size || offset + total < offset {
            return null
        }
        return startup.free_base + offset
    }

    // The first thread's carrier block, before main: its stack's limit, from the startup block.
    os_prepare_carrier #no_context :: fn(carrier: ptr[mut CarrierBlock]) {
        state :: intrinsics.process_state()
        if state.startup_block == null {
            return void
        }
        startup :: cast[ptr[SlopOsStartup]](state.startup_block)
        if startup.stack_size <= STACK_RESERVE {
            return void
        }
        carrier.native_stack_limit = cast[rawptr](startup.stack_base + STACK_RESERVE)
        carrier.stack_limit = carrier.native_stack_limit
    }

    /*
     * Pages of memory, zeroed, or null: a memory object of their own, mapped in the startup block's free
     * range, with a page in front holding its handle.
     */
    map_pages #no_context :: fn(size: usize) -> rawptr {
        startup :: cast[ptr[SlopOsStartup]](intrinsics.process_state().startup_block)
        total :: cast[u64]((size + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1)) + cast[u64](PAGE_SIZE)
        address :: reserve_addresses(cast[usize](total)) or_return null
        created :: x86_64.system_call(SLOP_OS_CALL_MEMORY_CREATE, cast[u64](startup.budget), total)
        if created.rax != 0 {
            return null
        }
        mapped :: x86_64.system_call(SLOP_OS_CALL_MEMORY_MAP, created.rdx, cast[u64](startup.space), address, 0, total,
            SLOP_OS_PROTECTION_READ_WRITE)
        if mapped.rax != 0 {
            x86_64.system_call(SLOP_OS_CALL_HANDLE_CLOSE, created.rdx)
            return null
        }
        cast[ptr[mut u64]](cast[rawptr](address))^ = created.rdx
        return cast[rawptr](address + cast[u64](PAGE_SIZE))
    }

    // The pages map_pages gave, unmapped, and their memory object closed.
    unmap_pages #no_context :: fn(address: rawptr, size: usize) {
        startup :: cast[ptr[SlopOsStartup]](intrinsics.process_state().startup_block)
        start :: cast[u64](address) - cast[u64](PAGE_SIZE)
        handle :: cast[ptr[u64]](cast[rawptr](start))^
        x86_64.system_call(SLOP_OS_CALL_MEMORY_UNMAP, cast[u64](startup.space), start)
        x86_64.system_call(SLOP_OS_CALL_HANDLE_CLOSE, handle)
    }

    // No standard output or error yet
    os_write #no_context :: fn(stream: OutputStream, bytes: rawptr, count: usize) {}

    // Ends the process, with code for whoever watches it end, running nothing else.
    os_exit_process #no_context :: fn(code: u32) #never_returns {
        x86_64.system_call(SLOP_OS_CALL_PROCESS_EXIT, cast[u64](code))
        intrinsics.trap()
    }

    // The kernel's monotonic clock; there's no wall clock yet.
    SYSTEM_CLOCK :: Clock.{
        data = null,
        monotonic = system_monotonic,
        wall = system_wall,
    }

    system_monotonic :: fn(data: mut rawptr) -> MonotonicTime {
        answer :: x86_64.system_call(SLOP_OS_CALL_CLOCK_MONOTONIC)
        if answer.rax != 0 {
            return 0
        }
        return cast[MonotonicTime](answer.rdx)
    }

    system_wall :: fn(data: mut rawptr) -> Result[Instant, ClockError] {
        return .Error(.Unavailable)
    }

    /*
     * What a hosted program's main starts with: memory from the kernel, the standard logger and
     * assertion handler, and the kernel's clock. Random numbers wait for an entropy source.
     */
    HOSTED_CONTEXT :: Context.{
        allocator = PAGES_ALLOCATOR,
        logger = &STANDARD_LOGGER,
        log_level = .INFO,
        clock = &SYSTEM_CLOCK,
        random = &NO_RANDOM,
        assertion_handler = printing_assertion_handler,
        user_data = null,
        extensions = null,
    }
}

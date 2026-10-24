package runtime

import intrinsics from "base"

/*
 * What the runtime needs from SlopOS, through its system calls and its startup block: memory, the clock,
 * random bytes, the entry's parameters, and ending the process. Threads, and waiting on an address,
 * aren't here yet (wait.hsc).
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
// The startup block's version, and a grant's kinds by name (os_entry_grant): ObjectKind's values
SLOP_OS_ABI_VERSION : u32 : 1
SLOP_OS_KIND_MEMORY_BUDGET : u32 : 1
SLOP_OS_KIND_MEMORY : u32 : 3
SLOP_OS_KIND_ADDRESS_SPACE : u32 : 4
SLOP_OS_KIND_THREAD : u32 : 5
SLOP_OS_KIND_PROCESS : u32 : 6
SLOP_OS_KIND_CHANNEL : u32 : 7
SLOP_OS_KIND_PORT : u32 : 8
SLOP_OS_KIND_IRQ : u32 : 9
SLOP_OS_KIND_PLATFORM : u32 : 12
SLOP_OS_KIND_INTERCEPT : u32 : 13
SLOP_OS_KIND_DEBUG_LOG : u32 : 14
/*
 * How a process ends before its entry runs: started by a kernel of another ABI version, or without a
 * grant its entry needs (os_entry_grant)
 */
SLOP_OS_EXIT_WRONG_ABI : u32 : 125
SLOP_OS_EXIT_MISSING_GRANT : u32 : 126

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
    // Where its grants are, as bytes from its start, and a random seed for the process
    grants : u64,
    seed : u8[32],
}

// One of the startup block's grants: a label, padded with zeros, its kind, and the handle.
SlopOsGrant :: struct {
    label : u8[32],
    kind : u8,
    reserved : u8[3],
    handle : u32,
    // The protocol a channel's grant speaks, or 0
    tag : u64,
}

// A system call, and what it gives in the system ABI's three result registers, on each architecture
#if OS == .SlopOS && TARGET_ARCH == .x86_64 {
    import x86_64 from "base/intrinsics"

    SlopOsAnswer :: struct {
        tag : u64,
        first : u64,
        second : u64,
    }

    slop_os_call #no_context :: fn(number: u64, a: u64 = 0, b: u64 = 0, c: u64 = 0, d: u64 = 0, e: u64 = 0, f: u64 = 0) -> SlopOsAnswer {
        made :: x86_64.system_call(number, a, b, c, d, e, f)
        return SlopOsAnswer.{tag = made.rax, first = made.rdx, second = made.r8}
    }
}
#else_if OS == .SlopOS && TARGET_ARCH == .arm64 {
    import aarch64 from "base/intrinsics"

    SlopOsAnswer :: struct {
        tag : u64,
        first : u64,
        second : u64,
    }

    slop_os_call #no_context :: fn(number: u64, a: u64 = 0, b: u64 = 0, c: u64 = 0, d: u64 = 0, e: u64 = 0, f: u64 = 0) -> SlopOsAnswer {
        made :: aarch64.system_call(number, a, b, c, d, e, f)
        return SlopOsAnswer.{tag = made.x0, first = made.x1, second = made.x2}
    }
}

#if OS == .SlopOS && (TARGET_ARCH == .x86_64 || TARGET_ARCH == .arm64) {
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
        // A block of another version can't be read: the process ends before anything reads it
        if startup.abi_version != SLOP_OS_ABI_VERSION || cast[u64](startup.size) < cast[u64](size_of(SlopOsStartup)) {
            os_exit_process(SLOP_OS_EXIT_WRONG_ABI)
        }
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
        created :: slop_os_call(SLOP_OS_CALL_MEMORY_CREATE, cast[u64](startup.budget), total)
        if created.tag != 0 {
            return null
        }
        mapped :: slop_os_call(SLOP_OS_CALL_MEMORY_MAP, created.first, cast[u64](startup.space), address, 0, total,
            SLOP_OS_PROTECTION_READ_WRITE)
        if mapped.tag != 0 {
            slop_os_call(SLOP_OS_CALL_HANDLE_CLOSE, created.first)
            return null
        }
        cast[ptr[mut u64]](cast[rawptr](address))^ = created.first
        return cast[rawptr](address + cast[u64](PAGE_SIZE))
    }

    // The pages map_pages gave, unmapped, and their memory object closed.
    unmap_pages #no_context :: fn(address: rawptr, size: usize) {
        startup :: cast[ptr[SlopOsStartup]](intrinsics.process_state().startup_block)
        start :: cast[u64](address) - cast[u64](PAGE_SIZE)
        handle :: cast[ptr[u64]](cast[rawptr](start))^
        slop_os_call(SLOP_OS_CALL_MEMORY_UNMAP, cast[u64](startup.space), start)
        slop_os_call(SLOP_OS_CALL_HANDLE_CLOSE, handle)
    }

    /*
     * A parameter of the program's entry, which the compiler's entry asks for (docs/compilation.md, Entry
     * Parameters): the handle of the startup grant labeled name, of the kind of the type named kind, like
     * "DebugLog" or "Channel". 0 for an optional one that isn't there; a required one that isn't there, or is
     * of another kind, ends the process with SLOP_OS_EXIT_MISSING_GRANT.
     */
    os_entry_grant #no_context :: fn(name: string, kind: string, required: bool) -> u32 {
        wanted :: slop_os_kind_of(kind)
        state :: intrinsics.process_state()
        if state.startup_block != null && wanted != 0 {
            startup :: cast[ptr[SlopOsStartup]](state.startup_block)
            with {
                i : u64 = 0
            }
            loop {
                grant :: cast[ptr[SlopOsGrant]](cast[u64](startup) + startup.grants + i * cast[u64](size_of(SlopOsGrant)))
                if cast[u32](grant.kind) == wanted && label_is(&grant.label, name) {
                    return grant.handle
                }
                i += 1
            }
            while i < cast[u64](startup.grant_count)
        }
        if required {
            os_exit_process(SLOP_OS_EXIT_MISSING_GRANT)
        }
        return 0
    }

    // A grant's kind, by its type's name, or 0 for a type that isn't one.
    slop_os_kind_of #no_context :: fn(kind: string) -> u32 {
        if kind == "MemoryBudget" {
            return SLOP_OS_KIND_MEMORY_BUDGET
        }
        if kind == "Memory" {
            return SLOP_OS_KIND_MEMORY
        }
        if kind == "AddressSpace" {
            return SLOP_OS_KIND_ADDRESS_SPACE
        }
        if kind == "Thread" {
            return SLOP_OS_KIND_THREAD
        }
        if kind == "Process" {
            return SLOP_OS_KIND_PROCESS
        }
        // A channel end, untyped or speaking a protocol, and a listener, which connections arrive on
        if kind == "Channel" || kind == "Listener" {
            return SLOP_OS_KIND_CHANNEL
        }
        if kind == "Port" {
            return SLOP_OS_KIND_PORT
        }
        if kind == "Irq" {
            return SLOP_OS_KIND_IRQ
        }
        if kind == "Platform" {
            return SLOP_OS_KIND_PLATFORM
        }
        if kind == "Intercept" {
            return SLOP_OS_KIND_INTERCEPT
        }
        if kind == "DebugLog" {
            return SLOP_OS_KIND_DEBUG_LOG
        }
        return 0
    }

    // Whether a grant's label, padded with zeros, is name.
    label_is #no_context :: fn(label: ptr[u8[32]], name: string) -> bool {
        if name.count > label^.count {
            return false
        }
        for byte, i in label^ {
            if i < name.count {
                if byte != cast[u8](name[i]) {
                    return false
                }
            }
            else if byte != 0 {
                return false
            }
        }
        return true
    }

    /*
     * Random bytes from the startup block's seed: ChaCha20's keystream, each block's first half the next key
     * ("fast key erasure"), so what was given can't be worked out later. Without a seed, it traps, as
     * NO_RANDOM does.
     */
    SYSTEM_RANDOM :: Random.{
        data = null,
        fill = system_random_fill,
    }

    system_random_fill :: fn(data: mut rawptr, bytes: mut u8[]) {
        state :: intrinsics.process_state()
        loop {
            intrinsics.spin_hint()
        }
        while intrinsics.interlocked_exchange_u32(&state.random_lock, 1) != 0
        if state.random_seeded == 0 {
            seeded := false
            if state.startup_block != null {
                startup :: cast[ptr[SlopOsStartup]](state.startup_block)
                state.random_key = startup.seed
                for byte in startup.seed {
                    seeded = seeded || byte != 0
                }
            }
            if !seeded {
                intrinsics.trap()
            }
            state.random_seeded = 1
            state.random_used = 32
        }
        for &byte in bytes {
            if state.random_used >= 32 {
                chacha20_refill(&state.random_key, &state.random_output)
                state.random_used = 0
            }
            used :: cast[usize](state.random_used)
            if used < state.random_output.count {
                byte^ = state.random_output[used]
            }
            state.random_used += 1
        }
        intrinsics.atomic_store_u32_release(&state.random_lock, 0)
    }

    // One ChaCha20 block of key's keystream: its first 32 bytes become key, its last 32 output.
    chacha20_refill #no_context :: fn(key: ptr[mut u8[32]], output: ptr[mut u8[32]]) {
        state : u32[16]
        state[0] = 0x61707865
        state[1] = 0x3320646e
        state[2] = 0x79622d32
        state[3] = 0x6b206574
        for i in 0..<8 {
            word : u32 = 0
            for j in 0..<4 {
                word = word | (cast[u32](key^[(4 * i + j) % 32]) << cast[u32](8 * j))
            }
            state[(4 + i) % 16] = word
        }
        x := state
        for round in 0..<10 {
            chacha_quarter(&x, 0, 4, 8, 12)
            chacha_quarter(&x, 1, 5, 9, 13)
            chacha_quarter(&x, 2, 6, 10, 14)
            chacha_quarter(&x, 3, 7, 11, 15)
            chacha_quarter(&x, 0, 5, 10, 15)
            chacha_quarter(&x, 1, 6, 11, 12)
            chacha_quarter(&x, 2, 7, 8, 13)
            chacha_quarter(&x, 3, 4, 9, 14)
        }
        for &word, i in x {
            word^ = word^ + state[i]
        }
        for &byte, i in key^ {
            byte^ = cast[u8](x[(i / 4) % 16] >> cast[u32](8 * (i % 4)))
        }
        for &byte, i in output^ {
            byte^ = cast[u8](x[(8 + i / 4) % 16] >> cast[u32](8 * (i % 4)))
        }
    }

    chacha_quarter #no_context :: fn(x: ptr[mut u32[16]], a: usize, b: usize, c: usize, d: usize) {
        x^[a % 16] = x^[a % 16] + x^[b % 16]
        x^[d % 16] = rotate(x^[d % 16] ~ x^[a % 16], 16)
        x^[c % 16] = x^[c % 16] + x^[d % 16]
        x^[b % 16] = rotate(x^[b % 16] ~ x^[c % 16], 12)
        x^[a % 16] = x^[a % 16] + x^[b % 16]
        x^[d % 16] = rotate(x^[d % 16] ~ x^[a % 16], 8)
        x^[c % 16] = x^[c % 16] + x^[d % 16]
        x^[b % 16] = rotate(x^[b % 16] ~ x^[c % 16], 7)
    }

    rotate #no_context :: fn(value: u32, bits: u32) -> u32 {
        return (value << bits) | (value >> (32 - bits))
    }

    // No standard output or error yet
    os_write #no_context :: fn(stream: OutputStream, bytes: rawptr, count: usize) {}

    // Ends the process, with code for whoever watches it end, running nothing else.
    os_exit_process #no_context :: fn(code: u32) #never_returns {
        slop_os_call(SLOP_OS_CALL_PROCESS_EXIT, cast[u64](code))
        intrinsics.trap()
    }

    // The kernel's monotonic clock; there's no wall clock yet.
    SYSTEM_CLOCK :: Clock.{
        data = null,
        monotonic = system_monotonic,
        wall = system_wall,
    }

    system_monotonic :: fn(data: mut rawptr) -> MonotonicTime {
        answer :: slop_os_call(SLOP_OS_CALL_CLOCK_MONOTONIC)
        if answer.tag != 0 {
            return 0
        }
        return cast[MonotonicTime](answer.first)
    }

    system_wall :: fn(data: mut rawptr) -> Result[Instant, ClockError] {
        return .Error(.Unavailable)
    }

    /*
     * What a hosted program's main starts with: memory from the kernel, the standard logger and
     * assertion handler, the kernel's clock, and random bytes from the startup block's seed.
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
}

package runtime

import compiler from "base"
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
/** The system call that closes a handle: its one argument is the handle. */
SLOP_OS_CALL_HANDLE_CLOSE : u64 : 0
/** The system call that reads the kernel's monotonic clock, in nanoseconds, in its answer's first result. */
SLOP_OS_CALL_CLOCK_MONOTONIC : u64 : 7
/** The system call that makes a memory object: from a memory budget's handle, of a size in bytes. */
SLOP_OS_CALL_MEMORY_CREATE : u64 : 26
/**
 * The system call that maps a memory object: its handle, an address space's, the address, the offset into the
 * object, the size in bytes, and a protection.
 */
SLOP_OS_CALL_MEMORY_MAP : u64 : 27
/**
 * The system call that gives the calling thread its per-thread page: a memory object's handle, and the page's offset
 * in it; NO_HANDLE (0) for none.
 */
SLOP_OS_CALL_THREAD_SET_PAGE : u64 : 92

/**
 * A thread's per-thread page, which the thread writes and the kernel reads (std/os/slop_os's ThreadPage, which has to
 * match it).
 */
SlopOsThreadPage :: struct {
    /** The CPU budget the thread runs on, a handle; 0 for its process's own. */
    budget : u64,
    /** The fiber running, its Fiber's address; 0 for none. */
    fiber : u64,
}

/** The system call that unmaps what was mapped: an address space's handle and the address it was mapped at. */
SLOP_OS_CALL_MEMORY_UNMAP : u64 : 28
/** The system call that ends the process, with an exit code. */
SLOP_OS_CALL_PROCESS_EXIT : u64 : 45
/** The system call that copies bytes into anonymous memory: its handle, an offset, the bytes' address and count. */
SLOP_OS_CALL_MEMORY_WRITE : u64 : 70
/** The system call that gives a channel end's protocol tag, in its answer's first result. */
SLOP_OS_CALL_CHANNEL_TAG : u64 : 50
/** The system call that writes a message to a channel end: its handle, the bytes' address, their count, a batch. */
SLOP_OS_CALL_CHANNEL_WRITE : u64 : 18
/** The batch argument of a channel write that isn't part of a batch. */
SLOP_OS_NO_BATCH : u64 : 0xffff
/** A mapping's protection: readable only. */
SLOP_OS_PROTECTION_READ : u64 : 1
/** A mapping's protection: readable and writable, not executable. */
SLOP_OS_PROTECTION_READ_WRITE : u64 : 3
// The startup block's version, and a grant's kinds by name (os_entry_grant): ObjectKind's values
/**
 * The startup block's ABI version this runtime reads; a block of another version ends the process with
 * SLOP_OS_EXIT_WRONG_ABI before main (os_prepare_carrier).
 */
SLOP_OS_ABI_VERSION : u32 : 12
/** A grant's kind: a memory budget, which memory objects are made from. */
SLOP_OS_KIND_MEMORY_BUDGET : u32 : 1
/** A grant's kind: a CPU budget. */
SLOP_OS_KIND_CPU_BUDGET : u32 : 2
/** A grant's kind: a memory object, which can be mapped. */
SLOP_OS_KIND_MEMORY : u32 : 3
/** A grant's kind: an address space. */
SLOP_OS_KIND_ADDRESS_SPACE : u32 : 4
/** A grant's kind: a thread. */
SLOP_OS_KIND_THREAD : u32 : 5
/** A grant's kind: a process. */
SLOP_OS_KIND_PROCESS : u32 : 6
/** A grant's kind: a channel end, which a Channel, Listener, Config, AppData, Stream or Sink parameter is. */
SLOP_OS_KIND_CHANNEL : u32 : 7
/** A grant's kind: a port. */
SLOP_OS_KIND_PORT : u32 : 8
/** A grant's kind: an interrupt line. */
SLOP_OS_KIND_IRQ : u32 : 9
/** A grant's kind: a range of I/O ports. */
SLOP_OS_KIND_IO_PORT_RANGE : u32 : 10
/** A grant's kind: a DMA domain. */
SLOP_OS_KIND_DMA_DOMAIN : u32 : 11
/** A grant's kind: the platform. */
SLOP_OS_KIND_PLATFORM : u32 : 12
/** A grant's kind: an intercept. */
SLOP_OS_KIND_INTERCEPT : u32 : 13
/** A grant's kind: the kernel's debug log. */
SLOP_OS_KIND_DEBUG_LOG : u32 : 14
/** A grant's kind: a device. */
SLOP_OS_KIND_DEVICE : u32 : 15
/*
 * How a process ends before its entry runs: started by a kernel of another ABI version, or without a
 * grant its entry needs (os_entry_grant)
 */
/** The exit code of a process started with a startup block of another ABI version, or one too small to read. */
SLOP_OS_EXIT_WRONG_ABI : u32 : 125
/**
 * The exit code of a process without a grant or value its entry requires, or with one of the wrong kind, protocol
 * or type (os_entry_grant, os_entry_value).
 */
SLOP_OS_EXIT_MISSING_GRANT : u32 : 126
/**
 * The exit code of a program whose entry gave back a Result's Error (os_entry_result); its value is in the grant
 * "result", for a launcher that gave one.
 */
SLOP_OS_EXIT_ERROR : u32 : 1
/** The grant "result"'s first four bytes, "HRES" read as a little-endian u32, once os_entry_result has written it. */
SLOP_OS_RESULT_MAGIC : u32 : 0x53455248

/**
 * The header at the start of the grant "result" (docs/compilation.md, Entry Results), which the value's bytes follow,
 * written as schema_write_value writes one.
 */
SlopOsResultHeader :: struct {
    /** SLOP_OS_RESULT_MAGIC. */
    magic : u32,
    /** 1 if the value is a Result's Error, 0 otherwise. */
    error : u32,
    /** How many bytes of value follow the header. */
    size : u64,
    /** The schema hash of the entry's result type (schema_hash). */
    schema : u8[32],
}

#assert size_of(SlopOsResultHeader) == 48

/**
 * The start of SlopOS's StartupBlock, which the process's entry is given.
 *
 * Only the part the runtime reads is declared; the kernel's block may be longer, which size says.
 */
SlopOsStartup :: struct {
    /** The block's ABI version, which has to be SLOP_OS_ABI_VERSION for the rest to be read. */
    abi_version : u32,
    /** The block's size in bytes, at least this struct's for it to be read. */
    size : u32,
    /** A handle to the process itself. */
    process : u32,
    /** A handle to the process's address space, which every mapping is made in. */
    space : u32,
    /** A handle to the process's memory budget, which every memory object the runtime makes comes from. */
    budget : u32,
    /** How many SlopOsGrants are at grants. */
    grant_count : u32,
    /** The address of the range the runtime maps its own memory in, which nothing else uses (reserve_addresses). */
    free_base : u64,
    /** The size of that range, in bytes. */
    free_size : u64,
    /** The address of the first thread's stack, its lowest. */
    stack_base : u64,
    /** The size of the first thread's stack, in bytes. */
    stack_size : u64,
    /** Where the grants are, as bytes from the block's start. */
    grants : u64,
    /** A random seed for the process, which SYSTEM_RANDOM's bytes come from; all zeros means there's none. */
    seed : u8[32],
}

/**
 * The clock page: a page of memory a process is given read-only as its grant "clock", which the wall clock is read
 * from. It holds the UTC time at a monotonic reading, which its writer keeps as the system's time is read and set,
 * under a sequence it makes odd while it writes and even again once it's done; the sequence is 0 until the time is
 * known.
 */
SlopOsClockPage :: struct {
    /** Odd while the writer writes, even once it's done, and 0 until the time is known. */
    sequence : u64,
    /** Nanoseconds since 1970-01-01T00:00:00Z, at the monotonic reading at. */
    utc : i64,
    /** The monotonic clock's reading, in nanoseconds, when the time was utc. */
    at : u64,
}

/** One of the startup block's grants: a label, padded with zeros, its kind, and the handle. */
SlopOsGrant :: struct {
    /** The grant's label, like "clock" or "library:name", its bytes followed by zeros; all 32 may be used. */
    label : u8[32],
    /** What the handle is: one of the SLOP_OS_KIND_ values. */
    kind : u8,
    /** Unused, zero. */
    reserved : u8[3],
    /** The handle the grant gives, which the process owns. */
    handle : u32,
}

// A system call, and what it gives in the system ABI's three result registers, on each architecture
#if OS == .SlopOS && TARGET_ARCH == .x86_64 {
    import x86_64 from "base/intrinsics"

    /** What a system call gives back, in the system ABI's three result registers. */
    SlopOsAnswer :: struct {
        /** 0 if the call succeeded, or the kernel's error code. */
        tag : u64,
        /** The call's first result, like a handle it made; what it means is the call's. */
        first : u64,
        /** The call's second result, if it has one. */
        second : u64,
    }

    /**
     * Make a system call.
     *
     * @param number The call's number, one of the SLOP_OS_CALL_ values.
     * @param a The call's first argument, or 0 if it takes fewer.
     * @param b The call's second argument, or 0 if it takes fewer.
     * @param c The call's third argument, or 0 if it takes fewer.
     * @param d The call's fourth argument, or 0 if it takes fewer.
     * @param e The call's fifth argument, or 0 if it takes fewer.
     * @param f The call's sixth argument, or 0 if it takes fewer.
     * @return What the kernel gave back: its tag 0 on success or an error code, and the call's results.
     */
    slop_os_call #no_context :: fn(number: u64, a: u64 = 0, b: u64 = 0, c: u64 = 0, d: u64 = 0, e: u64 = 0, f: u64 = 0) -> SlopOsAnswer {
        made :: x86_64.system_call(number, a, b, c, d, e, f)
        return SlopOsAnswer.{tag = made.rax, first = made.rdx, second = made.r8}
    }
}
#else_if OS == .SlopOS && TARGET_ARCH == .arm64 {
    import aarch64 from "base/intrinsics"

    /** What a system call gives back, in the system ABI's three result registers. */
    SlopOsAnswer :: struct {
        /** 0 if the call succeeded, or the kernel's error code. */
        tag : u64,
        /** The call's first result, like a handle it made; what it means is the call's. */
        first : u64,
        /** The call's second result, if it has one. */
        second : u64,
    }

    /**
     * Make a system call.
     *
     * @param number The call's number, one of the SLOP_OS_CALL_ values.
     * @param a The call's first argument, or 0 if it takes fewer.
     * @param b The call's second argument, or 0 if it takes fewer.
     * @param c The call's third argument, or 0 if it takes fewer.
     * @param d The call's fourth argument, or 0 if it takes fewer.
     * @param e The call's fifth argument, or 0 if it takes fewer.
     * @param f The call's sixth argument, or 0 if it takes fewer.
     * @return What the kernel gave back: its tag 0 on success or an error code, and the call's results.
     */
    slop_os_call #no_context :: fn(number: u64, a: u64 = 0, b: u64 = 0, c: u64 = 0, d: u64 = 0, e: u64 = 0, f: u64 = 0) -> SlopOsAnswer {
        made :: aarch64.system_call(number, a, b, c, d, e, f)
        return SlopOsAnswer.{tag = made.x0, first = made.x1, second = made.x2}
    }
}

#if OS == .SlopOS && (TARGET_ARCH == .x86_64 || TARGET_ARCH == .arm64) {
    /** The size of a page, in bytes: what mappings are rounded up to. */
    PAGE_SIZE : usize : 4096
    /**
     * Room left below a thread's stack limit, in bytes, for what runs before a stack check can, like an interrupted
     * call.
     */
    STACK_RESERVE : u64 : 8192

    /**
     * Take addresses from the startup block's free range, for the program to map something at.
     *
     * Addresses taken from it aren't given out again, even when what was to be mapped there fails to be; safe to call
     * from several threads at once.
     *
     * @param size How many bytes are wanted, rounded up to a whole number of pages; 0 takes none and gives the
     *     range's next address.
     * @return The page-aligned address of size bytes nothing else has, or null if the process has no startup block or
     *     the range hasn't size bytes left.
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

    /**
     * Prepare the first thread's carrier block, before main: its stack's limit, from the startup block.
     *
     * The limit is STACK_RESERVE bytes above the stack's base. It also starts serving the lifecycle channel
     * (slop_os_lifecycle.hsc). Without a startup block, or with a stack no bigger than STACK_RESERVE, the carrier is
     * left as it is and the lifecycle channel isn't served.
     *
     * @param carrier The first thread's carrier block, whose native_stack_limit and stack_limit are set.
     * @note A startup block of another ABI version, or smaller than SlopOsStartup, ends the process with
     *     SLOP_OS_EXIT_WRONG_ABI, so nothing reads what it can't.
     */
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
        // The lifecycle channel served from here on, before main (slop_os_lifecycle.hsc)
        slop_os_start_lifecycle()
    }

    /**
     * Map pages of memory, zeroed: a memory object of their own, made from the process's memory budget and mapped in
     * the startup block's free range, with a page in front holding its handle.
     *
     * @param size How many bytes are wanted, rounded up to a whole number of pages; one page more is taken for the
     *     handle.
     * @return The address of the first page after the handle's, page-aligned, which unmap_pages gives back; or null if
     *     the free range is used up, or the kernel wouldn't make or map the memory. The free range's addresses taken
     *     for a call that fails aren't given back.
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

    /**
     * Unmap the pages map_pages gave, and close their memory object, the handle page's too.
     *
     * Their addresses aren't given back to the free range, so they're never mapped again.
     *
     * @param address What map_pages returned; nothing else, and not null.
     * @param size The size given to map_pages; unused, as the whole mapping goes at once.
     */
    unmap_pages #no_context :: fn(address: rawptr, size: usize) {
        startup :: cast[ptr[SlopOsStartup]](intrinsics.process_state().startup_block)
        start :: cast[u64](address) - cast[u64](PAGE_SIZE)
        handle :: cast[ptr[u64]](cast[rawptr](start))^
        slop_os_call(SLOP_OS_CALL_MEMORY_UNMAP, cast[u64](startup.space), start)
        slop_os_call(SLOP_OS_CALL_HANDLE_CLOSE, handle)
    }

    /**
     * Find a handle parameter of the program's entry, which the compiler's entry asks for (docs/compilation.md, Entry
     * Parameters): the startup grant with its label, kind and protocol.
     *
     * The runtime asks for grants of its own this way too, like "clock", "events" and "library:" ones. The first grant
     * that matches is taken.
     *
     * @param name The grant's label, at most 32 bytes; a longer one never matches.
     * @param kind The name of the parameter's type, like "DebugLog" or "Channel", which says the grant's kind
     *     (slop_os_kind_of); a name that isn't a kind's never matches.
     * @param protocol For a type generic over a protocol, its generic argument's name, which the channel's tag has to
     *     be (protocol_of, speaks); empty for none.
     * @param required Whether the process ends without it. If true, a grant that isn't there, or is of another kind or
     *     protocol, ends the process with SLOP_OS_EXIT_MISSING_GRANT.
     * @return The grant's handle, which the process owns; or 0, when required is false, if there's no such grant or no
     *     startup block.
     */
    os_entry_grant #no_context :: fn(name: string, kind: string, protocol: string, required: bool) -> u32 {
        wanted :: slop_os_kind_of(kind)
        state :: intrinsics.process_state()
        if state.startup_block != null && wanted != 0 {
            startup :: cast[ptr[SlopOsStartup]](state.startup_block)
            // Checked before each grant is read, so a block with none reads nothing past its end
            i : u64 = 0
            loop {
                if i >= cast[u64](startup.grant_count) {
                    break
                }
                grant :: cast[ptr[SlopOsGrant]](cast[u64](startup) + startup.grants + i * cast[u64](size_of(SlopOsGrant)))
                if cast[u32](grant.kind) == wanted && label_is(&grant.label, name) && speaks(grant.handle, protocol_of(kind, protocol)) {
                    return grant.handle
                }
                i += 1
            }
        }
        if required {
            os_exit_process(SLOP_OS_EXIT_MISSING_GRANT)
        }
        return 0
    }

    /**
     * Name the protocol a grant of a kind speaks: its generic argument's, or for a Config[T], a connection to a value
     * of type T, the config protocol's, ConfigValue, whatever T is (the SlopOS repository's decisions 0107, 0109); for
     * an AppData, an installation's data directory, Dir's (0113); for a Stream[T] or a Sink[T], a stream's ends, the
     * stream protocol's, whatever T is.
     *
     * @param kind The name of the parameter's type, like "Config" or "Channel".
     * @param argument Its generic argument's name, or empty for a type that isn't generic.
     * @return The protocol's name: "ConfigValue", "Dir" or "Stream" for those kinds, and argument itself for any
     *     other, so empty when argument is.
     */
    protocol_of #no_context :: fn(kind: string, argument: string) -> string {
        return if kind == "Config" { "ConfigValue" } else if kind == "AppData" { "Dir" } else if kind == "Stream" || kind == "Sink" { "Stream" }
            else { argument }
    }

    /**
     * Check whether a channel end's tag is the protocol's, by its name: FNV-1a of the name, as std/os's protocol_tag
     * says. Anything else has no protocol to speak.
     *
     * @param handle The handle, which the kernel is asked for its tag; one that isn't a channel's has none.
     * @param protocol The protocol's name, or empty for no protocol, which every handle speaks.
     * @return True if protocol is empty, or the kernel gave the handle's tag and it's the name's hash; false if the
     *     tag differs, or the kernel refused, as it does for a handle that isn't a channel end.
     */
    speaks #no_context :: fn(handle: u32, protocol: string) -> bool {
        if protocol.count == 0 {
            return true
        }
        hash : u64 = 0xcbf29ce484222325
        for character in protocol {
            hash = (hash ~ cast[u64](cast[u8](character))) * 0x100000001b3
        }
        answer :: slop_os_call(SLOP_OS_CALL_CHANNEL_TAG, cast[u64](handle))
        return answer.tag == 0 && answer.first == hash
    }

    /**
     * Find a grant's kind, by the name of its parameter's type.
     *
     * @param kind The type's name, like "Memory" or "Channel"; Listener, Config, AppData, Stream and Sink are channel
     *     ends too.
     * @return One of the SLOP_OS_KIND_ values, or 0 for a name that isn't a kind's.
     */
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
        // A channel end, untyped or speaking a protocol, a listener, which connections arrive on, a Config[T] and an AppData, channels
        if kind == "Channel" || kind == "Listener" || kind == "Config" || kind == "AppData" || kind == "Stream" || kind == "Sink" {
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
        if kind == "DmaDomain" {
            return SLOP_OS_KIND_DMA_DOMAIN
        }
        if kind == "Device" {
            return SLOP_OS_KIND_DEVICE
        }
        if kind == "CpuBudget" {
            return SLOP_OS_KIND_CPU_BUDGET
        }
        if kind == "IoPortRange" {
            return SLOP_OS_KIND_IO_PORT_RANGE
        }
        return 0
    }

    /**
     * Check whether a grant's label, padded with zeros, is a name.
     *
     * @param label The grant's label: the name's bytes, then zeros to its end.
     * @param name The name to compare with, which matches only exactly; empty matches an all-zero label.
     * @return True if the label's bytes are the name's and every byte after them is 0; false if they differ, or the
     *     name is longer than 32 bytes.
     */
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

    /**
     * Random bytes from the startup block's seed: ChaCha20's keystream, each block's first half the next key
     * ("fast key erasure"), so what was given can't be worked out later. Without a seed, it traps, as
     * NO_RANDOM does.
     */
    SYSTEM_RANDOM :: Random.{
        data = null,
        fill = system_random_fill,
    }

    /**
     * Fill bytes with random bytes, SYSTEM_RANDOM's fill.
     *
     * The first call keys the generator from the startup block's seed; every call after takes the bytes left of the
     * last block before making more. A lock, spun on, makes it safe from several threads at once.
     *
     * @param data SYSTEM_RANDOM's data, null; unused, as the state is the process's (ProcessState's random_ fields).
     * @param bytes Where the random bytes go, every one of them overwritten; empty takes none.
     * @note Traps if the process has no startup block, or its seed is all zeros, as NO_RANDOM does: there's nothing
     *     random to give.
     */
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

    /**
     * Make one ChaCha20 block of a key's keystream: its first 32 bytes become the key, its last 32 the output.
     *
     * The nonce and counter are always 0, which is safe only because the key is replaced each time ("fast key
     * erasure"): no key is ever used for two blocks.
     *
     * @param key The 256-bit key, its words little-endian; replaced by the block's first half.
     * @param output Where the block's second half goes, the random bytes to give out.
     */
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

    /**
     * Apply ChaCha20's quarter round to four of the state's words.
     *
     * @param x The state's 16 words, four of them changed in place.
     * @param a The first word's index, 0 to 15; larger ones wrap, as each is taken modulo 16.
     * @param b The second word's index, 0 to 15.
     * @param c The third word's index, 0 to 15.
     * @param d The fourth word's index, 0 to 15.
     */
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

    /**
     * Rotate a word left.
     *
     * @param value The word to rotate.
     * @param bits How far, from 1 to 31; 0 or 32 and above shift by the width, which isn't a rotation.
     * @return The word with its bits moved left by bits, those shifted out of the top coming in at the bottom.
     */
    rotate #no_context :: fn(value: u32, bits: u32) -> u32 {
        return (value << bits) | (value >> (32 - bits))
    }

    /**
     * Write bytes to standard output or error, which SlopOS doesn't give a process yet: nothing is written.
     *
     * @param stream Which stream they're for; ignored.
     * @param bytes The bytes' address; not read.
     * @param count How many bytes there are; ignored.
     */
    os_write #no_context :: fn(stream: OutputStream, bytes: rawptr, count: usize) {}

    /**
     * End the process, running nothing else: no deferred code, no other thread.
     *
     * @param code The exit code, for whoever watches the process end.
     */
    os_exit_process #no_context :: fn(code: u32) #never_returns {
        slop_os_call(SLOP_OS_CALL_PROCESS_EXIT, cast[u64](code))
        intrinsics.trap()
    }

    /** The kernel's monotonic clock, and the wall clock from the clock page, if the process was given one. */
    SYSTEM_CLOCK :: Clock.{
        data = null,
        monotonic = system_monotonic,
        wall = system_wall,
    }

    /**
     * Read the kernel's monotonic clock, SYSTEM_CLOCK's monotonic.
     *
     * @param data SYSTEM_CLOCK's data, null; unused.
     * @return Nanoseconds since a point the kernel chose, which only grow; 0 if the kernel refused the call.
     */
    system_monotonic :: fn(data: mut rawptr) -> MonotonicTime {
        answer :: slop_os_call(SLOP_OS_CALL_CLOCK_MONOTONIC)
        if answer.tag != 0 {
            return 0
        }
        return cast[MonotonicTime](answer.first)
    }

    /**
     * Read the time on the clock page (SlopOsClockPage), SYSTEM_CLOCK's wall, read again if it was being written.
     *
     * The page's UTC time is moved on by how far the monotonic clock has since. It spins while the page is being
     * written, which its writer does briefly.
     *
     * @param data SYSTEM_CLOCK's data, null; passed on to system_monotonic.
     * @return The UTC time now, its nanos from 0 to 999,999,999 and its seconds rounded down, so negative before 1970.
     * @error Unavailable The process wasn't given a clock page.
     * @error NotSynchronized The page's writer doesn't know the time yet.
     */
    system_wall :: fn(data: mut rawptr) -> Result[Instant, ClockError] {
        page :: clock_page() or_return .Error(.Unavailable)
        loop {
            before :: intrinsics.atomic_load_u64_acquire(&page.sequence)
            if before == 0 {
                return .Error(.NotSynchronized)
            }
            if (before & 1) != 0 {
                continue
            }
            utc :: intrinsics.atomic_load_i64_no_fence(&page.utc)
            at :: intrinsics.atomic_load_u64_no_fence(&page.at)
            intrinsics.fence_acquire()
            if intrinsics.atomic_load_u64_no_fence(&page.sequence) != before {
                continue
            }
            nanoseconds :: utc + (cast[i64](system_monotonic(data)) - cast[i64](at))
            seconds := nanoseconds / 1_000_000_000
            nanos := nanoseconds % 1_000_000_000
            if nanos < 0 {
                seconds -= 1
                nanos += 1_000_000_000
            }
            return .Ok(Instant.{seconds = seconds, nanos = cast[u32](nanos)})
        }
    }

    /**
     * Find the clock page, mapped read-only the first time it's asked for.
     *
     * Safe from several threads at once: one maps it, and the others wait for it to.
     *
     * @return The page, mapped for the rest of the process's life; or null if the process wasn't given one or it
     *     couldn't be mapped, which every later call gives too.
     */
    clock_page #no_context :: fn() -> ptr[SlopOsClockPage]? {
        state :: intrinsics.process_state()
        loop {
            match intrinsics.atomic_load_u32_acquire(&state.clock_state) {
                case CLOCK_PAGE_MAPPED => return cast[ptr[SlopOsClockPage]](state.clock_page)
                case CLOCK_PAGE_NONE => return null
                case CLOCK_PAGE_MAPPING => continue
                case _ => {}
            }
            _, claimed :: intrinsics.interlocked_compare_exchange_u32(&state.clock_state, CLOCK_PAGE_MAPPING, CLOCK_PAGE_UNTRIED)
            if claimed {
                break
            }
        }
        state.clock_page = map_clock_page()
        if state.clock_page == null {
            intrinsics.atomic_store_u32_release(&state.clock_state, CLOCK_PAGE_NONE)
            return null
        }
        intrinsics.atomic_store_u32_release(&state.clock_state, CLOCK_PAGE_MAPPED)
        return cast[ptr[SlopOsClockPage]](state.clock_page)
    }

    /**
     * Read the locale's name from the process's grant "locale", a page holding the name up to its first zero, read
     * the first time it's asked for.
     *
     * Safe from several threads at once: one reads it, and the others wait for it to.
     *
     * @return The name, like "en-GB", at most LOCALE_NAME_BYTES bytes of it, kept in ProcessState for the rest of the
     *     process's life; empty if the process wasn't given the grant or it couldn't be mapped, which every later call
     *     gives too.
     */
    slop_os_locale_name :: fn() -> string {
        state :: intrinsics.process_state()
        loop {
            match intrinsics.atomic_load_u32_acquire(&state.locale_state) {
                case CLOCK_PAGE_MAPPED => return string_of(&state.locale_name[0], state.locale_name_count)
                case CLOCK_PAGE_NONE => return ""
                case CLOCK_PAGE_MAPPING => continue
                case _ => {}
            }
            _, claimed :: intrinsics.interlocked_compare_exchange_u32(&state.locale_state, CLOCK_PAGE_MAPPING, CLOCK_PAGE_UNTRIED)
            if claimed {
                break
            }
        }
        handle :: os_entry_grant("locale", "Memory", "", false)
        address :: if handle == 0 || state.startup_block == null { cast[u64](0) } else { reserve_addresses(PAGE_SIZE) or_else 0 }
        if address == 0 {
            intrinsics.atomic_store_u32_release(&state.locale_state, CLOCK_PAGE_NONE)
            return ""
        }
        startup :: cast[ptr[SlopOsStartup]](state.startup_block)
        mapped :: slop_os_call(SLOP_OS_CALL_MEMORY_MAP, cast[u64](handle), cast[u64](startup.space), address, 0, cast[u64](PAGE_SIZE),
            SLOP_OS_PROTECTION_READ)
        if mapped.tag != 0 {
            intrinsics.atomic_store_u32_release(&state.locale_state, CLOCK_PAGE_NONE)
            return ""
        }
        page :: view_of(cast[ptr[u8]](address), LOCALE_NAME_BYTES)
        count : usize = 0
        for byte in page {
            if byte == 0 || count >= state.locale_name.count {
                break
            }
            state.locale_name[count] = byte
            count += 1
        }
        state.locale_name_count = count
        intrinsics.atomic_store_u32_release(&state.locale_state, CLOCK_PAGE_MAPPED)
        return string_of(&state.locale_name[0], state.locale_name_count)
    }

    /**
     * Map the process's grant "clock" read-only, at addresses from the free range; clock_page calls it once.
     *
     * @return The page's address, mapped for the rest of the process's life; or null if there's no startup block, no
     *     such grant, no room left in the free range, or the kernel wouldn't map it.
     */
    map_clock_page #no_context :: fn() -> rawptr {
        state :: intrinsics.process_state()
        if state.startup_block == null {
            return null
        }
        startup :: cast[ptr[SlopOsStartup]](state.startup_block)
        handle :: os_entry_grant("clock", "Memory", "", false)
        if handle == 0 {
            return null
        }
        address :: reserve_addresses(PAGE_SIZE) or_return null
        mapped :: slop_os_call(SLOP_OS_CALL_MEMORY_MAP, cast[u64](handle), cast[u64](startup.space), address, 0, cast[u64](PAGE_SIZE),
            SLOP_OS_PROTECTION_READ)
        if mapped.tag != 0 {
            return null
        }
        return cast[rawptr](address)
    }

    /*
     * The grant "arguments" (docs/compilation.md, Entry Parameters): the values of an entry's parameters that aren't
     * handles, which whoever launched the program wrote (std/os's launch). Its header, then each value: the header of
     * its parameter, the parameter's name, and the value as schema_write_value writes one, each padded to 8 bytes.
     */
    /** The grant "arguments"' first four bytes, "HARG" read as a little-endian u32; anything else isn't read. */
    SLOP_OS_ARGUMENTS_MAGIC : u32 : 0x47524148
    /** The header at the start of the grant "arguments", which a SlopOsArgument and its bytes follow for each value. */
    SlopOsArguments :: struct {
        /** SLOP_OS_ARGUMENTS_MAGIC. */
        magic : u32,
        /** How many values follow. */
        count : u32,
        /** Every byte of it, the header's too; more than 16 MiB, rounded up to pages, isn't mapped. */
        total : u64,
    }

    /** A value's header: its parameter's name's bytes, its own, and its type's schema hash. */
    SlopOsArgument :: struct {
        /** How many bytes the parameter's name has, which follow this header, padded to 8. */
        name_bytes : u32,
        /** How many bytes the value has, as schema_write_value writes it, which follow the name, padded to 8. */
        value_bytes : u32,
        /** The schema hash of the type the value was written as (schema_hash). */
        hash : u8[32],
    }

    /**
     * Read a parameter of the program's entry that isn't a handle, which the compiler's entry asks for
     * (docs/compilation.md, Entry Parameters): the value of its name in the grant "arguments", if it was written as a
     * value of type, copied to the heap with its pointers made pointers again, and stored at into.
     *
     * An optional's is None when it isn't there, or isn't of its type; a required one that isn't there, or isn't of
     * its type, ends the process with SLOP_OS_EXIT_MISSING_GRANT. It's meant for the entry, before other threads run:
     * reading the grant the first time isn't guarded against another thread doing it at once.
     *
     * @param name The parameter's name, as it was written in the grant.
     * @param type The parameter's type. An optional (a union of Some with one type and None, that isn't null for
     *     None) is looked for as its Some's type, and is the only kind that can be missing.
     * @param into Where the value goes: room for a value of type, which is overwritten; for an optional, its tag and
     *     its Some's value. What the value points to is on the heap, the program's from then on.
     */
    os_entry_value :: fn(name: string, type: ptr[compiler.TypeInfo], into: rawptr) {
        // An optional's value is its Some's
        held := type
        optional : ptr[compiler.TypeInfoUnion]? = null
        some : usize = 0
        none : usize = 0
        info :: schema_unaliased(type)
        if info.variant == .UNION {
            union_info :: cast[ptr[compiler.TypeInfoUnion]](info)
            for each, i in union_info.variants {
                if each.name == "Some" && each.types.count == 1 {
                    some = i
                    held = each.types[0]
                    optional = union_info
                }
                else if each.name == "None" {
                    none = i
                }
            }
            if union_info.null_is_none || union_info.variants.count != 2 {
                optional = null
                held = type
            }
        }
        match optional {
            case Some(union_info) => {
                offset :: if some < union_info.variants.count && union_info.variants[some].offsets.count > 0 { union_info.variants[some].offsets[0] }
                    else { cast[usize](0) }
                found := false
                match slop_os_argument(name, held) {
                    case Some(bytes) => found = schema_read_value(bytes, held, cast[rawptr](cast[uintptr](into) + cast[uintptr](offset)))
                    case None => {}
                }
                tag_size :: match union_info.tag_type {
                    case Some(tag) => tag.size
                    case None => cast[usize](0)
                }
                tag :: if found { some } else { none }
                tag_bytes :: view_of(cast[ptr[mut u8]](into), tag_size)
                for i in cast[usize](0)..<tag_bytes.count {
                    tag_bytes[i] = cast[u8]((cast[u64](tag) >> (8 * i)) & 0xff)
                }
            }
            case None => {
                bytes :: slop_os_argument(name, type) or_else u8.[]
                if bytes.count == 0 || !schema_read_value(bytes, type, into) {
                    os_exit_process(SLOP_OS_EXIT_MISSING_GRANT)
                }
            }
        }
    }

    /**
     * Give the value the program's entry gave back to its launcher, which the compiler's entry calls for a main that
     * gives back anything but an integer (docs/compilation.md, Entry Results): written in the grant "result", if the
     * launcher gave one, and the process's exit code made from it.
     *
     * The grant is a memory object the launcher can read: SlopOsResultHeader, then the value as schema_write_value
     * writes one. A value that doesn't fit, or can't be written for want of memory, leaves the grant as it was; the exit
     * code still says Ok or Error.
     *
     * @param type The entry's result type.
     * @param value Where the result is: type.size bytes, read and not kept.
     * @return SLOP_OS_EXIT_ERROR for a Result's Error (a union whose variant is named Error); 0 otherwise.
     */
    os_entry_result :: fn(type: ptr[compiler.TypeInfo], value: rawptr) -> u32 {
        error :: is_error_result(type, value)
        code :: if error { SLOP_OS_EXIT_ERROR } else { cast[u32](0) }
        handle :: os_entry_grant("result", "Memory", "", false)
        if handle == 0 {
            return code
        }
        bytes : u8[..]
        defer array_free(&bytes)
        if schema_try_write_value_at(value, type, &bytes) != null {
            return code
        }
        header := SlopOsResultHeader.{magic = SLOP_OS_RESULT_MAGIC, error = if error { cast[u32](1) } else { cast[u32](0) },
            size = cast[u64](bytes.count), schema = schema_hash(type)}
        // The value first, so a launcher never finds a header before what it says is there
        if bytes.count > 0 {
            written :: slop_os_call(SLOP_OS_CALL_MEMORY_WRITE, cast[u64](handle), cast[u64](size_of(SlopOsResultHeader)),
                cast[u64](cast[uintptr](bytes.data)), cast[u64](bytes.count))
            if written.tag != 0 {
                return code
            }
        }
        _ = slop_os_call(SLOP_OS_CALL_MEMORY_WRITE, cast[u64](handle), 0, cast[u64](cast[uintptr](&header)), cast[u64](size_of(SlopOsResultHeader)))
        return code
    }

    /**
     * Tell whether an entry's result is a Result's Error: a union with a variant named Error, holding that one.
     *
     * @param type The result's type, aliases followed.
     * @param value Where the result is.
     * @return True if its tag is its Error variant's; false for any other type or variant.
     */
    is_error_result :: fn(type: ptr[compiler.TypeInfo], value: rawptr) -> bool {
        info :: schema_unaliased(type)
        if info.variant != .UNION {
            return false
        }
        union_info :: cast[ptr[compiler.TypeInfoUnion]](info)
        tag_type :: union_info.tag_type or_return false
        tag := cast[u64](0)
        for i in cast[usize](0)..<tag_type.size {
            tag |= cast[u64](cast[ptr[u8]](cast[uintptr](value) + cast[uintptr](i))^) << (8 * cast[u64](i))
        }
        for each, i in union_info.variants {
            if cast[u64](i) == tag {
                return each.name == "Error"
            }
        }
        return false
    }

    /**
     * Find the value written for a parameter in the grant "arguments", if it's of a type.
     *
     * @param name The parameter's name. Only the first value written with that name is looked at.
     * @param type The type it has to have been written as, compared by schema hash.
     * @return The value's bytes, as schema_write_value wrote them, a view of the grant, which stays mapped for the
     *     rest of the process's life; or null if there's no grant, it's malformed or cut short, no value has the
     *     name, or the first that has it was written as another type.
     */
    slop_os_argument :: fn(name: string, type: ptr[compiler.TypeInfo]) -> u8[]? {
        page :: slop_os_arguments() or_return null
        if page.count < size_of(SlopOsArguments) {
            return null
        }
        base :: cast[u64](cast[uintptr](page.data))
        header :: cast[ptr[SlopOsArguments]](cast[uintptr](base))
        if header.magic != SLOP_OS_ARGUMENTS_MAGIC {
            return null
        }
        expected :: schema_hash(type)
        at := size_of(SlopOsArguments)
        for i in cast[u32](0)..<header.count {
            if at + size_of(SlopOsArgument) > page.count {
                return null
            }
            argument :: cast[ptr[SlopOsArgument]](cast[uintptr](base + cast[u64](at)))
            name_at :: at + size_of(SlopOsArgument)
            value_at :: name_at + slop_os_padded(cast[usize](argument.name_bytes))
            next :: value_at + slop_os_padded(cast[usize](argument.value_bytes))
            if next > page.count || name_at + cast[usize](argument.name_bytes) > page.count {
                return null
            }
            if string_of(cast[ptr[u8]](cast[uintptr](base + cast[u64](name_at))), cast[usize](argument.name_bytes)) == name {
                for byte, j in expected {
                    if j >= argument.hash.count || argument.hash[j] != byte {
                        return null
                    }
                }
                return view_of(cast[ptr[u8]](cast[uintptr](base + cast[u64](value_at))), cast[usize](argument.value_bytes))
            }
            at = next
        }
        return null
    }

    /**
     * Round a count of bytes up to a multiple of 8, as each name and value in the grant "arguments" is padded.
     *
     * @param count The count, in bytes; within 7 of usize's largest, it wraps.
     * @return The smallest multiple of 8 that's at least count; 0 for 0.
     */
    slop_os_padded #no_context :: fn(count: usize) -> usize {
        return (count + 7) & ~cast[usize](7)
    }

    /**
     * Find the grant "arguments", mapped read-only the first time it's asked for.
     *
     * Its first page is mapped to read the header, then, if it's longer, the whole of it again elsewhere. Only the
     * first call tries; it isn't guarded against another thread making the first call at once.
     *
     * @return All of its bytes, its header's too, mapped for the rest of the process's life; or null if there's no
     *     such grant, no room in the free range, the kernel wouldn't map it, or its header's magic is wrong or its
     *     total is 0 or more than 16 MiB, which every later call gives too.
     */
    slop_os_arguments :: fn() -> u8[]? {
        state :: intrinsics.process_state()
        if !state.entry_arguments_tried {
            state.entry_arguments_tried = true
            handle :: os_entry_grant("arguments", "Memory", "", false)
            if handle == 0 || state.startup_block == null {
                return null
            }
            startup :: cast[ptr[SlopOsStartup]](state.startup_block)
            // Its header first, which says how much more there is
            first :: reserve_addresses(PAGE_SIZE) or_return null
            if slop_os_call(SLOP_OS_CALL_MEMORY_MAP, cast[u64](handle), cast[u64](startup.space), first, 0, cast[u64](PAGE_SIZE),
                SLOP_OS_PROTECTION_READ).tag != 0 {
                return null
            }
            header :: cast[ptr[SlopOsArguments]](cast[uintptr](first))
            total :: (header.total + cast[u64](PAGE_SIZE) - 1) & ~(cast[u64](PAGE_SIZE) - 1)
            if header.magic != SLOP_OS_ARGUMENTS_MAGIC || total == 0 || total > cast[u64](1) << 24 {
                return null
            }
            address := first
            if total > cast[u64](PAGE_SIZE) {
                address = reserve_addresses(cast[usize](total)) or_return null
                if slop_os_call(SLOP_OS_CALL_MEMORY_MAP, cast[u64](handle), cast[u64](startup.space), address, 0, total,
                    SLOP_OS_PROTECTION_READ).tag != 0 {
                    return null
                }
            }
            state.entry_arguments = cast[rawptr](cast[uintptr](address))
            state.entry_arguments_bytes = header.total
        }
        if state.entry_arguments == null {
            return null
        }
        return view_of(cast[ptr[u8]](state.entry_arguments), cast[usize](state.entry_arguments_bytes))
    }

    /**
     * What a hosted program's main starts with: memory from the kernel, the logger that writes records for the
     * events service (slop_os_events.hsc), the standard assertion handler, the kernel's clock, and random bytes from
     * the startup block's seed.
     */
    HOSTED_CONTEXT :: Context.{
        allocator = PAGES_ALLOCATOR,
        logger = &SLOP_OS_LOGGER,
        log_level = .INFO,
        clock = &SYSTEM_CLOCK,
        random = &SYSTEM_RANDOM,
        assertion_handler = printing_assertion_handler,
        user_data = null,
        extensions = null,
    }
}

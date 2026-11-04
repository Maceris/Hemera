package slop_os

import intrinsics from "base"
import runtime from "base"

/**
 * What a process starts with (knowledge/design/system-abi.md §6, docs/specs/programs.md): its first
 * thread's argument points at this, in memory its loader mapped into it, read-only, which stays for the
 * life of the process. The entry point's typed arguments are still to come (roadmap M6, 6d).
 */
StartupBlock :: struct {
    /**
     * The ABI_VERSION of the kernel that started the process; base's runtime ends a process whose block has another
     * with EXIT_WRONG_ABI, before main.
     */
    abi_version : u32,
    /** The size of StartupBlock as its writer knew it, in bytes; fields past it weren't written. */
    size : u32,
    /** The process itself, a handle of its own. */
    process : Process,
    /** The process's address space. */
    space : AddressSpace,
    /** The process's memory budget, which pays for what it makes. */
    budget : MemoryBudget,
    /** How many grants there are, from 0. */
    grant_count : u32,
    /**
     * Where the process's runtime maps its own memory, its heap and its threads' stacks: free_size bytes from
     * free_base, page-aligned, which the loader put at a random place and nothing else in the space uses.
     */
    free_base : u64,
    /** How many bytes the free range from free_base has, a multiple of the page size. */
    free_size : u64,
    /** The lowest address of the first thread's stack, whose top its stack pointer started near. */
    stack_base : u64,
    /** How many bytes the first thread's stack has, from stack_base. */
    stack_size : u64,
    /** Where the grants are: grant_count Grants, this many bytes from the block's start. */
    grants : u64,
    /**
     * A random seed, which base's runtime seeds context.random from: the boot's for the root task, and one its
     * loader drew for any other process (decisions/0012, 0068).
     */
    seed : u8[32],
    /** What the CPU the process runs on can do, as the kernel found. */
    cpu_features : CpuFeatures,
}

/** The most bytes of a grant's label; a shorter label is padded with zeros. */
GRANT_LABEL_SIZE :: 32

/**
 * A handle the process starts with, besides its own, and what it's for: a label like "platform",
 * "debug_log" or "module:hello.elf", in UTF-8, padded with zeros. An entry parameter's grant is labeled
 * with the parameter's name (decisions 0044, 0068).
 */
Grant :: struct {
    /** The label, UTF-8, padded with zeros; one of GRANT_LABEL_SIZE bytes has no zero after it (label_of). */
    label : u8[GRANT_LABEL_SIZE],
    /** The kind of object the handle is to. */
    kind : ObjectKind,
    /** Unused, so handle is aligned; zeros. */
    reserved : u8[3],
    /** The handle, in the process's table, the process's from the start. */
    handle : Handle,
}

#assert size_of(Grant) == 40

/**
 * The root task's "firmware" grant (the SlopOS repository's decisions 0070, 0073): the firmware tables, which the
 * kernel copies into read-only memory before the bootloader's memory is reclaimed. A FirmwareTables, then its count
 * FirmwareTable entries, then the tables, each at its offset from the start. ACPI's are the RSDP ("RSDP"), every
 * table its XSDT or RSDT lists, and the FADT's DSDT and FACS; a device tree's is its blob ("DTB "). Then, on both, the
 * kernel's own "RAM ", PhysicalRanges of the RAM it owns. physical is where the table was (0 for "RAM "), which ACPI's
 * tables use to point at one another.
 */
FirmwareTables :: struct {
    /** FIRMWARE_MAGIC, so a grant that isn't firmware tables can be told. */
    magic : u64,
    /** Whether the machine described itself with ACPI or a device tree. */
    kind : FirmwareKind,
    /** How many FirmwareTable entries follow this header. */
    count : u32,
}

/** "FWTABLES", in its bytes: a FirmwareTables's magic. */
FIRMWARE_MAGIC : u64 : 0x53454c4241545746

/** How the machine's firmware describes it. */
FirmwareKind :: enum #backed_by(u32) {
    /** ACPI's tables, from its RSDP. */
    Acpi = 1,
    /** A flattened device tree. */
    DeviceTree = 2,
}

/** One table of the firmware grant: what it is, how big, and where it is in the grant and was in memory. */
FirmwareTable :: struct {
    /** The table's signature, its four ASCII bytes: "RSDP", "FACP", "DSDT", "DTB ", "RAM ", "FB  " and the like. */
    signature : u8[4],
    /** The table's size in bytes. */
    size : u32,
    /** Where the table is, in bytes from the grant's start. */
    offset : u64,
    /** The physical address the table was at, which ACPI's tables point at one another by; 0 for "RAM ". */
    physical : u64,
}

/** The "RAM " table's entries: the RAM the kernel owns, which nothing else may claim for a device. */
PhysicalRange :: struct {
    /** The range's lowest physical address. */
    base : u64,
    /** The range's size in bytes. */
    size : u64,
}

/**
 * The "FB  " table: the first framebuffer the boot found, at the table entry's physical address, its pixels pitch times
 * height bytes, each color's bits where its size and shift say. A kernel without a framebuffer has no such table.
 */
FramebufferLayout :: struct {
    /** The width, in pixels. */
    width : u32,
    /** The height, in pixels. */
    height : u32,
    /** Bytes from the start of one row to the start of the next. */
    pitch : u32,
    /** How many bits each pixel has. */
    bits_per_pixel : u16,
    /** How many bits red has. */
    red_size : u8,
    /** Where red's bits start in a pixel, from its lowest bit. */
    red_shift : u8,
    /** How many bits green has. */
    green_size : u8,
    /** Where green's bits start in a pixel, from its lowest bit. */
    green_shift : u8,
    /** How many bits blue has. */
    blue_size : u8,
    /** Where blue's bits start in a pixel, from its lowest bit. */
    blue_shift : u8,
}

#assert size_of(FirmwareTables) == 16
#assert size_of(FirmwareTable) == 24
#assert size_of(FramebufferLayout) == 20

/**
 * The exit code of a process that ended before its entry ran because it was started by a kernel of another ABI
 * version, or with a startup block too small to read.
 */
EXIT_WRONG_ABI : u32 : runtime.SLOP_OS_EXIT_WRONG_ABI
/**
 * The exit code of a process that ended before its entry ran because it hadn't a grant its entry needs, or had one of
 * the wrong kind.
 */
EXIT_MISSING_GRANT : u32 : runtime.SLOP_OS_EXIT_MISSING_GRANT

/**
 * Fetch the process's startup block, which its entry was given.
 *
 * It needs no context, so it can be called anywhere.
 *
 * @return The block, read-only, good for the life of the process; a null pointer if the process was given none.
 */
startup_block :: fn() -> ptr[StartupBlock] #no_context {
    return cast[ptr[StartupBlock]](intrinsics.process_state().startup_block)
}

/**
 * View a startup block's grants.
 *
 * @param block The block, as startup_block gives it; not null.
 * @return Its grant_count grants, in the block's memory, so good as long as it is; empty if there are none.
 */
grants_of :: fn(block: ptr[StartupBlock]) -> Grant[] {
    return view_of(cast[ptr[Grant]](cast[u64](block) + block.grants), cast[usize](block.grant_count))
}

/**
 * Read a grant's label, without its padding.
 *
 * @param grant The grant, in a startup block.
 * @return The label's bytes up to its first zero, or all GRANT_LABEL_SIZE of them; a view of the grant's own bytes,
 *     not a copy, good as long as the grant is.
 */
label_of :: fn(grant: ptr[Grant]) -> string {
    count : usize = 0
    for byte in grant.label {
        if byte == 0 {
            break
        }
        count += 1
    }
    return string_of(&grant.label[0], count)
}

/**
 * Find a grant by its label and kind.
 *
 * @param block The startup block to look in; not null.
 * @param label The label, compared byte for byte, without padding.
 * @param kind The kind of object the grant's handle has to be to; a grant of the label but another kind isn't found.
 * @return The first such grant's handle, which is the process's, not a copy; null if there's none.
 */
find_grant :: fn(block: ptr[StartupBlock], label: string, kind: ObjectKind) -> Handle? {
    for &grant in grants_of(block) {
        if grant.kind == kind && label_of(grant) == label {
            return grant.handle
        }
    }
    return null
}

/*
 * base's runtime reads the start of the block, and makes a few calls, with copies of its own
 * (base/runtime/slop_os.hsc), which have to agree with these.
 */
#assert offset_of(StartupBlock, abi_version) == offset_of(runtime.SlopOsStartup, abi_version)
#assert offset_of(StartupBlock, size) == offset_of(runtime.SlopOsStartup, size)
#assert offset_of(StartupBlock, process) == offset_of(runtime.SlopOsStartup, process)
#assert offset_of(StartupBlock, space) == offset_of(runtime.SlopOsStartup, space)
#assert offset_of(StartupBlock, budget) == offset_of(runtime.SlopOsStartup, budget)
#assert offset_of(StartupBlock, free_base) == offset_of(runtime.SlopOsStartup, free_base)
#assert offset_of(StartupBlock, free_size) == offset_of(runtime.SlopOsStartup, free_size)
#assert offset_of(StartupBlock, stack_base) == offset_of(runtime.SlopOsStartup, stack_base)
#assert offset_of(StartupBlock, stack_size) == offset_of(runtime.SlopOsStartup, stack_size)
#assert offset_of(StartupBlock, grants) == offset_of(runtime.SlopOsStartup, grants)
#assert offset_of(StartupBlock, seed) == offset_of(runtime.SlopOsStartup, seed)
#assert size_of(runtime.SlopOsStartup) <= size_of(StartupBlock)
#assert size_of(runtime.SlopOsGrant) == size_of(Grant)
#assert offset_of(Grant, kind) == offset_of(runtime.SlopOsGrant, kind)
#assert offset_of(Grant, handle) == offset_of(runtime.SlopOsGrant, handle)
#assert cast[u64](SYSCALL_CHANNEL_TAG) == runtime.SLOP_OS_CALL_CHANNEL_TAG
#assert cast[u64](SYSCALL_CHANNEL_WRITE) == runtime.SLOP_OS_CALL_CHANNEL_WRITE
#assert cast[u64](NO_BATCH) == runtime.SLOP_OS_NO_BATCH
#assert ABI_VERSION == runtime.SLOP_OS_ABI_VERSION
#assert cast[u32](ObjectKind.MemoryBudget) == runtime.SLOP_OS_KIND_MEMORY_BUDGET
#assert cast[u32](ObjectKind.Memory) == runtime.SLOP_OS_KIND_MEMORY
#assert cast[u32](ObjectKind.AddressSpace) == runtime.SLOP_OS_KIND_ADDRESS_SPACE
#assert cast[u32](ObjectKind.Thread) == runtime.SLOP_OS_KIND_THREAD
#assert cast[u32](ObjectKind.Process) == runtime.SLOP_OS_KIND_PROCESS
#assert cast[u32](ObjectKind.Channel) == runtime.SLOP_OS_KIND_CHANNEL
#assert cast[u32](ObjectKind.Port) == runtime.SLOP_OS_KIND_PORT
#assert cast[u32](ObjectKind.Irq) == runtime.SLOP_OS_KIND_IRQ
#assert cast[u32](ObjectKind.Platform) == runtime.SLOP_OS_KIND_PLATFORM
#assert cast[u32](ObjectKind.Intercept) == runtime.SLOP_OS_KIND_INTERCEPT
#assert cast[u32](ObjectKind.DebugLog) == runtime.SLOP_OS_KIND_DEBUG_LOG
#assert cast[u32](ObjectKind.DmaDomain) == runtime.SLOP_OS_KIND_DMA_DOMAIN
#assert cast[u32](ObjectKind.Device) == runtime.SLOP_OS_KIND_DEVICE
#assert cast[u64](SYSCALL_HANDLE_CLOSE) == runtime.SLOP_OS_CALL_HANDLE_CLOSE
#assert cast[u64](SYSCALL_CLOCK_MONOTONIC) == runtime.SLOP_OS_CALL_CLOCK_MONOTONIC
#assert cast[u64](SYSCALL_MEMORY_CREATE) == runtime.SLOP_OS_CALL_MEMORY_CREATE
#assert cast[u64](SYSCALL_MEMORY_MAP) == runtime.SLOP_OS_CALL_MEMORY_MAP
#assert cast[u64](SYSCALL_MEMORY_UNMAP) == runtime.SLOP_OS_CALL_MEMORY_UNMAP
#assert cast[u64](SYSCALL_PROCESS_EXIT) == runtime.SLOP_OS_CALL_PROCESS_EXIT
#assert cast[u64](PROTECTION_READ | PROTECTION_WRITE) == runtime.SLOP_OS_PROTECTION_READ_WRITE
#assert cast[u64](PROTECTION_READ) == runtime.SLOP_OS_PROTECTION_READ

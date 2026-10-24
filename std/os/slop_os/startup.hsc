package slop_os

import intrinsics from "base"
import runtime from "base"

/*
 * What a process starts with (knowledge/design/system-abi.md §6, docs/specs/programs.md): its first
 * thread's argument points at this, in memory its loader mapped into it, read-only, which stays for the
 * life of the process. The entry point's typed arguments are still to come (roadmap M6, 6d).
 */
StartupBlock :: struct {
    // The ABI_VERSION of the kernel that started the process
    abi_version : u32,
    // size_of(StartupBlock) as its writer knew it
    size : u32,
    // The process itself, its address space, and its memory budget
    process : Process,
    space : AddressSpace,
    budget : MemoryBudget,
    // How many grants there are
    grant_count : u32,
    /*
     * Where the process's runtime maps its own memory, its heap and its threads' stacks: free_size bytes
     * from free_base, page-aligned, which the loader put at a random place and nothing else in the space uses
     */
    free_base : u64,
    free_size : u64,
    // The first thread's stack: stack_size bytes from stack_base, the top its stack pointer started near
    stack_base : u64,
    stack_size : u64,
    // Where the grants are: grant_count Grants, this many bytes from the block's start
    grants : u64,
    /*
     * A random seed, which base's runtime seeds context.random from: the boot's for the root task, and one its
     * loader drew for any other process (decisions/0012, 0068)
     */
    seed : u8[32],
    cpu_features : CpuFeatures,
}

// The most bytes of a grant's label.
GRANT_LABEL_SIZE :: 32

/*
 * A handle the process starts with, besides its own, and what it's for: a label like "platform",
 * "debug_log" or "module:hello.elf", in UTF-8, padded with zeros. An entry parameter's grant is labeled
 * with the parameter's name (decisions 0044, 0068).
 */
Grant :: struct {
    label : u8[GRANT_LABEL_SIZE],
    kind : ObjectKind,
    reserved : u8[3],
    handle : Handle,
}

#assert size_of(Grant) == 40

// How a process ends before its entry runs: started by a kernel of another ABI version, or without a grant its entry needs.
EXIT_WRONG_ABI : u32 : runtime.SLOP_OS_EXIT_WRONG_ABI
EXIT_MISSING_GRANT : u32 : runtime.SLOP_OS_EXIT_MISSING_GRANT

// The process's startup block, which its entry was given.
startup_block :: fn() -> ptr[StartupBlock] #no_context {
    return cast[ptr[StartupBlock]](intrinsics.process_state().startup_block)
}

// The block's grants.
grants_of :: fn(block: ptr[StartupBlock]) -> Grant[] {
    return view_of(cast[ptr[Grant]](cast[u64](block) + block.grants), cast[usize](block.grant_count))
}

// A grant's label, without its padding.
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

// The grant labeled label, of kind, or null.
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
#assert cast[u64](SYSCALL_HANDLE_CLOSE) == runtime.SLOP_OS_CALL_HANDLE_CLOSE
#assert cast[u64](SYSCALL_CLOCK_MONOTONIC) == runtime.SLOP_OS_CALL_CLOCK_MONOTONIC
#assert cast[u64](SYSCALL_MEMORY_CREATE) == runtime.SLOP_OS_CALL_MEMORY_CREATE
#assert cast[u64](SYSCALL_MEMORY_MAP) == runtime.SLOP_OS_CALL_MEMORY_MAP
#assert cast[u64](SYSCALL_MEMORY_UNMAP) == runtime.SLOP_OS_CALL_MEMORY_UNMAP
#assert cast[u64](SYSCALL_PROCESS_EXIT) == runtime.SLOP_OS_CALL_PROCESS_EXIT
#assert cast[u64](PROTECTION_READ | PROTECTION_WRITE) == runtime.SLOP_OS_PROTECTION_READ_WRITE

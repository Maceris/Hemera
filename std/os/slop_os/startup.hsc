package slop_os

import runtime from "base"

/*
 * What a process starts with (knowledge/design/system-abi.md §6): its first thread's argument points at
 * this, in memory its loader mapped into it, which stays for the life of the process. The rest of the
 * startup grants, and the entry point's typed arguments, are still to come (roadmap M6, 6d).
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
    reserved : u32,
    /*
     * Where the process's runtime maps its own memory, its heap and its threads' stacks: free_size bytes
     * from free_base, page-aligned, which the loader put at a random place and nothing else in the space uses
     */
    free_base : u64,
    free_size : u64,
    cpu_features : CpuFeatures,
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
#assert size_of(runtime.SlopOsStartup) <= size_of(StartupBlock)
#assert cast[u64](SYSCALL_HANDLE_CLOSE) == runtime.SLOP_OS_CALL_HANDLE_CLOSE
#assert cast[u64](SYSCALL_CLOCK_MONOTONIC) == runtime.SLOP_OS_CALL_CLOCK_MONOTONIC
#assert cast[u64](SYSCALL_MEMORY_CREATE) == runtime.SLOP_OS_CALL_MEMORY_CREATE
#assert cast[u64](SYSCALL_MEMORY_MAP) == runtime.SLOP_OS_CALL_MEMORY_MAP
#assert cast[u64](SYSCALL_MEMORY_UNMAP) == runtime.SLOP_OS_CALL_MEMORY_UNMAP
#assert cast[u64](SYSCALL_PROCESS_EXIT) == runtime.SLOP_OS_CALL_PROCESS_EXIT
#assert cast[u64](PROTECTION_READ | PROTECTION_WRITE) == runtime.SLOP_OS_PROTECTION_READ_WRITE

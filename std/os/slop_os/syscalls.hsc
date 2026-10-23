package slop_os

/*
 * The system calls, handles and rights (the SlopOS repository's knowledge/design/system-abi.md §4,
 * decisions 0008, 0010, 0015, 0034, 0038). Unstable until ABI v1 (decision 0027).
 *
 * A call's number goes in the first register, its arguments in the next six, and it answers in three:
 * 0 or the error's tag, then up to two values (on x86-64: rax; rdi, rsi, rdx, r10, r8, r9; rax, rdx,
 * r8). Error tags start at 1.
 */

ABI_VERSION : u32 : 0

// A handle as user space sees it: opaque, chosen by the kernel. 0 is never one.
Handle :: distinct alias u32
NO_HANDLE : Handle : 0

// The kinds of kernel object (decisions/0034), as handle_info reports them.
ObjectKind :: enum #backed_by(u8) {
    MemoryBudget = 1,
    CpuBudget = 2,
    Memory = 3,
    AddressSpace = 4,
    Thread = 5,
    Process = 6,
    Channel = 7,
    Port = 8,
    Irq = 9,
    IoPortRange = 10,
    IommuDomain = 11,
}

/*
 * Rights on a handle (decisions/0010): two for every kind, and the rest per kind. Duplicating a handle
 * can keep or drop rights, never add them.
 */
Rights :: distinct alias u32
// May make another handle to the object.
RIGHT_DUPLICATE : Rights : 1 << 0
// May send the handle to another process.
RIGHT_TRANSFER : Rights : 1 << 1
// An address space: may start threads in it.
RIGHT_SPACE_THREADS : Rights : 1 << 8
// Every right, which an owning handle has.
RIGHTS_ALL : Rights : 0xffffffff

Syscall :: enum #backed_by(u32) {
    // (handle) -> nothing. Closing an owning handle destroys the object.
    HandleClose = 0,
    // (handle, rights) -> a non-owning handle with those rights, which the handle must have.
    HandleDuplicate = 1,
    // (handle) -> its object's kind, and its rights.
    HandleInfo = 2,
    // () -> never returns: the calling thread ends.
    ThreadExit = 3,
    // (address space, entry, stack, argument) -> an owning handle to a new thread there, started.
    ThreadCreate = 4,
    // () -> an owning handle to a new process, a child of the caller's.
    ProcessCreate = 5,
    // () -> an owning handle to a new, empty address space.
    AddressSpaceCreate = 6,
}

// What a call on a handle can fail with.
HandleError :: enum #backed_by(u32) {
    // Not a handle of this process, or one already closed.
    InvalidHandle = 1,
    // The object was destroyed.
    ObjectGone = 2,
    // The handle lacks a right the call needs.
    MissingRight = 3,
    // The handle isn't to the kind of object the call takes.
    WrongKind = 4,
    // The process's handle table is full.
    TableFull = 5,
    OutOfMemory = 6,
    // A number the kernel doesn't have.
    NoSuchCall = 7,
}

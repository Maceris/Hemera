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
// A port: may wait on it.
RIGHT_PORT_WAIT : Rights : 1 << 8
// A port: may bind keys to it, set its timers and wake it.
RIGHT_PORT_BIND : Rights : 1 << 9
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
    // () -> the monotonic clock, in nanoseconds (decisions/0009).
    ClockMonotonic = 7,
    // () -> an owning handle to a new port.
    PortCreate = 8,
    // (port, key) -> nothing: a binding port_wake can raise.
    PortBindWake = 9,
    // (port, key, bits) -> nothing: a User packet for key's wake binding, its bits ORed into one already queued.
    PortWake = 10,
    // (port, key, deadline, slack) -> nothing: a Timer packet at deadline, binding key if it isn't yet.
    PortSetTimer = 11,
    // (port, key) -> nothing: the binding goes, with its packet if one is queued.
    PortUnbind = 12,
    /*
     * (port, packets, capacity, deadline) -> how many packets it wrote at packets, up to capacity: once
     * there's at least one, or 0 at deadline (NO_DEADLINE for none).
     */
    PortWait = 13,
}

// For PortWait: wait for as long as it takes.
NO_DEADLINE : u64 : 0xffffffffffffffff
// The most packets one PortWait gives.
MAX_PACKETS_PER_WAIT : u32 : 64

PacketKind :: enum #backed_by(u32) {
    // An object's signals: data[0] is the signals seen.
    Signal = 1,
    // A timer's deadline came: data[0] is the deadline.
    Timer = 2,
    // port_wake: data[0] is every bit raised since the packet was last taken.
    User = 3,
}

// One event, as PortWait writes it (knowledge/design/ipc.md §3).
Packet :: struct {
    key : u64,
    kind : PacketKind,
    reserved : u32,
    data : u64[2],
}

#assert size_of(Packet) == 32

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

// What a call on a port can fail with. Tags shared with HandleError mean the same.
PortError :: enum #backed_by(u32) {
    InvalidHandle = 1,
    ObjectGone = 2,
    MissingRight = 3,
    WrongKind = 4,
    OutOfMemory = 6,
    // The key is bound already.
    KeyInUse = 8,
    // No binding has that key, or not one of that kind.
    NoSuchKey = 9,
    // Packets would go somewhere the thread can't write.
    BadBuffer = 10,
}

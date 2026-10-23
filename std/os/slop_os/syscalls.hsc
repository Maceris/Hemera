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
    // The authority over the machine's hardware, which the root task holds and gives the platform service (decisions/0039).
    Platform = 12,
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
// An address space: may map things in it.
RIGHT_SPACE_MAP : Rights : 1 << 9
// A port: may wait on it.
RIGHT_PORT_WAIT : Rights : 1 << 8
// A port: may bind keys to it, set its timers and wake it.
RIGHT_PORT_BIND : Rights : 1 << 9
// A channel end: may map its rings. Without it, they're reached through ChannelRead and ChannelWrite (decisions/0024).
RIGHT_CHANNEL_MAP : Rights : 1 << 8
// A memory budget: may pay for what's created with it, and split off child budgets (decisions/0011).
RIGHT_BUDGET_CHARGE : Rights : 1 << 8
// A memory object: may map it readable, writable, executable.
RIGHT_MEMORY_READ : Rights : 1 << 8
RIGHT_MEMORY_WRITE : Rights : 1 << 9
RIGHT_MEMORY_EXECUTE : Rights : 1 << 10
// An IRQ: may acknowledge it, unmasking a level-triggered line.
RIGHT_IRQ_ACK : Rights : 1 << 8
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
    // (budget, address space, entry, stack, argument) -> an owning handle to a new thread there, started.
    ThreadCreate = 4,
    // (budget) -> an owning handle to a new process, a child of the caller's, whose budget it is.
    ProcessCreate = 5,
    // (budget) -> an owning handle to a new, empty address space.
    AddressSpaceCreate = 6,
    // () -> the monotonic clock, in nanoseconds (decisions/0009).
    ClockMonotonic = 7,
    // (budget) -> an owning handle to a new port.
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
    // (budget, ring bytes, 0 for the default) -> owning handles to a new channel's two ends.
    ChannelCreate = 14,
    // (end, address space, address) -> nothing: the channel's rings, mapped at address.
    ChannelMap = 15,
    // (end) -> nothing: the end's rings, unmapped.
    ChannelUnmap = 16,
    // (end, signals) -> nothing: Readable or Writable, raised on the other end.
    ChannelNotify = 17,
    // (end, payload, size, batch) -> nothing: one message, written into the end's ring through the kernel.
    ChannelWrite = 18,
    // (end, buffer, capacity) -> the next message's size, and its flags and batch: read through the kernel.
    ChannelRead = 19,
    // (end, handles, count, batch) -> nothing: the handles, moved out of the caller's table into batch.
    ChannelSendHandles = 20,
    // (end, batch, handles, capacity) -> how many: the batch's handles, in the caller's table.
    ChannelTakeHandles = 21,
    // (end, signals, port, packets, capacity, deadline) -> as PortWait, after ChannelNotify.
    ChannelNotifyAndWait = 22,
    // (port, object, signals, key, mode) -> nothing: a Signal packet for key when the object raises any of signals.
    PortBind = 23,
    // (budget, limit) -> an owning handle to a child budget of limit bytes, carved out of the budget.
    MemoryBudgetCreate = 24,
    // (budget) -> its limit, and how much of it is charged, in bytes.
    MemoryBudgetInfo = 25,
    // (budget, size) -> an owning handle to a new memory object of size bytes, zero-filled as it's touched.
    MemoryCreate = 26,
    // (memory, address space, address, offset, size, protection) -> nothing: size bytes of it from offset, mapped at address.
    MemoryMap = 27,
    // (address space, address) -> nothing: the mapping that starts at address, unmapped.
    MemoryUnmap = 28,
    // (platform, kind, registers) -> the controller's number, and how many lines it has.
    ControllerRegister = 29,
    // (platform, budget, controller, line, IRQ_* flags) -> an owning handle to the line's IRQ, routed and unmasked.
    IrqCreate = 30,
    // (irq) -> nothing: a level-triggered line, unmasked again.
    IrqAck = 31,
    // (platform, budget, physical address, size, cache) -> an owning handle to device memory at that address.
    MemoryCreatePhysical = 32,
    // (memory, budget, offset, size) -> an owning handle to a window onto size bytes of it from offset.
    MemoryCreateWindow = 33,
}

// For ControllerRegister: the kinds of interrupt controller.
ControllerKind :: enum #backed_by(u32) {
    IoApic = 1,
    GicDistributor = 2,
    Plic = 3,
}

// For IrqCreate: how the line signals, from the firmware tables. Edge-triggered and active-high without them.
IRQ_LEVEL : u32 : 1 << 0
IRQ_ACTIVE_LOW : u32 : 1 << 1

// For MemoryCreatePhysical: how device memory is cached.
CacheMode :: enum #backed_by(u32) {
    WriteBack = 1,
    WriteCombining = 2,
    // Uncached and strongly ordered, for device registers.
    Device = 3,
}

// For MemoryMap: how a mapping can be reached. Writable and executable at once is refused.
Protection :: distinct alias u32
PROTECTION_READ : Protection : 1 << 0
PROTECTION_WRITE : Protection : 1 << 1
PROTECTION_EXECUTE : Protection : 1 << 2

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
    // An IRQ's: data[0] is how many interrupts arrived since the packet was last taken.
    Irq = 4,
}

// One event, as PortWait writes it (knowledge/design/ipc.md §3).
Packet :: struct {
    key : u64,
    kind : PacketKind,
    reserved : u32,
    data : u64[2],
}

#assert size_of(Packet) == 32

// What an object can raise, for a port binding to see.
Signals :: distinct alias u32
// A channel end: the other end wrote a message.
SIGNAL_READABLE : Signals : 1 << 0
// A channel end: the other end made room.
SIGNAL_WRITABLE : Signals : 1 << 1
// A channel end: the other end is closed. It stays raised.
SIGNAL_PEER_CLOSED : Signals : 1 << 2

BindMode :: enum #backed_by(u32) {
    // Disarmed once its packet is queued; PortBind with the same key and object arms it again.
    Once = 1,
    Persistent = 2,
}

/*
 * A channel's memory (knowledge/design/ipc.md §2), as ChannelMap maps it: each direction's indices,
 * then end A's ring, which it writes and B reads, then B's. Rings are a power of two in size, so
 * indices are byte counts that wrap, never reduced.
 */
CHANNEL_DEFAULT_RING : u32 : 1024
CHANNEL_MIN_RING : u32 : 1024
CHANNEL_MAX_RING : u32 : 131072
CHANNEL_RINGS_OFFSET : u32 : 256

// One direction's indices: the producer's and the consumer's on separate cache lines.
RingIndices :: struct #align(64) {
    // The producer's: bytes committed, and whether it waits for room.
    tail : u32,
    producer_waiting : u32,
    reserved0 : u8[56],
    // The consumer's: bytes consumed, and whether it waits for a message.
    head : u32,
    consumer_waiting : u32,
    reserved1 : u8[56],
}

#assert size_of(RingIndices) == 128

// Before every message in a ring, which is padded to 8 bytes.
MessageHeader :: struct {
    size : u32,
    flags : u16,
    // With MESSAGE_HAS_HANDLES: the batch its handles are in.
    handle_batch : u16,
}

#assert size_of(MessageHeader) == 8

MESSAGE_HAS_HANDLES : u16 : 1 << 0
// For ChannelWrite: a message without handles.
NO_BATCH : u32 : 0xffff
// Handle batches in flight to each end, and the handles one holds.
HANDLE_BATCHES : u32 : 16
MAX_HANDLES_PER_BATCH : u32 : 64

// The bytes ChannelMap maps for rings of ring_bytes.
channel_memory_size :: fn(ring_bytes: u32) -> u64 {
    return (cast[u64](CHANNEL_RINGS_OFFSET) + 2 * cast[u64](ring_bytes) + 4095) & ~cast[u64](4095)
}

// The largest payload a ring of ring_bytes takes: a message is at most half the ring, and 64 KiB.
channel_max_payload :: fn(ring_bytes: u32) -> u32 {
    half :: ring_bytes / 2
    return (if half < 65536 { half } else { 65536 }) - cast[u32](size_of(MessageHeader))
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
    // The budget can't pay for it (decisions/0011).
    BudgetExceeded = 25,
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
    // The object has as many bindings as it takes.
    TooManyBindings = 11,
    BudgetExceeded = 25,
}

// What a call on a channel can fail with. Tags shared with HandleError and PortError mean the same.
ChannelError :: enum #backed_by(u32) {
    InvalidHandle = 1,
    ObjectGone = 2,
    MissingRight = 3,
    WrongKind = 4,
    TableFull = 5,
    OutOfMemory = 6,
    // Memory the call reads or writes isn't the caller's to.
    BadBuffer = 10,
    // The other end is closed.
    PeerClosed = 12,
    // No room in the ring for the message.
    Full = 13,
    // No message in the ring.
    Empty = 14,
    // More than the call takes: a message bigger than channel_max_payload, or a batch of more than MAX_HANDLES_PER_BATCH.
    TooBig = 15,
    // The message doesn't fit in the buffer; the call's first value is its size.
    BufferTooSmall = 16,
    // The end's rings are mapped already, or it can't be sent while they are.
    Mapped = 17,
    // Not a page-aligned user address, or something is mapped there.
    BadAddress = 18,
    // The batch is in use, or there's no such batch to take.
    BatchInUse = 19,
    NoSuchBatch = 20,
    // The other end broke the ring: its indices or a header are impossible.
    Corrupt = 21,
    // A handle can't go through this channel: one of its own ends.
    NotTransferable = 22,
    // The end is in a batch in flight.
    InFlight = 23,
    // Rings must be a power of two from CHANNEL_MIN_RING to CHANNEL_MAX_RING.
    InvalidSize = 24,
    BudgetExceeded = 25,
}

// What a call on a memory budget or a memory object can fail with. Tags shared with the others mean the same.
MemoryError :: enum #backed_by(u32) {
    InvalidHandle = 1,
    ObjectGone = 2,
    MissingRight = 3,
    WrongKind = 4,
    TableFull = 5,
    OutOfMemory = 6,
    // Not a page-aligned user address range, or it overlaps a mapping.
    BadAddress = 18,
    // Not a whole number of pages, none at all, more than MAX_MEMORY_SIZE, or past the memory object's end.
    InvalidSize = 24,
    BudgetExceeded = 25,
    // No mapping starts at that address.
    NotMapped = 26,
    // Writable and executable at once, or no access at all.
    BadProtection = 27,
}

// The largest memory object, 1 GiB.
MAX_MEMORY_SIZE : u64 : 1 << 30

// What registering a controller, making an IRQ or device memory can fail with. Tags shared with the others mean the same.
DeviceError :: enum #backed_by(u32) {
    InvalidHandle = 1,
    ObjectGone = 2,
    MissingRight = 3,
    WrongKind = 4,
    TableFull = 5,
    OutOfMemory = 6,
    // Not page-aligned, or memory the kernel owns.
    BadAddress = 18,
    InvalidSize = 24,
    BudgetExceeded = 25,
    // No controller of that kind there, or the architecture has none of that kind.
    NoController = 28,
    // Every controller the kernel takes is registered.
    TooManyControllers = 29,
    NoSuchController = 30,
    NoSuchLine = 31,
    // The line already has an IRQ.
    LineInUse = 32,
    // No CPU has a device interrupt free.
    NoFreeInterrupt = 33,
}

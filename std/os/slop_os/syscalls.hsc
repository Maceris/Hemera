package slop_os

/*
 * The system calls, handles and rights (the SlopOS repository's knowledge/design/system-abi.md §4,
 * decisions 0008, 0010, 0015, 0034, 0038). Unstable until ABI v1 (decision 0027).
 *
 * A call's number goes in the first register, its arguments in the next six, and it answers in three:
 * 0 or the error's tag, then up to two values (on x86-64: rax; rdi, rsi, rdx, r10, r8, r9; rax, rdx,
 * r8). Error tags start at 1.
 */

ABI_VERSION : u32 : 4

// A handle as user space sees it: opaque, chosen by the kernel. 0 is never one.
Handle :: distinct alias u32
NO_HANDLE : Handle : 0

// A handle to one kind of object (decisions/0015). Calls that take any kind take a Handle: cast[Handle](port).
Port :: distinct alias Handle
Channel :: distinct alias Handle
MemoryBudget :: distinct alias Handle
Memory :: distinct alias Handle
AddressSpace :: distinct alias Handle
Process :: distinct alias Handle
Thread :: distinct alias Handle
Irq :: distinct alias Handle
Platform :: distinct alias Handle
Intercept :: distinct alias Handle
DebugLog :: distinct alias Handle
Device :: distinct alias Handle
DmaDomain :: distinct alias Handle

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
    // Where devices' DMA reaches: without an IOMMU, all of memory, device addresses being physical ones.
    DmaDomain = 11,
    // The authority over the machine's hardware, which the root task holds and gives the platform service (decisions/0039).
    Platform = 12,
    // A process's subtree intercepted: its threads stop at system calls and faults for a debugger (decisions/0017).
    Intercept = 13,
    // Lines in the kernel's log, for programs to report before there's a console (decisions/0058).
    DebugLog = 14,
    // A PCIe function, for its message-signaled interrupts and its DMA domain.
    Device = 15,
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
// A process, over its whole subtree (decisions/0017): list its threads and read their registers.
RIGHT_PROCESS_INSPECT : Rights : 1 << 8
// A process: read its memory.
RIGHT_PROCESS_READ_MEMORY : Rights : 1 << 9
// A process: write its memory and its threads' registers, and suspend and resume them.
RIGHT_PROCESS_WRITE_STATE : Rights : 1 << 10
// A process: intercept its threads' system calls, and take their faults.
RIGHT_PROCESS_INTERCEPT : Rights : 1 << 11
// A process: destroy it, through a handle that isn't its owning one.
RIGHT_PROCESS_KILL : Rights : 1 << 12
// A process: start threads in it, and give it handles, for building it from an executable.
RIGHT_PROCESS_THREADS : Rights : 1 << 13
// A debug log: write lines to it.
RIGHT_DEBUG_LOG_WRITE : Rights : 1 << 8
// Every right, which an owning handle has.
RIGHTS_ALL : Rights : 0xffffffff

/*
 * The system calls (knowledge/design/system-abi.md §4): a field's position is its number, which is
 * append-only from v1. Everything else is generated from this table (syscall_table.hsc): the Syscall
 * enum, a stub per call (slop_os.port_wait(...)), and the kernel's dispatch.
 *
 * Each argument is a register-sized value, a handle, an integer, an enum or a pointer, or a slice,
 * which takes two registers; six registers in all. Each result is Result[T, E]: E an error enum, and T
 * nothing, a register-sized value, or a struct of up to two of them.
 */
Syscalls :: struct {
    // Closing an owning handle destroys the object.
    handle_close : fn(handle: Handle) -> Result[void, HandleError],
    // A non-owning handle with rights, which the handle must have.
    handle_duplicate : fn(handle: Handle, rights: Rights) -> Result[Handle, HandleError],
    handle_info : fn(handle: Handle) -> Result[HandleInfo, HandleError],
    // The calling thread ends.
    thread_exit : fn() #never_returns,
    // A new thread in space, started at entry with stack and argument.
    thread_create : fn(budget: MemoryBudget, space: AddressSpace, entry: u64, stack: u64, argument: u64) -> Result[Thread, HandleError],
    // A new process, a child of the caller's, whose budget budget is.
    process_create : fn(budget: MemoryBudget) -> Result[Process, HandleError],
    // A new, empty address space.
    address_space_create : fn(budget: MemoryBudget) -> Result[AddressSpace, HandleError],
    // The monotonic clock, in nanoseconds (decisions/0009).
    clock_monotonic : fn() -> Result[u64, HandleError],
    port_create : fn(budget: MemoryBudget) -> Result[Port, HandleError],
    // A binding port_wake can raise.
    port_bind_wake : fn(port: Port, key: u64) -> Result[void, PortError],
    // A User packet for key's wake binding, its bits ORed into one already queued.
    port_wake : fn(port: Port, key: u64, bits: u64) -> Result[void, PortError],
    // A Timer packet at deadline, binding key if it isn't yet.
    port_set_timer : fn(port: Port, key: u64, deadline: u64) -> Result[void, PortError],
    // The binding goes, with its packet if one is queued.
    port_unbind : fn(port: Port, key: u64) -> Result[void, PortError],
    // How many packets it wrote, up to packets.count: once there's at least one, or 0 at deadline (NO_DEADLINE for none).
    port_wait : fn(port: Port, packets: mut Packet[], deadline: u64) -> Result[u32, PortError],
    // A new channel's two ends, with rings of ring_bytes each way, 0 for the default, speaking the protocol tag says, 0 for none.
    channel_create : fn(budget: MemoryBudget, ring_bytes: u32, tag: u64) -> Result[ChannelPair, ChannelError],
    // The channel's rings, mapped at address.
    channel_map : fn(end: Channel, space: AddressSpace, address: u64) -> Result[void, ChannelError],
    channel_unmap : fn(end: Channel) -> Result[void, ChannelError],
    // Readable or Writable, raised on the other end.
    channel_notify : fn(end: Channel, signals: Signals) -> Result[void, ChannelError],
    // One message, written into the end's ring through the kernel, with batch (NO_BATCH for none).
    channel_write : fn(end: Channel, payload: u8[], batch: u32) -> Result[void, ChannelError],
    // The next message, read through the kernel into buffer. Its size goes at size too, also when the buffer is too small.
    channel_read : fn(end: Channel, buffer: mut u8[], size: ptr[mut u32]) -> Result[MessageInfo, ChannelError],
    // The handles, moved out of the caller's table into batch.
    channel_send_handles : fn(end: Channel, handles: Handle[], batch: u32) -> Result[void, ChannelError],
    // How many: the batch's handles, in the caller's table. How many there are goes at count too, also when handles is too small.
    channel_take_handles : fn(end: Channel, batch: u32, handles: mut Handle[], count: ptr[mut u32]) -> Result[u32, ChannelError],
    // As port_wait, after channel_notify.
    channel_notify_and_wait : fn(end: Channel, signals: Signals, port: Port, packets: mut Packet[], deadline: u64) -> Result[u32, ChannelError],
    // A Signal packet for key when the object raises any of signals, or an Irq packet for an IRQ's interrupts.
    port_bind : fn(port: Port, object: Handle, signals: Signals, key: u64, mode: BindMode) -> Result[void, PortError],
    // A child budget of limit bytes, carved out of the budget.
    memory_budget_create : fn(budget: MemoryBudget, limit: u64) -> Result[MemoryBudget, HandleError],
    memory_budget_info : fn(budget: MemoryBudget) -> Result[BudgetInfo, HandleError],
    // A new memory object of size bytes, zero-filled as it's touched.
    memory_create : fn(budget: MemoryBudget, size: u64) -> Result[Memory, MemoryError],
    // size bytes of the memory from offset, mapped at address.
    memory_map : fn(memory: Memory, space: AddressSpace, address: u64, offset: u64, size: u64, protection: Protection) -> Result[void, MemoryError],
    // The mapping that starts at address, unmapped.
    memory_unmap : fn(space: AddressSpace, address: u64) -> Result[void, MemoryError],
    controller_register : fn(platform: Platform, kind: ControllerKind, registers: u64) -> Result[ControllerInfo, DeviceError],
    // The line's IRQ, routed and unmasked; flags are IRQ_*.
    irq_create : fn(platform: Platform, budget: MemoryBudget, controller: u32, line: u32, flags: u32) -> Result[Irq, DeviceError],
    // A level-triggered line, unmasked again.
    irq_ack : fn(irq: Irq) -> Result[void, HandleError],
    // Device memory at a physical address.
    memory_create_physical : fn(platform: Platform, budget: MemoryBudget, address: u64, size: u64, cache: CacheMode) -> Result[Memory, DeviceError],
    // A window onto size bytes of the memory from offset.
    memory_create_window : fn(memory: Memory, budget: MemoryBudget, offset: u64, size: u64) -> Result[Memory, MemoryError],
    // How many threads the process's subtree has; up to ids.count of their IDs at ids.
    process_threads : fn(process: Process, ids: mut u64[]) -> Result[u32, ControlError],
    process_read_memory : fn(process: Process, space: AddressSpace, address: u64, buffer: mut u8[]) -> Result[void, ControlError],
    process_write_memory : fn(process: Process, space: AddressSpace, address: u64, buffer: u8[]) -> Result[void, ControlError],
    thread_suspend : fn(process: Process, thread: u64) -> Result[void, ControlError],
    thread_resume : fn(process: Process, thread: u64) -> Result[void, ControlError],
    // A stopped or suspended thread's THREAD_REGISTERS registers.
    thread_read_registers : fn(process: Process, thread: u64, registers: mut u64[]) -> Result[void, ControlError],
    thread_write_registers : fn(process: Process, thread: u64, registers: u64[]) -> Result[void, ControlError],
    // An intercept of the process's subtree, reporting to port under key.
    intercept_attach : fn(process: Process, port: Port, key: u64, calls: u64, points: u32) -> Result[Intercept, ControlError],
    // The next stop not yet reported.
    intercept_next : fn(intercept: Intercept, stop: ptr[mut StopInfo]) -> Result[void, ControlError],
    intercept_resume : fn(intercept: Intercept, thread: u64, action: InterceptAction) -> Result[void, ControlError],
    process_kill : fn(process: Process) -> Result[void, ControlError],
    // The calling process ends, with its subtree, giving code to whoever watches it end.
    process_exit : fn(code: u32) #never_returns,
    // A line of text in the kernel's log, its first DEBUG_LOG_LINE bytes.
    debug_log : fn(log: DebugLog, text: u8[]) -> Result[void, HandleError],
    // A new thread in the process, in space, which must be in its subtree, started at entry with stack and argument: its ID.
    thread_create_in : fn(process: Process, budget: MemoryBudget, space: AddressSpace, entry: u64, stack: u64, argument: u64) -> Result[u64, ControlError],
    // The handles, moved out of the caller's table into the process's, and what each is there written at given.
    process_give_handles : fn(process: Process, handles: Handle[], given: mut Handle[]) -> Result[void, ControlError],
    // How big the memory object is, in bytes.
    memory_size : fn(memory: Memory) -> Result[u64, HandleError],
    // The protocol tag the end's channel was made with.
    channel_tag : fn(end: Channel) -> Result[u64, ChannelError],
    /*
     * A PCIe function at address (DEVICE_ADDRESS), whose message-signaled interrupts the interrupt controller knows
     * as msi_source: on AArch64, the ITS's device ID, from the firmware tables' msi-map; unused on x86-64. config is
     * the physical address of its 4 KiB of configuration space, where the kernel turns its DMA off (Bus Master
     * Enable) when the Device is destroyed.
     */
    device_create : fn(platform: Platform, budget: MemoryBudget, address: u32, msi_source: u32, config: u64) -> Result[Device, DeviceError],
    // The device's DMA, in the domain: what an IOMMU will confine it to.
    device_attach : fn(platform: Platform, device: Device, domain: DmaDomain) -> Result[void, DeviceError],
    // An IRQ for one of the device's message-signaled interrupts, routed to a CPU the kernel picks.
    irq_create_msi : fn(device: Device, budget: MemoryBudget) -> Result[Irq, DeviceError],
    // What the device writes, and where, to raise a message-signaled IRQ.
    irq_message : fn(irq: Irq) -> Result[MsiMessage, DeviceError],
    // A new DMA domain; without an IOMMU, its device addresses are physical addresses.
    dma_domain_create : fn(platform: Platform, budget: MemoryBudget) -> Result[DmaDomain, DeviceError],
    // Memory for DMA in the domain: pinned, physically contiguous, zeroed, ending at or below limit (0 for none).
    dma_memory_create : fn(domain: DmaDomain, budget: MemoryBudget, size: u64, limit: u64) -> Result[Memory, DeviceError],
    // Where DMA memory is, to the devices in its domain.
    memory_device_address : fn(memory: Memory) -> Result[u64, DeviceError],
}

// The most of a line debug_log writes.
DEBUG_LOG_LINE : u64 : 200

/*
 * How a process ended, in the data[1] of the Signal packet its SIGNAL_TERMINATED raises: the code it
 * gave process_exit, or EXIT_KILLED when it was killed, which no code can be.
 */
EXIT_KILLED : u64 : 1 << 32

#insert syscall_numbers()
#insert syscall_stubs()

// A call's bit, for intercept_attach's calls, by its number (SYSCALL_<NAME>).
syscall_bit :: fn(number: u32) -> u64 #no_context {
    return cast[u64](1) << cast[u64](number)
}

// What handle_info gives.
HandleInfo :: struct {
    kind : ObjectKind,
    rights : Rights,
}

// What channel_create gives.
ChannelPair :: struct {
    a : Channel,
    b : Channel,
}

// What channel_read gives: the message's size, and its flags and batch (MessageHeader's).
MessageInfo :: struct {
    size : u32,
    flags_and_batch : u32,
}

// What memory_budget_info gives: its limit, and how much of it is charged, in bytes.
BudgetInfo :: struct {
    limit : u64,
    used : u64,
}

// What controller_register gives: the controller's number, and how many lines it has.
ControllerInfo :: struct {
    number : u32,
    lines : u32,
}

// What irq_message gives: what a device writes, and where, to raise a message-signaled interrupt (PCIe MSI and MSI-X).
MsiMessage :: struct {
    address : u64,
    data : u32,
}

// For DeviceCreate: a PCIe function's address, its segment, then its requester ID.
device_address :: fn(segment: u16, bus: u8, device: u8, function: u8) -> u32 #no_context {
    return cast[u32](segment) << 16 | cast[u32](bus) << 8 | (cast[u32](device) & 0x1f) << 3 | (cast[u32](function) & 7)
}

// For InterceptAttach: where threads stop. calls is a bit per syscall number below 64.
STOP_SYSCALL_ENTRY : u32 : 1 << 0
STOP_SYSCALL_EXIT : u32 : 1 << 1
// A fault the thread's memory doesn't resolve, which would otherwise destroy it.
STOP_FAULT : u32 : 1 << 2

StopPoint :: enum #backed_by(u32) {
    SyscallEntry = 1,
    SyscallExit = 2,
    Fault = 3,
}

// One stop, as InterceptNext writes it.
StopInfo :: struct {
    thread : u64,
    point : StopPoint,
    // The system call's number, or for a fault, how it accessed: 0 read, 1 write, 2 execute.
    number : u32,
    // For a fault: the address it touched.
    address : u64,
}

InterceptAction :: enum #backed_by(u32) {
    // Run the system call, with any registers changed (entry); return to user mode (exit); retry the access (fault).
    Continue = 1,
    // Entry only: don't run the system call; return with the registers as written.
    Skip = 2,
    // Destroy the thread.
    Kill = 3,
}

/*
 * ThreadReadRegisters' and ThreadWriteRegisters' registers, u64s, in this order on x86-64: rax, rbx, rcx,
 * rdx, rsi, rdi, rbp, rsp, r8 to r15, rip, rflags. Writing rflags changes only its status flags and DF.
 * On AArch64: x0 to x30, sp, pc, pstate; writing pstate changes only its condition flags (NZCV).
 */
#if TARGET_ARCH == .arm64 {
    THREAD_REGISTERS : u32 : 34
}
#else {
    THREAD_REGISTERS : u32 : 18
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
    // An intercept's: data[0] is how many threads stopped since the packet was last taken (InterceptNext reports them).
    Stop = 5,
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
// A process or a thread: destroyed. It stays raised.
SIGNAL_TERMINATED : Signals : 1 << 3

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
    // Memory the call reads isn't the caller's to.
    BadBuffer = 10,
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

// What process control can fail with. Tags shared with the others mean the same.
ControlError :: enum #backed_by(u32) {
    InvalidHandle = 1,
    ObjectGone = 2,
    MissingRight = 3,
    WrongKind = 4,
    TableFull = 5,
    OutOfMemory = 6,
    // Memory the call reads or writes isn't there, or isn't the caller's to.
    BadBuffer = 10,
    // InterceptNext: no stop left to report.
    Empty = 14,
    // ProcessGiveHandles: more than MAX_HANDLES_PER_BATCH handles.
    TooBig = 15,
    // The address space isn't in the process's subtree, or the range isn't mapped.
    BadAddress = 18,
    // ProcessGiveHandles: a handle that can't go to the process, such as an owning one to the process or above it.
    NotTransferable = 22,
    BudgetExceeded = 25,
    // No thread with that ID in the subtree, or none the intercept stopped.
    NoSuchThread = 34,
    // The thread isn't stopped or suspended, or (Skip) isn't stopped at a system call's entry.
    NotStopped = 35,
    // The process is intercepted already.
    AlreadyIntercepted = 36,
    // A register value user mode can't have.
    BadRegisters = 37,
}

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
    // Not memory made for DMA (memory_device_address), or its domain is gone.
    NotDmaMemory = 38,
    // No interrupt controller here takes message-signaled interrupts.
    NoMsi = 39,
    // The device has as many message-signaled IRQs as it can (MAX_DEVICE_MSIS).
    TooManyVectors = 40,
    // Another device has that address, or, where the interrupt controller uses sources, that MSI source.
    DeviceExists = 41,
}

// The most message-signaled IRQs one device has at once.
MAX_DEVICE_MSIS : u32 : 32

/*
 * Variable-size data in a protocol's message (the SlopOS repository's decisions 0040, 0071): count Ts after the
 * message's fixed part, at offset bytes from the message's start, aligned for T. A message's generated validator
 * checks it's inside the message before anything reads it (std/os's protocol_code). elements holds nothing; it
 * names T for the validator.
 */
Relative :: struct[T] {
    offset : u32,
    count : u32,
    elements : T[0],
}

// A handle field of a message as it travels: its index in the message's batch, or this for none.
NO_HANDLE_INDEX : u32 : 0xffffffff

/*
 * What a protocol package says of itself, as its PROTOCOL (decisions/0040): its name, its major version, a new one
 * for any change that isn't only appending, and who pays for the server's work (decisions/0037).
 */
Protocol :: struct {
    name : string,
    major_version : u32,
    lending : Lending,
}

Lending :: enum {
    // The client's budget, for each of its connections
    PerConnection,
    // The server's own
    Server,
}

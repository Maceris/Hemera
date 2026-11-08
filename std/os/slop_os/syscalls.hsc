package slop_os

/*
 * The system calls, handles and rights (the SlopOS repository's knowledge/design/system-abi.md §4,
 * decisions 0008, 0010, 0015, 0034, 0038). Unstable until ABI v1 (decision 0027).
 *
 * A call's number goes in the first register, its arguments in the next six, and it answers in three:
 * 0 or the error's tag, then up to two values (on x86-64: rax; rdi, rsi, rdx, r10, r8, r9; rax, rdx,
 * r8). Error tags start at 1.
 */

/**
 * The version of the system ABI this package describes. The startup block carries the kernel's, and a program built
 * against another refuses to start, until ABI v1.
 */
ABI_VERSION : u32 : 12

/**
 * A handle as user space sees it: opaque, chosen by the kernel, and good only in the process whose table it's in.
 * A closed handle fails with InvalidHandle rather than naming another object (decisions/0008).
 */
Handle :: distinct alias u32
/** No handle: 0 is never one. */
NO_HANDLE : Handle : 0

// A handle to one kind of object (decisions/0015). Calls that take any kind take a Handle: cast[Handle](port).
/** A handle to a port, where packets for the events bound to it queue. */
Port :: distinct alias Handle
/** A handle to one end of a channel, a pair of message rings between two ends. */
Channel :: distinct alias Handle
/** A handle to a memory budget, which pays for the kernel objects and memory made with it. */
MemoryBudget :: distinct alias Handle
/** A handle to a memory object, pages that can be mapped into address spaces. */
Memory :: distinct alias Handle
/** A handle to an address space, where memory is mapped and threads run. */
AddressSpace :: distinct alias Handle
/** A handle to a process, which owns objects and, through its subtree, child processes. */
Process :: distinct alias Handle
/** A handle to a thread. */
Thread :: distinct alias Handle
/** A handle to an interrupt, wired or message-signaled. */
Irq :: distinct alias Handle
/** A handle to the authority over the machine's hardware (decisions/0039). */
Platform :: distinct alias Handle
/** A handle to an intercept of a process's subtree, for a debugger (decisions/0017). */
Intercept :: distinct alias Handle
/** A handle to the kernel's log (decisions/0058). */
DebugLog :: distinct alias Handle
/** A handle to a PCIe function. */
Device :: distinct alias Handle
/** A handle to a CPU budget, the CPU time its threads get (decisions/0037, 0093). */
CpuBudget :: distinct alias Handle
/** A handle to a range of I/O ports, on an architecture that has them. */
IoPortRange :: distinct alias Handle
/** A handle to a DMA domain, where devices' DMA reaches. */
DmaDomain :: distinct alias Handle

/** The kinds of kernel object (decisions/0034), as handle_info reports them. */
ObjectKind :: enum #backed_by(u8) {
    /** A memory budget (MemoryBudget). */
    MemoryBudget = 1,
    /** A CPU budget (CpuBudget). */
    CpuBudget = 2,
    /** A memory object (Memory). */
    Memory = 3,
    /** An address space (AddressSpace). */
    AddressSpace = 4,
    /** A thread (Thread). */
    Thread = 5,
    /** A process (Process). */
    Process = 6,
    /** A channel end (Channel). */
    Channel = 7,
    /** A port (Port). */
    Port = 8,
    /** An interrupt (Irq). */
    Irq = 9,
    /** A range of I/O ports (IoPortRange). */
    IoPortRange = 10,
    /** Where devices' DMA reaches: without an IOMMU, all of memory, device addresses being physical ones. */
    DmaDomain = 11,
    /**
     * The authority over the machine's hardware, which the root task holds and gives the platform service
     * (decisions/0039).
     */
    Platform = 12,
    /** A process's subtree intercepted: its threads stop at system calls and faults for a debugger (decisions/0017). */
    Intercept = 13,
    /** Lines in the kernel's log, for programs to report before there's a console (decisions/0058). */
    DebugLog = 14,
    /** A PCIe function, for its message-signaled interrupts and its DMA domain. */
    Device = 15,
}

/**
 * Rights on a handle (decisions/0010), a bit set: two for every kind, in bits 0 and 1, and the rest per kind, from
 * bit 8, so the same bit means different rights on different kinds. Duplicating a handle can keep or drop rights,
 * never add them.
 */
Rights :: distinct alias u32
/** May make another handle to the object (handle_duplicate). */
RIGHT_DUPLICATE : Rights : 1 << 0
/** May send the handle to another process (channel_send_handles, process_give_handles). */
RIGHT_TRANSFER : Rights : 1 << 1
/** An address space: may start threads in it. */
RIGHT_SPACE_THREADS : Rights : 1 << 8
/** An address space: may map things in it. */
RIGHT_SPACE_MAP : Rights : 1 << 9
/** A port: may wait on it. */
RIGHT_PORT_WAIT : Rights : 1 << 8
/** A port: may bind keys to it, set its timers and wake it. */
RIGHT_PORT_BIND : Rights : 1 << 9
/**
 * A channel end: may map its rings. Without it, they're reached through channel_read and channel_write
 * (decisions/0024).
 */
RIGHT_CHANNEL_MAP : Rights : 1 << 8
/** A memory budget: may pay for what's created with it, and split off child budgets (decisions/0011). */
RIGHT_BUDGET_CHARGE : Rights : 1 << 8
/** A memory object: may map it readable, and read it through memory_read. Every mapping needs it. */
RIGHT_MEMORY_READ : Rights : 1 << 8
/** A memory object: may map it writable, write it through memory_write, and, for paged memory, act as its pager. */
RIGHT_MEMORY_WRITE : Rights : 1 << 9
/** A memory object: may map it executable. */
RIGHT_MEMORY_EXECUTE : Rights : 1 << 10
/** An IRQ: may acknowledge it, unmasking a level-triggered line. */
RIGHT_IRQ_ACK : Rights : 1 << 8
/** A process, over its whole subtree (decisions/0017): list its threads and read their registers. */
RIGHT_PROCESS_INSPECT : Rights : 1 << 8
/** A process: read its memory. */
RIGHT_PROCESS_READ_MEMORY : Rights : 1 << 9
/** A process: write its memory and its threads' registers, and suspend and resume them. */
RIGHT_PROCESS_WRITE_STATE : Rights : 1 << 10
/** A process: intercept its threads' system calls, and take their faults. */
RIGHT_PROCESS_INTERCEPT : Rights : 1 << 11
/** A process: destroy it, through a handle that isn't its owning one. */
RIGHT_PROCESS_KILL : Rights : 1 << 12
/** A process: start threads in it, give it handles, and set its CPU budget, for building it from an executable. */
RIGHT_PROCESS_THREADS : Rights : 1 << 13
/** A debug log: write lines to it. */
RIGHT_DEBUG_LOG_WRITE : Rights : 1 << 8
/** A CPU budget: may split child budgets off it (cpu_budget_create). */
RIGHT_CPU_BUDGET_SPLIT : Rights : 1 << 8
/** A CPU budget: may change its parameters (cpu_budget_set, cpu_budget_set_cpus). */
RIGHT_CPU_BUDGET_SET : Rights : 1 << 9
/** A CPU budget: may have threads run on it (process_set_cpu_budget, thread_use_cpu_budget). */
RIGHT_CPU_BUDGET_BIND : Rights : 1 << 10
/** A range of I/O ports: may read and write them. */
RIGHT_IO_PORTS_ACCESS : Rights : 1 << 8
/** Every right, which an owning handle has. */
RIGHTS_ALL : Rights : 0xffffffff

/**
 * The system calls (knowledge/design/system-abi.md §4): a field's position is its number, which is
 * append-only from v1. Everything else is generated from this table (syscall_table.hsc): the
 * SYSCALL_<NAME> numbers, a stub per call (slop_os.port_wait(...)), and the kernel's dispatch.
 *
 * Each argument is a register-sized value, a handle, an integer, an enum or a pointer, or a slice,
 * which takes two registers; six registers in all. Each result is Result[T, E]: E an error enum, and T
 * nothing, a register-sized value, or a struct of up to two of them.
 *
 * Errors every call that takes a handle can give, and which aren't repeated for each: InvalidHandle for a handle
 * that isn't the caller's or is closed, WrongKind for one to another kind of object than the call takes,
 * MissingRight for one without a right the call needs, and ObjectGone for an object destroyed. A call that makes an
 * object charges the memory budget it's given (which needs RIGHT_BUDGET_CHARGE) and can give OutOfMemory,
 * BudgetExceeded, and TableFull when the caller's handle table has no room, in which case the object is destroyed
 * again. An object a call makes is owned by the caller's process, through the owning handle it gives back: closing
 * that handle destroys the object.
 */
Syscalls :: struct {
    /**
     * Close a handle. Closing an owning handle destroys the object, and every other handle to it then gives
     * ObjectGone.
     *
     * @param handle The handle, of any kind; no right is needed. It's no longer good once the call returns Ok.
     * @error InvalidHandle Not a handle of the caller's, or one already closed.
     */
    handle_close : fn(handle: Handle) -> Result[void, HandleError],
    /**
     * Make another handle to the same object, never an owning one.
     *
     * @param handle The handle to duplicate, which needs RIGHT_DUPLICATE; it stays as it was.
     * @param rights The new handle's rights, each of which handle has to have.
     * @return The new handle, in the caller's table.
     * @error MissingRight The handle lacks RIGHT_DUPLICATE, or one of rights.
     * @error TableFull The caller's handle table has no room.
     */
    handle_duplicate : fn(handle: Handle, rights: Rights) -> Result[Handle, HandleError],
    /**
     * Describe a handle.
     *
     * @param handle The handle, of any kind; no right is needed.
     * @return The kind of object it's to, and the rights it has.
     * @error InvalidHandle Not a handle of the caller's, or one already closed.
     */
    handle_info : fn(handle: Handle) -> Result[HandleInfo, HandleError],
    /** End the calling thread, which raises its SIGNAL_TERMINATED. It never returns. */
    thread_exit : fn() #never_returns,
    /**
     * Make a thread in an address space and start it, owned by the caller's process.
     *
     * @param budget The memory budget that pays for the thread.
     * @param space Where it runs, which needs RIGHT_SPACE_THREADS.
     * @param entry The address in space it starts at.
     * @param stack Its initial stack pointer, an address in space.
     * @param argument A word handed to it in its first argument register.
     * @return An owning handle to the thread, which is running by the time the call returns.
     * @error ObjectGone The address space or the caller's process was destroyed.
     */
    thread_create : fn(budget: MemoryBudget, space: AddressSpace, entry: u64, stack: u64, argument: u64) -> Result[Thread, HandleError],
    /**
     * Make a process, a child of the caller's, with no threads or address spaces yet.
     *
     * @param budget The memory budget that pays for the process, and becomes its own.
     * @return An owning handle to the process; closing it destroys the process and its subtree.
     */
    process_create : fn(budget: MemoryBudget) -> Result[Process, HandleError],
    /**
     * Make an empty address space, owned by the caller's process.
     *
     * @param budget The memory budget that pays for it.
     * @return An owning handle to the address space.
     */
    address_space_create : fn(budget: MemoryBudget) -> Result[AddressSpace, HandleError],
    /**
     * Read the monotonic clock (decisions/0009), which never goes back.
     *
     * Time is read through a call, not a mapped page, so it can be recorded (decisions/0009).
     *
     * @return The time in nanoseconds. It always succeeds.
     */
    clock_monotonic : fn() -> Result[u64, HandleError],
    /**
     * Make a port, where packets for events bound to it queue until a port_wait takes them.
     *
     * @param budget The memory budget that pays for it.
     * @return An owning handle to the port, with every right.
     */
    port_create : fn(budget: MemoryBudget) -> Result[Port, HandleError],
    /**
     * Bind a key to a port for port_wake to raise.
     *
     * @param port The port, which needs RIGHT_PORT_BIND.
     * @param key The binding's key, which its packets carry; any value not bound on the port already.
     * @error KeyInUse The key is bound already.
     */
    port_bind_wake : fn(port: Port, key: u64) -> Result[void, PortError],
    /**
     * Raise a wake binding: queue a User packet for key, or OR bits into the one already queued.
     *
     * @param port The port, which needs RIGHT_PORT_BIND.
     * @param key A key port_bind_wake bound.
     * @param bits Bits for the packet's data[0], ORed with any raised since the packet was last taken.
     * @error NoSuchKey No wake binding has the key.
     */
    port_wake : fn(port: Port, key: u64, bits: u64) -> Result[void, PortError],
    /**
     * Set a timer: a Timer packet for key when the monotonic clock reaches deadline, binding key if it isn't yet, and
     * replacing the deadline if it's a timer already.
     *
     * @param port The port, which needs RIGHT_PORT_BIND.
     * @param key Any key: one not bound on the port yet is bound as a timer, and a timer's has its deadline replaced.
     *     The Timer packet carries it.
     * @param deadline When, in the monotonic clock's nanoseconds; one that has passed fires at once.
     * @error KeyInUse The key is bound already, to something other than a timer.
     */
    port_set_timer : fn(port: Port, key: u64, deadline: u64) -> Result[void, PortError],
    /**
     * Remove a binding, of any kind, with its packet if one is queued.
     *
     * @param port The port, which needs RIGHT_PORT_BIND.
     * @param key The key of the binding to remove, of whatever kind: a wake binding, a timer, or an object's
     *     (port_bind).
     * @error NoSuchKey No binding has the key.
     */
    port_unbind : fn(port: Port, key: u64) -> Result[void, PortError],
    /**
     * Wait for packets on a port, taking those queued: at once if there are any, or else blocking until one comes or
     * the deadline does.
     *
     * @param port The port, which needs RIGHT_PORT_WAIT.
     * @param packets Where packets are written, at most MAX_PACKETS_PER_WAIT of them however big it is. Empty, the
     *     call returns 0 at once.
     * @param deadline When to give up, in the monotonic clock's nanoseconds, or NO_DEADLINE to wait for as long as it
     *     takes.
     * @return How many packets it wrote at the start of packets: at least 1, or 0 when the deadline came first.
     * @error BadBuffer The packets aren't memory the caller can write.
     */
    port_wait : fn(port: Port, packets: mut Packet[], deadline: u64) -> Result[u32, PortError],
    /**
     * Make a channel: two ends, each with a ring it writes and the other reads, owned by the caller's process.
     *
     * @param budget The memory budget that pays for the channel and its rings.
     * @param ring_bytes Each ring's size in bytes: a power of two from CHANNEL_MIN_RING to CHANNEL_MAX_RING, or 0 for
     *     CHANNEL_DEFAULT_RING. A message can be at most channel_max_payload(ring_bytes).
     * @param tag The protocol the channel speaks, which channel_tag tells either end's holder, or 0 for none.
     * @return Owning handles to both ends, with every right.
     * @error InvalidSize The ring_bytes isn't 0 or a power of two in range.
     */
    channel_create : fn(budget: MemoryBudget, ring_bytes: u32, tag: u64) -> Result[ChannelPair, ChannelError],
    /**
     * Map a channel's memory (its indices and both rings, laid out as CHANNEL_RINGS_OFFSET describes) in an address
     * space, readable and writable, for the end's holder to read and write its rings directly.
     *
     * @param end The end, which needs RIGHT_CHANNEL_MAP; one end can be mapped once at a time.
     * @param space Where, which needs RIGHT_SPACE_MAP.
     * @param address A page-aligned user address with channel_memory_size(ring_bytes) bytes free from it.
     * @error Mapped The end's rings are mapped already.
     * @error BadAddress Not a page-aligned user address, or something is mapped there.
     */
    channel_map : fn(end: Channel, space: AddressSpace, address: u64) -> Result[void, ChannelError],
    /**
     * Unmap what channel_map mapped for an end.
     *
     * @param end The end; no right is needed.
     */
    channel_unmap : fn(end: Channel) -> Result[void, ChannelError],
    /**
     * Raise signals on the other end, after writing its ring directly (Readable) or reading from it (Writable): the
     * doorbell of the ring's wake protocol (knowledge/design/ipc.md §2).
     *
     * @param end The caller's end; no right is needed.
     * @param signals SIGNAL_READABLE, SIGNAL_WRITABLE, or both.
     * @error PeerClosed The other end is closed.
     */
    channel_notify : fn(end: Channel, signals: Signals) -> Result[void, ChannelError],
    /**
     * Write one message into the end's ring through the kernel, for a holder that hasn't mapped it, and raise
     * Readable on the other end.
     *
     * @param end The caller's end; no right is needed.
     * @param payload The message's bytes, copied; at most channel_max_payload of the ring's size.
     * @param batch The handle batch channel_send_handles filled for this message, or NO_BATCH for none.
     * @error PeerClosed The other end is closed.
     * @error Full The ring has no room for the message now; wait for Writable.
     * @error TooBig The message is bigger than the ring takes.
     * @error BadBuffer The payload isn't memory the caller can read.
     */
    channel_write : fn(end: Channel, payload: u8[], batch: u32) -> Result[void, ChannelError],
    /**
     * Read the next message from the other end's ring through the kernel, for a holder that hasn't mapped it.
     *
     * @param end The caller's end; no right is needed.
     * @param buffer Where the message's payload is copied.
     * @param size Where its size in bytes is written too, also when the buffer is too small; null for nowhere.
     * @return The message's size, and its header's flags and batch.
     * @error Empty No message is waiting.
     * @error BufferTooSmall The message doesn't fit in the buffer; it stays in the ring, and its size is at size.
     * @error BadBuffer The buffer or size isn't memory the caller can write.
     * @error Corrupt The other end broke the ring.
     */
    channel_read : fn(end: Channel, buffer: mut u8[], size: ptr[mut u32]) -> Result[MessageInfo, ChannelError],
    /**
     * Move handles out of the caller's table into one of the channel's handle batches, for the message that names it
     * to carry to the other end (knowledge/design/ipc.md, Handle transfer). If the receiver never takes them, objects
     * they owned are destroyed with the channel.
     *
     * @param end The caller's end; no right is needed.
     * @param handles The handles, at most MAX_HANDLES_PER_BATCH, each with RIGHT_TRANSFER. Once the call returns Ok
     *     they're no longer the caller's.
     * @param batch Which batch, below HANDLE_BATCHES, not in use already.
     * @error BatchInUse The batch is in use.
     * @error TooBig More than MAX_HANDLES_PER_BATCH handles.
     * @error NotTransferable One of the handles is to one of this channel's own ends.
     * @error InFlight One of the handles is to a channel end in a batch already.
     * @error Mapped One of the handles is to a channel end whose rings are mapped.
     */
    channel_send_handles : fn(end: Channel, handles: Handle[], batch: u32) -> Result[void, ChannelError],
    /**
     * Take a batch the other end sent into the caller's table, the caller's budget taking over their objects' charges
     * (decisions/0011).
     *
     * @param end The caller's end; no right is needed.
     * @param batch The batch a message named, below HANDLE_BATCHES.
     * @param handles Where the new handles are written, in the order they were sent.
     * @param count Where how many the batch has is written too, also when handles is too small; null for nowhere.
     * @return How many handles it took.
     * @error NoSuchBatch No batch of that number is waiting to be taken.
     * @error BufferTooSmall The handles can't hold the batch; it stays, and how many it has is at count.
     * @error BudgetExceeded The caller's budget can't absorb the objects; the batch stays.
     */
    channel_take_handles : fn(end: Channel, batch: u32, handles: mut Handle[], count: ptr[mut u32]) -> Result[u32, ChannelError],
    /**
     * Raise signals on the other end as channel_notify does, then wait on a port as port_wait does, in one call: a
     * thread the notify wakes is made ready on this CPU, to run here once the caller waits (knowledge/design/ipc.md
     * §5).
     *
     * @param end The caller's end; no right is needed.
     * @param signals What to raise on the other end, as channel_notify's.
     * @param port The port to wait on, which needs RIGHT_PORT_WAIT.
     * @param packets Where packets are written, as port_wait's.
     * @param deadline When to give up, as port_wait's.
     * @return How many packets it wrote, as port_wait's.
     * @error PeerClosed The other end is closed; nothing is waited for.
     * @error BadBuffer The packets aren't memory the caller can write.
     */
    channel_notify_and_wait : fn(end: Channel, signals: Signals, port: Port, packets: mut Packet[], deadline: u64) -> Result[u32, ChannelError],
    /**
     * Bind an object's events to a port: a Signal packet for key when the object raises any of signals, or an Irq
     * packet for an IRQ's interrupts.
     *
     * A channel end's packet comes at once for PeerClosed if its peer is closed, and for Readable if messages are
     * waiting in it; bound for Readable while it's empty, its next message raises Readable, as if a read had found
     * it empty.
     *
     * @param port The port, which needs RIGHT_PORT_BIND.
     * @param object What to watch: a channel end, a process (which needs RIGHT_PROCESS_INSPECT), a thread, an IRQ, a
     *     Device, or a memory budget (which needs RIGHT_BUDGET_CHARGE).
     * @param signals Which signals to see; ignored for an IRQ.
     * @param key The binding's key, which its packets carry.
     * @param mode Once, disarmed once its packet is queued, or Persistent.
     * @error WrongKind An object no port can watch.
     * @error KeyInUse The key is bound already.
     * @error TooManyBindings The object has as many bindings as it takes.
     */
    port_bind : fn(port: Port, object: Handle, signals: Signals, key: u64, mode: BindMode) -> Result[void, PortError],
    /**
     * Make a child memory budget, carved out of a budget.
     *
     * @param budget The parent budget, which pays for the child and needs RIGHT_BUDGET_CHARGE.
     * @param limit The most the child can charge, in bytes.
     * @return An owning handle to the child.
     */
    memory_budget_create : fn(budget: MemoryBudget, limit: u64) -> Result[MemoryBudget, HandleError],
    /**
     * Describe a memory budget.
     *
     * @param budget The budget; no right is needed.
     * @return Its limit, and how much of it is charged, in bytes.
     */
    memory_budget_info : fn(budget: MemoryBudget) -> Result[BudgetInfo, HandleError],
    /**
     * Make a memory object, its pages zero-filled as they're touched, paid for by a budget.
     *
     * @param budget The memory budget that pays for it.
     * @param size Its size in bytes: a whole number of pages, at least one, at most MAX_MEMORY_SIZE.
     * @return An owning handle to it, with every right.
     * @error InvalidSize The size isn't a whole number of pages, is 0, or is more than MAX_MEMORY_SIZE.
     */
    memory_create : fn(budget: MemoryBudget, size: u64) -> Result[Memory, MemoryError],
    /**
     * Map part of a memory object in an address space.
     *
     * @param memory The memory, which needs RIGHT_MEMORY_READ, and RIGHT_MEMORY_WRITE or RIGHT_MEMORY_EXECUTE when
     *     protection asks for them.
     * @param space Where, which needs RIGHT_SPACE_MAP.
     * @param address A page-aligned user address with size bytes free from it.
     * @param offset Where in the memory the mapping starts, in bytes, a whole number of pages.
     * @param size How many bytes, a whole number of pages, at least one, within the memory.
     * @param protection PROTECTION_ bits: readable, and writable or executable but not both.
     * @error BadAddress Not a page-aligned user address range, or it overlaps a mapping.
     * @error InvalidSize The size or offset isn't a whole number of pages, or runs past the memory's end.
     * @error BadProtection Writable and executable at once, or no access at all.
     */
    memory_map : fn(memory: Memory, space: AddressSpace, address: u64, offset: u64, size: u64, protection: Protection) -> Result[void, MemoryError],
    /**
     * Unmap the mapping that starts at an address, all of it.
     *
     * @param space The address space, which needs RIGHT_SPACE_MAP.
     * @param address The address a mapping starts at.
     * @error NotMapped No mapping starts at that address.
     */
    memory_unmap : fn(space: AddressSpace, address: u64) -> Result[void, MemoryError],
    /**
     * Register an interrupt controller the firmware tables describe, for its lines' IRQs.
     *
     * @param platform A handle to the Platform object, the authority over the machine's hardware, which the root task
     *     holds and passes on; a handle to another kind of object gives WrongKind.
     * @param kind What kind of controller is at registers; a kind not there, or one the architecture hasn't, gives
     *     NoController.
     * @param registers The physical address of its registers, page-aligned, not in the kernel's memory.
     * @return The controller's number, for irq_create, and how many lines it has.
     * @error NoController No controller of that kind there, or the architecture has none of that kind.
     * @error BadAddress The registers aren't page-aligned, or are in the kernel's memory.
     * @error TooManyControllers Every controller the kernel takes is registered.
     */
    controller_register : fn(platform: Platform, kind: ControllerKind, registers: u64) -> Result[ControllerInfo, DeviceError],
    /**
     * Make an IRQ for a controller's line, routed and unmasked, for a driver to bind to a port.
     *
     * @param platform A handle to the Platform object, the authority over the machine's hardware, which the root task
     *     holds and passes on; a handle to another kind of object gives WrongKind.
     * @param budget The memory budget that pays for it.
     * @param controller A number controller_register gave.
     * @param line The line, below the controller's count of lines.
     * @param flags IRQ_LEVEL and IRQ_ACTIVE_LOW from the firmware tables, or 0 for edge-triggered and active-high.
     * @return An owning handle to the IRQ, with every right.
     * @error NoSuchController No controller has that number.
     * @error NoSuchLine The controller has no such line.
     * @error LineInUse The line already has an IRQ.
     */
    irq_create : fn(platform: Platform, budget: MemoryBudget, controller: u32, line: u32, flags: u32) -> Result[Irq, DeviceError],
    /**
     * Acknowledge an interrupt, unmasking a level-triggered line again once its device is quiet.
     *
     * @param irq The IRQ, which needs RIGHT_IRQ_ACK.
     */
    irq_ack : fn(irq: Irq) -> Result[void, HandleError],
    /**
     * Make a memory object of device memory at a physical address, to map a device's registers or memory.
     *
     * @param platform A handle to the Platform object, the authority over the machine's hardware, which the root task
     *     holds and passes on; a handle to another kind of object gives WrongKind.
     * @param budget The memory budget that pays for it.
     * @param address The physical address, page-aligned, not in the kernel's memory.
     * @param size Its size in bytes, a whole number of pages.
     * @param cache How it's cached; Device for registers.
     * @return An owning handle to the memory.
     * @error BadAddress Not page-aligned, or memory the kernel owns.
     * @error InvalidSize Not a whole number of pages, or a cache mode that isn't one.
     */
    memory_create_physical : fn(platform: Platform, budget: MemoryBudget, address: u64, size: u64, cache: CacheMode) -> Result[Memory, DeviceError],
    /**
     * Make a window onto part of a memory object: a memory object of its own that maps those pages, which can be
     * mapped only as the original's handle can be.
     *
     * @param memory The memory; no right is needed, but its rights limit the window's mappings.
     * @param budget The memory budget that pays for the window.
     * @param offset Where the window starts in the memory, in bytes, a whole number of pages.
     * @param size How many bytes, a whole number of pages, within the memory.
     * @return An owning handle to the window.
     * @error InvalidSize The offset or size isn't a whole number of pages, or runs past the memory's end.
     */
    memory_create_window : fn(memory: Memory, budget: MemoryBudget, offset: u64, size: u64) -> Result[Memory, MemoryError],
    /**
     * List the threads of a process's subtree.
     *
     * @param process The process, which needs RIGHT_PROCESS_INSPECT.
     * @param ids Where their IDs are written, at most 64 of them however big it is.
     * @return How many threads the subtree has, which can be more than were written.
     * @error BadBuffer The IDs aren't memory the caller can write.
     */
    process_threads : fn(process: Process, ids: mut u64[]) -> Result[u32, ControlError],
    /**
     * Copy bytes from an address space in a process's subtree into the caller's buffer.
     *
     * @param process The process, which needs RIGHT_PROCESS_READ_MEMORY.
     * @param space An address space in its subtree, through a handle the caller has.
     * @param address Where in space to read from.
     * @param buffer Where the bytes go; it's filled.
     * @error BadAddress The space isn't in the subtree, or the range isn't mapped there or in the caller's memory.
     */
    process_read_memory : fn(process: Process, space: AddressSpace, address: u64, buffer: mut u8[]) -> Result[void, ControlError],
    /**
     * Copy the caller's bytes into an address space in a process's subtree.
     *
     * @param process The process, which needs RIGHT_PROCESS_WRITE_STATE.
     * @param space An address space in its subtree, through a handle the caller has.
     * @param address Where in space to write to.
     * @param buffer The bytes to write.
     * @error BadAddress The space isn't in the subtree, or the range isn't mapped there or in the caller's memory.
     */
    process_write_memory : fn(process: Process, space: AddressSpace, address: u64, buffer: u8[]) -> Result[void, ControlError],
    /**
     * Suspend a thread in a process's subtree until thread_resume. Suspending one already suspended changes nothing.
     *
     * @param process The process, which needs RIGHT_PROCESS_WRITE_STATE.
     * @param thread The thread's ID, as process_threads gives it.
     * @error NoSuchThread No thread with that ID in the subtree.
     */
    thread_suspend : fn(process: Process, thread: u64) -> Result[void, ControlError],
    /**
     * Resume a thread thread_suspend suspended.
     *
     * @param process The process, which needs RIGHT_PROCESS_WRITE_STATE.
     * @param thread The thread's ID, as process_threads gives it.
     * @error NoSuchThread No thread with that ID in the subtree.
     */
    thread_resume : fn(process: Process, thread: u64) -> Result[void, ControlError],
    /**
     * Read a stopped or suspended thread's registers.
     *
     * @param process The process, which needs RIGHT_PROCESS_INSPECT.
     * @param thread The thread's ID, as process_threads gives it.
     * @param registers Where the registers go: at least THREAD_REGISTERS of them, in THREAD_REGISTERS' order.
     * @error NoSuchThread No thread with that ID in the subtree.
     * @error NotStopped The thread isn't stopped or suspended.
     * @error BadBuffer Fewer than THREAD_REGISTERS, or not memory the caller can write.
     */
    thread_read_registers : fn(process: Process, thread: u64, registers: mut u64[]) -> Result[void, ControlError],
    /**
     * Write a stopped or suspended thread's registers, for when it runs again.
     *
     * @param process The process, which needs RIGHT_PROCESS_WRITE_STATE.
     * @param thread The thread's ID, as process_threads gives it.
     * @param registers The registers: at least THREAD_REGISTERS of them, in THREAD_REGISTERS' order.
     * @error NoSuchThread No thread with that ID in the subtree.
     * @error NotStopped The thread isn't stopped or suspended.
     * @error BadBuffer Fewer than THREAD_REGISTERS, or not memory the caller can read.
     * @error BadRegisters A value user mode can't have, like a kernel address for the instruction pointer.
     */
    thread_write_registers : fn(process: Process, thread: u64, registers: u64[]) -> Result[void, ControlError],
    /**
     * Intercept a process's subtree, for a debugger: its threads stop where points says, and each stop raises a Stop
     * packet on a port. Paid for by the caller's process's own budget, as it has no budget argument.
     *
     * @param process The process, which needs RIGHT_PROCESS_INTERCEPT.
     * @param port The port stops are reported to, which needs RIGHT_PORT_BIND.
     * @param key The Stop packets' key.
     * @param calls Which system calls stop at entry or exit: a bit per call number below 64 (syscall_bit).
     * @param points STOP_ bits: where threads stop.
     * @return An owning handle to the intercept; closing it lets the subtree run on unintercepted.
     * @error AlreadyIntercepted The process is intercepted already.
     */
    intercept_attach : fn(process: Process, port: Port, key: u64, calls: u64, points: u32) -> Result[Intercept, ControlError],
    /**
     * Take the next stop not yet reported.
     *
     * @param intercept The intercept; no right is needed.
     * @param stop Where the stop is written.
     * @error Empty No stop left to report.
     * @error BadBuffer The stop isn't memory the caller can write.
     */
    intercept_next : fn(intercept: Intercept, stop: ptr[mut StopInfo]) -> Result[void, ControlError],
    /**
     * Let a stopped thread go on.
     *
     * @param intercept The intercept; no right is needed.
     * @param thread The stopped thread's ID, as intercept_next gave it.
     * @param action What it does: Continue, Skip (only at a system call's entry), or Kill.
     * @error NoSuchThread No thread with that ID the intercept stopped.
     * @error NotStopped The thread isn't stopped, Skip somewhere other than a system call's entry, or an action that
     *     isn't one.
     */
    intercept_resume : fn(intercept: Intercept, thread: u64, action: InterceptAction) -> Result[void, ControlError],
    /**
     * Destroy a process and its subtree, which raises SIGNAL_TERMINATED with EXIT_KILLED.
     *
     * @param process The process, which needs RIGHT_PROCESS_KILL.
     */
    process_kill : fn(process: Process) -> Result[void, ControlError],
    /**
     * End the calling process, with its subtree and the calling thread. It never returns.
     *
     * @param code The exit code, for whoever watches it end: data[1] of the SIGNAL_TERMINATED packet.
     */
    process_exit : fn(code: u32) #never_returns,
    /**
     * Write a line of text in the kernel's log.
     *
     * @param log The debug log, which needs RIGHT_DEBUG_LOG_WRITE.
     * @param text The line, without its line break; only its first DEBUG_LOG_LINE bytes are written.
     * @error BadBuffer The text isn't memory the caller can read.
     */
    debug_log : fn(log: DebugLog, text: u8[]) -> Result[void, HandleError],
    /**
     * Make a thread owned by another process, in an address space in its subtree, and start it, as thread_create
     * would in the caller's (decisions/0067).
     *
     * @param process The process that owns the thread, which needs RIGHT_PROCESS_THREADS.
     * @param budget The memory budget that pays for the thread.
     * @param space Where it runs, which needs RIGHT_SPACE_THREADS and has to be in process's subtree.
     * @param entry The address in space it starts at.
     * @param stack Its initial stack pointer, an address in space.
     * @param argument A word handed to it in its first argument register.
     * @return The thread's ID, not a handle: the caller doesn't own it.
     * @error BadAddress The address space isn't in the process's subtree.
     */
    thread_create_in : fn(process: Process, budget: MemoryBudget, space: AddressSpace, entry: u64, stack: u64, argument: u64) -> Result[u64, ControlError],
    /**
     * Move handles out of the caller's table into another process's, for building it from an executable.
     *
     * @param process The process, which needs RIGHT_PROCESS_THREADS.
     * @param handles The handles, at most MAX_HANDLES_PER_BATCH, each with RIGHT_TRANSFER. Once the call returns Ok
     *     they're no longer the caller's.
     * @param given Where each one's handle in the process is written, in the same order: at least as many.
     * @error TooBig More than MAX_HANDLES_PER_BATCH handles.
     * @error BadBuffer The slices at given are too few, or the slices aren't the caller's memory.
     * @error MissingRight A handle lacks RIGHT_TRANSFER.
     * @error NotTransferable A handle that can't go to the process, such as an owning one to the process or above it.
     */
    process_give_handles : fn(process: Process, handles: Handle[], given: mut Handle[]) -> Result[void, ControlError],
    /**
     * Tell how big a memory object is.
     *
     * @param memory The memory; no right is needed.
     * @return Its size in bytes, a whole number of pages.
     */
    memory_size : fn(memory: Memory) -> Result[u64, HandleError],
    /**
     * Tell what protocol a channel speaks.
     *
     * @param end Either end; no right is needed.
     * @return The tag the channel was made with, 0 for none.
     */
    channel_tag : fn(end: Channel) -> Result[u64, ChannelError],
    /**
     * Make a Device for a PCIe function, for its message-signaled interrupts and its DMA domain.
     *
     * @param platform A handle to the Platform object, the authority over the machine's hardware, which the root task
     *     holds and passes on; a handle to another kind of object gives WrongKind.
     * @param budget The memory budget that pays for it.
     * @param address The function's address (device_address).
     * @param msi_source What the interrupt controller knows its message-signaled interrupts as: on AArch64, the ITS's
     *     device ID, from the firmware tables' msi-map; unused on x86-64.
     * @param config The physical address of its 4 KiB of configuration space, where the kernel turns its DMA off
     *     (Bus Master Enable) when the Device is destroyed.
     * @return An owning handle to the Device.
     * @error DeviceExists Another device has that address, or, where the interrupt controller uses sources, that MSI
     *     source.
     */
    device_create : fn(platform: Platform, budget: MemoryBudget, address: u32, msi_source: u32, config: u64) -> Result[Device, DeviceError],
    /**
     * Put a device's DMA in a domain: what an IOMMU will confine it to.
     *
     * @param platform A handle to the Platform object, the authority over the machine's hardware, which the root task
     *     holds and passes on; a handle to another kind of object gives WrongKind.
     * @param device The device; no right is needed.
     * @param domain The domain; no right is needed.
     * @error WrongIommu The device isn't behind the IOMMU its domain's other devices are, or behind none where
     *     they're behind one.
     */
    device_attach : fn(platform: Platform, device: Device, domain: DmaDomain) -> Result[void, DeviceError],
    /**
     * Make an IRQ for one of a device's message-signaled interrupts, routed to a CPU the kernel picks.
     *
     * @param device The device; no right is needed.
     * @param budget The memory budget that pays for it.
     * @return An owning handle to the IRQ; irq_message says what the device writes to raise it.
     * @error NoMsi No interrupt controller here takes message-signaled interrupts.
     * @error TooManyVectors The device has MAX_DEVICE_MSIS of them already.
     * @error NoFreeInterrupt No CPU has a device interrupt free.
     */
    irq_create_msi : fn(device: Device, budget: MemoryBudget) -> Result[Irq, DeviceError],
    /**
     * Tell what a device writes, and where, to raise a message-signaled IRQ, for its driver to program.
     *
     * @param irq The IRQ; no right is needed.
     * @return The message's address and data.
     * @error NoMsi The IRQ is a wired line's, which has no message.
     */
    irq_message : fn(irq: Irq) -> Result[MsiMessage, DeviceError],
    /**
     * Make a DMA domain. Without an IOMMU, its device addresses are physical addresses, and only a domain made
     * trusted has DMA memory.
     *
     * @param platform A handle to the Platform object, the authority over the machine's hardware, which the root task
     *     holds and passes on; a handle to another kind of object gives WrongKind.
     * @param budget The memory budget that pays for it.
     * @param flags DMA_DOMAIN_TRUSTED, or 0.
     * @return An owning handle to the domain.
     */
    dma_domain_create : fn(platform: Platform, budget: MemoryBudget, flags: u32) -> Result[DmaDomain, DeviceError],
    /**
     * Make memory for DMA in a domain: pinned, physically contiguous, and zeroed.
     *
     * @param domain The domain; no right is needed.
     * @param budget The memory budget that pays for it.
     * @param size Its size in bytes, a whole number of pages.
     * @param limit The highest device address it may end at, for devices that reach only so far, or 0 for none.
     * @return An owning handle to the memory; memory_device_address says where devices see it.
     * @error Untrusted No IOMMU translates the domain, and it wasn't made trusted.
     * @error InvalidSize Not a whole number of pages, or none.
     */
    dma_memory_create : fn(domain: DmaDomain, budget: MemoryBudget, size: u64, limit: u64) -> Result[Memory, DeviceError],
    /**
     * Tell where DMA memory is, to the devices in its domain.
     *
     * @param memory The memory; no right is needed.
     * @return Its device address.
     * @error NotDmaMemory Not memory dma_memory_create made, or its domain is gone.
     */
    memory_device_address : fn(memory: Memory) -> Result[u64, DeviceError],
    /**
     * Register an IOMMU the firmware tables describe, covering a range of requester IDs.
     *
     * The same IOMMU registered again, its registers at the same place, gives the same number, and covers those
     * requester IDs too. A device is attached through the IOMMU that covers it most narrowly.
     *
     * @param platform A handle to the Platform object, the authority over the machine's hardware, which the root task
     *     holds and passes on; a handle to another kind of object gives WrongKind.
     * @param kind What kind of IOMMU is at registers; a kind not there, or one the kernel can't drive, gives NoIommu.
     * @param registers Its registers: device memory itself (memory_create_physical, cached as Device), not a window
     *     onto it.
     * @param first The first requester ID it covers (DEVICE_ADDRESS, its segment then its requester ID).
     * @param count How many requester IDs it covers from first.
     * @param stream What the IOMMU knows first as: the stream ID requester IDs map to, counting up from it.
     * @return The number the kernel knows the IOMMU by, its place among those registered, from 0; the same IOMMU
     *     registered again gives the same number.
     * @error NoIommu No IOMMU of that kind there, or none the kernel can drive.
     * @error BadAddress The registers isn't device memory itself.
     * @error InvalidSize The registers is bigger than the IOMMU's registers can be.
     * @error TooManyIommus Every IOMMU the kernel takes is registered, or every range of requester IDs one covers.
     */
    iommu_register : fn(platform: Platform, kind: IommuKind, registers: Memory, first: u32, count: u32, stream: u32) -> Result[u32, DeviceError],
    /**
     * Make a CPU budget (the SlopOS repository's decisions 0037, 0093): a child of parent, whose threads get time
     * nanoseconds of CPU every period nanoseconds at priority, then run in the background band until it comes back.
     *
     * Its share, time over period, comes out of its parent's, which its children's together can't pass. Destroyed,
     * what ran on it runs on its parent.
     *
     * @param parent The budget it's split off, which needs RIGHT_CPU_BUDGET_SPLIT.
     * @param budget The memory budget that pays for it.
     * @param priority Its threads' priority, at most its parent's.
     * @param period How often its time comes back, in nanoseconds, more than 0.
     * @param time How much CPU it gets each period, in nanoseconds, at most period.
     * @return An owning handle to the budget.
     * @error BudgetExceeded Its share would take its parent's children past the parent's own.
     * @error InvalidArgument A period of 0, a time over period, or a priority over its parent's.
     */
    cpu_budget_create : fn(parent: CpuBudget, budget: MemoryBudget, priority: u32, period: u64, time: u64) -> Result[CpuBudget, HandleError],
    /**
     * Change a CPU budget's priority, period and time, within its parent's as cpu_budget_create's are.
     *
     * @param budget The budget, which needs RIGHT_CPU_BUDGET_SET.
     * @param priority Its threads' priority, at most its parent's.
     * @param period How often its time comes back, in nanoseconds, more than 0.
     * @param time How much CPU it gets each period, in nanoseconds, at most period.
     * @error BudgetExceeded The new share would take its parent's children past the parent's own, or be less than
     *     its own children's.
     * @error InvalidArgument A period of 0, a time over period, or a priority over its parent's.
     */
    cpu_budget_set : fn(budget: CpuBudget, priority: u32, period: u64, time: u64) -> Result[void, HandleError],
    /**
     * Describe a CPU budget, as words; cpu_budget_describe gives it as a CpuBudgetInfo.
     *
     * @param budget The budget; no right is needed.
     * @param info Where its CpuBudgetInfo goes, as at least CPU_BUDGET_INFO_WORDS words in its fields' order.
     * @error BadBuffer Fewer than CPU_BUDGET_INFO_WORDS words, or not memory the caller can write.
     */
    cpu_budget_info : fn(budget: CpuBudget, info: mut u64[]) -> Result[void, HandleError],
    /**
     * Put a process's threads, now and later, on a CPU budget.
     *
     * @param process The process, which needs RIGHT_PROCESS_THREADS.
     * @param budget The budget, which needs RIGHT_CPU_BUDGET_BIND.
     * @error ObjectGone The process or the budget was destroyed.
     */
    process_set_cpu_budget : fn(process: Process, budget: CpuBudget) -> Result[void, HandleError],
    /**
     * Make an object of a range of I/O ports, on an architecture that has them (x86-64).
     *
     * @param platform A handle to the Platform object, the authority over the machine's hardware, which the root task
     *     holds and passes on; a handle to another kind of object gives WrongKind.
     * @param budget The memory budget that pays for it.
     * @param first The number of the range's first port; the range can't run past the last port there is (0xffff on
     *     x86-64).
     * @param count How many ports, from first to first + count - 1.
     * @return An owning handle to the range.
     * @error InvalidArgument Ports past the last one, none, or an architecture without ports.
     */
    io_ports_create : fn(platform: Platform, budget: MemoryBudget, first: u32, count: u32) -> Result[IoPortRange, DeviceError],
    /**
     * Read an I/O port in a range.
     *
     * @param ports The range, which needs RIGHT_IO_PORTS_ACCESS.
     * @param offset The port's offset from the range's first.
     * @param width How many bytes: 1, 2 or 4.
     * @return The value read, zero-extended.
     * @error InvalidArgument A port outside the range, or a width that isn't 1, 2 or 4.
     */
    io_port_read : fn(ports: IoPortRange, offset: u32, width: u32) -> Result[u32, DeviceError],
    /**
     * Write an I/O port in a range.
     *
     * @param ports The range, which needs RIGHT_IO_PORTS_ACCESS.
     * @param offset The port's offset from the range's first.
     * @param width How many bytes: 1, 2 or 4.
     * @param value The value, of which only width bytes are written.
     * @error InvalidArgument A port outside the range, or a width that isn't 1, 2 or 4.
     */
    io_port_write : fn(ports: IoPortRange, offset: u32, width: u32, value: u32) -> Result[void, DeviceError],
    /**
     * Make a memory object whose pages its pager supplies (the SlopOS repository's decisions/0094): a touch of one
     * that isn't there yet waits, and raises key's wake binding on port, which the pager made.
     *
     * It can be mapped only to read or execute; only a handle that may write it (RIGHT_MEMORY_WRITE) asks what's
     * wanted and supplies.
     *
     * @param budget The memory budget that pays for it and its pages.
     * @param port The pager's port, which needs RIGHT_PORT_BIND.
     * @param key A wake binding on port.
     * @param size Its size in bytes: a whole number of pages, at most MAX_MEMORY_SIZE.
     * @return An owning handle to the memory.
     * @error NoPager The port has no wake binding with that key, or is gone.
     * @error InvalidSize Not a whole number of pages, none, or more than MAX_MEMORY_SIZE.
     */
    memory_create_paged : fn(budget: MemoryBudget, port: Port, key: u64, size: u64) -> Result[Memory, MemoryError],
    /**
     * Ask which page of paged memory a touch is waiting for, each reported once.
     *
     * @param memory The paged memory, which needs RIGHT_MEMORY_WRITE.
     * @return The page's offset in bytes.
     * @error NothingWanted No page is waited for that hasn't been reported.
     * @error NotPaged Not paged memory.
     */
    memory_page_wanted : fn(memory: Memory) -> Result[u64, MemoryError],
    /**
     * Supply a page of paged memory, copied from a page of another memory object, and wake whoever waited for it.
     *
     * @param memory The paged memory, which needs RIGHT_MEMORY_WRITE.
     * @param offset The page's offset in memory, in bytes, a whole number of pages.
     * @param source Where it's copied from, which needs RIGHT_MEMORY_READ.
     * @param source_offset The page's offset in source, in bytes, a whole number of pages.
     * @error NotPaged The memory isn't paged memory.
     * @error InvalidSize An offset that isn't a whole number of pages, or past its memory's end.
     */
    memory_supply : fn(memory: Memory, offset: u64, source: Memory, source_offset: u64) -> Result[void, MemoryError],
    /**
     * Copy bytes of memory into a buffer, through the kernel, with no mapping: for memory another process owns, whose
     * end is only ObjectGone, never a fault (the SlopOS repository's decisions/0098). Anonymous, DMA, contiguous, boot
     * module or paged memory, or a window onto one; a page of paged memory that isn't there is waited for from its
     * pager, the calling thread blocked until it's supplied.
     *
     * @param memory The memory, which needs RIGHT_MEMORY_READ.
     * @param offset Where in it to start, in bytes; any offset.
     * @param buffer Where the bytes go; it's filled.
     * @error ObjectGone The memory was destroyed, or its pager is gone.
     * @error WrongKind Device memory.
     * @error InvalidSize The range runs past the memory's end.
     */
    memory_read : fn(memory: Memory, offset: u64, buffer: mut u8[]) -> Result[void, MemoryError],
    /**
     * Copy bytes into memory, through the kernel, with no mapping, as memory_read reads it: anonymous, DMA or
     * contiguous memory, or a window onto one whose parent's handle allowed writing.
     *
     * @param memory The memory, which needs RIGHT_MEMORY_WRITE.
     * @param offset Where in it to start, in bytes; any offset.
     * @param bytes The bytes to write.
     * @error ObjectGone The memory was destroyed.
     * @error WrongKind Device, paged or boot module memory, or a window that isn't writable.
     * @error InvalidSize The range runs past the memory's end.
     */
    memory_write : fn(memory: Memory, offset: u64, bytes: u8[]) -> Result[void, MemoryError],
    /**
     * Set the CPUs a CPU budget's threads may run on (the SlopOS repository's decisions/0099). A child starts with
     * its parent's; the root's are every CPU. Its threads move at their next tick.
     *
     * @param budget The budget, which needs RIGHT_CPU_BUDGET_SET.
     * @param cpus A bit per CPU's index: at least one of them online, within its parent's, and over each of its
     *     children's.
     * @error InvalidArgument None of the CPUs online.
     * @error BudgetExceeded CPUs outside its parent's, or not covering one of its children's.
     */
    cpu_budget_set_cpus : fn(budget: CpuBudget, cpus: u64) -> Result[void, HandleError],
    /**
     * Route a message-signaled IRQ to another CPU.
     *
     * @param irq The IRQ; no right is needed.
     * @param cpu The CPU's index: online, and one of the caller's CPU budget's CPUs.
     * @error NoMsi The IRQ is a wired line's.
     * @error InvalidArgument A CPU that isn't online, or isn't the caller's CPU budget's.
     */
    irq_set_cpu : fn(irq: Irq, cpu: u32) -> Result[void, DeviceError],
    /**
     * Set a memory budget's pressure threshold (the SlopOS repository's decisions/0111): SIGNAL_PRESSURE is raised as
     * what it has charged reaches it, and again each time it does after falling below it; at once, if it's there
     * already.
     *
     * @param budget The budget, which needs RIGHT_BUDGET_CHARGE.
     * @param threshold In bytes, or 0 for none.
     */
    memory_budget_set_threshold : fn(budget: MemoryBudget, threshold: u64) -> Result[void, HandleError],
    /**
     * Give back a page of paged memory: unmapped everywhere, its frame freed and its charge returned, so the next
     * touch waits for its pager again.
     *
     * @param memory The paged memory, which needs RIGHT_MEMORY_WRITE.
     * @param offset The page's offset in bytes.
     * @error NotPaged Not paged memory.
     * @error NotSupplied The page isn't there.
     * @error MappedWidely More address spaces map it than one call takes it from (MAX_EVICT_SPACES), which only a
     *     less shared page avoids.
     */
    memory_evict : fn(memory: Memory, offset: u64) -> Result[void, MemoryError],
    /**
     * Ask whether a page of paged memory was touched since the last time this asked, through any mapping, clearing
     * the marks that say so.
     *
     * @param memory The paged memory, which needs RIGHT_MEMORY_WRITE.
     * @param offset The page's offset in bytes.
     * @return 1 if it was touched, 0 if it wasn't; always 0 where the hardware doesn't keep the marks.
     * @error NotPaged Not paged memory.
     */
    memory_page_accessed : fn(memory: Memory, offset: u64) -> Result[u64, MemoryError],
    /**
     * Run the calling thread on a CPU budget from now on, or on its process's again: a server running a
     * connection's work on the budget its client lent it (the SlopOS repository's decisions 0037, 0130). Destroyed
     * while a thread runs on it, the thread runs on its parent.
     *
     * @param budget The budget, which needs RIGHT_CPU_BUDGET_BIND, or NO_HANDLE for the process's own.
     * @error ObjectGone The budget was destroyed.
     */
    thread_use_cpu_budget : fn(budget: CpuBudget) -> Result[void, HandleError],
    /**
     * Count who holds a memory object besides its owner (the SlopOS repository's decisions/0178): handles to it that
     * aren't the owning one, in any process or on their way in a channel, its mappings, and its windows. A pager that
     * gives its memory out, like a store, closes it when no one does.
     *
     * @param memory The memory, its owning handle: only its owner asks.
     * @return How many hold it; 0 when only its owner does, as SIGNAL_UNHELD says when it falls to 0.
     * @error MissingRight Not the owning handle.
     */
    memory_holders : fn(memory: Memory) -> Result[u64, MemoryError],
    /**
     * Tell the kernel how this machine turns off (the SlopOS repository's decisions/0182), where it needs the firmware
     * to know: on x86-64, ACPI's PM1 control registers and the sleep type of S5, `\_S5`'s values. Read-modify-written
     * at the end, with SLP_EN set, after every other CPU has stopped. Calling it again replaces what was set, as an
     * ACPI service started again does.
     *
     * @param platform A handle to the Platform object, the authority over the machine's hardware, which the root task
     *     is given; no right is needed.
     * @param control_a The PM1a control register's I/O port, 1 to 65535.
     * @param control_b The PM1b control register's I/O port, 1 to 65535; 0 where there's no PM1b block.
     * @param sleep_a The sleep type written to PM1a's SLP_TYP for S5, 0 to 7.
     * @param sleep_b The sleep type written to PM1b's SLP_TYP for S5, 0 to 7; ignored without a PM1b block.
     * @error InvalidArgument A control_a of 0, or a sleep type over 7; or an architecture that turns off without
     *     the firmware's tables, as AArch64 does through PSCI.
     */
    power_set_off : fn(platform: Platform, control_a: u32, control_b: u32, sleep_a: u32, sleep_b: u32) -> Result[void, DeviceError],
    /**
     * Tell the kernel how this machine resets (decisions/0182), where the firmware says: on x86-64, the FADT's reset
     * register when it's an I/O port. Without it, the kernel resets x86-64 through the chipset's register, 0xcf9.
     * Calling it again replaces what was set.
     *
     * @param platform A handle to the Platform object; no right is needed.
     * @param port The reset register's I/O port, 1 to 65535.
     * @param value The byte written to it to reset, 0 to 255.
     * @error InvalidArgument A port of 0 or over 65535, or a value over 255; or an architecture without I/O ports or
     *     that resets through PSCI.
     */
    power_set_reset : fn(platform: Platform, port: u32, value: u32) -> Result[void, DeviceError],
    /**
     * Say what the kernel does once the root task ends (decisions/0182): halt, as it always has, turn the machine
     * off, or restart it. It's done after every other CPU has stopped and the objects left are logged; with test_exit
     * on the kernel's command line, the emulator is asked to exit with RootTaskEnded instead, unless test_power is on
     * it too. Calling it again replaces what was asked.
     *
     * @param platform A handle to the Platform object; no right is needed.
     * @param action What to do.
     * @error NoPowerOff Off, on a machine the kernel can't turn off: on x86-64 until power_set_off, or on AArch64
     *     without PSCI.
     * @error InvalidArgument An action that isn't one of PowerAction's.
     */
    power_end_with : fn(platform: Platform, action: PowerAction) -> Result[void, DeviceError],
}

/** The most address spaces memory_evict takes a page from at once. */
MAX_EVICT_SPACES :: 16

/**
 * What cpu_budget_info gives, in the order of its words.
 */
CpuBudgetInfo :: struct {
    /** Its threads' priority. */
    priority : u64,
    /** How often its time comes back, in nanoseconds. */
    period : u64,
    /** How much CPU it gets each period, in nanoseconds. */
    time : u64,
    /** Its share, time over period, in millionths of a CPU. */
    share : u64,
    /** How much of its share its children have together, in millionths of a CPU, at most share. */
    children_share : u64,
    /** The CPUs its threads may run on, a bit per CPU's index. */
    cpus : u64,
}

/** How many words cpu_budget_info writes: one for each of CpuBudgetInfo's fields. */
CPU_BUDGET_INFO_WORDS :: 6

/**
 * Describe a CPU budget: cpu_budget_info's words, as a CpuBudgetInfo. Needs no context.
 *
 * @param budget The budget; no right is needed.
 * @return What the budget is, or null if cpu_budget_info failed: the handle isn't a CPU budget's, or it's gone.
 */
cpu_budget_describe :: fn(budget: CpuBudget) -> CpuBudgetInfo? #no_context {
    words : u64[CPU_BUDGET_INFO_WORDS]
    if cpu_budget_info(budget, words) is_error {
        return null
    }
    return CpuBudgetInfo.{priority = words[0], period = words[1], time = words[2], share = words[3], children_share = words[4],
        cpus = words[5]}
}

/** The most of a line debug_log writes, in bytes; the rest is dropped. */
DEBUG_LOG_LINE : u64 : 200

/**
 * How a process ended, in the data[1] of the Signal packet its SIGNAL_TERMINATED raises: the code it
 * gave process_exit, or EXIT_KILLED when it was killed, which no code can be.
 */
EXIT_KILLED : u64 : 1 << 32

#insert syscall_numbers()
#insert syscall_stubs()

/**
 * Give a call's bit, for intercept_attach's calls.
 *
 * @param number The call's number (SYSCALL_<NAME>), below 64 for the bit to mean anything.
 * @return The call's bit; 0 for numbers 64 and up on x86-64, whose shifts wrap.
 */
syscall_bit :: fn(number: u32) -> u64 #no_context {
    return cast[u64](1) << cast[u64](number)
}

/** What handle_info gives. */
HandleInfo :: struct {
    /** The kind of object the handle is to. */
    kind : ObjectKind,
    /** The rights the handle has. */
    rights : Rights,
}

/** What channel_create gives: owning handles to a new channel's two ends. */
ChannelPair :: struct {
    /** End A, which writes the first ring and reads the second. */
    a : Channel,
    /** End B, which writes the second ring and reads the first. */
    b : Channel,
}

/** What channel_read gives: the message's size, and its flags and batch (MessageHeader's). */
MessageInfo :: struct {
    /** The payload's size in bytes, without its header. */
    size : u32,
    /** The header's flags in the low 16 bits and its handle batch in the high 16, as MessageHeader lays them out. */
    flags_and_batch : u32,
}

/** What memory_budget_info gives. */
BudgetInfo :: struct {
    /** The most the budget can charge, in bytes. */
    limit : u64,
    /** How much it has charged, in bytes, at most limit. */
    used : u64,
}

/** What controller_register gives. */
ControllerInfo :: struct {
    /** The controller's number, for irq_create. */
    number : u32,
    /** How many lines it has: irq_create's lines are below it. */
    lines : u32,
}

/**
 * What irq_message gives: what a device writes, and where, to raise a message-signaled interrupt (PCIe MSI and MSI-X).
 */
MsiMessage :: struct {
    /** The address the device writes to. */
    address : u64,
    /** The value it writes. */
    data : u32,
}

/**
 * Make a PCIe function's address, for device_create: its segment, then its requester ID.
 *
 * @param segment The PCI segment group the function is in, as the firmware tables number it, put in the high 16 bits; 0
 *     on a machine with one.
 * @param bus The bus number within the segment, 0 to 255, put in bits 8 to 15.
 * @param device The device number, 0 to 31; higher bits are dropped.
 * @param function The function number, 0 to 7; higher bits are dropped.
 * @return The address: segment in the high 16 bits, then bus, device and function.
 */
device_address :: fn(segment: u16, bus: u8, device: u8, function: u8) -> u32 #no_context {
    return cast[u32](segment) << 16 | cast[u32](bus) << 8 | (cast[u32](device) & 0x1f) << 3 | (cast[u32](function) & 7)
}

// For intercept_attach's points: where threads stop. Its calls is a bit per syscall number below 64.
/** At the entry of a system call in intercept_attach's calls, before it runs. */
STOP_SYSCALL_ENTRY : u32 : 1 << 0
/** At the exit of a system call in intercept_attach's calls, before user mode sees its result. */
STOP_SYSCALL_EXIT : u32 : 1 << 1
/** A fault the thread's memory doesn't resolve, which would otherwise destroy it. */
STOP_FAULT : u32 : 1 << 2

/** Where a thread stopped, in a StopInfo. */
StopPoint :: enum #backed_by(u32) {
    /** At a system call's entry (STOP_SYSCALL_ENTRY). */
    SyscallEntry = 1,
    /** At a system call's exit (STOP_SYSCALL_EXIT). */
    SyscallExit = 2,
    /** At a fault (STOP_FAULT). */
    Fault = 3,
}

/** One stop, as intercept_next writes it. */
StopInfo :: struct {
    /** The stopped thread's ID, for intercept_resume. */
    thread : u64,
    /** Where it stopped. */
    point : StopPoint,
    /** The system call's number, or for a fault, how it accessed: 0 read, 1 write, 2 execute. */
    number : u32,
    /** For a fault: the address it touched. Meaningless otherwise. */
    address : u64,
}

/** What a thread stopped by an intercept does next, for intercept_resume. */
InterceptAction :: enum #backed_by(u32) {
    /**
     * Run the system call, with any registers changed (entry); return to user mode (exit); retry the access (fault).
     */
    Continue = 1,
    /** Entry only: don't run the system call; return with the registers as written. */
    Skip = 2,
    /** Destroy the thread. */
    Kill = 3,
}

/*
 * ThreadReadRegisters' and ThreadWriteRegisters' registers, u64s, in this order on x86-64: rax, rbx, rcx,
 * rdx, rsi, rdi, rbp, rsp, r8 to r15, rip, rflags. Writing rflags changes only its status flags and DF.
 * On AArch64: x0 to x30, sp, pc, pstate; writing pstate changes only its condition flags (NZCV).
 */
#if TARGET_ARCH == .arm64 {
    /** How many registers thread_read_registers and thread_write_registers take: x0 to x30, sp, pc and pstate. */
    THREAD_REGISTERS : u32 : 34
}
#else {
    /** How many registers thread_read_registers and thread_write_registers take: x86-64's 16, rip and rflags. */
    THREAD_REGISTERS : u32 : 18
}

/** For controller_register: the kinds of interrupt controller. */
ControllerKind :: enum #backed_by(u32) {
    /** An x86 I/O APIC. */
    IoApic = 1,
    /** An Arm GIC's distributor. */
    GicDistributor = 2,
    /** A RISC-V platform-level interrupt controller. */
    Plic = 3,
}

/**
 * For dma_domain_create: the domain's DMA memory may be made where no IOMMU confines its devices, for a trusted
 * driver.
 */
DMA_DOMAIN_TRUSTED : u32 : 1 << 0

/** For iommu_register: the kinds of IOMMU. */
IommuKind :: enum #backed_by(u32) {
    /** Intel VT-d. */
    VtD = 1,
    /** AMD-Vi. */
    AmdVi = 2,
    /** Arm SMMUv3. */
    Smmuv3 = 3,
    /** The RISC-V IOMMU. */
    RiscV = 4,
}

// For irq_create's flags: how the line signals, from the firmware tables. Edge-triggered and active-high without them.
/** The line is level-triggered, and irq_ack unmasks it after each interrupt. */
IRQ_LEVEL : u32 : 1 << 0
/** The line is active-low. */
IRQ_ACTIVE_LOW : u32 : 1 << 1

/** For memory_create_physical: how device memory is cached. */
CacheMode :: enum #backed_by(u32) {
    /** Cached normally, for memory that behaves like RAM. */
    WriteBack = 1,
    /** Uncached, with writes combined, for frame buffers. */
    WriteCombining = 2,
    /** Uncached and strongly ordered, for device registers. */
    Device = 3,
}

/** For memory_map: how a mapping can be reached, a bit set. Writable and executable at once is refused. */
Protection :: distinct alias u32
/** Readable; every mapping has to be. */
PROTECTION_READ : Protection : 1 << 0
/** Writable. */
PROTECTION_WRITE : Protection : 1 << 1
/** Executable. */
PROTECTION_EXECUTE : Protection : 1 << 2

/** For port_wait: wait for as long as it takes. */
NO_DEADLINE : u64 : 0xffffffffffffffff
/** The most packets one port_wait gives. */
MAX_PACKETS_PER_WAIT : u32 : 64

/** What a Packet reports. */
PacketKind :: enum #backed_by(u32) {
    /** An object's signals: data[0] is the signals seen. */
    Signal = 1,
    /** A timer's deadline came: data[0] is the deadline. */
    Timer = 2,
    /** A port_wake: data[0] is every bit raised since the packet was last taken. */
    User = 3,
    /** An IRQ's: data[0] is how many interrupts arrived since the packet was last taken. */
    Irq = 4,
    /**
     * An intercept's: data[0] is how many threads stopped since the packet was last taken (intercept_next reports
     * them).
     */
    Stop = 5,
}

/** One event, as port_wait writes it (knowledge/design/ipc.md §3). Its layout is part of the system ABI. */
Packet :: struct {
    /** The key of the binding that raised it. */
    key : u64,
    /** What it reports, which says what data holds. */
    kind : PacketKind,
    /** Unused, 0. */
    reserved : u32,
    /**
     * What it reports, as kind says. A Signal packet's data[1] is SIGNAL_TERMINATED's exit code or EXIT_KILLED, or
     * SIGNAL_DMA_FAULT's device address; otherwise it's 0.
     */
    data : u64[2],
}

#assert size_of(Packet) == 32

/** What an object can raise, for a port binding to see: a bit set. */
Signals :: distinct alias u32
/** A channel end: the other end wrote a message. */
SIGNAL_READABLE : Signals : 1 << 0
/** A channel end: the other end made room. */
SIGNAL_WRITABLE : Signals : 1 << 1
/** A channel end: the other end is closed. It stays raised. */
SIGNAL_PEER_CLOSED : Signals : 1 << 2
/** A process or a thread: destroyed. It stays raised. */
SIGNAL_TERMINATED : Signals : 1 << 3
/** A Device: an IOMMU blocked its DMA, at the device address in the Signal packet's data[1]. */
SIGNAL_DMA_FAULT : Signals : 1 << 4
/** A MemoryBudget: what it has charged reached its threshold (memory_budget_set_threshold). */
SIGNAL_PRESSURE : Signals : 1 << 5
/**
 * A Memory, bound through its owning handle: no one holds it besides its owner any more (memory_holders fell to 0): no
 * other handle to it, no mapping, no window (the SlopOS repository's decisions/0178). Raised each time it falls to 0.
 */
SIGNAL_UNHELD : Signals : 1 << 6

/** How long a port binding lasts. */
BindMode :: enum #backed_by(u32) {
    /** Disarmed once its packet is queued; port_bind with the same key and object arms it again. */
    Once = 1,
    /** Armed until port_unbind, its packet queued again each time it's raised after being taken. */
    Persistent = 2,
}

/*
 * A channel's memory (knowledge/design/ipc.md §2), as channel_map maps it: each direction's indices,
 * then end A's ring, which it writes and B reads, then B's. Rings are a power of two in size, so
 * indices are byte counts that wrap, never reduced.
 */
/** The ring size channel_create gives for a ring_bytes of 0, in bytes. */
CHANNEL_DEFAULT_RING : u32 : 1024
/** The smallest ring, in bytes. */
CHANNEL_MIN_RING : u32 : 1024
/** The largest ring, in bytes. */
CHANNEL_MAX_RING : u32 : 131072
/** Where end A's ring starts in a channel's memory, in bytes, after both directions' RingIndices. */
CHANNEL_RINGS_OFFSET : u32 : 256

/**
 * One direction's indices: the producer's and the consumer's on separate cache lines. Both ends can write them, so
 * each treats what it reads from them as untrusted.
 */
RingIndices :: struct #align(64) {
    /** The producer's: bytes committed, ever, wrapping; written with a release store once a message is whole. */
    tail : u32,
    /** The producer's: nonzero while it waits for room, for the consumer to raise Writable. */
    producer_waiting : u32,
    /** Unused, keeping the consumer's on its own cache line. */
    reserved0 : u8[56],
    /** The consumer's: bytes consumed, ever, wrapping. */
    head : u32,
    /** The consumer's: nonzero while it waits for a message, for the producer to raise Readable. */
    consumer_waiting : u32,
    /** Unused, filling the cache line. */
    reserved1 : u8[56],
}

#assert size_of(RingIndices) == 128

/** Before every message in a ring, which is padded to 8 bytes. */
MessageHeader :: struct {
    /** The payload's size in bytes, after this header and without its padding. */
    size : u32,
    /** MESSAGE_ bits. */
    flags : u16,
    /** With MESSAGE_HAS_HANDLES: the batch its handles are in. */
    handle_batch : u16,
}

#assert size_of(MessageHeader) == 8

/** A MessageHeader flag: the message carries a handle batch, named by its handle_batch. */
MESSAGE_HAS_HANDLES : u16 : 1 << 0
/** For channel_write: a message without handles. */
NO_BATCH : u32 : 0xffff
/** How many handle batches can be in flight to each end at once; batches are numbered below it. */
HANDLE_BATCHES : u32 : 16
/** The most handles one batch holds. */
MAX_HANDLES_PER_BATCH : u32 : 64

/**
 * Give the size of a channel's memory, as channel_map maps it.
 *
 * @param ring_bytes Each ring's size in bytes, as channel_create took it (not 0).
 * @return The bytes channel_map maps: the indices and both rings, rounded up to whole 4 KiB pages.
 */
channel_memory_size :: fn(ring_bytes: u32) -> u64 {
    return (cast[u64](CHANNEL_RINGS_OFFSET) + 2 * cast[u64](ring_bytes) + 4095) & ~cast[u64](4095)
}

/**
 * Give the largest payload a ring takes: a message is at most half the ring, and 64 KiB, its header included.
 *
 * @param ring_bytes The ring's size in bytes, from CHANNEL_MIN_RING to CHANNEL_MAX_RING.
 * @return The largest payload in bytes, without its header.
 */
channel_max_payload :: fn(ring_bytes: u32) -> u32 {
    half :: ring_bytes / 2
    return (if half < 65536 { half } else { 65536 }) - cast[u32](size_of(MessageHeader))
}

/** What a call on a handle can fail with. */
HandleError :: enum #backed_by(u32) {
    /** Not a handle of this process, or one already closed. */
    InvalidHandle = 1,
    /** The object was destroyed. */
    ObjectGone = 2,
    /** The handle lacks a right the call needs. */
    MissingRight = 3,
    /** The handle isn't to the kind of object the call takes. */
    WrongKind = 4,
    /** The process's handle table is full. */
    TableFull = 5,
    /** The kernel has no memory for what the call makes. */
    OutOfMemory = 6,
    /** A number the kernel doesn't have. */
    NoSuchCall = 7,
    /** Memory the call reads isn't the caller's to. */
    BadBuffer = 10,
    /** The budget can't pay for it (decisions/0011). */
    BudgetExceeded = 25,
    /** A number the call can't take, like a CPU budget's period of 0. */
    InvalidArgument = 46,
}

/** What a call on a port can fail with. Tags shared with HandleError mean the same. */
PortError :: enum #backed_by(u32) {
    /** Not a handle of this process, or one already closed. */
    InvalidHandle = 1,
    /** The object was destroyed. */
    ObjectGone = 2,
    /** The handle lacks a right the call needs. */
    MissingRight = 3,
    /** The handle isn't to the kind of object the call takes. */
    WrongKind = 4,
    /** The kernel has no memory for the binding or the port. */
    OutOfMemory = 6,
    /** The key is bound already. */
    KeyInUse = 8,
    /** No binding has that key, or not one of that kind. */
    NoSuchKey = 9,
    /** Packets would go somewhere the thread can't write. */
    BadBuffer = 10,
    /** The object has as many bindings as it takes. */
    TooManyBindings = 11,
    /** The budget can't pay for it (decisions/0011). */
    BudgetExceeded = 25,
}

/** What a call on a channel can fail with. Tags shared with HandleError and PortError mean the same. */
ChannelError :: enum #backed_by(u32) {
    /** Not a handle of this process, or one already closed. */
    InvalidHandle = 1,
    /** The object was destroyed. */
    ObjectGone = 2,
    /** The handle lacks a right the call needs. */
    MissingRight = 3,
    /** The handle isn't to the kind of object the call takes. */
    WrongKind = 4,
    /** The process's handle table is full. */
    TableFull = 5,
    /** The kernel has no memory for what the call makes. */
    OutOfMemory = 6,
    /** Memory the call reads or writes isn't the caller's to. */
    BadBuffer = 10,
    /** The other end is closed. */
    PeerClosed = 12,
    /** No room in the ring for the message. */
    Full = 13,
    /** No message in the ring. */
    Empty = 14,
    /**
     * More than the call takes: a message bigger than channel_max_payload, or a batch of more than
     * MAX_HANDLES_PER_BATCH.
     */
    TooBig = 15,
    /** The message doesn't fit in the buffer; the call's first value is its size. */
    BufferTooSmall = 16,
    /** The end's rings are mapped already, or it can't be sent while they are. */
    Mapped = 17,
    /** Not a page-aligned user address, or something is mapped there. */
    BadAddress = 18,
    /** The batch is in use. */
    BatchInUse = 19,
    /** There's no such batch to take. */
    NoSuchBatch = 20,
    /** The other end broke the ring: its indices or a header are impossible. */
    Corrupt = 21,
    /** A handle can't go through this channel: one of its own ends. */
    NotTransferable = 22,
    /** The end is in a batch in flight. */
    InFlight = 23,
    /** Rings must be a power of two from CHANNEL_MIN_RING to CHANNEL_MAX_RING. */
    InvalidSize = 24,
    /** The budget can't pay for it (decisions/0011). */
    BudgetExceeded = 25,
}

/** What a call on a memory budget or a memory object can fail with. Tags shared with the others mean the same. */
MemoryError :: enum #backed_by(u32) {
    /** Not a handle of this process, or one already closed. */
    InvalidHandle = 1,
    /** The object was destroyed. */
    ObjectGone = 2,
    /** The handle lacks a right the call needs. */
    MissingRight = 3,
    /** The handle isn't to the kind of object the call takes. */
    WrongKind = 4,
    /** The process's handle table is full. */
    TableFull = 5,
    /** The kernel has no memory for what the call makes. */
    OutOfMemory = 6,
    /** Not a page-aligned user address range, or it overlaps a mapping. */
    BadAddress = 18,
    /** Not a whole number of pages, none at all, more than MAX_MEMORY_SIZE, or past the memory object's end. */
    InvalidSize = 24,
    /** The budget can't pay for it (decisions/0011). */
    BudgetExceeded = 25,
    /** No mapping starts at that address. */
    NotMapped = 26,
    /** Writable and executable at once, or no access at all. */
    BadProtection = 27,
    /** The port has no wake binding with that key, or is gone. */
    NoPager = 28,
    /** No page of the paged memory is waited for that hasn't been reported. */
    NothingWanted = 29,
    /** Not paged memory. */
    NotPaged = 30,
    /** A page of paged memory that hasn't been supplied. */
    NotSupplied = 31,
    /** A page mapped in more address spaces than memory_evict takes it from at once. */
    MappedWidely = 32,
}

/** The largest memory object, 1 GiB, in bytes. */
MAX_MEMORY_SIZE : u64 : 1 << 30

/** What process control can fail with. Tags shared with the others mean the same. */
ControlError :: enum #backed_by(u32) {
    /** Not a handle of this process, or one already closed. */
    InvalidHandle = 1,
    /** The object was destroyed. */
    ObjectGone = 2,
    /** The handle lacks a right the call needs. */
    MissingRight = 3,
    /** The handle isn't to the kind of object the call takes. */
    WrongKind = 4,
    /** The process's handle table is full. */
    TableFull = 5,
    /** The kernel has no memory for what the call makes. */
    OutOfMemory = 6,
    /** Memory the call reads or writes isn't there, or isn't the caller's to. */
    BadBuffer = 10,
    /** From intercept_next: no stop is left to report. */
    Empty = 14,
    /** From process_give_handles: more than MAX_HANDLES_PER_BATCH handles. */
    TooBig = 15,
    /** The address space isn't in the process's subtree, or the range isn't mapped. */
    BadAddress = 18,
    /** From process_give_handles: a handle that can't go to the process, like an owning one to it or above it. */
    NotTransferable = 22,
    /** The budget can't pay for it (decisions/0011). */
    BudgetExceeded = 25,
    /** No thread with that ID in the subtree, or none the intercept stopped. */
    NoSuchThread = 34,
    /** The thread isn't stopped or suspended, or (Skip) isn't stopped at a system call's entry. */
    NotStopped = 35,
    /** The process is intercepted already. */
    AlreadyIntercepted = 36,
    /** A register value user mode can't have. */
    BadRegisters = 37,
}

/**
 * What registering a controller, making an IRQ or device memory can fail with. Tags shared with the others mean the
 * same.
 */
DeviceError :: enum #backed_by(u32) {
    /** Not a handle of this process, or one already closed. */
    InvalidHandle = 1,
    /** The object was destroyed. */
    ObjectGone = 2,
    /** The handle lacks a right the call needs. */
    MissingRight = 3,
    /** The handle isn't to the kind of object the call takes. */
    WrongKind = 4,
    /** The process's handle table is full. */
    TableFull = 5,
    /** The kernel has no memory for what the call makes, or to map the controller's registers. */
    OutOfMemory = 6,
    /** Not page-aligned, or memory the kernel owns. */
    BadAddress = 18,
    /** A size the call can't take: not a whole number of pages, none, or too big. */
    InvalidSize = 24,
    /** The budget can't pay for it (decisions/0011). */
    BudgetExceeded = 25,
    /** No controller of that kind there, or the architecture has none of that kind. */
    NoController = 28,
    /** Every controller the kernel takes is registered. */
    TooManyControllers = 29,
    /** No registered controller has that number. */
    NoSuchController = 30,
    /** The controller has no line of that number. */
    NoSuchLine = 31,
    /** The line already has an IRQ. */
    LineInUse = 32,
    /** No CPU has a device interrupt free. */
    NoFreeInterrupt = 33,
    /** Not memory made for DMA (memory_device_address), or its domain is gone. */
    NotDmaMemory = 38,
    /** No interrupt controller here takes message-signaled interrupts, or the IRQ isn't message-signaled. */
    NoMsi = 39,
    /** The device has as many message-signaled IRQs as it can (MAX_DEVICE_MSIS). */
    TooManyVectors = 40,
    /** Another device has that address, or, where the interrupt controller uses sources, that MSI source. */
    DeviceExists = 41,
    /** No IOMMU of that kind there, or none the kernel can drive. */
    NoIommu = 42,
    /** Every IOMMU the kernel takes is registered, or every range of requester IDs one covers. */
    TooManyIommus = 43,
    /** The device isn't behind the IOMMU its domain's other devices are, or behind none where they're behind one. */
    WrongIommu = 44,
    /** DMA memory in a domain no IOMMU translates, which wasn't made trusted (DMA_DOMAIN_TRUSTED). */
    Untrusted = 45,
    /**
     * Ports outside the range, a width that isn't 1, 2 or 4, or ports where the architecture has none; or a CPU that
     * isn't online, or isn't the caller's CPU budget's.
     */
    InvalidArgument = 46,
    /** The kernel has no way to turn this machine off: no power_set_off on x86-64, or no PSCI on AArch64. */
    NoPowerOff = 47,
}

/** For power_end_with: what the kernel does once the root task ends. */
PowerAction :: enum #backed_by(u32) {
    /** Halt every CPU, leaving the machine on: what it does when nothing's been asked. */
    Halt = 1,
    /** Turn the machine off: ACPI's S5 on x86-64, PSCI's SYSTEM_OFF on AArch64. */
    Off = 2,
    /** Reset the machine, warm, so it boots again. */
    Restart = 3,
}

/** The most message-signaled IRQs one device has at once. */
MAX_DEVICE_MSIS : u32 : 32

/**
 * Variable-size data in a protocol's message (the SlopOS repository's decisions 0040, 0071): count Ts after the
 * message's fixed part, at offset bytes from the message's start, aligned for T. A message's generated validator
 * checks it's inside the message before anything reads it (std/os's protocol_code).
 *
 * @tparam T The elements' type.
 */
Relative :: struct[T] {
    /** Where the elements start, in bytes from the message's start, aligned for T; untrusted until validated. */
    offset : u32,
    /** How many elements, not bytes; 0 for none. */
    count : u32,
    /** Holds nothing; it names T for the validator. */
    elements : T[0],
}

/** A handle field of a message as it travels: its index in the message's batch, or this for none. */
NO_HANDLE_INDEX : u32 : 0xffffffff

/**
 * What a protocol package says of itself, as its PROTOCOL (decisions/0040).
 */
Protocol :: struct {
    /** The protocol's name. */
    name : string,
    /** Its major version: a new one for any change that isn't only appending. */
    major_version : u32,
    /** Who pays for the server's work (decisions/0037). */
    lending : Lending,
}

/** Who pays for a server's work on a protocol's connections (decisions/0037). */
Lending :: enum {
    /** The client's budget, lent for each of its connections. */
    PerConnection,
    /** The server's own. */
    Server,
}

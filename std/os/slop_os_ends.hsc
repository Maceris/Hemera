package os


/*
 * SlopOS's side of std/os (the SlopOS repository's decisions 0040, 0044, 0068): channels typed by the
 * protocol they speak, sending and receiving fixed-layout messages on them, and launching programs through
 * the process manager, typed by the program's entry.
 *
 *     main :: fn(log: slop_os.DebugLog?, manager: os.Channel[process_manager.ProcessManager]) -> int {
 *         ...
 *         launched :: os.launch(manager, port, "hello", module, 2 * MIB, hello.main, HelloGrants.{log = copy})?
 *     }
 *
 * A program's entry takes its grants as parameters, named after them (docs/compilation.md, Entry
 * Parameters); exit, the clock and random numbers are base's and std's as on any system.
 */
#if OS == .SlopOS {
    import compiler from "base"
    import runtime from "base"
    import slop_os from "std/os"
    import process_manager from "std/os/slop_os"

    /**
     * A channel end that speaks protocol P.
     *
     * An entry parameter of one is the grant of its name, and where one arrives, as a grant or in a message, its
     * channel's tag has to be P's (protocol_tag), or it's refused.
     *
     * @tparam P The protocol: a type named after it, like process_manager.ProcessManager. Only its name is used.
     */
    Channel :: struct[P] {
        /** The end itself, a handle in the caller's table, which whoever holds the Channel[P] owns and closes. */
        end : slop_os.Channel,
    }

    /**
     * A channel end that connections to a P arrive on, each a message with the connection's end as its one handle.
     *
     * An entry parameter of one is the grant of its name, checked as a Channel[P]'s is.
     *
     * @tparam P The protocol the connections speak, as Channel[P] names it.
     */
    Listener :: struct[P] {
        /** The end connections arrive on, a handle in the caller's table, which its holder owns and closes. */
        end : slop_os.Channel,
    }

    /**
     * The reading end of a stream (std/os/slop_os's stream), which reads records of T.
     *
     * The Sink[T] at its other end writes them. Their channel is tagged with the stream protocol, whatever T is, and T
     * is checked when the stream opens. records is no bytes, there so T is in their schemas: a manifest says what
     * records a program reads and writes, for a launcher, like a shell, that connects them, checks they're the same,
     * and reads them.
     *
     * @tparam T The records' type.
     */
    Stream :: struct[T] #packed #align(4) {
        /** The channel end, tagged with the stream protocol; its holder owns and closes it. */
        end : slop_os.Channel,
        /** No bytes: only there so T is in the type's schema. */
        records : T[0],
    }

    /**
     * The writing end of a stream (std/os/slop_os's stream), which writes records of T for the Stream[T] at its
     * other end, tagged and checked as Stream[T] is.
     *
     * @tparam T The records' type.
     */
    Sink :: struct[T] #packed #align(4) {
        /** The channel end, tagged with the stream protocol; its holder owns and closes it. */
        end : slop_os.Channel,
        /** No bytes: only there so T is in the type's schema. */
        records : T[0],
    }

    /**
     * Compute the tag of the protocol P (decisions/0040, 0071).
     *
     * A channel for P is made with it (channel_create), and the end of a Channel[P] or Listener[P] has to have it
     * where it arrives: as an entry's parameter, or in a message.
     *
     * @tparam P The protocol, by its type's name without its package.
     * @return The 64-bit FNV-1a hash of P's name; never 0 in practice, which means no protocol.
     */
    protocol_tag :: fn[P]() -> u64 {
        return end_tag(type_info_of(Channel[P]))
    }

    /**
     * Make a new channel for P, both ends tagged with its protocol_tag.
     *
     * @tparam P The protocol its ends speak.
     * @param budget The memory budget its rings are charged to.
     * @param ring_bytes How many bytes each way's ring holds: 0 for the kernel's default, or else a power of two from
     *     CHANNEL_MIN_RING to CHANNEL_MAX_RING. A message is at most half of it (channel_max_payload).
     * @return Its two ends, new handles in the caller's table, which the caller owns.
     * @error InvalidSize The ring_bytes isn't 0 or a power of two in range.
     * @error BudgetExceeded The budget can't pay for the rings.
     * @error OutOfMemory The kernel had no memory for them.
     * @error TableFull The caller's handle table has no room for the ends.
     * @error InvalidHandle The budget isn't a handle of the caller's.
     * @error WrongKind The budget isn't a memory budget.
     * @error MissingRight The budget lacks the right to be charged.
     */
    channel_for :: fn[P](budget: slop_os.MemoryBudget, ring_bytes: u32) -> Result[slop_os.ChannelPair, slop_os.ChannelError] {
        return slop_os.channel_create(budget, ring_bytes, protocol_tag[P]())
    }

    /**
     * Check whether a channel end was made for P.
     *
     * @tparam P The protocol asked about.
     * @param end The end, which stays the caller's.
     * @return True if its channel's tag is P's protocol_tag; false for another tag, or when the tag can't be read (a
     *     closed or invalid handle).
     */
    speaks :: fn[P](end: slop_os.Channel) -> bool {
        return (slop_os.channel_tag(end) or_else 0) == protocol_tag[P]()
    }

    /**
     * Compute the protocol tag that a channel end's type needs where it arrives.
     *
     * @param type The type: a Channel[P] or Listener[P], a Stream[T] or Sink[T], or anything else.
     * @return For a Channel[P] or Listener[P], the FNV-1a hash of P's name without its package; for a Stream[T] or
     *     Sink[T], the stream protocol's tag, name_tag("Stream"); and 0, meaning no protocol, for any other type.
     */
    end_tag :: fn(type: ptr[compiler.TypeInfo]) -> u64 {
        if type.variant != .STRUCT {
            return 0
        }
        name :: cast[ptr[compiler.TypeInfoStruct]](type).name
        start : usize = 0
        if starts_with(name, "Stream[") || starts_with(name, "Sink[") {
            return name_tag("Stream")
        }
        if starts_with(name, "Channel[") {
            start = 8
        }
        else if starts_with(name, "Listener[") {
            start = 9
        }
        else {
            return 0
        }
        // P's own name, without its package or the closing bracket
        end := name.count - 1
        from := start
        for i in start..<end {
            if name[i] == '.' {
                from = i + 1
            }
        }
        // FNV-1a, 64-bit
        hash : u64 = 0xcbf29ce484222325
        for i in from..<end {
            hash = (hash ~ cast[u64](cast[u8](name[i]))) * 0x100000001b3
        }
        return hash
    }

    /**
     * Compute the tag of the protocol named name, as its channels carry it.
     *
     * @param name The protocol's name without its package, like "Stream"; its bytes are hashed as they are.
     * @return The 64-bit FNV-1a hash of name's bytes.
     */
    name_tag :: fn(name: string) -> u64 {
        hash : u64 = 0xcbf29ce484222325
        for character in name {
            hash = (hash ~ cast[u64](cast[u8](character))) * 0x100000001b3
        }
        return hash
    }

    /**
     * Check whether text starts with prefix, byte for byte.
     *
     * @param text The text looked in.
     * @param prefix What it has to start with; "" starts every text.
     * @return True if text's first bytes are prefix's.
     */
    starts_with :: fn(text: string, prefix: string) -> bool {
        return text.count >= prefix.count && string_of(cast[ptr[u8]](text.data), prefix.count) == prefix
    }

    // ---- Messages: fixed-layout structs, sent as their bytes

    /** What receive and try_receive give: the message's size, and how many handles came with it. */
    Received :: struct {
        /** The message's size in bytes, at most the buffer's count. */
        size : u32,
        /** How many handles came with it, at the start of the handles given; 0 for a message without any. */
        handle_count : u32,
    }

    /**
     * View a fixed-layout message as its bytes, for send.
     *
     * @tparam T The message's type.
     * @param message The message; it isn't copied.
     * @return Its size_of(T) bytes, good as long as message is.
     */
    bytes_of :: fn[T](message: ptr[T]) -> u8[] {
        return view_of(cast[ptr[u8]](message), size_of(T))
    }

    /**
     * View a fixed-layout message as bytes that can be written, for receive to read into.
     *
     * @tparam T The message's type.
     * @param message The message; it isn't copied.
     * @return Its size_of(T) bytes, good as long as message is.
     */
    mut_bytes_of :: fn[T](message: ptr[mut T]) -> mut u8[] {
        return view_of(cast[ptr[mut u8]](message), size_of(T))
    }

    /**
     * Send a message through a channel end, waiting while its ring is full.
     *
     * The handles go first, in the first of the other end's HANDLE_BATCHES batches that's free, then the bytes, which
     * name that batch.
     *
     * @param end The end it's sent through, which stays the caller's.
     * @param port A port bound to end (port_for), waited on while the ring is full; nothing else should be bound to it,
     *     as the packets it gives while waiting are dropped.
     * @param bytes The message, at most channel_max_payload of the ring's size.
     * @param handles At most MAX_HANDLES_PER_BATCH handles that go with it, moved out of the caller's table once
     *     they're sent, so they're no longer the caller's; none for a message without handles.
     * @return Null once it's sent; otherwise why not, from the kernel: BatchInUse when every batch is in use,
     *     PeerClosed when the other end is closed, TooBig, and the like. If the bytes fail after the handles were sent,
     *     the handles are gone from the caller's table anyway.
     */
    send :: fn(end: slop_os.Channel, port: slop_os.Port, bytes: u8[], handles: slop_os.Handle[]) -> slop_os.ChannelError? {
        batch := slop_os.NO_BATCH
        if handles.count != 0 {
            batch = 0
            loop {
                match slop_os.channel_send_handles(end, handles, batch) {
                    case Ok => break
                    case Error(error) => {
                        if error != .BatchInUse || batch + 1 >= slop_os.HANDLE_BATCHES {
                            return error
                        }
                        batch += 1
                    }
                }
            }
        }
        loop {
            match slop_os.channel_write(end, bytes, batch) {
                case Ok => return null
                case Error(error) => {
                    if error != .Full {
                        return error
                    }
                    packets : slop_os.Packet[4]
                    _ = slop_os.port_wait(port, packets, slop_os.NO_DEADLINE)
                }
            }
        }
    }

    /**
     * Receive the next message from a channel end, without waiting.
     *
     * @param end The end it's read from, which stays the caller's.
     * @param buffer Where the message's bytes go; it should hold the largest message expected.
     * @param handles Where the handles that came with it go, now the caller's to close.
     * @return The message's size and how many handles came with it.
     * @error Empty There's no message yet; the end's next message raises SIGNAL_READABLE.
     * @error BufferTooSmall The message doesn't fit in buffer.
     * @error PeerClosed The other end is closed.
     * @error InvalidHandle The end isn't a handle of the caller's.
     * @error Corrupt The other end broke the ring.
     */
    try_receive :: fn(end: slop_os.Channel, buffer: mut u8[], handles: mut slop_os.Handle[]) -> Result[Received, slop_os.ChannelError] {
        info :: slop_os.channel_read(end, buffer, cast[ptr[mut u32]](0))?
        received := Received.{size = info.size}
        if info.flags_and_batch & cast[u32](slop_os.MESSAGE_HAS_HANDLES) != 0 {
            received.handle_count = slop_os.channel_take_handles(end, info.flags_and_batch >> 16, handles, cast[ptr[mut u32]](0))?
        }
        return .Ok(received)
    }

    /**
     * Receive the next message from a channel end, as try_receive does, waiting on port until one comes.
     *
     * @param end The end it's read from, which stays the caller's.
     * @param port A port bound to end (port_for), waited on with no deadline; the packets it gives are dropped.
     * @param buffer Where the message's bytes go; it should hold the largest message expected.
     * @param handles Where the handles that came with it go, now the caller's to close.
     * @return The message's size and how many handles came with it.
     * @error ObjectGone Waiting on port failed.
     * @error BufferTooSmall The message doesn't fit in buffer.
     * @error PeerClosed The other end is closed.
     * @error InvalidHandle The end isn't a handle of the caller's.
     * @error Corrupt The other end broke the ring.
     */
    receive :: fn(end: slop_os.Channel, port: slop_os.Port, buffer: mut u8[], handles: mut slop_os.Handle[]) -> Result[Received, slop_os.ChannelError] {
        loop {
            match try_receive(end, buffer, handles) {
                case Ok(received) => return .Ok(received)
                case Error(error) => {
                    if error != .Empty {
                        return .Error(error)
                    }
                    packets : slop_os.Packet[4]
                    _ = slop_os.port_wait(port, packets, slop_os.NO_DEADLINE) or_return .Error(.ObjectGone)
                }
            }
        }
    }

    /**
     * Make a port for send and receive to wait on with one end.
     *
     * @param budget The memory budget the port is charged to.
     * @param end The end it's bound to, persistently, for SIGNAL_READABLE, SIGNAL_WRITABLE and SIGNAL_PEER_CLOSED,
     *     under key 0. It stays the caller's.
     * @return The port, a new handle the caller owns and closes; null if it couldn't be made or bound, with nothing
     *     left behind.
     */
    port_for :: fn(budget: slop_os.MemoryBudget, end: slop_os.Channel) -> slop_os.Port? {
        port :: slop_os.port_create(budget) or_return null
        signals :: cast[slop_os.Signals](cast[u32](slop_os.SIGNAL_READABLE) | cast[u32](slop_os.SIGNAL_WRITABLE) | cast[u32](slop_os.SIGNAL_PEER_CLOSED))
        match slop_os.port_bind(port, cast[slop_os.Handle](end), signals, 0, .Persistent) {
            case Ok => return port
            case Error(error) => {
                _ = slop_os.handle_close(cast[slop_os.Handle](port))
                return null
            }
        }
    }

    /**
     * Send a request and wait for its reply.
     *
     * @param end The end both go through, which stays the caller's.
     * @param port A port bound to end (port_for).
     * @param request The request's bytes, as send takes them.
     * @param handles The handles that go with it, moved out of the caller's table, as send moves them.
     * @param reply Where the reply's bytes go. There's room for one handle with it, which is taken into the caller's
     *     table and not given back, so a reply shouldn't carry any.
     * @return The reply's size, and how many handles came with it.
     * @error PeerClosed The other end is closed.
     * @error BatchInUse Every batch of the other end's is in use, so the request wasn't sent.
     * @error TooBig The request is bigger than the ring takes.
     * @error BufferTooSmall The reply, or its handles, didn't fit.
     * @error ObjectGone Waiting on port failed.
     */
    call :: fn(end: slop_os.Channel, port: slop_os.Port, request: u8[], handles: slop_os.Handle[], reply: mut u8[])
        -> Result[Received, slop_os.ChannelError] {
        match send(end, port, request, handles) {
            case Some(error) => return .Error(error)
            case None => {}
        }
        none : slop_os.Handle[1]
        return receive(end, port, reply, none)
    }

    /**
     * Add a grant to what a Load gives the program.
     *
     * @param load The Load the grant is added to.
     * @param label The grant's label, its first GRANT_LABEL_SIZE bytes kept and the rest cut off.
     * @param handle The grant's handle, which the Load holds from now on.
     * @return True if it was added; false if the Load has as many grants as it holds (MAX_GRANTS), leaving it as it was
     *     and the handle the caller's.
     */
    add_grant :: fn(load: ptr[mut process_manager.Load], label: string, handle: slop_os.Handle) -> bool {
        index :: cast[usize](load.grant_count)
        if index >= load.labels.count || index >= load.grants.count {
            return false
        }
        load.labels[index] = label_from(label)
        load.grants[index] = handle
        load.grant_count += 1
        return true
    }

    /** The start of a typed library's grant's label, which its file's name follows. */
    LIBRARY_PREFIX :: "library:"

    /**
     * Check whether a grant labeled label gives one of libraries.
     *
     * @param libraries The libraries a launch names.
     * @param label A grant's label.
     * @return True if label is LIBRARY_PREFIX followed by exactly one of their names.
     */
    library_named :: fn(libraries: LaunchLibrary[], label: string) -> bool {
        bytes :: string_bytes(label)
        for library in libraries {
            if bytes.count != LIBRARY_PREFIX.count + library.name.count {
                continue
            }
            same := true
            for byte, i in string_bytes(library.name) {
                at :: LIBRARY_PREFIX.count + i
                if at >= bytes.count || bytes[at] != byte {
                    same = false
                    break
                }
            }
            if same {
                return true
            }
        }
        return false
    }

    /**
     * Put text in a grant label's form.
     *
     * @param text The label, as bytes; past GRANT_LABEL_SIZE bytes it's cut off.
     * @return Its bytes, then zeros to GRANT_LABEL_SIZE.
     */
    label_from :: fn(text: string) -> u8[slop_os.GRANT_LABEL_SIZE] {
        label : u8[slop_os.GRANT_LABEL_SIZE]
        for byte, i in text {
            if i < label.count {
                label[i] = cast[u8](byte)
            }
        }
        return label
    }

    // ---- Launching programs

    /**
     * Require G to be the grants for an entry of type F: a struct with a field for each of the entry's parameters, of
     * the same name and type, and none other. Anything else is a compile error.
     *
     * @param F The entry's function type.
     * @param G The grants' struct type.
     */
    EntryGrants #constraint :: fn(F: type, G: type) {
        entry :: type_info_of(F)
        grants :: type_info_of(G)
        compiler.require(entry.variant == .FUNCTION, "% isn't a function's type", F)
        compiler.require(grants.variant == .STRUCT, "% isn't a struct", G)
        if entry.variant != .FUNCTION || grants.variant != .STRUCT {
            return void
        }
        inputs :: cast[ptr[compiler.TypeInfoFunction]](entry).input
        members :: cast[ptr[compiler.TypeInfoStruct]](grants).members
        for input in inputs {
            found := false
            for member in members {
                if member.name == input.name {
                    found = true
                    compiler.require(member.member_type == input.type, "%'s field % isn't of its parameter's type", G, member.name)
                }
            }
            compiler.require(found, "% has no field for the entry's parameter %", G, input.name)
        }
        for member in members {
            found := false
            for input in inputs {
                found = found || input.name == member.name
            }
            compiler.require(found, "%'s field % isn't one of the entry's parameters", G, member.name)
        }
    }

    /** Why a launch failed; whichever it is, what the launch made for the program was given back. */
    LaunchError :: enum {
        /**
         * The caller's budget couldn't pay for the program's, its process, its address space or its arguments page, or
         * the watch couldn't be bound.
         */
        NoBudget,
        /**
         * More grants than a Load takes (MAX_GRANTS), a label too long, a handle that couldn't be duplicated, or a CPU
         * budget the process couldn't be put on.
         */
        BadGrants,
        /** The manager couldn't be sent the request, or didn't answer it. */
        ManagerGone,
        /** The manager couldn't load it: the executable isn't a program, or it ran out of memory. */
        NotLoaded,
    }

    /** Where a launch says the program ended: a Once binding of its process's SIGNAL_TERMINATED to port, under key. */
    LaunchWatch :: struct {
        /** The port the program's end is reported on; it stays the caller's. */
        port : slop_os.Port,
        /** The key the end's packet comes with, which mustn't be bound on port already. */
        key : u64,
    }

    /**
     * What a launch does beyond its grants.
     *
     * It can watch the program's end from before it starts, so even a program that ends at once is seen to; run it on
     * a CPU budget (RIGHT_CPU_BUDGET_BIND) from its first instruction rather than on the launcher's; and give it the
     * clock page (a read-only memory object the clock service keeps, base's runtime.SlopOsClockPage), as the grant
     * "clock", which base's runtime reads the wall clock from, whatever the program's entry takes; and give it a ring
     * for its log records and the ring's doorbell (LaunchEvents), as the grants "events", which base's logger writes
     * to; and give it its end of a lifecycle channel (std/os/slop_os's lifecycle), as the grant "lifecycle", which
     * base's runtime serves; and give it a page holding its locale's name, as the grant "locale", which base's
     * runtime.locale_name reads and std/locale formats human-facing text by. The handles given are the program's once
     * it's started, and the caller's still if it isn't, but cpu_budget's.
     */
    LaunchOptions :: struct {
        /** Where the program's end is reported, bound before it starts; null for no watch. */
        watch : LaunchWatch?,
        /**
         * Where the program's faults are reported: an intercept of its faults alone (slop_os.intercept_attach with
         * STOP_FAULT and STOP_FAULT_LIMITED, so a fault not seen to within a second ends the program anyway), or a
         * debugger's (LaunchFaults.debugging), attached before it starts, so even its first instruction's is; null for
         * none, when a fault the kernel can't resolve ends the program.
         */
        faults : LaunchFaults?,
        /**
         * The CPU budget it runs on, whose handle the launch closes once it has tried to put the process on it; null
         * to run on the launcher's.
         */
        cpu_budget : slop_os.CpuBudget?,
        /** The clock page, given as the grant "clock" and then the program's; null to give none. */
        clock : slop_os.Memory?,
        /** Its log records' ring and doorbell, given as the grants "events" and then the program's; null for none. */
        events : LaunchEvents?,
        /** Its end of a lifecycle channel, given as the grant "lifecycle" and then the program's; null for none. */
        lifecycle : slop_os.Channel?,
        /** The page with its locale's name, given as the grant "locale" and then the program's; null for none. */
        locale : slop_os.Memory?,
        /**
         * Memory the program writes what its entry gives back in, given as the grant "result" (Hemera's
         * docs/compilation.md, Entry Results): a handle the launcher made, with RIGHT_MEMORY_WRITE, whose memory it
         * keeps and reads once the program's ended (entry_result); null for none, when what it gives back is only its
         * exit code.
         */
        result : slop_os.Memory?,
        /**
         * The typed libraries the program imports, each given as the grant library:<its file>, which base's runtime
         * binds before main (the SlopOS repository's decisions 0119, 0120); the program's to own. Every library the
         * launcher was given itself is given too, but those named here (0121). Empty for none.
         */
        libraries : LaunchLibrary[],
    }

    /**
     * A typed library a launched program imports: its file's name, as the program's import table names it, and its
     * bytes.
     */
    LaunchLibrary :: struct {
        /** The library's file's name, as the program's import table names it; the grant's label is library:<name>. */
        name : string,
        /** The library's bytes, a handle given to the program, which then owns it. */
        memory : slop_os.Memory,
    }

    /**
     * A program's log records' ring and its doorbell, which the events service gives (base's runtime.SlopOsEventsRing).
     */
    LaunchEvents :: struct {
        /** The ring's memory, given as the first grant "events". */
        ring : slop_os.Memory,
        /** The channel end that rings its doorbell, given as the second grant "events". */
        doorbell : slop_os.Channel,
    }

    /** Where a launched program's faults are reported (LaunchOptions.faults). */
    LaunchFaults :: struct {
        /** The port the intercept's stops are reported on, as packets of kind Stop. */
        port : slop_os.Port,
        /** The key the stops' packets carry. */
        key : u64,
        /**
         * Whether a debugger holds it: then it stops at faults for as long as it looks, not STOP_FAULT_LIMITED, and
         * at every system call's entry too, so the program's first call stops it before its main runs; the debugger
         * changes that with intercept_set. False for crash reports.
         */
        debugging : bool,
    }

    /** What a launch with LaunchOptions.faults gives to report the program's faults with. */
    LaunchedFaults :: struct {
        /**
         * The intercept of the program's faults, a handle the caller owns: intercept_next reads each stop, and
         * intercept_resume lets it go. Closing it lets every stopped thread go on, which faults again.
         */
        intercept : slop_os.Intercept,
        /**
         * The program's address space, a handle the caller owns with no rights, for process_read_memory, which needs
         * none on it.
         */
        space : slop_os.AddressSpace,
    }

    /** A program launch started, in a process the caller owns, with a budget split off its own. */
    Launched :: struct {
        /** The program's process, a handle the caller owns: to watch, to kill, or to close. */
        process : slop_os.Process,
        /** The program's budget, split off the caller's, a handle the caller owns. */
        budget : slop_os.MemoryBudget,
        /** The ID of the program's first thread, as the manager gave it. */
        thread : u64,
        /** The address the program's image was loaded at, its relocations applied for, in its address space. */
        image : u64,
        /** Its fault intercept and address space, when LaunchOptions.faults asked; null otherwise. */
        faults : LaunchedFaults?,
    }

    /**
     * Start the program in executable through the process manager, in a process of the caller's.
     *
     * Each field of grants is one of entry's parameters: a handle, moved to the program as the grant of its name, or
     * an optional one that's None, which it goes without; and a field that isn't a handle is a value, written for the
     * program in its grant "arguments" (docs/compilation.md, Entry Parameters), an optional one that's None not
     * written. A launch that fails gives back what it made for the program (its budget, its process, the watch on its
     * end, and the handles it made for the manager), so none of it stays charged to the caller.
     *
     * @tparam F The entry's function type.
     * @tparam G The grants' struct type, which EntryGrants requires to match F.
     * @param manager The process manager's channel, which stays the caller's.
     * @param port A port bound to manager's end (port_for), waited on for its answer.
     * @param name The program's name, for the manager's log; past GRANT_LABEL_SIZE bytes it's cut off.
     * @param executable The program's file, which stays the caller's: it's duplicated for the manager, executable too
     *     where the caller's handle allows it.
     * @param budget How many bytes of memory the program's budget has, split off the caller's.
     * @param entry The program's entry; only its type is used, to check grants.
     * @param grants The handles and values the program's entry takes. The handles are the program's once it's
     *     started; if the launch fails before the Load is sent, they're still the caller's.
     * @param options What the launch does beyond its grants (LaunchOptions).
     * @return The started program's process, budget, first thread and image's address, and its faults' intercept.
     * @error NoBudget The caller's budget couldn't pay, or the arguments page couldn't be written.
     * @error BadGrants The grants don't fit a Load, or a handle couldn't be duplicated.
     * @error ManagerGone The manager couldn't be asked, or didn't answer.
     * @error NotLoaded The manager couldn't load the program.
     */
    launch :: fn[F, G](manager: Channel[process_manager.ProcessManager], port: slop_os.Port, name: string, executable: slop_os.Memory,
        budget: u64, entry: F, grants: G, options: LaunchOptions = LaunchOptions.{}) -> Result[Launched, LaunchError] where EntryGrants(F, G) {
        // Gathered without the heap, so launching takes no longer than it did
        given : NamedGrant[process_manager.MAX_GRANTS]
        given_count : usize = 0
        for member in cast[ptr[compiler.TypeInfoStruct]](type_info_of(G)).members {
            if !is_grant(member.member_type) {
                continue
            }
            handle :: grant_in(address_of(grants) + cast[u64](member.offset), member.member_type)
            if handle != slop_os.NO_HANDLE && given_count < given.count {
                given[given_count] = NamedGrant.{label = member.name, handle = handle}
                given_count += 1
            }
        }
        page :: match arguments_of(grants) {
            case Ok(made) => made
            case Error(error) => return .Error(.NoBudget)
        }
        return launch_given(manager, port, name, executable, budget, view_of(&given[0], given_count), page, options)
    }

    /** A grant given by its label: a handle a launch moves to the program, as the parameter of its name. */
    NamedGrant :: struct {
        /** The parameter's name, at most GRANT_LABEL_SIZE bytes; more is cut off. */
        label : string,
        /** The handle, the program's once it's started. */
        handle : slop_os.Handle,
    }

    /** What a program's entry gave back, read from the memory given it as the grant "result" (entry_result). */
    EntryResult :: struct {
        /** Whether it's a Result's Error, which the program's exit code says too. */
        error : bool,
        /** The schema hash of the entry's result type, which the value was written as. */
        schema : u8[32],
        /** The value's bytes, as schema.write_value writes one, from context's allocator: the caller's to free. */
        value : u8[..],
    }

    /**
     * In what an entry gives back as its error, the parameter the error came from, by its name: a launcher that reads
     * the error by its schema, like a shell, shows it with the parameter, as --name.
     */
    ParameterName :: struct {
        /** The parameter's name, as the entry declares it. */
        name : string,
    }

    /** The most bytes of value entry_result reads: 1 MiB. */
    MAX_ENTRY_RESULT : u64 : 1 << 20

    /**
     * Read what a program's entry gave back, once it's ended, from the memory its launcher gave it as the grant
     * "result" (Hemera's docs/compilation.md, Entry Results).
     *
     * @param memory The memory, the launcher's, kept; it needs RIGHT_MEMORY_READ, and is read through the kernel.
     * @return What it gave back; null if it wrote nothing (no header, as from a program whose entry gives an exit code,
     *     or one that ended before it got there), its size is past the memory's or MAX_ENTRY_RESULT, or it couldn't be
     *     read.
     */
    entry_result :: fn(memory: slop_os.Memory) -> EntryResult? {
        header := runtime.SlopOsResultHeader.{}
        header_bytes :: view_of(cast[ptr[mut u8]](&header), size_of(runtime.SlopOsResultHeader))
        if (slop_os.memory_read(memory, 0, header_bytes) is_error) || header.magic != runtime.SLOP_OS_RESULT_MAGIC {
            return null
        }
        available :: slop_os.memory_size(memory) or_return null
        if header.size > MAX_ENTRY_RESULT || header.size > available - cast[u64](size_of(runtime.SlopOsResultHeader)) {
            return null
        }
        made := EntryResult.{error = header.error != 0, schema = header.schema}
        for i in cast[u64](0)..<header.size {
            runtime.array_add(&made.value, cast[u8](0))
        }
        if made.value.count > 0 && (slop_os.memory_read(memory, cast[u64](size_of(runtime.SlopOsResultHeader)), made.value[0..<made.value.count]) is_error) {
            runtime.array_free(&made.value)
            return null
        }
        return made
    }

    /**
     * A value a launch writes for the program, as the parameter of its name: the schema hash of the parameter's type,
     * and the value as std/schema's write_value writes one of it.
     */
    NamedValue :: struct {
        /** The parameter's name. */
        name : string,
        /** The schema hash of the type the value was written as, which the program checks against its parameter's. */
        hash : u8[32],
        /** The value's bytes, as std/schema's write_value writes it; only read by the launch. */
        value : u8[],
    }

    /**
     * Start a program as launch does, for a launcher that knows its entry only as it runs, from its manifest, like a
     * shell.
     *
     * @param manager The process manager's channel, which stays the caller's.
     * @param port A port bound to manager's end (port_for), waited on for its answer.
     * @param name The program's name, for the manager's log; past GRANT_LABEL_SIZE bytes it's cut off.
     * @param executable The program's file, which stays the caller's, as launch takes it.
     * @param budget How many bytes of memory the program's budget has, split off the caller's.
     * @param grants Its grants, each a handle and the label of its parameter. The handles are the program's once it's
     *     started, and the caller's still if it isn't.
     * @param values Its values, each written already, with its type's schema hash; none gives no "arguments" grant.
     * @param options What the launch does beyond its grants (LaunchOptions).
     * @return The started program's process, budget, first thread and image's address, and its faults' intercept.
     * @error NoBudget The caller's budget couldn't pay, or the arguments page couldn't be written.
     * @error BadGrants The grants don't fit a Load, or a handle couldn't be duplicated.
     * @error ManagerGone The manager couldn't be asked, or didn't answer.
     * @error NotLoaded The manager couldn't load the program.
     */
    launch_named :: fn(manager: Channel[process_manager.ProcessManager], port: slop_os.Port, name: string, executable: slop_os.Memory,
        budget: u64, grants: NamedGrant[], values: NamedValue[], options: LaunchOptions = LaunchOptions.{}) -> Result[Launched, LaunchError] {
        page :: match arguments_page(values) {
            case Ok(made) => made
            case Error(error) => return .Error(.NoBudget)
        }
        return launch_given(manager, port, name, executable, budget, grants, page, options)
    }

    /**
     * Start a program with grants, and with values written in arguments: launch's and launch_named's work.
     *
     * @param manager The process manager's channel, which stays the caller's.
     * @param port A port bound to manager's end (port_for), waited on for its answer.
     * @param name The program's name, for the manager's log.
     * @param executable The program's file, which stays the caller's.
     * @param budget How many bytes of memory the program's budget has, split off the caller's.
     * @param grants The grants by their labels; their handles are the program's once it's started.
     * @param arguments The page of the values written for the program, or null for none. It's the launch's: given to
     *     the program as the grant "arguments", or closed.
     * @param options What the launch does beyond its grants (LaunchOptions).
     * @return The started program's process, budget, first thread and image's address, and its faults' intercept.
     * @error NoBudget The caller's budget couldn't pay for the program's budget, process or address space, or the
     *     watch or the fault intercept couldn't be made.
     * @error BadGrants The grants don't fit a Load, a label is too long, a handle couldn't be duplicated, or the
     *     process couldn't be put on the CPU budget.
     * @error ManagerGone The manager couldn't be sent the Load, or didn't answer it.
     * @error NotLoaded The manager answered with anything but Loaded.
     */
    launch_given :: fn(manager: Channel[process_manager.ProcessManager], port: slop_os.Port, name: string, executable: slop_os.Memory,
        budget: u64, grants: NamedGrant[], arguments: slop_os.Memory?, options: LaunchOptions) -> Result[Launched, LaunchError] {
        // The page's the Load's once it's among its grants
        page_kept := false
        defer {
            if !page_kept {
                match arguments {
                    case Some(memory) => _ = slop_os.handle_close(cast[slop_os.Handle](memory))
                    case None => {}
                }
            }
        }
        block :: slop_os.startup_block()
        child :: slop_os.memory_budget_create(block.budget, budget) or_return .Error(.NoBudget)
        load := process_manager.Load.{name = label_from(name)}
        process := cast[slop_os.Process](slop_os.NO_HANDLE)
        watch : LaunchWatch? = null
        faults : LaunchedFaults? = null
        // Whether the Load's gone to the manager, whose its handles are then, and where its own copies of the
        // launcher's libraries start among its grants, none until they're added (the grants before are the caller's)
        sent := false
        copies_from := load.grants.count
        started := false
        defer {
            if !started {
                give_back(&load, sent, copies_from, watch, process, child)
                match faults {
                    case Some(made) => {
                        _ = slop_os.handle_close(cast[slop_os.Handle](made.intercept))
                        if cast[slop_os.Handle](made.space) != slop_os.NO_HANDLE {
                            _ = slop_os.handle_close(cast[slop_os.Handle](made.space))
                        }
                    }
                    case None => {}
                }
            }
        }
        process = slop_os.process_create(child) or_return .Error(.NoBudget)
        match options.watch {
            case Some(watching) => {
                slop_os.port_bind(watching.port, cast[slop_os.Handle](process), slop_os.SIGNAL_TERMINATED, watching.key, .Once)
                    or_return .Error(.NoBudget)
                watch = watching
            }
            case None => {}
        }
        match options.cpu_budget {
            case Some(cpu) => {
                put :: slop_os.process_set_cpu_budget(process, cpu)
                _ = slop_os.handle_close(cast[slop_os.Handle](cpu))
                put or_return .Error(.BadGrants)
            }
            case None => {}
        }
        load.space = slop_os.address_space_create(child) or_return .Error(.NoBudget)
        match options.faults {
            case Some(reported) => {
                points :: if reported.debugging { slop_os.STOP_FAULT | slop_os.STOP_SYSCALL_ENTRY } else { slop_os.STOP_FAULT | slop_os.STOP_FAULT_LIMITED }
                calls :: if reported.debugging { ~cast[u64](0) } else { cast[u64](0) }
                intercept :: slop_os.intercept_attach(process, reported.port, reported.key, calls, points)
                    or_return .Error(.NoBudget)
                faults = LaunchedFaults.{intercept = intercept, space = cast[slop_os.AddressSpace](slop_os.NO_HANDLE)}
                kept :: slop_os.handle_duplicate(cast[slop_os.Handle](load.space), cast[slop_os.Rights](0)) or_return .Error(.BadGrants)
                faults = LaunchedFaults.{intercept = intercept, space = cast[slop_os.AddressSpace](kept)}
            }
            case None => {}
        }
        process_rights :: cast[slop_os.Rights](cast[u32](slop_os.RIGHT_PROCESS_THREADS) | cast[u32](slop_os.RIGHT_DUPLICATE)
            | cast[u32](slop_os.RIGHT_TRANSFER))
        load.process = cast[slop_os.Process](slop_os.handle_duplicate(cast[slop_os.Handle](process), process_rights) or_return .Error(.BadGrants))
        budget_rights :: cast[slop_os.Rights](cast[u32](slop_os.RIGHT_BUDGET_CHARGE) | cast[u32](slop_os.RIGHT_DUPLICATE)
            | cast[u32](slop_os.RIGHT_TRANSFER))
        load.budget = cast[slop_os.MemoryBudget](slop_os.handle_duplicate(cast[slop_os.Handle](child), budget_rights) or_return .Error(.BadGrants))
        // To execute too, where the caller may, so the manager can map its read-only segments straight from it
        executable_rights :: cast[slop_os.Rights](cast[u32](slop_os.RIGHT_MEMORY_READ) | cast[u32](slop_os.RIGHT_TRANSFER))
        executing :: cast[slop_os.Rights](cast[u32](executable_rights) | cast[u32](slop_os.RIGHT_MEMORY_EXECUTE))
        load.executable = cast[slop_os.Memory](slop_os.handle_duplicate(cast[slop_os.Handle](executable), executing)
            or_else (slop_os.handle_duplicate(cast[slop_os.Handle](executable), executable_rights) or_return .Error(.BadGrants)))
        for grant in grants {
            if !add_grant(&load, grant.label, grant.handle) {
                return .Error(.BadGrants)
            }
        }
        match options.clock {
            case Some(page) => if !add_grant(&load, "clock", cast[slop_os.Handle](page)) {
                return .Error(.BadGrants)
            }
            case None => {}
        }
        match options.events {
            case Some(events) => if !add_grant(&load, "events", cast[slop_os.Handle](events.ring))
                || !add_grant(&load, "events", cast[slop_os.Handle](events.doorbell)) {
                return .Error(.BadGrants)
            }
            case None => {}
        }
        match options.lifecycle {
            case Some(end) => if !add_grant(&load, "lifecycle", cast[slop_os.Handle](end)) {
                return .Error(.BadGrants)
            }
            case None => {}
        }
        match options.locale {
            case Some(page) => if !add_grant(&load, "locale", cast[slop_os.Handle](page)) {
                return .Error(.BadGrants)
            }
            case None => {}
        }
        match options.result {
            case Some(memory) => if !add_grant(&load, "result", cast[slop_os.Handle](memory)) {
                return .Error(.BadGrants)
            }
            case None => {}
        }
        for library in options.libraries {
            label : u8[slop_os.GRANT_LABEL_SIZE]
            count := cast[usize](0)
            for text in string.[LIBRARY_PREFIX, library.name] {
                for byte in string_bytes(text) {
                    if count >= label.count {
                        return .Error(.BadGrants)
                    }
                    label[count] = byte
                    count += 1
                }
            }
            if !add_grant(&load, string_of(&label[0], count), cast[slop_os.Handle](library.memory)) {
                return .Error(.BadGrants)
            }
        }
        // The launcher's own libraries, which it may share on and run, and the values written for it
        copies_from = cast[usize](load.grant_count)
        match arguments {
            case Some(memory) => {
                if !add_grant(&load, "arguments", cast[slop_os.Handle](memory)) {
                    return .Error(.BadGrants)
                }
                page_kept = true
            }
            case None => {}
        }
        library_rights :: cast[slop_os.Rights](cast[u32](slop_os.RIGHT_MEMORY_READ) | cast[u32](slop_os.RIGHT_MEMORY_EXECUTE)
            | cast[u32](slop_os.RIGHT_DUPLICATE) | cast[u32](slop_os.RIGHT_TRANSFER))
        for &grant in slop_os.grants_of(block) {
            label :: slop_os.label_of(grant)
            if grant.kind != .Memory || !starts_with(label, LIBRARY_PREFIX) || library_named(options.libraries, label) {
                continue
            }
            match slop_os.handle_duplicate(grant.handle, library_rights) {
                case Ok(copy) => if !add_grant(&load, label, copy) {
                    _ = slop_os.handle_close(copy)
                    return .Error(.BadGrants)
                }
                case Error(error) => {}
            }
        }
        out := Outgoing.{}
        request :: begin[process_manager.Request](&out)
        request^ = .Load(load)
        match process_manager.send_request(manager.end, port, &out) {
            case Some(error) => return .Error(.ManagerGone)
            case None => {}
        }
        sent = true
        into := Incoming.{}
        match process_manager.receive_response(manager.end, port, &into, true) {
            case Received => {}
            case _ => return .Error(.ManagerGone)
        }
        match message_of[process_manager.Response](&into)^ {
            case Loaded(loaded) => {
                started = true
                return .Ok(Launched.{process = process, budget = child, thread = loaded.thread, image = loaded.image, faults = faults})
            }
            case _ => return .Error(.NotLoaded)
        }
    }

    /**
     * Give back what launch made for a program that didn't start.
     *
     * @param load The Load it was making, whose handles are closed unless it was sent.
     * @param sent Whether the Load went to the manager, which made its handles the manager's, so they aren't closed.
     * @param copies_from Where the Load's own copies of the launcher's libraries start among its grants, closed with
     *     the rest when it wasn't sent; the grants before are the caller's and stay open.
     * @param watch The watch on the process's end, unbound so its key isn't kept by a fired or unfired binding; null
     *     for none.
     * @param process The program's process, closed unless it's NO_HANDLE.
     * @param child The program's budget, which charged the caller's for all of it, closed.
     */
    give_back :: fn(load: ptr[process_manager.Load], sent: bool, copies_from: usize, watch: LaunchWatch?, process: slop_os.Process,
        child: slop_os.MemoryBudget) {
        if !sent {
            for handle in slop_os.Handle.[cast[slop_os.Handle](load.process), cast[slop_os.Handle](load.space), cast[slop_os.Handle](load.budget),
                cast[slop_os.Handle](load.executable)] {
                if handle != slop_os.NO_HANDLE {
                    _ = slop_os.handle_close(handle)
                }
            }
            for i in copies_from..<cast[usize](load.grant_count) {
                if i < load.grants.count && load.grants[i] != slop_os.NO_HANDLE {
                    _ = slop_os.handle_close(load.grants[i])
                }
            }
        }
        match watch {
            case Some(watching) => _ = slop_os.port_unbind(watching.port, watching.key)
            case None => {}
        }
        if cast[slop_os.Handle](process) != slop_os.NO_HANDLE {
            _ = slop_os.handle_close(cast[slop_os.Handle](process))
        }
        _ = slop_os.handle_close(cast[slop_os.Handle](child))
    }

    /**
     * Decide whether a field of a program's grants is a handle, given as the grant of its name, or a value, written in
     * its grant "arguments", as the compiler decides it for the entry's parameter.
     *
     * @param type The field's type, as the entry's parameter has it, not null and only read; an optional that isn't a
     *     nullable pointer is looked through to what it holds.
     * @return True for a 4-byte distinct alias or struct whose name, without its generic arguments, is a kind of handle
     *     base's runtime knows, or an optional (not a nullable pointer) of one; false for anything else, a value.
     */
    is_grant :: fn(type: ptr[compiler.TypeInfo]) -> bool {
        held := type
        if type.variant == .UNION {
            optional :: cast[ptr[compiler.TypeInfoUnion]](type)
            if optional.null_is_none {
                return false
            }
            for variant in optional.variants {
                if variant.name == "Some" && variant.types.count == 1 {
                    held = variant.types[0]
                }
            }
            if held == type {
                return false
            }
        }
        if held.size != 4 {
            return false
        }
        name := ""
        if held.variant == .ALIAS && cast[ptr[compiler.TypeInfoAlias]](held).is_distinct {
            name = cast[ptr[compiler.TypeInfoAlias]](held).name
        }
        else if held.variant == .STRUCT {
            name = cast[ptr[compiler.TypeInfoStruct]](held).name
        }
        for character, i in name {
            if character == '[' && i <= name.count {
                name = name[0..<i]
                break
            }
        }
        return name.count > 0 && runtime.slop_os_kind_of(name) != 0
    }

    /**
     * Write the values among a launch's grants as a page for the grant "arguments", which base's
     * runtime.os_entry_value reads.
     *
     * @param grants The grants struct; its fields that aren't handles (is_grant) are written, an optional's Some value
     *     as the value and its None not at all.
     * @return The page, a new memory object charged to the caller's budget, which the caller owns; null if there are
     *     no values to write.
     * @error OutOfMemory A value couldn't be written.
     * @error BudgetExceeded The caller's budget couldn't pay for the page.
     * @error InvalidSize The values are more than a memory object holds.
     */
    arguments_of :: fn(grants: any) -> Result[slop_os.Memory?, slop_os.MemoryError] {
        type :: type_info_of(grants.type)
        // Every value's bytes, one after another, and where each one's are, made views once they're all written
        written : u8[..]
        defer runtime.array_free(&written)
        found : WrittenValue[..]
        defer runtime.array_free(&found)
        for member in cast[ptr[compiler.TypeInfoStruct]](type).members {
            if is_grant(member.member_type) {
                continue
            }
            // An optional's Some value, or nothing for its None
            value_type := member.member_type
            value_at := address_of(grants) + cast[u64](member.offset)
            if value_type.variant == .UNION && !cast[ptr[compiler.TypeInfoUnion]](value_type).null_is_none {
                optional :: cast[ptr[compiler.TypeInfoUnion]](value_type)
                tag_size :: match optional.tag_type {
                    case Some(tag) => tag.size
                    case None => cast[usize](0)
                }
                tag := cast[u64](0)
                for byte, i in view_of(cast[ptr[u8]](value_at), tag_size) {
                    tag |= cast[u64](byte) << (8 * i)
                }
                if tag >= cast[u64](optional.variants.count) {
                    continue
                }
                chosen :: optional.variants[cast[usize](tag)]
                if chosen.name != "Some" || chosen.types.count != 1 || chosen.offsets.count != 1 {
                    continue
                }
                value_type = chosen.types[0]
                value_at += cast[u64](chosen.offsets[0])
            }
            start :: written.count
            if runtime.schema_try_write_value_at(cast[rawptr](value_at), value_type, &written) != null {
                return .Error(.OutOfMemory)
            }
            runtime.array_add(&found, WrittenValue.{name = member.name, hash = runtime.schema_hash(value_type), start = start,
                end = written.count})
        }
        values : NamedValue[..]
        defer runtime.array_free(&values)
        for each in found {
            value : u8[]
            if each.end > each.start && each.end <= written.count {
                value = written[each.start..<each.end]
            }
            runtime.array_add(&values, NamedValue.{name = each.name, hash = each.hash, value = value})
        }
        return arguments_page(values)
    }

    /** A value arguments_of has written: its name and type, and where its bytes are among all of them. */
    WrittenValue :: struct {
        /** The parameter's name. */
        name : string,
        /** The schema hash of its type. */
        hash : u8[32],
        /** Where its bytes start among the written bytes, an index. */
        start : usize,
        /** Where they end, just past the last: start for an empty value. */
        end : usize,
    }

    /**
     * Write values as a page for the grant "arguments" (docs/compilation.md, Entry Parameters).
     *
     * The page holds its header (runtime.SlopOsArguments), then each value's (runtime.SlopOsArgument), its name and its
     * bytes, each padded to 8 bytes; it's rounded up to whole 4096-byte pages.
     *
     * @param values The values, in the order they're written; only read.
     * @return The page, a new memory object charged to the caller's budget, which the caller owns; null if values is
     *     empty.
     * @error BudgetExceeded The caller's budget couldn't pay for the page.
     * @error InvalidSize The values are more than a memory object holds.
     * @error OutOfMemory The kernel had no memory for it.
     */
    arguments_page :: fn(values: NamedValue[]) -> Result[slop_os.Memory?, slop_os.MemoryError] {
        if values.count == 0 {
            return .Ok(null)
        }
        written : u8[..]
        defer runtime.array_free(&written)
        header := runtime.SlopOsArguments.{magic = runtime.SLOP_OS_ARGUMENTS_MAGIC, count = cast[u32](values.count)}
        add_bytes(&written, view_of(cast[ptr[u8]](&header), size_of(runtime.SlopOsArguments)))
        for each in values {
            argument := runtime.SlopOsArgument.{name_bytes = cast[u32](each.name.count), value_bytes = cast[u32](each.value.count),
                hash = each.hash}
            add_bytes(&written, view_of(cast[ptr[u8]](&argument), size_of(runtime.SlopOsArgument)))
            add_bytes(&written, string_bytes(each.name))
            pad(&written)
            add_bytes(&written, each.value)
            pad(&written)
        }
        header.total = cast[u64](written.count)
        for byte, i in view_of(cast[ptr[u8]](&header), size_of(runtime.SlopOsArguments)) {
            if i < written.count {
                written[i] = byte
            }
        }
        size :: (cast[u64](written.count) + 4095) & ~cast[u64](4095)
        memory :: slop_os.memory_create(slop_os.startup_block().budget, size)?
        match slop_os.memory_write(memory, 0, written) {
            case Ok => {}
            case Error(error) => {
                _ = slop_os.handle_close(cast[slop_os.Handle](memory))
                return .Error(error)
            }
        }
        return .Ok(memory)
    }

    /**
     * Find where a launch's grants are, as a number: they're read field by field, by their type's description.
     *
     * @param grants The grants, as any.
     * @return Their address, good as long as the value grants refers to is.
     */
    address_of :: fn(grants: any) -> u64 {
        return cast[u64](cast[uintptr](grants.data))
    }

    /**
     * Append bytes to a growing array, from its own allocator.
     *
     * @param into The array, grown as needed.
     * @param bytes What's appended; only read.
     */
    add_bytes :: fn(into: ptr[mut u8[..]], bytes: u8[]) {
        for byte in bytes {
            runtime.array_add(into, byte)
        }
    }

    /**
     * Pad a growing array with zeros to a multiple of 8 bytes.
     *
     * @param into The array, given up to 7 zero bytes; nothing if its count is a multiple of 8 already.
     */
    pad :: fn(into: ptr[mut u8[..]]) {
        loop {
            if into.count % 8 == 0 {
                break
            }
            runtime.array_add(into, cast[u8](0))
        }
    }

    /**
     * Read a grant's handle from a field of a launch's grants.
     *
     * @param address Where the field is.
     * @param type The field's type: a handle, or an optional of one.
     * @return The handle, or NO_HANDLE for an optional's None.
     */
    grant_in :: fn(address: u64, type: ptr[compiler.TypeInfo]) -> slop_os.Handle {
        if type.variant == .UNION {
            optional :: cast[ptr[compiler.TypeInfoUnion]](type)
            some := optional.variants.count
            for variant, i in optional.variants {
                if variant.name == "Some" {
                    some = i
                }
            }
            if some >= optional.variants.count || optional.variants[some].types.count == 0 || optional.variants[some].offsets.count == 0 {
                return slop_os.NO_HANDLE
            }
            // Some is tagged with its index, in a tag of its own width
            tag_size :: match optional.tag_type {
                case Some(tag) => tag.size
                case None => cast[usize](4)
            }
            tag :: if tag_size == 1 { cast[u64](cast[ptr[u8]](address)^) } else if tag_size == 2 { cast[u64](cast[ptr[u16]](address)^) }
                else { cast[u64](cast[ptr[u32]](address)^) }
            if tag != cast[u64](some) {
                return slop_os.NO_HANDLE
            }
            return cast[ptr[slop_os.Handle]](address + cast[u64](optional.variants[some].offsets[0]))^
        }
        return cast[ptr[slop_os.Handle]](address)^
    }
}

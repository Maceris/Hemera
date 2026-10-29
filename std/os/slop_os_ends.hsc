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
    import slop_os from "std/os"
    import process_manager from "std/os/slop_os"

    /*
     * A channel end that speaks protocol P, a type named after it, like process_manager.ProcessManager, and
     * one that connections to a P arrive on, each a message with the connection's end as its one handle.
     * An entry parameter of either is the grant of its name.
     */
    Channel :: struct[P] {
        end : slop_os.Channel,
    }

    Listener :: struct[P] {
        end : slop_os.Channel,
    }

    /*
     * The tag of the protocol P (decisions/0040, 0071): FNV-1a of its name, which a channel for P is made with
     * (channel_create), and which the end of a Channel[P] or Listener[P] has to have where it arrives: as an entry's
     * parameter, or in a message.
     */
    protocol_tag :: fn[P]() -> u64 {
        return end_tag(type_info_of(Channel[P]))
    }

    // A new channel for P, with rings of ring_bytes each way, 0 for the default.
    channel_for :: fn[P](budget: slop_os.MemoryBudget, ring_bytes: u32) -> Result[slop_os.ChannelPair, slop_os.ChannelError] {
        return slop_os.channel_create(budget, ring_bytes, protocol_tag[P]())
    }

    // Whether a channel end was made for P.
    speaks :: fn[P](end: slop_os.Channel) -> bool {
        return (slop_os.channel_tag(end) or_else 0) == protocol_tag[P]()
    }

    // The tag of a Channel[P] or Listener[P] type, from P's name; 0 for another type.
    end_tag :: fn(type: ptr[compiler.TypeInfo]) -> u64 {
        if type.variant != .STRUCT {
            return 0
        }
        name :: cast[ptr[compiler.TypeInfoStruct]](type).name
        start : usize = 0
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

    starts_with :: fn(text: string, prefix: string) -> bool {
        return text.count >= prefix.count && string_of(cast[ptr[u8]](text.data), prefix.count) == prefix
    }

    // ---- Messages: fixed-layout structs, sent as their bytes

    // What receive gives: the message's size, and how many handles came with it.
    Received :: struct {
        size : u32,
        handle_count : u32,
    }

    // A message's bytes.
    bytes_of :: fn[T](message: ptr[T]) -> u8[] {
        return view_of(cast[ptr[u8]](message), size_of(T))
    }

    mut_bytes_of :: fn[T](message: ptr[mut T]) -> mut u8[] {
        return view_of(cast[ptr[mut u8]](message), size_of(T))
    }

    /*
     * bytes, with handles in a batch the other end has free, moved out of the caller's table. Waits on
     * port, bound to the end (port_for), while the ring is full.
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

    /*
     * The next message, its bytes in buffer and its handles in handles, without waiting: Empty if there's
     * none yet, which leaves the end's next write raising SIGNAL_READABLE.
     */
    try_receive :: fn(end: slop_os.Channel, buffer: mut u8[], handles: mut slop_os.Handle[]) -> Result[Received, slop_os.ChannelError] {
        info :: slop_os.channel_read(end, buffer, cast[ptr[mut u32]](0))?
        received := Received.{size = info.size}
        if info.flags_and_batch & cast[u32](slop_os.MESSAGE_HAS_HANDLES) != 0 {
            received.handle_count = slop_os.channel_take_handles(end, info.flags_and_batch >> 16, handles, cast[ptr[mut u32]](0))?
        }
        return .Ok(received)
    }

    // The next message, as try_receive, waiting on port (port_for) for it.
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

    // A port for one end, which SIGNAL_READABLE, SIGNAL_WRITABLE and SIGNAL_PEER_CLOSED wake, for send and receive to wait on.
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

    // A request, then its reply, on an end and its port_for.
    call :: fn(end: slop_os.Channel, port: slop_os.Port, request: u8[], handles: slop_os.Handle[], reply: mut u8[])
        -> Result[Received, slop_os.ChannelError] {
        match send(end, port, request, handles) {
            case Some(error) => return .Error(error)
            case None => {}
        }
        none : slop_os.Handle[1]
        return receive(end, port, reply, none)
    }

    // A grant added to what a Load gives, labeled label: false if it has as many as it holds.
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

    // A label in a grant's form: its bytes, then zeros.
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

    /*
     * A program's grants, G, for its entry, F: a struct with a field for each of the entry's parameters,
     * of the same name and type.
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

    LaunchError :: enum {
        // The caller's budget couldn't pay for the program's
        NoBudget,
        // More grants than a Load takes, or no handle for one
        BadGrants,
        // The manager didn't answer
        ManagerGone,
        // The manager couldn't load it: the executable isn't a program, or it ran out of memory
        NotLoaded,
    }

    // Where a launch says the program ended: a Once binding of its process's SIGNAL_TERMINATED to port, under key.
    LaunchWatch :: struct {
        port : slop_os.Port,
        key : u64,
    }

    /*
     * What a launch does beyond its grants: watch the program's end from before it starts; run it on a CPU budget
     * (RIGHT_CPU_BUDGET_BIND) from its first instruction rather than on the launcher's; and give it the clock page (a
     * read-only memory object the clock service keeps, base's runtime.SlopOsClockPage), as the grant "clock", which
     * base's runtime reads the wall clock from, whatever the program's entry takes; and give it a ring for its log
     * records and the ring's doorbell (LaunchEvents), as the grants "events", which base's logger writes to.
     */
    LaunchOptions :: struct {
        watch : LaunchWatch?,
        cpu_budget : slop_os.CpuBudget?,
        clock : slop_os.Memory?,
        events : LaunchEvents?,
    }

    // A program's log records' ring and its doorbell, which the events service gives (base's runtime.SlopOsEventsRing).
    LaunchEvents :: struct {
        ring : slop_os.Memory,
        doorbell : slop_os.Channel,
    }

    // A program launch started, in a process the caller owns, with a budget split off its own.
    Launched :: struct {
        process : slop_os.Process,
        budget : slop_os.MemoryBudget,
        thread : u64,
    }

    /*
     * The program in executable, started through the process manager in a process of the caller's, with a
     * budget of budget bytes split off the caller's: grants, a G whose fields are entry's parameters, each a
     * handle moved to the program, or None for an optional one it goes without. name is for the manager's log. options
     * (LaunchOptions) can watch its end from before it starts, so even a program that ends at once is seen to, put it on a
     * CPU budget, and give it the clock page and its events ring; the budget's handle is closed once it's on it, and the
     * clock page's and the ring's are the program's.
     */
    launch :: fn[F, G](manager: Channel[process_manager.ProcessManager], port: slop_os.Port, name: string, executable: slop_os.Memory,
        budget: u64, entry: F, grants: G, options: LaunchOptions = LaunchOptions.{}) -> Result[Launched, LaunchError] where EntryGrants(F, G) {
        block :: slop_os.startup_block()
        child :: slop_os.memory_budget_create(block.budget, budget) or_return .Error(.NoBudget)
        process :: slop_os.process_create(child) or_return .Error(.NoBudget)
        match options.watch {
            case Some(watching) => slop_os.port_bind(watching.port, cast[slop_os.Handle](process), slop_os.SIGNAL_TERMINATED, watching.key, .Once)
                or_return .Error(.NoBudget)
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
        space :: slop_os.address_space_create(child) or_return .Error(.NoBudget)
        load := process_manager.Load.{name = label_from(name), space = space}
        process_rights :: cast[slop_os.Rights](cast[u32](slop_os.RIGHT_PROCESS_THREADS) | cast[u32](slop_os.RIGHT_DUPLICATE)
            | cast[u32](slop_os.RIGHT_TRANSFER))
        load.process = cast[slop_os.Process](slop_os.handle_duplicate(cast[slop_os.Handle](process), process_rights) or_return .Error(.BadGrants))
        budget_rights :: cast[slop_os.Rights](cast[u32](slop_os.RIGHT_BUDGET_CHARGE) | cast[u32](slop_os.RIGHT_DUPLICATE)
            | cast[u32](slop_os.RIGHT_TRANSFER))
        load.budget = cast[slop_os.MemoryBudget](slop_os.handle_duplicate(cast[slop_os.Handle](child), budget_rights) or_return .Error(.BadGrants))
        executable_rights :: cast[slop_os.Rights](cast[u32](slop_os.RIGHT_MEMORY_READ) | cast[u32](slop_os.RIGHT_TRANSFER))
        load.executable = cast[slop_os.Memory](slop_os.handle_duplicate(cast[slop_os.Handle](executable), executable_rights)
            or_return .Error(.BadGrants))
        for member in cast[ptr[compiler.TypeInfoStruct]](type_info_of(G)).members {
            handle :: grant_in(cast[u64](&grants) + cast[u64](member.offset), member.member_type)
            if handle == slop_os.NO_HANDLE {
                continue
            }
            index :: cast[usize](load.grant_count)
            if index >= load.labels.count || index >= load.grants.count {
                return .Error(.BadGrants)
            }
            load.labels[index] = label_from(member.name)
            load.grants[index] = handle
            load.grant_count += 1
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
        out := Outgoing.{}
        request :: begin[process_manager.Request](&out)
        request^ = .Load(load)
        match process_manager.send_request(manager.end, port, &out) {
            case Some(error) => return .Error(.ManagerGone)
            case None => {}
        }
        into := Incoming.{}
        match process_manager.receive_response(manager.end, port, &into, true) {
            case Received => {}
            case _ => return .Error(.ManagerGone)
        }
        match message_of[process_manager.Response](&into)^ {
            case Loaded(thread) => return .Ok(Launched.{process = process, budget = child, thread = thread})
            case _ => {
                _ = slop_os.handle_close(cast[slop_os.Handle](process))
                return .Error(.NotLoaded)
            }
        }
    }

    // A grant's handle, a field of type at address: the handle, or NO_HANDLE for an optional's None.
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

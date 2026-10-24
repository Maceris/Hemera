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
     * The tag of the protocol P (decisions/0040): a hash of its name, which the launcher puts in the grant
     * of a Channel[P] or Listener[P], so a program can see it was given what it was built for (speaks).
     */
    protocol_tag :: fn[P]() -> u64 {
        return end_tag(type_info_of(Channel[P]))
    }

    /*
     * Whether a channel speaks P, as far as the process's startup grants say: false only for a grant of its
     * end tagged with another protocol.
     */
    speaks :: fn[P](channel: Channel[P]) -> bool {
        for &grant in slop_os.grants_of(slop_os.startup_block()) {
            if grant.handle == cast[slop_os.Handle](channel.end) && grant.tag != 0 {
                return grant.tag == protocol_tag[P]()
            }
        }
        return true
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

    // The next connection to arrive on a listener, waiting on port (port_for) for it.
    accept :: fn[P](listener: Listener[P], port: slop_os.Port) -> Result[Channel[P], slop_os.ChannelError] {
        message : u64[2]
        handles : slop_os.Handle[1]
        received :: receive(listener.end, port, view_of(cast[ptr[mut u8]](&message[0]), 16), handles)?
        if received.handle_count != 1 {
            return .Error(.InvalidHandle)
        }
        return .Ok(Channel[P].{end = cast[slop_os.Channel](handles[0])})
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
        // More grants than a LoadRequest takes, or no handle for one
        BadGrants,
        // The manager didn't answer
        ManagerGone,
        // The manager couldn't load it: the executable isn't a program, or it ran out of memory
        NotLoaded,
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
     * handle moved to the program, or None for an optional one it goes without. name is for the manager's log.
     */
    launch :: fn[F, G](manager: Channel[process_manager.ProcessManager], port: slop_os.Port, name: string, executable: slop_os.Memory,
        budget: u64, entry: F, grants: G) -> Result[Launched, LaunchError] where EntryGrants(F, G) {
        block :: slop_os.startup_block()
        child :: slop_os.memory_budget_create(block.budget, budget) or_return .Error(.NoBudget)
        process :: slop_os.process_create(child) or_return .Error(.NoBudget)
        space :: slop_os.address_space_create(child) or_return .Error(.NoBudget)
        request := process_manager.LoadRequest.{tag = process_manager.LOAD, name = label_from(name)}
        handles : slop_os.Handle[process_manager.LOAD_HANDLES_AND_GRANTS]
        process_rights :: cast[slop_os.Rights](cast[u32](slop_os.RIGHT_PROCESS_THREADS) | cast[u32](slop_os.RIGHT_DUPLICATE)
            | cast[u32](slop_os.RIGHT_TRANSFER))
        handles[0] = slop_os.handle_duplicate(cast[slop_os.Handle](process), process_rights) or_return .Error(.BadGrants)
        handles[1] = cast[slop_os.Handle](space)
        budget_rights :: cast[slop_os.Rights](cast[u32](slop_os.RIGHT_BUDGET_CHARGE) | cast[u32](slop_os.RIGHT_DUPLICATE)
            | cast[u32](slop_os.RIGHT_TRANSFER))
        handles[2] = slop_os.handle_duplicate(cast[slop_os.Handle](child), budget_rights) or_return .Error(.BadGrants)
        executable_rights :: cast[slop_os.Rights](cast[u32](slop_os.RIGHT_MEMORY_READ) | cast[u32](slop_os.RIGHT_TRANSFER))
        handles[3] = slop_os.handle_duplicate(cast[slop_os.Handle](executable), executable_rights) or_return .Error(.BadGrants)
        count : usize = process_manager.LOAD_HANDLES
        for member in cast[ptr[compiler.TypeInfoStruct]](type_info_of(G)).members {
            held, handle :: grant_in(cast[u64](&grants) + cast[u64](member.offset), member.member_type)
            if handle == slop_os.NO_HANDLE {
                continue
            }
            index :: cast[usize](request.grant_count)
            if index >= request.labels.count || index >= request.tags.count || count >= handles.count {
                return .Error(.BadGrants)
            }
            request.labels[index] = label_from(member.name)
            request.tags[index] = end_tag(held)
            request.grant_count += 1
            handles[count] = handle
            count += 1
        }
        reply := process_manager.LoadReply.{}
        match call(manager.end, port, bytes_of(&request), view_of(&handles[0], count), mut_bytes_of(&reply)) {
            case Ok(received) => {}
            case Error(error) => return .Error(.ManagerGone)
        }
        if reply.status != .Loaded {
            _ = slop_os.handle_close(cast[slop_os.Handle](process))
            return .Error(.NotLoaded)
        }
        return .Ok(Launched.{process = process, budget = child, thread = reply.thread})
    }

    // A grant's handle, a field of type at address: the handle, or NO_HANDLE for an optional's None, and its type.
    grant_in :: fn(address: u64, type: ptr[compiler.TypeInfo]) -> (held: ptr[compiler.TypeInfo], handle: slop_os.Handle) {
        if type.variant == .UNION {
            optional :: cast[ptr[compiler.TypeInfoUnion]](type)
            if optional.variants.count == 0 || optional.variants[0].types.count == 0 || optional.variants[0].offsets.count == 0 {
                return type, slop_os.NO_HANDLE
            }
            // Some is the first variant, tagged 0, in a tag of its own width
            tag_size :: match optional.tag_type {
                case Some(tag) => tag.size
                case None => cast[usize](4)
            }
            tag :: if tag_size == 1 { cast[u64](cast[ptr[u8]](address)^) } else if tag_size == 2 { cast[u64](cast[ptr[u16]](address)^) }
                else { cast[u64](cast[ptr[u32]](address)^) }
            if tag != 0 {
                return optional.variants[0].types[0], slop_os.NO_HANDLE
            }
            return optional.variants[0].types[0], cast[ptr[slop_os.Handle]](address + cast[u64](optional.variants[0].offsets[0]))^
        }
        return type, cast[ptr[slop_os.Handle]](address)^
    }
}

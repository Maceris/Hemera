package process_manager

// Only for SlopOS, where std/os has what its generated code needs: base.OS, since the #insert in it could declare an OS of its own
#if base.OS == .SlopOS {
    import os from "std"
    import slop_os from "std/os"

    /*
     * The process manager's protocol (the SlopOS repository's decisions 0040, 0067, 0071): it loads programs into
     * processes their requesters made, which stay theirs, and serves each client one request at a time, in order.
     * std/os's launch speaks it. Its messages' code is generated (os.protocol_code), so a handle in one moves with it.
     */

    // The protocol, for os.Channel[ProcessManager]: its name is its tag's (os.protocol_tag).
    ProcessManager :: struct {}

    PROTOCOL :: slop_os.Protocol.{name = "process_manager", major_version = 1, lending = .PerConnection}

    // The rings a connection to the manager needs, for a Load (channel_create's ring bytes).
    RING_BYTES : u32 : 2048

    // The most grants a Load gives the new program.
    MAX_GRANTS :: 12

    Request :: union {
        // Load a program into a process the requester made, which stays the requester's and is paid for by it.
        Load(Load),
        // Serve another client, on its end.
        Connect(os.Channel[ProcessManager]),
    }

    /*
     * The process (RIGHT_PROCESS_THREADS, RIGHT_DUPLICATE and RIGHT_TRANSFER), its address space (owning, which goes to
     * the process), its memory budget (RIGHT_BUDGET_CHARGE, RIGHT_DUPLICATE and RIGHT_TRANSFER), the executable (a memory
     * object, RIGHT_MEMORY_READ), and grant_count grants, each labeled by labels, with RIGHT_TRANSFER. The manager keeps
     * none of them.
     */
    Load :: struct {
        // The program's name, for the manager's log
        name : u8[slop_os.GRANT_LABEL_SIZE],
        process : slop_os.Process,
        space : slop_os.AddressSpace,
        budget : slop_os.MemoryBudget,
        executable : slop_os.Memory,
        grant_count : u32,
        labels : u8[MAX_GRANTS][slop_os.GRANT_LABEL_SIZE],
        grants : slop_os.Handle[MAX_GRANTS],
    }

    LoadStatus :: enum #backed_by(u32) {
        // Not a Load's handles, or too many grants
        BadRequest = 2,
        // The executable isn't one the loader takes
        NotAProgram = 3,
        // The budget couldn't pay, or there was no room
        NoMemory = 4,
        // The entropy service didn't answer
        NoRandom = 5,
        // A call failed building it
        Failed = 6,
    }

    Response :: union {
        // Loaded, with its first thread's ID
        Loaded(u64),
        NotLoaded(LoadStatus),
        Unsupported,
    }

    // Every request can be sent again after a reconnect: a Load the manager didn't answer built nothing that stays.
    is_idempotent :: fn(request: ptr[Request]) -> bool {
        return match request^ {
            case Load(_) => true
            case Connect(_) => true
        }
    }

    #insert os.protocol_code(Request, Response)

    #assert cast[u32](size_of(Request)) <= slop_os.channel_max_payload(RING_BYTES)

    /*
     * A new connection to the manager that end reaches: a channel for ProcessManager, one end sent in a Connect, the other
     * given back, or null.
     */
    connect :: fn(end: slop_os.Channel, port: slop_os.Port, budget: slop_os.MemoryBudget) -> os.Channel[ProcessManager]? {
        pair :: os.channel_for[ProcessManager](budget, RING_BYTES) or_return null
        out := os.Outgoing.{}
        request :: os.begin[Request](&out)
        request^ = .Connect(os.Channel[ProcessManager].{end = pair.a})
        match send_request(end, port, &out) {
            case Some(error) => {
                _ = slop_os.handle_close(cast[slop_os.Handle](pair.a))
                _ = slop_os.handle_close(cast[slop_os.Handle](pair.b))
                return null
            }
            case None => return os.Channel[ProcessManager].{end = pair.b}
        }
    }
}

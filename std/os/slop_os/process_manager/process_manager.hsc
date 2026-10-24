package process_manager

import slop_os from "std/os"

/*
 * The process manager's protocol (the SlopOS repository's decisions 0067, 0068): it loads programs into
 * processes their requesters made, which stay theirs, and serves each client one request at a time, in
 * order. Each message is a fixed-layout struct starting with its tag, sent as its bytes, with its handles
 * in the message's batch in the order its comment gives. std/os's launch speaks it.
 */

// The protocol, for os.Channel[ProcessManager]: its name is its tag's (os.protocol_tag).
ProcessManager :: struct {}

// Load a program into a process the requester made, which stays the requester's and is paid for by it.
LOAD : u32 : 1
// Serve another client: the request's one handle is a channel end to read requests from.
CONNECT : u32 : 2

// The rings a connection to the manager needs, for a LoadRequest (channel_create's ring bytes).
RING_BYTES : u32 : 2048

// The most grants a LoadRequest gives the new program.
MAX_GRANTS :: 12
// The handles a LoadRequest comes with: the process, its space, its budget and the executable, then its grants.
LOAD_HANDLES :: 4
LOAD_HANDLES_AND_GRANTS :: LOAD_HANDLES + MAX_GRANTS

/*
 * LOAD, with handles: the process (RIGHT_PROCESS_THREADS, RIGHT_DUPLICATE and RIGHT_TRANSFER), its address
 * space (owning, which goes to the process), its memory budget (RIGHT_BUDGET_CHARGE, RIGHT_DUPLICATE and
 * RIGHT_TRANSFER), the executable (a memory object, RIGHT_MEMORY_READ), then grant_count grants, each labeled
 * by labels and tagged by tags, in order, with RIGHT_TRANSFER. The manager keeps none of them.
 */
LoadRequest :: struct {
    tag : u32,
    grant_count : u32,
    // The program's name, for the manager's log
    name : u8[slop_os.GRANT_LABEL_SIZE],
    labels : u8[MAX_GRANTS][slop_os.GRANT_LABEL_SIZE],
    // Each grant's protocol, for a channel end, or 0 (slop_os.Grant.tag)
    tags : u64[MAX_GRANTS],
}

LoadStatus :: enum #backed_by(u32) {
    Loaded = 1,
    // Not a LoadRequest's handles, or too many grants
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

// The answer to a LoadRequest: its status, and once it's loaded, its first thread's ID.
LoadReply :: struct {
    tag : u32,
    status : LoadStatus,
    thread : u64,
}

// CONNECT, with the end to serve.
ConnectRequest :: struct {
    tag : u32,
    reserved : u32,
}

#assert cast[u32](size_of(LoadRequest)) <= slop_os.channel_max_payload(RING_BYTES)

package process_manager

import os from "std"
import slop_os from "std/os"

/*
 * The process manager's protocol (the SlopOS repository's decisions 0040, 0067, 0071): it loads programs into
 * processes their requesters made, which stay theirs, and serves each client one request at a time, in order.
 * std/os's launch speaks it. Its messages' code is generated (os.protocol_code), so a handle in one moves with it.
 */

/** The protocol, for os.Channel[ProcessManager]: its name is its tag's (os.protocol_tag). */
ProcessManager :: struct {}

/**
 * What the protocol says of itself: its name, which its channels' tag is made from, its major version, and that the
 * client's budget pays for the server's work, for each of its connections.
 */
PROTOCOL :: slop_os.Protocol.{name = "process_manager", major_version = 3, lending = .PerConnection}

/**
 * The bytes of each of the rings a connection to the manager needs, each way, so a Load fits in one message
 * (channel_create's ring bytes).
 */
RING_BYTES : u32 : 4096

/**
 * The most grants a Load gives the new program: with the Load's own four handles, within the 64 a message carries.
 */
MAX_GRANTS :: 48

/** What a client asks of the process manager. */
Request :: union {
    /**
     * Load a program into a process the requester made, which stays the requester's and is paid for by it. Its
     * handles move to the manager with it. Answered with Loaded, or NotLoaded and why.
     */
    Load(Load),
    /** Serve another client, on the end given, which moves to the manager. Not answered. */
    Connect(os.Channel[ProcessManager]),
}

/**
 * What a Load gives the manager, every handle of it moved with the message; the manager keeps none of them once
 * it's done.
 */
Load :: struct {
    /** The program's name, for the manager's log only: UTF-8, padded with zeros. */
    name : u8[slop_os.GRANT_LABEL_SIZE],
    /**
     * The process to load into, made by the requester, with RIGHT_PROCESS_THREADS, RIGHT_DUPLICATE and
     * RIGHT_TRANSFER: a duplicate, so the requester keeps the process.
     */
    process : slop_os.Process,
    /** The process's address space, empty, an owning handle, which goes to the process. */
    space : slop_os.AddressSpace,
    /**
     * The memory budget that pays for the program's memory, with RIGHT_BUDGET_CHARGE, RIGHT_DUPLICATE and
     * RIGHT_TRANSFER.
     */
    budget : slop_os.MemoryBudget,
    /** The executable, a memory object holding the program's file, with RIGHT_MEMORY_READ. */
    executable : slop_os.Memory,
    /** How many of grants and labels are used, from the first: 0 to MAX_GRANTS. */
    grant_count : u32,
    /**
     * Each grant's label, which the program finds it by in its startup block: UTF-8, padded with zeros; the first
     * grant_count are used.
     */
    labels : u8[MAX_GRANTS][slop_os.GRANT_LABEL_SIZE],
    /** The handles the program starts with, each with RIGHT_TRANSFER; the first grant_count are used. */
    grants : slop_os.Handle[MAX_GRANTS],
    /**
     * The seeds to build it with, when seeded: the program's own 32 bytes (its context.random), then the 32 its
     * layout's drawn from; so a replay is the recording's program to the byte (the SlopOS repository's
     * decisions/0183). Unused otherwise, when the manager draws them.
     */
    seeds : u8[64],
    /** Whether seeds are given; false for the manager's own, from the entropy service. */
    seeded : bool,
}

/** Why a Load failed, as NotLoaded says. */
LoadStatus :: enum #backed_by(u32) {
    /** Not a Load's handles, or too many grants. */
    BadRequest = 2,
    /** The executable isn't one the loader takes. */
    NotAProgram = 3,
    /** The budget couldn't pay, or there was no room. */
    NoMemory = 4,
    /** The entropy service didn't answer, so the program's seed couldn't be drawn. */
    NoRandom = 5,
    /** A call failed building it. */
    Failed = 6,
}

/** A program the manager started, as Loaded says. */
Started :: struct {
    /** Its first thread's ID, not a handle. */
    thread : u64,
    /** The address its image was loaded at, which its relocations were applied for, in its address space. */
    image : u64,
    /** The seeds it was built with, given or drawn (Load's seeds). */
    seeds : u8[64],
}

/** What the process manager answers. */
Response :: union {
    /** The answer to Load when the program's loaded: its first thread, and where its image is. */
    Loaded(Started),
    /** The answer to Load when it failed, and why. */
    NotLoaded(LoadStatus),
    /** The answer to a request the manager doesn't know, as from a newer client; every protocol has it. */
    Unsupported,
}

/**
 * Tell whether a request may be sent again, after a reconnect, without doing more than sending it once did.
 *
 * @param request The request, which isn't changed.
 * @return True for every request: a Load the manager didn't answer built nothing that stays.
 */
is_idempotent :: fn(request: ptr[Request]) -> bool {
    return match request^ {
        case Load(_) => true
        case Connect(_) => true
    }
}

#insert os.protocol_code(Request, Response)

#assert cast[u32](size_of(Request)) <= slop_os.channel_max_payload(RING_BYTES)

/**
 * Make a new connection to the process manager a connection reaches, with a Connect.
 *
 * The new channel's rings are RING_BYTES each way, so a Load fits. The Connect isn't answered, so a manager that
 * won't take the connection is learned of only when the new end finds its other end closed.
 *
 * @param end A connection to the manager, kept by the caller; only the Connect is sent on it.
 * @param port A port bound to end (port_for), waited on while end's ring is full.
 * @param budget The memory budget that pays for the new channel.
 * @return The new connection's end, which the caller owns and closes; null if the channel couldn't be made or the
 *     Connect couldn't be sent, and then nothing is left open.
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

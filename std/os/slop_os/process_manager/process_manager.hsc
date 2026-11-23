package process_manager

import os from "std:os"
import slop_os from "std:os/slop_os"

/*
 * The process manager's protocol (the SlopOS repository's decisions 0040, 0067, 0071, 0195): it makes a process for
 * each program it loads, charged to the requester's budget, and gives the requester the process's owning handle, so
 * the program is the requester's and outlives the manager; but with only the rights to watch it and end it, and to
 * read it where the Load asks (rights), never to start threads in it. What the requester wants before the program's
 * first instruction, the manager does for it: its CPU budget, a watch on its end, an intercept of it, which reports
 * the program's faults and samples it, but can't steer it (RIGHT_INTERCEPT_STEER). Steering a program, as a debugger
 * or a recorder does, is given only on the user's say (decisions/0195, 18b): Steer, which the manager answers only on
 * the connections of its steering listener, whose end the system's supervisor holds and gives on to the session
 * manager. It serves each client one request at a time, in order; std/os's launch speaks it. Its messages' code is generated
 * (os.protocol_code), so a handle in one moves with it.
 */

/** The protocol, for os.Channel[ProcessManager]: its name is its tag's (os.protocol_tag). */
ProcessManager :: struct {}

/**
 * What the protocol says of itself: its name, which its channels' tag is made from, its major version, and that the
 * client's budget pays for the server's work, for each of its connections.
 */
PROTOCOL :: slop_os.Protocol.{name = "process_manager", major_version = 4, lending = .PerConnection}

/**
 * The bytes of each of the rings a connection to the manager needs, each way, so a Load fits in one message
 * (channel_create's ring bytes).
 */
RING_BYTES : u32 : 8192

/**
 * The most grants a Load gives the new program: with the Load's own five handles, within the 64 a message carries, and
 * with the builder's own six, within the 64 process_give_handles takes.
 */
MAX_GRANTS :: 56

/** What a client asks of the process manager. */
Request :: union {
    /**
     * Load a program into a new process, the requester's and paid for by it. Its handles move to the manager with it.
     * Answered with Loaded, or NotLoaded and why.
     */
    Load(Load),
    /**
     * Serve another client, on the end given, which moves to the manager; one sent on a steering connection is a
     * steering connection too. Not answered.
     */
    Connect(os.Channel[ProcessManager]),
    /**
     * On a steering connection only: steer a program the manager loaded, which the user has allowed. Answered with
     * Steered, or NotSteered and why; on any other connection, NotSteered(NotAllowed).
     */
    Steer(Steer),
    /**
     * On a steering connection only (decisions/0195, 18d): which program the manager loaded holds the other end of
     * a channel whose one end is given, moving with the request, which the manager closes (channel_peer_owned_by).
     * Answered with Identified, or NotSteered: NoProgram if none does, NotAllowed on any other connection.
     */
    Identify(slop_os.Channel),
}

/** A program the manager loaded, as Identified says. */
Identity :: struct {
    /** Its process, with RIGHT_PROCESS_INSPECT and RIGHT_TRANSFER, which moves to the requester. */
    process : slop_os.Process,
    /** The executable it was loaded from, with RIGHT_MEMORY_READ and RIGHT_TRANSFER, which moves to the requester. */
    executable : slop_os.Memory,
    /** Whether it's been steered (Steer): what it does may be its steerer's, not its executable's. */
    steered : bool,
}

/** A program to steer, as Steer asks for it. */
Steer :: struct {
    /**
     * A handle to the program's process with RIGHT_PROCESS_KILL, as its launcher has, which the manager finds the
     * program by (handle_same) and closes; moved with the request.
     */
    process : slop_os.Process,
    /**
     * A port its stops go to from now, with RIGHT_PORT_BIND and RIGHT_TRANSFER: the intercept it had is detached
     * and a new one attached there, stopping at faults; NO_HANDLE to keep the one it has, or attach none.
     */
    port : slop_os.Port,
    /** The new intercept's key, with port. */
    key : u64,
}

/** A program steered, as Steered gives it. */
Steering :: struct {
    /** Its intercept, with RIGHT_INTERCEPT_STEER, a handle that moves to the requester; NO_HANDLE without one. */
    intercept : slop_os.Intercept,
    /**
     * Its process, with RIGHT_PROCESS_INSPECT, _READ_MEMORY, _WRITE_STATE, _KILL and RIGHT_TRANSFER, never
     * RIGHT_PROCESS_THREADS or _INTERCEPT; moves to the requester.
     */
    process : slop_os.Process,
    /** Its address space, with RIGHT_TRANSFER alone, for process_read_memory and process_write_memory. */
    space : slop_os.AddressSpace,
}

/** Why a Steer was refused. */
NotSteered :: enum #backed_by(u32) {
    /** Not a steering connection. */
    NotAllowed = 1,
    /** No program the manager loaded, live, that handle's to, or a handle without RIGHT_PROCESS_KILL. */
    NoProgram = 2,
    /** The intercept couldn't be attached, or a handle not made, as with a port without the right. */
    Failed = 3,
}

/**
 * What a Load gives the manager, every handle of it moved with the message; the manager keeps none of them once
 * it's done.
 */
Load :: struct {
    /** The program's name, for the manager's log only: UTF-8, padded with zeros. */
    name : u8[slop_os.GRANT_LABEL_SIZE],
    /**
     * The memory budget that pays for the program: its process, its address space and its memory, with
     * RIGHT_BUDGET_CHARGE, RIGHT_DUPLICATE and RIGHT_TRANSFER.
     */
    budget : slop_os.MemoryBudget,
    /**
     * The CPU budget the program runs on from its first instruction, with RIGHT_CPU_BUDGET_BIND and RIGHT_TRANSFER;
     * NO_HANDLE for the manager's own. Closed once it's put on.
     */
    cpu_budget : slop_os.CpuBudget,
    /**
     * A port of the requester's its end is reported on, a Once binding of SIGNAL_TERMINATED under watch_key made
     * before it starts, so even a program that ends at once is seen to: a duplicate with RIGHT_PORT_BIND and
     * RIGHT_TRANSFER, closed once it's bound; NO_HANDLE for no watch.
     */
    watch_port : slop_os.Port,
    /** The key watch_port's packet comes with, which mustn't be bound on it already. */
    watch_key : u64,
    /**
     * A port of the requester's an intercept of the program reports its stops on, attached before it starts
     * (intercept_attach), as for its crash reports or a debugger: a duplicate with RIGHT_PORT_BIND and RIGHT_TRANSFER,
     * closed once it's attached; NO_HANDLE for none.
     */
    intercept_port : slop_os.Port,
    /** The intercept's key, calls and STOP_ bits, as intercept_attach takes them. */
    intercept_key : u64,
    intercept_calls : u64,
    intercept_points : u32,
    /**
     * Rights the requester's handle to the process has beside RIGHT_PROCESS_KILL, RIGHT_PROCESS_INSPECT,
     * RIGHT_DUPLICATE and RIGHT_TRANSFER: RIGHT_PROCESS_READ_MEMORY; the rest are never given, but through Steer.
     * 0 for none.
     */
    rights : slop_os.Rights,
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
    /** The CPU budget given couldn't be put on the process: destroyed, or a handle without the right. */
    NoCpuBudget = 7,
    /** The watch or the intercept couldn't be made, as with a port without the right, or a key bound already. */
    NoWatch = 8,
}

/** A program the manager started, as Loaded says. */
Started :: struct {
    /**
     * Its process, the owning handle, which moves to the requester: closing it ends the program. With
     * RIGHT_PROCESS_KILL, RIGHT_PROCESS_INSPECT, RIGHT_DUPLICATE and RIGHT_TRANSFER, and those of the Load's rights
     * it may have. NO_HANDLE, with no intercept or space, for a program that ended before it was answered, whose
     * process is gone: its end was reported on the Load's watch.
     */
    process : slop_os.Process,
    /**
     * The intercept the Load asked for, which moves to the requester, without RIGHT_INTERCEPT_STEER: the manager keeps
     * its owning handle while the program runs. NO_HANDLE for none.
     */
    intercept : slop_os.Intercept,
    /**
     * With the intercept, the program's address space, with RIGHT_TRANSFER alone, for process_read_memory, which
     * needs none on it, and to move on, as to a debugger; NO_HANDLE without one.
     */
    space : slop_os.AddressSpace,
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
    /** Steer's answer: the program's steering handles. */
    Steered(Steering),
    /** Identify's answer: the program that holds the channel's other end. */
    Identified(Identity),
    /** Steer's answer when it's refused. */
    NotSteered(NotSteered),
    /** The answer to a request the manager doesn't know, as from a newer client; every protocol has it. */
    Unsupported,
}

/**
 * Tell whether a request may be sent again, after a reconnect, without doing more than sending it once did.
 *
 * @param request The request, which isn't changed.
 * @return True for every request: a Load the manager didn't answer built nothing that stays.
 */
is_idempotent :: fn(request : ptr[Request]) -> bool {
    return match request^ {
        case Load(_) => true
        case Connect(_) => true
        case Steer(_) => true
        case Identify(_) => true
    }
}

#insert os.protocol_code(Request, Response)

#assert cast[u32](size_of(Request)) <= slop_os.channel_max_payload(RING_BYTES)

/**
 * Ask the process manager to steer a program it loaded, on a steering connection, once the user's allowed it, and wait
 * for its answer.
 *
 * @param end A steering connection to the manager, kept by the caller.
 * @param port A port bound to end, waited on for the answer.
 * @param process A handle to the program's process with RIGHT_PROCESS_KILL and RIGHT_DUPLICATE, as its launcher has,
 *     which stays the caller's: a duplicate goes with the request.
 * @param stops A port the program's stops go to from now, with RIGHT_PORT_BIND and RIGHT_TRANSFER, which moves with the
 *     request, the caller's no longer, sent or not: its intercept is replaced by one there, stopping at faults; null to
 *     keep the intercept it has.
 * @param key The new intercept's key, with stops.
 * @return Its steering handles, the caller's (Steering); or why not: NotAllowed, as on a connection that isn't a
 *     steering one, NoProgram, or Failed, as when a handle couldn't be duplicated or the manager didn't answer.
 */
steer :: fn(
    end : slop_os.Channel,
    port : slop_os.Port,
    process : slop_os.Process,
    stops : slop_os.Port?,
    key : u64
) -> Result[Steering, NotSteered] {
    out := os.Outgoing.{}
    request :: os.begin[Request](&out)
    given := Steer.{port = cast[slop_os.Port](slop_os.NO_HANDLE), key = key}
    given.process = cast[slop_os.Process](slop_os.handle_duplicate(
        cast[slop_os.Handle](process),
        cast[slop_os.Rights](cast[u32](slop_os.RIGHT_PROCESS_KILL) | cast[u32](slop_os.RIGHT_TRANSFER))
    ) or_else slop_os.NO_HANDLE)
    if cast[slop_os.Handle](given.process) == slop_os.NO_HANDLE {
        match stops {
            case Some(stopping) => _ = slop_os.handle_close(cast[slop_os.Handle](stopping))
            case None => {}
        }
        return .Error(.Failed)
    }
    match stops {
        case Some(stopping) => given.port = stopping
        case None => {}
    }
    request^ = .Steer(given)
    if send_request(end, port, &out) is_some {
        _ = slop_os.handle_close(cast[slop_os.Handle](given.process))
        if cast[slop_os.Handle](given.port) != slop_os.NO_HANDLE {
            _ = slop_os.handle_close(cast[slop_os.Handle](given.port))
        }
        return .Error(.Failed)
    }
    into := os.Incoming.{}
    match receive_response(end, port, &into, true) {
        case Received => {}
        case _ => return .Error(.Failed)
    }
    return match os.message_of[Response](&into)^ {
        case Steered(steering) => .Ok(steering)
        case NotSteered(why) => .Error(why)
        case _ => .Error(.Failed)
    }
}

/**
 * Ask the process manager, on a steering connection, which program it loaded holds a channel's other end, and wait.
 *
 * @param end A steering connection to the manager, kept by the caller.
 * @param port A port bound to end, waited on for the answer.
 * @param channel The caller's end of the channel, which stays the caller's: a duplicate goes with the request.
 * @return The program, its handles the caller's (Identity); or why not: NoProgram if no program it loaded holds it,
 *     NotAllowed, or Failed, as when the duplicate couldn't be made or the manager didn't answer.
 */
identify :: fn(end : slop_os.Channel, port : slop_os.Port, channel : slop_os.Channel) -> Result[Identity, NotSteered] {
    copy :: slop_os.handle_duplicate(cast[slop_os.Handle](channel), slop_os.RIGHT_TRANSFER) or_return .Error(.Failed)
    out := os.Outgoing.{}
    request :: os.begin[Request](&out)
    request^ = .Identify(cast[slop_os.Channel](copy))
    if send_request(end, port, &out) is_some {
        _ = slop_os.handle_close(copy)
        return .Error(.Failed)
    }
    into := os.Incoming.{}
    match receive_response(end, port, &into, true) {
        case Received => {}
        case _ => return .Error(.Failed)
    }
    return match os.message_of[Response](&into)^ {
        case Identified(identity) => .Ok(identity)
        case NotSteered(why) => .Error(why)
        case _ => .Error(.Failed)
    }
}

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
connect :: fn(
    end : slop_os.Channel,
    port : slop_os.Port,
    budget : slop_os.MemoryBudget
) -> os.Channel[ProcessManager]? {
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

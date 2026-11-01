package lifecycle

#if base.OS == .SlopOS {
    import runtime from "base"
    import slop_os from "std/os"

    /*
     * The lifecycle channel (the SlopOS repository's decisions 0136, 0139): what a launcher keeps to ask a program it
     * launched whether it's responding, and to stop. The program's end is given as the launch's lifecycle option, and
     * base's runtime serves it on a thread of its own, so a Ping is answered whatever the program's code is doing, and a
     * Stop is what stop_requested says, and what on_stop wakes a port for. Messages are base's
     * runtime.SlopOsLifecycleMessage, 8 bytes each way.
     */

    Answer :: enum {
        // To a Ping, with its sequence
        Pong,
        // To a Stop: the program's been told
        Stopping,
    }

    // An answer, and the sequence of what it answers.
    Reply :: struct {
        answer : Answer,
        sequence : u32,
    }

    // A new lifecycle channel: the launcher's end, a, and the program's, b, for LaunchOptions.lifecycle.
    make :: fn(budget: slop_os.MemoryBudget) -> slop_os.ChannelPair? {
        match slop_os.channel_create(budget, 0, 0) {
            case Ok(pair) => return pair
            case Error(error) => return null
        }
    }

    // A Ping with sequence, which the program answers with a Pong with it; whether it went.
    ping :: fn(end: slop_os.Channel, sequence: u32) -> bool {
        return send(end, runtime.SLOP_OS_LIFECYCLE_PING, sequence)
    }

    // A Stop: the program's asked to end, as it chooses to; whether it went.
    stop :: fn(end: slop_os.Channel) -> bool {
        return send(end, runtime.SLOP_OS_LIFECYCLE_STOP, 0)
    }

    send :: fn(end: slop_os.Channel, kind: u32, sequence: u32) -> bool {
        message := runtime.SlopOsLifecycleMessage.{kind = kind, sequence = sequence}
        bytes :: view_of(cast[ptr[u8]](&message), size_of(runtime.SlopOsLifecycleMessage))
        match slop_os.channel_write(end, bytes, slop_os.NO_BATCH) {
            case Ok => return true
            case Error(error) => return false
        }
    }

    // The program's next answer; null if there's none yet, or the program's end is gone.
    read :: fn(end: slop_os.Channel) -> Reply? {
        message := runtime.SlopOsLifecycleMessage.{}
        buffer :: view_of(cast[ptr[mut u8]](&message), size_of(runtime.SlopOsLifecycleMessage))
        size : u32 = 0
        match slop_os.channel_read(end, buffer, &size) {
            case Ok(_) => {}
            case Error(error) => return null
        }
        if message.kind == runtime.SLOP_OS_LIFECYCLE_PONG {
            return Reply.{answer = .Pong, sequence = message.sequence}
        }
        if message.kind == runtime.SLOP_OS_LIFECYCLE_STOPPING {
            return Reply.{answer = .Stopping, sequence = message.sequence}
        }
        return null
    }

    // In the program: whether whoever launched it has asked it to stop.
    stop_requested :: fn() -> bool {
        return runtime.slop_os_stop_requested()
    }

    /*
     * In the program: a User packet for key on port once it's asked to stop, or at once if it has been, for a program
     * waiting on its port to notice.
     */
    on_stop :: fn(port: slop_os.Port, key: u64) -> bool {
        match slop_os.port_bind_wake(port, key) {
            case Ok => {}
            case Error(error) => return false
        }
        runtime.slop_os_on_stop(cast[u64](cast[slop_os.Handle](port)), key)
        return true
    }
}

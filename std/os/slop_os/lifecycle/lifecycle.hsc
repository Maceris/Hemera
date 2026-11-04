package lifecycle

#if base.OS == .SlopOS {
    import runtime from "base"
    import slop_os from "std/os"

    /*
     * The lifecycle channel (the SlopOS repository's decisions 0136, 0139): what a launcher keeps to ask a program it
     * launched whether it's responding, and to stop. The program's end is given as the launch's lifecycle option,
     * and base's runtime serves it on a thread of its own, so a Ping is answered whatever the program's code is doing,
     * and a Stop is what stop_requested says, and what on_stop wakes a port for. Messages are base's
     * runtime.SlopOsLifecycleMessage, 8 bytes each way.
     */

    /** What a program's answer on its lifecycle channel is. */
    Answer :: enum {
        /** The answer to a Ping, with its sequence: the program's runtime is answering. */
        Pong,
        /**
         * The answer to a Stop: the program's been told. It doesn't say the program has stopped, or that it will;
         * whoever launched it decides how long to wait.
         */
        Stopping,
    }

    /** An answer, and the sequence of what it answers. */
    Reply :: struct {
        /** Whether it answers a Ping or a Stop. */
        answer : Answer,
        /** The sequence of the Ping it answers, as ping was given it; a Stop's is 0, as stop sends it. */
        sequence : u32,
    }

    /**
     * Make a new lifecycle channel, for LaunchOptions.lifecycle.
     *
     * The channel has the default rings and no protocol tag, since its messages are base's runtime's, not a protocol
     * package's.
     *
     * @param budget The memory budget that pays for the channel.
     * @return The channel's ends, both the caller's: a, the launcher's, to keep, and b, the program's, to give the
     *     launch; null if the channel couldn't be made.
     */
    make :: fn(budget: slop_os.MemoryBudget) -> slop_os.ChannelPair? {
        match slop_os.channel_create(budget, 0, 0) {
            case Ok(pair) => return pair
            case Error(error) => return null
        }
    }

    /**
     * Ask the program whether it's answering: send a Ping, which its runtime answers with a Pong, whatever the
     * program's code is doing.
     *
     * It doesn't wait: the Pong comes to read, once the program's runtime has answered.
     *
     * @param end The launcher's end of the lifecycle channel, kept by the caller.
     * @param sequence The caller's number for the Ping, which its Pong carries back, so a late Pong can be told from a
     *     new one; any value.
     * @return True if the Ping went; false if it couldn't be written, as when the ring's full or the program's end is
     *     gone.
     */
    ping :: fn(end: slop_os.Channel, sequence: u32) -> bool {
        return send(end, runtime.SLOP_OS_LIFECYCLE_PING, sequence)
    }

    /**
     * Ask the program to stop: send a Stop, which its runtime passes on (stop_requested, on_stop) and answers with
     * Stopping.
     *
     * The program ends as it chooses to, or not at all; this doesn't end it, or wait.
     *
     * @param end The launcher's end of the lifecycle channel, kept by the caller.
     * @return True if the Stop went; false if it couldn't be written, as when the ring's full or the program's end is
     *     gone.
     */
    stop :: fn(end: slop_os.Channel) -> bool {
        return send(end, runtime.SLOP_OS_LIFECYCLE_STOP, 0)
    }

    /**
     * Write one lifecycle message on a channel, through the kernel's copy, without waiting.
     *
     * @param end The end to write on, kept by the caller.
     * @param kind What the message is: one of base's runtime.SLOP_OS_LIFECYCLE_ constants.
     * @param sequence The message's sequence, which its answer carries back.
     * @return True if it was written; false if it couldn't be, as when the ring's full or the other end is gone.
     */
    send :: fn(end: slop_os.Channel, kind: u32, sequence: u32) -> bool {
        message := runtime.SlopOsLifecycleMessage.{kind = kind, sequence = sequence}
        bytes :: view_of(cast[ptr[u8]](&message), size_of(runtime.SlopOsLifecycleMessage))
        match slop_os.channel_write(end, bytes, slop_os.NO_BATCH) {
            case Ok => return true
            case Error(error) => return false
        }
    }

    /**
     * Take the program's next answer, without waiting for one.
     *
     * @param end The launcher's end of the lifecycle channel, kept by the caller.
     * @return The answer and the sequence of what it answers; null if there's none yet, if the program's end is gone,
     *     or if the message isn't a Pong or a Stopping, which is then dropped.
     */
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

    /**
     * In the program: tell whether whoever launched it has asked it to stop.
     *
     * Safe from any thread; a thread that sees true sees everything the runtime did before.
     *
     * @return True once a Stop has come on the lifecycle channel, and from then on; false before, and always for a
     *     program given no lifecycle channel.
     */
    stop_requested :: fn() -> bool {
        return runtime.slop_os_stop_requested()
    }

    /**
     * In the program: ask for a User packet for key on port once it's asked to stop, or at once if it has been, for a
     * program waiting on its port to notice.
     *
     * It makes the port's wake binding for key first (port_bind_wake). Only one port is remembered: a later call
     * replaces an earlier one's port and key.
     *
     * @param port A port of the program's, which has to stay open for as long as a stop may come.
     * @param key The key the packet carries, so the program can tell it from its port's other packets; the port
     *     mustn't have another binding for it.
     * @return True if the wake binding was made and the packet asked for; false if the binding couldn't be made, and
     *     then nothing was asked for.
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

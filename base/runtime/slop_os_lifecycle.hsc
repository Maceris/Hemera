package runtime

import intrinsics from "base"

/*
 * The lifecycle channel on SlopOS (the SlopOS repository's decisions 0136, 0139): a program given a channel labeled
 * "lifecycle" has it served by a thread of the runtime's own, started before main, so answering doesn't depend on the
 * program's code. Ping is answered with Pong and its sequence; Stop asks the program to end, which it learns from
 * slop_os_stop_requested, or from a packet on a port it asked for one on with slop_os_on_stop, and is answered with
 * Stopping. Whoever holds the other end decides what a missed Pong, or a program still running after Stop, means. The
 * messages are 8 bytes, a kind and a sequence, read and written through the kernel's copy, so the runtime needs no
 * mapping or protocol code for them; std/os/slop_os's lifecycle is the other end.
 */
#if OS == .SlopOS && (TARGET_ARCH == .x86_64 || TARGET_ARCH == .arm64) {
    /** The kernel's error for a channel read whose other end has closed, which ends the lifecycle thread's serving. */
    SLOP_OS_ERROR_PEER_CLOSED : u64 : 12

    /** A message on the lifecycle channel, either way: 8 bytes, written and read whole through the kernel's copy. */
    SlopOsLifecycleMessage :: struct {
        /** What the message is: one of the SLOP_OS_LIFECYCLE_ constants; one of any other kind is ignored. */
        kind : u32,
        /**
         * The asker's number for the message, chosen by the other end; an answer carries its question's, so the other
         * end can tell which question a Pong or Stopping answers.
         */
        sequence : u32,
    }

    /** A question from the other end: is the program still answering? Answered with SLOP_OS_LIFECYCLE_PONG. */
    SLOP_OS_LIFECYCLE_PING : u32 : 1
    /**
     * A request from the other end that the program end. Remembered for slop_os_stop_requested, and answered with
     * SLOP_OS_LIFECYCLE_STOPPING.
     */
    SLOP_OS_LIFECYCLE_STOP : u32 : 2
    /** The runtime's answer to SLOP_OS_LIFECYCLE_PING, with the ping's sequence. */
    SLOP_OS_LIFECYCLE_PONG : u32 : 3
    /**
     * The runtime's answer to SLOP_OS_LIFECYCLE_STOP, with the stop's sequence. It says the request was passed on to
     * the program, not that the program has stopped or will.
     */
    SLOP_OS_LIFECYCLE_STOPPING : u32 : 4
    /**
     * From the program, unasked: how far along its work is, its sequence the thousandths done, 0 to 1000. Written by
     * the program's own code (std/os/slop_os's lifecycle.report_progress), never by the lifecycle thread.
     */
    SLOP_OS_LIFECYCLE_PROGRESS : u32 : 5

    /** The lifecycle thread's stack, in bytes, which needs little: it calls the kernel, and nothing else. */
    SLOP_OS_LIFECYCLE_STACK : usize : 16 * 1024

    /**
     * What the lifecycle thread starts with: its carrier block and its end of the channel. It's in mapped pages of its
     * own, kept for the rest of the process, since the thread has no one to give them back to.
     */
    SlopOsLifecycle :: struct {
        /** The lifecycle thread's carrier block, its stack limits set from its own stack. */
        carrier : CarrierBlock,
        /** The handle of the program's end of the lifecycle channel, from its startup grant. */
        channel : u64,
        /** The lowest address of the thread's SLOP_OS_LIFECYCLE_STACK bytes of stack, from map_pages. */
        stack : rawptr,
    }

    /**
     * Start the lifecycle thread, if the program was given a "lifecycle" channel.
     *
     * Called before main, from the entry, which has no context yet; nothing it does needs one. Without the grant,
     * nothing happens. If the thread's block or stack can't be mapped, or the kernel won't make the thread, the program
     * runs without its channel being served, and nothing reports it; whatever was mapped stays mapped.
     */
    slop_os_start_lifecycle #no_context :: fn() {
        channel :: os_entry_grant("lifecycle", "Channel", "", false)
        if channel == 0 {
            return void
        }
        lifecycle :: cast[ptr[mut SlopOsLifecycle]](map_pages(size_of(SlopOsLifecycle)))
        stack :: map_pages(SLOP_OS_LIFECYCLE_STACK)
        if cast[rawptr](lifecycle) == null || stack == null {
            return void
        }
        lifecycle.channel = cast[u64](channel)
        lifecycle.stack = stack
        lifecycle.carrier.native_stack_limit = cast[rawptr](cast[u64](cast[uintptr](stack)) + STACK_RESERVE)
        lifecycle.carrier.stack_limit = lifecycle.carrier.native_stack_limit
        _ = slop_os_start_thread(cast[rawptr](slop_os_lifecycle_entry), stack, SLOP_OS_LIFECYCLE_STACK, cast[u64](cast[uintptr](lifecycle)))
    }

    /**
     * Run the lifecycle thread: load its carrier block, answer every message until the other end closes, then end the
     * thread.
     *
     * It's the kernel thread's entry, so it never returns; its stack and block stay mapped after it ends.
     *
     * @param argument The address of the thread's SlopOsLifecycle, as slop_os_start_lifecycle gave it.
     */
    slop_os_lifecycle_entry #calling_convention(.c) #no_context :: fn(argument: u64) #never_returns {
        lifecycle :: cast[ptr[mut SlopOsLifecycle]](cast[rawptr](cast[uintptr](argument)))
        intrinsics.set_carrier(&lifecycle.carrier)
        slop_os_serve_lifecycle(lifecycle.channel)
        slop_os_call(SLOP_OS_CALL_THREAD_EXIT)
        loop {
            intrinsics.trap()
        }
    }

    /**
     * Answer the lifecycle channel's messages until its other end closes.
     *
     * Between reads it waits on a port of its own, bound to the channel's readable and peer-closed signals. Ping is
     * answered with Pong, and Stop is passed on through slop_os_request_stop and answered with Stopping, each with the
     * question's sequence; a message of any other kind is dropped without an answer. If the port can't be made or
     * bound, it returns at once and the channel goes unanswered. The port is closed at the end; the channel isn't.
     *
     * @param channel The handle of the program's end of the lifecycle channel, which has to stay open while this runs.
     */
    slop_os_serve_lifecycle #no_context :: fn(channel: u64) {
        startup :: cast[ptr[SlopOsStartup]](intrinsics.process_state().startup_block)
        port :: slop_os_call(SLOP_OS_CALL_PORT_CREATE, cast[u64](startup.budget))
        if port.tag != 0 {
            return void
        }
        signals :: SLOP_OS_SIGNAL_READABLE | SLOP_OS_SIGNAL_PEER_CLOSED
        if slop_os_call(SLOP_OS_CALL_PORT_BIND, port.first, channel, signals, 0, SLOP_OS_BIND_PERSISTENT).tag != 0 {
            return void
        }
        loop {
            message : SlopOsLifecycleMessage
            read :: slop_os_call(SLOP_OS_CALL_CHANNEL_READ, channel, cast[u64](cast[uintptr](&message)), cast[u64](size_of(SlopOsLifecycleMessage)), 0)
            if read.tag == SLOP_OS_ERROR_PEER_CLOSED {
                break
            }
            if read.tag != 0 {
                // Nothing to read until the channel says there is
                packets : u64[SLOP_OS_PACKET_WORDS]
                slop_os_call(SLOP_OS_CALL_PORT_WAIT, port.first, cast[u64](cast[uintptr](&packets[0])), 1, SLOP_OS_NO_DEADLINE)
                continue
            }
            answer := SlopOsLifecycleMessage.{sequence = message.sequence}
            if message.kind == SLOP_OS_LIFECYCLE_PING {
                answer.kind = SLOP_OS_LIFECYCLE_PONG
            }
            else if message.kind == SLOP_OS_LIFECYCLE_STOP {
                slop_os_request_stop()
                answer.kind = SLOP_OS_LIFECYCLE_STOPPING
            }
            else {
                continue
            }
            slop_os_call(SLOP_OS_CALL_CHANNEL_WRITE, channel, cast[u64](cast[uintptr](&answer)), cast[u64](size_of(SlopOsLifecycleMessage)),
                SLOP_OS_NO_BATCH)
        }
        slop_os_call(SLOP_OS_CALL_HANDLE_CLOSE, port.first)
    }

    /**
     * Record that a stop was asked for, and wake the port the program asked for a packet on, if it asked for one.
     *
     * Safe from any thread: the request is stored with release ordering, so a thread that sees it through
     * slop_os_stop_requested sees everything before it. Asking again wakes the port again.
     */
    slop_os_request_stop #no_context :: fn() {
        state :: intrinsics.process_state()
        intrinsics.atomic_store_u32_release(&state.stop_requested, 1)
        port :: intrinsics.atomic_load_u64_acquire(&state.stop_port)
        if port != 0 {
            slop_os_call(SLOP_OS_CALL_PORT_WAKE, port, state.stop_key, 1)
        }
    }

    /**
     * Tell whether whoever started the program has asked it to stop.
     *
     * @return True once a Stop has come on the lifecycle channel, and from then on; false before, and always for a
     *     program given no lifecycle channel.
     */
    slop_os_stop_requested #no_context :: fn() -> bool {
        return intrinsics.atomic_load_u32_acquire(&intrinsics.process_state().stop_requested) != 0
    }

    /**
     * Ask for a User packet for key on port once a stop's asked for, or at once if it has been already.
     *
     * Only one port is remembered: a later call replaces an earlier one's port and key. The packet comes through the
     * port's wake binding, so a wake binding for key has to be made on the port first (port_bind_wake), or the wake is
     * lost.
     *
     * @param port The handle of a port of the program's, which has to stay open for as long as a stop may come; 0
     *     asks for no packet from then on.
     * @param key The key the packet carries, so the program can tell it from its port's other packets.
     */
    slop_os_on_stop #no_context :: fn(port: u64, key: u64) {
        state :: intrinsics.process_state()
        state.stop_key = key
        intrinsics.atomic_store_u64_release(&state.stop_port, port)
        if slop_os_stop_requested() {
            slop_os_call(SLOP_OS_CALL_PORT_WAKE, port, key, 1)
        }
    }
}

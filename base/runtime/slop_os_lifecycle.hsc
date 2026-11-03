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
    SLOP_OS_ERROR_PEER_CLOSED : u64 : 12

    SlopOsLifecycleMessage :: struct {
        kind : u32,
        sequence : u32,
    }

    SLOP_OS_LIFECYCLE_PING : u32 : 1
    SLOP_OS_LIFECYCLE_STOP : u32 : 2
    SLOP_OS_LIFECYCLE_PONG : u32 : 3
    SLOP_OS_LIFECYCLE_STOPPING : u32 : 4

    /** The lifecycle thread's stack, which needs little: it calls the kernel, and nothing else */
    SLOP_OS_LIFECYCLE_STACK : usize : 16 * 1024

    /** What the lifecycle thread starts with: its carrier block and its end of the channel. */
    SlopOsLifecycle :: struct {
        carrier : CarrierBlock,
        channel : u64,
        stack : rawptr,
    }

    /**
     * The lifecycle thread, if the program was given a "lifecycle" channel: started before main, from the entry, which
     * has no context yet; nothing it does needs one.
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

    /** The lifecycle thread: every message answered, until the other end closes, when the thread ends. */
    slop_os_lifecycle_entry #calling_convention(.c) #no_context :: fn(argument: u64) #never_returns {
        lifecycle :: cast[ptr[mut SlopOsLifecycle]](cast[rawptr](cast[uintptr](argument)))
        intrinsics.set_carrier(&lifecycle.carrier)
        slop_os_serve_lifecycle(lifecycle.channel)
        slop_os_call(SLOP_OS_CALL_THREAD_EXIT)
        loop {
            intrinsics.trap()
        }
    }

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

    /** The stop asked for: remembered, and the port the program asked for a packet on, if any, woken. */
    slop_os_request_stop #no_context :: fn() {
        state :: intrinsics.process_state()
        intrinsics.atomic_store_u32_release(&state.stop_requested, 1)
        port :: intrinsics.atomic_load_u64_acquire(&state.stop_port)
        if port != 0 {
            slop_os_call(SLOP_OS_CALL_PORT_WAKE, port, state.stop_key, 1)
        }
    }

    /** Whether whoever started the program has asked it to stop. */
    slop_os_stop_requested #no_context :: fn() -> bool {
        return intrinsics.atomic_load_u32_acquire(&intrinsics.process_state().stop_requested) != 0
    }

    /**
     * A User packet for key on port, which a wake binding for key must be made on first (port_bind_wake), once a stop's
     * asked for, or at once if it has been.
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

package net

/*
 * TCP and UDP over a connection to SlopOS's network service (std/os/slop_os's network, tcp_stream, tcp_listener and
 * datagrams protocols), on SlopOS only.
 *
 * A TCP connection's data is in memory this makes and maps, two rings the service maps too: write copies into the
 * first, read copies out of the second, and each tells the service how far, waiting while there's no room or nothing
 * to read. Each call waits on a port of the connection's own, so a program on fibers waits a fiber at a time.
 *
 *     connection :: net.open(network, net_address.Endpoint.{address = net_address.v4(10, 0, 2, 2), port = 7})?
 *     _ = net.write(&connection, string_bytes("hello"))
 *     count :: net.read(&connection, buffer)?      // 0 once the peer has finished
 *     net.close(&connection)
 *
 * Names are resolved by the service: open_name connects to a host by name, and resolve gives a name's addresses.
 */

#if base.OS == .SlopOS {
    import runtime from "base"
    import os from "std"
    import slop_os from "std/os"
    import net_address from "std/os/slop_os"
    import network from "std/os/slop_os"
    import tcp_stream from "std/os/slop_os"
    import tcp_listener from "std/os/slop_os"
    import datagrams from "std/os/slop_os"

    /** The memory a connection's rings are made in by default: 128 KiB, rings of 64 KiB each way. */
    DEFAULT_MEMORY : u64 : 131072
    /** A page's size: a connection's memory is a whole number of them. */
    PAGE : u64 : 4096

    /** Why open, listen, udp or accept failed. */
    Failure :: enum {
        /** The service refused: the connection's policy doesn't allow it. */
        NotAllowed,
        /** The port's taken already. */
        PortTaken,
        /** No route, or no address to send from. */
        NoRoute,
        /** The service, or this program, has no room. */
        NoRoom,
        /** The endpoint isn't one. */
        BadEndpoint,
        /** Nothing listens there: the peer refused. */
        Refused,
        /** Nothing answered. */
        TimedOut,
        /** The peer reset it. */
        Reset,
        /** The connection to the service failed. */
        Broken,
        /** The name doesn't exist. */
        NoSuchName,
        /** The name has no address of the kinds asked for. */
        NoAddress,
        /** No DNS server answered, or every one failed: maybe for now. */
        ResolveFailed,
        /** The name isn't one. */
        BadName,
    }

    /** A name's addresses, as resolve gives them. */
    Addresses :: struct {
        /** The first count are the name's, IPv6 and IPv4 taking turns, IPv6 first. */
        addresses : net_address.Address[network.MAX_ADDRESSES],
        count : usize,
    }

    /** A TCP connection's state, the caller's, until close. */
    Tcp :: struct {
        /** Its channel. */
        stream : os.Channel[tcp_stream.TcpStream],
        /** A port of its own, bound to stream, waited on. */
        port : slop_os.Port,
        /** Its memory, and where it's mapped. */
        memory : slop_os.Memory,
        at : u64,
        /** Each ring's size: half the memory. */
        ring : u64,
        /** How far it's written and read, from the start. */
        written : u64,
        read : u64,
        /** Its progress, as the service last said. */
        progress : tcp_stream.Progress,
        /** Whether a Watch is held. */
        watching : bool,
        /** Whether it's finished writing. */
        finished : bool,
    }

    /** A listening port's state, the caller's, until close_listener. */
    Listener :: struct {
        channel : os.Channel[tcp_listener.TcpListener],
        port : slop_os.Port,
    }

    /** A UDP socket's state, the caller's, until close_udp. */
    Udp :: struct {
        channel : os.Channel[datagrams.Datagrams],
        port : slop_os.Port,
    }

    /**
     * Open a TCP connection, and wait until it's open or has failed.
     *
     * @param service A connection to the network service, the caller's.
     * @param to Who to.
     * @param memory_bytes The memory for its rings: at least two pages, rounded up to a whole number of them.
     * @return The connection, open; or why it couldn't be.
     */
    open :: fn(service: os.Channel[network.Network], to: net_address.Endpoint, memory_bytes: u64 = DEFAULT_MEMORY)
        -> Result[Tcp, Failure] {
        startup :: slop_os.startup_block()
        made :: match make_memory(memory_bytes) {
            case Ok(found) => found
            case Error(failure) => return .Error(failure)
        }
        tcp := made
        handle :: match give_memory(tcp.memory) {
            case Some(found) => found
            case None => {
                unmake(&tcp)
                return .Error(.NoRoom)
            }
        }
        port :: match os.port_for(startup.budget, service.end) {
            case Some(found) => found
            case None => {
                unmake(&tcp)
                return .Error(.NoRoom)
            }
        }
        defer slop_os.handle_close(cast[slop_os.Handle](port))
        out := os.Outgoing.{}
        request :: os.begin[network.Request](&out)
        request^ = .Open(network.OpenTo.{to = to, memory = handle})
        if network.send_request(service.end, port, &out) is_some {
            unmake(&tcp)
            return .Error(.Broken)
        }
        into := os.Incoming.{}
        match network.receive_response(service.end, port, &into, true) {
            case Received => {}
            case _ => {
                unmake(&tcp)
                return .Error(.Broken)
            }
        }
        match os.message_of[network.Response](&into)^ {
            case Opened(stream) => tcp.stream = stream
            case Refused(refusal) => {
                unmake(&tcp)
                return .Error(failure_of(refusal))
            }
            case _ => {
                unmake(&tcp)
                return .Error(.Broken)
            }
        }
        return started(tcp)
    }

    /**
     * Open a TCP connection to a host by name, and wait until it's open or has failed. The service resolves the name and
     * tries its addresses, IPv6 first, as RFC 8305's Happy Eyeballs does, each as the connection's policy allows a name
     * to reach (network.allows_named).
     *
     * @param service A connection to the network service, the caller's.
     * @param name The host's name: any case, a final dot or not, at most network.MAX_NAME bytes.
     * @param port Its port, 1 to 65535.
     * @param memory_bytes The memory for its rings: at least two pages, rounded up to a whole number of them.
     * @return The connection, open; or why it couldn't be: NotAllowed if the policy allows none of the name's addresses,
     *     the resolver's failure, or the last address's.
     */
    open_name :: fn(service: os.Channel[network.Network], name: string, port: u16, memory_bytes: u64 = DEFAULT_MEMORY)
        -> Result[Tcp, Failure] {
        startup :: slop_os.startup_block()
        made :: match make_memory(memory_bytes) {
            case Ok(found) => found
            case Error(failure) => return .Error(failure)
        }
        tcp := made
        handle :: match give_memory(tcp.memory) {
            case Some(found) => found
            case None => {
                unmake(&tcp)
                return .Error(.NoRoom)
            }
        }
        asking :: match os.port_for(startup.budget, service.end) {
            case Some(found) => found
            case None => {
                unmake(&tcp)
                return .Error(.NoRoom)
            }
        }
        defer slop_os.handle_close(cast[slop_os.Handle](asking))
        out := os.Outgoing.{}
        request :: os.begin[network.Request](&out)
        text :: os.append(&out, string_bytes(name))
        request^ = .OpenName(network.OpenNamed.{name = text, port = port, memory = handle})
        if network.send_request(service.end, asking, &out) is_some {
            unmake(&tcp)
            return .Error(.Broken)
        }
        into := os.Incoming.{}
        match network.receive_response(service.end, asking, &into, true) {
            case Received => {}
            case _ => {
                unmake(&tcp)
                return .Error(.Broken)
            }
        }
        match os.message_of[network.Response](&into)^ {
            case Opened(stream) => tcp.stream = stream
            case Refused(refusal) => {
                unmake(&tcp)
                return .Error(failure_of(refusal))
            }
            case _ => {
                unmake(&tcp)
                return .Error(.Broken)
            }
        }
        return started(tcp)
    }

    /**
     * Give a name's addresses, and wait for them.
     *
     * @param service A connection to the network service, the caller's, whose policy allows connecting somewhere.
     * @param name The name: any case, a final dot or not, at most network.MAX_NAME bytes.
     * @param kinds Which addresses: IPv4's, IPv6's, or both.
     * @return Its addresses, at least one; or why there are none: NotAllowed if the policy allows connecting nowhere,
     *     NoSuchName, NoAddress, ResolveFailed, BadName, or Broken if the service couldn't be asked.
     */
    resolve :: fn(service: os.Channel[network.Network], name: string, kinds: network.Kinds = .Both) -> Result[Addresses, Failure] {
        startup :: slop_os.startup_block()
        asking :: os.port_for(startup.budget, service.end) or_return .Error(.NoRoom)
        defer slop_os.handle_close(cast[slop_os.Handle](asking))
        out := os.Outgoing.{}
        request :: os.begin[network.Request](&out)
        text :: os.append(&out, string_bytes(name))
        request^ = .Resolve(network.ResolveName.{name = text, kinds = kinds})
        if network.send_request(service.end, asking, &out) is_some {
            return .Error(.Broken)
        }
        into := os.Incoming.{}
        match network.receive_response(service.end, asking, &into, true) {
            case Received => {}
            case _ => return .Error(.Broken)
        }
        return match os.message_of[network.Response](&into)^ {
            case Resolved(found) => {
                got := Addresses.{}
                for address in os.items(&into, found) {
                    if got.count < got.addresses.count {
                        got.addresses[got.count] = network.address_of(address)
                        got.count += 1
                    }
                }
                if got.count == 0 { Result[Addresses, Failure].Error(.NoAddress) } else { Result[Addresses, Failure].Ok(got) }
            }
            case Refused(refusal) => .Error(failure_of(refusal))
            case _ => .Error(.Broken)
        }
    }

    /**
     * Give a connection made its own port, and wait for it to open.
     *
     * @param tcp The connection, its channel had.
     * @return It, open; or why it isn't, closed.
     */
    started :: fn(tcp: Tcp) -> Result[Tcp, Failure] {
        made := tcp
        match os.port_for(slop_os.startup_block().budget, made.stream.end) {
            case Some(found) => made.port = found
            case None => {
                close(&made)
                return .Error(.NoRoom)
            }
        }
        loop {
            if made.progress.connected {
                return .Ok(made)
            }
            if made.progress.ending != .None {
                why :: failure_of_ending(made.progress.ending)
                close(&made)
                return .Error(why)
            }
            if !wait(&made) {
                close(&made)
                return .Error(.Broken)
            }
        }
        while true
        return .Error(.Broken)
    }

    /**
     * Write bytes: as many as there's room for at a time, waiting for more room, until they're all written.
     *
     * @param tcp The connection, not finished.
     * @param bytes What's written.
     * @return How many were written: all of them, or fewer if the connection ended first, or was finished.
     */
    write :: fn(tcp: ptr[mut Tcp], bytes: u8[]) -> usize {
        if tcp.finished {
            return 0
        }
        done := cast[usize](0)
        loop {
            if done >= bytes.count {
                break
            }
            room :: tcp.ring - (tcp.written - tcp.progress.acknowledged)
            if room == 0 {
                if tcp.progress.ending != .None || !wait(tcp) {
                    break
                }
                continue
            }
            count :: if cast[u64](bytes.count - done) < room { bytes.count - done } else { cast[usize](room) }
            ring :: view_of(cast[ptr[mut u8]](tcp.at), cast[usize](tcp.ring))
            for i in 0..<count {
                at :: cast[usize]((tcp.written + cast[u64](i)) % tcp.ring)
                if at < ring.count && done + i < bytes.count {
                    ring[at] = bytes[done + i]
                }
            }
            tcp.written += cast[u64](count)
            done += count
            tell(tcp, .Wrote(tcp.written))
        }
        while true
        return done
    }

    /**
     * Read bytes: what's arrived, waiting for some if none has.
     *
     * @param tcp The connection.
     * @param into Where they go.
     * @return How many: at least 1, unless the peer has finished and everything's read, which gives 0; Error with why
     *     the connection ended, if it did before finishing.
     */
    read :: fn(tcp: ptr[mut Tcp], into: mut u8[]) -> Result[usize, Failure] {
        loop {
            waiting :: tcp.progress.delivered - tcp.read
            if waiting > 0 {
                count :: if cast[u64](into.count) < waiting { into.count } else { cast[usize](waiting) }
                ring :: view_of(cast[ptr[u8]](tcp.at + tcp.ring), cast[usize](tcp.ring))
                for &byte, i in into {
                    if i >= count {
                        break
                    }
                    at :: cast[usize]((tcp.read + cast[u64](i)) % tcp.ring)
                    if at < ring.count {
                        byte^ = ring[at]
                    }
                }
                tcp.read += cast[u64](count)
                tell(tcp, .Read(tcp.read))
                return .Ok(count)
            }
            if tcp.progress.peer_finished || tcp.progress.ending == .Closed {
                return .Ok(0)
            }
            if tcp.progress.ending != .None {
                return .Error(failure_of_ending(tcp.progress.ending))
            }
            if !wait(tcp) {
                return .Error(.Broken)
            }
        }
        while true
        return .Ok(0)
    }

    /**
     * Finish writing: the peer's told there's no more, once it has every byte written.
     *
     * @param tcp The connection.
     */
    finish :: fn(tcp: ptr[mut Tcp]) {
        if !tcp.finished {
            tcp.finished = true
            tell(tcp, .Finish)
        }
    }

    /**
     * Wait until every byte written is acknowledged, or the connection has ended.
     *
     * @param tcp The connection.
     * @return True if they all were.
     */
    flush :: fn(tcp: ptr[mut Tcp]) -> bool {
        loop {
            if tcp.progress.acknowledged >= tcp.written {
                return true
            }
            if tcp.progress.ending != .None || !wait(tcp) {
                return false
            }
        }
        while true
        return false
    }

    /**
     * Close a connection: its channel, which resets it if it hasn't ended, its memory, and its port.
     *
     * @param tcp The connection, not used again.
     */
    close :: fn(tcp: ptr[mut Tcp]) {
        _ = slop_os.handle_close(cast[slop_os.Handle](tcp.stream.end))
        if cast[slop_os.Handle](tcp.port) != slop_os.NO_HANDLE {
            _ = slop_os.handle_close(cast[slop_os.Handle](tcp.port))
        }
        unmake(tcp)
    }

    /**
     * Listen on a TCP port.
     *
     * @param service A connection to the network service, the caller's.
     * @param port The port, 1 to 65535.
     * @return The listener; or why not.
     */
    listen :: fn(service: os.Channel[network.Network], port: u16) -> Result[Listener, Failure] {
        startup :: slop_os.startup_block()
        waiting :: os.port_for(startup.budget, service.end) or_return .Error(.NoRoom)
        defer slop_os.handle_close(cast[slop_os.Handle](waiting))
        out := os.Outgoing.{}
        request :: os.begin[network.Request](&out)
        request^ = .Listen(port)
        if network.send_request(service.end, waiting, &out) is_some {
            return .Error(.Broken)
        }
        into := os.Incoming.{}
        match network.receive_response(service.end, waiting, &into, true) {
            case Received => {}
            case _ => return .Error(.Broken)
        }
        match os.message_of[network.Response](&into)^ {
            case Listening(channel) => {
                match os.port_for(startup.budget, channel.end) {
                    case Some(found) => return .Ok(Listener.{channel = channel, port = found})
                    case None => {
                        _ = slop_os.handle_close(cast[slop_os.Handle](channel.end))
                        return .Error(.NoRoom)
                    }
                }
            }
            case Refused(refusal) => return .Error(failure_of(refusal))
            case _ => return .Error(.Broken)
        }
    }

    /**
     * Take the next connection to a listener, waiting for one.
     *
     * @param listener The listener.
     * @param memory_bytes The memory for its rings: at least two pages, rounded up to a whole number of them.
     * @return The connection, open, and who it's from; or why not.
     */
    accept :: fn(listener: ptr[mut Listener], memory_bytes: u64 = DEFAULT_MEMORY) -> Result[Accepted, Failure] {
        made :: match make_memory(memory_bytes) {
            case Ok(found) => found
            case Error(failure) => return .Error(failure)
        }
        tcp := made
        handle :: match give_memory(tcp.memory) {
            case Some(found) => found
            case None => {
                unmake(&tcp)
                return .Error(.NoRoom)
            }
        }
        out := os.Outgoing.{}
        request :: os.begin[tcp_listener.Request](&out)
        request^ = .Accept(handle)
        if tcp_listener.send_request(listener.channel.end, listener.port, &out) is_some {
            unmake(&tcp)
            return .Error(.Broken)
        }
        into := os.Incoming.{}
        match tcp_listener.receive_response(listener.channel.end, listener.port, &into, true) {
            case Received => {}
            case _ => {
                unmake(&tcp)
                return .Error(.Broken)
            }
        }
        remote := net_address.Endpoint.{}
        match os.message_of[tcp_listener.Response](&into)^ {
            case Accepted(accepted) => {
                tcp.stream = accepted.stream
                remote = accepted.remote
            }
            case _ => {
                unmake(&tcp)
                return .Error(.NoRoom)
            }
        }
        return match started(tcp) {
            case Ok(opened) => .Ok(Accepted.{tcp = opened, remote = remote})
            case Error(failure) => .Error(failure)
        }
    }

    /** A connection accepted, and who it's from. */
    Accepted :: struct {
        tcp : Tcp,
        remote : net_address.Endpoint,
    }

    /**
     * Stop listening.
     *
     * @param listener The listener, not used again.
     */
    close_listener :: fn(listener: ptr[mut Listener]) {
        _ = slop_os.handle_close(cast[slop_os.Handle](listener.channel.end))
        _ = slop_os.handle_close(cast[slop_os.Handle](listener.port))
    }

    /**
     * Open a UDP socket.
     *
     * @param service A connection to the network service, the caller's.
     * @param port The port, or 0 for an ephemeral one.
     * @return The socket; or why not.
     */
    udp :: fn(service: os.Channel[network.Network], port: u16 = 0) -> Result[Udp, Failure] {
        startup :: slop_os.startup_block()
        waiting :: os.port_for(startup.budget, service.end) or_return .Error(.NoRoom)
        defer slop_os.handle_close(cast[slop_os.Handle](waiting))
        out := os.Outgoing.{}
        request :: os.begin[network.Request](&out)
        request^ = .Udp(port)
        if network.send_request(service.end, waiting, &out) is_some {
            return .Error(.Broken)
        }
        into := os.Incoming.{}
        match network.receive_response(service.end, waiting, &into, true) {
            case Received => {}
            case _ => return .Error(.Broken)
        }
        match os.message_of[network.Response](&into)^ {
            case Bound(channel) => {
                match os.port_for(startup.budget, channel.end) {
                    case Some(found) => return .Ok(Udp.{channel = channel, port = found})
                    case None => {
                        _ = slop_os.handle_close(cast[slop_os.Handle](channel.end))
                        return .Error(.NoRoom)
                    }
                }
            }
            case Refused(refusal) => return .Error(failure_of(refusal))
            case _ => return .Error(.Broken)
        }
    }

    /**
     * Send a datagram; one that can't go is dropped, as one lost would be.
     *
     * @param socket The socket.
     * @param to Who to.
     * @param bytes Its payload, at most datagrams.MAX_DATAGRAM bytes; more is cut off.
     * @return True once it's sent to the service; false if the socket's connection failed.
     */
    send_to :: fn(socket: ptr[mut Udp], to: net_address.Endpoint, bytes: u8[]) -> bool {
        out := os.Outgoing.{}
        request :: os.begin[datagrams.Request](&out)
        count :: if bytes.count < datagrams.MAX_DATAGRAM { bytes.count } else { cast[usize](datagrams.MAX_DATAGRAM) }
        request^ = .Send(datagrams.SendTo.{to = to, bytes = os.append(&out, bytes[0..<count])})
        return datagrams.send_request(socket.channel.end, socket.port, &out) is_none
    }

    /** A datagram received: who from, and how many of its bytes were taken. */
    Got :: struct {
        from : net_address.Endpoint,
        count : usize,
    }

    /**
     * Receive a datagram, waiting for one.
     *
     * @param socket The socket.
     * @param into Where its payload goes; what doesn't fit is dropped.
     * @return Who sent it, and how many bytes were put in into; null if the socket's connection failed.
     */
    receive_from :: fn(socket: ptr[mut Udp], into: mut u8[]) -> Got? {
        out := os.Outgoing.{}
        request :: os.begin[datagrams.Request](&out)
        request^ = .Receive
        if datagrams.send_request(socket.channel.end, socket.port, &out) is_some {
            return null
        }
        incoming := os.Incoming.{}
        match datagrams.receive_response(socket.channel.end, socket.port, &incoming, true) {
            case Received => {}
            case _ => return null
        }
        match os.message_of[datagrams.Response](&incoming)^ {
            case Datagram(arrived) => {
                bytes :: os.items(&incoming, arrived.bytes)
                count :: if bytes.count < into.count { bytes.count } else { into.count }
                for i in 0..<count {
                    if i < into.count && i < bytes.count {
                        into[i] = bytes[i]
                    }
                }
                return Got.{from = arrived.from, count = count}
            }
            case _ => return null
        }
    }

    /**
     * Close a UDP socket.
     *
     * @param socket The socket, not used again.
     */
    close_udp :: fn(socket: ptr[mut Udp]) {
        _ = slop_os.handle_close(cast[slop_os.Handle](socket.channel.end))
        _ = slop_os.handle_close(cast[slop_os.Handle](socket.port))
    }

    // ---- Within

    /**
     * Make a connection's memory, and map it.
     *
     * @param bytes How much, at least two pages, rounded up to a whole number of them.
     * @return A Tcp with only its memory, mapping and rings set; Error if the memory couldn't be made or mapped.
     */
    make_memory :: fn(bytes: u64) -> Result[Tcp, Failure] {
        startup :: slop_os.startup_block()
        size := (bytes + PAGE - 1) / PAGE * PAGE
        if size < 2 * PAGE {
            size = 2 * PAGE
        }
        // Rings of whole pages
        if (size / PAGE) % 2 != 0 {
            size += PAGE
        }
        memory :: slop_os.memory_create(startup.budget, size) or_return .Error(.NoRoom)
        at :: match runtime.reserve_addresses(cast[usize](size)) {
            case Some(found) => found
            case None => {
                _ = slop_os.handle_close(cast[slop_os.Handle](memory))
                return .Error(.NoRoom)
            }
        }
        read_write :: cast[slop_os.Protection](cast[u32](slop_os.PROTECTION_READ) | cast[u32](slop_os.PROTECTION_WRITE))
        if slop_os.memory_map(memory, startup.space, at, 0, size, read_write) is_error {
            _ = slop_os.handle_close(cast[slop_os.Handle](memory))
            return .Error(.NoRoom)
        }
        return .Ok(Tcp.{memory = memory, at = at, ring = size / 2, port = cast[slop_os.Port](slop_os.NO_HANDLE)})
    }

    /**
     * Give a duplicate of a connection's memory, to move to the service.
     *
     * @param memory The memory.
     * @return The duplicate, read-write and movable; null if it couldn't be made.
     */
    give_memory :: fn(memory: slop_os.Memory) -> slop_os.Memory? {
        rights :: cast[slop_os.Rights](cast[u32](slop_os.RIGHT_MEMORY_READ) | cast[u32](slop_os.RIGHT_MEMORY_WRITE)
            | cast[u32](slop_os.RIGHT_TRANSFER))
        copy :: slop_os.handle_duplicate(cast[slop_os.Handle](memory), rights) or_return null
        return cast[slop_os.Memory](copy)
    }

    /**
     * Give back a connection's memory: unmapped and closed.
     *
     * @param tcp The connection.
     */
    unmake :: fn(tcp: ptr[mut Tcp]) {
        if tcp.at != 0 {
            _ = slop_os.memory_unmap(slop_os.startup_block().space, tcp.at)
            tcp.at = 0
        }
        if cast[slop_os.Handle](tcp.memory) != slop_os.NO_HANDLE {
            _ = slop_os.handle_close(cast[slop_os.Handle](tcp.memory))
            tcp.memory = cast[slop_os.Memory](slop_os.NO_HANDLE)
        }
    }

    /**
     * Tell the service something that isn't answered.
     *
     * @param tcp The connection.
     * @param request Wrote, Read, Finish or Abort.
     */
    tell :: fn(tcp: ptr[mut Tcp], request: tcp_stream.Request) {
        out := os.Outgoing.{}
        made :: os.begin[tcp_stream.Request](&out)
        made^ = request
        _ = tcp_stream.send_request(tcp.stream.end, tcp.port, &out)
    }

    /**
     * Say where a connection runs: its local and remote endpoints, and its rings' size. Any progress the service says
     * meanwhile is taken, as wait takes it.
     *
     * @param tcp The connection.
     * @return What the service says of it; null if the channel failed.
     */
    describe :: fn(tcp: ptr[mut Tcp]) -> tcp_stream.StreamInfo? {
        tell(tcp, .Describe)
        loop {
            into := os.Incoming.{}
            match tcp_stream.receive_response(tcp.stream.end, tcp.port, &into, true) {
                case Received => {}
                case _ => return null
            }
            match os.message_of[tcp_stream.Response](&into)^ {
                case Described(info) => return info
                case Progress(progress) => {
                    tcp.progress = progress
                    tcp.watching = false
                }
                case _ => {}
            }
        }
    }

    /**
     * Wait for the connection's progress to change.
     *
     * @param tcp The connection, whose progress is updated.
     * @return True once it has; false if the channel failed.
     */
    wait :: fn(tcp: ptr[mut Tcp]) -> bool {
        if !tcp.watching {
            out := os.Outgoing.{}
            made :: os.begin[tcp_stream.Request](&out)
            made^ = .Watch(tcp.progress)
            if tcp_stream.send_request(tcp.stream.end, tcp.port, &out) is_some {
                return false
            }
            tcp.watching = true
        }
        into := os.Incoming.{}
        match tcp_stream.receive_response(tcp.stream.end, tcp.port, &into, true) {
            case Received => {}
            case _ => return false
        }
        match os.message_of[tcp_stream.Response](&into)^ {
            case Progress(progress) => {
                tcp.progress = progress
                tcp.watching = false
                return true
            }
            case _ => return true
        }
    }

    /**
     * Give the failure a refusal means.
     *
     * @param refusal The refusal.
     * @return The failure.
     */
    failure_of :: fn(refusal: network.Refusal) -> Failure {
        return match refusal {
            case .NotAllowed => .NotAllowed
            case .PortTaken => .PortTaken
            case .NoRoute => .NoRoute
            case .NoRoom => .NoRoom
            case .BadMemory => .NoRoom
            case .BadEndpoint => .BadEndpoint
            case .NoSuchName => .NoSuchName
            case .NoAddress => .NoAddress
            case .ResolveFailed => .ResolveFailed
            case .BadName => .BadName
        }
    }

    /**
     * Give the failure an ending means.
     *
     * @param ending How the connection ended, not Closed or None.
     * @return The failure.
     */
    failure_of_ending :: fn(ending: tcp_stream.Ending) -> Failure {
        return match ending {
            case .Refused => .Refused
            case .TimedOut => .TimedOut
            case .Reset => .Reset
            case _ => .Broken
        }
    }
}

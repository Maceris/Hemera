package net

/*
 * Time from an NTS server (std/ntp, RFC 8915), on SlopOS only: nts_establish runs NTS Key Establishment over TLS to a
 * server by name, its certificate checked against trust anchors, which gives a session its keys and cookies; nts_query
 * then asks the NTP server it named, over UDP, with a cookie, and gives the offset and delay of an authenticated
 * answer.
 *
 *     session := ntp.Session.{}
 *     _ = net.nts_establish(network, "time.example", net.anchor_bytes(anchors), &session)
 *     sample :: net.nts_query(network, "time.example", &session, 2_000_000_000)?
 *     // sample.offset: how far the server's clock is ahead of this one's
 */

#if base.OS == .SlopOS {
    import runtime from "base"
    import ntp from "std"
    import os from "std"
    import time from "std"
    import tls from "std"
    import slop_os from "std/os"
    import net_address from "std/os/slop_os"
    import network from "std/os/slop_os"

    /** How long NTS-KE may take, connecting to its server's last record, before it's given up: 10 s. */
    NTS_KE_TIMEOUT : u64 : 10_000_000_000

    /** Why NTS gave no time. */
    NtsFailure :: enum {
        /** NTS-KE's TLS connection failed or was refused: tls says why. */
        Tls,
        /** The server didn't agree on ALPN's "ntske/1". */
        NotNtsKe,
        /** NTS-KE's response ended early, or wasn't one, or refused, or didn't agree: ke says how, error its Error code. */
        KeyEstablishment,
        /** The keys couldn't be exported. */
        Keys,
        /** The NTP server's name didn't resolve, or a socket couldn't be had: network says why. */
        Network,
        /** The session has no cookie left: NTS-KE again. */
        NoCookie,
        /** Nothing answered in time, or nothing that answered the request. */
        NoAnswer,
        /** An answer came that wasn't authenticated: forged or damaged, and refused. */
        Forged,
        /** The server can't read the cookies: NTS-KE again. */
        Nak,
        /** The answer was authenticated, but its time can't be used. */
        Unusable,
    }

    /** NTS's failure, with what more there is to say. */
    NtsProblem :: struct {
        why : NtsFailure,
        /** With Tls, TLS's failure. */
        tls : TlsFailure,
        /** With KeyEstablishment, how reading the response ended, and an Error record's code. */
        ke : ntp.KeOutcome,
        error : u16,
        /** With Network, the failure. */
        network : Failure,
    }

    /** NTS-KE's response's buffer. */
    KeBuffer :: struct {
        bytes : u8[16384],
    }

    /**
     * Run NTS Key Establishment with a server: TLS to its port, 4460 unless said, by name, its certificate checked against the anchors,
     * offering "ntske/1"; NTPv4 and AES-SIV-CMAC-256 asked for; and the session given the keys and cookies it answers.
     *
     * @param service A connection to the network service whose policy allows TCP to the server's port 4460.
     * @param host The NTS-KE server's name.
     * @param anchors The trust anchors, DER certificates one after another.
     * @param session The session, set afresh: keyed, with cookies, on success; not keyed otherwise.
     * @param port The NTS-KE server's port: ntp.NTS_KE_PORT, 4460, the default.
     * @return Null on success; why not otherwise.
     */
    nts_establish :: fn(service: os.Channel[network.Network], host: string, anchors: u8[], session: ptr[mut ntp.Session],
        port: u16 = ntp.NTS_KE_PORT) -> NtsProblem? {

        session.keyed = false
        session.cookie_count = 0
        // A server that stops answering ends it, rather than hold the caller, as the clock, for ever (13h)
        deadline :: (slop_os.clock_monotonic() or_else 0) + NTS_KE_TIMEOUT
        stream := match connect_tls(service, host, port, anchors, ntp.ALPN, deadline) {
            case Ok(found) => found
            case Error(failure) => return NtsProblem.{why = .Tls, tls = failure}
        }
        defer close_tls(&stream)
        if !tls.protocol_agreed(state(&stream)) {
            return NtsProblem.{why = .NotNtsKe}
        }
        request : u8[32]
        count :: ntp.ke_request(request[0..<request.count])
        if write_tls(&stream, tls.range(request, 0, count)) != count {
            return NtsProblem.{why = .KeyEstablishment, ke = .Incomplete}
        }
        buffer :: runtime.new(KeBuffer)
        defer runtime.free(buffer)
        got := cast[usize](0)
        reading := ntp.KeReading.{outcome = .Incomplete}
        loop {
            reading = ntp.read_ke_response(tls.range(buffer.bytes, 0, got), session)
            if reading.outcome != .Incomplete || got >= buffer.bytes.count {
                break
            }
            more :: read_tls(&stream, tls.range_mut(buffer.bytes, got, buffer.bytes.count)) or_else 0
            if more == 0 {
                break
            }
            got += more
        }
        while true
        if reading.outcome != .Done {
            return NtsProblem.{why = .KeyEstablishment, ke = reading.outcome, error = reading.error}
        }
        if !ntp.take_keys(session, state(&stream)) {
            return NtsProblem.{why = .Keys}
        }
        return null
    }

    /**
     * Ask a session's NTP server the time, once, with a cookie: its answer taken only if it's authenticated.
     *
     * @param service A connection to the network service whose policy allows UDP to the NTP server.
     * @param host The NTS-KE server's name: the NTP server's, unless NTS-KE named another.
     * @param session The session, keyed: it spends a cookie, and keeps those the answer brings.
     * @param timeout How long to wait for the answer, in nanoseconds.
     * @return The offset and delay; or why there are none.
     */
    nts_query :: fn(service: os.Channel[network.Network], host: string, session: ptr[mut ntp.Session], timeout: u64)
        -> Result[ntp.Sample, NtsProblem] {

        server :: if session.server_length > 0 { string_of(&session.server[0], session.server_length) } else { host }
        to := net_address.Endpoint.{port = session.port}
        match net_address.parse_v4(server) {
            case Some(address) => to.address = address
            case None => match resolve(service, server) {
                case Ok(found) => {
                    if found.count == 0 {
                        return .Error(NtsProblem.{why = .Network, network = .NoAddress})
                    }
                    to.address = found.addresses[0]
                }
                case Error(failure) => return .Error(NtsProblem.{why = .Network, network = failure})
            }
        }
        socket := match udp(service) {
            case Ok(found) => found
            case Error(failure) => return .Error(NtsProblem.{why = .Network, network = failure})
        }
        defer close_udp(&socket)
        packet : u8[ntp.REQUEST_BYTES]
        pending := ntp.Pending.{}
        count :: ntp.make_request(session, packet[0..<packet.count], &pending)
        if count == 0 {
            return .Error(NtsProblem.{why = .NoCookie})
        }
        sent :: now_nanoseconds()
        if !send_to(&socket, to, tls.range(packet, 0, count)) {
            return .Error(NtsProblem.{why = .Network, network = .Broken})
        }
        deadline :: (slop_os.clock_monotonic() or_else 0) + timeout
        // A forged answer, or an unauthenticated NAK, doesn't end the wait, as anyone can send one ahead of the server's
        forged := false
        nak := false
        answer : u8[2048]
        loop {
            got := receive_from(&socket, answer[0..<answer.count], deadline) or_break
            arrived :: now_nanoseconds()
            read :: ntp.read_response(session, &pending, tls.range(answer, 0, got.count))
            match read.outcome {
                case .Good => return .Ok(ntp.sample_of(sent, &read.reply, arrived))
                case .Unusable => return .Error(NtsProblem.{why = .Unusable})
                case .NotAnswer => {}
                case .Forged => forged = true
                case .Nak => nak = true
            }
        }
        while true
        return .Error(NtsProblem.{why = if nak { NtsFailure.Nak } else if forged { NtsFailure.Forged } else { NtsFailure.NoAnswer }})
    }

    /** The wall clock's time, in nanoseconds since 1970 UTC; 0 if it can't be read. */
    now_nanoseconds :: fn() -> i64 {
        now :: time.now() or_else runtime.Instant.{}
        return now.seconds * 1_000_000_000 + cast[i64](now.nanos)
    }
}

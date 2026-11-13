package net

/*
 * TLS 1.3 over a TCP connection (std/tls, decisions/0188, 13f), on SlopOS only: connect_tls connects to a host by name
 * and checks its certificate against trust anchors and its name, as part of connecting; connect_tls_unverified
 * doesn't. accept_tls serves one over a listener's connection. The anchors come from a trust store, a read-only
 * directory of roots the program's given (load_anchors); there's no global one.
 *
 *     anchors :: net.load_anchors(trust) or_return 2
 *     stream := net.connect_tls(network, "example.com", 443, net.anchor_bytes(anchors))?
 *     _ = net.write_tls(&stream, string_bytes("GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"))
 *     count :: net.read_tls(&stream, buffer)?     // 0 once the server's closed
 *     net.close_tls(&stream)
 */

#if base.OS == .SlopOS {
    import runtime from "base"
    import crypto from "std"
    import os from "std"
    import time from "std"
    import tls from "std"
    import slop_os from "std/os"
    import net_address from "std/os/slop_os"
    import network from "std/os/slop_os"
    import files from "std/os/slop_os"
    import read_only_dir from "std/os/slop_os"

    /** The most anchors' bytes load_anchors keeps: 256 KiB, a public set of roots' size. */
    ANCHOR_BYTES :: 262144
    /** The bytes of a file in the trust store read at once: a PEM file of many roots fits. */
    TRUST_FILE_BYTES :: 262144

    /** Trust anchors: DER certificates one after another, the first count bytes. */
    Anchors :: struct {
        bytes : u8[ANCHOR_BYTES],
        count : usize,
    }

    /** Why a TLS connection wasn't made, or failed. */
    TlsFailure :: struct {
        /** The TCP connection's failure, if that's what failed; null if TLS did. */
        network : Failure?,
        /** How TLS ended: Refused by this side, or a PeerAlert. */
        ending : tls.Ending,
        /** The alert sent or received. */
        alert : u8,
        /** For a certificate refused: why, and whether it was its name. */
        certificate : crypto.X509Verdict,
        wrong_name : bool,
    }

    /** A TLS connection over TCP, the caller's until close_tls. */
    TlsStream :: struct {
        tcp : Tcp,
        /** The TLS state's address, a tls.Connection on the heap, some 300 KiB. */
        connection : u64,
        /** The address of what arrived and TLS hasn't taken yet, a Buffered on the heap. */
        buffer : u64,
    }

    /** A stream's TLS state. */
    state :: fn(stream: ptr[TlsStream]) -> ptr[mut tls.Connection] {
        return cast[ptr[mut tls.Connection]](cast[uintptr](stream.connection))
    }

    /** What's arrived on a stream that TLS hasn't taken yet. */
    buffered_of :: fn(stream: ptr[TlsStream]) -> ptr[mut Buffered] {
        return cast[ptr[mut Buffered]](cast[uintptr](stream.buffer))
    }

    /** A new stream over a TCP connection, its TLS state and buffer made, zeroed. */
    stream_over :: fn(tcp: Tcp) -> TlsStream {
        return TlsStream.{tcp = tcp, connection = cast[u64](cast[uintptr](runtime.new(tls.Connection))),
            buffer = cast[u64](cast[uintptr](runtime.new(Buffered)))}
    }

    /** What arrived and TLS hasn't taken yet. */
    Buffered :: struct {
        bytes : u8[16384],
        start : usize,
        count : usize,
    }

    /**
     * Read a trust store: every file in a read-only directory, PEM (every CERTIFICATE in it) or DER, its certificates
     * gathered as anchors.
     *
     * @param trust The trust store, the caller's.
     * @return The anchors, on the heap, the caller's to free; null if the directory couldn't be listed, or nothing in it
     *     was a certificate. Past ANCHOR_BYTES, the rest are left out.
     */
    load_anchors :: fn(trust: os.Channel[read_only_dir.ReadOnlyDir]) -> ptr[mut Anchors]? {
        startup :: slop_os.startup_block()
        port :: os.port_for(startup.budget, trust.end) or_return null
        defer slop_os.handle_close(cast[slop_os.Handle](port))
        anchors :: runtime.new(Anchors)
        text :: runtime.new(TrustFile)
        defer runtime.free(text)
        cursor := cast[u64](0)
        loop {
            out := os.Outgoing.{}
            os.begin[read_only_dir.Request](&out)^ = .List(cursor)
            if read_only_dir.send_request(trust.end, port, &out) is_some {
                break
            }
            into := os.Incoming.{}
            match read_only_dir.receive_response(trust.end, port, &into, true) {
                case Received => {}
                case _ => break
            }
            listing := files.Listing.{}
            name_bytes : u8[256]
            name_length := cast[usize](0)
            match os.message_of[read_only_dir.Response](&into)^ {
                case Listed(found) => {
                    listing = found
                    for byte in os.items(&into, found.name) {
                        if name_length < name_bytes.count {
                            name_bytes[name_length] = byte
                            name_length += 1
                        }
                    }
                }
                case _ => break
            }
            cursor = listing.next
            if listing.kind != .File {
                continue
            }
            length :: read_trust_file(trust, port, tls.range(name_bytes, 0, name_length), text)
            add_certificates(anchors, tls.range(text.bytes, 0, length))
        }
        if anchors.count == 0 {
            runtime.free(anchors)
            return null
        }
        return anchors
    }

    /** A file of the trust store, read whole. */
    TrustFile :: struct {
        bytes : u8[TRUST_FILE_BYTES],
    }

    /**
     * Read a file of the trust store whole, as much as fits.
     *
     * @param trust The trust store.
     * @param port A port bound to it.
     * @param name The file's name.
     * @param into Where it goes.
     * @return How many bytes were read; 0 if it couldn't be opened.
     */
    read_trust_file :: fn(trust: os.Channel[read_only_dir.ReadOnlyDir], port: slop_os.Port, name: u8[], into: ptr[mut TrustFile]) -> usize {
        out := os.Outgoing.{}
        request :: os.begin[read_only_dir.Request](&out)
        request^ = .OpenReadOnlyFile(os.append(&out, name))
        if read_only_dir.send_request(trust.end, port, &out) is_some {
            return 0
        }
        answer := os.Incoming.{}
        match read_only_dir.receive_response(trust.end, port, &answer, true) {
            case Received => {}
            case _ => return 0
        }
        channel :: match os.message_of[read_only_dir.Response](&answer)^ {
            case OpenedReadOnlyFile(opened) => opened
            case _ => return 0
        }
        file, error :: os.file_on(channel.end, false)
        if error != null {
            return 0
        }
        defer os.close(file)
        total := cast[usize](0)
        loop {
            if total >= into.bytes.count {
                break
            }
            count :: os.read(file, tls.range_mut(into.bytes, total, into.bytes.count)) or_else 0
            if count == 0 {
                break
            }
            total += count
        }
        while true
        return total
    }

    /**
     * Add a file's certificates to anchors: every CERTIFICATE of a PEM file, or a DER certificate as it is.
     *
     * @param anchors The anchors, added to while there's room.
     * @param text The file.
     */
    add_certificates :: fn(anchors: ptr[mut Anchors], text: u8[]) {
        room :: tls.range_mut(anchors.bytes, anchors.count, anchors.bytes.count)
        match crypto.pem_certificates(text, room) {
            case Some(count) => {
                if count > 0 {
                    anchors.count += count
                    return void
                }
            }
            case None => {}
        }
        // DER: a SEQUENCE, kept whole if it's a certificate that can be read
        if text.count > 0 && text[0] == 0x30 && text.count <= room.count && (crypto.x509_parse(text) is_some) {
            for byte, i in text {
                room[i] = byte
            }
            anchors.count += text.count
        }
    }

    /**
     * Give anchors' bytes, as tls.client takes them.
     *
     * @param anchors The anchors.
     * @return Their DER, a view of anchors'.
     */
    anchor_bytes :: fn(anchors: ptr[Anchors]) -> u8[] {
        return tls.range(anchors.bytes, 0, anchors.count)
    }

    /**
     * Connect to a host by name over TLS, its certificate checked against the anchors and its name, and wait for the
     * handshake.
     *
     * @param service A connection to the network service, whose policy allows the host's addresses by name.
     * @param host The host's name, or an IPv4 address's text, which its certificate has to match.
     * @param port Its port.
     * @param anchors The trust anchors, DER certificates one after another, the caller's while the stream's open.
     * @param protocol The application protocol offered by ALPN, like "ntske/1"; empty, the default, for none.
     *     tls.protocol_agreed(state(&stream)) says whether the server took it.
     * @param deadline When waiting on the peer gives up, connecting and after, in the monotonic clock's nanoseconds; 0,
     *     the default, for never. A peer that stops answering then fails it as Broken (net.set_deadline).
     * @return The stream, connected; or why it isn't.
     */
    connect_tls :: fn(service: os.Channel[network.Network], host: string, port: u16, anchors: u8[], protocol: string = "",
        deadline: u64 = 0) -> Result[TlsStream, TlsFailure] {

        return connect_with(service, host, port, anchors, true, protocol, deadline)
    }

    /**
     * Connect to a host over TLS without checking its certificate chain or name: whoever holds the certificate's key is
     * talked to, whoever that is. For a peer known some other way.
     *
     * @param service A connection to the network service.
     * @param host The host's name, sent as SNI, or an IPv4 address's text.
     * @param port Its port.
     * @return The stream, connected; or why it isn't.
     */
    connect_tls_unverified :: fn(service: os.Channel[network.Network], host: string, port: u16) -> Result[TlsStream, TlsFailure] {
        return connect_with(service, host, port, string_bytes(""), false, "", 0)
    }

    /** connect_tls's and connect_tls_unverified's work. */
    connect_with :: fn(service: os.Channel[network.Network], host: string, port: u16, anchors: u8[], verify: bool,
        protocol: string, deadline: u64) -> Result[TlsStream, TlsFailure] {

        opened := match net_address.parse_v4(host) {
            case Some(address) => open(service, net_address.Endpoint.{address = address, port = port}, deadline = deadline)
            case None => open_name(service, host, port, deadline = deadline)
        }
        tcp := match opened {
            case Ok(found) => found
            case Error(failure) => return .Error(TlsFailure.{network = failure})
        }
        stream := stream_over(tcp)
        if verify {
            now :: time.now() or_else runtime.Instant.{}
            tls.client(state(&stream), host, anchors, now.seconds, protocol)
        }
        else {
            tls.client_unverified(state(&stream), host)
        }
        return handshake(&stream)
    }

    /**
     * Accept a connection on a listener, and serve TLS on it with an identity, waiting for the handshake.
     *
     * @param listener The listener.
     * @param identity The server's chain and key; its chain's bytes the caller's while the stream's open.
     * @return The stream, connected; or why it isn't.
     */
    accept_tls :: fn(listener: ptr[mut Listener], identity: ptr[tls.Identity]) -> Result[TlsStream, TlsFailure] {
        accepted := match accept(listener) {
            case Ok(found) => found
            case Error(failure) => return .Error(TlsFailure.{network = failure})
        }
        stream := stream_over(accepted.tcp)
        tls.server(state(&stream), identity)
        return handshake(&stream)
    }

    /**
     * Run a stream's handshake to its end.
     *
     * @param stream The stream, its TLS set up.
     * @return A copy of it, connected; or why not, the stream closed.
     */
    handshake :: fn(stream: ptr[mut TlsStream]) -> Result[TlsStream, TlsFailure] {
        loop {
            send_waiting(stream)
            if tls.connected(state(stream)) {
                return .Ok(stream^)
            }
            if tls.ended(state(stream)) || !take_more(stream) {
                why :: failure_of_tls(stream)
                close_tls(stream)
                return .Error(why)
            }
        }
    }

    /** Why a stream's TLS ended, as a TlsFailure. */
    failure_of_tls :: fn(stream: ptr[TlsStream]) -> TlsFailure {
        connection :: state(stream)
        if !tls.ended(connection) {
            return TlsFailure.{network = Failure.Broken}
        }
        return TlsFailure.{ending = connection.ending, alert = connection.alert, certificate = connection.certificate,
            wrong_name = connection.wrong_name}
    }

    /** Send what TLS has for the peer. */
    send_waiting :: fn(stream: ptr[mut TlsStream]) {
        loop {
            out :: tls.output(state(stream))
            if out.count == 0 {
                return void
            }
            written :: write(&stream.tcp, out)
            tls.sent(state(stream), written)
            if written == 0 {
                return void
            }
        }
    }

    /**
     * Give TLS what's arrived, waiting for some if nothing's buffered.
     *
     * @param stream The stream.
     * @return False if the peer finished or the connection failed before anything more arrived.
     */
    take_more :: fn(stream: ptr[mut TlsStream]) -> bool {
        buffered :: buffered_of(stream)
        if buffered.count == 0 {
            buffered.start = 0
            count :: read(&stream.tcp, buffered.bytes[0..<buffered.bytes.count]) or_else 0
            if count == 0 {
                return false
            }
            buffered.count = count
        }
        end :: buffered.start + buffered.count
        if end > buffered.bytes.count {
            return false
        }
        taken :: tls.received(state(stream), tls.range(buffered.bytes, buffered.start, end))
        buffered.start += taken
        buffered.count -= taken
        return true
    }

    /**
     * Write data over TLS, sent as it's sealed.
     *
     * @param stream The stream.
     * @param data What's written.
     * @return How many bytes were written: all, or fewer if the connection's ended.
     */
    write_tls :: fn(stream: ptr[mut TlsStream], data: u8[]) -> usize {
        done := cast[usize](0)
        loop {
            if done >= data.count || !tls.connected(state(stream)) {
                break
            }
            taken :: tls.write(state(stream), tls.range(data, done, data.count))
            done += taken
            send_waiting(stream)
            if taken == 0 && tls.output(state(stream)).count > 0 {
                break
            }
        }
        while true
        return done
    }

    /**
     * Read data that's arrived over TLS, waiting for some.
     *
     * @param stream The stream.
     * @param into Where it goes.
     * @return How many bytes, at least 1; 0 once the peer's closed with close_notify and everything's read; or why the
     *     connection failed.
     */
    read_tls :: fn(stream: ptr[mut TlsStream], into: mut u8[]) -> Result[usize, TlsFailure] {
        loop {
            count :: tls.read(state(stream), into)
            // KeyUpdate's answer, or an alert, may wait to go
            send_waiting(stream)
            if count > 0 {
                return .Ok(count)
            }
            if tls.ended(state(stream)) {
                if state(stream).ending == .Closed || state(stream).ending == .LocalClose {
                    return .Ok(0)
                }
                return .Error(failure_of_tls(stream))
            }
            if !take_more(stream) {
                return .Error(TlsFailure.{network = Failure.Broken})
            }
        }
    }

    /**
     * Close a stream: close_notify sent, the TCP connection finished, waited on until the peer's acknowledged everything
     * or it's ended, and closed; and its state freed. Closing a connection that hasn't ended resets it, which could lose
     * the close_notify, so it waits.
     *
     * @param stream The stream, not used after.
     */
    close_tls :: fn(stream: ptr[mut TlsStream]) {
        tls.close(state(stream))
        send_waiting(stream)
        finish(&stream.tcp)
        _ = flush(&stream.tcp)
        close(&stream.tcp)
        tls.forget(state(stream))
        runtime.free(state(stream))
        runtime.free(buffered_of(stream))
    }
}

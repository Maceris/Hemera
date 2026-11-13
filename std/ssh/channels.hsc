package ssh

import compiler from "base"

/*
 * The connection protocol (RFC 4254): session channels, each with its window both ways. What arrives on a channel
 * waits in its buffer, CHANNEL_BUFFER bytes, which is the window the peer's given; reading it gives the window back,
 * once half's been read. What's written goes out as the peer's window and largest packet allow. A server opens only
 * "session" channels, and refuses global requests and anything else; a client opens sessions and asks for a terminal,
 * a shell, a command or a subsystem on them. Extended data, standard error, arrives with the rest.
 */

/** Take a message of the connection protocol's. */
handle_connection :: fn(conn: ptr[mut Connection], message: u8[]) {
    kind :: byte_at(message, 0)
    reader := Reader.{at = 1, end = message.count}
    if kind == MSG_GLOBAL_REQUEST {
        _ = get_string(message, &reader)
        if get_bool(message, &reader) {
            send_byte_message(conn, MSG_REQUEST_FAILURE)
        }
        return void
    }
    if kind == MSG_REQUEST_SUCCESS || kind == MSG_REQUEST_FAILURE {
        return void
    }
    if kind == MSG_CHANNEL_OPEN {
        take_open(conn, message)
        return void
    }
    index :: cast[usize](get_u32(message, &reader))
    if reader.bad || index >= CHANNELS || conn.channels[index].state == .Free {
        fail(conn, DISCONNECT_PROTOCOL_ERROR, "a message for a channel that isn't open")
        return void
    }
    channel :: &conn.channels[index]
    if kind == MSG_CHANNEL_OPEN_CONFIRMATION && conn.role == .Client && channel.state == .Opening {
        channel.remote = get_u32(message, &reader)
        channel.remote_window = cast[u64](get_u32(message, &reader))
        channel.remote_packet = get_u32(message, &reader)
        channel.state = .Open
        event(conn, .ChannelOpened(cast[u32](index)))
        return void
    }
    if kind == MSG_CHANNEL_OPEN_FAILURE && conn.role == .Client && channel.state == .Opening {
        channel^ = Channel.{}
        event(conn, .ChannelRefused(cast[u32](index)))
        return void
    }
    if channel.state != .Open {
        fail(conn, DISCONNECT_PROTOCOL_ERROR, "a message for a channel not yet open")
        return void
    }
    if kind == MSG_CHANNEL_WINDOW_ADJUST {
        channel.remote_window += cast[u64](get_u32(message, &reader))
        return void
    }
    if kind == MSG_CHANNEL_DATA || kind == MSG_CHANNEL_EXTENDED_DATA {
        if kind == MSG_CHANNEL_EXTENDED_DATA {
            _ = get_u32(message, &reader)
        }
        data :: get_string(message, &reader)
        take_data(conn, index, data)
        return void
    }
    if kind == MSG_CHANNEL_EOF {
        channel.eof_received = true
        event(conn, .ChannelEof(cast[u32](index)))
        return void
    }
    if kind == MSG_CHANNEL_CLOSE {
        channel.close_received = true
        if !channel.close_sent {
            channel_close(conn, cast[u32](index))
        }
        free_if_closed(conn, index)
        return void
    }
    if kind == MSG_CHANNEL_REQUEST {
        take_channel_request(conn, index, message, reader)
        return void
    }
    if (kind == MSG_CHANNEL_SUCCESS || kind == MSG_CHANNEL_FAILURE) && conn.role == .Client && channel.awaited > 0 {
        channel.awaited -= 1
        event(conn, .RequestAnswered(Answered.{channel = cast[u32](index), ok = kind == MSG_CHANNEL_SUCCESS}))
        return void
    }
    fail(conn, DISCONNECT_PROTOCOL_ERROR, "a channel message out of place")
}

/** Send a message of its number alone. */
send_byte_message :: fn(conn: ptr[mut Connection], kind: u8) {
    writer := Writer.{}
    put_u8(conn.message[0..<PAYLOAD_BYTES], &writer, kind)
    send_message(conn, range(conn.message[0..<PAYLOAD_BYTES], 0, writer.at))
}

/** Send a message of its number and a channel's peer's number for it. */
send_channel_message :: fn(conn: ptr[mut Connection], kind: u8, remote: u32) {
    writer := Writer.{}
    put_u8(conn.message[0..<PAYLOAD_BYTES], &writer, kind)
    put_u32(conn.message[0..<PAYLOAD_BYTES], &writer, remote)
    send_message(conn, range(conn.message[0..<PAYLOAD_BYTES], 0, writer.at))
}

/** A server's: take a CHANNEL_OPEN, a session's opened if there's room; anything else refused. */
take_open :: fn(conn: ptr[mut Connection], message: u8[]) {
    reader := Reader.{at = 1, end = message.count}
    kind :: get_string(message, &reader)
    sender :: get_u32(message, &reader)
    window :: get_u32(message, &reader)
    packet :: get_u32(message, &reader)
    reason := cast[u32](0)
    index := cast[usize](CHANNELS)
    if conn.role != .Server || !is(kind, "session") {
        // SSH_OPEN_ADMINISTRATIVELY_PROHIBITED: no forwarding, no channels a client didn't ask for
        reason = 1
    }
    else {
        for each, i in conn.channels {
            if index == CHANNELS && each.state == .Free {
                index = i
            }
        }
        // SSH_OPEN_RESOURCE_SHORTAGE
        if index >= CHANNELS {
            reason = 4
        }
    }
    writer := Writer.{}
    data :: conn.message[0..<PAYLOAD_BYTES]
    if reason != 0 || reader.bad || index >= conn.channels.count {
        put_u8(data, &writer, MSG_CHANNEL_OPEN_FAILURE)
        put_u32(data, &writer, sender)
        put_u32(data, &writer, if reason == 0 { cast[u32](2) } else { reason })
        put_text(data, &writer, "refused")
        put_text(data, &writer, "")
        send_message(conn, range(data, 0, writer.at))
        return void
    }
    conn.channels[index] = Channel.{state = .Open, remote = sender, remote_window = cast[u64](window),
        remote_packet = if packet < CHANNEL_PACKET { packet } else { cast[u32](CHANNEL_PACKET) }}
    put_u8(data, &writer, MSG_CHANNEL_OPEN_CONFIRMATION)
    put_u32(data, &writer, sender)
    put_u32(data, &writer, cast[u32](index))
    put_u32(data, &writer, CHANNEL_BUFFER)
    put_u32(data, &writer, CHANNEL_PACKET)
    send_message(conn, range(data, 0, writer.at))
    event(conn, .ChannelOpened(cast[u32](index)))
}

/** Take a channel's data into its buffer: more than its window ends the connection. */
take_data :: fn(conn: ptr[mut Connection], index: usize, data: u8[]) {
    if index >= conn.channels.count {
        return void
    }
    channel :: &conn.channels[index]
    if channel.eof_received || data.count > CHANNEL_BUFFER - channel.count {
        fail(conn, DISCONNECT_PROTOCOL_ERROR, "data past a channel's window")
        return void
    }
    for byte in data {
        at :: (channel.first + channel.count) % CHANNEL_BUFFER
        channel.buffer[at] = byte
        channel.count += 1
    }
    if data.count > 0 && !channel.announced {
        channel.announced = true
        event(conn, .ChannelData(cast[u32](index)))
    }
}

/** Take a CHANNEL_REQUEST. */
take_channel_request :: fn(conn: ptr[mut Connection], index: usize, message: u8[], from: Reader) {
    reader := from
    name :: get_string(message, &reader)
    want_reply :: get_bool(message, &reader)
    if index >= conn.channels.count {
        return void
    }
    remote :: conn.channels[index].remote
    if conn.role == .Client {
        // exit-status, or exit-signal, as 128 and a common number for it
        if is(name, "exit-status") {
            status :: get_u32(message, &reader)
            event(conn, .ExitStatus(Exited.{channel = cast[u32](index), status = status}))
        }
        else if is(name, "exit-signal") {
            signal :: get_string(message, &reader)
            event(conn, .ExitStatus(Exited.{channel = cast[u32](index), status = 128 + signal_number(signal)}))
        }
        else if want_reply {
            send_channel_message(conn, MSG_CHANNEL_FAILURE, remote)
        }
        return void
    }
    request := ChannelRequest.{channel = cast[u32](index), want_reply = want_reply}
    if is(name, "pty-req") {
        request.kind = .Pty
        keep_text(&request, get_string(message, &reader))
        request.columns = get_u32(message, &reader)
        request.rows = get_u32(message, &reader)
    }
    else if is(name, "shell") {
        request.kind = .Shell
    }
    else if is(name, "exec") {
        request.kind = .Exec
        keep_text(&request, get_string(message, &reader))
    }
    else if is(name, "subsystem") {
        request.kind = .Subsystem
        keep_text(&request, get_string(message, &reader))
    }
    else if is(name, "window-change") {
        request.kind = .WindowChange
        request.columns = get_u32(message, &reader)
        request.rows = get_u32(message, &reader)
    }
    else if is(name, "signal") {
        request.kind = .Signal
        keep_text(&request, get_string(message, &reader))
    }
    if reader.bad || request.kind == .None {
        // env, and anything else, refused
        if want_reply {
            send_channel_message(conn, MSG_CHANNEL_FAILURE, remote)
        }
        return void
    }
    conn.request = request
    if request.kind == .WindowChange || request.kind == .Signal {
        if want_reply {
            send_channel_message(conn, MSG_CHANNEL_SUCCESS, remote)
        }
        event(conn, if request.kind == .WindowChange { Event.WindowChanged(cast[u32](index)) } else { Event.Signal(cast[u32](index)) })
        return void
    }
    conn.waiting = .Request
    event(conn, .ChannelRequest(cast[u32](index)))
}

/** Keep a request's text, as much as fits. */
keep_text :: fn(request: ptr[mut ChannelRequest], text: u8[]) {
    request.text_length = 0
    for byte, i in text {
        if i < request.text.count {
            request.text[i] = byte
            request.text_length = i + 1
        }
    }
}

/** A request's text: its terminal type, command, subsystem or signal. */
request_text :: fn(request: ptr[ChannelRequest]) -> u8[] {
    return range(request.text[0..<REQUEST_TEXT_BYTES], 0, request.text_length)
}

/** A signal's common number, by its name as SSH sends it (RFC 4254, 6.10); 0 for one not known. */
signal_number :: fn(name: u8[]) -> u32 {
    names :: string.["HUP", "INT", "QUIT", "ILL", "ABRT", "FPE", "KILL", "USR1", "SEGV", "USR2", "PIPE", "ALRM", "TERM"]
    numbers :: u32.[1, 2, 3, 4, 6, 8, 9, 10, 11, 12, 13, 14, 15]
    for each, i in names {
        if is(name, each) && i < numbers.count {
            return numbers[i]
        }
    }
    return 0
}

/**
 * A server's answer to ChannelRequest: replied to if the client wanted one.
 *
 * @param conn The connection, its ChannelRequest event taken.
 * @param ok Whether it's done: a terminal given, a shell or command started, a subsystem run.
 */
answer_request :: fn(conn: ptr[mut Connection], ok: bool) {
    if conn.waiting != .Request {
        return void
    }
    conn.waiting = .Nothing
    index :: cast[usize](conn.request.channel)
    if conn.request.want_reply && index < conn.channels.count && conn.channels[index].state == .Open {
        send_channel_message(conn, if ok { MSG_CHANNEL_SUCCESS } else { MSG_CHANNEL_FAILURE }, conn.channels[index].remote)
    }
    process(conn)
}

// ---- Channels, the caller's side

/**
 * A client's: open a session channel.
 *
 * @param conn The connection, authenticated.
 * @return The channel's number, ChannelOpened or ChannelRefused coming for it; null if there's no room.
 */
open_session :: fn(conn: ptr[mut Connection]) -> u32? {
    if conn.role != .Client || !conn.authenticated {
        return null
    }
    for &each, i in conn.channels {
        if each.state == .Free {
            each^ = Channel.{state = .Opening}
            writer := Writer.{}
            data :: conn.message[0..<PAYLOAD_BYTES]
            put_u8(data, &writer, MSG_CHANNEL_OPEN)
            put_text(data, &writer, "session")
            put_u32(data, &writer, cast[u32](i))
            put_u32(data, &writer, CHANNEL_BUFFER)
            put_u32(data, &writer, CHANNEL_PACKET)
            send_message(conn, range(data, 0, writer.at))
            return cast[u32](i)
        }
    }
    return null
}

/** The channel at a number, if it's open. */
open_channel :: fn(conn: ptr[mut Connection], number: u32) -> ptr[mut Channel]? {
    index :: cast[usize](number)
    if index >= conn.channels.count || conn.channels[index].state != .Open {
        return null
    }
    return &conn.channels[index]
}

/**
 * A client's: ask for something on a session channel, its answer as RequestAnswered.
 *
 * @param conn The connection.
 * @param number The channel.
 * @param kind Pty (text the terminal's type, with columns and rows), Shell, Exec (text the command), Subsystem
 *     (text its name), or WindowChange (columns and rows; no answer comes).
 * @param text The text it has, or empty.
 * @param columns The terminal's width, for Pty and WindowChange.
 * @param rows Its height.
 * @return True once it's sent.
 */
channel_request :: fn(conn: ptr[mut Connection], number: u32, kind: RequestKind, text: string, columns: u32 = 80, rows: u32 = 24) -> bool {
    channel :: open_channel(conn, number) or_return false
    writer := Writer.{}
    data :: conn.message[0..<PAYLOAD_BYTES]
    put_u8(data, &writer, MSG_CHANNEL_REQUEST)
    put_u32(data, &writer, channel.remote)
    want_reply :: kind != .WindowChange
    match kind {
        case .Pty => {
            put_text(data, &writer, "pty-req")
            put_bool(data, &writer, true)
            put_text(data, &writer, text)
            put_u32(data, &writer, columns)
            put_u32(data, &writer, rows)
            put_u32(data, &writer, 0)
            put_u32(data, &writer, 0)
            put_text(data, &writer, "")
        }
        case .Shell => {
            put_text(data, &writer, "shell")
            put_bool(data, &writer, true)
        }
        case .Exec => {
            put_text(data, &writer, "exec")
            put_bool(data, &writer, true)
            put_text(data, &writer, text)
        }
        case .Subsystem => {
            put_text(data, &writer, "subsystem")
            put_bool(data, &writer, true)
            put_text(data, &writer, text)
        }
        case .WindowChange => {
            put_text(data, &writer, "window-change")
            put_bool(data, &writer, false)
            put_u32(data, &writer, columns)
            put_u32(data, &writer, rows)
            put_u32(data, &writer, 0)
            put_u32(data, &writer, 0)
        }
        case _ => return false
    }
    if want_reply {
        channel.awaited += 1
    }
    send_message(conn, range(data, 0, writer.at))
    return true
}

/**
 * A server's: say how a channel's command ended, before closing it.
 *
 * @param conn The connection.
 * @param number The channel.
 * @param status The exit status.
 */
channel_exit_status :: fn(conn: ptr[mut Connection], number: u32, status: u32) {
    channel :: open_channel(conn, number) or_return void
    writer := Writer.{}
    data :: conn.message[0..<PAYLOAD_BYTES]
    put_u8(data, &writer, MSG_CHANNEL_REQUEST)
    put_u32(data, &writer, channel.remote)
    put_text(data, &writer, "exit-status")
    put_bool(data, &writer, false)
    put_u32(data, &writer, status)
    send_message(conn, range(data, 0, writer.at))
}

/**
 * Write to a channel, as much as the peer's window, its largest packet and the output's room allow.
 *
 * @param conn The connection.
 * @param number The channel.
 * @param bytes What's written.
 * @param errors Whether it's standard error, as a server's extended data.
 * @return How many were written; fewer than given while the window's short, and 0 while keys are exchanged, after EOF,
 *     or for a channel that isn't open.
 */
channel_write :: fn(conn: ptr[mut Connection], number: u32, bytes: u8[], errors: bool = false) -> usize {
    channel :: open_channel(conn, number) or_return 0
    if channel.eof_sent || channel.close_sent || exchanging(conn) || conn.ended {
        return 0
    }
    written := cast[usize](0)
    loop {
        room :: conn.outgoing.count - conn.outgoing_count
        most := cast[u64](bytes.count - written)
        if most > channel.remote_window {
            most = channel.remote_window
        }
        if most > cast[u64](channel.remote_packet) {
            most = cast[u64](channel.remote_packet)
        }
        // A packet's overhead, at most: header, padding, tag
        if room < 128 {
            break
        }
        if most > cast[u64](room - 128) {
            most = cast[u64](room - 128)
        }
        if most == 0 {
            break
        }
        count :: cast[usize](most)
        writer := Writer.{}
        data :: conn.message[0..<PAYLOAD_BYTES]
        put_u8(data, &writer, if errors { MSG_CHANNEL_EXTENDED_DATA } else { MSG_CHANNEL_DATA })
        put_u32(data, &writer, channel.remote)
        if errors {
            put_u32(data, &writer, 1)
        }
        put_string(data, &writer, range(bytes, written, written + count))
        send_message(conn, range(data, 0, writer.at))
        channel.remote_window -= most
        written += count
    }
    while written < bytes.count
    return written
}

/**
 * Read what's arrived on a channel, giving the window back once half the buffer's been read.
 *
 * @param conn The connection.
 * @param number The channel.
 * @param into Where it goes.
 * @return How many bytes; 0 if none are waiting.
 */
channel_read :: fn(conn: ptr[mut Connection], number: u32, into: mut u8[]) -> usize {
    channel :: open_channel(conn, number) or_return 0
    count := cast[usize](0)
    loop {
        into[count] = channel.buffer[channel.first % CHANNEL_BUFFER]
        channel.first = (channel.first + 1) % CHANNEL_BUFFER
        channel.count -= 1
        count += 1
    }
    while count < into.count && channel.count > 0
    channel.consumed += cast[u64](count)
    if channel.count == 0 {
        channel.announced = false
    }
    if channel.consumed >= CHANNEL_BUFFER / 2 && !channel.eof_received {
        writer := Writer.{}
        data :: conn.message[0..<PAYLOAD_BYTES]
        put_u8(data, &writer, MSG_CHANNEL_WINDOW_ADJUST)
        put_u32(data, &writer, channel.remote)
        put_u32(data, &writer, cast[u32](channel.consumed))
        send_message(conn, range(data, 0, writer.at))
        channel.consumed = 0
    }
    // Room again: what's arrived may be read now; a channel closed both ways is freed once it's all read
    process(conn)
    free_if_closed(conn, cast[usize](number))
    return count
}

/** How many bytes wait to be read on a channel. */
channel_waiting :: fn(conn: ptr[mut Connection], number: u32) -> usize {
    channel :: open_channel(conn, number) or_return 0
    return channel.count
}

/** Say this side will write nothing more on a channel. */
channel_eof :: fn(conn: ptr[mut Connection], number: u32) {
    channel :: open_channel(conn, number) or_return void
    if channel.eof_sent || channel.close_sent {
        return void
    }
    channel.eof_sent = true
    send_channel_message(conn, MSG_CHANNEL_EOF, channel.remote)
}

/** Close a channel: once the peer has too, and what arrived on it is read, ChannelClosed says so and its number's free. */
channel_close :: fn(conn: ptr[mut Connection], number: u32) {
    channel :: open_channel(conn, number) or_return void
    if channel.close_sent {
        return void
    }
    channel.close_sent = true
    send_channel_message(conn, MSG_CHANNEL_CLOSE, channel.remote)
    free_if_closed(conn, cast[usize](number))
}

/** Free a channel closed both ways, once what arrived on it is read. */
free_if_closed :: fn(conn: ptr[mut Connection], index: usize) {
    if index >= conn.channels.count {
        return void
    }
    if conn.channels[index].state == .Open && conn.channels[index].close_sent && conn.channels[index].close_received
        && conn.channels[index].count == 0 {
        conn.channels[index] = Channel.{}
        event(conn, .ChannelClosed(cast[u32](index)))
    }
}

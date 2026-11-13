package ssh

import compiler from "base"
import crypto from "std"
import random from "std"

/*
 * An SSH connection, either side's. Its caller makes it with client or server, then:
 *
 *     taken :: ssh.received(conn, bytes)     // what arrived
 *     send_bytes(ssh.output(conn))           // what to send
 *     ssh.sent(conn, count)
 *     loop { event :: ssh.take_event(conn) or_break; ... }
 *
 * Some events wait for an answer, and nothing more of what's arrived is read until it comes: a client's HostKey
 * (trust_host_key), a server's Password and PublicKey (answer_authentication), and a server's ChannelRequest
 * (answer_request). Channels' data is read with channel_read and written with channel_write.
 *
 * The transport is RFC 4253's, with OpenSSH's strict key exchange, which a peer that offers it is held to: in the first
 * exchange only its messages are taken, and sequence numbers start again at each NEWKEYS, which closes off Terrapin's
 * prefix truncation. A key exchange starts again after REKEY_BYTES either way, or when the peer starts one, or rekey
 * is called; messages written meanwhile are held until it's done.
 */

/** This side's version, as sent. */
VERSION :: "SSH-2.0-SlopOS_1.0"
/** The longest packet taken, by its length field. */
MAX_PACKET :: 65536
/** Room for what's arrived and not yet read. */
INCOMING_BYTES :: 70000
/** Room for what's to be sent. */
OUTGOING_BYTES :: 200000
/** Room for a packet's payload, as read or built. */
PAYLOAD_BYTES :: 66000
/** The longest KEXINIT kept, for the exchange hash. */
KEXINIT_BYTES :: 8192
/** Room for messages held while keys are exchanged. */
HELD_BYTES :: 70000
/** How many channels a connection has open at once. */
CHANNELS :: 4
/** Each channel's buffer for what arrives, and the window it gives the peer. */
CHANNEL_BUFFER :: 65536
/** The largest data packet a channel takes, or sends. */
CHANNEL_PACKET :: 32768
/** The longest user name taken. */
USER_BYTES :: 64
/** The longest password taken. */
PASSWORD_BYTES :: 256
/** The longest command, subsystem or signal name, or terminal type, a channel request has. */
REQUEST_TEXT_BYTES :: 1024
/** The longest banner kept. */
BANNER_BYTES :: 1024
/** How many authentication requests a server takes, past which it disconnects. */
MAX_AUTH_TRIES :: 6
/** How many bytes either way before keys are exchanged again: 1 GiB. */
REKEY_BYTES : u64 : 1 << 30
/** How many events wait at once. */
EVENTS :: 64

// Messages (RFC 4250, 4.1)
MSG_DISCONNECT : u8 : 1
MSG_IGNORE : u8 : 2
MSG_UNIMPLEMENTED : u8 : 3
MSG_DEBUG : u8 : 4
MSG_SERVICE_REQUEST : u8 : 5
MSG_SERVICE_ACCEPT : u8 : 6
MSG_EXT_INFO : u8 : 7
MSG_KEXINIT : u8 : 20
MSG_NEWKEYS : u8 : 21
MSG_KEX_INIT : u8 : 30
MSG_KEX_REPLY : u8 : 31
MSG_USERAUTH_REQUEST : u8 : 50
MSG_USERAUTH_FAILURE : u8 : 51
MSG_USERAUTH_SUCCESS : u8 : 52
MSG_USERAUTH_BANNER : u8 : 53
MSG_USERAUTH_PK_OK : u8 : 60
MSG_GLOBAL_REQUEST : u8 : 80
MSG_REQUEST_SUCCESS : u8 : 81
MSG_REQUEST_FAILURE : u8 : 82
MSG_CHANNEL_OPEN : u8 : 90
MSG_CHANNEL_OPEN_CONFIRMATION : u8 : 91
MSG_CHANNEL_OPEN_FAILURE : u8 : 92
MSG_CHANNEL_WINDOW_ADJUST : u8 : 93
MSG_CHANNEL_DATA : u8 : 94
MSG_CHANNEL_EXTENDED_DATA : u8 : 95
MSG_CHANNEL_EOF : u8 : 96
MSG_CHANNEL_CLOSE : u8 : 97
MSG_CHANNEL_REQUEST : u8 : 98
MSG_CHANNEL_SUCCESS : u8 : 99
MSG_CHANNEL_FAILURE : u8 : 100

// Disconnect reasons (RFC 4250, 4.2.2)
DISCONNECT_PROTOCOL_ERROR : u32 : 2
DISCONNECT_KEY_EXCHANGE_FAILED : u32 : 3
DISCONNECT_MAC_ERROR : u32 : 5
DISCONNECT_SERVICE_NOT_AVAILABLE : u32 : 7
DISCONNECT_HOST_KEY_NOT_VERIFIABLE : u32 : 9
DISCONNECT_BY_APPLICATION : u32 : 11
DISCONNECT_NO_MORE_AUTH_METHODS : u32 : 14

/** Which side a connection is. */
Role :: enum {
    Client,
    Server,
}

/** The key exchange chosen. */
KeyExchange :: enum {
    None,
    /** mlkem768x25519-sha256: ML-KEM-768 and X25519, K a string of SHA-256 of both secrets. */
    Hybrid,
    /** curve25519-sha256 (RFC 8731): K an mpint of X25519's secret. */
    Curve,
}

/** A direction's cipher. */
Cipher :: enum {
    None,
    Chacha,
    Gcm,
}

/** One direction's keys and count. */
Direction :: struct {
    cipher : Cipher,
    chacha : crypto.SshChachaKeys,
    gcm_key : crypto.Key256,
    /** aes256-gcm's nonce: 4 fixed bytes, then 8 counting packets (RFC 5647, 7.1). */
    gcm_nonce : crypto.Nonce96,
    sequence : u32,
    /** Bytes through these keys, for rekeying. */
    bytes : u64,
}

/** What the connection waits on its caller for, reading nothing more meanwhile. */
Waiting :: enum {
    Nothing,
    Trust,
    Authentication,
    Request,
}

/** Where a channel is. */
ChannelState :: enum {
    Free,
    /** A client's, asked for, not yet confirmed. */
    Opening,
    Open,
}

/** A channel. */
Channel :: struct {
    state : ChannelState,
    /** The peer's number for it, its window, and its largest packet. */
    remote : u32,
    remote_window : u64,
    remote_packet : u32,
    /** What arrived, not yet read: a ring. */
    buffer : u8[CHANNEL_BUFFER],
    first : usize,
    count : usize,
    /** Bytes read since a window adjustment last gave them back. */
    consumed : u64,
    eof_received : bool,
    eof_sent : bool,
    close_received : bool,
    close_sent : bool,
    /** Whether ChannelData's been said for what's in the buffer. */
    announced : bool,
    /** A client's requests with their answers still to come. */
    awaited : u32,
}

/** What kind a channel request is. */
RequestKind :: enum {
    None,
    Pty,
    Shell,
    Exec,
    Subsystem,
    WindowChange,
    Signal,
}

/** A channel request, a server's to answer, or a window change or signal to take. */
ChannelRequest :: struct {
    kind : RequestKind,
    channel : u32,
    want_reply : bool,
    /** pty-req's and window-change's size, in characters. */
    columns : u32,
    rows : u32,
    /** pty-req's terminal type, exec's command, subsystem's name, signal's name; text_length bytes of it. */
    text : u8[REQUEST_TEXT_BYTES],
    text_length : usize,
}

/** A client's request answered. */
Answered :: struct {
    channel : u32,
    ok : bool,
}

/** A command's ending, as the server said it. */
Exited :: struct {
    channel : u32,
    /** Its exit status; for a signal, 128 plus a common number for it, as shells give. */
    status : u32,
}

/** What's happened, for the caller. */
Event :: union {
    /** A client's: the server's host key, its signature checked, host_key says; trust_host_key answers. */
    HostKey,
    /** A client's: a password's wanted, the server allowing one; give_password answers, or close. */
    PasswordWanted,
    /** A client's: authenticated; channels can be opened. */
    Authenticated,
    /** A client's: every method this side has was refused. */
    AuthenticationRefused,
    /** A client's: the server's banner, banner says. */
    Banner,
    /** A server's: a password for offered_user, offered_password; answer_authentication answers. */
    Password,
    /** A server's: offered_key for offered_user, its signature checked if true; answer_authentication answers. */
    PublicKey(bool),
    /** A channel's open. */
    ChannelOpened(u32),
    /** A client's channel was refused. */
    ChannelRefused(u32),
    /** A server's: a channel request, request says; answer_request answers. */
    ChannelRequest(u32),
    /** A client's request answered. */
    RequestAnswered(Answered),
    /** A server's: a channel's terminal resized, request says. */
    WindowChanged(u32),
    /** A server's: a signal for a channel's process, request says. */
    Signal(u32),
    /** Data's arrived on a channel, for channel_read. */
    ChannelData(u32),
    /** The peer's sent all it will on a channel. */
    ChannelEof(u32),
    /** A channel's closed, both ways; its number's free. */
    ChannelClosed(u32),
    /** A client's: the command on a channel ended. */
    ExitStatus(Exited),
    /** The connection's ended, ended_reason says why. */
    Ended,
}

/** A connection: some 600 KiB, so on the heap. */
Connection :: struct {
    role : Role,
    /** A server's: the one exchange, or cipher, it offers, for tests; None for all. */
    only_kex : KeyExchange,
    only_cipher : Cipher,
    ended : bool,
    /** Why it ended: a disconnect reason, the peer's or this side's. */
    ended_reason : u32,
    waiting : Waiting,

    incoming : u8[INCOMING_BYTES],
    incoming_count : usize,
    outgoing : u8[OUTGOING_BYTES],
    outgoing_count : usize,
    /** A packet's payload as read, declassified, wiped once it's taken. */
    payload : u8[PAYLOAD_BYTES],
    /** A message being built. */
    message : u8[PAYLOAD_BYTES],
    /** A packet being sealed. */
    sealing : crypto.SecretByte[PAYLOAD_BYTES],
    /** Messages held while keys are exchanged, each its length then itself. */
    held : u8[HELD_BYTES],
    held_count : usize,

    // The version exchange
    version_received : bool,
    peer_version : u8[256],
    peer_version_length : usize,

    // Key exchange
    our_kexinit : u8[KEXINIT_BYTES],
    our_kexinit_length : usize,
    their_kexinit : u8[KEXINIT_BYTES],
    their_kexinit_length : usize,
    kex_sent : bool,
    kex_received : bool,
    exchange_sent : bool,
    newkeys_sent : bool,
    newkeys_received : bool,
    first_done : bool,
    strict : bool,
    peer_wants_ext_info : bool,
    skip_guess : bool,
    exchange : KeyExchange,
    cipher_out : Cipher,
    cipher_in : Cipher,
    x25519 : crypto.X25519SecretKey,
    ml_kem : crypto.MlKem768SecretKey,
    /** The client's C_INIT or Q_C, and the server's S_REPLY or Q_S, as the exchange hash has them. */
    client_share : u8[1216],
    client_share_length : usize,
    server_share : u8[1120],
    server_share_length : usize,
    /** K as the exchange hash and key derivation have it: an mpint or a string. */
    shared : crypto.SecretByte[40],
    shared_length : usize,
    exchange_hash : u8[32],
    session_id : u8[32],
    out : Direction,
    into : Direction,
    next_out : Direction,
    next_in : Direction,

    // Host keys
    host_secret : crypto.Ed25519SecretKey,
    host_key : PublicKey,

    // Authentication
    authenticated : bool,
    service_accepted : bool,
    user : u8[USER_BYTES],
    user_length : usize,
    client_key : crypto.Ed25519SecretKey,
    has_client_key : bool,
    key_tried : bool,
    password_tried : bool,
    auth_tries : u32,
    offered_password : crypto.SecretByte[PASSWORD_BYTES],
    offered_password_length : usize,
    offered_key : PublicKey,
    offered_signed : bool,
    /** A server's: the algorithm name offered with the key, for PK_OK. */
    offered_algorithm : u8[32],
    offered_algorithm_length : usize,
    pending_password : bool,
    banner : u8[BANNER_BYTES],
    banner_length : usize,

    // The connection protocol
    channels : Channel[CHANNELS],
    request : ChannelRequest,

    events : Event[EVENTS],
    events_first : usize,
    events_count : usize,
}

// ---- Setting up

/**
 * Set a connection up as a server, and queue its version and KEXINIT.
 *
 * @param conn The connection, zeroed, as runtime.new gives it.
 * @param host_key The server's Ed25519 host key, copied.
 * @param only_kex The one key exchange to offer, for tests; None, the default, for all.
 * @param only_cipher The one cipher to offer, for tests; None, the default, for all.
 */
server #constant_time :: fn(conn: ptr[mut Connection], host_key: ptr[crypto.Ed25519SecretKey], only_kex: KeyExchange = .None,
    only_cipher: Cipher = .None) {

    conn.role = .Server
    conn.only_kex = only_kex
    conn.only_cipher = only_cipher
    conn.host_secret = host_key^
    public :: crypto.ed25519_public_key(host_key)
    blob :: ed25519_blob(&public)
    conn.host_key = parse_public_key(blob[0..<ED25519_BLOB_BYTES]) or_else PublicKey.{}
    start(conn)
}

/**
 * Set a connection up as a client, and queue its version and KEXINIT.
 *
 * @param conn The connection, zeroed.
 * @param user The user to log in as, at most USER_BYTES.
 * @param key The user's Ed25519 key, tried first, or null for none; copied.
 */
client #constant_time :: fn(conn: ptr[mut Connection], user: string, key: ptr[crypto.Ed25519SecretKey]?) {
    conn.role = .Client
    bytes :: string_bytes(user)
    for byte, i in bytes {
        if i < conn.user.count {
            conn.user[i] = byte
        }
    }
    conn.user_length = if bytes.count < USER_BYTES { bytes.count } else { cast[usize](USER_BYTES) }
    match key {
        case Some(given) => {
            conn.client_key = given^
            conn.has_client_key = true
        }
        case None => {}
    }
    start(conn)
}

/** Queue the version line and KEXINIT. */
start :: fn(conn: ptr[mut Connection]) {
    line :: string_bytes(VERSION)
    for byte in line {
        push_out(conn, byte)
    }
    push_out(conn, 0x0d)
    push_out(conn, 0x0a)
    send_kexinit(conn)
}

/** Put a byte on the output as it is, before any packet. */
push_out :: fn(conn: ptr[mut Connection], byte: u8) {
    if conn.outgoing_count < conn.outgoing.count {
        conn.outgoing[conn.outgoing_count] = byte
        conn.outgoing_count += 1
    }
}

// ---- The caller's side

/**
 * Take bytes that arrived, and read what can be read of them: packets taken, events made.
 *
 * @param conn The connection.
 * @param bytes What arrived.
 * @return How many were taken: all of them, unless there's no room, which reading events and channels makes.
 */
received :: fn(conn: ptr[mut Connection], bytes: u8[]) -> usize {
    room :: conn.incoming.count - conn.incoming_count
    count :: if bytes.count < room { bytes.count } else { room }
    for i in cast[usize](0)..<count {
        if conn.incoming_count < conn.incoming.count && i < bytes.count {
            conn.incoming[conn.incoming_count] = bytes[i]
            conn.incoming_count += 1
        }
    }
    process(conn)
    return count
}

/** What's waiting to be sent. */
output :: fn(conn: ptr[Connection]) -> u8[] {
    return range(conn.outgoing[0..<OUTGOING_BYTES], 0, conn.outgoing_count)
}

/** Say how many of output's bytes were sent, which are dropped from it. */
sent :: fn(conn: ptr[mut Connection], count: usize) {
    conn.outgoing_count = drop_front(conn.outgoing[0..<OUTGOING_BYTES], conn.outgoing_count, count)
}

/** Take the next event; null if there's none. Reading may go on once an answer's given. */
take_event :: fn(conn: ptr[mut Connection]) -> Event? {
    if conn.events_count == 0 {
        return null
    }
    at :: conn.events_first % EVENTS
    conn.events_first = (conn.events_first + 1) % EVENTS
    conn.events_count -= 1
    return if at < conn.events.count { conn.events[at] } else { null }
}

/** Queue an event; one past EVENTS ends the connection, as the caller's stopped taking them. */
event :: fn(conn: ptr[mut Connection], happened: Event) {
    if conn.events_count >= EVENTS {
        conn.ended = true
        conn.ended_reason = DISCONNECT_BY_APPLICATION
        return void
    }
    at :: (conn.events_first + conn.events_count) % EVENTS
    if at < conn.events.count {
        conn.events[at] = happened
        conn.events_count += 1
    }
}

/** Whether the connection's ended. */
is_ended :: fn(conn: ptr[Connection]) -> bool {
    return conn.ended
}

/** The user: a client's own, or, on a server, the one authenticated or being. */
user_of :: fn(conn: ptr[Connection]) -> u8[] {
    return range(conn.user[0..<USER_BYTES], 0, conn.user_length)
}

/** A client's: the server's host key, once HostKey's said. */
host_key_of :: fn(conn: ptr[Connection]) -> ptr[PublicKey] {
    return &conn.host_key
}

/** A server's: the password offered, while Password waits for its answer. */
offered_password_of #constant_time :: fn(conn: ptr[Connection]) -> crypto.SecretByte[] {
    return range(conn.offered_password[0..<PASSWORD_BYTES], 0, conn.offered_password_length)
}

/** A server's: the key offered, while PublicKey waits for its answer. */
offered_key_of :: fn(conn: ptr[Connection]) -> ptr[PublicKey] {
    return &conn.offered_key
}

/** A server's: the channel request, while ChannelRequest waits, or after WindowChanged or Signal. */
request_of :: fn(conn: ptr[Connection]) -> ptr[ChannelRequest] {
    return &conn.request
}

/** A client's: the server's banner, once Banner's said. */
banner_of :: fn(conn: ptr[Connection]) -> u8[] {
    return range(conn.banner[0..<BANNER_BYTES], 0, conn.banner_length)
}

/** The session's identifier, the first exchange hash, once keys are exchanged. */
session_id_of :: fn(conn: ptr[Connection]) -> u8[] {
    return conn.session_id[0..<32]
}

/**
 * End the connection: a DISCONNECT sent, with a reason and a description.
 *
 * @param conn The connection.
 * @param reason A disconnect reason, DISCONNECT_BY_APPLICATION usually.
 * @param text The description.
 */
disconnect :: fn(conn: ptr[mut Connection], reason: u32, text: string) {
    if conn.ended {
        return void
    }
    writer := Writer.{}
    put_u8(conn.message[0..<PAYLOAD_BYTES], &writer, MSG_DISCONNECT)
    put_u32(conn.message[0..<PAYLOAD_BYTES], &writer, reason)
    put_text(conn.message[0..<PAYLOAD_BYTES], &writer, text)
    put_text(conn.message[0..<PAYLOAD_BYTES], &writer, "")
    send_packet(conn, range(conn.message[0..<PAYLOAD_BYTES], 0, writer.at))
    conn.ended = true
    conn.ended_reason = reason
    event(conn, .Ended)
}

/** End the connection for a protocol error: a reason, and nothing more read. */
fail :: fn(conn: ptr[mut Connection], reason: u32, text: string) {
    disconnect(conn, reason, text)
}

// ---- Reading

/** Read what can be read: the version, then packets, until one waits on the caller or more must arrive. */
process :: fn(conn: ptr[mut Connection]) {
    loop {
        if conn.ended || conn.waiting != .Nothing {
            return void
        }
        if !conn.version_received {
            if !read_version(conn) {
                return void
            }
            continue
        }
        length :: next_packet(conn) or_return void
        handle(conn, range(conn.payload[0..<PAYLOAD_BYTES], 0, length))
        for i in cast[usize](0)..<length {
            if i < conn.payload.count {
                conn.payload[i] = 0
            }
        }
    }
    while true
}

/**
 * Read the peer's version line, if it's all here: lines before it that aren't one are passed over, as RFC 4253 lets
 * a server send them.
 *
 * @return True once it's read; false if more must arrive, or it isn't SSH 2.0, when the connection's ended.
 */
read_version :: fn(conn: ptr[mut Connection]) -> bool {
    loop {
        end := conn.incoming_count
        for i in cast[usize](0)..<conn.incoming_count {
            if end == conn.incoming_count && i < conn.incoming.count && conn.incoming[i] == 0x0a {
                end = i
            }
        }
        if end == conn.incoming_count {
            if conn.incoming_count > 255 {
                conn.ended = true
                conn.ended_reason = DISCONNECT_PROTOCOL_ERROR
                event(conn, .Ended)
            }
            return false
        }
        line_end := end
        if line_end > 0 && byte_at(conn.incoming[0..<INCOMING_BYTES], line_end - 1) == 0x0d {
            line_end -= 1
        }
        line :: range(conn.incoming[0..<INCOMING_BYTES], 0, line_end)
        is_version :: same(range(line, 0, 4), string_bytes("SSH-"))
        if is_version {
            if !same(range(line, 0, 8), string_bytes("SSH-2.0-")) || line.count > 255 {
                conn.ended = true
                conn.ended_reason = DISCONNECT_PROTOCOL_ERROR
                event(conn, .Ended)
                return false
            }
            for byte, i in line {
                if i < conn.peer_version.count {
                    conn.peer_version[i] = byte
                }
            }
            conn.peer_version_length = line.count
        }
        drop_incoming(conn, end + 1)
        if is_version {
            conn.version_received = true
            return true
        }
    }
    while true
    return false
}

/** Drop bytes read from the front of what's arrived. */
drop_incoming :: fn(conn: ptr[mut Connection], count: usize) {
    conn.incoming_count = drop_front(conn.incoming[0..<INCOMING_BYTES], conn.incoming_count, count)
}

/**
 * Take a packet's message.
 *
 * @param conn The connection.
 * @param message The payload: its message number, then what that message has.
 */
handle :: fn(conn: ptr[mut Connection], message: u8[]) {
    if message.count == 0 {
        fail(conn, DISCONNECT_PROTOCOL_ERROR, "an empty packet")
        return void
    }
    kind :: message[0]
    // In a strict first exchange, only its own messages, and KEXINIT has to be first (OpenSSH's PROTOCOL, 1.10)
    if conn.strict && !conn.first_done && kind != MSG_KEXINIT && kind != MSG_NEWKEYS && kind != MSG_KEX_INIT
        && kind != MSG_KEX_REPLY {
        fail(conn, DISCONNECT_PROTOCOL_ERROR, "a message during the strict key exchange")
        return void
    }
    if conn.skip_guess && (kind == MSG_KEX_INIT || kind == MSG_KEX_REPLY) {
        // The peer guessed the exchange wrong: its first message for it is passed over (RFC 4253, 7)
        conn.skip_guess = false
        return void
    }
    if kind == MSG_DISCONNECT {
        reader := Reader.{at = 1, end = message.count}
        conn.ended_reason = get_u32(message, &reader)
        conn.ended = true
        event(conn, .Ended)
        return void
    }
    if kind == MSG_IGNORE || kind == MSG_DEBUG || kind == MSG_UNIMPLEMENTED {
        return void
    }
    if kind == MSG_KEXINIT || kind == MSG_NEWKEYS || kind == MSG_KEX_INIT || kind == MSG_KEX_REPLY {
        handle_kex(conn, message)
        return void
    }
    // Nothing but the exchange's own messages while keys are exchanged (RFC 4253, 7.1)
    if !conn.first_done || (conn.kex_received && !conn.newkeys_received) {
        fail(conn, DISCONNECT_PROTOCOL_ERROR, "a message before keys were exchanged")
        return void
    }
    if kind == MSG_EXT_INFO {
        return void
    }
    if kind == MSG_SERVICE_REQUEST || kind == MSG_SERVICE_ACCEPT || (kind >= 50 && kind <= 79) {
        handle_auth(conn, message)
        return void
    }
    if !conn.authenticated {
        fail(conn, DISCONNECT_PROTOCOL_ERROR, "a message before authentication")
        return void
    }
    if kind >= 80 && kind <= 127 {
        handle_connection(conn, message)
        return void
    }
    unimplemented(conn)
}

/** Answer a message this side doesn't know, by the sequence number it came with. */
unimplemented :: fn(conn: ptr[mut Connection]) {
    writer := Writer.{}
    put_u8(conn.message[0..<PAYLOAD_BYTES], &writer, MSG_UNIMPLEMENTED)
    put_u32(conn.message[0..<PAYLOAD_BYTES], &writer, conn.into.sequence - 1)
    send_message(conn, range(conn.message[0..<PAYLOAD_BYTES], 0, writer.at))
}

/** Random bytes, from context.random. */
random_bytes :: fn(into: mut u8[]) {
    random.fill(into)
}

/** Random secret bytes. */
random_secret #constant_time :: fn(into: mut crypto.SecretByte[]) {
    bytes : u8[64]
    random.fill(bytes[0..<64])
    for i in cast[usize](0)..<into.count {
        into[i] = cast[crypto.SecretByte](bytes[i % 64])
    }
    for &byte in bytes {
        byte^ = 0
    }
}

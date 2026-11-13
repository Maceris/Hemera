/*
 * std/ssh against OpenSSH, on Linux: a program that speaks SSH on its standard input and output, which
 * linux_tests.py's openssh_interop runs with OpenSSH's own programs, as
 *
 *     ssh -o ProxyCommand="ssh_openssh server HOST_KEY AUTHORIZED PASSWORD" ...     a server for OpenSSH's ssh
 *     ssh_openssh client USER KEY KNOWN_HOST COMMAND [DATA] < from_sshd > to_sshd   a client of sshd -i
 *     ssh_openssh keygen FILE                                                     a key for ssh-keygen to read
 *     ssh_openssh fingerprint FILE                                                a public key's fingerprint
 *
 * The server takes the key in AUTHORIZED or the password, and runs two commands of its own: cat, which gives back
 * what it's sent, and anything else, which it answers with "ran " and the command, exiting 7. A shell, with or without
 * a terminal, is cat. The client checks the server's key is the one in KNOWN_HOST, logs in with KEY, runs COMMAND, sends
 * it DATA's contents if there's a DATA, writes what comes back to standard error, and exits with its exit status.
 */
package ssh_openssh

import compiler from "base"
import runtime from "base"
import crypto from "std"
import os from "std"
import ssh from "std"
import strings from "std"

STANDARD_INPUT :: os.File.{handle = 0}
STANDARD_OUTPUT :: os.File.{handle = 1}
STANDARD_ERROR :: os.File.{handle = 2}

/** What a program here keeps: its connection, and what's arrived on its standard input that it hasn't taken. */
Side :: struct {
    conn : ssh.Connection,
    pending : u8[65536],
    pending_first : usize,
    pending_count : usize,
    input_ended : bool,
    // The server's
    authorized : ssh.PublicKey,
    channel : u32,
    echoing : bool,
    // The client's
    known : ssh.PublicKey,
    data : string,
    exit_status : u32,
    exited : bool,
    finished : bool,
}

main :: fn() -> int {
    arguments :: os.arguments()
    if arguments.count < 2 {
        return 2
    }
    mode :: arguments[1]
    if mode == "keygen" && arguments.count == 3 {
        return keygen(arguments[2])
    }
    if mode == "fingerprint" && arguments.count == 3 {
        return print_fingerprint(arguments[2])
    }
    if mode == "server" && arguments.count == 5 {
        return serve(arguments[2], arguments[3], arguments[4])
    }
    if mode == "client" && (arguments.count == 6 || arguments.count == 7) {
        return connect(arguments[2], arguments[3], arguments[4], arguments[5], if arguments.count == 7 { arguments[6] } else { "" })
    }
    return 2
}

/** A file's contents, or "" if it can't be read. */
contents :: fn(path: string) -> string {
    file :: os.open(path, .READ) or_return ""
    defer os.close(file)
    return os.read_all(file, context.allocator) or_return ""
}

/** Write a key's private key text to path, and its line to path.pub. */
keygen #constant_time :: fn(path: string) -> int {
    random : u8[32]
    ssh.random_bytes(random[0..<32])
    seed : crypto.Ed25519SecretKey
    for i in cast[usize](0)..<32 {
        seed[i] = random[i]
        random[i] = 0
    }
    text : u8[ssh.PRIVATE_KEY_TEXT_BYTES]
    length :: ssh.private_key_text(&seed, "hemera@test", text[0..<ssh.PRIVATE_KEY_TEXT_BYTES])
    public :: crypto.ed25519_public_key(&seed)
    blob :: ssh.ed25519_blob(&public)
    key :: ssh.parse_public_key(blob[0..<ssh.ED25519_BLOB_BYTES]) or_return 3
    line : u8[200]
    line_length :: ssh.key_line(&key, "hemera@test", line[0..<200])
    if length == 0 || line_length == 0 {
        return 3
    }
    file :: os.open(path, .WRITE) or_return 4
    _ = os.write(file, string_of(&text[0], length))
    os.close(file)
    public_path :: strings.format("%.pub", path) or_return 4
    public_file :: os.open(public_path, .WRITE) or_return 4
    _ = os.write(public_file, string_of(&line[0], line_length))
    _ = os.write(public_file, "\n")
    os.close(public_file)
    return 0
}

/** Print the fingerprint of the key on a file's first line. */
print_fingerprint :: fn(path: string) -> int {
    key :: ssh.parse_key_line(first_line(contents(path))) or_return 3
    printed :: ssh.fingerprint(ssh.blob_of(&key))
    _ = os.write(STANDARD_OUTPUT, string_of(&printed[0], 50))
    _ = os.write(STANDARD_OUTPUT, "\n")
    return 0
}

/** One of the program's arguments; the ones serve and connect need are there. */
argument :: fn(position: usize) -> string {
    arguments :: os.arguments()
    return if position < arguments.count { arguments[position] } else { "" }
}

/** Write bytes to standard output: false if it's gone. */
write_out :: fn(bytes: u8[]) -> bool {
    if bytes.count == 0 {
        return true
    }
    return os.write(STANDARD_OUTPUT, string_of(&bytes[0], bytes.count)) == null
}

/** A text's first line, without its line break. */
first_line :: fn(text: string) -> u8[] {
    bytes :: string_bytes(text)
    for byte, i in bytes {
        if byte == 0x0a {
            return bytes[0..<i]
        }
    }
    return bytes
}

/** Serve one connection on standard input and output. */
serve #constant_time :: fn(host_key_path: string, authorized_path: string, password: string) -> int {
    host :: ssh.parse_private_key(string_bytes(contents(host_key_path))) or_return 3
    side :: runtime.new(Side)
    defer runtime.free(side)
    side.authorized = ssh.parse_key_line(first_line(contents(authorized_path))) or_return 3
    ssh.server(&side.conn, &host)
    run(side, server_events)
    return 0
}

/** Connect as a client on standard input and output. */
connect #constant_time :: fn(user: string, key_path: string, known_path: string, command: string, data_path: string) -> int {
    key :: ssh.parse_private_key(string_bytes(contents(key_path))) or_return 3
    side :: runtime.new(Side)
    defer runtime.free(side)
    side.known = ssh.parse_key_line(first_line(contents(known_path))) or_return 3
    side.data = if data_path.count > 0 { contents(data_path) } else { "" }
    ssh.client(&side.conn, user, &key)
    run(side, client_events)
    if !side.exited {
        return 100
    }
    return cast[int](side.exit_status)
}

/** Move bytes between the connection and standard input and output, taking its events, until it ends. */
run :: fn(side: ptr[mut Side], events: (fn(ptr[mut Side]))) {
    loop {
        events(side)
        out :: ssh.output(&side.conn)
        if out.count > 0 {
            if !write_out(out) {
                return void
            }
            ssh.sent(&side.conn, out.count)
            continue
        }
        if ssh.is_ended(&side.conn) || side.finished {
            return void
        }
        if side.pending_count > 0 {
            taken :: ssh.received(&side.conn, ssh.range(side.pending[0..<65536], side.pending_first, side.pending_first + side.pending_count))
            side.pending_first += taken
            side.pending_count -= taken
            if taken > 0 {
                continue
            }
        }
        if side.input_ended {
            return void
        }
        if side.pending_count == 0 {
            side.pending_first = 0
            count :: os.read(STANDARD_INPUT, side.pending[0..<65536]) or_else 0
            side.pending_count = count
            side.input_ended = count == 0
        }
        else {
            // Stuck with bytes the connection won't take: it's waiting on a channel's reader, which events() is
            events(side)
            if ssh.output(&side.conn).count == 0 && !ssh.is_ended(&side.conn) {
                return void
            }
        }
    }
    while true
}

/** The server's events. */
server_events #constant_time :: fn(side: ptr[mut Side]) {
    loop {
        happened :: ssh.take_event(&side.conn) or_break
        match happened {
            case Password => {
                offered :: ssh.offered_password_of(&side.conn)
                ssh.answer_authentication(&side.conn, crypto.equal(offered, string_bytes(argument(4))))
            }
            case PublicKey(signed) => {
                offered :: ssh.offered_key_of(&side.conn)
                ssh.answer_authentication(&side.conn, ssh.same(ssh.blob_of(offered), ssh.blob_of(&side.authorized)))
            }
            case ChannelOpened(number) => side.channel = number
            case ChannelRequest(number) => {
                request :: ssh.request_of(&side.conn)
                kind :: request.kind
                if kind == .Pty {
                    ssh.answer_request(&side.conn, true)
                }
                else if kind == .Shell {
                    ssh.answer_request(&side.conn, true)
                    side.echoing = true
                }
                else if kind == .Exec {
                    command :: ssh.request_text(request)
                    ssh.answer_request(&side.conn, true)
                    if ssh.is(command, "cat") {
                        side.echoing = true
                    }
                    else {
                        _ = ssh.channel_write(&side.conn, number, string_bytes("ran "))
                        _ = ssh.channel_write(&side.conn, number, command)
                        _ = ssh.channel_write(&side.conn, number, string_bytes("\n"))
                        ssh.channel_exit_status(&side.conn, number, 7)
                        ssh.channel_eof(&side.conn, number)
                        ssh.channel_close(&side.conn, number)
                    }
                }
                else {
                    ssh.answer_request(&side.conn, false)
                }
            }
            case ChannelData(number) => {
                chunk : u8[16384]
                loop {
                    got :: ssh.channel_read(&side.conn, number, chunk[0..<16384])
                    if got == 0 {
                        break
                    }
                    if side.echoing {
                        written := cast[usize](0)
                        loop {
                            written += ssh.channel_write(&side.conn, number, ssh.range(chunk[0..<16384], written, got))
                            if written >= got || !flush(side) {
                                break
                            }
                        }
                        while true
                    }
                }
                while true
            }
            case ChannelEof(number) => {
                if side.echoing {
                    ssh.channel_exit_status(&side.conn, number, 0)
                    ssh.channel_eof(&side.conn, number)
                    ssh.channel_close(&side.conn, number)
                }
            }
            case ChannelClosed(number) => {}
            case _ => {}
        }
    }
    while true
}

/**
 * Write what the connection has out, and take what's arrived, while a channel's window is shut: true if anything
 * moved.
 */
flush :: fn(side: ptr[mut Side]) -> bool {
    out :: ssh.output(&side.conn)
    if out.count > 0 {
        if !write_out(out) {
            return false
        }
        ssh.sent(&side.conn, out.count)
    }
    if side.pending_count == 0 && !side.input_ended {
        side.pending_first = 0
        count :: os.read(STANDARD_INPUT, side.pending[0..<65536]) or_else 0
        side.pending_count = count
        side.input_ended = count == 0
    }
    if side.pending_count > 0 {
        taken :: ssh.received(&side.conn, ssh.range(side.pending[0..<65536], side.pending_first, side.pending_first + side.pending_count))
        side.pending_first += taken
        side.pending_count -= taken
        return true
    }
    return out.count > 0
}

/** The client's events. */
client_events :: fn(side: ptr[mut Side]) {
    loop {
        happened :: ssh.take_event(&side.conn) or_break
        match happened {
            case HostKey => {
                ssh.trust_host_key(&side.conn, ssh.same(ssh.blob_of(ssh.host_key_of(&side.conn)), ssh.blob_of(&side.known)))
            }
            case Authenticated => {
                side.channel = ssh.open_session(&side.conn) or_else 0
            }
            case AuthenticationRefused => side.finished = true
            case PasswordWanted => side.finished = true
            case ChannelOpened(number) => {
                _ = ssh.channel_request(&side.conn, number, .Exec, argument(5))
                data :: string_bytes(side.data)
                written := cast[usize](0)
                loop {
                    written += ssh.channel_write(&side.conn, number, ssh.range(data, written, data.count))
                    if written >= data.count || !flush(side) {
                        break
                    }
                }
                while true
                ssh.channel_eof(&side.conn, number)
            }
            case ChannelRefused(number) => side.finished = true
            case ChannelData(number) => {
                chunk : u8[16384]
                loop {
                    got :: ssh.channel_read(&side.conn, number, chunk[0..<16384])
                    if got == 0 {
                        break
                    }
                    _ = os.write(STANDARD_ERROR, string_of(&chunk[0], got))
                }
                while true
            }
            case ExitStatus(exit) => {
                side.exit_status = exit.status
                side.exited = true
            }
            case ChannelClosed(number) => {
                ssh.disconnect(&side.conn, ssh.DISCONNECT_BY_APPLICATION, "done")
                side.finished = true
            }
            case _ => {}
        }
    }
    while true
}

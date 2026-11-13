/*
 * std/ssh: a client and a server in memory, pumped against each other. Logging in with a key and with a password, a
 * wrong one refused; a command run and its output and exit status; data both ways through the windows, by each key
 * exchange and cipher; a rekey in the middle of it; a changed byte refused; and random bytes taken without harm. Run
 * with hemera --test.
 */
package ssh_test

import compiler from "base"
import runtime from "base"
import crypto from "std"
import ssh from "std"
import testing from "std"

/** A client, a server, and what each has seen. */
Pair :: struct {
    client : ssh.Connection,
    server : ssh.Connection,
    /** The server's: the password it takes, and the key it takes. */
    password : string,
    key : ssh.PublicKey,
    /** What the client gives when asked for a password. */
    given_password : string,
    trusted : bool,
    authenticated : bool,
    refused : bool,
    password_asks : u32,
    client_channel : u32,
    client_opened : bool,
    server_channel : u32,
    server_opened : bool,
    answered : u32,
    requests : u32,
    last_request : ssh.RequestKind,
    command : u8[64],
    command_length : usize,
    client_got : u8[300000],
    client_got_count : usize,
    server_got : u8[300000],
    server_got_count : usize,
    exit_status : u32,
    exited : bool,
    client_closed : bool,
    server_closed : bool,
    client_eof : bool,
    server_eof : bool,
}

/** A key from a byte repeated, to know it. */
key_of #constant_time :: fn(byte: u8) -> crypto.Ed25519SecretKey {
    key : crypto.Ed25519SecretKey
    for i in cast[usize](0)..<32 {
        key[i] = byte
    }
    return key
}

/**
 * Make a pair: the server with host key 1s, offering one exchange or cipher if asked; the client logging in as alice,
 * with key 2s or none.
 */
make_pair #constant_time :: fn(with_key: bool, kex: ssh.KeyExchange = .None, cipher: ssh.Cipher = .None) -> ptr[mut Pair] {
    pair :: runtime.new(Pair)
    host :: key_of(1)
    user :: key_of(2)
    ssh.server(&pair.server, &host, kex, cipher)
    ssh.client(&pair.client, "alice", if with_key { &user } else { null })
    public :: crypto.ed25519_public_key(&user)
    blob :: ssh.ed25519_blob(&public)
    pair.key = ssh.parse_public_key(blob[0..<ssh.ED25519_BLOB_BYTES]) or_else ssh.PublicKey.{}
    pair.password = "correct horse"
    pair.given_password = "correct horse"
    pair.trusted = true
    return pair
}

/** Move what each side has for the other across, and take each side's events, until neither has anything new. */
pump :: fn(pair: ptr[mut Pair]) {
    for round in 0..<2000 {
        moved := false
        out :: ssh.output(&pair.client)
        if out.count > 0 {
            taken :: ssh.received(&pair.server, out)
            ssh.sent(&pair.client, taken)
            moved = moved || taken > 0
        }
        back :: ssh.output(&pair.server)
        if back.count > 0 {
            taken :: ssh.received(&pair.client, back)
            ssh.sent(&pair.server, taken)
            moved = moved || taken > 0
        }
        moved = client_events(pair) || moved
        moved = server_events(pair) || moved
        if !moved {
            return void
        }
    }
}

/** Take the client's events. */
client_events #constant_time :: fn(pair: ptr[mut Pair]) -> bool {
    any := false
    loop {
        happened :: ssh.take_event(&pair.client) or_break
        any = true
        match happened {
            case HostKey => ssh.trust_host_key(&pair.client, pair.trusted)
            case PasswordWanted => {
                pair.password_asks += 1
                ssh.give_password(&pair.client, crypto.as_secret(string_bytes(pair.given_password)))
            }
            case Authenticated => pair.authenticated = true
            case AuthenticationRefused => pair.refused = true
            case ChannelOpened(number) => {
                pair.client_channel = number
                pair.client_opened = true
            }
            case RequestAnswered(answer) => pair.answered += 1
            case ChannelData(number) => {
                loop {
                    room :: pair.client_got.count - pair.client_got_count
                    got :: ssh.channel_read(&pair.client, number, range(pair.client_got[0..<300000], pair.client_got_count, pair.client_got_count + (if room < 4096 { room } else { 4096 })))
                    pair.client_got_count += got
                    if got == 0 {
                        break
                    }
                }
                while true
            }
            case ExitStatus(exit) => {
                pair.exit_status = exit.status
                pair.exited = true
            }
            case ChannelEof(number) => pair.client_eof = true
            case ChannelClosed(number) => pair.client_closed = true
            case _ => {}
        }
    }
    while true
    return any
}

/** Take the server's events. */
server_events #constant_time :: fn(pair: ptr[mut Pair]) -> bool {
    any := false
    loop {
        happened :: ssh.take_event(&pair.server) or_break
        any = true
        match happened {
            case Password => {
                offered :: ssh.offered_password_of(&pair.server)
                ssh.answer_authentication(&pair.server, crypto.equal(offered, string_bytes(pair.password)))
            }
            case PublicKey(signed) => {
                offered :: ssh.offered_key_of(&pair.server)
                ssh.answer_authentication(&pair.server, ssh.same(ssh.blob_of(offered), ssh.blob_of(&pair.key)))
            }
            case ChannelOpened(number) => {
                pair.server_channel = number
                pair.server_opened = true
            }
            case ChannelRequest(number) => {
                request :: ssh.request_of(&pair.server)
                pair.requests += 1
                pair.last_request = request.kind
                text :: ssh.request_text(request)
                pair.command_length = 0
                for byte, i in text {
                    if i < pair.command.count {
                        pair.command[i] = byte
                        pair.command_length = i + 1
                    }
                }
                ssh.answer_request(&pair.server, true)
            }
            case ChannelData(number) => {
                loop {
                    room :: pair.server_got.count - pair.server_got_count
                    got :: ssh.channel_read(&pair.server, number, range(pair.server_got[0..<300000], pair.server_got_count, pair.server_got_count + (if room < 4096 { room } else { 4096 })))
                    pair.server_got_count += got
                    if got == 0 {
                        break
                    }
                }
                while true
            }
            case ChannelEof(number) => pair.server_eof = true
            case ChannelClosed(number) => pair.server_closed = true
            case _ => {}
        }
    }
    while true
    return any
}

/** Part of a view to write, or none. */
range :: fn(view: mut u8[], from: usize, to: usize) -> mut u8[] {
    if from > to || to > view.count {
        return view[0..<0]
    }
    return view[from..<to]
}

/** A pattern's byte at an offset. */
pattern :: fn(seed: u64, at: usize) -> u8 {
    x := seed * 0x9e3779b97f4a7c15 + cast[u64](at) * 0x2545f4914f6cdd1d
    x = x ~ (x >> 29)
    return cast[u8](x)
}

logs_in_with_a_key_and_runs_a_command #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    pair :: make_pair(true)
    defer runtime.free(pair)
    pump(pair)
    testing.require(t, pair.authenticated, "the client's authenticated with its key")?
    testing.expect(t, ssh.same(ssh.user_of(&pair.server), string_bytes("alice")), "as alice")
    channel :: ssh.open_session(&pair.client) or_else 99
    pump(pair)
    testing.require(t, pair.client_opened && pair.server_opened, "a session channel's open")?
    testing.expect(t, ssh.channel_request(&pair.client, channel, .Exec, "echo hi"), "exec asked")
    pump(pair)
    testing.expect(t, pair.last_request == .Exec && ssh.same(range(pair.command[0..<64], 0, pair.command_length), string_bytes("echo hi")), "the server got the command")
    testing.expect_eq(t, pair.answered, cast[u32](1), "and answered it")
    output :: "hi\n"
    testing.expect_eq(t, ssh.channel_write(&pair.server, pair.server_channel, string_bytes(output)), output.count, "the command's output written")
    ssh.channel_exit_status(&pair.server, pair.server_channel, 3)
    ssh.channel_eof(&pair.server, pair.server_channel)
    ssh.channel_close(&pair.server, pair.server_channel)
    pump(pair)
    testing.expect(t, ssh.same(range(pair.client_got[0..<300000], 0, pair.client_got_count), string_bytes(output)), "the client read it")
    testing.expect(t, pair.exited && pair.exit_status == 3, "and its exit status")
    testing.expect(t, pair.client_eof && pair.client_closed && pair.server_closed, "the channel closed both ways")
    return .Ok
}

logs_in_with_a_password #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    pair :: make_pair(false)
    defer runtime.free(pair)
    pump(pair)
    testing.expect(t, pair.authenticated, "the right password's taken")
    wrong :: make_pair(false)
    defer runtime.free(wrong)
    wrong.given_password = "wrong"
    pump(wrong)
    testing.expect(t, !wrong.authenticated, "a wrong password isn't")
    testing.expect(t, wrong.password_asks > 1, "the client's asked again")
    testing.expect(t, ssh.is_ended(&wrong.server), "until the server gives up")
    return .Ok
}

refuses_an_untrusted_host_key #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    pair :: make_pair(true)
    defer runtime.free(pair)
    pair.trusted = false
    pump(pair)
    testing.expect(t, !pair.authenticated && ssh.is_ended(&pair.client), "the client ends, not trusting the key")
    return .Ok
}

/** Data both ways, more than the windows hold, by each exchange and cipher, and through a rekey. */
moves_data_each_way #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    exchanges :: ssh.KeyExchange.[.Hybrid, .Curve]
    ciphers :: ssh.Cipher.[.Chacha, .Gcm]
    for exchange in exchanges {
        for cipher in ciphers {
            pair :: make_pair(true, exchange, cipher)
            defer runtime.free(pair)
            pump(pair)
            testing.require(t, pair.authenticated, "authenticated")?
            channel :: ssh.open_session(&pair.client) or_else 99
            pump(pair)
            _ = ssh.channel_request(&pair.client, channel, .Shell, "")
            pump(pair)
            total :: cast[usize](200000)
            sent_up := cast[usize](0)
            sent_down := cast[usize](0)
            rekeyed := false
            for round in 0..<2000 {
                if sent_up < total {
                    chunk : u8[8192]
                    for i in cast[usize](0)..<8192 {
                        chunk[i] = pattern(1, sent_up + i)
                    }
                    count :: if total - sent_up < 8192 { total - sent_up } else { cast[usize](8192) }
                    sent_up += ssh.channel_write(&pair.client, channel, range(chunk[0..<8192], 0, count))
                }
                if sent_down < total {
                    chunk : u8[8192]
                    for i in cast[usize](0)..<8192 {
                        chunk[i] = pattern(2, sent_down + i)
                    }
                    count :: if total - sent_down < 8192 { total - sent_down } else { cast[usize](8192) }
                    sent_down += ssh.channel_write(&pair.server, pair.server_channel, range(chunk[0..<8192], 0, count))
                }
                if !rekeyed && sent_up > total / 2 {
                    ssh.rekey(&pair.client)
                    rekeyed = true
                }
                pump(pair)
            }
            testing.expect_eq(t, pair.server_got_count, total, "everything the client wrote arrived")
            testing.expect_eq(t, pair.client_got_count, total, "and everything the server wrote")
            right := true
            for i in cast[usize](0)..<total {
                if i < pair.server_got.count && pair.server_got[i] != pattern(1, i) {
                    right = false
                }
                if i < pair.client_got.count && pair.client_got[i] != pattern(2, i) {
                    right = false
                }
            }
            testing.expect(t, right, "as it was written")
            testing.expect(t, !ssh.is_ended(&pair.client) && !ssh.is_ended(&pair.server), "through a rekey")
        }
    }
    return .Ok
}

/** A byte changed on its way ends the connection: its packet isn't authentic. */
refuses_a_changed_packet #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    pair :: make_pair(true)
    defer runtime.free(pair)
    pump(pair)
    testing.require(t, pair.authenticated, "authenticated")?
    channel :: ssh.open_session(&pair.client) or_else 99
    _ = ssh.channel_write(&pair.client, channel, string_bytes("unchanged"))
    out :: ssh.output(&pair.client)
    copy : u8[4096]
    count :: if out.count < 4096 { out.count } else { cast[usize](4096) }
    for i in cast[usize](0)..<count {
        if i < copy.count && i < out.count {
            copy[i] = out[i]
        }
    }
    middle :: count / 2
    if middle < copy.count {
        copy[middle] = copy[middle] ~ 1
    }
    _ = ssh.received(&pair.server, range(copy[0..<4096], 0, count))
    testing.expect(t, ssh.is_ended(&pair.server), "the server ends the connection")
    return .Ok
}

/** Random bytes after a version line, as a peer might send, are taken without harm. */
takes_any_bytes #test :: fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    server :: runtime.new(ssh.Connection)
    defer runtime.free(server)
    host :: key_of(1)
    ssh.server(server, &host)
    _ = ssh.received(server, string_bytes("SSH-2.0-test\r\n"))
    bytes :: testing.draw_bytes(source, 3000)
    _ = ssh.received(server, bytes)
    return .Ok
}

/** A key ssh-keygen -t ed25519 wrote, with its line and fingerprint as ssh-keygen gave them. */
OPENSSH_KEY :: "-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW\nQyNTUxOQAAACBHGbroFg4trZq0hMw+WeSf0EYbeqUurFwnc3lFuqiWNgAAAJDAYp01wGKd\nNQAAAAtzc2gtZWQyNTUxOQAAACBHGbroFg4trZq0hMw+WeSf0EYbeqUurFwnc3lFuqiWNg\nAAAEAkFA+yIfbogRYAP7cVmJVXuby0PjtTmg7ZIWYdCPhJ8EcZuugWDi2tmrSEzD5Z5J/Q\nRht6pS6sXCdzeUW6qJY2AAAAC3ZlY3RvckB0ZXN0AQI=\n-----END OPENSSH PRIVATE KEY-----\n"
OPENSSH_LINE :: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEcZuugWDi2tmrSEzD5Z5J/QRht6pS6sXCdzeUW6qJY2 vector@test"
OPENSSH_FINGERPRINT :: "SHA256:bBEtczzyIjtfN3fYz88H8A1mtM1727e1zgfHXEs8XyI"

/** The public key of a private key's seed, as a PublicKey. */
public_of #constant_time :: fn(secret: ptr[crypto.Ed25519SecretKey]) -> ssh.PublicKey {
    public :: crypto.ed25519_public_key(secret)
    blob :: ssh.ed25519_blob(&public)
    return ssh.parse_public_key(blob[0..<ssh.ED25519_BLOB_BYTES]) or_else ssh.PublicKey.{}
}

reads_and_writes_openssh_keys #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    secret :: ssh.parse_private_key(string_bytes(OPENSSH_KEY))
    testing.require(t, secret != null, "ssh-keygen's private key is read")?
    seed :: secret or_else key_of(0)
    key :: public_of(&seed)
    line : u8[200]
    length :: ssh.key_line(&key, "vector@test", line[0..<200])
    testing.expect(t, ssh.is(range(line[0..<200], 0, length), OPENSSH_LINE), "its public key's line is ssh-keygen's")
    read :: ssh.parse_key_line(string_bytes(OPENSSH_LINE)) or_else ssh.PublicKey.{}
    testing.expect(t, ssh.same(ssh.blob_of(&read), ssh.blob_of(&key)), "and ssh-keygen's line is read as the key")
    printed :: ssh.fingerprint(ssh.blob_of(&key))
    testing.expect(t, ssh.is(printed[0..<50], OPENSSH_FINGERPRINT), "its fingerprint is ssh-keygen's")
    // Written and read again
    text : u8[ssh.PRIVATE_KEY_TEXT_BYTES]
    written :: ssh.private_key_text(&seed, "again@test", text[0..<ssh.PRIVATE_KEY_TEXT_BYTES])
    testing.require(t, written > 0, "the key's written")?
    again :: ssh.parse_private_key(range(text[0..<ssh.PRIVATE_KEY_TEXT_BYTES], 0, written)) or_else key_of(0)
    key_again :: public_of(&again)
    testing.expect(t, ssh.same(ssh.blob_of(&key_again), ssh.blob_of(&key)), "and read back as the same key")
    // Damaged, it isn't read
    damaged : u8[600]
    original :: string_bytes(OPENSSH_KEY)
    for byte, i in original {
        if i < damaged.count {
            damaged[i] = byte
        }
    }
    damaged[200] = 0x41 + (damaged[200] - 0x40) % 26
    testing.expect(t, ssh.parse_private_key(range(damaged[0..<600], 0, original.count)) == null, "a damaged key isn't read")
    testing.expect(t, ssh.parse_key_line(string_bytes("ssh-rsa AAAAC3NzaC1lZDI1NTE5AAAAIEcZuugWDi2tmrSEzD5Z5J/QRht6pS6sXCdzeUW6qJY2")) == null,
        "nor a line whose name isn't its key's")
    return .Ok
}

/** Any bytes as a key's line, a private key's text or a key's blob are refused or read, without harm. */
reads_any_keys #test :: fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    bytes :: testing.draw_bytes(source, 1500)
    _ = ssh.parse_key_line(bytes)
    _ = ssh.parse_public_key(bytes)
    _ = ssh.parse_private_key(bytes)
    return .Ok
}

/** Random bytes after a version line, sent to a client, are taken without harm. */
client_takes_any_bytes #test :: fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    client :: runtime.new(ssh.Connection)
    defer runtime.free(client)
    ssh.client(client, "alice", null)
    _ = ssh.received(client, string_bytes("SSH-2.0-test\r\n"))
    bytes :: testing.draw_bytes(source, 3000)
    _ = ssh.received(client, bytes)
    return .Ok
}

/**
 * A NEWKEYS in the clear, right after the client's sent its exchange, before it has any keys (as a man in the middle
 * would send one, to have it read the rest in the clear), ends the connection.
 */
refuses_newkeys_before_the_reply #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    pair :: make_pair(true)
    defer runtime.free(pair)
    // The server's version and KEXINIT to the client, which answers with its KEXINIT and its exchange
    server_out :: ssh.output(&pair.server)
    taken :: ssh.received(&pair.client, server_out)
    ssh.sent(&pair.server, taken)
    testing.require(t, !ssh.is_ended(&pair.client), "the client's taken the server's KEXINIT")?
    // NEWKEYS: length 12, padding 10, the message, the padding
    forged : u8[16]
    forged[3] = 12
    forged[4] = 10
    forged[5] = 21
    _ = ssh.received(&pair.client, forged[0..<16])
    testing.expect(t, ssh.is_ended(&pair.client), "the client ends the connection")
    return .Ok
}

/** A client that doesn't offer strict key exchange is refused: Terrapin's prefix truncation works on one. */
refuses_a_peer_without_strict_key_exchange #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    server :: runtime.new(ssh.Connection)
    defer runtime.free(server)
    host :: key_of(1)
    ssh.server(server, &host)
    // A client's version and KEXINIT that offers curve25519-sha256 and nothing more
    hello : u8[1024]
    writer := ssh.Writer.{}
    out :: hello[0..<1024]
    ssh.put_bytes(out, &writer, string_bytes("SSH-2.0-test\r\n"))
    length_at :: writer.at
    ssh.put_u32(out, &writer, 0)
    ssh.put_u8(out, &writer, 4)
    ssh.put_u8(out, &writer, ssh.MSG_KEXINIT)
    for i in 0..<16 {
        ssh.put_u8(out, &writer, 7)
    }
    ssh.put_text(out, &writer, "curve25519-sha256")
    ssh.put_text(out, &writer, "ssh-ed25519")
    for i in 0..<2 {
        ssh.put_text(out, &writer, "chacha20-poly1305@openssh.com")
    }
    for i in 0..<2 {
        ssh.put_text(out, &writer, "hmac-sha2-256")
    }
    for i in 0..<2 {
        ssh.put_text(out, &writer, "none")
    }
    for i in 0..<2 {
        ssh.put_text(out, &writer, "")
    }
    ssh.put_bool(out, &writer, false)
    ssh.put_u32(out, &writer, 0)
    // Padding to a multiple of 8, at least 4
    pad := 8 - (writer.at - length_at) % 8
    if pad < 4 {
        pad += 8
    }
    for i in cast[usize](0)..<pad {
        ssh.put_u8(out, &writer, 0)
    }
    packet_length :: writer.at - length_at - 4
    for i in cast[usize](0)..<4 {
        ssh.set_byte(out, length_at + i, cast[u8](packet_length >> (8 * (3 - i))))
    }
    ssh.set_byte(out, length_at + 4, cast[u8](pad))
    _ = ssh.received(server, range(hello[0..<1024], 0, writer.at))
    testing.expect(t, ssh.is_ended(server), "the server ends the connection")
    return .Ok
}

/** A client that asks for a key exchange again before it's logged in is refused: each is costly to the server. */
refuses_a_second_key_exchange_before_logging_in #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    pair :: make_pair(true)
    defer runtime.free(pair)
    pair.trusted = true
    // Up to the first exchange's end, without logging in: the client's events aren't taken, so it waits on its host key
    for round in 0..<20 {
        out :: ssh.output(&pair.client)
        if out.count > 0 {
            ssh.sent(&pair.client, ssh.received(&pair.server, out))
        }
        back :: ssh.output(&pair.server)
        if back.count > 0 {
            ssh.sent(&pair.server, ssh.received(&pair.client, back))
        }
    }
    _ = ssh.take_event(&pair.client)
    ssh.trust_host_key(&pair.client, true)
    // The client's NEWKEYS, then at once a KEXINIT again
    ssh.sent(&pair.client, ssh.received(&pair.server, ssh.output(&pair.client)))
    ssh.rekey(&pair.client)
    _ = ssh.received(&pair.server, ssh.output(&pair.client))
    testing.expect(t, ssh.is_ended(&pair.server), "the server ends the connection")
    return .Ok
}

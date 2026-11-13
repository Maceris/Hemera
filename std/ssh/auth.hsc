package ssh

import compiler from "base"
import crypto from "std"

/*
 * User authentication (RFC 4252), after the client's service request for ssh-userauth. A server takes "none" (which
 * says what it allows: publickey and password), "password" and "publickey"; a key offered without a signature is
 * answered PK_OK if the caller allows it, and one with a signature is checked over the session's identifier and the
 * request (RFC 4252, 7) before the caller's asked. After MAX_AUTH_TRIES requests it disconnects. A client offers its
 * key, if it has one, signed at once, then a password, if the server allows one, asking its caller for it.
 */

/** Take a message of authentication's, or the service request before it. */
handle_auth :: fn(conn: ptr[mut Connection], message: u8[]) {
    kind :: byte_at(message, 0)
    reader := Reader.{at = 1, end = message.count}
    if conn.role == .Server {
        if kind == MSG_SERVICE_REQUEST && !conn.service_accepted {
            service :: get_string(message, &reader)
            if !is(service, "ssh-userauth") {
                fail(conn, DISCONNECT_SERVICE_NOT_AVAILABLE, "only ssh-userauth")
                return void
            }
            conn.service_accepted = true
            writer := Writer.{}
            put_u8(conn.message[0..<PAYLOAD_BYTES], &writer, MSG_SERVICE_ACCEPT)
            put_text(conn.message[0..<PAYLOAD_BYTES], &writer, "ssh-userauth")
            send_message(conn, range(conn.message[0..<PAYLOAD_BYTES], 0, writer.at))
            return void
        }
        if kind == MSG_USERAUTH_REQUEST && conn.service_accepted && !conn.authenticated {
            take_request(conn, message)
            return void
        }
        // Once authenticated, more requests are ignored (RFC 4252, 5.1)
        if kind == MSG_USERAUTH_REQUEST && conn.authenticated {
            return void
        }
        fail(conn, DISCONNECT_PROTOCOL_ERROR, "an authentication message out of place")
        return void
    }
    if kind == MSG_SERVICE_ACCEPT && !conn.service_accepted {
        conn.service_accepted = true
        next_method(conn, true)
        return void
    }
    if kind == MSG_USERAUTH_BANNER {
        text :: get_string(message, &reader)
        conn.banner_length = 0
        for byte, i in text {
            if i < conn.banner.count {
                conn.banner[i] = byte
                conn.banner_length = i + 1
            }
        }
        event(conn, .Banner)
        return void
    }
    if kind == MSG_USERAUTH_SUCCESS && !conn.authenticated {
        conn.authenticated = true
        conn.pending_password = false
        event(conn, .Authenticated)
        return void
    }
    if kind == MSG_USERAUTH_FAILURE && !conn.authenticated {
        methods :: get_string(message, &reader)
        next_method(conn, has_name(methods, string_bytes("password")))
        return void
    }
    fail(conn, DISCONNECT_PROTOCOL_ERROR, "an authentication message out of place")
}

/** A server's, as its first packet under the first keys: say which signature algorithms it takes for users' keys (RFC 8308). */
send_ext_info :: fn(conn: ptr[mut Connection]) {
    writer := Writer.{}
    put_u8(conn.message[0..<PAYLOAD_BYTES], &writer, MSG_EXT_INFO)
    put_u32(conn.message[0..<PAYLOAD_BYTES], &writer, 1)
    put_text(conn.message[0..<PAYLOAD_BYTES], &writer, "server-sig-algs")
    put_text(conn.message[0..<PAYLOAD_BYTES], &writer, SERVER_SIG_ALGS)
    send_packet(conn, range(conn.message[0..<PAYLOAD_BYTES], 0, writer.at))
}

/** A server's: take a USERAUTH_REQUEST. */
take_request :: fn(conn: ptr[mut Connection], message: u8[]) {
    conn.auth_tries += 1
    if conn.auth_tries > MAX_AUTH_TRIES {
        disconnect(conn, DISCONNECT_NO_MORE_AUTH_METHODS, "too many authentication tries")
        return void
    }
    reader := Reader.{at = 1, end = message.count}
    user :: get_string(message, &reader)
    service :: get_string(message, &reader)
    method :: get_string(message, &reader)
    if reader.bad || user.count == 0 || user.count > USER_BYTES || !is(service, "ssh-connection") {
        refuse_auth(conn)
        return void
    }
    conn.user_length = user.count
    for byte, i in user {
        if i < conn.user.count {
            conn.user[i] = byte
        }
    }
    if is(method, "password") {
        changing :: get_bool(message, &reader)
        password :: get_string(message, &reader)
        if reader.bad || changing || password.count > PASSWORD_BYTES {
            refuse_auth(conn)
            return void
        }
        take_password(conn, password)
        conn.waiting = .Authentication
        event(conn, .Password)
        return void
    }
    if is(method, "publickey") {
        signed :: get_bool(message, &reader)
        algorithm :: get_string(message, &reader)
        blob :: get_string(message, &reader)
        key :: parse_public_key(blob) or_else PublicKey.{}
        if reader.bad || key.kind == .None || !algorithm_fits(key.kind, algorithm) || algorithm.count > conn.offered_algorithm.count {
            refuse_auth(conn)
            return void
        }
        conn.offered_key = key
        conn.offered_signed = signed
        conn.offered_algorithm_length = algorithm.count
        for byte, i in algorithm {
            if i < conn.offered_algorithm.count {
                conn.offered_algorithm[i] = byte
            }
        }
        if signed {
            // The signature, over the session's identifier and the request up to it
            before :: reader.at
            signature :: get_string(message, &reader)
            if !done(&reader) || !signed_request_matches(conn, range(message, 1, before), signature) {
                refuse_auth(conn)
                return void
            }
        }
        conn.waiting = .Authentication
        event(conn, .PublicKey(signed))
        return void
    }
    // "none", or a method this side doesn't have: what it does have
    refuse_auth(conn)
}

/** Keep a password offered, secret. */
take_password #constant_time :: fn(conn: ptr[mut Connection], password: u8[]) {
    for i in cast[usize](0)..<PASSWORD_BYTES {
        conn.offered_password[i] = if i < password.count { cast[crypto.SecretByte](password[i]) } else { cast[crypto.SecretByte](0) }
    }
    conn.offered_password_length = password.count
}

/**
 * Check a publickey request's signature: over the session's identifier, as a string, then the request's message up to
 * its signature.
 *
 * @param conn The connection, its offered_key set.
 * @param request The request after its message number, up to the signature.
 * @param signature The signature's blob.
 * @return True if the key signed it.
 */
signed_request_matches :: fn(conn: ptr[mut Connection], request: u8[], signature: u8[]) -> bool {
    writer := Writer.{}
    data :: conn.message[0..<PAYLOAD_BYTES]
    put_string(data, &writer, conn.session_id[0..<32])
    put_u8(data, &writer, MSG_USERAUTH_REQUEST)
    put_bytes(data, &writer, request)
    if writer.overflow {
        return false
    }
    return verify_signature(&conn.offered_key, range(data, 0, writer.at), signature)
}

/** A server's: send USERAUTH_FAILURE, with what it allows. */
refuse_auth :: fn(conn: ptr[mut Connection]) {
    writer := Writer.{}
    put_u8(conn.message[0..<PAYLOAD_BYTES], &writer, MSG_USERAUTH_FAILURE)
    put_text(conn.message[0..<PAYLOAD_BYTES], &writer, "publickey,password")
    put_bool(conn.message[0..<PAYLOAD_BYTES], &writer, false)
    send_message(conn, range(conn.message[0..<PAYLOAD_BYTES], 0, writer.at))
}

/**
 * A server's answer to Password or PublicKey: a password or a signed key allowed authenticates the user; a key
 * offered without a signature allowed is answered PK_OK, for the client to sign with it next; anything refused gets
 * USERAUTH_FAILURE. The password is wiped either way.
 *
 * @param conn The connection, its Password or PublicKey event taken.
 * @param allowed Whether the password is the user's, or the key one of theirs.
 */
answer_authentication :: fn(conn: ptr[mut Connection], allowed: bool) {
    if conn.waiting != .Authentication {
        return void
    }
    conn.waiting = .Nothing
    wipe_password(conn)
    if !allowed {
        refuse_auth(conn)
        process(conn)
        return void
    }
    writer := Writer.{}
    if conn.offered_key.kind != .None && !conn.offered_signed {
        put_u8(conn.message[0..<PAYLOAD_BYTES], &writer, MSG_USERAUTH_PK_OK)
        put_string(conn.message[0..<PAYLOAD_BYTES], &writer, range(conn.offered_algorithm[0..<32], 0, conn.offered_algorithm_length))
        put_string(conn.message[0..<PAYLOAD_BYTES], &writer, blob_of(&conn.offered_key))
        conn.offered_key = PublicKey.{}
    }
    else {
        put_u8(conn.message[0..<PAYLOAD_BYTES], &writer, MSG_USERAUTH_SUCCESS)
        conn.authenticated = true
    }
    send_message(conn, range(conn.message[0..<PAYLOAD_BYTES], 0, writer.at))
    process(conn)
}

/** Wipe the password offered. */
wipe_password #constant_time :: fn(conn: ptr[mut Connection]) {
    for i in cast[usize](0)..<PASSWORD_BYTES {
        conn.offered_password[i] = 0
    }
    conn.offered_password_length = 0
}

/**
 * A client's: try the next method it has: its key, signed, then a password, asked of its caller.
 *
 * @param conn The connection.
 * @param password_allowed Whether the server said it takes passwords.
 */
next_method :: fn(conn: ptr[mut Connection], password_allowed: bool) {
    if conn.has_client_key && !conn.key_tried {
        conn.key_tried = true
        send_key_request(conn)
        return void
    }
    if password_allowed {
        conn.pending_password = true
        event(conn, .PasswordWanted)
        return void
    }
    event(conn, .AuthenticationRefused)
}

/** A client's: send a publickey request signed with its Ed25519 key. */
send_key_request :: fn(conn: ptr[mut Connection]) {
    public :: crypto.ed25519_public_key(&conn.client_key)
    blob :: ed25519_blob(&public)
    // The request, after its number, and what's signed: the session's identifier, then the request with its number
    request : u8[256]
    writer := Writer.{}
    put_string(request[0..<256], &writer, user_of(conn))
    put_text(request[0..<256], &writer, "ssh-connection")
    put_text(request[0..<256], &writer, "publickey")
    put_bool(request[0..<256], &writer, true)
    put_text(request[0..<256], &writer, "ssh-ed25519")
    put_string(request[0..<256], &writer, blob[0..<ED25519_BLOB_BYTES])
    signed := Writer.{}
    data :: conn.message[0..<PAYLOAD_BYTES]
    put_string(data, &signed, conn.session_id[0..<32])
    put_u8(data, &signed, MSG_USERAUTH_REQUEST)
    put_bytes(data, &signed, range(request[0..<256], 0, writer.at))
    signature :: ed25519_signature(&conn.client_key, range(data, 0, signed.at))
    out := Writer.{}
    put_u8(data, &out, MSG_USERAUTH_REQUEST)
    put_bytes(data, &out, range(request[0..<256], 0, writer.at))
    put_string(data, &out, signature[0..<ED25519_SIGNATURE_BYTES])
    send_message(conn, range(data, 0, out.at))
}

/**
 * A client's answer to PasswordWanted: the password sent.
 *
 * @param conn The connection, its PasswordWanted event taken.
 * @param password The password, wiped from the message once it's sealed.
 */
give_password #constant_time :: fn(conn: ptr[mut Connection], password: crypto.SecretByte[]) {
    if !conn.pending_password || password.count > PASSWORD_BYTES {
        return void
    }
    conn.pending_password = false
    writer := Writer.{}
    data :: conn.message[0..<PAYLOAD_BYTES]
    put_u8(data, &writer, MSG_USERAUTH_REQUEST)
    put_string(data, &writer, user_of(conn))
    put_text(data, &writer, "ssh-connection")
    put_text(data, &writer, "password")
    put_bool(data, &writer, false)
    put_u32(data, &writer, cast[u32](password.count))
    for byte in password {
        // Sealed into the packet at once, and wiped from here
        put_u8(data, &writer, compiler.declassify(cast[u8](byte)))
    }
    send_message(conn, range(data, 0, writer.at))
    for i in cast[usize](0)..<writer.at {
        if i < data.count {
            data[i] = 0
        }
    }
}

/**
 * SSH (RFC 4251 to 4254): the transport, its key exchange and ciphers; user authentication; and the connection
 * protocol's channels; both the client's side and the server's. A connection is a state machine its caller feeds what
 * arrives (received), takes what to send from (output, sent), asks what's happened (take_event) and answers, as
 * std/tls's is; nothing in it waits, or makes a system call, so it runs in memory for tests and over any stream.
 *
 * What it speaks: key exchange by mlkem768x25519-sha256, ML-KEM-768 with X25519, or curve25519-sha256 (RFC 8731), with
 * OpenSSH's strict key exchange against Terrapin; ssh-ed25519 host keys (RFC 8709); chacha20-poly1305@openssh.com and
 * aes256-gcm@openssh.com; users' keys ssh-ed25519, ecdsa-sha2-nistp256 and rsa-sha2-256 and -512 (RFC 8332), and
 * passwords; session channels, with pty-req, shell, exec, subsystem, window-change, signal and exit-status. Also
 * OpenSSH's key formats: public key lines as authorized_keys has them, unencrypted openssh-key-v1 private keys, and
 * SHA256 fingerprints.
 *
 * Freestanding: its caller gives every buffer, and its randomness comes from context.random.
 */
package ssh

import tiers from "std"

/** The package's tier, Freestanding: it needs only base, and allocates nothing. */
PACKAGE_TIER :: tiers.Tier.Freestanding

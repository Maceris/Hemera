/*
 * std/crypto's X25519 and Ed25519 against values from Python's cryptography package: RFC 7748's and
 * RFC 8032's inputs and more. X25519 keys agree from both sides, refuse low-order points and take u mod p
 * with its top bit dropped. Ed25519 signatures match, verify, and are refused for a changed message, key
 * or signature, an S that isn't below L, and a public key whose y isn't below p. P-256's public keys,
 * ECDSA signatures (RFC 6979's) and ECDH, with bad keys and points refused.
 */
package curves_test

import compiler from "base"
import crypto from "std"
import testing from "std"

// hex's bytes into into, how many there were
decode :: fn(hex: string, into: ptr[mut u8[1024]]) -> usize {
    for c, j in hex {
        nibble := cast[u8](c) - cast[u8]('0')
        if c >= 'a' {
            nibble = cast[u8](c) - cast[u8]('a') + 10
        }
        into[(j / 2) % 1024] = into[(j / 2) % 1024] * 16 + nibble
    }
    return (hex.count / 2) % 1025
}

bytes32 :: fn(hex: string) -> u8[32] {
    bytes : u8[1024]
    _ = decode(hex, &bytes)
    result : u8[32]
    for i in 0..<32 {
        result[i] = bytes[i]
    }
    return result
}

// Whether two public byte arrays are the same
same_public :: fn(a: u8[32], b: u8[32]) -> bool {
    for i in 0..<32 {
        if a[i] != b[i] {
            return false
        }
    }
    return true
}

// The secret matches expected
same #constant_time :: fn(secret: crypto.SecretByte[32], expected: u8[32]) -> bool {
    return crypto.equal(secret, expected)
}

// X25519 of secret and u is expected
check_x25519 :: fn(secret_hex: string, u_hex: string, expected_hex: string) -> bool {
    secret := cast[crypto.X25519SecretKey](bytes32(secret_hex))
    public := cast[crypto.X25519PublicKey](bytes32(u_hex))
    shared : crypto.SecretByte[32]
    return crypto.x25519(&secret, &public, &shared) && same(shared, bytes32(expected_hex))
}

// Both public keys are expected, and both sides get the same, expected, shared secret
check_pair :: fn(a_hex: string, b_hex: string, a_public_hex: string, b_public_hex: string, shared_hex: string) -> bool {
    a := cast[crypto.X25519SecretKey](bytes32(a_hex))
    b := cast[crypto.X25519SecretKey](bytes32(b_hex))
    a_public := crypto.x25519_public_key(&a)
    b_public := crypto.x25519_public_key(&b)
    if !same_public(cast[u8[32]](a_public), bytes32(a_public_hex)) || !same_public(cast[u8[32]](b_public), bytes32(b_public_hex)) {
        return false
    }
    a_shared : crypto.SecretByte[32]
    b_shared : crypto.SecretByte[32]
    return crypto.x25519(&a, &b_public, &a_shared) && crypto.x25519(&b, &a_public, &b_shared) &&
        same(a_shared, bytes32(shared_hex)) && same(b_shared, bytes32(shared_hex))
}

// A low-order point is refused, and leaves zeros
check_low_order :: fn(u_hex: string) -> bool {
    secret := cast[crypto.X25519SecretKey](bytes32("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a"))
    public := cast[crypto.X25519PublicKey](bytes32(u_hex))
    shared : crypto.SecretByte[32]
    return !crypto.x25519(&secret, &public, &shared) && same(shared, u8.[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
}

/** What went wrong signing with a key, or that nothing did. */
Signing :: enum {
    /** Everything held. */
    GOOD,
    /** The public key, alone or in a key pair, wasn't what was expected. */
    WRONG_PUBLIC_KEY,
    /** The signature, by the secret key or the key pair, wasn't what was expected. */
    WRONG_SIGNATURE,
    /** The signature didn't verify. */
    REFUSED,
    /** It verified for a changed message. */
    CHANGED_MESSAGE_VERIFIED,
    /** It verified with R changed. */
    CHANGED_R_VERIFIED,
    /** It verified with S changed. */
    CHANGED_S_VERIFIED,
    /** It verified with the public key changed. */
    CHANGED_KEY_VERIFIED,
}

/**
 * Check signing with a key: the public key and signature are expected, the signature verifies, and a flipped bit in
 * the message, the signature's R or S, or the public key is refused.
 *
 * @param secret_hex The secret key, 32 bytes in hex.
 * @param message_hex The message in hex, up to 1024 bytes; empty for none.
 * @param public_hex The public key expected, 32 bytes in hex.
 * @param signature_hex The signature expected, 64 bytes in hex.
 * @return GOOD if everything held; otherwise the first thing that didn't.
 */
check_ed25519 :: fn(secret_hex: string, message_hex: string, public_hex: string, signature_hex: string) -> Signing {
    secret := cast[crypto.Ed25519SecretKey](bytes32(secret_hex))
    message : u8[1024]
    message_count := decode(message_hex, &message) % 1025
    expected_signature : u8[1024]
    _ = decode(signature_hex, &expected_signature)
    public := crypto.ed25519_public_key(&secret)
    if !same_public(cast[u8[32]](public), bytes32(public_hex)) {
        return .WRONG_PUBLIC_KEY
    }
    signature := crypto.ed25519_sign(&secret, message[0..<message_count])
    for i in 0..<64 {
        if signature[i] != expected_signature[i] {
            return .WRONG_SIGNATURE
        }
    }
    if !crypto.ed25519_verify(&public, message[0..<message_count], &signature) {
        return .REFUSED
    }
    // A key pair has the same public key, and signs the same
    pair := crypto.ed25519_key_pair(&secret)
    if !same_public(cast[u8[32]](pair.public_key), bytes32(public_hex)) {
        return .WRONG_PUBLIC_KEY
    }
    signed_with := crypto.ed25519_sign_with(&pair, message[0..<message_count])
    for i in 0..<64 {
        if signed_with[i] != expected_signature[i] {
            return .WRONG_SIGNATURE
        }
    }
    if message_count > 0 {
        message[0] = message[0] ~ 1
        if crypto.ed25519_verify(&public, message[0..<message_count], &signature) {
            return .CHANGED_MESSAGE_VERIFIED
        }
        message[0] = message[0] ~ 1
    }
    signature[5] = signature[5] ~ 4
    if crypto.ed25519_verify(&public, message[0..<message_count], &signature) {
        return .CHANGED_R_VERIFIED
    }
    signature[5] = signature[5] ~ 4
    signature[40] = signature[40] ~ 1
    if crypto.ed25519_verify(&public, message[0..<message_count], &signature) {
        return .CHANGED_S_VERIFIED
    }
    signature[40] = signature[40] ~ 1
    public[0] = public[0] ~ 2
    if crypto.ed25519_verify(&public, message[0..<message_count], &signature) {
        return .CHANGED_KEY_VERIFIED
    }
    return .GOOD
}

// A signature that would verify is refused anyway: S + L for S, or a public key's y + p for y
check_refused :: fn(public_hex: string, message_hex: string, signature_hex: string) -> bool {
    public := cast[crypto.Ed25519PublicKey](bytes32(public_hex))
    message : u8[1024]
    message_count := decode(message_hex, &message) % 1025
    bytes : u8[1024]
    _ = decode(signature_hex, &bytes)
    signature : crypto.Ed25519Signature
    for i in 0..<64 {
        signature[i] = bytes[i]
    }
    return !crypto.ed25519_verify(&public, message[0..<message_count], &signature)
}

agrees_with_rfc_7748s_x25519 #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect(t, check_x25519("a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4", "e6db6867583030db3582b07da55aaeb00d7a4ee0b8a9bdd78c2f1c57f9ad4e46", "bf7e105ae6c67777cd4083991633f633ba9b8f2c137778d3098db43814189c6b"),
        "RFC 7748, 5.2's first vector")
    testing.expect(t, check_x25519("4b66e9d4d1b4673c5ad22691957d6af5c11b6421e0ea01d42ca4169e7918ba0d", "e5210f12786811d3f4b7959d0538ae2c31dbe7106fc03c3efc4cd549c715a493", "95cbde9476e8907d7aade45cb4b873f88b595a68799fa152e6f8f7647aac7957"),
        "RFC 7748, 5.2's second vector")
    return .Ok
}

takes_u_mod_p #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect(t, check_x25519("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a", "f2ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f", "717efc3f25e74904ccdf9896b6eb5836e85a45b5a7a26f9e3acf91f0eb7d3f4a"),
        "u is 2^255 - 14, which is p + 5, so it's taken as 5")
    return .Ok
}

drops_us_top_bit #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect(t, check_x25519("a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4", "e6db6867583030db3582b07da55aaeb00d7a4ee0b8a9bdd78c2f1c57f9ad4ec6", "bf7e105ae6c67777cd4083991633f633ba9b8f2c137778d3098db43814189c6b"),
        "the first vector with u's top bit set gives the same as without")
    return .Ok
}

agrees_from_both_sides #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect(t, check_pair("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a", "5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb",
        "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a", "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f",
        "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742"),
        "RFC 7748, 6.1's Alice and Bob")
    testing.expect(t, check_pair("01080f161d242b323940474e555c636a71787f868d949ba2a9b0b7bec5ccd3da", "c8d5e2effc091623303d4a5764717e8b98a5b2bfccd9e6f3000d1a2734414e5b",
        "c8feca81be196cdf2cadeabf13c4903d7632dce4955aa68b6e5d9adef54e2616", "114c732a1716f9e3cd4ce3e5d6f5b56cfef6ad8289c6c5029141797fab24cb2c",
        "a01bfd88194879358fc7584d28d24b071d866d2bf584f3041348f65dc4cbc560"),
        "a pair from Python's cryptography")
    testing.expect(t, check_pair("040c141c242c343c444c545c646c747c848c949ca4acb4bcc4ccd4dce4ecf4fc", "c9d8e7f60514233241505f6e7d8c9baab9c8d7e6f504132231404f5e6d7c8b9a",
        "b9f5306fbfc3b94808c126a1ceeac5f671a18a388172fbca2a275d1314ae5307", "ed90e7856a20ad4b3a943191be56016937b4e64b9f188f121836c74af4cee151",
        "41efd3cc4d45f2d2a79e0c67b66afa0f6b030c6c9e06dd6acebbda541a85b121"),
        "another pair from Python's cryptography")
    testing.expect(t, check_pair("071019222b343d464f58616a737c858e97a0a9b2bbc4cdd6dfe8f1fa030c151e", "cadbecfd0e1f30415263748596a7b8c9daebfc0d1e2f405162738495a6b7c8d9",
        "0c3988c2a4ff9f62cb5f8fdcfc1b827a3332a00f64380298d6fc0a2f02f97438", "192cc13778a2bc84460d6d6b3f466d8506237664ecc122b3ea57b4abfe766512",
        "11ee466f2d64298fced2fb8d6cd823da895a700c3d860dcc485da9c379c7eb44"),
        "a third pair from Python's cryptography")
    return .Ok
}

refuses_low_order_points #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect(t, check_low_order("0000000000000000000000000000000000000000000000000000000000000000"),
        "0 is of order 1: refused, leaving zeros")
    testing.expect(t, check_low_order("0100000000000000000000000000000000000000000000000000000000000000"),
        "1 is of order 4: refused, leaving zeros")
    testing.expect(t, check_low_order("e0eb7a7c3b41b8ae1656e3faf19fc46ada098deb9c32b1fd866205165f49b800"),
        "a point of order 8: refused, leaving zeros")
    testing.expect(t, check_low_order("ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f"),
        "p - 1 is of order 2: refused, leaving zeros")
    testing.expect(t, check_low_order("edffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f"),
        "p, which is 0 mod p: refused, leaving zeros")
    return .Ok
}

signs_as_rfc_8032_does #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    case_13 :: check_ed25519("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60", "",
        "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a", "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b")
    testing.expect_eq(t, case_13, Signing.GOOD, "RFC 8032, 7.1's TEST 1: an empty message")
    case_14 :: check_ed25519("4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb", "72",
        "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c", "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00")
    testing.expect_eq(t, case_14, Signing.GOOD, "RFC 8032, 7.1's TEST 2: one byte")
    case_15 :: check_ed25519("c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7", "af82",
        "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025", "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a")
    testing.expect_eq(t, case_15, Signing.GOOD, "RFC 8032, 7.1's TEST 3: two bytes")
    case_16 :: check_ed25519("833fe62409237b9d62ec77587520911e9a759cec1d19755b7da901b96dca3d42", "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
        "ec172b93ad5e563bf4932c70e1245034c35467ef2efd4d64ebf819683467e2bf", "dc2a4459e7369633a52b1bf277839a00201009a3efbf3ecb69bea2186c26b58909351fc9ac90b3ecfdfbc7c66431e0303dca179c138ac17ad9bef1177331a704")
    testing.expect_eq(t, case_16, Signing.GOOD, "RFC 8032, 7.1's TEST SHA(abc): 64 bytes")
    return .Ok
}

signs_as_pythons_cryptography_does #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    case_17 :: check_ed25519("09141f2a35404b56616c77828d98a3aeb9c4cfdae5f0fb06111c27323d48535e", "11",
        "4a6d5ba76cd5b47759e66d9d05fdcaa413d60706897dc4fe21289f0b38ea1909", "4910572d75b505bd836a561005ccd7639fd2a3013e05bf75760b1d0234848518c356e8a2fa762fe4abe9963fa5726dc1cd313a1f3b43f327c05e866065d6620d")
    testing.expect_eq(t, case_17, Signing.GOOD, "one byte, from Python's cryptography")
    case_18 :: check_ed25519("0e1a26323e4a56626e7a86929eaab6c2cedae6f2fe0a16222e3a46525e6a7682", "1115191d2125292d3135393d4145494d5155595d6165696d7175797d8185898d9195999da1a5a9adb1b5b9bdc1c5c9cdd1d5d9dde1e5e9edf1f5f9fd0105090d",
        "14214c755faa82c48b4e5ecabbb87456ea2374555f987b22930f7c4d07fed8f3", "74e338fa126eb1fcd7e0edf38fb0cb7225368885a9c28ba2cc2ce97239900cae1253b605ae629e460539f6a879f5fce46625f414d0e9d7a6f5390d765ffda90f")
    testing.expect_eq(t, case_18, Signing.GOOD, "64 bytes, from Python's cryptography")
    case_19 :: check_ed25519("13202d3a4754616e7b8895a2afbcc9d6e3f0fd0a1724313e4b5865727f8c99a6", "11161b20252a2f34393e43484d52575c61666b70757a7f84898e93989da2a7acb1b6bbc0c5cacfd4d9dee3e8edf2f7fc01060b10151a1f24292e33383d42474c51565b60656a6f74797e83888d92979ca1a6abb0b5babfc4c9ced3d8dde2e7ecf1f6fb00050a0f14191e23282d32373c41464b50555a5f64696e73787d8287",
        "392dded85b1b7798b6ee6f432df0be957a8358659a7f5cfdebe1af0ccc744b11", "ee6f4bdb1d8e42f94a764242a6c3f5c88fd26ab8eee1ad4f65e1e62051a1bdfa2f34aada49765741ce0fc3159bbc561fedf475885361edfb3cbc83bee3a6d201")
    testing.expect_eq(t, case_19, Signing.GOOD, "127 bytes, from Python's cryptography")
    case_20 :: check_ed25519("18263442505e6c7a8896a4b2c0cedceaf8061422303e4c5a68768492a0aebcca", "11171d23292f353b41474d53595f656b71777d83898f959ba1a7adb3b9bfc5cbd1d7dde3e9eff5fb01070d13191f252b31373d43494f555b61676d73797f858b91979da3a9afb5bbc1c7cdd3d9dfe5ebf1f7fd03090f151b21272d33393f454b51575d63696f757b81878d93999fa5abb1b7bdc3c9cfd5dbe1e7edf3f9ff050b11171d23292f353b41474d53595f656b71777d83898f959ba1a7adb3b9bfc5cbd1d7dde3e9eff5fb01070d13191f252b31373d43494f555b61676d73797f858b91979da3a9afb5bbc1c7cdd3d9dfe5ebf1f7fd03090f151b21272d33393f454b51575d63696f757b81878d93999fa5abb1b7bdc3c9cfd5dbe1e7edf3f9ff050b11171d23292f353b41474d53595f656b71777d83898f959ba1a7adb3b9bfc5cbd1d7dde3e9eff5fb01070d13191f252b31373d43494f555b61676d73797f858b91979da3a9afb5bbc1c7cdd3d9dfe5ebf1f7fd03090f151b21272d33393f454b51575d63696f757b81878d93999fa5abb1b7bdc3c9cfd5dbe1e7edf3f9ff050b11171d23292f353b41474d53595f656b71777d83898f959ba1a7adb3b9bfc5cbd1d7dde3e9eff5fb01070d13191f252b31373d43494f555b61676d73797f858b91979da3a9afb5bbc1c7cdd3d9dfe5ebf1f7fd03090f151b21272d33393f454b51575d63696f757b81878d93999fa5abb1b7bdc3c9cfd5dbe1e7edf3f9ff050b11171d23292f353b41474d53595f656b71777d83898f959ba1a7adb3b9bfc5cbd1d7dde3e9eff5fb01070d13191f252b31373d43494f555b61676d73797f858b91979da3a9afb5bbc1c7cdd3d9dfe5ebf1f7fd03090f151b21272d33393f454b51575d63696f757b81878d93999fa5abb1b7bdc3c9cfd5dbe1e7edf3f9ff050b11171d23292f353b41474d53595f656b71777d83898f959ba1a7adb3b9bfc5cbd1d7dde3e9eff5fb01070d13191f252b31373d43494f555b61676d73797f858b91979da3a9afb5bbc1c7cdd3d9dfe5ebf1f7fd03090f151b21272d33393f454b51575d63696f757b81878d93999fa5abb1b7bdc3c9cfd5dbe1e7edf3f9ff050b11171d23292f353b41474d53595f656b71777d83898f959ba1a7adb3b9bfc5cbd1d7dde3e9eff5fb01070d13191f252b31373d43494f555b61676d73797f858b91979da3a9afb5bbc1c7cdd3d9dfe5ebf1f7fd03090f151b21272d33393f454b51575d63696f757b81878d93999fa5abb1b7bdc3c9cfd5dbe1e7edf3f9ff050b11171d23292f353b41474d53595f656b71777d83898f959ba1a7adb3b9bfc5cbd1d7dde3e9eff5fb01070d13191f252b31373d43494f555b61676d73797f858b91979da3a9afb5bbc1c7cdd3d9dfe5ebf1f7fd03090f151b21272d33393f454b51575d63696f757b",
        "64417ca150d9b49cbeaecd03baeb5e0a9fa9753cd24421759204e6d1a8d82b38", "ff4ea1c1752545ff5c9db8242a52853b632487f773e2ffd38c3a28fb308fb1ca7703126e91edab2f594fa5dcd8f8e47237c8a8b2a4502a2a260e5a93fda8b00f")
    testing.expect_eq(t, case_20, Signing.GOOD, "1000 bytes, from Python's cryptography")
    return .Ok
}

refuses_an_s_not_below_l #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect(t, check_refused("3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c", "72",
        "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69daf52db7415978abc61b2c2eb6aeebfca0387b2eaeb4302aeeb00d291612bb0c10"),
        "TEST 2's signature with S + L for S verifies but for being reduced")
    return .Ok
}

refuses_a_public_key_whose_y_isnt_below_p #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect(t, check_refused("eeffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f", "",
        "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
        "y is p + 1, which reduced would be 1, the neutral point's y")
    return .Ok
}

bytes_of :: fn(hex: string, into: ptr[mut u8[1024]]) -> u8[] {
    for i in 0..<1024 {
        into[i] = 0
    }
    count := decode(hex, into)
    if count > 1024 {
        count = 1024
    }
    return into[0..<count]
}

same_bytes :: fn(a: u8[], b: u8[]) -> bool {
    if a.count != b.count {
        return false
    }
    for byte, i in a {
        if byte != b[i] {
            return false
        }
    }
    return true
}

// RFC 6979's P-256 key (section A.2.5)
P256_RFC6979_KEY :: "c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721"
P256_RFC6979_PUBLIC :: "0460fed4ba255a9d31c961eb74c6356d68c049b8923b61fa6ce669622e60f29fb67903fe1008b8bc99a41ae9e95628bc64f2f1b20c2d7e9f5177a3c294d4462299"

// RFC 6979's signatures with that key, of "sample" and "test" with SHA-256
P256_RFC6979_SIGNATURES :: string.[
    "efd48b2aacb6a8fd1140dd9cd45e81d69d2c877b56aaf991c34d0ea84eaf3716f7cb1c942d657c41d436c7a1b6e29f65f3e900dbb9aff4064dc4ab2f843acda8",
    "f1abb023518351cd71d881567b1ea663ed3efcf6c5132b354f28d3b0b7d38367019f4113742a2b14bd25926b49c649155f267e60d3814b4c0cc84250e46f0083",
]

p256_key #constant_time :: fn(hex: string) -> crypto.P256SecretKey {
    return compiler.secret(cast[crypto.P256SecretKey](bytes32(hex)))
}

derives_p256_public_keys #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    buffer : u8[1024]
    secret := p256_key(P256_RFC6979_KEY)
    public : crypto.P256PublicKey
    testing.expect(t, crypto.p256_public_key(&secret, &public), "a key from 1 to n - 1 is taken")
    testing.expect(t, same_bytes(public[0..<65], bytes_of(P256_RFC6979_PUBLIC, &buffer)), "its public key is RFC 6979's")
    zero := p256_key("0000000000000000000000000000000000000000000000000000000000000000")
    order := p256_key("ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551")
    testing.expect(t, !crypto.p256_public_key(&zero, &public), "0 isn't a secret key")
    testing.expect(t, !crypto.p256_public_key(&order, &public), "n isn't either")
    return .Ok
}

signs_with_p256_as_rfc_6979_does #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    buffer : u8[1024]
    secret := p256_key(P256_RFC6979_KEY)
    public := bytes_of(P256_RFC6979_PUBLIC, &buffer)
    expected := u8.[0]
    for message, i in string.["sample", "test"] {
        digest := crypto.sha256(bit_cast[u8[]](message))
        none : crypto.P256Signature
        maybe := crypto.p256_ecdsa_sign(&secret, digest, crypto.as_secret(expected[0..<0]))
        testing.expect(t, maybe != null, "a good key signs")
        signature := maybe or_else none
        other : u8[1024]
        wanted := bytes_of(P256_RFC6979_SIGNATURES[i % 2], &other)
        testing.expect(t, same_bytes(signature[0..<64], wanted), "the signature is RFC 6979's, its nonce from the key and digest")
        testing.expect(t, crypto.p256_ecdsa_verify(public, digest, &signature), "and verifies")
        digest[0] = digest[0] ~ 1
        testing.expect(t, !crypto.p256_ecdsa_verify(public, digest, &signature), "but not for another digest")
    }
    return .Ok
}

signs_with_p256_and_random_bytes #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    buffer : u8[1024]
    secret := p256_key(P256_RFC6979_KEY)
    public := bytes_of(P256_RFC6979_PUBLIC, &buffer)
    digest := crypto.sha256(bit_cast[u8[]]("sample"))
    random := u8.[1, 2, 3, 4, 5, 6, 7, 8]
    none : crypto.P256Signature
    signature := crypto.p256_ecdsa_sign(&secret, digest, crypto.as_secret(random)) or_else none
    plain := crypto.p256_ecdsa_sign(&secret, digest, crypto.as_secret(random[0..<0])) or_else none
    testing.expect(t, crypto.p256_ecdsa_verify(public, digest, &signature), "a signature with random bytes mixed in verifies")
    testing.expect(t, !same_bytes(signature[0..<64], plain[0..<64]), "and its nonce isn't RFC 6979's alone")
    signature[40] = signature[40] ~ 0x10
    testing.expect(t, !crypto.p256_ecdsa_verify(public, digest, &signature), "a changed s is refused")
    return .Ok
}

agrees_on_p256_shared_secrets #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    a := p256_key(P256_RFC6979_KEY)
    b := p256_key("0612465c89a023ab17855b0a6bcebfd3febb53aef84138647b5352e02c10c346")
    a_public : crypto.P256PublicKey
    b_public : crypto.P256PublicKey
    _ = crypto.p256_public_key(&a, &a_public)
    _ = crypto.p256_public_key(&b, &b_public)
    a_shared : crypto.SecretByte[32]
    b_shared : crypto.SecretByte[32]
    testing.expect(t, crypto.p256_ecdh(&a, b_public[0..<65], &a_shared) && crypto.p256_ecdh(&b, a_public[0..<65], &b_shared), "both sides agree")
    plain : u8[32]
    for i in 0..<32 {
        plain[i] = compiler.declassify(b_shared[i])
    }
    testing.expect(t, crypto.equal(a_shared, plain), "on the same secret")
    a_public[64] = a_public[64] ~ 1
    testing.expect(t, !crypto.p256_ecdh(&b, a_public[0..<65], &b_shared), "a point off the curve is refused")
    return .Ok
}

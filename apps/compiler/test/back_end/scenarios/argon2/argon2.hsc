/*
 * std/crypto's Argon2id against RFC 9106's test vector, with its secret key and associated data, and
 * values from Python's argon2-cffi: the smallest memory, several lanes, memory that isn't a multiple of
 * 4 a lane, hashes from 4 to 1024 bytes, and 2 MiB, past one block of addresses. Bad parameters are
 * refused. main returns 42 if they all worked.
 */
package argon2_test

import compiler from "base"
import runtime from "base"
import crypto from "std"

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

// Argon2id of the inputs is expected
check #constant_time :: fn(password_hex: string, salt_hex: string, key_hex: string, associated_hex: string,
    memory_kib: u32, passes: u32, lanes: u32, expected_hex: string) -> bool {

    password : u8[1024]
    password_count := decode(password_hex, &password) % 1025
    salt : u8[1024]
    salt_count := decode(salt_hex, &salt) % 1025
    key : u8[1024]
    key_count := decode(key_hex, &key) % 1025
    associated : u8[1024]
    associated_count := decode(associated_hex, &associated) % 1025
    expected : u8[1024]
    expected_count := decode(expected_hex, &expected) % 1025
    parameters := crypto.Argon2Parameters.{memory_kib = memory_kib, passes = passes, lanes = lanes}
    blocks, error := runtime.new_array(crypto.Argon2Block, crypto.argon2_blocks_needed(parameters))
    if error != null {
        return false
    }
    hash : crypto.SecretByte[1024]
    if !crypto.argon2id_keyed(crypto.as_secret(password[0..<password_count]), salt[0..<salt_count],
        crypto.as_secret(key[0..<key_count]), associated[0..<associated_count], parameters, blocks, hash[0..<expected_count]) {

        return false
    }
    return crypto.equal(hash[0..<expected_count], expected[0..<expected_count])
}

// Parameters that aren't allowed, and too few blocks, are refused
refused :: fn() -> bool {
    blocks : crypto.Argon2Block[8]
    hash : crypto.SecretByte[32]
    salt := u8.[1, 2, 3, 4, 5, 6, 7, 8]
    password := crypto.as_secret(u8.[1])
    good := crypto.Argon2Parameters.{memory_kib = 8, passes = 1, lanes = 1}
    if !crypto.argon2id(password, salt, good, blocks, hash) {
        return false
    }
    return !crypto.argon2id(password, salt[0..<7], good, blocks, hash)
        && !crypto.argon2id(password, salt, good, blocks, hash[0..<3])
        && !crypto.argon2id(password, salt, crypto.Argon2Parameters.{memory_kib = 8, passes = 0, lanes = 1}, blocks, hash)
        && !crypto.argon2id(password, salt, crypto.Argon2Parameters.{memory_kib = 8, passes = 1, lanes = 0}, blocks, hash)
        && !crypto.argon2id(password, salt, crypto.Argon2Parameters.{memory_kib = 15, passes = 1, lanes = 2}, blocks, hash)
        && !crypto.argon2id(password, salt, crypto.Argon2Parameters.{memory_kib = 16, passes = 1, lanes = 1}, blocks, hash)
}

main :: fn() -> int {
    failures := 0
    // RFC 9106, 5.3
    if !check("0101010101010101010101010101010101010101010101010101010101010101", "02020202020202020202020202020202",
        "0303030303030303", "040404040404040404040404", 32, 3, 4,
        "0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659") {
        failures += 1
    }
    if !check("70617373776f7264", "736f6d6573616c74", "", "", 8, 1, 1,
        "f137f8e186a403a679ccd0606e5ab5dcdafe43c1640855ac8c6e33e9bd63eeb3") {
        failures += 1
    }
    if !check("0104070a0d101316191c1f2225282b2e3134373a", "02070c11161b20252a2f34393e43484d", "", "", 64, 2, 2,
        "b48e16a5a7a03a404d9cd809af62292d74d651792ee5eb3d71318db4447a5d2474951f881c6769fc9d9918bddfc9fc27766af87455d13314e52c9292cf024935") {
        failures += 1
    }
    if !check("07", "090a0b0c0d0e0f10", "", "", 37, 1, 2,
        "8a1ac3563f93cd4fe4cdb74e4d52214c80a98310d9cda52974b4bcc5ddf81e14") {
        failures += 1
    }
    if !check("030a11181f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ff060d141b222930373e454c535a61686f767d848b9299a0a7aeb5bc", "05101b26313c47525d68737e89949faab5c0cbd6e1ecf7020d18232e39444f5a", "", "", 16, 3, 1,
        "9c842037") {
        failures += 1
    }
    if !check("010e1b2835424f5c697683909daab7c4d1deebf805121f2c394653606d7a8794a1", "0306090c0f1215181b1e2124272a2d30", "", "", 32, 1, 4,
        "ae886f9de93908da80908d701c9665c7ee7f45accd4e0f42cb2e21b2a42fe1806763403817f91f78c7fd0abbbb9b1a559ef76b2e1a27b6c95e1c5ea300a3fb754be479d7146d37d348db9db9564ae69093337bde23736aa402715314b2b5f145f58ffb98") {
        failures += 1
    }
    if !check("", "01030507090b0d0f", "", "", 8, 1, 1,
        "fcd706ff756353639534bc96c5d553d2fca02d42f2bedfdaab2fbf28952b1a4fa220b3fb85fdf079ca1583030852bcedd12aea0c594c4993bf2cd922aa988095e40fc592404aa8fdf5c2f65ed7378b63829f37d220e9642e341f6e65117c4a66d067ec094a910a36b7a1735cbc971f1a53a1a36fbdf5dcde1aee3277e93bde3209b8f349998949ac1aadc94becc4fae465bb82375d934b94b8a72d0f4bfa74774fd7b09ff93a2fe3b24e50c91a9d13ea2e5c5abd7f5e02c68c0e48c55246f05cd021e77cf8ff4babf510ca2d983405fcd152c21c9712d9224b1b842978dd8f8c6b96c8fcc929bafdc75a75bad09e5b528dc3a9777ec2868b4ec2055efce3d5a16683921eb260285ec7793066fabe9b420b336348889f41fed3a0c8747d5c3f2aab24da91e1a2a890a60b3972bcdc4afbf726fc516996414bb78c12738793ffa41c54b1f0feeeb6906ed7c1ced780f33beb09b7391d3105d5f7bbe5d01c74c4fca0c5ee17e4a29f334bee2afdd19c994ae355bab60d48b39cabcd14f16ef7127a24e2028d6bb5f28fbbc0f840c8405d754658a9bc6c487f24e11a05379ec86abd5f09e0eb7f4dac1370631a4e6f0193bf0301fa599ac80acc82c57f356a180fe05eec4ad960984859566b90bc51e3a26eb18eb57b0949fdc3c120080b0d57abe78953b24d6ca7ac5107f654305821c6138b7873d508aadae6556ff2ef0ff3427e6edd2ef93d0c37b1dd9edd3fbfb77b2fb141906415f56eba6ec3eec887286fcb6eff47f119f4212dac916d31ba251fc9b6ec6e6667cd6a00ea75d0b11852c454f749822b7f034381747af962ba5600d41d76e058773fed98201b2528c373a1a54c823000d07e8f2f1326052463c9568cd66d326ba492348f525138faf3176716769a230a4e8719415dc255c51dd3d46b25c51fe38ebac22d703b25b37153c3a4627de37cc45f0fd5d30540c51bb033ba958f62f9780ed1fd0611f6e3676e34af205209b90adf9212f04fd18abc9d13776a455567d8c66bef376f22444f40c255440d986f587bce6218ab3782ace315a553cdc17bc9c015f1990ae169cae18cdc10feedb700e28b099a44097bc13233ee27500b75c478d919329daf902212975073eab3d7d759febecfdba8190827da3106d57d8c74189a38bca2a1a7564110e891725a57a656e01f455da87d239ddb5269d86f5a0bc30dd1345f8a6579e8f841bc9bf07955bbef8f04446082b921e3b80890ab3cb8e5515bbf913d8df3d6f301d7585e16044029df5c7d3890a471782fbb76f3258401830552dedbd861f3d2ac11687c4d4d7de35c78bb3be0e74c2f3ae115c80766a6c7ae031aea1929b240f9e2c247c21d0f8664b4f428e0e8ef043f3c768d6af818e88001a9cbb94d71efd4644c643acff30fa0b4f95c607b9f0e00f8976e35529dcf006200175bb6c4cd76") {
        failures += 1
    }
    if !check("09121b242d363f48515a636c", "0102030405060708090a0b0c0d0e0f10", "", "", 2048, 2, 3,
        "4dffd96a0f26b9a1f574506ef50e196f1cf3808e9ddedc5317bedebc3cf5aefb") {
        failures += 1
    }
    if !refused() {
        failures += 1
    }
    if failures == 0 {
        return 42
    }
    return failures
}

/*
 * std/crypto's hashes (docs/memory.md, Secrets): SHA-256 and SHA-512 (FIPS 180-4), HMAC (RFC 4231's
 * cases), HKDF (RFC 5869's first case, and one with SHA-512), BLAKE2b (RFC 7693) and BLAKE3, keyed and
 * not, over empty, short, block-sized and longer messages, across BLAKE3's chunks and tree, in one go and
 * in parts, against values worked out by Python's hashlib and hmac and the blake3 package. main returns 42 if they all matched.
 */
package hashes_test

import compiler from "base"
import runtime from "base"
import crypto from "std"

bytes :: fn(text: string) -> u8[] {
    return bit_cast[u8[]](text)
}

// The first count bytes of 0, 1, ..., 250, 0, 1, ...
pattern :: fn(count: usize, buffer: ptr[mut u8[1000]]) -> u8[] {
    for i in 0..<1000 {
        buffer[i] = cast[u8](i % 251)
    }
    return buffer[0..<count % 1001]
}

repeat #constant_time :: fn(byte: u8, count: usize, key: ptr[mut crypto.SecretByte[200]]) -> crypto.SecretByte[] {
    for i in 0..<200 {
        key[i] = cast[crypto.SecretByte](byte)
    }
    return key[0..<count % 201]
}

counting :: fn(first: u8, count: usize, salt: ptr[mut u8[200]]) -> u8[] {
    for i in 0..<200 {
        salt[i] = first + cast[u8](i)
    }
    return salt[0..<count % 201]
}

// A secret, now that it's been worked out, to compare
public #constant_time :: fn(into: ptr[mut u8[200]], secret: crypto.SecretByte[]) -> u8[] {
    for i in 0..<secret.count {
        if i < 200 {
            into[i] = compiler.declassify(secret[i])
        }
    }
    return into[0..<secret.count % 201]
}

hex :: fn(digest: u8[], expected: string) -> bool {
    if expected.count != digest.count * 2 || digest.count > 200 {
        return false
    }
    decoded : u8[200]
    for c, j in expected {
        nibble := cast[u8](c) - cast[u8]('0')
        if c >= 'a' {
            nibble = cast[u8](c) - cast[u8]('a') + 10
        }
        decoded[(j / 2) % 200] = decoded[(j / 2) % 200] * 16 + nibble
    }
    for byte, i in digest {
        if byte != decoded[i % 200] {
            return false
        }
    }
    return true
}

expand256 #constant_time :: fn(length: usize, output: ptr[mut crypto.SecretByte[200]]) -> crypto.SecretByte[] {
    key : crypto.SecretByte[200]
    salt : u8[200]
    pseudo_random := crypto.hkdf_sha256_extract(counting(0, 13, &salt), repeat(0x0b, 22, &key))
    if !crypto.hkdf_sha256_expand(pseudo_random, counting(0xf0, 10, &salt), output[0..<length % 201]) {
        return output[0..<0]
    }
    return output[0..<length % 201]
}

expand512 #constant_time :: fn(length: usize, output: ptr[mut crypto.SecretByte[200]]) -> crypto.SecretByte[] {
    key : crypto.SecretByte[200]
    salt : u8[200]
    pseudo_random := crypto.hkdf_sha512_extract(counting(0, 13, &salt), repeat(0x0b, 22, &key))
    if !crypto.hkdf_sha512_expand(pseudo_random, counting(0xf0, 10, &salt), output[0..<length % 201]) {
        return output[0..<0]
    }
    return output[0..<length % 201]
}

blake :: fn(digest: ptr[mut u8[64]], data: u8[], size: usize) -> u8[] {
    if !crypto.blake2b(data, digest[0..<size % 65]) {
        return digest[0..<0]
    }
    return digest[0..<size % 65]
}

keyed_blake :: fn(digest: ptr[mut u8[64]], data: u8[], size: usize) -> u8[] {
    salt : u8[200]
    hasher := crypto.blake2b_start_keyed(size, crypto.as_secret(counting(0, 64, &salt))) or_return digest[0..<0]
    crypto.blake2b_update(&hasher, data)
    crypto.blake2b_finish(&hasher, digest[0..<size % 65])
    return digest[0..<size % 65]
}

// The first count bytes of 0, 1, ..., 250, 0, 1, ... up to 5000
large_pattern :: fn(count: usize, buffer: ptr[mut u8[5000]]) -> u8[] {
    for i in 0..<5000 {
        buffer[i] = cast[u8](i % 251)
    }
    return buffer[0..<count % 5001]
}

three :: fn(digest: ptr[mut u8[200]], buffer: ptr[mut u8[5000]], count: usize, size: usize) -> u8[] {
    crypto.blake3(large_pattern(count, buffer), digest[0..<size % 201])
    return digest[0..<size % 201]
}

keyed_three :: fn(digest: ptr[mut u8[200]], buffer: ptr[mut u8[5000]], count: usize, size: usize) -> u8[] {
    salt : u8[200]
    hasher := crypto.blake3_start_keyed(crypto.as_secret(counting(0, 32, &salt))) or_return digest[0..<0]
    crypto.blake3_update(&hasher, large_pattern(count, buffer))
    crypto.blake3_finish(&hasher, digest[0..<size % 201])
    return digest[0..<size % 201]
}

// BLAKE3 of 5000 bytes, given in uneven parts, some of them secret
streamed_three :: fn(digest: ptr[mut u8[200]], buffer: ptr[mut u8[5000]]) -> u8[] {
    _ = large_pattern(5000, buffer)
    hasher := crypto.blake3_start()
    crypto.blake3_update(&hasher, buffer[0..<1])
    crypto.blake3_update_secret(&hasher, crypto.as_secret(buffer[1..<1500]))
    crypto.blake3_update(&hasher, buffer[1500..<1500])
    crypto.blake3_update(&hasher, buffer[1500..<5000])
    crypto.blake3_finish(&hasher, digest[0..<32])
    return digest[0..<32]
}

/*
 * BLAKE3 of count bytes of the pattern, in two parts, the first first bytes long, with whole chunks a batch at a
 * time: eight wide only if asked and the CPU can, four otherwise.
 */
batched_three :: fn(digest: ptr[mut u8[200]], count: usize, keyed: bool, first: usize, eight: bool) -> u8[] {
    data, error := runtime.new_array(u8, count)
    if error != null {
        return digest[0..<0]
    }
    for byte, i in data {
        data[i] = cast[u8](i % 251)
    }
    salt : u8[200]
    hasher := crypto.blake3_start()
    if keyed {
        hasher = crypto.blake3_start_keyed(crypto.as_secret(counting(0, 32, &salt))) or_return digest[0..<0]
    }
    hasher.wide = eight && crypto.vectors_wide()
    split := first
    if split > data.count {
        split = data.count
    }
    crypto.blake3_update(&hasher, data[0..<split])
    crypto.blake3_update(&hasher, data[split..<data.count])
    crypto.blake3_finish(&hasher, digest[0..<32])
    return digest[0..<32]
}

// SHA-256 of the pattern, given in uneven parts, some of them secret
streamed :: fn(output: ptr[mut u8[64]]) -> u8[] {
    buffer : u8[1000]
    _ = pattern(1000, &buffer)
    hasher := crypto.sha256_start()
    crypto.sha256_update(&hasher, buffer[0..<1])
    crypto.sha256_update_secret(&hasher, crypto.as_secret(buffer[1..<70]))
    crypto.sha256_update(&hasher, buffer[70..<700])
    crypto.sha256_update(&hasher, buffer[700..<700])
    crypto.sha256_update(&hasher, buffer[700..<1000])
    digest := crypto.sha256_finish(&hasher)
    for i in 0..<32 {
        output[i] = digest[i]
    }
    return output[0..<32]
}

main :: fn() -> int {
    buffer : u8[1000]
    key : crypto.SecretByte[200]
    salt : u8[200]
    output : crypto.SecretByte[200]
    digest : u8[64]
    plain : u8[200]
    wide : u8[200]
    large : u8[5000]
    if !hex(crypto.sha256(bytes("")), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") {
        return 1
    }
    if !hex(crypto.sha256(bytes("abc")), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") {
        return 2
    }
    if !hex(crypto.sha256(pattern(1000, &buffer)), "4e4c294b331f7a2099a379bec34b9f9fc03dc46ab465d998f4d683da53487e6d") {
        return 3
    }
    if !hex(crypto.sha256(pattern(55, &buffer)), "463eb28e72f82e0a96c0a4cc53690c571281131f672aa229e0d45ae59b598b59") {
        return 4
    }
    if !hex(crypto.sha256(pattern(64, &buffer)), "fdeab9acf3710362bd2658cdc9a29e8f9c757fcf9811603a8c447cd1d9151108") {
        return 5
    }
    if !hex(crypto.sha512(bytes("")), "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e") {
        return 6
    }
    if !hex(crypto.sha512(bytes("abc")), "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f") {
        return 7
    }
    if !hex(crypto.sha512(pattern(1000, &buffer)), "5096498d96f50f9a137c4db5b8b0cd38383ad55350fb5a98805fedc31fa1262f1f0cf4d6f12d7ecd8dedd933a4c9126344fe22e937a8ad35fdeae1e876ae698b") {
        return 8
    }
    if !hex(crypto.sha512(pattern(111, &buffer)), "a1a111449b198d9b1f538bad7f3fc1022b3a5b1a5e90a0bc860de8512746cbc31599e6c834de3a3235327af0b51ff57bf7acf1974a73014d9c3953812edc7c8d") {
        return 9
    }
    if !hex(public(&plain, crypto.hmac_sha256(repeat(0x0b, 20, &key), bytes("Hi There"))), "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7") {
        return 10
    }
    if !hex(public(&plain, crypto.hmac_sha512(repeat(0x0b, 20, &key), bytes("Hi There"))), "87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cdedaa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854") {
        return 11
    }
    if !hex(public(&plain, crypto.hmac_sha256(repeat(0xaa, 131, &key), bytes("Test Using Larger Than Block-Size Key - Hash Key First"))), "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54") {
        return 12
    }
    if !hex(public(&plain, crypto.hmac_sha512(repeat(0xaa, 131, &key), bytes("Test Using Larger Than Block-Size Key - Hash Key First"))), "80b24263c7c1a3ebb71493c1dd7be8b49b46d1f41b4aeec1121b013783f8f3526b56d037e05f2598bd0fd2215d6a1e5295e64f73f63f0aec8b915a985d786598") {
        return 13
    }
    if !hex(public(&plain, crypto.hkdf_sha256_extract(counting(0, 13, &salt), repeat(0x0b, 22, &key))), "077709362c2e32df0ddc3f0dc47bba6390b6c73bb50f9c3122ec844ad7c2b3e5") {
        return 14
    }
    if !hex(public(&plain, expand256(42, &output)), "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865") {
        return 15
    }
    if !hex(public(&plain, crypto.hkdf_sha512_extract(counting(0, 13, &salt), repeat(0x0b, 22, &key))), "665799823737ded04a88e47e54a5890bb2c3d247c7a4254a8e61350723590a26c36238127d8661b88cf80ef802d57e2f7cebcf1e00e083848be19929c61b4237") {
        return 16
    }
    if !hex(public(&plain, expand512(100, &output)), "832390086cda71fb47625bb5ceb168e4c8e26a1a16ed34d9fc7fe92c1481579338da362cb8d9f925d7cbcce0dff7098769cf15959867d571c1715450cb530137be3fb62f3cf32b84feba8f1eb1b563e20d9749b8640b8264c4b69b14ad5199115e1d609c") {
        return 17
    }
    if !hex(blake(&digest, bytes(""), 64), "786a02f742015903c6c6fd852552d272912f4740e15847618a86e217f71f5419d25e1031afee585313896444934eb04b903a685b1448b755d56f701afe9be2ce") {
        return 18
    }
    if !hex(blake(&digest, bytes("abc"), 64), "ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d17d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923") {
        return 19
    }
    if !hex(blake(&digest, pattern(1000, &buffer), 64), "c11e1c0340bd7e5a1b275f1230c962fad215ecb1391486e74e31b960a2f2996381a5fad092da06841d5f26e38f6ecfeaf441acbcd1c2de61aef121e7927175f5") {
        return 20
    }
    if !hex(blake(&digest, counting(0, 128, &salt), 64), "2319e3789c47e2daa5fe807f61bec2a1a6537fa03f19ff32e87eecbfd64b7e0e8ccff439ac333b040f19b0c4ddd11a61e24ac1fe0f10a039806c5dcc0da3d115") {
        return 21
    }
    if !hex(blake(&digest, pattern(129, &buffer), 20), "a7bf25f1599102ab631e3052e8303a2c097d1a7e") {
        return 22
    }
    if !hex(keyed_blake(&digest, pattern(1000, &buffer), 32), "c3159507ea5f870ec11f0b2192472e3eed43ceab71f09c782ffd52c64601eab1") {
        return 23
    }
    if !hex(keyed_blake(&digest, bytes(""), 64), "10ebb67700b1868efb4417987acf4690ae9d972fb7a590c2f02871799aaa4786b5e996e8f0f4eb981fc214b005f42d2ff4233499391653df7aefcbc13fc51568") {
        return 24
    }
    if !hex(streamed(&digest), "4e4c294b331f7a2099a379bec34b9f9fc03dc46ab465d998f4d683da53487e6d") {
        return 25
    }
    if !hex(crypto.sha256(pattern(56, &buffer)), "da2ae4d6b36748f2a318f23e7ab1dfdf45acdc9d049bd80e59de82a60895f562") {
        return 26
    }
    if !hex(crypto.sha256(pattern(63, &buffer)), "29af2686fd53374a36b0846694cc342177e428d1647515f078784d69cdb9e488") {
        return 27
    }
    if !hex(crypto.sha512(pattern(112, &buffer)), "c5fbd731d19d2ae1180f001be72c2c1aaba1d7b094b3748880e24593b8e117a750e11c1bd867cc2f96dace8c8b74abd2d5c4f236be444e77d30d1916174070b9") {
        return 28
    }
    if !hex(crypto.sha512(pattern(115, &buffer)), "e528abd6c315eade09a981e4861f6148c9dd4f2fce0ea54cd3e9796f17033a3751fe9a223aa23cde0e051a10c2bc27c0298be97cb87c7110667a115b6d30657c") {
        return 29
    }
    if !hex(crypto.sha512(pattern(119, &buffer)), "43e497279c2ce805903a33b54b746ea92d607f7c4807986c849823b81097a9099b5896ac7cc66df3a93edc8a91b6f3971d6c7f5688daf635737760bd080e27b3") {
        return 30
    }
    if !hex(crypto.sha512(pattern(120, &buffer)), "9636708964c5ff6600510319e07bf3fcfcb1f4058fec278efb677964ba1e140c1632505452f802e99bcf09da3d456dc3868d149a0788a730e49d239ce7415145") {
        return 31
    }
    if !hex(crypto.sha512(pattern(127, &buffer)), "eab89674feaa34e27aebeeff3c0a4d70070bb872d5e9f186cf1dbbdee517b6e35724d629ff025a5b07185e911ada7e3c8acf830aa0e4f71777bd2d44f504f7f0") {
        return 32
    }
    if !hex(crypto.sha512(pattern(128, &buffer)), "1dffd5e3adb71d45d2245939665521ae001a317a03720a45732ba1900ca3b8351fc5c9b4ca513eba6f80bc7b1d1fdad4abd13491cb824d61b08d8c0e1561b3f7") {
        return 33
    }
    if !hex(crypto.sha512(pattern(240, &buffer)), "6c48466c9f6c07e4ab762c696b7eeb35cfe236fca73683e5fab873ac3489b4d2eb3d7afcce7e8165dbbf37aded3b5b0c889c0b7e0f1790a8330d8677429d91a5") {
        return 34
    }
    if !hex(three(&wide, &large, 0, 32), "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262") {
        return 35
    }
    if !hex(three(&wide, &large, 1, 32), "2d3adedff11b61f14c886e35afa036736dcd87a74d27b5c1510225d0f592e213") {
        return 36
    }
    if !hex(three(&wide, &large, 64, 32), "4eed7141ea4a5cd4b788606bd23f46e212af9cacebacdc7d1f4c6dc7f2511b98") {
        return 37
    }
    if !hex(three(&wide, &large, 65, 32), "de1e5fa0be70df6d2be8fffd0e99ceaa8eb6e8c93a63f2d8d1c30ecb6b263dee") {
        return 38
    }
    if !hex(three(&wide, &large, 1023, 32), "10108970eeda3eb932baac1428c7a2163b0e924c9a9e25b35bba72b28f70bd11") {
        return 39
    }
    if !hex(three(&wide, &large, 1024, 32), "42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7") {
        return 40
    }
    if !hex(three(&wide, &large, 1025, 32), "d00278ae47eb27b34faecf67b4fe263f82d5412916c1ffd97c8cb7fb814b8444") {
        return 41
    }
    if !hex(three(&wide, &large, 2048, 32), "e776b6028c7cd22a4d0ba182a8bf62205d2ef576467e838ed6f2529b85fba24a") {
        return 43
    }
    if !hex(three(&wide, &large, 2049, 32), "5f4d72f40d7a5f82b15ca2b2e44b1de3c2ef86c426c95c1af0b6879522563030") {
        return 44
    }
    if !hex(three(&wide, &large, 3072, 32), "b98cb0ff3623be03326b373de6b9095218513e64f1ee2edd2525c7ad1e5cffd2") {
        return 45
    }
    if !hex(three(&wide, &large, 5000, 32), "ee78d92070de3df1c57c37002abf0a6b1a6589acdeef4d8ffac7cf3d9e8f2836") {
        return 46
    }
    if !hex(three(&wide, &large, 3072, 131), "b98cb0ff3623be03326b373de6b9095218513e64f1ee2edd2525c7ad1e5cffd29a3f6b0b978d6608335c09dc94ccf682f9951cdfc501bfe47b9c9189a6fc7b404d120258506341a6d802857322fbd20d3e5dae05b95c88793fa83db1cb08e7d8008d1599b6209d78336e24839724c191b2a52a80448306e0daa84a3fdb566661a37e11") {
        return 47
    }
    if !hex(three(&wide, &large, 100, 64), "8e2eb1bba3040b8f611a1240a0e111c74b45cfc9caed10b95f6372db1c40b8b5d9c178672a4afac6663ac3e7e72a557b9f634f7a4321268e61a2afb5bdf2606e") {
        return 48
    }
    if !hex(keyed_three(&wide, &large, 5000, 32), "3742909929a310dec551d9163c279136d6506f289f75c283c5df101108cd09e5") {
        return 49
    }
    if !hex(keyed_three(&wide, &large, 0, 40), "73492b19995d71cdb1e9d74decc09809eb732f1b00bc95c27cb15f9dd4d6478f097a9b7858239644") {
        return 50
    }
    if !hex(streamed_three(&wide, &large), "ee78d92070de3df1c57c37002abf0a6b1a6589acdeef4d8ffac7cf3d9e8f2836") {
        return 51
    }
    if !hex(batched_three(&wide, 4097, false, 0, false), "9b4052b38f1c5fc8b1f9ff7ac7b27cd242487b3d890d15c96a1c25b8aa0fb995") {
        return 52
    }
    if !hex(batched_three(&wide, 4097, false, 0, true), "9b4052b38f1c5fc8b1f9ff7ac7b27cd242487b3d890d15c96a1c25b8aa0fb995") {
        return 53
    }
    if !hex(batched_three(&wide, 8193, false, 0, false), "bab6c09cb8ce8cf459261398d2e7aef35700bf488116ceb94a36d0f5f1b7bc3b") {
        return 54
    }
    if !hex(batched_three(&wide, 8193, false, 0, true), "bab6c09cb8ce8cf459261398d2e7aef35700bf488116ceb94a36d0f5f1b7bc3b") {
        return 55
    }
    if !hex(batched_three(&wide, 9216, false, 0, false), "e5ef79624045ef3e98fd23342e61d7eb965997b32928f9de591cd0d465a223fb") {
        return 56
    }
    if !hex(batched_three(&wide, 9216, false, 0, true), "e5ef79624045ef3e98fd23342e61d7eb965997b32928f9de591cd0d465a223fb") {
        return 57
    }
    if !hex(batched_three(&wide, 17409, false, 100, false), "50bc54238ac9271c9f3471f5206a04eb25d2e26b3214ed971cc55230b0d22864") {
        return 58
    }
    if !hex(batched_three(&wide, 17409, false, 100, true), "50bc54238ac9271c9f3471f5206a04eb25d2e26b3214ed971cc55230b0d22864") {
        return 59
    }
    if !hex(batched_three(&wide, 65537, false, 1024, false), "7c99f9840a73dfcb6e5bfe4ff6d1558acab7e015640790c26411818bdbe17eca") {
        return 60
    }
    if !hex(batched_three(&wide, 65537, false, 1024, true), "7c99f9840a73dfcb6e5bfe4ff6d1558acab7e015640790c26411818bdbe17eca") {
        return 61
    }
    if !hex(batched_three(&wide, 20000, true, 0, false), "07ffcc30936202a02092efceaa79bb53bbf99298ad4915f5a218f754f5d0bd12") {
        return 62
    }
    if !hex(batched_three(&wide, 20000, true, 0, true), "07ffcc30936202a02092efceaa79bb53bbf99298ad4915f5a218f754f5d0bd12") {
        return 63
    }
    if !hex(batched_three(&wide, 20000, true, 333, false), "07ffcc30936202a02092efceaa79bb53bbf99298ad4915f5a218f754f5d0bd12") {
        return 64
    }
    if !hex(batched_three(&wide, 20000, true, 333, true), "07ffcc30936202a02092efceaa79bb53bbf99298ad4915f5a218f754f5d0bd12") {
        return 65
    }
    // equal: the same, one byte off, and a different count
    tag := crypto.hmac_sha256(repeat(0x0b, 20, &key), bytes("Hi There"))
    _ = public(&plain, tag)
    if !crypto.equal(tag, plain[0..<32]) {
        return 90
    }
    plain[31] = plain[31] ~ 1
    if crypto.equal(tag, plain[0..<32]) || crypto.equal(tag, plain[0..<31]) {
        return 91
    }
    return 42
}

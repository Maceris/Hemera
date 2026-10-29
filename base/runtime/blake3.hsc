package runtime

import intrinsics from "base"

/*
 * BLAKE3-256 of public bytes, all at once, for what base names by hash (schema_hash): a plain version of std's
 * crypto.blake3, with no vectors, no keys and no secrets, which gives the same digest. std's is the one to use
 * for anything else.
 */

HASH_BLAKE3_CHUNK :: 1024
HASH_BLAKE3_CHUNK_START : u32 : 1
HASH_BLAKE3_CHUNK_END : u32 : 2
HASH_BLAKE3_PARENT : u32 : 4
HASH_BLAKE3_ROOT : u32 : 8

HASH_BLAKE3_START :: u32.[0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
HASH_BLAKE3_PERMUTATION :: usize.[2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8]

// A chaining value, kept on the stack of finished subtrees.
HashBlake3Chain :: struct {
    words : u32[8],
}

// What a compression is given: kept for the last one, which can be the root's.
HashBlake3Output :: struct {
    chain : u32[8],
    words : u32[16],
    counter : u64,
    length : u32,
    flags : u32,
}

// The BLAKE3-256 digest of data.
hash_blake3 #no_context :: fn(data: u8[]) -> u8[32] {
    chunks :: if data.count == 0 { cast[usize](1) } else { (data.count + HASH_BLAKE3_CHUNK - 1) / HASH_BLAKE3_CHUNK }
    // Enough for 2^54 chunks
    stack : HashBlake3Chain[54]
    depth : usize = 0
    last :: chunks - 1
    for chunk in cast[usize](0)..<last {
        chain := hash_blake3_chaining_value(hash_blake3_chunk(data, chunk))
        // Merged with each finished subtree its count completes
        done := chunk + 1
        loop {
            if (done & 1) != 0 || depth == 0 {
                break
            }
            depth -= 1
            chain = hash_blake3_chaining_value(hash_blake3_parent(stack[depth % 54].words, chain))
            done >>= 1
        }
        stack[depth % 54].words = chain
        depth += 1
    }
    output := hash_blake3_chunk(data, last)
    loop {
        if depth == 0 {
            break
        }
        depth -= 1
        output = hash_blake3_parent(stack[depth % 54].words, hash_blake3_chaining_value(output))
    }
    words :: hash_blake3_compress(&output, 0, HASH_BLAKE3_ROOT)
    digest : u8[32]
    for i in 0..<32 {
        digest[i] = cast[u8]((words[i / 4] >> (8 * cast[u32](i % 4))) & 0xff)
    }
    return digest
}

// A chunk's last compression, which makes its chaining value, after every block before it.
hash_blake3_chunk #no_context :: fn(data: u8[], chunk: usize) -> HashBlake3Output {
    start :: chunk * HASH_BLAKE3_CHUNK
    end :: if start + HASH_BLAKE3_CHUNK < data.count { start + HASH_BLAKE3_CHUNK } else { data.count }
    output := HashBlake3Output.{chain = HASH_BLAKE3_START, counter = cast[u64](chunk), flags = HASH_BLAKE3_CHUNK_START}
    at := start
    loop {
        length :: if end - at > 64 { cast[usize](64) } else { end - at }
        output.words = hash_blake3_words(data, at, length)
        output.length = cast[u32](length)
        if at + length >= end {
            output.flags |= HASH_BLAKE3_CHUNK_END
            return output
        }
        output.chain = hash_blake3_chaining_value(output)
        output.flags = 0
        at += length
    }
}

hash_blake3_parent #no_context :: fn(left: u32[8], right: u32[8]) -> HashBlake3Output {
    output := HashBlake3Output.{chain = HASH_BLAKE3_START, counter = 0, length = 64, flags = HASH_BLAKE3_PARENT}
    for i in 0..<8 {
        output.words[i] = left[i]
        output.words[i + 8] = right[i]
    }
    return output
}

// length bytes of data from at, as a block's words, zeros after them.
hash_blake3_words #no_context :: fn(data: u8[], at: usize, length: usize) -> u32[16] {
    words : u32[16]
    for i in cast[usize](0)..<length {
        if at + i < data.count {
            words[(i / 4) % 16] |= cast[u32](data[at + i]) << (8 * cast[u32](i % 4))
        }
    }
    return words
}

hash_blake3_chaining_value #no_context :: fn(output: HashBlake3Output) -> u32[8] {
    given := output
    words :: hash_blake3_compress(&given, given.counter, 0)
    chain : u32[8]
    for i in 0..<8 {
        chain[i] = words[i]
    }
    return chain
}

hash_blake3_mix #no_context :: fn(v: ptr[mut u32[16]], a: usize, b: usize, c: usize, d: usize, x: u32, y: u32) {
    v[a % 16] = v[a % 16] + v[b % 16] + x
    v[d % 16] = intrinsics.rotate_right(v[d % 16] ~ v[a % 16], 16)
    v[c % 16] = v[c % 16] + v[d % 16]
    v[b % 16] = intrinsics.rotate_right(v[b % 16] ~ v[c % 16], 12)
    v[a % 16] = v[a % 16] + v[b % 16] + y
    v[d % 16] = intrinsics.rotate_right(v[d % 16] ~ v[a % 16], 8)
    v[c % 16] = v[c % 16] + v[d % 16]
    v[b % 16] = intrinsics.rotate_right(v[b % 16] ~ v[c % 16], 7)
}

hash_blake3_compress #no_context :: fn(output: ptr[HashBlake3Output], counter: u64, extra_flags: u32) -> u32[16] {
    v : u32[16]
    for i in 0..<8 {
        v[i] = output.chain[i]
    }
    for i in 0..<4 {
        v[i + 8] = HASH_BLAKE3_START[i]
    }
    v[12] = cast[u32](counter)
    v[13] = cast[u32](counter >> 32)
    v[14] = output.length
    v[15] = output.flags | extra_flags
    m := output.words
    for round in 0..<7 {
        hash_blake3_mix(&v, 0, 4, 8, 12, m[0], m[1])
        hash_blake3_mix(&v, 1, 5, 9, 13, m[2], m[3])
        hash_blake3_mix(&v, 2, 6, 10, 14, m[4], m[5])
        hash_blake3_mix(&v, 3, 7, 11, 15, m[6], m[7])
        hash_blake3_mix(&v, 0, 5, 10, 15, m[8], m[9])
        hash_blake3_mix(&v, 1, 6, 11, 12, m[10], m[11])
        hash_blake3_mix(&v, 2, 7, 8, 13, m[12], m[13])
        hash_blake3_mix(&v, 3, 4, 9, 14, m[14], m[15])
        permuted : u32[16]
        for i in 0..<16 {
            permuted[i] = m[HASH_BLAKE3_PERMUTATION[i] % 16]
        }
        m = permuted
    }
    for i in 0..<8 {
        v[i] = v[i] ~ v[i + 8]
        v[i + 8] = v[i + 8] ~ output.chain[i]
    }
    return v
}

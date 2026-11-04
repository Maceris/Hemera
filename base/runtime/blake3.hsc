package runtime

import intrinsics from "base"

/*
 * BLAKE3-256 of public bytes, all at once, for what base names by hash (schema_hash): a plain version of std's
 * crypto.blake3, with no vectors, no keys and no secrets, which gives the same digest. std's is the one to use
 * for anything else.
 */

/** The size in bytes of a BLAKE3 chunk, the leaves of its tree: 16 blocks of 64 bytes. */
HASH_BLAKE3_CHUNK :: 1024
/** The compression flag for a chunk's first block. */
HASH_BLAKE3_CHUNK_START : u32 : 1
/** The compression flag for a chunk's last block. */
HASH_BLAKE3_CHUNK_END : u32 : 2
/** The compression flag for a parent node, joining two chaining values. */
HASH_BLAKE3_PARENT : u32 : 4
/** The compression flag for the root, whose output is the digest. */
HASH_BLAKE3_ROOT : u32 : 8

/** BLAKE3's initial chaining value, the key when hashing unkeyed: SHA-256's first eight words. */
HASH_BLAKE3_START :: u32.[0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
/** The order a block's message words are permuted into between rounds: word i of the next is word PERMUTATION[i]. */
HASH_BLAKE3_PERMUTATION :: usize.[2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8]

/** A chaining value, kept on the stack of finished subtrees. */
HashBlake3Chain :: struct {
    /** The chaining value's eight words. */
    words : u32[8],
}

/** What a compression is given: kept for the last one, which can be the root's. */
HashBlake3Output :: struct {
    /** The chaining value going in: HASH_BLAKE3_START for a chunk's first block or a parent, else the last block's. */
    chain : u32[8],
    /** The block's message, 64 bytes as little-endian words, zeros past length. */
    words : u32[16],
    /** The chunk's index in the input for a chunk's blocks, 0 for a parent. */
    counter : u64,
    /** How many bytes of the block are input, 0 to 64; a parent's are always 64. */
    length : u32,
    /** The HASH_BLAKE3_ flags for the block, besides HASH_BLAKE3_ROOT, which is added only for the root's. */
    flags : u32,
}

/**
 * Hash bytes with BLAKE3-256, all at once.
 *
 * @param data The bytes, any number, none too; they're public: nothing here is careful with secrets.
 * @return The 32-byte digest, the same as std's crypto.blake3 gives for the same bytes.
 */
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

/**
 * Compress every block of a chunk but its last, and give what its last compression takes.
 *
 * @param data All of the input.
 * @param chunk Which chunk, from 0; its bytes are the HASH_BLAKE3_CHUNK bytes from chunk * HASH_BLAKE3_CHUNK, or fewer
 *     at the input's end. The last chunk of empty input has none, and is one empty block.
 * @return The chunk's last compression, with HASH_BLAKE3_CHUNK_END set, for hash_blake3_chaining_value, or for the
 *     root's compression when it's the only chunk.
 */
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

/**
 * Make the compression of a parent node, joining two subtrees.
 *
 * @param left The chaining value of the left subtree, the earlier input.
 * @param right The chaining value of the right subtree, the later input.
 * @return The parent's compression, its block the two values together, for hash_blake3_chaining_value or the root's.
 */
hash_blake3_parent #no_context :: fn(left: u32[8], right: u32[8]) -> HashBlake3Output {
    output := HashBlake3Output.{chain = HASH_BLAKE3_START, counter = 0, length = 64, flags = HASH_BLAKE3_PARENT}
    for i in 0..<8 {
        output.words[i] = left[i]
        output.words[i + 8] = right[i]
    }
    return output
}

/**
 * Read a block of the input as its words.
 *
 * @param data All of the input.
 * @param at Where the block starts in data, in bytes.
 * @param length How many bytes the block has, 0 to 64; bytes past data's end are read as zeros.
 * @return The block's bytes as 16 little-endian words, zeros after them.
 */
hash_blake3_words #no_context :: fn(data: u8[], at: usize, length: usize) -> u32[16] {
    words : u32[16]
    for i in cast[usize](0)..<length {
        if at + i < data.count {
            words[(i / 4) % 16] |= cast[u32](data[at + i]) << (8 * cast[u32](i % 4))
        }
    }
    return words
}

/**
 * Compress a block for its chaining value, for the next block or a parent: not the root's.
 *
 * @param output What the compression is given.
 * @return The first eight words of the compression's output.
 */
hash_blake3_chaining_value #no_context :: fn(output: HashBlake3Output) -> u32[8] {
    given := output
    words :: hash_blake3_compress(&given, given.counter, 0)
    chain : u32[8]
    for i in 0..<8 {
        chain[i] = words[i]
    }
    return chain
}

/**
 * Mix two message words into four words of the state: BLAKE3's quarter-round, G.
 *
 * @param v The compression's state of 16 words, changed in place.
 * @param a The first state word's index, 0 to 15.
 * @param b The second state word's index, 0 to 15.
 * @param c The third state word's index, 0 to 15.
 * @param d The fourth state word's index, 0 to 15.
 * @param x The first message word mixed in.
 * @param y The second message word mixed in.
 */
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

/**
 * Run BLAKE3's compression function: seven rounds over a block.
 *
 * @param output What the compression is given; only read.
 * @param counter The counter, in place of output's: the chunk's index for a chunk's block, 0 for a parent or the root.
 * @param extra_flags Flags added to output's, like HASH_BLAKE3_ROOT for the root; 0 for none.
 * @return All 16 words of the output: the first eight are the chaining value, or the root's digest as little-endian
 *     words.
 */
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

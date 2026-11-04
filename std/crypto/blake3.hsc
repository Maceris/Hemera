package crypto

import compiler from "base"
import intrinsics from "base"

/*
 * BLAKE3: a fast hash, of any length, keyed or not. Input goes in 1024-byte chunks, whose chaining
 * values are merged in a tree as they come, so a hasher holds a stack of them rather than the input.
 *
 *     digest : u8[32]
 *     crypto.blake3(message, digest)
 *
 *     hasher := crypto.blake3_start_keyed(key) or_return false
 *     crypto.blake3_update(&hasher, message)
 *     crypto.blake3_finish(&hasher, digest)       // any size: more bytes are more of the same output
 *
 * Whole chunks with more input after them are hashed several at once in vectors: eight with AVX2, when the
 * hasher's wide says so, otherwise four. A kernel without vector state sets wide to false after starting.
 */

/** How many bytes a BLAKE3 block has: a chunk's blocks are compressed one at a time. */
BLAKE3_BLOCK :: 64
/** How many bytes a BLAKE3 chunk has: the leaves of the tree its chaining values are merged in. */
BLAKE3_CHUNK :: 1024
/** How many bytes a BLAKE3 key has, exactly. */
BLAKE3_KEY :: 32
/** How many chaining values the stack holds: enough for 2^54 chunks, as many as a 64-bit count of bytes holds. */
BLAKE3_STACK :: 54

/** The flag for a chunk's first block. */
BLAKE3_CHUNK_START :: 1
/** The flag for a chunk's last block. */
BLAKE3_CHUNK_END :: 2
/** The flag for a parent node's compression, of two chaining values. */
BLAKE3_PARENT :: 4
/** The flag for the root's compressions, which make the output. */
BLAKE3_ROOT :: 8
/** The flag on every compression of a keyed hash. */
BLAKE3_KEYED_HASH :: 16

/** A chaining value, or the key, which hold what was hashed, so they're secrets. */
Blake3Chain :: distinct alias u32[8] #secret
/** A block as 16 little-endian words, or the words a compression mixes. */
Blake3Words :: distinct alias u32[16] #secret
/** A block of input, as bytes. */
Blake3Block :: distinct alias u8[64] #secret

/** What a BLAKE3 hasher holds that's secret: the key, the chunk being hashed, and the tree's chaining values. */
Blake3State :: struct #secret {
    /** The key's words, or the initialization vector for an unkeyed hash; every chunk and parent starts from it. */
    key: Blake3Chain,
    /** The chaining value of the chunk being hashed, so far. */
    chunk: Blake3Chain,
    /** The block being filled. */
    block: Blake3Block,
    /** The chaining values of the subtrees not yet merged, the oldest and largest first; depth of them are used. */
    stack: Blake3Chain[54],
}

/**
 * A BLAKE3 hash in progress: from blake3_start or blake3_start_keyed, fed with blake3_update, and read with
 * blake3_finish, which leaves it as it was.
 */
Blake3 :: struct {
    /** The key, the chunk, the block and the stack, secret. */
    state: Blake3State,
    /** BLAKE3_KEYED_HASH for a keyed hasher, 0 otherwise: the flags every compression gets. */
    flags: u32,
    /** How many bytes of the block are filled, 0 to 64: a full block stays until more comes. */
    buffered: usize,
    /** How many of the chunk's blocks were compressed, 0 to 15. */
    blocks: usize,
    /** Which chunk is being hashed, counted from 0: how many chunks are on or merged into the stack. */
    chunk_counter: u64,
    /** How many chaining values are on the stack, 0 to BLAKE3_STACK. */
    depth: usize,
    /**
     * Whether whole chunks go eight at a time with AVX2, as vectors_wide() says when it starts; a kernel
     * without vector state sets it to false, and they go four at a time with what the target has.
     */
    wide: bool,
}

/** What a compression is given, kept to make the root's output, or a chaining value, from. */
Blake3Output :: struct #secret {
    /** The chaining value the compression starts from. */
    chain: Blake3Chain,
    /** The block, as words, zero-padded. */
    words: Blake3Words,
    /** The chunk's number, or 0 for a parent. */
    counter: u64,
    /** How many of the block's bytes are input, 0 to 64. */
    length: u32,
    /** The compression's flags, BLAKE3_ROOT aside, which is added when it's the root. */
    flags: u32,
}

/** BLAKE3's initialization vector, the same as SHA-256's initial hash value. */
BLAKE3_START :: u32.[0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
/** BLAKE3's message permutation, applied to the block's words after each round. */
BLAKE3_PERMUTATION :: usize.[2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8]

/**
 * Start an unkeyed BLAKE3 hash.
 *
 * @return The hasher, with nothing hashed yet, and wide set to whether AVX2 can be used.
 */
blake3_start :: fn() -> Blake3 {
    hasher := Blake3.{wide = vectors_wide()}
    for i in 0..<8 {
        hasher.state.key[i] = BLAKE3_START[i]
        hasher.state.chunk[i] = BLAKE3_START[i]
    }
    return hasher
}

/**
 * Start a keyed BLAKE3 hash, which makes it a message authentication code or a pseudorandom function.
 *
 * @param key The key, exactly 32 bytes, which should be uniformly random; it's copied into the hasher's secret
 *     state.
 * @return The hasher, with wide set to whether AVX2 can be used, or None if the key isn't 32 bytes.
 */
blake3_start_keyed #constant_time :: fn(key: SecretByte[]) -> Blake3? {
    if key.count != BLAKE3_KEY {
        return null
    }
    hasher := Blake3.{flags = BLAKE3_KEYED_HASH, wide = vectors_wide()}
    for i in 0..<8 {
        word := compiler.secret(cast[u32](0))
        for j in 0..<4 {
            word = word | (cast[u32](key[4 * i + j]) << (8 * cast[u32](j)))
        }
        hasher.state.key[i] = word
        hasher.state.chunk[i] = word
    }
    return hasher
}

/**
 * Mix four of the working words with two message words: BLAKE3's G.
 *
 * @param v The working words, four of which are mixed in place.
 * @param a The index in v, 0 to 15, of G's first word.
 * @param b The index in v of G's second word.
 * @param c The index in v of G's third word.
 * @param d The index in v of G's fourth word.
 * @param x The block's message words.
 * @param xi The index in x, 0 to 15, of the first message word.
 * @param yi The index in x of the second message word.
 */
blake3_mix #constant_time :: fn(v: ptr[mut Blake3Words], a: usize, b: usize, c: usize, d: usize, x: ptr[Blake3Words],
    xi: usize, yi: usize) {

    v[a % 16] = v[a % 16] + v[b % 16] + x[xi % 16]
    v[d % 16] = intrinsics.rotate_right(v[d % 16] ~ v[a % 16], 16)
    v[c % 16] = v[c % 16] + v[d % 16]
    v[b % 16] = intrinsics.rotate_right(v[b % 16] ~ v[c % 16], 12)
    v[a % 16] = v[a % 16] + v[b % 16] + x[yi % 16]
    v[d % 16] = intrinsics.rotate_right(v[d % 16] ~ v[a % 16], 8)
    v[c % 16] = v[c % 16] + v[d % 16]
    v[b % 16] = intrinsics.rotate_right(v[b % 16] ~ v[c % 16], 7)
}

/**
 * Do BLAKE3's compression function: seven rounds over a block.
 *
 * @param output What's compressed: the chaining value, the block, its length and its flags.
 * @param counter The counter: the chunk's number for a chaining value, or which 64 bytes of the root's output.
 * @param extra_flags Flags added to output's: BLAKE3_ROOT for the root's output, 0 otherwise.
 * @return The 16 words: the first 8 are a chaining value, and all 16 are 64 bytes of the root's output.
 */
blake3_compress #constant_time :: fn(output: ptr[Blake3Output], counter: u64, extra_flags: u32) -> Blake3Words {
    v : Blake3Words
    for i in 0..<8 {
        v[i] = output.chain[i]
    }
    for i in 0..<4 {
        v[i + 8] = BLAKE3_START[i]
    }
    v[12] = cast[u32](counter)
    v[13] = cast[u32](counter >> 32)
    v[14] = output.length
    v[15] = output.flags | extra_flags
    m := output.words
    for round in 0..<7 {
        blake3_mix(&v, 0, 4, 8, 12, &m, 0, 1)
        blake3_mix(&v, 1, 5, 9, 13, &m, 2, 3)
        blake3_mix(&v, 2, 6, 10, 14, &m, 4, 5)
        blake3_mix(&v, 3, 7, 11, 15, &m, 6, 7)
        blake3_mix(&v, 0, 5, 10, 15, &m, 8, 9)
        blake3_mix(&v, 1, 6, 11, 12, &m, 10, 11)
        blake3_mix(&v, 2, 7, 8, 13, &m, 12, 13)
        blake3_mix(&v, 3, 4, 9, 14, &m, 14, 15)
        permuted : Blake3Words
        for i in 0..<16 {
            permuted[i] = m[BLAKE3_PERMUTATION[i] % 16]
        }
        m = permuted
    }
    for i in 0..<8 {
        v[i] = v[i] ~ v[i + 8]
        v[i + 8] = v[i + 8] ~ output.chain[i]
    }
    return v
}

/**
 * Compress to a chaining value, for a block within a chunk, a chunk, or a parent that isn't the root.
 *
 * @param output What's compressed; its counter, the chunk's number, is declassified, as it isn't secret.
 * @return The chaining value, secret.
 */
blake3_chaining_value #constant_time :: fn(output: ptr[Blake3Output]) -> Blake3Chain {
    // Which chunk it is, which isn't a secret
    words := blake3_compress(output, compiler.declassify(output.counter), 0)
    chain : Blake3Chain
    for i in 0..<8 {
        chain[i] = words[i]
    }
    return chain
}

/**
 * Read the block being filled as words, for compressing.
 *
 * @param block The hasher's 64-byte block buffer; read, not changed.
 * @param length How many of its bytes are input, 0 to 64; the rest are read as zeros, whatever they hold.
 * @return The 16 little-endian words.
 */
blake3_block_words #constant_time :: fn(block: ptr[Blake3Block], length: usize) -> Blake3Words {
    words : Blake3Words
    for i in 0..<16 {
        word := compiler.secret(cast[u32](0))
        for j in 0..<4 {
            at := 4 * i + j
            if cast[usize](at) < length {
                word = word | (cast[u32](block[at]) << (8 * cast[u32](j)))
            }
        }
        words[i] = word
    }
    return words
}

/**
 * Take the chunk being filled as what makes its chaining value, or the root's output when it's the only chunk.
 *
 * @param hasher The hasher, which isn't changed.
 * @return Its last block's compression input, flagged as the chunk's end, and as its start when it's its first.
 */
blake3_chunk_output #constant_time :: fn(hasher: ptr[Blake3]) -> Blake3Output {
    start : u32 = 0
    if hasher.blocks == 0 {
        start = BLAKE3_CHUNK_START
    }
    return Blake3Output.{
        chain = hasher.state.chunk,
        words = blake3_block_words(&hasher.state.block, hasher.buffered),
        counter = hasher.chunk_counter,
        length = cast[u32](hasher.buffered),
        flags = hasher.flags | start | BLAKE3_CHUNK_END,
    }
}

/**
 * Make two chaining values' parent node, as what makes its own chaining value, or the root's output.
 *
 * @param key The key, or the initialization vector, the parent's compression starts from.
 * @param left The left child's chaining value, the older.
 * @param right The right child's chaining value.
 * @param flags The hasher's flags; BLAKE3_PARENT is added.
 * @return The parent's compression input.
 */
blake3_parent_output #constant_time :: fn(key: ptr[Blake3Chain], left: ptr[Blake3Chain], right: ptr[Blake3Chain], flags: u32) -> Blake3Output {
    output := Blake3Output.{chain = key^, counter = 0, length = BLAKE3_BLOCK, flags = flags | BLAKE3_PARENT}
    for i in 0..<8 {
        output.words[i] = left[i]
        output.words[i + 8] = right[i]
    }
    return output
}

/**
 * End a full chunk: its chaining value onto the stack, and a new chunk started.
 *
 * @param hasher The hasher, its chunk full and more input coming.
 */
blake3_end_chunk #constant_time :: fn(hasher: ptr[mut Blake3]) {
    output := blake3_chunk_output(hasher)
    blake3_push_chain(hasher, blake3_chaining_value(&output))
}

/**
 * Push a chunk's chaining value onto the stack, merged with those it completes a subtree with, and start a new chunk.
 *
 * @param hasher The hasher, whose chunk counter says which chunk this was.
 * @param chunk_chain The chunk's chaining value.
 */
blake3_push_chain #constant_time :: fn(hasher: ptr[mut Blake3], chunk_chain: Blake3Chain) {
    chain := chunk_chain
    total := hasher.chunk_counter + 1
    loop {
        hasher.depth -= 1
        parent := blake3_parent_output(&hasher.state.key, &hasher.state.stack[hasher.depth % BLAKE3_STACK], &chain, hasher.flags)
        chain = blake3_chaining_value(&parent)
        total = total >> 1
    }
    while (total & 1) == 0 && hasher.depth > 0
    hasher.state.stack[hasher.depth % BLAKE3_STACK] = chain
    hasher.depth += 1
    hasher.chunk_counter += 1
    hasher.state.chunk = hasher.state.key
    hasher.blocks = 0
    hasher.buffered = 0
}

/**
 * Make room for one more byte: a full chunk ended, and a full block compressed. It's only done once more comes, as
 * the last block and chunk are compressed differently.
 *
 * @param hasher The hasher, about to take a byte.
 */
blake3_make_room #constant_time :: fn(hasher: ptr[mut Blake3]) {
    if hasher.blocks * BLAKE3_BLOCK + hasher.buffered == BLAKE3_CHUNK {
        blake3_end_chunk(hasher)
    }
    if hasher.buffered == BLAKE3_BLOCK {
        output := blake3_chunk_output(hasher)
        output.flags = output.flags & ~cast[u32](BLAKE3_CHUNK_END)
        hasher.state.chunk = blake3_chaining_value(&output)
        hasher.blocks += 1
        hasher.buffered = 0
    }
}

/**
 * Add public bytes to what a BLAKE3 hasher hashes.
 *
 * @param hasher A hasher from blake3_start or blake3_start_keyed, read from already or not; its state advances by data.
 * @param data The next bytes, of any number, none included; they're hashed, not kept.
 */
blake3_update :: fn(hasher: ptr[mut Blake3], data: u8[]) {
    blake3_absorb(hasher, as_secret(data))
}

/**
 * Add secret bytes to what a BLAKE3 hasher hashes, in constant time.
 *
 * @param hasher A hasher from blake3_start or blake3_start_keyed, read from already or not; its state advances by data.
 * @param data The next bytes, of any number; how many isn't secret, what they are is.
 */
blake3_update_secret #constant_time :: fn(hasher: ptr[mut Blake3], data: SecretByte[]) {
    blake3_absorb(hasher, data)
}

/*
 * Whole chunks several at a time, in vectors: a chunk a lane, each of its 16 blocks compressed in turn in every
 * lane at once. Only chunks with more input after them, since the last chunk may be the root.
 */
/** Sixteen words of four chunks at once, in 128-bit vectors: word i of every chunk in vector i, a chunk a lane. */
Blake3Lanes4 :: distinct alias vector[u32, 4][16] #secret
/** Sixteen words of eight chunks at once, in AVX2's 256-bit vectors: word i of every chunk in vector i. */
Blake3Lanes8 :: distinct alias vector[u32, 8][16] #secret

/** How many bytes a batch of chunks can have: eight chunks. */
BLAKE3_BATCH :: 8192
/** Up to eight chunks' bytes, one after another. */
Blake3Batch :: distinct alias u8[8192] #secret
/** Up to eight chunks' chaining values, 8 words each, one after another. */
Blake3Chains :: distinct alias u32[64] #secret

/**
 * Do BLAKE3's G on the same words of every lane: a template, made for four lanes and for eight.
 *
 * @tparam T The lanes' type: Blake3Lanes4 or Blake3Lanes8.
 * @param v The working words, four of whose vectors are mixed in place.
 * @param a The index in v, 0 to 15, of G's first word.
 * @param b The index in v of G's second word.
 * @param c The index in v of G's third word.
 * @param d The index in v of G's fourth word.
 * @param x The blocks' message words.
 * @param xi The index in x, 0 to 15, of the first message word.
 * @param yi The index in x of the second message word.
 */
blake3_mix_lanes :: fn[T](v: ptr[mut T], a: usize, b: usize, c: usize, d: usize, x: ptr[T], xi: usize, yi: usize) {
    v[a % 16] = v[a % 16] + v[b % 16] + x[xi % 16]
    v[d % 16] = intrinsics.rotate_right(v[d % 16] ~ v[a % 16], 16)
    v[c % 16] = v[c % 16] + v[d % 16]
    v[b % 16] = intrinsics.rotate_right(v[b % 16] ~ v[c % 16], 12)
    v[a % 16] = v[a % 16] + v[b % 16] + x[yi % 16]
    v[d % 16] = intrinsics.rotate_right(v[d % 16] ~ v[a % 16], 8)
    v[c % 16] = v[c % 16] + v[d % 16]
    v[b % 16] = intrinsics.rotate_right(v[b % 16] ~ v[c % 16], 7)
}

/**
 * Work out the chaining values of four whole chunks at once, a chunk a lane, in 128-bit vectors.
 *
 * @param hasher The hasher, for its key, flags and chunk counter, the first chunk's number; it isn't changed.
 * @param batch The chunks, its first 4096 bytes.
 * @param chains Where the four chaining values go, its first 32 words.
 */
blake3_chunks4 #constant_time :: fn(hasher: ptr[Blake3], batch: ptr[Blake3Batch], chains: ptr[mut Blake3Chains]) {
    cv : Blake3Lanes4
    for i in 0..<8 {
        cv[i] = intrinsics.splat[vector[u32, 4]](hasher.state.key[i])
    }
    counters : u64[4]
    low : u32[4]
    high : u32[4]
    for l in 0..<4 {
        counters[l] = hasher.chunk_counter + cast[u64](l)
        low[l] = cast[u32](counters[l])
        high[l] = cast[u32](counters[l] >> 32)
    }
    for block in 0..<16 {
        flags := hasher.flags
        if block == 0 {
            flags = flags | BLAKE3_CHUNK_START
        }
        if block == 15 {
            flags = flags | BLAKE3_CHUNK_END
        }
        // Word w of the block in each chunk, as one vector
        m : Blake3Lanes4
        for w in 0..<16 {
            words := compiler.secret(u32.[0, 0, 0, 0])
            for l in 0..<4 {
                at := cast[usize](1024 * l + 64 * block + 4 * w)
                word := compiler.secret(cast[u32](0))
                for j in 0..<4 {
                    word = word | (cast[u32](batch[(at + cast[usize](j)) % BLAKE3_BATCH]) << (8 * cast[u32](j)))
                }
                words[l] = word
            }
            m[w] = bit_cast[vector[u32, 4]](words)
        }
        x : Blake3Lanes4
        for i in 0..<8 {
            x[i] = cv[i]
        }
        for i in 0..<4 {
            x[8 + i] = intrinsics.splat[vector[u32, 4]](BLAKE3_START[i])
        }
        x[12] = bit_cast[vector[u32, 4]](low)
        x[13] = bit_cast[vector[u32, 4]](high)
        x[14] = intrinsics.splat[vector[u32, 4]](cast[u32](BLAKE3_BLOCK))
        x[15] = intrinsics.splat[vector[u32, 4]](flags)
        for round in 0..<7 {
            blake3_mix_lanes(&x, 0, 4, 8, 12, &m, 0, 1)
            blake3_mix_lanes(&x, 1, 5, 9, 13, &m, 2, 3)
            blake3_mix_lanes(&x, 2, 6, 10, 14, &m, 4, 5)
            blake3_mix_lanes(&x, 3, 7, 11, 15, &m, 6, 7)
            blake3_mix_lanes(&x, 0, 5, 10, 15, &m, 8, 9)
            blake3_mix_lanes(&x, 1, 6, 11, 12, &m, 10, 11)
            blake3_mix_lanes(&x, 2, 7, 8, 13, &m, 12, 13)
            blake3_mix_lanes(&x, 3, 4, 9, 14, &m, 14, 15)
            permuted : Blake3Lanes4
            for i in 0..<16 {
                permuted[i] = m[BLAKE3_PERMUTATION[i] % 16]
            }
            m = permuted
        }
        for i in 0..<8 {
            cv[i] = x[i] ~ x[i + 8]
        }
    }
    for i in 0..<8 {
        lanes := bit_cast[u32[4]](cv[i])
        for l in 0..<4 {
            chains[8 * l + i] = lanes[l]
        }
    }
}

#if TARGET_ARCH == .x86_64 {
    /**
     * Work out the chaining values of eight whole chunks at once, a chunk a lane, with AVX2.
     *
     * @param hasher The hasher, for its key, flags and chunk counter, the first chunk's number; it isn't changed.
     *     The CPU has to have AVX2, as vectors_wide says.
     * @param batch The chunks, all 8192 bytes.
     * @param chains Where the eight chaining values go.
     */
    blake3_chunks8 #constant_time #target_features("avx2") :: fn(hasher: ptr[Blake3], batch: ptr[Blake3Batch], chains: ptr[mut Blake3Chains]) {
        cv : Blake3Lanes8
        for i in 0..<8 {
            cv[i] = intrinsics.splat[vector[u32, 8]](hasher.state.key[i])
        }
        counters : u64[8]
        low : u32[8]
        high : u32[8]
        for l in 0..<8 {
            counters[l] = hasher.chunk_counter + cast[u64](l)
            low[l] = cast[u32](counters[l])
            high[l] = cast[u32](counters[l] >> 32)
        }
        for block in 0..<16 {
            flags := hasher.flags
            if block == 0 {
                flags = flags | BLAKE3_CHUNK_START
            }
            if block == 15 {
                flags = flags | BLAKE3_CHUNK_END
            }
            // Word w of the block in each chunk, as one vector
            m : Blake3Lanes8
            for w in 0..<16 {
                words := compiler.secret(u32.[0, 0, 0, 0, 0, 0, 0, 0])
                for l in 0..<8 {
                    at := cast[usize](1024 * l + 64 * block + 4 * w)
                    word := compiler.secret(cast[u32](0))
                    for j in 0..<4 {
                        word = word | (cast[u32](batch[(at + cast[usize](j)) % BLAKE3_BATCH]) << (8 * cast[u32](j)))
                    }
                    words[l] = word
                }
                m[w] = bit_cast[vector[u32, 8]](words)
            }
            x : Blake3Lanes8
            for i in 0..<8 {
                x[i] = cv[i]
            }
            for i in 0..<4 {
                x[8 + i] = intrinsics.splat[vector[u32, 8]](BLAKE3_START[i])
            }
            x[12] = bit_cast[vector[u32, 8]](low)
            x[13] = bit_cast[vector[u32, 8]](high)
            x[14] = intrinsics.splat[vector[u32, 8]](cast[u32](BLAKE3_BLOCK))
            x[15] = intrinsics.splat[vector[u32, 8]](flags)
            for round in 0..<7 {
                blake3_mix_lanes(&x, 0, 4, 8, 12, &m, 0, 1)
                blake3_mix_lanes(&x, 1, 5, 9, 13, &m, 2, 3)
                blake3_mix_lanes(&x, 2, 6, 10, 14, &m, 4, 5)
                blake3_mix_lanes(&x, 3, 7, 11, 15, &m, 6, 7)
                blake3_mix_lanes(&x, 0, 5, 10, 15, &m, 8, 9)
                blake3_mix_lanes(&x, 1, 6, 11, 12, &m, 10, 11)
                blake3_mix_lanes(&x, 2, 7, 8, 13, &m, 12, 13)
                blake3_mix_lanes(&x, 3, 4, 9, 14, &m, 14, 15)
                permuted : Blake3Lanes8
                for i in 0..<16 {
                    permuted[i] = m[BLAKE3_PERMUTATION[i] % 16]
                }
                m = permuted
            }
            for i in 0..<8 {
                cv[i] = x[i] ~ x[i + 8]
            }
        }
        for i in 0..<8 {
            lanes := bit_cast[u32[8]](cv[i])
            for l in 0..<8 {
                chains[8 * l + i] = lanes[l]
            }
        }
    }
}

/**
 * Count the chunks a batch takes.
 *
 * @param hasher The hasher, whose wide decides.
 * @return Eight with AVX2, on x86-64 when wide is set; four otherwise.
 */
blake3_batch_chunks :: fn(hasher: ptr[Blake3]) -> usize {
    #if TARGET_ARCH == .x86_64 {
        if hasher.wide {
            return 8
        }
    }
    return 4
}

/**
 * Hash a batch of whole chunks, and push their chaining values onto the stack.
 *
 * @param hasher The hasher, at a chunk's start.
 * @param data The input from there, with more than blake3_batch_chunks * 1024 bytes, as none of the batch's chunks
 *     may be the last; only that many are taken.
 */
blake3_batch #constant_time :: fn(hasher: ptr[mut Blake3], data: SecretByte[]) {
    count := blake3_batch_chunks(hasher)
    batch : Blake3Batch
    for byte, i in data {
        if i >= count * BLAKE3_CHUNK {
            break
        }
        batch[i % BLAKE3_BATCH] = cast[u8](byte)
    }
    chains : Blake3Chains
    made := false
    #if TARGET_ARCH == .x86_64 {
        if hasher.wide {
            blake3_chunks8(hasher, &batch, &chains)
            made = true
        }
    }
    if !made {
        blake3_chunks4(hasher, &batch, &chains)
    }
    for l in cast[usize](0)..<count {
        chain : Blake3Chain
        for i in cast[usize](0)..<8 {
            chain[i] = chains[(8 * l + i) % 64]
        }
        blake3_push_chain(hasher, chain)
    }
}

/**
 * Add bytes to what a BLAKE3 hasher hashes: whole chunks a batch at a time where there's more after them, the rest a
 * byte at a time.
 *
 * @param hasher The hasher, which takes data: chunks with more input after them are compressed and their chaining
 *     values pushed, and the rest is left buffered, as the last chunk may be the root.
 * @param data The bytes, of any number.
 */
blake3_absorb #constant_time :: fn(hasher: ptr[mut Blake3], data: SecretByte[]) {
    at : usize = 0
    loop {
        batch := blake3_batch_chunks(hasher) * BLAKE3_CHUNK
        filled := hasher.blocks * BLAKE3_BLOCK + hasher.buffered
        if (filled == 0 || filled == BLAKE3_CHUNK) && data.count - at > batch {
            if filled == BLAKE3_CHUNK {
                blake3_end_chunk(hasher)
            }
            blake3_batch(hasher, data[at..<data.count])
            at += batch
        }
        else {
            blake3_make_room(hasher)
            hasher.state.block[hasher.buffered % BLAKE3_BLOCK] = cast[u8](data[at])
            hasher.buffered += 1
            at += 1
        }
    }
    while at < data.count
}


/**
 * Read a BLAKE3 hash, keeping it a secret. The hasher isn't changed, so more input can follow, and be hashed again.
 *
 * @param hasher A hasher after any number of updates, none included; read, not changed.
 * @param output Where the hash goes, as long as output is: any length, none included. A longer output's first bytes
 *     are a shorter one's.
 */
blake3_finish_secret #constant_time :: fn(hasher: ptr[Blake3], output: mut SecretByte[]) {
    root := blake3_chunk_output(hasher)
    for level in 0..<hasher.depth #reverse {
        chain := blake3_chaining_value(&root)
        root = blake3_parent_output(&hasher.state.key, &hasher.state.stack[level % BLAKE3_STACK], &chain, hasher.flags)
    }
    for i in 0..<output.count {
        // A new compression for each 64 bytes, counting them
        if i % BLAKE3_BLOCK == 0 {
            words := blake3_compress(&root, cast[u64](i / BLAKE3_BLOCK), BLAKE3_ROOT)
            for j in cast[usize](0)..<BLAKE3_BLOCK {
                at := i + j
                if at < output.count {
                    output[at] = cast[SecretByte](words[j / 4 % 16] >> (8 * cast[u32](j % 4)))
                }
            }
        }
    }
}

/**
 * Read a BLAKE3 hash. The hasher isn't changed, so more input can follow, and be hashed again.
 *
 * @param hasher A hasher after any number of updates, none included; read, not changed.
 * @param output Where the hash goes, as long as output is: any length, none included, though 32 bytes is BLAKE3's
 *     usual. A longer output's first bytes are a shorter one's.
 */
blake3_finish :: fn(hasher: ptr[Blake3], output: mut u8[]) {
    block : SecretByte[64]
    for start in 0..<output.count {
        if start % 64 == 0 {
            blake3_finish_from(hasher, start / 64, block)
            for j in cast[usize](0)..<BLAKE3_BLOCK {
                at := start + j
                if at < output.count {
                    output[at] = compiler.declassify(block[j])
                }
            }
        }
    }
}

/**
 * Read 64 bytes of a BLAKE3 hash's output, from anywhere in it. The hasher isn't changed.
 *
 * @param hasher A hasher after any number of updates, none included; read, not changed.
 * @param block_index Which 64 bytes: the output's bytes from 64 * block_index on.
 * @param block Where they go: its first 64 bytes, or as many as it has.
 */
blake3_finish_from #constant_time :: fn(hasher: ptr[Blake3], block_index: usize, block: mut SecretByte[]) {
    root := blake3_chunk_output(hasher)
    for level in 0..<hasher.depth #reverse {
        chain := blake3_chaining_value(&root)
        root = blake3_parent_output(&hasher.state.key, &hasher.state.stack[level % BLAKE3_STACK], &chain, hasher.flags)
    }
    words := blake3_compress(&root, cast[u64](block_index), BLAKE3_ROOT)
    for j in 0..<block.count {
        if j < 64 {
            block[j] = cast[SecretByte](words[j / 4 % 16] >> (8 * cast[u32](j % 4)))
        }
    }
}

/**
 * Hash bytes with unkeyed BLAKE3, when they're all at hand.
 *
 * @param data The bytes, of any number, none included.
 * @param output Where the hash goes, as long as output is: any length, though 32 bytes is BLAKE3's usual.
 */
blake3 :: fn(data: u8[], output: mut u8[]) {
    hasher := blake3_start()
    blake3_update(&hasher, data)
    blake3_finish(&hasher, output)
}

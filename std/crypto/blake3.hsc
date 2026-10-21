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

BLAKE3_BLOCK :: 64
BLAKE3_CHUNK :: 1024
BLAKE3_KEY :: 32
// Enough for 2^54 chunks, as many as a 64-bit count of bytes holds
BLAKE3_STACK :: 54

BLAKE3_CHUNK_START :: 1
BLAKE3_CHUNK_END :: 2
BLAKE3_PARENT :: 4
BLAKE3_ROOT :: 8
BLAKE3_KEYED_HASH :: 16

// A chaining value, or the key, which hold what was hashed
Blake3Chain :: distinct alias u32[8] #secret
// A block as words, and the words a compression mixes
Blake3Words :: distinct alias u32[16] #secret
Blake3Block :: distinct alias u8[64] #secret

Blake3State :: struct #secret {
    key: Blake3Chain,
    chunk: Blake3Chain,
    block: Blake3Block,
    stack: Blake3Chain[54],
}

Blake3 :: struct {
    state: Blake3State,
    // KEYED_HASH for a keyed hasher
    flags: u32,
    // How much of block is filled, how many of the chunk's blocks were compressed, which chunk this
    // is, and how many chaining values are on the stack
    buffered: usize,
    blocks: usize,
    chunk_counter: u64,
    depth: usize,
    // Whether whole chunks go eight at a time with AVX2, as vectors_wide() says when it starts; a kernel
    // without vector state sets it to false, and they go four at a time with what the target has
    wide: bool,
}

// What a compression is given, kept to make the root's output, or a chaining value, from
Blake3Output :: struct #secret {
    chain: Blake3Chain,
    words: Blake3Words,
    counter: u64,
    length: u32,
    flags: u32,
}

BLAKE3_START :: u32.[0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
BLAKE3_PERMUTATION :: usize.[2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8]

blake3_start :: fn() -> Blake3 {
    hasher := Blake3.{wide = vectors_wide()}
    for i in 0..<8 {
        hasher.state.key[i] = BLAKE3_START[i]
        hasher.state.chunk[i] = BLAKE3_START[i]
    }
    return hasher
}

// A keyed hasher, for a key of exactly 32 bytes, or null for another size.
blake3_start_keyed #constant_time :: fn(key: SecretByte[]) -> Blake3? {
    if key.count != BLAKE3_KEY {
        return null
    }
    hasher := Blake3.{flags = BLAKE3_KEYED_HASH, wide = vectors_wide()}
    for i in 0..<8 {
        word := compiler.secret(cast[u32](0))
        for j in 0..<4 {
            word = word | (cast[u32](key[(4 * i + j) % BLAKE3_KEY]) << (8 * cast[u32](j)))
        }
        hasher.state.key[i] = word
        hasher.state.chunk[i] = word
    }
    return hasher
}

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

// The 16 words of a compression: the first 8 a chaining value, all 16 the root's output.
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

blake3_chaining_value #constant_time :: fn(output: ptr[Blake3Output]) -> Blake3Chain {
    // Which chunk it is, which isn't a secret
    words := blake3_compress(output, compiler.declassify(output.counter), 0)
    chain : Blake3Chain
    for i in 0..<8 {
        chain[i] = words[i]
    }
    return chain
}

// The block being filled as words, for compressing: its first length bytes, then zeros.
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

// The chunk being filled, as what makes its chaining value.
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

// Two chaining values' parent, as what makes its own.
blake3_parent_output #constant_time :: fn(key: ptr[Blake3Chain], left: ptr[Blake3Chain], right: ptr[Blake3Chain], flags: u32) -> Blake3Output {
    output := Blake3Output.{chain = key^, counter = 0, length = BLAKE3_BLOCK, flags = flags | BLAKE3_PARENT}
    for i in 0..<8 {
        output.words[i] = left[i]
        output.words[i + 8] = right[i]
    }
    return output
}

// A full chunk's chaining value onto the stack.
blake3_end_chunk #constant_time :: fn(hasher: ptr[mut Blake3]) {
    output := blake3_chunk_output(hasher)
    blake3_push_chain(hasher, blake3_chaining_value(&output))
}

// A chunk's chaining value onto the stack, merged with those it completes a subtree with, and a new chunk started.
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

// Room for one more byte: a full chunk ended, and a full block compressed, only once more comes.
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

blake3_update :: fn(hasher: ptr[mut Blake3], data: u8[]) {
    blake3_absorb(hasher, as_secret(data))
}

blake3_update_secret #constant_time :: fn(hasher: ptr[mut Blake3], data: SecretByte[]) {
    blake3_absorb(hasher, data)
}

/*
 * Whole chunks several at a time, in vectors: a chunk a lane, each of its 16 blocks compressed in turn in every
 * lane at once. Only chunks with more input after them, since the last chunk may be the root.
 */
Blake3Lanes4 :: distinct alias vector[u32, 4][16] #secret
Blake3Lanes8 :: distinct alias vector[u32, 8][16] #secret

// Up to eight chunks' bytes, and their chaining values
BLAKE3_BATCH :: 8192
Blake3Batch :: distinct alias u8[8192] #secret
Blake3Chains :: distinct alias u32[64] #secret

// BLAKE3's G on the same words of every lane: a template, made for four lanes and for eight.
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

// The chaining values of 4 whole chunks at once, the batch's first 4096 bytes, a chunk a lane.
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
    // The chaining values of 8 whole chunks at once, the batch's first 8192 bytes, a chunk a lane.
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

// How many chunks a batch takes: eight with AVX2, four otherwise.
blake3_batch_chunks :: fn(hasher: ptr[Blake3]) -> usize {
    #if TARGET_ARCH == .x86_64 {
        if hasher.wide {
            return 8
        }
    }
    return 4
}

// A batch of whole chunks, data's first batch_chunks * 1024 bytes, onto the stack.
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

// data into the hasher: whole chunks a batch at a time where there's more after them, the rest a byte at a time.
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


// output filled with the hash, as long as output is. The hasher isn't changed, so more can follow.
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

// 64 bytes of the output, the block'th of them
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

blake3 :: fn(data: u8[], output: mut u8[]) {
    hasher := blake3_start()
    blake3_update(&hasher, data)
    blake3_finish(&hasher, output)
}

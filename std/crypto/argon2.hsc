package crypto

import compiler from "base"
import intrinsics from "base"

/*
 * Argon2id (RFC 9106): a password hash that takes memory as well as time, so guessing passwords costs
 * an attacker as much memory per guess. The caller passes the memory, as blocks of 1 KiB, at least
 * argon2_blocks_needed(parameters) of them, and the salt, at least 8 random bytes kept with the hash.
 *
 *     parameters := crypto.Argon2Parameters.{memory_kib = 65536, passes = 3, lanes = 4}
 *     blocks := ...   // argon2_blocks_needed(parameters) crypto.Argon2Blocks, from wherever suits
 *     hash : crypto.SecretByte[32]
 *     _ = crypto.argon2id(password, salt, parameters, blocks, hash)
 *
 * Which blocks it reads depends on the password from halfway through the first pass, by design: that's
 * Argon2id's trade between Argon2i, whose reads say nothing, and Argon2d, which resists cracking hardware
 * better. So those block numbers are declassified, the one place timing can follow the password. The
 * blocks are wiped before it returns.
 *
 * Blocks are compressed four words at a time with AVX2 when vectors_wide() says the CPU and the OS allow it;
 * a kernel without vector state calls argon2id_keyed_with with wide = false.
 */

// m, t and p: the memory in KiB, at least 8 per lane, how many passes over it, and how many lanes.
Argon2Parameters :: struct {
    memory_kib: u32,
    passes: u32,
    lanes: u32,
}

// One of the memory's 1 KiB blocks.
Argon2Block :: distinct alias u64[128] #secret

ARGON2_VERSION :: 0x13
ARGON2_ID :: 2

// How many blocks parameters needs: the memory, rounded down to a multiple of 4 per lane.
argon2_blocks_needed :: fn(parameters: Argon2Parameters) -> usize {
    lanes := cast[usize](parameters.lanes)
    if lanes == 0 {
        return 0
    }
    return 4 * lanes * (cast[usize](parameters.memory_kib) / (4 * lanes))
}

// v[a] + v[b] + 2 * their low halves multiplied, Argon2's change to BLAKE2b's adding, into v[a].
argon2_add #constant_time :: fn(v: ptr[mut Argon2Block], a: usize, b: usize) {
    x := v[a % 128]
    y := v[b % 128]
    v[a % 128] = x + y + 2 * (x & 0xffff_ffff) * (y & 0xffff_ffff)
}

// BLAKE2b's G with argon2_add, on four of the block's words.
argon2_mix #constant_time :: fn(v: ptr[mut Argon2Block], a: usize, b: usize, c: usize, d: usize) {
    argon2_add(v, a, b)
    v[d % 128] = intrinsics.rotate_right(v[d % 128] ~ v[a % 128], 32)
    argon2_add(v, c, d)
    v[b % 128] = intrinsics.rotate_right(v[b % 128] ~ v[c % 128], 24)
    argon2_add(v, a, b)
    v[d % 128] = intrinsics.rotate_right(v[d % 128] ~ v[a % 128], 16)
    argon2_add(v, c, d)
    v[b % 128] = intrinsics.rotate_right(v[b % 128] ~ v[c % 128], 63)
}

// The permutation P on sixteen of the block's words, at at[0], at[1], and so on.
argon2_permute #constant_time :: fn(v: ptr[mut Argon2Block], at: usize[16]) {
    argon2_mix(v, at[0], at[4], at[8], at[12])
    argon2_mix(v, at[1], at[5], at[9], at[13])
    argon2_mix(v, at[2], at[6], at[10], at[14])
    argon2_mix(v, at[3], at[7], at[11], at[15])
    argon2_mix(v, at[0], at[5], at[10], at[15])
    argon2_mix(v, at[1], at[6], at[11], at[12])
    argon2_mix(v, at[2], at[7], at[8], at[13])
    argon2_mix(v, at[3], at[4], at[9], at[14])
}

#if TARGET_ARCH == .x86_64 {
    // Argon2's G on the rows' four columns at once: BLAKE2b's, with argon2_add's multiplications, and no message.
    argon2_mix_rows #constant_time #target_features("avx2") :: fn(r: ptr[mut Blake2bRows]) {
        low := intrinsics.splat[vector[u64, 4]](0xffff_ffff)
        product := (r[0] & low) * (r[1] & low)
        r[0] = r[0] + r[1] + product + product
        r[3] = intrinsics.rotate_right(r[3] ~ r[0], 32)
        product = (r[2] & low) * (r[3] & low)
        r[2] = r[2] + r[3] + product + product
        r[1] = intrinsics.rotate_right(r[1] ~ r[2], 24)
        product = (r[0] & low) * (r[1] & low)
        r[0] = r[0] + r[1] + product + product
        r[3] = intrinsics.rotate_right(r[3] ~ r[0], 16)
        product = (r[2] & low) * (r[3] & low)
        r[2] = r[2] + r[3] + product + product
        r[1] = intrinsics.rotate_right(r[1] ~ r[2], 63)
    }

    /*
     * argon2_permute with AVX2, on the sixteen words as four rows of four like blake2b_compress_wide's: row k's
     * lane j the word at base + row_step * k + pair_step * (j / 2) + j % 2, a P on a row of the block or a column.
     */
    argon2_permute_wide #constant_time #target_features("avx2") :: fn(v: ptr[mut Argon2Block], base: usize, row_step: usize,
        pair_step: usize) {

        r : Blake2bRows
        for k in cast[usize](0)..<4 {
            at := base + row_step * k
            r[k] = vector[u64, 4].{v[at % 128], v[(at + 1) % 128], v[(at + pair_step) % 128], v[(at + pair_step + 1) % 128]}
        }
        argon2_mix_rows(&r)
        r[1] = intrinsics.rotate_lanes(r[1], 1)
        r[2] = intrinsics.rotate_lanes(r[2], 2)
        r[3] = intrinsics.rotate_lanes(r[3], 3)
        argon2_mix_rows(&r)
        r[1] = intrinsics.rotate_lanes(r[1], 3)
        r[2] = intrinsics.rotate_lanes(r[2], 2)
        r[3] = intrinsics.rotate_lanes(r[3], 1)
        for k in cast[usize](0)..<4 {
            at := base + row_step * k
            words := bit_cast[u64[4]](r[k])
            v[at % 128] = words[0]
            v[(at + 1) % 128] = words[1]
            v[(at + pair_step) % 128] = words[2]
            v[(at + pair_step + 1) % 128] = words[3]
        }
    }

    // argon2_compress with AVX2.
    argon2_compress_wide #constant_time #target_features("avx2") :: fn(x: ptr[Argon2Block], y: ptr[Argon2Block], out: ptr[mut Argon2Block],
        keep: bool) {

        r : Argon2Block
        for k in 0..<128 {
            r[k] = x[k] ~ y[k]
        }
        q := r
        // Each row's sixteen words, then each column's two words of every row
        for row in cast[usize](0)..<8 {
            argon2_permute_wide(&q, 16 * row, 4, 2)
        }
        for column in cast[usize](0)..<8 {
            argon2_permute_wide(&q, 2 * column, 32, 16)
        }
        for k in 0..<128 {
            if keep {
                out[k] = out[k] ~ q[k] ~ r[k]
            }
            else {
                out[k] = q[k] ~ r[k]
            }
        }
    }
}

/*
 * The compression G: R = x ~ y, P on each of R's eight rows of sixteen words, then on each of its eight
 * columns of two words a row, and that ~ R, into out, or ~'d into what's there, as passes after the first do.
 */
argon2_compress #constant_time :: fn(x: ptr[Argon2Block], y: ptr[Argon2Block], out: ptr[mut Argon2Block], keep: bool, wide: bool) {
    #if TARGET_ARCH == .x86_64 {
        if wide {
            argon2_compress_wide(x, y, out, keep)
            return void
        }
    }
    r : Argon2Block
    for k in 0..<128 {
        r[k] = x[k] ~ y[k]
    }
    q := r
    for row in 0..<8 {
        at : usize[16]
        for k in 0..<16 {
            at[k] = cast[usize](16 * row + k)
        }
        argon2_permute(&q, at)
    }
    for column in 0..<8 {
        at : usize[16]
        for k in 0..<8 {
            at[2 * k] = cast[usize](16 * k + 2 * column)
            at[2 * k + 1] = cast[usize](16 * k + 2 * column + 1)
        }
        argon2_permute(&q, at)
    }
    for k in 0..<128 {
        if keep {
            out[k] = out[k] ~ q[k] ~ r[k]
        }
        else {
            out[k] = q[k] ~ r[k]
        }
    }
}

argon2_le32 :: fn(value: u32) -> u8[4] {
    return u8.[cast[u8](value), cast[u8](value >> 8), cast[u8](value >> 16), cast[u8](value >> 24)]
}

/*
 * H', the hash of any length (RFC 9106, 3.3): BLAKE2b of output's size, then the count and input, for 64
 * bytes or fewer; for more, 32 bytes of each in a chain of 64-byte hashes, and the rest from the last.
 */
argon2_hash_long #constant_time :: fn(input: SecretByte[], output: mut SecretByte[], wide: bool) {
    count := output.count
    if count <= 64 {
        hasher := blake2b_start(count) or_return void
        hasher.wide = hasher.wide && wide
        blake2b_update(&hasher, argon2_le32(cast[u32](count)))
        blake2b_update_secret(&hasher, input)
        blake2b_finish_secret(&hasher, output)
        return void
    }
    hasher := blake2b_start(64) or_return void
    hasher.wide = hasher.wide && wide
    blake2b_update(&hasher, argon2_le32(cast[u32](count)))
    blake2b_update_secret(&hasher, input)
    chained : SecretByte[64]
    blake2b_finish_secret(&hasher, chained)
    written : usize = 0
    loop {
        for i in 0..<32 {
            output[(written + cast[usize](i)) % count] = chained[i]
        }
        written += 32
        next := blake2b_start(64) or_return void
        if count - written <= 64 {
            next = blake2b_start(count - written) or_return void
        }
        next.wide = next.wide && wide
        blake2b_update_secret(&next, chained)
        blake2b_finish_secret(&next, chained)
    }
    while count - written > 64
    for i in written..<count {
        output[i] = chained[(i - written) % 64]
    }
    intrinsics.secure_zero(&chained, size_of(SecretByte[64]))
}

argon2_block_bytes #constant_time :: fn(block: ptr[Argon2Block]) -> SecretByte[1024] {
    bytes : SecretByte[1024]
    for i in 0..<128 {
        for j in 0..<8 {
            bytes[8 * i + j] = cast[SecretByte](block[i] >> (8 * cast[u64](j)))
        }
    }
    return bytes
}

argon2_block_of #constant_time :: fn(bytes: ptr[SecretByte[1024]]) -> Argon2Block {
    block : Argon2Block
    for i in 0..<128 {
        for j in 0..<8 {
            block[i] = block[i] | (cast[u64](bytes[8 * i + j]) << (8 * cast[u64](j)))
        }
    }
    return block
}

// Where the memory is, and how it's laid out: lanes of columns blocks, each four segments long.
Argon2Memory :: struct #scoped {
    blocks: mut Argon2Block[],
    lanes: usize,
    columns: usize,
    segment: usize,
    passes: usize,
    // Whether compressing uses AVX2
    wide: bool,
}

/*
 * One lane's segment of a slice in a pass (RFC 9106, 3.4): each block from the one before it and one
 * chosen earlier, from this lane or, after the first slice, another.
 */
argon2_fill_segment #constant_time :: fn(memory: ptr[Argon2Memory], pass: usize, slice: usize, lane: usize) {
    blocks := memory.blocks
    columns := memory.columns
    segment := memory.segment
    // The first pass's first half chooses from counters, not the blocks, ARGON2_ID's Argon2i half
    independent := pass == 0 && slice < 2
    input : Argon2Block
    addresses : Argon2Block
    zero : Argon2Block
    input[0] = cast[u64](pass)
    input[1] = cast[u64](lane)
    input[2] = cast[u64](slice)
    input[3] = cast[u64](blocks.count)
    input[4] = cast[u64](memory.passes)
    input[5] = ARGON2_ID
    start : usize = 0
    if pass == 0 && slice == 0 {
        // Each lane's first two blocks are made from the password
        start = 2
    }
    for i in start..<segment {
        if independent && (i == start || i % 128 == 0) {
            input[6] += 1
            argon2_compress(&zero, &input, &addresses, false, memory.wide)
            argon2_compress(&zero, &addresses, &addresses, false, memory.wide)
        }
        column := slice * segment + i
        current := lane * columns + column
        previous := current - 1
        if column == 0 {
            previous = current + columns - 1
        }
        if current >= blocks.count || previous >= blocks.count {
            return void
        }
        // The choice: declassified, as Argon2id's second half chooses from what the blocks hold
        choice := compiler.declassify(addresses[i % 128])
        if !independent {
            choice = compiler.declassify(blocks[previous][0])
        }
        j1 := choice & 0xffff_ffff
        j2 := choice >> 32
        reference_lane := cast[usize](j2 % cast[u64](memory.lanes))
        if pass == 0 && slice == 0 {
            reference_lane = lane
        }
        // How many blocks it can choose from: finished segments, and this one's so far if it's this lane
        area := slice * segment
        if pass > 0 {
            area = columns - segment
        }
        if reference_lane == lane {
            area = area + i - 1
        }
        else if i == 0 {
            area = area - 1
        }
        x := (j1 * j1) >> 32
        y := (cast[u64](area) * x) >> 32
        start_column : usize = 0
        if pass > 0 && slice < 3 {
            start_column = (slice + 1) * segment
        }
        reference := reference_lane * columns + (start_column + area - 1 - cast[usize](y)) % columns
        if reference >= blocks.count {
            return void
        }
        argon2_compress(&blocks[previous], &blocks[reference], &blocks[current], pass > 0, memory.wide)
    }
}

/*
 * Argon2id with a secret key, like a pepper kept apart from the hashes, and associated data, both
 * empty for the plain one (RFC 9106, 3.2). False, writing nothing, for a hash under 4 bytes, a salt
 * under 8, no lanes or passes, under 8 KiB a lane, or fewer blocks than argon2_blocks_needed.
 */
argon2id_keyed #constant_time :: fn(password: SecretByte[], salt: u8[], key: SecretByte[], associated: u8[],
    parameters: Argon2Parameters, blocks: mut Argon2Block[], hash: mut SecretByte[]) -> bool {

    return argon2id_keyed_with(password, salt, key, associated, parameters, blocks, hash, vectors_wide())
}

// argon2id_keyed, with AVX2 only if wide: a kernel without vector state gives false.
argon2id_keyed_with #constant_time :: fn(password: SecretByte[], salt: u8[], key: SecretByte[], associated: u8[],
    parameters: Argon2Parameters, blocks: mut Argon2Block[], hash: mut SecretByte[], wide: bool) -> bool {

    lanes := cast[usize](parameters.lanes)
    needed := argon2_blocks_needed(parameters)
    if hash.count < 4 || salt.count < 8 || lanes == 0 || lanes > 0xff_ffff || parameters.passes == 0
        || cast[usize](parameters.memory_kib) < 8 * lanes || blocks.count < needed {
        return false
    }

    // H0, from the parameters and every input
    hasher := blake2b_start(64) or_return false
    hasher.wide = hasher.wide && wide
    blake2b_update(&hasher, argon2_le32(parameters.lanes))
    blake2b_update(&hasher, argon2_le32(cast[u32](hash.count)))
    blake2b_update(&hasher, argon2_le32(parameters.memory_kib))
    blake2b_update(&hasher, argon2_le32(parameters.passes))
    blake2b_update(&hasher, argon2_le32(ARGON2_VERSION))
    blake2b_update(&hasher, argon2_le32(ARGON2_ID))
    blake2b_update(&hasher, argon2_le32(cast[u32](password.count)))
    blake2b_update_secret(&hasher, password)
    blake2b_update(&hasher, argon2_le32(cast[u32](salt.count)))
    blake2b_update(&hasher, salt)
    blake2b_update(&hasher, argon2_le32(cast[u32](key.count)))
    blake2b_update_secret(&hasher, key)
    blake2b_update(&hasher, argon2_le32(cast[u32](associated.count)))
    blake2b_update(&hasher, associated)
    // H0, then which of the first two blocks, then the lane
    seed : SecretByte[72]
    blake2b_finish_secret(&hasher, seed[0..<64])

    memory := Argon2Memory.{blocks = blocks[0..<needed], lanes = lanes, columns = needed / lanes, segment = needed / lanes / 4,
        passes = cast[usize](parameters.passes), wide = wide}
    block_bytes : SecretByte[1024]
    for lane in 0..<lanes {
        for first in 0..<2 {
            number := argon2_le32(cast[u32](first))
            lane_number := argon2_le32(cast[u32](lane))
            for k in 0..<4 {
                seed[64 + k] = cast[SecretByte](number[k])
                seed[68 + k] = cast[SecretByte](lane_number[k])
            }
            argon2_hash_long(seed, block_bytes, wide)
            at := lane * memory.columns + cast[usize](first)
            if at < blocks.count {
                blocks[at] = argon2_block_of(&block_bytes)
            }
        }
    }

    for pass in 0..<memory.passes {
        for slice in 0..<4 {
            for lane in 0..<lanes {
                argon2_fill_segment(&memory, pass, cast[usize](slice), lane)
            }
        }
    }

    // The last column's blocks, ~'d together, give the hash
    last : Argon2Block
    for lane in 0..<lanes {
        at := lane * memory.columns + memory.columns - 1
        if at < blocks.count {
            for k in 0..<128 {
                last[k] = last[k] ~ blocks[at][k]
            }
        }
    }
    block_bytes = argon2_block_bytes(&last)
    argon2_hash_long(block_bytes, hash, wide)

    intrinsics.secure_zero(&seed, size_of(SecretByte[72]))
    intrinsics.secure_zero(&block_bytes, size_of(SecretByte[1024]))
    intrinsics.secure_zero(&last, size_of(Argon2Block))
    for i in 0..<needed {
        if i < blocks.count {
            intrinsics.secure_zero(&blocks[i], size_of(Argon2Block))
        }
    }
    return true
}

// Argon2id of a password and salt into hash, of hash's size; see argon2id_keyed for when it's false.
argon2id #constant_time :: fn(password: SecretByte[], salt: u8[], parameters: Argon2Parameters, blocks: mut Argon2Block[],
    hash: mut SecretByte[]) -> bool {

    return argon2id_keyed(password, salt, as_secret(u8.[]), u8.[], parameters, blocks, hash)
}

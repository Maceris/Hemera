package containers

import compiler from "base"

/**
 * size bits, all clear to start, in 64-bit words in the bitmap itself: for things like which frames or IDs are in use.
 *
 * Bits at or past size are left alone by everything here, and an index at or past size is ignored. Its zero value has
 * every bit clear. Nothing in it is atomic, so threads sharing one need a lock.
 *
 *     used : Bitmap[512]
 *     bit_set(&used, 3)
 *     free :: bit_find_clear(&used, 0)     // the first clear bit from 0, if any
 *
 * @tparam size How many bits it holds: at least 1. It takes size rounded up to a multiple of 64 bits.
 */
Bitmap :: struct[size: usize] where compiler.AtLeastOne(size) {
    /** The bits, 64 to a word, bit i at bit i % 64 of word i / 64. */
    words : u64[(size + 63) / 64],
}

/**
 * Set a bit.
 *
 * @tparam size How many bits the bitmap holds.
 * @param bitmap A bitmap to set the bit in; no other bit changes.
 * @param index The bit, from 0; at or past size, nothing happens.
 */
bit_set :: fn[size: usize](bitmap: ptr[mut Bitmap[size]], index: usize) {
    word :: index / 64
    if index < size && word < bitmap.words.count {
        bitmap.words[word] |= cast[u64](1) << cast[u64](index % 64)
    }
}

/**
 * Clear a bit.
 *
 * @tparam size How many bits the bitmap holds.
 * @param bitmap A bitmap to clear the bit in; no other bit changes.
 * @param index The bit, from 0; at or past size, nothing happens.
 */
bit_clear :: fn[size: usize](bitmap: ptr[mut Bitmap[size]], index: usize) {
    word :: index / 64
    if index < size && word < bitmap.words.count {
        bitmap.words[word] &= ~(cast[u64](1) << cast[u64](index % 64))
    }
}

/**
 * Tell whether a bit is set.
 *
 * @tparam size How many bits the bitmap holds.
 * @param bitmap A bitmap to read; it isn't changed.
 * @param index The bit, from 0; at or past size, it reads as clear.
 * @return True if it's set; false if it's clear, or index is at or past size.
 */
bit_test :: fn[size: usize](bitmap: ptr[Bitmap[size]], index: usize) -> bool {
    word :: index / 64
    if index >= size || word >= bitmap.words.count {
        return false
    }
    return (bitmap.words[word] >> cast[u64](index % 64)) & 1 != 0
}

/**
 * Find the first set bit at or after an index.
 *
 * @tparam size How many bits the bitmap holds.
 * @param bitmap A bitmap to search; it isn't changed.
 * @param from The index to start at, from 0.
 * @return The first set bit's index, below size; null if none is set from there on, or from is at or past size.
 */
bit_find_set :: fn[size: usize](bitmap: ptr[Bitmap[size]], from: usize) -> usize? {
    return find_bit(bitmap.words, size, from, false)
}

/**
 * Find the first clear bit at or after an index.
 *
 * @tparam size How many bits the bitmap holds.
 * @param bitmap A bitmap to search; it isn't changed.
 * @param from The index to start at, from 0.
 * @return The first clear bit's index, below size; null if every bit from there on is set, or from is at or past size.
 */
bit_find_clear :: fn[size: usize](bitmap: ptr[Bitmap[size]], from: usize) -> usize? {
    return find_bit(bitmap.words, size, from, true)
}

/**
 * Count the bits that are set.
 *
 * @tparam size How many bits the bitmap holds.
 * @param bitmap A bitmap to count in; it isn't changed. Bits at or past size are counted too, so they must be clear, as
 *     nothing here sets them.
 * @return How many are set, from 0 to size.
 */
bit_count :: fn[size: usize](bitmap: ptr[Bitmap[size]]) -> usize {
    count : usize = 0
    for i in 0..<bitmap.words.count {
        // Clearing the lowest set bit until there's none left
        word := bitmap.words[i]
        loop {
            if word == 0 {
                break
            }
            word &= word - 1
            count += 1
        }
    }
    return count
}

/**
 * Clear every bit.
 *
 * @tparam size How many bits the bitmap holds.
 * @param bitmap A bitmap to clear; every word of it becomes 0.
 */
bit_clear_all :: fn[size: usize](bitmap: ptr[mut Bitmap[size]]) {
    for i in 0..<bitmap.words.count {
        bitmap.words[i] = 0
    }
}

/**
 * Find the first bit at or after an index, below size, that's clear or set, a word at a time, skipping words with
 * nothing to find.
 *
 * @param words The bitmap's words, 64 bits to each.
 * @param size How many bits count, from the first word's lowest; bits at or past it are never found.
 * @param from The index to start at, from 0.
 * @param looking_for_clear True to find a clear bit, false to find a set one.
 * @return The bit's index, below size; null if there's none from there on.
 */
find_bit :: fn(words: u64[], size: usize, from: usize, looking_for_clear: bool) -> usize? {
    index := from
    loop {
        if index >= size {
            break
        }
        word_index :: index / 64
        if word_index >= words.count {
            break
        }
        // The word's bits from this one on, set where what's looked for is
        word :: if looking_for_clear { ~words[word_index] } else { words[word_index] }
        bits :: word >> cast[u64](index % 64)
        if bits == 0 {
            index = (word_index + 1) * 64
            continue
        }
        // The lowest set bit of bits
        offset : usize = 0
        loop {
            if (bits >> cast[u64](offset)) & 1 != 0 {
                break
            }
            offset += 1
        }
        found :: index + offset
        if found >= size {
            break
        }
        return found
    }
    return null
}

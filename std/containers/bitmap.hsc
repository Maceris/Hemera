package containers

/*
 * size bits, all clear to start, in 64-bit words in the bitmap itself: for things like which
 * frames or IDs are in use. Bits at or past size are left alone by everything here.
 *
 *     used : Bitmap[512]
 *     bit_set(&used, 3)
 *     free :: bit_find_clear(&used, 0)     // the first clear bit from 0, if any
 */
Bitmap :: struct[size: usize] {
    words : u64[(size + 63) / 64],
}

bit_set :: fn[size: usize](bitmap: ptr[mut Bitmap[size]], index: usize) {
    word :: index / 64
    if index < size && word < bitmap.words.count {
        bitmap.words[word] |= cast[u64](1) << cast[u64](index % 64)
    }
}

bit_clear :: fn[size: usize](bitmap: ptr[mut Bitmap[size]], index: usize) {
    word :: index / 64
    if index < size && word < bitmap.words.count {
        bitmap.words[word] &= ~(cast[u64](1) << cast[u64](index % 64))
    }
}

bit_test :: fn[size: usize](bitmap: ptr[Bitmap[size]], index: usize) -> bool {
    word :: index / 64
    if index >= size || word >= bitmap.words.count {
        return false
    }
    return (bitmap.words[word] >> cast[u64](index % 64)) & 1 != 0
}

// The first set bit at or after from, if there is one.
bit_find_set :: fn[size: usize](bitmap: ptr[Bitmap[size]], from: usize) -> usize? {
    return find_bit(bitmap.words, size, from, false)
}

// The first clear bit at or after from, if there is one.
bit_find_clear :: fn[size: usize](bitmap: ptr[Bitmap[size]], from: usize) -> usize? {
    return find_bit(bitmap.words, size, from, true)
}

// How many bits are set.
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

bit_clear_all :: fn[size: usize](bitmap: ptr[mut Bitmap[size]]) {
    for i in 0..<bitmap.words.count {
        bitmap.words[i] = 0
    }
}

/*
 * The first bit at or after from, below size, that's clear (looking_for_clear) or set: a word at a
 * time, skipping words with nothing to find.
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

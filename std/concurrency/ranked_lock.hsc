package concurrency

/*
 * Spin locks taken in a declared order, as Linux's lockdep checks it, but from ranks written down rather than inferred:
 * each lock has a rank, and whoever takes locks keeps the ranks it holds in a HeldRanks, one per CPU or thread. A lock
 * may be taken only above every rank held, so two holders can't each wait for what the other holds. lock_ranked takes
 * the lock either way, and says whether it was in order; what to do about one that isn't is the caller's to decide.
 *
 *     held : concurrency.HeldRanks           // one per CPU, or per thread
 *     in_order :: concurrency.lock_ranked(&port.lock, RANK_PORT, &held)
 *     defer _ = concurrency.unlock_ranked(&port.lock, RANK_PORT, &held)
 *
 * Locks of the same rank are taken in the same order, by address, with lock_ranked_after, which checks that order.
 */

// The most locks one holder holds at once that HeldRanks keeps; more are taken, but not checked.
MAX_HELD_RANKS :: 16

HeldRanks :: struct {
    ranks : u32[MAX_HELD_RANKS],
    // The address of each lock, for locks of one rank taken by address
    locks : u64[MAX_HELD_RANKS],
    count : u32,
}

// The highest rank held, and its lock's address, or none.
highest_held :: fn(held: ptr[HeldRanks]) -> (rank: u32, lock: u64, any: bool) {
    count :: cast[usize](held.count)
    if count == 0 || count > MAX_HELD_RANKS {
        return 0, 0, false
    }
    top :: count - 1
    if top >= held.ranks.count || top >= held.locks.count {
        return 0, 0, false
    }
    return held.ranks[top], held.locks[top], true
}

// Takes spin_lock, of rank, and whether every rank held was below it.
lock_ranked :: fn(spin_lock: ptr[mut SpinLock], rank: u32, held: ptr[mut HeldRanks]) -> bool {
    highest, highest_lock, any :: highest_held(held)
    in_order :: !any || highest < rank
    lock(spin_lock)
    push_held(held, rank, cast[u64](cast[uintptr](spin_lock)))
    return in_order
}

/*
 * Like lock_ranked, but a lock of the same rank as the highest held may be taken too, if its address is above that
 * one's: the order for two locks of one kind, like two budgets.
 */
lock_ranked_after :: fn(spin_lock: ptr[mut SpinLock], rank: u32, held: ptr[mut HeldRanks]) -> bool {
    highest, highest_lock, any :: highest_held(held)
    address :: cast[u64](cast[uintptr](spin_lock))
    in_order :: !any || highest < rank || (highest == rank && highest_lock < address)
    lock(spin_lock)
    push_held(held, rank, address)
    return in_order
}

push_held :: fn(held: ptr[mut HeldRanks], rank: u32, address: u64) {
    count :: cast[usize](held.count)
    if count < held.ranks.count && count < held.locks.count {
        held.ranks[count] = rank
        held.locks[count] = address
    }
    held.count += 1
}

/*
 * Gives back spin_lock, of rank, taken with lock_ranked: whether it was held, as the holder's records say. Locks needn't
 * be given back in the order they were taken.
 */
unlock_ranked :: fn(spin_lock: ptr[mut SpinLock], rank: u32, held: ptr[mut HeldRanks]) -> bool {
    address :: cast[u64](cast[uintptr](spin_lock))
    unlock(spin_lock)
    count :: cast[usize](held.count)
    if count == 0 {
        return false
    }
    // Past what's kept, the lock given back is among those taken but not kept
    if count > MAX_HELD_RANKS {
        held.count -= 1
        return true
    }
    // The last record of it, removed, the ones after it moved down
    with {
        i := count
    }
    loop {
        if i == 0 {
            return false
        }
        i -= 1
        if i < held.ranks.count && i < held.locks.count && held.ranks[i] == rank && held.locks[i] == address {
            for j in i..<count - 1 {
                if j + 1 < held.ranks.count && j + 1 < held.locks.count {
                    held.ranks[j] = held.ranks[j + 1]
                    held.locks[j] = held.locks[j + 1]
                }
            }
            held.count -= 1
            return true
        }
    }
}

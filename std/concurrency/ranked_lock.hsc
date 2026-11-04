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

/** The most locks one holder holds at once that HeldRanks keeps; more are taken, but not checked. */
MAX_HELD_RANKS :: 16

/**
 * The ranks of the locks one holder holds, in the order they were taken: one per CPU or thread.
 *
 * Its zero value holds nothing. It's its holder's alone, so it isn't locked itself.
 */
HeldRanks :: struct {
    /** The rank of each lock held, oldest first; the first min(count, MAX_HELD_RANKS) are filled in. */
    ranks : u32[MAX_HELD_RANKS],
    /** The address of each lock held, matching ranks, for locks of one rank taken by address. */
    locks : u64[MAX_HELD_RANKS],
    /** How many locks are held, including any past MAX_HELD_RANKS, which aren't kept. */
    count : u32,
}

/**
 * Find the newest lock held, which has the highest rank when they were taken in order.
 *
 * @param held The holder's ranks.
 * @return rank The newest lock's rank, or 0 if there's none to look at.
 * @return lock The newest lock's address, or 0 if there's none to look at.
 * @return any Whether there's one: false when nothing's held, or more is held than MAX_HELD_RANKS keeps, so the newest
 *     isn't known.
 */
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

/**
 * Take a spin lock of a rank, and record it as held.
 *
 * It's taken whether or not it's in order; what to do about one that isn't is the caller's to decide.
 *
 * @param spin_lock The lock, which this spins for.
 * @param rank The lock's rank: higher ranks are taken after lower ones.
 * @param held The holder's ranks, this CPU's or thread's.
 * @return True if it was in order: nothing was held, or the newest rank held was below rank; also true when more is
 *     held than MAX_HELD_RANKS keeps, since then it can't be checked.
 */
lock_ranked :: fn(spin_lock: ptr[mut SpinLock], rank: u32, held: ptr[mut HeldRanks]) -> bool {
    highest, highest_lock, any :: highest_held(held)
    in_order :: !any || highest < rank
    lock(spin_lock)
    push_held(held, rank, cast[u64](cast[uintptr](spin_lock)))
    return in_order
}

/**
 * Take a spin lock of a rank, like lock_ranked, but allowing a lock of the same rank as the newest held after it.
 *
 * A lock of the same rank is in order if its address is above that one's: the order for two locks of one kind, like
 * two budgets.
 *
 * @param spin_lock The lock, which this spins for.
 * @param rank The lock's rank.
 * @param held The holder's ranks, this CPU's or thread's.
 * @return True if it was in order: nothing was held, the newest rank held was below rank, or it was rank and its lock
 *     was at a lower address; also true when more is held than MAX_HELD_RANKS keeps.
 */
lock_ranked_after :: fn(spin_lock: ptr[mut SpinLock], rank: u32, held: ptr[mut HeldRanks]) -> bool {
    highest, highest_lock, any :: highest_held(held)
    address :: cast[u64](cast[uintptr](spin_lock))
    in_order :: !any || highest < rank || (highest == rank && highest_lock < address)
    lock(spin_lock)
    push_held(held, rank, address)
    return in_order
}

/**
 * Record a lock as held, as the newest.
 *
 * @param held The holder's ranks.
 * @param rank The lock's rank.
 * @param address The lock's address. Past MAX_HELD_RANKS locks, it's counted but not kept.
 */
push_held :: fn(held: ptr[mut HeldRanks], rank: u32, address: u64) {
    count :: cast[usize](held.count)
    if count < held.ranks.count && count < held.locks.count {
        held.ranks[count] = rank
        held.locks[count] = address
    }
    held.count += 1
}

/**
 * Give back a spin lock taken with lock_ranked or lock_ranked_after, and remove its record.
 *
 * Locks needn't be given back in the order they were taken. The lock is unlocked even if the records don't have it.
 *
 * @param spin_lock The lock.
 * @param rank The rank it was taken with.
 * @param held The holder's ranks.
 * @return True if it was held, as the holder's records say, or more was held than MAX_HELD_RANKS keeps, so it can't be
 *     told; false if the records had no lock of that rank and address, which leaves them unchanged.
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

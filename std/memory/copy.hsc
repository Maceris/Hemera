package memory

import intrinsics from "base:intrinsics"

/**
 * Copy elements from one slice to another, as many as both have room for, at once rather than one at a time: a row of
 * pixels, or a block of bytes. Where the two overlap, what's copied is the source as it was before.
 *
 * @param into Where the elements go: its first min(into.count, from.count) are written; the rest are left.
 * @param from Where they come from: only read.
 * @return How many elements were copied: the smaller of the two counts, 0 when either is empty.
 */
copy :: fn[T](into : mut T[], from : T[]) -> usize {
    count :: if into.count < from.count { into.count } else { from.count }
    if count == 0 {
        return 0
    }
    intrinsics.mem_copy(cast[mut rawptr](into.data), cast[rawptr](from.data), count * size_of(T))
    return count
}

package intrinsics

import compiler from "base"

/*
 * Atomic operations, each on one naturally aligned value.
 *
 * Without a suffix, an operation is sequentially consistent. The suffixes choose a weaker
 * ordering: _acquire for loads and read-modify-writes, _release for stores and
 * read-modify-writes, _acquire_release for read-modify-writes, and _no_fence, which is
 * atomic but orders nothing else.
 *
 * A _weak compare-exchange may fail even when the value matched, which is cheaper on
 * architectures without a single compare-exchange instruction (ARM, RISC-V). Use it in
 * retry loops. Its ordering suffix comes after _weak.
 *
 * They're made by atomic_operations below, so they aren't written out here. Each is named for its
 * operation, then its type, then its ordering, and comes in every type: i8, u8, i16, u16, i32, u32,
 * i64, u64, i128, u128, int, uint, uintptr and rawptr. For a type T:
 *
 *   atomic_load_T[_acquire | _no_fence]
 *       : fn(target: ptr[T]) -> T
 *   atomic_store_T[_release | _no_fence]
 *       : fn(target: ptr[mut T], value: T)
 *   interlocked_and_T, interlocked_or_T, interlocked_xor_T, interlocked_exchange_T,
 *   interlocked_exchange_add_T[_acquire | _release | _acquire_release | _no_fence]
 *       : fn(target: ptr[mut T], value: T) -> T
 *   interlocked_increment_T, interlocked_decrement_T[_acquire | _release | _acquire_release | _no_fence]
 *       : fn(target: ptr[mut T]) -> (old: T)
 *   interlocked_compare_exchange_T[_weak][_acquire | _release | _acquire_release | _no_fence]
 *       : fn(target: ptr[mut T], exchange: T, expected: T) -> (old: T, success: bool)
 *
 * Every interlocked operation gives the value target held before it. A compare-exchange stores
 * exchange only if target held expected, and success says whether it did. For example:
 *
 *   count := atomic_load_u32_acquire(&shared.count)
 *   atomic_store_u64_release(&shared.ready, 1)
 *   before :: interlocked_exchange_add_uint(&total, 4)          // total was before, is now before + 4
 *   old :: interlocked_decrement_u32(&object.references)        // the last reference if old == 1
 *   _, claimed :: interlocked_compare_exchange_u32(&slot.owner, me, 0)
 *
 * To see them all, as Hemera, compile with --show-inserted=atomics.hsc:<the #insert's line>.
 */

#insert atomic_operations()

/*
 * Later loads/stores cannot move before earlier loads, but only for compiler
 * reordering. Does not emit instructions.
 */
compiler_fence_acquire : fn() : ---
/*
 * Later loads/stores cannot move before earlier loads, and also
 * earlier loads/stores cannot move after later stores, but only for compiler
 * reordering. Does not emit instructions.
 */
compiler_fence_acquire_release : fn() : ---
/*
 * Earlier loads/stores cannot move after later stores, but only for compiler
 * reordering. Does not emit instructions.
 */
compiler_fence_release : fn() : ---
/*
 * A full barrier, including store->load ordering, but only for compiler
 * reordering. Does not emit instructions.
 */
compiler_fence_sequentially_consistent : fn() : ---

/*
 * Later loads/stores cannot move before earlier loads.
 */
fence_acquire : fn() : ---
/*
 * Later loads/stores cannot move before earlier loads, and also
 * earlier loads/stores cannot move after later stores.
 */
fence_acquire_release : fn() : ---
/*
 * Earlier loads/stores cannot move after later stores.
 */
fence_release : fn() : ---
/*
 * A full barrier, including store->load ordering.
 */
fence_sequentially_consistent : fn() : ---

/*
 * The atomic operations, made from three lists: the types they come in, the orderings each kind of
 * operation takes, and the operations themselves, each with its signature.
 */
atomic_operations :: fn() -> compiler.Code {
    types :: compiler.Code.[
        compiler.type_code(i8), compiler.type_code(u8), compiler.type_code(i16), compiler.type_code(u16),
        compiler.type_code(i32), compiler.type_code(u32), compiler.type_code(i64), compiler.type_code(u64),
        compiler.type_code(i128), compiler.type_code(u128), compiler.type_code(int), compiler.type_code(uint),
        compiler.type_code(uintptr), compiler.type_code(rawptr),
    ]
    load_orderings :: string.["", "_acquire", "_no_fence"]
    store_orderings :: string.["", "_release", "_no_fence"]
    read_modify_write_orderings :: string.["", "_acquire", "_acquire_release", "_no_fence", "_release"]

    made : AtomicDeclarations
    for T in types {
        type_name :: compiler.code_text(T)
        for ordering in load_orderings {
            add_atomic(&made, #code {
                #insert compiler.name("atomic_load_", type_name, ordering) : fn(target: ptr[#insert T]) -> #insert T : ---
            })
        }
        for ordering in store_orderings {
            add_atomic(&made, #code {
                #insert compiler.name("atomic_store_", type_name, ordering) : fn(target: ptr[mut #insert T], value: #insert T) : ---
            })
        }
        for ordering in read_modify_write_orderings {
            // Each gives the value from before
            for operation in string.["and", "exchange", "exchange_add", "or", "xor"] {
                add_atomic(&made, #code {
                    #insert compiler.name("interlocked_", operation, "_", type_name, ordering)
                        : fn(target: ptr[mut #insert T], value: #insert T) -> #insert T : ---
                })
            }
            for operation in string.["increment", "decrement"] {
                add_atomic(&made, #code {
                    #insert compiler.name("interlocked_", operation, "_", type_name, ordering)
                        : fn(target: ptr[mut #insert T]) -> (old: #insert T) : ---
                })
            }
            for weak in string.["", "_weak"] {
                add_atomic(&made, #code {
                    #insert compiler.name("interlocked_compare_exchange_", type_name, weak, ordering)
                        : fn(target: ptr[mut #insert T], exchange: #insert T, expected: #insert T) -> (old: #insert T, success: bool) : ---
                })
            }
        }
    }
    // The rest hold no code, which a list leaves out
    return compiler.list(made.codes)
}

// The declarations atomic_operations makes, in the first count of codes.
AtomicDeclarations :: struct {
    codes : compiler.Code[1024],
    count : usize,
}

add_atomic :: fn(made: ptr[mut AtomicDeclarations], code: compiler.Code) {
    if made.count < made.codes.count {
        made.codes[made.count] = code
        made.count += 1
    }
    else {
        compiler.report_error(#caller_location, "more atomic operations than AtomicDeclarations holds")
    }
}

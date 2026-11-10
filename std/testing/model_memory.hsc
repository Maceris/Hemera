package testing

import runtime from "base"

/*
 * The model checker's memory (docs/testing.md, Model Checking): what its atomics read, as the C11 memory model lets them,
 * which a weakly ordered CPU can show, not only what the latest store left.
 *
 * Each atomic location keeps its newest MAX_LOCATION_STORES stores in modification order, each with its thread's vector
 * clock when it stored and the clock it releases. A load may read any store from the newest it has read or that
 * happens-before it to the newest of all; which, another of the schedule's choices, the newest first. An acquire load
 * takes on the release clock of what it read, a relaxed one keeps it for an acquire fence; a release store releases its
 * thread's clock, a relaxed one the clock of its thread's last release fence. A read-modify-write reads the newest store,
 * and carries on what it released, as a release sequence does. Sequentially consistent operations and fences also go
 * through one clock every such operation takes on and adds to, and a sequentially consistent load reads the newest store:
 * stricter than C11, so it may miss what C11 allows there, but never shows what it doesn't.
 *
 * A location's first store is what memory held when the model first saw it; every store is written to memory too, the
 * newest of them, so plain reads see it. Memory that no longer holds the newest store was written plainly, or reused for
 * something else, and its history starts again from what it holds (resync). A location past MAX_MODEL_LOCATIONS is done
 * sequentially consistently.
 */

/** The most atomic locations the model keeps stores for in one execution. */
MAX_MODEL_LOCATIONS :: 128
/** The most stores a location keeps, the newest; a load can read only these. */
MAX_LOCATION_STORES :: 8

/** A vector clock: each thread's count of its own stores and releases, as far as a thread has seen. */
ModelClock :: struct {
    times : u32[MAX_MODEL_THREADS],
}

/** A store to an atomic location. */
ModelStore :: struct {
    /** What it stored, zero-extended. */
    value : u64,
    /** Its thread. */
    thread : usize,
    /** Its thread's own time when it stored, which a load happens after if its thread has seen it. */
    time : u32,
    /** The clock an acquire reading it takes on: its thread's, for a release; its last release fence's otherwise. */
    released : ModelClock,
}

/** An atomic location the model keeps stores for. */
ModelLocation :: struct {
    /** Its address; 0 for a place not in use. */
    address : u64,
    /** Its width in bytes. */
    width : u32,
    /** Its newest stores, the oldest first, from stores[0]. */
    stores : ModelStore[MAX_LOCATION_STORES],
    /** How many of stores are in use. */
    count : usize,
    /** How many stores it's had, those dropped as it filled included: the number of the newest, plus one. */
    total : u64,
    /** For each thread, the number of the newest store it has read or made, which it can't read before: coherence. */
    seen : u64[MAX_MODEL_THREADS],
}

/** What the model keeps of each thread's view of memory, besides its fiber. */
ModelView :: struct {
    /** Its vector clock. */
    clock : ModelClock,
    /** Its clock at its last release fence, which its relaxed stores release. */
    fenced : ModelClock,
    /** What its relaxed loads read released, which its next acquire fence takes on. */
    pending : ModelClock,
    /**
     * Whether it stopped at a spin hint since its last load, so its next reads the newest store: stores become visible
     * in time, as every CPU makes them, which C11 alone doesn't promise, and a thread waiting for one would otherwise
     * be shown an old one for ever.
     */
    fresh : bool,
    /**
     * Whether its last load read an older store than the newest, so there's something newer for it to see: stopped at
     * a spin hint, it isn't waiting for another thread, as it can go on by reading again.
     */
    stale : bool,
}

/**
 * Take on another clock: each thread's time the later of the two.
 *
 * @param into The clock that grows.
 * @param from The clock taken on.
 */
join_clock #no_context :: fn(into: ptr[mut ModelClock], from: ptr[ModelClock]) {
    for &time, i in into.times {
        if i < from.times.count && from.times[i] > time^ {
            time^ = from.times[i]
        }
    }
}

/**
 * Find the location an atomic is on, made with what memory holds if it's new.
 *
 * @param model The model, whose locations may grow.
 * @param address The location.
 * @param width Its width.
 * @return Its place among the model's locations; null when they're full.
 */
location_of #no_context :: fn(model: ptr[mut Model], address: rawptr, width: u32) -> usize? {
    at :: cast[u64](cast[uintptr](address))
    for &each, i in model.locations {
        if i >= model.location_count {
            break
        }
        if each.address == at {
            return i
        }
    }
    index :: model.location_count
    if index >= model.locations.count {
        return null
    }
    first, success :: runtime.native_atomic(.Load, width, address, 0, 0)
    made :: &model.locations[index]
    made^ = ModelLocation.{address = at, width = width, count = 1, total = 1}
    // The first store, which happens before every thread's every access
    made.stores[0] = ModelStore.{value = first, thread = MAX_MODEL_THREADS}
    model.location_count = index + 1
    return index
}

/**
 * Start a location's history again from what memory holds, if that isn't its newest store: a plain write, or the memory
 * reused for something else, as a freed object's or a stack slot's is, which the model doesn't see. What's there then
 * happens before every thread's every access, as the location's first store does.
 *
 * @param location The location, whose stores and seen are reset if memory changed.
 * @param address Its address.
 */
resync #no_context :: fn(location: ptr[mut ModelLocation], address: rawptr) {
    held, read :: runtime.native_atomic(.Load, location.width, address, 0, 0)
    newest :: if location.count > 0 { location.count - 1 } else { cast[usize](0) }
    if location.count > 0 && newest < location.stores.count && location.stores[newest].value == held {
        return void
    }
    location.stores[0] = ModelStore.{value = held, thread = MAX_MODEL_THREADS}
    location.count = 1
    location.total += 1
    for &seen in location.seen {
        seen^ = location.total - 1
    }
}

/**
 * Tell whether a thread has seen a store, so its loads can't read an older one: the store's thread's time when it
 * stored is no later than the thread's clock says of that thread.
 *
 * @param store The store.
 * @param view The thread's view.
 * @return True if it happens before what the thread does next.
 */
happened #no_context :: fn(store: ptr[ModelStore], view: ptr[ModelView]) -> bool {
    if store.thread >= view.clock.times.count {
        return true
    }
    return store.time <= view.clock.times[store.thread]
}

/**
 * Do an atomic operation as the memory model lets it: a load reads one of the stores it may, chosen; a store adds one;
 * a read-modify-write reads the newest and adds one.
 *
 * @param model The model, whose locations, views and choices change.
 * @param operation What's done.
 * @param order Its memory order.
 * @param width Its location's width.
 * @param address The location.
 * @param value The value.
 * @param expected A compare-exchange's expected value.
 * @return old What it read.
 * @return success Whether a compare-exchange stored; true for the others.
 */
memory_atomic #no_context :: fn(model: ptr[mut Model], operation: runtime.ModelOperation, order: runtime.ModelOrder, width: u32,
    address: rawptr, value: u64, expected: u64) -> (old: u64, success: bool) {
    thread :: model.current
    found :: location_of(model, address, width)
    if (found is_none) || thread >= model.views.count {
        return runtime.native_atomic(operation, width, address, value, expected)
    }
    index :: found or_else 0
    if index >= model.locations.count {
        return runtime.native_atomic(operation, width, address, value, expected)
    }
    location :: &model.locations[index]
    resync(location, address)
    view :: &model.views[thread]
    acquires :: order == .Acquire || order == .AcquireRelease || order == .SequentiallyConsistent
    releases :: order == .Release || order == .AcquireRelease || order == .SequentiallyConsistent
    if order == .SequentiallyConsistent {
        join_clock(&view.clock, &model.sequential)
    }
    mask :: if width >= 8 { ~cast[u64](0) } else { (cast[u64](1) << (cast[u64](width) * 8)) - 1 }
    if operation == .Load {
        read :: read_store(model, location, thread, order == .SequentiallyConsistent)
        if read < location.stores.count {
            take_release(view, &location.stores[read].released, acquires)
            if order == .SequentiallyConsistent {
                join_clock(&model.sequential, &view.clock)
            }
            return location.stores[read].value, true
        }
        return 0, true
    }
    // Every other operation reads the newest store, if it reads one
    newest :: if location.count > 0 { location.count - 1 } else { cast[usize](0) }
    old := cast[u64](0)
    carried := ModelClock.{}
    if newest < location.stores.count {
        old = location.stores[newest].value
        carried = location.stores[newest].released
    }
    stored := value & mask
    match operation {
        case .Store => {}
        case .Exchange => {}
        case .Add => stored = (old + value) & mask
        case .Subtract => stored = (old - value) & mask
        case .And => stored = old & value & mask
        case .Or => stored = (old | value) & mask
        case .Xor => stored = (old ~ value) & mask
        case _ => {
            // A compare-exchange that finds something else only reads it
            if old != (expected & mask) {
                take_release(view, &carried, acquires)
                return old, false
            }
        }
    }
    if operation != .Store {
        take_release(view, &carried, acquires)
    }
    // Its thread's time moves on, and what it releases is its clock, or its last release fence's
    if thread < view.clock.times.count {
        view.clock.times[thread] += 1
    }
    released := if releases { view.clock } else { view.fenced }
    // A read-modify-write continues the release sequence of what it read
    if operation != .Store {
        join_clock(&released, &carried)
    }
    add_store(location, ModelStore.{value = stored, thread = thread, time = if thread < view.clock.times.count { view.clock.times[thread] } else { 0 },
        released = released}, thread)
    if order == .SequentiallyConsistent {
        join_clock(&model.sequential, &view.clock)
    }
    // The newest, for plain reads
    _, _ = runtime.native_atomic(.Store, width, address, stored, 0)
    return old, true
}

/**
 * Choose which store a load reads: from the newest its thread has read or made, or that happens before it, whichever is
 * newer, to the newest of all, the newest first; a sequentially consistent load reads the newest. Its thread has seen it
 * after.
 *
 * @param model The model, whose choices grow by one where there's more than one store to read.
 * @param location The location, whose seen changes.
 * @param thread The thread loading.
 * @param newest_only Whether only the newest may be read.
 * @return The store's place in the location's stores.
 */
read_store #no_context :: fn(model: ptr[mut Model], location: ptr[mut ModelLocation], thread: usize, newest_only: bool) -> usize {
    if location.count == 0 {
        return 0
    }
    newest :: location.count - 1
    // The oldest it may read: what it's seen already, or what happens before it
    first_number :: location.total - cast[u64](location.count)
    oldest := cast[usize](0)
    if thread < location.seen.count && location.seen[thread] > first_number {
        oldest = cast[usize](location.seen[thread] - first_number)
    }
    if thread < model.views.count {
        for i in 0..<location.count {
            if i < location.stores.count && i > oldest && happened(&location.stores[i], &model.views[thread]) {
                oldest = i
            }
        }
    }
    // After a spin hint, the newest (ModelView.fresh)
    fresh := false
    if thread < model.views.count {
        fresh = model.views[thread].fresh
        model.views[thread].fresh = false
    }
    if oldest > newest || newest_only || fresh {
        oldest = newest
    }
    back :: choose_option(model, newest - oldest + 1, false)
    read :: newest - back
    if thread < model.views.count {
        model.views[thread].stale = read != newest
    }
    if thread < location.seen.count {
        location.seen[thread] = first_number + cast[u64](read)
    }
    return read
}

/**
 * Take on what a store read released: at once for an acquire, or kept for the thread's next acquire fence.
 *
 * @param view The thread's view.
 * @param released What the store released.
 * @param acquires Whether the load acquires.
 */
take_release #no_context :: fn(view: ptr[mut ModelView], released: ptr[ModelClock], acquires: bool) {
    if acquires {
        join_clock(&view.clock, released)
    }
    else {
        join_clock(&view.pending, released)
    }
}

/**
 * Add a store to a location, its newest, the oldest dropped if it's full; its thread has seen it.
 *
 * @param location The location.
 * @param store The store.
 * @param thread Its thread.
 */
add_store #no_context :: fn(location: ptr[mut ModelLocation], store: ModelStore, thread: usize) {
    if location.count >= location.stores.count {
        for i in 1..<location.stores.count {
            location.stores[i - 1] = location.stores[i]
        }
        location.count = location.stores.count - 1
    }
    if location.count < location.stores.count {
        location.stores[location.count] = store
        location.count += 1
    }
    location.total += 1
    if thread < location.seen.count {
        location.seen[thread] = location.total - 1
    }
}

/**
 * Do a fence as the memory model has it: a release fence keeps its thread's clock for its relaxed stores, an acquire
 * fence takes on what its relaxed loads read released, and a sequentially consistent one does both, through the
 * sequentially consistent clock.
 *
 * @param model The model.
 * @param order The fence's order.
 */
memory_fence #no_context :: fn(model: ptr[mut Model], order: runtime.ModelOrder) {
    thread :: model.current
    if thread >= model.views.count {
        return void
    }
    view :: &model.views[thread]
    if order == .Acquire || order == .AcquireRelease || order == .SequentiallyConsistent {
        join_clock(&view.clock, &view.pending)
    }
    if order == .SequentiallyConsistent {
        join_clock(&view.clock, &model.sequential)
        join_clock(&model.sequential, &view.clock)
    }
    if order == .Release || order == .AcquireRelease || order == .SequentiallyConsistent {
        view.fenced = view.clock
    }
}

package model_checking

import runtime from "base"
import fiber from "std"
import testing from "std"

/*
 * The fiber pool's carrier queues under the model checker (docs/testing.md, Model Checking): a carrier adds fibers to
 * its own queue and takes them back while another steals half of it, and every fiber is taken once, by one of them,
 * none lost. The queue's slots are plain memory, which the model doesn't see; its head and tail are what's checked.
 */

/** How many fibers the owner queues. */
QUEUED :: 3

/** Two carriers' parts of a pool, the fibers queued, and how many times each was taken. */
Queues :: struct {
    pool : ptr[mut fiber.FiberPool],
    owner : ptr[mut fiber.PoolCarrier],
    thief : ptr[mut fiber.PoolCarrier],
    fibers : ptr[mut runtime.Fiber][QUEUED],
    taken : u32[QUEUED],
    /** How many executions took a fiber other than once. */
    wrong : u32,
}

queues_of :: fn(data: any) -> ptr[mut Queues] {
    return cast[ptr[ptr[mut Queues]]](data.data)^
}

/**
 * Count a fiber taken.
 *
 * @param queues The queues.
 * @param taken The fiber.
 */
count_taken :: fn(queues: ptr[mut Queues], taken: ptr[mut runtime.Fiber]) {
    for each, i in queues.fibers {
        if each == taken && i < queues.taken.count {
            queues.taken[i] += 1
        }
    }
}

owner_adds_and_takes : runtime.ThreadFunction : fn(data #escaping : any) {
    queues :: queues_of(data)
    for each in queues.fibers {
        fiber.add_local(queues.owner, each)
    }
    loop {
        taken :: fiber.take_local(queues.owner) or_break
        count_taken(queues, taken)
    }
}

thief_steals : runtime.ThreadFunction : fn(data #escaping : any) {
    queues :: queues_of(data)
    match fiber.steal_from(queues.thief, queues.owner) {
        case Some(first) => count_taken(queues, first)
        case None => return void
    }
    loop {
        taken :: fiber.take_local(queues.thief) or_break
        count_taken(queues, taken)
    }
}

queues_body : runtime.ThreadFunction : fn(data #escaping : any) {
    queues :: queues_of(data)
    queues.owner^ = fiber.PoolCarrier.{pool = queues.pool}
    queues.thief^ = fiber.PoolCarrier.{pool = queues.pool}
    for &each in queues.taken {
        each^ = 0
    }
    first :: testing.spawn(owner_adds_and_takes, data) or_return void
    second :: testing.spawn(thief_steals, data) or_return void
    testing.join(first)
    testing.join(second)
    for count in queues.taken {
        if count != 1 {
            queues.wrong += 1
            break
        }
    }
}

pool_queues_hand_each_fiber_out_once #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    queues :: runtime.new(Queues)
    defer runtime.free(queues)
    queues.pool = runtime.new(fiber.FiberPool)
    defer runtime.free(queues.pool)
    queues.owner = runtime.new(fiber.PoolCarrier)
    defer runtime.free(queues.owner)
    queues.thief = runtime.new(fiber.PoolCarrier)
    defer runtime.free(queues.thief)
    for &each in queues.fibers {
        each^ = runtime.new(runtime.Fiber)
    }
    defer {
        for each in queues.fibers {
            runtime.free(each)
        }
    }
    attempt :: runtime.new(testing.T)
    defer runtime.free(attempt)
    outcome :: testing.check_model(attempt, queues_body, queues)
    testing.expect(t, outcome is_ok, "every schedule runs")
    testing.expect_eq(t, queues.wrong, 0, "in every schedule, each fiber is taken once")
    return .Ok
}

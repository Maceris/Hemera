package fiber

import array from "base"
import intrinsics from "base"

FIBER_LOCAL_QUEUE_SIZE :: 255
FIBER_GLOBAL_QUEUE_INTERVAL :: 31
FIBER_RUN_NEXT_CAP :: 3
FIBER_MIN_FROZEN_CAPACITY :: 4096

FiberSchedulerGlobalData :: struct {
    global_queue : ptr[Fiber][..],
    thread_data : ptr[FiberSchedulerLocalData][..],
    should_stop : bool,
}

FiberSchedulerLocalData :: struct {
    global_data : ptr[FiberSchedulerGlobalData],
    local_queue : FiberQueue,
    run_next : ptr[Fiber]?,
    index : usize,
    tasks_since_last_global_pull : u8,
    run_next_count : u8,
    /*
     * The fiber currently running on this thread, so that yield knows what to freeze.
     * The fiber's stack top (where its frames start) lives in its stack_state,
     * and is set by fiber_start/fiber_thaw.
     */
    current_fiber : ptr[Fiber]?,
}

create_fiber :: fn(function: ThreadFunction, data: any? = null) -> ptr[Fiber] {
    result := new(Fiber)
    result.function = function
    result.data = data
    result.state = .NotStarted
}

create_fiber_scheduler :: fn() -> ptr[FiberSchedulerGlobalData] {
    result :: new(FiberSchedulerGlobalData)
}

run_fiber_scheduler : ThreadFunction : fn(data: any) {
    if data.type != ptr[FiberSchedulerGlobalData] {
        log_error("run_fiber_scheduler expected a pointer to FiberSchedulerGlobalData, but got %", data.type)
        return void
    }
    if context.is_running_on_a_fiber {
        log_error("run_fiber_scheduler is being called from a fiber")
        return void
    }
    global_data : ptr[FiberSchedulerGlobalData] : data.value

    local_data := new(FiberSchedulerLocalData)
    {
        //TODO(ches) synchronize access with a lock
        new_index :: global_data.thread_data.count
        array_add(global_data.thread_data, local_data)
        local_data.index = new_index
    }
    local_data.global_data = global_data

    push_context new_context {
        new_context.is_running_on_a_fiber = true
        new_context.fiber_data = cast[rawptr](local_data);
        new_context.fiber_yield_function = yield

        next_task : ptr[Fiber]? = null
        next_task_index : usize = 0
        exit : intrinsics.FiberExit

        loop {
            if global_data.global_queue.count == 0 {
                //TODO(ches) sleep
                continue
            }
            //TODO(ches) actually have a strategy for updating tasks
            //TODO(ches) grab and release locks for the queue

            next_task_index = (next_task_index + 1) % global_data.global_queue.count;
            next_task = global_data.global_queue[next_task_index]

            switch next_task.state {
                case .Running: continue
                case .NotStarted:
                    next_task.state = .Running
                    local_data.current_fiber = next_task
                    /*
                     * Calls the function with fiber_thaw_trampoline as its return address,
                     * and comes back here when the fiber yields or its function returns.
                     */
                    exit = intrinsics.fiber_start(&next_task.stack_state, next_task.function, next_task.data)
                case .Suspended:
                    next_task.state = .Running
                    local_data.current_fiber = next_task
                    /*
                     * Thaws only the innermost frozen frame (the one that called fiber_freeze) just
                     * below this stack pointer, restores the fiber's registers and jumps to where it yielded.
                     * Outer frames are thawed one at a time by fiber_thaw_trampoline as each frame returns.
                     * Comes back here, like a normal call, when the fiber yields again or finishes.
                     */
                    exit = intrinsics.fiber_thaw(&next_task.stack_state)
            }

            // Nothing from the fiber is left on this thread's stack now
            local_data.current_fiber = null

            switch exit {
                case .Yielded:
                    next_task.state = .Suspended
                case .Finished:
                    //TODO(ches) grab and release locks for the queue
                    array_remove_fast(global_data.global_queue, next_task_index)
                    if next_task.stack_state.frozen_frames.count > 0 {
                        free(next_task.stack_state.frozen_frames)
                    }
                    free(next_task)
            }
        }
        while !global_data.should_stop
    }
}

/*
 * Make sure there are at least `needed` free bytes below frozen_low,
 * since fiber_freeze can't allocate.
 */
ensure_frozen_capacity :: fn(state: ptr[mut intrinsics.FiberStackState], needed: usize) {
    if state.frozen_low >= needed {
        return void
    }

    used : usize : state.frozen_frames.count - state.frozen_low
    new_capacity : usize = state.frozen_frames.count * 2
    if new_capacity < used + needed {
        new_capacity = used + needed
    }
    if new_capacity < FIBER_MIN_FROZEN_CAPACITY {
        new_capacity = FIBER_MIN_FROZEN_CAPACITY
    }

    /*
     * The frozen frames grow downward like the stack, so keep them at the high end of the new buffer.
     * Moving them is fine: the only pointer into this buffer is the outermost thawed frame's saved BP,
     * and that frame is about to be frozen too, then re-patched when it is thawed again.
     */
    new_frames : u8[] = new_array(u8, new_capacity)
    if used > 0 {
        mem_copy_non_overlapping(
            cast[rawptr](cast[uintptr](new_frames.data) + cast[uintptr](new_capacity - used)),
            cast[rawptr](cast[uintptr](state.frozen_frames.data) + cast[uintptr](state.frozen_low)),
            used)
    }
    if state.frozen_frames.count > 0 {
        free(state.frozen_frames)
    }
    state.frozen_frames = new_frames
    state.frozen_low = new_capacity - used
}

yield :: fn() {
    if !context.is_running_on_a_fiber {
        // Returns to the actual yield call site, yielding is not reasonable
        return void
    }
    local_data : ptr[FiberSchedulerLocalData] : cast[ptr[FiberSchedulerLocalData]](context.fiber_data)
    current :: local_data.current_fiber or_return

    /*
     * Everything from this frame up to the stack top belongs to the fiber and is about to be frozen.
     * Growing the buffer calls other functions, which is fine since they return before the freeze.
     */
    live_bytes : usize : cast[usize](cast[uintptr](current.stack_state.stack_top) - cast[uintptr](intrinsics.get_stack_pointer()))
    ensure_frozen_capacity(&current.stack_state, live_bytes)

    /*
     * Saves the registers, copies [stack pointer, stack top) below frozen_low, and makes the
     * scheduler's fiber_start/fiber_thaw call return .Yielded.
     * This call only "returns" once the fiber is resumed, possibly on another thread,
     * so don't use local_data or current after this.
     */
    intrinsics.fiber_freeze(&current.stack_state)
}

package fiber

import array from "base"
import intrinsics from "base"

FIBER_LOCAL_QUEUE_SIZE :: 255
FIBER_GLOBAL_QUEUE_INTERVAL :: 31
FIBER_RUN_NEXT_CAP :: 3

FiberState :: enum {
    Blocked,
    Running,
    Waiting,
}

FiberSchedulerGlobalData :: struct {
    global_queue : ptr[Fiber][..],
    thread_data : ptr[FiberSchedulerLocalData][..],
}

FiberSchedulerLocalData :: struct {
    global_data : ptr[FiberSchedulerGlobalData],
    local_queue : FiberQueue,
    run_next : ptr[Fiber]?,
    index : usize,
    tasks_since_last_global_pull : u8,
    run_next_count : u8,
}

create_fiber() :: ptr[Fiber] {
    result := new(Fiber)
    result.frozen_stack = null
    result.state = .NotStarted
}

create_fiber_scheduler :: fn() -> ptr[FiberSchedulerGlobalData] {
    result :: new(FiberSchedulerGlobalData)
}

run_fiber_scheduler : ThreadFunction : fn(data: any) {
    //TODO(ches) do the scheduler stuff
    
    if data.type != ptr[FiberSchedulerGlobalData] {
        log_error("run_fiber_scheduler expected a pointer to FiberSchedulerGlobalData, but got %", data.type)
        return void
    }
    global_data : ptr[FiberSchedulerGlobalData] : data.value

    local_data : new(FiberSchedulerLocalData)
    {
        //TODO(ches) synchronize access with a lock
        new_index :: global_data.thread_data.count
        array_add(global_data.thread_data, local_data)
        local_data.index = new_index
    }
    local_data.global_data = global_data

    new_context : Context
    new_context.is_running_on_a_fiber = true
    new_context.fiber_yield_function = yield

    push_context new_context {
        
    }
}

thaw_one_stack_frame :: fn(fiber: Fiber) {
    frame_size : u32

    frozen_stack :: fiber.frozen_stack or_return void

    if frozen_stack.size == 0 {

    }

    //TODO(ches) if we are out of stack frames, consider the task done
    //TODO(ches) copy over the buffer, if there is one, to the space on the next stack frame where it should have gone
    //TODO(ches) load a buffer for the return value of the next stack frame on top of fiber_base_pointer
    //TODO(ches) then load one stack frame from the current coroutine on top of new buffer, or fiber_base_pointer if no return
    //TODO(ches) set the return pointer from this function to the start of that new stack frame
    //TODO(ches) update the return pointer of that new frame to this function
}

yield :: fn() {
    if !context.is_running_on_a_fiber {
        // Returns to the actual yield call site, yielding is not reasonable
        return void
    }
    stack_max : rawptr : get_return_address()
    stack_min : rawptr : context.fiber_base_pointer
    stack_size : uintptr : cast[uintptr](stack_max) - cast[uintptr](stack_min)
    //TODO(ches) store the stack frame contents and size

    //TODO(ches) how do the stacks return locations work now that we may have moved the stack?
    //TODO(ches) can we copy over just one frame at a time, with room for return values? How much room?

    set_return_address(stack_min)
    /*
     * Returns to where the fiber function was run from, not what called yield.
     * The actual return from the yield function, from the perspective of 
     * the function calling it, happens after the fiber is resumed.
     */
}

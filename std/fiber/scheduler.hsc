package fiber

import intrinsics from "base"

FiberState :: enum {
    Blocked,
    Running,
    Waiting,
}

FiberScheduler :: struct {
    active_fibers : ptr[mut Fiber][..]
}

start_fiber_scheduler :: fn(scheduler: ptr[mut FiberScheduler]) {
    //TODO(ches) do the scheduler stuff

    new_context : Context
    new_context.is_running_on_a_fiber = true
    new_context.fiber_yield_function = yield

    push_context new_context {
        
    }
}

thaw_one_stack_frame :: fn(fiber: Fiber) {
    frame_size : u32

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

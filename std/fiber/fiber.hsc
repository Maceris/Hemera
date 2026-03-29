package fiber

import runtime from "base"

Fiber :: struct {
    function : ThreadFunction,
    data : any?,
    frozen_stack : u8[]?,
    /*
     * When calling yield this is the return address from yield, so we can resume where it yielded.
     * When we thaw a partial stack, this is where the return address of the first thawed stack frame goes,
     * so we know where it was going to return to, even though we update the frame to now return back to the scheduler.
     */
    last_frame_return_address: rawptr,
    state : FiberState,
}

FiberState :: enum {
    NotStarted,
    Running,
    Suspended,
}
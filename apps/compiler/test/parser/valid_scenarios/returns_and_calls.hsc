package valid_scenarios

two_results :: fn() -> (int, int) { return 2, 3 }
named_results :: fn() -> (x, y: int) { return 4, 5 }
typed_named_results :: fn() -> (found: ptr[Fiber]?, error: AllocatorError?) { return null, null }
nested_fn_results :: fn() -> (int, (fn() -> int)) { return 1, one_result }

calls :: fn() {
    create_rectangle(x=1, y=2, width=50, height=75)
    create_rectangle(1, 2, height=75, width=50)
}

variants :: fn() -> Result[int, string] {
    if failed() {
        return .Error("failed")
    }
    return .Ok(3)
}

or_return_void :: fn(carrier: ptr[CarrierBlock]) {
    current :: carrier.current_fiber or_return void
    local_data :: carrier.scheduler_data
}

or_return_with_value :: fn() -> int {
    value :: maybe_value() or_return -1
    return value
}

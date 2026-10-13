package valid_scenarios

underscore_assignment :: fn() {
    _ = one_result()
    _, second = two_results()
    first, _ = two_results()
    _ = interlocked_increment_u32_no_fence(&count)
}

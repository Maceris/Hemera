package valid_scenarios

switch_cases :: fn(task: ptr[Task], value: char) -> int {
    // Like C, a case runs every statement up to the next case
    switch task.state {
        case .Running: print("running")
        case .NotStarted:
            task.state = .Running
            exit = start(task)
        case .Suspended:
            task.state = .Running
        #fall_through
        case .Finished: {
            print("finished")
        }
    }
    switch value {
        case '0': return 0
        case '1'..='9': return 1
        case _: return -1
    }
}

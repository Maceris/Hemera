package valid_scenarios

match_forms :: fn(result: Result[int, string], x: int) -> int {
    // Each arm starts with case, so they need no separators
    name : string : match x {
        case 1 => "one"
        case 2, 3 => "two or three"
        case 4..<10 => "small"
        case _ => "big"
    }
    doubled :: match result {
        case Ok(value) => value * 2
        case Error(_) => 0
    }
    match result {
        case Ok(value) => {
            print(value)
            print(name)
        }
        case Error(message) => return -1
    }
    match settings.mode {
        case .Fast => print("fast")
        case .Slow => print("slow")
    }
    return match result {
        case Ok(value) => value
        case _ => doubled
    }
}

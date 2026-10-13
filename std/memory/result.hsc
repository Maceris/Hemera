package memory

is_error :: fn[T, E](result: Result[T, E]) -> bool {
    return match result {
        case Error(_) => true
        case _ => false
    }
}

is_ok :: fn[T, E](result: Result[T, E]) -> bool {
    return match result {
        case Ok(_) => true
        case _ => false
    }
}

unwrap_list :: fn[T, E](results: Result[T, E][..]) -> Result[T[..], E] {
    new_results: T[..]

    for result in results {
        match result {
            case Error(E) => return .Error(E)
            case Ok(T) => array_add(&new_results, T)
        }
    }
    
    return .Ok(new_results)
}

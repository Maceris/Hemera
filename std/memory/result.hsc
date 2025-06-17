package memory

Result :: union[T, E] {
    Ok(T),
    Error(E),
}

is_error :: fn[T, E](result: Result[T, E]) -> bool {
    return match result {
        Error(_) => true,
        _ => false,
    }
}

is_ok :: fn[T, E](result: Result[T, E]) -> bool {
    return match result {
        Ok(_) => true,
        _ => false,
    }
}

unwrap_list :: fn[T, E](results: Result[T, E][..]) -> Result[T[..], E] {
    new_results: T[..]

    for result in results {
        match result {
            Error(E) => return Result::Error(E),
            Ok(T) => array_add(&new_results, T),
        }
    }
    
    return Result::Ok(new_results)
}

unwrap_or :: fn[T, E](result: Result[T, E], def: T) -> T {
    match optional {
        Ok(T) => return T,
        Error(_) => return def,
    }
}

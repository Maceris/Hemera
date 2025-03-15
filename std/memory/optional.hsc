package memory

Optional :: union<T> {
    None,
    Some(T),
}

is_none :: fn<T>(optional: Optional<T>) -> bool {
    return match optional {
        None => true,
        _ => false,
    }
}

is_some :: fn<T>(optional: Optional<T>) -> bool {
    return match optional {
        Some(_) => true,
        _ => false,
    }
}

unwrap_or :: fn<T>(optional: Optional<T>, def: T) -> T {
    match optional {
        Some(T) => return T,
        None => return def,
    }
}

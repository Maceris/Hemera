package memory

Optional :: union<T> {
    None,
    Some(T),
}

is_none :: fn(optional : Optional<T>) -> bool {
    return match optional {
        None => true,
        _ => false,
    }
}

is_some :: fn(optional : Optional<T>) -> bool {
    return match optional {
        Some(_) => true,
        _ => false,
    }
}

unwrap :: fn(optional: Optional<T>) -> T {
    match optional {
        Some(T) => return T,
        None => panic("Provided a `None` Optional to `unwrap(Optional)`"),
    }
}

unwrap_or :: fn(optional: Optional<T>, def: T) -> T {
    match optional {
        Some(T) => return T,
        None => return def,
    }
}

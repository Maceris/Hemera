package memory

Option :: union<T> {
    None,
    Some(T),
}

is_none :: fn<T>(option: Option<T>) -> bool {
    return match option {
        None => true,
        _ => false,
    }
}

is_some :: fn<T>(option: Option<T>) -> bool {
    return match option {
        Some(_) => true,
        _ => false,
    }
}

unwrap_or :: fn<T>(option: Option<T>, def: T) -> T {
    match option {
        Some(T) => return T,
        None => return def,
    }
}

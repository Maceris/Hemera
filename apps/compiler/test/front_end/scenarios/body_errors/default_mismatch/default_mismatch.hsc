package default_mismatch

// A default has to fit its parameter's type, like any value given for it
greet :: fn(times: int = "twice") -> int {
    return times
}

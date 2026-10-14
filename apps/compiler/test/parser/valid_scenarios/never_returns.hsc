package valid_scenarios

// On declarations, after the name
exit #never_returns :: fn(code: int) {
    loop {
        halt()
    }
}
trap #never_returns : fn() : ---
exported_exit #export #never_returns :: fn() {
    trap()
}

// In function types, after the signature
Handler :: alias fn(location: SourceCodeLocation, message: string) #never_returns
Callbacks :: struct {
    on_fatal : fn(code: int) #never_returns,
    on_error : fn() -> int,
    entry : fn() #never_returns?,
}
literal_handler : Handler : fn(location: SourceCodeLocation, message: string) #never_returns {
    trap()
}

never_returns :: fn(start: (fn(entry: (fn() #never_returns))), value: int?) -> int {
    found :: value or_else 0
    if found < 0 {
        exit(1)
    }
    return found
}

// Other directives after a function type start the next statement
ThreadFunction :: fn(any) -> void
#if OS == .Windows {
    WINDOWS :: true
}

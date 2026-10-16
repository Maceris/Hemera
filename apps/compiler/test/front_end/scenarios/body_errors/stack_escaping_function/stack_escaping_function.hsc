package stack_escaping_function

// A function that keeps its parameter can't be used where callers expect it doesn't
Keeps :: fn(data #escaping : string)
Borrows :: fn(data: string)

keeps : Keeps : fn(data #escaping : string) {}
borrows : Borrows : fn(data: string) {}

main :: fn() {
    // Allowed: one that doesn't keep it, where keeping is allowed
    allowed : Keeps = borrows
    not_allowed : Borrows = keeps
}

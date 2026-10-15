package signed_enum

// An enum is backed by an unsigned integer
Level :: enum #backed_by(i8) {
    Low,
    High,
}

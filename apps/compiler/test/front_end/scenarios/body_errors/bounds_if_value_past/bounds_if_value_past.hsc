package bounds_if_value_past

// One branch of the if gives one past the count
past :: fn(text: u8[], want: usize) -> u8[] {
    n :: if want < text.count { want } else { text.count + 1 }
    return text[0..<n]
}

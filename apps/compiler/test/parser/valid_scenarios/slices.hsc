package valid_scenarios

slices :: fn(a: int[10]) {
    b : int[] : a[2..<5]
    c : int[] : a[2..=4]
    d : int[] : a[5..]
    e : int[] : a[..<5]
    f : int[] : a[..=5]
    g : int[] : a[0..<a.count]
}

// [..] in a type used as a value
Bytes :: ptr[u8][..]

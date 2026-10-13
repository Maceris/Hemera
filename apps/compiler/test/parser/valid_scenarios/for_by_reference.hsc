package valid_scenarios

for_by_reference :: fn(values: int[..]) {
    for &value in values {
        value^ = 0
    }
    for &value, index in values {
        value^ = index
    }
    for value, index in values {
        print(value + index)
    }
    for i in 0..<10 #reverse {
        print(i)
    }
}

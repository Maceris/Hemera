package valid_scenarios

multi_name_declarations :: fn() {
    a, b :: two_results()
    result, _ :: new(Foo)
    _, error := new_array(u8, 16)
    year, month, day : int : date(now())
    with {
        first, second := two_results()
    }
    loop {
        break
    }
}

package valid_scenarios

// Values that start with an identifier are expressions, which covers naming a type.
// alias is optional, except after distinct.
Alias :: int
Alias2 :: alias int
Alias3 :: Alias
Meters :: distinct alias f64
SAME_AS_OTHER :: OTHER_CONSTANT
FIRST_FIELD :: settings.first

declaration_values :: fn(info: ptr[TypeInfoArray], node: ptr[Node]?, dimension: usize) {
    count := info.dimensions[dimension].count
    size :: info.base_type.size
    copy := node
    loop {
        current :: node or_break
        next :: current.next or_continue
    }
    value :: maybe_value() or_else 4
    uninitialized : Rectangle = ---
}

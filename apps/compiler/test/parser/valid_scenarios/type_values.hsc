package valid_scenarios

// Types used as values, like when comparing type values or passing them to functions
GlobalDataPointer :: ptr[mut GlobalData]
Lookup :: Map[string, ptr[mut Node]]
Handler :: Callbacks[fn(int) -> bool]

type_values :: fn(data: any) -> bool {
    if data.type_ != ptr[mut GlobalData] {
        return false
    }
    size :: size_of(Result[int, string])
    names :: new(ptr[mut Node][..])
    return types_are_aliases(data.type_, ptr[mut GlobalData])
}

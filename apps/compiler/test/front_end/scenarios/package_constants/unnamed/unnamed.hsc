package unnamed

import compiler from "base:compiler"

// A struct of its own called PackageInfo, whose constants don't count
PackageInfo :: struct {
    constants : int[],
}

own_count :: fn(package: PackageInfo) -> usize {
    return package.constants.count
}

// Base's PackageInfo, but other fields of it
function_count :: fn(package: compiler.PackageInfo) -> usize {
    return package.functions.count + package.types.count
}

main :: fn() -> int {
    return 0
}

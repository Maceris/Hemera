package named

import compiler from "base:compiler"

// Names base's PackageInfo.constants, so describing a package for this program works out every constant's value
constant_count :: fn(package: compiler.PackageInfo) -> usize {
    return package.constants.count
}

main :: fn() -> int {
    return 0
}

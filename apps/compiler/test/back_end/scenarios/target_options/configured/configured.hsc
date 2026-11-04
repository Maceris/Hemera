// A target built with debug info for release: main returns 42 if its code is told it's built for release.
package configured

import compiler from "base"

RELEASE :: #run compiler.current_build_options().configuration == .Release

main :: fn() -> int {
    if RELEASE {
        return 42
    }
    return 1
}

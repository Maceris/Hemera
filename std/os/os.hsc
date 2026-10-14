package os

import intrinsics from "base"

exit #never_returns :: fn(code: int) {
    //TODO(ches) exit the program
    // Until then, stop it without the exit code
    intrinsics.trap()
}

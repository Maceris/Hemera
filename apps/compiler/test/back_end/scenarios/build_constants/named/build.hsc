/*
 * A build package whose check names PackageInfo.constants, so describing the app works out every constant's value:
 * the check reports LIMIT's and GREETING's as a warning, or an error if one has none.
 */
package build

import compiler from "base:compiler"

check_constants :: fn(target: ptr[compiler.BuildOptions], program: ptr[compiler.ProgramInfo]) -> bool {
    limit := 0
    greeting := ""
    for &constant in program.root.constants {
        if constant.value.data == null {
            compiler.report_error(constant.location, "% has no value", constant.name)
            return false
        }
        if constant.name == "LIMIT" && constant.type == int {
            limit = cast[ptr[int]](constant.value.data)^
        }
        if constant.name == "GREETING" && constant.type == string {
            greeting = cast[ptr[string]](constant.value.data)^
        }
    }
    compiler.report_warning(program.root.location, "LIMIT is %, GREETING is %", limit, greeting)
    return true
}

build :: fn() {
    app := compiler.command_line_options()
    app.name = "app"
    app.root = "../app"
    app.output_path = compiler.target_setting("output")
    target :: compiler.add_target(app)
    compiler.add_check(check_constants)
}

#run build()

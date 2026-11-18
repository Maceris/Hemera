/*
 * A build package whose check never names PackageInfo.constants, so describing the app leaves its constants'
 * values out: the check finds LIMIT's with find_constant, and reports it as a warning.
 */
package build

import compiler from "base:compiler"

check_limit :: fn(target: ptr[compiler.BuildOptions], program: ptr[compiler.ProgramInfo]) -> bool {
    limit :: compiler.find_constant(program.root, "LIMIT") or_else compiler.ConstantInfo.{}
    if limit.type != int || limit.value.data == null {
        compiler.report_error(program.root.location, "find_constant gave LIMIT no value")
        return false
    }
    compiler.report_warning(limit.location, "LIMIT is %", cast[ptr[int]](limit.value.data)^)
    return true
}

build :: fn() {
    app := compiler.command_line_options()
    app.name = "app"
    app.root = "../app"
    app.output_path = compiler.target_setting("output")
    target :: compiler.add_target(app)
    compiler.add_check(check_limit)
}

#run build()

/*
 * A build package for the back end's test: it registers the app target, a check that every target's main
 * returns an exit code, and a step after every target. The check and the step each report a warning, so the
 * test can tell they ran. Settings from the test say where the app goes.
 */
package build

import compiler from "base"

check_program :: fn(target: ptr[compiler.BuildOptions], program: ptr[compiler.ProgramInfo]) -> bool {
    main_function :: compiler.find_function(program.root, "main") or_else compiler.FunctionInfo.{}
    if main_function.return_values.count != 1 {
        compiler.report_error(main_function.location, "main should return an exit code")
        return false
    }
    compiler.report_warning(main_function.location, "checked %", target.name)
    return true
}

report_outputs :: fn(inputs: compiler.TargetOutput[]) -> bool {
    for &input in inputs {
        compiler.report_warning(#caller_location, "built % at %", input.name, input.path)
    }
    return true
}

build :: fn() {
    app := compiler.command_line_options()
    app.name = "app"
    app.root = "../app"
    app.output_path = compiler.target_setting("output")
    target :: compiler.add_target(app)
    compiler.add_check(check_program)
    step :: compiler.add_step(report_outputs, compiler.all_targets())
}

#run build()

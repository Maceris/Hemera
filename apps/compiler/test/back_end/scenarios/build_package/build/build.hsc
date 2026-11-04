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
    defaults :: reflects_defaults(program)
    if defaults != "" || !reflects_bindings(program, &main_function) {
        compiler.report_error(main_function.location, "the app's functions aren't reflected as they're declared: %", defaults)
        return false
    }
    compiler.report_warning(main_function.location, "checked %", target.name)
    return true
}

// scale's constant defaults have their values; value has none, and where's is the caller's, so it has none either
reflects_defaults :: fn(program: ptr[compiler.ProgramInfo]) -> string {
    scale :: compiler.find_function(program.root, "scale") or_return "no scale"
    if scale.parameters.count != 5 {
        return "scale doesn't have 5 parameters"
    }
    if (scale.parameters[0].default_value is_some) || (scale.parameters[4].default_value is_some) {
        return "scale's value or where has a default"
    }
    factor :: scale.parameters[1].default_value or_return "factor has no default"
    label :: scale.parameters[2].default_value or_return "label has no default"
    mode :: scale.parameters[3].default_value or_return "mode has no default"
    // The app's Mode is the target's type, so it's compared by name (see ConstantInfo)
    if factor.type != int || cast[ptr[int]](factor.data)^ != 3 || label.type != string || cast[ptr[string]](label.data)^ != "scaled"
        || type_info_of(mode.type).variant != .ENUM || cast[ptr[u32]](mode.data)^ != 1 {
        return "a default has the wrong value"
    }
    return ""
}

// main's call to pick is to its instance, whose generic parameter T is bound to int; pick itself binds nothing
reflects_bindings :: fn(program: ptr[compiler.ProgramInfo], main_function: ptr[compiler.FunctionInfo]) -> bool {
    generic :: compiler.find_function(program.root, "pick") or_return false
    if generic.generic_bindings.count != 0 {
        return false
    }
    for &call in main_function.calls {
        if call.name == "pick[int]" {
            instance :: compiler.find_function(program.root, call.name) or_return false
            return instance.generic_bindings.count == 1 && instance.generic_bindings[0].original_name == "T"
                && instance.generic_bindings[0].value == int && instance.parameters.count == 2
        }
    }
    return false
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

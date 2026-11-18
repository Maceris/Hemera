/*
 * A build package with several targets, built at once (--jobs): four of the same package, each given an
 * answer of its own, and with the setting broken=yes, one that doesn't check. Settings from the test say
 * where each goes. Its check reads every record each target is described with, which targets write at once.
 */
package build

import compiler from "base:compiler"
import runtime from "base:runtime"

// Every package, file, import, function and type a target is described with has its name and place
whole_records :: fn(target: ptr[compiler.BuildOptions], program: ptr[compiler.ProgramInfo]) -> bool {
    if program.packages.count == 0 {
        compiler.report_error(#source_location, "% is described with no packages", target.name)
        return false
    }
    for &package in program.packages {
        whole := package.name != "" && package.path != "" && package.files.count > 0
        for file in package.files {
            whole = whole && file != ""
        }
        for &import in package.imports {
            whole = whole && import.path != "" && import.alias != "" && import.location.file_path != ""
        }
        for &function in package.functions {
            whole = whole && function.name != "" && function.location.file_path != ""
        }
        for &type in package.types {
            whole = whole && type.name != "" && type.location.file_path != ""
        }
        if !whole {
            compiler.report_error(package.location, "% isn't described whole for %", package.name, target.name)
            return false
        }
    }
    return true
}

NAMES :: string.["app_0", "app_1", "app_2", "app_3"]
ANSWERS :: string.["10", "11", "12", "13"]
OUTPUTS :: string.["output_0", "output_1", "output_2", "output_3"]

build :: fn() {
    for name, i in NAMES {
        app := compiler.command_line_options()
        app.name = name
        app.root = "../app"
        app.output_path = compiler.target_setting(OUTPUTS[i])
        runtime.array_add(&app.settings, compiler.TargetSetting.{name = "answer", value = ANSWERS[i]})
        target :: compiler.add_target(app)
    }
    if compiler.target_setting("broken", default = "no") == "yes" {
        broken := compiler.command_line_options()
        broken.name = "broken"
        broken.root = "../broken"
        broken.output_path = compiler.target_setting("broken_output")
        target :: compiler.add_target(broken)
    }
    compiler.add_check(whole_records)
}

#run build()

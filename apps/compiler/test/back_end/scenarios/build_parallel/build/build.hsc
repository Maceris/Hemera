/*
 * A build package with several targets, built at once (--jobs): four of the same package, each given an
 * answer of its own, and with the setting broken=yes, one that doesn't check. Settings from the test say
 * where each goes.
 */
package build

import compiler from "base"
import runtime from "base"

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
}

#run build()

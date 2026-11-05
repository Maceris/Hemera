/*
 * A build package whose targets each set one of TargetOptions or BuildOptions that add_target reads: a configuration
 * that doesn't follow the debug info, a linker of the build's own, by its path, a linker that isn't on the PATH, and a
 * max_frame_size that a function's frame is larger than. Settings from the test say where each goes, and where the
 * linker is.
 */
package build

import compiler from "base"

build :: fn() {
    // Debug info, but built for release, which its code checks
    configured := compiler.command_line_options()
    configured.name = "configured"
    configured.root = "../configured"
    configured.output_path = compiler.target_setting("configured_output")
    configured.backend_options.debug_info = true
    configured.configuration = .Release
    configured.target_options.linker = compiler.target_setting("linker")
    target :: compiler.add_target(configured)

    unlinked := compiler.command_line_options()
    unlinked.name = "unlinked"
    unlinked.root = "../configured"
    unlinked.output_path = compiler.target_setting("unlinked_output")
    unlinked.target_options.linker = "hemera-no-such-linker"
    second :: compiler.add_target(unlinked)

    // Unoptimized, so its large buffer stays in its frame
    framed := compiler.command_line_options()
    framed.name = "framed"
    framed.root = "../framed"
    framed.output_path = compiler.target_setting("framed_output")
    framed.backend_options.optimization_level = .O0
    framed.target_options.max_frame_size = 16384
    third :: compiler.add_target(framed)
}

#run build()

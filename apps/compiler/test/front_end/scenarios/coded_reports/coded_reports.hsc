package coded_reports

import compiler from "base:compiler"

/*
 * compiler.report's diagnostics, with codes of their own (docs/compilation.md, Diagnostics): a warning with the
 * package's own prefix, and an error with another's; then four that break its rules, each an error in its place.
 */

#run compiler.report(.Warning, #package_name, "W0001", #source_location, "warned at line %", #line)
#run compiler.report(.Error, "fonts", "E0042", #source_location, "an error of fonts'")

// A warning's code starting with E, the compiler's prefix, a prefix that isn't a name, and a code with a -
#run compiler.report(.Warning, #package_name, "E0001", #source_location, "the wrong letter")
#run compiler.report(.Error, "hemera", "E0001", #source_location, "the compiler's prefix")
#run compiler.report(.Warning, "two words", "W0001", #source_location, "not a name")
#run compiler.report(.Warning, #package_name, "W-1", #source_location, "not letters and digits")

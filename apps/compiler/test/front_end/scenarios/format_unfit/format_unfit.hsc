package format_unfit

import runtime from "base"

// Format strings written in place, checked against their values (docs/format_strings.md)
main :: fn() {
    runtime.log_info("fine: %{08x} %2{>6} %{.2} %% %{*^9}", 255, "right", 1.5, true)
    runtime.log_info("too few: % %", 1)
    runtime.log_info("bad: %{08q}", 1)
    runtime.log_info("zero: %0", 1)
    runtime.log_info("hex string: %{x}", "text")
    runtime.log_info("plus string: %{+}", "text")
    runtime.log_info("prefix decimal: %{#}", 3)
    runtime.log_info("precision int: %{.2}", 3)
}

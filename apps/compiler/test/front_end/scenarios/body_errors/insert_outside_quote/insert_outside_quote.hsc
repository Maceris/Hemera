package insert_outside_quote

import compiler from "base"

// #insert outside a #code quote, which comes later
main :: fn() {
    code :: #code(1)
    #insert code
}

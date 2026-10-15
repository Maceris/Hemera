package io

import formatting

print :: fn(text: string) {
    todo("print text")
}

printf :: fn(format_string: string, args: any...) {
    format(format_string, args)
    |> print()
}

println :: fn(text: string) {
    todo("print line")
}

package io

import formatting

print :: fn(text: string) {
    //TODO(ches) print text
}

printf :: fn(format: string, args: any...) {
    format(format, args) 
    |> print()
}

println :: fn(text: string) {
    //TODO(ches) print line
}

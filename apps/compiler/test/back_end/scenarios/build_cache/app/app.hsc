// The build cache's test's app: it exits with its answer file's first byte, so changing the file changes it.
package app

ANSWER :: #file_data("answer.txt")

main :: fn() -> int {
    return cast[int](ANSWER[0])
}

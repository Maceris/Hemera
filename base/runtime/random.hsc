package runtime

Random :: struct {
    data : rawptr,
    fill : fn(data: mut rawptr, bytes: mut u8[])
}
package runtime

Allocator_Error :: enum u8 {
    None               = 0,
    OutOfMemory        = 1,
    InvalidPointer     = 2,
    InvalidArgument    = 3,
    ModeNotImplemented = 4,
}

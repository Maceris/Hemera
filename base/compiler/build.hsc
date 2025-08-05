package compiler

BuildOptions :: struct {
    backend_options : BackendOptions,
    configuration : Configuration,
    target_options : TargetOptions,
}

BackendOptions :: struct {
    backend_type : BackendType,
    llvm_options : LLVMOptions,
}

LLVMOptions :: struct {

}

BackendType :: enum {
    LLVM,
}

Configuration :: enum {
    Debug,
    Release
}

TargetOptions :: struct {
    architecture : Architecture,
    os : OperatingSystem,
    output_type : OutputType,
}

OutputType :: enum {
    DynamicLibrary,
    Executable,
    Nothing,
    StaticLibrary,
}

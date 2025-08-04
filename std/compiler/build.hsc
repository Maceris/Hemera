package compiler

Architecture :: enum {
    arm,
    arm64,
    x86,
    x86_64,
}

BackendOptions :: struct {
    llvm_options : LLVMOptions,
}

LLVMOptions :: struct {

}

BackendType :: enum {
    LLVM,
}

BuildOptions :: struct {
    backend_options : BackendOptions,
    configuration : Configuration,
    target_options : TargetOptions,
}

Configuration :: enum {
    Debug,
    Release
}

OS :: enum {
    Linux,
    Mac,
    Windows,
}

OutputType :: enum {
    DynamicLibrary,
    Executable,
    Nothing,
    StaticLibrary,
}

TargetOptions :: struct {
    architecture : Architecture,
    os : OS,
    output_type : OutputType,
}

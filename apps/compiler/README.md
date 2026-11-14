# Compiler

This is the compiler for Hemera.

# Projects

The main projects are:

* generate_errors - Used to convert errors/warnings from text files to C++ code with doc comments
* Hemera - The executable part, essentially just a main method
* HemeraLib - The core project, built as a library so we can run tests
* HemeraTest - Unit test suite for the compiler
* HMIR - An MLIR dialect (should be at MLIR/Libraries/HMIR in Visual Studio)

# Requirements

The LLVM requirements apply, see https://llvm.org/docs/GettingStarted.html#software.

* [CMake](http://www.cmake.org/) >=3.20.0
* python >=3.8
* zlib >=1.2.3.4
* libxml2

# Building

This project uses submodules for some third party libraries, and so the `--recursive` flag must be used when cloning the
repository in order to build.

```bash
$ git clone --recursive https://github.com/Maceris/Hemera.git
```

If you accidentally clone without using `--recursive`, (or to update the source tree after a new submodule has been added),
run this command to update dependencies:
```bash
$ git submodule update --init --recursive
```

The build starts from the repository's root, whose `CMakeLists.txt` adds the compiler and the tools built on it, all
sharing one build of LLVM. Configure and build with the presets in `CMakePresets.json`, from the repository's root:
```bash
cmake --preset windows
cmake --build --preset release
```

The `windows` preset makes Visual Studio 2022 projects using clang-cl in `build/windows`, with `Hemera.sln` at its
top. Programs go in `build/windows/bin/<configuration>`, like `build/windows/bin/Release/hemera.exe`, and libraries in
`build/windows/lib/<configuration>`; everything else in `build/windows` is CMake's and LLVM's. To start again from
nothing, delete the preset's folder, or configure with `cmake --preset windows --fresh`.

The `release` and `debug` build presets build the compiler and its tests, and only the parts of LLVM they use; building
the solution's `ALL_BUILD` builds every LLVM library too. LLVM's own programs, like `llc` and `FileCheck`, aren't built
unless asked for by name (`cmake --build build/windows --config Release --target llc`). Programs Hemera builds are
linked by the `lld-link` or `ld.lld` on the PATH, which Visual Studio's LLVM tools provide.

Since the build includes LLVM, Debug builds take a long time and a lot of disk space. Release builds are very much
recommended. A Debug compiler is also much slower at compiling Hemera: most of the time goes in LLVM's code generation,
which a Debug LLVM does about ten to twenty times slower. Use the Release compiler to build programs, and Debug for
debugging the compiler. Both can be built in the same folder, each with its own outputs. The Debug compiler is
`hemera-debug` (`build/windows/bin/Debug/hemera-debug.exe`), so both folders can be on the PATH and each run by name.

## Crashes and Memory Errors

If the compiler crashes on Windows, it writes a minidump before it ends, `hemera-crash-<process ID>.dmp`, into the
folder `HEMERA_CRASH_DUMPS` names, or the temporary folder, and says where on standard error, followed by a stack
trace. Open it in Visual Studio or WinDbg with the compiler's PDB, which Release builds have too.

For memory errors that only show now and then, configure with `cmake --preset windows -DHEMERA_ASAN=ON` to also build `hemera-asan`, the
compiler with AddressSanitizer (`cmake --build build/windows --config Release --target HemeraAsan`). Only the compiler's own code
is instrumented, so LLVM isn't rebuilt for it. It runs like `hemera`, about twice as slowly, and stops at the first
use of freed memory, overflow or other error it finds, with where the memory was allocated and freed.

## Build Issues

**Paths too long on Windows**

Try moving the project to a directory as close to the root of the disk is possible.
You can also try this, but it may still cause issues with MSVC:

1. Press Win+R, type regedit, and hit enter
2. Navigate to HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\FileSystem
3. Set LongPathsEnabled to 1

**ASM Compiler not found**
Try installing clang and add `-DCMAKE_ASM_COMPILER=clang` (`clang-cl` for windows) or `-T ClangCL` to the cmake command.

**ZLIB and/or LibXml2 not found**
On Windows, you can install vcpkg and install the libraries from there

`vcpkg install zlib`
Set `ZLIB_ROOT` environment variable to the path like `<vcpkg>\packages\zlib_x64-windows\`

`vcpkg install libxml2:x64-windows`
Set `LIBXML2_ROOT` environment variable to the path like `<vcpkg>\packages\libxml2_x64-windows\`

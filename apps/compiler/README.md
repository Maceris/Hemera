# Compiler

This is the compiler for Hemera.

# Projects

The main projects are:

* generate_errors - Used to convert errors/warnings from text files to C++ code with doc comments
* Hemera - The executable part, essentially just a main method
* HemeraLib - The core project, built as a library so we can run tests
* HemeraTest - Unit test suite for the compiler

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

To minimally create the project or solution files for the project, create a directory named "bin" under this folder, and run
`cmake ..` from bin. For example:
```bash
mkdir bin
cd bin
cmake ..
```

It's recommended to use pre-installed LLVM tools (ideally the same version) for building and linking. e.g.
`cmake .. -T ClangCL`

This will generate all of the project files in the `bin` folder, where build output will also be stored.
If using Visual Studio, you can open the Loquat solution and build and run it from there.

Note that since this includes LLVM, Debug builds require a very large amount of time and disk space.
A full debug build could be tens or even hundreds of GB of disk space and will take hours.
Around 75 GB would be a reasonable estimate. The exact space requirements will vary by system.
Release builds are very much recommended, but will still not be small or fast.

It's quite likely that you'll need to build a few times to get a full/clean build, 
as some stages/tools depend on the outputs of others to be used as build tools.

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

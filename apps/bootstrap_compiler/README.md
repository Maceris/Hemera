# Bootstrap Compiler

This is the compiler for Hemera.

# Projects

The main projects are:

generate_errors - Used to convert errors/warnings from text files to C++ code with doc comments
Hemera - The executable part, essentially just a main method
HemeraLib - The core project, built as a library so we can run tests
HemeraTest - Unit test suite for the compiler

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

The build system uses [cmake](http://www.cmake.org/).

To create the project or solution files for the project, create a directory named "bin" under this folder, and run
`cmake ..` from bin. For example:
```bash
mkdir bin
cd bin
cmake ..
```
This is set up as `generate-project.bat` (for Windows) or `generate-project.sh` (for Linux) for convenience.

This will generate all of the project files in the `bin` folder, where build output will also be stored.
If using Visual Studio, you can open the Loquat solution and build and run it from there.

Note that since this includes LLVM, Debug builds require a very large amount of time and disk space.
A full debug build could be tens or even hundreds of GB of disk space and will take hours.
The exact space requirements will vary by system.
Release builds are very much recommended, but will still not be small or fast.

When building on Windows, the generated paths might get quite long and exceed filesystem limits.
You may need to clone to a less-nested folder or enable the LongPathsEnabled registry key.

It's quite likely that you'll need to build several times to get a full/clean build, 
as some stages/tools depend on the outputs of others to be used as build tools.

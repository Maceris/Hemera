# Bootstrap Compiler

This is the compiler for Hemera.

# Building

This project uses submodules for some third party libraries, and so the `--recursive` flag must be used when cloning the
repository.

```bash
$ git clone --recursive https://github.com/Maceris/Hemera.git
```

If you accidentally clone without using `--recursive`, (or to update the source tree after a new submodule has been added),
run this command to update dependencies:
```bash
$ git submodule update --init --recursive
```

The build system uses [cmake](http://www.cmake.org/).

To create the project or solution files for the project, you can run `regenerate-project.bat` or `regenerate-project.sh`. 
This will generate all of the project files in the `bin` folder. These can be rerun to wipe out the whole bin directory
again and regenerate the project contents.

It's not recommended to use that script if the project has already been built, due to the size of the LLVM build outputs, so
instead you can cd into `bin` and run `cmake ..` should the parent CMakeLists.txt change.

If using Visual Studio, you can open the Loquat solution and build and run it from there.

Note that since this includes LLVM, Debug builds require a lot of time and disk space. An LLVM-only build will need about 1-3 GB of space. A full build of LLVM and Clang will need around 15-20 GB of disk space. The exact space requirements will vary by system.

When building on Windows, the generated paths might get pretty long and exceed filesystem limits. You may need to clone to a less-nested folder or enable the LongPathsEnabled registry key.

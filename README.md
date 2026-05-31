# Hemera

A programming language designed to be nice to use for building software that is nice to use.

For more specific information [about the language](/docs/about.md), please see the docs directory.

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

## Folders

* `apps/` - Applications like the compiler, formatter, LSP
* `base/` - Packages that are part of the base language, required for targets and implementations
* `docs/` - Documentation
* `examples/` - Example projects
* `std/` - The standard library, intended to support the runtime, operating system specific calls, and other common core functionality
* `vendor/` - Binding and ports for third-party libraries that are commonly used

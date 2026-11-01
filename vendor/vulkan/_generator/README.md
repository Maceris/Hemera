# Vulkan binding generator

`generate.py` writes the generated files of the `vulkan` package (everything but `package_info.hsc` and
`vulkan_utilities.hsc`) from the Vulkan registry, `vk.xml`, which the Vulkan SDK has in `share/vulkan/registry`:

```bash
python vendor/vulkan/_generator/generate.py [path/to/vk.xml]
```

`check_layouts.py` checks the result against `vulkan_core.h`: it builds a C program and a Hemera program that print
every struct's size, alignment and field offsets, and compares them. It needs clang and the Release compiler:

```bash
python vendor/vulkan/_generator/check_layouts.py [path/to/hemera] [path/to/clang]
```

Run both after updating the SDK. The module docstring of `generate.py` says how each part of the C API is mapped.

## Linking

Programs link the loader's import library, `vulkan-1.lib`, which lld-link finds through the `LIB` environment
variable. Setting `LIB` replaces the folders the linker would otherwise search, so it lists the Windows SDK's too:

```bash
LIB="C:\VulkanSDK\1.3.268.0\Lib;C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0\um\x64" hemera examples/vulkan_info
```

## Building structs for commands

The structs aren't `#scoped`, so they can be kept anywhere. The one passed to a command can be a local, but what it
points at, directly or through `pNext`, comes from an allocator: a pointer to a local can't be stored in a struct
whose address is then taken (docs/memory.md, Deep Pointers). `std`'s `memory.Arena` suits this, reset each frame;
`examples/vulkan_info` builds a `pNext` chain from one.

## Not done yet

* Calls through the loaded `PFN_` pointers (`VulkanInstanceProcs` and `VulkanDeviceProcs`) don't go through the shim
  that moves foreign calls onto the thread's native stack, which only `#foreign` functions get, so a driver's code would
  run on whatever stack the caller is on, a stack segment or a fiber's stack included. Function values with `.c` need
  that shim too.
* Platform extensions (Win32 surfaces and the like) and the video extensions are left out.
* Bitfields are one `u32` per group, with no accessors.

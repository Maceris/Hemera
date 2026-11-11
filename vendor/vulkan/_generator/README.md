# Vulkan binding generator

`generate.py` writes the generated files of the `vulkan` package (everything but `package_info.hsc` and
`vulkan_utilities.hsc`) from the Vulkan registry, `vk.xml`, which the Vulkan SDK has in `share/vulkan/registry`:

```bash
python vendor/vulkan/_generator/generate.py [path/to/vk.xml]
```

`check_layouts.py` checks the result against the C headers (`vulkan_core.h`, `vulkan_beta.h` and every platform's,
with `windows.h` and stand-ins for the other platforms' headers): it builds a C program and a Hemera program that
print every struct's size, alignment and field offsets, and compares them. It needs clang and the Release compiler:

```bash
python vendor/vulkan/_generator/check_layouts.py [path/to/hemera] [path/to/clang]
```

Run both after updating the SDK. The module docstring of `generate.py` says how each part of the C API is mapped.

## Linking

Programs link the loader's import library, `vulkan-1.lib`, from the Vulkan SDK's `Lib` folder, given to the linker
with `--library-path`, or a build package's `TargetOptions.library_paths` (docs/compilation.md, Linking):

```bash
hemera --library-path=C:/VulkanSDK/1.3.268.0/Lib examples/vulkan_info
```

## Platforms

Every platform extension is in the package on every OS; there's nothing to choose or define, as C's
`VK_USE_PLATFORM_*` macros do. Their types from other headers (`HWND`, `Display`, `wl_surface`, `CAMetalLayer`...)
are in `vulkan_platform.hsc` and `vulkan_types.hsc`: opaque structs for what C only uses through pointers, and
aliases of what the header defines otherwise, so a value from another library's bindings passes straight in (QNX's
`_screen_context` and the like lose their leading underscore).

Only the surface commands the loader exports are `#foreign`, each on its own OS, since linking needs them:
`vkCreateWin32SurfaceKHR` and `vkGetPhysicalDeviceWin32PresentationSupportKHR` on Windows; the Xlib, XCB and Wayland
ones on Linux. A program using them puts the call in the same `#if OS == ...`. Every other platform command (Win32's
external memory handles, Metal's objects...) is a field of `VulkanInstanceProcs` or `VulkanDeviceProcs`, null where
the driver doesn't have it. Like any extension, a platform's has to be enabled when the instance or device is
created; `examples/vulkan_info` enables Win32's surface extension.

Provisional extensions (`VK_ENABLE_BETA_EXTENSIONS` in C), such as `VK_KHR_portability_subset`, are included, with a
comment on each of their structs and commands, since they can change in a later registry.

## Building structs for commands

The structs aren't `#scoped`, so they can be kept anywhere. The one passed to a command can be a local, but what it
points at, directly or through `pNext`, comes from an allocator: a pointer to a local can't be stored in a struct
whose address is then taken (docs/memory.md, Deep Pointers). `std`'s `memory.Arena` suits this, reset each frame;
`examples/vulkan_info` builds a `pNext` chain from one.

Calls through the loaded `PFN_` pointers (`VulkanInstanceProcs` and `VulkanDeviceProcs`) go through a shim onto the
thread's own stack, as calls to the `#foreign` commands do (docs/calling_convention.md, Calls to Foreign Code).

## Not done yet

* The video extensions are left out, since their types come from the video headers (`video.xml`), and so is GGP's
  platform (`VK_GGP_*`), whose header was never published.
* Bitfields are one `u32` per group, with no accessors.

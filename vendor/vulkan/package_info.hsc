/*
 * Vulkan, as its C API: generated from the Vulkan registry by _generator/generate.py, see _generator/README.md.
 */
package vulkan

// The Vulkan loader: vulkan-1.lib from the Vulkan SDK on Windows, libvulkan.so on Linux
#if OS == .Windows {
    VULKAN :: #library("vulkan-1")
}
#if OS == .Linux {
    VULKAN :: #library("vulkan")
}

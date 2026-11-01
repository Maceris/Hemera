package vulkan

// What the generator doesn't make: C macros, and the null handles

VK_NULL_HANDLE : VkHandle : null
VK_NULL_NON_DISPATCHABLE_HANDLE : VkNonDispatchableHandle : 0

VK_MAKE_API_VERSION :: fn(variant, major, minor, patch: u32) -> u32 {
    return (variant << 29) | (major << 22) | (minor << 12) | patch
}

VK_API_VERSION_VARIANT :: fn(version: u32) -> u32 {
    return version >> 29
}

VK_API_VERSION_MAJOR :: fn(version: u32) -> u32 {
    return (version >> 22) & 0x7F
}

VK_API_VERSION_MINOR :: fn(version: u32) -> u32 {
    return (version >> 12) & 0x3FF
}

VK_API_VERSION_PATCH :: fn(version: u32) -> u32 {
    return version & 0xFFF
}

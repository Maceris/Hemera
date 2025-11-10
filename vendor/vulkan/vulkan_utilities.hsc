package vulkan

vk_is_null_handle :: fn[HandleType](handle: HandleType) -> bool {
    if (types_are_aliases(HandleType, VkHandle)) {
        return cast[VkHandle](handle) == VK_NULL_HANDLE
    }
    else if (types_are_aliases(HandleType, VkNonDispatchableHandle)) {
        return cast[VkNonDispatchableHandle](handle) == VK_NULL_NON_DISPATCHABLE_HANDLE
    }

    return false
}

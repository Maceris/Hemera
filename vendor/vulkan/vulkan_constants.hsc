package vulkan

API_VERSION_1_0 :: VK_MAKE_API_VERSION(0, 1, 0, 0)
API_VERSION_1_1 :: VK_MAKE_API_VERSION(0, 1, 1, 0)
API_VERSION_1_2 :: VK_MAKE_API_VERSION(0, 1, 2, 0)
API_VERSION_1_3 :: VK_MAKE_API_VERSION(0, 1, 3, 0)
API_VERSION_1_4 :: VK_MAKE_API_VERSION(0, 1, 4, 0)

VK_ATTACHMENT_UNUSED             : uint : ~0
VK_FALSE                         : uint : 0
VK_LOD_CLAMP_NONE                : f32  : 1000.0
VK_QUEUE_FAMILY_IGNORED          : uint : ~0
VK_REMAINING_ARRAY_LAYERS        : uint : ~0
VK_REMAINING_MIP_LEVELS          : uint : ~0
VK_SUBPASS_EXTERNAL              : uint : ~0
VK_TRUE                          : uint : 1
VK_WHOLE_SIZE                    : u64  : ~0
VK_MAX_MEMORY_TYPES              : uint : 32
VK_MAX_PHYSICAL_DEVICE_NAME_SIZE : uint : 256
VK_UUID_SIZE                     : uint : 16
VK_MAX_EXTENSION_NAME_SIZE       : uint : 256
VK_MAX_DESCRIPTION_SIZE          : uint : 256
VK_MAX_MEMORY_HEAPS              : uint : 16

VK_NULL_HANDLE                   : VkHandle : cast[VkHandle](null)
VK_NULL_NON_DISPATCHABLE_HANDLE  : VkNonDispatchableHandle : cast[VkNonDispatchableHandle](0)

// TODO(ches) Add more Vulkan constants

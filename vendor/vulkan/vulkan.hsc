package vulkan

// See https://raw.githubusercontent.com/KhronosGroup/Vulkan-Headers/master/include/vulkan/vulkan_core.h

API_VERSION_1_0 :: MAKE_VERSION(0, 1, 0, 0)
API_VERSION_1_1 :: MAKE_VERSION(0, 1, 1, 0)
API_VERSION_1_2 :: MAKE_VERSION(0, 1, 2, 0)
API_VERSION_1_3 :: MAKE_VERSION(0, 1, 3, 0)
API_VERSION_1_4 :: MAKE_VERSION(0, 1, 4, 0)

MAKE_VERSION :: fn(variant, major, minor, patch: u32) -> u32 {
    return (variant << 29) | (major << 22) | (minor << 12) | patch
}

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

// Aliases
VkDeviceAddress :: distinct alias u64
VkDeviceSize    :: distinct alias u64
VkFlags         :: distinct alias u32
VkFlags64       :: distinct alias u64
VkSampleMask    :: distinct alias u32

VkHandle                :: distinct alias rawptr
VkNonDispatchableHandle :: distinct alias u64

// Handles
VkInstance                      :: distinct alias VkHandle
VkPhysicalDevice                :: distinct alias VkHandle
VkDevice                        :: distinct alias VkHandle
VkQueue                         :: distinct alias VkHandle
VkCommandBuffer                 :: distinct alias VkHandle

VkBuffer                        :: distinct alias VkNonDispatchableHandle
VkImage                         :: distinct alias VkNonDispatchableHandle
VkSemaphore                     :: distinct alias VkNonDispatchableHandle
VkFence                         :: distinct alias VkNonDispatchableHandle
VkDeviceMemory                  :: distinct alias VkNonDispatchableHandle
VkEvent                         :: distinct alias VkNonDispatchableHandle
VkQueryPool                     :: distinct alias VkNonDispatchableHandle
VkBufferView                    :: distinct alias VkNonDispatchableHandle
VkImageView                     :: distinct alias VkNonDispatchableHandle
VkShaderModule                  :: distinct alias VkNonDispatchableHandle
VkPipelineCache                 :: distinct alias VkNonDispatchableHandle
VkPipelineLayout                :: distinct alias VkNonDispatchableHandle
VkPipeline                      :: distinct alias VkNonDispatchableHandle
VkRenderPass                    :: distinct alias VkNonDispatchableHandle
VkDescriptorSetLayout           :: distinct alias VkNonDispatchableHandle
VkSampler                       :: distinct alias VkNonDispatchableHandle
VkDescriptorSet                 :: distinct alias VkNonDispatchableHandle
VkDescriptorPool                :: distinct alias VkNonDispatchableHandle
VkFramebuffer                   :: distinct alias VkNonDispatchableHandle
VkCommandPool                   :: distinct alias VkNonDispatchableHandle
VkSamplerYcbcrConversion        :: distinct alias VkNonDispatchableHandle
VkDescriptorUpdateTemplate      :: distinct alias VkNonDispatchableHandle
VkPrivateDataSlot               :: distinct alias VkNonDispatchableHandle
VkSurfaceKHR                    :: distinct alias VkNonDispatchableHandle
VkSwapchainKHR                  :: distinct alias VkNonDispatchableHandle
VkDisplayKHR                    :: distinct alias VkNonDispatchableHandle
VkDisplayModeKHR                :: distinct alias VkNonDispatchableHandle
VkVideoSessionKHR               :: distinct alias VkNonDispatchableHandle
VkVideoSessionParametersKHR     :: distinct alias VkNonDispatchableHandle
VkDeferredOperationKHR          :: distinct alias VkNonDispatchableHandle
VkDebugReportCallbackEXT        :: distinct alias VkNonDispatchableHandle
VkCuModuleNVX                   :: distinct alias VkNonDispatchableHandle
VkCuFunctionNVX                 :: distinct alias VkNonDispatchableHandle
VkDebugUtilsMessengerEXT        :: distinct alias VkNonDispatchableHandle
VkValidationCacheEXT            :: distinct alias VkNonDispatchableHandle
VkAccelerationStructureNV       :: distinct alias VkNonDispatchableHandle
VkPerformanceConfigurationINTEL :: distinct alias VkNonDispatchableHandle
VkIndirectCommandsLayoutNV      :: distinct alias VkNonDispatchableHandle
VkCudaModuleNV                  :: distinct alias VkNonDispatchableHandle
VkCudaFunctionNV                :: distinct alias VkNonDispatchableHandle
VkAccelerationStructureKHR      :: distinct alias VkNonDispatchableHandle
VkMicromapEXT                   :: distinct alias VkNonDispatchableHandle
VkOpticalFlowSessionNV          :: distinct alias VkNonDispatchableHandle
VkShaderEXT                     :: distinct alias VkNonDispatchableHandle

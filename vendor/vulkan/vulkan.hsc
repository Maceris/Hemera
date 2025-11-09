package vulkan

// See https://raw.githubusercontent.com/KhronosGroup/Vulkan-Headers/master/include/vulkan/vulkan_core.h

VkDeviceAddress :: distinct alias u64
VkDeviceSize    :: distinct alias u64
VkFlags         :: distinct alias u32
VkFlags64       :: distinct alias u64
VkSampleMask    :: distinct alias u32

// Flags
VkAccelerationStructureCreateFlagsKHR                  : distinct alias VkFlags
VkAccelerationStructureMotionInfoFlagsNV               : distinct alias VkFlags
VkAccelerationStructureMotionInstanceFlagsNV           : distinct alias VkFlags
VkAccessFlags                                          : distinct alias VkFlags
VkAcquireProfilingLockFlagsKHR                         : distinct alias VkFlags
VkAttachmentDescriptionFlags                           : distinct alias VkFlags
VkBufferCreateFlags                                    : distinct alias VkFlags
VkBufferUsageFlags                                     : distinct alias VkFlags
VkBufferViewCreateFlags                                : distinct alias VkFlags
VkBuildAccelerationStructureFlagsKHR                   : distinct alias VkFlags
VkBuildMicromapFlagsEXT                                : distinct alias VkFlags
VkColorComponentFlags                                  : distinct alias VkFlags
VkCommandBufferResetFlags                              : distinct alias VkFlags
VkCommandBufferUsageFlags                              : distinct alias VkFlags
VkCommandPoolCreateFlags                               : distinct alias VkFlags
VkCommandPoolResetFlags                                : distinct alias VkFlags
VkCommandPoolTrimFlags                                 : distinct alias VkFlags
VkCompositeAlphaFlagsKHR                               : distinct alias VkFlags
VkConditionalRenderingFlagsEXT                         : distinct alias VkFlags
VkCullModeFlags                                        : distinct alias VkFlags
VkDebugReportFlagsEXT                                  : distinct alias VkFlags
VkDebugUtilsMessageSeverityFlagsEXT                    : distinct alias VkFlags
VkDebugUtilsMessageTypeFlagsEXT                        : distinct alias VkFlags
VkDebugUtilsMessengerCallbackDataFlagsEXT              : distinct alias VkFlags
VkDebugUtilsMessengerCreateFlagsEXT                    : distinct alias VkFlags
VkDependencyFlags                                      : distinct alias VkFlags
VkDescriptorBindingFlags                               : distinct alias VkFlags
VkDescriptorPoolCreateFlags                            : distinct alias VkFlags
VkDescriptorPoolResetFlags                             : distinct alias VkFlags
VkDescriptorSetLayoutCreateFlags                       : distinct alias VkFlags
VkDescriptorUpdateTemplateCreateFlags                  : distinct alias VkFlags
VkDeviceAddressBindingFlagsEXT                         : distinct alias VkFlags
VkDeviceCreateFlags                                    : distinct alias VkFlags
VkDeviceDiagnosticsConfigFlagsNV                       : distinct alias VkFlags
VkDeviceGroupPresentModeFlagsKHR                       : distinct alias VkFlags
VkDeviceMemoryReportFlagsEXT                           : distinct alias VkFlags
VkDeviceQueueCreateFlags                               : distinct alias VkFlags
VkDirectDriverLoadingFlagsLUNARG                       : distinct alias VkFlags
VkDisplayModeCreateFlagsKHR                            : distinct alias VkFlags
VkDisplayPlaneAlphaFlagsKHR                            : distinct alias VkFlags
VkDisplaySurfaceCreateFlagsKHR                         : distinct alias VkFlags
VkEventCreateFlags                                     : distinct alias VkFlags
VkExternalFenceFeatureFlags                            : distinct alias VkFlags
VkExternalFenceHandleTypeFlags                         : distinct alias VkFlags
VkExternalMemoryFeatureFlags                           : distinct alias VkFlags
VkExternalMemoryFeatureFlagsNV                         : distinct alias VkFlags
VkExternalMemoryHandleTypeFlags                        : distinct alias VkFlags
VkExternalMemoryHandleTypeFlagsNV                      : distinct alias VkFlags
VkExternalSemaphoreFeatureFlags                        : distinct alias VkFlags
VkExternalSemaphoreHandleTypeFlags                     : distinct alias VkFlags
VkFenceCreateFlags                                     : distinct alias VkFlags
VkFenceImportFlags                                     : distinct alias VkFlags
VkFormatFeatureFlags                                   : distinct alias VkFlags
VkFrameBoundaryFlagsEXT                                : distinct alias VkFlags
VkFramebufferCreateFlags                               : distinct alias VkFlags
VkGeometryFlagsKHR                                     : distinct alias VkFlags
VkGeometryInstanceFlagsKHR                             : distinct alias VkFlags
VkGraphicsPipelineLibraryFlagsEXT                      : distinct alias VkFlags
VkHeadlessSurfaceCreateFlagsEXT                        : distinct alias VkFlags
VkHostImageCopyFlagsEXT                                : distinct alias VkFlags
VkImageAspectFlags                                     : distinct alias VkFlags
VkImageCompressionFixedRateFlagsEXT                    : distinct alias VkFlags
VkImageCompressionFlagsEXT                             : distinct alias VkFlags
VkImageCreateFlags                                     : distinct alias VkFlags
VkImageUsageFlags                                      : distinct alias VkFlags
VkImageViewCreateFlags                                 : distinct alias VkFlags
VkIndirectCommandsLayoutUsageFlagsNV                   : distinct alias VkFlags
VkIndirectStateFlagsNV                                 : distinct alias VkFlags
VkInstanceCreateFlags                                  : distinct alias VkFlags
VkMemoryAllocateFlags                                  : distinct alias VkFlags
VkMemoryHeapFlags                                      : distinct alias VkFlags
VkMemoryMapFlags                                       : distinct alias VkFlags
VkMemoryPropertyFlags                                  : distinct alias VkFlags
VkMemoryUnmapFlagsKHR                                  : distinct alias VkFlags
VkMicromapCreateFlagsEXT                               : distinct alias VkFlags
VkOpticalFlowExecuteFlagsNV                            : distinct alias VkFlags
VkOpticalFlowGridSizeFlagsNV                           : distinct alias VkFlags
VkOpticalFlowSessionCreateFlagsNV                      : distinct alias VkFlags
VkOpticalFlowUsageFlagsNV                              : distinct alias VkFlags
VkPeerMemoryFeatureFlags                               : distinct alias VkFlags
VkPerformanceCounterDescriptionFlagsKHR                : distinct alias VkFlags
VkPipelineCacheCreateFlags                             : distinct alias VkFlags
VkPipelineColorBlendStateCreateFlags                   : distinct alias VkFlags
VkPipelineCompilerControlFlagsAMD                      : distinct alias VkFlags
VkPipelineCoverageModulationStateCreateFlagsNV         : distinct alias VkFlags
VkPipelineCoverageReductionStateCreateFlagsNV          : distinct alias VkFlags
VkPipelineCoverageToColorStateCreateFlagsNV            : distinct alias VkFlags
VkPipelineCreateFlags                                  : distinct alias VkFlags
VkPipelineCreationFeedbackFlags                        : distinct alias VkFlags
VkPipelineDepthStencilStateCreateFlags                 : distinct alias VkFlags
VkPipelineDiscardRectangleStateCreateFlagsEXT          : distinct alias VkFlags
VkPipelineDynamicStateCreateFlags                      : distinct alias VkFlags
VkPipelineInputAssemblyStateCreateFlags                : distinct alias VkFlags
VkPipelineLayoutCreateFlags                            : distinct alias VkFlags
VkPipelineMultisampleStateCreateFlags                  : distinct alias VkFlags
VkPipelineRasterizationConservativeStateCreateFlagsEXT : distinct alias VkFlags
VkPipelineRasterizationDepthClipStateCreateFlagsEXT    : distinct alias VkFlags
VkPipelineRasterizationStateCreateFlags                : distinct alias VkFlags
VkPipelineRasterizationStateStreamCreateFlagsEXT       : distinct alias VkFlags
VkPipelineShaderStageCreateFlags                       : distinct alias VkFlags
VkPipelineStageFlags                                   : distinct alias VkFlags
VkPipelineTessellationStateCreateFlags                 : distinct alias VkFlags
VkPipelineVertexInputStateCreateFlags                  : distinct alias VkFlags
VkPipelineViewportStateCreateFlags                     : distinct alias VkFlags
VkPipelineViewportSwizzleStateCreateFlagsNV            : distinct alias VkFlags
VkPresentGravityFlagsEXT                               : distinct alias VkFlags
VkPresentScalingFlagsEXT                               : distinct alias VkFlags
VkPrivateDataSlotCreateFlags                           : distinct alias VkFlags
VkQueryControlFlags                                    : distinct alias VkFlags
VkQueryPipelineStatisticFlags                          : distinct alias VkFlags
VkQueryPoolCreateFlags                                 : distinct alias VkFlags
VkQueryResultFlags                                     : distinct alias VkFlags
VkQueueFlags                                           : distinct alias VkFlags
VkRenderingFlags                                       : distinct alias VkFlags
VkRenderPassCreateFlags                                : distinct alias VkFlags
VkResolveModeFlags                                     : distinct alias VkFlags
VkSampleCountFlags                                     : distinct alias VkFlags
VkSamplerCreateFlags                                   : distinct alias VkFlags
VkSemaphoreCreateFlags                                 : distinct alias VkFlags
VkSemaphoreImportFlags                                 : distinct alias VkFlags
VkSemaphoreWaitFlags                                   : distinct alias VkFlags
VkShaderCorePropertiesFlagsAMD                         : distinct alias VkFlags
VkShaderCreateFlagsEXT                                 : distinct alias VkFlags
VkShaderModuleCreateFlags                              : distinct alias VkFlags
VkShaderStageFlags                                     : distinct alias VkFlags
VkSparseImageFormatFlags                               : distinct alias VkFlags
VkSparseMemoryBindFlags                                : distinct alias VkFlags
VkStencilFaceFlags                                     : distinct alias VkFlags
VkSubgroupFeatureFlags                                 : distinct alias VkFlags
VkSubmitFlags                                          : distinct alias VkFlags
VkSubpassDescriptionFlags                              : distinct alias VkFlags
VkSurfaceCounterFlagsEXT                               : distinct alias VkFlags
VkSurfaceTransformFlagsKHR                             : distinct alias VkFlags
VkSwapchainCreateFlagsKHR                              : distinct alias VkFlags
VkToolPurposeFlags                                     : distinct alias VkFlags
VkValidationCacheCreateFlagsEXT                        : distinct alias VkFlags
VkVideoBeginCodingFlagsKHR                             : distinct alias VkFlags
VkVideoCapabilityFlagsKHR                              : distinct alias VkFlags
VkVideoChromaSubsamplingFlagsKHR                       : distinct alias VkFlags
VkVideoCodecOperationFlagsKHR                          : distinct alias VkFlags
VkVideoCodingControlFlagsKHR                           : distinct alias VkFlags
VkVideoComponentBitDepthFlagsKHR                       : distinct alias VkFlags
VkVideoDecodeCapabilityFlagsKHR                        : distinct alias VkFlags
VkVideoDecodeFlagsKHR                                  : distinct alias VkFlags
VkVideoDecodeH264PictureLayoutFlagsKHR                 : distinct alias VkFlags
VkVideoDecodeUsageFlagsKHR                             : distinct alias VkFlags
VkVideoEncodeCapabilityFlagsKHR                        : distinct alias VkFlags
VkVideoEncodeContentFlagsKHR                           : distinct alias VkFlags
VkVideoEncodeFeedbackFlagsKHR                          : distinct alias VkFlags
VkVideoEncodeFlagsKHR                                  : distinct alias VkFlags
VkVideoEncodeH264CapabilityFlagsKHR                    : distinct alias VkFlags
VkVideoEncodeH264RateControlFlagsKHR                   : distinct alias VkFlags
VkVideoEncodeH264StdFlagsKHR                           : distinct alias VkFlags
VkVideoEncodeH265CapabilityFlagsKHR                    : distinct alias VkFlags
VkVideoEncodeH265CtbSizeFlagsKHR                       : distinct alias VkFlags
VkVideoEncodeH265RateControlFlagsKHR                   : distinct alias VkFlags
VkVideoEncodeH265StdFlagsKHR                           : distinct alias VkFlags
VkVideoEncodeH265TransformBlockSizeFlagsKHR            : distinct alias VkFlags
VkVideoEncodeRateControlFlagsKHR                       : distinct alias VkFlags
VkVideoEncodeRateControlModeFlagsKHR                   : distinct alias VkFlags
VkVideoEncodeUsageFlagsKHR                             : distinct alias VkFlags
VkVideoEndCodingFlagsKHR                               : distinct alias VkFlags
VkVideoSessionCreateFlagsKHR                           : distinct alias VkFlags
VkVideoSessionParametersCreateFlagsKHR                 : distinct alias VkFlags
VkAccessFlagBits2                                      : distinct alias VkFlags64
VkAccessFlags2                                         : distinct alias VkFlags64
VkBufferUsageFlagBits2KHR                              : distinct alias VkFlags64
VkBufferUsageFlags2KHR                                 : distinct alias VkFlags64
VkFormatFeatureFlagBits2                               : distinct alias VkFlags64
VkFormatFeatureFlags2                                  : distinct alias VkFlags64
VkMemoryDecompressionMethodFlagBitsNV                  : distinct alias VkFlags64
VkMemoryDecompressionMethodFlagsNV                     : distinct alias VkFlags64
VkPhysicalDeviceSchedulingControlsFlagBitsARM          : distinct alias VkFlags64
VkPhysicalDeviceSchedulingControlsFlagsARM             : distinct alias VkFlags64
VkPipelineCreateFlagBits2KHR                           : distinct alias VkFlags64
VkPipelineCreateFlags2KHR                              : distinct alias VkFlags64
VkPipelineStageFlagBits2                               : distinct alias VkFlags64
VkPipelineStageFlags2                                  : distinct alias VkFlags64

// Handles
VkHandle                :: distinct alias rawptr
VkNonDispatchableHandle :: distinct alias u64

VkInstance                      :: distinct alias VkHandle
VkPhysicalDevice                :: distinct alias VkHandle
VkDevice                        :: distinct alias VkHandle
VkQueue                         :: distinct alias VkHandle
VkCommandBuffer                 :: distinct alias VkHandle

VkAccelerationStructureKHR      :: distinct alias VkNonDispatchableHandle
VkAccelerationStructureNV       :: distinct alias VkNonDispatchableHandle
VkBuffer                        :: distinct alias VkNonDispatchableHandle
VkBufferView                    :: distinct alias VkNonDispatchableHandle
VkCommandPool                   :: distinct alias VkNonDispatchableHandle
VkCudaFunctionNV                :: distinct alias VkNonDispatchableHandle
VkCudaModuleNV                  :: distinct alias VkNonDispatchableHandle
VkCuFunctionNVX                 :: distinct alias VkNonDispatchableHandle
VkCuModuleNVX                   :: distinct alias VkNonDispatchableHandle
VkDebugReportCallbackEXT        :: distinct alias VkNonDispatchableHandle
VkDebugUtilsMessengerEXT        :: distinct alias VkNonDispatchableHandle
VkDeferredOperationKHR          :: distinct alias VkNonDispatchableHandle
VkDescriptorPool                :: distinct alias VkNonDispatchableHandle
VkDescriptorSet                 :: distinct alias VkNonDispatchableHandle
VkDescriptorSetLayout           :: distinct alias VkNonDispatchableHandle
VkDescriptorUpdateTemplate      :: distinct alias VkNonDispatchableHandle
VkDeviceMemory                  :: distinct alias VkNonDispatchableHandle
VkDisplayKHR                    :: distinct alias VkNonDispatchableHandle
VkDisplayModeKHR                :: distinct alias VkNonDispatchableHandle
VkEvent                         :: distinct alias VkNonDispatchableHandle
VkFence                         :: distinct alias VkNonDispatchableHandle
VkFramebuffer                   :: distinct alias VkNonDispatchableHandle
VkImage                         :: distinct alias VkNonDispatchableHandle
VkImageView                     :: distinct alias VkNonDispatchableHandle
VkIndirectCommandsLayoutNV      :: distinct alias VkNonDispatchableHandle
VkMicromapEXT                   :: distinct alias VkNonDispatchableHandle
VkOpticalFlowSessionNV          :: distinct alias VkNonDispatchableHandle
VkPerformanceConfigurationINTEL :: distinct alias VkNonDispatchableHandle
VkPipeline                      :: distinct alias VkNonDispatchableHandle
VkPipelineCache                 :: distinct alias VkNonDispatchableHandle
VkPipelineLayout                :: distinct alias VkNonDispatchableHandle
VkPrivateDataSlot               :: distinct alias VkNonDispatchableHandle
VkQueryPool                     :: distinct alias VkNonDispatchableHandle
VkRenderPass                    :: distinct alias VkNonDispatchableHandle
VkSampler                       :: distinct alias VkNonDispatchableHandle
VkSamplerYcbcrConversion        :: distinct alias VkNonDispatchableHandle
VkSemaphore                     :: distinct alias VkNonDispatchableHandle
VkShaderEXT                     :: distinct alias VkNonDispatchableHandle
VkShaderModule                  :: distinct alias VkNonDispatchableHandle
VkSurfaceKHR                    :: distinct alias VkNonDispatchableHandle
VkSwapchainKHR                  :: distinct alias VkNonDispatchableHandle
VkValidationCacheEXT            :: distinct alias VkNonDispatchableHandle
VkVideoSessionKHR               :: distinct alias VkNonDispatchableHandle
VkVideoSessionParametersKHR     :: distinct alias VkNonDispatchableHandle


// Other aliases
VkAabbPositionsNV                                             :: alias VkAabbPositionsKHR
VkAccelerationStructureInstanceNV                             :: alias VkAccelerationStructureInstanceKHR
VkAccelerationStructureTypeNV                                 :: alias VkAccelerationStructureTypeKHR
VkAccessFlagBits2KHR                                          :: alias VkAccessFlagBits2
VkAccessFlags2KHR                                             :: alias VkAccessFlags2
VkAttachmentDescription2KHR                                   :: alias VkAttachmentDescription2
VkAttachmentDescriptionStencilLayoutKHR                       :: alias VkAttachmentDescriptionStencilLayout
VkAttachmentReference2KHR                                     :: alias VkAttachmentReference2
VkAttachmentReferenceStencilLayoutKHR                         :: alias VkAttachmentReferenceStencilLayout
VkAttachmentSampleCountInfoNV                                 :: alias VkAttachmentSampleCountInfoAMD
VkBindBufferMemoryDeviceGroupInfoKHR                          :: alias VkBindBufferMemoryDeviceGroupInfo
VkBindBufferMemoryInfoKHR                                     :: alias VkBindBufferMemoryInfo
VkBindImageMemoryDeviceGroupInfoKHR                           :: alias VkBindImageMemoryDeviceGroupInfo
VkBindImageMemoryInfoKHR                                      :: alias VkBindImageMemoryInfo
VkBindImagePlaneMemoryInfoKHR                                 :: alias VkBindImagePlaneMemoryInfo
VkBlitImageInfo2KHR                                           :: alias VkBlitImageInfo2
VkBufferCopy2KHR                                              :: alias VkBufferCopy2
VkBufferDeviceAddressInfoEXT                                  :: alias VkBufferDeviceAddressInfo
VkBufferDeviceAddressInfoKHR                                  :: alias VkBufferDeviceAddressInfo
VkBufferImageCopy2KHR                                         :: alias VkBufferImageCopy2
VkBufferMemoryBarrier2KHR                                     :: alias VkBufferMemoryBarrier2
VkBufferMemoryRequirementsInfo2KHR                            :: alias VkBufferMemoryRequirementsInfo2
VkBufferOpaqueCaptureAddressCreateInfoKHR                     :: alias VkBufferOpaqueCaptureAddressCreateInfo
VkBuildAccelerationStructureFlagBitsNV                        :: alias VkBuildAccelerationStructureFlagBitsKHR
VkBuildAccelerationStructureFlagsNV                           :: alias VkBuildAccelerationStructureFlagsKHR
VkCalibratedTimestampInfoEXT                                  :: alias VkCalibratedTimestampInfoKHR
VkChromaLocationKHR                                           :: alias VkChromaLocation
VkCommandBufferInheritanceRenderingInfoKHR                    :: alias VkCommandBufferInheritanceRenderingInfo
VkCommandBufferSubmitInfoKHR                                  :: alias VkCommandBufferSubmitInfo
VkCommandPoolTrimFlagsKHR                                     :: alias VkCommandPoolTrimFlags
VkComponentTypeNV                                             :: alias VkComponentTypeKHR
VkConformanceVersionKHR                                       :: alias VkConformanceVersion
VkCopyAccelerationStructureModeNV                             :: alias VkCopyAccelerationStructureModeKHR
VkCopyBufferInfo2KHR                                          :: alias VkCopyBufferInfo2
VkCopyBufferToImageInfo2KHR                                   :: alias VkCopyBufferToImageInfo2
VkCopyImageInfo2KHR                                           :: alias VkCopyImageInfo2
VkCopyImageToBufferInfo2KHR                                   :: alias VkCopyImageToBufferInfo2
VkDependencyInfoKHR                                           :: alias VkDependencyInfo
VkDescriptorBindingFlagBitsEXT                                :: alias VkDescriptorBindingFlagBits
VkDescriptorBindingFlagsEXT                                   :: alias VkDescriptorBindingFlags
VkDescriptorPoolInlineUniformBlockCreateInfoEXT               :: alias VkDescriptorPoolInlineUniformBlockCreateInfo
VkDescriptorSetLayoutBindingFlagsCreateInfoEXT                :: alias VkDescriptorSetLayoutBindingFlagsCreateInfo
VkDescriptorSetLayoutSupportKHR                               :: alias VkDescriptorSetLayoutSupport
VkDescriptorSetVariableDescriptorCountAllocateInfoEXT         :: alias VkDescriptorSetVariableDescriptorCountAllocateInfo
VkDescriptorSetVariableDescriptorCountLayoutSupportEXT        :: alias VkDescriptorSetVariableDescriptorCountLayoutSupport
VkDescriptorUpdateTemplateCreateFlagsKHR                      :: alias VkDescriptorUpdateTemplateCreateFlags
VkDescriptorUpdateTemplateCreateInfoKHR                       :: alias VkDescriptorUpdateTemplateCreateInfo
VkDescriptorUpdateTemplateEntryKHR                            :: alias VkDescriptorUpdateTemplateEntry
VkDescriptorUpdateTemplateKHR                                 :: alias VkDescriptorUpdateTemplate
VkDescriptorUpdateTemplateTypeKHR                             :: alias VkDescriptorUpdateTemplateType
VkDeviceBufferMemoryRequirementsKHR                           :: alias VkDeviceBufferMemoryRequirements
VkDeviceGroupBindSparseInfoKHR                                :: alias VkDeviceGroupBindSparseInfo
VkDeviceGroupCommandBufferBeginInfoKHR                        :: alias VkDeviceGroupCommandBufferBeginInfo
VkDeviceGroupDeviceCreateInfoKHR                              :: alias VkDeviceGroupDeviceCreateInfo
VkDeviceGroupRenderPassBeginInfoKHR                           :: alias VkDeviceGroupRenderPassBeginInfo
VkDeviceGroupSubmitInfoKHR                                    :: alias VkDeviceGroupSubmitInfo
VkDeviceImageMemoryRequirementsKHR                            :: alias VkDeviceImageMemoryRequirements
VkDeviceMemoryOpaqueCaptureAddressInfoKHR                     :: alias VkDeviceMemoryOpaqueCaptureAddressInfo
VkDevicePrivateDataCreateInfoEXT                              :: alias VkDevicePrivateDataCreateInfo
VkDeviceQueueGlobalPriorityCreateInfoEXT                      :: alias VkDeviceQueueGlobalPriorityCreateInfoKHR
VkDriverIdKHR                                                 :: alias VkDriverId
VkExportFenceCreateInfoKHR                                    :: alias VkExportFenceCreateInfo
VkExportMemoryAllocateInfoKHR                                 :: alias VkExportMemoryAllocateInfo
VkExportSemaphoreCreateInfoKHR                                :: alias VkExportSemaphoreCreateInfo
VkExternalBufferPropertiesKHR                                 :: alias VkExternalBufferProperties
VkExternalFenceFeatureFlagBitsKHR                             :: alias VkExternalFenceFeatureFlagBits
VkExternalFenceFeatureFlagsKHR                                :: alias VkExternalFenceFeatureFlags
VkExternalFenceHandleTypeFlagBitsKHR                          :: alias VkExternalFenceHandleTypeFlagBits
VkExternalFenceHandleTypeFlagsKHR                             :: alias VkExternalFenceHandleTypeFlags
VkExternalFencePropertiesKHR                                  :: alias VkExternalFenceProperties
VkExternalImageFormatPropertiesKHR                            :: alias VkExternalImageFormatProperties
VkExternalMemoryBufferCreateInfoKHR                           :: alias VkExternalMemoryBufferCreateInfo
VkExternalMemoryFeatureFlagBitsKHR                            :: alias VkExternalMemoryFeatureFlagBits
VkExternalMemoryFeatureFlagsKHR                               :: alias VkExternalMemoryFeatureFlags
VkExternalMemoryHandleTypeFlagBitsKHR                         :: alias VkExternalMemoryHandleTypeFlagBits
VkExternalMemoryHandleTypeFlagsKHR                            :: alias VkExternalMemoryHandleTypeFlags
VkExternalMemoryImageCreateInfoKHR                            :: alias VkExternalMemoryImageCreateInfo
VkExternalMemoryPropertiesKHR                                 :: alias VkExternalMemoryProperties
VkExternalSemaphoreFeatureFlagBitsKHR                         :: alias VkExternalSemaphoreFeatureFlagBits
VkExternalSemaphoreFeatureFlagsKHR                            :: alias VkExternalSemaphoreFeatureFlags
VkExternalSemaphoreHandleTypeFlagBitsKHR                      :: alias VkExternalSemaphoreHandleTypeFlagBits
VkExternalSemaphoreHandleTypeFlagsKHR                         :: alias VkExternalSemaphoreHandleTypeFlags
VkExternalSemaphorePropertiesKHR                              :: alias VkExternalSemaphoreProperties
VkFenceImportFlagBitsKHR                                      :: alias VkFenceImportFlagBits
VkFenceImportFlagsKHR                                         :: alias VkFenceImportFlags
VkFormatFeatureFlagBits2KHR                                   :: alias VkFormatFeatureFlagBits2
VkFormatFeatureFlags2KHR                                      :: alias VkFormatFeatureFlags2
VkFormatProperties2KHR                                        :: alias VkFormatProperties2
VkFormatProperties3KHR                                        :: alias VkFormatProperties3
VkFramebufferAttachmentImageInfoKHR                           :: alias VkFramebufferAttachmentImageInfo
VkFramebufferAttachmentsCreateInfoKHR                         :: alias VkFramebufferAttachmentsCreateInfo
VkGeometryFlagBitsNV                                          :: alias VkGeometryFlagBitsKHR
VkGeometryFlagsNV                                             :: alias VkGeometryFlagsKHR
VkGeometryInstanceFlagBitsNV                                  :: alias VkGeometryInstanceFlagBitsKHR
VkGeometryInstanceFlagsNV                                     :: alias VkGeometryInstanceFlagsKHR
VkGeometryTypeNV                                              :: alias VkGeometryTypeKHR
VkImageBlit2KHR                                               :: alias VkImageBlit2
VkImageCopy2KHR                                               :: alias VkImageCopy2
VkImageFormatListCreateInfoKHR                                :: alias VkImageFormatListCreateInfo
VkImageFormatProperties2KHR                                   :: alias VkImageFormatProperties2
VkImageMemoryBarrier2KHR                                      :: alias VkImageMemoryBarrier2
VkImageMemoryRequirementsInfo2KHR                             :: alias VkImageMemoryRequirementsInfo2
VkImagePlaneMemoryRequirementsInfoKHR                         :: alias VkImagePlaneMemoryRequirementsInfo
VkImageResolve2KHR                                            :: alias VkImageResolve2
VkImageSparseMemoryRequirementsInfo2KHR                       :: alias VkImageSparseMemoryRequirementsInfo2
VkImageStencilUsageCreateInfoEXT                              :: alias VkImageStencilUsageCreateInfo
VkImageSubresource2EXT                                        :: alias VkImageSubresource2KHR
VkImageViewUsageCreateInfoKHR                                 :: alias VkImageViewUsageCreateInfo
VkInputAttachmentAspectReferenceKHR                           :: alias VkInputAttachmentAspectReference
VkLineRasterizationModeEXT                                    :: alias VkLineRasterizationModeKHR
VkMemoryAllocateFlagBitsKHR                                   :: alias VkMemoryAllocateFlagBits
VkMemoryAllocateFlagsInfoKHR                                  :: alias VkMemoryAllocateFlagsInfo
VkMemoryAllocateFlagsKHR                                      :: alias VkMemoryAllocateFlags
VkMemoryBarrier2KHR                                           :: alias VkMemoryBarrier2
VkMemoryDedicatedAllocateInfoKHR                              :: alias VkMemoryDedicatedAllocateInfo
VkMemoryDedicatedRequirementsKHR                              :: alias VkMemoryDedicatedRequirements
VkMemoryOpaqueCaptureAddressAllocateInfoKHR                   :: alias VkMemoryOpaqueCaptureAddressAllocateInfo
VkMemoryRequirements2KHR                                      :: alias VkMemoryRequirements2
VkMutableDescriptorTypeCreateInfoVALVE                        :: alias VkMutableDescriptorTypeCreateInfoEXT
VkMutableDescriptorTypeListVALVE                              :: alias VkMutableDescriptorTypeListEXT
VkPeerMemoryFeatureFlagBitsKHR                                :: alias VkPeerMemoryFeatureFlagBits
VkPeerMemoryFeatureFlagsKHR                                   :: alias VkPeerMemoryFeatureFlags
VkPhysicalDevice16BitStorageFeaturesKHR                       :: alias VkPhysicalDevice16BitStorageFeatures
VkPhysicalDevice8BitStorageFeaturesKHR                        :: alias VkPhysicalDevice8BitStorageFeatures
VkPhysicalDeviceBufferAddressFeaturesEXT                      :: alias VkPhysicalDeviceBufferDeviceAddressFeaturesEXT
VkPhysicalDeviceBufferDeviceAddressFeaturesKHR                :: alias VkPhysicalDeviceBufferDeviceAddressFeatures
VkPhysicalDeviceDepthStencilResolvePropertiesKHR              :: alias VkPhysicalDeviceDepthStencilResolveProperties
VkPhysicalDeviceDescriptorIndexingFeaturesEXT                 :: alias VkPhysicalDeviceDescriptorIndexingFeatures
VkPhysicalDeviceDescriptorIndexingPropertiesEXT               :: alias VkPhysicalDeviceDescriptorIndexingProperties
VkPhysicalDeviceDriverPropertiesKHR                           :: alias VkPhysicalDeviceDriverProperties
VkPhysicalDeviceDynamicRenderingFeaturesKHR                   :: alias VkPhysicalDeviceDynamicRenderingFeatures
VkPhysicalDeviceExternalBufferInfoKHR                         :: alias VkPhysicalDeviceExternalBufferInfo
VkPhysicalDeviceExternalFenceInfoKHR                          :: alias VkPhysicalDeviceExternalFenceInfo
VkPhysicalDeviceExternalImageFormatInfoKHR                    :: alias VkPhysicalDeviceExternalImageFormatInfo
VkPhysicalDeviceExternalSemaphoreInfoKHR                      :: alias VkPhysicalDeviceExternalSemaphoreInfo
VkPhysicalDeviceFeatures2KHR                                  :: alias VkPhysicalDeviceFeatures2
VkPhysicalDeviceFloat16Int8FeaturesKHR                        :: alias VkPhysicalDeviceShaderFloat16Int8Features
VkPhysicalDeviceFloatControlsPropertiesKHR                    :: alias VkPhysicalDeviceFloatControlsProperties
VkPhysicalDeviceFragmentShaderBarycentricFeaturesNV           :: alias VkPhysicalDeviceFragmentShaderBarycentricFeaturesKHR
VkPhysicalDeviceGlobalPriorityQueryFeaturesEXT                :: alias VkPhysicalDeviceGlobalPriorityQueryFeaturesKHR
VkPhysicalDeviceGroupPropertiesKHR                            :: alias VkPhysicalDeviceGroupProperties
VkPhysicalDeviceHostQueryResetFeaturesEXT                     :: alias VkPhysicalDeviceHostQueryResetFeatures
VkPhysicalDeviceIDPropertiesKHR                               :: alias VkPhysicalDeviceIDProperties
VkPhysicalDeviceImageFormatInfo2KHR                           :: alias VkPhysicalDeviceImageFormatInfo2
VkPhysicalDeviceImagelessFramebufferFeaturesKHR               :: alias VkPhysicalDeviceImagelessFramebufferFeatures
VkPhysicalDeviceImageRobustnessFeaturesEXT                    :: alias VkPhysicalDeviceImageRobustnessFeatures
VkPhysicalDeviceIndexTypeUint8FeaturesEXT                     :: alias VkPhysicalDeviceIndexTypeUint8FeaturesKHR
VkPhysicalDeviceInlineUniformBlockFeaturesEXT                 :: alias VkPhysicalDeviceInlineUniformBlockFeatures
VkPhysicalDeviceInlineUniformBlockPropertiesEXT               :: alias VkPhysicalDeviceInlineUniformBlockProperties
VkPhysicalDeviceLineRasterizationFeaturesEXT                  :: alias VkPhysicalDeviceLineRasterizationFeaturesKHR
VkPhysicalDeviceLineRasterizationPropertiesEXT                :: alias VkPhysicalDeviceLineRasterizationPropertiesKHR
VkPhysicalDeviceMaintenance3PropertiesKHR                     :: alias VkPhysicalDeviceMaintenance3Properties
VkPhysicalDeviceMaintenance4FeaturesKHR                       :: alias VkPhysicalDeviceMaintenance4Features
VkPhysicalDeviceMaintenance4PropertiesKHR                     :: alias VkPhysicalDeviceMaintenance4Properties
VkPhysicalDeviceMemoryProperties2KHR                          :: alias VkPhysicalDeviceMemoryProperties2
VkPhysicalDeviceMultiviewFeaturesKHR                          :: alias VkPhysicalDeviceMultiviewFeatures
VkPhysicalDeviceMultiviewPropertiesKHR                        :: alias VkPhysicalDeviceMultiviewProperties
VkPhysicalDeviceMutableDescriptorTypeFeaturesVALVE            :: alias VkPhysicalDeviceMutableDescriptorTypeFeaturesEXT
VkPhysicalDevicePipelineCreationCacheControlFeaturesEXT       :: alias VkPhysicalDevicePipelineCreationCacheControlFeatures
VkPhysicalDevicePointClippingPropertiesKHR                    :: alias VkPhysicalDevicePointClippingProperties
VkPhysicalDevicePrivateDataFeaturesEXT                        :: alias VkPhysicalDevicePrivateDataFeatures
VkPhysicalDeviceProperties2KHR                                :: alias VkPhysicalDeviceProperties2
VkPhysicalDeviceRasterizationOrderAttachmentAccessFeaturesARM :: alias VkPhysicalDeviceRasterizationOrderAttachmentAccessFeaturesEXT
VkPhysicalDeviceSamplerFilterMinmaxPropertiesEXT              :: alias VkPhysicalDeviceSamplerFilterMinmaxProperties
VkPhysicalDeviceSamplerYcbcrConversionFeaturesKHR             :: alias VkPhysicalDeviceSamplerYcbcrConversionFeatures
VkPhysicalDeviceScalarBlockLayoutFeaturesEXT                  :: alias VkPhysicalDeviceScalarBlockLayoutFeatures
VkPhysicalDeviceSeparateDepthStencilLayoutsFeaturesKHR        :: alias VkPhysicalDeviceSeparateDepthStencilLayoutsFeatures
VkPhysicalDeviceShaderAtomicInt64FeaturesKHR                  :: alias VkPhysicalDeviceShaderAtomicInt64Features
VkPhysicalDeviceShaderDemoteToHelperInvocationFeaturesEXT     :: alias VkPhysicalDeviceShaderDemoteToHelperInvocationFeatures
VkPhysicalDeviceShaderDrawParameterFeatures                   :: alias VkPhysicalDeviceShaderDrawParametersFeatures
VkPhysicalDeviceShaderFloat16Int8FeaturesKHR                  :: alias VkPhysicalDeviceShaderFloat16Int8Features
VkPhysicalDeviceShaderIntegerDotProductFeaturesKHR            :: alias VkPhysicalDeviceShaderIntegerDotProductFeatures
VkPhysicalDeviceShaderIntegerDotProductPropertiesKHR          :: alias VkPhysicalDeviceShaderIntegerDotProductProperties
VkPhysicalDeviceShaderSubgroupExtendedTypesFeaturesKHR        :: alias VkPhysicalDeviceShaderSubgroupExtendedTypesFeatures
VkPhysicalDeviceShaderTerminateInvocationFeaturesKHR          :: alias VkPhysicalDeviceShaderTerminateInvocationFeatures
VkPhysicalDeviceSparseImageFormatInfo2KHR                     :: alias VkPhysicalDeviceSparseImageFormatInfo2
VkPhysicalDeviceSubgroupSizeControlFeaturesEXT                :: alias VkPhysicalDeviceSubgroupSizeControlFeatures
VkPhysicalDeviceSubgroupSizeControlPropertiesEXT              :: alias VkPhysicalDeviceSubgroupSizeControlProperties
VkPhysicalDeviceSynchronization2FeaturesKHR                   :: alias VkPhysicalDeviceSynchronization2Features
VkPhysicalDeviceTexelBufferAlignmentPropertiesEXT             :: alias VkPhysicalDeviceTexelBufferAlignmentProperties
VkPhysicalDeviceTextureCompressionASTCHDRFeaturesEXT          :: alias VkPhysicalDeviceTextureCompressionASTCHDRFeatures
VkPhysicalDeviceTimelineSemaphoreFeaturesKHR                  :: alias VkPhysicalDeviceTimelineSemaphoreFeatures
VkPhysicalDeviceTimelineSemaphorePropertiesKHR                :: alias VkPhysicalDeviceTimelineSemaphoreProperties
VkPhysicalDeviceToolPropertiesEXT                             :: alias VkPhysicalDeviceToolProperties
VkPhysicalDeviceUniformBufferStandardLayoutFeaturesKHR        :: alias VkPhysicalDeviceUniformBufferStandardLayoutFeatures
VkPhysicalDeviceVariablePointerFeatures                       :: alias VkPhysicalDeviceVariablePointersFeatures
VkPhysicalDeviceVariablePointerFeaturesKHR                    :: alias VkPhysicalDeviceVariablePointersFeatures
VkPhysicalDeviceVariablePointersFeaturesKHR                   :: alias VkPhysicalDeviceVariablePointersFeatures
VkPhysicalDeviceVertexAttributeDivisorFeaturesEXT             :: alias VkPhysicalDeviceVertexAttributeDivisorFeaturesKHR
VkPhysicalDeviceVulkanMemoryModelFeaturesKHR                  :: alias VkPhysicalDeviceVulkanMemoryModelFeatures
VkPhysicalDeviceZeroInitializeWorkgroupMemoryFeaturesKHR      :: alias VkPhysicalDeviceZeroInitializeWorkgroupMemoryFeatures
VkPipelineCreationFeedbackCreateInfoEXT                       :: alias VkPipelineCreationFeedbackCreateInfo
VkPipelineCreationFeedbackEXT                                 :: alias VkPipelineCreationFeedback
VkPipelineCreationFeedbackFlagBitsEXT                         :: alias VkPipelineCreationFeedbackFlagBits
VkPipelineCreationFeedbackFlagsEXT                            :: alias VkPipelineCreationFeedbackFlags
VkPipelineInfoEXT                                             :: alias VkPipelineInfoKHR
VkPipelineRasterizationLineStateCreateInfoEXT                 :: alias VkPipelineRasterizationLineStateCreateInfoKHR
VkPipelineRenderingCreateInfoKHR                              :: alias VkPipelineRenderingCreateInfo
VkPipelineShaderStageRequiredSubgroupSizeCreateInfoEXT        :: alias VkPipelineShaderStageRequiredSubgroupSizeCreateInfo
VkPipelineStageFlagBits2KHR                                   :: alias VkPipelineStageFlagBits2
VkPipelineStageFlags2KHR                                      :: alias VkPipelineStageFlags2
VkPipelineTessellationDomainOriginStateCreateInfoKHR          :: alias VkPipelineTessellationDomainOriginStateCreateInfo
VkPipelineVertexInputDivisorStateCreateInfoEXT                :: alias VkPipelineVertexInputDivisorStateCreateInfoKHR
VkPointClippingBehaviorKHR                                    :: alias VkPointClippingBehavior
VkPrivateDataSlotCreateFlagsEXT                               :: alias VkPrivateDataSlotCreateFlags
VkPrivateDataSlotCreateInfoEXT                                :: alias VkPrivateDataSlotCreateInfo
VkPrivateDataSlotEXT                                          :: alias VkPrivateDataSlot
VkQueryPoolCreateInfoINTEL                                    :: alias VkQueryPoolPerformanceQueryCreateInfoINTEL
VkQueueFamilyGlobalPriorityPropertiesEXT                      :: alias VkQueueFamilyGlobalPriorityPropertiesKHR
VkQueueFamilyProperties2KHR                                   :: alias VkQueueFamilyProperties2
VkQueueGlobalPriorityEXT                                      :: alias VkQueueGlobalPriorityKHR
VkRayTracingShaderGroupTypeNV                                 :: alias VkRayTracingShaderGroupTypeKHR
VkRemoteAddressNV                                             :: alias rawptr
VkRenderingAttachmentInfoKHR                                  :: alias VkRenderingAttachmentInfo
VkRenderingFlagBitsKHR                                        :: alias VkRenderingFlagBits
VkRenderingFlagsKHR                                           :: alias VkRenderingFlags
VkRenderingInfoKHR                                            :: alias VkRenderingInfo
VkRenderPassAttachmentBeginInfoKHR                            :: alias VkRenderPassAttachmentBeginInfo
VkRenderPassCreateInfo2KHR                                    :: alias VkRenderPassCreateInfo2
VkRenderPassInputAttachmentAspectCreateInfoKHR                :: alias VkRenderPassInputAttachmentAspectCreateInfo
VkRenderPassMultiviewCreateInfoKHR                            :: alias VkRenderPassMultiviewCreateInfo
VkResolveImageInfo2KHR                                        :: alias VkResolveImageInfo2
VkResolveModeFlagBitsKHR                                      :: alias VkResolveModeFlagBits
VkResolveModeFlagsKHR                                         :: alias VkResolveModeFlags
VkSamplerReductionModeCreateInfoEXT                           :: alias VkSamplerReductionModeCreateInfo
VkSamplerReductionModeEXT                                     :: alias VkSamplerReductionMode
VkSamplerYcbcrConversionCreateInfoKHR                         :: alias VkSamplerYcbcrConversionCreateInfo
VkSamplerYcbcrConversionImageFormatPropertiesKHR              :: alias VkSamplerYcbcrConversionImageFormatProperties
VkSamplerYcbcrConversionInfoKHR                               :: alias VkSamplerYcbcrConversionInfo
VkSamplerYcbcrConversionKHR                                   :: alias VkSamplerYcbcrConversion
VkSamplerYcbcrModelConversionKHR                              :: alias VkSamplerYcbcrModelConversion
VkSamplerYcbcrRangeKHR                                        :: alias VkSamplerYcbcrRange
VkScopeNV                                                     :: alias VkScopeKHR
VkSemaphoreImportFlagBitsKHR                                  :: alias VkSemaphoreImportFlagBits
VkSemaphoreImportFlagsKHR                                     :: alias VkSemaphoreImportFlags
VkSemaphoreSignalInfoKHR                                      :: alias VkSemaphoreSignalInfo
VkSemaphoreSubmitInfoKHR                                      :: alias VkSemaphoreSubmitInfo
VkSemaphoreTypeCreateInfoKHR                                  :: alias VkSemaphoreTypeCreateInfo
VkSemaphoreTypeKHR                                            :: alias VkSemaphoreType
VkSemaphoreWaitFlagBitsKHR                                    :: alias VkSemaphoreWaitFlagBits
VkSemaphoreWaitFlagsKHR                                       :: alias VkSemaphoreWaitFlags
VkSemaphoreWaitInfoKHR                                        :: alias VkSemaphoreWaitInfo
VkShaderFloatControlsIndependenceKHR                          :: alias VkShaderFloatControlsIndependence
VkShaderRequiredSubgroupSizeCreateInfoEXT                     :: alias VkPipelineShaderStageRequiredSubgroupSizeCreateInfo
VkSparseImageFormatProperties2KHR                             :: alias VkSparseImageFormatProperties2
VkSparseImageMemoryRequirements2KHR                           :: alias VkSparseImageMemoryRequirements2
VkSubmitFlagBitsKHR                                           :: alias VkSubmitFlagBits
VkSubmitFlagsKHR                                              :: alias VkSubmitFlags
VkSubmitInfo2KHR                                              :: alias VkSubmitInfo2
VkSubpassBeginInfoKHR                                         :: alias VkSubpassBeginInfo
VkSubpassDependency2KHR                                       :: alias VkSubpassDependency2
VkSubpassDescription2KHR                                      :: alias VkSubpassDescription2
VkSubpassDescriptionDepthStencilResolveKHR                    :: alias VkSubpassDescriptionDepthStencilResolve
VkSubpassEndInfoKHR                                           :: alias VkSubpassEndInfo
VkSubresourceLayout2EXT                                       :: alias VkSubresourceLayout2KHR
VkTessellationDomainOriginKHR                                 :: alias VkTessellationDomainOrigin
VkTimeDomainEXT                                               :: alias VkTimeDomainKHR
VkTimelineSemaphoreSubmitInfoKHR                              :: alias VkTimelineSemaphoreSubmitInfo
VkToolPurposeFlagBitsEXT                                      :: alias VkToolPurposeFlagBits
VkToolPurposeFlagsEXT                                         :: alias VkToolPurposeFlags
VkTransformMatrixNV                                           :: alias VkTransformMatrixKHR
VkVertexInputBindingDivisorDescriptionEXT                     :: alias VkVertexInputBindingDivisorDescriptionKHR
VkWriteDescriptorSetInlineUniformBlockEXT                     :: alias VkWriteDescriptorSetInlineUniformBlock

// Bit flag types

VkAccelerationStructureCreateFlagBitsKHR       :: distinct alias u32
VkAccessFlagBits                               :: distinct alias u32
VkAcquireProfilingLockFlagBitsKHR              :: distinct alias u32
VkAttachmentDescriptionFlagBits                :: distinct alias u32
VkBufferCreateFlagBits                         :: distinct alias u32
VkBufferUsageFlagBits                          :: distinct alias u32
VkBuildAccelerationStructureFlagBitsKHR        :: distinct alias u32
VkBuildMicromapFlagBitsEXT                     :: distinct alias u32
VkColorComponentFlagBits                       :: distinct alias u32
VkCommandBufferResetFlagBits                   :: distinct alias u32
VkCommandBufferUsageFlagBits                   :: distinct alias u32
VkCommandPoolCreateFlagBits                    :: distinct alias u32
VkCommandPoolResetFlagBits                     :: distinct alias u32
VkCompositeAlphaFlagBitsKHR                    :: distinct alias u32
VkConditionalRenderingFlagBitsEXT              :: distinct alias u32
VkCullModeFlagBits                             :: distinct alias u32
VkDebugReportFlagBitsEXT                       :: distinct alias u32
VkDebugUtilsMessageSeverityFlagBitsEXT         :: distinct alias u32
VkDebugUtilsMessageTypeFlagBitsEXT             :: distinct alias u32
VkDependencyFlagBits                           :: distinct alias u32
VkDescriptorBindingFlagBits                    :: distinct alias u32
VkDescriptorPoolCreateFlagBits                 :: distinct alias u32
VkDescriptorSetLayoutCreateFlagBits            :: distinct alias u32
VkDeviceAddressBindingFlagBitsEXT              :: distinct alias u32
VkDeviceDiagnosticsConfigFlagBitsNV            :: distinct alias u32
VkDeviceGroupPresentModeFlagBitsKHR            :: distinct alias u32
VkDeviceQueueCreateFlagBits                    :: distinct alias u32
VkDisplayPlaneAlphaFlagBitsKHR                 :: distinct alias u32
VkEventCreateFlagBits                          :: distinct alias u32
VkExternalFenceFeatureFlagBits                 :: distinct alias u32
VkExternalFenceHandleTypeFlagBits              :: distinct alias u32
VkExternalMemoryFeatureFlagBits                :: distinct alias u32
VkExternalMemoryFeatureFlagBitsNV              :: distinct alias u32
VkExternalMemoryHandleTypeFlagBits             :: distinct alias u32
VkExternalMemoryHandleTypeFlagBitsNV           :: distinct alias u32
VkExternalSemaphoreFeatureFlagBits             :: distinct alias u32
VkExternalSemaphoreHandleTypeFlagBits          :: distinct alias u32
VkFenceCreateFlagBits                          :: distinct alias u32
VkFenceImportFlagBits                          :: distinct alias u32
VkFormatFeatureFlagBits                        :: distinct alias u32
VkFrameBoundaryFlagBitsEXT                     :: distinct alias u32
VkFramebufferCreateFlagBits                    :: distinct alias u32
VkGeometryFlagBitsKHR                          :: distinct alias u32
VkGeometryInstanceFlagBitsKHR                  :: distinct alias u32
VkGraphicsPipelineLibraryFlagBitsEXT           :: distinct alias u32
VkHostImageCopyFlagBitsEXT                     :: distinct alias u32
VkImageAspectFlagBits                          :: distinct alias u32
VkImageCompressionFixedRateFlagBitsEXT         :: distinct alias u32
VkImageCompressionFlagBitsEXT                  :: distinct alias u32
VkImageCreateFlagBits                          :: distinct alias u32
VkImageUsageFlagBits                           :: distinct alias u32
VkImageViewCreateFlagBits                      :: distinct alias u32
VkIndirectCommandsLayoutUsageFlagBitsNV        :: distinct alias u32
VkIndirectStateFlagBitsNV                      :: distinct alias u32
VkInstanceCreateFlagBits                       :: distinct alias u32
VkMemoryAllocateFlagBits                       :: distinct alias u32
VkMemoryHeapFlagBits                           :: distinct alias u32
VkMemoryMapFlagBits                            :: distinct alias u32
VkMemoryPropertyFlagBits                       :: distinct alias u32
VkMemoryUnmapFlagBitsKHR                       :: distinct alias u32
VkMicromapCreateFlagBitsEXT                    :: distinct alias u32
VkOpticalFlowExecuteFlagBitsNV                 :: distinct alias u32
VkOpticalFlowGridSizeFlagBitsNV                :: distinct alias u32
VkOpticalFlowSessionCreateFlagBitsNV           :: distinct alias u32
VkOpticalFlowUsageFlagBitsNV                   :: distinct alias u32
VkPeerMemoryFeatureFlagBits                    :: distinct alias u32
VkPerformanceCounterDescriptionFlagBitsKHR     :: distinct alias u32
VkPipelineCacheCreateFlagBits                  :: distinct alias u32
VkPipelineColorBlendStateCreateFlagBits        :: distinct alias u32
VkPipelineCompilerControlFlagBitsAMD           :: distinct alias u32
VkPipelineCreateFlagBits                       :: distinct alias u32
VkPipelineCreationFeedbackFlagBits             :: distinct alias u32
VkPipelineDepthStencilStateCreateFlagBits      :: distinct alias u32
VkPipelineLayoutCreateFlagBits                 :: distinct alias u32
VkPipelineShaderStageCreateFlagBits            :: distinct alias u32
VkPipelineStageFlagBits                        :: distinct alias u32
VkPresentGravityFlagBitsEXT                    :: distinct alias u32
VkPresentScalingFlagBitsEXT                    :: distinct alias u32
VkQueryControlFlagBits                         :: distinct alias u32
VkQueryPipelineStatisticFlagBits               :: distinct alias u32
VkQueryResultFlagBits                          :: distinct alias u32
VkQueueFlagBits                                :: distinct alias u32
VkRenderingFlagBits                            :: distinct alias u32
VkRenderPassCreateFlagBits                     :: distinct alias u32
VkResolveModeFlagBits                          :: distinct alias u32
VkSampleCountFlagBits                          :: distinct alias u32
VkSamplerCreateFlagBits                        :: distinct alias u32
VkSemaphoreImportFlagBits                      :: distinct alias u32
VkSemaphoreWaitFlagBits                        :: distinct alias u32
VkShaderCorePropertiesFlagBitsAMD              :: distinct alias u32
VkShaderCreateFlagBitsEXT                      :: distinct alias u32
VkShaderStageFlagBits                          :: distinct alias u32
VkSparseImageFormatFlagBits                    :: distinct alias u32
VkSparseMemoryBindFlagBits                     :: distinct alias u32
VkStencilFaceFlagBits                          :: distinct alias u32
VkSubgroupFeatureFlagBits                      :: distinct alias u32
VkSubmitFlagBits                               :: distinct alias u32
VkSubpassDescriptionFlagBits                   :: distinct alias u32
VkSurfaceCounterFlagBitsEXT                    :: distinct alias u32
VkSurfaceTransformFlagBitsKHR                  :: distinct alias u32
VkSwapchainCreateFlagBitsKHR                   :: distinct alias u32
VkToolPurposeFlagBits                          :: distinct alias u32
VkVideoCapabilityFlagBitsKHR                   :: distinct alias u32
VkVideoChromaSubsamplingFlagBitsKHR            :: distinct alias u32
VkVideoCodecOperationFlagBitsKHR               :: distinct alias u32
VkVideoCodingControlFlagBitsKHR                :: distinct alias u32
VkVideoComponentBitDepthFlagBitsKHR            :: distinct alias u32
VkVideoDecodeCapabilityFlagBitsKHR             :: distinct alias u32
VkVideoDecodeH264PictureLayoutFlagBitsKHR      :: distinct alias u32
VkVideoDecodeUsageFlagBitsKHR                  :: distinct alias u32
VkVideoEncodeCapabilityFlagBitsKHR             :: distinct alias u32
VkVideoEncodeContentFlagBitsKHR                :: distinct alias u32
VkVideoEncodeFeedbackFlagBitsKHR               :: distinct alias u32
VkVideoEncodeFlagBitsKHR                       :: distinct alias u32
VkVideoEncodeH264CapabilityFlagBitsKHR         :: distinct alias u32
VkVideoEncodeH264RateControlFlagBitsKHR        :: distinct alias u32
VkVideoEncodeH264StdFlagBitsKHR                :: distinct alias u32
VkVideoEncodeH265CapabilityFlagBitsKHR         :: distinct alias u32
VkVideoEncodeH265CtbSizeFlagBitsKHR            :: distinct alias u32
VkVideoEncodeH265RateControlFlagBitsKHR        :: distinct alias u32
VkVideoEncodeH265StdFlagBitsKHR                :: distinct alias u32
VkVideoEncodeH265TransformBlockSizeFlagBitsKHR :: distinct alias u32
VkVideoEncodeRateControlModeFlagBitsKHR        :: distinct alias u32
VkVideoEncodeUsageFlagBitsKHR                  :: distinct alias u32
VkVideoSessionCreateFlagBitsKHR                :: distinct alias u32


// Function pointers
PFN_vkAcquireDrmDisplayEXT                                            :: alias fn(physicalDevice: VkPhysicalDevice, drmFd: i32, display: VkDisplayKHR) -> VkResult
PFN_vkAcquireNextImage2KHR                                            :: alias fn(device: VkDevice, pAcquireInfo: ptr[VkAcquireNextImageInfoKHR], pImageIndex: ptr[u32]) -> VkResult
PFN_vkAcquireNextImageKHR                                             :: alias fn(device: VkDevice, swapchain: VkSwapchainKHR, timeout: u64, semaphore: VkSemaphore, fence: VkFence, pImageIndex: ptr[u32]) -> VkResult
PFN_vkAcquirePerformanceConfigurationINTEL                            :: alias fn(device: VkDevice, pAcquireInfo: ptr[VkPerformanceConfigurationAcquireInfoINTEL], pConfiguration: ptr[VkPerformanceConfigurationINTEL]) -> VkResult
PFN_vkAcquireProfilingLockKHR                                         :: alias fn(device: VkDevice, pInfo: ptr[VkAcquireProfilingLockInfoKHR]) -> VkResult
PFN_vkAllocateCommandBuffers                                          :: alias fn(device: VkDevice, pAllocateInfo: ptr[VkCommandBufferAllocateInfo], pCommandBuffers: ptr[VkCommandBuffer]) -> VkResult
PFN_vkAllocateDescriptorSets                                          :: alias fn(device: VkDevice, pAllocateInfo: ptr[VkDescriptorSetAllocateInfo], pDescriptorSets: ptr[VkDescriptorSet]) -> VkResult
PFN_vkAllocateMemory                                                  :: alias fn(device: VkDevice, pAllocateInfo: ptr[VkMemoryAllocateInfo], pAllocator: ptr[VkAllocationCallbacks], pMemory: ptr[VkDeviceMemory]) -> VkResult
PFN_vkAllocationFunction                                              :: alias fn(pUserData: rawptr, size: uint, alignmenat: uint, allocationScope: VkSystemAllocationScope) -> rawptr
PFN_vkBeginCommandBuffer                                              :: alias fn(commandBuffer: VkCommandBuffer, pBeginInfo: ptr[VkCommandBufferBeginInfo]) -> VkResult
PFN_vkBindAccelerationStructureMemoryNV                               :: alias fn(device: VkDevice, bindInfoCount: u32, pBindInfos: ptr[VkBindAccelerationStructureMemoryInfoNV]) -> VkResult
PFN_vkBindBufferMemory                                                :: alias fn(device: VkDevice, buffer: VkBuffer, memory: VkDeviceMemory, memoryOffset: VkDeviceSize) -> VkResult
PFN_vkBindBufferMemory2                                               :: alias fn(device: VkDevice, bindInfoCount: u32, pBindInfos: ptr[VkBindBufferMemoryInfo]) -> VkResult
PFN_vkBindBufferMemory2KHR                                            :: alias fn(device: VkDevice, bindInfoCount: u32, pBindInfos: ptr[VkBindBufferMemoryInfo]) -> VkResult
PFN_vkBindImageMemory                                                 :: alias fn(device: VkDevice, image: VkImage, memory: VkDeviceMemory, memoryOffset: VkDeviceSize) -> VkResult
PFN_vkBindImageMemory2                                                :: alias fn(device: VkDevice, bindInfoCount: u32, pBindInfos: ptr[VkBindImageMemoryInfo]) -> VkResult
PFN_vkBindImageMemory2KHR                                             :: alias fn(device: VkDevice, bindInfoCount: u32, pBindInfos: ptr[VkBindImageMemoryInfo]) -> VkResult
PFN_vkBindOpticalFlowSessionImageNV                                   :: alias fn(device: VkDevice, session: VkOpticalFlowSessionNV, bindingPoint: VkOpticalFlowSessionBindingPointNV, view: VkImageView, layout: VkImageLayout) -> VkResult
PFN_vkBindVideoSessionMemoryKHR                                       :: alias fn(device: VkDevice, videoSession: VkVideoSessionKHR, bindSessionMemoryInfoCount: u32, pBindSessionMemoryInfos: ptr[VkBindVideoSessionMemoryInfoKHR]) -> VkResult
PFN_vkBuildAccelerationStructuresKHR                                  :: alias fn(device: VkDevice, deferredOperation: VkDeferredOperationKHR, infoCount: u32, pInfos: ptr[VkAccelerationStructureBuildGeometryInfoKHR], ptr[VkAccelerationStructureBuildRangeInfoKHR] ppBuildRangeInfos: ptr[const]) -> VkResult
PFN_vkBuildMicromapsEXT                                               :: alias fn(device: VkDevice, deferredOperation: VkDeferredOperationKHR, infoCount: u32, pInfos: ptr[VkMicromapBuildInfoEXT]) -> VkResult
PFN_vkCmdBeginConditionalRenderingEXT                                 :: alias fn(commandBuffer: VkCommandBuffer, pConditionalRenderingBegin: ptr[VkConditionalRenderingBeginInfoEXT]) -> void
PFN_vkCmdBeginDebugUtilsLabelEXT                                      :: alias fn(commandBuffer: VkCommandBuffer, pLabelInfo: ptr[VkDebugUtilsLabelEXT]) -> void
PFN_vkCmdBeginQuery                                                   :: alias fn(commandBuffer: VkCommandBuffer, queryPool: VkQueryPool, query: u32, flags: VkQueryControlFlags) -> void
PFN_vkCmdBeginQueryIndexedEXT                                         :: alias fn(commandBuffer: VkCommandBuffer, queryPool: VkQueryPool, query: u32, flags: VkQueryControlFlags, index: u32) -> void
PFN_vkCmdBeginRendering                                               :: alias fn(commandBuffer: VkCommandBuffer, pRenderingInfo: ptr[VkRenderingInfo]) -> void
PFN_vkCmdBeginRenderingKHR                                            :: alias fn(commandBuffer: VkCommandBuffer, pRenderingInfo: ptr[VkRenderingInfo]) -> void
PFN_vkCmdBeginRenderPass                                              :: alias fn(commandBuffer: VkCommandBuffer, pRenderPassBegin: ptr[VkRenderPassBeginInfo], contents: VkSubpassContents) -> void
PFN_vkCmdBeginRenderPass2                                             :: alias fn(commandBuffer: VkCommandBuffer, pRenderPassBegin: ptr[VkRenderPassBeginInfo], pSubpassBeginInfo: ptr[VkSubpassBeginInfo]) -> void
PFN_vkCmdBeginRenderPass2KHR                                          :: alias fn(commandBuffer: VkCommandBuffer, pRenderPassBegin: ptr[VkRenderPassBeginInfo], pSubpassBeginInfo: ptr[VkSubpassBeginInfo]) -> void
PFN_vkCmdBeginTransformFeedbackEXT                                    :: alias fn(commandBuffer: VkCommandBuffer, firstCounterBuffer: u32, counterBufferCount: u32, pCounterBuffers: ptr[VkBuffer], pCounterBufferOffsets: ptr[VkDeviceSize]) -> void
PFN_vkCmdBeginVideoCodingKHR                                          :: alias fn(commandBuffer: VkCommandBuffer, pBeginInfo: ptr[VkVideoBeginCodingInfoKHR]) -> void
PFN_vkCmdBindDescriptorBufferEmbeddedSamplers2EXT                     :: alias fn(commandBuffer: VkCommandBuffer, pBindDescriptorBufferEmbeddedSamplersInfo: ptr[VkBindDescriptorBufferEmbeddedSamplersInfoEXT]) -> void
PFN_vkCmdBindDescriptorBufferEmbeddedSamplersEXT                      :: alias fn(commandBuffer: VkCommandBuffer, pipelineBindPoint: VkPipelineBindPoint, layout: VkPipelineLayout, set: u32) -> void
PFN_vkCmdBindDescriptorBuffersEXT                                     :: alias fn(commandBuffer: VkCommandBuffer, bufferCount: u32, pBindingInfos: ptr[VkDescriptorBufferBindingInfoEXT]) -> void
PFN_vkCmdBindDescriptorSets                                           :: alias fn(commandBuffer: VkCommandBuffer, pipelineBindPoint: VkPipelineBindPoint, layout: VkPipelineLayout, firstSet: u32, descriptorSetCount: u32, pDescriptorSets: ptr[VkDescriptorSet], dynamicOffsetCount: u32, pDynamicOffsets: ptr[u32]) -> void
PFN_vkCmdBindDescriptorSets2KHR                                       :: alias fn(commandBuffer: VkCommandBuffer, pBindDescriptorSetsInfo: ptr[VkBindDescriptorSetsInfoKHR]) -> void
PFN_vkCmdBindIndexBuffer                                              :: alias fn(commandBuffer: VkCommandBuffer, buffer: VkBuffer, offset: VkDeviceSize, indexType: VkIndexType) -> void
PFN_vkCmdBindIndexBuffer2KHR                                          :: alias fn(commandBuffer: VkCommandBuffer, buffer: VkBuffer, offset: VkDeviceSize, size: VkDeviceSize, indexType: VkIndexType) -> void
PFN_vkCmdBindInvocationMaskHUAWEI                                     :: alias fn(commandBuffer: VkCommandBuffer, imageView: VkImageView, imageLayout: VkImageLayout) -> void
PFN_vkCmdBindPipeline                                                 :: alias fn(commandBuffer: VkCommandBuffer, pipelineBindPoint: VkPipelineBindPoint, pipeline: VkPipeline) -> void
PFN_vkCmdBindPipelineShaderGroupNV                                    :: alias fn(commandBuffer: VkCommandBuffer, pipelineBindPoint: VkPipelineBindPoint, pipeline: VkPipeline, groupIndex: u32) -> void
PFN_vkCmdBindShadersEXT                                               :: alias fn(commandBuffer: VkCommandBuffer, stageCount: u32, pStages: ptr[VkShaderStageFlagBits], pShaders: ptr[VkShaderEXT]) -> void
PFN_vkCmdBindShadingRateImageNV                                       :: alias fn(commandBuffer: VkCommandBuffer, imageView: VkImageView, imageLayout: VkImageLayout) -> void
PFN_vkCmdBindTransformFeedbackBuffersEXT                              :: alias fn(commandBuffer: VkCommandBuffer, firstBinding: u32, bindingCount: u32, pBuffers: ptr[VkBuffer], pOffsets: ptr[VkDeviceSize], pSizes: ptr[VkDeviceSize]) -> void
PFN_vkCmdBindVertexBuffers                                            :: alias fn(commandBuffer: VkCommandBuffer, firstBinding: u32, bindingCount: u32, pBuffers: ptr[VkBuffer], pOffsets: ptr[VkDeviceSize]) -> void
PFN_vkCmdBindVertexBuffers2                                           :: alias fn(commandBuffer: VkCommandBuffer, firstBinding: u32, bindingCount: u32, pBuffers: ptr[VkBuffer], pOffsets: ptr[VkDeviceSize], pSizes: ptr[VkDeviceSize], pStrides: ptr[VkDeviceSize]) -> void
PFN_vkCmdBindVertexBuffers2EXT                                        :: alias fn(commandBuffer: VkCommandBuffer, firstBinding: u32, bindingCount: u32, pBuffers: ptr[VkBuffer], pOffsets: ptr[VkDeviceSize], pSizes: ptr[VkDeviceSize], pStrides: ptr[VkDeviceSize]) -> void
PFN_vkCmdBlitImage                                                    :: alias fn(commandBuffer: VkCommandBuffer, srcImage: VkImage, srcImageLayout: VkImageLayout, dstImage: VkImage, dstImageLayout: VkImageLayout, regionCount: u32, pRegions: ptr[VkImageBlit], filter: VkFilter) -> void
PFN_vkCmdBlitImage2                                                   :: alias fn(commandBuffer: VkCommandBuffer, pBlitImageInfo: ptr[VkBlitImageInfo2]) -> void
PFN_vkCmdBlitImage2KHR                                                :: alias fn(commandBuffer: VkCommandBuffer, pBlitImageInfo: ptr[VkBlitImageInfo2]) -> void
PFN_vkCmdBuildAccelerationStructureNV                                 :: alias fn(commandBuffer: VkCommandBuffer, pInfo: ptr[VkAccelerationStructureInfoNV], instanceData: VkBuffer, instanceOffset: VkDeviceSize, update: b32, dst: VkAccelerationStructureNV, src: VkAccelerationStructureNV, scratch: VkBuffer, scratchOffset: VkDeviceSize) -> void
PFN_vkCmdBuildAccelerationStructuresIndirectKHR                       :: alias fn(commandBuffer: VkCommandBuffer, infoCount: u32, pInfos: ptr[VkAccelerationStructureBuildGeometryInfoKHR], pIndirectDeviceAddresses: ptr[VkDeviceAddress], pIndirectStrides: ptr[u32], ptr[u32] ppMaxPrimitiveCounts: ptr[const]) -> void
PFN_vkCmdBuildAccelerationStructuresKHR                               :: alias fn(commandBuffer: VkCommandBuffer, infoCount: u32, pInfos: ptr[VkAccelerationStructureBuildGeometryInfoKHR], ptr[VkAccelerationStructureBuildRangeInfoKHR] ppBuildRangeInfos: ptr[const]) -> void
PFN_vkCmdBuildMicromapsEXT                                            :: alias fn(commandBuffer: VkCommandBuffer, infoCount: u32, pInfos: ptr[VkMicromapBuildInfoEXT]) -> void
PFN_vkCmdClearAttachments                                             :: alias fn(commandBuffer: VkCommandBuffer, attachmentCount: u32, pAttachments: ptr[VkClearAttachment], rectCount: u32, pRects: ptr[VkClearRect]) -> void
PFN_vkCmdClearColorImage                                              :: alias fn(commandBuffer: VkCommandBuffer, image: VkImage, imageLayout: VkImageLayout, pColor: ptr[VkClearColorValue], rangeCount: u32, pRanges: ptr[VkImageSubresourceRange]) -> void
PFN_vkCmdClearDepthStencilImage                                       :: alias fn(commandBuffer: VkCommandBuffer, image: VkImage, imageLayout: VkImageLayout, pDepthStencil: ptr[VkClearDepthStencilValue], rangeCount: u32, pRanges: ptr[VkImageSubresourceRange]) -> void
PFN_vkCmdControlVideoCodingKHR                                        :: alias fn(commandBuffer: VkCommandBuffer, pCodingControlInfo: ptr[VkVideoCodingControlInfoKHR]) -> void
PFN_vkCmdCopyAccelerationStructureKHR                                 :: alias fn(commandBuffer: VkCommandBuffer, pInfo: ptr[VkCopyAccelerationStructureInfoKHR]) -> void
PFN_vkCmdCopyAccelerationStructureNV                                  :: alias fn(commandBuffer: VkCommandBuffer, dst: VkAccelerationStructureNV, src: VkAccelerationStructureNV, mode: VkCopyAccelerationStructureModeKHR) -> void
PFN_vkCmdCopyAccelerationStructureToMemoryKHR                         :: alias fn(commandBuffer: VkCommandBuffer, pInfo: ptr[VkCopyAccelerationStructureToMemoryInfoKHR]) -> void
PFN_vkCmdCopyBuffer                                                   :: alias fn(commandBuffer: VkCommandBuffer, srcBuffer: VkBuffer, dstBuffer: VkBuffer, regionCount: u32, pRegions: ptr[VkBufferCopy]) -> void
PFN_vkCmdCopyBuffer2                                                  :: alias fn(commandBuffer: VkCommandBuffer, pCopyBufferInfo: ptr[VkCopyBufferInfo2]) -> void
PFN_vkCmdCopyBuffer2KHR                                               :: alias fn(commandBuffer: VkCommandBuffer, pCopyBufferInfo: ptr[VkCopyBufferInfo2]) -> void
PFN_vkCmdCopyBufferToImage                                            :: alias fn(commandBuffer: VkCommandBuffer, srcBuffer: VkBuffer, dstImage: VkImage, dstImageLayout: VkImageLayout, regionCount: u32, pRegions: ptr[VkBufferImageCopy]) -> void
PFN_vkCmdCopyBufferToImage2                                           :: alias fn(commandBuffer: VkCommandBuffer, pCopyBufferToImageInfo: ptr[VkCopyBufferToImageInfo2]) -> void
PFN_vkCmdCopyBufferToImage2KHR                                        :: alias fn(commandBuffer: VkCommandBuffer, pCopyBufferToImageInfo: ptr[VkCopyBufferToImageInfo2]) -> void
PFN_vkCmdCopyImage                                                    :: alias fn(commandBuffer: VkCommandBuffer, srcImage: VkImage, srcImageLayout: VkImageLayout, dstImage: VkImage, dstImageLayout: VkImageLayout, regionCount: u32, pRegions: ptr[VkImageCopy]) -> void
PFN_vkCmdCopyImage2                                                   :: alias fn(commandBuffer: VkCommandBuffer, pCopyImageInfo: ptr[VkCopyImageInfo2]) -> void
PFN_vkCmdCopyImage2KHR                                                :: alias fn(commandBuffer: VkCommandBuffer, pCopyImageInfo: ptr[VkCopyImageInfo2]) -> void
PFN_vkCmdCopyImageToBuffer                                            :: alias fn(commandBuffer: VkCommandBuffer, srcImage: VkImage, srcImageLayout: VkImageLayout, dstBuffer: VkBuffer, regionCount: u32, pRegions: ptr[VkBufferImageCopy]) -> void
PFN_vkCmdCopyImageToBuffer2                                           :: alias fn(commandBuffer: VkCommandBuffer, pCopyImageToBufferInfo: ptr[VkCopyImageToBufferInfo2]) -> void
PFN_vkCmdCopyImageToBuffer2KHR                                        :: alias fn(commandBuffer: VkCommandBuffer, pCopyImageToBufferInfo: ptr[VkCopyImageToBufferInfo2]) -> void
PFN_vkCmdCopyMemoryIndirectNV                                         :: alias fn(commandBuffer: VkCommandBuffer, copyBufferAddress: VkDeviceAddress, copyCount: u32, stride: u32) -> void
PFN_vkCmdCopyMemoryToAccelerationStructureKHR                         :: alias fn(commandBuffer: VkCommandBuffer, pInfo: ptr[VkCopyMemoryToAccelerationStructureInfoKHR]) -> void
PFN_vkCmdCopyMemoryToImageIndirectNV                                  :: alias fn(commandBuffer: VkCommandBuffer, copyBufferAddress: VkDeviceAddress, copyCount: u32, stride: u32, dstImage: VkImage, dstImageLayout: VkImageLayout, pImageSubresources: ptr[VkImageSubresourceLayers]) -> void
PFN_vkCmdCopyMemoryToMicromapEXT                                      :: alias fn(commandBuffer: VkCommandBuffer, pInfo: ptr[VkCopyMemoryToMicromapInfoEXT]) -> void
PFN_vkCmdCopyMicromapEXT                                              :: alias fn(commandBuffer: VkCommandBuffer, pInfo: ptr[VkCopyMicromapInfoEXT]) -> void
PFN_vkCmdCopyMicromapToMemoryEXT                                      :: alias fn(commandBuffer: VkCommandBuffer, pInfo: ptr[VkCopyMicromapToMemoryInfoEXT]) -> void
PFN_vkCmdCopyQueryPoolResults                                         :: alias fn(commandBuffer: VkCommandBuffer, queryPool: VkQueryPool, firstQuery: u32, queryCount: u32, dstBuffer: VkBuffer, dstOffset: VkDeviceSize, stride: VkDeviceSize, flags: VkQueryResultFlags) -> void
PFN_vkCmdCudaLaunchKernelNV                                           :: alias fn(commandBuffer: VkCommandBuffer, pLaunchInfo: ptr[VkCudaLaunchInfoNV]) -> void
PFN_vkCmdCuLaunchKernelNVX                                            :: alias fn(commandBuffer: VkCommandBuffer, pLaunchInfo: ptr[VkCuLaunchInfoNVX]) -> void
PFN_vkCmdDebugMarkerBeginEXT                                          :: alias fn(commandBuffer: VkCommandBuffer, pMarkerInfo: ptr[VkDebugMarkerMarkerInfoEXT]) -> void
PFN_vkCmdDebugMarkerEndEXT                                            :: alias fn(commandBuffer: VkCommandBuffer) -> void
PFN_vkCmdDebugMarkerInsertEXT                                         :: alias fn(commandBuffer: VkCommandBuffer, pMarkerInfo: ptr[VkDebugMarkerMarkerInfoEXT]) -> void
PFN_vkCmdDecodeVideoKHR                                               :: alias fn(commandBuffer: VkCommandBuffer, pDecodeInfo: ptr[VkVideoDecodeInfoKHR]) -> void
PFN_vkCmdDecompressMemoryIndirectCountNV                              :: alias fn(commandBuffer: VkCommandBuffer, indirectCommandsAddress: VkDeviceAddress, indirectCommandsCountAddress: VkDeviceAddress, stride: u32) -> void
PFN_vkCmdDecompressMemoryNV                                           :: alias fn(commandBuffer: VkCommandBuffer, decompressRegionCount: u32, pDecompressMemoryRegions: ptr[VkDecompressMemoryRegionNV]) -> void
PFN_vkCmdDispatch                                                     :: alias fn(commandBuffer: VkCommandBuffer, groupCountX: u32, groupCountY: u32, groupCountZ: u32) -> void
PFN_vkCmdDispatchBase                                                 :: alias fn(commandBuffer: VkCommandBuffer, baseGroupX: u32, baseGroupY: u32, baseGroupZ: u32, groupCountX: u32, groupCountY: u32, groupCountZ: u32) -> void
PFN_vkCmdDispatchBaseKHR                                              :: alias fn(commandBuffer: VkCommandBuffer, baseGroupX: u32, baseGroupY: u32, baseGroupZ: u32, groupCountX: u32, groupCountY: u32, groupCountZ: u32) -> void
PFN_vkCmdDispatchIndirect                                             :: alias fn(commandBuffer: VkCommandBuffer, buffer: VkBuffer, offset: VkDeviceSize) -> void
PFN_vkCmdDraw                                                         :: alias fn(commandBuffer: VkCommandBuffer, vertexCount: u32, instanceCount: u32, firstVertex: u32, firstInstance: u32) -> void
PFN_vkCmdDrawClusterHUAWEI                                            :: alias fn(commandBuffer: VkCommandBuffer, groupCountX: u32, groupCountY: u32, groupCountZ: u32) -> void
PFN_vkCmdDrawClusterIndirectHUAWEI                                    :: alias fn(commandBuffer: VkCommandBuffer, buffer: VkBuffer, offset: VkDeviceSize) -> void
PFN_vkCmdDrawIndexed                                                  :: alias fn(commandBuffer: VkCommandBuffer, indexCount: u32, instanceCount: u32, firstIndex: u32, vertexOffset: i32, firstInstance: u32) -> void
PFN_vkCmdDrawIndexedIndirect                                          :: alias fn(commandBuffer: VkCommandBuffer, buffer: VkBuffer, offset: VkDeviceSize, drawCount: u32, stride: u32) -> void
PFN_vkCmdDrawIndexedIndirectCount                                     :: alias fn(commandBuffer: VkCommandBuffer, buffer: VkBuffer, offset: VkDeviceSize, countBuffer: VkBuffer, countBufferOffset: VkDeviceSize, maxDrawCount: u32, stride: u32) -> void
PFN_vkCmdDrawIndexedIndirectCountAMD                                  :: alias fn(commandBuffer: VkCommandBuffer, buffer: VkBuffer, offset: VkDeviceSize, countBuffer: VkBuffer, countBufferOffset: VkDeviceSize, maxDrawCount: u32, stride: u32) -> void
PFN_vkCmdDrawIndexedIndirectCountKHR                                  :: alias fn(commandBuffer: VkCommandBuffer, buffer: VkBuffer, offset: VkDeviceSize, countBuffer: VkBuffer, countBufferOffset: VkDeviceSize, maxDrawCount: u32, stride: u32) -> void
PFN_vkCmdDrawIndirect                                                 :: alias fn(commandBuffer: VkCommandBuffer, buffer: VkBuffer, offset: VkDeviceSize, drawCount: u32, stride: u32) -> void
PFN_vkCmdDrawIndirectByteCountEXT                                     :: alias fn(commandBuffer: VkCommandBuffer, instanceCount: u32, firstInstance: u32, counterBuffer: VkBuffer, counterBufferOffset: VkDeviceSize, counterOffset: u32, vertexStride: u32) -> void
PFN_vkCmdDrawIndirectCount                                            :: alias fn(commandBuffer: VkCommandBuffer, buffer: VkBuffer, offset: VkDeviceSize, countBuffer: VkBuffer, countBufferOffset: VkDeviceSize, maxDrawCount: u32, stride: u32) -> void
PFN_vkCmdDrawIndirectCountAMD                                         :: alias fn(commandBuffer: VkCommandBuffer, buffer: VkBuffer, offset: VkDeviceSize, countBuffer: VkBuffer, countBufferOffset: VkDeviceSize, maxDrawCount: u32, stride: u32) -> void
PFN_vkCmdDrawIndirectCountKHR                                         :: alias fn(commandBuffer: VkCommandBuffer, buffer: VkBuffer, offset: VkDeviceSize, countBuffer: VkBuffer, countBufferOffset: VkDeviceSize, maxDrawCount: u32, stride: u32) -> void
PFN_vkCmdDrawMeshTasksEXT                                             :: alias fn(commandBuffer: VkCommandBuffer, groupCountX: u32, groupCountY: u32, groupCountZ: u32) -> void
PFN_vkCmdDrawMeshTasksIndirectCountEXT                                :: alias fn(commandBuffer: VkCommandBuffer, buffer: VkBuffer, offset: VkDeviceSize, countBuffer: VkBuffer, countBufferOffset: VkDeviceSize, maxDrawCount: u32, stride: u32) -> void
PFN_vkCmdDrawMeshTasksIndirectCountNV                                 :: alias fn(commandBuffer: VkCommandBuffer, buffer: VkBuffer, offset: VkDeviceSize, countBuffer: VkBuffer, countBufferOffset: VkDeviceSize, maxDrawCount: u32, stride: u32) -> void
PFN_vkCmdDrawMeshTasksIndirectEXT                                     :: alias fn(commandBuffer: VkCommandBuffer, buffer: VkBuffer, offset: VkDeviceSize, drawCount: u32, stride: u32) -> void
PFN_vkCmdDrawMeshTasksIndirectNV                                      :: alias fn(commandBuffer: VkCommandBuffer, buffer: VkBuffer, offset: VkDeviceSize, drawCount: u32, stride: u32) -> void
PFN_vkCmdDrawMeshTasksNV                                              :: alias fn(commandBuffer: VkCommandBuffer, taskCount: u32, firstTask: u32) -> void
PFN_vkCmdDrawMultiEXT                                                 :: alias fn(commandBuffer: VkCommandBuffer, drawCount: u32, pVertexInfo: ptr[VkMultiDrawInfoEXT], instanceCount: u32, firstInstance: u32, stride: u32) -> void
PFN_vkCmdDrawMultiIndexedEXT                                          :: alias fn(commandBuffer: VkCommandBuffer, drawCount: u32, pIndexInfo: ptr[VkMultiDrawIndexedInfoEXT], instanceCount: u32, firstInstance: u32, stride: u32, pVertexOffset: ptr[i32]) -> void
PFN_vkCmdEncodeVideoKHR                                               :: alias fn(commandBuffer: VkCommandBuffer, pEncodeInfo: ptr[VkVideoEncodeInfoKHR]) -> void
PFN_vkCmdEndConditionalRenderingEXT                                   :: alias fn(commandBuffer: VkCommandBuffer) -> void
PFN_vkCmdEndDebugUtilsLabelEXT                                        :: alias fn(commandBuffer: VkCommandBuffer) -> void
PFN_vkCmdEndQuery                                                     :: alias fn(commandBuffer: VkCommandBuffer, queryPool: VkQueryPool, query: u32) -> void
PFN_vkCmdEndQueryIndexedEXT                                           :: alias fn(commandBuffer: VkCommandBuffer, queryPool: VkQueryPool, query: u32, index: u32) -> void
PFN_vkCmdEndRendering                                                 :: alias fn(commandBuffer: VkCommandBuffer) -> void
PFN_vkCmdEndRenderingKHR                                              :: alias fn(commandBuffer: VkCommandBuffer) -> void
PFN_vkCmdEndRenderPass                                                :: alias fn(commandBuffer: VkCommandBuffer) -> void
PFN_vkCmdEndRenderPass2                                               :: alias fn(commandBuffer: VkCommandBuffer, pSubpassEndInfo: ptr[VkSubpassEndInfo]) -> void
PFN_vkCmdEndRenderPass2KHR                                            :: alias fn(commandBuffer: VkCommandBuffer, pSubpassEndInfo: ptr[VkSubpassEndInfo]) -> void
PFN_vkCmdEndTransformFeedbackEXT                                      :: alias fn(commandBuffer: VkCommandBuffer, firstCounterBuffer: u32, counterBufferCount: u32, pCounterBuffers: ptr[VkBuffer], pCounterBufferOffsets: ptr[VkDeviceSize]) -> void
PFN_vkCmdEndVideoCodingKHR                                            :: alias fn(commandBuffer: VkCommandBuffer, pEndCodingInfo: ptr[VkVideoEndCodingInfoKHR]) -> void
PFN_vkCmdExecuteCommands                                              :: alias fn(commandBuffer: VkCommandBuffer, commandBufferCount: u32, pCommandBuffers: ptr[VkCommandBuffer]) -> void
PFN_vkCmdExecuteGeneratedCommandsNV                                   :: alias fn(commandBuffer: VkCommandBuffer, isPreprocessed: b32, pGeneratedCommandsInfo: ptr[VkGeneratedCommandsInfoNV]) -> void
PFN_vkCmdFillBuffer                                                   :: alias fn(commandBuffer: VkCommandBuffer, dstBuffer: VkBuffer, dstOffset: VkDeviceSize, size: VkDeviceSize, data: u32) -> void
PFN_vkCmdInsertDebugUtilsLabelEXT                                     :: alias fn(commandBuffer: VkCommandBuffer, pLabelInfo: ptr[VkDebugUtilsLabelEXT]) -> void
PFN_vkCmdNextSubpass                                                  :: alias fn(commandBuffer: VkCommandBuffer, contents: VkSubpassContents) -> void
PFN_vkCmdNextSubpass2                                                 :: alias fn(commandBuffer: VkCommandBuffer, pSubpassBeginInfo: ptr[VkSubpassBeginInfo], pSubpassEndInfo: ptr[VkSubpassEndInfo]) -> void
PFN_vkCmdNextSubpass2KHR                                              :: alias fn(commandBuffer: VkCommandBuffer, pSubpassBeginInfo: ptr[VkSubpassBeginInfo], pSubpassEndInfo: ptr[VkSubpassEndInfo]) -> void
PFN_vkCmdOpticalFlowExecuteNV                                         :: alias fn(commandBuffer: VkCommandBuffer, session: VkOpticalFlowSessionNV, pExecuteInfo: ptr[VkOpticalFlowExecuteInfoNV]) -> void
PFN_vkCmdPipelineBarrier                                              :: alias fn(commandBuffer: VkCommandBuffer, srcStageMask: VkPipelineStageFlags, dstStageMask: VkPipelineStageFlags, dependencyFlags: VkDependencyFlags, memoryBarrierCount: u32, pMemoryBarriers: ptr[VkMemoryBarrier], bufferMemoryBarrierCount: u32, pBufferMemoryBarriers: ptr[VkBufferMemoryBarrier], imageMemoryBarrierCount: u32, pImageMemoryBarriers: ptr[VkImageMemoryBarrier]) -> void
PFN_vkCmdPipelineBarrier2                                             :: alias fn(commandBuffer: VkCommandBuffer, pDependencyInfo: ptr[VkDependencyInfo]) -> void
PFN_vkCmdPipelineBarrier2KHR                                          :: alias fn(commandBuffer: VkCommandBuffer, pDependencyInfo: ptr[VkDependencyInfo]) -> void
PFN_vkCmdPreprocessGeneratedCommandsNV                                :: alias fn(commandBuffer: VkCommandBuffer, pGeneratedCommandsInfo: ptr[VkGeneratedCommandsInfoNV]) -> void
PFN_vkCmdPushConstants                                                :: alias fn(commandBuffer: VkCommandBuffer, layout: VkPipelineLayout, stageFlags: VkShaderStageFlags, offset: u32, size: u32, pValues: rawptr) -> void
PFN_vkCmdPushConstants2KHR                                            :: alias fn(commandBuffer: VkCommandBuffer, pPushConstantsInfo: ptr[VkPushConstantsInfoKHR]) -> void
PFN_vkCmdPushDescriptorSet2KHR                                        :: alias fn(commandBuffer: VkCommandBuffer, pPushDescriptorSetInfo: ptr[VkPushDescriptorSetInfoKHR]) -> void
PFN_vkCmdPushDescriptorSetKHR                                         :: alias fn(commandBuffer: VkCommandBuffer, pipelineBindPoint: VkPipelineBindPoint, layout: VkPipelineLayout, set: u32, descriptorWriteCount: u32, pDescriptorWrites: ptr[VkWriteDescriptorSet]) -> void
PFN_vkCmdPushDescriptorSetWithTemplate2KHR                            :: alias fn(commandBuffer: VkCommandBuffer, pPushDescriptorSetWithTemplateInfo: ptr[VkPushDescriptorSetWithTemplateInfoKHR]) -> void
PFN_vkCmdPushDescriptorSetWithTemplateKHR                             :: alias fn(commandBuffer: VkCommandBuffer, descriptorUpdateTemplate: VkDescriptorUpdateTemplate, layout: VkPipelineLayout, set: u32, pData: rawptr) -> void
PFN_vkCmdResetEvent                                                   :: alias fn(commandBuffer: VkCommandBuffer, event: VkEvent, stageMask: VkPipelineStageFlags) -> void
PFN_vkCmdResetEvent2                                                  :: alias fn(commandBuffer: VkCommandBuffer, event: VkEvent, stageMask: VkPipelineStageFlags2) -> void
PFN_vkCmdResetEvent2KHR                                               :: alias fn(commandBuffer: VkCommandBuffer, event: VkEvent, stageMask: VkPipelineStageFlags2) -> void
PFN_vkCmdResetQueryPool                                               :: alias fn(commandBuffer: VkCommandBuffer, queryPool: VkQueryPool, firstQuery: u32, queryCount: u32) -> void
PFN_vkCmdResolveImage                                                 :: alias fn(commandBuffer: VkCommandBuffer, srcImage: VkImage, srcImageLayout: VkImageLayout, dstImage: VkImage, dstImageLayout: VkImageLayout, regionCount: u32, pRegions: ptr[VkImageResolve]) -> void
PFN_vkCmdResolveImage2                                                :: alias fn(commandBuffer: VkCommandBuffer, pResolveImageInfo: ptr[VkResolveImageInfo2]) -> void
PFN_vkCmdResolveImage2KHR                                             :: alias fn(commandBuffer: VkCommandBuffer, pResolveImageInfo: ptr[VkResolveImageInfo2]) -> void
PFN_vkCmdSetAlphaToCoverageEnableEXT                                  :: alias fn(commandBuffer: VkCommandBuffer, alphaToCoverageEnable: b32) -> void
PFN_vkCmdSetAlphaToOneEnableEXT                                       :: alias fn(commandBuffer: VkCommandBuffer, alphaToOneEnable: b32) -> void
PFN_vkCmdSetAttachmentFeedbackLoopEnableEXT                           :: alias fn(commandBuffer: VkCommandBuffer, aspectMask: VkImageAspectFlags) -> void
PFN_vkCmdSetBlendConstants                                            :: alias fn(commandBuffer: VkCommandBuffer, blendConstants[4]: float) -> void
PFN_vkCmdSetCheckpointNV                                              :: alias fn(commandBuffer: VkCommandBuffer, pCheckpointMarker: rawptr) -> void
PFN_vkCmdSetCoarseSampleOrderNV                                       :: alias fn(commandBuffer: VkCommandBuffer, sampleOrderType: VkCoarseSampleOrderTypeNV, customSampleOrderCount: u32, pCustomSampleOrders: ptr[VkCoarseSampleOrderCustomNV]) -> void
PFN_vkCmdSetColorBlendAdvancedEXT                                     :: alias fn(commandBuffer: VkCommandBuffer, firstAttachment: u32, attachmentCount: u32, pColorBlendAdvanced: ptr[VkColorBlendAdvancedEXT]) -> void
PFN_vkCmdSetColorBlendEnableEXT                                       :: alias fn(commandBuffer: VkCommandBuffer, firstAttachment: u32, attachmentCount: u32, pColorBlendEnables: ptr[b32]) -> void
PFN_vkCmdSetColorBlendEquationEXT                                     :: alias fn(commandBuffer: VkCommandBuffer, firstAttachment: u32, attachmentCount: u32, pColorBlendEquations: ptr[VkColorBlendEquationEXT]) -> void
PFN_vkCmdSetColorWriteEnableEXT                                       :: alias fn(commandBuffer: VkCommandBuffer, attachmentCount: u32, pColorWriteEnables: ptr[b32]) -> void
PFN_vkCmdSetColorWriteMaskEXT                                         :: alias fn(commandBuffer: VkCommandBuffer, firstAttachment: u32, attachmentCount: u32, pColorWriteMasks: ptr[VkColorComponentFlags]) -> void
PFN_vkCmdSetConservativeRasterizationModeEXT                          :: alias fn(commandBuffer: VkCommandBuffer, conservativeRasterizationMode: VkConservativeRasterizationModeEXT) -> void
PFN_vkCmdSetCoverageModulationModeNV                                  :: alias fn(commandBuffer: VkCommandBuffer, coverageModulationMode: VkCoverageModulationModeNV) -> void
PFN_vkCmdSetCoverageModulationTableEnableNV                           :: alias fn(commandBuffer: VkCommandBuffer, coverageModulationTableEnable: b32) -> void
PFN_vkCmdSetCoverageModulationTableNV                                 :: alias fn(commandBuffer: VkCommandBuffer, coverageModulationTableCount: u32, pCoverageModulationTable: ptr[float]) -> void
PFN_vkCmdSetCoverageReductionModeNV                                   :: alias fn(commandBuffer: VkCommandBuffer, coverageReductionMode: VkCoverageReductionModeNV) -> void
PFN_vkCmdSetCoverageToColorEnableNV                                   :: alias fn(commandBuffer: VkCommandBuffer, coverageToColorEnable: b32) -> void
PFN_vkCmdSetCoverageToColorLocationNV                                 :: alias fn(commandBuffer: VkCommandBuffer, coverageToColorLocation: u32) -> void
PFN_vkCmdSetCullMode                                                  :: alias fn(commandBuffer: VkCommandBuffer, cullMode: VkCullModeFlags) -> void
PFN_vkCmdSetCullModeEXT                                               :: alias fn(commandBuffer: VkCommandBuffer, cullMode: VkCullModeFlags) -> void
PFN_vkCmdSetDepthBias                                                 :: alias fn(commandBuffer: VkCommandBuffer, depthBiasConstantFactor: float, depthBiasClamp: float, depthBiasSlopeFactor: float) -> void
PFN_vkCmdSetDepthBias2EXT                                             :: alias fn(commandBuffer: VkCommandBuffer, pDepthBiasInfo: ptr[VkDepthBiasInfoEXT]) -> void
PFN_vkCmdSetDepthBiasEnable                                           :: alias fn(commandBuffer: VkCommandBuffer, depthBiasEnable: b32) -> void
PFN_vkCmdSetDepthBiasEnableEXT                                        :: alias fn(commandBuffer: VkCommandBuffer, depthBiasEnable: b32) -> void
PFN_vkCmdSetDepthBounds                                               :: alias fn(commandBuffer: VkCommandBuffer, minDepthBounds: float, maxDepthBounds: float) -> void
PFN_vkCmdSetDepthBoundsTestEnable                                     :: alias fn(commandBuffer: VkCommandBuffer, depthBoundsTestEnable: b32) -> void
PFN_vkCmdSetDepthBoundsTestEnableEXT                                  :: alias fn(commandBuffer: VkCommandBuffer, depthBoundsTestEnable: b32) -> void
PFN_vkCmdSetDepthClampEnableEXT                                       :: alias fn(commandBuffer: VkCommandBuffer, depthClampEnable: b32) -> void
PFN_vkCmdSetDepthClipEnableEXT                                        :: alias fn(commandBuffer: VkCommandBuffer, depthClipEnable: b32) -> void
PFN_vkCmdSetDepthClipNegativeOneToOneEXT                              :: alias fn(commandBuffer: VkCommandBuffer, negativeOneToOne: b32) -> void
PFN_vkCmdSetDepthCompareOp                                            :: alias fn(commandBuffer: VkCommandBuffer, depthCompareOp: VkCompareOp) -> void
PFN_vkCmdSetDepthCompareOpEXT                                         :: alias fn(commandBuffer: VkCommandBuffer, depthCompareOp: VkCompareOp) -> void
PFN_vkCmdSetDepthTestEnable                                           :: alias fn(commandBuffer: VkCommandBuffer, depthTestEnable: b32) -> void
PFN_vkCmdSetDepthTestEnableEXT                                        :: alias fn(commandBuffer: VkCommandBuffer, depthTestEnable: b32) -> void
PFN_vkCmdSetDepthWriteEnable                                          :: alias fn(commandBuffer: VkCommandBuffer, depthWriteEnable: b32) -> void
PFN_vkCmdSetDepthWriteEnableEXT                                       :: alias fn(commandBuffer: VkCommandBuffer, depthWriteEnable: b32) -> void
PFN_vkCmdSetDescriptorBufferOffsets2EXT                               :: alias fn(commandBuffer: VkCommandBuffer, pSetDescriptorBufferOffsetsInfo: ptr[VkSetDescriptorBufferOffsetsInfoEXT]) -> void
PFN_vkCmdSetDescriptorBufferOffsetsEXT                                :: alias fn(commandBuffer: VkCommandBuffer, pipelineBindPoint: VkPipelineBindPoint, layout: VkPipelineLayout, firstSet: u32, setCount: u32, pBufferIndices: ptr[u32], pOffsets: ptr[VkDeviceSize]) -> void
PFN_vkCmdSetDeviceMask                                                :: alias fn(commandBuffer: VkCommandBuffer, deviceMask: u32) -> void
PFN_vkCmdSetDeviceMaskKHR                                             :: alias fn(commandBuffer: VkCommandBuffer, deviceMask: u32) -> void
PFN_vkCmdSetDiscardRectangleEnableEXT                                 :: alias fn(commandBuffer: VkCommandBuffer, discardRectangleEnable: b32) -> void
PFN_vkCmdSetDiscardRectangleEXT                                       :: alias fn(commandBuffer: VkCommandBuffer, firstDiscardRectangle: u32, discardRectangleCount: u32, pDiscardRectangles: ptr[VkRect2D]) -> void
PFN_vkCmdSetDiscardRectangleModeEXT                                   :: alias fn(commandBuffer: VkCommandBuffer, discardRectangleMode: VkDiscardRectangleModeEXT) -> void
PFN_vkCmdSetEvent                                                     :: alias fn(commandBuffer: VkCommandBuffer, event: VkEvent, stageMask: VkPipelineStageFlags) -> void
PFN_vkCmdSetEvent2                                                    :: alias fn(commandBuffer: VkCommandBuffer, event: VkEvent, pDependencyInfo: ptr[VkDependencyInfo]) -> void
PFN_vkCmdSetEvent2KHR                                                 :: alias fn(commandBuffer: VkCommandBuffer, event: VkEvent, pDependencyInfo: ptr[VkDependencyInfo]) -> void
PFN_vkCmdSetExclusiveScissorEnableNV                                  :: alias fn(commandBuffer: VkCommandBuffer, firstExclusiveScissor: u32, exclusiveScissorCount: u32, pExclusiveScissorEnables: ptr[b32]) -> void
PFN_vkCmdSetExclusiveScissorNV                                        :: alias fn(commandBuffer: VkCommandBuffer, firstExclusiveScissor: u32, exclusiveScissorCount: u32, pExclusiveScissors: ptr[VkRect2D]) -> void
PFN_vkCmdSetExtraPrimitiveOverestimationSizeEXT                       :: alias fn(commandBuffer: VkCommandBuffer, extraPrimitiveOverestimationSize: float) -> void
PFN_vkCmdSetFragmentShadingRateEnumNV                                 :: alias fn(commandBuffer: VkCommandBuffer, shadingRate: VkFragmentShadingRateNV, combinerOps[2]: VkFragmentShadingRateCombinerOpKHR) -> void
PFN_vkCmdSetFragmentShadingRateKHR                                    :: alias fn(commandBuffer: VkCommandBuffer, pFragmentSize: ptr[VkExtent2D], combinerOps[2]: VkFragmentShadingRateCombinerOpKHR) -> void
PFN_vkCmdSetFrontFace                                                 :: alias fn(commandBuffer: VkCommandBuffer, frontFace: VkFrontFace) -> void
PFN_vkCmdSetFrontFaceEXT                                              :: alias fn(commandBuffer: VkCommandBuffer, frontFace: VkFrontFace) -> void
PFN_vkCmdSetLineRasterizationModeEXT                                  :: alias fn(commandBuffer: VkCommandBuffer, lineRasterizationMode: VkLineRasterizationModeEXT) -> void
PFN_vkCmdSetLineStippleEnableEXT                                      :: alias fn(commandBuffer: VkCommandBuffer, stippledLineEnable: b32) -> void
PFN_vkCmdSetLineStippleEXT                                            :: alias fn(commandBuffer: VkCommandBuffer, lineStippleFactor: u32, lineStipplePattern: u16) -> void
PFN_vkCmdSetLineStippleKHR                                            :: alias fn(commandBuffer: VkCommandBuffer, lineStippleFactor: u32, lineStipplePattern: u16) -> void
PFN_vkCmdSetLineWidth                                                 :: alias fn(commandBuffer: VkCommandBuffer, lineWidth: float) -> void
PFN_vkCmdSetLogicOpEnableEXT                                          :: alias fn(commandBuffer: VkCommandBuffer, logicOpEnable: b32) -> void
PFN_vkCmdSetLogicOpEXT                                                :: alias fn(commandBuffer: VkCommandBuffer, logicOp: VkLogicOp) -> void
PFN_vkCmdSetPatchControlPointsEXT                                     :: alias fn(commandBuffer: VkCommandBuffer, patchControlPoints: u32) -> void
PFN_vkCmdSetPerformanceMarkerINTEL                                    :: alias fn(commandBuffer: VkCommandBuffer, pMarkerInfo: ptr[VkPerformanceMarkerInfoINTEL]) -> VkResult
PFN_vkCmdSetPerformanceOverrideINTEL                                  :: alias fn(commandBuffer: VkCommandBuffer, pOverrideInfo: ptr[VkPerformanceOverrideInfoINTEL]) -> VkResult
PFN_vkCmdSetPerformanceStreamMarkerINTEL                              :: alias fn(commandBuffer: VkCommandBuffer, pMarkerInfo: ptr[VkPerformanceStreamMarkerInfoINTEL]) -> VkResult
PFN_vkCmdSetPolygonModeEXT                                            :: alias fn(commandBuffer: VkCommandBuffer, polygonMode: VkPolygonMode) -> void
PFN_vkCmdSetPrimitiveRestartEnable                                    :: alias fn(commandBuffer: VkCommandBuffer, primitiveRestartEnable: b32) -> void
PFN_vkCmdSetPrimitiveRestartEnableEXT                                 :: alias fn(commandBuffer: VkCommandBuffer, primitiveRestartEnable: b32) -> void
PFN_vkCmdSetPrimitiveTopology                                         :: alias fn(commandBuffer: VkCommandBuffer, primitiveTopology: VkPrimitiveTopology) -> void
PFN_vkCmdSetPrimitiveTopologyEXT                                      :: alias fn(commandBuffer: VkCommandBuffer, primitiveTopology: VkPrimitiveTopology) -> void
PFN_vkCmdSetProvokingVertexModeEXT                                    :: alias fn(commandBuffer: VkCommandBuffer, provokingVertexMode: VkProvokingVertexModeEXT) -> void
PFN_vkCmdSetRasterizationSamplesEXT                                   :: alias fn(commandBuffer: VkCommandBuffer, rasterizationSamples: VkSampleCountFlagBits) -> void
PFN_vkCmdSetRasterizationStreamEXT                                    :: alias fn(commandBuffer: VkCommandBuffer, rasterizationStream: u32) -> void
PFN_vkCmdSetRasterizerDiscardEnable                                   :: alias fn(commandBuffer: VkCommandBuffer, rasterizerDiscardEnable: b32) -> void
PFN_vkCmdSetRasterizerDiscardEnableEXT                                :: alias fn(commandBuffer: VkCommandBuffer, rasterizerDiscardEnable: b32) -> void
PFN_vkCmdSetRayTracingPipelineStackSizeKHR                            :: alias fn(commandBuffer: VkCommandBuffer, pipelineStackSize: u32) -> void
PFN_vkCmdSetRenderingAttachmentLocationsKHR                           :: alias fn(commandBuffer: VkCommandBuffer, pLocationInfo: ptr[VkRenderingAttachmentLocationInfoKHR]) -> void
PFN_vkCmdSetRenderingInputAttachmentIndicesKHR                        :: alias fn(commandBuffer: VkCommandBuffer, pLocationInfo: ptr[VkRenderingInputAttachmentIndexInfoKHR]) -> void
PFN_vkCmdSetRepresentativeFragmentTestEnableNV                        :: alias fn(commandBuffer: VkCommandBuffer, representativeFragmentTestEnable: b32) -> void
PFN_vkCmdSetSampleLocationsEnableEXT                                  :: alias fn(commandBuffer: VkCommandBuffer, sampleLocationsEnable: b32) -> void
PFN_vkCmdSetSampleLocationsEXT                                        :: alias fn(commandBuffer: VkCommandBuffer, pSampleLocationsInfo: ptr[VkSampleLocationsInfoEXT]) -> void
PFN_vkCmdSetSampleMaskEXT                                             :: alias fn(commandBuffer: VkCommandBuffer, samples: VkSampleCountFlagBits, pSampleMask: ptr[VkSampleMask]) -> void
PFN_vkCmdSetScissor                                                   :: alias fn(commandBuffer: VkCommandBuffer, firstScissor: u32, scissorCount: u32, pScissors: ptr[VkRect2D]) -> void
PFN_vkCmdSetScissorWithCount                                          :: alias fn(commandBuffer: VkCommandBuffer, scissorCount: u32, pScissors: ptr[VkRect2D]) -> void
PFN_vkCmdSetScissorWithCountEXT                                       :: alias fn(commandBuffer: VkCommandBuffer, scissorCount: u32, pScissors: ptr[VkRect2D]) -> void
PFN_vkCmdSetShadingRateImageEnableNV                                  :: alias fn(commandBuffer: VkCommandBuffer, shadingRateImageEnable: b32) -> void
PFN_vkCmdSetStencilCompareMask                                        :: alias fn(commandBuffer: VkCommandBuffer, faceMask: VkStencilFaceFlags, compareMask: u32) -> void
PFN_vkCmdSetStencilOp                                                 :: alias fn(commandBuffer: VkCommandBuffer, faceMask: VkStencilFaceFlags, failOp: VkStencilOp, passOp: VkStencilOp, depthFailOp: VkStencilOp, compareOp: VkCompareOp) -> void
PFN_vkCmdSetStencilOpEXT                                              :: alias fn(commandBuffer: VkCommandBuffer, faceMask: VkStencilFaceFlags, failOp: VkStencilOp, passOp: VkStencilOp, depthFailOp: VkStencilOp, compareOp: VkCompareOp) -> void
PFN_vkCmdSetStencilReference                                          :: alias fn(commandBuffer: VkCommandBuffer, faceMask: VkStencilFaceFlags, reference: u32) -> void
PFN_vkCmdSetStencilTestEnable                                         :: alias fn(commandBuffer: VkCommandBuffer, stencilTestEnable: b32) -> void
PFN_vkCmdSetStencilTestEnableEXT                                      :: alias fn(commandBuffer: VkCommandBuffer, stencilTestEnable: b32) -> void
PFN_vkCmdSetStencilWriteMask                                          :: alias fn(commandBuffer: VkCommandBuffer, faceMask: VkStencilFaceFlags, writeMask: u32) -> void
PFN_vkCmdSetTessellationDomainOriginEXT                               :: alias fn(commandBuffer: VkCommandBuffer, domainOrigin: VkTessellationDomainOrigin) -> void
PFN_vkCmdSetVertexInputEXT                                            :: alias fn(commandBuffer: VkCommandBuffer, vertexBindingDescriptionCount: u32, pVertexBindingDescriptions: ptr[VkVertexInputBindingDescription2EXT], vertexAttributeDescriptionCount: u32, pVertexAttributeDescriptions: ptr[VkVertexInputAttributeDescription2EXT]) -> void
PFN_vkCmdSetViewport                                                  :: alias fn(commandBuffer: VkCommandBuffer, firstViewport: u32, viewportCount: u32, pViewports: ptr[VkViewport]) -> void
PFN_vkCmdSetViewportShadingRatePaletteNV                              :: alias fn(commandBuffer: VkCommandBuffer, firstViewport: u32, viewportCount: u32, pShadingRatePalettes: ptr[VkShadingRatePaletteNV]) -> void
PFN_vkCmdSetViewportSwizzleNV                                         :: alias fn(commandBuffer: VkCommandBuffer, firstViewport: u32, viewportCount: u32, pViewportSwizzles: ptr[VkViewportSwizzleNV]) -> void
PFN_vkCmdSetViewportWithCount                                         :: alias fn(commandBuffer: VkCommandBuffer, viewportCount: u32, pViewports: ptr[VkViewport]) -> void
PFN_vkCmdSetViewportWithCountEXT                                      :: alias fn(commandBuffer: VkCommandBuffer, viewportCount: u32, pViewports: ptr[VkViewport]) -> void
PFN_vkCmdSetViewportWScalingEnableNV                                  :: alias fn(commandBuffer: VkCommandBuffer, viewportWScalingEnable: b32) -> void
PFN_vkCmdSetViewportWScalingNV                                        :: alias fn(commandBuffer: VkCommandBuffer, firstViewport: u32, viewportCount: u32, pViewportWScalings: ptr[VkViewportWScalingNV]) -> void
PFN_vkCmdSubpassShadingHUAWEI                                         :: alias fn(commandBuffer: VkCommandBuffer) -> void
PFN_vkCmdTraceRaysIndirect2KHR                                        :: alias fn(commandBuffer: VkCommandBuffer, indirectDeviceAddress: VkDeviceAddress) -> void
PFN_vkCmdTraceRaysIndirectKHR                                         :: alias fn(commandBuffer: VkCommandBuffer, pRaygenShaderBindingTable: ptr[VkStridedDeviceAddressRegionKHR], pMissShaderBindingTable: ptr[VkStridedDeviceAddressRegionKHR], pHitShaderBindingTable: ptr[VkStridedDeviceAddressRegionKHR], pCallableShaderBindingTable: ptr[VkStridedDeviceAddressRegionKHR], indirectDeviceAddress: VkDeviceAddress) -> void
PFN_vkCmdTraceRaysKHR                                                 :: alias fn(commandBuffer: VkCommandBuffer, pRaygenShaderBindingTable: ptr[VkStridedDeviceAddressRegionKHR], pMissShaderBindingTable: ptr[VkStridedDeviceAddressRegionKHR], pHitShaderBindingTable: ptr[VkStridedDeviceAddressRegionKHR], pCallableShaderBindingTable: ptr[VkStridedDeviceAddressRegionKHR], width: u32, height: u32, depth: u32) -> void
PFN_vkCmdTraceRaysNV                                                  :: alias fn(commandBuffer: VkCommandBuffer, raygenShaderBindingTableBuffer: VkBuffer, raygenShaderBindingOffset: VkDeviceSize, missShaderBindingTableBuffer: VkBuffer, missShaderBindingOffset: VkDeviceSize, missShaderBindingStride: VkDeviceSize, hitShaderBindingTableBuffer: VkBuffer, hitShaderBindingOffset: VkDeviceSize, hitShaderBindingStride: VkDeviceSize, callableShaderBindingTableBuffer: VkBuffer, callableShaderBindingOffset: VkDeviceSize, callableShaderBindingStride: VkDeviceSize, width: u32, height: u32, depth: u32) -> void
PFN_vkCmdUpdateBuffer                                                 :: alias fn(commandBuffer: VkCommandBuffer, dstBuffer: VkBuffer, dstOffset: VkDeviceSize, dataSize: VkDeviceSize, pData: rawptr) -> void
PFN_vkCmdUpdatePipelineIndirectBufferNV                               :: alias fn(commandBuffer: VkCommandBuffer, pipelineBindPoint: VkPipelineBindPoint, pipeline: VkPipeline) -> void
PFN_vkCmdWaitEvents                                                   :: alias fn(commandBuffer: VkCommandBuffer, eventCount: u32, pEvents: ptr[VkEvent], srcStageMask: VkPipelineStageFlags, dstStageMask: VkPipelineStageFlags, memoryBarrierCount: u32, pMemoryBarriers: ptr[VkMemoryBarrier], bufferMemoryBarrierCount: u32, pBufferMemoryBarriers: ptr[VkBufferMemoryBarrier], imageMemoryBarrierCount: u32, pImageMemoryBarriers: ptr[VkImageMemoryBarrier]) -> void
PFN_vkCmdWaitEvents2                                                  :: alias fn(commandBuffer: VkCommandBuffer, eventCount: u32, pEvents: ptr[VkEvent], pDependencyInfos: ptr[VkDependencyInfo]) -> void
PFN_vkCmdWaitEvents2KHR                                               :: alias fn(commandBuffer: VkCommandBuffer, eventCount: u32, pEvents: ptr[VkEvent], pDependencyInfos: ptr[VkDependencyInfo]) -> void
PFN_vkCmdWriteAccelerationStructuresPropertiesKHR                     :: alias fn(commandBuffer: VkCommandBuffer, accelerationStructureCount: u32, pAccelerationStructures: ptr[VkAccelerationStructureKHR], queryType: VkQueryType, queryPool: VkQueryPool, firstQuery: u32) -> void
PFN_vkCmdWriteAccelerationStructuresPropertiesNV                      :: alias fn(commandBuffer: VkCommandBuffer, accelerationStructureCount: u32, pAccelerationStructures: ptr[VkAccelerationStructureNV], queryType: VkQueryType, queryPool: VkQueryPool, firstQuery: u32) -> void
PFN_vkCmdWriteBufferMarker2AMD                                        :: alias fn(commandBuffer: VkCommandBuffer, stage: VkPipelineStageFlags2, dstBuffer: VkBuffer, dstOffset: VkDeviceSize, marker: u32) -> void
PFN_vkCmdWriteBufferMarkerAMD                                         :: alias fn(commandBuffer: VkCommandBuffer, pipelineStage: VkPipelineStageFlagBits, dstBuffer: VkBuffer, dstOffset: VkDeviceSize, marker: u32) -> void
PFN_vkCmdWriteMicromapsPropertiesEXT                                  :: alias fn(commandBuffer: VkCommandBuffer, micromapCount: u32, pMicromaps: ptr[VkMicromapEXT], queryType: VkQueryType, queryPool: VkQueryPool, firstQuery: u32) -> void
PFN_vkCmdWriteTimestamp                                               :: alias fn(commandBuffer: VkCommandBuffer, pipelineStage: VkPipelineStageFlagBits, queryPool: VkQueryPool, query: u32) -> void
PFN_vkCmdWriteTimestamp2                                              :: alias fn(commandBuffer: VkCommandBuffer, stage: VkPipelineStageFlags2, queryPool: VkQueryPool, query: u32) -> void
PFN_vkCmdWriteTimestamp2KHR                                           :: alias fn(commandBuffer: VkCommandBuffer, stage: VkPipelineStageFlags2, queryPool: VkQueryPool, query: u32) -> void
PFN_vkCompileDeferredNV                                               :: alias fn(device: VkDevice, pipeline: VkPipeline, shader: u32) -> VkResult
PFN_vkCopyAccelerationStructureKHR                                    :: alias fn(device: VkDevice, deferredOperation: VkDeferredOperationKHR, pInfo: ptr[VkCopyAccelerationStructureInfoKHR]) -> VkResult
PFN_vkCopyAccelerationStructureToMemoryKHR                            :: alias fn(device: VkDevice, deferredOperation: VkDeferredOperationKHR, pInfo: ptr[VkCopyAccelerationStructureToMemoryInfoKHR]) -> VkResult
PFN_vkCopyImageToImageEXT                                             :: alias fn(device: VkDevice, pCopyImageToImageInfo: ptr[VkCopyImageToImageInfoEXT]) -> VkResult
PFN_vkCopyImageToMemoryEXT                                            :: alias fn(device: VkDevice, pCopyImageToMemoryInfo: ptr[VkCopyImageToMemoryInfoEXT]) -> VkResult
PFN_vkCopyMemoryToAccelerationStructureKHR                            :: alias fn(device: VkDevice, deferredOperation: VkDeferredOperationKHR, pInfo: ptr[VkCopyMemoryToAccelerationStructureInfoKHR]) -> VkResult
PFN_vkCopyMemoryToImageEXT                                            :: alias fn(device: VkDevice, pCopyMemoryToImageInfo: ptr[VkCopyMemoryToImageInfoEXT]) -> VkResult
PFN_vkCopyMemoryToMicromapEXT                                         :: alias fn(device: VkDevice, deferredOperation: VkDeferredOperationKHR, pInfo: ptr[VkCopyMemoryToMicromapInfoEXT]) -> VkResult
PFN_vkCopyMicromapEXT                                                 :: alias fn(device: VkDevice, deferredOperation: VkDeferredOperationKHR, pInfo: ptr[VkCopyMicromapInfoEXT]) -> VkResult
PFN_vkCopyMicromapToMemoryEXT                                         :: alias fn(device: VkDevice, deferredOperation: VkDeferredOperationKHR, pInfo: ptr[VkCopyMicromapToMemoryInfoEXT]) -> VkResult
PFN_vkCreateAccelerationStructureKHR                                  :: alias fn(device: VkDevice, pCreateInfo: ptr[VkAccelerationStructureCreateInfoKHR], pAllocator: ptr[VkAllocationCallbacks], pAccelerationStructure: ptr[VkAccelerationStructureKHR]) -> VkResult
PFN_vkCreateAccelerationStructureNV                                   :: alias fn(device: VkDevice, pCreateInfo: ptr[VkAccelerationStructureCreateInfoNV], pAllocator: ptr[VkAllocationCallbacks], pAccelerationStructure: ptr[VkAccelerationStructureNV]) -> VkResult
PFN_vkCreateBuffer                                                    :: alias fn(device: VkDevice, pCreateInfo: ptr[VkBufferCreateInfo], pAllocator: ptr[VkAllocationCallbacks], pBuffer: ptr[VkBuffer]) -> VkResult
PFN_vkCreateBufferView                                                :: alias fn(device: VkDevice, pCreateInfo: ptr[VkBufferViewCreateInfo], pAllocator: ptr[VkAllocationCallbacks], pView: ptr[VkBufferView]) -> VkResult
PFN_vkCreateCommandPool                                               :: alias fn(device: VkDevice, pCreateInfo: ptr[VkCommandPoolCreateInfo], pAllocator: ptr[VkAllocationCallbacks], pCommandPool: ptr[VkCommandPool]) -> VkResult
PFN_vkCreateComputePipelines                                          :: alias fn(device: VkDevice, pipelineCache: VkPipelineCache, createInfoCount: u32, pCreateInfos: ptr[VkComputePipelineCreateInfo], pAllocator: ptr[VkAllocationCallbacks], pPipelines: ptr[VkPipeline]) -> VkResult
PFN_vkCreateCudaFunctionNV                                            :: alias fn(device: VkDevice, pCreateInfo: ptr[VkCudaFunctionCreateInfoNV], pAllocator: ptr[VkAllocationCallbacks], pFunction: ptr[VkCudaFunctionNV]) -> VkResult
PFN_vkCreateCudaModuleNV                                              :: alias fn(device: VkDevice, pCreateInfo: ptr[VkCudaModuleCreateInfoNV], pAllocator: ptr[VkAllocationCallbacks], pModule: ptr[VkCudaModuleNV]) -> VkResult
PFN_vkCreateCuFunctionNVX                                             :: alias fn(device: VkDevice, pCreateInfo: ptr[VkCuFunctionCreateInfoNVX], pAllocator: ptr[VkAllocationCallbacks], pFunction: ptr[VkCuFunctionNVX]) -> VkResult
PFN_vkCreateCuModuleNVX                                               :: alias fn(device: VkDevice, pCreateInfo: ptr[VkCuModuleCreateInfoNVX], pAllocator: ptr[VkAllocationCallbacks], pModule: ptr[VkCuModuleNVX]) -> VkResult
PFN_vkCreateDebugReportCallbackEXT                                    :: alias fn(instance: VkInstance, pCreateInfo: ptr[VkDebugReportCallbackCreateInfoEXT], pAllocator: ptr[VkAllocationCallbacks], pCallback: ptr[VkDebugReportCallbackEXT]) -> VkResult
PFN_vkCreateDebugUtilsMessengerEXT                                    :: alias fn(instance: VkInstance, pCreateInfo: ptr[VkDebugUtilsMessengerCreateInfoEXT], pAllocator: ptr[VkAllocationCallbacks], pMessenger: ptr[VkDebugUtilsMessengerEXT]) -> VkResult
PFN_vkCreateDeferredOperationKHR                                      :: alias fn(device: VkDevice, pAllocator: ptr[VkAllocationCallbacks], pDeferredOperation: ptr[VkDeferredOperationKHR]) -> VkResult
PFN_vkCreateDescriptorPool                                            :: alias fn(device: VkDevice, pCreateInfo: ptr[VkDescriptorPoolCreateInfo], pAllocator: ptr[VkAllocationCallbacks], pDescriptorPool: ptr[VkDescriptorPool]) -> VkResult
PFN_vkCreateDescriptorSetLayout                                       :: alias fn(device: VkDevice, pCreateInfo: ptr[VkDescriptorSetLayoutCreateInfo], pAllocator: ptr[VkAllocationCallbacks], pSetLayout: ptr[VkDescriptorSetLayout]) -> VkResult
PFN_vkCreateDescriptorUpdateTemplate                                  :: alias fn(device: VkDevice, pCreateInfo: ptr[VkDescriptorUpdateTemplateCreateInfo], pAllocator: ptr[VkAllocationCallbacks], pDescriptorUpdateTemplate: ptr[VkDescriptorUpdateTemplate]) -> VkResult
PFN_vkCreateDescriptorUpdateTemplateKHR                               :: alias fn(device: VkDevice, pCreateInfo: ptr[VkDescriptorUpdateTemplateCreateInfo], pAllocator: ptr[VkAllocationCallbacks], pDescriptorUpdateTemplate: ptr[VkDescriptorUpdateTemplate]) -> VkResult
PFN_vkCreateDevice                                                    :: alias fn(physicalDevice: VkPhysicalDevice, pCreateInfo: ptr[VkDeviceCreateInfo], pAllocator: ptr[VkAllocationCallbacks], pDevice: ptr[VkDevice]) -> VkResult
PFN_vkCreateDisplayModeKHR                                            :: alias fn(physicalDevice: VkPhysicalDevice, display: VkDisplayKHR, pCreateInfo: ptr[VkDisplayModeCreateInfoKHR], pAllocator: ptr[VkAllocationCallbacks], pMode: ptr[VkDisplayModeKHR]) -> VkResult
PFN_vkCreateDisplayPlaneSurfaceKHR                                    :: alias fn(instance: VkInstance, pCreateInfo: ptr[VkDisplaySurfaceCreateInfoKHR], pAllocator: ptr[VkAllocationCallbacks], pSurface: ptr[VkSurfaceKHR]) -> VkResult
PFN_vkCreateEvent                                                     :: alias fn(device: VkDevice, pCreateInfo: ptr[VkEventCreateInfo], pAllocator: ptr[VkAllocationCallbacks], pEvent: ptr[VkEvent]) -> VkResult
PFN_vkCreateFence                                                     :: alias fn(device: VkDevice, pCreateInfo: ptr[VkFenceCreateInfo], pAllocator: ptr[VkAllocationCallbacks], pFence: ptr[VkFence]) -> VkResult
PFN_vkCreateFramebuffer                                               :: alias fn(device: VkDevice, pCreateInfo: ptr[VkFramebufferCreateInfo], pAllocator: ptr[VkAllocationCallbacks], pFramebuffer: ptr[VkFramebuffer]) -> VkResult
PFN_vkCreateGraphicsPipelines                                         :: alias fn(device: VkDevice, pipelineCache: VkPipelineCache, createInfoCount: u32, pCreateInfos: ptr[VkGraphicsPipelineCreateInfo], pAllocator: ptr[VkAllocationCallbacks], pPipelines: ptr[VkPipeline]) -> VkResult
PFN_vkCreateHeadlessSurfaceEXT                                        :: alias fn(instance: VkInstance, pCreateInfo: ptr[VkHeadlessSurfaceCreateInfoEXT], pAllocator: ptr[VkAllocationCallbacks], pSurface: ptr[VkSurfaceKHR]) -> VkResult
PFN_vkCreateImage                                                     :: alias fn(device: VkDevice, pCreateInfo: ptr[VkImageCreateInfo], pAllocator: ptr[VkAllocationCallbacks], pImage: ptr[VkImage]) -> VkResult
PFN_vkCreateImageView                                                 :: alias fn(device: VkDevice, pCreateInfo: ptr[VkImageViewCreateInfo], pAllocator: ptr[VkAllocationCallbacks], pView: ptr[VkImageView]) -> VkResult
PFN_vkCreateIndirectCommandsLayoutNV                                  :: alias fn(device: VkDevice, pCreateInfo: ptr[VkIndirectCommandsLayoutCreateInfoNV], pAllocator: ptr[VkAllocationCallbacks], pIndirectCommandsLayout: ptr[VkIndirectCommandsLayoutNV]) -> VkResult
PFN_vkCreateInstance                                                  :: alias fn(pCreateInfo: ptr[VkInstanceCreateInfo], pAllocator: ptr[VkAllocationCallbacks], pInstance: ptr[VkInstance]) -> VkResult
PFN_vkCreateMicromapEXT                                               :: alias fn(device: VkDevice, pCreateInfo: ptr[VkMicromapCreateInfoEXT], pAllocator: ptr[VkAllocationCallbacks], pMicromap: ptr[VkMicromapEXT]) -> VkResult
PFN_vkCreateOpticalFlowSessionNV                                      :: alias fn(device: VkDevice, pCreateInfo: ptr[VkOpticalFlowSessionCreateInfoNV], pAllocator: ptr[VkAllocationCallbacks], pSession: ptr[VkOpticalFlowSessionNV]) -> VkResult
PFN_vkCreatePipelineCache                                             :: alias fn(device: VkDevice, pCreateInfo: ptr[VkPipelineCacheCreateInfo], pAllocator: ptr[VkAllocationCallbacks], pPipelineCache: ptr[VkPipelineCache]) -> VkResult
PFN_vkCreatePipelineLayout                                            :: alias fn(device: VkDevice, pCreateInfo: ptr[VkPipelineLayoutCreateInfo], pAllocator: ptr[VkAllocationCallbacks], pPipelineLayout: ptr[VkPipelineLayout]) -> VkResult
PFN_vkCreatePrivateDataSlot                                           :: alias fn(device: VkDevice, pCreateInfo: ptr[VkPrivateDataSlotCreateInfo], pAllocator: ptr[VkAllocationCallbacks], pPrivateDataSlot: ptr[VkPrivateDataSlot]) -> VkResult
PFN_vkCreatePrivateDataSlotEXT                                        :: alias fn(device: VkDevice, pCreateInfo: ptr[VkPrivateDataSlotCreateInfo], pAllocator: ptr[VkAllocationCallbacks], pPrivateDataSlot: ptr[VkPrivateDataSlot]) -> VkResult
PFN_vkCreateQueryPool                                                 :: alias fn(device: VkDevice, pCreateInfo: ptr[VkQueryPoolCreateInfo], pAllocator: ptr[VkAllocationCallbacks], pQueryPool: ptr[VkQueryPool]) -> VkResult
PFN_vkCreateRayTracingPipelinesKHR                                    :: alias fn(device: VkDevice, deferredOperation: VkDeferredOperationKHR, pipelineCache: VkPipelineCache, createInfoCount: u32, pCreateInfos: ptr[VkRayTracingPipelineCreateInfoKHR], pAllocator: ptr[VkAllocationCallbacks], pPipelines: ptr[VkPipeline]) -> VkResult
PFN_vkCreateRayTracingPipelinesNV                                     :: alias fn(device: VkDevice, pipelineCache: VkPipelineCache, createInfoCount: u32, pCreateInfos: ptr[VkRayTracingPipelineCreateInfoNV], pAllocator: ptr[VkAllocationCallbacks], pPipelines: ptr[VkPipeline]) -> VkResult
PFN_vkCreateRenderPass                                                :: alias fn(device: VkDevice, pCreateInfo: ptr[VkRenderPassCreateInfo], pAllocator: ptr[VkAllocationCallbacks], pRenderPass: ptr[VkRenderPass]) -> VkResult
PFN_vkCreateRenderPass2                                               :: alias fn(device: VkDevice, pCreateInfo: ptr[VkRenderPassCreateInfo2], pAllocator: ptr[VkAllocationCallbacks], pRenderPass: ptr[VkRenderPass]) -> VkResult
PFN_vkCreateRenderPass2KHR                                            :: alias fn(device: VkDevice, pCreateInfo: ptr[VkRenderPassCreateInfo2], pAllocator: ptr[VkAllocationCallbacks], pRenderPass: ptr[VkRenderPass]) -> VkResult
PFN_vkCreateSampler                                                   :: alias fn(device: VkDevice, pCreateInfo: ptr[VkSamplerCreateInfo], pAllocator: ptr[VkAllocationCallbacks], pSampler: ptr[VkSampler]) -> VkResult
PFN_vkCreateSamplerYcbcrConversion                                    :: alias fn(device: VkDevice, pCreateInfo: ptr[VkSamplerYcbcrConversionCreateInfo], pAllocator: ptr[VkAllocationCallbacks], pYcbcrConversion: ptr[VkSamplerYcbcrConversion]) -> VkResult
PFN_vkCreateSamplerYcbcrConversionKHR                                 :: alias fn(device: VkDevice, pCreateInfo: ptr[VkSamplerYcbcrConversionCreateInfo], pAllocator: ptr[VkAllocationCallbacks], pYcbcrConversion: ptr[VkSamplerYcbcrConversion]) -> VkResult
PFN_vkCreateSemaphore                                                 :: alias fn(device: VkDevice, pCreateInfo: ptr[VkSemaphoreCreateInfo], pAllocator: ptr[VkAllocationCallbacks], pSemaphore: ptr[VkSemaphore]) -> VkResult
PFN_vkCreateShaderModule                                              :: alias fn(device: VkDevice, pCreateInfo: ptr[VkShaderModuleCreateInfo], pAllocator: ptr[VkAllocationCallbacks], pShaderModule: ptr[VkShaderModule]) -> VkResult
PFN_vkCreateShadersEXT                                                :: alias fn(device: VkDevice, createInfoCount: u32, pCreateInfos: ptr[VkShaderCreateInfoEXT], pAllocator: ptr[VkAllocationCallbacks], pShaders: ptr[VkShaderEXT]) -> VkResult
PFN_vkCreateSharedSwapchainsKHR                                       :: alias fn(device: VkDevice, swapchainCount: u32, pCreateInfos: ptr[VkSwapchainCreateInfoKHR], pAllocator: ptr[VkAllocationCallbacks], pSwapchains: ptr[VkSwapchainKHR]) -> VkResult
PFN_vkCreateSwapchainKHR                                              :: alias fn(device: VkDevice, pCreateInfo: ptr[VkSwapchainCreateInfoKHR], pAllocator: ptr[VkAllocationCallbacks], pSwapchain: ptr[VkSwapchainKHR]) -> VkResult
PFN_vkCreateValidationCacheEXT                                        :: alias fn(device: VkDevice, pCreateInfo: ptr[VkValidationCacheCreateInfoEXT], pAllocator: ptr[VkAllocationCallbacks], pValidationCache: ptr[VkValidationCacheEXT]) -> VkResult
PFN_vkCreateVideoSessionKHR                                           :: alias fn(device: VkDevice, pCreateInfo: ptr[VkVideoSessionCreateInfoKHR], pAllocator: ptr[VkAllocationCallbacks], pVideoSession: ptr[VkVideoSessionKHR]) -> VkResult
PFN_vkCreateVideoSessionParametersKHR                                 :: alias fn(device: VkDevice, pCreateInfo: ptr[VkVideoSessionParametersCreateInfoKHR], pAllocator: ptr[VkAllocationCallbacks], pVideoSessionParameters: ptr[VkVideoSessionParametersKHR]) -> VkResult
PFN_vkDebugMarkerSetObjectNameEXT                                     :: alias fn(device: VkDevice, pNameInfo: ptr[VkDebugMarkerObjectNameInfoEXT]) -> VkResult
PFN_vkDebugMarkerSetObjectTagEXT                                      :: alias fn(device: VkDevice, pTagInfo: ptr[VkDebugMarkerObjectTagInfoEXT]) -> VkResult
PFN_vkDebugReportCallbackEXT                                          :: alias fn(flags: VkDebugReportFlagsEXT, objectType: VkDebugReportObjectTypeEXT, object: u64, location: uint, messageCode: i32, pLayerPrefix: string, pMessage: string, pUserData: rawptr) -> b32
PFN_vkDebugReportMessageEXT                                           :: alias fn(instance: VkInstance, flags: VkDebugReportFlagsEXT, objectType: VkDebugReportObjectTypeEXT, object: u64, location: uint, messageCode: i32, pLayerPrefix: string, pMessage: string) -> void
PFN_vkDebugUtilsMessengerCallbackEXT                                  :: alias fn(messageSeverity: VkDebugUtilsMessageSeverityFlagBitsEXT, messageTypes: VkDebugUtilsMessageTypeFlagsEXT, pCallbackData: ptr[VkDebugUtilsMessengerCallbackDataEXT], pUserData: rawptr) -> b32
PFN_vkDeferredOperationJoinKHR                                        :: alias fn(device: VkDevice, operation: VkDeferredOperationKHR) -> VkResult
PFN_vkDestroyAccelerationStructureKHR                                 :: alias fn(device: VkDevice, accelerationStructure: VkAccelerationStructureKHR, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyAccelerationStructureNV                                  :: alias fn(device: VkDevice, accelerationStructure: VkAccelerationStructureNV, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyBuffer                                                   :: alias fn(device: VkDevice, buffer: VkBuffer, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyBufferView                                               :: alias fn(device: VkDevice, bufferView: VkBufferView, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyCommandPool                                              :: alias fn(device: VkDevice, commandPool: VkCommandPool, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyCudaFunctionNV                                           :: alias fn(device: VkDevice, function: VkCudaFunctionNV, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyCudaModuleNV                                             :: alias fn(device: VkDevice, module: VkCudaModuleNV, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyCuFunctionNVX                                            :: alias fn(device: VkDevice, function: VkCuFunctionNVX, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyCuModuleNVX                                              :: alias fn(device: VkDevice, module: VkCuModuleNVX, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyDebugReportCallbackEXT                                   :: alias fn(instance: VkInstance, callback: VkDebugReportCallbackEXT, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyDebugUtilsMessengerEXT                                   :: alias fn(instance: VkInstance, messenger: VkDebugUtilsMessengerEXT, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyDeferredOperationKHR                                     :: alias fn(device: VkDevice, operation: VkDeferredOperationKHR, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyDescriptorPool                                           :: alias fn(device: VkDevice, descriptorPool: VkDescriptorPool, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyDescriptorSetLayout                                      :: alias fn(device: VkDevice, descriptorSetLayout: VkDescriptorSetLayout, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyDescriptorUpdateTemplate                                 :: alias fn(device: VkDevice, descriptorUpdateTemplate: VkDescriptorUpdateTemplate, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyDescriptorUpdateTemplateKHR                              :: alias fn(device: VkDevice, descriptorUpdateTemplate: VkDescriptorUpdateTemplate, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyDevice                                                   :: alias fn(device: VkDevice, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyEvent                                                    :: alias fn(device: VkDevice, event: VkEvent, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyFence                                                    :: alias fn(device: VkDevice, fence: VkFence, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyFramebuffer                                              :: alias fn(device: VkDevice, framebuffer: VkFramebuffer, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyImage                                                    :: alias fn(device: VkDevice, image: VkImage, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyImageView                                                :: alias fn(device: VkDevice, imageView: VkImageView, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyIndirectCommandsLayoutNV                                 :: alias fn(device: VkDevice, indirectCommandsLayout: VkIndirectCommandsLayoutNV, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyInstance                                                 :: alias fn(instance: VkInstance, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyMicromapEXT                                              :: alias fn(device: VkDevice, micromap: VkMicromapEXT, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyOpticalFlowSessionNV                                     :: alias fn(device: VkDevice, session: VkOpticalFlowSessionNV, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyPipeline                                                 :: alias fn(device: VkDevice, pipeline: VkPipeline, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyPipelineCache                                            :: alias fn(device: VkDevice, pipelineCache: VkPipelineCache, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyPipelineLayout                                           :: alias fn(device: VkDevice, pipelineLayout: VkPipelineLayout, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyPrivateDataSlot                                          :: alias fn(device: VkDevice, privateDataSlot: VkPrivateDataSlot, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyPrivateDataSlotEXT                                       :: alias fn(device: VkDevice, privateDataSlot: VkPrivateDataSlot, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyQueryPool                                                :: alias fn(device: VkDevice, queryPool: VkQueryPool, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyRenderPass                                               :: alias fn(device: VkDevice, renderPass: VkRenderPass, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroySampler                                                  :: alias fn(device: VkDevice, sampler: VkSampler, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroySamplerYcbcrConversion                                   :: alias fn(device: VkDevice, ycbcrConversion: VkSamplerYcbcrConversion, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroySamplerYcbcrConversionKHR                                :: alias fn(device: VkDevice, ycbcrConversion: VkSamplerYcbcrConversion, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroySemaphore                                                :: alias fn(device: VkDevice, semaphore: VkSemaphore, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyShaderEXT                                                :: alias fn(device: VkDevice, shader: VkShaderEXT, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyShaderModule                                             :: alias fn(device: VkDevice, shaderModule: VkShaderModule, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroySurfaceKHR                                               :: alias fn(instance: VkInstance, surface: VkSurfaceKHR, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroySwapchainKHR                                             :: alias fn(device: VkDevice, swapchain: VkSwapchainKHR, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyValidationCacheEXT                                       :: alias fn(device: VkDevice, validationCache: VkValidationCacheEXT, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyVideoSessionKHR                                          :: alias fn(device: VkDevice, videoSession: VkVideoSessionKHR, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDestroyVideoSessionParametersKHR                                :: alias fn(device: VkDevice, videoSessionParameters: VkVideoSessionParametersKHR, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkDeviceMemoryReportCallbackEXT                                   :: alias fn(pCallbackData: ptr[VkDeviceMemoryReportCallbackDataEXT], pUserData: rawptr) -> void
PFN_vkDeviceWaitIdle                                                  :: alias fn(device: VkDevice) -> VkResult
PFN_vkDisplayPowerControlEXT                                          :: alias fn(device: VkDevice, display: VkDisplayKHR, pDisplayPowerInfo: ptr[VkDisplayPowerInfoEXT]) -> VkResult
PFN_vkEndCommandBuffer                                                :: alias fn(commandBuffer: VkCommandBuffer) -> VkResult
PFN_vkEnumerateDeviceExtensionProperties                              :: alias fn(physicalDevice: VkPhysicalDevice, pLayerName: string, pPropertyCount: ptr[u32], pProperties: ptr[VkExtensionProperties]) -> VkResult
PFN_vkEnumerateDeviceLayerProperties                                  :: alias fn(physicalDevice: VkPhysicalDevice, pPropertyCount: ptr[u32], pProperties: ptr[VkLayerProperties]) -> VkResult
PFN_vkEnumerateInstanceExtensionProperties                            :: alias fn(pLayerName: string, pPropertyCount: ptr[u32], pProperties: ptr[VkExtensionProperties]) -> VkResult
PFN_vkEnumerateInstanceLayerProperties                                :: alias fn(pPropertyCount: ptr[u32], pProperties: ptr[VkLayerProperties]) -> VkResult
PFN_vkEnumerateInstanceVersion                                        :: alias fn(pApiVersion: ptr[u32]) -> VkResult
PFN_vkEnumeratePhysicalDeviceGroups                                   :: alias fn(instance: VkInstance, pPhysicalDeviceGroupCount: ptr[u32], pPhysicalDeviceGroupProperties: ptr[VkPhysicalDeviceGroupProperties]) -> VkResult
PFN_vkEnumeratePhysicalDeviceGroupsKHR                                :: alias fn(instance: VkInstance, pPhysicalDeviceGroupCount: ptr[u32], pPhysicalDeviceGroupProperties: ptr[VkPhysicalDeviceGroupProperties]) -> VkResult
PFN_vkEnumeratePhysicalDeviceQueueFamilyPerformanceQueryCountersKHR   :: alias fn(physicalDevice: VkPhysicalDevice, queueFamilyIndex: u32, pCounterCount: ptr[u32], pCounters: ptr[VkPerformanceCounterKHR], pCounterDescriptions: ptr[VkPerformanceCounterDescriptionKHR]) -> VkResult
PFN_vkEnumeratePhysicalDevices                                        :: alias fn(instance: VkInstance, pPhysicalDeviceCount: ptr[u32], pPhysicalDevices: ptr[VkPhysicalDevice]) -> VkResult
PFN_vkFlushMappedMemoryRanges                                         :: alias fn(device: VkDevice, memoryRangeCount: u32, pMemoryRanges: ptr[VkMappedMemoryRange]) -> VkResult
PFN_vkFreeCommandBuffers                                              :: alias fn(device: VkDevice, commandPool: VkCommandPool, commandBufferCount: u32, pCommandBuffers: ptr[VkCommandBuffer]) -> void
PFN_vkFreeDescriptorSets                                              :: alias fn(device: VkDevice, descriptorPool: VkDescriptorPool, descriptorSetCount: u32, pDescriptorSets: ptr[VkDescriptorSet]) -> VkResult
PFN_vkFreeFunction                                                    :: alias fn(pUserData: rawptr, pMemory: rawptr) -> void
PFN_vkFreeMemory                                                      :: alias fn(device: VkDevice, memory: VkDeviceMemory, pAllocator: ptr[VkAllocationCallbacks]) -> void
PFN_vkGetAccelerationStructureBuildSizesKHR                           :: alias fn(device: VkDevice, buildType: VkAccelerationStructureBuildTypeKHR, pBuildInfo: ptr[VkAccelerationStructureBuildGeometryInfoKHR], pMaxPrimitiveCounts: ptr[u32], pSizeInfo: ptr[VkAccelerationStructureBuildSizesInfoKHR]) -> void
PFN_vkGetAccelerationStructureDeviceAddressKHR                        :: alias fn(device: VkDevice, pInfo: ptr[VkAccelerationStructureDeviceAddressInfoKHR]) -> VkDeviceAddress
PFN_vkGetAccelerationStructureHandleNV                                :: alias fn(device: VkDevice, accelerationStructure: VkAccelerationStructureNV, dataSize: uint, pData: rawptr) -> VkResult
PFN_vkGetAccelerationStructureMemoryRequirementsNV                    :: alias fn(device: VkDevice, pInfo: ptr[VkAccelerationStructureMemoryRequirementsInfoNV], pMemoryRequirements: ptr[VkMemoryRequirements2KHR]) -> void
PFN_vkGetAccelerationStructureOpaqueCaptureDescriptorDataEXT          :: alias fn(device: VkDevice, pInfo: ptr[VkAccelerationStructureCaptureDescriptorDataInfoEXT], pData: rawptr) -> VkResult
PFN_vkGetBufferDeviceAddress                                          :: alias fn(device: VkDevice, pInfo: ptr[VkBufferDeviceAddressInfo]) -> VkDeviceAddress
PFN_vkGetBufferDeviceAddressEXT                                       :: alias fn(device: VkDevice, pInfo: ptr[VkBufferDeviceAddressInfo]) -> VkDeviceAddress
PFN_vkGetBufferDeviceAddressKHR                                       :: alias fn(device: VkDevice, pInfo: ptr[VkBufferDeviceAddressInfo]) -> VkDeviceAddress
PFN_vkGetBufferMemoryRequirements                                     :: alias fn(device: VkDevice, buffer: VkBuffer, pMemoryRequirements: ptr[VkMemoryRequirements]) -> void
PFN_vkGetBufferMemoryRequirements2                                    :: alias fn(device: VkDevice, pInfo: ptr[VkBufferMemoryRequirementsInfo2], pMemoryRequirements: ptr[VkMemoryRequirements2]) -> void
PFN_vkGetBufferMemoryRequirements2KHR                                 :: alias fn(device: VkDevice, pInfo: ptr[VkBufferMemoryRequirementsInfo2], pMemoryRequirements: ptr[VkMemoryRequirements2]) -> void
PFN_vkGetBufferOpaqueCaptureAddress                                   :: alias fn(device: VkDevice, pInfo: ptr[VkBufferDeviceAddressInfo]) -> u64
PFN_vkGetBufferOpaqueCaptureAddressKHR                                :: alias fn(device: VkDevice, pInfo: ptr[VkBufferDeviceAddressInfo]) -> u64
PFN_vkGetBufferOpaqueCaptureDescriptorDataEXT                         :: alias fn(device: VkDevice, pInfo: ptr[VkBufferCaptureDescriptorDataInfoEXT], pData: rawptr) -> VkResult
PFN_vkGetCalibratedTimestampsEXT                                      :: alias fn(device: VkDevice, timestampCount: u32, pTimestampInfos: ptr[VkCalibratedTimestampInfoKHR], pTimestamps: ptr[u64], pMaxDeviation: ptr[u64]) -> VkResult
PFN_vkGetCalibratedTimestampsKHR                                      :: alias fn(device: VkDevice, timestampCount: u32, pTimestampInfos: ptr[VkCalibratedTimestampInfoKHR], pTimestamps: ptr[u64], pMaxDeviation: ptr[u64]) -> VkResult
PFN_vkGetCudaModuleCacheNV                                            :: alias fn(device: VkDevice, module: VkCudaModuleNV, pCacheSize: ptr[uint], pCacheData: rawptr) -> VkResult
PFN_vkGetDeferredOperationMaxConcurrencyKHR                           :: alias fn(device: VkDevice, operation: VkDeferredOperationKHR) -> u32
PFN_vkGetDeferredOperationResultKHR                                   :: alias fn(device: VkDevice, operation: VkDeferredOperationKHR) -> VkResult
PFN_vkGetDescriptorEXT                                                :: alias fn(device: VkDevice, pDescriptorInfo: ptr[VkDescriptorGetInfoEXT], dataSize: uint, pDescriptor: rawptr) -> void
PFN_vkGetDescriptorSetHostMappingVALVE                                :: alias fn(device: VkDevice, descriptorSet: VkDescriptorSet, ppData: ptr[rawptr]) -> void
PFN_vkGetDescriptorSetLayoutBindingOffsetEXT                          :: alias fn(device: VkDevice, layout: VkDescriptorSetLayout, binding: u32, pOffset: ptr[VkDeviceSize]) -> void
PFN_vkGetDescriptorSetLayoutHostMappingInfoVALVE                      :: alias fn(device: VkDevice, pBindingReference: ptr[VkDescriptorSetBindingReferenceVALVE], pHostMapping: ptr[VkDescriptorSetLayoutHostMappingInfoVALVE]) -> void
PFN_vkGetDescriptorSetLayoutSizeEXT                                   :: alias fn(device: VkDevice, layout: VkDescriptorSetLayout, pLayoutSizeInBytes: ptr[VkDeviceSize]) -> void
PFN_vkGetDescriptorSetLayoutSupport                                   :: alias fn(device: VkDevice, pCreateInfo: ptr[VkDescriptorSetLayoutCreateInfo], pSupport: ptr[VkDescriptorSetLayoutSupport]) -> void
PFN_vkGetDescriptorSetLayoutSupportKHR                                :: alias fn(device: VkDevice, pCreateInfo: ptr[VkDescriptorSetLayoutCreateInfo], pSupport: ptr[VkDescriptorSetLayoutSupport]) -> void
PFN_vkGetDeviceAccelerationStructureCompatibilityKHR                  :: alias fn(device: VkDevice, pVersionInfo: ptr[VkAccelerationStructureVersionInfoKHR], pCompatibility: ptr[VkAccelerationStructureCompatibilityKHR]) -> void
PFN_vkGetDeviceBufferMemoryRequirements                               :: alias fn(device: VkDevice, pInfo: ptr[VkDeviceBufferMemoryRequirements], pMemoryRequirements: ptr[VkMemoryRequirements2]) -> void
PFN_vkGetDeviceBufferMemoryRequirementsKHR                            :: alias fn(device: VkDevice, pInfo: ptr[VkDeviceBufferMemoryRequirements], pMemoryRequirements: ptr[VkMemoryRequirements2]) -> void
PFN_vkGetDeviceFaultInfoEXT                                           :: alias fn(device: VkDevice, pFaultCounts: ptr[VkDeviceFaultCountsEXT], pFaultInfo: ptr[VkDeviceFaultInfoEXT]) -> VkResult
PFN_vkGetDeviceGroupPeerMemoryFeatures                                :: alias fn(device: VkDevice, heapIndex: u32, localDeviceIndex: u32, remoteDeviceIndex: u32, pPeerMemoryFeatures: ptr[VkPeerMemoryFeatureFlags]) -> void
PFN_vkGetDeviceGroupPeerMemoryFeaturesKHR                             :: alias fn(device: VkDevice, heapIndex: u32, localDeviceIndex: u32, remoteDeviceIndex: u32, pPeerMemoryFeatures: ptr[VkPeerMemoryFeatureFlags]) -> void
PFN_vkGetDeviceGroupPresentCapabilitiesKHR                            :: alias fn(device: VkDevice, pDeviceGroupPresentCapabilities: ptr[VkDeviceGroupPresentCapabilitiesKHR]) -> VkResult
PFN_vkGetDeviceGroupSurfacePresentModesKHR                            :: alias fn(device: VkDevice, surface: VkSurfaceKHR, pModes: ptr[VkDeviceGroupPresentModeFlagsKHR]) -> VkResult
PFN_vkGetDeviceImageMemoryRequirements                                :: alias fn(device: VkDevice, pInfo: ptr[VkDeviceImageMemoryRequirements], pMemoryRequirements: ptr[VkMemoryRequirements2]) -> void
PFN_vkGetDeviceImageMemoryRequirementsKHR                             :: alias fn(device: VkDevice, pInfo: ptr[VkDeviceImageMemoryRequirements], pMemoryRequirements: ptr[VkMemoryRequirements2]) -> void
PFN_vkGetDeviceImageSparseMemoryRequirements                          :: alias fn(device: VkDevice, pInfo: ptr[VkDeviceImageMemoryRequirements], pSparseMemoryRequirementCount: ptr[u32], pSparseMemoryRequirements: ptr[VkSparseImageMemoryRequirements2]) -> void
PFN_vkGetDeviceImageSparseMemoryRequirementsKHR                       :: alias fn(device: VkDevice, pInfo: ptr[VkDeviceImageMemoryRequirements], pSparseMemoryRequirementCount: ptr[u32], pSparseMemoryRequirements: ptr[VkSparseImageMemoryRequirements2]) -> void
PFN_vkGetDeviceImageSubresourceLayoutKHR                              :: alias fn(device: VkDevice, pInfo: ptr[VkDeviceImageSubresourceInfoKHR], pLayout: ptr[VkSubresourceLayout2KHR]) -> void
PFN_vkGetDeviceMemoryCommitment                                       :: alias fn(device: VkDevice, memory: VkDeviceMemory, pCommittedMemoryInBytes: ptr[VkDeviceSize]) -> void
PFN_vkGetDeviceMemoryOpaqueCaptureAddress                             :: alias fn(device: VkDevice, pInfo: ptr[VkDeviceMemoryOpaqueCaptureAddressInfo]) -> u64
PFN_vkGetDeviceMemoryOpaqueCaptureAddressKHR                          :: alias fn(device: VkDevice, pInfo: ptr[VkDeviceMemoryOpaqueCaptureAddressInfo]) -> u64
PFN_vkGetDeviceMicromapCompatibilityEXT                               :: alias fn(device: VkDevice, pVersionInfo: ptr[VkMicromapVersionInfoEXT], pCompatibility: ptr[VkAccelerationStructureCompatibilityKHR]) -> void
PFN_vkGetDeviceProcAddr                                               :: alias fn(device: VkDevice, pName: string) -> PFN_vkVoidFunction
PFN_vkGetDeviceQueue                                                  :: alias fn(device: VkDevice, queueFamilyIndex: u32, queueIndex: u32, pQueue: ptr[VkQueue]) -> void
PFN_vkGetDeviceQueue2                                                 :: alias fn(device: VkDevice, pQueueInfo: ptr[VkDeviceQueueInfo2], pQueue: ptr[VkQueue]) -> void
PFN_vkGetDeviceSubpassShadingMaxWorkgroupSizeHUAWEI                   :: alias fn(device: VkDevice, renderpass: VkRenderPass, pMaxWorkgroupSize: ptr[VkExtent2D]) -> VkResult
PFN_vkGetDisplayModeProperties2KHR                                    :: alias fn(physicalDevice: VkPhysicalDevice, display: VkDisplayKHR, pPropertyCount: ptr[u32], pProperties: ptr[VkDisplayModeProperties2KHR]) -> VkResult
PFN_vkGetDisplayModePropertiesKHR                                     :: alias fn(physicalDevice: VkPhysicalDevice, display: VkDisplayKHR, pPropertyCount: ptr[u32], pProperties: ptr[VkDisplayModePropertiesKHR]) -> VkResult
PFN_vkGetDisplayPlaneCapabilities2KHR                                 :: alias fn(physicalDevice: VkPhysicalDevice, pDisplayPlaneInfo: ptr[VkDisplayPlaneInfo2KHR], pCapabilities: ptr[VkDisplayPlaneCapabilities2KHR]) -> VkResult
PFN_vkGetDisplayPlaneCapabilitiesKHR                                  :: alias fn(physicalDevice: VkPhysicalDevice, mode: VkDisplayModeKHR, planeIndex: u32, pCapabilities: ptr[VkDisplayPlaneCapabilitiesKHR]) -> VkResult
PFN_vkGetDisplayPlaneSupportedDisplaysKHR                             :: alias fn(physicalDevice: VkPhysicalDevice, planeIndex: u32, pDisplayCount: ptr[u32], pDisplays: ptr[VkDisplayKHR]) -> VkResult
PFN_vkGetDrmDisplayEXT                                                :: alias fn(physicalDevice: VkPhysicalDevice, drmFd: i32, connectorId: u32, display: ptr[VkDisplayKHR]) -> VkResult
PFN_vkGetDynamicRenderingTilePropertiesQCOM                           :: alias fn(device: VkDevice, pRenderingInfo: ptr[VkRenderingInfo], pProperties: ptr[VkTilePropertiesQCOM]) -> VkResult
PFN_vkGetEncodedVideoSessionParametersKHR                             :: alias fn(device: VkDevice, pVideoSessionParametersInfo: ptr[VkVideoEncodeSessionParametersGetInfoKHR], pFeedbackInfo: ptr[VkVideoEncodeSessionParametersFeedbackInfoKHR], pDataSize: ptr[uint], pData: rawptr) -> VkResult
PFN_vkGetEventStatus                                                  :: alias fn(device: VkDevice, event: VkEvent) -> VkResult
PFN_vkGetFenceFdKHR                                                   :: alias fn(device: VkDevice, pGetFdInfo: ptr[VkFenceGetFdInfoKHR], pFd: ptr[int]) -> VkResult
PFN_vkGetFenceStatus                                                  :: alias fn(device: VkDevice, fence: VkFence) -> VkResult
PFN_vkGetFramebufferTilePropertiesQCOM                                :: alias fn(device: VkDevice, framebuffer: VkFramebuffer, pPropertiesCount: ptr[u32], pProperties: ptr[VkTilePropertiesQCOM]) -> VkResult
PFN_vkGetGeneratedCommandsMemoryRequirementsNV                        :: alias fn(device: VkDevice, pInfo: ptr[VkGeneratedCommandsMemoryRequirementsInfoNV], pMemoryRequirements: ptr[VkMemoryRequirements2]) -> void
PFN_vkGetImageDrmFormatModifierPropertiesEXT                          :: alias fn(device: VkDevice, image: VkImage, pProperties: ptr[VkImageDrmFormatModifierPropertiesEXT]) -> VkResult
PFN_vkGetImageMemoryRequirements                                      :: alias fn(device: VkDevice, image: VkImage, pMemoryRequirements: ptr[VkMemoryRequirements]) -> void
PFN_vkGetImageMemoryRequirements2                                     :: alias fn(device: VkDevice, pInfo: ptr[VkImageMemoryRequirementsInfo2], pMemoryRequirements: ptr[VkMemoryRequirements2]) -> void
PFN_vkGetImageMemoryRequirements2KHR                                  :: alias fn(device: VkDevice, pInfo: ptr[VkImageMemoryRequirementsInfo2], pMemoryRequirements: ptr[VkMemoryRequirements2]) -> void
PFN_vkGetImageOpaqueCaptureDescriptorDataEXT                          :: alias fn(device: VkDevice, pInfo: ptr[VkImageCaptureDescriptorDataInfoEXT], pData: rawptr) -> VkResult
PFN_vkGetImageSparseMemoryRequirements                                :: alias fn(device: VkDevice, image: VkImage, pSparseMemoryRequirementCount: ptr[u32], pSparseMemoryRequirements: ptr[VkSparseImageMemoryRequirements]) -> void
PFN_vkGetImageSparseMemoryRequirements2                               :: alias fn(device: VkDevice, pInfo: ptr[VkImageSparseMemoryRequirementsInfo2], pSparseMemoryRequirementCount: ptr[u32], pSparseMemoryRequirements: ptr[VkSparseImageMemoryRequirements2]) -> void
PFN_vkGetImageSparseMemoryRequirements2KHR                            :: alias fn(device: VkDevice, pInfo: ptr[VkImageSparseMemoryRequirementsInfo2], pSparseMemoryRequirementCount: ptr[u32], pSparseMemoryRequirements: ptr[VkSparseImageMemoryRequirements2]) -> void
PFN_vkGetImageSubresourceLayout                                       :: alias fn(device: VkDevice, image: VkImage, pSubresource: ptr[VkImageSubresource], pLayout: ptr[VkSubresourceLayout]) -> void
PFN_vkGetImageSubresourceLayout2EXT                                   :: alias fn(device: VkDevice, image: VkImage, pSubresource: ptr[VkImageSubresource2KHR], pLayout: ptr[VkSubresourceLayout2KHR]) -> void
PFN_vkGetImageSubresourceLayout2KHR                                   :: alias fn(device: VkDevice, image: VkImage, pSubresource: ptr[VkImageSubresource2KHR], pLayout: ptr[VkSubresourceLayout2KHR]) -> void
PFN_vkGetImageViewAddressNVX                                          :: alias fn(device: VkDevice, imageView: VkImageView, pProperties: ptr[VkImageViewAddressPropertiesNVX]) -> VkResult
PFN_vkGetImageViewHandleNVX                                           :: alias fn(device: VkDevice, pInfo: ptr[VkImageViewHandleInfoNVX]) -> u32
PFN_vkGetImageViewOpaqueCaptureDescriptorDataEXT                      :: alias fn(device: VkDevice, pInfo: ptr[VkImageViewCaptureDescriptorDataInfoEXT], pData: rawptr) -> VkResult
PFN_vkGetInstanceProcAddr                                             :: alias fn(instance: VkInstance, pName: string) -> PFN_vkVoidFunction
PFN_vkGetInstanceProcAddrLUNARG                                       :: alias fn(instance: VkInstance, pName: string) -> PFN_vkVoidFunction
PFN_vkGetLatencyTimingsNV                                             :: alias fn(device: VkDevice, swapchain: VkSwapchainKHR, pLatencyMarkerInfo: ptr[VkGetLatencyMarkerInfoNV]) -> void
PFN_vkGetMemoryFdKHR                                                  :: alias fn(device: VkDevice, pGetFdInfo: ptr[VkMemoryGetFdInfoKHR], pFd: ptr[int]) -> VkResult
PFN_vkGetMemoryFdPropertiesKHR                                        :: alias fn(device: VkDevice, handleType: VkExternalMemoryHandleTypeFlagBits, fd: int, pMemoryFdProperties: ptr[VkMemoryFdPropertiesKHR]) -> VkResult
PFN_vkGetMemoryHostPointerPropertiesEXT                               :: alias fn(device: VkDevice, handleType: VkExternalMemoryHandleTypeFlagBits, pHostPointer: rawptr, pMemoryHostPointerProperties: ptr[VkMemoryHostPointerPropertiesEXT]) -> VkResult
PFN_vkGetMemoryRemoteAddressNV                                        :: alias fn(device: VkDevice, pMemoryGetRemoteAddressInfo: ptr[VkMemoryGetRemoteAddressInfoNV], pAddress: ptr[VkRemoteAddressNV]) -> VkResult
PFN_vkGetMicromapBuildSizesEXT                                        :: alias fn(device: VkDevice, buildType: VkAccelerationStructureBuildTypeKHR, pBuildInfo: ptr[VkMicromapBuildInfoEXT], pSizeInfo: ptr[VkMicromapBuildSizesInfoEXT]) -> void
PFN_vkGetPastPresentationTimingGOOGLE                                 :: alias fn(device: VkDevice, swapchain: VkSwapchainKHR, pPresentationTimingCount: ptr[u32], pPresentationTimings: ptr[VkPastPresentationTimingGOOGLE]) -> VkResult
PFN_vkGetPerformanceParameterINTEL                                    :: alias fn(device: VkDevice, parameter: VkPerformanceParameterTypeINTEL, pValue: ptr[VkPerformanceValueINTEL]) -> VkResult
PFN_vkGetPhysicalDeviceCalibrateableTimeDomainsEXT                    :: alias fn(physicalDevice: VkPhysicalDevice, pTimeDomainCount: ptr[u32], pTimeDomains: ptr[VkTimeDomainKHR]) -> VkResult
PFN_vkGetPhysicalDeviceCalibrateableTimeDomainsKHR                    :: alias fn(physicalDevice: VkPhysicalDevice, pTimeDomainCount: ptr[u32], pTimeDomains: ptr[VkTimeDomainKHR]) -> VkResult
PFN_vkGetPhysicalDeviceCooperativeMatrixPropertiesKHR                 :: alias fn(physicalDevice: VkPhysicalDevice, pPropertyCount: ptr[u32], pProperties: ptr[VkCooperativeMatrixPropertiesKHR]) -> VkResult
PFN_vkGetPhysicalDeviceCooperativeMatrixPropertiesNV                  :: alias fn(physicalDevice: VkPhysicalDevice, pPropertyCount: ptr[u32], pProperties: ptr[VkCooperativeMatrixPropertiesNV]) -> VkResult
PFN_vkGetPhysicalDeviceDisplayPlaneProperties2KHR                     :: alias fn(physicalDevice: VkPhysicalDevice, pPropertyCount: ptr[u32], pProperties: ptr[VkDisplayPlaneProperties2KHR]) -> VkResult
PFN_vkGetPhysicalDeviceDisplayPlanePropertiesKHR                      :: alias fn(physicalDevice: VkPhysicalDevice, pPropertyCount: ptr[u32], pProperties: ptr[VkDisplayPlanePropertiesKHR]) -> VkResult
PFN_vkGetPhysicalDeviceDisplayProperties2KHR                          :: alias fn(physicalDevice: VkPhysicalDevice, pPropertyCount: ptr[u32], pProperties: ptr[VkDisplayProperties2KHR]) -> VkResult
PFN_vkGetPhysicalDeviceDisplayPropertiesKHR                           :: alias fn(physicalDevice: VkPhysicalDevice, pPropertyCount: ptr[u32], pProperties: ptr[VkDisplayPropertiesKHR]) -> VkResult
PFN_vkGetPhysicalDeviceExternalBufferProperties                       :: alias fn(physicalDevice: VkPhysicalDevice, pExternalBufferInfo: ptr[VkPhysicalDeviceExternalBufferInfo], pExternalBufferProperties: ptr[VkExternalBufferProperties]) -> void
PFN_vkGetPhysicalDeviceExternalBufferPropertiesKHR                    :: alias fn(physicalDevice: VkPhysicalDevice, pExternalBufferInfo: ptr[VkPhysicalDeviceExternalBufferInfo], pExternalBufferProperties: ptr[VkExternalBufferProperties]) -> void
PFN_vkGetPhysicalDeviceExternalFenceProperties                        :: alias fn(physicalDevice: VkPhysicalDevice, pExternalFenceInfo: ptr[VkPhysicalDeviceExternalFenceInfo], pExternalFenceProperties: ptr[VkExternalFenceProperties]) -> void
PFN_vkGetPhysicalDeviceExternalFencePropertiesKHR                     :: alias fn(physicalDevice: VkPhysicalDevice, pExternalFenceInfo: ptr[VkPhysicalDeviceExternalFenceInfo], pExternalFenceProperties: ptr[VkExternalFenceProperties]) -> void
PFN_vkGetPhysicalDeviceExternalImageFormatPropertiesNV                :: alias fn(physicalDevice: VkPhysicalDevice, format: VkFormat, type: VkImageType, tiling: VkImageTiling, usage: VkImageUsageFlags, flags: VkImageCreateFlags, externalHandleType: VkExternalMemoryHandleTypeFlagsNV, pExternalImageFormatProperties: ptr[VkExternalImageFormatPropertiesNV]) -> VkResult
PFN_vkGetPhysicalDeviceExternalSemaphoreProperties                    :: alias fn(physicalDevice: VkPhysicalDevice, pExternalSemaphoreInfo: ptr[VkPhysicalDeviceExternalSemaphoreInfo], pExternalSemaphoreProperties: ptr[VkExternalSemaphoreProperties]) -> void
PFN_vkGetPhysicalDeviceExternalSemaphorePropertiesKHR                 :: alias fn(physicalDevice: VkPhysicalDevice, pExternalSemaphoreInfo: ptr[VkPhysicalDeviceExternalSemaphoreInfo], pExternalSemaphoreProperties: ptr[VkExternalSemaphoreProperties]) -> void
PFN_vkGetPhysicalDeviceFeatures                                       :: alias fn(physicalDevice: VkPhysicalDevice, pFeatures: ptr[VkPhysicalDeviceFeatures]) -> void
PFN_vkGetPhysicalDeviceFeatures2                                      :: alias fn(physicalDevice: VkPhysicalDevice, pFeatures: ptr[VkPhysicalDeviceFeatures2]) -> void
PFN_vkGetPhysicalDeviceFeatures2KHR                                   :: alias fn(physicalDevice: VkPhysicalDevice, pFeatures: ptr[VkPhysicalDeviceFeatures2]) -> void
PFN_vkGetPhysicalDeviceFormatProperties                               :: alias fn(physicalDevice: VkPhysicalDevice, format: VkFormat, pFormatProperties: ptr[VkFormatProperties]) -> void
PFN_vkGetPhysicalDeviceFormatProperties2                              :: alias fn(physicalDevice: VkPhysicalDevice, format: VkFormat, pFormatProperties: ptr[VkFormatProperties2]) -> void
PFN_vkGetPhysicalDeviceFormatProperties2KHR                           :: alias fn(physicalDevice: VkPhysicalDevice, format: VkFormat, pFormatProperties: ptr[VkFormatProperties2]) -> void
PFN_vkGetPhysicalDeviceFragmentShadingRatesKHR                        :: alias fn(physicalDevice: VkPhysicalDevice, pFragmentShadingRateCount: ptr[u32], pFragmentShadingRates: ptr[VkPhysicalDeviceFragmentShadingRateKHR]) -> VkResult
PFN_vkGetPhysicalDeviceImageFormatProperties                          :: alias fn(physicalDevice: VkPhysicalDevice, format: VkFormat, type: VkImageType, tiling: VkImageTiling, usage: VkImageUsageFlags, flags: VkImageCreateFlags, pImageFormatProperties: ptr[VkImageFormatProperties]) -> VkResult
PFN_vkGetPhysicalDeviceImageFormatProperties2                         :: alias fn(physicalDevice: VkPhysicalDevice, pImageFormatInfo: ptr[VkPhysicalDeviceImageFormatInfo2], pImageFormatProperties: ptr[VkImageFormatProperties2]) -> VkResult
PFN_vkGetPhysicalDeviceImageFormatProperties2KHR                      :: alias fn(physicalDevice: VkPhysicalDevice, pImageFormatInfo: ptr[VkPhysicalDeviceImageFormatInfo2], pImageFormatProperties: ptr[VkImageFormatProperties2]) -> VkResult
PFN_vkGetPhysicalDeviceMemoryProperties                               :: alias fn(physicalDevice: VkPhysicalDevice, pMemoryProperties: ptr[VkPhysicalDeviceMemoryProperties]) -> void
PFN_vkGetPhysicalDeviceMemoryProperties2                              :: alias fn(physicalDevice: VkPhysicalDevice, pMemoryProperties: ptr[VkPhysicalDeviceMemoryProperties2]) -> void
PFN_vkGetPhysicalDeviceMemoryProperties2KHR                           :: alias fn(physicalDevice: VkPhysicalDevice, pMemoryProperties: ptr[VkPhysicalDeviceMemoryProperties2]) -> void
PFN_vkGetPhysicalDeviceMultisamplePropertiesEXT                       :: alias fn(physicalDevice: VkPhysicalDevice, samples: VkSampleCountFlagBits, pMultisampleProperties: ptr[VkMultisamplePropertiesEXT]) -> void
PFN_vkGetPhysicalDeviceOpticalFlowImageFormatsNV                      :: alias fn(physicalDevice: VkPhysicalDevice, pOpticalFlowImageFormatInfo: ptr[VkOpticalFlowImageFormatInfoNV], pFormatCount: ptr[u32], pImageFormatProperties: ptr[VkOpticalFlowImageFormatPropertiesNV]) -> VkResult
PFN_vkGetPhysicalDevicePresentRectanglesKHR                           :: alias fn(physicalDevice: VkPhysicalDevice, surface: VkSurfaceKHR, pRectCount: ptr[u32], pRects: ptr[VkRect2D]) -> VkResult
PFN_vkGetPhysicalDeviceProperties                                     :: alias fn(physicalDevice: VkPhysicalDevice, pProperties: ptr[VkPhysicalDeviceProperties]) -> void
PFN_vkGetPhysicalDeviceProperties2                                    :: alias fn(physicalDevice: VkPhysicalDevice, pProperties: ptr[VkPhysicalDeviceProperties2]) -> void
PFN_vkGetPhysicalDeviceProperties2KHR                                 :: alias fn(physicalDevice: VkPhysicalDevice, pProperties: ptr[VkPhysicalDeviceProperties2]) -> void
PFN_vkGetPhysicalDeviceQueueFamilyPerformanceQueryPassesKHR           :: alias fn(physicalDevice: VkPhysicalDevice, pPerformanceQueryCreateInfo: ptr[VkQueryPoolPerformanceCreateInfoKHR], pNumPasses: ptr[u32]) -> void
PFN_vkGetPhysicalDeviceQueueFamilyProperties                          :: alias fn(physicalDevice: VkPhysicalDevice, pQueueFamilyPropertyCount: ptr[u32], pQueueFamilyProperties: ptr[VkQueueFamilyProperties]) -> void
PFN_vkGetPhysicalDeviceQueueFamilyProperties2                         :: alias fn(physicalDevice: VkPhysicalDevice, pQueueFamilyPropertyCount: ptr[u32], pQueueFamilyProperties: ptr[VkQueueFamilyProperties2]) -> void
PFN_vkGetPhysicalDeviceQueueFamilyProperties2KHR                      :: alias fn(physicalDevice: VkPhysicalDevice, pQueueFamilyPropertyCount: ptr[u32], pQueueFamilyProperties: ptr[VkQueueFamilyProperties2]) -> void
PFN_vkGetPhysicalDeviceSparseImageFormatProperties                    :: alias fn(physicalDevice: VkPhysicalDevice, format: VkFormat, type: VkImageType, samples: VkSampleCountFlagBits, usage: VkImageUsageFlags, tiling: VkImageTiling, pPropertyCount: ptr[u32], pProperties: ptr[VkSparseImageFormatProperties]) -> void
PFN_vkGetPhysicalDeviceSparseImageFormatProperties2                   :: alias fn(physicalDevice: VkPhysicalDevice, pFormatInfo: ptr[VkPhysicalDeviceSparseImageFormatInfo2], pPropertyCount: ptr[u32], pProperties: ptr[VkSparseImageFormatProperties2]) -> void
PFN_vkGetPhysicalDeviceSparseImageFormatProperties2KHR                :: alias fn(physicalDevice: VkPhysicalDevice, pFormatInfo: ptr[VkPhysicalDeviceSparseImageFormatInfo2], pPropertyCount: ptr[u32], pProperties: ptr[VkSparseImageFormatProperties2]) -> void
PFN_vkGetPhysicalDeviceSupportedFramebufferMixedSamplesCombinationsNV :: alias fn(physicalDevice: VkPhysicalDevice, pCombinationCount: ptr[u32], pCombinations: ptr[VkFramebufferMixedSamplesCombinationNV]) -> VkResult
PFN_vkGetPhysicalDeviceSurfaceCapabilities2EXT                        :: alias fn(physicalDevice: VkPhysicalDevice, surface: VkSurfaceKHR, pSurfaceCapabilities: ptr[VkSurfaceCapabilities2EXT]) -> VkResult
PFN_vkGetPhysicalDeviceSurfaceCapabilities2KHR                        :: alias fn(physicalDevice: VkPhysicalDevice, pSurfaceInfo: ptr[VkPhysicalDeviceSurfaceInfo2KHR], pSurfaceCapabilities: ptr[VkSurfaceCapabilities2KHR]) -> VkResult
PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR                         :: alias fn(physicalDevice: VkPhysicalDevice, surface: VkSurfaceKHR, pSurfaceCapabilities: ptr[VkSurfaceCapabilitiesKHR]) -> VkResult
PFN_vkGetPhysicalDeviceSurfaceFormats2KHR                             :: alias fn(physicalDevice: VkPhysicalDevice, pSurfaceInfo: ptr[VkPhysicalDeviceSurfaceInfo2KHR], pSurfaceFormatCount: ptr[u32], pSurfaceFormats: ptr[VkSurfaceFormat2KHR]) -> VkResult
PFN_vkGetPhysicalDeviceSurfaceFormatsKHR                              :: alias fn(physicalDevice: VkPhysicalDevice, surface: VkSurfaceKHR, pSurfaceFormatCount: ptr[u32], pSurfaceFormats: ptr[VkSurfaceFormatKHR]) -> VkResult
PFN_vkGetPhysicalDeviceSurfacePresentModesKHR                         :: alias fn(physicalDevice: VkPhysicalDevice, surface: VkSurfaceKHR, pPresentModeCount: ptr[u32], pPresentModes: ptr[VkPresentModeKHR]) -> VkResult
PFN_vkGetPhysicalDeviceSurfaceSupportKHR                              :: alias fn(physicalDevice: VkPhysicalDevice, queueFamilyIndex: u32, surface: VkSurfaceKHR, pSupported: ptr[b32]) -> VkResult
PFN_vkGetPhysicalDeviceToolProperties                                 :: alias fn(physicalDevice: VkPhysicalDevice, pToolCount: ptr[u32], pToolProperties: ptr[VkPhysicalDeviceToolProperties]) -> VkResult
PFN_vkGetPhysicalDeviceToolPropertiesEXT                              :: alias fn(physicalDevice: VkPhysicalDevice, pToolCount: ptr[u32], pToolProperties: ptr[VkPhysicalDeviceToolProperties]) -> VkResult
PFN_vkGetPhysicalDeviceVideoCapabilitiesKHR                           :: alias fn(physicalDevice: VkPhysicalDevice, pVideoProfile: ptr[VkVideoProfileInfoKHR], pCapabilities: ptr[VkVideoCapabilitiesKHR]) -> VkResult
PFN_vkGetPhysicalDeviceVideoEncodeQualityLevelPropertiesKHR           :: alias fn(physicalDevice: VkPhysicalDevice, pQualityLevelInfo: ptr[VkPhysicalDeviceVideoEncodeQualityLevelInfoKHR], pQualityLevelProperties: ptr[VkVideoEncodeQualityLevelPropertiesKHR]) -> VkResult
PFN_vkGetPhysicalDeviceVideoFormatPropertiesKHR                       :: alias fn(physicalDevice: VkPhysicalDevice, pVideoFormatInfo: ptr[VkPhysicalDeviceVideoFormatInfoKHR], pVideoFormatPropertyCount: ptr[u32], pVideoFormatProperties: ptr[VkVideoFormatPropertiesKHR]) -> VkResult
PFN_vkGetPipelineCacheData                                            :: alias fn(device: VkDevice, pipelineCache: VkPipelineCache, pDataSize: ptr[uint], pData: rawptr) -> VkResult
PFN_vkGetPipelineExecutableInternalRepresentationsKHR                 :: alias fn(device: VkDevice, pExecutableInfo: ptr[VkPipelineExecutableInfoKHR], pInternalRepresentationCount: ptr[u32], pInternalRepresentations: ptr[VkPipelineExecutableInternalRepresentationKHR]) -> VkResult
PFN_vkGetPipelineExecutablePropertiesKHR                              :: alias fn(device: VkDevice, pPipelineInfo: ptr[VkPipelineInfoKHR], pExecutableCount: ptr[u32], pProperties: ptr[VkPipelineExecutablePropertiesKHR]) -> VkResult
PFN_vkGetPipelineExecutableStatisticsKHR                              :: alias fn(device: VkDevice, pExecutableInfo: ptr[VkPipelineExecutableInfoKHR], pStatisticCount: ptr[u32], pStatistics: ptr[VkPipelineExecutableStatisticKHR]) -> VkResult
PFN_vkGetPipelineIndirectDeviceAddressNV                              :: alias fn(device: VkDevice, pInfo: ptr[VkPipelineIndirectDeviceAddressInfoNV]) -> VkDeviceAddress
PFN_vkGetPipelineIndirectMemoryRequirementsNV                         :: alias fn(device: VkDevice, pCreateInfo: ptr[VkComputePipelineCreateInfo], pMemoryRequirements: ptr[VkMemoryRequirements2]) -> void
PFN_vkGetPipelinePropertiesEXT                                        :: alias fn(device: VkDevice, pPipelineInfo: ptr[VkPipelineInfoEXT], pPipelineProperties: ptr[VkBaseOutStructure]) -> VkResult
PFN_vkGetPrivateData                                                  :: alias fn(device: VkDevice, objectType: VkObjectType, objectHandle: u64, privateDataSlot: VkPrivateDataSlot, pData: ptr[u64]) -> void
PFN_vkGetPrivateDataEXT                                               :: alias fn(device: VkDevice, objectType: VkObjectType, objectHandle: u64, privateDataSlot: VkPrivateDataSlot, pData: ptr[u64]) -> void
PFN_vkGetQueryPoolResults                                             :: alias fn(device: VkDevice, queryPool: VkQueryPool, firstQuery: u32, queryCount: u32, dataSize: uint, pData: rawptr, stride: VkDeviceSize, flags: VkQueryResultFlags) -> VkResult
PFN_vkGetQueueCheckpointData2NV                                       :: alias fn(queue: VkQueue, pCheckpointDataCount: ptr[u32], pCheckpointData: ptr[VkCheckpointData2NV]) -> void
PFN_vkGetQueueCheckpointDataNV                                        :: alias fn(queue: VkQueue, pCheckpointDataCount: ptr[u32], pCheckpointData: ptr[VkCheckpointDataNV]) -> void
PFN_vkGetRayTracingCaptureReplayShaderGroupHandlesKHR                 :: alias fn(device: VkDevice, pipeline: VkPipeline, firstGroup: u32, groupCount: u32, dataSize: uint, pData: rawptr) -> VkResult
PFN_vkGetRayTracingShaderGroupHandlesKHR                              :: alias fn(device: VkDevice, pipeline: VkPipeline, firstGroup: u32, groupCount: u32, dataSize: uint, pData: rawptr) -> VkResult
PFN_vkGetRayTracingShaderGroupHandlesNV                               :: alias fn(device: VkDevice, pipeline: VkPipeline, firstGroup: u32, groupCount: u32, dataSize: uint, pData: rawptr) -> VkResult
PFN_vkGetRayTracingShaderGroupStackSizeKHR                            :: alias fn(device: VkDevice, pipeline: VkPipeline, group: u32, groupShader: VkShaderGroupShaderKHR) -> VkDeviceSize
PFN_vkGetRefreshCycleDurationGOOGLE                                   :: alias fn(device: VkDevice, swapchain: VkSwapchainKHR, pDisplayTimingProperties: ptr[VkRefreshCycleDurationGOOGLE]) -> VkResult
PFN_vkGetRenderAreaGranularity                                        :: alias fn(device: VkDevice, renderPass: VkRenderPass, pGranularity: ptr[VkExtent2D]) -> void
PFN_vkGetRenderingAreaGranularityKHR                                  :: alias fn(device: VkDevice, pRenderingAreaInfo: ptr[VkRenderingAreaInfoKHR], pGranularity: ptr[VkExtent2D]) -> void
PFN_vkGetSamplerOpaqueCaptureDescriptorDataEXT                        :: alias fn(device: VkDevice, pInfo: ptr[VkSamplerCaptureDescriptorDataInfoEXT], pData: rawptr) -> VkResult
PFN_vkGetSemaphoreCounterValue                                        :: alias fn(device: VkDevice, semaphore: VkSemaphore, pValue: ptr[u64]) -> VkResult
PFN_vkGetSemaphoreCounterValueKHR                                     :: alias fn(device: VkDevice, semaphore: VkSemaphore, pValue: ptr[u64]) -> VkResult
PFN_vkGetSemaphoreFdKHR                                               :: alias fn(device: VkDevice, pGetFdInfo: ptr[VkSemaphoreGetFdInfoKHR], pFd: ptr[int]) -> VkResult
PFN_vkGetShaderBinaryDataEXT                                          :: alias fn(device: VkDevice, shader: VkShaderEXT, pDataSize: ptr[uint], pData: rawptr) -> VkResult
PFN_vkGetShaderInfoAMD                                                :: alias fn(device: VkDevice, pipeline: VkPipeline, shaderStage: VkShaderStageFlagBits, infoType: VkShaderInfoTypeAMD, pInfoSize: ptr[uint], pInfo: rawptr) -> VkResult
PFN_vkGetShaderModuleCreateInfoIdentifierEXT                          :: alias fn(device: VkDevice, pCreateInfo: ptr[VkShaderModuleCreateInfo], pIdentifier: ptr[VkShaderModuleIdentifierEXT]) -> void
PFN_vkGetShaderModuleIdentifierEXT                                    :: alias fn(device: VkDevice, shaderModule: VkShaderModule, pIdentifier: ptr[VkShaderModuleIdentifierEXT]) -> void
PFN_vkGetSwapchainCounterEXT                                          :: alias fn(device: VkDevice, swapchain: VkSwapchainKHR, counter: VkSurfaceCounterFlagBitsEXT, pCounterValue: ptr[u64]) -> VkResult
PFN_vkGetSwapchainImagesKHR                                           :: alias fn(device: VkDevice, swapchain: VkSwapchainKHR, pSwapchainImageCount: ptr[u32], pSwapchainImages: ptr[VkImage]) -> VkResult
PFN_vkGetSwapchainStatusKHR                                           :: alias fn(device: VkDevice, swapchain: VkSwapchainKHR) -> VkResult
PFN_vkGetValidationCacheDataEXT                                       :: alias fn(device: VkDevice, validationCache: VkValidationCacheEXT, pDataSize: ptr[uint], pData: rawptr) -> VkResult
PFN_vkGetVideoSessionMemoryRequirementsKHR                            :: alias fn(device: VkDevice, videoSession: VkVideoSessionKHR, pMemoryRequirementsCount: ptr[u32], pMemoryRequirements: ptr[VkVideoSessionMemoryRequirementsKHR]) -> VkResult
PFN_vkImportFenceFdKHR                                                :: alias fn(device: VkDevice, pImportFenceFdInfo: ptr[VkImportFenceFdInfoKHR]) -> VkResult
PFN_vkImportSemaphoreFdKHR                                            :: alias fn(device: VkDevice, pImportSemaphoreFdInfo: ptr[VkImportSemaphoreFdInfoKHR]) -> VkResult
PFN_vkInitializePerformanceApiINTEL                                   :: alias fn(device: VkDevice, pInitializeInfo: ptr[VkInitializePerformanceApiInfoINTEL]) -> VkResult
PFN_vkInternalAllocationNotification                                  :: alias fn(pUserData: rawptr, size: uint, allocationType: VkInternalAllocationType, allocationScope: VkSystemAllocationScope) -> void
PFN_vkInternalFreeNotification                                        :: alias fn(pUserData: rawptr, size: uint, allocationType: VkInternalAllocationType, allocationScope: VkSystemAllocationScope) -> void
PFN_vkInvalidateMappedMemoryRanges                                    :: alias fn(device: VkDevice, memoryRangeCount: u32, pMemoryRanges: ptr[VkMappedMemoryRange]) -> VkResult
PFN_vkLatencySleepNV                                                  :: alias fn(device: VkDevice, swapchain: VkSwapchainKHR, pSleepInfo: ptr[VkLatencySleepInfoNV]) -> VkResult
PFN_vkMapMemory                                                       :: alias fn(device: VkDevice, memory: VkDeviceMemory, offset: VkDeviceSize, size: VkDeviceSize, flags: VkMemoryMapFlags, ppData: ptr[rawptr]) -> VkResult
PFN_vkMapMemory2KHR                                                   :: alias fn(device: VkDevice, pMemoryMapInfo: ptr[VkMemoryMapInfoKHR], ppData: ptr[rawptr]) -> VkResult
PFN_vkMergePipelineCaches                                             :: alias fn(device: VkDevice, dstCache: VkPipelineCache, srcCacheCount: u32, pSrcCaches: ptr[VkPipelineCache]) -> VkResult
PFN_vkMergeValidationCachesEXT                                        :: alias fn(device: VkDevice, dstCache: VkValidationCacheEXT, srcCacheCount: u32, pSrcCaches: ptr[VkValidationCacheEXT]) -> VkResult
PFN_vkQueueBeginDebugUtilsLabelEXT                                    :: alias fn(queue: VkQueue, pLabelInfo: ptr[VkDebugUtilsLabelEXT]) -> void
PFN_vkQueueBindSparse                                                 :: alias fn(queue: VkQueue, bindInfoCount: u32, pBindInfo: ptr[VkBindSparseInfo], fence: VkFence) -> VkResult
PFN_vkQueueEndDebugUtilsLabelEXT                                      :: alias fn(queue: VkQueue) -> void
PFN_vkQueueInsertDebugUtilsLabelEXT                                   :: alias fn(queue: VkQueue, pLabelInfo: ptr[VkDebugUtilsLabelEXT]) -> void
PFN_vkQueueNotifyOutOfBandNV                                          :: alias fn(queue: VkQueue, pQueueTypeInfo: ptr[VkOutOfBandQueueTypeInfoNV]) -> void
PFN_vkQueuePresentKHR                                                 :: alias fn(queue: VkQueue, pPresentInfo: ptr[VkPresentInfoKHR]) -> VkResult
PFN_vkQueueSetPerformanceConfigurationINTEL                           :: alias fn(queue: VkQueue, configuration: VkPerformanceConfigurationINTEL) -> VkResult
PFN_vkQueueSubmit                                                     :: alias fn(queue: VkQueue, submitCount: u32, pSubmits: ptr[VkSubmitInfo], fence: VkFence) -> VkResult
PFN_vkQueueSubmit2                                                    :: alias fn(queue: VkQueue, submitCount: u32, pSubmits: ptr[VkSubmitInfo2], fence: VkFence) -> VkResult
PFN_vkQueueSubmit2KHR                                                 :: alias fn(queue: VkQueue, submitCount: u32, pSubmits: ptr[VkSubmitInfo2], fence: VkFence) -> VkResult
PFN_vkQueueWaitIdle                                                   :: alias fn(queue: VkQueue) -> VkResult
PFN_vkReallocationFunction                                            :: alias fn(pUserData: rawptr, pOriginal: rawptr, size: uint, alignment: uint, allocationScope: VkSystemAllocationScope) -> rawptr
PFN_vkRegisterDeviceEventEXT                                          :: alias fn(device: VkDevice, pDeviceEventInfo: ptr[VkDeviceEventInfoEXT], pAllocator: ptr[VkAllocationCallbacks], pFence: ptr[VkFence]) -> VkResult
PFN_vkRegisterDisplayEventEXT                                         :: alias fn(device: VkDevice, display: VkDisplayKHR, pDisplayEventInfo: ptr[VkDisplayEventInfoEXT], pAllocator: ptr[VkAllocationCallbacks], pFence: ptr[VkFence]) -> VkResult
PFN_vkReleaseDisplayEXT                                               :: alias fn(physicalDevice: VkPhysicalDevice, display: VkDisplayKHR) -> VkResult
PFN_vkReleasePerformanceConfigurationINTEL                            :: alias fn(device: VkDevice, configuration: VkPerformanceConfigurationINTEL) -> VkResult
PFN_vkReleaseProfilingLockKHR                                         :: alias fn(device: VkDevice) -> void
PFN_vkReleaseSwapchainImagesEXT                                       :: alias fn(device: VkDevice, pReleaseInfo: ptr[VkReleaseSwapchainImagesInfoEXT]) -> VkResult
PFN_vkResetCommandBuffer                                              :: alias fn(commandBuffer: VkCommandBuffer, flags: VkCommandBufferResetFlags) -> VkResult
PFN_vkResetCommandPool                                                :: alias fn(device: VkDevice, commandPool: VkCommandPool, flags: VkCommandPoolResetFlags) -> VkResult
PFN_vkResetDescriptorPool                                             :: alias fn(device: VkDevice, descriptorPool: VkDescriptorPool, flags: VkDescriptorPoolResetFlags) -> VkResult
PFN_vkResetEvent                                                      :: alias fn(device: VkDevice, event: VkEvent) -> VkResult
PFN_vkResetFences                                                     :: alias fn(device: VkDevice, fenceCount: u32, pFences: ptr[VkFence]) -> VkResult
PFN_vkResetQueryPool                                                  :: alias fn(device: VkDevice, queryPool: VkQueryPool, firstQuery: u32, queryCount: u32) -> void
PFN_vkResetQueryPoolEXT                                               :: alias fn(device: VkDevice, queryPool: VkQueryPool, firstQuery: u32, queryCount: u32) -> void
PFN_vkSetDebugUtilsObjectNameEXT                                      :: alias fn(device: VkDevice, pNameInfo: ptr[VkDebugUtilsObjectNameInfoEXT]) -> VkResult
PFN_vkSetDebugUtilsObjectTagEXT                                       :: alias fn(device: VkDevice, pTagInfo: ptr[VkDebugUtilsObjectTagInfoEXT]) -> VkResult
PFN_vkSetDeviceMemoryPriorityEXT                                      :: alias fn(device: VkDevice, memory: VkDeviceMemory, priority: float) -> void
PFN_vkSetEvent                                                        :: alias fn(device: VkDevice, event: VkEvent) -> VkResult
PFN_vkSetHdrMetadataEXT                                               :: alias fn(device: VkDevice, swapchainCount: u32, pSwapchains: ptr[VkSwapchainKHR], pMetadata: ptr[VkHdrMetadataEXT]) -> void
PFN_vkSetLatencyMarkerNV                                              :: alias fn(device: VkDevice, swapchain: VkSwapchainKHR, pLatencyMarkerInfo: ptr[VkSetLatencyMarkerInfoNV]) -> void
PFN_vkSetLatencySleepModeNV                                           :: alias fn(device: VkDevice, swapchain: VkSwapchainKHR, pSleepModeInfo: ptr[VkLatencySleepModeInfoNV]) -> VkResult
PFN_vkSetLocalDimmingAMD                                              :: alias fn(device: VkDevice, swapChain: VkSwapchainKHR, localDimmingEnable: b32) -> void
PFN_vkSetPrivateData                                                  :: alias fn(device: VkDevice, objectType: VkObjectType, objectHandle: u64, privateDataSlot: VkPrivateDataSlot, data: u64) -> VkResult
PFN_vkSetPrivateDataEXT                                               :: alias fn(device: VkDevice, objectType: VkObjectType, objectHandle: u64, privateDataSlot: VkPrivateDataSlot, data: u64) -> VkResult
PFN_vkSignalSemaphore                                                 :: alias fn(device: VkDevice, pSignalInfo: ptr[VkSemaphoreSignalInfo]) -> VkResult
PFN_vkSignalSemaphoreKHR                                              :: alias fn(device: VkDevice, pSignalInfo: ptr[VkSemaphoreSignalInfo]) -> VkResult
PFN_vkSubmitDebugUtilsMessageEXT                                      :: alias fn(instance: VkInstance, messageSeverity: VkDebugUtilsMessageSeverityFlagBitsEXT, messageTypes: VkDebugUtilsMessageTypeFlagsEXT, pCallbackData: ptr[VkDebugUtilsMessengerCallbackDataEXT]) -> void
PFN_vkTransitionImageLayoutEXT                                        :: alias fn(device: VkDevice, transitionCount: u32, pTransitions: ptr[VkHostImageLayoutTransitionInfoEXT]) -> VkResult
PFN_vkTrimCommandPool                                                 :: alias fn(device: VkDevice, commandPool: VkCommandPool, flags: VkCommandPoolTrimFlags) -> void
PFN_vkTrimCommandPoolKHR                                              :: alias fn(device: VkDevice, commandPool: VkCommandPool, flags: VkCommandPoolTrimFlags) -> void
PFN_vkUninitializePerformanceApiINTEL                                 :: alias fn(device: VkDevice) -> void
PFN_vkUnmapMemory                                                     :: alias fn(device: VkDevice, memory: VkDeviceMemory) -> void
PFN_vkUnmapMemory2KHR                                                 :: alias fn(device: VkDevice, pMemoryUnmapInfo: ptr[VkMemoryUnmapInfoKHR]) -> VkResult
PFN_vkUpdateDescriptorSets                                            :: alias fn(device: VkDevice, descriptorWriteCount: u32, pDescriptorWrites: ptr[VkWriteDescriptorSet], descriptorCopyCount: u32, pDescriptorCopies: ptr[VkCopyDescriptorSet]) -> void
PFN_vkUpdateDescriptorSetWithTemplate                                 :: alias fn(device: VkDevice, descriptorSet: VkDescriptorSet, descriptorUpdateTemplate: VkDescriptorUpdateTemplate, pData: rawptr) -> void
PFN_vkUpdateDescriptorSetWithTemplateKHR                              :: alias fn(device: VkDevice, descriptorSet: VkDescriptorSet, descriptorUpdateTemplate: VkDescriptorUpdateTemplate, pData: rawptr) -> void
PFN_vkUpdateVideoSessionParametersKHR                                 :: alias fn(device: VkDevice, videoSessionParameters: VkVideoSessionParametersKHR, pUpdateInfo: ptr[VkVideoSessionParametersUpdateInfoKHR]) -> VkResult
PFN_vkVoidFunction                                                    :: alias fn() -> void
PFN_vkWaitForFences                                                   :: alias fn(device: VkDevice, fenceCount: u32, pFences: ptr[VkFence], waitAll: b32, timeout: u64) -> VkResult
PFN_vkWaitForPresentKHR                                               :: alias fn(device: VkDevice, swapchain: VkSwapchainKHR, presentId: u64, timeout: u64) -> VkResult
PFN_vkWaitSemaphores                                                  :: alias fn(device: VkDevice, pWaitInfo: ptr[VkSemaphoreWaitInfo], timeout: u64) -> VkResult
PFN_vkWaitSemaphoresKHR                                               :: alias fn(device: VkDevice, pWaitInfo: ptr[VkSemaphoreWaitInfo], timeout: u64) -> VkResult
PFN_vkWriteAccelerationStructuresPropertiesKHR                        :: alias fn(device: VkDevice, accelerationStructureCount: u32, pAccelerationStructures: ptr[VkAccelerationStructureKHR], queryType: VkQueryType, dataSize: uint, pData: rawptr, stride: uint) -> VkResult
PFN_vkWriteMicromapsPropertiesEXT                                     :: alias fn(device: VkDevice, micromapCount: u32, pMicromaps: ptr[VkMicromapEXT], queryType: VkQueryType, dataSize: uint, pData: rawptr, stride: uint) -> VkResult

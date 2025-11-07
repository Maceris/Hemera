package vulkan

//TODO(ches) check these over

VkExtent2D :: struct {
    width : u32,
    height : u32,
}

VkExtent3D :: struct {
    width : u32,
    height : u32,
    depth : u32,
}

VkOffset2D :: struct {
    x : i32,
    y : i32,
}

VkOffset3D :: struct {
    x : i32,
    y : i32,
    z : i32,
}

VkRect2D :: struct {
    offset : VkOffset2D,
    extent : VkExtent2D,
}

VkBaseInStructure :: struct {
    sType : VkStructureType,
    pNext : ptr[VkBaseInStructure],
}

VkBaseOutStructure :: struct {
    sType : VkStructureType,
    pNext : ptr[VkBaseOutStructure],
}

VkBufferMemoryBarrier :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    srcAccessMask : VkAccessFlags,
    dstAccessMask : VkAccessFlags,
    srcQueueFamilyIndex : u32,
    dstQueueFamilyIndex : u32,
    buffer : VkBuffer,
    offset : VkDeviceSize,
    size : VkDeviceSize,
}

VkDispatchIndirectCommand :: struct {
    x : u32,
    y : u32,
    z : u32,
}

VkDrawIndexedIndirectCommand :: struct {
    indexCount : u32,
    instanceCount : u32,
    firstIndex : u32,
    vertexOffset : i32,
    firstInstance : u32,
}

VkDrawIndirectCommand :: struct {
    vertexCount : u32,
    instanceCount : u32,
    firstVertex : u32,
    firstInstance : u32,
}

VkImageSubresourceRange :: struct {
    aspectMask : VkImageAspectFlags,
    baseMipLevel : u32,
    levelCount : u32,
    baseArrayLayer : u32,
    layerCount : u32,
}

VkImageMemoryBarrier :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    srcAccessMask : VkAccessFlags,
    dstAccessMask : VkAccessFlags,
    oldLayout : VkImageLayout,
    newLayout : VkImageLayout,
    srcQueueFamilyIndex : u32,
    dstQueueFamilyIndex : u32,
    image : VkImage,
    subresourceRange : VkImageSubresourceRange,
}

VkMemoryBarrier :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    srcAccessMask : VkAccessFlags,
    dstAccessMask : VkAccessFlags,
}

VkPipelineCacheHeaderVersionOne :: struct {
    headerSize : u32,
    headerVersion : VkPipelineCacheHeaderVersion,
    vendorID : u32,
    deviceID : u32,
    pipelineCacheUUID[VK_UUID_SIZE] : u8,
}

VkAllocationCallbacks :: struct {
    pUserData : rawptr,
    pfnAllocation : PFN_vkAllocationFunction,
    pfnReallocation : PFN_vkReallocationFunction,
    pfnFree : PFN_vkFreeFunction,
    pfnInternalAllocation : PFN_vkInternalAllocationNotification,
    pfnInternalFree : PFN_vkInternalFreeNotification,
}

VkApplicationInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pApplicationName : ptr[char],
    applicationVersion : u32,
    pEngineName : ptr[char],
    engineVersion : u32,
    apiVersion : u32,
}

VkFormatProperties :: struct {
    linearTilingFeatures : VkFormatFeatureFlags,
    optimalTilingFeatures : VkFormatFeatureFlags,
    bufferFeatures : VkFormatFeatureFlags,
}

VkImageFormatProperties :: struct {
    maxExtent : VkExtent3D,
    maxMipLevels : u32,
    maxArrayLayers : u32,
    sampleCounts : VkSampleCountFlags,
    maxResourceSize : VkDeviceSize,
}

VkInstanceCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkInstanceCreateFlags,
    pApplicationInfo : ptr[VkApplicationInfo],
    enabledLayerCount : u32,
    ppEnabledLayerNames : ptr[cstring],
    enabledExtensionCount : u32,
    ppEnabledExtensionNames : ptr[cstring],
}

VkMemoryHeap :: struct {
    size : VkDeviceSize,
    flags : VkMemoryHeapFlags,
}

VkMemoryType :: struct {
    propertyFlags : VkMemoryPropertyFlags,
    heapIndex : u32,
}

VkPhysicalDeviceFeatures :: struct {
    robustBufferAccess : VkBool32,
    fullDrawIndexUint32 : VkBool32,
    imageCubeArray : VkBool32,
    independentBlend : VkBool32,
    geometryShader : VkBool32,
    tessellationShader : VkBool32,
    sampleRateShading : VkBool32,
    dualSrcBlend : VkBool32,
    logicOp : VkBool32,
    multiDrawIndirect : VkBool32,
    drawIndirectFirstInstance : VkBool32,
    depthClamp : VkBool32,
    depthBiasClamp : VkBool32,
    fillModeNonSolid : VkBool32,
    depthBounds : VkBool32,
    wideLines : VkBool32,
    largePoints : VkBool32,
    alphaToOne : VkBool32,
    multiViewport : VkBool32,
    samplerAnisotropy : VkBool32,
    textureCompressionETC2 : VkBool32,
    textureCompressionASTC_LDR : VkBool32,
    textureCompressionBC : VkBool32,
    occlusionQueryPrecise : VkBool32,
    pipelineStatisticsQuery : VkBool32,
    vertexPipelineStoresAndAtomics : VkBool32,
    fragmentStoresAndAtomics : VkBool32,
    shaderTessellationAndGeometryPointSize : VkBool32,
    shaderImageGatherExtended : VkBool32,
    shaderStorageImageExtendedFormats : VkBool32,
    shaderStorageImageMultisample : VkBool32,
    shaderStorageImageReadWithoutFormat : VkBool32,
    shaderStorageImageWriteWithoutFormat : VkBool32,
    shaderUniformBufferArrayDynamicIndexing : VkBool32,
    shaderSampledImageArrayDynamicIndexing : VkBool32,
    shaderStorageBufferArrayDynamicIndexing : VkBool32,
    shaderStorageImageArrayDynamicIndexing : VkBool32,
    shaderClipDistance : VkBool32,
    shaderCullDistance : VkBool32,
    shaderFloat64 : VkBool32,
    shaderInt64 : VkBool32,
    shaderInt16 : VkBool32,
    shaderResourceResidency : VkBool32,
    shaderResourceMinLod : VkBool32,
    sparseBinding : VkBool32,
    sparseResidencyBuffer : VkBool32,
    sparseResidencyImage2D : VkBool32,
    sparseResidencyImage3D : VkBool32,
    sparseResidency2Samples : VkBool32,
    sparseResidency4Samples : VkBool32,
    sparseResidency8Samples : VkBool32,
    sparseResidency16Samples : VkBool32,
    sparseResidencyAliased : VkBool32,
    variableMultisampleRate : VkBool32,
    inheritedQueries : VkBool32,
}

VkPhysicalDeviceLimits :: struct {
    maxImageDimension1D : u32,
    maxImageDimension2D : u32,
    maxImageDimension3D : u32,
    maxImageDimensionCube : u32,
    maxImageArrayLayers : u32,
    maxTexelBufferElements : u32,
    maxUniformBufferRange : u32,
    maxStorageBufferRange : u32,
    maxPushConstantsSize : u32,
    maxMemoryAllocationCount : u32,
    maxSamplerAllocationCount : u32,
    bufferImageGranularity : VkDeviceSize,
    sparseAddressSpaceSize : VkDeviceSize,
    maxBoundDescriptorSets : u32,
    maxPerStageDescriptorSamplers : u32,
    maxPerStageDescriptorUniformBuffers : u32,
    maxPerStageDescriptorStorageBuffers : u32,
    maxPerStageDescriptorSampledImages : u32,
    maxPerStageDescriptorStorageImages : u32,
    maxPerStageDescriptorInputAttachments : u32,
    maxPerStageResources : u32,
    maxDescriptorSetSamplers : u32,
    maxDescriptorSetUniformBuffers : u32,
    maxDescriptorSetUniformBuffersDynamic : u32,
    maxDescriptorSetStorageBuffers : u32,
    maxDescriptorSetStorageBuffersDynamic : u32,
    maxDescriptorSetSampledImages : u32,
    maxDescriptorSetStorageImages : u32,
    maxDescriptorSetInputAttachments : u32,
    maxVertexInputAttributes : u32,
    maxVertexInputBindings : u32,
    maxVertexInputAttributeOffset : u32,
    maxVertexInputBindingStride : u32,
    maxVertexOutputComponents : u32,
    maxTessellationGenerationLevel : u32,
    maxTessellationPatchSize : u32,
    maxTessellationControlPerVertexInputComponents : u32,
    maxTessellationControlPerVertexOutputComponents : u32,
    maxTessellationControlPerPatchOutputComponents : u32,
    maxTessellationControlTotalOutputComponents : u32,
    maxTessellationEvaluationInputComponents : u32,
    maxTessellationEvaluationOutputComponents : u32,
    maxGeometryShaderInvocations : u32,
    maxGeometryInputComponents : u32,
    maxGeometryOutputComponents : u32,
    maxGeometryOutputVertices : u32,
    maxGeometryTotalOutputComponents : u32,
    maxFragmentInputComponents : u32,
    maxFragmentOutputAttachments : u32,
    maxFragmentDualSrcAttachments : u32,
    maxFragmentCombinedOutputResources : u32,
    maxComputeSharedMemorySize : u32,
    maxComputeWorkGroupCount[3] : u32,
    maxComputeWorkGroupInvocations : u32,
    maxComputeWorkGroupSize[3] : u32,
    subPixelPrecisionBits : u32,
    subTexelPrecisionBits : u32,
    mipmapPrecisionBits : u32,
    maxDrawIndexedIndexValue : u32,
    maxDrawIndirectCount : u32,
    maxSamplerLodBias : f32,
    maxSamplerAnisotropy : f32,
    maxViewports : u32,
    maxViewportDimensions[2] : u32,
    viewportBoundsRange : f32[2],
    viewportSubPixelBits : u32,
    minMemoryMapAlignment : size_t,
    minTexelBufferOffsetAlignment : VkDeviceSize,
    minUniformBufferOffsetAlignment : VkDeviceSize,
    minStorageBufferOffsetAlignment : VkDeviceSize,
    minTexelOffset : i32,
    maxTexelOffset : u32,
    minTexelGatherOffset : i32,
    maxTexelGatherOffset : u32,
    minInterpolationOffset : f32,
    maxInterpolationOffset : f32,
    subPixelInterpolationOffsetBits : u32,
    maxFramebufferWidth : u32,
    maxFramebufferHeight : u32,
    maxFramebufferLayers : u32,
    framebufferColorSampleCounts : VkSampleCountFlags,
    framebufferDepthSampleCounts : VkSampleCountFlags,
    framebufferStencilSampleCounts : VkSampleCountFlags,
    framebufferNoAttachmentsSampleCounts : VkSampleCountFlags,
    maxColorAttachments : u32,
    sampledImageColorSampleCounts : VkSampleCountFlags,
    sampledImageIntegerSampleCounts : VkSampleCountFlags,
    sampledImageDepthSampleCounts : VkSampleCountFlags,
    sampledImageStencilSampleCounts : VkSampleCountFlags,
    storageImageSampleCounts : VkSampleCountFlags,
    maxSampleMaskWords : u32,
    timestampComputeAndGraphics : VkBool32,
    timestampPeriod : f32,
    maxClipDistances : u32,
    maxCullDistances : u32,
    maxCombinedClipAndCullDistances : u32,
    discreteQueuePriorities : u32,
    pointSizeRange : f32[2],
    lineWidthRange : f32[2],
    pointSizeGranularity : f32,
    lineWidthGranularity : f32,
    strictLines : VkBool32,
    standardSampleLocations : VkBool32,
    optimalBufferCopyOffsetAlignment : VkDeviceSize,
    optimalBufferCopyRowPitchAlignment : VkDeviceSize,
    nonCoherentAtomSize : VkDeviceSize,
}

VkPhysicalDeviceMemoryProperties :: struct {
    memoryTypeCount : u32,
    memoryTypes : VkMemoryType[VK_MAX_MEMORY_TYPES],
    memoryHeapCount : u32,
    memoryHeaps : VkMemoryHeap[VK_MAX_MEMORY_HEAPS],
}

VkPhysicalDeviceSparseProperties :: struct {
    residencyStandard2DBlockShape : VkBool32,
    residencyStandard2DMultisampleBlockShape : VkBool32,
    residencyStandard3DBlockShape : VkBool32,
    residencyAlignedMipSize : VkBool32,
    residencyNonResidentStrict : VkBool32,
}

VkPhysicalDeviceProperties :: struct {
    apiVersion : u32,
    driverVersion : u32,
    vendorID : u32,
    deviceID : u32,
    deviceType : VkPhysicalDeviceType,
    deviceName : char[VK_MAX_PHYSICAL_DEVICE_NAME_SIZE],
    pipelineCacheUUID[VK_UUID_SIZE] : u8,
    limits : VkPhysicalDeviceLimits,
    sparseProperties : VkPhysicalDeviceSparseProperties,
}

VkQueueFamilyProperties :: struct {
    queueFlags : VkQueueFlags,
    queueCount : u32,
    timestampValidBits : u32,
    minImageTransferGranularity : VkExtent3D,
}

VkDeviceQueueCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkDeviceQueueCreateFlags,
    queueFamilyIndex : u32,
    queueCount : u32,
    pQueuePriorities : ptr[f32],
}

VkDeviceCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkDeviceCreateFlags,
    queueCreateInfoCount : u32,
    pQueueCreateInfos : ptr[VkDeviceQueueCreateInfo],
    enabledLayerCount : u32,
    ppEnabledLayerNames : ptr[cstring],
    enabledExtensionCount : u32,
    ppEnabledExtensionNames : ptr[cstring],
    pEnabledFeatures : ptr[VkPhysicalDeviceFeatures],
}

VkExtensionProperties :: struct {
    extensionName : char[VK_MAX_EXTENSION_NAME_SIZE],
    specVersion : u32,
}

VkLayerProperties :: struct {
    layerName : char[VK_MAX_EXTENSION_NAME_SIZE],
    specVersion : u32,
    implementationVersion : u32,
    description : char[VK_MAX_DESCRIPTION_SIZE],
}

VkSubmitInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    waitSemaphoreCount : u32,
    pWaitSemaphores : ptr[VkSemaphore],
    pWaitDstStageMask : ptr[VkPipelineStageFlags],
    commandBufferCount : u32,
    pCommandBuffers : ptr[VkCommandBuffer],
    signalSemaphoreCount : u32,
    pSignalSemaphores : ptr[VkSemaphore],
}

VkMappedMemoryRange :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    memory : VkDeviceMemory,
    offset : VkDeviceSize,
    size : VkDeviceSize,
}

VkMemoryAllocateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    allocationSize : VkDeviceSize,
    memoryTypeIndex : u32,
}

VkMemoryRequirements :: struct {
    size : VkDeviceSize,
    alignment : VkDeviceSize,
    memoryTypeBits : u32,
}

VkSparseMemoryBind :: struct {
    resourceOffset : VkDeviceSize,
    size : VkDeviceSize,
    memory : VkDeviceMemory,
    memoryOffset : VkDeviceSize,
    flags : VkSparseMemoryBindFlags,
}

VkSparseBufferMemoryBindInfo :: struct {
    buffer : VkBuffer,
    bindCount : u32,
    pBinds : ptr[VkSparseMemoryBind],
}

VkSparseImageOpaqueMemoryBindInfo :: struct {
    image : VkImage,
    bindCount : u32,
    pBinds : ptr[VkSparseMemoryBind],
}

VkImageSubresource :: struct {
    aspectMask : VkImageAspectFlags,
    mipLevel : u32,
    arrayLayer : u32,
}

VkSparseImageMemoryBind :: struct {
    subresource : VkImageSubresource,
    offset : VkOffset3D,
    extent : VkExtent3D,
    memory : VkDeviceMemory,
    memoryOffset : VkDeviceSize,
    flags : VkSparseMemoryBindFlags,
}

VkSparseImageMemoryBindInfo :: struct {
    image : VkImage,
    bindCount : u32,
    pBinds : ptr[VkSparseImageMemoryBind],
}

VkBindSparseInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    waitSemaphoreCount : u32,
    pWaitSemaphores : ptr[VkSemaphore],
    bufferBindCount : u32,
    pBufferBinds : ptr[VkSparseBufferMemoryBindInfo],
    imageOpaqueBindCount : u32,
    pImageOpaqueBinds : ptr[VkSparseImageOpaqueMemoryBindInfo],
    imageBindCount : u32,
    pImageBinds : ptr[VkSparseImageMemoryBindInfo],
    signalSemaphoreCount : u32,
    pSignalSemaphores : ptr[VkSemaphore],
}

VkSparseImageFormatProperties :: struct {
    aspectMask : VkImageAspectFlags,
    imageGranularity : VkExtent3D,
    flags : VkSparseImageFormatFlags,
}

VkSparseImageMemoryRequirements :: struct {
    formatProperties : VkSparseImageFormatProperties,
    imageMipTailFirstLod : u32,
    imageMipTailSize : VkDeviceSize,
    imageMipTailOffset : VkDeviceSize,
    imageMipTailStride : VkDeviceSize,
}

VkFenceCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkFenceCreateFlags,
}

VkSemaphoreCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkSemaphoreCreateFlags,
}

VkEventCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkEventCreateFlags,
}

VkQueryPoolCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkQueryPoolCreateFlags,
    queryType : VkQueryType,
    queryCount : u32,
    pipelineStatistics : VkQueryPipelineStatisticFlags,
}

VkBufferCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkBufferCreateFlags,
    size : VkDeviceSize,
    usage : VkBufferUsageFlags,
    sharingMode : VkSharingMode,
    queueFamilyIndexCount : u32,
    pQueueFamilyIndices : ptr[u32],
}

VkBufferViewCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkBufferViewCreateFlags,
    buffer : VkBuffer,
    format : VkFormat,
    offset : VkDeviceSize,
    range : VkDeviceSize,
}

VkImageCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkImageCreateFlags,
    imageType : VkImageType,
    format : VkFormat,
    extent : VkExtent3D,
    mipLevels : u32,
    arrayLayers : u32,
    samples : VkSampleCountFlagBits,
    tiling : VkImageTiling,
    usage : VkImageUsageFlags,
    sharingMode : VkSharingMode,
    queueFamilyIndexCount : u32,
    pQueueFamilyIndices : ptr[u32],
    initialLayout : VkImageLayout,
}

VkSubresourceLayout :: struct {
    offset : VkDeviceSize,
    size : VkDeviceSize,
    rowPitch : VkDeviceSize,
    arrayPitch : VkDeviceSize,
    depthPitch : VkDeviceSize,
}

VkComponentMapping :: struct {
    r : VkComponentSwizzle,
    g : VkComponentSwizzle,
    b : VkComponentSwizzle,
    a : VkComponentSwizzle,
}

VkImageViewCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkImageViewCreateFlags,
    image : VkImage,
    viewType : VkImageViewType,
    format : VkFormat,
    components : VkComponentMapping,
    subresourceRange : VkImageSubresourceRange,
}

VkShaderModuleCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkShaderModuleCreateFlags,
    codeSize : size_t,
    pCode : ptr[u32],
}

VkPipelineCacheCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineCacheCreateFlags,
    initialDataSize : size_t,
    pInitialData : rawptr,
}

VkSpecializationMapEntry :: struct {
    constantID : u32,
    offset : u32,
    size : size_t,
}

VkSpecializationInfo :: struct {
    mapEntryCount : u32,
    pMapEntries : ptr[VkSpecializationMapEntry],
    dataSize : size_t,
    pData : rawptr,
}

VkPipelineShaderStageCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineShaderStageCreateFlags,
    stage : VkShaderStageFlagBits,
    module : VkShaderModule,
    pName : ptr[char],
    pSpecializationInfo : ptr[VkSpecializationInfo],
}

VkComputePipelineCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineCreateFlags,
    stage : VkPipelineShaderStageCreateInfo,
    layout : VkPipelineLayout,
    basePipelineHandle : VkPipeline,
    basePipelineIndex : i32,
}

VkVertexInputBindingDescription :: struct {
    binding : u32,
    stride : u32,
    inputRate : VkVertexInputRate,
}

VkVertexInputAttributeDescription :: struct {
    location : u32,
    binding : u32,
    format : VkFormat,
    offset : u32,
}

VkPipelineVertexInputStateCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineVertexInputStateCreateFlags,
    vertexBindingDescriptionCount : u32,
    pVertexBindingDescriptions : ptr[VkVertexInputBindingDescription],
    vertexAttributeDescriptionCount : u32,
    pVertexAttributeDescriptions : ptr[VkVertexInputAttributeDescription],
}

VkPipelineInputAssemblyStateCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineInputAssemblyStateCreateFlags,
    topology : VkPrimitiveTopology,
    primitiveRestartEnable : VkBool32,
}

VkPipelineTessellationStateCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineTessellationStateCreateFlags,
    patchControlPoints : u32,
}

VkViewport :: struct {
    x : f32,
    y : f32,
    width : f32,
    height : f32,
    minDepth : f32,
    maxDepth : f32,
}

VkPipelineViewportStateCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineViewportStateCreateFlags,
    viewportCount : u32,
    pViewports : ptr[VkViewport],
    scissorCount : u32,
    pScissors : ptr[VkRect2D],
}

VkPipelineRasterizationStateCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineRasterizationStateCreateFlags,
    depthClampEnable : VkBool32,
    rasterizerDiscardEnable : VkBool32,
    polygonMode : VkPolygonMode,
    cullMode : VkCullModeFlags,
    frontFace : VkFrontFace,
    depthBiasEnable : VkBool32,
    depthBiasConstantFactor : f32,
    depthBiasClamp : f32,
    depthBiasSlopeFactor : f32,
    lineWidth : f32,
}

VkPipelineMultisampleStateCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineMultisampleStateCreateFlags,
    rasterizationSamples : VkSampleCountFlagBits,
    sampleShadingEnable : VkBool32,
    minSampleShading : f32,
    pSampleMask : ptr[VkSampleMask],
    alphaToCoverageEnable : VkBool32,
    alphaToOneEnable : VkBool32,
}

VkStencilOpState :: struct {
    failOp : VkStencilOp,
    passOp : VkStencilOp,
    depthFailOp : VkStencilOp,
    compareOp : VkCompareOp,
    compareMask : u32,
    writeMask : u32,
    reference : u32,
}

VkPipelineDepthStencilStateCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineDepthStencilStateCreateFlags,
    depthTestEnable : VkBool32,
    depthWriteEnable : VkBool32,
    depthCompareOp : VkCompareOp,
    depthBoundsTestEnable : VkBool32,
    stencilTestEnable : VkBool32,
    front : VkStencilOpState,
    back : VkStencilOpState,
    minDepthBounds : f32,
    maxDepthBounds : f32,
}

VkPipelineColorBlendAttachmentState :: struct {
    blendEnable : VkBool32,
    srcColorBlendFactor : VkBlendFactor,
    dstColorBlendFactor : VkBlendFactor,
    colorBlendOp : VkBlendOp,
    srcAlphaBlendFactor : VkBlendFactor,
    dstAlphaBlendFactor : VkBlendFactor,
    alphaBlendOp : VkBlendOp,
    colorWriteMask : VkColorComponentFlags,
}

VkPipelineColorBlendStateCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineColorBlendStateCreateFlags,
    logicOpEnable : VkBool32,
    logicOp : VkLogicOp,
    attachmentCount : u32,
    pAttachments : ptr[VkPipelineColorBlendAttachmentState],
    blendConstants : f32[4],
}

VkPipelineDynamicStateCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineDynamicStateCreateFlags,
    dynamicStateCount : u32,
    pDynamicStates : ptr[VkDynamicState],
}

VkGraphicsPipelineCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineCreateFlags,
    stageCount : u32,
    pStages : ptr[VkPipelineShaderStageCreateInfo],
    pVertexInputState : ptr[VkPipelineVertexInputStateCreateInfo],
    pInputAssemblyState : ptr[VkPipelineInputAssemblyStateCreateInfo],
    pTessellationState : ptr[VkPipelineTessellationStateCreateInfo],
    pViewportState : ptr[VkPipelineViewportStateCreateInfo],
    pRasterizationState : ptr[VkPipelineRasterizationStateCreateInfo],
    pMultisampleState : ptr[VkPipelineMultisampleStateCreateInfo],
    pDepthStencilState : ptr[VkPipelineDepthStencilStateCreateInfo],
    pColorBlendState : ptr[VkPipelineColorBlendStateCreateInfo],
    pDynamicState : ptr[VkPipelineDynamicStateCreateInfo],
    layout : VkPipelineLayout,
    renderPass : VkRenderPass,
    subpass : u32,
    basePipelineHandle : VkPipeline,
    basePipelineIndex : i32,
}

VkPushConstantRange :: struct {
    stageFlags : VkShaderStageFlags,
    offset : u32,
    size : u32,
}

VkPipelineLayoutCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineLayoutCreateFlags,
    setLayoutCount : u32,
    pSetLayouts : ptr[VkDescriptorSetLayout],
    pushConstantRangeCount : u32,
    pPushConstantRanges : ptr[VkPushConstantRange],
}

VkSamplerCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkSamplerCreateFlags,
    magFilter : VkFilter,
    minFilter : VkFilter,
    mipmapMode : VkSamplerMipmapMode,
    addressModeU : VkSamplerAddressMode,
    addressModeV : VkSamplerAddressMode,
    addressModeW : VkSamplerAddressMode,
    mipLodBias : f32,
    anisotropyEnable : VkBool32,
    maxAnisotropy : f32,
    compareEnable : VkBool32,
    compareOp : VkCompareOp,
    minLod : f32,
    maxLod : f32,
    borderColor : VkBorderColor,
    unnormalizedCoordinates : VkBool32,
}

VkCopyDescriptorSet :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    srcSet : VkDescriptorSet,
    srcBinding : u32,
    srcArrayElement : u32,
    dstSet : VkDescriptorSet,
    dstBinding : u32,
    dstArrayElement : u32,
    descriptorCount : u32,
}

VkDescriptorBufferInfo :: struct {
    buffer : VkBuffer,
    offset : VkDeviceSize,
    range : VkDeviceSize,
}

VkDescriptorImageInfo :: struct {
    sampler : VkSampler,
    imageView : VkImageView,
    imageLayout : VkImageLayout,
}

VkDescriptorPoolSize :: struct {
    type : VkDescriptorType,
    descriptorCount : u32,
}

VkDescriptorPoolCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkDescriptorPoolCreateFlags,
    maxSets : u32,
    poolSizeCount : u32,
    pPoolSizes : ptr[VkDescriptorPoolSize],
}

VkDescriptorSetAllocateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    descriptorPool : VkDescriptorPool,
    descriptorSetCount : u32,
    pSetLayouts : ptr[VkDescriptorSetLayout],
}

VkDescriptorSetLayoutBinding :: struct {
    binding : u32,
    descriptorType : VkDescriptorType,
    descriptorCount : u32,
    stageFlags : VkShaderStageFlags,
    pImmutableSamplers : ptr[VkSampler],
}

VkDescriptorSetLayoutCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkDescriptorSetLayoutCreateFlags,
    bindingCount : u32,
    pBindings : ptr[VkDescriptorSetLayoutBinding],
}

VkWriteDescriptorSet :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    dstSet : VkDescriptorSet,
    dstBinding : u32,
    dstArrayElement : u32,
    descriptorCount : u32,
    descriptorType : VkDescriptorType,
    pImageInfo : ptr[VkDescriptorImageInfo],
    pBufferInfo : ptr[VkDescriptorBufferInfo],
    pTexelBufferView : ptr[VkBufferView],
}

VkAttachmentDescription :: struct {
    flags : VkAttachmentDescriptionFlags,
    format : VkFormat,
    samples : VkSampleCountFlagBits,
    loadOp : VkAttachmentLoadOp,
    storeOp : VkAttachmentStoreOp,
    stencilLoadOp : VkAttachmentLoadOp,
    stencilStoreOp : VkAttachmentStoreOp,
    initialLayout : VkImageLayout,
    finalLayout : VkImageLayout,
}

VkAttachmentReference :: struct {
    attachment : u32,
    layout : VkImageLayout,
}

VkFramebufferCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkFramebufferCreateFlags,
    renderPass : VkRenderPass,
    attachmentCount : u32,
    pAttachments : ptr[VkImageView],
    width : u32,
    height : u32,
    layers : u32,
}

VkSubpassDescription :: struct {
    flags : VkSubpassDescriptionFlags,
    pipelineBindPoint : VkPipelineBindPoint,
    inputAttachmentCount : u32,
    pInputAttachments : ptr[VkAttachmentReference],
    colorAttachmentCount : u32,
    pColorAttachments : ptr[VkAttachmentReference],
    pResolveAttachments : ptr[VkAttachmentReference],
    pDepthStencilAttachment : ptr[VkAttachmentReference],
    preserveAttachmentCount : u32,
    pPreserveAttachments : ptr[u32],
}

VkSubpassDependency :: struct {
    srcSubpass : u32,
    dstSubpass : u32,
    srcStageMask : VkPipelineStageFlags,
    dstStageMask : VkPipelineStageFlags,
    srcAccessMask : VkAccessFlags,
    dstAccessMask : VkAccessFlags,
    dependencyFlags : VkDependencyFlags,
}

VkRenderPassCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkRenderPassCreateFlags,
    attachmentCount : u32,
    pAttachments : ptr[VkAttachmentDescription],
    subpassCount : u32,
    pSubpasses : ptr[VkSubpassDescription],
    dependencyCount : u32,
    pDependencies : ptr[VkSubpassDependency],
}

VkCommandPoolCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkCommandPoolCreateFlags,
    queueFamilyIndex : u32,
}

VkCommandBufferAllocateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    commandPool : VkCommandPool,
    level : VkCommandBufferLevel,
    commandBufferCount : u32,
}

VkCommandBufferInheritanceInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    renderPass : VkRenderPass,
    subpass : u32,
    framebuffer : VkFramebuffer,
    occlusionQueryEnable : VkBool32,
    queryFlags : VkQueryControlFlags,
    pipelineStatistics : VkQueryPipelineStatisticFlags,
}

VkCommandBufferBeginInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkCommandBufferUsageFlags,
    pInheritanceInfo : ptr[VkCommandBufferInheritanceInfo],
}

VkBufferCopy :: struct {
    srcOffset : VkDeviceSize,
    dstOffset : VkDeviceSize,
    size : VkDeviceSize,
}

VkImageSubresourceLayers :: struct {
    aspectMask : VkImageAspectFlags,
    mipLevel : u32,
    baseArrayLayer : u32,
    layerCount : u32,
}

VkBufferImageCopy :: struct {
    bufferOffset : VkDeviceSize,
    bufferRowLength : u32,
    bufferImageHeight : u32,
    imageSubresource : VkImageSubresourceLayers,
    imageOffset : VkOffset3D,
    imageExtent : VkExtent3D,
}

VkClearDepthStencilValue :: struct {
    depth : f32,
    stencil : u32,
}

VkClearAttachment :: struct {
    aspectMask : VkImageAspectFlags,
    colorAttachment : u32,
    clearValue : VkClearValue,
}

VkClearRect :: struct {
    rect : VkRect2D,
    baseArrayLayer : u32,
    layerCount : u32,
}

VkImageBlit :: struct {
    srcSubresource : VkImageSubresourceLayers,
    srcOffsets : VkOffset3D[2],
    dstSubresource : VkImageSubresourceLayers,
    dstOffsets : VkOffset3D[2],
}

VkImageCopy :: struct {
    srcSubresource : VkImageSubresourceLayers,
    srcOffset : VkOffset3D,
    dstSubresource : VkImageSubresourceLayers,
    dstOffset : VkOffset3D,
    extent : VkExtent3D,
}

VkImageResolve :: struct {
    srcSubresource : VkImageSubresourceLayers,
    srcOffset : VkOffset3D,
    dstSubresource : VkImageSubresourceLayers,
    dstOffset : VkOffset3D,
    extent : VkExtent3D,
}

VkRenderPassBeginInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    renderPass : VkRenderPass,
    framebuffer : VkFramebuffer,
    renderArea : VkRect2D,
    clearValueCount : u32,
    pClearValues : ptr[VkClearValue],
}

VkPhysicalDeviceSubgroupProperties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    subgroupSize : u32,
    supportedStages : VkShaderStageFlags,
    supportedOperations : VkSubgroupFeatureFlags,
    quadOperationsInAllStages : VkBool32,
}

VkBindBufferMemoryInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    buffer : VkBuffer,
    memory : VkDeviceMemory,
    memoryOffset : VkDeviceSize,
}

VkBindImageMemoryInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    image : VkImage,
    memory : VkDeviceMemory,
    memoryOffset : VkDeviceSize,
}

VkPhysicalDevice16BitStorageFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    storageBuffer16BitAccess : VkBool32,
    uniformAndStorageBuffer16BitAccess : VkBool32,
    storagePushConstant16 : VkBool32,
    storageInputOutput16 : VkBool32,
}

VkMemoryDedicatedRequirements :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    prefersDedicatedAllocation : VkBool32,
    requiresDedicatedAllocation : VkBool32,
}

VkMemoryDedicatedAllocateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    image : VkImage,
    buffer : VkBuffer,
}

VkMemoryAllocateFlagsInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkMemoryAllocateFlags,
    deviceMask : u32,
}

VkDeviceGroupRenderPassBeginInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    deviceMask : u32,
    deviceRenderAreaCount : u32,
    pDeviceRenderAreas : ptr[VkRect2D],
}

VkDeviceGroupCommandBufferBeginInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    deviceMask : u32,
}

VkDeviceGroupSubmitInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    waitSemaphoreCount : u32,
    pWaitSemaphoreDeviceIndices : ptr[u32],
    commandBufferCount : u32,
    pCommandBufferDeviceMasks : ptr[u32],
    signalSemaphoreCount : u32,
    pSignalSemaphoreDeviceIndices : ptr[u32],
}

VkDeviceGroupBindSparseInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    resourceDeviceIndex : u32,
    memoryDeviceIndex : u32,
}

VkBindBufferMemoryDeviceGroupInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    deviceIndexCount : u32,
    pDeviceIndices : ptr[u32],
}

VkBindImageMemoryDeviceGroupInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    deviceIndexCount : u32,
    pDeviceIndices : ptr[u32],
    splitInstanceBindRegionCount : u32,
    pSplitInstanceBindRegions : ptr[VkRect2D],
}

VkPhysicalDeviceGroupProperties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    physicalDeviceCount : u32,
    physicalDevices : VkPhysicalDevice[VK_MAX_DEVICE_GROUP_SIZE],
    subsetAllocation : VkBool32,
}

VkDeviceGroupDeviceCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    physicalDeviceCount : u32,
    pPhysicalDevices : ptr[VkPhysicalDevice],
}

VkBufferMemoryRequirementsInfo2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    buffer : VkBuffer,
}

VkImageMemoryRequirementsInfo2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    image : VkImage,
}

VkImageSparseMemoryRequirementsInfo2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    image : VkImage,
}

VkMemoryRequirements2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    memoryRequirements : VkMemoryRequirements,
}

VkSparseImageMemoryRequirements2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    memoryRequirements : VkSparseImageMemoryRequirements,
}

VkPhysicalDeviceFeatures2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    features : VkPhysicalDeviceFeatures,
}

VkPhysicalDeviceProperties2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    properties : VkPhysicalDeviceProperties,
}

VkFormatProperties2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    formatProperties : VkFormatProperties,
}

VkImageFormatProperties2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    imageFormatProperties : VkImageFormatProperties,
}

VkPhysicalDeviceImageFormatInfo2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    format : VkFormat,
    type : VkImageType,
    tiling : VkImageTiling,
    usage : VkImageUsageFlags,
    flags : VkImageCreateFlags,
}

VkQueueFamilyProperties2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    queueFamilyProperties : VkQueueFamilyProperties,
}

VkPhysicalDeviceMemoryProperties2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    memoryProperties : VkPhysicalDeviceMemoryProperties,
}

VkSparseImageFormatProperties2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    properties : VkSparseImageFormatProperties,
}

VkPhysicalDeviceSparseImageFormatInfo2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    format : VkFormat,
    type : VkImageType,
    samples : VkSampleCountFlagBits,
    usage : VkImageUsageFlags,
    tiling : VkImageTiling,
}

VkPhysicalDevicePointClippingProperties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pointClippingBehavior : VkPointClippingBehavior,
}

VkInputAttachmentAspectReference :: struct {
    subpass : u32,
    inputAttachmentIndex : u32,
    aspectMask : VkImageAspectFlags,
}

VkRenderPassInputAttachmentAspectCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    aspectReferenceCount : u32,
    pAspectReferences : ptr[VkInputAttachmentAspectReference],
}

VkImageViewUsageCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    usage : VkImageUsageFlags,
}

VkPipelineTessellationDomainOriginStateCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    domainOrigin : VkTessellationDomainOrigin,
}

VkRenderPassMultiviewCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    subpassCount : u32,
    pViewMasks : ptr[u32],
    dependencyCount : u32,
    pViewOffsets : ptr[i32],
    correlationMaskCount : u32,
    pCorrelationMasks : ptr[u32],
}

VkPhysicalDeviceMultiviewFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    multiview : VkBool32,
    multiviewGeometryShader : VkBool32,
    multiviewTessellationShader : VkBool32,
}

VkPhysicalDeviceMultiviewProperties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxMultiviewViewCount : u32,
    maxMultiviewInstanceIndex : u32,
}

VkPhysicalDeviceVariablePointersFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    variablePointersStorageBuffer : VkBool32,
    variablePointers : VkBool32,
}

VkPhysicalDeviceProtectedMemoryFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    protectedMemory : VkBool32,
}

VkPhysicalDeviceProtectedMemoryProperties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    protectedNoFault : VkBool32,
}

VkDeviceQueueInfo2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkDeviceQueueCreateFlags,
    queueFamilyIndex : u32,
    queueIndex : u32,
}

VkProtectedSubmitInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    protectedSubmit : VkBool32,
}

VkSamplerYcbcrConversionCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    format : VkFormat,
    ycbcrModel : VkSamplerYcbcrModelConversion,
    ycbcrRange : VkSamplerYcbcrRange,
    components : VkComponentMapping,
    xChromaOffset : VkChromaLocation,
    yChromaOffset : VkChromaLocation,
    chromaFilter : VkFilter,
    forceExplicitReconstruction : VkBool32,
}

VkSamplerYcbcrConversionInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    conversion : VkSamplerYcbcrConversion,
}

VkBindImagePlaneMemoryInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    planeAspect : VkImageAspectFlagBits,
}

VkImagePlaneMemoryRequirementsInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    planeAspect : VkImageAspectFlagBits,
}

VkPhysicalDeviceSamplerYcbcrConversionFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    samplerYcbcrConversion : VkBool32,
}

VkSamplerYcbcrConversionImageFormatProperties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    combinedImageSamplerDescriptorCount : u32,
}

VkDescriptorUpdateTemplateEntry :: struct {
    dstBinding : u32,
    dstArrayElement : u32,
    descriptorCount : u32,
    descriptorType : VkDescriptorType,
    offset : size_t,
    stride : size_t,
}

VkDescriptorUpdateTemplateCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkDescriptorUpdateTemplateCreateFlags,
    descriptorUpdateEntryCount : u32,
    pDescriptorUpdateEntries : ptr[VkDescriptorUpdateTemplateEntry],
    templateType : VkDescriptorUpdateTemplateType,
    descriptorSetLayout : VkDescriptorSetLayout,
    pipelineBindPoint : VkPipelineBindPoint,
    pipelineLayout : VkPipelineLayout,
    set : u32,
}

VkExternalMemoryProperties :: struct {
    externalMemoryFeatures : VkExternalMemoryFeatureFlags,
    exportFromImportedHandleTypes : VkExternalMemoryHandleTypeFlags,
    compatibleHandleTypes : VkExternalMemoryHandleTypeFlags,
}

VkPhysicalDeviceExternalImageFormatInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    handleType : VkExternalMemoryHandleTypeFlagBits,
}

VkExternalImageFormatProperties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    externalMemoryProperties : VkExternalMemoryProperties,
}

VkPhysicalDeviceExternalBufferInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkBufferCreateFlags,
    usage : VkBufferUsageFlags,
    handleType : VkExternalMemoryHandleTypeFlagBits,
}

VkExternalBufferProperties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    externalMemoryProperties : VkExternalMemoryProperties,
}

VkPhysicalDeviceIDProperties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    deviceUUID[VK_UUID_SIZE] : u8,
    driverUUID[VK_UUID_SIZE] : u8,
    deviceLUID[VK_LUID_SIZE] : u8,
    deviceNodeMask : u32,
    deviceLUIDValid : VkBool32,
}

VkExternalMemoryImageCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    handleTypes : VkExternalMemoryHandleTypeFlags,
}

VkExternalMemoryBufferCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    handleTypes : VkExternalMemoryHandleTypeFlags,
}

VkExportMemoryAllocateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    handleTypes : VkExternalMemoryHandleTypeFlags,
}

VkPhysicalDeviceExternalFenceInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    handleType : VkExternalFenceHandleTypeFlagBits,
}

VkExternalFenceProperties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    exportFromImportedHandleTypes : VkExternalFenceHandleTypeFlags,
    compatibleHandleTypes : VkExternalFenceHandleTypeFlags,
    externalFenceFeatures : VkExternalFenceFeatureFlags,
}

VkExportFenceCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    handleTypes : VkExternalFenceHandleTypeFlags,
}

VkExportSemaphoreCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    handleTypes : VkExternalSemaphoreHandleTypeFlags,
}

VkPhysicalDeviceExternalSemaphoreInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    handleType : VkExternalSemaphoreHandleTypeFlagBits,
}

VkExternalSemaphoreProperties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    exportFromImportedHandleTypes : VkExternalSemaphoreHandleTypeFlags,
    compatibleHandleTypes : VkExternalSemaphoreHandleTypeFlags,
    externalSemaphoreFeatures : VkExternalSemaphoreFeatureFlags,
}

VkPhysicalDeviceMaintenance3Properties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxPerSetDescriptors : u32,
    maxMemoryAllocationSize : VkDeviceSize,
}

VkDescriptorSetLayoutSupport :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    supported : VkBool32,
}

VkPhysicalDeviceShaderDrawParametersFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderDrawParameters : VkBool32,
}

VkPhysicalDeviceVulkan11Features :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    storageBuffer16BitAccess : VkBool32,
    uniformAndStorageBuffer16BitAccess : VkBool32,
    storagePushConstant16 : VkBool32,
    storageInputOutput16 : VkBool32,
    multiview : VkBool32,
    multiviewGeometryShader : VkBool32,
    multiviewTessellationShader : VkBool32,
    variablePointersStorageBuffer : VkBool32,
    variablePointers : VkBool32,
    protectedMemory : VkBool32,
    samplerYcbcrConversion : VkBool32,
    shaderDrawParameters : VkBool32,
}

VkPhysicalDeviceVulkan11Properties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    deviceUUID[VK_UUID_SIZE] : u8,
    driverUUID[VK_UUID_SIZE] : u8,
    deviceLUID[VK_LUID_SIZE] : u8,
    deviceNodeMask : u32,
    deviceLUIDValid : VkBool32,
    subgroupSize : u32,
    subgroupSupportedStages : VkShaderStageFlags,
    subgroupSupportedOperations : VkSubgroupFeatureFlags,
    subgroupQuadOperationsInAllStages : VkBool32,
    pointClippingBehavior : VkPointClippingBehavior,
    maxMultiviewViewCount : u32,
    maxMultiviewInstanceIndex : u32,
    protectedNoFault : VkBool32,
    maxPerSetDescriptors : u32,
    maxMemoryAllocationSize : VkDeviceSize,
}

VkPhysicalDeviceVulkan12Features :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    samplerMirrorClampToEdge : VkBool32,
    drawIndirectCount : VkBool32,
    storageBuffer8BitAccess : VkBool32,
    uniformAndStorageBuffer8BitAccess : VkBool32,
    storagePushConstant8 : VkBool32,
    shaderBufferInt64Atomics : VkBool32,
    shaderSharedInt64Atomics : VkBool32,
    shaderFloat16 : VkBool32,
    shaderInt8 : VkBool32,
    descriptorIndexing : VkBool32,
    shaderInputAttachmentArrayDynamicIndexing : VkBool32,
    shaderUniformTexelBufferArrayDynamicIndexing : VkBool32,
    shaderStorageTexelBufferArrayDynamicIndexing : VkBool32,
    shaderUniformBufferArrayNonUniformIndexing : VkBool32,
    shaderSampledImageArrayNonUniformIndexing : VkBool32,
    shaderStorageBufferArrayNonUniformIndexing : VkBool32,
    shaderStorageImageArrayNonUniformIndexing : VkBool32,
    shaderInputAttachmentArrayNonUniformIndexing : VkBool32,
    shaderUniformTexelBufferArrayNonUniformIndexing : VkBool32,
    shaderStorageTexelBufferArrayNonUniformIndexing : VkBool32,
    descriptorBindingUniformBufferUpdateAfterBind : VkBool32,
    descriptorBindingSampledImageUpdateAfterBind : VkBool32,
    descriptorBindingStorageImageUpdateAfterBind : VkBool32,
    descriptorBindingStorageBufferUpdateAfterBind : VkBool32,
    descriptorBindingUniformTexelBufferUpdateAfterBind : VkBool32,
    descriptorBindingStorageTexelBufferUpdateAfterBind : VkBool32,
    descriptorBindingUpdateUnusedWhilePending : VkBool32,
    descriptorBindingPartiallyBound : VkBool32,
    descriptorBindingVariableDescriptorCount : VkBool32,
    runtimeDescriptorArray : VkBool32,
    samplerFilterMinmax : VkBool32,
    scalarBlockLayout : VkBool32,
    imagelessFramebuffer : VkBool32,
    uniformBufferStandardLayout : VkBool32,
    shaderSubgroupExtendedTypes : VkBool32,
    separateDepthStencilLayouts : VkBool32,
    hostQueryReset : VkBool32,
    timelineSemaphore : VkBool32,
    bufferDeviceAddress : VkBool32,
    bufferDeviceAddressCaptureReplay : VkBool32,
    bufferDeviceAddressMultiDevice : VkBool32,
    vulkanMemoryModel : VkBool32,
    vulkanMemoryModelDeviceScope : VkBool32,
    vulkanMemoryModelAvailabilityVisibilityChains : VkBool32,
    shaderOutputViewportIndex : VkBool32,
    shaderOutputLayer : VkBool32,
    subgroupBroadcastDynamicId : VkBool32,
}

VkConformanceVersion :: struct {
    major : u8,
    minor : u8,
    subminor : u8,
    patch : u8,
}

VkPhysicalDeviceVulkan12Properties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    driverID : VkDriverId,
    driverName : char[VK_MAX_DRIVER_NAME_SIZE],
    driverInfo : char[VK_MAX_DRIVER_INFO_SIZE],
    conformanceVersion : VkConformanceVersion,
    denormBehaviorIndependence : VkShaderFloatControlsIndependence,
    roundingModeIndependence : VkShaderFloatControlsIndependence,
    shaderSignedZeroInfNanPreserveFloat16 : VkBool32,
    shaderSignedZeroInfNanPreserveFloat32 : VkBool32,
    shaderSignedZeroInfNanPreserveFloat64 : VkBool32,
    shaderDenormPreserveFloat16 : VkBool32,
    shaderDenormPreserveFloat32 : VkBool32,
    shaderDenormPreserveFloat64 : VkBool32,
    shaderDenormFlushToZeroFloat16 : VkBool32,
    shaderDenormFlushToZeroFloat32 : VkBool32,
    shaderDenormFlushToZeroFloat64 : VkBool32,
    shaderRoundingModeRTEFloat16 : VkBool32,
    shaderRoundingModeRTEFloat32 : VkBool32,
    shaderRoundingModeRTEFloat64 : VkBool32,
    shaderRoundingModeRTZFloat16 : VkBool32,
    shaderRoundingModeRTZFloat32 : VkBool32,
    shaderRoundingModeRTZFloat64 : VkBool32,
    maxUpdateAfterBindDescriptorsInAllPools : u32,
    shaderUniformBufferArrayNonUniformIndexingNative : VkBool32,
    shaderSampledImageArrayNonUniformIndexingNative : VkBool32,
    shaderStorageBufferArrayNonUniformIndexingNative : VkBool32,
    shaderStorageImageArrayNonUniformIndexingNative : VkBool32,
    shaderInputAttachmentArrayNonUniformIndexingNative : VkBool32,
    robustBufferAccessUpdateAfterBind : VkBool32,
    quadDivergentImplicitLod : VkBool32,
    maxPerStageDescriptorUpdateAfterBindSamplers : u32,
    maxPerStageDescriptorUpdateAfterBindUniformBuffers : u32,
    maxPerStageDescriptorUpdateAfterBindStorageBuffers : u32,
    maxPerStageDescriptorUpdateAfterBindSampledImages : u32,
    maxPerStageDescriptorUpdateAfterBindStorageImages : u32,
    maxPerStageDescriptorUpdateAfterBindInputAttachments : u32,
    maxPerStageUpdateAfterBindResources : u32,
    maxDescriptorSetUpdateAfterBindSamplers : u32,
    maxDescriptorSetUpdateAfterBindUniformBuffers : u32,
    maxDescriptorSetUpdateAfterBindUniformBuffersDynamic : u32,
    maxDescriptorSetUpdateAfterBindStorageBuffers : u32,
    maxDescriptorSetUpdateAfterBindStorageBuffersDynamic : u32,
    maxDescriptorSetUpdateAfterBindSampledImages : u32,
    maxDescriptorSetUpdateAfterBindStorageImages : u32,
    maxDescriptorSetUpdateAfterBindInputAttachments : u32,
    supportedDepthResolveModes : VkResolveModeFlags,
    supportedStencilResolveModes : VkResolveModeFlags,
    independentResolveNone : VkBool32,
    independentResolve : VkBool32,
    filterMinmaxSingleComponentFormats : VkBool32,
    filterMinmaxImageComponentMapping : VkBool32,
    maxTimelineSemaphoreValueDifference : u64,
    framebufferIntegerColorSampleCounts : VkSampleCountFlags,
}

VkImageFormatListCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    viewFormatCount : u32,
    pViewFormats : ptr[VkFormat],
}

VkAttachmentDescription2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkAttachmentDescriptionFlags,
    format : VkFormat,
    samples : VkSampleCountFlagBits,
    loadOp : VkAttachmentLoadOp,
    storeOp : VkAttachmentStoreOp,
    stencilLoadOp : VkAttachmentLoadOp,
    stencilStoreOp : VkAttachmentStoreOp,
    initialLayout : VkImageLayout,
    finalLayout : VkImageLayout,
}

VkAttachmentReference2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    attachment : u32,
    layout : VkImageLayout,
    aspectMask : VkImageAspectFlags,
}

VkSubpassDescription2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkSubpassDescriptionFlags,
    pipelineBindPoint : VkPipelineBindPoint,
    viewMask : u32,
    inputAttachmentCount : u32,
    pInputAttachments : ptr[VkAttachmentReference2],
    colorAttachmentCount : u32,
    pColorAttachments : ptr[VkAttachmentReference2],
    pResolveAttachments : ptr[VkAttachmentReference2],
    pDepthStencilAttachment : ptr[VkAttachmentReference2],
    preserveAttachmentCount : u32,
    pPreserveAttachments : ptr[u32],
}

VkSubpassDependency2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    srcSubpass : u32,
    dstSubpass : u32,
    srcStageMask : VkPipelineStageFlags,
    dstStageMask : VkPipelineStageFlags,
    srcAccessMask : VkAccessFlags,
    dstAccessMask : VkAccessFlags,
    dependencyFlags : VkDependencyFlags,
    viewOffset : i32,
}

VkRenderPassCreateInfo2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkRenderPassCreateFlags,
    attachmentCount : u32,
    pAttachments : ptr[VkAttachmentDescription2],
    subpassCount : u32,
    pSubpasses : ptr[VkSubpassDescription2],
    dependencyCount : u32,
    pDependencies : ptr[VkSubpassDependency2],
    correlatedViewMaskCount : u32,
    pCorrelatedViewMasks : ptr[u32],
}

VkSubpassBeginInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    contents : VkSubpassContents,
}

VkSubpassEndInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
}

VkPhysicalDevice8BitStorageFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    storageBuffer8BitAccess : VkBool32,
    uniformAndStorageBuffer8BitAccess : VkBool32,
    storagePushConstant8 : VkBool32,
}

VkPhysicalDeviceDriverProperties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    driverID : VkDriverId,
    driverName : char[VK_MAX_DRIVER_NAME_SIZE],
    driverInfo : char[VK_MAX_DRIVER_INFO_SIZE],
    conformanceVersion : VkConformanceVersion,
}

VkPhysicalDeviceShaderAtomicInt64Features :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderBufferInt64Atomics : VkBool32,
    shaderSharedInt64Atomics : VkBool32,
}

VkPhysicalDeviceShaderFloat16Int8Features :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderFloat16 : VkBool32,
    shaderInt8 : VkBool32,
}

VkPhysicalDeviceFloatControlsProperties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    denormBehaviorIndependence : VkShaderFloatControlsIndependence,
    roundingModeIndependence : VkShaderFloatControlsIndependence,
    shaderSignedZeroInfNanPreserveFloat16 : VkBool32,
    shaderSignedZeroInfNanPreserveFloat32 : VkBool32,
    shaderSignedZeroInfNanPreserveFloat64 : VkBool32,
    shaderDenormPreserveFloat16 : VkBool32,
    shaderDenormPreserveFloat32 : VkBool32,
    shaderDenormPreserveFloat64 : VkBool32,
    shaderDenormFlushToZeroFloat16 : VkBool32,
    shaderDenormFlushToZeroFloat32 : VkBool32,
    shaderDenormFlushToZeroFloat64 : VkBool32,
    shaderRoundingModeRTEFloat16 : VkBool32,
    shaderRoundingModeRTEFloat32 : VkBool32,
    shaderRoundingModeRTEFloat64 : VkBool32,
    shaderRoundingModeRTZFloat16 : VkBool32,
    shaderRoundingModeRTZFloat32 : VkBool32,
    shaderRoundingModeRTZFloat64 : VkBool32,
}

VkDescriptorSetLayoutBindingFlagsCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    bindingCount : u32,
    pBindingFlags : ptr[VkDescriptorBindingFlags],
}

VkPhysicalDeviceDescriptorIndexingFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderInputAttachmentArrayDynamicIndexing : VkBool32,
    shaderUniformTexelBufferArrayDynamicIndexing : VkBool32,
    shaderStorageTexelBufferArrayDynamicIndexing : VkBool32,
    shaderUniformBufferArrayNonUniformIndexing : VkBool32,
    shaderSampledImageArrayNonUniformIndexing : VkBool32,
    shaderStorageBufferArrayNonUniformIndexing : VkBool32,
    shaderStorageImageArrayNonUniformIndexing : VkBool32,
    shaderInputAttachmentArrayNonUniformIndexing : VkBool32,
    shaderUniformTexelBufferArrayNonUniformIndexing : VkBool32,
    shaderStorageTexelBufferArrayNonUniformIndexing : VkBool32,
    descriptorBindingUniformBufferUpdateAfterBind : VkBool32,
    descriptorBindingSampledImageUpdateAfterBind : VkBool32,
    descriptorBindingStorageImageUpdateAfterBind : VkBool32,
    descriptorBindingStorageBufferUpdateAfterBind : VkBool32,
    descriptorBindingUniformTexelBufferUpdateAfterBind : VkBool32,
    descriptorBindingStorageTexelBufferUpdateAfterBind : VkBool32,
    descriptorBindingUpdateUnusedWhilePending : VkBool32,
    descriptorBindingPartiallyBound : VkBool32,
    descriptorBindingVariableDescriptorCount : VkBool32,
    runtimeDescriptorArray : VkBool32,
}

VkPhysicalDeviceDescriptorIndexingProperties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxUpdateAfterBindDescriptorsInAllPools : u32,
    shaderUniformBufferArrayNonUniformIndexingNative : VkBool32,
    shaderSampledImageArrayNonUniformIndexingNative : VkBool32,
    shaderStorageBufferArrayNonUniformIndexingNative : VkBool32,
    shaderStorageImageArrayNonUniformIndexingNative : VkBool32,
    shaderInputAttachmentArrayNonUniformIndexingNative : VkBool32,
    robustBufferAccessUpdateAfterBind : VkBool32,
    quadDivergentImplicitLod : VkBool32,
    maxPerStageDescriptorUpdateAfterBindSamplers : u32,
    maxPerStageDescriptorUpdateAfterBindUniformBuffers : u32,
    maxPerStageDescriptorUpdateAfterBindStorageBuffers : u32,
    maxPerStageDescriptorUpdateAfterBindSampledImages : u32,
    maxPerStageDescriptorUpdateAfterBindStorageImages : u32,
    maxPerStageDescriptorUpdateAfterBindInputAttachments : u32,
    maxPerStageUpdateAfterBindResources : u32,
    maxDescriptorSetUpdateAfterBindSamplers : u32,
    maxDescriptorSetUpdateAfterBindUniformBuffers : u32,
    maxDescriptorSetUpdateAfterBindUniformBuffersDynamic : u32,
    maxDescriptorSetUpdateAfterBindStorageBuffers : u32,
    maxDescriptorSetUpdateAfterBindStorageBuffersDynamic : u32,
    maxDescriptorSetUpdateAfterBindSampledImages : u32,
    maxDescriptorSetUpdateAfterBindStorageImages : u32,
    maxDescriptorSetUpdateAfterBindInputAttachments : u32,
}

VkDescriptorSetVariableDescriptorCountAllocateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    descriptorSetCount : u32,
    pDescriptorCounts : ptr[u32],
}

VkDescriptorSetVariableDescriptorCountLayoutSupport :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxVariableDescriptorCount : u32,
}

VkSubpassDescriptionDepthStencilResolve :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    depthResolveMode : VkResolveModeFlagBits,
    stencilResolveMode : VkResolveModeFlagBits,
    pDepthStencilResolveAttachment : ptr[VkAttachmentReference2],
}

VkPhysicalDeviceDepthStencilResolveProperties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    supportedDepthResolveModes : VkResolveModeFlags,
    supportedStencilResolveModes : VkResolveModeFlags,
    independentResolveNone : VkBool32,
    independentResolve : VkBool32,
}

VkPhysicalDeviceScalarBlockLayoutFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    scalarBlockLayout : VkBool32,
}

VkImageStencilUsageCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    stencilUsage : VkImageUsageFlags,
}

VkSamplerReductionModeCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    reductionMode : VkSamplerReductionMode,
}

VkPhysicalDeviceSamplerFilterMinmaxProperties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    filterMinmaxSingleComponentFormats : VkBool32,
    filterMinmaxImageComponentMapping : VkBool32,
}

VkPhysicalDeviceVulkanMemoryModelFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    vulkanMemoryModel : VkBool32,
    vulkanMemoryModelDeviceScope : VkBool32,
    vulkanMemoryModelAvailabilityVisibilityChains : VkBool32,
}

VkPhysicalDeviceImagelessFramebufferFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    imagelessFramebuffer : VkBool32,
}

VkFramebufferAttachmentImageInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkImageCreateFlags,
    usage : VkImageUsageFlags,
    width : u32,
    height : u32,
    layerCount : u32,
    viewFormatCount : u32,
    pViewFormats : ptr[VkFormat],
}

VkFramebufferAttachmentsCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    attachmentImageInfoCount : u32,
    pAttachmentImageInfos : ptr[VkFramebufferAttachmentImageInfo],
}

VkRenderPassAttachmentBeginInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    attachmentCount : u32,
    pAttachments : ptr[VkImageView],
}

VkPhysicalDeviceUniformBufferStandardLayoutFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    uniformBufferStandardLayout : VkBool32,
}

VkPhysicalDeviceShaderSubgroupExtendedTypesFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderSubgroupExtendedTypes : VkBool32,
}

VkPhysicalDeviceSeparateDepthStencilLayoutsFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    separateDepthStencilLayouts : VkBool32,
}

VkAttachmentReferenceStencilLayout :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    stencilLayout : VkImageLayout,
}

VkAttachmentDescriptionStencilLayout :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    stencilInitialLayout : VkImageLayout,
    stencilFinalLayout : VkImageLayout,
}

VkPhysicalDeviceHostQueryResetFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    hostQueryReset : VkBool32,
}

VkPhysicalDeviceTimelineSemaphoreFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    timelineSemaphore : VkBool32,
}

VkPhysicalDeviceTimelineSemaphoreProperties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxTimelineSemaphoreValueDifference : u64,
}

VkSemaphoreTypeCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    semaphoreType : VkSemaphoreType,
    initialValue : u64,
}

VkTimelineSemaphoreSubmitInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    waitSemaphoreValueCount : u32,
    pWaitSemaphoreValues : ptr[u64],
    signalSemaphoreValueCount : u32,
    pSignalSemaphoreValues : ptr[u64],
}

VkSemaphoreWaitInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkSemaphoreWaitFlags,
    semaphoreCount : u32,
    pSemaphores : ptr[VkSemaphore],
    pValues : ptr[u64],
}

VkSemaphoreSignalInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    semaphore : VkSemaphore,
    value : u64,
}

VkPhysicalDeviceBufferDeviceAddressFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    bufferDeviceAddress : VkBool32,
    bufferDeviceAddressCaptureReplay : VkBool32,
    bufferDeviceAddressMultiDevice : VkBool32,
}

VkBufferDeviceAddressInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    buffer : VkBuffer,
}

VkBufferOpaqueCaptureAddressCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    opaqueCaptureAddress : u64,
}

VkMemoryOpaqueCaptureAddressAllocateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    opaqueCaptureAddress : u64,
}

VkDeviceMemoryOpaqueCaptureAddressInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    memory : VkDeviceMemory,
}

VkPhysicalDeviceVulkan13Features :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    robustImageAccess : VkBool32,
    inlineUniformBlock : VkBool32,
    descriptorBindingInlineUniformBlockUpdateAfterBind : VkBool32,
    pipelineCreationCacheControl : VkBool32,
    privateData : VkBool32,
    shaderDemoteToHelperInvocation : VkBool32,
    shaderTerminateInvocation : VkBool32,
    subgroupSizeControl : VkBool32,
    computeFullSubgroups : VkBool32,
    synchronization2 : VkBool32,
    textureCompressionASTC_HDR : VkBool32,
    shaderZeroInitializeWorkgroupMemory : VkBool32,
    dynamicRendering : VkBool32,
    shaderIntegerDotProduct : VkBool32,
    maintenance4 : VkBool32,
}

VkPhysicalDeviceVulkan13Properties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    minSubgroupSize : u32,
    maxSubgroupSize : u32,
    maxComputeWorkgroupSubgroups : u32,
    requiredSubgroupSizeStages : VkShaderStageFlags,
    maxInlineUniformBlockSize : u32,
    maxPerStageDescriptorInlineUniformBlocks : u32,
    maxPerStageDescriptorUpdateAfterBindInlineUniformBlocks : u32,
    maxDescriptorSetInlineUniformBlocks : u32,
    maxDescriptorSetUpdateAfterBindInlineUniformBlocks : u32,
    maxInlineUniformTotalSize : u32,
    integerDotProduct8BitUnsignedAccelerated : VkBool32,
    integerDotProduct8BitSignedAccelerated : VkBool32,
    integerDotProduct8BitMixedSignednessAccelerated : VkBool32,
    integerDotProduct4x8BitPackedUnsignedAccelerated : VkBool32,
    integerDotProduct4x8BitPackedSignedAccelerated : VkBool32,
    integerDotProduct4x8BitPackedMixedSignednessAccelerated : VkBool32,
    integerDotProduct16BitUnsignedAccelerated : VkBool32,
    integerDotProduct16BitSignedAccelerated : VkBool32,
    integerDotProduct16BitMixedSignednessAccelerated : VkBool32,
    integerDotProduct32BitUnsignedAccelerated : VkBool32,
    integerDotProduct32BitSignedAccelerated : VkBool32,
    integerDotProduct32BitMixedSignednessAccelerated : VkBool32,
    integerDotProduct64BitUnsignedAccelerated : VkBool32,
    integerDotProduct64BitSignedAccelerated : VkBool32,
    integerDotProduct64BitMixedSignednessAccelerated : VkBool32,
    integerDotProductAccumulatingSaturating8BitUnsignedAccelerated : VkBool32,
    integerDotProductAccumulatingSaturating8BitSignedAccelerated : VkBool32,
    integerDotProductAccumulatingSaturating8BitMixedSignednessAccelerated : VkBool32,
    integerDotProductAccumulatingSaturating4x8BitPackedUnsignedAccelerated : VkBool32,
    integerDotProductAccumulatingSaturating4x8BitPackedSignedAccelerated : VkBool32,
    integerDotProductAccumulatingSaturating4x8BitPackedMixedSignednessAccelerated : VkBool32,
    integerDotProductAccumulatingSaturating16BitUnsignedAccelerated : VkBool32,
    integerDotProductAccumulatingSaturating16BitSignedAccelerated : VkBool32,
    integerDotProductAccumulatingSaturating16BitMixedSignednessAccelerated : VkBool32,
    integerDotProductAccumulatingSaturating32BitUnsignedAccelerated : VkBool32,
    integerDotProductAccumulatingSaturating32BitSignedAccelerated : VkBool32,
    integerDotProductAccumulatingSaturating32BitMixedSignednessAccelerated : VkBool32,
    integerDotProductAccumulatingSaturating64BitUnsignedAccelerated : VkBool32,
    integerDotProductAccumulatingSaturating64BitSignedAccelerated : VkBool32,
    integerDotProductAccumulatingSaturating64BitMixedSignednessAccelerated : VkBool32,
    storageTexelBufferOffsetAlignmentBytes : VkDeviceSize,
    storageTexelBufferOffsetSingleTexelAlignment : VkBool32,
    uniformTexelBufferOffsetAlignmentBytes : VkDeviceSize,
    uniformTexelBufferOffsetSingleTexelAlignment : VkBool32,
    maxBufferSize : VkDeviceSize,
}

VkPipelineCreationFeedback :: struct {
    flags : VkPipelineCreationFeedbackFlags,
    duration : u64,
}

VkPipelineCreationFeedbackCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pPipelineCreationFeedback : ptr[VkPipelineCreationFeedback],
    pipelineStageCreationFeedbackCount : u32,
    pPipelineStageCreationFeedbacks : ptr[VkPipelineCreationFeedback],
}

VkPhysicalDeviceShaderTerminateInvocationFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderTerminateInvocation : VkBool32,
}

VkPhysicalDeviceToolProperties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    name : char[VK_MAX_EXTENSION_NAME_SIZE],
    version : char[VK_MAX_EXTENSION_NAME_SIZE],
    purposes : VkToolPurposeFlags,
    description : char[VK_MAX_DESCRIPTION_SIZE],
    layer : char[VK_MAX_EXTENSION_NAME_SIZE],
}

VkPhysicalDeviceShaderDemoteToHelperInvocationFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderDemoteToHelperInvocation : VkBool32,
}

VkPhysicalDevicePrivateDataFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    privateData : VkBool32,
}

VkDevicePrivateDataCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    privateDataSlotRequestCount : u32,
}

VkPrivateDataSlotCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPrivateDataSlotCreateFlags,
}

VkPhysicalDevicePipelineCreationCacheControlFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pipelineCreationCacheControl : VkBool32,
}

VkMemoryBarrier2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    srcStageMask : VkPipelineStageFlags2,
    srcAccessMask : VkAccessFlags2,
    dstStageMask : VkPipelineStageFlags2,
    dstAccessMask : VkAccessFlags2,
}

VkBufferMemoryBarrier2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    srcStageMask : VkPipelineStageFlags2,
    srcAccessMask : VkAccessFlags2,
    dstStageMask : VkPipelineStageFlags2,
    dstAccessMask : VkAccessFlags2,
    srcQueueFamilyIndex : u32,
    dstQueueFamilyIndex : u32,
    buffer : VkBuffer,
    offset : VkDeviceSize,
    size : VkDeviceSize,
}

VkImageMemoryBarrier2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    srcStageMask : VkPipelineStageFlags2,
    srcAccessMask : VkAccessFlags2,
    dstStageMask : VkPipelineStageFlags2,
    dstAccessMask : VkAccessFlags2,
    oldLayout : VkImageLayout,
    newLayout : VkImageLayout,
    srcQueueFamilyIndex : u32,
    dstQueueFamilyIndex : u32,
    image : VkImage,
    subresourceRange : VkImageSubresourceRange,
}

VkDependencyInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    dependencyFlags : VkDependencyFlags,
    memoryBarrierCount : u32,
    pMemoryBarriers : ptr[VkMemoryBarrier2],
    bufferMemoryBarrierCount : u32,
    pBufferMemoryBarriers : ptr[VkBufferMemoryBarrier2],
    imageMemoryBarrierCount : u32,
    pImageMemoryBarriers : ptr[VkImageMemoryBarrier2],
}

VkSemaphoreSubmitInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    semaphore : VkSemaphore,
    value : u64,
    stageMask : VkPipelineStageFlags2,
    deviceIndex : u32,
}

VkCommandBufferSubmitInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    commandBuffer : VkCommandBuffer,
    deviceMask : u32,
}

VkSubmitInfo2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkSubmitFlags,
    waitSemaphoreInfoCount : u32,
    pWaitSemaphoreInfos : ptr[VkSemaphoreSubmitInfo],
    commandBufferInfoCount : u32,
    pCommandBufferInfos : ptr[VkCommandBufferSubmitInfo],
    signalSemaphoreInfoCount : u32,
    pSignalSemaphoreInfos : ptr[VkSemaphoreSubmitInfo],
}

VkPhysicalDeviceSynchronization2Features :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    synchronization2 : VkBool32,
}

VkPhysicalDeviceZeroInitializeWorkgroupMemoryFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderZeroInitializeWorkgroupMemory : VkBool32,
}

VkPhysicalDeviceImageRobustnessFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    robustImageAccess : VkBool32,
}

VkBufferCopy2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    srcOffset : VkDeviceSize,
    dstOffset : VkDeviceSize,
    size : VkDeviceSize,
}

VkCopyBufferInfo2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    srcBuffer : VkBuffer,
    dstBuffer : VkBuffer,
    regionCount : u32,
    pRegions : ptr[VkBufferCopy2],
}

VkImageCopy2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    srcSubresource : VkImageSubresourceLayers,
    srcOffset : VkOffset3D,
    dstSubresource : VkImageSubresourceLayers,
    dstOffset : VkOffset3D,
    extent : VkExtent3D,
}

VkCopyImageInfo2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    srcImage : VkImage,
    srcImageLayout : VkImageLayout,
    dstImage : VkImage,
    dstImageLayout : VkImageLayout,
    regionCount : u32,
    pRegions : ptr[VkImageCopy2],
}

VkBufferImageCopy2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    bufferOffset : VkDeviceSize,
    bufferRowLength : u32,
    bufferImageHeight : u32,
    imageSubresource : VkImageSubresourceLayers,
    imageOffset : VkOffset3D,
    imageExtent : VkExtent3D,
}

VkCopyBufferToImageInfo2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    srcBuffer : VkBuffer,
    dstImage : VkImage,
    dstImageLayout : VkImageLayout,
    regionCount : u32,
    pRegions : ptr[VkBufferImageCopy2],
}

VkCopyImageToBufferInfo2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    srcImage : VkImage,
    srcImageLayout : VkImageLayout,
    dstBuffer : VkBuffer,
    regionCount : u32,
    pRegions : ptr[VkBufferImageCopy2],
}

VkImageBlit2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    srcSubresource : VkImageSubresourceLayers,
    srcOffsets : VkOffset3D[2],
    dstSubresource : VkImageSubresourceLayers,
    dstOffsets : VkOffset3D[2],
}

VkBlitImageInfo2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    srcImage : VkImage,
    srcImageLayout : VkImageLayout,
    dstImage : VkImage,
    dstImageLayout : VkImageLayout,
    regionCount : u32,
    pRegions : ptr[VkImageBlit2],
    filter : VkFilter,
}

VkImageResolve2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    srcSubresource : VkImageSubresourceLayers,
    srcOffset : VkOffset3D,
    dstSubresource : VkImageSubresourceLayers,
    dstOffset : VkOffset3D,
    extent : VkExtent3D,
}

VkResolveImageInfo2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    srcImage : VkImage,
    srcImageLayout : VkImageLayout,
    dstImage : VkImage,
    dstImageLayout : VkImageLayout,
    regionCount : u32,
    pRegions : ptr[VkImageResolve2],
}

VkPhysicalDeviceSubgroupSizeControlFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    subgroupSizeControl : VkBool32,
    computeFullSubgroups : VkBool32,
}

VkPhysicalDeviceSubgroupSizeControlProperties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    minSubgroupSize : u32,
    maxSubgroupSize : u32,
    maxComputeWorkgroupSubgroups : u32,
    requiredSubgroupSizeStages : VkShaderStageFlags,
}

VkPipelineShaderStageRequiredSubgroupSizeCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    requiredSubgroupSize : u32,
}

VkPhysicalDeviceInlineUniformBlockFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    inlineUniformBlock : VkBool32,
    descriptorBindingInlineUniformBlockUpdateAfterBind : VkBool32,
}

VkPhysicalDeviceInlineUniformBlockProperties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxInlineUniformBlockSize : u32,
    maxPerStageDescriptorInlineUniformBlocks : u32,
    maxPerStageDescriptorUpdateAfterBindInlineUniformBlocks : u32,
    maxDescriptorSetInlineUniformBlocks : u32,
    maxDescriptorSetUpdateAfterBindInlineUniformBlocks : u32,
}

VkWriteDescriptorSetInlineUniformBlock :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    dataSize : u32,
    pData : rawptr,
}

VkDescriptorPoolInlineUniformBlockCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxInlineUniformBlockBindings : u32,
}

VkPhysicalDeviceTextureCompressionASTCHDRFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    textureCompressionASTC_HDR : VkBool32,
}

VkRenderingAttachmentInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    imageView : VkImageView,
    imageLayout : VkImageLayout,
    resolveMode : VkResolveModeFlagBits,
    resolveImageView : VkImageView,
    resolveImageLayout : VkImageLayout,
    loadOp : VkAttachmentLoadOp,
    storeOp : VkAttachmentStoreOp,
    clearValue : VkClearValue,
}

VkRenderingInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkRenderingFlags,
    renderArea : VkRect2D,
    layerCount : u32,
    viewMask : u32,
    colorAttachmentCount : u32,
    pColorAttachments : ptr[VkRenderingAttachmentInfo],
    pDepthAttachment : ptr[VkRenderingAttachmentInfo],
    pStencilAttachment : ptr[VkRenderingAttachmentInfo],
}

VkPipelineRenderingCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    viewMask : u32,
    colorAttachmentCount : u32,
    pColorAttachmentFormats : ptr[VkFormat],
    depthAttachmentFormat : VkFormat,
    stencilAttachmentFormat : VkFormat,
}

VkPhysicalDeviceDynamicRenderingFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    dynamicRendering : VkBool32,
}

VkCommandBufferInheritanceRenderingInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkRenderingFlags,
    viewMask : u32,
    colorAttachmentCount : u32,
    pColorAttachmentFormats : ptr[VkFormat],
    depthAttachmentFormat : VkFormat,
    stencilAttachmentFormat : VkFormat,
    rasterizationSamples : VkSampleCountFlagBits,
}

VkPhysicalDeviceShaderIntegerDotProductFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderIntegerDotProduct : VkBool32,
}

VkPhysicalDeviceShaderIntegerDotProductProperties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    integerDotProduct8BitUnsignedAccelerated : VkBool32,
    integerDotProduct8BitSignedAccelerated : VkBool32,
    integerDotProduct8BitMixedSignednessAccelerated : VkBool32,
    integerDotProduct4x8BitPackedUnsignedAccelerated : VkBool32,
    integerDotProduct4x8BitPackedSignedAccelerated : VkBool32,
    integerDotProduct4x8BitPackedMixedSignednessAccelerated : VkBool32,
    integerDotProduct16BitUnsignedAccelerated : VkBool32,
    integerDotProduct16BitSignedAccelerated : VkBool32,
    integerDotProduct16BitMixedSignednessAccelerated : VkBool32,
    integerDotProduct32BitUnsignedAccelerated : VkBool32,
    integerDotProduct32BitSignedAccelerated : VkBool32,
    integerDotProduct32BitMixedSignednessAccelerated : VkBool32,
    integerDotProduct64BitUnsignedAccelerated : VkBool32,
    integerDotProduct64BitSignedAccelerated : VkBool32,
    integerDotProduct64BitMixedSignednessAccelerated : VkBool32,
    integerDotProductAccumulatingSaturating8BitUnsignedAccelerated : VkBool32,
    integerDotProductAccumulatingSaturating8BitSignedAccelerated : VkBool32,
    integerDotProductAccumulatingSaturating8BitMixedSignednessAccelerated : VkBool32,
    integerDotProductAccumulatingSaturating4x8BitPackedUnsignedAccelerated : VkBool32,
    integerDotProductAccumulatingSaturating4x8BitPackedSignedAccelerated : VkBool32,
    integerDotProductAccumulatingSaturating4x8BitPackedMixedSignednessAccelerated : VkBool32,
    integerDotProductAccumulatingSaturating16BitUnsignedAccelerated : VkBool32,
    integerDotProductAccumulatingSaturating16BitSignedAccelerated : VkBool32,
    integerDotProductAccumulatingSaturating16BitMixedSignednessAccelerated : VkBool32,
    integerDotProductAccumulatingSaturating32BitUnsignedAccelerated : VkBool32,
    integerDotProductAccumulatingSaturating32BitSignedAccelerated : VkBool32,
    integerDotProductAccumulatingSaturating32BitMixedSignednessAccelerated : VkBool32,
    integerDotProductAccumulatingSaturating64BitUnsignedAccelerated : VkBool32,
    integerDotProductAccumulatingSaturating64BitSignedAccelerated : VkBool32,
    integerDotProductAccumulatingSaturating64BitMixedSignednessAccelerated : VkBool32,
}

VkPhysicalDeviceTexelBufferAlignmentProperties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    storageTexelBufferOffsetAlignmentBytes : VkDeviceSize,
    storageTexelBufferOffsetSingleTexelAlignment : VkBool32,
    uniformTexelBufferOffsetAlignmentBytes : VkDeviceSize,
    uniformTexelBufferOffsetSingleTexelAlignment : VkBool32,
}

VkFormatProperties3 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    linearTilingFeatures : VkFormatFeatureFlags2,
    optimalTilingFeatures : VkFormatFeatureFlags2,
    bufferFeatures : VkFormatFeatureFlags2,
}

VkPhysicalDeviceMaintenance4Features :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maintenance4 : VkBool32,
}

VkPhysicalDeviceMaintenance4Properties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxBufferSize : VkDeviceSize,
}

VkDeviceBufferMemoryRequirements :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pCreateInfo : ptr[VkBufferCreateInfo],
}

VkDeviceImageMemoryRequirements :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pCreateInfo : ptr[VkImageCreateInfo],
    planeAspect : VkImageAspectFlagBits,
}

VkSurfaceCapabilitiesKHR :: struct {
    minImageCount : u32,
    maxImageCount : u32,
    currentExtent : VkExtent2D,
    minImageExtent : VkExtent2D,
    maxImageExtent : VkExtent2D,
    maxImageArrayLayers : u32,
    supportedTransforms : VkSurfaceTransformFlagsKHR,
    currentTransform : VkSurfaceTransformFlagBitsKHR,
    supportedCompositeAlpha : VkCompositeAlphaFlagsKHR,
    supportedUsageFlags : VkImageUsageFlags,
}

VkSurfaceFormatKHR :: struct {
    format : VkFormat,
    colorSpace : VkColorSpaceKHR,
}

VkSwapchainCreateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkSwapchainCreateFlagsKHR,
    surface : VkSurfaceKHR,
    minImageCount : u32,
    imageFormat : VkFormat,
    imageColorSpace : VkColorSpaceKHR,
    imageExtent : VkExtent2D,
    imageArrayLayers : u32,
    imageUsage : VkImageUsageFlags,
    imageSharingMode : VkSharingMode,
    queueFamilyIndexCount : u32,
    pQueueFamilyIndices : ptr[u32],
    preTransform : VkSurfaceTransformFlagBitsKHR,
    compositeAlpha : VkCompositeAlphaFlagBitsKHR,
    presentMode : VkPresentModeKHR,
    clipped : VkBool32,
    oldSwapchain : VkSwapchainKHR,
}

VkPresentInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    waitSemaphoreCount : u32,
    pWaitSemaphores : ptr[VkSemaphore],
    swapchainCount : u32,
    pSwapchains : ptr[VkSwapchainKHR],
    pImageIndices : ptr[u32],
    pResults : ptr[VkResult],
}

VkImageSwapchainCreateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    swapchain : VkSwapchainKHR,
}

VkBindImageMemorySwapchainInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    swapchain : VkSwapchainKHR,
    imageIndex : u32,
}

VkAcquireNextImageInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    swapchain : VkSwapchainKHR,
    timeout : u64,
    semaphore : VkSemaphore,
    fence : VkFence,
    deviceMask : u32,
}

VkDeviceGroupPresentCapabilitiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    presentMask[VK_MAX_DEVICE_GROUP_SIZE] : u32,
    modes : VkDeviceGroupPresentModeFlagsKHR,
}

VkDeviceGroupPresentInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    swapchainCount : u32,
    pDeviceMasks : ptr[u32],
    mode : VkDeviceGroupPresentModeFlagBitsKHR,
}

VkDeviceGroupSwapchainCreateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    modes : VkDeviceGroupPresentModeFlagsKHR,
}

VkDisplayModeParametersKHR :: struct {
    visibleRegion : VkExtent2D,
    refreshRate : u32,
}

VkDisplayModeCreateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkDisplayModeCreateFlagsKHR,
    parameters : VkDisplayModeParametersKHR,
}

VkDisplayModePropertiesKHR :: struct {
    displayMode : VkDisplayModeKHR,
    parameters : VkDisplayModeParametersKHR,
}

VkDisplayPlaneCapabilitiesKHR :: struct {
    supportedAlpha : VkDisplayPlaneAlphaFlagsKHR,
    minSrcPosition : VkOffset2D,
    maxSrcPosition : VkOffset2D,
    minSrcExtent : VkExtent2D,
    maxSrcExtent : VkExtent2D,
    minDstPosition : VkOffset2D,
    maxDstPosition : VkOffset2D,
    minDstExtent : VkExtent2D,
    maxDstExtent : VkExtent2D,
}

VkDisplayPlanePropertiesKHR :: struct {
    currentDisplay : VkDisplayKHR,
    currentStackIndex : u32,
}

VkDisplayPropertiesKHR :: struct {
    display : VkDisplayKHR,
    displayName : ptr[char],
    physicalDimensions : VkExtent2D,
    physicalResolution : VkExtent2D,
    supportedTransforms : VkSurfaceTransformFlagsKHR,
    planeReorderPossible : VkBool32,
    persistentContent : VkBool32,
}

VkDisplaySurfaceCreateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkDisplaySurfaceCreateFlagsKHR,
    displayMode : VkDisplayModeKHR,
    planeIndex : u32,
    planeStackIndex : u32,
    transform : VkSurfaceTransformFlagBitsKHR,
    globalAlpha : f32,
    alphaMode : VkDisplayPlaneAlphaFlagBitsKHR,
    imageExtent : VkExtent2D,
}

VkDisplayPresentInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    srcRect : VkRect2D,
    dstRect : VkRect2D,
    persistent : VkBool32,
}

VkQueueFamilyQueryResultStatusPropertiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    queryResultStatusSupport : VkBool32,
}

VkQueueFamilyVideoPropertiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    videoCodecOperations : VkVideoCodecOperationFlagsKHR,
}

VkVideoProfileInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    videoCodecOperation : VkVideoCodecOperationFlagBitsKHR,
    chromaSubsampling : VkVideoChromaSubsamplingFlagsKHR,
    lumaBitDepth : VkVideoComponentBitDepthFlagsKHR,
    chromaBitDepth : VkVideoComponentBitDepthFlagsKHR,
}

VkVideoProfileListInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    profileCount : u32,
    pProfiles : ptr[VkVideoProfileInfoKHR],
}

VkVideoCapabilitiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkVideoCapabilityFlagsKHR,
    minBitstreamBufferOffsetAlignment : VkDeviceSize,
    minBitstreamBufferSizeAlignment : VkDeviceSize,
    pictureAccessGranularity : VkExtent2D,
    minCodedExtent : VkExtent2D,
    maxCodedExtent : VkExtent2D,
    maxDpbSlots : u32,
    maxActiveReferencePictures : u32,
    stdHeaderVersion : VkExtensionProperties,
}

VkPhysicalDeviceVideoFormatInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    imageUsage : VkImageUsageFlags,
}

VkVideoFormatPropertiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    format : VkFormat,
    componentMapping : VkComponentMapping,
    imageCreateFlags : VkImageCreateFlags,
    imageType : VkImageType,
    imageTiling : VkImageTiling,
    imageUsageFlags : VkImageUsageFlags,
}

VkVideoPictureResourceInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    codedOffset : VkOffset2D,
    codedExtent : VkExtent2D,
    baseArrayLayer : u32,
    imageViewBinding : VkImageView,
}

VkVideoReferenceSlotInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    slotIndex : i32,
    pPictureResource : ptr[VkVideoPictureResourceInfoKHR],
}

VkVideoSessionMemoryRequirementsKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    memoryBindIndex : u32,
    memoryRequirements : VkMemoryRequirements,
}

VkBindVideoSessionMemoryInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    memoryBindIndex : u32,
    memory : VkDeviceMemory,
    memoryOffset : VkDeviceSize,
    memorySize : VkDeviceSize,
}

VkVideoSessionCreateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    queueFamilyIndex : u32,
    flags : VkVideoSessionCreateFlagsKHR,
    pVideoProfile : ptr[VkVideoProfileInfoKHR],
    pictureFormat : VkFormat,
    maxCodedExtent : VkExtent2D,
    referencePictureFormat : VkFormat,
    maxDpbSlots : u32,
    maxActiveReferencePictures : u32,
    pStdHeaderVersion : ptr[VkExtensionProperties],
}

VkVideoSessionParametersCreateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkVideoSessionParametersCreateFlagsKHR,
    videoSessionParametersTemplate : VkVideoSessionParametersKHR,
    videoSession : VkVideoSessionKHR,
}

VkVideoSessionParametersUpdateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    updateSequenceCount : u32,
}

VkVideoBeginCodingInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkVideoBeginCodingFlagsKHR,
    videoSession : VkVideoSessionKHR,
    videoSessionParameters : VkVideoSessionParametersKHR,
    referenceSlotCount : u32,
    pReferenceSlots : ptr[VkVideoReferenceSlotInfoKHR],
}

VkVideoEndCodingInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkVideoEndCodingFlagsKHR,
}

VkVideoCodingControlInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkVideoCodingControlFlagsKHR,
}

VkVideoDecodeCapabilitiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkVideoDecodeCapabilityFlagsKHR,
}

VkVideoDecodeUsageInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    videoUsageHints : VkVideoDecodeUsageFlagsKHR,
}

VkVideoDecodeInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkVideoDecodeFlagsKHR,
    srcBuffer : VkBuffer,
    srcBufferOffset : VkDeviceSize,
    srcBufferRange : VkDeviceSize,
    dstPictureResource : VkVideoPictureResourceInfoKHR,
    pSetupReferenceSlot : ptr[VkVideoReferenceSlotInfoKHR],
    referenceSlotCount : u32,
    pReferenceSlots : ptr[VkVideoReferenceSlotInfoKHR],
}

VkVideoEncodeH264CapabilitiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkVideoEncodeH264CapabilityFlagsKHR,
    maxLevelIdc : StdVideoH264LevelIdc,
    maxSliceCount : u32,
    maxPPictureL0ReferenceCount : u32,
    maxBPictureL0ReferenceCount : u32,
    maxL1ReferenceCount : u32,
    maxTemporalLayerCount : u32,
    expectDyadicTemporalLayerPattern : VkBool32,
    minQp : i32,
    maxQp : i32,
    prefersGopRemainingFrames : VkBool32,
    requiresGopRemainingFrames : VkBool32,
    stdSyntaxFlags : VkVideoEncodeH264StdFlagsKHR,
}

VkVideoEncodeH264QpKHR :: struct {
    qpI : i32,
    qpP : i32,
    qpB : i32,
}

VkVideoEncodeH264QualityLevelPropertiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    preferredRateControlFlags : VkVideoEncodeH264RateControlFlagsKHR,
    preferredGopFrameCount : u32,
    preferredIdrPeriod : u32,
    preferredConsecutiveBFrameCount : u32,
    preferredTemporalLayerCount : u32,
    preferredConstantQp : VkVideoEncodeH264QpKHR,
    preferredMaxL0ReferenceCount : u32,
    preferredMaxL1ReferenceCount : u32,
    preferredStdEntropyCodingModeFlag : VkBool32,
}

VkVideoEncodeH264SessionCreateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    useMaxLevelIdc : VkBool32,
    maxLevelIdc : StdVideoH264LevelIdc,
}

VkVideoEncodeH264SessionParametersAddInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    stdSPSCount : u32,
    pStdSPSs : ptr[StdVideoH264SequenceParameterSet],
    stdPPSCount : u32,
    pStdPPSs : ptr[StdVideoH264PictureParameterSet],
}

VkVideoEncodeH264SessionParametersCreateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxStdSPSCount : u32,
    maxStdPPSCount : u32,
    pParametersAddInfo : ptr[VkVideoEncodeH264SessionParametersAddInfoKHR],
}

VkVideoEncodeH264SessionParametersGetInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    writeStdSPS : VkBool32,
    writeStdPPS : VkBool32,
    stdSPSId : u32,
    stdPPSId : u32,
}

VkVideoEncodeH264SessionParametersFeedbackInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    hasStdSPSOverrides : VkBool32,
    hasStdPPSOverrides : VkBool32,
}

VkVideoEncodeH264NaluSliceInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    constantQp : i32,
    pStdSliceHeader : ptr[StdVideoEncodeH264SliceHeader],
}

VkVideoEncodeH264PictureInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    naluSliceEntryCount : u32,
    pNaluSliceEntries : ptr[VkVideoEncodeH264NaluSliceInfoKHR],
    pStdPictureInfo : ptr[StdVideoEncodeH264PictureInfo],
    generatePrefixNalu : VkBool32,
}

VkVideoEncodeH264DpbSlotInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pStdReferenceInfo : ptr[StdVideoEncodeH264ReferenceInfo],
}

VkVideoEncodeH264ProfileInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    stdProfileIdc : StdVideoH264ProfileIdc,
}

VkVideoEncodeH264RateControlInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkVideoEncodeH264RateControlFlagsKHR,
    gopFrameCount : u32,
    idrPeriod : u32,
    consecutiveBFrameCount : u32,
    temporalLayerCount : u32,
}

VkVideoEncodeH264FrameSizeKHR :: struct {
    frameISize : u32,
    framePSize : u32,
    frameBSize : u32,
}

VkVideoEncodeH264RateControlLayerInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    useMinQp : VkBool32,
    minQp : VkVideoEncodeH264QpKHR,
    useMaxQp : VkBool32,
    maxQp : VkVideoEncodeH264QpKHR,
    useMaxFrameSize : VkBool32,
    maxFrameSize : VkVideoEncodeH264FrameSizeKHR,
}

VkVideoEncodeH264GopRemainingFrameInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    useGopRemainingFrames : VkBool32,
    gopRemainingI : u32,
    gopRemainingP : u32,
    gopRemainingB : u32,
}

VkVideoEncodeH265CapabilitiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkVideoEncodeH265CapabilityFlagsKHR,
    maxLevelIdc : StdVideoH265LevelIdc,
    maxSliceSegmentCount : u32,
    maxTiles : VkExtent2D,
    ctbSizes : VkVideoEncodeH265CtbSizeFlagsKHR,
    transformBlockSizes : VkVideoEncodeH265TransformBlockSizeFlagsKHR,
    maxPPictureL0ReferenceCount : u32,
    maxBPictureL0ReferenceCount : u32,
    maxL1ReferenceCount : u32,
    maxSubLayerCount : u32,
    expectDyadicTemporalSubLayerPattern : VkBool32,
    minQp : i32,
    maxQp : i32,
    prefersGopRemainingFrames : VkBool32,
    requiresGopRemainingFrames : VkBool32,
    stdSyntaxFlags : VkVideoEncodeH265StdFlagsKHR,
}

VkVideoEncodeH265SessionCreateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    useMaxLevelIdc : VkBool32,
    maxLevelIdc : StdVideoH265LevelIdc,
}

VkVideoEncodeH265QpKHR :: struct {
    qpI : i32,
    qpP : i32,
    qpB : i32,
}

VkVideoEncodeH265QualityLevelPropertiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    preferredRateControlFlags : VkVideoEncodeH265RateControlFlagsKHR,
    preferredGopFrameCount : u32,
    preferredIdrPeriod : u32,
    preferredConsecutiveBFrameCount : u32,
    preferredSubLayerCount : u32,
    preferredConstantQp : VkVideoEncodeH265QpKHR,
    preferredMaxL0ReferenceCount : u32,
    preferredMaxL1ReferenceCount : u32,
}

VkVideoEncodeH265SessionParametersAddInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    stdVPSCount : u32,
    pStdVPSs : ptr[StdVideoH265VideoParameterSet],
    stdSPSCount : u32,
    pStdSPSs : ptr[StdVideoH265SequenceParameterSet],
    stdPPSCount : u32,
    pStdPPSs : ptr[StdVideoH265PictureParameterSet],
}

VkVideoEncodeH265SessionParametersCreateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxStdVPSCount : u32,
    maxStdSPSCount : u32,
    maxStdPPSCount : u32,
    pParametersAddInfo : ptr[VkVideoEncodeH265SessionParametersAddInfoKHR],
}

VkVideoEncodeH265SessionParametersGetInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    writeStdVPS : VkBool32,
    writeStdSPS : VkBool32,
    writeStdPPS : VkBool32,
    stdVPSId : u32,
    stdSPSId : u32,
    stdPPSId : u32,
}

VkVideoEncodeH265SessionParametersFeedbackInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    hasStdVPSOverrides : VkBool32,
    hasStdSPSOverrides : VkBool32,
    hasStdPPSOverrides : VkBool32,
}

VkVideoEncodeH265NaluSliceSegmentInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    constantQp : i32,
    pStdSliceSegmentHeader : ptr[StdVideoEncodeH265SliceSegmentHeader],
}

VkVideoEncodeH265PictureInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    naluSliceSegmentEntryCount : u32,
    pNaluSliceSegmentEntries : ptr[VkVideoEncodeH265NaluSliceSegmentInfoKHR],
    pStdPictureInfo : ptr[StdVideoEncodeH265PictureInfo],
}

VkVideoEncodeH265DpbSlotInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pStdReferenceInfo : ptr[StdVideoEncodeH265ReferenceInfo],
}

VkVideoEncodeH265ProfileInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    stdProfileIdc : StdVideoH265ProfileIdc,
}

VkVideoEncodeH265RateControlInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkVideoEncodeH265RateControlFlagsKHR,
    gopFrameCount : u32,
    idrPeriod : u32,
    consecutiveBFrameCount : u32,
    subLayerCount : u32,
}

VkVideoEncodeH265FrameSizeKHR :: struct {
    frameISize : u32,
    framePSize : u32,
    frameBSize : u32,
}

VkVideoEncodeH265RateControlLayerInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    useMinQp : VkBool32,
    minQp : VkVideoEncodeH265QpKHR,
    useMaxQp : VkBool32,
    maxQp : VkVideoEncodeH265QpKHR,
    useMaxFrameSize : VkBool32,
    maxFrameSize : VkVideoEncodeH265FrameSizeKHR,
}

VkVideoEncodeH265GopRemainingFrameInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    useGopRemainingFrames : VkBool32,
    gopRemainingI : u32,
    gopRemainingP : u32,
    gopRemainingB : u32,
}

VkVideoDecodeH264ProfileInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    stdProfileIdc : StdVideoH264ProfileIdc,
    pictureLayout : VkVideoDecodeH264PictureLayoutFlagBitsKHR,
}

VkVideoDecodeH264CapabilitiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxLevelIdc : StdVideoH264LevelIdc,
    fieldOffsetGranularity : VkOffset2D,
}

VkVideoDecodeH264SessionParametersAddInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    stdSPSCount : u32,
    pStdSPSs : ptr[StdVideoH264SequenceParameterSet],
    stdPPSCount : u32,
    pStdPPSs : ptr[StdVideoH264PictureParameterSet],
}

VkVideoDecodeH264SessionParametersCreateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxStdSPSCount : u32,
    maxStdPPSCount : u32,
    pParametersAddInfo : ptr[VkVideoDecodeH264SessionParametersAddInfoKHR],
}

VkVideoDecodeH264PictureInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pStdPictureInfo : ptr[StdVideoDecodeH264PictureInfo],
    sliceCount : u32,
    pSliceOffsets : ptr[u32],
}

VkVideoDecodeH264DpbSlotInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pStdReferenceInfo : ptr[StdVideoDecodeH264ReferenceInfo],
}

VkRenderingFragmentShadingRateAttachmentInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    imageView : VkImageView,
    imageLayout : VkImageLayout,
    shadingRateAttachmentTexelSize : VkExtent2D,
}

VkRenderingFragmentDensityMapAttachmentInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    imageView : VkImageView,
    imageLayout : VkImageLayout,
}

VkAttachmentSampleCountInfoAMD :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    colorAttachmentCount : u32,
    pColorAttachmentSamples : ptr[VkSampleCountFlagBits],
    depthStencilAttachmentSamples : VkSampleCountFlagBits,
}

VkMultiviewPerViewAttributesInfoNVX :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    perViewAttributes : VkBool32,
    perViewAttributesPositionXOnly : VkBool32,
}

VkImportMemoryFdInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    handleType : VkExternalMemoryHandleTypeFlagBits,
    fd : int,
}

VkMemoryFdPropertiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    memoryTypeBits : u32,
}

VkMemoryGetFdInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    memory : VkDeviceMemory,
    handleType : VkExternalMemoryHandleTypeFlagBits,
}

VkImportSemaphoreFdInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    semaphore : VkSemaphore,
    flags : VkSemaphoreImportFlags,
    handleType : VkExternalSemaphoreHandleTypeFlagBits,
    fd : int,
}

VkSemaphoreGetFdInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    semaphore : VkSemaphore,
    handleType : VkExternalSemaphoreHandleTypeFlagBits,
}

VkPhysicalDevicePushDescriptorPropertiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxPushDescriptors : u32,
}

VkRectLayerKHR :: struct {
    offset : VkOffset2D,
    extent : VkExtent2D,
    layer : u32,
}

VkPresentRegionKHR :: struct {
    rectangleCount : u32,
    pRectangles : ptr[VkRectLayerKHR],
}

VkPresentRegionsKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    swapchainCount : u32,
    pRegions : ptr[VkPresentRegionKHR],
}

VkSharedPresentSurfaceCapabilitiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    sharedPresentSupportedUsageFlags : VkImageUsageFlags,
}

VkImportFenceFdInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    fence : VkFence,
    flags : VkFenceImportFlags,
    handleType : VkExternalFenceHandleTypeFlagBits,
    fd : int,
}

VkFenceGetFdInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    fence : VkFence,
    handleType : VkExternalFenceHandleTypeFlagBits,
}

VkPhysicalDevicePerformanceQueryFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    performanceCounterQueryPools : VkBool32,
    performanceCounterMultipleQueryPools : VkBool32,
}

VkPhysicalDevicePerformanceQueryPropertiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    allowCommandBufferQueryCopies : VkBool32,
}

VkPerformanceCounterKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    unit : VkPerformanceCounterUnitKHR,
    scope : VkPerformanceCounterScopeKHR,
    storage : VkPerformanceCounterStorageKHR,
    uuid[VK_UUID_SIZE] : u8,
}

VkPerformanceCounterDescriptionKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPerformanceCounterDescriptionFlagsKHR,
    name : char[VK_MAX_DESCRIPTION_SIZE],
    category : char[VK_MAX_DESCRIPTION_SIZE],
    description : char[VK_MAX_DESCRIPTION_SIZE],
}

VkQueryPoolPerformanceCreateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    queueFamilyIndex : u32,
    counterIndexCount : u32,
    pCounterIndices : ptr[u32],
}

VkAcquireProfilingLockInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkAcquireProfilingLockFlagsKHR,
    timeout : u64,
}

VkPerformanceQuerySubmitInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    counterPassIndex : u32,
}

VkPhysicalDeviceSurfaceInfo2KHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    surface : VkSurfaceKHR,
}

VkSurfaceCapabilities2KHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    surfaceCapabilities : VkSurfaceCapabilitiesKHR,
}

VkSurfaceFormat2KHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    surfaceFormat : VkSurfaceFormatKHR,
}

VkDisplayProperties2KHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    displayProperties : VkDisplayPropertiesKHR,
}

VkDisplayPlaneProperties2KHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    displayPlaneProperties : VkDisplayPlanePropertiesKHR,
}

VkDisplayModeProperties2KHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    displayModeProperties : VkDisplayModePropertiesKHR,
}

VkDisplayPlaneInfo2KHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    mode : VkDisplayModeKHR,
    planeIndex : u32,
}

VkDisplayPlaneCapabilities2KHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    capabilities : VkDisplayPlaneCapabilitiesKHR,
}

VkPhysicalDeviceShaderClockFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderSubgroupClock : VkBool32,
    shaderDeviceClock : VkBool32,
}

VkVideoDecodeH265ProfileInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    stdProfileIdc : StdVideoH265ProfileIdc,
}

VkVideoDecodeH265CapabilitiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxLevelIdc : StdVideoH265LevelIdc,
}

VkVideoDecodeH265SessionParametersAddInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    stdVPSCount : u32,
    pStdVPSs : ptr[StdVideoH265VideoParameterSet],
    stdSPSCount : u32,
    pStdSPSs : ptr[StdVideoH265SequenceParameterSet],
    stdPPSCount : u32,
    pStdPPSs : ptr[StdVideoH265PictureParameterSet],
}

VkVideoDecodeH265SessionParametersCreateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxStdVPSCount : u32,
    maxStdSPSCount : u32,
    maxStdPPSCount : u32,
    pParametersAddInfo : ptr[VkVideoDecodeH265SessionParametersAddInfoKHR],
}

VkVideoDecodeH265PictureInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pStdPictureInfo : ptr[StdVideoDecodeH265PictureInfo],
    sliceSegmentCount : u32,
    pSliceSegmentOffsets : ptr[u32],
}

VkVideoDecodeH265DpbSlotInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pStdReferenceInfo : ptr[StdVideoDecodeH265ReferenceInfo],
}

VkDeviceQueueGlobalPriorityCreateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    globalPriority : VkQueueGlobalPriorityKHR,
}

VkPhysicalDeviceGlobalPriorityQueryFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    globalPriorityQuery : VkBool32,
}

VkQueueFamilyGlobalPriorityPropertiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    priorityCount : u32,
    priorities : VkQueueGlobalPriorityKHR[VK_MAX_GLOBAL_PRIORITY_SIZE_KHR],
}

VkFragmentShadingRateAttachmentInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pFragmentShadingRateAttachment : ptr[VkAttachmentReference2],
    shadingRateAttachmentTexelSize : VkExtent2D,
}

VkPipelineFragmentShadingRateStateCreateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    fragmentSize : VkExtent2D,
    combinerOps : VkFragmentShadingRateCombinerOpKHR[2],
}

VkPhysicalDeviceFragmentShadingRateFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pipelineFragmentShadingRate : VkBool32,
    primitiveFragmentShadingRate : VkBool32,
    attachmentFragmentShadingRate : VkBool32,
}

VkPhysicalDeviceFragmentShadingRatePropertiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    minFragmentShadingRateAttachmentTexelSize : VkExtent2D,
    maxFragmentShadingRateAttachmentTexelSize : VkExtent2D,
    maxFragmentShadingRateAttachmentTexelSizeAspectRatio : u32,
    primitiveFragmentShadingRateWithMultipleViewports : VkBool32,
    layeredShadingRateAttachments : VkBool32,
    fragmentShadingRateNonTrivialCombinerOps : VkBool32,
    maxFragmentSize : VkExtent2D,
    maxFragmentSizeAspectRatio : u32,
    maxFragmentShadingRateCoverageSamples : u32,
    maxFragmentShadingRateRasterizationSamples : VkSampleCountFlagBits,
    fragmentShadingRateWithShaderDepthStencilWrites : VkBool32,
    fragmentShadingRateWithSampleMask : VkBool32,
    fragmentShadingRateWithShaderSampleMask : VkBool32,
    fragmentShadingRateWithConservativeRasterization : VkBool32,
    fragmentShadingRateWithFragmentShaderInterlock : VkBool32,
    fragmentShadingRateWithCustomSampleLocations : VkBool32,
    fragmentShadingRateStrictMultiplyCombiner : VkBool32,
}

VkPhysicalDeviceFragmentShadingRateKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    sampleCounts : VkSampleCountFlags,
    fragmentSize : VkExtent2D,
}

VkPhysicalDeviceDynamicRenderingLocalReadFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    dynamicRenderingLocalRead : VkBool32,
}

VkRenderingAttachmentLocationInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    colorAttachmentCount : u32,
    pColorAttachmentLocations : ptr[u32],
}

VkRenderingInputAttachmentIndexInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    colorAttachmentCount : u32,
    pColorAttachmentInputIndices : ptr[u32],
    pDepthInputAttachmentIndex : ptr[u32],
    pStencilInputAttachmentIndex : ptr[u32],
}

VkPhysicalDeviceShaderQuadControlFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderQuadControl : VkBool32,
}

VkSurfaceProtectedCapabilitiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    supportsProtected : VkBool32,
}

VkPhysicalDevicePresentWaitFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    presentWait : VkBool32,
}

VkPhysicalDevicePipelineExecutablePropertiesFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pipelineExecutableInfo : VkBool32,
}

VkPipelineInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pipeline : VkPipeline,
}

VkPipelineExecutablePropertiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    stages : VkShaderStageFlags,
    name : char[VK_MAX_DESCRIPTION_SIZE],
    description : char[VK_MAX_DESCRIPTION_SIZE],
    subgroupSize : u32,
}

VkPipelineExecutableInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pipeline : VkPipeline,
    executableIndex : u32,
}

VkPipelineExecutableStatisticKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    name : char[VK_MAX_DESCRIPTION_SIZE],
    description : char[VK_MAX_DESCRIPTION_SIZE],
    format : VkPipelineExecutableStatisticFormatKHR,
    value : VkPipelineExecutableStatisticValueKHR,
}

VkPipelineExecutableInternalRepresentationKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    name : char[VK_MAX_DESCRIPTION_SIZE],
    description : char[VK_MAX_DESCRIPTION_SIZE],
    isText : VkBool32,
    dataSize : size_t,
    pData : rawptr,
}

VkMemoryMapInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkMemoryMapFlags,
    memory : VkDeviceMemory,
    offset : VkDeviceSize,
    size : VkDeviceSize,
}

VkMemoryUnmapInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkMemoryUnmapFlagsKHR,
    memory : VkDeviceMemory,
}

VkPipelineLibraryCreateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    libraryCount : u32,
    pLibraries : ptr[VkPipeline],
}

VkPresentIdKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    swapchainCount : u32,
    pPresentIds : ptr[u64],
}

VkPhysicalDevicePresentIdFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    presentId : VkBool32,
}

VkVideoEncodeInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkVideoEncodeFlagsKHR,
    dstBuffer : VkBuffer,
    dstBufferOffset : VkDeviceSize,
    dstBufferRange : VkDeviceSize,
    srcPictureResource : VkVideoPictureResourceInfoKHR,
    pSetupReferenceSlot : ptr[VkVideoReferenceSlotInfoKHR],
    referenceSlotCount : u32,
    pReferenceSlots : ptr[VkVideoReferenceSlotInfoKHR],
    precedingExternallyEncodedBytes : u32,
}

VkVideoEncodeCapabilitiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkVideoEncodeCapabilityFlagsKHR,
    rateControlModes : VkVideoEncodeRateControlModeFlagsKHR,
    maxRateControlLayers : u32,
    maxBitrate : u64,
    maxQualityLevels : u32,
    encodeInputPictureGranularity : VkExtent2D,
    supportedEncodeFeedbackFlags : VkVideoEncodeFeedbackFlagsKHR,
}

VkQueryPoolVideoEncodeFeedbackCreateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    encodeFeedbackFlags : VkVideoEncodeFeedbackFlagsKHR,
}

VkVideoEncodeUsageInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    videoUsageHints : VkVideoEncodeUsageFlagsKHR,
    videoContentHints : VkVideoEncodeContentFlagsKHR,
    tuningMode : VkVideoEncodeTuningModeKHR,
}

VkVideoEncodeRateControlLayerInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    averageBitrate : u64,
    maxBitrate : u64,
    frameRateNumerator : u32,
    frameRateDenominator : u32,
}

VkVideoEncodeRateControlInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkVideoEncodeRateControlFlagsKHR,
    rateControlMode : VkVideoEncodeRateControlModeFlagBitsKHR,
    layerCount : u32,
    pLayers : ptr[VkVideoEncodeRateControlLayerInfoKHR],
    virtualBufferSizeInMs : u32,
    initialVirtualBufferSizeInMs : u32,
}

VkPhysicalDeviceVideoEncodeQualityLevelInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pVideoProfile : ptr[VkVideoProfileInfoKHR],
    qualityLevel : u32,
}

VkVideoEncodeQualityLevelPropertiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    preferredRateControlMode : VkVideoEncodeRateControlModeFlagBitsKHR,
    preferredRateControlLayerCount : u32,
}

VkVideoEncodeQualityLevelInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    qualityLevel : u32,
}

VkVideoEncodeSessionParametersGetInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    videoSessionParameters : VkVideoSessionParametersKHR,
}

VkVideoEncodeSessionParametersFeedbackInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    hasOverrides : VkBool32,
}

VkQueueFamilyCheckpointProperties2NV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    checkpointExecutionStageMask : VkPipelineStageFlags2,
}

VkCheckpointData2NV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    stage : VkPipelineStageFlags2,
    pCheckpointMarker : rawptr,
}

VkPhysicalDeviceFragmentShaderBarycentricFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    fragmentShaderBarycentric : VkBool32,
}

VkPhysicalDeviceFragmentShaderBarycentricPropertiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    triStripVertexOrderIndependentOfProvokingVertex : VkBool32,
}

VkPhysicalDeviceShaderSubgroupUniformControlFlowFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderSubgroupUniformControlFlow : VkBool32,
}

VkPhysicalDeviceWorkgroupMemoryExplicitLayoutFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    workgroupMemoryExplicitLayout : VkBool32,
    workgroupMemoryExplicitLayoutScalarBlockLayout : VkBool32,
    workgroupMemoryExplicitLayout8BitAccess : VkBool32,
    workgroupMemoryExplicitLayout16BitAccess : VkBool32,
}

VkPhysicalDeviceRayTracingMaintenance1FeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    rayTracingMaintenance1 : VkBool32,
    rayTracingPipelineTraceRaysIndirect2 : VkBool32,
}

VkTraceRaysIndirectCommand2KHR :: struct {
    raygenShaderRecordAddress : VkDeviceAddress,
    raygenShaderRecordSize : VkDeviceSize,
    missShaderBindingTableAddress : VkDeviceAddress,
    missShaderBindingTableSize : VkDeviceSize,
    missShaderBindingTableStride : VkDeviceSize,
    hitShaderBindingTableAddress : VkDeviceAddress,
    hitShaderBindingTableSize : VkDeviceSize,
    hitShaderBindingTableStride : VkDeviceSize,
    callableShaderBindingTableAddress : VkDeviceAddress,
    callableShaderBindingTableSize : VkDeviceSize,
    callableShaderBindingTableStride : VkDeviceSize,
    width : u32,
    height : u32,
    depth : u32,
}

VkPhysicalDeviceShaderSubgroupRotateFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderSubgroupRotate : VkBool32,
    shaderSubgroupRotateClustered : VkBool32,
}

VkPhysicalDeviceShaderMaximalReconvergenceFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderMaximalReconvergence : VkBool32,
}

VkPhysicalDeviceMaintenance5FeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maintenance5 : VkBool32,
}

VkPhysicalDeviceMaintenance5PropertiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    earlyFragmentMultisampleCoverageAfterSampleCounting : VkBool32,
    earlyFragmentSampleMaskTestBeforeSampleCounting : VkBool32,
    depthStencilSwizzleOneSupport : VkBool32,
    polygonModePointSize : VkBool32,
    nonStrictSinglePixelWideLinesUseParallelogram : VkBool32,
    nonStrictWideLinesUseParallelogram : VkBool32,
}

VkRenderingAreaInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    viewMask : u32,
    colorAttachmentCount : u32,
    pColorAttachmentFormats : ptr[VkFormat],
    depthAttachmentFormat : VkFormat,
    stencilAttachmentFormat : VkFormat,
}

VkImageSubresource2KHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    imageSubresource : VkImageSubresource,
}

VkDeviceImageSubresourceInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pCreateInfo : ptr[VkImageCreateInfo],
    pSubresource : ptr[VkImageSubresource2KHR],
}

VkSubresourceLayout2KHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    subresourceLayout : VkSubresourceLayout,
}

VkPipelineCreateFlags2CreateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineCreateFlags2KHR,
}

VkBufferUsageFlags2CreateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    usage : VkBufferUsageFlags2KHR,
}

VkPhysicalDeviceRayTracingPositionFetchFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    rayTracingPositionFetch : VkBool32,
}

VkCooperativeMatrixPropertiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    MSize : u32,
    NSize : u32,
    KSize : u32,
    AType : VkComponentTypeKHR,
    BType : VkComponentTypeKHR,
    CType : VkComponentTypeKHR,
    ResultType : VkComponentTypeKHR,
    saturatingAccumulation : VkBool32,
    scope : VkScopeKHR,
}

VkPhysicalDeviceCooperativeMatrixFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    cooperativeMatrix : VkBool32,
    cooperativeMatrixRobustBufferAccess : VkBool32,
}

VkPhysicalDeviceCooperativeMatrixPropertiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    cooperativeMatrixSupportedStages : VkShaderStageFlags,
}

VkVideoDecodeAV1ProfileInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    stdProfile : StdVideoAV1Profile,
    filmGrainSupport : VkBool32,
}

VkVideoDecodeAV1CapabilitiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxLevel : StdVideoAV1Level,
}

VkVideoDecodeAV1SessionParametersCreateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pStdSequenceHeader : ptr[StdVideoAV1SequenceHeader],
}

VkVideoDecodeAV1PictureInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pStdPictureInfo : ptr[StdVideoDecodeAV1PictureInfo],
    referenceNameSlotIndices[VK_MAX_VIDEO_AV1_REFERENCES_PER_FRAME_KHR] : i32,
    frameHeaderOffset : u32,
    tileCount : u32,
    pTileOffsets : ptr[u32],
    pTileSizes : ptr[u32],
}

VkVideoDecodeAV1DpbSlotInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pStdReferenceInfo : ptr[StdVideoDecodeAV1ReferenceInfo],
}

VkPhysicalDeviceVideoMaintenance1FeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    videoMaintenance1 : VkBool32,
}

VkVideoInlineQueryInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    queryPool : VkQueryPool,
    firstQuery : u32,
    queryCount : u32,
}

VkPhysicalDeviceVertexAttributeDivisorPropertiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxVertexAttribDivisor : u32,
    supportsNonZeroFirstInstance : VkBool32,
}

VkVertexInputBindingDivisorDescriptionKHR :: struct {
    binding : u32,
    divisor : u32,
}

VkPipelineVertexInputDivisorStateCreateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    vertexBindingDivisorCount : u32,
    pVertexBindingDivisors : ptr[VkVertexInputBindingDivisorDescriptionKHR],
}

VkPhysicalDeviceVertexAttributeDivisorFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    vertexAttributeInstanceRateDivisor : VkBool32,
    vertexAttributeInstanceRateZeroDivisor : VkBool32,
}

VkPhysicalDeviceShaderFloatControls2FeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderFloatControls2 : VkBool32,
}

VkPhysicalDeviceIndexTypeUint8FeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    indexTypeUint8 : VkBool32,
}

VkPhysicalDeviceLineRasterizationFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    rectangularLines : VkBool32,
    bresenhamLines : VkBool32,
    smoothLines : VkBool32,
    stippledRectangularLines : VkBool32,
    stippledBresenhamLines : VkBool32,
    stippledSmoothLines : VkBool32,
}

VkPhysicalDeviceLineRasterizationPropertiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    lineSubPixelPrecisionBits : u32,
}

VkPipelineRasterizationLineStateCreateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    lineRasterizationMode : VkLineRasterizationModeKHR,
    stippledLineEnable : VkBool32,
    lineStippleFactor : u32,
    lineStipplePattern : u16,
}

VkCalibratedTimestampInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    timeDomain : VkTimeDomainKHR,
}

VkPhysicalDeviceShaderExpectAssumeFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderExpectAssume : VkBool32,
}

VkPhysicalDeviceMaintenance6FeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maintenance6 : VkBool32,
}

VkPhysicalDeviceMaintenance6PropertiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    blockTexelViewCompatibleMultipleLayers : VkBool32,
    maxCombinedImageSamplerDescriptorCount : u32,
    fragmentShadingRateClampCombinerInputs : VkBool32,
}

VkBindMemoryStatusKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pResult : ptr[VkResult],
}

VkBindDescriptorSetsInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    stageFlags : VkShaderStageFlags,
    layout : VkPipelineLayout,
    firstSet : u32,
    descriptorSetCount : u32,
    pDescriptorSets : ptr[VkDescriptorSet],
    dynamicOffsetCount : u32,
    pDynamicOffsets : ptr[u32],
}

VkPushConstantsInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    layout : VkPipelineLayout,
    stageFlags : VkShaderStageFlags,
    offset : u32,
    size : u32,
    pValues : rawptr,
}

VkPushDescriptorSetInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    stageFlags : VkShaderStageFlags,
    layout : VkPipelineLayout,
    set : u32,
    descriptorWriteCount : u32,
    pDescriptorWrites : ptr[VkWriteDescriptorSet],
}

VkPushDescriptorSetWithTemplateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    descriptorUpdateTemplate : VkDescriptorUpdateTemplate,
    layout : VkPipelineLayout,
    set : u32,
    pData : rawptr,
}

VkSetDescriptorBufferOffsetsInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    stageFlags : VkShaderStageFlags,
    layout : VkPipelineLayout,
    firstSet : u32,
    setCount : u32,
    pBufferIndices : ptr[u32],
    pOffsets : ptr[VkDeviceSize],
}

VkBindDescriptorBufferEmbeddedSamplersInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    stageFlags : VkShaderStageFlags,
    layout : VkPipelineLayout,
    set : u32,
}

VkDebugReportCallbackCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkDebugReportFlagsEXT,
    pfnCallback : PFN_vkDebugReportCallbackEXT,
    pUserData : rawptr,
}

VkPipelineRasterizationStateRasterizationOrderAMD :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    rasterizationOrder : VkRasterizationOrderAMD,
}

VkDebugMarkerObjectNameInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    objectType : VkDebugReportObjectTypeEXT,
    object : u64,
    pObjectName : ptr[char],
}

VkDebugMarkerObjectTagInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    objectType : VkDebugReportObjectTypeEXT,
    object : u64,
    tagName : u64,
    tagSize : size_t,
    pTag : rawptr,
}

VkDebugMarkerMarkerInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pMarkerName : ptr[char],
    color : f32[4],
}

VkDedicatedAllocationImageCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    dedicatedAllocation : VkBool32,
}

VkDedicatedAllocationBufferCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    dedicatedAllocation : VkBool32,
}

VkDedicatedAllocationMemoryAllocateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    image : VkImage,
    buffer : VkBuffer,
}

VkPhysicalDeviceTransformFeedbackFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    transformFeedback : VkBool32,
    geometryStreams : VkBool32,
}

VkPhysicalDeviceTransformFeedbackPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxTransformFeedbackStreams : u32,
    maxTransformFeedbackBuffers : u32,
    maxTransformFeedbackBufferSize : VkDeviceSize,
    maxTransformFeedbackStreamDataSize : u32,
    maxTransformFeedbackBufferDataSize : u32,
    maxTransformFeedbackBufferDataStride : u32,
    transformFeedbackQueries : VkBool32,
    transformFeedbackStreamsLinesTriangles : VkBool32,
    transformFeedbackRasterizationStreamSelect : VkBool32,
    transformFeedbackDraw : VkBool32,
}

VkPipelineRasterizationStateStreamCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineRasterizationStateStreamCreateFlagsEXT,
    rasterizationStream : u32,
}

VkCuModuleCreateInfoNVX :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    dataSize : size_t,
    pData : rawptr,
}

VkCuFunctionCreateInfoNVX :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    module : VkCuModuleNVX,
    pName : ptr[char],
}

VkCuLaunchInfoNVX :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    function : VkCuFunctionNVX,
    gridDimX : u32,
    gridDimY : u32,
    gridDimZ : u32,
    blockDimX : u32,
    blockDimY : u32,
    blockDimZ : u32,
    sharedMemBytes : u32,
    paramCount : size_t,
    pParams : ptr[rawptr],
    extraCount : size_t,
    pExtras : ptr[rawptr],
}

VkImageViewHandleInfoNVX :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    imageView : VkImageView,
    descriptorType : VkDescriptorType,
    sampler : VkSampler,
}

VkImageViewAddressPropertiesNVX :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    deviceAddress : VkDeviceAddress,
    size : VkDeviceSize,
}

VkTextureLODGatherFormatPropertiesAMD :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    supportsTextureGatherLODBiasAMD : VkBool32,
}

VkShaderResourceUsageAMD :: struct {
    numUsedVgprs : u32,
    numUsedSgprs : u32,
    ldsSizePerLocalWorkGroup : u32,
    ldsUsageSizeInBytes : size_t,
    scratchMemUsageInBytes : size_t,
}

VkShaderStatisticsInfoAMD :: struct {
    shaderStageMask : VkShaderStageFlags,
    resourceUsage : VkShaderResourceUsageAMD,
    numPhysicalVgprs : u32,
    numPhysicalSgprs : u32,
    numAvailableVgprs : u32,
    numAvailableSgprs : u32,
    computeWorkGroupSize[3] : u32,
}

VkPhysicalDeviceCornerSampledImageFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    cornerSampledImage : VkBool32,
}

VkExternalImageFormatPropertiesNV :: struct {
    imageFormatProperties : VkImageFormatProperties,
    externalMemoryFeatures : VkExternalMemoryFeatureFlagsNV,
    exportFromImportedHandleTypes : VkExternalMemoryHandleTypeFlagsNV,
    compatibleHandleTypes : VkExternalMemoryHandleTypeFlagsNV,
}

VkExternalMemoryImageCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    handleTypes : VkExternalMemoryHandleTypeFlagsNV,
}

VkExportMemoryAllocateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    handleTypes : VkExternalMemoryHandleTypeFlagsNV,
}

VkValidationFlagsEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    disabledValidationCheckCount : u32,
    pDisabledValidationChecks : ptr[VkValidationCheckEXT],
}

VkImageViewASTCDecodeModeEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    decodeMode : VkFormat,
}

VkPhysicalDeviceASTCDecodeFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    decodeModeSharedExponent : VkBool32,
}

VkPhysicalDevicePipelineRobustnessFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pipelineRobustness : VkBool32,
}

VkPhysicalDevicePipelineRobustnessPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    defaultRobustnessStorageBuffers : VkPipelineRobustnessBufferBehaviorEXT,
    defaultRobustnessUniformBuffers : VkPipelineRobustnessBufferBehaviorEXT,
    defaultRobustnessVertexInputs : VkPipelineRobustnessBufferBehaviorEXT,
    defaultRobustnessImages : VkPipelineRobustnessImageBehaviorEXT,
}

VkPipelineRobustnessCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    storageBuffers : VkPipelineRobustnessBufferBehaviorEXT,
    uniformBuffers : VkPipelineRobustnessBufferBehaviorEXT,
    vertexInputs : VkPipelineRobustnessBufferBehaviorEXT,
    images : VkPipelineRobustnessImageBehaviorEXT,
}

VkConditionalRenderingBeginInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    buffer : VkBuffer,
    offset : VkDeviceSize,
    flags : VkConditionalRenderingFlagsEXT,
}

VkPhysicalDeviceConditionalRenderingFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    conditionalRendering : VkBool32,
    inheritedConditionalRendering : VkBool32,
}

VkCommandBufferInheritanceConditionalRenderingInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    conditionalRenderingEnable : VkBool32,
}

VkViewportWScalingNV :: struct {
    xcoeff : f32,
    ycoeff : f32,
}

VkPipelineViewportWScalingStateCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    viewportWScalingEnable : VkBool32,
    viewportCount : u32,
    pViewportWScalings : ptr[VkViewportWScalingNV],
}

VkSurfaceCapabilities2EXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    minImageCount : u32,
    maxImageCount : u32,
    currentExtent : VkExtent2D,
    minImageExtent : VkExtent2D,
    maxImageExtent : VkExtent2D,
    maxImageArrayLayers : u32,
    supportedTransforms : VkSurfaceTransformFlagsKHR,
    currentTransform : VkSurfaceTransformFlagBitsKHR,
    supportedCompositeAlpha : VkCompositeAlphaFlagsKHR,
    supportedUsageFlags : VkImageUsageFlags,
    supportedSurfaceCounters : VkSurfaceCounterFlagsEXT,
}

VkDisplayPowerInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    powerState : VkDisplayPowerStateEXT,
}

VkDeviceEventInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    deviceEvent : VkDeviceEventTypeEXT,
}

VkDisplayEventInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    displayEvent : VkDisplayEventTypeEXT,
}

VkSwapchainCounterCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    surfaceCounters : VkSurfaceCounterFlagsEXT,
}

VkRefreshCycleDurationGOOGLE :: struct {
    refreshDuration : u64,
}

VkPastPresentationTimingGOOGLE :: struct {
    presentID : u32,
    desiredPresentTime : u64,
    actualPresentTime : u64,
    earliestPresentTime : u64,
    presentMargin : u64,
}

VkPresentTimeGOOGLE :: struct {
    presentID : u32,
    desiredPresentTime : u64,
}

VkPresentTimesInfoGOOGLE :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    swapchainCount : u32,
    pTimes : ptr[VkPresentTimeGOOGLE],
}

VkPhysicalDeviceMultiviewPerViewAttributesPropertiesNVX :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    perViewPositionAllComponents : VkBool32,
}

VkViewportSwizzleNV :: struct {
    x : VkViewportCoordinateSwizzleNV,
    y : VkViewportCoordinateSwizzleNV,
    z : VkViewportCoordinateSwizzleNV,
    w : VkViewportCoordinateSwizzleNV,
}

VkPipelineViewportSwizzleStateCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineViewportSwizzleStateCreateFlagsNV,
    viewportCount : u32,
    pViewportSwizzles : ptr[VkViewportSwizzleNV],
}

VkPhysicalDeviceDiscardRectanglePropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxDiscardRectangles : u32,
}

VkPipelineDiscardRectangleStateCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineDiscardRectangleStateCreateFlagsEXT,
    discardRectangleMode : VkDiscardRectangleModeEXT,
    discardRectangleCount : u32,
    pDiscardRectangles : ptr[VkRect2D],
}

VkPhysicalDeviceConservativeRasterizationPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    primitiveOverestimationSize : f32,
    maxExtraPrimitiveOverestimationSize : f32,
    extraPrimitiveOverestimationSizeGranularity : f32,
    primitiveUnderestimation : VkBool32,
    conservativePointAndLineRasterization : VkBool32,
    degenerateTrianglesRasterized : VkBool32,
    degenerateLinesRasterized : VkBool32,
    fullyCoveredFragmentShaderInputVariable : VkBool32,
    conservativeRasterizationPostDepthCoverage : VkBool32,
}

VkPipelineRasterizationConservativeStateCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineRasterizationConservativeStateCreateFlagsEXT,
    conservativeRasterizationMode : VkConservativeRasterizationModeEXT,
    extraPrimitiveOverestimationSize : f32,
}

VkPhysicalDeviceDepthClipEnableFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    depthClipEnable : VkBool32,
}

VkPipelineRasterizationDepthClipStateCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineRasterizationDepthClipStateCreateFlagsEXT,
    depthClipEnable : VkBool32,
}

VkXYColorEXT :: struct {
    x : f32,
    y : f32,
}

VkHdrMetadataEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    displayPrimaryRed : VkXYColorEXT,
    displayPrimaryGreen : VkXYColorEXT,
    displayPrimaryBlue : VkXYColorEXT,
    whitePoint : VkXYColorEXT,
    maxLuminance : f32,
    minLuminance : f32,
    maxContentLightLevel : f32,
    maxFrameAverageLightLevel : f32,
}

VkPhysicalDeviceRelaxedLineRasterizationFeaturesIMG :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    relaxedLineRasterization : VkBool32,
}

VkDebugUtilsLabelEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pLabelName : ptr[char],
    color : f32[4],
}

VkDebugUtilsObjectNameInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    objectType : VkObjectType,
    objectHandle : u64,
    pObjectName : ptr[char],
}

VkDebugUtilsMessengerCallbackDataEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkDebugUtilsMessengerCallbackDataFlagsEXT,
    pMessageIdName : ptr[char],
    messageIdNumber : i32,
    pMessage : ptr[char],
    queueLabelCount : u32,
    pQueueLabels : ptr[VkDebugUtilsLabelEXT],
    cmdBufLabelCount : u32,
    pCmdBufLabels : ptr[VkDebugUtilsLabelEXT],
    objectCount : u32,
    pObjects : ptr[VkDebugUtilsObjectNameInfoEXT],
}

VkDebugUtilsMessengerCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkDebugUtilsMessengerCreateFlagsEXT,
    messageSeverity : VkDebugUtilsMessageSeverityFlagsEXT,
    messageType : VkDebugUtilsMessageTypeFlagsEXT,
    pfnUserCallback : PFN_vkDebugUtilsMessengerCallbackEXT,
    pUserData : rawptr,
}

VkDebugUtilsObjectTagInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    objectType : VkObjectType,
    objectHandle : u64,
    tagName : u64,
    tagSize : size_t,
    pTag : rawptr,
}

VkSampleLocationEXT :: struct {
    x : f32,
    y : f32,
}

VkSampleLocationsInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    sampleLocationsPerPixel : VkSampleCountFlagBits,
    sampleLocationGridSize : VkExtent2D,
    sampleLocationsCount : u32,
    pSampleLocations : ptr[VkSampleLocationEXT],
}

VkAttachmentSampleLocationsEXT :: struct {
    attachmentIndex : u32,
    sampleLocationsInfo : VkSampleLocationsInfoEXT,
}

VkSubpassSampleLocationsEXT :: struct {
    subpassIndex : u32,
    sampleLocationsInfo : VkSampleLocationsInfoEXT,
}

VkRenderPassSampleLocationsBeginInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    attachmentInitialSampleLocationsCount : u32,
    pAttachmentInitialSampleLocations : ptr[VkAttachmentSampleLocationsEXT],
    postSubpassSampleLocationsCount : u32,
    pPostSubpassSampleLocations : ptr[VkSubpassSampleLocationsEXT],
}

VkPipelineSampleLocationsStateCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    sampleLocationsEnable : VkBool32,
    sampleLocationsInfo : VkSampleLocationsInfoEXT,
}

VkPhysicalDeviceSampleLocationsPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    sampleLocationSampleCounts : VkSampleCountFlags,
    maxSampleLocationGridSize : VkExtent2D,
    sampleLocationCoordinateRange : f32[2],
    sampleLocationSubPixelBits : u32,
    variableSampleLocations : VkBool32,
}

VkMultisamplePropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxSampleLocationGridSize : VkExtent2D,
}

VkPhysicalDeviceBlendOperationAdvancedFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    advancedBlendCoherentOperations : VkBool32,
}

VkPhysicalDeviceBlendOperationAdvancedPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    advancedBlendMaxColorAttachments : u32,
    advancedBlendIndependentBlend : VkBool32,
    advancedBlendNonPremultipliedSrcColor : VkBool32,
    advancedBlendNonPremultipliedDstColor : VkBool32,
    advancedBlendCorrelatedOverlap : VkBool32,
    advancedBlendAllOperations : VkBool32,
}

VkPipelineColorBlendAdvancedStateCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    srcPremultiplied : VkBool32,
    dstPremultiplied : VkBool32,
    blendOverlap : VkBlendOverlapEXT,
}

VkPipelineCoverageToColorStateCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineCoverageToColorStateCreateFlagsNV,
    coverageToColorEnable : VkBool32,
    coverageToColorLocation : u32,
}

VkPipelineCoverageModulationStateCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineCoverageModulationStateCreateFlagsNV,
    coverageModulationMode : VkCoverageModulationModeNV,
    coverageModulationTableEnable : VkBool32,
    coverageModulationTableCount : u32,
    pCoverageModulationTable : ptr[f32],
}

VkPhysicalDeviceShaderSMBuiltinsPropertiesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderSMCount : u32,
    shaderWarpsPerSM : u32,
}

VkPhysicalDeviceShaderSMBuiltinsFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderSMBuiltins : VkBool32,
}

VkDrmFormatModifierPropertiesEXT :: struct {
    drmFormatModifier : u64,
    drmFormatModifierPlaneCount : u32,
    drmFormatModifierTilingFeatures : VkFormatFeatureFlags,
}

VkDrmFormatModifierPropertiesListEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    drmFormatModifierCount : u32,
    pDrmFormatModifierProperties : ptr[VkDrmFormatModifierPropertiesEXT],
}

VkPhysicalDeviceImageDrmFormatModifierInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    drmFormatModifier : u64,
    sharingMode : VkSharingMode,
    queueFamilyIndexCount : u32,
    pQueueFamilyIndices : ptr[u32],
}

VkImageDrmFormatModifierListCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    drmFormatModifierCount : u32,
    pDrmFormatModifiers : ptr[u64],
}

VkImageDrmFormatModifierExplicitCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    drmFormatModifier : u64,
    drmFormatModifierPlaneCount : u32,
    pPlaneLayouts : ptr[VkSubresourceLayout],
}

VkImageDrmFormatModifierPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    drmFormatModifier : u64,
}

VkDrmFormatModifierProperties2EXT :: struct {
    drmFormatModifier : u64,
    drmFormatModifierPlaneCount : u32,
    drmFormatModifierTilingFeatures : VkFormatFeatureFlags2,
}

VkDrmFormatModifierPropertiesList2EXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    drmFormatModifierCount : u32,
    pDrmFormatModifierProperties : ptr[VkDrmFormatModifierProperties2EXT],
}

VkValidationCacheCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkValidationCacheCreateFlagsEXT,
    initialDataSize : size_t,
    pInitialData : rawptr,
}

VkShaderModuleValidationCacheCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    validationCache : VkValidationCacheEXT,
}

VkShadingRatePaletteNV :: struct {
    shadingRatePaletteEntryCount : u32,
    pShadingRatePaletteEntries : ptr[VkShadingRatePaletteEntryNV],
}

VkPipelineViewportShadingRateImageStateCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shadingRateImageEnable : VkBool32,
    viewportCount : u32,
    pShadingRatePalettes : ptr[VkShadingRatePaletteNV],
}

VkPhysicalDeviceShadingRateImageFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shadingRateImage : VkBool32,
    shadingRateCoarseSampleOrder : VkBool32,
}

VkPhysicalDeviceShadingRateImagePropertiesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shadingRateTexelSize : VkExtent2D,
    shadingRatePaletteSize : u32,
    shadingRateMaxCoarseSamples : u32,
}

VkCoarseSampleLocationNV :: struct {
    pixelX : u32,
    pixelY : u32,
    sample : u32,
}

VkCoarseSampleOrderCustomNV :: struct {
    shadingRate : VkShadingRatePaletteEntryNV,
    sampleCount : u32,
    sampleLocationCount : u32,
    pSampleLocations : ptr[VkCoarseSampleLocationNV],
}

VkPipelineViewportCoarseSampleOrderStateCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    sampleOrderType : VkCoarseSampleOrderTypeNV,
    customSampleOrderCount : u32,
    pCustomSampleOrders : ptr[VkCoarseSampleOrderCustomNV],
}

VkRayTracingShaderGroupCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    type : VkRayTracingShaderGroupTypeKHR,
    generalShader : u32,
    closestHitShader : u32,
    anyHitShader : u32,
    intersectionShader : u32,
}

VkRayTracingPipelineCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineCreateFlags,
    stageCount : u32,
    pStages : ptr[VkPipelineShaderStageCreateInfo],
    groupCount : u32,
    pGroups : ptr[VkRayTracingShaderGroupCreateInfoNV],
    maxRecursionDepth : u32,
    layout : VkPipelineLayout,
    basePipelineHandle : VkPipeline,
    basePipelineIndex : i32,
}

VkGeometryTrianglesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    vertexData : VkBuffer,
    vertexOffset : VkDeviceSize,
    vertexCount : u32,
    vertexStride : VkDeviceSize,
    vertexFormat : VkFormat,
    indexData : VkBuffer,
    indexOffset : VkDeviceSize,
    indexCount : u32,
    indexType : VkIndexType,
    transformData : VkBuffer,
    transformOffset : VkDeviceSize,
}

VkGeometryAABBNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    aabbData : VkBuffer,
    numAABBs : u32,
    stride : u32,
    offset : VkDeviceSize,
}

VkGeometryDataNV :: struct {
    triangles : VkGeometryTrianglesNV,
    aabbs : VkGeometryAABBNV,
}

VkGeometryNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    geometryType : VkGeometryTypeKHR,
    geometry : VkGeometryDataNV,
    flags : VkGeometryFlagsKHR,
}

VkAccelerationStructureInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    type : VkAccelerationStructureTypeNV,
    flags : VkBuildAccelerationStructureFlagsNV,
    instanceCount : u32,
    geometryCount : u32,
    pGeometries : ptr[VkGeometryNV],
}

VkAccelerationStructureCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    compactedSize : VkDeviceSize,
    info : VkAccelerationStructureInfoNV,
}

VkBindAccelerationStructureMemoryInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    accelerationStructure : VkAccelerationStructureNV,
    memory : VkDeviceMemory,
    memoryOffset : VkDeviceSize,
    deviceIndexCount : u32,
    pDeviceIndices : ptr[u32],
}

VkWriteDescriptorSetAccelerationStructureNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    accelerationStructureCount : u32,
    pAccelerationStructures : ptr[VkAccelerationStructureNV],
}

VkAccelerationStructureMemoryRequirementsInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    type : VkAccelerationStructureMemoryRequirementsTypeNV,
    accelerationStructure : VkAccelerationStructureNV,
}

VkPhysicalDeviceRayTracingPropertiesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderGroupHandleSize : u32,
    maxRecursionDepth : u32,
    maxShaderGroupStride : u32,
    shaderGroupBaseAlignment : u32,
    maxGeometryCount : u64,
    maxInstanceCount : u64,
    maxTriangleCount : u64,
    maxDescriptorSetAccelerationStructures : u32,
}

VkTransformMatrixKHR :: struct {
    matrix : f32[3][4],
}

VkAabbPositionsKHR :: struct {
    minX : f32,
    minY : f32,
    minZ : f32,
    maxX : f32,
    maxY : f32,
    maxZ : f32,
}

VkAccelerationStructureInstanceKHR :: struct {
    transform : VkTransformMatrixKHR,
    instanceCustomIndex : u32, // TODO(ches) make this 24 bits
    mask : u32, //TODO(ches) make this 8 bits
    instanceShaderBindingTableRecordOffset:24 : u32, // TODO(ches) make this 24 bits
    flags : VkGeometryInstanceFlagsKHR, //TODO(ches) make this 8 bits
    accelerationStructureReference : u64,
}

VkPhysicalDeviceRepresentativeFragmentTestFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    representativeFragmentTest : VkBool32,
}

VkPipelineRepresentativeFragmentTestStateCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    representativeFragmentTestEnable : VkBool32,
}

VkPhysicalDeviceImageViewImageFormatInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    imageViewType : VkImageViewType,
}

VkFilterCubicImageViewImageFormatPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    filterCubic : VkBool32,
    filterCubicMinmax : VkBool32,
}

VkImportMemoryHostPointerInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    handleType : VkExternalMemoryHandleTypeFlagBits,
    pHostPointer : rawptr,
}

VkMemoryHostPointerPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    memoryTypeBits : u32,
}

VkPhysicalDeviceExternalMemoryHostPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    minImportedHostPointerAlignment : VkDeviceSize,
}

VkPipelineCompilerControlCreateInfoAMD :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    compilerControlFlags : VkPipelineCompilerControlFlagsAMD,
}

VkPhysicalDeviceShaderCorePropertiesAMD :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderEngineCount : u32,
    shaderArraysPerEngineCount : u32,
    computeUnitsPerShaderArray : u32,
    simdPerComputeUnit : u32,
    wavefrontsPerSimd : u32,
    wavefrontSize : u32,
    sgprsPerSimd : u32,
    minSgprAllocation : u32,
    maxSgprAllocation : u32,
    sgprAllocationGranularity : u32,
    vgprsPerSimd : u32,
    minVgprAllocation : u32,
    maxVgprAllocation : u32,
    vgprAllocationGranularity : u32,
}

VkDeviceMemoryOverallocationCreateInfoAMD :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    overallocationBehavior : VkMemoryOverallocationBehaviorAMD,
}

VkPhysicalDeviceVertexAttributeDivisorPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxVertexAttribDivisor : u32,
}

VkPhysicalDeviceComputeShaderDerivativesFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    computeDerivativeGroupQuads : VkBool32,
    computeDerivativeGroupLinear : VkBool32,
}

VkPhysicalDeviceMeshShaderFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    taskShader : VkBool32,
    meshShader : VkBool32,
}

VkPhysicalDeviceMeshShaderPropertiesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxDrawMeshTasksCount : u32,
    maxTaskWorkGroupInvocations : u32,
    maxTaskWorkGroupSize[3] : u32,
    maxTaskTotalMemorySize : u32,
    maxTaskOutputCount : u32,
    maxMeshWorkGroupInvocations : u32,
    maxMeshWorkGroupSize[3] : u32,
    maxMeshTotalMemorySize : u32,
    maxMeshOutputVertices : u32,
    maxMeshOutputPrimitives : u32,
    maxMeshMultiviewViewCount : u32,
    meshOutputPerVertexGranularity : u32,
    meshOutputPerPrimitiveGranularity : u32,
}

VkDrawMeshTasksIndirectCommandNV :: struct {
    taskCount : u32,
    firstTask : u32,
}

VkPhysicalDeviceShaderImageFootprintFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    imageFootprint : VkBool32,
}

VkPipelineViewportExclusiveScissorStateCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    exclusiveScissorCount : u32,
    pExclusiveScissors : ptr[VkRect2D],
}

VkPhysicalDeviceExclusiveScissorFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    exclusiveScissor : VkBool32,
}

VkQueueFamilyCheckpointPropertiesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    checkpointExecutionStageMask : VkPipelineStageFlags,
}

VkCheckpointDataNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    stage : VkPipelineStageFlagBits,
    pCheckpointMarker : rawptr,
}

VkPhysicalDeviceShaderIntegerFunctions2FeaturesINTEL :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderIntegerFunctions2 : VkBool32,
}

VkPerformanceValueINTEL :: struct {
    type : VkPerformanceValueTypeINTEL,
    data : VkPerformanceValueDataINTEL,
}

VkInitializePerformanceApiInfoINTEL :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pUserData : rawptr,
}

VkQueryPoolPerformanceQueryCreateInfoINTEL :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    performanceCountersSampling : VkQueryPoolSamplingModeINTEL,
}

VkPerformanceMarkerInfoINTEL :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    marker : u64,
}

VkPerformanceStreamMarkerInfoINTEL :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    marker : u32,
}

VkPerformanceOverrideInfoINTEL :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    type : VkPerformanceOverrideTypeINTEL,
    enable : VkBool32,
    parameter : u64,
}

VkPerformanceConfigurationAcquireInfoINTEL :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    type : VkPerformanceConfigurationTypeINTEL,
}

VkPhysicalDevicePCIBusInfoPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pciDomain : u32,
    pciBus : u32,
    pciDevice : u32,
    pciFunction : u32,
}

VkDisplayNativeHdrSurfaceCapabilitiesAMD :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    localDimmingSupport : VkBool32,
}

VkSwapchainDisplayNativeHdrCreateInfoAMD :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    localDimmingEnable : VkBool32,
}

VkPhysicalDeviceFragmentDensityMapFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    fragmentDensityMap : VkBool32,
    fragmentDensityMapDynamic : VkBool32,
    fragmentDensityMapNonSubsampledImages : VkBool32,
}

VkPhysicalDeviceFragmentDensityMapPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    minFragmentDensityTexelSize : VkExtent2D,
    maxFragmentDensityTexelSize : VkExtent2D,
    fragmentDensityInvocations : VkBool32,
}

VkRenderPassFragmentDensityMapCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    fragmentDensityMapAttachment : VkAttachmentReference,
}

VkPhysicalDeviceShaderCoreProperties2AMD :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderCoreFeatures : VkShaderCorePropertiesFlagsAMD,
    activeComputeUnitCount : u32,
}

VkPhysicalDeviceCoherentMemoryFeaturesAMD :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    deviceCoherentMemory : VkBool32,
}

VkPhysicalDeviceShaderImageAtomicInt64FeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderImageInt64Atomics : VkBool32,
    sparseImageInt64Atomics : VkBool32,
}

VkPhysicalDeviceMemoryBudgetPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    heapBudget : VkDeviceSize[VK_MAX_MEMORY_HEAPS],
    heapUsage : VkDeviceSize[VK_MAX_MEMORY_HEAPS],
}

VkPhysicalDeviceMemoryPriorityFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    memoryPriority : VkBool32,
}

VkMemoryPriorityAllocateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    priority : f32,
}

VkPhysicalDeviceDedicatedAllocationImageAliasingFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    dedicatedAllocationImageAliasing : VkBool32,
}

VkPhysicalDeviceBufferDeviceAddressFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    bufferDeviceAddress : VkBool32,
    bufferDeviceAddressCaptureReplay : VkBool32,
    bufferDeviceAddressMultiDevice : VkBool32,
}

VkBufferDeviceAddressCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    deviceAddress : VkDeviceAddress,
}

VkValidationFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    enabledValidationFeatureCount : u32,
    pEnabledValidationFeatures : ptr[VkValidationFeatureEnableEXT],
    disabledValidationFeatureCount : u32,
    pDisabledValidationFeatures : ptr[VkValidationFeatureDisableEXT],
}

VkCooperativeMatrixPropertiesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    MSize : u32,
    NSize : u32,
    KSize : u32,
    AType : VkComponentTypeNV,
    BType : VkComponentTypeNV,
    CType : VkComponentTypeNV,
    DType : VkComponentTypeNV,
    scope : VkScopeNV,
}

VkPhysicalDeviceCooperativeMatrixFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    cooperativeMatrix : VkBool32,
    cooperativeMatrixRobustBufferAccess : VkBool32,
}

VkPhysicalDeviceCooperativeMatrixPropertiesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    cooperativeMatrixSupportedStages : VkShaderStageFlags,
}

VkPhysicalDeviceCoverageReductionModeFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    coverageReductionMode : VkBool32,
}

VkPipelineCoverageReductionStateCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineCoverageReductionStateCreateFlagsNV,
    coverageReductionMode : VkCoverageReductionModeNV,
}

VkFramebufferMixedSamplesCombinationNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    coverageReductionMode : VkCoverageReductionModeNV,
    rasterizationSamples : VkSampleCountFlagBits,
    depthStencilSamples : VkSampleCountFlags,
    colorSamples : VkSampleCountFlags,
}

VkPhysicalDeviceFragmentShaderInterlockFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    fragmentShaderSampleInterlock : VkBool32,
    fragmentShaderPixelInterlock : VkBool32,
    fragmentShaderShadingRateInterlock : VkBool32,
}

VkPhysicalDeviceYcbcrImageArraysFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    ycbcrImageArrays : VkBool32,
}

VkPhysicalDeviceProvokingVertexFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    provokingVertexLast : VkBool32,
    transformFeedbackPreservesProvokingVertex : VkBool32,
}

VkPhysicalDeviceProvokingVertexPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    provokingVertexModePerPipeline : VkBool32,
    transformFeedbackPreservesTriangleFanProvokingVertex : VkBool32,
}

VkPipelineRasterizationProvokingVertexStateCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    provokingVertexMode : VkProvokingVertexModeEXT,
}

VkHeadlessSurfaceCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkHeadlessSurfaceCreateFlagsEXT,
}

VkPhysicalDeviceShaderAtomicFloatFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderBufferFloat32Atomics : VkBool32,
    shaderBufferFloat32AtomicAdd : VkBool32,
    shaderBufferFloat64Atomics : VkBool32,
    shaderBufferFloat64AtomicAdd : VkBool32,
    shaderSharedFloat32Atomics : VkBool32,
    shaderSharedFloat32AtomicAdd : VkBool32,
    shaderSharedFloat64Atomics : VkBool32,
    shaderSharedFloat64AtomicAdd : VkBool32,
    shaderImageFloat32Atomics : VkBool32,
    shaderImageFloat32AtomicAdd : VkBool32,
    sparseImageFloat32Atomics : VkBool32,
    sparseImageFloat32AtomicAdd : VkBool32,
}

VkPhysicalDeviceExtendedDynamicStateFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    extendedDynamicState : VkBool32,
}

VkPhysicalDeviceHostImageCopyFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    hostImageCopy : VkBool32,
}

VkPhysicalDeviceHostImageCopyPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    copySrcLayoutCount : u32,
    pCopySrcLayouts : ptr[VkImageLayout],
    copyDstLayoutCount : u32,
    pCopyDstLayouts : ptr[VkImageLayout],
    optimalTilingLayoutUUID[VK_UUID_SIZE] : u8,
    identicalMemoryTypeRequirements : VkBool32,
}

VkMemoryToImageCopyEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pHostPointer : rawptr,
    memoryRowLength : u32,
    memoryImageHeight : u32,
    imageSubresource : VkImageSubresourceLayers,
    imageOffset : VkOffset3D,
    imageExtent : VkExtent3D,
}

VkImageToMemoryCopyEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pHostPointer : rawptr,
    memoryRowLength : u32,
    memoryImageHeight : u32,
    imageSubresource : VkImageSubresourceLayers,
    imageOffset : VkOffset3D,
    imageExtent : VkExtent3D,
}

VkCopyMemoryToImageInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkHostImageCopyFlagsEXT,
    dstImage : VkImage,
    dstImageLayout : VkImageLayout,
    regionCount : u32,
    pRegions : ptr[VkMemoryToImageCopyEXT],
}

VkCopyImageToMemoryInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkHostImageCopyFlagsEXT,
    srcImage : VkImage,
    srcImageLayout : VkImageLayout,
    regionCount : u32,
    pRegions : ptr[VkImageToMemoryCopyEXT],
}

VkCopyImageToImageInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkHostImageCopyFlagsEXT,
    srcImage : VkImage,
    srcImageLayout : VkImageLayout,
    dstImage : VkImage,
    dstImageLayout : VkImageLayout,
    regionCount : u32,
    pRegions : ptr[VkImageCopy2],
}

VkHostImageLayoutTransitionInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    image : VkImage,
    oldLayout : VkImageLayout,
    newLayout : VkImageLayout,
    subresourceRange : VkImageSubresourceRange,
}

VkSubresourceHostMemcpySizeEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    size : VkDeviceSize,
}

VkHostImageCopyDevicePerformanceQueryEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    optimalDeviceAccess : VkBool32,
    identicalMemoryLayout : VkBool32,
}

VkPhysicalDeviceMapMemoryPlacedFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    memoryMapPlaced : VkBool32,
    memoryMapRangePlaced : VkBool32,
    memoryUnmapReserve : VkBool32,
}

VkPhysicalDeviceMapMemoryPlacedPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    minPlacedMemoryMapAlignment : VkDeviceSize,
}

VkMemoryMapPlacedInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pPlacedAddress : rawptr,
}

VkPhysicalDeviceShaderAtomicFloat2FeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderBufferFloat16Atomics : VkBool32,
    shaderBufferFloat16AtomicAdd : VkBool32,
    shaderBufferFloat16AtomicMinMax : VkBool32,
    shaderBufferFloat32AtomicMinMax : VkBool32,
    shaderBufferFloat64AtomicMinMax : VkBool32,
    shaderSharedFloat16Atomics : VkBool32,
    shaderSharedFloat16AtomicAdd : VkBool32,
    shaderSharedFloat16AtomicMinMax : VkBool32,
    shaderSharedFloat32AtomicMinMax : VkBool32,
    shaderSharedFloat64AtomicMinMax : VkBool32,
    shaderImageFloat32AtomicMinMax : VkBool32,
    sparseImageFloat32AtomicMinMax : VkBool32,
}

VkSurfacePresentModeEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    presentMode : VkPresentModeKHR,
}

VkSurfacePresentScalingCapabilitiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    supportedPresentScaling : VkPresentScalingFlagsEXT,
    supportedPresentGravityX : VkPresentGravityFlagsEXT,
    supportedPresentGravityY : VkPresentGravityFlagsEXT,
    minScaledImageExtent : VkExtent2D,
    maxScaledImageExtent : VkExtent2D,
}

VkSurfacePresentModeCompatibilityEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    presentModeCount : u32,
    pPresentModes : ptr[VkPresentModeKHR],
}

VkPhysicalDeviceSwapchainMaintenance1FeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    swapchainMaintenance1 : VkBool32,
}

VkSwapchainPresentFenceInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    swapchainCount : u32,
    pFences : ptr[VkFence],
}

VkSwapchainPresentModesCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    presentModeCount : u32,
    pPresentModes : ptr[VkPresentModeKHR],
}

VkSwapchainPresentModeInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    swapchainCount : u32,
    pPresentModes : ptr[VkPresentModeKHR],
}

VkSwapchainPresentScalingCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    scalingBehavior : VkPresentScalingFlagsEXT,
    presentGravityX : VkPresentGravityFlagsEXT,
    presentGravityY : VkPresentGravityFlagsEXT,
}

VkReleaseSwapchainImagesInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    swapchain : VkSwapchainKHR,
    imageIndexCount : u32,
    pImageIndices : ptr[u32],
}

VkPhysicalDeviceDeviceGeneratedCommandsPropertiesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxGraphicsShaderGroupCount : u32,
    maxIndirectSequenceCount : u32,
    maxIndirectCommandsTokenCount : u32,
    maxIndirectCommandsStreamCount : u32,
    maxIndirectCommandsTokenOffset : u32,
    maxIndirectCommandsStreamStride : u32,
    minSequencesCountBufferOffsetAlignment : u32,
    minSequencesIndexBufferOffsetAlignment : u32,
    minIndirectCommandsBufferOffsetAlignment : u32,
}

VkPhysicalDeviceDeviceGeneratedCommandsFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    deviceGeneratedCommands : VkBool32,
}

VkGraphicsShaderGroupCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    stageCount : u32,
    pStages : ptr[VkPipelineShaderStageCreateInfo],
    pVertexInputState : ptr[VkPipelineVertexInputStateCreateInfo],
    pTessellationState : ptr[VkPipelineTessellationStateCreateInfo],
}

VkGraphicsPipelineShaderGroupsCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    groupCount : u32,
    pGroups : ptr[VkGraphicsShaderGroupCreateInfoNV],
    pipelineCount : u32,
    pPipelines : ptr[VkPipeline],
}

VkBindShaderGroupIndirectCommandNV :: struct {
    groupIndex : u32,
}

VkBindIndexBufferIndirectCommandNV :: struct {
    bufferAddress : VkDeviceAddress,
    size : u32,
    indexType : VkIndexType,
}

VkBindVertexBufferIndirectCommandNV :: struct {
    bufferAddress : VkDeviceAddress,
    size : u32,
    stride : u32,
}

VkSetStateFlagsIndirectCommandNV :: struct {
    data : u32,
}

VkIndirectCommandsStreamNV :: struct {
    buffer : VkBuffer,
    offset : VkDeviceSize,
}

VkIndirectCommandsLayoutTokenNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    tokenType : VkIndirectCommandsTokenTypeNV,
    stream : u32,
    offset : u32,
    vertexBindingUnit : u32,
    vertexDynamicStride : VkBool32,
    pushconstantPipelineLayout : VkPipelineLayout,
    pushconstantShaderStageFlags : VkShaderStageFlags,
    pushconstantOffset : u32,
    pushconstantSize : u32,
    indirectStateFlags : VkIndirectStateFlagsNV,
    indexTypeCount : u32,
    pIndexTypes : ptr[VkIndexType],
    pIndexTypeValues : ptr[u32],
}

VkIndirectCommandsLayoutCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkIndirectCommandsLayoutUsageFlagsNV,
    pipelineBindPoint : VkPipelineBindPoint,
    tokenCount : u32,
    pTokens : ptr[VkIndirectCommandsLayoutTokenNV],
    streamCount : u32,
    pStreamStrides : ptr[u32],
}

VkGeneratedCommandsInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pipelineBindPoint : VkPipelineBindPoint,
    pipeline : VkPipeline,
    indirectCommandsLayout : VkIndirectCommandsLayoutNV,
    streamCount : u32,
    pStreams : ptr[VkIndirectCommandsStreamNV],
    sequencesCount : u32,
    preprocessBuffer : VkBuffer,
    preprocessOffset : VkDeviceSize,
    preprocessSize : VkDeviceSize,
    sequencesCountBuffer : VkBuffer,
    sequencesCountOffset : VkDeviceSize,
    sequencesIndexBuffer : VkBuffer,
    sequencesIndexOffset : VkDeviceSize,
}

VkGeneratedCommandsMemoryRequirementsInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pipelineBindPoint : VkPipelineBindPoint,
    pipeline : VkPipeline,
    indirectCommandsLayout : VkIndirectCommandsLayoutNV,
    maxSequencesCount : u32,
}

VkPhysicalDeviceInheritedViewportScissorFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    inheritedViewportScissor2D : VkBool32,
}

VkCommandBufferInheritanceViewportScissorInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    viewportScissor2D : VkBool32,
    viewportDepthCount : u32,
    pViewportDepths : ptr[VkViewport],
}

VkPhysicalDeviceTexelBufferAlignmentFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    texelBufferAlignment : VkBool32,
}

VkRenderPassTransformBeginInfoQCOM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    transform : VkSurfaceTransformFlagBitsKHR,
}

VkCommandBufferInheritanceRenderPassTransformInfoQCOM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    transform : VkSurfaceTransformFlagBitsKHR,
    renderArea : VkRect2D,
}

VkPhysicalDeviceDepthBiasControlFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    depthBiasControl : VkBool32,
    leastRepresentableValueForceUnormRepresentation : VkBool32,
    floatRepresentation : VkBool32,
    depthBiasExact : VkBool32,
}

VkDepthBiasInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    depthBiasConstantFactor : f32,
    depthBiasClamp : f32,
    depthBiasSlopeFactor : f32,
}

VkDepthBiasRepresentationInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    depthBiasRepresentation : VkDepthBiasRepresentationEXT,
    depthBiasExact : VkBool32,
}

VkPhysicalDeviceDeviceMemoryReportFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    deviceMemoryReport : VkBool32,
}

VkDeviceMemoryReportCallbackDataEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkDeviceMemoryReportFlagsEXT,
    type : VkDeviceMemoryReportEventTypeEXT,
    memoryObjectId : u64,
    size : VkDeviceSize,
    objectType : VkObjectType,
    objectHandle : u64,
    heapIndex : u32,
}

VkDeviceDeviceMemoryReportCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkDeviceMemoryReportFlagsEXT,
    pfnUserCallback : PFN_vkDeviceMemoryReportCallbackEXT,
    pUserData : rawptr,
}

VkPhysicalDeviceRobustness2FeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    robustBufferAccess2 : VkBool32,
    robustImageAccess2 : VkBool32,
    nullDescriptor : VkBool32,
}

VkPhysicalDeviceRobustness2PropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    robustStorageBufferAccessSizeAlignment : VkDeviceSize,
    robustUniformBufferAccessSizeAlignment : VkDeviceSize,
}

VkSamplerCustomBorderColorCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    customBorderColor : VkClearColorValue,
    format : VkFormat,
}

VkPhysicalDeviceCustomBorderColorPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxCustomBorderColorSamplers : u32,
}

VkPhysicalDeviceCustomBorderColorFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    customBorderColors : VkBool32,
    customBorderColorWithoutFormat : VkBool32,
}

VkPhysicalDevicePresentBarrierFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    presentBarrier : VkBool32,
}

VkSurfaceCapabilitiesPresentBarrierNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    presentBarrierSupported : VkBool32,
}

VkSwapchainPresentBarrierCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    presentBarrierEnable : VkBool32,
}

VkPhysicalDeviceDiagnosticsConfigFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    diagnosticsConfig : VkBool32,
}

VkDeviceDiagnosticsConfigCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkDeviceDiagnosticsConfigFlagsNV,
}

VkCudaModuleCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    dataSize : size_t,
    pData : rawptr,
}

VkCudaFunctionCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    module : VkCudaModuleNV,
    pName : ptr[char],
}

VkCudaLaunchInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    function : VkCudaFunctionNV,
    gridDimX : u32,
    gridDimY : u32,
    gridDimZ : u32,
    blockDimX : u32,
    blockDimY : u32,
    blockDimZ : u32,
    sharedMemBytes : u32,
    paramCount : size_t,
    pParams : ptr[rawptr],
    extraCount : size_t,
    pExtras : ptr[rawptr],
}

VkPhysicalDeviceCudaKernelLaunchFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    cudaKernelLaunchFeatures : VkBool32,
}

VkPhysicalDeviceCudaKernelLaunchPropertiesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    computeCapabilityMinor : u32,
    computeCapabilityMajor : u32,
}

VkQueryLowLatencySupportNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pQueriedLowLatencyData : rawptr,
}

VkPhysicalDeviceDescriptorBufferPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    combinedImageSamplerDescriptorSingleArray : VkBool32,
    bufferlessPushDescriptors : VkBool32,
    allowSamplerImageViewPostSubmitCreation : VkBool32,
    descriptorBufferOffsetAlignment : VkDeviceSize,
    maxDescriptorBufferBindings : u32,
    maxResourceDescriptorBufferBindings : u32,
    maxSamplerDescriptorBufferBindings : u32,
    maxEmbeddedImmutableSamplerBindings : u32,
    maxEmbeddedImmutableSamplers : u32,
    bufferCaptureReplayDescriptorDataSize : size_t,
    imageCaptureReplayDescriptorDataSize : size_t,
    imageViewCaptureReplayDescriptorDataSize : size_t,
    samplerCaptureReplayDescriptorDataSize : size_t,
    accelerationStructureCaptureReplayDescriptorDataSize : size_t,
    samplerDescriptorSize : size_t,
    combinedImageSamplerDescriptorSize : size_t,
    sampledImageDescriptorSize : size_t,
    storageImageDescriptorSize : size_t,
    uniformTexelBufferDescriptorSize : size_t,
    robustUniformTexelBufferDescriptorSize : size_t,
    storageTexelBufferDescriptorSize : size_t,
    robustStorageTexelBufferDescriptorSize : size_t,
    uniformBufferDescriptorSize : size_t,
    robustUniformBufferDescriptorSize : size_t,
    storageBufferDescriptorSize : size_t,
    robustStorageBufferDescriptorSize : size_t,
    inputAttachmentDescriptorSize : size_t,
    accelerationStructureDescriptorSize : size_t,
    maxSamplerDescriptorBufferRange : VkDeviceSize,
    maxResourceDescriptorBufferRange : VkDeviceSize,
    samplerDescriptorBufferAddressSpaceSize : VkDeviceSize,
    resourceDescriptorBufferAddressSpaceSize : VkDeviceSize,
    descriptorBufferAddressSpaceSize : VkDeviceSize,
}

VkPhysicalDeviceDescriptorBufferDensityMapPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    combinedImageSamplerDensityMapDescriptorSize : size_t,
}

VkPhysicalDeviceDescriptorBufferFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    descriptorBuffer : VkBool32,
    descriptorBufferCaptureReplay : VkBool32,
    descriptorBufferImageLayoutIgnored : VkBool32,
    descriptorBufferPushDescriptors : VkBool32,
}

VkDescriptorAddressInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    address : VkDeviceAddress,
    range : VkDeviceSize,
    format : VkFormat,
}

VkDescriptorBufferBindingInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    address : VkDeviceAddress,
    usage : VkBufferUsageFlags,
}

VkDescriptorBufferBindingPushDescriptorBufferHandleEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    buffer : VkBuffer,
}

VkDescriptorGetInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    type : VkDescriptorType,
    data : VkDescriptorDataEXT,
}

VkBufferCaptureDescriptorDataInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    buffer : VkBuffer,
}

VkImageCaptureDescriptorDataInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    image : VkImage,
}

VkImageViewCaptureDescriptorDataInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    imageView : VkImageView,
}

VkSamplerCaptureDescriptorDataInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    sampler : VkSampler,
}

VkOpaqueCaptureDescriptorDataCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    opaqueCaptureDescriptorData : rawptr,
}

VkAccelerationStructureCaptureDescriptorDataInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    accelerationStructure : VkAccelerationStructureKHR,
    accelerationStructureNV : VkAccelerationStructureNV,
}

VkPhysicalDeviceGraphicsPipelineLibraryFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    graphicsPipelineLibrary : VkBool32,
}

VkPhysicalDeviceGraphicsPipelineLibraryPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    graphicsPipelineLibraryFastLinking : VkBool32,
    graphicsPipelineLibraryIndependentInterpolationDecoration : VkBool32,
}

VkGraphicsPipelineLibraryCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkGraphicsPipelineLibraryFlagsEXT,
}

VkPhysicalDeviceShaderEarlyAndLateFragmentTestsFeaturesAMD :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderEarlyAndLateFragmentTests : VkBool32,
}

VkPhysicalDeviceFragmentShadingRateEnumsFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    fragmentShadingRateEnums : VkBool32,
    supersampleFragmentShadingRates : VkBool32,
    noInvocationFragmentShadingRates : VkBool32,
}

VkPhysicalDeviceFragmentShadingRateEnumsPropertiesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxFragmentShadingRateInvocationCount : VkSampleCountFlagBits,
}

VkPipelineFragmentShadingRateEnumStateCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shadingRateType : VkFragmentShadingRateTypeNV,
    shadingRate : VkFragmentShadingRateNV,
    combinerOps : VkFragmentShadingRateCombinerOpKHR[2],
}

VkAccelerationStructureGeometryMotionTrianglesDataNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    vertexData : VkDeviceOrHostAddressConstKHR,
}

VkAccelerationStructureMotionInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxInstances : u32,
    flags : VkAccelerationStructureMotionInfoFlagsNV,
}

VkAccelerationStructureMatrixMotionInstanceNV :: struct {
    transformT0 : VkTransformMatrixKHR,
    transformT1 : VkTransformMatrixKHR,
    instanceCustomIndex : u32, //TODO(ches) make this 24 bits
    mask : u32, //TODO(ches) make this 8 bits
    instanceShaderBindingTableRecordOffset : u32, //TODO(ches) make this 24 bits
    flags : VkGeometryInstanceFlagsKHR, //TODO(ches) make this 8 bits
    accelerationStructureReference : u64,
}

VkSRTDataNV :: struct {
    sx : f32,
    a : f32,
    b : f32,
    pvx : f32,
    sy : f32,
    c : f32,
    pvy : f32,
    sz : f32,
    pvz : f32,
    qx : f32,
    qy : f32,
    qz : f32,
    qw : f32,
    tx : f32,
    ty : f32,
    tz : f32,
}

VkAccelerationStructureSRTMotionInstanceNV :: struct {
    transformT0 : VkSRTDataNV,
    transformT1 : VkSRTDataNV,
    instanceCustomIndex : u32, //TODO(ches) make this 24 bits
    mask : u32, //TODO(ches) make this 8 bits
    instanceShaderBindingTableRecordOffset : u32, //TODO(ches) make this 24 bits
    flags : VkGeometryInstanceFlagsKHR, //TODO(ches) make this 8 bits
    accelerationStructureReference : u64,
}

VkAccelerationStructureMotionInstanceNV :: struct {
    type : VkAccelerationStructureMotionInstanceTypeNV,
    flags : VkAccelerationStructureMotionInstanceFlagsNV,
    data : VkAccelerationStructureMotionInstanceDataNV,
}

VkPhysicalDeviceRayTracingMotionBlurFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    rayTracingMotionBlur : VkBool32,
    rayTracingMotionBlurPipelineTraceRaysIndirect : VkBool32,
}

VkPhysicalDeviceYcbcr2Plane444FormatsFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    ycbcr2plane444Formats : VkBool32,
}

VkPhysicalDeviceFragmentDensityMap2FeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    fragmentDensityMapDeferred : VkBool32,
}

VkPhysicalDeviceFragmentDensityMap2PropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    subsampledLoads : VkBool32,
    subsampledCoarseReconstructionEarlyAccess : VkBool32,
    maxSubsampledArrayLayers : u32,
    maxDescriptorSetSubsampledSamplers : u32,
}

VkCopyCommandTransformInfoQCOM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    transform : VkSurfaceTransformFlagBitsKHR,
}

VkPhysicalDeviceImageCompressionControlFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    imageCompressionControl : VkBool32,
}

VkImageCompressionControlEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkImageCompressionFlagsEXT,
    compressionControlPlaneCount : u32,
    pFixedRateFlags : ptr[VkImageCompressionFixedRateFlagsEXT],
}

VkImageCompressionPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    imageCompressionFlags : VkImageCompressionFlagsEXT,
    imageCompressionFixedRateFlags : VkImageCompressionFixedRateFlagsEXT,
}

VkPhysicalDeviceAttachmentFeedbackLoopLayoutFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    attachmentFeedbackLoopLayout : VkBool32,
}

VkPhysicalDevice4444FormatsFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    formatA4R4G4B4 : VkBool32,
    formatA4B4G4R4 : VkBool32,
}

VkPhysicalDeviceFaultFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    deviceFault : VkBool32,
    deviceFaultVendorBinary : VkBool32,
}

VkDeviceFaultCountsEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    addressInfoCount : u32,
    vendorInfoCount : u32,
    vendorBinarySize : VkDeviceSize,
}

VkDeviceFaultAddressInfoEXT :: struct {
    addressType : VkDeviceFaultAddressTypeEXT,
    reportedAddress : VkDeviceAddress,
    addressPrecision : VkDeviceSize,
}

VkDeviceFaultVendorInfoEXT :: struct {
    description : char[VK_MAX_DESCRIPTION_SIZE],
    vendorFaultCode : u64,
    vendorFaultData : u64,
}

VkDeviceFaultInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    description : char[VK_MAX_DESCRIPTION_SIZE],
    pAddressInfos : ptr[VkDeviceFaultAddressInfoEXT],
    pVendorInfos : ptr[VkDeviceFaultVendorInfoEXT],
    pVendorBinaryData : rawptr,
}

VkDeviceFaultVendorBinaryHeaderVersionOneEXT :: struct {
    headerSize : u32,
    headerVersion : VkDeviceFaultVendorBinaryHeaderVersionEXT,
    vendorID : u32,
    deviceID : u32,
    driverVersion : u32,
    pipelineCacheUUID[VK_UUID_SIZE] : u8,
    applicationNameOffset : u32,
    applicationVersion : u32,
    engineNameOffset : u32,
    engineVersion : u32,
    apiVersion : u32,
}

VkPhysicalDeviceRasterizationOrderAttachmentAccessFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    rasterizationOrderColorAttachmentAccess : VkBool32,
    rasterizationOrderDepthAttachmentAccess : VkBool32,
    rasterizationOrderStencilAttachmentAccess : VkBool32,
}

VkPhysicalDeviceRGBA10X6FormatsFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    formatRgba10x6WithoutYCbCrSampler : VkBool32,
}

VkPhysicalDeviceMutableDescriptorTypeFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    mutableDescriptorType : VkBool32,
}

VkMutableDescriptorTypeListEXT :: struct {
    descriptorTypeCount : u32,
    pDescriptorTypes : ptr[VkDescriptorType],
}

VkMutableDescriptorTypeCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    mutableDescriptorTypeListCount : u32,
    pMutableDescriptorTypeLists : ptr[VkMutableDescriptorTypeListEXT],
}

VkPhysicalDeviceVertexInputDynamicStateFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    vertexInputDynamicState : VkBool32,
}

VkVertexInputBindingDescription2EXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    binding : u32,
    stride : u32,
    inputRate : VkVertexInputRate,
    divisor : u32,
}

VkVertexInputAttributeDescription2EXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    location : u32,
    binding : u32,
    format : VkFormat,
    offset : u32,
}

VkPhysicalDeviceDrmPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    hasPrimary : VkBool32,
    hasRender : VkBool32,
    primaryMajor : i64,
    primaryMinor : i64,
    renderMajor : i64,
    renderMinor : i64,
}

VkPhysicalDeviceAddressBindingReportFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    reportAddressBinding : VkBool32,
}

VkDeviceAddressBindingCallbackDataEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkDeviceAddressBindingFlagsEXT,
    baseAddress : VkDeviceAddress,
    size : VkDeviceSize,
    bindingType : VkDeviceAddressBindingTypeEXT,
}

VkPhysicalDeviceDepthClipControlFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    depthClipControl : VkBool32,
}

VkPipelineViewportDepthClipControlCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    negativeOneToOne : VkBool32,
}

VkPhysicalDevicePrimitiveTopologyListRestartFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    primitiveTopologyListRestart : VkBool32,
    primitiveTopologyPatchListRestart : VkBool32,
}

VkSubpassShadingPipelineCreateInfoHUAWEI :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    renderPass : VkRenderPass,
    subpass : u32,
}

VkPhysicalDeviceSubpassShadingFeaturesHUAWEI :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    subpassShading : VkBool32,
}

VkPhysicalDeviceSubpassShadingPropertiesHUAWEI :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxSubpassShadingWorkgroupSizeAspectRatio : u32,
}

VkPhysicalDeviceInvocationMaskFeaturesHUAWEI :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    invocationMask : VkBool32,
}

VkMemoryGetRemoteAddressInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    memory : VkDeviceMemory,
    handleType : VkExternalMemoryHandleTypeFlagBits,
}

VkPhysicalDeviceExternalMemoryRDMAFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    externalMemoryRDMA : VkBool32,
}

VkPipelinePropertiesIdentifierEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pipelineIdentifier[VK_UUID_SIZE] : u8,
}

VkPhysicalDevicePipelinePropertiesFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pipelinePropertiesIdentifier : VkBool32,
}

VkPhysicalDeviceFrameBoundaryFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    frameBoundary : VkBool32,
}

VkFrameBoundaryEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkFrameBoundaryFlagsEXT,
    frameID : u64,
    imageCount : u32,
    pImages : ptr[VkImage],
    bufferCount : u32,
    pBuffers : ptr[VkBuffer],
    tagName : u64,
    tagSize : size_t,
    pTag : rawptr,
}

VkPhysicalDeviceMultisampledRenderToSingleSampledFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    multisampledRenderToSingleSampled : VkBool32,
}

VkSubpassResolvePerformanceQueryEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    optimal : VkBool32,
}

VkMultisampledRenderToSingleSampledInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    multisampledRenderToSingleSampledEnable : VkBool32,
    rasterizationSamples : VkSampleCountFlagBits,
}

VkPhysicalDeviceExtendedDynamicState2FeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    extendedDynamicState2 : VkBool32,
    extendedDynamicState2LogicOp : VkBool32,
    extendedDynamicState2PatchControlPoints : VkBool32,
}

VkPhysicalDeviceColorWriteEnableFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    colorWriteEnable : VkBool32,
}

VkPipelineColorWriteCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    attachmentCount : u32,
    pColorWriteEnables : ptr[VkBool32],
}

VkPhysicalDevicePrimitivesGeneratedQueryFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    primitivesGeneratedQuery : VkBool32,
    primitivesGeneratedQueryWithRasterizerDiscard : VkBool32,
    primitivesGeneratedQueryWithNonZeroStreams : VkBool32,
}

VkPhysicalDeviceImageViewMinLodFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    minLod : VkBool32,
}

VkImageViewMinLodCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    minLod : f32,
}

VkPhysicalDeviceMultiDrawFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    multiDraw : VkBool32,
}

VkPhysicalDeviceMultiDrawPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxMultiDrawCount : u32,
}

VkMultiDrawInfoEXT :: struct {
    firstVertex : u32,
    vertexCount : u32,
}

VkMultiDrawIndexedInfoEXT :: struct {
    firstIndex : u32,
    indexCount : u32,
    vertexOffset : i32,
}

VkPhysicalDeviceImage2DViewOf3DFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    image2DViewOf3D : VkBool32,
    sampler2DViewOf3D : VkBool32,
}

VkPhysicalDeviceShaderTileImageFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderTileImageColorReadAccess : VkBool32,
    shaderTileImageDepthReadAccess : VkBool32,
    shaderTileImageStencilReadAccess : VkBool32,
}

VkPhysicalDeviceShaderTileImagePropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderTileImageCoherentReadAccelerated : VkBool32,
    shaderTileImageReadSampleFromPixelRateInvocation : VkBool32,
    shaderTileImageReadFromHelperInvocation : VkBool32,
}

VkMicromapUsageEXT :: struct {
    count : u32,
    subdivisionLevel : u32,
    format : u32,
}

VkMicromapBuildInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    type : VkMicromapTypeEXT,
    flags : VkBuildMicromapFlagsEXT,
    mode : VkBuildMicromapModeEXT,
    dstMicromap : VkMicromapEXT,
    usageCountsCount : u32,
    pUsageCounts : ptr[VkMicromapUsageEXT],
    ppUsageCounts : ptr[ptr[VkMicromapUsageEXT]],
    data : VkDeviceOrHostAddressConstKHR,
    scratchData : VkDeviceOrHostAddressKHR,
    triangleArray : VkDeviceOrHostAddressConstKHR,
    triangleArrayStride : VkDeviceSize,
}

VkMicromapCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    createFlags : VkMicromapCreateFlagsEXT,
    buffer : VkBuffer,
    offset : VkDeviceSize,
    size : VkDeviceSize,
    type : VkMicromapTypeEXT,
    deviceAddress : VkDeviceAddress,
}

VkPhysicalDeviceOpacityMicromapFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    micromap : VkBool32,
    micromapCaptureReplay : VkBool32,
    micromapHostCommands : VkBool32,
}

VkPhysicalDeviceOpacityMicromapPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxOpacity2StateSubdivisionLevel : u32,
    maxOpacity4StateSubdivisionLevel : u32,
}

VkMicromapVersionInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pVersionData : ptr[u8],
}

VkCopyMicromapToMemoryInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    src : VkMicromapEXT,
    dst : VkDeviceOrHostAddressKHR,
    mode : VkCopyMicromapModeEXT,
}

VkCopyMemoryToMicromapInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    src : VkDeviceOrHostAddressConstKHR,
    dst : VkMicromapEXT,
    mode : VkCopyMicromapModeEXT,
}

VkCopyMicromapInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    src : VkMicromapEXT,
    dst : VkMicromapEXT,
    mode : VkCopyMicromapModeEXT,
}

VkMicromapBuildSizesInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    micromapSize : VkDeviceSize,
    buildScratchSize : VkDeviceSize,
    discardable : VkBool32,
}

VkAccelerationStructureTrianglesOpacityMicromapEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    indexType : VkIndexType,
    indexBuffer : VkDeviceOrHostAddressConstKHR,
    indexStride : VkDeviceSize,
    baseTriangle : u32,
    usageCountsCount : u32,
    pUsageCounts : ptr[VkMicromapUsageEXT],
    ppUsageCounts : ptr[ptr[VkMicromapUsageEXT]],
    micromap : VkMicromapEXT,
}

VkMicromapTriangleEXT :: struct {
    dataOffset : u32,
    subdivisionLevel : u16,
    format : u16,
}

VkPhysicalDeviceClusterCullingShaderFeaturesHUAWEI :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    clustercullingShader : VkBool32,
    multiviewClusterCullingShader : VkBool32,
}

VkPhysicalDeviceClusterCullingShaderPropertiesHUAWEI :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxWorkGroupCount[3] : u32,
    maxWorkGroupSize[3] : u32,
    maxOutputClusterCount : u32,
    indirectBufferOffsetAlignment : VkDeviceSize,
}

VkPhysicalDeviceClusterCullingShaderVrsFeaturesHUAWEI :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    clusterShadingRate : VkBool32,
}

VkPhysicalDeviceBorderColorSwizzleFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    borderColorSwizzle : VkBool32,
    borderColorSwizzleFromImage : VkBool32,
}

VkSamplerBorderColorComponentMappingCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    components : VkComponentMapping,
    srgb : VkBool32,
}

VkPhysicalDevicePageableDeviceLocalMemoryFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pageableDeviceLocalMemory : VkBool32,
}

VkPhysicalDeviceShaderCorePropertiesARM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pixelRate : u32,
    texelRate : u32,
    fmaRate : u32,
}

VkDeviceQueueShaderCoreControlCreateInfoARM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderCoreCount : u32,
}

VkPhysicalDeviceSchedulingControlsFeaturesARM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    schedulingControls : VkBool32,
}

VkPhysicalDeviceSchedulingControlsPropertiesARM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    schedulingControlsFlags : VkPhysicalDeviceSchedulingControlsFlagsARM,
}

VkPhysicalDeviceImageSlicedViewOf3DFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    imageSlicedViewOf3D : VkBool32,
}

VkImageViewSlicedCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    sliceOffset : u32,
    sliceCount : u32,
}

VkPhysicalDeviceDescriptorSetHostMappingFeaturesVALVE :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    descriptorSetHostMapping : VkBool32,
}

VkDescriptorSetBindingReferenceVALVE :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    descriptorSetLayout : VkDescriptorSetLayout,
    binding : u32,
}

VkDescriptorSetLayoutHostMappingInfoVALVE :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    descriptorOffset : size_t,
    descriptorSize : u32,
}

VkPhysicalDeviceDepthClampZeroOneFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    depthClampZeroOne : VkBool32,
}

VkPhysicalDeviceNonSeamlessCubeMapFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    nonSeamlessCubeMap : VkBool32,
}

VkPhysicalDeviceRenderPassStripedFeaturesARM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    renderPassStriped : VkBool32,
}

VkPhysicalDeviceRenderPassStripedPropertiesARM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    renderPassStripeGranularity : VkExtent2D,
    maxRenderPassStripes : u32,
}

VkRenderPassStripeInfoARM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    stripeArea : VkRect2D,
}

VkRenderPassStripeBeginInfoARM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    stripeInfoCount : u32,
    pStripeInfos : ptr[VkRenderPassStripeInfoARM],
}

VkRenderPassStripeSubmitInfoARM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    stripeSemaphoreInfoCount : u32,
    pStripeSemaphoreInfos : ptr[VkSemaphoreSubmitInfo],
}

VkPhysicalDeviceFragmentDensityMapOffsetFeaturesQCOM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    fragmentDensityMapOffset : VkBool32,
}

VkPhysicalDeviceFragmentDensityMapOffsetPropertiesQCOM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    fragmentDensityOffsetGranularity : VkExtent2D,
}

VkSubpassFragmentDensityMapOffsetEndInfoQCOM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    fragmentDensityOffsetCount : u32,
    pFragmentDensityOffsets : ptr[VkOffset2D],
}

VkCopyMemoryIndirectCommandNV :: struct {
    srcAddress : VkDeviceAddress,
    dstAddress : VkDeviceAddress,
    size : VkDeviceSize,
}

VkCopyMemoryToImageIndirectCommandNV :: struct {
    srcAddress : VkDeviceAddress,
    bufferRowLength : u32,
    bufferImageHeight : u32,
    imageSubresource : VkImageSubresourceLayers,
    imageOffset : VkOffset3D,
    imageExtent : VkExtent3D,
}

VkPhysicalDeviceCopyMemoryIndirectFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    indirectCopy : VkBool32,
}

VkPhysicalDeviceCopyMemoryIndirectPropertiesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    supportedQueues : VkQueueFlags,
}

VkDecompressMemoryRegionNV :: struct {
    srcAddress : VkDeviceAddress,
    dstAddress : VkDeviceAddress,
    compressedSize : VkDeviceSize,
    decompressedSize : VkDeviceSize,
    decompressionMethod : VkMemoryDecompressionMethodFlagsNV,
}

VkPhysicalDeviceMemoryDecompressionFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    memoryDecompression : VkBool32,
}

VkPhysicalDeviceMemoryDecompressionPropertiesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    decompressionMethods : VkMemoryDecompressionMethodFlagsNV,
    maxDecompressionIndirectCount : u64,
}

VkPhysicalDeviceDeviceGeneratedCommandsComputeFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    deviceGeneratedCompute : VkBool32,
    deviceGeneratedComputePipelines : VkBool32,
    deviceGeneratedComputeCaptureReplay : VkBool32,
}

VkComputePipelineIndirectBufferInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    deviceAddress : VkDeviceAddress,
    size : VkDeviceSize,
    pipelineDeviceAddressCaptureReplay : VkDeviceAddress,
}

VkPipelineIndirectDeviceAddressInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pipelineBindPoint : VkPipelineBindPoint,
    pipeline : VkPipeline,
}

VkBindPipelineIndirectCommandNV :: struct {
    pipelineAddress : VkDeviceAddress,
}

VkPhysicalDeviceLinearColorAttachmentFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    linearColorAttachment : VkBool32,
}

VkPhysicalDeviceImageCompressionControlSwapchainFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    imageCompressionControlSwapchain : VkBool32,
}

VkImageViewSampleWeightCreateInfoQCOM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    filterCenter : VkOffset2D,
    filterSize : VkExtent2D,
    numPhases : u32,
}

VkPhysicalDeviceImageProcessingFeaturesQCOM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    textureSampleWeighted : VkBool32,
    textureBoxFilter : VkBool32,
    textureBlockMatch : VkBool32,
}

VkPhysicalDeviceImageProcessingPropertiesQCOM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxWeightFilterPhases : u32,
    maxWeightFilterDimension : VkExtent2D,
    maxBlockMatchRegion : VkExtent2D,
    maxBoxFilterBlockSize : VkExtent2D,
}

VkPhysicalDeviceNestedCommandBufferFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    nestedCommandBuffer : VkBool32,
    nestedCommandBufferRendering : VkBool32,
    nestedCommandBufferSimultaneousUse : VkBool32,
}

VkPhysicalDeviceNestedCommandBufferPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxCommandBufferNestingLevel : u32,
}

VkExternalMemoryAcquireUnmodifiedEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    acquireUnmodifiedMemory : VkBool32,
}

VkPhysicalDeviceExtendedDynamicState3FeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    extendedDynamicState3TessellationDomainOrigin : VkBool32,
    extendedDynamicState3DepthClampEnable : VkBool32,
    extendedDynamicState3PolygonMode : VkBool32,
    extendedDynamicState3RasterizationSamples : VkBool32,
    extendedDynamicState3SampleMask : VkBool32,
    extendedDynamicState3AlphaToCoverageEnable : VkBool32,
    extendedDynamicState3AlphaToOneEnable : VkBool32,
    extendedDynamicState3LogicOpEnable : VkBool32,
    extendedDynamicState3ColorBlendEnable : VkBool32,
    extendedDynamicState3ColorBlendEquation : VkBool32,
    extendedDynamicState3ColorWriteMask : VkBool32,
    extendedDynamicState3RasterizationStream : VkBool32,
    extendedDynamicState3ConservativeRasterizationMode : VkBool32,
    extendedDynamicState3ExtraPrimitiveOverestimationSize : VkBool32,
    extendedDynamicState3DepthClipEnable : VkBool32,
    extendedDynamicState3SampleLocationsEnable : VkBool32,
    extendedDynamicState3ColorBlendAdvanced : VkBool32,
    extendedDynamicState3ProvokingVertexMode : VkBool32,
    extendedDynamicState3LineRasterizationMode : VkBool32,
    extendedDynamicState3LineStippleEnable : VkBool32,
    extendedDynamicState3DepthClipNegativeOneToOne : VkBool32,
    extendedDynamicState3ViewportWScalingEnable : VkBool32,
    extendedDynamicState3ViewportSwizzle : VkBool32,
    extendedDynamicState3CoverageToColorEnable : VkBool32,
    extendedDynamicState3CoverageToColorLocation : VkBool32,
    extendedDynamicState3CoverageModulationMode : VkBool32,
    extendedDynamicState3CoverageModulationTableEnable : VkBool32,
    extendedDynamicState3CoverageModulationTable : VkBool32,
    extendedDynamicState3CoverageReductionMode : VkBool32,
    extendedDynamicState3RepresentativeFragmentTestEnable : VkBool32,
    extendedDynamicState3ShadingRateImageEnable : VkBool32,
}

VkPhysicalDeviceExtendedDynamicState3PropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    dynamicPrimitiveTopologyUnrestricted : VkBool32,
}

VkColorBlendEquationEXT :: struct {
    srcColorBlendFactor : VkBlendFactor,
    dstColorBlendFactor : VkBlendFactor,
    colorBlendOp : VkBlendOp,
    srcAlphaBlendFactor : VkBlendFactor,
    dstAlphaBlendFactor : VkBlendFactor,
    alphaBlendOp : VkBlendOp,
}

VkColorBlendAdvancedEXT :: struct {
    advancedBlendOp : VkBlendOp,
    srcPremultiplied : VkBool32,
    dstPremultiplied : VkBool32,
    blendOverlap : VkBlendOverlapEXT,
    clampResults : VkBool32,
}

VkPhysicalDeviceSubpassMergeFeedbackFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    subpassMergeFeedback : VkBool32,
}

VkRenderPassCreationControlEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    disallowMerging : VkBool32,
}

VkRenderPassCreationFeedbackInfoEXT :: struct {
    postMergeSubpassCount : u32,
}

VkRenderPassCreationFeedbackCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pRenderPassFeedback : ptr[VkRenderPassCreationFeedbackInfoEXT],
}

VkRenderPassSubpassFeedbackInfoEXT :: struct {
    subpassMergeStatus : VkSubpassMergeStatusEXT,
    description : char[VK_MAX_DESCRIPTION_SIZE],
    postMergeIndex : u32,
}

VkRenderPassSubpassFeedbackCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pSubpassFeedback : ptr[VkRenderPassSubpassFeedbackInfoEXT],
}

VkDirectDriverLoadingInfoLUNARG :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkDirectDriverLoadingFlagsLUNARG,
    pfnGetInstanceProcAddr : PFN_vkGetInstanceProcAddrLUNARG,
}

VkDirectDriverLoadingListLUNARG :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    mode : VkDirectDriverLoadingModeLUNARG,
    driverCount : u32,
    pDrivers : ptr[VkDirectDriverLoadingInfoLUNARG],
}

VkPhysicalDeviceShaderModuleIdentifierFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderModuleIdentifier : VkBool32,
}

VkPhysicalDeviceShaderModuleIdentifierPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderModuleIdentifierAlgorithmUUID[VK_UUID_SIZE] : u8,
}

VkPipelineShaderStageModuleIdentifierCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    identifierSize : u32,
    pIdentifier : ptr[u8],
}

VkShaderModuleIdentifierEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    identifierSize : u32,
    identifier[VK_MAX_SHADER_MODULE_IDENTIFIER_SIZE_EXT] : u8,
}

VkPhysicalDeviceOpticalFlowFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    opticalFlow : VkBool32,
}

VkPhysicalDeviceOpticalFlowPropertiesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    supportedOutputGridSizes : VkOpticalFlowGridSizeFlagsNV,
    supportedHintGridSizes : VkOpticalFlowGridSizeFlagsNV,
    hintSupported : VkBool32,
    costSupported : VkBool32,
    bidirectionalFlowSupported : VkBool32,
    globalFlowSupported : VkBool32,
    minWidth : u32,
    minHeight : u32,
    maxWidth : u32,
    maxHeight : u32,
    maxNumRegionsOfInterest : u32,
}

VkOpticalFlowImageFormatInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    usage : VkOpticalFlowUsageFlagsNV,
}

VkOpticalFlowImageFormatPropertiesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    format : VkFormat,
}

VkOpticalFlowSessionCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    width : u32,
    height : u32,
    imageFormat : VkFormat,
    flowVectorFormat : VkFormat,
    costFormat : VkFormat,
    outputGridSize : VkOpticalFlowGridSizeFlagsNV,
    hintGridSize : VkOpticalFlowGridSizeFlagsNV,
    performanceLevel : VkOpticalFlowPerformanceLevelNV,
    flags : VkOpticalFlowSessionCreateFlagsNV,
}

VkOpticalFlowSessionCreatePrivateDataInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    id : u32,
    size : u32,
    pPrivateData : rawptr,
}

VkOpticalFlowExecuteInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkOpticalFlowExecuteFlagsNV,
    regionCount : u32,
    pRegions : ptr[VkRect2D],
}

VkPhysicalDeviceLegacyDitheringFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    legacyDithering : VkBool32,
}

VkPhysicalDevicePipelineProtectedAccessFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pipelineProtectedAccess : VkBool32,
}

VkPhysicalDeviceShaderObjectFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderObject : VkBool32,
}

VkPhysicalDeviceShaderObjectPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderBinaryUUID[VK_UUID_SIZE] : u8,
    shaderBinaryVersion : u32,
}

VkShaderCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkShaderCreateFlagsEXT,
    stage : VkShaderStageFlagBits,
    nextStage : VkShaderStageFlags,
    codeType : VkShaderCodeTypeEXT,
    codeSize : size_t,
    pCode : rawptr,
    pName : ptr[char],
    setLayoutCount : u32,
    pSetLayouts : ptr[VkDescriptorSetLayout],
    pushConstantRangeCount : u32,
    pPushConstantRanges : ptr[VkPushConstantRange],
    pSpecializationInfo : ptr[VkSpecializationInfo],
}

VkPhysicalDeviceTilePropertiesFeaturesQCOM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    tileProperties : VkBool32,
}

VkTilePropertiesQCOM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    tileSize : VkExtent3D,
    apronSize : VkExtent2D,
    origin : VkOffset2D,
}

VkPhysicalDeviceAmigoProfilingFeaturesSEC :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    amigoProfiling : VkBool32,
}

VkAmigoProfilingSubmitInfoSEC :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    firstDrawTimestamp : u64,
    swapBufferTimestamp : u64,
}

VkPhysicalDeviceMultiviewPerViewViewportsFeaturesQCOM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    multiviewPerViewViewports : VkBool32,
}

VkPhysicalDeviceRayTracingInvocationReorderPropertiesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    rayTracingInvocationReorderReorderingHint : VkRayTracingInvocationReorderModeNV,
}

VkPhysicalDeviceRayTracingInvocationReorderFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    rayTracingInvocationReorder : VkBool32,
}

VkPhysicalDeviceExtendedSparseAddressSpaceFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    extendedSparseAddressSpace : VkBool32,
}

VkPhysicalDeviceExtendedSparseAddressSpacePropertiesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    extendedSparseAddressSpaceSize : VkDeviceSize,
    extendedSparseImageUsageFlags : VkImageUsageFlags,
    extendedSparseBufferUsageFlags : VkBufferUsageFlags,
}

VkLayerSettingEXT :: struct {
    pLayerName : ptr[char],
    pSettingName : ptr[char],
    type : VkLayerSettingTypeEXT,
    valueCount : u32,
    pValues : rawptr,
}

VkLayerSettingsCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    settingCount : u32,
    pSettings : ptr[VkLayerSettingEXT],
}

VkPhysicalDeviceShaderCoreBuiltinsFeaturesARM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderCoreBuiltins : VkBool32,
}

VkPhysicalDeviceShaderCoreBuiltinsPropertiesARM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderCoreMask : u64,
    shaderCoreCount : u32,
    shaderWarpsPerCore : u32,
}

VkPhysicalDevicePipelineLibraryGroupHandlesFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pipelineLibraryGroupHandles : VkBool32,
}

VkPhysicalDeviceDynamicRenderingUnusedAttachmentsFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    dynamicRenderingUnusedAttachments : VkBool32,
}

VkLatencySleepModeInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    lowLatencyMode : VkBool32,
    lowLatencyBoost : VkBool32,
    minimumIntervalUs : u32,
}

VkLatencySleepInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    signalSemaphore : VkSemaphore,
    value : u64,
}

VkSetLatencyMarkerInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    presentID : u64,
    marker : VkLatencyMarkerNV,
}

VkLatencyTimingsFrameReportNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    presentID : u64,
    inputSampleTimeUs : u64,
    simStartTimeUs : u64,
    simEndTimeUs : u64,
    renderSubmitStartTimeUs : u64,
    renderSubmitEndTimeUs : u64,
    presentStartTimeUs : u64,
    presentEndTimeUs : u64,
    driverStartTimeUs : u64,
    driverEndTimeUs : u64,
    osRenderQueueStartTimeUs : u64,
    osRenderQueueEndTimeUs : u64,
    gpuRenderStartTimeUs : u64,
    gpuRenderEndTimeUs : u64,
}

VkGetLatencyMarkerInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    timingCount : u32,
    pTimings : ptr[VkLatencyTimingsFrameReportNV],
}

VkLatencySubmissionPresentIdNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    presentID : u64,
}

VkSwapchainLatencyCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    latencyModeEnable : VkBool32,
}

VkOutOfBandQueueTypeInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    queueType : VkOutOfBandQueueTypeNV,
}

VkLatencySurfaceCapabilitiesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    presentModeCount : u32,
    pPresentModes : ptr[VkPresentModeKHR],
}

VkPhysicalDeviceMultiviewPerViewRenderAreasFeaturesQCOM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    multiviewPerViewRenderAreas : VkBool32,
}

VkMultiviewPerViewRenderAreasRenderPassBeginInfoQCOM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    perViewRenderAreaCount : u32,
    pPerViewRenderAreas : ptr[VkRect2D],
}

VkPhysicalDevicePerStageDescriptorSetFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    perStageDescriptorSet : VkBool32,
    dynamicPipelineLayout : VkBool32,
}

VkPhysicalDeviceImageProcessing2FeaturesQCOM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    textureBlockMatch2 : VkBool32,
}

VkPhysicalDeviceImageProcessing2PropertiesQCOM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxBlockMatchWindow : VkExtent2D,
}

VkSamplerBlockMatchWindowCreateInfoQCOM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    windowExtent : VkExtent2D,
    windowCompareMode : VkBlockMatchWindowCompareModeQCOM,
}

VkPhysicalDeviceCubicWeightsFeaturesQCOM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    selectableCubicWeights : VkBool32,
}

VkSamplerCubicWeightsCreateInfoQCOM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    cubicWeights : VkCubicFilterWeightsQCOM,
}

VkBlitImageCubicWeightsInfoQCOM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    cubicWeights : VkCubicFilterWeightsQCOM,
}

VkPhysicalDeviceYcbcrDegammaFeaturesQCOM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    ycbcrDegamma : VkBool32,
}

VkSamplerYcbcrConversionYcbcrDegammaCreateInfoQCOM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    enableYDegamma : VkBool32,
    enableCbCrDegamma : VkBool32,
}

VkPhysicalDeviceCubicClampFeaturesQCOM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    cubicRangeClamp : VkBool32,
}

VkPhysicalDeviceAttachmentFeedbackLoopDynamicStateFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    attachmentFeedbackLoopDynamicState : VkBool32,
}

VkPhysicalDeviceLayeredDriverPropertiesMSFT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    underlyingAPI : VkLayeredDriverUnderlyingApiMSFT,
}

VkPhysicalDeviceDescriptorPoolOverallocationFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    descriptorPoolOverallocation : VkBool32,
}

VkPhysicalDeviceShaderAtomicFloat16VectorFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderFloat16VectorAtomics : VkBool32,
}

VkAccelerationStructureBuildRangeInfoKHR :: struct {
    primitiveCount : u32,
    primitiveOffset : u32,
    firstVertex : u32,
    transformOffset : u32,
}

VkAccelerationStructureGeometryTrianglesDataKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    vertexFormat : VkFormat,
    vertexData : VkDeviceOrHostAddressConstKHR,
    vertexStride : VkDeviceSize,
    maxVertex : u32,
    indexType : VkIndexType,
    indexData : VkDeviceOrHostAddressConstKHR,
    transformData : VkDeviceOrHostAddressConstKHR,
}

VkAccelerationStructureGeometryAabbsDataKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    data : VkDeviceOrHostAddressConstKHR,
    stride : VkDeviceSize,
}

VkAccelerationStructureGeometryInstancesDataKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    arrayOfPointers : VkBool32,
    data : VkDeviceOrHostAddressConstKHR,
}

VkAccelerationStructureGeometryKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    geometryType : VkGeometryTypeKHR,
    geometry : VkAccelerationStructureGeometryDataKHR,
    flags : VkGeometryFlagsKHR,
}

VkAccelerationStructureBuildGeometryInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    type : VkAccelerationStructureTypeKHR,
    flags : VkBuildAccelerationStructureFlagsKHR,
    mode : VkBuildAccelerationStructureModeKHR,
    srcAccelerationStructure : VkAccelerationStructureKHR,
    dstAccelerationStructure : VkAccelerationStructureKHR,
    geometryCount : u32,
    pGeometries : ptr[VkAccelerationStructureGeometryKHR],
    ppGeometries : ptr[ptr[VkAccelerationStructureGeometryKHR]],
    scratchData : VkDeviceOrHostAddressKHR,
}

VkAccelerationStructureCreateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    createFlags : VkAccelerationStructureCreateFlagsKHR,
    buffer : VkBuffer,
    offset : VkDeviceSize,
    size : VkDeviceSize,
    type : VkAccelerationStructureTypeKHR,
    deviceAddress : VkDeviceAddress,
}

VkWriteDescriptorSetAccelerationStructureKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    accelerationStructureCount : u32,
    pAccelerationStructures : ptr[VkAccelerationStructureKHR],
}

VkPhysicalDeviceAccelerationStructureFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    accelerationStructure : VkBool32,
    accelerationStructureCaptureReplay : VkBool32,
    accelerationStructureIndirectBuild : VkBool32,
    accelerationStructureHostCommands : VkBool32,
    descriptorBindingAccelerationStructureUpdateAfterBind : VkBool32,
}

VkPhysicalDeviceAccelerationStructurePropertiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxGeometryCount : u64,
    maxInstanceCount : u64,
    maxPrimitiveCount : u64,
    maxPerStageDescriptorAccelerationStructures : u32,
    maxPerStageDescriptorUpdateAfterBindAccelerationStructures : u32,
    maxDescriptorSetAccelerationStructures : u32,
    maxDescriptorSetUpdateAfterBindAccelerationStructures : u32,
    minAccelerationStructureScratchOffsetAlignment : u32,
}

VkAccelerationStructureDeviceAddressInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    accelerationStructure : VkAccelerationStructureKHR,
}

VkAccelerationStructureVersionInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pVersionData : ptr[u8],
}

VkCopyAccelerationStructureToMemoryInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    src : VkAccelerationStructureKHR,
    dst : VkDeviceOrHostAddressKHR,
    mode : VkCopyAccelerationStructureModeKHR,
}

VkCopyMemoryToAccelerationStructureInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    src : VkDeviceOrHostAddressConstKHR,
    dst : VkAccelerationStructureKHR,
    mode : VkCopyAccelerationStructureModeKHR,
}

VkCopyAccelerationStructureInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    src : VkAccelerationStructureKHR,
    dst : VkAccelerationStructureKHR,
    mode : VkCopyAccelerationStructureModeKHR,
}

VkAccelerationStructureBuildSizesInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    accelerationStructureSize : VkDeviceSize,
    updateScratchSize : VkDeviceSize,
    buildScratchSize : VkDeviceSize,
}

VkRayTracingShaderGroupCreateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    type : VkRayTracingShaderGroupTypeKHR,
    generalShader : u32,
    closestHitShader : u32,
    anyHitShader : u32,
    intersectionShader : u32,
    pShaderGroupCaptureReplayHandle : rawptr,
}

VkRayTracingPipelineInterfaceCreateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxPipelineRayPayloadSize : u32,
    maxPipelineRayHitAttributeSize : u32,
}

VkRayTracingPipelineCreateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineCreateFlags,
    stageCount : u32,
    pStages : ptr[VkPipelineShaderStageCreateInfo],
    groupCount : u32,
    pGroups : ptr[VkRayTracingShaderGroupCreateInfoKHR],
    maxPipelineRayRecursionDepth : u32,
    pLibraryInfo : ptr[VkPipelineLibraryCreateInfoKHR],
    pLibraryInterface : ptr[VkRayTracingPipelineInterfaceCreateInfoKHR],
    pDynamicState : ptr[VkPipelineDynamicStateCreateInfo],
    layout : VkPipelineLayout,
    basePipelineHandle : VkPipeline,
    basePipelineIndex : i32,
}

VkPhysicalDeviceRayTracingPipelineFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    rayTracingPipeline : VkBool32,
    rayTracingPipelineShaderGroupHandleCaptureReplay : VkBool32,
    rayTracingPipelineShaderGroupHandleCaptureReplayMixed : VkBool32,
    rayTracingPipelineTraceRaysIndirect : VkBool32,
    rayTraversalPrimitiveCulling : VkBool32,
}

VkPhysicalDeviceRayTracingPipelinePropertiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderGroupHandleSize : u32,
    maxRayRecursionDepth : u32,
    maxShaderGroupStride : u32,
    shaderGroupBaseAlignment : u32,
    shaderGroupHandleCaptureReplaySize : u32,
    maxRayDispatchInvocationCount : u32,
    shaderGroupHandleAlignment : u32,
    maxRayHitAttributeSize : u32,
}

VkStridedDeviceAddressRegionKHR :: struct {
    deviceAddress : VkDeviceAddress,
    stride : VkDeviceSize,
    size : VkDeviceSize,
}

VkTraceRaysIndirectCommandKHR :: struct {
    width : u32,
    height : u32,
    depth : u32,
}

VkPhysicalDeviceRayQueryFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    rayQuery : VkBool32,
}

VkPhysicalDeviceMeshShaderFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    taskShader : VkBool32,
    meshShader : VkBool32,
    multiviewMeshShader : VkBool32,
    primitiveFragmentShadingRateMeshShader : VkBool32,
    meshShaderQueries : VkBool32,
}

VkPhysicalDeviceMeshShaderPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxTaskWorkGroupTotalCount : u32,
    maxTaskWorkGroupCount[3] : u32,
    maxTaskWorkGroupInvocations : u32,
    maxTaskWorkGroupSize[3] : u32,
    maxTaskPayloadSize : u32,
    maxTaskSharedMemorySize : u32,
    maxTaskPayloadAndSharedMemorySize : u32,
    maxMeshWorkGroupTotalCount : u32,
    maxMeshWorkGroupCount[3] : u32,
    maxMeshWorkGroupInvocations : u32,
    maxMeshWorkGroupSize[3] : u32,
    maxMeshSharedMemorySize : u32,
    maxMeshPayloadAndSharedMemorySize : u32,
    maxMeshOutputMemorySize : u32,
    maxMeshPayloadAndOutputMemorySize : u32,
    maxMeshOutputComponents : u32,
    maxMeshOutputVertices : u32,
    maxMeshOutputPrimitives : u32,
    maxMeshOutputLayers : u32,
    maxMeshMultiviewViewCount : u32,
    meshOutputPerVertexGranularity : u32,
    meshOutputPerPrimitiveGranularity : u32,
    maxPreferredTaskWorkGroupInvocations : u32,
    maxPreferredMeshWorkGroupInvocations : u32,
    prefersLocalInvocationVertexOutput : VkBool32,
    prefersLocalInvocationPrimitiveOutput : VkBool32,
    prefersCompactVertexOutput : VkBool32,
    prefersCompactPrimitiveOutput : VkBool32,
}

VkDrawMeshTasksIndirectCommandEXT :: struct {
    groupCountX : u32,
    groupCountY : u32,
    groupCountZ : u32,
}

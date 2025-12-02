package vulkan

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
    pipelineCacheUUID : u8[VK_UUID_SIZE],
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
    applicationName : string,
    applicationVersion : u32,
    engineName : string,
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
    enabledLayerNames : string[],
    enabledExtensionNames : string[],
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
    robustBufferAccess : b32,
    fullDrawIndexUint32 : b32,
    imageCubeArray : b32,
    independentBlend : b32,
    geometryShader : b32,
    tessellationShader : b32,
    sampleRateShading : b32,
    dualSrcBlend : b32,
    logicOp : b32,
    multiDrawIndirect : b32,
    drawIndirectFirstInstance : b32,
    depthClamp : b32,
    depthBiasClamp : b32,
    fillModeNonSolid : b32,
    depthBounds : b32,
    wideLines : b32,
    largePoints : b32,
    alphaToOne : b32,
    multiViewport : b32,
    samplerAnisotropy : b32,
    textureCompressionETC2 : b32,
    textureCompressionASTC_LDR : b32,
    textureCompressionBC : b32,
    occlusionQueryPrecise : b32,
    pipelineStatisticsQuery : b32,
    vertexPipelineStoresAndAtomics : b32,
    fragmentStoresAndAtomics : b32,
    shaderTessellationAndGeometryPointSize : b32,
    shaderImageGatherExtended : b32,
    shaderStorageImageExtendedFormats : b32,
    shaderStorageImageMultisample : b32,
    shaderStorageImageReadWithoutFormat : b32,
    shaderStorageImageWriteWithoutFormat : b32,
    shaderUniformBufferArrayDynamicIndexing : b32,
    shaderSampledImageArrayDynamicIndexing : b32,
    shaderStorageBufferArrayDynamicIndexing : b32,
    shaderStorageImageArrayDynamicIndexing : b32,
    shaderClipDistance : b32,
    shaderCullDistance : b32,
    shaderFloat64 : b32,
    shaderInt64 : b32,
    shaderInt16 : b32,
    shaderResourceResidency : b32,
    shaderResourceMinLod : b32,
    sparseBinding : b32,
    sparseResidencyBuffer : b32,
    sparseResidencyImage2D : b32,
    sparseResidencyImage3D : b32,
    sparseResidency2Samples : b32,
    sparseResidency4Samples : b32,
    sparseResidency8Samples : b32,
    sparseResidency16Samples : b32,
    sparseResidencyAliased : b32,
    variableMultisampleRate : b32,
    inheritedQueries : b32,
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
    maxComputeWorkGroupCount : u32[3],
    maxComputeWorkGroupInvocations : u32,
    maxComputeWorkGroupSize : u32[3],
    subPixelPrecisionBits : u32,
    subTexelPrecisionBits : u32,
    mipmapPrecisionBits : u32,
    maxDrawIndexedIndexValue : u32,
    maxDrawIndirectCount : u32,
    maxSamplerLodBias : f32,
    maxSamplerAnisotropy : f32,
    maxViewports : u32,
    maxViewportDimensions : u32[2],
    viewportBoundsRange : f32[2],
    viewportSubPixelBits : u32,
    minMemoryMapAlignment : u64,
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
    timestampComputeAndGraphics : b32,
    timestampPeriod : f32,
    maxClipDistances : u32,
    maxCullDistances : u32,
    maxCombinedClipAndCullDistances : u32,
    discreteQueuePriorities : u32,
    pointSizeRange : f32[2],
    lineWidthRange : f32[2],
    pointSizeGranularity : f32,
    lineWidthGranularity : f32,
    strictLines : b32,
    standardSampleLocations : b32,
    optimalBufferCopyOffsetAlignment : VkDeviceSize,
    optimalBufferCopyRowPitchAlignment : VkDeviceSize,
    nonCoherentAtomSize : VkDeviceSize,
}

VkPhysicalDeviceMemoryProperties :: struct {
    memoryTypes : VkMemoryType[],
    memoryHeaps : VkMemoryHeap[],
}

VkPhysicalDeviceSparseProperties :: struct {
    residencyStandard2DBlockShape : b32,
    residencyStandard2DMultisampleBlockShape : b32,
    residencyStandard3DBlockShape : b32,
    residencyAlignedMipSize : b32,
    residencyNonResidentStrict : b32,
}

VkPhysicalDeviceProperties :: struct {
    apiVersion : u32,
    driverVersion : u32,
    vendorID : u32,
    deviceID : u32,
    deviceType : VkPhysicalDeviceType,
    deviceName : string,
    pipelineCacheUUID : u8[VK_UUID_SIZE],
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
    queuePriorities : f32[],
}

VkDeviceCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkDeviceCreateFlags,
    queueCreateInfos : VkDeviceQueueCreateInfo[],
    enabledLayerNames : string[],
    enabledExtensionNames : string[],
    enabledFeatures : VkPhysicalDeviceFeatures?,
}

VkExtensionProperties :: struct {
    extensionName : string,
    specVersion : u32,
}

VkLayerProperties :: struct {
    layerName : string,
    specVersion : u32,
    implementationVersion : u32,
    description : string,
}

VkSubmitInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    waitSemaphores : VkSemaphore[],
    pWaitDstStageMask : ptr[VkPipelineStageFlags],
    commandBuffers : VkCommandBuffer[],
    signalSemaphores : VkSemaphore[],
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
    binds : VkSparseMemoryBind[],
}

VkSparseImageOpaqueMemoryBindInfo :: struct {
    image : VkImage,
    binds : VkSparseMemoryBind[],
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
    binds : VkSparseImageMemoryBind[],
}

VkBindSparseInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    waitSemaphores : VkSemaphore[],
    bufferBinds : VkSparseBufferMemoryBindInfo[],
    imageOpaqueBinds : VkSparseImageOpaqueMemoryBindInfo[],
    imageBinds : VkSparseImageMemoryBindInfo[],
    signalSemaphores : VkSemaphore[],
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
    queueFamilyIndices : u32[],
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
    queueFamilyIndices : u32[],
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
    codeSize : u64,
    pCode : ptr[u32],
}

VkPipelineCacheCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineCacheCreateFlags,
    initialDataSize : u64,
    pInitialData : rawptr,
}

VkSpecializationMapEntry :: struct {
    constantID : u32,
    offset : u32,
    size : u64,
}

VkSpecializationInfo :: struct {
    mapEntries : VkSpecializationMapEntry[],
    dataSize : u64,
    pData : rawptr,
}

VkPipelineShaderStageCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineShaderStageCreateFlags,
    stage : VkShaderStageFlagBits,
    module : VkShaderModule,
    name : string,
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
    vertexBindingDescriptions : VkVertexInputBindingDescription[],
    vertexAttributeDescriptions : VkVertexInputAttributeDescription[],
}

VkPipelineInputAssemblyStateCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineInputAssemblyStateCreateFlags,
    topology : VkPrimitiveTopology,
    primitiveRestartEnable : b32,
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
    viewports : VkViewport[],
    scissors : VkRect2D[],
}

VkPipelineRasterizationStateCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineRasterizationStateCreateFlags,
    depthClampEnable : b32,
    rasterizerDiscardEnable : b32,
    polygonMode : VkPolygonMode,
    cullMode : VkCullModeFlags,
    frontFace : VkFrontFace,
    depthBiasEnable : b32,
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
    sampleShadingEnable : b32,
    minSampleShading : f32,
    pSampleMask : ptr[VkSampleMask],
    alphaToCoverageEnable : b32,
    alphaToOneEnable : b32,
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
    depthTestEnable : b32,
    depthWriteEnable : b32,
    depthCompareOp : VkCompareOp,
    depthBoundsTestEnable : b32,
    stencilTestEnable : b32,
    front : VkStencilOpState,
    back : VkStencilOpState,
    minDepthBounds : f32,
    maxDepthBounds : f32,
}

VkPipelineColorBlendAttachmentState :: struct {
    blendEnable : b32,
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
    logicOpEnable : b32,
    logicOp : VkLogicOp,
    attachments : VkPipelineColorBlendAttachmentState[],
    blendConstants : f32[4],
}

VkPipelineDynamicStateCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineDynamicStateCreateFlags,
    dynamicStates : VkDynamicState[],
}

VkGraphicsPipelineCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineCreateFlags,
    stages : VkPipelineShaderStageCreateInfo[],
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
    setLayouts : VkDescriptorSetLayout[],
    pushConstantRanges : VkPushConstantRange[],
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
    anisotropyEnable : b32,
    maxAnisotropy : f32,
    compareEnable : b32,
    compareOp : VkCompareOp,
    minLod : f32,
    maxLod : f32,
    borderColor : VkBorderColor,
    unnormalizedCoordinates : b32,
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
    poolSizes : VkDescriptorPoolSize[],
}

VkDescriptorSetAllocateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    descriptorPool : VkDescriptorPool,
    descriptorSetCount : u32,
    setLayouts : VkDescriptorSetLayout[],
}

VkDescriptorSetLayoutBinding :: struct {
    binding : u32,
    descriptorType : VkDescriptorType,
    descriptorCount : u32,
    stageFlags : VkShaderStageFlags,
    immutableSamplers : VkSampler[],
}

VkDescriptorSetLayoutCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkDescriptorSetLayoutCreateFlags,
    bindings : VkDescriptorSetLayoutBinding[],
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
    attachments : VkImageView[],
    width : u32,
    height : u32,
    layers : u32,
}

VkSubpassDescription :: struct {
    flags : VkSubpassDescriptionFlags,
    pipelineBindPoint : VkPipelineBindPoint,
    inputAttachments : VkAttachmentReference[],
    colorAttachments : VkAttachmentReference[],
    resolveAttachments : VkAttachmentReference[],
    pDepthStencilAttachment : ptr[VkAttachmentReference],
    preserveAttachments : u32[],
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
    attachments : VkAttachmentDescription[],
    subpasses : VkSubpassDescription[],
    dependencies : VkSubpassDependency[],
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
    occlusionQueryEnable : b32,
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
    clearValues : VkClearValue[],
}

VkPhysicalDeviceSubgroupProperties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    subgroupSize : u32,
    supportedStages : VkShaderStageFlags,
    supportedOperations : VkSubgroupFeatureFlags,
    quadOperationsInAllStages : b32,
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
    storageBuffer16BitAccess : b32,
    uniformAndStorageBuffer16BitAccess : b32,
    storagePushConstant16 : b32,
    storageInputOutput16 : b32,
}

VkMemoryDedicatedRequirements :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    prefersDedicatedAllocation : b32,
    requiresDedicatedAllocation : b32,
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
    deviceRenderAreas : VkRect2D[],
}

VkDeviceGroupCommandBufferBeginInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    deviceMask : u32,
}

VkDeviceGroupSubmitInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    waitSemaphoreDeviceIndices : u32[],
    commandBufferDeviceMasks : u32[],
    signalSemaphoreDeviceIndices : u32[],
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
    deviceIndices : u32[],
}

VkBindImageMemoryDeviceGroupInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    deviceIndices : u32[],
    splitInstanceBindRegions : VkRect2D[],
}

VkPhysicalDeviceGroupProperties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    physicalDevices : VkPhysicalDevice[],
    subsetAllocation : b32,
}

VkDeviceGroupDeviceCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    physicalDevices : VkPhysicalDevice[],
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
    aspectReferences : VkInputAttachmentAspectReference[],
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
    viewMasks : u32[],
    dependencyCount : u32,
    viewOffsets : i32[],
    correlationMaskCount : u32,
    correlationMasks : u32[],
}

VkPhysicalDeviceMultiviewFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    multiview : b32,
    multiviewGeometryShader : b32,
    multiviewTessellationShader : b32,
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
    variablePointersStorageBuffer : b32,
    variablePointers : b32,
}

VkPhysicalDeviceProtectedMemoryFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    protectedMemory : b32,
}

VkPhysicalDeviceProtectedMemoryProperties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    protectedNoFault : b32,
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
    protectedSubmit : b32,
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
    forceExplicitReconstruction : b32,
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
    samplerYcbcrConversion : b32,
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
    offset : u64,
    stride : u64,
}

VkDescriptorUpdateTemplateCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkDescriptorUpdateTemplateCreateFlags,
    descriptorUpdateEntries : VkDescriptorUpdateTemplateEntry[],
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
    deviceUUID : u8[VK_UUID_SIZE],
    driverUUID : u8[VK_UUID_SIZE],
    deviceLUID : u8[VK_LUID_SIZE],
    deviceNodeMask : u32,
    deviceLUIDValid : b32,
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
    supported : b32,
}

VkPhysicalDeviceShaderDrawParametersFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderDrawParameters : b32,
}

VkPhysicalDeviceVulkan11Features :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    storageBuffer16BitAccess : b32,
    uniformAndStorageBuffer16BitAccess : b32,
    storagePushConstant16 : b32,
    storageInputOutput16 : b32,
    multiview : b32,
    multiviewGeometryShader : b32,
    multiviewTessellationShader : b32,
    variablePointersStorageBuffer : b32,
    variablePointers : b32,
    protectedMemory : b32,
    samplerYcbcrConversion : b32,
    shaderDrawParameters : b32,
}

VkPhysicalDeviceVulkan11Properties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    deviceUUID : u8[VK_UUID_SIZE],
    driverUUID : u8[VK_UUID_SIZE],
    deviceLUID : u8[VK_LUID_SIZE],
    deviceNodeMask : u32,
    deviceLUIDValid : b32,
    subgroupSize : u32,
    subgroupSupportedStages : VkShaderStageFlags,
    subgroupSupportedOperations : VkSubgroupFeatureFlags,
    subgroupQuadOperationsInAllStages : b32,
    pointClippingBehavior : VkPointClippingBehavior,
    maxMultiviewViewCount : u32,
    maxMultiviewInstanceIndex : u32,
    protectedNoFault : b32,
    maxPerSetDescriptors : u32,
    maxMemoryAllocationSize : VkDeviceSize,
}

VkPhysicalDeviceVulkan12Features :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    samplerMirrorClampToEdge : b32,
    drawIndirectCount : b32,
    storageBuffer8BitAccess : b32,
    uniformAndStorageBuffer8BitAccess : b32,
    storagePushConstant8 : b32,
    shaderBufferInt64Atomics : b32,
    shaderSharedInt64Atomics : b32,
    shaderFloat16 : b32,
    shaderInt8 : b32,
    descriptorIndexing : b32,
    shaderInputAttachmentArrayDynamicIndexing : b32,
    shaderUniformTexelBufferArrayDynamicIndexing : b32,
    shaderStorageTexelBufferArrayDynamicIndexing : b32,
    shaderUniformBufferArrayNonUniformIndexing : b32,
    shaderSampledImageArrayNonUniformIndexing : b32,
    shaderStorageBufferArrayNonUniformIndexing : b32,
    shaderStorageImageArrayNonUniformIndexing : b32,
    shaderInputAttachmentArrayNonUniformIndexing : b32,
    shaderUniformTexelBufferArrayNonUniformIndexing : b32,
    shaderStorageTexelBufferArrayNonUniformIndexing : b32,
    descriptorBindingUniformBufferUpdateAfterBind : b32,
    descriptorBindingSampledImageUpdateAfterBind : b32,
    descriptorBindingStorageImageUpdateAfterBind : b32,
    descriptorBindingStorageBufferUpdateAfterBind : b32,
    descriptorBindingUniformTexelBufferUpdateAfterBind : b32,
    descriptorBindingStorageTexelBufferUpdateAfterBind : b32,
    descriptorBindingUpdateUnusedWhilePending : b32,
    descriptorBindingPartiallyBound : b32,
    descriptorBindingVariableDescriptorCount : b32,
    runtimeDescriptorArray : b32,
    samplerFilterMinmax : b32,
    scalarBlockLayout : b32,
    imagelessFramebuffer : b32,
    uniformBufferStandardLayout : b32,
    shaderSubgroupExtendedTypes : b32,
    separateDepthStencilLayouts : b32,
    hostQueryReset : b32,
    timelineSemaphore : b32,
    bufferDeviceAddress : b32,
    bufferDeviceAddressCaptureReplay : b32,
    bufferDeviceAddressMultiDevice : b32,
    vulkanMemoryModel : b32,
    vulkanMemoryModelDeviceScope : b32,
    vulkanMemoryModelAvailabilityVisibilityChains : b32,
    shaderOutputViewportIndex : b32,
    shaderOutputLayer : b32,
    subgroupBroadcastDynamicId : b32,
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
    driverName : string,
    driverInfo : string,
    conformanceVersion : VkConformanceVersion,
    denormBehaviorIndependence : VkShaderFloatControlsIndependence,
    roundingModeIndependence : VkShaderFloatControlsIndependence,
    shaderSignedZeroInfNanPreserveFloat16 : b32,
    shaderSignedZeroInfNanPreserveFloat32 : b32,
    shaderSignedZeroInfNanPreserveFloat64 : b32,
    shaderDenormPreserveFloat16 : b32,
    shaderDenormPreserveFloat32 : b32,
    shaderDenormPreserveFloat64 : b32,
    shaderDenormFlushToZeroFloat16 : b32,
    shaderDenormFlushToZeroFloat32 : b32,
    shaderDenormFlushToZeroFloat64 : b32,
    shaderRoundingModeRTEFloat16 : b32,
    shaderRoundingModeRTEFloat32 : b32,
    shaderRoundingModeRTEFloat64 : b32,
    shaderRoundingModeRTZFloat16 : b32,
    shaderRoundingModeRTZFloat32 : b32,
    shaderRoundingModeRTZFloat64 : b32,
    maxUpdateAfterBindDescriptorsInAllPools : u32,
    shaderUniformBufferArrayNonUniformIndexingNative : b32,
    shaderSampledImageArrayNonUniformIndexingNative : b32,
    shaderStorageBufferArrayNonUniformIndexingNative : b32,
    shaderStorageImageArrayNonUniformIndexingNative : b32,
    shaderInputAttachmentArrayNonUniformIndexingNative : b32,
    robustBufferAccessUpdateAfterBind : b32,
    quadDivergentImplicitLod : b32,
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
    independentResolveNone : b32,
    independentResolve : b32,
    filterMinmaxSingleComponentFormats : b32,
    filterMinmaxImageComponentMapping : b32,
    maxTimelineSemaphoreValueDifference : u64,
    framebufferIntegerColorSampleCounts : VkSampleCountFlags,
}

VkImageFormatListCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    viewFormats : VkFormat[],
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
    inputAttachments : VkAttachmentReference2[],
    colorAttachments : VkAttachmentReference2[],
    resolveAttachments : VkAttachmentReference2[],
    pDepthStencilAttachment : ptr[VkAttachmentReference2],
    preserveAttachments : u32[],
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
    attachments : VkAttachmentDescription2[],
    subpasses : VkSubpassDescription2[],
    dependencies : VkSubpassDependency2[],
    correlatedViewMasks : u32[],
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
    storageBuffer8BitAccess : b32,
    uniformAndStorageBuffer8BitAccess : b32,
    storagePushConstant8 : b32,
}

VkPhysicalDeviceDriverProperties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    driverID : VkDriverId,
    driverName : string,
    driverInfo : string,
    conformanceVersion : VkConformanceVersion,
}

VkPhysicalDeviceShaderAtomicInt64Features :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderBufferInt64Atomics : b32,
    shaderSharedInt64Atomics : b32,
}

VkPhysicalDeviceShaderFloat16Int8Features :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderFloat16 : b32,
    shaderInt8 : b32,
}

VkPhysicalDeviceFloatControlsProperties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    denormBehaviorIndependence : VkShaderFloatControlsIndependence,
    roundingModeIndependence : VkShaderFloatControlsIndependence,
    shaderSignedZeroInfNanPreserveFloat16 : b32,
    shaderSignedZeroInfNanPreserveFloat32 : b32,
    shaderSignedZeroInfNanPreserveFloat64 : b32,
    shaderDenormPreserveFloat16 : b32,
    shaderDenormPreserveFloat32 : b32,
    shaderDenormPreserveFloat64 : b32,
    shaderDenormFlushToZeroFloat16 : b32,
    shaderDenormFlushToZeroFloat32 : b32,
    shaderDenormFlushToZeroFloat64 : b32,
    shaderRoundingModeRTEFloat16 : b32,
    shaderRoundingModeRTEFloat32 : b32,
    shaderRoundingModeRTEFloat64 : b32,
    shaderRoundingModeRTZFloat16 : b32,
    shaderRoundingModeRTZFloat32 : b32,
    shaderRoundingModeRTZFloat64 : b32,
}

VkDescriptorSetLayoutBindingFlagsCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    bindingFlags : VkDescriptorBindingFlags[],
}

VkPhysicalDeviceDescriptorIndexingFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderInputAttachmentArrayDynamicIndexing : b32,
    shaderUniformTexelBufferArrayDynamicIndexing : b32,
    shaderStorageTexelBufferArrayDynamicIndexing : b32,
    shaderUniformBufferArrayNonUniformIndexing : b32,
    shaderSampledImageArrayNonUniformIndexing : b32,
    shaderStorageBufferArrayNonUniformIndexing : b32,
    shaderStorageImageArrayNonUniformIndexing : b32,
    shaderInputAttachmentArrayNonUniformIndexing : b32,
    shaderUniformTexelBufferArrayNonUniformIndexing : b32,
    shaderStorageTexelBufferArrayNonUniformIndexing : b32,
    descriptorBindingUniformBufferUpdateAfterBind : b32,
    descriptorBindingSampledImageUpdateAfterBind : b32,
    descriptorBindingStorageImageUpdateAfterBind : b32,
    descriptorBindingStorageBufferUpdateAfterBind : b32,
    descriptorBindingUniformTexelBufferUpdateAfterBind : b32,
    descriptorBindingStorageTexelBufferUpdateAfterBind : b32,
    descriptorBindingUpdateUnusedWhilePending : b32,
    descriptorBindingPartiallyBound : b32,
    descriptorBindingVariableDescriptorCount : b32,
    runtimeDescriptorArray : b32,
}

VkPhysicalDeviceDescriptorIndexingProperties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxUpdateAfterBindDescriptorsInAllPools : u32,
    shaderUniformBufferArrayNonUniformIndexingNative : b32,
    shaderSampledImageArrayNonUniformIndexingNative : b32,
    shaderStorageBufferArrayNonUniformIndexingNative : b32,
    shaderStorageImageArrayNonUniformIndexingNative : b32,
    shaderInputAttachmentArrayNonUniformIndexingNative : b32,
    robustBufferAccessUpdateAfterBind : b32,
    quadDivergentImplicitLod : b32,
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
    descriptorCounts : u32[],
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
    independentResolveNone : b32,
    independentResolve : b32,
}

VkPhysicalDeviceScalarBlockLayoutFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    scalarBlockLayout : b32,
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
    filterMinmaxSingleComponentFormats : b32,
    filterMinmaxImageComponentMapping : b32,
}

VkPhysicalDeviceVulkanMemoryModelFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    vulkanMemoryModel : b32,
    vulkanMemoryModelDeviceScope : b32,
    vulkanMemoryModelAvailabilityVisibilityChains : b32,
}

VkPhysicalDeviceImagelessFramebufferFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    imagelessFramebuffer : b32,
}

VkFramebufferAttachmentImageInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkImageCreateFlags,
    usage : VkImageUsageFlags,
    width : u32,
    height : u32,
    layerCount : u32,
    viewFormats : VkFormat[],
}

VkFramebufferAttachmentsCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    attachmentImageInfos : VkFramebufferAttachmentImageInfo[],
}

VkRenderPassAttachmentBeginInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    attachments : VkImageView[],
}

VkPhysicalDeviceUniformBufferStandardLayoutFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    uniformBufferStandardLayout : b32,
}

VkPhysicalDeviceShaderSubgroupExtendedTypesFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderSubgroupExtendedTypes : b32,
}

VkPhysicalDeviceSeparateDepthStencilLayoutsFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    separateDepthStencilLayouts : b32,
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
    hostQueryReset : b32,
}

VkPhysicalDeviceTimelineSemaphoreFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    timelineSemaphore : b32,
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
    waitSemaphoreValues : u64[],
    signalSemaphoreValues : u64[],
}

VkSemaphoreWaitInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkSemaphoreWaitFlags,
    semaphores : VkSemaphore[],
    values : u64[],
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
    bufferDeviceAddress : b32,
    bufferDeviceAddressCaptureReplay : b32,
    bufferDeviceAddressMultiDevice : b32,
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
    robustImageAccess : b32,
    inlineUniformBlock : b32,
    descriptorBindingInlineUniformBlockUpdateAfterBind : b32,
    pipelineCreationCacheControl : b32,
    privateData : b32,
    shaderDemoteToHelperInvocation : b32,
    shaderTerminateInvocation : b32,
    subgroupSizeControl : b32,
    computeFullSubgroups : b32,
    synchronization2 : b32,
    textureCompressionASTC_HDR : b32,
    shaderZeroInitializeWorkgroupMemory : b32,
    dynamicRendering : b32,
    shaderIntegerDotProduct : b32,
    maintenance4 : b32,
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
    integerDotProduct8BitUnsignedAccelerated : b32,
    integerDotProduct8BitSignedAccelerated : b32,
    integerDotProduct8BitMixedSignednessAccelerated : b32,
    integerDotProduct4x8BitPackedUnsignedAccelerated : b32,
    integerDotProduct4x8BitPackedSignedAccelerated : b32,
    integerDotProduct4x8BitPackedMixedSignednessAccelerated : b32,
    integerDotProduct16BitUnsignedAccelerated : b32,
    integerDotProduct16BitSignedAccelerated : b32,
    integerDotProduct16BitMixedSignednessAccelerated : b32,
    integerDotProduct32BitUnsignedAccelerated : b32,
    integerDotProduct32BitSignedAccelerated : b32,
    integerDotProduct32BitMixedSignednessAccelerated : b32,
    integerDotProduct64BitUnsignedAccelerated : b32,
    integerDotProduct64BitSignedAccelerated : b32,
    integerDotProduct64BitMixedSignednessAccelerated : b32,
    integerDotProductAccumulatingSaturating8BitUnsignedAccelerated : b32,
    integerDotProductAccumulatingSaturating8BitSignedAccelerated : b32,
    integerDotProductAccumulatingSaturating8BitMixedSignednessAccelerated : b32,
    integerDotProductAccumulatingSaturating4x8BitPackedUnsignedAccelerated : b32,
    integerDotProductAccumulatingSaturating4x8BitPackedSignedAccelerated : b32,
    integerDotProductAccumulatingSaturating4x8BitPackedMixedSignednessAccelerated : b32,
    integerDotProductAccumulatingSaturating16BitUnsignedAccelerated : b32,
    integerDotProductAccumulatingSaturating16BitSignedAccelerated : b32,
    integerDotProductAccumulatingSaturating16BitMixedSignednessAccelerated : b32,
    integerDotProductAccumulatingSaturating32BitUnsignedAccelerated : b32,
    integerDotProductAccumulatingSaturating32BitSignedAccelerated : b32,
    integerDotProductAccumulatingSaturating32BitMixedSignednessAccelerated : b32,
    integerDotProductAccumulatingSaturating64BitUnsignedAccelerated : b32,
    integerDotProductAccumulatingSaturating64BitSignedAccelerated : b32,
    integerDotProductAccumulatingSaturating64BitMixedSignednessAccelerated : b32,
    storageTexelBufferOffsetAlignmentBytes : VkDeviceSize,
    storageTexelBufferOffsetSingleTexelAlignment : b32,
    uniformTexelBufferOffsetAlignmentBytes : VkDeviceSize,
    uniformTexelBufferOffsetSingleTexelAlignment : b32,
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
    pipelineStageCreationFeedbacks : VkPipelineCreationFeedback[],
}

VkPhysicalDeviceShaderTerminateInvocationFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderTerminateInvocation : b32,
}

VkPhysicalDeviceToolProperties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    name : string,
    version : string,
    purposes : VkToolPurposeFlags,
    description : string,
    layer : string,
}

VkPhysicalDeviceShaderDemoteToHelperInvocationFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderDemoteToHelperInvocation : b32,
}

VkPhysicalDevicePrivateDataFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    privateData : b32,
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
    pipelineCreationCacheControl : b32,
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
    memoryBarriers : VkMemoryBarrier2[],
    bufferMemoryBarriers : VkBufferMemoryBarrier2[],
    imageMemoryBarriers : VkImageMemoryBarrier2[],
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
    waitSemaphoreInfos : VkSemaphoreSubmitInfo[],
    commandBufferInfos : VkCommandBufferSubmitInfo[],
    signalSemaphoreInfos : VkSemaphoreSubmitInfo[],
}

VkPhysicalDeviceSynchronization2Features :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    synchronization2 : b32,
}

VkPhysicalDeviceZeroInitializeWorkgroupMemoryFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderZeroInitializeWorkgroupMemory : b32,
}

VkPhysicalDeviceImageRobustnessFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    robustImageAccess : b32,
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
    regions : VkBufferCopy2[],
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
    regions : VkImageCopy2[],
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
    regions : VkBufferImageCopy2[],
}

VkCopyImageToBufferInfo2 :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    srcImage : VkImage,
    srcImageLayout : VkImageLayout,
    dstBuffer : VkBuffer,
    regions : VkBufferImageCopy2[],
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
    regions : VkImageBlit2[],
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
    regions : VkImageResolve2[],
}

VkPhysicalDeviceSubgroupSizeControlFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    subgroupSizeControl : b32,
    computeFullSubgroups : b32,
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
    inlineUniformBlock : b32,
    descriptorBindingInlineUniformBlockUpdateAfterBind : b32,
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
    textureCompressionASTC_HDR : b32,
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
    colorAttachments : VkRenderingAttachmentInfo[],
    pDepthAttachment : ptr[VkRenderingAttachmentInfo],
    pStencilAttachment : ptr[VkRenderingAttachmentInfo],
}

VkPipelineRenderingCreateInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    viewMask : u32,
    colorAttachmentCount : u32,
    colorAttachmentFormats : VkFormat[],
    depthAttachmentFormat : VkFormat,
    stencilAttachmentFormat : VkFormat,
}

VkPhysicalDeviceDynamicRenderingFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    dynamicRendering : b32,
}

VkCommandBufferInheritanceRenderingInfo :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkRenderingFlags,
    viewMask : u32,
    colorAttachmentFormats : VkFormat[],
    depthAttachmentFormat : VkFormat,
    stencilAttachmentFormat : VkFormat,
    rasterizationSamples : VkSampleCountFlagBits,
}

VkPhysicalDeviceShaderIntegerDotProductFeatures :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderIntegerDotProduct : b32,
}

VkPhysicalDeviceShaderIntegerDotProductProperties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    integerDotProduct8BitUnsignedAccelerated : b32,
    integerDotProduct8BitSignedAccelerated : b32,
    integerDotProduct8BitMixedSignednessAccelerated : b32,
    integerDotProduct4x8BitPackedUnsignedAccelerated : b32,
    integerDotProduct4x8BitPackedSignedAccelerated : b32,
    integerDotProduct4x8BitPackedMixedSignednessAccelerated : b32,
    integerDotProduct16BitUnsignedAccelerated : b32,
    integerDotProduct16BitSignedAccelerated : b32,
    integerDotProduct16BitMixedSignednessAccelerated : b32,
    integerDotProduct32BitUnsignedAccelerated : b32,
    integerDotProduct32BitSignedAccelerated : b32,
    integerDotProduct32BitMixedSignednessAccelerated : b32,
    integerDotProduct64BitUnsignedAccelerated : b32,
    integerDotProduct64BitSignedAccelerated : b32,
    integerDotProduct64BitMixedSignednessAccelerated : b32,
    integerDotProductAccumulatingSaturating8BitUnsignedAccelerated : b32,
    integerDotProductAccumulatingSaturating8BitSignedAccelerated : b32,
    integerDotProductAccumulatingSaturating8BitMixedSignednessAccelerated : b32,
    integerDotProductAccumulatingSaturating4x8BitPackedUnsignedAccelerated : b32,
    integerDotProductAccumulatingSaturating4x8BitPackedSignedAccelerated : b32,
    integerDotProductAccumulatingSaturating4x8BitPackedMixedSignednessAccelerated : b32,
    integerDotProductAccumulatingSaturating16BitUnsignedAccelerated : b32,
    integerDotProductAccumulatingSaturating16BitSignedAccelerated : b32,
    integerDotProductAccumulatingSaturating16BitMixedSignednessAccelerated : b32,
    integerDotProductAccumulatingSaturating32BitUnsignedAccelerated : b32,
    integerDotProductAccumulatingSaturating32BitSignedAccelerated : b32,
    integerDotProductAccumulatingSaturating32BitMixedSignednessAccelerated : b32,
    integerDotProductAccumulatingSaturating64BitUnsignedAccelerated : b32,
    integerDotProductAccumulatingSaturating64BitSignedAccelerated : b32,
    integerDotProductAccumulatingSaturating64BitMixedSignednessAccelerated : b32,
}

VkPhysicalDeviceTexelBufferAlignmentProperties :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    storageTexelBufferOffsetAlignmentBytes : VkDeviceSize,
    storageTexelBufferOffsetSingleTexelAlignment : b32,
    uniformTexelBufferOffsetAlignmentBytes : VkDeviceSize,
    uniformTexelBufferOffsetSingleTexelAlignment : b32,
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
    maintenance4 : b32,
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
    queueFamilyIndices : u32[],
    preTransform : VkSurfaceTransformFlagBitsKHR,
    compositeAlpha : VkCompositeAlphaFlagBitsKHR,
    presentMode : VkPresentModeKHR,
    clipped : b32,
    oldSwapchain : VkSwapchainKHR,
}

VkPresentInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    waitSemaphores : VkSemaphore[],
    swapchains : VkSwapchainKHR[],
    imageIndices : u32[],
    results : ptr[VkResult][],
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
    presentMask : u32[VK_MAX_DEVICE_GROUP_SIZE],
    modes : VkDeviceGroupPresentModeFlagsKHR,
}

VkDeviceGroupPresentInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    swapchainCount : u32,
    deviceMasks : u32[],
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
    displayName : string,
    physicalDimensions : VkExtent2D,
    physicalResolution : VkExtent2D,
    supportedTransforms : VkSurfaceTransformFlagsKHR,
    planeReorderPossible : b32,
    persistentContent : b32,
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
    persistent : b32,
}

VkQueueFamilyQueryResultStatusPropertiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    queryResultStatusSupport : b32,
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
    profiles : VkVideoProfileInfoKHR[],
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
    referenceSlots : VkVideoReferenceSlotInfoKHR[],
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
    referenceSlots : VkVideoReferenceSlotInfoKHR[],
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
    expectDyadicTemporalLayerPattern : b32,
    minQp : i32,
    maxQp : i32,
    prefersGopRemainingFrames : b32,
    requiresGopRemainingFrames : b32,
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
    preferredStdEntropyCodingModeFlag : b32,
}

VkVideoEncodeH264SessionCreateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    useMaxLevelIdc : b32,
    maxLevelIdc : StdVideoH264LevelIdc,
}

VkVideoEncodeH264SessionParametersAddInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    stdSPSs : StdVideoH264SequenceParameterSet[],
    stdPPSs : StdVideoH264PictureParameterSet[],
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
    writeStdSPS : b32,
    writeStdPPS : b32,
    stdSPSId : u32,
    stdPPSId : u32,
}

VkVideoEncodeH264SessionParametersFeedbackInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    hasStdSPSOverrides : b32,
    hasStdPPSOverrides : b32,
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
    naluSliceEntries : VkVideoEncodeH264NaluSliceInfoKHR[],
    pStdPictureInfo : ptr[StdVideoEncodeH264PictureInfo],
    generatePrefixNalu : b32,
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
    useMinQp : b32,
    minQp : VkVideoEncodeH264QpKHR,
    useMaxQp : b32,
    maxQp : VkVideoEncodeH264QpKHR,
    useMaxFrameSize : b32,
    maxFrameSize : VkVideoEncodeH264FrameSizeKHR,
}

VkVideoEncodeH264GopRemainingFrameInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    useGopRemainingFrames : b32,
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
    expectDyadicTemporalSubLayerPattern : b32,
    minQp : i32,
    maxQp : i32,
    prefersGopRemainingFrames : b32,
    requiresGopRemainingFrames : b32,
    stdSyntaxFlags : VkVideoEncodeH265StdFlagsKHR,
}

VkVideoEncodeH265SessionCreateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    useMaxLevelIdc : b32,
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
    stdVPSs : StdVideoH265VideoParameterSet[],
    stdSPSs : StdVideoH265SequenceParameterSet[],
    stdPPSs : StdVideoH265PictureParameterSet[],
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
    writeStdVPS : b32,
    writeStdSPS : b32,
    writeStdPPS : b32,
    stdVPSId : u32,
    stdSPSId : u32,
    stdPPSId : u32,
}

VkVideoEncodeH265SessionParametersFeedbackInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    hasStdVPSOverrides : b32,
    hasStdSPSOverrides : b32,
    hasStdPPSOverrides : b32,
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
    naluSliceSegmentEntries : VkVideoEncodeH265NaluSliceSegmentInfoKHR[],
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
    useMinQp : b32,
    minQp : VkVideoEncodeH265QpKHR,
    useMaxQp : b32,
    maxQp : VkVideoEncodeH265QpKHR,
    useMaxFrameSize : b32,
    maxFrameSize : VkVideoEncodeH265FrameSizeKHR,
}

VkVideoEncodeH265GopRemainingFrameInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    useGopRemainingFrames : b32,
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
    stdSPSs : StdVideoH264SequenceParameterSet[],
    stdPPSs : StdVideoH264PictureParameterSet[],
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
    sliceOffsets : u32[],
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
    colorAttachmentSamples : VkSampleCountFlagBits[],
    depthStencilAttachmentSamples : VkSampleCountFlagBits,
}

VkMultiviewPerViewAttributesInfoNVX :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    perViewAttributes : b32,
    perViewAttributesPositionXOnly : b32,
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
    rectangles : VkRectLayerKHR[],
}

VkPresentRegionsKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    swapchainCount : u32,
    regions : VkPresentRegionKHR[],
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
    performanceCounterQueryPools : b32,
    performanceCounterMultipleQueryPools : b32,
}

VkPhysicalDevicePerformanceQueryPropertiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    allowCommandBufferQueryCopies : b32,
}

VkPerformanceCounterKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    unit : VkPerformanceCounterUnitKHR,
    scope : VkPerformanceCounterScopeKHR,
    storage : VkPerformanceCounterStorageKHR,
    uuid : u8[VK_UUID_SIZE],
}

VkPerformanceCounterDescriptionKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPerformanceCounterDescriptionFlagsKHR,
    name : string,
    category : string,
    description : string,
}

VkQueryPoolPerformanceCreateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    queueFamilyIndex : u32,
    counterIndices : u32[],
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
    shaderSubgroupClock : b32,
    shaderDeviceClock : b32,
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
    stdVPSs : StdVideoH265VideoParameterSet[],
    stdSPSs : StdVideoH265SequenceParameterSet[],
    stdPPSs : StdVideoH265PictureParameterSet[],
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
    sliceSegmentOffsets : u32[],
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
    globalPriorityQuery : b32,
}

VkQueueFamilyGlobalPriorityPropertiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    priorities : VkQueueGlobalPriorityKHR[],
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
    pipelineFragmentShadingRate : b32,
    primitiveFragmentShadingRate : b32,
    attachmentFragmentShadingRate : b32,
}

VkPhysicalDeviceFragmentShadingRatePropertiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    minFragmentShadingRateAttachmentTexelSize : VkExtent2D,
    maxFragmentShadingRateAttachmentTexelSize : VkExtent2D,
    maxFragmentShadingRateAttachmentTexelSizeAspectRatio : u32,
    primitiveFragmentShadingRateWithMultipleViewports : b32,
    layeredShadingRateAttachments : b32,
    fragmentShadingRateNonTrivialCombinerOps : b32,
    maxFragmentSize : VkExtent2D,
    maxFragmentSizeAspectRatio : u32,
    maxFragmentShadingRateCoverageSamples : u32,
    maxFragmentShadingRateRasterizationSamples : VkSampleCountFlagBits,
    fragmentShadingRateWithShaderDepthStencilWrites : b32,
    fragmentShadingRateWithSampleMask : b32,
    fragmentShadingRateWithShaderSampleMask : b32,
    fragmentShadingRateWithConservativeRasterization : b32,
    fragmentShadingRateWithFragmentShaderInterlock : b32,
    fragmentShadingRateWithCustomSampleLocations : b32,
    fragmentShadingRateStrictMultiplyCombiner : b32,
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
    dynamicRenderingLocalRead : b32,
}

VkRenderingAttachmentLocationInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    colorAttachmentLocations : u32[],
}

VkRenderingInputAttachmentIndexInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    colorAttachmentInputIndices : u32[],
    pDepthInputAttachmentIndex : ptr[u32],
    pStencilInputAttachmentIndex : ptr[u32],
}

VkPhysicalDeviceShaderQuadControlFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderQuadControl : b32,
}

VkSurfaceProtectedCapabilitiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    supportsProtected : b32,
}

VkPhysicalDevicePresentWaitFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    presentWait : b32,
}

VkPhysicalDevicePipelineExecutablePropertiesFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pipelineExecutableInfo : b32,
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
    name : string,
    description : string,
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
    name : string,
    description : string,
    format : VkPipelineExecutableStatisticFormatKHR,
    value : VkPipelineExecutableStatisticValueKHR,
}

VkPipelineExecutableInternalRepresentationKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    name : string,
    description : string,
    isText : b32,
    dataSize : u64,
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
    libraries : VkPipeline[],
}

VkPresentIdKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    swapchainCount : u32,
    presentIds : u64[],
}

VkPhysicalDevicePresentIdFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    presentId : b32,
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
    referenceSlots : VkVideoReferenceSlotInfoKHR[],
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
    layers : VkVideoEncodeRateControlLayerInfoKHR[],
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
    hasOverrides : b32,
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
    fragmentShaderBarycentric : b32,
}

VkPhysicalDeviceFragmentShaderBarycentricPropertiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    triStripVertexOrderIndependentOfProvokingVertex : b32,
}

VkPhysicalDeviceShaderSubgroupUniformControlFlowFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderSubgroupUniformControlFlow : b32,
}

VkPhysicalDeviceWorkgroupMemoryExplicitLayoutFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    workgroupMemoryExplicitLayout : b32,
    workgroupMemoryExplicitLayoutScalarBlockLayout : b32,
    workgroupMemoryExplicitLayout8BitAccess : b32,
    workgroupMemoryExplicitLayout16BitAccess : b32,
}

VkPhysicalDeviceRayTracingMaintenance1FeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    rayTracingMaintenance1 : b32,
    rayTracingPipelineTraceRaysIndirect2 : b32,
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
    shaderSubgroupRotate : b32,
    shaderSubgroupRotateClustered : b32,
}

VkPhysicalDeviceShaderMaximalReconvergenceFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderMaximalReconvergence : b32,
}

VkPhysicalDeviceMaintenance5FeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maintenance5 : b32,
}

VkPhysicalDeviceMaintenance5PropertiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    earlyFragmentMultisampleCoverageAfterSampleCounting : b32,
    earlyFragmentSampleMaskTestBeforeSampleCounting : b32,
    depthStencilSwizzleOneSupport : b32,
    polygonModePointSize : b32,
    nonStrictSinglePixelWideLinesUseParallelogram : b32,
    nonStrictWideLinesUseParallelogram : b32,
}

VkRenderingAreaInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    viewMask : u32,
    colorAttachmentFormats : VkFormat[],
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
    rayTracingPositionFetch : b32,
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
    saturatingAccumulation : b32,
    scope : VkScopeKHR,
}

VkPhysicalDeviceCooperativeMatrixFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    cooperativeMatrix : b32,
    cooperativeMatrixRobustBufferAccess : b32,
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
    filmGrainSupport : b32,
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
    referenceNameSlotIndices : i32[VK_MAX_VIDEO_AV1_REFERENCES_PER_FRAME_KHR],
    frameHeaderOffset : u32,
    tileCount : u32,
    tileOffsets : u32[],
    tileSizes : u32[],
}

VkVideoDecodeAV1DpbSlotInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pStdReferenceInfo : ptr[StdVideoDecodeAV1ReferenceInfo],
}

VkPhysicalDeviceVideoMaintenance1FeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    videoMaintenance1 : b32,
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
    supportsNonZeroFirstInstance : b32,
}

VkVertexInputBindingDivisorDescriptionKHR :: struct {
    binding : u32,
    divisor : u32,
}

VkPipelineVertexInputDivisorStateCreateInfoKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    vertexBindingDivisors : VkVertexInputBindingDivisorDescriptionKHR[],
}

VkPhysicalDeviceVertexAttributeDivisorFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    vertexAttributeInstanceRateDivisor : b32,
    vertexAttributeInstanceRateZeroDivisor : b32,
}

VkPhysicalDeviceShaderFloatControls2FeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderFloatControls2 : b32,
}

VkPhysicalDeviceIndexTypeUint8FeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    indexTypeUint8 : b32,
}

VkPhysicalDeviceLineRasterizationFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    rectangularLines : b32,
    bresenhamLines : b32,
    smoothLines : b32,
    stippledRectangularLines : b32,
    stippledBresenhamLines : b32,
    stippledSmoothLines : b32,
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
    stippledLineEnable : b32,
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
    shaderExpectAssume : b32,
}

VkPhysicalDeviceMaintenance6FeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maintenance6 : b32,
}

VkPhysicalDeviceMaintenance6PropertiesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    blockTexelViewCompatibleMultipleLayers : b32,
    maxCombinedImageSamplerDescriptorCount : u32,
    fragmentShadingRateClampCombinerInputs : b32,
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
    descriptorSets : VkDescriptorSet[],
    dynamicOffsets : u32[],
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
    descriptorWrites : VkWriteDescriptorSet[],
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
    bufferIndices : u32[],
    offsets : VkDeviceSize[],
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
    objectName : string,
}

VkDebugMarkerObjectTagInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    objectType : VkDebugReportObjectTypeEXT,
    object : u64,
    tagName : u64,
    tagSize : u64,
    pTag : rawptr,
}

VkDebugMarkerMarkerInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    markerName : string,
    color : f32[4],
}

VkDedicatedAllocationImageCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    dedicatedAllocation : b32,
}

VkDedicatedAllocationBufferCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    dedicatedAllocation : b32,
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
    transformFeedback : b32,
    geometryStreams : b32,
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
    transformFeedbackQueries : b32,
    transformFeedbackStreamsLinesTriangles : b32,
    transformFeedbackRasterizationStreamSelect : b32,
    transformFeedbackDraw : b32,
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
    dataSize : u64,
    pData : rawptr,
}

VkCuFunctionCreateInfoNVX :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    module : VkCuModuleNVX,
    pName : string,
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
    params : rawptr[],
    extras : rawptr[],
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
    supportsTextureGatherLODBiasAMD : b32,
}

VkShaderResourceUsageAMD :: struct {
    numUsedVgprs : u32,
    numUsedSgprs : u32,
    ldsSizePerLocalWorkGroup : u32,
    ldsUsageSizeInBytes : u64,
    scratchMemUsageInBytes : u64,
}

VkShaderStatisticsInfoAMD :: struct {
    shaderStageMask : VkShaderStageFlags,
    resourceUsage : VkShaderResourceUsageAMD,
    numPhysicalVgprs : u32,
    numPhysicalSgprs : u32,
    numAvailableVgprs : u32,
    numAvailableSgprs : u32,
    computeWorkGroupSize : u32[3],
}

VkPhysicalDeviceCornerSampledImageFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    cornerSampledImage : b32,
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
    disabledValidationChecks : VkValidationCheckEXT[],
}

VkImageViewASTCDecodeModeEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    decodeMode : VkFormat,
}

VkPhysicalDeviceASTCDecodeFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    decodeModeSharedExponent : b32,
}

VkPhysicalDevicePipelineRobustnessFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pipelineRobustness : b32,
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
    conditionalRendering : b32,
    inheritedConditionalRendering : b32,
}

VkCommandBufferInheritanceConditionalRenderingInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    conditionalRenderingEnable : b32,
}

VkViewportWScalingNV :: struct {
    xcoeff : f32,
    ycoeff : f32,
}

VkPipelineViewportWScalingStateCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    viewportWScalingEnable : b32,
    viewportWScalings : VkViewportWScalingNV[],
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
    times : VkPresentTimeGOOGLE[],
}

VkPhysicalDeviceMultiviewPerViewAttributesPropertiesNVX :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    perViewPositionAllComponents : b32,
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
    viewportSwizzles : VkViewportSwizzleNV[],
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
    discardRectangles : VkRect2D[],
}

VkPhysicalDeviceConservativeRasterizationPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    primitiveOverestimationSize : f32,
    maxExtraPrimitiveOverestimationSize : f32,
    extraPrimitiveOverestimationSizeGranularity : f32,
    primitiveUnderestimation : b32,
    conservativePointAndLineRasterization : b32,
    degenerateTrianglesRasterized : b32,
    degenerateLinesRasterized : b32,
    fullyCoveredFragmentShaderInputVariable : b32,
    conservativeRasterizationPostDepthCoverage : b32,
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
    depthClipEnable : b32,
}

VkPipelineRasterizationDepthClipStateCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineRasterizationDepthClipStateCreateFlagsEXT,
    depthClipEnable : b32,
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
    relaxedLineRasterization : b32,
}

VkDebugUtilsLabelEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    labelName : string,
    color : f32[4],
}

VkDebugUtilsObjectNameInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    objectType : VkObjectType,
    objectHandle : u64,
    objectName : string,
}

VkDebugUtilsMessengerCallbackDataEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkDebugUtilsMessengerCallbackDataFlagsEXT,
    messageIdName : string,
    messageIdNumber : i32,
    message : string,
    queueLabels : VkDebugUtilsLabelEXT[],
    cmdBufLabels : VkDebugUtilsLabelEXT[],
    objects : VkDebugUtilsObjectNameInfoEXT[],
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
    tagSize : u64,
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
    sampleLocations : VkSampleLocationEXT[],
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
    attachmentInitialSampleLocations : VkAttachmentSampleLocationsEXT[],
    postSubpassSampleLocations : VkSubpassSampleLocationsEXT[],
}

VkPipelineSampleLocationsStateCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    sampleLocationsEnable : b32,
    sampleLocationsInfo : VkSampleLocationsInfoEXT,
}

VkPhysicalDeviceSampleLocationsPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    sampleLocationSampleCounts : VkSampleCountFlags,
    maxSampleLocationGridSize : VkExtent2D,
    sampleLocationCoordinateRange : f32[2],
    sampleLocationSubPixelBits : u32,
    variableSampleLocations : b32,
}

VkMultisamplePropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxSampleLocationGridSize : VkExtent2D,
}

VkPhysicalDeviceBlendOperationAdvancedFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    advancedBlendCoherentOperations : b32,
}

VkPhysicalDeviceBlendOperationAdvancedPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    advancedBlendMaxColorAttachments : u32,
    advancedBlendIndependentBlend : b32,
    advancedBlendNonPremultipliedSrcColor : b32,
    advancedBlendNonPremultipliedDstColor : b32,
    advancedBlendCorrelatedOverlap : b32,
    advancedBlendAllOperations : b32,
}

VkPipelineColorBlendAdvancedStateCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    srcPremultiplied : b32,
    dstPremultiplied : b32,
    blendOverlap : VkBlendOverlapEXT,
}

VkPipelineCoverageToColorStateCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineCoverageToColorStateCreateFlagsNV,
    coverageToColorEnable : b32,
    coverageToColorLocation : u32,
}

VkPipelineCoverageModulationStateCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkPipelineCoverageModulationStateCreateFlagsNV,
    coverageModulationMode : VkCoverageModulationModeNV,
    coverageModulationTableEnable : b32,
    coverageModulationTable : ptr[f32],
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
    shaderSMBuiltins : b32,
}

VkDrmFormatModifierPropertiesEXT :: struct {
    drmFormatModifier : u64,
    drmFormatModifierPlaneCount : u32,
    drmFormatModifierTilingFeatures : VkFormatFeatureFlags,
}

VkDrmFormatModifierPropertiesListEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    drmFormatModifierProperties : VkDrmFormatModifierPropertiesEXT[],
}

VkPhysicalDeviceImageDrmFormatModifierInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    drmFormatModifier : u64,
    sharingMode : VkSharingMode,
    queueFamilyIndices : u32[],
}

VkImageDrmFormatModifierListCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    drmFormatModifiers : u64[],
}

VkImageDrmFormatModifierExplicitCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    drmFormatModifier : u64,
    drmFormatModifierPlaneCount : u32,
    planeLayouts : VkSubresourceLayout[],
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
    drmFormatModifierProperties : VkDrmFormatModifierProperties2EXT[],
}

VkValidationCacheCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkValidationCacheCreateFlagsEXT,
    initialDataSize : u64,
    pInitialData : rawptr,
}

VkShaderModuleValidationCacheCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    validationCache : VkValidationCacheEXT,
}

VkShadingRatePaletteNV :: struct {
    shadingRatePaletteEntries : VkShadingRatePaletteEntryNV[],
}

VkPipelineViewportShadingRateImageStateCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shadingRateImageEnable : b32,
    shadingRatePalettes : VkShadingRatePaletteNV[],
}

VkPhysicalDeviceShadingRateImageFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shadingRateImage : b32,
    shadingRateCoarseSampleOrder : b32,
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
    sampleLocations : VkCoarseSampleLocationNV[],
}

VkPipelineViewportCoarseSampleOrderStateCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    sampleOrderType : VkCoarseSampleOrderTypeNV,
    customSampleOrders : VkCoarseSampleOrderCustomNV[],
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
    stages : VkPipelineShaderStageCreateInfo[],
    groups : VkRayTracingShaderGroupCreateInfoNV[],
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
    geometries : VkGeometryNV[],
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
    deviceIndices : u32[],
}

VkWriteDescriptorSetAccelerationStructureNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    accelerationStructures : VkAccelerationStructureNV[],
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
    // Most significant 8 bits is the mask
    instanceCustomIndexAndMask : u32,
    // Most significant 8 bits is the VkGeometryInstanceFlagsKHR
    instanceShaderBindingTableRecordOffsetAndFlags : u32,
    accelerationStructureReference : u64,
}

VkPhysicalDeviceRepresentativeFragmentTestFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    representativeFragmentTest : b32,
}

VkPipelineRepresentativeFragmentTestStateCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    representativeFragmentTestEnable : b32,
}

VkPhysicalDeviceImageViewImageFormatInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    imageViewType : VkImageViewType,
}

VkFilterCubicImageViewImageFormatPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    filterCubic : b32,
    filterCubicMinmax : b32,
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
    computeDerivativeGroupQuads : b32,
    computeDerivativeGroupLinear : b32,
}

VkPhysicalDeviceMeshShaderFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    taskShader : b32,
    meshShader : b32,
}

VkPhysicalDeviceMeshShaderPropertiesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxDrawMeshTasksCount : u32,
    maxTaskWorkGroupInvocations : u32,
    maxTaskWorkGroupSize : u32[3],
    maxTaskTotalMemorySize : u32,
    maxTaskOutputCount : u32,
    maxMeshWorkGroupInvocations : u32,
    maxMeshWorkGroupSize : u32[3],
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
    imageFootprint : b32,
}

VkPipelineViewportExclusiveScissorStateCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    exclusiveScissors : VkRect2D[],
}

VkPhysicalDeviceExclusiveScissorFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    exclusiveScissor : b32,
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
    shaderIntegerFunctions2 : b32,
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
    enable : b32,
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
    localDimmingSupport : b32,
}

VkSwapchainDisplayNativeHdrCreateInfoAMD :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    localDimmingEnable : b32,
}

VkPhysicalDeviceFragmentDensityMapFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    fragmentDensityMap : b32,
    fragmentDensityMapDynamic : b32,
    fragmentDensityMapNonSubsampledImages : b32,
}

VkPhysicalDeviceFragmentDensityMapPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    minFragmentDensityTexelSize : VkExtent2D,
    maxFragmentDensityTexelSize : VkExtent2D,
    fragmentDensityInvocations : b32,
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
    deviceCoherentMemory : b32,
}

VkPhysicalDeviceShaderImageAtomicInt64FeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderImageInt64Atomics : b32,
    sparseImageInt64Atomics : b32,
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
    memoryPriority : b32,
}

VkMemoryPriorityAllocateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    priority : f32,
}

VkPhysicalDeviceDedicatedAllocationImageAliasingFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    dedicatedAllocationImageAliasing : b32,
}

VkPhysicalDeviceBufferDeviceAddressFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    bufferDeviceAddress : b32,
    bufferDeviceAddressCaptureReplay : b32,
    bufferDeviceAddressMultiDevice : b32,
}

VkBufferDeviceAddressCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    deviceAddress : VkDeviceAddress,
}

VkValidationFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    enabledValidationFeatures : VkValidationFeatureEnableEXT[],
    disabledValidationFeatures : VkValidationFeatureDisableEXT[],
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
    cooperativeMatrix : b32,
    cooperativeMatrixRobustBufferAccess : b32,
}

VkPhysicalDeviceCooperativeMatrixPropertiesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    cooperativeMatrixSupportedStages : VkShaderStageFlags,
}

VkPhysicalDeviceCoverageReductionModeFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    coverageReductionMode : b32,
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
    fragmentShaderSampleInterlock : b32,
    fragmentShaderPixelInterlock : b32,
    fragmentShaderShadingRateInterlock : b32,
}

VkPhysicalDeviceYcbcrImageArraysFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    ycbcrImageArrays : b32,
}

VkPhysicalDeviceProvokingVertexFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    provokingVertexLast : b32,
    transformFeedbackPreservesProvokingVertex : b32,
}

VkPhysicalDeviceProvokingVertexPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    provokingVertexModePerPipeline : b32,
    transformFeedbackPreservesTriangleFanProvokingVertex : b32,
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
    shaderBufferFloat32Atomics : b32,
    shaderBufferFloat32AtomicAdd : b32,
    shaderBufferFloat64Atomics : b32,
    shaderBufferFloat64AtomicAdd : b32,
    shaderSharedFloat32Atomics : b32,
    shaderSharedFloat32AtomicAdd : b32,
    shaderSharedFloat64Atomics : b32,
    shaderSharedFloat64AtomicAdd : b32,
    shaderImageFloat32Atomics : b32,
    shaderImageFloat32AtomicAdd : b32,
    sparseImageFloat32Atomics : b32,
    sparseImageFloat32AtomicAdd : b32,
}

VkPhysicalDeviceExtendedDynamicStateFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    extendedDynamicState : b32,
}

VkPhysicalDeviceHostImageCopyFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    hostImageCopy : b32,
}

VkPhysicalDeviceHostImageCopyPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    copySrcLayouts : VkImageLayout[],
    copyDstLayouts : VkImageLayout[],
    optimalTilingLayoutUUID : u8[VK_UUID_SIZE],
    identicalMemoryTypeRequirements : b32,
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
    regions : VkMemoryToImageCopyEXT[],
}

VkCopyImageToMemoryInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkHostImageCopyFlagsEXT,
    srcImage : VkImage,
    srcImageLayout : VkImageLayout,
    regions : VkImageToMemoryCopyEXT[],
}

VkCopyImageToImageInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkHostImageCopyFlagsEXT,
    srcImage : VkImage,
    srcImageLayout : VkImageLayout,
    dstImage : VkImage,
    dstImageLayout : VkImageLayout,
    regions : VkImageCopy2[],
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
    optimalDeviceAccess : b32,
    identicalMemoryLayout : b32,
}

VkPhysicalDeviceMapMemoryPlacedFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    memoryMapPlaced : b32,
    memoryMapRangePlaced : b32,
    memoryUnmapReserve : b32,
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
    shaderBufferFloat16Atomics : b32,
    shaderBufferFloat16AtomicAdd : b32,
    shaderBufferFloat16AtomicMinMax : b32,
    shaderBufferFloat32AtomicMinMax : b32,
    shaderBufferFloat64AtomicMinMax : b32,
    shaderSharedFloat16Atomics : b32,
    shaderSharedFloat16AtomicAdd : b32,
    shaderSharedFloat16AtomicMinMax : b32,
    shaderSharedFloat32AtomicMinMax : b32,
    shaderSharedFloat64AtomicMinMax : b32,
    shaderImageFloat32AtomicMinMax : b32,
    sparseImageFloat32AtomicMinMax : b32,
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
    presentModes : VkPresentModeKHR[],
}

VkPhysicalDeviceSwapchainMaintenance1FeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    swapchainMaintenance1 : b32,
}

VkSwapchainPresentFenceInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    fences : VkFence[],
}

VkSwapchainPresentModesCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    presentModes : VkPresentModeKHR[],
}

VkSwapchainPresentModeInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    presentModes : VkPresentModeKHR[],
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
    imageIndices : u32[],
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
    deviceGeneratedCommands : b32,
}

VkGraphicsShaderGroupCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    stages : VkPipelineShaderStageCreateInfo[],
    pVertexInputState : ptr[VkPipelineVertexInputStateCreateInfo],
    pTessellationState : ptr[VkPipelineTessellationStateCreateInfo],
}

VkGraphicsPipelineShaderGroupsCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    groups : VkGraphicsShaderGroupCreateInfoNV[],
    pipelines : VkPipeline[],
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
    vertexDynamicStride : b32,
    pushconstantPipelineLayout : VkPipelineLayout,
    pushconstantShaderStageFlags : VkShaderStageFlags,
    pushconstantOffset : u32,
    pushconstantSize : u32,
    indirectStateFlags : VkIndirectStateFlagsNV,
    indexTypes : VkIndexType[],
    indexTypeValues : u32[],
}

VkIndirectCommandsLayoutCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkIndirectCommandsLayoutUsageFlagsNV,
    pipelineBindPoint : VkPipelineBindPoint,
    tokens : VkIndirectCommandsLayoutTokenNV[],
    streamStrides : u32[],
}

VkGeneratedCommandsInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pipelineBindPoint : VkPipelineBindPoint,
    pipeline : VkPipeline,
    indirectCommandsLayout : VkIndirectCommandsLayoutNV,
    streams : VkIndirectCommandsStreamNV[],
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
    inheritedViewportScissor2D : b32,
}

VkCommandBufferInheritanceViewportScissorInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    viewportScissor2D : b32,
    viewportDepths : VkViewport[],
}

VkPhysicalDeviceTexelBufferAlignmentFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    texelBufferAlignment : b32,
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
    depthBiasControl : b32,
    leastRepresentableValueForceUnormRepresentation : b32,
    floatRepresentation : b32,
    depthBiasExact : b32,
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
    depthBiasExact : b32,
}

VkPhysicalDeviceDeviceMemoryReportFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    deviceMemoryReport : b32,
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
    robustBufferAccess2 : b32,
    robustImageAccess2 : b32,
    nullDescriptor : b32,
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
    customBorderColors : b32,
    customBorderColorWithoutFormat : b32,
}

VkPhysicalDevicePresentBarrierFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    presentBarrier : b32,
}

VkSurfaceCapabilitiesPresentBarrierNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    presentBarrierSupported : b32,
}

VkSwapchainPresentBarrierCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    presentBarrierEnable : b32,
}

VkPhysicalDeviceDiagnosticsConfigFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    diagnosticsConfig : b32,
}

VkDeviceDiagnosticsConfigCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkDeviceDiagnosticsConfigFlagsNV,
}

VkCudaModuleCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    dataSize : u64,
    pData : rawptr,
}

VkCudaFunctionCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    module : VkCudaModuleNV,
    name : string,
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
    params : rawptr[],
    extras : rawptr[],
}

VkPhysicalDeviceCudaKernelLaunchFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    cudaKernelLaunchFeatures : b32,
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
    combinedImageSamplerDescriptorSingleArray : b32,
    bufferlessPushDescriptors : b32,
    allowSamplerImageViewPostSubmitCreation : b32,
    descriptorBufferOffsetAlignment : VkDeviceSize,
    maxDescriptorBufferBindings : u32,
    maxResourceDescriptorBufferBindings : u32,
    maxSamplerDescriptorBufferBindings : u32,
    maxEmbeddedImmutableSamplerBindings : u32,
    maxEmbeddedImmutableSamplers : u32,
    bufferCaptureReplayDescriptorDataSize : u64,
    imageCaptureReplayDescriptorDataSize : u64,
    imageViewCaptureReplayDescriptorDataSize : u64,
    samplerCaptureReplayDescriptorDataSize : u64,
    accelerationStructureCaptureReplayDescriptorDataSize : u64,
    samplerDescriptorSize : u64,
    combinedImageSamplerDescriptorSize : u64,
    sampledImageDescriptorSize : u64,
    storageImageDescriptorSize : u64,
    uniformTexelBufferDescriptorSize : u64,
    robustUniformTexelBufferDescriptorSize : u64,
    storageTexelBufferDescriptorSize : u64,
    robustStorageTexelBufferDescriptorSize : u64,
    uniformBufferDescriptorSize : u64,
    robustUniformBufferDescriptorSize : u64,
    storageBufferDescriptorSize : u64,
    robustStorageBufferDescriptorSize : u64,
    inputAttachmentDescriptorSize : u64,
    accelerationStructureDescriptorSize : u64,
    maxSamplerDescriptorBufferRange : VkDeviceSize,
    maxResourceDescriptorBufferRange : VkDeviceSize,
    samplerDescriptorBufferAddressSpaceSize : VkDeviceSize,
    resourceDescriptorBufferAddressSpaceSize : VkDeviceSize,
    descriptorBufferAddressSpaceSize : VkDeviceSize,
}

VkPhysicalDeviceDescriptorBufferDensityMapPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    combinedImageSamplerDensityMapDescriptorSize : u64,
}

VkPhysicalDeviceDescriptorBufferFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    descriptorBuffer : b32,
    descriptorBufferCaptureReplay : b32,
    descriptorBufferImageLayoutIgnored : b32,
    descriptorBufferPushDescriptors : b32,
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
    graphicsPipelineLibrary : b32,
}

VkPhysicalDeviceGraphicsPipelineLibraryPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    graphicsPipelineLibraryFastLinking : b32,
    graphicsPipelineLibraryIndependentInterpolationDecoration : b32,
}

VkGraphicsPipelineLibraryCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkGraphicsPipelineLibraryFlagsEXT,
}

VkPhysicalDeviceShaderEarlyAndLateFragmentTestsFeaturesAMD :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderEarlyAndLateFragmentTests : b32,
}

VkPhysicalDeviceFragmentShadingRateEnumsFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    fragmentShadingRateEnums : b32,
    supersampleFragmentShadingRates : b32,
    noInvocationFragmentShadingRates : b32,
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
    // Most significant 8 bits is the mask
    instanceCustomIndexAndMask : u32,
    // Most significant 8 bits is the VkGeometryInstanceFlagsKHR
    instanceShaderBindingTableRecordOffset : u32,
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
    // Most significant 8 bits is the mask
    instanceCustomIndexAndMask : u32,
    // Most significant 8 bits is the VkGeometryInstanceFlagsKHR
    instanceShaderBindingTableRecordOffsetAndFlags : u32,
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
    rayTracingMotionBlur : b32,
    rayTracingMotionBlurPipelineTraceRaysIndirect : b32,
}

VkPhysicalDeviceYcbcr2Plane444FormatsFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    ycbcr2plane444Formats : b32,
}

VkPhysicalDeviceFragmentDensityMap2FeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    fragmentDensityMapDeferred : b32,
}

VkPhysicalDeviceFragmentDensityMap2PropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    subsampledLoads : b32,
    subsampledCoarseReconstructionEarlyAccess : b32,
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
    imageCompressionControl : b32,
}

VkImageCompressionControlEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkImageCompressionFlagsEXT,
    fixedRateFlags : VkImageCompressionFixedRateFlagsEXT[],
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
    attachmentFeedbackLoopLayout : b32,
}

VkPhysicalDevice4444FormatsFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    formatA4R4G4B4 : b32,
    formatA4B4G4R4 : b32,
}

VkPhysicalDeviceFaultFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    deviceFault : b32,
    deviceFaultVendorBinary : b32,
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
    description : string,
    vendorFaultCode : u64,
    vendorFaultData : u64,
}

VkDeviceFaultInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    description : string,
    addressInfos : VkDeviceFaultAddressInfoEXT[],
    vendorInfos : VkDeviceFaultVendorInfoEXT[],
    pVendorBinaryData : rawptr,
}

VkDeviceFaultVendorBinaryHeaderVersionOneEXT :: struct {
    headerSize : u32,
    headerVersion : VkDeviceFaultVendorBinaryHeaderVersionEXT,
    vendorID : u32,
    deviceID : u32,
    driverVersion : u32,
    pipelineCacheUUID : u8[VK_UUID_SIZE],
    applicationNameOffset : u32,
    applicationVersion : u32,
    engineNameOffset : u32,
    engineVersion : u32,
    apiVersion : u32,
}

VkPhysicalDeviceRasterizationOrderAttachmentAccessFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    rasterizationOrderColorAttachmentAccess : b32,
    rasterizationOrderDepthAttachmentAccess : b32,
    rasterizationOrderStencilAttachmentAccess : b32,
}

VkPhysicalDeviceRGBA10X6FormatsFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    formatRgba10x6WithoutYCbCrSampler : b32,
}

VkPhysicalDeviceMutableDescriptorTypeFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    mutableDescriptorType : b32,
}

VkMutableDescriptorTypeListEXT :: struct {
    descriptorTypes : VkDescriptorType[],
}

VkMutableDescriptorTypeCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    mutableDescriptorTypeLists : VkMutableDescriptorTypeListEXT[],
}

VkPhysicalDeviceVertexInputDynamicStateFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    vertexInputDynamicState : b32,
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
    hasPrimary : b32,
    hasRender : b32,
    primaryMajor : i64,
    primaryMinor : i64,
    renderMajor : i64,
    renderMinor : i64,
}

VkPhysicalDeviceAddressBindingReportFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    reportAddressBinding : b32,
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
    depthClipControl : b32,
}

VkPipelineViewportDepthClipControlCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    negativeOneToOne : b32,
}

VkPhysicalDevicePrimitiveTopologyListRestartFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    primitiveTopologyListRestart : b32,
    primitiveTopologyPatchListRestart : b32,
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
    subpassShading : b32,
}

VkPhysicalDeviceSubpassShadingPropertiesHUAWEI :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxSubpassShadingWorkgroupSizeAspectRatio : u32,
}

VkPhysicalDeviceInvocationMaskFeaturesHUAWEI :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    invocationMask : b32,
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
    externalMemoryRDMA : b32,
}

VkPipelinePropertiesIdentifierEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pipelineIdentifier : u8[VK_UUID_SIZE],
}

VkPhysicalDevicePipelinePropertiesFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pipelinePropertiesIdentifier : b32,
}

VkPhysicalDeviceFrameBoundaryFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    frameBoundary : b32,
}

VkFrameBoundaryEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkFrameBoundaryFlagsEXT,
    frameID : u64,
    images : VkImage[],
    buffers : VkBuffer[],
    tagName : u64,
    tagSize : u64,
    pTag : rawptr,
}

VkPhysicalDeviceMultisampledRenderToSingleSampledFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    multisampledRenderToSingleSampled : b32,
}

VkSubpassResolvePerformanceQueryEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    optimal : b32,
}

VkMultisampledRenderToSingleSampledInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    multisampledRenderToSingleSampledEnable : b32,
    rasterizationSamples : VkSampleCountFlagBits,
}

VkPhysicalDeviceExtendedDynamicState2FeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    extendedDynamicState2 : b32,
    extendedDynamicState2LogicOp : b32,
    extendedDynamicState2PatchControlPoints : b32,
}

VkPhysicalDeviceColorWriteEnableFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    colorWriteEnable : b32,
}

VkPipelineColorWriteCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    attachmentCount : u32,
    colorWriteEnables : b32[],
}

VkPhysicalDevicePrimitivesGeneratedQueryFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    primitivesGeneratedQuery : b32,
    primitivesGeneratedQueryWithRasterizerDiscard : b32,
    primitivesGeneratedQueryWithNonZeroStreams : b32,
}

VkPhysicalDeviceImageViewMinLodFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    minLod : b32,
}

VkImageViewMinLodCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    minLod : f32,
}

VkPhysicalDeviceMultiDrawFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    multiDraw : b32,
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
    image2DViewOf3D : b32,
    sampler2DViewOf3D : b32,
}

VkPhysicalDeviceShaderTileImageFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderTileImageColorReadAccess : b32,
    shaderTileImageDepthReadAccess : b32,
    shaderTileImageStencilReadAccess : b32,
}

VkPhysicalDeviceShaderTileImagePropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderTileImageCoherentReadAccelerated : b32,
    shaderTileImageReadSampleFromPixelRateInvocation : b32,
    shaderTileImageReadFromHelperInvocation : b32,
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
    usageCounts : VkMicromapUsageEXT[],
    ppUsageCounts : ptr[VkMicromapUsageEXT][],
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
    micromap : b32,
    micromapCaptureReplay : b32,
    micromapHostCommands : b32,
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
    pVersionData : rawptr,
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
    discardable : b32,
}

VkAccelerationStructureTrianglesOpacityMicromapEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    indexType : VkIndexType,
    indexBuffer : VkDeviceOrHostAddressConstKHR,
    indexStride : VkDeviceSize,
    baseTriangle : u32,
    usageCounts : VkMicromapUsageEXT[],
    ppUsageCounts : ptr[VkMicromapUsageEXT][],
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
    clustercullingShader : b32,
    multiviewClusterCullingShader : b32,
}

VkPhysicalDeviceClusterCullingShaderPropertiesHUAWEI :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxWorkGroupCount : u32[3],
    maxWorkGroupSize : u32[3],
    maxOutputClusterCount : u32,
    indirectBufferOffsetAlignment : VkDeviceSize,
}

VkPhysicalDeviceClusterCullingShaderVrsFeaturesHUAWEI :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    clusterShadingRate : b32,
}

VkPhysicalDeviceBorderColorSwizzleFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    borderColorSwizzle : b32,
    borderColorSwizzleFromImage : b32,
}

VkSamplerBorderColorComponentMappingCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    components : VkComponentMapping,
    srgb : b32,
}

VkPhysicalDevicePageableDeviceLocalMemoryFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pageableDeviceLocalMemory : b32,
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
    schedulingControls : b32,
}

VkPhysicalDeviceSchedulingControlsPropertiesARM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    schedulingControlsFlags : VkPhysicalDeviceSchedulingControlsFlagsARM,
}

VkPhysicalDeviceImageSlicedViewOf3DFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    imageSlicedViewOf3D : b32,
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
    descriptorSetHostMapping : b32,
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
    descriptorOffset : u64,
    descriptorSize : u32,
}

VkPhysicalDeviceDepthClampZeroOneFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    depthClampZeroOne : b32,
}

VkPhysicalDeviceNonSeamlessCubeMapFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    nonSeamlessCubeMap : b32,
}

VkPhysicalDeviceRenderPassStripedFeaturesARM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    renderPassStriped : b32,
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
    stripeInfos : VkRenderPassStripeInfoARM[],
}

VkRenderPassStripeSubmitInfoARM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    stripeSemaphoreInfos : VkSemaphoreSubmitInfo[],
}

VkPhysicalDeviceFragmentDensityMapOffsetFeaturesQCOM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    fragmentDensityMapOffset : b32,
}

VkPhysicalDeviceFragmentDensityMapOffsetPropertiesQCOM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    fragmentDensityOffsetGranularity : VkExtent2D,
}

VkSubpassFragmentDensityMapOffsetEndInfoQCOM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    fragmentDensityOffsets : VkOffset2D[],
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
    indirectCopy : b32,
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
    memoryDecompression : b32,
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
    deviceGeneratedCompute : b32,
    deviceGeneratedComputePipelines : b32,
    deviceGeneratedComputeCaptureReplay : b32,
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
    linearColorAttachment : b32,
}

VkPhysicalDeviceImageCompressionControlSwapchainFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    imageCompressionControlSwapchain : b32,
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
    textureSampleWeighted : b32,
    textureBoxFilter : b32,
    textureBlockMatch : b32,
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
    nestedCommandBuffer : b32,
    nestedCommandBufferRendering : b32,
    nestedCommandBufferSimultaneousUse : b32,
}

VkPhysicalDeviceNestedCommandBufferPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxCommandBufferNestingLevel : u32,
}

VkExternalMemoryAcquireUnmodifiedEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    acquireUnmodifiedMemory : b32,
}

VkPhysicalDeviceExtendedDynamicState3FeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    extendedDynamicState3TessellationDomainOrigin : b32,
    extendedDynamicState3DepthClampEnable : b32,
    extendedDynamicState3PolygonMode : b32,
    extendedDynamicState3RasterizationSamples : b32,
    extendedDynamicState3SampleMask : b32,
    extendedDynamicState3AlphaToCoverageEnable : b32,
    extendedDynamicState3AlphaToOneEnable : b32,
    extendedDynamicState3LogicOpEnable : b32,
    extendedDynamicState3ColorBlendEnable : b32,
    extendedDynamicState3ColorBlendEquation : b32,
    extendedDynamicState3ColorWriteMask : b32,
    extendedDynamicState3RasterizationStream : b32,
    extendedDynamicState3ConservativeRasterizationMode : b32,
    extendedDynamicState3ExtraPrimitiveOverestimationSize : b32,
    extendedDynamicState3DepthClipEnable : b32,
    extendedDynamicState3SampleLocationsEnable : b32,
    extendedDynamicState3ColorBlendAdvanced : b32,
    extendedDynamicState3ProvokingVertexMode : b32,
    extendedDynamicState3LineRasterizationMode : b32,
    extendedDynamicState3LineStippleEnable : b32,
    extendedDynamicState3DepthClipNegativeOneToOne : b32,
    extendedDynamicState3ViewportWScalingEnable : b32,
    extendedDynamicState3ViewportSwizzle : b32,
    extendedDynamicState3CoverageToColorEnable : b32,
    extendedDynamicState3CoverageToColorLocation : b32,
    extendedDynamicState3CoverageModulationMode : b32,
    extendedDynamicState3CoverageModulationTableEnable : b32,
    extendedDynamicState3CoverageModulationTable : b32,
    extendedDynamicState3CoverageReductionMode : b32,
    extendedDynamicState3RepresentativeFragmentTestEnable : b32,
    extendedDynamicState3ShadingRateImageEnable : b32,
}

VkPhysicalDeviceExtendedDynamicState3PropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    dynamicPrimitiveTopologyUnrestricted : b32,
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
    srcPremultiplied : b32,
    dstPremultiplied : b32,
    blendOverlap : VkBlendOverlapEXT,
    clampResults : b32,
}

VkPhysicalDeviceSubpassMergeFeedbackFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    subpassMergeFeedback : b32,
}

VkRenderPassCreationControlEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    disallowMerging : b32,
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
    description : string,
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
    drivers : VkDirectDriverLoadingInfoLUNARG[],
}

VkPhysicalDeviceShaderModuleIdentifierFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderModuleIdentifier : b32,
}

VkPhysicalDeviceShaderModuleIdentifierPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderModuleIdentifierAlgorithmUUID : u8[VK_UUID_SIZE],
}

VkPipelineShaderStageModuleIdentifierCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    identifier : u8[],
}

VkShaderModuleIdentifierEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    identifier : u8[],
}

VkPhysicalDeviceOpticalFlowFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    opticalFlow : b32,
}

VkPhysicalDeviceOpticalFlowPropertiesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    supportedOutputGridSizes : VkOpticalFlowGridSizeFlagsNV,
    supportedHintGridSizes : VkOpticalFlowGridSizeFlagsNV,
    hintSupported : b32,
    costSupported : b32,
    bidirectionalFlowSupported : b32,
    globalFlowSupported : b32,
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
    regions : VkRect2D[],
}

VkPhysicalDeviceLegacyDitheringFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    legacyDithering : b32,
}

VkPhysicalDevicePipelineProtectedAccessFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    pipelineProtectedAccess : b32,
}

VkPhysicalDeviceShaderObjectFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderObject : b32,
}

VkPhysicalDeviceShaderObjectPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderBinaryUUID : u8[VK_UUID_SIZE],
    shaderBinaryVersion : u32,
}

VkShaderCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    flags : VkShaderCreateFlagsEXT,
    stage : VkShaderStageFlagBits,
    nextStage : VkShaderStageFlags,
    codeType : VkShaderCodeTypeEXT,
    codeSize : u64,
    pCode : rawptr,
    name : string,
    setLayouts : VkDescriptorSetLayout[],
    pushConstantRanges : VkPushConstantRange[],
    pSpecializationInfo : ptr[VkSpecializationInfo],
}

VkPhysicalDeviceTilePropertiesFeaturesQCOM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    tileProperties : b32,
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
    amigoProfiling : b32,
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
    multiviewPerViewViewports : b32,
}

VkPhysicalDeviceRayTracingInvocationReorderPropertiesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    rayTracingInvocationReorderReorderingHint : VkRayTracingInvocationReorderModeNV,
}

VkPhysicalDeviceRayTracingInvocationReorderFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    rayTracingInvocationReorder : b32,
}

VkPhysicalDeviceExtendedSparseAddressSpaceFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    extendedSparseAddressSpace : b32,
}

VkPhysicalDeviceExtendedSparseAddressSpacePropertiesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    extendedSparseAddressSpaceSize : VkDeviceSize,
    extendedSparseImageUsageFlags : VkImageUsageFlags,
    extendedSparseBufferUsageFlags : VkBufferUsageFlags,
}

VkLayerSettingEXT :: struct {
    layerName : string,
    settingName : string,
    type : VkLayerSettingTypeEXT,
    values : rawptr,
}

VkLayerSettingsCreateInfoEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    settings : VkLayerSettingEXT[],
}

VkPhysicalDeviceShaderCoreBuiltinsFeaturesARM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderCoreBuiltins : b32,
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
    pipelineLibraryGroupHandles : b32,
}

VkPhysicalDeviceDynamicRenderingUnusedAttachmentsFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    dynamicRenderingUnusedAttachments : b32,
}

VkLatencySleepModeInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    lowLatencyMode : b32,
    lowLatencyBoost : b32,
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
    timings : VkLatencyTimingsFrameReportNV[],
}

VkLatencySubmissionPresentIdNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    presentID : u64,
}

VkSwapchainLatencyCreateInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    latencyModeEnable : b32,
}

VkOutOfBandQueueTypeInfoNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    queueType : VkOutOfBandQueueTypeNV,
}

VkLatencySurfaceCapabilitiesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    presentModes : VkPresentModeKHR[],
}

VkPhysicalDeviceMultiviewPerViewRenderAreasFeaturesQCOM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    multiviewPerViewRenderAreas : b32,
}

VkMultiviewPerViewRenderAreasRenderPassBeginInfoQCOM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    perViewRenderAreas : VkRect2D[],
}

VkPhysicalDevicePerStageDescriptorSetFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    perStageDescriptorSet : b32,
    dynamicPipelineLayout : b32,
}

VkPhysicalDeviceImageProcessing2FeaturesQCOM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    textureBlockMatch2 : b32,
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
    selectableCubicWeights : b32,
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
    ycbcrDegamma : b32,
}

VkSamplerYcbcrConversionYcbcrDegammaCreateInfoQCOM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    enableYDegamma : b32,
    enableCbCrDegamma : b32,
}

VkPhysicalDeviceCubicClampFeaturesQCOM :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    cubicRangeClamp : b32,
}

VkPhysicalDeviceAttachmentFeedbackLoopDynamicStateFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    attachmentFeedbackLoopDynamicState : b32,
}

VkPhysicalDeviceLayeredDriverPropertiesMSFT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    underlyingAPI : VkLayeredDriverUnderlyingApiMSFT,
}

VkPhysicalDeviceDescriptorPoolOverallocationFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    descriptorPoolOverallocation : b32,
}

VkPhysicalDeviceShaderAtomicFloat16VectorFeaturesNV :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    shaderFloat16VectorAtomics : b32,
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
    arrayOfPointers : b32,
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
    geometries : VkAccelerationStructureGeometryKHR[],
    ppGeometries : ptr[VkAccelerationStructureGeometryKHR][],
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
    accelerationStructures : VkAccelerationStructureKHR[],
}

VkPhysicalDeviceAccelerationStructureFeaturesKHR :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    accelerationStructure : b32,
    accelerationStructureCaptureReplay : b32,
    accelerationStructureIndirectBuild : b32,
    accelerationStructureHostCommands : b32,
    descriptorBindingAccelerationStructureUpdateAfterBind : b32,
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
    pVersionData : rawptr,
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
    stages : VkPipelineShaderStageCreateInfo[],
    groups : VkRayTracingShaderGroupCreateInfoKHR[],
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
    rayTracingPipeline : b32,
    rayTracingPipelineShaderGroupHandleCaptureReplay : b32,
    rayTracingPipelineShaderGroupHandleCaptureReplayMixed : b32,
    rayTracingPipelineTraceRaysIndirect : b32,
    rayTraversalPrimitiveCulling : b32,
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
    rayQuery : b32,
}

VkPhysicalDeviceMeshShaderFeaturesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    taskShader : b32,
    meshShader : b32,
    multiviewMeshShader : b32,
    primitiveFragmentShadingRateMeshShader : b32,
    meshShaderQueries : b32,
}

VkPhysicalDeviceMeshShaderPropertiesEXT :: struct {
    sType : VkStructureType,
    pNext : rawptr,
    maxTaskWorkGroupTotalCount : u32,
    maxTaskWorkGroupCount : u32[3],
    maxTaskWorkGroupInvocations : u32,
    maxTaskWorkGroupSize : u32[3],
    maxTaskPayloadSize : u32,
    maxTaskSharedMemorySize : u32,
    maxTaskPayloadAndSharedMemorySize : u32,
    maxMeshWorkGroupTotalCount : u32,
    maxMeshWorkGroupCount : u32[3],
    maxMeshWorkGroupInvocations : u32,
    maxMeshWorkGroupSize : u32[3],
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
    prefersLocalInvocationVertexOutput : b32,
    prefersLocalInvocationPrimitiveOutput : b32,
    prefersCompactVertexOutput : b32,
    prefersCompactPrimitiveOutput : b32,
}

VkDrawMeshTasksIndirectCommandEXT :: struct {
    groupCountX : u32,
    groupCountY : u32,
    groupCountZ : u32,
}

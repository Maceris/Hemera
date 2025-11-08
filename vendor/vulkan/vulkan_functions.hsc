package vulkan

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

vkCreateInstance(
    pCreateInfo: ptr[VkInstanceCreateInfo],
    pAllocator: ptr[VkAllocationCallbacks],
    pInstance: ptr[VkInstance]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyInstance(
    instance: VkInstance,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkEnumeratePhysicalDevices(
    instance: VkInstance,
    pPhysicalDeviceCount: ptr[u32],
    pPhysicalDevices: ptr[VkPhysicalDevice]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPhysicalDeviceFeatures(
    physicalDevice: VkPhysicalDevice,
    pFeatures: ptr[VkPhysicalDeviceFeatures]) -> void
{
    //TODO(ches) do this
}

vkGetPhysicalDeviceFormatProperties(
    physicalDevice: VkPhysicalDevice,
    format: VkFormat,
    pFormatProperties: ptr[VkFormatProperties]) -> void
{
    //TODO(ches) do this
}

vkGetPhysicalDeviceImageFormatProperties(
    physicalDevice: VkPhysicalDevice,
    format: VkFormat,
    type: VkImageType,
    tiling: VkImageTiling,
    usage: VkImageUsageFlags,
    flags: VkImageCreateFlags,
    pImageFormatProperties: ptr[VkImageFormatProperties]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPhysicalDeviceProperties(
    physicalDevice: VkPhysicalDevice,
    pProperties: ptr[VkPhysicalDeviceProperties]) -> void
{
    //TODO(ches) do this
}

vkGetPhysicalDeviceQueueFamilyProperties(
    physicalDevice: VkPhysicalDevice,
    pQueueFamilyPropertyCount: ptr[u32],
    pQueueFamilyProperties: ptr[VkQueueFamilyProperties]) -> void
{
    //TODO(ches) do this
}

vkGetPhysicalDeviceMemoryProperties(
    physicalDevice: VkPhysicalDevice,
    pMemoryProperties: ptr[VkPhysicalDeviceMemoryProperties]) -> void
{
    //TODO(ches) do this
}

vkGetInstanceProcAddr(
    instance: VkInstance,
    pName: ptr[char]) -> PFN_vkVoidFunction
{
    //TODO(ches) do this
}

vkGetDeviceProcAddr(
    device: VkDevice,
    pName: ptr[char]) -> PFN_vkVoidFunction
{
    //TODO(ches) do this
}

vkCreateDevice(
    physicalDevice: VkPhysicalDevice,
    pCreateInfo: ptr[VkDeviceCreateInfo],
    pAllocator: ptr[VkAllocationCallbacks],
    pDevice: ptr[VkDevice]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyDevice(
    device: VkDevice,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkEnumerateInstanceExtensionProperties(
    pLayerName: ptr[char],
    pPropertyCount: ptr[u32],
    pProperties: ptr[VkExtensionProperties]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkEnumerateDeviceExtensionProperties(
    physicalDevice: VkPhysicalDevice,
    pLayerName: ptr[char],
    pPropertyCount: ptr[u32],
    pProperties: ptr[VkExtensionProperties]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkEnumerateInstanceLayerProperties(
    pPropertyCount: ptr[u32],
    pProperties: ptr[VkLayerProperties]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkEnumerateDeviceLayerProperties(
    physicalDevice: VkPhysicalDevice,
    pPropertyCount: ptr[u32],
    pProperties: ptr[VkLayerProperties]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetDeviceQueue(
    device: VkDevice,
    queueFamilyIndex: u32,
    queueIndex: u32,
    pQueue: ptr[VkQueue]) -> void
{
    //TODO(ches) do this
}

vkQueueSubmit(
    queue: VkQueue,
    submitCount: u32,
    pSubmits: ptr[VkSubmitInfo],
    fence: VkFence) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkQueueWaitIdle(
    queue: VkQueue) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDeviceWaitIdle(
    device: VkDevice) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkAllocateMemory(
    device: VkDevice,
    pAllocateInfo: ptr[VkMemoryAllocateInfo],
    pAllocator: ptr[VkAllocationCallbacks],
    pMemory: ptr[VkDeviceMemory]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkFreeMemory(
    device: VkDevice,
    memory: VkDeviceMemory,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkMapMemory(
    device: VkDevice,
    memory: VkDeviceMemory,
    offset: VkDeviceSize,
    size: VkDeviceSize,
    flags: VkMemoryMapFlags,
    ptr[ptr[void]] ppData) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkUnmapMemory(
    device: VkDevice,
    memory: VkDeviceMemory) -> void
{
    //TODO(ches) do this
}

vkFlushMappedMemoryRanges(
    device: VkDevice,
    memoryRangeCount: u32,
    pMemoryRanges: ptr[VkMappedMemoryRange]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkInvalidateMappedMemoryRanges(
    device: VkDevice,
    memoryRangeCount: u32,
    pMemoryRanges: ptr[VkMappedMemoryRange]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetDeviceMemoryCommitment(
    device: VkDevice,
    memory: VkDeviceMemory,
    pCommittedMemoryInBytes: ptr[VkDeviceSize]) -> void
{
    //TODO(ches) do this
}

vkBindBufferMemory(
    device: VkDevice,
    buffer: VkBuffer,
    memory: VkDeviceMemory,
    memoryOffset: VkDeviceSize) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkBindImageMemory(
    device: VkDevice,
    image: VkImage,
    memory: VkDeviceMemory,
    memoryOffset: VkDeviceSize) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetBufferMemoryRequirements(
    device: VkDevice,
    buffer: VkBuffer,
    pMemoryRequirements: ptr[VkMemoryRequirements]) -> void
{
    //TODO(ches) do this
}

vkGetImageMemoryRequirements(
    device: VkDevice,
    image: VkImage,
    pMemoryRequirements: ptr[VkMemoryRequirements]) -> void
{
    //TODO(ches) do this
}

vkGetImageSparseMemoryRequirements(
    device: VkDevice,
    image: VkImage,
    pSparseMemoryRequirementCount: ptr[u32],
    pSparseMemoryRequirements: ptr[VkSparseImageMemoryRequirements]) -> void
{
    //TODO(ches) do this
}

vkGetPhysicalDeviceSparseImageFormatProperties(
    physicalDevice: VkPhysicalDevice,
    format: VkFormat,
    type: VkImageType,
    samples: VkSampleCountFlagBits,
    usage: VkImageUsageFlags,
    tiling: VkImageTiling,
    pPropertyCount: ptr[u32],
    pProperties: ptr[VkSparseImageFormatProperties]) -> void
{
    //TODO(ches) do this
}

vkQueueBindSparse(
    queue: VkQueue,
    bindInfoCount: u32,
    pBindInfo: ptr[VkBindSparseInfo],
    fence: VkFence) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCreateFence(
    device: VkDevice,
    pCreateInfo: ptr[VkFenceCreateInfo],
    pAllocator: ptr[VkAllocationCallbacks],
    pFence: ptr[VkFence]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyFence(
    device: VkDevice,
    fence: VkFence,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkResetFences(
    device: VkDevice,
    fenceCount: u32,
    pFences: ptr[VkFence]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetFenceStatus(
    device: VkDevice,
    fence: VkFence) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkWaitForFences(
    device: VkDevice,
    fenceCount: u32,
    pFences: ptr[VkFence],
    waitAll: VkBool32,
    timeout: u64) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCreateSemaphore(
    device: VkDevice,
    pCreateInfo: ptr[VkSemaphoreCreateInfo],
    pAllocator: ptr[VkAllocationCallbacks],
    pSemaphore: ptr[VkSemaphore]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroySemaphore(
    device: VkDevice,
    semaphore: VkSemaphore,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkCreateEvent(
    device: VkDevice,
    pCreateInfo: ptr[VkEventCreateInfo],
    pAllocator: ptr[VkAllocationCallbacks],
    pEvent: ptr[VkEvent]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyEvent(
    device: VkDevice,
    event: VkEvent,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkGetEventStatus(
    device: VkDevice,
    event: VkEvent) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkSetEvent(
    device: VkDevice,
    event: VkEvent) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkResetEvent(
    device: VkDevice,
    event: VkEvent) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCreateQueryPool(
    device: VkDevice,
    pCreateInfo: ptr[VkQueryPoolCreateInfo],
    pAllocator: ptr[VkAllocationCallbacks],
    pQueryPool: ptr[VkQueryPool]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyQueryPool(
    device: VkDevice,
    queryPool: VkQueryPool,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkGetQueryPoolResults(
    device: VkDevice,
    queryPool: VkQueryPool,
    firstQuery: u32,
    queryCount: u32,
    dataSize: uint,
    pData: ptr[void],
    stride: VkDeviceSize,
    flags: VkQueryResultFlags) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCreateBuffer(
    device: VkDevice,
    pCreateInfo: ptr[VkBufferCreateInfo],
    pAllocator: ptr[VkAllocationCallbacks],
    pBuffer: ptr[VkBuffer]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyBuffer(
    device: VkDevice,
    buffer: VkBuffer,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkCreateBufferView(
    device: VkDevice,
    pCreateInfo: ptr[VkBufferViewCreateInfo],
    pAllocator: ptr[VkAllocationCallbacks],
    pView: ptr[VkBufferView]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyBufferView(
    device: VkDevice,
    bufferView: VkBufferView,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkCreateImage(
    device: VkDevice,
    pCreateInfo: ptr[VkImageCreateInfo],
    pAllocator: ptr[VkAllocationCallbacks],
    pImage: ptr[VkImage]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyImage(
    device: VkDevice,
    image: VkImage,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkGetImageSubresourceLayout(
    device: VkDevice,
    image: VkImage,
    pSubresource: ptr[VkImageSubresource],
    pLayout: ptr[VkSubresourceLayout]) -> void
{
    //TODO(ches) do this
}

vkCreateImageView(
    device: VkDevice,
    pCreateInfo: ptr[VkImageViewCreateInfo],
    pAllocator: ptr[VkAllocationCallbacks],
    pView: ptr[VkImageView]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyImageView(
    device: VkDevice,
    imageView: VkImageView,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkCreateShaderModule(
    device: VkDevice,
    pCreateInfo: ptr[VkShaderModuleCreateInfo],
    pAllocator: ptr[VkAllocationCallbacks],
    pShaderModule: ptr[VkShaderModule]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyShaderModule(
    device: VkDevice,
    shaderModule: VkShaderModule,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkCreatePipelineCache(
    device: VkDevice,
    pCreateInfo: ptr[VkPipelineCacheCreateInfo],
    pAllocator: ptr[VkAllocationCallbacks],
    pPipelineCache: ptr[VkPipelineCache]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyPipelineCache(
    device: VkDevice,
    pipelineCache: VkPipelineCache,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkGetPipelineCacheData(
    device: VkDevice,
    pipelineCache: VkPipelineCache,
    pDataSize: ptr[uint],
    pData: ptr[void]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkMergePipelineCaches(
    device: VkDevice,
    dstCache: VkPipelineCache,
    srcCacheCount: u32,
    pSrcCaches: ptr[VkPipelineCache]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCreateGraphicsPipelines(
    device: VkDevice,
    pipelineCache: VkPipelineCache,
    createInfoCount: u32,
    pCreateInfos: ptr[VkGraphicsPipelineCreateInfo],
    pAllocator: ptr[VkAllocationCallbacks],
    pPipelines: ptr[VkPipeline]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCreateComputePipelines(
    device: VkDevice,
    pipelineCache: VkPipelineCache,
    createInfoCount: u32,
    pCreateInfos: ptr[VkComputePipelineCreateInfo],
    pAllocator: ptr[VkAllocationCallbacks],
    pPipelines: ptr[VkPipeline]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyPipeline(
    device: VkDevice,
    pipeline: VkPipeline,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkCreatePipelineLayout(
    device: VkDevice,
    pCreateInfo: ptr[VkPipelineLayoutCreateInfo],
    pAllocator: ptr[VkAllocationCallbacks],
    pPipelineLayout: ptr[VkPipelineLayout]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyPipelineLayout(
    device: VkDevice,
    pipelineLayout: VkPipelineLayout,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkCreateSampler(
    device: VkDevice,
    pCreateInfo: ptr[VkSamplerCreateInfo],
    pAllocator: ptr[VkAllocationCallbacks],
    pSampler: ptr[VkSampler]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroySampler(
    device: VkDevice,
    sampler: VkSampler,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkCreateDescriptorSetLayout(
    device: VkDevice,
    pCreateInfo: ptr[VkDescriptorSetLayoutCreateInfo],
    pAllocator: ptr[VkAllocationCallbacks],
    pSetLayout: ptr[VkDescriptorSetLayout]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyDescriptorSetLayout(
    device: VkDevice,
    descriptorSetLayout: VkDescriptorSetLayout,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkCreateDescriptorPool(
    device: VkDevice,
    pCreateInfo: ptr[VkDescriptorPoolCreateInfo],
    pAllocator: ptr[VkAllocationCallbacks],
    pDescriptorPool: ptr[VkDescriptorPool]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyDescriptorPool(
    device: VkDevice,
    descriptorPool: VkDescriptorPool,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkResetDescriptorPool(
    device: VkDevice,
    descriptorPool: VkDescriptorPool,
    flags: VkDescriptorPoolResetFlags) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkAllocateDescriptorSets(
    device: VkDevice,
    pAllocateInfo: ptr[VkDescriptorSetAllocateInfo],
    pDescriptorSets: ptr[VkDescriptorSet]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkFreeDescriptorSets(
    device: VkDevice,
    descriptorPool: VkDescriptorPool,
    descriptorSetCount: u32,
    pDescriptorSets: ptr[VkDescriptorSet]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkUpdateDescriptorSets(
    device: VkDevice,
    descriptorWriteCount: u32,
    pDescriptorWrites: ptr[VkWriteDescriptorSet],
    descriptorCopyCount: u32,
    pDescriptorCopies: ptr[VkCopyDescriptorSet]) -> void
{
    //TODO(ches) do this
}

vkCreateFramebuffer(
    device: VkDevice,
    pCreateInfo: ptr[VkFramebufferCreateInfo],
    pAllocator: ptr[VkAllocationCallbacks],
    pFramebuffer: ptr[VkFramebuffer]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyFramebuffer(
    device: VkDevice,
    framebuffer: VkFramebuffer,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkCreateRenderPass(
    device: VkDevice,
    pCreateInfo: ptr[VkRenderPassCreateInfo],
    pAllocator: ptr[VkAllocationCallbacks],
    pRenderPass: ptr[VkRenderPass]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyRenderPass(
    device: VkDevice,
    renderPass: VkRenderPass,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkGetRenderAreaGranularity(
    device: VkDevice,
    renderPass: VkRenderPass,
    pGranularity: ptr[VkExtent2D]) -> void
{
    //TODO(ches) do this
}

vkCreateCommandPool(
    device: VkDevice,
    pCreateInfo: ptr[VkCommandPoolCreateInfo],
    pAllocator: ptr[VkAllocationCallbacks],
    pCommandPool: ptr[VkCommandPool]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyCommandPool(
    device: VkDevice,
    commandPool: VkCommandPool,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkResetCommandPool(
    device: VkDevice,
    commandPool: VkCommandPool,
    flags: VkCommandPoolResetFlags) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkAllocateCommandBuffers(
    device: VkDevice,
    pAllocateInfo: ptr[VkCommandBufferAllocateInfo],
    pCommandBuffers: ptr[VkCommandBuffer]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkFreeCommandBuffers(
    device: VkDevice,
    commandPool: VkCommandPool,
    commandBufferCount: u32,
    pCommandBuffers: ptr[VkCommandBuffer]) -> void
{
    //TODO(ches) do this
}

vkBeginCommandBuffer(
    commandBuffer: VkCommandBuffer,
    pBeginInfo: ptr[VkCommandBufferBeginInfo]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkEndCommandBuffer(
    commandBuffer: VkCommandBuffer) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkResetCommandBuffer(
    commandBuffer: VkCommandBuffer,
    flags: VkCommandBufferResetFlags) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCmdBindPipeline(
    commandBuffer: VkCommandBuffer,
    pipelineBindPoint: VkPipelineBindPoint,
    pipeline: VkPipeline) -> void
{
    //TODO(ches) do this
}

vkCmdSetViewport(
    commandBuffer: VkCommandBuffer,
    firstViewport: u32,
    viewportCount: u32,
    pViewports: ptr[VkViewport]) -> void
{
    //TODO(ches) do this
}

vkCmdSetScissor(
    commandBuffer: VkCommandBuffer,
    firstScissor: u32,
    scissorCount: u32,
    pScissors: ptr[VkRect2D]) -> void
{
    //TODO(ches) do this
}

vkCmdSetLineWidth(
    commandBuffer: VkCommandBuffer,
    lineWidth: float) -> void
{
    //TODO(ches) do this
}

vkCmdSetDepthBias(
    commandBuffer: VkCommandBuffer,
    depthBiasConstantFactor: float,
    depthBiasClamp: float,
    depthBiasSlopeFactor: float) -> void
{
    //TODO(ches) do this
}

vkCmdSetBlendConstants(
    commandBuffer: VkCommandBuffer,
    float blendConstants[4]) -> void
{
    //TODO(ches) do this
}

vkCmdSetDepthBounds(
    commandBuffer: VkCommandBuffer,
    minDepthBounds: float,
    maxDepthBounds: float) -> void
{
    //TODO(ches) do this
}

vkCmdSetStencilCompareMask(
    commandBuffer: VkCommandBuffer,
    faceMask: VkStencilFaceFlags,
    compareMask: u32) -> void
{
    //TODO(ches) do this
}

vkCmdSetStencilWriteMask(
    commandBuffer: VkCommandBuffer,
    faceMask: VkStencilFaceFlags,
    writeMask: u32) -> void
{
    //TODO(ches) do this
}

vkCmdSetStencilReference(
    commandBuffer: VkCommandBuffer,
    faceMask: VkStencilFaceFlags,
    reference: u32) -> void
{
    //TODO(ches) do this
}

vkCmdBindDescriptorSets(
    commandBuffer: VkCommandBuffer,
    pipelineBindPoint: VkPipelineBindPoint,
    layout: VkPipelineLayout,
    firstSet: u32,
    descriptorSetCount: u32,
    pDescriptorSets: ptr[VkDescriptorSet],
    dynamicOffsetCount: u32,
    pDynamicOffsets: ptr[u32]) -> void
{
    //TODO(ches) do this
}

vkCmdBindIndexBuffer(
    commandBuffer: VkCommandBuffer,
    buffer: VkBuffer,
    offset: VkDeviceSize,
    indexType: VkIndexType) -> void
{
    //TODO(ches) do this
}

vkCmdBindVertexBuffers(
    commandBuffer: VkCommandBuffer,
    firstBinding: u32,
    bindingCount: u32,
    pBuffers: ptr[VkBuffer],
    pOffsets: ptr[VkDeviceSize]) -> void
{
    //TODO(ches) do this
}

vkCmdDraw(
    commandBuffer: VkCommandBuffer,
    vertexCount: u32,
    instanceCount: u32,
    firstVertex: u32,
    firstInstance: u32) -> void
{
    //TODO(ches) do this
}

vkCmdDrawIndexed(
    commandBuffer: VkCommandBuffer,
    indexCount: u32,
    instanceCount: u32,
    firstIndex: u32,
    vertexOffset: i32,
    firstInstance: u32) -> void
{
    //TODO(ches) do this
}

vkCmdDrawIndirect(
    commandBuffer: VkCommandBuffer,
    buffer: VkBuffer,
    offset: VkDeviceSize,
    drawCount: u32,
    stride: u32) -> void
{
    //TODO(ches) do this
}

vkCmdDrawIndexedIndirect(
    commandBuffer: VkCommandBuffer,
    buffer: VkBuffer,
    offset: VkDeviceSize,
    drawCount: u32,
    stride: u32) -> void
{
    //TODO(ches) do this
}

vkCmdDispatch(
    commandBuffer: VkCommandBuffer,
    groupCountX: u32,
    groupCountY: u32,
    groupCountZ: u32) -> void
{
    //TODO(ches) do this
}

vkCmdDispatchIndirect(
    commandBuffer: VkCommandBuffer,
    buffer: VkBuffer,
    offset: VkDeviceSize) -> void
{
    //TODO(ches) do this
}

vkCmdCopyBuffer(
    commandBuffer: VkCommandBuffer,
    srcBuffer: VkBuffer,
    dstBuffer: VkBuffer,
    regionCount: u32,
    pRegions: ptr[VkBufferCopy]) -> void
{
    //TODO(ches) do this
}

vkCmdCopyImage(
    commandBuffer: VkCommandBuffer,
    srcImage: VkImage,
    srcImageLayout: VkImageLayout,
    dstImage: VkImage,
    dstImageLayout: VkImageLayout,
    regionCount: u32,
    pRegions: ptr[VkImageCopy]) -> void
{
    //TODO(ches) do this
}

vkCmdBlitImage(
    commandBuffer: VkCommandBuffer,
    srcImage: VkImage,
    srcImageLayout: VkImageLayout,
    dstImage: VkImage,
    dstImageLayout: VkImageLayout,
    regionCount: u32,
    pRegions: ptr[VkImageBlit],
    filter: VkFilter) -> void
{
    //TODO(ches) do this
}

vkCmdCopyBufferToImage(
    commandBuffer: VkCommandBuffer,
    srcBuffer: VkBuffer,
    dstImage: VkImage,
    dstImageLayout: VkImageLayout,
    regionCount: u32,
    pRegions: ptr[VkBufferImageCopy]) -> void
{
    //TODO(ches) do this
}

vkCmdCopyImageToBuffer(
    commandBuffer: VkCommandBuffer,
    srcImage: VkImage,
    srcImageLayout: VkImageLayout,
    dstBuffer: VkBuffer,
    regionCount: u32,
    pRegions: ptr[VkBufferImageCopy]) -> void
{
    //TODO(ches) do this
}

vkCmdUpdateBuffer(
    commandBuffer: VkCommandBuffer,
    dstBuffer: VkBuffer,
    dstOffset: VkDeviceSize,
    dataSize: VkDeviceSize,
    pData: ptr[void]) -> void
{
    //TODO(ches) do this
}

vkCmdFillBuffer(
    commandBuffer: VkCommandBuffer,
    dstBuffer: VkBuffer,
    dstOffset: VkDeviceSize,
    size: VkDeviceSize,
    data: u32) -> void
{
    //TODO(ches) do this
}

vkCmdClearColorImage(
    commandBuffer: VkCommandBuffer,
    image: VkImage,
    imageLayout: VkImageLayout,
    pColor: ptr[VkClearColorValue],
    rangeCount: u32,
    pRanges: ptr[VkImageSubresourceRange]) -> void
{
    //TODO(ches) do this
}

vkCmdClearDepthStencilImage(
    commandBuffer: VkCommandBuffer,
    image: VkImage,
    imageLayout: VkImageLayout,
    pDepthStencil: ptr[VkClearDepthStencilValue],
    rangeCount: u32,
    pRanges: ptr[VkImageSubresourceRange]) -> void
{
    //TODO(ches) do this
}

vkCmdClearAttachments(
    commandBuffer: VkCommandBuffer,
    attachmentCount: u32,
    pAttachments: ptr[VkClearAttachment],
    rectCount: u32,
    pRects: ptr[VkClearRect]) -> void
{
    //TODO(ches) do this
}

vkCmdResolveImage(
    commandBuffer: VkCommandBuffer,
    srcImage: VkImage,
    srcImageLayout: VkImageLayout,
    dstImage: VkImage,
    dstImageLayout: VkImageLayout,
    regionCount: u32,
    pRegions: ptr[VkImageResolve]) -> void
{
    //TODO(ches) do this
}

vkCmdSetEvent(
    commandBuffer: VkCommandBuffer,
    event: VkEvent,
    stageMask: VkPipelineStageFlags) -> void
{
    //TODO(ches) do this
}

vkCmdResetEvent(
    commandBuffer: VkCommandBuffer,
    event: VkEvent,
    stageMask: VkPipelineStageFlags) -> void
{
    //TODO(ches) do this
}

vkCmdWaitEvents(
    commandBuffer: VkCommandBuffer,
    eventCount: u32,
    pEvents: ptr[VkEvent],
    srcStageMask: VkPipelineStageFlags,
    dstStageMask: VkPipelineStageFlags,
    memoryBarrierCount: u32,
    pMemoryBarriers: ptr[VkMemoryBarrier],
    bufferMemoryBarrierCount: u32,
    pBufferMemoryBarriers: ptr[VkBufferMemoryBarrier],
    imageMemoryBarrierCount: u32,
    pImageMemoryBarriers: ptr[VkImageMemoryBarrier]) -> void
{
    //TODO(ches) do this
}

vkCmdPipelineBarrier(
    commandBuffer: VkCommandBuffer,
    srcStageMask: VkPipelineStageFlags,
    dstStageMask: VkPipelineStageFlags,
    dependencyFlags: VkDependencyFlags,
    memoryBarrierCount: u32,
    pMemoryBarriers: ptr[VkMemoryBarrier],
    bufferMemoryBarrierCount: u32,
    pBufferMemoryBarriers: ptr[VkBufferMemoryBarrier],
    imageMemoryBarrierCount: u32,
    pImageMemoryBarriers: ptr[VkImageMemoryBarrier]) -> void
{
    //TODO(ches) do this
}

vkCmdBeginQuery(
    commandBuffer: VkCommandBuffer,
    queryPool: VkQueryPool,
    query: u32,
    flags: VkQueryControlFlags) -> void
{
    //TODO(ches) do this
}

vkCmdEndQuery(
    commandBuffer: VkCommandBuffer,
    queryPool: VkQueryPool,
    query: u32) -> void
{
    //TODO(ches) do this
}

vkCmdResetQueryPool(
    commandBuffer: VkCommandBuffer,
    queryPool: VkQueryPool,
    firstQuery: u32,
    queryCount: u32) -> void
{
    //TODO(ches) do this
}

vkCmdWriteTimestamp(
    commandBuffer: VkCommandBuffer,
    pipelineStage: VkPipelineStageFlagBits,
    queryPool: VkQueryPool,
    query: u32) -> void
{
    //TODO(ches) do this
}

vkCmdCopyQueryPoolResults(
    commandBuffer: VkCommandBuffer,
    queryPool: VkQueryPool,
    firstQuery: u32,
    queryCount: u32,
    dstBuffer: VkBuffer,
    dstOffset: VkDeviceSize,
    stride: VkDeviceSize,
    flags: VkQueryResultFlags) -> void
{
    //TODO(ches) do this
}

vkCmdPushConstants(
    commandBuffer: VkCommandBuffer,
    layout: VkPipelineLayout,
    stageFlags: VkShaderStageFlags,
    offset: u32,
    size: u32,
    pValues: ptr[void]) -> void
{
    //TODO(ches) do this
}

vkCmdBeginRenderPass(
    commandBuffer: VkCommandBuffer,
    pRenderPassBegin: ptr[VkRenderPassBeginInfo],
    contents: VkSubpassContents) -> void
{
    //TODO(ches) do this
}

vkCmdNextSubpass(
    commandBuffer: VkCommandBuffer,
    contents: VkSubpassContents) -> void
{
    //TODO(ches) do this
}

vkCmdEndRenderPass(
    commandBuffer: VkCommandBuffer) -> void
{
    //TODO(ches) do this
}

vkCmdExecuteCommands(
    commandBuffer: VkCommandBuffer,
    commandBufferCount: u32,
    pCommandBuffers: ptr[VkCommandBuffer]) -> void
{
    //TODO(ches) do this
}

vkEnumerateInstanceVersion(
    pApiVersion: ptr[u32]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkBindBufferMemory2(
    device: VkDevice,
    bindInfoCount: u32,
    pBindInfos: ptr[VkBindBufferMemoryInfo]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkBindImageMemory2(
    device: VkDevice,
    bindInfoCount: u32,
    pBindInfos: ptr[VkBindImageMemoryInfo]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetDeviceGroupPeerMemoryFeatures(
    device: VkDevice,
    heapIndex: u32,
    localDeviceIndex: u32,
    remoteDeviceIndex: u32,
    pPeerMemoryFeatures: ptr[VkPeerMemoryFeatureFlags]) -> void
{
    //TODO(ches) do this
}

vkCmdSetDeviceMask(
    commandBuffer: VkCommandBuffer,
    deviceMask: u32) -> void
{
    //TODO(ches) do this
}

vkCmdDispatchBase(
    commandBuffer: VkCommandBuffer,
    baseGroupX: u32,
    baseGroupY: u32,
    baseGroupZ: u32,
    groupCountX: u32,
    groupCountY: u32,
    groupCountZ: u32) -> void
{
    //TODO(ches) do this
}

vkEnumeratePhysicalDeviceGroups(
    instance: VkInstance,
    pPhysicalDeviceGroupCount: ptr[u32],
    pPhysicalDeviceGroupProperties: ptr[VkPhysicalDeviceGroupProperties]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetImageMemoryRequirements2(
    device: VkDevice,
    pInfo: ptr[VkImageMemoryRequirementsInfo2],
    pMemoryRequirements: ptr[VkMemoryRequirements2]) -> void
{
    //TODO(ches) do this
}

vkGetBufferMemoryRequirements2(
    device: VkDevice,
    pInfo: ptr[VkBufferMemoryRequirementsInfo2],
    pMemoryRequirements: ptr[VkMemoryRequirements2]) -> void
{
    //TODO(ches) do this
}

vkGetImageSparseMemoryRequirements2(
    device: VkDevice,
    pInfo: ptr[VkImageSparseMemoryRequirementsInfo2],
    pSparseMemoryRequirementCount: ptr[u32],
    pSparseMemoryRequirements: ptr[VkSparseImageMemoryRequirements2]) -> void
{
    //TODO(ches) do this
}

vkGetPhysicalDeviceFeatures2(
    physicalDevice: VkPhysicalDevice,
    pFeatures: ptr[VkPhysicalDeviceFeatures2]) -> void
{
    //TODO(ches) do this
}

vkGetPhysicalDeviceProperties2(
    physicalDevice: VkPhysicalDevice,
    pProperties: ptr[VkPhysicalDeviceProperties2]) -> void
{
    //TODO(ches) do this
}

vkGetPhysicalDeviceFormatProperties2(
    physicalDevice: VkPhysicalDevice,
    format: VkFormat,
    pFormatProperties: ptr[VkFormatProperties2]) -> void
{
    //TODO(ches) do this
}

vkGetPhysicalDeviceImageFormatProperties2(
    physicalDevice: VkPhysicalDevice,
    pImageFormatInfo: ptr[VkPhysicalDeviceImageFormatInfo2],
    pImageFormatProperties: ptr[VkImageFormatProperties2]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPhysicalDeviceQueueFamilyProperties2(
    physicalDevice: VkPhysicalDevice,
    pQueueFamilyPropertyCount: ptr[u32],
    pQueueFamilyProperties: ptr[VkQueueFamilyProperties2]) -> void
{
    //TODO(ches) do this
}

vkGetPhysicalDeviceMemoryProperties2(
    physicalDevice: VkPhysicalDevice,
    pMemoryProperties: ptr[VkPhysicalDeviceMemoryProperties2]) -> void
{
    //TODO(ches) do this
}

vkGetPhysicalDeviceSparseImageFormatProperties2(
    physicalDevice: VkPhysicalDevice,
    pFormatInfo: ptr[VkPhysicalDeviceSparseImageFormatInfo2],
    pPropertyCount: ptr[u32],
    pProperties: ptr[VkSparseImageFormatProperties2]) -> void
{
    //TODO(ches) do this
}

vkTrimCommandPool(
    device: VkDevice,
    commandPool: VkCommandPool,
    flags: VkCommandPoolTrimFlags) -> void
{
    //TODO(ches) do this
}

vkGetDeviceQueue2(
    device: VkDevice,
    pQueueInfo: ptr[VkDeviceQueueInfo2],
    pQueue: ptr[VkQueue]) -> void
{
    //TODO(ches) do this
}

vkCreateSamplerYcbcrConversion(
    device: VkDevice,
    pCreateInfo: ptr[VkSamplerYcbcrConversionCreateInfo],
    pAllocator: ptr[VkAllocationCallbacks],
    pYcbcrConversion: ptr[VkSamplerYcbcrConversion]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroySamplerYcbcrConversion(
    device: VkDevice,
    ycbcrConversion: VkSamplerYcbcrConversion,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkCreateDescriptorUpdateTemplate(
    device: VkDevice,
    pCreateInfo: ptr[VkDescriptorUpdateTemplateCreateInfo],
    pAllocator: ptr[VkAllocationCallbacks],
    pDescriptorUpdateTemplate: ptr[VkDescriptorUpdateTemplate]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyDescriptorUpdateTemplate(
    device: VkDevice,
    descriptorUpdateTemplate: VkDescriptorUpdateTemplate,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkUpdateDescriptorSetWithTemplate(
    device: VkDevice,
    descriptorSet: VkDescriptorSet,
    descriptorUpdateTemplate: VkDescriptorUpdateTemplate,
    pData: ptr[void]) -> void
{
    //TODO(ches) do this
}

vkGetPhysicalDeviceExternalBufferProperties(
    physicalDevice: VkPhysicalDevice,
    pExternalBufferInfo: ptr[VkPhysicalDeviceExternalBufferInfo],
    pExternalBufferProperties: ptr[VkExternalBufferProperties]) -> void
{
    //TODO(ches) do this
}

vkGetPhysicalDeviceExternalFenceProperties(
    physicalDevice: VkPhysicalDevice,
    pExternalFenceInfo: ptr[VkPhysicalDeviceExternalFenceInfo],
    pExternalFenceProperties: ptr[VkExternalFenceProperties]) -> void
{
    //TODO(ches) do this
}

vkGetPhysicalDeviceExternalSemaphoreProperties(
    physicalDevice: VkPhysicalDevice,
    pExternalSemaphoreInfo: ptr[VkPhysicalDeviceExternalSemaphoreInfo],
    pExternalSemaphoreProperties: ptr[VkExternalSemaphoreProperties]) -> void
{
    //TODO(ches) do this
}

vkGetDescriptorSetLayoutSupport(
    device: VkDevice,
    pCreateInfo: ptr[VkDescriptorSetLayoutCreateInfo],
    pSupport: ptr[VkDescriptorSetLayoutSupport]) -> void
{
    //TODO(ches) do this
}

(0, 1, 2, 0)// Patch version should always be set to 0

vkCmdDrawIndirectCount(
    commandBuffer: VkCommandBuffer,
    buffer: VkBuffer,
    offset: VkDeviceSize,
    countBuffer: VkBuffer,
    countBufferOffset: VkDeviceSize,
    maxDrawCount: u32,
    stride: u32) -> void
{
    //TODO(ches) do this
}

vkCmdDrawIndexedIndirectCount(
    commandBuffer: VkCommandBuffer,
    buffer: VkBuffer,
    offset: VkDeviceSize,
    countBuffer: VkBuffer,
    countBufferOffset: VkDeviceSize,
    maxDrawCount: u32,
    stride: u32) -> void
{
    //TODO(ches) do this
}

vkCreateRenderPass2(
    device: VkDevice,
    pCreateInfo: ptr[VkRenderPassCreateInfo2],
    pAllocator: ptr[VkAllocationCallbacks],
    pRenderPass: ptr[VkRenderPass]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCmdBeginRenderPass2(
    commandBuffer: VkCommandBuffer,
    pRenderPassBegin: ptr[VkRenderPassBeginInfo],
    pSubpassBeginInfo: ptr[VkSubpassBeginInfo]) -> void
{
    //TODO(ches) do this
}

vkCmdNextSubpass2(
    commandBuffer: VkCommandBuffer,
    pSubpassBeginInfo: ptr[VkSubpassBeginInfo],
    pSubpassEndInfo: ptr[VkSubpassEndInfo]) -> void
{
    //TODO(ches) do this
}

vkCmdEndRenderPass2(
    commandBuffer: VkCommandBuffer,
    pSubpassEndInfo: ptr[VkSubpassEndInfo]) -> void
{
    //TODO(ches) do this
}

vkResetQueryPool(
    device: VkDevice,
    queryPool: VkQueryPool,
    firstQuery: u32,
    queryCount: u32) -> void
{
    //TODO(ches) do this
}

vkGetSemaphoreCounterValue(
    device: VkDevice,
    semaphore: VkSemaphore,
    pValue: ptr[u64]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkWaitSemaphores(
    device: VkDevice,
    pWaitInfo: ptr[VkSemaphoreWaitInfo],
    timeout: u64) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkSignalSemaphore(
    device: VkDevice,
    pSignalInfo: ptr[VkSemaphoreSignalInfo]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetBufferDeviceAddress(
    device: VkDevice,
    pInfo: ptr[VkBufferDeviceAddressInfo]) -> VkDeviceAddress
{
    //TODO(ches) do this
}

vkGetBufferOpaqueCaptureAddress(
    device: VkDevice,
    pInfo: ptr[VkBufferDeviceAddressInfo]) -> u64
{
    //TODO(ches) do this
}

vkGetDeviceMemoryOpaqueCaptureAddress(
    device: VkDevice,
    pInfo: ptr[VkDeviceMemoryOpaqueCaptureAddressInfo]) -> u64
{
    //TODO(ches) do this
}

vkGetPhysicalDeviceToolProperties(
    physicalDevice: VkPhysicalDevice,
    pToolCount: ptr[u32],
    pToolProperties: ptr[VkPhysicalDeviceToolProperties]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCreatePrivateDataSlot(
    device: VkDevice,
    pCreateInfo: ptr[VkPrivateDataSlotCreateInfo],
    pAllocator: ptr[VkAllocationCallbacks],
    pPrivateDataSlot: ptr[VkPrivateDataSlot]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyPrivateDataSlot(
    device: VkDevice,
    privateDataSlot: VkPrivateDataSlot,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkSetPrivateData(
    device: VkDevice,
    objectType: VkObjectType,
    objectHandle: u64,
    privateDataSlot: VkPrivateDataSlot,
    data: u64) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPrivateData(
    device: VkDevice,
    objectType: VkObjectType,
    objectHandle: u64,
    privateDataSlot: VkPrivateDataSlot,
    pData: ptr[u64]) -> void
{
    //TODO(ches) do this
}

vkCmdSetEvent2(
    commandBuffer: VkCommandBuffer,
    event: VkEvent,
    pDependencyInfo: ptr[VkDependencyInfo]) -> void
{
    //TODO(ches) do this
}

vkCmdResetEvent2(
    commandBuffer: VkCommandBuffer,
    event: VkEvent,
    stageMask: VkPipelineStageFlags2) -> void
{
    //TODO(ches) do this
}

vkCmdWaitEvents2(
    commandBuffer: VkCommandBuffer,
    eventCount: u32,
    pEvents: ptr[VkEvent],
    pDependencyInfos: ptr[VkDependencyInfo]) -> void
{
    //TODO(ches) do this
}

vkCmdPipelineBarrier2(
    commandBuffer: VkCommandBuffer,
    pDependencyInfo: ptr[VkDependencyInfo]) -> void
{
    //TODO(ches) do this
}

vkCmdWriteTimestamp2(
    commandBuffer: VkCommandBuffer,
    stage: VkPipelineStageFlags2,
    queryPool: VkQueryPool,
    query: u32) -> void
{
    //TODO(ches) do this
}

vkQueueSubmit2(
    queue: VkQueue,
    submitCount: u32,
    pSubmits: ptr[VkSubmitInfo2],
    fence: VkFence) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCmdCopyBuffer2(
    commandBuffer: VkCommandBuffer,
    pCopyBufferInfo: ptr[VkCopyBufferInfo2]) -> void
{
    //TODO(ches) do this
}

vkCmdCopyImage2(
    commandBuffer: VkCommandBuffer,
    pCopyImageInfo: ptr[VkCopyImageInfo2]) -> void
{
    //TODO(ches) do this
}

vkCmdCopyBufferToImage2(
    commandBuffer: VkCommandBuffer,
    pCopyBufferToImageInfo: ptr[VkCopyBufferToImageInfo2]) -> void
{
    //TODO(ches) do this
}

vkCmdCopyImageToBuffer2(
    commandBuffer: VkCommandBuffer,
    pCopyImageToBufferInfo: ptr[VkCopyImageToBufferInfo2]) -> void
{
    //TODO(ches) do this
}

vkCmdBlitImage2(
    commandBuffer: VkCommandBuffer,
    pBlitImageInfo: ptr[VkBlitImageInfo2]) -> void
{
    //TODO(ches) do this
}

vkCmdResolveImage2(
    commandBuffer: VkCommandBuffer,
    pResolveImageInfo: ptr[VkResolveImageInfo2]) -> void
{
    //TODO(ches) do this
}

vkCmdBeginRendering(
    commandBuffer: VkCommandBuffer,
    pRenderingInfo: ptr[VkRenderingInfo]) -> void
{
    //TODO(ches) do this
}

vkCmdEndRendering(
    commandBuffer: VkCommandBuffer) -> void
{
    //TODO(ches) do this
}

vkCmdSetCullMode(
    commandBuffer: VkCommandBuffer,
    cullMode: VkCullModeFlags) -> void
{
    //TODO(ches) do this
}

vkCmdSetFrontFace(
    commandBuffer: VkCommandBuffer,
    frontFace: VkFrontFace) -> void
{
    //TODO(ches) do this
}

vkCmdSetPrimitiveTopology(
    commandBuffer: VkCommandBuffer,
    primitiveTopology: VkPrimitiveTopology) -> void
{
    //TODO(ches) do this
}

vkCmdSetViewportWithCount(
    commandBuffer: VkCommandBuffer,
    viewportCount: u32,
    pViewports: ptr[VkViewport]) -> void
{
    //TODO(ches) do this
}

vkCmdSetScissorWithCount(
    commandBuffer: VkCommandBuffer,
    scissorCount: u32,
    pScissors: ptr[VkRect2D]) -> void
{
    //TODO(ches) do this
}

vkCmdBindVertexBuffers2(
    commandBuffer: VkCommandBuffer,
    firstBinding: u32,
    bindingCount: u32,
    pBuffers: ptr[VkBuffer],
    pOffsets: ptr[VkDeviceSize],
    pSizes: ptr[VkDeviceSize],
    pStrides: ptr[VkDeviceSize]) -> void
{
    //TODO(ches) do this
}

vkCmdSetDepthTestEnable(
    commandBuffer: VkCommandBuffer,
    depthTestEnable: VkBool32) -> void
{
    //TODO(ches) do this
}

vkCmdSetDepthWriteEnable(
    commandBuffer: VkCommandBuffer,
    depthWriteEnable: VkBool32) -> void
{
    //TODO(ches) do this
}

vkCmdSetDepthCompareOp(
    commandBuffer: VkCommandBuffer,
    depthCompareOp: VkCompareOp) -> void
{
    //TODO(ches) do this
}

vkCmdSetDepthBoundsTestEnable(
    commandBuffer: VkCommandBuffer,
    depthBoundsTestEnable: VkBool32) -> void
{
    //TODO(ches) do this
}

vkCmdSetStencilTestEnable(
    commandBuffer: VkCommandBuffer,
    stencilTestEnable: VkBool32) -> void
{
    //TODO(ches) do this
}

vkCmdSetStencilOp(
    commandBuffer: VkCommandBuffer,
    faceMask: VkStencilFaceFlags,
    failOp: VkStencilOp,
    passOp: VkStencilOp,
    depthFailOp: VkStencilOp,
    compareOp: VkCompareOp) -> void
{
    //TODO(ches) do this
}

vkCmdSetRasterizerDiscardEnable(
    commandBuffer: VkCommandBuffer,
    rasterizerDiscardEnable: VkBool32) -> void
{
    //TODO(ches) do this
}

vkCmdSetDepthBiasEnable(
    commandBuffer: VkCommandBuffer,
    depthBiasEnable: VkBool32) -> void
{
    //TODO(ches) do this
}

vkCmdSetPrimitiveRestartEnable(
    commandBuffer: VkCommandBuffer,
    primitiveRestartEnable: VkBool32) -> void
{
    //TODO(ches) do this
}

vkGetDeviceBufferMemoryRequirements(
    device: VkDevice,
    pInfo: ptr[VkDeviceBufferMemoryRequirements],
    pMemoryRequirements: ptr[VkMemoryRequirements2]) -> void
{
    //TODO(ches) do this
}

vkGetDeviceImageMemoryRequirements(
    device: VkDevice,
    pInfo: ptr[VkDeviceImageMemoryRequirements],
    pMemoryRequirements: ptr[VkMemoryRequirements2]) -> void
{
    //TODO(ches) do this
}

vkGetDeviceImageSparseMemoryRequirements(
    device: VkDevice,
    pInfo: ptr[VkDeviceImageMemoryRequirements],
    pSparseMemoryRequirementCount: ptr[u32],
    pSparseMemoryRequirements: ptr[VkSparseImageMemoryRequirements2]) -> void
{
    //TODO(ches) do this
}

vkDestroySurfaceKHR(
    instance: VkInstance,
    surface: VkSurfaceKHR,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkGetPhysicalDeviceSurfaceSupportKHR(
    physicalDevice: VkPhysicalDevice,
    queueFamilyIndex: u32,
    surface: VkSurfaceKHR,
    pSupported: ptr[VkBool32]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
    physicalDevice: VkPhysicalDevice,
    surface: VkSurfaceKHR,
    pSurfaceCapabilities: ptr[VkSurfaceCapabilitiesKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPhysicalDeviceSurfaceFormatsKHR(
    physicalDevice: VkPhysicalDevice,
    surface: VkSurfaceKHR,
    pSurfaceFormatCount: ptr[u32],
    pSurfaceFormats: ptr[VkSurfaceFormatKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPhysicalDeviceSurfacePresentModesKHR(
    physicalDevice: VkPhysicalDevice,
    surface: VkSurfaceKHR,
    pPresentModeCount: ptr[u32],
    pPresentModes: ptr[VkPresentModeKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCreateSwapchainKHR(
    device: VkDevice,
    pCreateInfo: ptr[VkSwapchainCreateInfoKHR],
    pAllocator: ptr[VkAllocationCallbacks],
    pSwapchain: ptr[VkSwapchainKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroySwapchainKHR(
    device: VkDevice,
    swapchain: VkSwapchainKHR,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkGetSwapchainImagesKHR(
    device: VkDevice,
    swapchain: VkSwapchainKHR,
    pSwapchainImageCount: ptr[u32],
    pSwapchainImages: ptr[VkImage]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkAcquireNextImageKHR(
    device: VkDevice,
    swapchain: VkSwapchainKHR,
    timeout: u64,
    semaphore: VkSemaphore,
    fence: VkFence,
    pImageIndex: ptr[u32]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkQueuePresentKHR(
    queue: VkQueue,
    pPresentInfo: ptr[VkPresentInfoKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetDeviceGroupPresentCapabilitiesKHR(
    device: VkDevice,
    pDeviceGroupPresentCapabilities: ptr[VkDeviceGroupPresentCapabilitiesKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetDeviceGroupSurfacePresentModesKHR(
    device: VkDevice,
    surface: VkSurfaceKHR,
    pModes: ptr[VkDeviceGroupPresentModeFlagsKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPhysicalDevicePresentRectanglesKHR(
    physicalDevice: VkPhysicalDevice,
    surface: VkSurfaceKHR,
    pRectCount: ptr[u32],
    pRects: ptr[VkRect2D]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkAcquireNextImage2KHR(
    device: VkDevice,
    pAcquireInfo: ptr[VkAcquireNextImageInfoKHR],
    pImageIndex: ptr[u32]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPhysicalDeviceDisplayPropertiesKHR(
    physicalDevice: VkPhysicalDevice,
    pPropertyCount: ptr[u32],
    pProperties: ptr[VkDisplayPropertiesKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPhysicalDeviceDisplayPlanePropertiesKHR(
    physicalDevice: VkPhysicalDevice,
    pPropertyCount: ptr[u32],
    pProperties: ptr[VkDisplayPlanePropertiesKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetDisplayPlaneSupportedDisplaysKHR(
    physicalDevice: VkPhysicalDevice,
    planeIndex: u32,
    pDisplayCount: ptr[u32],
    pDisplays: ptr[VkDisplayKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetDisplayModePropertiesKHR(
    physicalDevice: VkPhysicalDevice,
    display: VkDisplayKHR,
    pPropertyCount: ptr[u32],
    pProperties: ptr[VkDisplayModePropertiesKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCreateDisplayModeKHR(
    physicalDevice: VkPhysicalDevice,
    display: VkDisplayKHR,
    pCreateInfo: ptr[VkDisplayModeCreateInfoKHR],
    pAllocator: ptr[VkAllocationCallbacks],
    pMode: ptr[VkDisplayModeKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetDisplayPlaneCapabilitiesKHR(
    physicalDevice: VkPhysicalDevice,
    mode: VkDisplayModeKHR,
    planeIndex: u32,
    pCapabilities: ptr[VkDisplayPlaneCapabilitiesKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCreateDisplayPlaneSurfaceKHR(
    instance: VkInstance,
    pCreateInfo: ptr[VkDisplaySurfaceCreateInfoKHR],
    pAllocator: ptr[VkAllocationCallbacks],
    pSurface: ptr[VkSurfaceKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCreateSharedSwapchainsKHR(
    device: VkDevice,
    swapchainCount: u32,
    pCreateInfos: ptr[VkSwapchainCreateInfoKHR],
    pAllocator: ptr[VkAllocationCallbacks],
    pSwapchains: ptr[VkSwapchainKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPhysicalDeviceVideoCapabilitiesKHR(
    physicalDevice: VkPhysicalDevice,
    pVideoProfile: ptr[VkVideoProfileInfoKHR],
    pCapabilities: ptr[VkVideoCapabilitiesKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPhysicalDeviceVideoFormatPropertiesKHR(
    physicalDevice: VkPhysicalDevice,
    pVideoFormatInfo: ptr[VkPhysicalDeviceVideoFormatInfoKHR],
    pVideoFormatPropertyCount: ptr[u32],
    pVideoFormatProperties: ptr[VkVideoFormatPropertiesKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCreateVideoSessionKHR(
    device: VkDevice,
    pCreateInfo: ptr[VkVideoSessionCreateInfoKHR],
    pAllocator: ptr[VkAllocationCallbacks],
    pVideoSession: ptr[VkVideoSessionKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyVideoSessionKHR(
    device: VkDevice,
    videoSession: VkVideoSessionKHR,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkGetVideoSessionMemoryRequirementsKHR(
    device: VkDevice,
    videoSession: VkVideoSessionKHR,
    pMemoryRequirementsCount: ptr[u32],
    pMemoryRequirements: ptr[VkVideoSessionMemoryRequirementsKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkBindVideoSessionMemoryKHR(
    device: VkDevice,
    videoSession: VkVideoSessionKHR,
    bindSessionMemoryInfoCount: u32,
    pBindSessionMemoryInfos: ptr[VkBindVideoSessionMemoryInfoKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCreateVideoSessionParametersKHR(
    device: VkDevice,
    pCreateInfo: ptr[VkVideoSessionParametersCreateInfoKHR],
    pAllocator: ptr[VkAllocationCallbacks],
    pVideoSessionParameters: ptr[VkVideoSessionParametersKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkUpdateVideoSessionParametersKHR(
    device: VkDevice,
    videoSessionParameters: VkVideoSessionParametersKHR,
    pUpdateInfo: ptr[VkVideoSessionParametersUpdateInfoKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyVideoSessionParametersKHR(
    device: VkDevice,
    videoSessionParameters: VkVideoSessionParametersKHR,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkCmdBeginVideoCodingKHR(
    commandBuffer: VkCommandBuffer,
    pBeginInfo: ptr[VkVideoBeginCodingInfoKHR]) -> void
{
    //TODO(ches) do this
}

vkCmdEndVideoCodingKHR(
    commandBuffer: VkCommandBuffer,
    pEndCodingInfo: ptr[VkVideoEndCodingInfoKHR]) -> void
{
    //TODO(ches) do this
}

vkCmdControlVideoCodingKHR(
    commandBuffer: VkCommandBuffer,
    pCodingControlInfo: ptr[VkVideoCodingControlInfoKHR]) -> void
{
    //TODO(ches) do this
}

vkCmdDecodeVideoKHR(
    commandBuffer: VkCommandBuffer,
    pDecodeInfo: ptr[VkVideoDecodeInfoKHR]) -> void
{
    //TODO(ches) do this
}

vkCmdBeginRenderingKHR(
    commandBuffer: VkCommandBuffer,
    pRenderingInfo: ptr[VkRenderingInfo]) -> void
{
    //TODO(ches) do this
}

vkCmdEndRenderingKHR(
    commandBuffer: VkCommandBuffer) -> void
{
    //TODO(ches) do this
}

vkGetPhysicalDeviceFeatures2KHR(
    physicalDevice: VkPhysicalDevice,
    pFeatures: ptr[VkPhysicalDeviceFeatures2]) -> void
{
    //TODO(ches) do this
}

vkGetPhysicalDeviceProperties2KHR(
    physicalDevice: VkPhysicalDevice,
    pProperties: ptr[VkPhysicalDeviceProperties2]) -> void
{
    //TODO(ches) do this
}

vkGetPhysicalDeviceFormatProperties2KHR(
    physicalDevice: VkPhysicalDevice,
    format: VkFormat,
    pFormatProperties: ptr[VkFormatProperties2]) -> void
{
    //TODO(ches) do this
}

vkGetPhysicalDeviceImageFormatProperties2KHR(
    physicalDevice: VkPhysicalDevice,
    pImageFormatInfo: ptr[VkPhysicalDeviceImageFormatInfo2],
    pImageFormatProperties: ptr[VkImageFormatProperties2]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPhysicalDeviceQueueFamilyProperties2KHR(
    physicalDevice: VkPhysicalDevice,
    pQueueFamilyPropertyCount: ptr[u32],
    pQueueFamilyProperties: ptr[VkQueueFamilyProperties2]) -> void
{
    //TODO(ches) do this
}

vkGetPhysicalDeviceMemoryProperties2KHR(
    physicalDevice: VkPhysicalDevice,
    pMemoryProperties: ptr[VkPhysicalDeviceMemoryProperties2]) -> void
{
    //TODO(ches) do this
}

vkGetPhysicalDeviceSparseImageFormatProperties2KHR(
    physicalDevice: VkPhysicalDevice,
    pFormatInfo: ptr[VkPhysicalDeviceSparseImageFormatInfo2],
    pPropertyCount: ptr[u32],
    pProperties: ptr[VkSparseImageFormatProperties2]) -> void
{
    //TODO(ches) do this
}

vkGetDeviceGroupPeerMemoryFeaturesKHR(
    device: VkDevice,
    heapIndex: u32,
    localDeviceIndex: u32,
    remoteDeviceIndex: u32,
    pPeerMemoryFeatures: ptr[VkPeerMemoryFeatureFlags]) -> void
{
    //TODO(ches) do this
}

vkCmdSetDeviceMaskKHR(
    commandBuffer: VkCommandBuffer,
    deviceMask: u32) -> void
{
    //TODO(ches) do this
}

vkCmdDispatchBaseKHR(
    commandBuffer: VkCommandBuffer,
    baseGroupX: u32,
    baseGroupY: u32,
    baseGroupZ: u32,
    groupCountX: u32,
    groupCountY: u32,
    groupCountZ: u32) -> void
{
    //TODO(ches) do this
}

vkTrimCommandPoolKHR(
    device: VkDevice,
    commandPool: VkCommandPool,
    flags: VkCommandPoolTrimFlags) -> void
{
    //TODO(ches) do this
}

vkEnumeratePhysicalDeviceGroupsKHR(
    instance: VkInstance,
    pPhysicalDeviceGroupCount: ptr[u32],
    pPhysicalDeviceGroupProperties: ptr[VkPhysicalDeviceGroupProperties]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPhysicalDeviceExternalBufferPropertiesKHR(
    physicalDevice: VkPhysicalDevice,
    pExternalBufferInfo: ptr[VkPhysicalDeviceExternalBufferInfo],
    pExternalBufferProperties: ptr[VkExternalBufferProperties]) -> void
{
    //TODO(ches) do this
}

vkGetMemoryFdKHR(
    device: VkDevice,
    pGetFdInfo: ptr[VkMemoryGetFdInfoKHR],
    pFd: ptr[int]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetMemoryFdPropertiesKHR(
    device: VkDevice,
    handleType: VkExternalMemoryHandleTypeFlagBits,
    fd: int,
    pMemoryFdProperties: ptr[VkMemoryFdPropertiesKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPhysicalDeviceExternalSemaphorePropertiesKHR(
    physicalDevice: VkPhysicalDevice,
    pExternalSemaphoreInfo: ptr[VkPhysicalDeviceExternalSemaphoreInfo],
    pExternalSemaphoreProperties: ptr[VkExternalSemaphoreProperties]) -> void
{
    //TODO(ches) do this
}

vkImportSemaphoreFdKHR(
    device: VkDevice,
    pImportSemaphoreFdInfo: ptr[VkImportSemaphoreFdInfoKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetSemaphoreFdKHR(
    device: VkDevice,
    pGetFdInfo: ptr[VkSemaphoreGetFdInfoKHR],
    pFd: ptr[int]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCmdPushDescriptorSetKHR(
    commandBuffer: VkCommandBuffer,
    pipelineBindPoint: VkPipelineBindPoint,
    layout: VkPipelineLayout,
    set: u32,
    descriptorWriteCount: u32,
    pDescriptorWrites: ptr[VkWriteDescriptorSet]) -> void
{
    //TODO(ches) do this
}

vkCmdPushDescriptorSetWithTemplateKHR(
    commandBuffer: VkCommandBuffer,
    descriptorUpdateTemplate: VkDescriptorUpdateTemplate,
    layout: VkPipelineLayout,
    set: u32,
    pData: ptr[void]) -> void
{
    //TODO(ches) do this
}

vkCreateDescriptorUpdateTemplateKHR(
    device: VkDevice,
    pCreateInfo: ptr[VkDescriptorUpdateTemplateCreateInfo],
    pAllocator: ptr[VkAllocationCallbacks],
    pDescriptorUpdateTemplate: ptr[VkDescriptorUpdateTemplate]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyDescriptorUpdateTemplateKHR(
    device: VkDevice,
    descriptorUpdateTemplate: VkDescriptorUpdateTemplate,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkUpdateDescriptorSetWithTemplateKHR(
    device: VkDevice,
    descriptorSet: VkDescriptorSet,
    descriptorUpdateTemplate: VkDescriptorUpdateTemplate,
    pData: ptr[void]) -> void
{
    //TODO(ches) do this
}

vkCreateRenderPass2KHR(
    device: VkDevice,
    pCreateInfo: ptr[VkRenderPassCreateInfo2],
    pAllocator: ptr[VkAllocationCallbacks],
    pRenderPass: ptr[VkRenderPass]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCmdBeginRenderPass2KHR(
    commandBuffer: VkCommandBuffer,
    pRenderPassBegin: ptr[VkRenderPassBeginInfo],
    pSubpassBeginInfo: ptr[VkSubpassBeginInfo]) -> void
{
    //TODO(ches) do this
}

vkCmdNextSubpass2KHR(
    commandBuffer: VkCommandBuffer,
    pSubpassBeginInfo: ptr[VkSubpassBeginInfo],
    pSubpassEndInfo: ptr[VkSubpassEndInfo]) -> void
{
    //TODO(ches) do this
}

vkCmdEndRenderPass2KHR(
    commandBuffer: VkCommandBuffer,
    pSubpassEndInfo: ptr[VkSubpassEndInfo]) -> void
{
    //TODO(ches) do this
}

vkGetSwapchainStatusKHR(
    device: VkDevice,
    swapchain: VkSwapchainKHR) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPhysicalDeviceExternalFencePropertiesKHR(
    physicalDevice: VkPhysicalDevice,
    pExternalFenceInfo: ptr[VkPhysicalDeviceExternalFenceInfo],
    pExternalFenceProperties: ptr[VkExternalFenceProperties]) -> void
{
    //TODO(ches) do this
}

vkImportFenceFdKHR(
    device: VkDevice,
    pImportFenceFdInfo: ptr[VkImportFenceFdInfoKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetFenceFdKHR(
    device: VkDevice,
    pGetFdInfo: ptr[VkFenceGetFdInfoKHR],
    pFd: ptr[int]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkEnumeratePhysicalDeviceQueueFamilyPerformanceQueryCountersKHR(
    physicalDevice: VkPhysicalDevice,
    queueFamilyIndex: u32,
    pCounterCount: ptr[u32],
    pCounters: ptr[VkPerformanceCounterKHR],
    pCounterDescriptions: ptr[VkPerformanceCounterDescriptionKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPhysicalDeviceQueueFamilyPerformanceQueryPassesKHR(
    physicalDevice: VkPhysicalDevice,
    pPerformanceQueryCreateInfo: ptr[VkQueryPoolPerformanceCreateInfoKHR],
    pNumPasses: ptr[u32]) -> void
{
    //TODO(ches) do this
}

vkAcquireProfilingLockKHR(
    device: VkDevice,
    pInfo: ptr[VkAcquireProfilingLockInfoKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkReleaseProfilingLockKHR(
    device: VkDevice) -> void
{
    //TODO(ches) do this
}

vkGetPhysicalDeviceSurfaceCapabilities2KHR(
    physicalDevice: VkPhysicalDevice,
    pSurfaceInfo: ptr[VkPhysicalDeviceSurfaceInfo2KHR],
    pSurfaceCapabilities: ptr[VkSurfaceCapabilities2KHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPhysicalDeviceSurfaceFormats2KHR(
    physicalDevice: VkPhysicalDevice,
    pSurfaceInfo: ptr[VkPhysicalDeviceSurfaceInfo2KHR],
    pSurfaceFormatCount: ptr[u32],
    pSurfaceFormats: ptr[VkSurfaceFormat2KHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPhysicalDeviceDisplayProperties2KHR(
    physicalDevice: VkPhysicalDevice,
    pPropertyCount: ptr[u32],
    pProperties: ptr[VkDisplayProperties2KHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPhysicalDeviceDisplayPlaneProperties2KHR(
    physicalDevice: VkPhysicalDevice,
    pPropertyCount: ptr[u32],
    pProperties: ptr[VkDisplayPlaneProperties2KHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetDisplayModeProperties2KHR(
    physicalDevice: VkPhysicalDevice,
    display: VkDisplayKHR,
    pPropertyCount: ptr[u32],
    pProperties: ptr[VkDisplayModeProperties2KHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetDisplayPlaneCapabilities2KHR(
    physicalDevice: VkPhysicalDevice,
    pDisplayPlaneInfo: ptr[VkDisplayPlaneInfo2KHR],
    pCapabilities: ptr[VkDisplayPlaneCapabilities2KHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetImageMemoryRequirements2KHR(
    device: VkDevice,
    pInfo: ptr[VkImageMemoryRequirementsInfo2],
    pMemoryRequirements: ptr[VkMemoryRequirements2]) -> void
{
    //TODO(ches) do this
}

vkGetBufferMemoryRequirements2KHR(
    device: VkDevice,
    pInfo: ptr[VkBufferMemoryRequirementsInfo2],
    pMemoryRequirements: ptr[VkMemoryRequirements2]) -> void
{
    //TODO(ches) do this
}

vkGetImageSparseMemoryRequirements2KHR(
    device: VkDevice,
    pInfo: ptr[VkImageSparseMemoryRequirementsInfo2],
    pSparseMemoryRequirementCount: ptr[u32],
    pSparseMemoryRequirements: ptr[VkSparseImageMemoryRequirements2]) -> void
{
    //TODO(ches) do this
}

vkCreateSamplerYcbcrConversionKHR(
    device: VkDevice,
    pCreateInfo: ptr[VkSamplerYcbcrConversionCreateInfo],
    pAllocator: ptr[VkAllocationCallbacks],
    pYcbcrConversion: ptr[VkSamplerYcbcrConversion]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroySamplerYcbcrConversionKHR(
    device: VkDevice,
    ycbcrConversion: VkSamplerYcbcrConversion,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkBindBufferMemory2KHR(
    device: VkDevice,
    bindInfoCount: u32,
    pBindInfos: ptr[VkBindBufferMemoryInfo]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkBindImageMemory2KHR(
    device: VkDevice,
    bindInfoCount: u32,
    pBindInfos: ptr[VkBindImageMemoryInfo]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetDescriptorSetLayoutSupportKHR(
    device: VkDevice,
    pCreateInfo: ptr[VkDescriptorSetLayoutCreateInfo],
    pSupport: ptr[VkDescriptorSetLayoutSupport]) -> void
{
    //TODO(ches) do this
}

vkCmdDrawIndirectCountKHR(
    commandBuffer: VkCommandBuffer,
    buffer: VkBuffer,
    offset: VkDeviceSize,
    countBuffer: VkBuffer,
    countBufferOffset: VkDeviceSize,
    maxDrawCount: u32,
    stride: u32) -> void
{
    //TODO(ches) do this
}

vkCmdDrawIndexedIndirectCountKHR(
    commandBuffer: VkCommandBuffer,
    buffer: VkBuffer,
    offset: VkDeviceSize,
    countBuffer: VkBuffer,
    countBufferOffset: VkDeviceSize,
    maxDrawCount: u32,
    stride: u32) -> void
{
    //TODO(ches) do this
}

vkGetSemaphoreCounterValueKHR(
    device: VkDevice,
    semaphore: VkSemaphore,
    pValue: ptr[u64]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkWaitSemaphoresKHR(
    device: VkDevice,
    pWaitInfo: ptr[VkSemaphoreWaitInfo],
    timeout: u64) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkSignalSemaphoreKHR(
    device: VkDevice,
    pSignalInfo: ptr[VkSemaphoreSignalInfo]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPhysicalDeviceFragmentShadingRatesKHR(
    physicalDevice: VkPhysicalDevice,
    pFragmentShadingRateCount: ptr[u32],
    pFragmentShadingRates: ptr[VkPhysicalDeviceFragmentShadingRateKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCmdSetFragmentShadingRateKHR(
    commandBuffer: VkCommandBuffer,
    pFragmentSize: ptr[VkExtent2D],
    VkFragmentShadingRateCombinerOpKHR combinerOps[2]) -> void
{
    //TODO(ches) do this
}

vkCmdSetRenderingAttachmentLocationsKHR(
    commandBuffer: VkCommandBuffer,
    pLocationInfo: ptr[VkRenderingAttachmentLocationInfoKHR]) -> void
{
    //TODO(ches) do this
}

vkCmdSetRenderingInputAttachmentIndicesKHR(
    commandBuffer: VkCommandBuffer,
    pLocationInfo: ptr[VkRenderingInputAttachmentIndexInfoKHR]) -> void
{
    //TODO(ches) do this
}

vkWaitForPresentKHR(
    device: VkDevice,
    swapchain: VkSwapchainKHR,
    presentId: u64,
    timeout: u64) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetBufferDeviceAddressKHR(
    device: VkDevice,
    pInfo: ptr[VkBufferDeviceAddressInfo]) -> VkDeviceAddress
{
    //TODO(ches) do this
}

vkGetBufferOpaqueCaptureAddressKHR(
    device: VkDevice,
    pInfo: ptr[VkBufferDeviceAddressInfo]) -> u64
{
    //TODO(ches) do this
}

vkGetDeviceMemoryOpaqueCaptureAddressKHR(
    device: VkDevice,
    pInfo: ptr[VkDeviceMemoryOpaqueCaptureAddressInfo]) -> u64
{
    //TODO(ches) do this
}

vkCreateDeferredOperationKHR(
    device: VkDevice,
    pAllocator: ptr[VkAllocationCallbacks],
    pDeferredOperation: ptr[VkDeferredOperationKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyDeferredOperationKHR(
    device: VkDevice,
    operation: VkDeferredOperationKHR,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkGetDeferredOperationMaxConcurrencyKHR(
    device: VkDevice,
    operation: VkDeferredOperationKHR) -> u32
{
    //TODO(ches) do this
}

vkGetDeferredOperationResultKHR(
    device: VkDevice,
    operation: VkDeferredOperationKHR) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDeferredOperationJoinKHR(
    device: VkDevice,
    operation: VkDeferredOperationKHR) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPipelineExecutablePropertiesKHR(
    device: VkDevice,
    pPipelineInfo: ptr[VkPipelineInfoKHR],
    pExecutableCount: ptr[u32],
    pProperties: ptr[VkPipelineExecutablePropertiesKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPipelineExecutableStatisticsKHR(
    device: VkDevice,
    pExecutableInfo: ptr[VkPipelineExecutableInfoKHR],
    pStatisticCount: ptr[u32],
    pStatistics: ptr[VkPipelineExecutableStatisticKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPipelineExecutableInternalRepresentationsKHR(
    device: VkDevice,
    pExecutableInfo: ptr[VkPipelineExecutableInfoKHR],
    pInternalRepresentationCount: ptr[u32],
    pInternalRepresentations: ptr[VkPipelineExecutableInternalRepresentationKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkMapMemory2KHR(
    device: VkDevice,
    pMemoryMapInfo: ptr[VkMemoryMapInfoKHR],
    ptr[ptr[void]] ppData) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkUnmapMemory2KHR(
    device: VkDevice,
    pMemoryUnmapInfo: ptr[VkMemoryUnmapInfoKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPhysicalDeviceVideoEncodeQualityLevelPropertiesKHR(
    physicalDevice: VkPhysicalDevice,
    pQualityLevelInfo: ptr[VkPhysicalDeviceVideoEncodeQualityLevelInfoKHR],
    pQualityLevelProperties: ptr[VkVideoEncodeQualityLevelPropertiesKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetEncodedVideoSessionParametersKHR(
    device: VkDevice,
    pVideoSessionParametersInfo: ptr[VkVideoEncodeSessionParametersGetInfoKHR],
    pFeedbackInfo: ptr[VkVideoEncodeSessionParametersFeedbackInfoKHR],
    pDataSize: ptr[uint],
    pData: ptr[void]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCmdEncodeVideoKHR(
    commandBuffer: VkCommandBuffer,
    pEncodeInfo: ptr[VkVideoEncodeInfoKHR]) -> void
{
    //TODO(ches) do this
}

vkCmdSetEvent2KHR(
    commandBuffer: VkCommandBuffer,
    event: VkEvent,
    pDependencyInfo: ptr[VkDependencyInfo]) -> void
{
    //TODO(ches) do this
}

vkCmdResetEvent2KHR(
    commandBuffer: VkCommandBuffer,
    event: VkEvent,
    stageMask: VkPipelineStageFlags2) -> void
{
    //TODO(ches) do this
}

vkCmdWaitEvents2KHR(
    commandBuffer: VkCommandBuffer,
    eventCount: u32,
    pEvents: ptr[VkEvent],
    pDependencyInfos: ptr[VkDependencyInfo]) -> void
{
    //TODO(ches) do this
}

vkCmdPipelineBarrier2KHR(
    commandBuffer: VkCommandBuffer,
    pDependencyInfo: ptr[VkDependencyInfo]) -> void
{
    //TODO(ches) do this
}

vkCmdWriteTimestamp2KHR(
    commandBuffer: VkCommandBuffer,
    stage: VkPipelineStageFlags2,
    queryPool: VkQueryPool,
    query: u32) -> void
{
    //TODO(ches) do this
}

vkQueueSubmit2KHR(
    queue: VkQueue,
    submitCount: u32,
    pSubmits: ptr[VkSubmitInfo2],
    fence: VkFence) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCmdWriteBufferMarker2AMD(
    commandBuffer: VkCommandBuffer,
    stage: VkPipelineStageFlags2,
    dstBuffer: VkBuffer,
    dstOffset: VkDeviceSize,
    marker: u32) -> void
{
    //TODO(ches) do this
}

vkGetQueueCheckpointData2NV(
    queue: VkQueue,
    pCheckpointDataCount: ptr[u32],
    pCheckpointData: ptr[VkCheckpointData2NV]) -> void
{
    //TODO(ches) do this
}

vkCmdCopyBuffer2KHR(
    commandBuffer: VkCommandBuffer,
    pCopyBufferInfo: ptr[VkCopyBufferInfo2]) -> void
{
    //TODO(ches) do this
}

vkCmdCopyImage2KHR(
    commandBuffer: VkCommandBuffer,
    pCopyImageInfo: ptr[VkCopyImageInfo2]) -> void
{
    //TODO(ches) do this
}

vkCmdCopyBufferToImage2KHR(
    commandBuffer: VkCommandBuffer,
    pCopyBufferToImageInfo: ptr[VkCopyBufferToImageInfo2]) -> void
{
    //TODO(ches) do this
}

vkCmdCopyImageToBuffer2KHR(
    commandBuffer: VkCommandBuffer,
    pCopyImageToBufferInfo: ptr[VkCopyImageToBufferInfo2]) -> void
{
    //TODO(ches) do this
}

vkCmdBlitImage2KHR(
    commandBuffer: VkCommandBuffer,
    pBlitImageInfo: ptr[VkBlitImageInfo2]) -> void
{
    //TODO(ches) do this
}

vkCmdResolveImage2KHR(
    commandBuffer: VkCommandBuffer,
    pResolveImageInfo: ptr[VkResolveImageInfo2]) -> void
{
    //TODO(ches) do this
}

vkCmdTraceRaysIndirect2KHR(
    commandBuffer: VkCommandBuffer,
    indirectDeviceAddress: VkDeviceAddress) -> void
{
    //TODO(ches) do this
}

vkGetDeviceBufferMemoryRequirementsKHR(
    device: VkDevice,
    pInfo: ptr[VkDeviceBufferMemoryRequirements],
    pMemoryRequirements: ptr[VkMemoryRequirements2]) -> void
{
    //TODO(ches) do this
}

vkGetDeviceImageMemoryRequirementsKHR(
    device: VkDevice,
    pInfo: ptr[VkDeviceImageMemoryRequirements],
    pMemoryRequirements: ptr[VkMemoryRequirements2]) -> void
{
    //TODO(ches) do this
}

vkGetDeviceImageSparseMemoryRequirementsKHR(
    device: VkDevice,
    pInfo: ptr[VkDeviceImageMemoryRequirements],
    pSparseMemoryRequirementCount: ptr[u32],
    pSparseMemoryRequirements: ptr[VkSparseImageMemoryRequirements2]) -> void
{
    //TODO(ches) do this
}

vkCmdBindIndexBuffer2KHR(
    commandBuffer: VkCommandBuffer,
    buffer: VkBuffer,
    offset: VkDeviceSize,
    size: VkDeviceSize,
    indexType: VkIndexType) -> void
{
    //TODO(ches) do this
}

vkGetRenderingAreaGranularityKHR(
    device: VkDevice,
    pRenderingAreaInfo: ptr[VkRenderingAreaInfoKHR],
    pGranularity: ptr[VkExtent2D]) -> void
{
    //TODO(ches) do this
}

vkGetDeviceImageSubresourceLayoutKHR(
    device: VkDevice,
    pInfo: ptr[VkDeviceImageSubresourceInfoKHR],
    pLayout: ptr[VkSubresourceLayout2KHR]) -> void
{
    //TODO(ches) do this
}

vkGetImageSubresourceLayout2KHR(
    device: VkDevice,
    image: VkImage,
    pSubresource: ptr[VkImageSubresource2KHR],
    pLayout: ptr[VkSubresourceLayout2KHR]) -> void
{
    //TODO(ches) do this
}

vkGetPhysicalDeviceCooperativeMatrixPropertiesKHR(
    physicalDevice: VkPhysicalDevice,
    pPropertyCount: ptr[u32],
    pProperties: ptr[VkCooperativeMatrixPropertiesKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCmdSetLineStippleKHR(
    commandBuffer: VkCommandBuffer,
    lineStippleFactor: u32,
    lineStipplePattern: u16) -> void
{
    //TODO(ches) do this
}

vkGetPhysicalDeviceCalibrateableTimeDomainsKHR(
    physicalDevice: VkPhysicalDevice,
    pTimeDomainCount: ptr[u32],
    pTimeDomains: ptr[VkTimeDomainKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetCalibratedTimestampsKHR(
    device: VkDevice,
    timestampCount: u32,
    pTimestampInfos: ptr[VkCalibratedTimestampInfoKHR],
    pTimestamps: ptr[u64],
    pMaxDeviation: ptr[u64]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCmdBindDescriptorSets2KHR(
    commandBuffer: VkCommandBuffer,
    pBindDescriptorSetsInfo: ptr[VkBindDescriptorSetsInfoKHR]) -> void
{
    //TODO(ches) do this
}

vkCmdPushConstants2KHR(
    commandBuffer: VkCommandBuffer,
    pPushConstantsInfo: ptr[VkPushConstantsInfoKHR]) -> void
{
    //TODO(ches) do this
}

vkCmdPushDescriptorSet2KHR(
    commandBuffer: VkCommandBuffer,
    pPushDescriptorSetInfo: ptr[VkPushDescriptorSetInfoKHR]) -> void
{
    //TODO(ches) do this
}

vkCmdPushDescriptorSetWithTemplate2KHR(
    commandBuffer: VkCommandBuffer,
    pPushDescriptorSetWithTemplateInfo: ptr[VkPushDescriptorSetWithTemplateInfoKHR]) -> void
{
    //TODO(ches) do this
}

vkCmdSetDescriptorBufferOffsets2EXT(
    commandBuffer: VkCommandBuffer,
    pSetDescriptorBufferOffsetsInfo: ptr[VkSetDescriptorBufferOffsetsInfoEXT]) -> void
{
    //TODO(ches) do this
}

vkCmdBindDescriptorBufferEmbeddedSamplers2EXT(
    commandBuffer: VkCommandBuffer,
    pBindDescriptorBufferEmbeddedSamplersInfo: ptr[VkBindDescriptorBufferEmbeddedSamplersInfoEXT]) -> void
{
    //TODO(ches) do this
}

vkCreateDebugReportCallbackEXT(
    instance: VkInstance,
    pCreateInfo: ptr[VkDebugReportCallbackCreateInfoEXT],
    pAllocator: ptr[VkAllocationCallbacks],
    pCallback: ptr[VkDebugReportCallbackEXT]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyDebugReportCallbackEXT(
    instance: VkInstance,
    callback: VkDebugReportCallbackEXT,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkDebugReportMessageEXT(
    instance: VkInstance,
    flags: VkDebugReportFlagsEXT,
    objectType: VkDebugReportObjectTypeEXT,
    object: u64,
    location: uint,
    messageCode: i32,
    pLayerPrefix: ptr[char],
    pMessage: ptr[char]) -> void
{
    //TODO(ches) do this
}

vkDebugMarkerSetObjectTagEXT(
    device: VkDevice,
    pTagInfo: ptr[VkDebugMarkerObjectTagInfoEXT]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDebugMarkerSetObjectNameEXT(
    device: VkDevice,
    pNameInfo: ptr[VkDebugMarkerObjectNameInfoEXT]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCmdDebugMarkerBeginEXT(
    commandBuffer: VkCommandBuffer,
    pMarkerInfo: ptr[VkDebugMarkerMarkerInfoEXT]) -> void
{
    //TODO(ches) do this
}

vkCmdDebugMarkerEndEXT(
    commandBuffer: VkCommandBuffer) -> void
{
    //TODO(ches) do this
}

vkCmdDebugMarkerInsertEXT(
    commandBuffer: VkCommandBuffer,
    pMarkerInfo: ptr[VkDebugMarkerMarkerInfoEXT]) -> void
{
    //TODO(ches) do this
}

vkCmdBindTransformFeedbackBuffersEXT(
    commandBuffer: VkCommandBuffer,
    firstBinding: u32,
    bindingCount: u32,
    pBuffers: ptr[VkBuffer],
    pOffsets: ptr[VkDeviceSize],
    pSizes: ptr[VkDeviceSize]) -> void
{
    //TODO(ches) do this
}

vkCmdBeginTransformFeedbackEXT(
    commandBuffer: VkCommandBuffer,
    firstCounterBuffer: u32,
    counterBufferCount: u32,
    pCounterBuffers: ptr[VkBuffer],
    pCounterBufferOffsets: ptr[VkDeviceSize]) -> void
{
    //TODO(ches) do this
}

vkCmdEndTransformFeedbackEXT(
    commandBuffer: VkCommandBuffer,
    firstCounterBuffer: u32,
    counterBufferCount: u32,
    pCounterBuffers: ptr[VkBuffer],
    pCounterBufferOffsets: ptr[VkDeviceSize]) -> void
{
    //TODO(ches) do this
}

vkCmdBeginQueryIndexedEXT(
    commandBuffer: VkCommandBuffer,
    queryPool: VkQueryPool,
    query: u32,
    flags: VkQueryControlFlags,
    index: u32) -> void
{
    //TODO(ches) do this
}

vkCmdEndQueryIndexedEXT(
    commandBuffer: VkCommandBuffer,
    queryPool: VkQueryPool,
    query: u32,
    index: u32) -> void
{
    //TODO(ches) do this
}

vkCmdDrawIndirectByteCountEXT(
    commandBuffer: VkCommandBuffer,
    instanceCount: u32,
    firstInstance: u32,
    counterBuffer: VkBuffer,
    counterBufferOffset: VkDeviceSize,
    counterOffset: u32,
    vertexStride: u32) -> void
{
    //TODO(ches) do this
}

vkCreateCuModuleNVX(
    device: VkDevice,
    pCreateInfo: ptr[VkCuModuleCreateInfoNVX],
    pAllocator: ptr[VkAllocationCallbacks],
    pModule: ptr[VkCuModuleNVX]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCreateCuFunctionNVX(
    device: VkDevice,
    pCreateInfo: ptr[VkCuFunctionCreateInfoNVX],
    pAllocator: ptr[VkAllocationCallbacks],
    pFunction: ptr[VkCuFunctionNVX]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyCuModuleNVX(
    device: VkDevice,
    module: VkCuModuleNVX,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkDestroyCuFunctionNVX(
    device: VkDevice,
    function: VkCuFunctionNVX,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkCmdCuLaunchKernelNVX(
    commandBuffer: VkCommandBuffer,
    pLaunchInfo: ptr[VkCuLaunchInfoNVX]) -> void
{
    //TODO(ches) do this
}

vkGetImageViewHandleNVX(
    device: VkDevice,
    pInfo: ptr[VkImageViewHandleInfoNVX]) -> u32
{
    //TODO(ches) do this
}

vkGetImageViewAddressNVX(
    device: VkDevice,
    imageView: VkImageView,
    pProperties: ptr[VkImageViewAddressPropertiesNVX]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCmdDrawIndirectCountAMD(
    commandBuffer: VkCommandBuffer,
    buffer: VkBuffer,
    offset: VkDeviceSize,
    countBuffer: VkBuffer,
    countBufferOffset: VkDeviceSize,
    maxDrawCount: u32,
    stride: u32) -> void
{
    //TODO(ches) do this
}

vkCmdDrawIndexedIndirectCountAMD(
    commandBuffer: VkCommandBuffer,
    buffer: VkBuffer,
    offset: VkDeviceSize,
    countBuffer: VkBuffer,
    countBufferOffset: VkDeviceSize,
    maxDrawCount: u32,
    stride: u32) -> void
{
    //TODO(ches) do this
}

vkGetShaderInfoAMD(
    device: VkDevice,
    pipeline: VkPipeline,
    shaderStage: VkShaderStageFlagBits,
    infoType: VkShaderInfoTypeAMD,
    pInfoSize: ptr[uint],
    pInfo: ptr[void]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPhysicalDeviceExternalImageFormatPropertiesNV(
    physicalDevice: VkPhysicalDevice,
    format: VkFormat,
    type: VkImageType,
    tiling: VkImageTiling,
    usage: VkImageUsageFlags,
    flags: VkImageCreateFlags,
    externalHandleType: VkExternalMemoryHandleTypeFlagsNV,
    pExternalImageFormatProperties: ptr[VkExternalImageFormatPropertiesNV]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCmdBeginConditionalRenderingEXT(
    commandBuffer: VkCommandBuffer,
    pConditionalRenderingBegin: ptr[VkConditionalRenderingBeginInfoEXT]) -> void
{
    //TODO(ches) do this
}

vkCmdEndConditionalRenderingEXT(
    commandBuffer: VkCommandBuffer) -> void
{
    //TODO(ches) do this
}

vkCmdSetViewportWScalingNV(
    commandBuffer: VkCommandBuffer,
    firstViewport: u32,
    viewportCount: u32,
    pViewportWScalings: ptr[VkViewportWScalingNV]) -> void
{
    //TODO(ches) do this
}

vkReleaseDisplayEXT(
    physicalDevice: VkPhysicalDevice,
    display: VkDisplayKHR) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPhysicalDeviceSurfaceCapabilities2EXT(
    physicalDevice: VkPhysicalDevice,
    surface: VkSurfaceKHR,
    pSurfaceCapabilities: ptr[VkSurfaceCapabilities2EXT]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDisplayPowerControlEXT(
    device: VkDevice,
    display: VkDisplayKHR,
    pDisplayPowerInfo: ptr[VkDisplayPowerInfoEXT]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkRegisterDeviceEventEXT(
    device: VkDevice,
    pDeviceEventInfo: ptr[VkDeviceEventInfoEXT],
    pAllocator: ptr[VkAllocationCallbacks],
    pFence: ptr[VkFence]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkRegisterDisplayEventEXT(
    device: VkDevice,
    display: VkDisplayKHR,
    pDisplayEventInfo: ptr[VkDisplayEventInfoEXT],
    pAllocator: ptr[VkAllocationCallbacks],
    pFence: ptr[VkFence]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetSwapchainCounterEXT(
    device: VkDevice,
    swapchain: VkSwapchainKHR,
    counter: VkSurfaceCounterFlagBitsEXT,
    pCounterValue: ptr[u64]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetRefreshCycleDurationGOOGLE(
    device: VkDevice,
    swapchain: VkSwapchainKHR,
    pDisplayTimingProperties: ptr[VkRefreshCycleDurationGOOGLE]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPastPresentationTimingGOOGLE(
    device: VkDevice,
    swapchain: VkSwapchainKHR,
    pPresentationTimingCount: ptr[u32],
    pPresentationTimings: ptr[VkPastPresentationTimingGOOGLE]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCmdSetDiscardRectangleEXT(
    commandBuffer: VkCommandBuffer,
    firstDiscardRectangle: u32,
    discardRectangleCount: u32,
    pDiscardRectangles: ptr[VkRect2D]) -> void
{
    //TODO(ches) do this
}

vkCmdSetDiscardRectangleEnableEXT(
    commandBuffer: VkCommandBuffer,
    discardRectangleEnable: VkBool32) -> void
{
    //TODO(ches) do this
}

vkCmdSetDiscardRectangleModeEXT(
    commandBuffer: VkCommandBuffer,
    discardRectangleMode: VkDiscardRectangleModeEXT) -> void
{
    //TODO(ches) do this
}

vkSetHdrMetadataEXT(
    device: VkDevice,
    swapchainCount: u32,
    pSwapchains: ptr[VkSwapchainKHR],
    pMetadata: ptr[VkHdrMetadataEXT]) -> void
{
    //TODO(ches) do this
}

vkSetDebugUtilsObjectNameEXT(
    device: VkDevice,
    pNameInfo: ptr[VkDebugUtilsObjectNameInfoEXT]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkSetDebugUtilsObjectTagEXT(
    device: VkDevice,
    pTagInfo: ptr[VkDebugUtilsObjectTagInfoEXT]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkQueueBeginDebugUtilsLabelEXT(
    queue: VkQueue,
    pLabelInfo: ptr[VkDebugUtilsLabelEXT]) -> void
{
    //TODO(ches) do this
}

vkQueueEndDebugUtilsLabelEXT(
    queue: VkQueue) -> void
{
    //TODO(ches) do this
}

vkQueueInsertDebugUtilsLabelEXT(
    queue: VkQueue,
    pLabelInfo: ptr[VkDebugUtilsLabelEXT]) -> void
{
    //TODO(ches) do this
}

vkCmdBeginDebugUtilsLabelEXT(
    commandBuffer: VkCommandBuffer,
    pLabelInfo: ptr[VkDebugUtilsLabelEXT]) -> void
{
    //TODO(ches) do this
}

vkCmdEndDebugUtilsLabelEXT(
    commandBuffer: VkCommandBuffer) -> void
{
    //TODO(ches) do this
}

vkCmdInsertDebugUtilsLabelEXT(
    commandBuffer: VkCommandBuffer,
    pLabelInfo: ptr[VkDebugUtilsLabelEXT]) -> void
{
    //TODO(ches) do this
}

vkCreateDebugUtilsMessengerEXT(
    instance: VkInstance,
    pCreateInfo: ptr[VkDebugUtilsMessengerCreateInfoEXT],
    pAllocator: ptr[VkAllocationCallbacks],
    pMessenger: ptr[VkDebugUtilsMessengerEXT]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyDebugUtilsMessengerEXT(
    instance: VkInstance,
    messenger: VkDebugUtilsMessengerEXT,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkSubmitDebugUtilsMessageEXT(
    instance: VkInstance,
    messageSeverity: VkDebugUtilsMessageSeverityFlagBitsEXT,
    messageTypes: VkDebugUtilsMessageTypeFlagsEXT,
    pCallbackData: ptr[VkDebugUtilsMessengerCallbackDataEXT]) -> void
{
    //TODO(ches) do this
}

vkCmdSetSampleLocationsEXT(
    commandBuffer: VkCommandBuffer,
    pSampleLocationsInfo: ptr[VkSampleLocationsInfoEXT]) -> void
{
    //TODO(ches) do this
}

vkGetPhysicalDeviceMultisamplePropertiesEXT(
    physicalDevice: VkPhysicalDevice,
    samples: VkSampleCountFlagBits,
    pMultisampleProperties: ptr[VkMultisamplePropertiesEXT]) -> void
{
    //TODO(ches) do this
}

vkGetImageDrmFormatModifierPropertiesEXT(
    device: VkDevice,
    image: VkImage,
    pProperties: ptr[VkImageDrmFormatModifierPropertiesEXT]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCreateValidationCacheEXT(
    device: VkDevice,
    pCreateInfo: ptr[VkValidationCacheCreateInfoEXT],
    pAllocator: ptr[VkAllocationCallbacks],
    pValidationCache: ptr[VkValidationCacheEXT]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyValidationCacheEXT(
    device: VkDevice,
    validationCache: VkValidationCacheEXT,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkMergeValidationCachesEXT(
    device: VkDevice,
    dstCache: VkValidationCacheEXT,
    srcCacheCount: u32,
    pSrcCaches: ptr[VkValidationCacheEXT]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetValidationCacheDataEXT(
    device: VkDevice,
    validationCache: VkValidationCacheEXT,
    pDataSize: ptr[uint],
    pData: ptr[void]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCmdBindShadingRateImageNV(
    commandBuffer: VkCommandBuffer,
    imageView: VkImageView,
    imageLayout: VkImageLayout) -> void
{
    //TODO(ches) do this
}

vkCmdSetViewportShadingRatePaletteNV(
    commandBuffer: VkCommandBuffer,
    firstViewport: u32,
    viewportCount: u32,
    pShadingRatePalettes: ptr[VkShadingRatePaletteNV]) -> void
{
    //TODO(ches) do this
}

vkCmdSetCoarseSampleOrderNV(
    commandBuffer: VkCommandBuffer,
    sampleOrderType: VkCoarseSampleOrderTypeNV,
    customSampleOrderCount: u32,
    pCustomSampleOrders: ptr[VkCoarseSampleOrderCustomNV]) -> void
{
    //TODO(ches) do this
}

vkCreateAccelerationStructureNV(
    device: VkDevice,
    pCreateInfo: ptr[VkAccelerationStructureCreateInfoNV],
    pAllocator: ptr[VkAllocationCallbacks],
    pAccelerationStructure: ptr[VkAccelerationStructureNV]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyAccelerationStructureNV(
    device: VkDevice,
    accelerationStructure: VkAccelerationStructureNV,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkGetAccelerationStructureMemoryRequirementsNV(
    device: VkDevice,
    pInfo: ptr[VkAccelerationStructureMemoryRequirementsInfoNV],
    pMemoryRequirements: ptr[VkMemoryRequirements2KHR]) -> void
{
    //TODO(ches) do this
}

vkBindAccelerationStructureMemoryNV(
    device: VkDevice,
    bindInfoCount: u32,
    pBindInfos: ptr[VkBindAccelerationStructureMemoryInfoNV]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCmdBuildAccelerationStructureNV(
    commandBuffer: VkCommandBuffer,
    pInfo: ptr[VkAccelerationStructureInfoNV],
    instanceData: VkBuffer,
    instanceOffset: VkDeviceSize,
    update: VkBool32,
    dst: VkAccelerationStructureNV,
    src: VkAccelerationStructureNV,
    scratch: VkBuffer,
    scratchOffset: VkDeviceSize) -> void
{
    //TODO(ches) do this
}

vkCmdCopyAccelerationStructureNV(
    commandBuffer: VkCommandBuffer,
    dst: VkAccelerationStructureNV,
    src: VkAccelerationStructureNV,
    mode: VkCopyAccelerationStructureModeKHR) -> void
{
    //TODO(ches) do this
}

vkCmdTraceRaysNV(
    commandBuffer: VkCommandBuffer,
    raygenShaderBindingTableBuffer: VkBuffer,
    raygenShaderBindingOffset: VkDeviceSize,
    missShaderBindingTableBuffer: VkBuffer,
    missShaderBindingOffset: VkDeviceSize,
    missShaderBindingStride: VkDeviceSize,
    hitShaderBindingTableBuffer: VkBuffer,
    hitShaderBindingOffset: VkDeviceSize,
    hitShaderBindingStride: VkDeviceSize,
    callableShaderBindingTableBuffer: VkBuffer,
    callableShaderBindingOffset: VkDeviceSize,
    callableShaderBindingStride: VkDeviceSize,
    width: u32,
    height: u32,
    depth: u32) -> void
{
    //TODO(ches) do this
}

vkCreateRayTracingPipelinesNV(
    device: VkDevice,
    pipelineCache: VkPipelineCache,
    createInfoCount: u32,
    pCreateInfos: ptr[VkRayTracingPipelineCreateInfoNV],
    pAllocator: ptr[VkAllocationCallbacks],
    pPipelines: ptr[VkPipeline]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetRayTracingShaderGroupHandlesKHR(
    device: VkDevice,
    pipeline: VkPipeline,
    firstGroup: u32,
    groupCount: u32,
    dataSize: uint,
    pData: ptr[void]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetRayTracingShaderGroupHandlesNV(
    device: VkDevice,
    pipeline: VkPipeline,
    firstGroup: u32,
    groupCount: u32,
    dataSize: uint,
    pData: ptr[void]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetAccelerationStructureHandleNV(
    device: VkDevice,
    accelerationStructure: VkAccelerationStructureNV,
    dataSize: uint,
    pData: ptr[void]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCmdWriteAccelerationStructuresPropertiesNV(
    commandBuffer: VkCommandBuffer,
    accelerationStructureCount: u32,
    pAccelerationStructures: ptr[VkAccelerationStructureNV],
    queryType: VkQueryType,
    queryPool: VkQueryPool,
    firstQuery: u32) -> void
{
    //TODO(ches) do this
}

vkCompileDeferredNV(
    device: VkDevice,
    pipeline: VkPipeline,
    shader: u32) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetMemoryHostPointerPropertiesEXT(
    device: VkDevice,
    handleType: VkExternalMemoryHandleTypeFlagBits,
    pHostPointer: ptr[void],
    pMemoryHostPointerProperties: ptr[VkMemoryHostPointerPropertiesEXT]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCmdWriteBufferMarkerAMD(
    commandBuffer: VkCommandBuffer,
    pipelineStage: VkPipelineStageFlagBits,
    dstBuffer: VkBuffer,
    dstOffset: VkDeviceSize,
    marker: u32) -> void
{
    //TODO(ches) do this
}

vkGetPhysicalDeviceCalibrateableTimeDomainsEXT(
    physicalDevice: VkPhysicalDevice,
    pTimeDomainCount: ptr[u32],
    pTimeDomains: ptr[VkTimeDomainKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetCalibratedTimestampsEXT(
    device: VkDevice,
    timestampCount: u32,
    pTimestampInfos: ptr[VkCalibratedTimestampInfoKHR],
    pTimestamps: ptr[u64],
    pMaxDeviation: ptr[u64]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCmdDrawMeshTasksNV(
    commandBuffer: VkCommandBuffer,
    taskCount: u32,
    firstTask: u32) -> void
{
    //TODO(ches) do this
}

vkCmdDrawMeshTasksIndirectNV(
    commandBuffer: VkCommandBuffer,
    buffer: VkBuffer,
    offset: VkDeviceSize,
    drawCount: u32,
    stride: u32) -> void
{
    //TODO(ches) do this
}

vkCmdDrawMeshTasksIndirectCountNV(
    commandBuffer: VkCommandBuffer,
    buffer: VkBuffer,
    offset: VkDeviceSize,
    countBuffer: VkBuffer,
    countBufferOffset: VkDeviceSize,
    maxDrawCount: u32,
    stride: u32) -> void
{
    //TODO(ches) do this
}

vkCmdSetExclusiveScissorEnableNV(
    commandBuffer: VkCommandBuffer,
    firstExclusiveScissor: u32,
    exclusiveScissorCount: u32,
    pExclusiveScissorEnables: ptr[VkBool32]) -> void
{
    //TODO(ches) do this
}

vkCmdSetExclusiveScissorNV(
    commandBuffer: VkCommandBuffer,
    firstExclusiveScissor: u32,
    exclusiveScissorCount: u32,
    pExclusiveScissors: ptr[VkRect2D]) -> void
{
    //TODO(ches) do this
}

vkCmdSetCheckpointNV(
    commandBuffer: VkCommandBuffer,
    pCheckpointMarker: ptr[void]) -> void
{
    //TODO(ches) do this
}

vkGetQueueCheckpointDataNV(
    queue: VkQueue,
    pCheckpointDataCount: ptr[u32],
    pCheckpointData: ptr[VkCheckpointDataNV]) -> void
{
    //TODO(ches) do this
}

vkInitializePerformanceApiINTEL(
    device: VkDevice,
    pInitializeInfo: ptr[VkInitializePerformanceApiInfoINTEL]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkUninitializePerformanceApiINTEL(
    device: VkDevice) -> void
{
    //TODO(ches) do this
}

vkCmdSetPerformanceMarkerINTEL(
    commandBuffer: VkCommandBuffer,
    pMarkerInfo: ptr[VkPerformanceMarkerInfoINTEL]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCmdSetPerformanceStreamMarkerINTEL(
    commandBuffer: VkCommandBuffer,
    pMarkerInfo: ptr[VkPerformanceStreamMarkerInfoINTEL]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCmdSetPerformanceOverrideINTEL(
    commandBuffer: VkCommandBuffer,
    pOverrideInfo: ptr[VkPerformanceOverrideInfoINTEL]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkAcquirePerformanceConfigurationINTEL(
    device: VkDevice,
    pAcquireInfo: ptr[VkPerformanceConfigurationAcquireInfoINTEL],
    pConfiguration: ptr[VkPerformanceConfigurationINTEL]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkReleasePerformanceConfigurationINTEL(
    device: VkDevice,
    configuration: VkPerformanceConfigurationINTEL) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkQueueSetPerformanceConfigurationINTEL(
    queue: VkQueue,
    configuration: VkPerformanceConfigurationINTEL) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPerformanceParameterINTEL(
    device: VkDevice,
    parameter: VkPerformanceParameterTypeINTEL,
    pValue: ptr[VkPerformanceValueINTEL]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkSetLocalDimmingAMD(
    device: VkDevice,
    swapChain: VkSwapchainKHR,
    localDimmingEnable: VkBool32) -> void
{
    //TODO(ches) do this
}

vkGetBufferDeviceAddressEXT(
    device: VkDevice,
    pInfo: ptr[VkBufferDeviceAddressInfo]) -> VkDeviceAddress
{
    //TODO(ches) do this
}

vkGetPhysicalDeviceToolPropertiesEXT(
    physicalDevice: VkPhysicalDevice,
    pToolCount: ptr[u32],
    pToolProperties: ptr[VkPhysicalDeviceToolProperties]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPhysicalDeviceCooperativeMatrixPropertiesNV(
    physicalDevice: VkPhysicalDevice,
    pPropertyCount: ptr[u32],
    pProperties: ptr[VkCooperativeMatrixPropertiesNV]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPhysicalDeviceSupportedFramebufferMixedSamplesCombinationsNV(
    physicalDevice: VkPhysicalDevice,
    pCombinationCount: ptr[u32],
    pCombinations: ptr[VkFramebufferMixedSamplesCombinationNV]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCreateHeadlessSurfaceEXT(
    instance: VkInstance,
    pCreateInfo: ptr[VkHeadlessSurfaceCreateInfoEXT],
    pAllocator: ptr[VkAllocationCallbacks],
    pSurface: ptr[VkSurfaceKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCmdSetLineStippleEXT(
    commandBuffer: VkCommandBuffer,
    lineStippleFactor: u32,
    lineStipplePattern: u16) -> void
{
    //TODO(ches) do this
}

vkResetQueryPoolEXT(
    device: VkDevice,
    queryPool: VkQueryPool,
    firstQuery: u32,
    queryCount: u32) -> void
{
    //TODO(ches) do this
}

vkCmdSetCullModeEXT(
    commandBuffer: VkCommandBuffer,
    cullMode: VkCullModeFlags) -> void
{
    //TODO(ches) do this
}

vkCmdSetFrontFaceEXT(
    commandBuffer: VkCommandBuffer,
    frontFace: VkFrontFace) -> void
{
    //TODO(ches) do this
}

vkCmdSetPrimitiveTopologyEXT(
    commandBuffer: VkCommandBuffer,
    primitiveTopology: VkPrimitiveTopology) -> void
{
    //TODO(ches) do this
}

vkCmdSetViewportWithCountEXT(
    commandBuffer: VkCommandBuffer,
    viewportCount: u32,
    pViewports: ptr[VkViewport]) -> void
{
    //TODO(ches) do this
}

vkCmdSetScissorWithCountEXT(
    commandBuffer: VkCommandBuffer,
    scissorCount: u32,
    pScissors: ptr[VkRect2D]) -> void
{
    //TODO(ches) do this
}

vkCmdBindVertexBuffers2EXT(
    commandBuffer: VkCommandBuffer,
    firstBinding: u32,
    bindingCount: u32,
    pBuffers: ptr[VkBuffer],
    pOffsets: ptr[VkDeviceSize],
    pSizes: ptr[VkDeviceSize],
    pStrides: ptr[VkDeviceSize]) -> void
{
    //TODO(ches) do this
}

vkCmdSetDepthTestEnableEXT(
    commandBuffer: VkCommandBuffer,
    depthTestEnable: VkBool32) -> void
{
    //TODO(ches) do this
}

vkCmdSetDepthWriteEnableEXT(
    commandBuffer: VkCommandBuffer,
    depthWriteEnable: VkBool32) -> void
{
    //TODO(ches) do this
}

vkCmdSetDepthCompareOpEXT(
    commandBuffer: VkCommandBuffer,
    depthCompareOp: VkCompareOp) -> void
{
    //TODO(ches) do this
}

vkCmdSetDepthBoundsTestEnableEXT(
    commandBuffer: VkCommandBuffer,
    depthBoundsTestEnable: VkBool32) -> void
{
    //TODO(ches) do this
}

vkCmdSetStencilTestEnableEXT(
    commandBuffer: VkCommandBuffer,
    stencilTestEnable: VkBool32) -> void
{
    //TODO(ches) do this
}

vkCmdSetStencilOpEXT(
    commandBuffer: VkCommandBuffer,
    faceMask: VkStencilFaceFlags,
    failOp: VkStencilOp,
    passOp: VkStencilOp,
    depthFailOp: VkStencilOp,
    compareOp: VkCompareOp) -> void
{
    //TODO(ches) do this
}

vkCopyMemoryToImageEXT(
    device: VkDevice,
    pCopyMemoryToImageInfo: ptr[VkCopyMemoryToImageInfoEXT]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCopyImageToMemoryEXT(
    device: VkDevice,
    pCopyImageToMemoryInfo: ptr[VkCopyImageToMemoryInfoEXT]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCopyImageToImageEXT(
    device: VkDevice,
    pCopyImageToImageInfo: ptr[VkCopyImageToImageInfoEXT]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkTransitionImageLayoutEXT(
    device: VkDevice,
    transitionCount: u32,
    pTransitions: ptr[VkHostImageLayoutTransitionInfoEXT]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetImageSubresourceLayout2EXT(
    device: VkDevice,
    image: VkImage,
    pSubresource: ptr[VkImageSubresource2KHR],
    pLayout: ptr[VkSubresourceLayout2KHR]) -> void
{
    //TODO(ches) do this
}

vkReleaseSwapchainImagesEXT(
    device: VkDevice,
    pReleaseInfo: ptr[VkReleaseSwapchainImagesInfoEXT]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetGeneratedCommandsMemoryRequirementsNV(
    device: VkDevice,
    pInfo: ptr[VkGeneratedCommandsMemoryRequirementsInfoNV],
    pMemoryRequirements: ptr[VkMemoryRequirements2]) -> void
{
    //TODO(ches) do this
}

vkCmdPreprocessGeneratedCommandsNV(
    commandBuffer: VkCommandBuffer,
    pGeneratedCommandsInfo: ptr[VkGeneratedCommandsInfoNV]) -> void
{
    //TODO(ches) do this
}

vkCmdExecuteGeneratedCommandsNV(
    commandBuffer: VkCommandBuffer,
    isPreprocessed: VkBool32,
    pGeneratedCommandsInfo: ptr[VkGeneratedCommandsInfoNV]) -> void
{
    //TODO(ches) do this
}

vkCmdBindPipelineShaderGroupNV(
    commandBuffer: VkCommandBuffer,
    pipelineBindPoint: VkPipelineBindPoint,
    pipeline: VkPipeline,
    groupIndex: u32) -> void
{
    //TODO(ches) do this
}

vkCreateIndirectCommandsLayoutNV(
    device: VkDevice,
    pCreateInfo: ptr[VkIndirectCommandsLayoutCreateInfoNV],
    pAllocator: ptr[VkAllocationCallbacks],
    pIndirectCommandsLayout: ptr[VkIndirectCommandsLayoutNV]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyIndirectCommandsLayoutNV(
    device: VkDevice,
    indirectCommandsLayout: VkIndirectCommandsLayoutNV,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkCmdSetDepthBias2EXT(
    commandBuffer: VkCommandBuffer,
    pDepthBiasInfo: ptr[VkDepthBiasInfoEXT]) -> void
{
    //TODO(ches) do this
}

vkAcquireDrmDisplayEXT(
    physicalDevice: VkPhysicalDevice,
    drmFd: i32,
    display: VkDisplayKHR) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetDrmDisplayEXT(
    physicalDevice: VkPhysicalDevice,
    drmFd: i32,
    connectorId: u32,
    display: ptr[VkDisplayKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCreatePrivateDataSlotEXT(
    device: VkDevice,
    pCreateInfo: ptr[VkPrivateDataSlotCreateInfo],
    pAllocator: ptr[VkAllocationCallbacks],
    pPrivateDataSlot: ptr[VkPrivateDataSlot]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyPrivateDataSlotEXT(
    device: VkDevice,
    privateDataSlot: VkPrivateDataSlot,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkSetPrivateDataEXT(
    device: VkDevice,
    objectType: VkObjectType,
    objectHandle: u64,
    privateDataSlot: VkPrivateDataSlot,
    data: u64) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPrivateDataEXT(
    device: VkDevice,
    objectType: VkObjectType,
    objectHandle: u64,
    privateDataSlot: VkPrivateDataSlot,
    pData: ptr[u64]) -> void
{
    //TODO(ches) do this
}

vkCreateCudaModuleNV(
    device: VkDevice,
    pCreateInfo: ptr[VkCudaModuleCreateInfoNV],
    pAllocator: ptr[VkAllocationCallbacks],
    pModule: ptr[VkCudaModuleNV]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetCudaModuleCacheNV(
    device: VkDevice,
    module: VkCudaModuleNV,
    pCacheSize: ptr[uint],
    pCacheData: ptr[void]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCreateCudaFunctionNV(
    device: VkDevice,
    pCreateInfo: ptr[VkCudaFunctionCreateInfoNV],
    pAllocator: ptr[VkAllocationCallbacks],
    pFunction: ptr[VkCudaFunctionNV]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyCudaModuleNV(
    device: VkDevice,
    module: VkCudaModuleNV,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkDestroyCudaFunctionNV(
    device: VkDevice,
    function: VkCudaFunctionNV,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkCmdCudaLaunchKernelNV(
    commandBuffer: VkCommandBuffer,
    pLaunchInfo: ptr[VkCudaLaunchInfoNV]) -> void
{
    //TODO(ches) do this
}

vkGetDescriptorSetLayoutSizeEXT(
    device: VkDevice,
    layout: VkDescriptorSetLayout,
    pLayoutSizeInBytes: ptr[VkDeviceSize]) -> void
{
    //TODO(ches) do this
}

vkGetDescriptorSetLayoutBindingOffsetEXT(
    device: VkDevice,
    layout: VkDescriptorSetLayout,
    binding: u32,
    pOffset: ptr[VkDeviceSize]) -> void
{
    //TODO(ches) do this
}

vkGetDescriptorEXT(
    device: VkDevice,
    pDescriptorInfo: ptr[VkDescriptorGetInfoEXT],
    dataSize: uint,
    pDescriptor: ptr[void]) -> void
{
    //TODO(ches) do this
}

vkCmdBindDescriptorBuffersEXT(
    commandBuffer: VkCommandBuffer,
    bufferCount: u32,
    pBindingInfos: ptr[VkDescriptorBufferBindingInfoEXT]) -> void
{
    //TODO(ches) do this
}

vkCmdSetDescriptorBufferOffsetsEXT(
    commandBuffer: VkCommandBuffer,
    pipelineBindPoint: VkPipelineBindPoint,
    layout: VkPipelineLayout,
    firstSet: u32,
    setCount: u32,
    pBufferIndices: ptr[u32],
    pOffsets: ptr[VkDeviceSize]) -> void
{
    //TODO(ches) do this
}

vkCmdBindDescriptorBufferEmbeddedSamplersEXT(
    commandBuffer: VkCommandBuffer,
    pipelineBindPoint: VkPipelineBindPoint,
    layout: VkPipelineLayout,
    set: u32) -> void
{
    //TODO(ches) do this
}

vkGetBufferOpaqueCaptureDescriptorDataEXT(
    device: VkDevice,
    pInfo: ptr[VkBufferCaptureDescriptorDataInfoEXT],
    pData: ptr[void]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetImageOpaqueCaptureDescriptorDataEXT(
    device: VkDevice,
    pInfo: ptr[VkImageCaptureDescriptorDataInfoEXT],
    pData: ptr[void]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetImageViewOpaqueCaptureDescriptorDataEXT(
    device: VkDevice,
    pInfo: ptr[VkImageViewCaptureDescriptorDataInfoEXT],
    pData: ptr[void]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetSamplerOpaqueCaptureDescriptorDataEXT(
    device: VkDevice,
    pInfo: ptr[VkSamplerCaptureDescriptorDataInfoEXT],
    pData: ptr[void]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetAccelerationStructureOpaqueCaptureDescriptorDataEXT(
    device: VkDevice,
    pInfo: ptr[VkAccelerationStructureCaptureDescriptorDataInfoEXT],
    pData: ptr[void]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCmdSetFragmentShadingRateEnumNV(
    commandBuffer: VkCommandBuffer,
    shadingRate: VkFragmentShadingRateNV,
    VkFragmentShadingRateCombinerOpKHR combinerOps[2]) -> void
{
    //TODO(ches) do this
}

vkGetDeviceFaultInfoEXT(
    device: VkDevice,
    pFaultCounts: ptr[VkDeviceFaultCountsEXT],
    pFaultInfo: ptr[VkDeviceFaultInfoEXT]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCmdSetVertexInputEXT(
    commandBuffer: VkCommandBuffer,
    vertexBindingDescriptionCount: u32,
    pVertexBindingDescriptions: ptr[VkVertexInputBindingDescription2EXT],
    vertexAttributeDescriptionCount: u32,
    pVertexAttributeDescriptions: ptr[VkVertexInputAttributeDescription2EXT]) -> void
{
    //TODO(ches) do this
}

vkGetDeviceSubpassShadingMaxWorkgroupSizeHUAWEI(
    device: VkDevice,
    renderpass: VkRenderPass,
    pMaxWorkgroupSize: ptr[VkExtent2D]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCmdSubpassShadingHUAWEI(
    commandBuffer: VkCommandBuffer) -> void
{
    //TODO(ches) do this
}

vkCmdBindInvocationMaskHUAWEI(
    commandBuffer: VkCommandBuffer,
    imageView: VkImageView,
    imageLayout: VkImageLayout) -> void
{
    //TODO(ches) do this
}

vkGetMemoryRemoteAddressNV(
    device: VkDevice,
    pMemoryGetRemoteAddressInfo: ptr[VkMemoryGetRemoteAddressInfoNV],
    pAddress: ptr[VkRemoteAddressNV]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetPipelinePropertiesEXT(
    device: VkDevice,
    pPipelineInfo: ptr[VkPipelineInfoEXT],
    pPipelineProperties: ptr[VkBaseOutStructure]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCmdSetPatchControlPointsEXT(
    commandBuffer: VkCommandBuffer,
    patchControlPoints: u32) -> void
{
    //TODO(ches) do this
}

vkCmdSetRasterizerDiscardEnableEXT(
    commandBuffer: VkCommandBuffer,
    rasterizerDiscardEnable: VkBool32) -> void
{
    //TODO(ches) do this
}

vkCmdSetDepthBiasEnableEXT(
    commandBuffer: VkCommandBuffer,
    depthBiasEnable: VkBool32) -> void
{
    //TODO(ches) do this
}

vkCmdSetLogicOpEXT(
    commandBuffer: VkCommandBuffer,
    logicOp: VkLogicOp) -> void
{
    //TODO(ches) do this
}

vkCmdSetPrimitiveRestartEnableEXT(
    commandBuffer: VkCommandBuffer,
    primitiveRestartEnable: VkBool32) -> void
{
    //TODO(ches) do this
}

vkCmdSetColorWriteEnableEXT(
    commandBuffer: VkCommandBuffer,
    attachmentCount: u32,
    pColorWriteEnables: ptr[VkBool32]) -> void
{
    //TODO(ches) do this
}

vkCmdDrawMultiEXT(
    commandBuffer: VkCommandBuffer,
    drawCount: u32,
    pVertexInfo: ptr[VkMultiDrawInfoEXT],
    instanceCount: u32,
    firstInstance: u32,
    stride: u32) -> void
{
    //TODO(ches) do this
}

vkCmdDrawMultiIndexedEXT(
    commandBuffer: VkCommandBuffer,
    drawCount: u32,
    pIndexInfo: ptr[VkMultiDrawIndexedInfoEXT],
    instanceCount: u32,
    firstInstance: u32,
    stride: u32,
    pVertexOffset: ptr[i32]) -> void
{
    //TODO(ches) do this
}

vkCreateMicromapEXT(
    device: VkDevice,
    pCreateInfo: ptr[VkMicromapCreateInfoEXT],
    pAllocator: ptr[VkAllocationCallbacks],
    pMicromap: ptr[VkMicromapEXT]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyMicromapEXT(
    device: VkDevice,
    micromap: VkMicromapEXT,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkCmdBuildMicromapsEXT(
    commandBuffer: VkCommandBuffer,
    infoCount: u32,
    pInfos: ptr[VkMicromapBuildInfoEXT]) -> void
{
    //TODO(ches) do this
}

vkBuildMicromapsEXT(
    device: VkDevice,
    deferredOperation: VkDeferredOperationKHR,
    infoCount: u32,
    pInfos: ptr[VkMicromapBuildInfoEXT]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCopyMicromapEXT(
    device: VkDevice,
    deferredOperation: VkDeferredOperationKHR,
    pInfo: ptr[VkCopyMicromapInfoEXT]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCopyMicromapToMemoryEXT(
    device: VkDevice,
    deferredOperation: VkDeferredOperationKHR,
    pInfo: ptr[VkCopyMicromapToMemoryInfoEXT]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCopyMemoryToMicromapEXT(
    device: VkDevice,
    deferredOperation: VkDeferredOperationKHR,
    pInfo: ptr[VkCopyMemoryToMicromapInfoEXT]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkWriteMicromapsPropertiesEXT(
    device: VkDevice,
    micromapCount: u32,
    pMicromaps: ptr[VkMicromapEXT],
    queryType: VkQueryType,
    dataSize: uint,
    pData: ptr[void],
    stride: uint) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCmdCopyMicromapEXT(
    commandBuffer: VkCommandBuffer,
    pInfo: ptr[VkCopyMicromapInfoEXT]) -> void
{
    //TODO(ches) do this
}

vkCmdCopyMicromapToMemoryEXT(
    commandBuffer: VkCommandBuffer,
    pInfo: ptr[VkCopyMicromapToMemoryInfoEXT]) -> void
{
    //TODO(ches) do this
}

vkCmdCopyMemoryToMicromapEXT(
    commandBuffer: VkCommandBuffer,
    pInfo: ptr[VkCopyMemoryToMicromapInfoEXT]) -> void
{
    //TODO(ches) do this
}

vkCmdWriteMicromapsPropertiesEXT(
    commandBuffer: VkCommandBuffer,
    micromapCount: u32,
    pMicromaps: ptr[VkMicromapEXT],
    queryType: VkQueryType,
    queryPool: VkQueryPool,
    firstQuery: u32) -> void
{
    //TODO(ches) do this
}

vkGetDeviceMicromapCompatibilityEXT(
    device: VkDevice,
    pVersionInfo: ptr[VkMicromapVersionInfoEXT],
    pCompatibility: ptr[VkAccelerationStructureCompatibilityKHR]) -> void
{
    //TODO(ches) do this
}

vkGetMicromapBuildSizesEXT(
    device: VkDevice,
    buildType: VkAccelerationStructureBuildTypeKHR,
    pBuildInfo: ptr[VkMicromapBuildInfoEXT],
    pSizeInfo: ptr[VkMicromapBuildSizesInfoEXT]) -> void
{
    //TODO(ches) do this
}

vkCmdDrawClusterHUAWEI(
    commandBuffer: VkCommandBuffer,
    groupCountX: u32,
    groupCountY: u32,
    groupCountZ: u32) -> void
{
    //TODO(ches) do this
}

vkCmdDrawClusterIndirectHUAWEI(
    commandBuffer: VkCommandBuffer,
    buffer: VkBuffer,
    offset: VkDeviceSize) -> void
{
    //TODO(ches) do this
}

vkSetDeviceMemoryPriorityEXT(
    device: VkDevice,
    memory: VkDeviceMemory,
    priority: float) -> void
{
    //TODO(ches) do this
}

vkGetDescriptorSetLayoutHostMappingInfoVALVE(
    device: VkDevice,
    pBindingReference: ptr[VkDescriptorSetBindingReferenceVALVE],
    pHostMapping: ptr[VkDescriptorSetLayoutHostMappingInfoVALVE]) -> void
{
    //TODO(ches) do this
}

vkGetDescriptorSetHostMappingVALVE(
    device: VkDevice,
    descriptorSet: VkDescriptorSet,
    ptr[ptr[void]] ppData) -> void
{
    //TODO(ches) do this
}

vkCmdCopyMemoryIndirectNV(
    commandBuffer: VkCommandBuffer,
    copyBufferAddress: VkDeviceAddress,
    copyCount: u32,
    stride: u32) -> void
{
    //TODO(ches) do this
}

vkCmdCopyMemoryToImageIndirectNV(
    commandBuffer: VkCommandBuffer,
    copyBufferAddress: VkDeviceAddress,
    copyCount: u32,
    stride: u32,
    dstImage: VkImage,
    dstImageLayout: VkImageLayout,
    pImageSubresources: ptr[VkImageSubresourceLayers]) -> void
{
    //TODO(ches) do this
}

vkCmdDecompressMemoryNV(
    commandBuffer: VkCommandBuffer,
    decompressRegionCount: u32,
    pDecompressMemoryRegions: ptr[VkDecompressMemoryRegionNV]) -> void
{
    //TODO(ches) do this
}

vkCmdDecompressMemoryIndirectCountNV(
    commandBuffer: VkCommandBuffer,
    indirectCommandsAddress: VkDeviceAddress,
    indirectCommandsCountAddress: VkDeviceAddress,
    stride: u32) -> void
{
    //TODO(ches) do this
}

vkGetPipelineIndirectMemoryRequirementsNV(
    device: VkDevice,
    pCreateInfo: ptr[VkComputePipelineCreateInfo],
    pMemoryRequirements: ptr[VkMemoryRequirements2]) -> void
{
    //TODO(ches) do this
}

vkCmdUpdatePipelineIndirectBufferNV(
    commandBuffer: VkCommandBuffer,
    pipelineBindPoint: VkPipelineBindPoint,
    pipeline: VkPipeline) -> void
{
    //TODO(ches) do this
}

vkGetPipelineIndirectDeviceAddressNV(
    device: VkDevice,
    pInfo: ptr[VkPipelineIndirectDeviceAddressInfoNV]) -> VkDeviceAddress
{
    //TODO(ches) do this
}

vkCmdSetDepthClampEnableEXT(
    commandBuffer: VkCommandBuffer,
    depthClampEnable: VkBool32) -> void
{
    //TODO(ches) do this
}

vkCmdSetPolygonModeEXT(
    commandBuffer: VkCommandBuffer,
    polygonMode: VkPolygonMode) -> void
{
    //TODO(ches) do this
}

vkCmdSetRasterizationSamplesEXT(
    commandBuffer: VkCommandBuffer,
    rasterizationSamples: VkSampleCountFlagBits) -> void
{
    //TODO(ches) do this
}

vkCmdSetSampleMaskEXT(
    commandBuffer: VkCommandBuffer,
    samples: VkSampleCountFlagBits,
    pSampleMask: ptr[VkSampleMask]) -> void
{
    //TODO(ches) do this
}

vkCmdSetAlphaToCoverageEnableEXT(
    commandBuffer: VkCommandBuffer,
    alphaToCoverageEnable: VkBool32) -> void
{
    //TODO(ches) do this
}

vkCmdSetAlphaToOneEnableEXT(
    commandBuffer: VkCommandBuffer,
    alphaToOneEnable: VkBool32) -> void
{
    //TODO(ches) do this
}

vkCmdSetLogicOpEnableEXT(
    commandBuffer: VkCommandBuffer,
    logicOpEnable: VkBool32) -> void
{
    //TODO(ches) do this
}

vkCmdSetColorBlendEnableEXT(
    commandBuffer: VkCommandBuffer,
    firstAttachment: u32,
    attachmentCount: u32,
    pColorBlendEnables: ptr[VkBool32]) -> void
{
    //TODO(ches) do this
}

vkCmdSetColorBlendEquationEXT(
    commandBuffer: VkCommandBuffer,
    firstAttachment: u32,
    attachmentCount: u32,
    pColorBlendEquations: ptr[VkColorBlendEquationEXT]) -> void
{
    //TODO(ches) do this
}

vkCmdSetColorWriteMaskEXT(
    commandBuffer: VkCommandBuffer,
    firstAttachment: u32,
    attachmentCount: u32,
    pColorWriteMasks: ptr[VkColorComponentFlags]) -> void
{
    //TODO(ches) do this
}

vkCmdSetTessellationDomainOriginEXT(
    commandBuffer: VkCommandBuffer,
    domainOrigin: VkTessellationDomainOrigin) -> void
{
    //TODO(ches) do this
}

vkCmdSetRasterizationStreamEXT(
    commandBuffer: VkCommandBuffer,
    rasterizationStream: u32) -> void
{
    //TODO(ches) do this
}

vkCmdSetConservativeRasterizationModeEXT(
    commandBuffer: VkCommandBuffer,
    conservativeRasterizationMode: VkConservativeRasterizationModeEXT) -> void
{
    //TODO(ches) do this
}

vkCmdSetExtraPrimitiveOverestimationSizeEXT(
    commandBuffer: VkCommandBuffer,
    extraPrimitiveOverestimationSize: float) -> void
{
    //TODO(ches) do this
}

vkCmdSetDepthClipEnableEXT(
    commandBuffer: VkCommandBuffer,
    depthClipEnable: VkBool32) -> void
{
    //TODO(ches) do this
}

vkCmdSetSampleLocationsEnableEXT(
    commandBuffer: VkCommandBuffer,
    sampleLocationsEnable: VkBool32) -> void
{
    //TODO(ches) do this
}

vkCmdSetColorBlendAdvancedEXT(
    commandBuffer: VkCommandBuffer,
    firstAttachment: u32,
    attachmentCount: u32,
    pColorBlendAdvanced: ptr[VkColorBlendAdvancedEXT]) -> void
{
    //TODO(ches) do this
}

vkCmdSetProvokingVertexModeEXT(
    commandBuffer: VkCommandBuffer,
    provokingVertexMode: VkProvokingVertexModeEXT) -> void
{
    //TODO(ches) do this
}

vkCmdSetLineRasterizationModeEXT(
    commandBuffer: VkCommandBuffer,
    lineRasterizationMode: VkLineRasterizationModeEXT) -> void
{
    //TODO(ches) do this
}

vkCmdSetLineStippleEnableEXT(
    commandBuffer: VkCommandBuffer,
    stippledLineEnable: VkBool32) -> void
{
    //TODO(ches) do this
}

vkCmdSetDepthClipNegativeOneToOneEXT(
    commandBuffer: VkCommandBuffer,
    negativeOneToOne: VkBool32) -> void
{
    //TODO(ches) do this
}

vkCmdSetViewportWScalingEnableNV(
    commandBuffer: VkCommandBuffer,
    viewportWScalingEnable: VkBool32) -> void
{
    //TODO(ches) do this
}

vkCmdSetViewportSwizzleNV(
    commandBuffer: VkCommandBuffer,
    firstViewport: u32,
    viewportCount: u32,
    pViewportSwizzles: ptr[VkViewportSwizzleNV]) -> void
{
    //TODO(ches) do this
}

vkCmdSetCoverageToColorEnableNV(
    commandBuffer: VkCommandBuffer,
    coverageToColorEnable: VkBool32) -> void
{
    //TODO(ches) do this
}

vkCmdSetCoverageToColorLocationNV(
    commandBuffer: VkCommandBuffer,
    coverageToColorLocation: u32) -> void
{
    //TODO(ches) do this
}

vkCmdSetCoverageModulationModeNV(
    commandBuffer: VkCommandBuffer,
    coverageModulationMode: VkCoverageModulationModeNV) -> void
{
    //TODO(ches) do this
}

vkCmdSetCoverageModulationTableEnableNV(
    commandBuffer: VkCommandBuffer,
    coverageModulationTableEnable: VkBool32) -> void
{
    //TODO(ches) do this
}

vkCmdSetCoverageModulationTableNV(
    commandBuffer: VkCommandBuffer,
    coverageModulationTableCount: u32,
    pCoverageModulationTable: ptr[float]) -> void
{
    //TODO(ches) do this
}

vkCmdSetShadingRateImageEnableNV(
    commandBuffer: VkCommandBuffer,
    shadingRateImageEnable: VkBool32) -> void
{
    //TODO(ches) do this
}

vkCmdSetRepresentativeFragmentTestEnableNV(
    commandBuffer: VkCommandBuffer,
    representativeFragmentTestEnable: VkBool32) -> void
{
    //TODO(ches) do this
}

vkCmdSetCoverageReductionModeNV(
    commandBuffer: VkCommandBuffer,
    coverageReductionMode: VkCoverageReductionModeNV) -> void
{
    //TODO(ches) do this
}

vkGetShaderModuleIdentifierEXT(
    device: VkDevice,
    shaderModule: VkShaderModule,
    pIdentifier: ptr[VkShaderModuleIdentifierEXT]) -> void
{
    //TODO(ches) do this
}

vkGetShaderModuleCreateInfoIdentifierEXT(
    device: VkDevice,
    pCreateInfo: ptr[VkShaderModuleCreateInfo],
    pIdentifier: ptr[VkShaderModuleIdentifierEXT]) -> void
{
    //TODO(ches) do this
}

vkGetPhysicalDeviceOpticalFlowImageFormatsNV(
    physicalDevice: VkPhysicalDevice,
    pOpticalFlowImageFormatInfo: ptr[VkOpticalFlowImageFormatInfoNV],
    pFormatCount: ptr[u32],
    pImageFormatProperties: ptr[VkOpticalFlowImageFormatPropertiesNV]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCreateOpticalFlowSessionNV(
    device: VkDevice,
    pCreateInfo: ptr[VkOpticalFlowSessionCreateInfoNV],
    pAllocator: ptr[VkAllocationCallbacks],
    pSession: ptr[VkOpticalFlowSessionNV]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyOpticalFlowSessionNV(
    device: VkDevice,
    session: VkOpticalFlowSessionNV,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkBindOpticalFlowSessionImageNV(
    device: VkDevice,
    session: VkOpticalFlowSessionNV,
    bindingPoint: VkOpticalFlowSessionBindingPointNV,
    view: VkImageView,
    layout: VkImageLayout) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCmdOpticalFlowExecuteNV(
    commandBuffer: VkCommandBuffer,
    session: VkOpticalFlowSessionNV,
    pExecuteInfo: ptr[VkOpticalFlowExecuteInfoNV]) -> void
{
    //TODO(ches) do this
}

vkCreateShadersEXT(
    device: VkDevice,
    createInfoCount: u32,
    pCreateInfos: ptr[VkShaderCreateInfoEXT],
    pAllocator: ptr[VkAllocationCallbacks],
    pShaders: ptr[VkShaderEXT]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyShaderEXT(
    device: VkDevice,
    shader: VkShaderEXT,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkGetShaderBinaryDataEXT(
    device: VkDevice,
    shader: VkShaderEXT,
    pDataSize: ptr[uint],
    pData: ptr[void]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCmdBindShadersEXT(
    commandBuffer: VkCommandBuffer,
    stageCount: u32,
    pStages: ptr[VkShaderStageFlagBits],
    pShaders: ptr[VkShaderEXT]) -> void
{
    //TODO(ches) do this
}

vkGetFramebufferTilePropertiesQCOM(
    device: VkDevice,
    framebuffer: VkFramebuffer,
    pPropertiesCount: ptr[u32],
    pProperties: ptr[VkTilePropertiesQCOM]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetDynamicRenderingTilePropertiesQCOM(
    device: VkDevice,
    pRenderingInfo: ptr[VkRenderingInfo],
    pProperties: ptr[VkTilePropertiesQCOM]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkSetLatencySleepModeNV(
    device: VkDevice,
    swapchain: VkSwapchainKHR,
    pSleepModeInfo: ptr[VkLatencySleepModeInfoNV]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkLatencySleepNV(
    device: VkDevice,
    swapchain: VkSwapchainKHR,
    pSleepInfo: ptr[VkLatencySleepInfoNV]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkSetLatencyMarkerNV(
    device: VkDevice,
    swapchain: VkSwapchainKHR,
    pLatencyMarkerInfo: ptr[VkSetLatencyMarkerInfoNV]) -> void
{
    //TODO(ches) do this
}

vkGetLatencyTimingsNV(
    device: VkDevice,
    swapchain: VkSwapchainKHR,
    pLatencyMarkerInfo: ptr[VkGetLatencyMarkerInfoNV]) -> void
{
    //TODO(ches) do this
}

vkQueueNotifyOutOfBandNV(
    queue: VkQueue,
    pQueueTypeInfo: ptr[VkOutOfBandQueueTypeInfoNV]) -> void
{
    //TODO(ches) do this
}

vkCmdSetAttachmentFeedbackLoopEnableEXT(
    commandBuffer: VkCommandBuffer,
    aspectMask: VkImageAspectFlags) -> void
{
    //TODO(ches) do this
}

vkCreateAccelerationStructureKHR(
    device: VkDevice,
    pCreateInfo: ptr[VkAccelerationStructureCreateInfoKHR],
    pAllocator: ptr[VkAllocationCallbacks],
    pAccelerationStructure: ptr[VkAccelerationStructureKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkDestroyAccelerationStructureKHR(
    device: VkDevice,
    accelerationStructure: VkAccelerationStructureKHR,
    pAllocator: ptr[VkAllocationCallbacks]) -> void
{
    //TODO(ches) do this
}

vkCmdBuildAccelerationStructuresKHR(
    commandBuffer: VkCommandBuffer,
    infoCount: u32,
    pInfos: ptr[VkAccelerationStructureBuildGeometryInfoKHR],
    ptr[VkAccelerationStructureBuildRangeInfoKHR] ppBuildRangeInfos: ptr[const]) -> void
{
    //TODO(ches) do this
}

vkCmdBuildAccelerationStructuresIndirectKHR(
    commandBuffer: VkCommandBuffer,
    infoCount: u32,
    pInfos: ptr[VkAccelerationStructureBuildGeometryInfoKHR],
    pIndirectDeviceAddresses: ptr[VkDeviceAddress],
    pIndirectStrides: ptr[u32],
    ptr[u32] ppMaxPrimitiveCounts: ptr[const]) -> void
{
    //TODO(ches) do this
}

vkBuildAccelerationStructuresKHR(
    device: VkDevice,
    deferredOperation: VkDeferredOperationKHR,
    infoCount: u32,
    pInfos: ptr[VkAccelerationStructureBuildGeometryInfoKHR],
    ptr[VkAccelerationStructureBuildRangeInfoKHR] ppBuildRangeInfos: ptr[const]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCopyAccelerationStructureKHR(
    device: VkDevice,
    deferredOperation: VkDeferredOperationKHR,
    pInfo: ptr[VkCopyAccelerationStructureInfoKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCopyAccelerationStructureToMemoryKHR(
    device: VkDevice,
    deferredOperation: VkDeferredOperationKHR,
    pInfo: ptr[VkCopyAccelerationStructureToMemoryInfoKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCopyMemoryToAccelerationStructureKHR(
    device: VkDevice,
    deferredOperation: VkDeferredOperationKHR,
    pInfo: ptr[VkCopyMemoryToAccelerationStructureInfoKHR]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkWriteAccelerationStructuresPropertiesKHR(
    device: VkDevice,
    accelerationStructureCount: u32,
    pAccelerationStructures: ptr[VkAccelerationStructureKHR],
    queryType: VkQueryType,
    dataSize: uint,
    pData: ptr[void],
    stride: uint) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCmdCopyAccelerationStructureKHR(
    commandBuffer: VkCommandBuffer,
    pInfo: ptr[VkCopyAccelerationStructureInfoKHR]) -> void
{
    //TODO(ches) do this
}

vkCmdCopyAccelerationStructureToMemoryKHR(
    commandBuffer: VkCommandBuffer,
    pInfo: ptr[VkCopyAccelerationStructureToMemoryInfoKHR]) -> void
{
    //TODO(ches) do this
}

vkCmdCopyMemoryToAccelerationStructureKHR(
    commandBuffer: VkCommandBuffer,
    pInfo: ptr[VkCopyMemoryToAccelerationStructureInfoKHR]) -> void
{
    //TODO(ches) do this
}

vkGetAccelerationStructureDeviceAddressKHR(
    device: VkDevice,
    pInfo: ptr[VkAccelerationStructureDeviceAddressInfoKHR]) -> VkDeviceAddress
{
    //TODO(ches) do this
}

vkCmdWriteAccelerationStructuresPropertiesKHR(
    commandBuffer: VkCommandBuffer,
    accelerationStructureCount: u32,
    pAccelerationStructures: ptr[VkAccelerationStructureKHR],
    queryType: VkQueryType,
    queryPool: VkQueryPool,
    firstQuery: u32) -> void
{
    //TODO(ches) do this
}

vkGetDeviceAccelerationStructureCompatibilityKHR(
    device: VkDevice,
    pVersionInfo: ptr[VkAccelerationStructureVersionInfoKHR],
    pCompatibility: ptr[VkAccelerationStructureCompatibilityKHR]) -> void
{
    //TODO(ches) do this
}

vkGetAccelerationStructureBuildSizesKHR(
    device: VkDevice,
    buildType: VkAccelerationStructureBuildTypeKHR,
    pBuildInfo: ptr[VkAccelerationStructureBuildGeometryInfoKHR],
    pMaxPrimitiveCounts: ptr[u32],
    pSizeInfo: ptr[VkAccelerationStructureBuildSizesInfoKHR]) -> void
{
    //TODO(ches) do this
}

vkCmdTraceRaysKHR(
    commandBuffer: VkCommandBuffer,
    pRaygenShaderBindingTable: ptr[VkStridedDeviceAddressRegionKHR],
    pMissShaderBindingTable: ptr[VkStridedDeviceAddressRegionKHR],
    pHitShaderBindingTable: ptr[VkStridedDeviceAddressRegionKHR],
    pCallableShaderBindingTable: ptr[VkStridedDeviceAddressRegionKHR],
    width: u32,
    height: u32,
    depth: u32) -> void
{
    //TODO(ches) do this
}

vkCreateRayTracingPipelinesKHR(
    device: VkDevice,
    deferredOperation: VkDeferredOperationKHR,
    pipelineCache: VkPipelineCache,
    createInfoCount: u32,
    pCreateInfos: ptr[VkRayTracingPipelineCreateInfoKHR],
    pAllocator: ptr[VkAllocationCallbacks],
    pPipelines: ptr[VkPipeline]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkGetRayTracingCaptureReplayShaderGroupHandlesKHR(
    device: VkDevice,
    pipeline: VkPipeline,
    firstGroup: u32,
    groupCount: u32,
    dataSize: uint,
    pData: ptr[void]) -> VkResult
{
    //TODO(ches) do this
    return .VK_SUCCESS
}

vkCmdTraceRaysIndirectKHR(
    commandBuffer: VkCommandBuffer,
    pRaygenShaderBindingTable: ptr[VkStridedDeviceAddressRegionKHR],
    pMissShaderBindingTable: ptr[VkStridedDeviceAddressRegionKHR],
    pHitShaderBindingTable: ptr[VkStridedDeviceAddressRegionKHR],
    pCallableShaderBindingTable: ptr[VkStridedDeviceAddressRegionKHR],
    indirectDeviceAddress: VkDeviceAddress) -> void
{
    //TODO(ches) do this
}

vkGetRayTracingShaderGroupStackSizeKHR(
    device: VkDevice,
    pipeline: VkPipeline,
    group: u32,
    groupShader: VkShaderGroupShaderKHR) -> VkDeviceSize
{
    //TODO(ches) do this
}

vkCmdSetRayTracingPipelineStackSizeKHR(
    commandBuffer: VkCommandBuffer,
    pipelineStackSize: u32) -> void
{
    //TODO(ches) do this
}

vkCmdDrawMeshTasksEXT(
    commandBuffer: VkCommandBuffer,
    groupCountX: u32,
    groupCountY: u32,
    groupCountZ: u32) -> void
{
    //TODO(ches) do this
}

vkCmdDrawMeshTasksIndirectEXT(
    commandBuffer: VkCommandBuffer,
    buffer: VkBuffer,
    offset: VkDeviceSize,
    drawCount: u32,
    stride: u32) -> void
{
    //TODO(ches) do this
}

vkCmdDrawMeshTasksIndirectCountEXT(
    commandBuffer: VkCommandBuffer,
    buffer: VkBuffer,
    offset: VkDeviceSize,
    countBuffer: VkBuffer,
    countBufferOffset: VkDeviceSize,
    maxDrawCount: u32,
    stride: u32) -> void
{
    //TODO(ches) do this
}

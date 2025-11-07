package vulkan

VkClearColorValue :: struct #union {
    float32 : f32[4],
    int32 : i32[4],
    uint32 : u32[4],
}

VkClearValue :: struct #union {
    color : VkClearColorValue,
    depthStencil : VkClearDepthStencilValue,
}

VkPerformanceCounterResultKHR :: struct #union {
    int32 : i32,
    int64 : i64,
    uint32 : u32,
    uint64 : u64,
    float32 : f32,
    float64 : f64,
}

VkPipelineExecutableStatisticValueKHR :: struct #union {
    b32 : b32,
    i64 : i64,
    u64 : u64,
    f64 : f64,
}

VkPerformanceValueDataINTEL :: struct #union {
    value32 : u32,
    value64 : u64,
    valueFloat : f32,
    valueBool : b32,
    valueString : cstring,
}

VkDescriptorDataEXT :: struct #union {
    pSampler : ptr[VkSampler],
    pCombinedImageSampler : ptr[VkDescriptorImageInfo],
    pInputAttachmentImage : ptr[VkDescriptorImageInfo],
    pSampledImage : ptr[VkDescriptorImageInfo],
    pStorageImage : ptr[VkDescriptorImageInfo],
    pUniformTexelBuffer : ptr[VkDescriptorAddressInfoEXT],
    pStorageTexelBuffer : ptr[VkDescriptorAddressInfoEXT],
    pUniformBuffer : ptr[VkDescriptorAddressInfoEXT],
    pStorageBuffer : ptr[VkDescriptorAddressInfoEXT],
    accelerationStructure : VkDeviceAddress,
}

VkDeviceOrHostAddressConstKHR :: struct #union {
    deviceAddress : VkDeviceAddress,
    hostAddress : rawptr,
}

VkAccelerationStructureMotionInstanceDataNV :: struct #union {
    staticInstance : VkAccelerationStructureInstanceKHR,
    matrixMotionInstance : VkAccelerationStructureMatrixMotionInstanceNV,
    srtMotionInstance : VkAccelerationStructureSRTMotionInstanceNV,
}

VkDeviceOrHostAddressKHR :: struct #union {
    deviceAddress : VkDeviceAddress,
    hostAddress : rawptr,
}

VkAccelerationStructureGeometryDataKHR :: struct #union {
    triangles : VkAccelerationStructureGeometryTrianglesDataKHR,
    aabbs : VkAccelerationStructureGeometryAabbsDataKHR,
    instances : VkAccelerationStructureGeometryInstancesDataKHR,
}


package vulkan

VK_API_VERSION_1_0 :: VK_MAKE_API_VERSION(0, 1, 0, 0)
VK_API_VERSION_1_1 :: VK_MAKE_API_VERSION(0, 1, 1, 0)
VK_API_VERSION_1_2 :: VK_MAKE_API_VERSION(0, 1, 2, 0)
VK_API_VERSION_1_3 :: VK_MAKE_API_VERSION(0, 1, 3, 0)
VK_API_VERSION_1_4 :: VK_MAKE_API_VERSION(0, 1, 4, 0)

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
VK_MAX_DEVICE_GROUP_SIZE         : uint : 32
VK_LUID_SIZE                     : uint : 8
VK_QUEUE_FAMILY_EXTERNAL         : uint : ~1
VK_MAX_DRIVER_NAME_SIZE          : uint : 256
VK_MAX_DRIVER_INFO_SIZE          : uint : 256

VK_NULL_HANDLE                   : VkHandle : cast[VkHandle](null)
VK_NULL_NON_DISPATCHABLE_HANDLE  : VkNonDispatchableHandle : cast[VkNonDispatchableHandle](0)

// Extension constants
VK_AMD_buffer_marker                                         :: 1
VK_AMD_BUFFER_MARKER_EXTENSION_NAME                          :: "VK_AMD_buffer_marker"
VK_AMD_BUFFER_MARKER_SPEC_VERSION                            :: 1
VK_AMD_device_coherent_memory                                :: 1
VK_AMD_DEVICE_COHERENT_MEMORY_EXTENSION_NAME                 :: "VK_AMD_device_coherent_memory"
VK_AMD_DEVICE_COHERENT_MEMORY_SPEC_VERSION                   :: 1
VK_AMD_display_native_hdr                                    :: 1
VK_AMD_DISPLAY_NATIVE_HDR_EXTENSION_NAME                     :: "VK_AMD_display_native_hdr"
VK_AMD_DISPLAY_NATIVE_HDR_SPEC_VERSION                       :: 1
VK_AMD_draw_indirect_count                                   :: 1
VK_AMD_DRAW_INDIRECT_COUNT_EXTENSION_NAME                    :: "VK_AMD_draw_indirect_count"
VK_AMD_DRAW_INDIRECT_COUNT_SPEC_VERSION                      :: 2
VK_AMD_gcn_shader                                            :: 1
VK_AMD_GCN_SHADER_EXTENSION_NAME                             :: "VK_AMD_gcn_shader"
VK_AMD_GCN_SHADER_SPEC_VERSION                               :: 1
VK_AMD_gpu_shader_half_float                                 :: 1
VK_AMD_GPU_SHADER_HALF_FLOAT_EXTENSION_NAME                  :: "VK_AMD_gpu_shader_half_float"
VK_AMD_GPU_SHADER_HALF_FLOAT_SPEC_VERSION                    :: 2
VK_AMD_gpu_shader_int16                                      :: 1
VK_AMD_GPU_SHADER_INT16_EXTENSION_NAME                       :: "VK_AMD_gpu_shader_int16"
VK_AMD_GPU_SHADER_INT16_SPEC_VERSION                         :: 2
VK_AMD_memory_overallocation_behavior                        :: 1
VK_AMD_MEMORY_OVERALLOCATION_BEHAVIOR_EXTENSION_NAME         :: "VK_AMD_memory_overallocation_behavior"
VK_AMD_MEMORY_OVERALLOCATION_BEHAVIOR_SPEC_VERSION           :: 1
VK_AMD_mixed_attachment_samples                              :: 1
VK_AMD_MIXED_ATTACHMENT_SAMPLES_EXTENSION_NAME               :: "VK_AMD_mixed_attachment_samples"
VK_AMD_MIXED_ATTACHMENT_SAMPLES_SPEC_VERSION                 :: 1
VK_AMD_negative_viewport_height                              :: 1
VK_AMD_NEGATIVE_VIEWPORT_HEIGHT_EXTENSION_NAME               :: "VK_AMD_negative_viewport_height"
VK_AMD_NEGATIVE_VIEWPORT_HEIGHT_SPEC_VERSION                 :: 1
VK_AMD_pipeline_compiler_control                             :: 1
VK_AMD_PIPELINE_COMPILER_CONTROL_EXTENSION_NAME              :: "VK_AMD_pipeline_compiler_control"
VK_AMD_PIPELINE_COMPILER_CONTROL_SPEC_VERSION                :: 1
VK_AMD_rasterization_order                                   :: 1
VK_AMD_RASTERIZATION_ORDER_EXTENSION_NAME                    :: "VK_AMD_rasterization_order"
VK_AMD_RASTERIZATION_ORDER_SPEC_VERSION                      :: 1
VK_AMD_shader_ballot                                         :: 1
VK_AMD_SHADER_BALLOT_EXTENSION_NAME                          :: "VK_AMD_shader_ballot"
VK_AMD_SHADER_BALLOT_SPEC_VERSION                            :: 1
VK_AMD_shader_core_properties                                :: 1
VK_AMD_SHADER_CORE_PROPERTIES_2_EXTENSION_NAME               :: "VK_AMD_shader_core_properties2"
VK_AMD_SHADER_CORE_PROPERTIES_2_SPEC_VERSION                 :: 1
VK_AMD_SHADER_CORE_PROPERTIES_EXTENSION_NAME                 :: "VK_AMD_shader_core_properties"
VK_AMD_SHADER_CORE_PROPERTIES_SPEC_VERSION                   :: 2
VK_AMD_shader_core_properties2                               :: 1
VK_AMD_shader_early_and_late_fragment_tests                  :: 1
VK_AMD_SHADER_EARLY_AND_LATE_FRAGMENT_TESTS_EXTENSION_NAME   :: "VK_AMD_shader_early_and_late_fragment_tests"
VK_AMD_SHADER_EARLY_AND_LATE_FRAGMENT_TESTS_SPEC_VERSION     :: 1
VK_AMD_shader_explicit_vertex_parameter                      :: 1
VK_AMD_SHADER_EXPLICIT_VERTEX_PARAMETER_EXTENSION_NAME       :: "VK_AMD_shader_explicit_vertex_parameter"
VK_AMD_SHADER_EXPLICIT_VERTEX_PARAMETER_SPEC_VERSION         :: 1
VK_AMD_shader_fragment_mask                                  :: 1
VK_AMD_SHADER_FRAGMENT_MASK_EXTENSION_NAME                   :: "VK_AMD_shader_fragment_mask"
VK_AMD_SHADER_FRAGMENT_MASK_SPEC_VERSION                     :: 1
VK_AMD_shader_image_load_store_lod                           :: 1
VK_AMD_SHADER_IMAGE_LOAD_STORE_LOD_EXTENSION_NAME            :: "VK_AMD_shader_image_load_store_lod"
VK_AMD_SHADER_IMAGE_LOAD_STORE_LOD_SPEC_VERSION              :: 1
VK_AMD_shader_info                                           :: 1
VK_AMD_SHADER_INFO_EXTENSION_NAME                            :: "VK_AMD_shader_info"
VK_AMD_SHADER_INFO_SPEC_VERSION                              :: 1
VK_AMD_shader_trinary_minmax                                 :: 1
VK_AMD_SHADER_TRINARY_MINMAX_EXTENSION_NAME                  :: "VK_AMD_shader_trinary_minmax"
VK_AMD_SHADER_TRINARY_MINMAX_SPEC_VERSION                    :: 1
VK_AMD_texture_gather_bias_lod                               :: 1
VK_AMD_TEXTURE_GATHER_BIAS_LOD_EXTENSION_NAME                :: "VK_AMD_texture_gather_bias_lod"
VK_AMD_TEXTURE_GATHER_BIAS_LOD_SPEC_VERSION                  :: 1
VK_ARM_rasterization_order_attachment_access                 :: 1
VK_ARM_RASTERIZATION_ORDER_ATTACHMENT_ACCESS_EXTENSION_NAME  :: "VK_ARM_rasterization_order_attachment_access"
VK_ARM_RASTERIZATION_ORDER_ATTACHMENT_ACCESS_SPEC_VERSION    :: 1
VK_ARM_render_pass_striped                                   :: 1
VK_ARM_RENDER_PASS_STRIPED_EXTENSION_NAME                    :: "VK_ARM_render_pass_striped"
VK_ARM_RENDER_PASS_STRIPED_SPEC_VERSION                      :: 1
VK_ARM_scheduling_controls                                   :: 1
VK_ARM_SCHEDULING_CONTROLS_EXTENSION_NAME                    :: "VK_ARM_scheduling_controls"
VK_ARM_SCHEDULING_CONTROLS_SPEC_VERSION                      :: 1
VK_ARM_shader_core_builtins                                  :: 1
VK_ARM_SHADER_CORE_BUILTINS_EXTENSION_NAME                   :: "VK_ARM_shader_core_builtins"
VK_ARM_SHADER_CORE_BUILTINS_SPEC_VERSION                     :: 2
VK_ARM_shader_core_properties                                :: 1
VK_ARM_SHADER_CORE_PROPERTIES_EXTENSION_NAME                 :: "VK_ARM_shader_core_properties"
VK_ARM_SHADER_CORE_PROPERTIES_SPEC_VERSION                   :: 1
VK_EXT_4444_formats                                          :: 1
VK_EXT_4444_FORMATS_EXTENSION_NAME                           :: "VK_EXT_4444_formats"
VK_EXT_4444_FORMATS_SPEC_VERSION                             :: 1
VK_EXT_acquire_drm_display                                   :: 1
VK_EXT_ACQUIRE_DRM_DISPLAY_EXTENSION_NAME                    :: "VK_EXT_acquire_drm_display"
VK_EXT_ACQUIRE_DRM_DISPLAY_SPEC_VERSION                      :: 1
VK_EXT_astc_decode_mode                                      :: 1
VK_EXT_ASTC_DECODE_MODE_EXTENSION_NAME                       :: "VK_EXT_astc_decode_mode"
VK_EXT_ASTC_DECODE_MODE_SPEC_VERSION                         :: 1
VK_EXT_attachment_feedback_loop_dynamic_state                :: 1
VK_EXT_ATTACHMENT_FEEDBACK_LOOP_DYNAMIC_STATE_EXTENSION_NAME :: "VK_EXT_attachment_feedback_loop_dynamic_state"
VK_EXT_ATTACHMENT_FEEDBACK_LOOP_DYNAMIC_STATE_SPEC_VERSION   :: 1
VK_EXT_attachment_feedback_loop_layout                       :: 1
VK_EXT_ATTACHMENT_FEEDBACK_LOOP_LAYOUT_EXTENSION_NAME        :: "VK_EXT_attachment_feedback_loop_layout"
VK_EXT_ATTACHMENT_FEEDBACK_LOOP_LAYOUT_SPEC_VERSION          :: 2
VK_EXT_blend_operation_advanced                              :: 1
VK_EXT_BLEND_OPERATION_ADVANCED_EXTENSION_NAME               :: "VK_EXT_blend_operation_advanced"
VK_EXT_BLEND_OPERATION_ADVANCED_SPEC_VERSION                 :: 2
VK_EXT_border_color_swizzle                                  :: 1
VK_EXT_BORDER_COLOR_SWIZZLE_EXTENSION_NAME                   :: "VK_EXT_border_color_swizzle"
VK_EXT_BORDER_COLOR_SWIZZLE_SPEC_VERSION                     :: 1
VK_EXT_buffer_device_address                                 :: 1
VK_EXT_BUFFER_DEVICE_ADDRESS_EXTENSION_NAME                  :: "VK_EXT_buffer_device_address"
VK_EXT_BUFFER_DEVICE_ADDRESS_SPEC_VERSION                    :: 2
VK_EXT_calibrated_timestamps                                 :: 1
VK_EXT_CALIBRATED_TIMESTAMPS_EXTENSION_NAME                  :: "VK_EXT_calibrated_timestamps"
VK_EXT_CALIBRATED_TIMESTAMPS_SPEC_VERSION                    :: 2
VK_EXT_color_write_enable                                    :: 1
VK_EXT_COLOR_WRITE_ENABLE_EXTENSION_NAME                     :: "VK_EXT_color_write_enable"
VK_EXT_COLOR_WRITE_ENABLE_SPEC_VERSION                       :: 1
VK_EXT_conditional_rendering                                 :: 1
VK_EXT_CONDITIONAL_RENDERING_EXTENSION_NAME                  :: "VK_EXT_conditional_rendering"
VK_EXT_CONDITIONAL_RENDERING_SPEC_VERSION                    :: 2
VK_EXT_conservative_rasterization                            :: 1
VK_EXT_CONSERVATIVE_RASTERIZATION_EXTENSION_NAME             :: "VK_EXT_conservative_rasterization"
VK_EXT_CONSERVATIVE_RASTERIZATION_SPEC_VERSION               :: 1
VK_EXT_custom_border_color                                   :: 1
VK_EXT_CUSTOM_BORDER_COLOR_EXTENSION_NAME                    :: "VK_EXT_custom_border_color"
VK_EXT_CUSTOM_BORDER_COLOR_SPEC_VERSION                      :: 12
VK_EXT_debug_marker                                          :: 1
VK_EXT_DEBUG_MARKER_EXTENSION_NAME                           :: "VK_EXT_debug_marker"
VK_EXT_DEBUG_MARKER_SPEC_VERSION                             :: 4
VK_EXT_debug_report                                          :: 1
VK_EXT_DEBUG_REPORT_EXTENSION_NAME                           :: "VK_EXT_debug_report"
VK_EXT_DEBUG_REPORT_SPEC_VERSION                             :: 10
VK_EXT_debug_utils                                           :: 1
VK_EXT_DEBUG_UTILS_EXTENSION_NAME                            :: "VK_EXT_debug_utils"
VK_EXT_DEBUG_UTILS_SPEC_VERSION                              :: 2
VK_EXT_depth_bias_control                                    :: 1
VK_EXT_DEPTH_BIAS_CONTROL_EXTENSION_NAME                     :: "VK_EXT_depth_bias_control"
VK_EXT_DEPTH_BIAS_CONTROL_SPEC_VERSION                       :: 1
VK_EXT_depth_clamp_zero_one                                  :: 1
VK_EXT_DEPTH_CLAMP_ZERO_ONE_EXTENSION_NAME                   :: "VK_EXT_depth_clamp_zero_one"
VK_EXT_DEPTH_CLAMP_ZERO_ONE_SPEC_VERSION                     :: 1
VK_EXT_depth_clip_control                                    :: 1
VK_EXT_DEPTH_CLIP_CONTROL_EXTENSION_NAME                     :: "VK_EXT_depth_clip_control"
VK_EXT_DEPTH_CLIP_CONTROL_SPEC_VERSION                       :: 1
VK_EXT_depth_clip_enable                                     :: 1
VK_EXT_DEPTH_CLIP_ENABLE_EXTENSION_NAME                      :: "VK_EXT_depth_clip_enable"
VK_EXT_DEPTH_CLIP_ENABLE_SPEC_VERSION                        :: 1
VK_EXT_depth_range_unrestricted                              :: 1
VK_EXT_DEPTH_RANGE_UNRESTRICTED_EXTENSION_NAME               :: "VK_EXT_depth_range_unrestricted"
VK_EXT_DEPTH_RANGE_UNRESTRICTED_SPEC_VERSION                 :: 1
VK_EXT_descriptor_buffer                                     :: 1
VK_EXT_DESCRIPTOR_BUFFER_EXTENSION_NAME                      :: "VK_EXT_descriptor_buffer"
VK_EXT_DESCRIPTOR_BUFFER_SPEC_VERSION                        :: 1
VK_EXT_descriptor_indexing                                   :: 1
VK_EXT_DESCRIPTOR_INDEXING_EXTENSION_NAME                    :: "VK_EXT_descriptor_indexing"
VK_EXT_DESCRIPTOR_INDEXING_SPEC_VERSION                      :: 2
VK_EXT_device_address_binding_report                         :: 1
VK_EXT_DEVICE_ADDRESS_BINDING_REPORT_EXTENSION_NAME          :: "VK_EXT_device_address_binding_report"
VK_EXT_DEVICE_ADDRESS_BINDING_REPORT_SPEC_VERSION            :: 1
VK_EXT_device_fault                                          :: 1
VK_EXT_DEVICE_FAULT_EXTENSION_NAME                           :: "VK_EXT_device_fault"
VK_EXT_DEVICE_FAULT_SPEC_VERSION                             :: 2
VK_EXT_device_memory_report                                  :: 1
VK_EXT_DEVICE_MEMORY_REPORT_EXTENSION_NAME                   :: "VK_EXT_device_memory_report"
VK_EXT_DEVICE_MEMORY_REPORT_SPEC_VERSION                     :: 2
VK_EXT_direct_mode_display                                   :: 1
VK_EXT_DIRECT_MODE_DISPLAY_EXTENSION_NAME                    :: "VK_EXT_direct_mode_display"
VK_EXT_DIRECT_MODE_DISPLAY_SPEC_VERSION                      :: 1
VK_EXT_discard_rectangles                                    :: 1
VK_EXT_DISCARD_RECTANGLES_EXTENSION_NAME                     :: "VK_EXT_discard_rectangles"
VK_EXT_DISCARD_RECTANGLES_SPEC_VERSION                       :: 2
VK_EXT_display_control                                       :: 1
VK_EXT_DISPLAY_CONTROL_EXTENSION_NAME                        :: "VK_EXT_display_control"
VK_EXT_DISPLAY_CONTROL_SPEC_VERSION                          :: 1
VK_EXT_display_surface_counter                               :: 1
VK_EXT_DISPLAY_SURFACE_COUNTER_EXTENSION_NAME                :: "VK_EXT_display_surface_counter"
VK_EXT_DISPLAY_SURFACE_COUNTER_SPEC_VERSION                  :: 1
VK_EXT_dynamic_rendering_unused_attachments                  :: 1
VK_EXT_DYNAMIC_RENDERING_UNUSED_ATTACHMENTS_EXTENSION_NAME   :: "VK_EXT_dynamic_rendering_unused_attachments"
VK_EXT_DYNAMIC_RENDERING_UNUSED_ATTACHMENTS_SPEC_VERSION     :: 1
VK_EXT_extended_dynamic_state                                :: 1
VK_EXT_EXTENDED_DYNAMIC_STATE_2_EXTENSION_NAME               :: "VK_EXT_extended_dynamic_state2"
VK_EXT_EXTENDED_DYNAMIC_STATE_2_SPEC_VERSION                 :: 1
VK_EXT_EXTENDED_DYNAMIC_STATE_3_EXTENSION_NAME               :: "VK_EXT_extended_dynamic_state3"
VK_EXT_EXTENDED_DYNAMIC_STATE_3_SPEC_VERSION                 :: 2
VK_EXT_EXTENDED_DYNAMIC_STATE_EXTENSION_NAME                 :: "VK_EXT_extended_dynamic_state"
VK_EXT_EXTENDED_DYNAMIC_STATE_SPEC_VERSION                   :: 1
VK_EXT_extended_dynamic_state2                               :: 1
VK_EXT_extended_dynamic_state3                               :: 1
VK_EXT_external_memory_acquire_unmodified                    :: 1
VK_EXT_EXTERNAL_MEMORY_ACQUIRE_UNMODIFIED_EXTENSION_NAME     :: "VK_EXT_external_memory_acquire_unmodified"
VK_EXT_EXTERNAL_MEMORY_ACQUIRE_UNMODIFIED_SPEC_VERSION       :: 1
VK_EXT_external_memory_dma_buf                               :: 1
VK_EXT_EXTERNAL_MEMORY_DMA_BUF_EXTENSION_NAME                :: "VK_EXT_external_memory_dma_buf"
VK_EXT_EXTERNAL_MEMORY_DMA_BUF_SPEC_VERSION                  :: 1
VK_EXT_external_memory_host                                  :: 1
VK_EXT_EXTERNAL_MEMORY_HOST_EXTENSION_NAME                   :: "VK_EXT_external_memory_host"
VK_EXT_EXTERNAL_MEMORY_HOST_SPEC_VERSION                     :: 1
VK_EXT_filter_cubic                                          :: 1
VK_EXT_FILTER_CUBIC_EXTENSION_NAME                           :: "VK_EXT_filter_cubic"
VK_EXT_FILTER_CUBIC_SPEC_VERSION                             :: 3
VK_EXT_fragment_density_map                                  :: 1
VK_EXT_FRAGMENT_DENSITY_MAP_2_EXTENSION_NAME                 :: "VK_EXT_fragment_density_map2"
VK_EXT_FRAGMENT_DENSITY_MAP_2_SPEC_VERSION                   :: 1
VK_EXT_FRAGMENT_DENSITY_MAP_EXTENSION_NAME                   :: "VK_EXT_fragment_density_map"
VK_EXT_FRAGMENT_DENSITY_MAP_SPEC_VERSION                     :: 2
VK_EXT_fragment_density_map2                                 :: 1
VK_EXT_fragment_shader_interlock                             :: 1
VK_EXT_FRAGMENT_SHADER_INTERLOCK_EXTENSION_NAME              :: "VK_EXT_fragment_shader_interlock"
VK_EXT_FRAGMENT_SHADER_INTERLOCK_SPEC_VERSION                :: 1
VK_EXT_frame_boundary                                        :: 1
VK_EXT_FRAME_BOUNDARY_EXTENSION_NAME                         :: "VK_EXT_frame_boundary"
VK_EXT_FRAME_BOUNDARY_SPEC_VERSION                           :: 1
VK_EXT_global_priority                                       :: 1
VK_EXT_GLOBAL_PRIORITY_EXTENSION_NAME                        :: "VK_EXT_global_priority"
VK_EXT_global_priority_query                                 :: 1
VK_EXT_GLOBAL_PRIORITY_QUERY_EXTENSION_NAME                  :: "VK_EXT_global_priority_query"
VK_EXT_GLOBAL_PRIORITY_QUERY_SPEC_VERSION                    :: 1
VK_EXT_GLOBAL_PRIORITY_SPEC_VERSION                          :: 2
VK_EXT_graphics_pipeline_library                             :: 1
VK_EXT_GRAPHICS_PIPELINE_LIBRARY_EXTENSION_NAME              :: "VK_EXT_graphics_pipeline_library"
VK_EXT_GRAPHICS_PIPELINE_LIBRARY_SPEC_VERSION                :: 1
VK_EXT_hdr_metadata                                          :: 1
VK_EXT_HDR_METADATA_EXTENSION_NAME                           :: "VK_EXT_hdr_metadata"
VK_EXT_HDR_METADATA_SPEC_VERSION                             :: 2
VK_EXT_headless_surface                                      :: 1
VK_EXT_HEADLESS_SURFACE_EXTENSION_NAME                       :: "VK_EXT_headless_surface"
VK_EXT_HEADLESS_SURFACE_SPEC_VERSION                         :: 1
VK_EXT_host_image_copy                                       :: 1
VK_EXT_HOST_IMAGE_COPY_EXTENSION_NAME                        :: "VK_EXT_host_image_copy"
VK_EXT_HOST_IMAGE_COPY_SPEC_VERSION                          :: 1
VK_EXT_host_query_reset                                      :: 1
VK_EXT_HOST_QUERY_RESET_EXTENSION_NAME                       :: "VK_EXT_host_query_reset"
VK_EXT_HOST_QUERY_RESET_SPEC_VERSION                         :: 1
VK_EXT_image_2d_view_of_3d                                   :: 1
VK_EXT_IMAGE_2D_VIEW_OF_3D_EXTENSION_NAME                    :: "VK_EXT_image_2d_view_of_3d"
VK_EXT_IMAGE_2D_VIEW_OF_3D_SPEC_VERSION                      :: 1
VK_EXT_image_compression_control                             :: 1
VK_EXT_IMAGE_COMPRESSION_CONTROL_EXTENSION_NAME              :: "VK_EXT_image_compression_control"
VK_EXT_IMAGE_COMPRESSION_CONTROL_SPEC_VERSION                :: 1
VK_EXT_image_compression_control_swapchain                   :: 1
VK_EXT_IMAGE_COMPRESSION_CONTROL_SWAPCHAIN_EXTENSION_NAME    :: "VK_EXT_image_compression_control_swapchain"
VK_EXT_IMAGE_COMPRESSION_CONTROL_SWAPCHAIN_SPEC_VERSION      :: 1
VK_EXT_image_drm_format_modifier                             :: 1
VK_EXT_IMAGE_DRM_FORMAT_MODIFIER_EXTENSION_NAME              :: "VK_EXT_image_drm_format_modifier"
VK_EXT_IMAGE_DRM_FORMAT_MODIFIER_SPEC_VERSION                :: 2
VK_EXT_image_robustness                                      :: 1
VK_EXT_IMAGE_ROBUSTNESS_EXTENSION_NAME                       :: "VK_EXT_image_robustness"
VK_EXT_IMAGE_ROBUSTNESS_SPEC_VERSION                         :: 1
VK_EXT_image_sliced_view_of_3d                               :: 1
VK_EXT_IMAGE_SLICED_VIEW_OF_3D_EXTENSION_NAME                :: "VK_EXT_image_sliced_view_of_3d"
VK_EXT_IMAGE_SLICED_VIEW_OF_3D_SPEC_VERSION                  :: 1
VK_EXT_image_view_min_lod                                    :: 1
VK_EXT_IMAGE_VIEW_MIN_LOD_EXTENSION_NAME                     :: "VK_EXT_image_view_min_lod"
VK_EXT_IMAGE_VIEW_MIN_LOD_SPEC_VERSION                       :: 1
VK_EXT_index_type_uint8                                      :: 1
VK_EXT_INDEX_TYPE_UINT8_EXTENSION_NAME                       :: "VK_EXT_index_type_uint8"
VK_EXT_INDEX_TYPE_UINT8_SPEC_VERSION                         :: 1
VK_EXT_inline_uniform_block                                  :: 1
VK_EXT_INLINE_UNIFORM_BLOCK_EXTENSION_NAME                   :: "VK_EXT_inline_uniform_block"
VK_EXT_INLINE_UNIFORM_BLOCK_SPEC_VERSION                     :: 1
VK_EXT_layer_settings                                        :: 1
VK_EXT_LAYER_SETTINGS_EXTENSION_NAME                         :: "VK_EXT_layer_settings"
VK_EXT_LAYER_SETTINGS_SPEC_VERSION                           :: 2
VK_EXT_legacy_dithering                                      :: 1
VK_EXT_LEGACY_DITHERING_EXTENSION_NAME                       :: "VK_EXT_legacy_dithering"
VK_EXT_LEGACY_DITHERING_SPEC_VERSION                         :: 1
VK_EXT_line_rasterization                                    :: 1
VK_EXT_LINE_RASTERIZATION_EXTENSION_NAME                     :: "VK_EXT_line_rasterization"
VK_EXT_LINE_RASTERIZATION_SPEC_VERSION                       :: 1
VK_EXT_load_store_op_none                                    :: 1
VK_EXT_LOAD_STORE_OP_NONE_EXTENSION_NAME                     :: "VK_EXT_load_store_op_none"
VK_EXT_LOAD_STORE_OP_NONE_SPEC_VERSION                       :: 1
VK_EXT_map_memory_placed                                     :: 1
VK_EXT_MAP_MEMORY_PLACED_EXTENSION_NAME                      :: "VK_EXT_map_memory_placed"
VK_EXT_MAP_MEMORY_PLACED_SPEC_VERSION                        :: 1
VK_EXT_memory_budget                                         :: 1
VK_EXT_MEMORY_BUDGET_EXTENSION_NAME                          :: "VK_EXT_memory_budget"
VK_EXT_MEMORY_BUDGET_SPEC_VERSION                            :: 1
VK_EXT_memory_priority                                       :: 1
VK_EXT_MEMORY_PRIORITY_EXTENSION_NAME                        :: "VK_EXT_memory_priority"
VK_EXT_MEMORY_PRIORITY_SPEC_VERSION                          :: 1
VK_EXT_mesh_shader                                           :: 1
VK_EXT_MESH_SHADER_EXTENSION_NAME                            :: "VK_EXT_mesh_shader"
VK_EXT_MESH_SHADER_SPEC_VERSION                              :: 1
VK_EXT_multi_draw                                            :: 1
VK_EXT_MULTI_DRAW_EXTENSION_NAME                             :: "VK_EXT_multi_draw"
VK_EXT_MULTI_DRAW_SPEC_VERSION                               :: 1
VK_EXT_multisampled_render_to_single_sampled                 :: 1
VK_EXT_MULTISAMPLED_RENDER_TO_SINGLE_SAMPLED_EXTENSION_NAME  :: "VK_EXT_multisampled_render_to_single_sampled"
VK_EXT_MULTISAMPLED_RENDER_TO_SINGLE_SAMPLED_SPEC_VERSION    :: 1
VK_EXT_mutable_descriptor_type                               :: 1
VK_EXT_MUTABLE_DESCRIPTOR_TYPE_EXTENSION_NAME                :: "VK_EXT_mutable_descriptor_type"
VK_EXT_MUTABLE_DESCRIPTOR_TYPE_SPEC_VERSION                  :: 1
VK_EXT_nested_command_buffer                                 :: 1
VK_EXT_NESTED_COMMAND_BUFFER_EXTENSION_NAME                  :: "VK_EXT_nested_command_buffer"
VK_EXT_NESTED_COMMAND_BUFFER_SPEC_VERSION                    :: 1
VK_EXT_non_seamless_cube_map                                 :: 1
VK_EXT_NON_SEAMLESS_CUBE_MAP_EXTENSION_NAME                  :: "VK_EXT_non_seamless_cube_map"
VK_EXT_NON_SEAMLESS_CUBE_MAP_SPEC_VERSION                    :: 1
VK_EXT_opacity_micromap                                      :: 1
VK_EXT_OPACITY_MICROMAP_EXTENSION_NAME                       :: "VK_EXT_opacity_micromap"
VK_EXT_OPACITY_MICROMAP_SPEC_VERSION                         :: 2
VK_EXT_pageable_device_local_memory                          :: 1
VK_EXT_PAGEABLE_DEVICE_LOCAL_MEMORY_EXTENSION_NAME           :: "VK_EXT_pageable_device_local_memory"
VK_EXT_PAGEABLE_DEVICE_LOCAL_MEMORY_SPEC_VERSION             :: 1
VK_EXT_pci_bus_info                                          :: 1
VK_EXT_PCI_BUS_INFO_EXTENSION_NAME                           :: "VK_EXT_pci_bus_info"
VK_EXT_PCI_BUS_INFO_SPEC_VERSION                             :: 2
VK_EXT_physical_device_drm                                   :: 1
VK_EXT_PHYSICAL_DEVICE_DRM_EXTENSION_NAME                    :: "VK_EXT_physical_device_drm"
VK_EXT_PHYSICAL_DEVICE_DRM_SPEC_VERSION                      :: 1
VK_EXT_pipeline_creation_cache_control                       :: 1
VK_EXT_PIPELINE_CREATION_CACHE_CONTROL_EXTENSION_NAME        :: "VK_EXT_pipeline_creation_cache_control"
VK_EXT_PIPELINE_CREATION_CACHE_CONTROL_SPEC_VERSION          :: 3
VK_EXT_pipeline_creation_feedback                            :: 1
VK_EXT_PIPELINE_CREATION_FEEDBACK_EXTENSION_NAME             :: "VK_EXT_pipeline_creation_feedback"
VK_EXT_PIPELINE_CREATION_FEEDBACK_SPEC_VERSION               :: 1
VK_EXT_pipeline_library_group_handles                        :: 1
VK_EXT_PIPELINE_LIBRARY_GROUP_HANDLES_EXTENSION_NAME         :: "VK_EXT_pipeline_library_group_handles"
VK_EXT_PIPELINE_LIBRARY_GROUP_HANDLES_SPEC_VERSION           :: 1
VK_EXT_pipeline_properties                                   :: 1
VK_EXT_PIPELINE_PROPERTIES_EXTENSION_NAME                    :: "VK_EXT_pipeline_properties"
VK_EXT_PIPELINE_PROPERTIES_SPEC_VERSION                      :: 1
VK_EXT_pipeline_protected_access                             :: 1
VK_EXT_PIPELINE_PROTECTED_ACCESS_EXTENSION_NAME              :: "VK_EXT_pipeline_protected_access"
VK_EXT_PIPELINE_PROTECTED_ACCESS_SPEC_VERSION                :: 1
VK_EXT_pipeline_robustness                                   :: 1
VK_EXT_PIPELINE_ROBUSTNESS_EXTENSION_NAME                    :: "VK_EXT_pipeline_robustness"
VK_EXT_PIPELINE_ROBUSTNESS_SPEC_VERSION                      :: 1
VK_EXT_post_depth_coverage                                   :: 1
VK_EXT_POST_DEPTH_COVERAGE_EXTENSION_NAME                    :: "VK_EXT_post_depth_coverage"
VK_EXT_POST_DEPTH_COVERAGE_SPEC_VERSION                      :: 1
VK_EXT_primitive_topology_list_restart                       :: 1
VK_EXT_PRIMITIVE_TOPOLOGY_LIST_RESTART_EXTENSION_NAME        :: "VK_EXT_primitive_topology_list_restart"
VK_EXT_PRIMITIVE_TOPOLOGY_LIST_RESTART_SPEC_VERSION          :: 1
VK_EXT_primitives_generated_query                            :: 1
VK_EXT_PRIMITIVES_GENERATED_QUERY_EXTENSION_NAME             :: "VK_EXT_primitives_generated_query"
VK_EXT_PRIMITIVES_GENERATED_QUERY_SPEC_VERSION               :: 1
VK_EXT_private_data                                          :: 1
VK_EXT_PRIVATE_DATA_EXTENSION_NAME                           :: "VK_EXT_private_data"
VK_EXT_PRIVATE_DATA_SPEC_VERSION                             :: 1
VK_EXT_provoking_vertex                                      :: 1
VK_EXT_PROVOKING_VERTEX_EXTENSION_NAME                       :: "VK_EXT_provoking_vertex"
VK_EXT_PROVOKING_VERTEX_SPEC_VERSION                         :: 1
VK_EXT_queue_family_foreign                                  :: 1
VK_EXT_QUEUE_FAMILY_FOREIGN_EXTENSION_NAME                   :: "VK_EXT_queue_family_foreign"
VK_EXT_QUEUE_FAMILY_FOREIGN_SPEC_VERSION                     :: 1
VK_EXT_rasterization_order_attachment_access                 :: 1
VK_EXT_RASTERIZATION_ORDER_ATTACHMENT_ACCESS_EXTENSION_NAME  :: "VK_EXT_rasterization_order_attachment_access"
VK_EXT_RASTERIZATION_ORDER_ATTACHMENT_ACCESS_SPEC_VERSION    :: 1
VK_EXT_rgba10x6_formats                                      :: 1
VK_EXT_RGBA10X6_FORMATS_EXTENSION_NAME                       :: "VK_EXT_rgba10x6_formats"
VK_EXT_RGBA10X6_FORMATS_SPEC_VERSION                         :: 1
VK_EXT_ROBUSTNESS_2_EXTENSION_NAME                           :: "VK_EXT_robustness2"
VK_EXT_ROBUSTNESS_2_SPEC_VERSION                             :: 1
VK_EXT_robustness2                                           :: 1
VK_EXT_sample_locations                                      :: 1
VK_EXT_SAMPLE_LOCATIONS_EXTENSION_NAME                       :: "VK_EXT_sample_locations"
VK_EXT_SAMPLE_LOCATIONS_SPEC_VERSION                         :: 1
VK_EXT_sampler_filter_minmax                                 :: 1
VK_EXT_SAMPLER_FILTER_MINMAX_EXTENSION_NAME                  :: "VK_EXT_sampler_filter_minmax"
VK_EXT_SAMPLER_FILTER_MINMAX_SPEC_VERSION                    :: 2
VK_EXT_scalar_block_layout                                   :: 1
VK_EXT_SCALAR_BLOCK_LAYOUT_EXTENSION_NAME                    :: "VK_EXT_scalar_block_layout"
VK_EXT_SCALAR_BLOCK_LAYOUT_SPEC_VERSION                      :: 1
VK_EXT_separate_stencil_usage                                :: 1
VK_EXT_SEPARATE_STENCIL_USAGE_EXTENSION_NAME                 :: "VK_EXT_separate_stencil_usage"
VK_EXT_SEPARATE_STENCIL_USAGE_SPEC_VERSION                   :: 1
VK_EXT_shader_atomic_float                                   :: 1
VK_EXT_SHADER_ATOMIC_FLOAT_2_EXTENSION_NAME                  :: "VK_EXT_shader_atomic_float2"
VK_EXT_SHADER_ATOMIC_FLOAT_2_SPEC_VERSION                    :: 1
VK_EXT_SHADER_ATOMIC_FLOAT_EXTENSION_NAME                    :: "VK_EXT_shader_atomic_float"
VK_EXT_SHADER_ATOMIC_FLOAT_SPEC_VERSION                      :: 1
VK_EXT_shader_atomic_float2                                  :: 1
VK_EXT_shader_demote_to_helper_invocation                    :: 1
VK_EXT_SHADER_DEMOTE_TO_HELPER_INVOCATION_EXTENSION_NAME     :: "VK_EXT_shader_demote_to_helper_invocation"
VK_EXT_SHADER_DEMOTE_TO_HELPER_INVOCATION_SPEC_VERSION       :: 1
VK_EXT_shader_image_atomic_int64                             :: 1
VK_EXT_SHADER_IMAGE_ATOMIC_INT64_EXTENSION_NAME              :: "VK_EXT_shader_image_atomic_int64"
VK_EXT_SHADER_IMAGE_ATOMIC_INT64_SPEC_VERSION                :: 1
VK_EXT_shader_module_identifier                              :: 1
VK_EXT_SHADER_MODULE_IDENTIFIER_EXTENSION_NAME               :: "VK_EXT_shader_module_identifier"
VK_EXT_SHADER_MODULE_IDENTIFIER_SPEC_VERSION                 :: 1
VK_EXT_shader_object                                         :: 1
VK_EXT_SHADER_OBJECT_EXTENSION_NAME                          :: "VK_EXT_shader_object"
VK_EXT_SHADER_OBJECT_SPEC_VERSION                            :: 1
VK_EXT_shader_stencil_export                                 :: 1
VK_EXT_SHADER_STENCIL_EXPORT_EXTENSION_NAME                  :: "VK_EXT_shader_stencil_export"
VK_EXT_SHADER_STENCIL_EXPORT_SPEC_VERSION                    :: 1
VK_EXT_shader_subgroup_ballot                                :: 1
VK_EXT_SHADER_SUBGROUP_BALLOT_EXTENSION_NAME                 :: "VK_EXT_shader_subgroup_ballot"
VK_EXT_SHADER_SUBGROUP_BALLOT_SPEC_VERSION                   :: 1
VK_EXT_shader_subgroup_vote                                  :: 1
VK_EXT_SHADER_SUBGROUP_VOTE_EXTENSION_NAME                   :: "VK_EXT_shader_subgroup_vote"
VK_EXT_SHADER_SUBGROUP_VOTE_SPEC_VERSION                     :: 1
VK_EXT_shader_tile_image                                     :: 1
VK_EXT_SHADER_TILE_IMAGE_EXTENSION_NAME                      :: "VK_EXT_shader_tile_image"
VK_EXT_SHADER_TILE_IMAGE_SPEC_VERSION                        :: 1
VK_EXT_shader_viewport_index_layer                           :: 1
VK_EXT_SHADER_VIEWPORT_INDEX_LAYER_EXTENSION_NAME            :: "VK_EXT_shader_viewport_index_layer"
VK_EXT_SHADER_VIEWPORT_INDEX_LAYER_SPEC_VERSION              :: 1
VK_EXT_subgroup_size_control                                 :: 1
VK_EXT_SUBGROUP_SIZE_CONTROL_EXTENSION_NAME                  :: "VK_EXT_subgroup_size_control"
VK_EXT_SUBGROUP_SIZE_CONTROL_SPEC_VERSION                    :: 2
VK_EXT_subpass_merge_feedback                                :: 1
VK_EXT_SUBPASS_MERGE_FEEDBACK_EXTENSION_NAME                 :: "VK_EXT_subpass_merge_feedback"
VK_EXT_SUBPASS_MERGE_FEEDBACK_SPEC_VERSION                   :: 2
VK_EXT_SURFACE_MAINTENANCE_1_EXTENSION_NAME                  :: "VK_EXT_surface_maintenance1"
VK_EXT_SURFACE_MAINTENANCE_1_SPEC_VERSION                    :: 1
VK_EXT_surface_maintenance1                                  :: 1
VK_EXT_SWAPCHAIN_COLOR_SPACE_EXTENSION_NAME                  :: "VK_EXT_swapchain_colorspace"
VK_EXT_SWAPCHAIN_COLOR_SPACE_SPEC_VERSION                    :: 4
VK_EXT_swapchain_colorspace                                  :: 1
VK_EXT_SWAPCHAIN_MAINTENANCE_1_EXTENSION_NAME                :: "VK_EXT_swapchain_maintenance1"
VK_EXT_SWAPCHAIN_MAINTENANCE_1_SPEC_VERSION                  :: 1
VK_EXT_swapchain_maintenance1                                :: 1
VK_EXT_texel_buffer_alignment                                :: 1
VK_EXT_TEXEL_BUFFER_ALIGNMENT_EXTENSION_NAME                 :: "VK_EXT_texel_buffer_alignment"
VK_EXT_TEXEL_BUFFER_ALIGNMENT_SPEC_VERSION                   :: 1
VK_EXT_texture_compression_astc_hdr                          :: 1
VK_EXT_TEXTURE_COMPRESSION_ASTC_HDR_EXTENSION_NAME           :: "VK_EXT_texture_compression_astc_hdr"
VK_EXT_TEXTURE_COMPRESSION_ASTC_HDR_SPEC_VERSION             :: 1
VK_EXT_tooling_info                                          :: 1
VK_EXT_TOOLING_INFO_EXTENSION_NAME                           :: "VK_EXT_tooling_info"
VK_EXT_TOOLING_INFO_SPEC_VERSION                             :: 1
VK_EXT_transform_feedback                                    :: 1
VK_EXT_TRANSFORM_FEEDBACK_EXTENSION_NAME                     :: "VK_EXT_transform_feedback"
VK_EXT_TRANSFORM_FEEDBACK_SPEC_VERSION                       :: 1
VK_EXT_validation_cache                                      :: 1
VK_EXT_VALIDATION_CACHE_EXTENSION_NAME                       :: "VK_EXT_validation_cache"
VK_EXT_VALIDATION_CACHE_SPEC_VERSION                         :: 1
VK_EXT_validation_features                                   :: 1
VK_EXT_VALIDATION_FEATURES_EXTENSION_NAME                    :: "VK_EXT_validation_features"
VK_EXT_VALIDATION_FEATURES_SPEC_VERSION                      :: 6
VK_EXT_validation_flags                                      :: 1
VK_EXT_VALIDATION_FLAGS_EXTENSION_NAME                       :: "VK_EXT_validation_flags"
VK_EXT_VALIDATION_FLAGS_SPEC_VERSION                         :: 3
VK_EXT_vertex_attribute_divisor                              :: 1
VK_EXT_VERTEX_ATTRIBUTE_DIVISOR_EXTENSION_NAME               :: "VK_EXT_vertex_attribute_divisor"
VK_EXT_VERTEX_ATTRIBUTE_DIVISOR_SPEC_VERSION                 :: 3
VK_EXT_vertex_input_dynamic_state                            :: 1
VK_EXT_VERTEX_INPUT_DYNAMIC_STATE_EXTENSION_NAME             :: "VK_EXT_vertex_input_dynamic_state"
VK_EXT_VERTEX_INPUT_DYNAMIC_STATE_SPEC_VERSION               :: 2
VK_EXT_ycbcr_2plane_444_formats                              :: 1
VK_EXT_YCBCR_2PLANE_444_FORMATS_EXTENSION_NAME               :: "VK_EXT_ycbcr_2plane_444_formats"
VK_EXT_YCBCR_2PLANE_444_FORMATS_SPEC_VERSION                 :: 1
VK_EXT_ycbcr_image_arrays                                    :: 1
VK_EXT_YCBCR_IMAGE_ARRAYS_EXTENSION_NAME                     :: "VK_EXT_ycbcr_image_arrays"
VK_EXT_YCBCR_IMAGE_ARRAYS_SPEC_VERSION                       :: 1
VK_GOOGLE_decorate_string                                    :: 1
VK_GOOGLE_DECORATE_STRING_EXTENSION_NAME                     :: "VK_GOOGLE_decorate_string"
VK_GOOGLE_DECORATE_STRING_SPEC_VERSION                       :: 1
VK_GOOGLE_display_timing                                     :: 1
VK_GOOGLE_DISPLAY_TIMING_EXTENSION_NAME                      :: "VK_GOOGLE_display_timing"
VK_GOOGLE_DISPLAY_TIMING_SPEC_VERSION                        :: 1
VK_GOOGLE_HLSL_FUNCTIONALITY_1_EXTENSION_NAME                :: "VK_GOOGLE_hlsl_functionality1"
VK_GOOGLE_HLSL_FUNCTIONALITY_1_SPEC_VERSION                  :: 1
VK_GOOGLE_hlsl_functionality1                                :: 1
VK_GOOGLE_HLSL_FUNCTIONALITY1_EXTENSION_NAME                 :: VK_GOOGLE_HLSL_FUNCTIONALITY_1_EXTENSION_NAME
VK_GOOGLE_HLSL_FUNCTIONALITY1_SPEC_VERSION                   :: VK_GOOGLE_HLSL_FUNCTIONALITY_1_SPEC_VERSION
VK_GOOGLE_surfaceless_query                                  :: 1
VK_GOOGLE_SURFACELESS_QUERY_EXTENSION_NAME                   :: "VK_GOOGLE_surfaceless_query"
VK_GOOGLE_SURFACELESS_QUERY_SPEC_VERSION                     :: 2
VK_GOOGLE_user_type                                          :: 1
VK_GOOGLE_USER_TYPE_EXTENSION_NAME                           :: "VK_GOOGLE_user_type"
VK_GOOGLE_USER_TYPE_SPEC_VERSION                             :: 1
VK_HUAWEI_cluster_culling_shader                             :: 1
VK_HUAWEI_CLUSTER_CULLING_SHADER_EXTENSION_NAME              :: "VK_HUAWEI_cluster_culling_shader"
VK_HUAWEI_CLUSTER_CULLING_SHADER_SPEC_VERSION                :: 3
VK_HUAWEI_invocation_mask                                    :: 1
VK_HUAWEI_INVOCATION_MASK_EXTENSION_NAME                     :: "VK_HUAWEI_invocation_mask"
VK_HUAWEI_INVOCATION_MASK_SPEC_VERSION                       :: 1
VK_HUAWEI_subpass_shading                                    :: 1
VK_HUAWEI_SUBPASS_SHADING_EXTENSION_NAME                     :: "VK_HUAWEI_subpass_shading"
VK_HUAWEI_SUBPASS_SHADING_SPEC_VERSION                       :: 3
VK_IMG_filter_cubic                                          :: 1
VK_IMG_FILTER_CUBIC_EXTENSION_NAME                           :: "VK_IMG_filter_cubic"
VK_IMG_FILTER_CUBIC_SPEC_VERSION                             :: 1
VK_IMG_format_pvrtc                                          :: 1
VK_IMG_FORMAT_PVRTC_EXTENSION_NAME                           :: "VK_IMG_format_pvrtc"
VK_IMG_FORMAT_PVRTC_SPEC_VERSION                             :: 1
VK_IMG_relaxed_line_rasterization                            :: 1
VK_IMG_RELAXED_LINE_RASTERIZATION_EXTENSION_NAME             :: "VK_IMG_relaxed_line_rasterization"
VK_IMG_RELAXED_LINE_RASTERIZATION_SPEC_VERSION               :: 1
VK_INTEL_performance_query                                   :: 1
VK_INTEL_PERFORMANCE_QUERY_EXTENSION_NAME                    :: "VK_INTEL_performance_query"
VK_INTEL_PERFORMANCE_QUERY_SPEC_VERSION                      :: 2
VK_INTEL_SHADER_INTEGER_FUNCTIONS_2_EXTENSION_NAME           :: "VK_INTEL_shader_integer_functions2"
VK_INTEL_SHADER_INTEGER_FUNCTIONS_2_SPEC_VERSION             :: 1
VK_INTEL_shader_integer_functions2                           :: 1
VK_KHR_16bit_storage                                         :: 1
VK_KHR_16BIT_STORAGE_EXTENSION_NAME                          :: "VK_KHR_16bit_storage"
VK_KHR_16BIT_STORAGE_SPEC_VERSION                            :: 1
VK_KHR_8bit_storage                                          :: 1
VK_KHR_8BIT_STORAGE_EXTENSION_NAME                           :: "VK_KHR_8bit_storage"
VK_KHR_8BIT_STORAGE_SPEC_VERSION                             :: 1
VK_KHR_acceleration_structure                                :: 1
VK_KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME                 :: "VK_KHR_acceleration_structure"
VK_KHR_ACCELERATION_STRUCTURE_SPEC_VERSION                   :: 13
VK_KHR_BIND_MEMORY_2_EXTENSION_NAME                          :: "VK_KHR_bind_memory2"
VK_KHR_BIND_MEMORY_2_SPEC_VERSION                            :: 1
VK_KHR_bind_memory2                                          :: 1
VK_KHR_buffer_device_address                                 :: 1
VK_KHR_BUFFER_DEVICE_ADDRESS_EXTENSION_NAME                  :: "VK_KHR_buffer_device_address"
VK_KHR_BUFFER_DEVICE_ADDRESS_SPEC_VERSION                    :: 1
VK_KHR_calibrated_timestamps                                 :: 1
VK_KHR_CALIBRATED_TIMESTAMPS_EXTENSION_NAME                  :: "VK_KHR_calibrated_timestamps"
VK_KHR_CALIBRATED_TIMESTAMPS_SPEC_VERSION                    :: 1
VK_KHR_cooperative_matrix                                    :: 1
VK_KHR_COOPERATIVE_MATRIX_EXTENSION_NAME                     :: "VK_KHR_cooperative_matrix"
VK_KHR_COOPERATIVE_MATRIX_SPEC_VERSION                       :: 2
VK_KHR_COPY_COMMANDS_2_EXTENSION_NAME                        :: "VK_KHR_copy_commands2"
VK_KHR_COPY_COMMANDS_2_SPEC_VERSION                          :: 1
VK_KHR_copy_commands2                                        :: 1
VK_KHR_CREATE_RENDERPASS_2_EXTENSION_NAME                    :: "VK_KHR_create_renderpass2"
VK_KHR_CREATE_RENDERPASS_2_SPEC_VERSION                      :: 1
VK_KHR_create_renderpass2                                    :: 1
VK_KHR_dedicated_allocation                                  :: 1
VK_KHR_DEDICATED_ALLOCATION_EXTENSION_NAME                   :: "VK_KHR_dedicated_allocation"
VK_KHR_DEDICATED_ALLOCATION_SPEC_VERSION                     :: 3
VK_KHR_deferred_host_operations                              :: 1
VK_KHR_DEFERRED_HOST_OPERATIONS_EXTENSION_NAME               :: "VK_KHR_deferred_host_operations"
VK_KHR_DEFERRED_HOST_OPERATIONS_SPEC_VERSION                 :: 4
VK_KHR_depth_stencil_resolve                                 :: 1
VK_KHR_DEPTH_STENCIL_RESOLVE_EXTENSION_NAME                  :: "VK_KHR_depth_stencil_resolve"
VK_KHR_DEPTH_STENCIL_RESOLVE_SPEC_VERSION                    :: 1
VK_KHR_descriptor_update_template                            :: 1
VK_KHR_DESCRIPTOR_UPDATE_TEMPLATE_EXTENSION_NAME             :: "VK_KHR_descriptor_update_template"
VK_KHR_DESCRIPTOR_UPDATE_TEMPLATE_SPEC_VERSION               :: 1
VK_KHR_device_group                                          :: 1
VK_KHR_device_group_creation                                 :: 1
VK_KHR_DEVICE_GROUP_CREATION_EXTENSION_NAME                  :: "VK_KHR_device_group_creation"
VK_KHR_DEVICE_GROUP_CREATION_SPEC_VERSION                    :: 1
VK_KHR_DEVICE_GROUP_EXTENSION_NAME                           :: "VK_KHR_device_group"
VK_KHR_DEVICE_GROUP_SPEC_VERSION                             :: 4
VK_KHR_display                                               :: 1
VK_KHR_DISPLAY_EXTENSION_NAME                                :: "VK_KHR_display"
VK_KHR_DISPLAY_SPEC_VERSION                                  :: 23
VK_KHR_display_swapchain                                     :: 1
VK_KHR_DISPLAY_SWAPCHAIN_EXTENSION_NAME                      :: "VK_KHR_display_swapchain"
VK_KHR_DISPLAY_SWAPCHAIN_SPEC_VERSION                        :: 10
VK_KHR_draw_indirect_count                                   :: 1
VK_KHR_DRAW_INDIRECT_COUNT_EXTENSION_NAME                    :: "VK_KHR_draw_indirect_count"
VK_KHR_DRAW_INDIRECT_COUNT_SPEC_VERSION                      :: 1
VK_KHR_driver_properties                                     :: 1
VK_KHR_DRIVER_PROPERTIES_EXTENSION_NAME                      :: "VK_KHR_driver_properties"
VK_KHR_DRIVER_PROPERTIES_SPEC_VERSION                        :: 1
VK_KHR_dynamic_rendering                                     :: 1
VK_KHR_DYNAMIC_RENDERING_EXTENSION_NAME                      :: "VK_KHR_dynamic_rendering"
VK_KHR_dynamic_rendering_local_read                          :: 1
VK_KHR_DYNAMIC_RENDERING_LOCAL_READ_EXTENSION_NAME           :: "VK_KHR_dynamic_rendering_local_read"
VK_KHR_DYNAMIC_RENDERING_LOCAL_READ_SPEC_VERSION             :: 1
VK_KHR_DYNAMIC_RENDERING_SPEC_VERSION                        :: 1
VK_KHR_external_fence                                        :: 1
VK_KHR_external_fence_capabilities                           :: 1
VK_KHR_EXTERNAL_FENCE_CAPABILITIES_EXTENSION_NAME            :: "VK_KHR_external_fence_capabilities"
VK_KHR_EXTERNAL_FENCE_CAPABILITIES_SPEC_VERSION              :: 1
VK_KHR_EXTERNAL_FENCE_EXTENSION_NAME                         :: "VK_KHR_external_fence"
VK_KHR_external_fence_fd                                     :: 1
VK_KHR_EXTERNAL_FENCE_FD_EXTENSION_NAME                      :: "VK_KHR_external_fence_fd"
VK_KHR_EXTERNAL_FENCE_FD_SPEC_VERSION                        :: 1
VK_KHR_EXTERNAL_FENCE_SPEC_VERSION                           :: 1
VK_KHR_external_memory                                       :: 1
VK_KHR_external_memory_capabilities                          :: 1
VK_KHR_EXTERNAL_MEMORY_CAPABILITIES_EXTENSION_NAME           :: "VK_KHR_external_memory_capabilities"
VK_KHR_EXTERNAL_MEMORY_CAPABILITIES_SPEC_VERSION             :: 1
VK_KHR_EXTERNAL_MEMORY_EXTENSION_NAME                        :: "VK_KHR_external_memory"
VK_KHR_external_memory_fd                                    :: 1
VK_KHR_EXTERNAL_MEMORY_FD_EXTENSION_NAME                     :: "VK_KHR_external_memory_fd"
VK_KHR_EXTERNAL_MEMORY_FD_SPEC_VERSION                       :: 1
VK_KHR_EXTERNAL_MEMORY_SPEC_VERSION                          :: 1
VK_KHR_external_semaphore                                    :: 1
VK_KHR_external_semaphore_capabilities                       :: 1
VK_KHR_EXTERNAL_SEMAPHORE_CAPABILITIES_EXTENSION_NAME        :: "VK_KHR_external_semaphore_capabilities"
VK_KHR_EXTERNAL_SEMAPHORE_CAPABILITIES_SPEC_VERSION          :: 1
VK_KHR_EXTERNAL_SEMAPHORE_EXTENSION_NAME                     :: "VK_KHR_external_semaphore"
VK_KHR_external_semaphore_fd                                 :: 1
VK_KHR_EXTERNAL_SEMAPHORE_FD_EXTENSION_NAME                  :: "VK_KHR_external_semaphore_fd"
VK_KHR_EXTERNAL_SEMAPHORE_FD_SPEC_VERSION                    :: 1
VK_KHR_EXTERNAL_SEMAPHORE_SPEC_VERSION                       :: 1
VK_KHR_FORMAT_FEATURE_FLAGS_2_EXTENSION_NAME                 :: "VK_KHR_format_feature_flags2"
VK_KHR_FORMAT_FEATURE_FLAGS_2_SPEC_VERSION                   :: 2
VK_KHR_format_feature_flags2                                 :: 1
VK_KHR_fragment_shader_barycentric                           :: 1
VK_KHR_FRAGMENT_SHADER_BARYCENTRIC_EXTENSION_NAME            :: "VK_KHR_fragment_shader_barycentric"
VK_KHR_FRAGMENT_SHADER_BARYCENTRIC_SPEC_VERSION              :: 1
VK_KHR_fragment_shading_rate                                 :: 1
VK_KHR_FRAGMENT_SHADING_RATE_EXTENSION_NAME                  :: "VK_KHR_fragment_shading_rate"
VK_KHR_FRAGMENT_SHADING_RATE_SPEC_VERSION                    :: 2
VK_KHR_GET_DISPLAY_PROPERTIES_2_EXTENSION_NAME               :: "VK_KHR_get_display_properties2"
VK_KHR_GET_DISPLAY_PROPERTIES_2_SPEC_VERSION                 :: 1
VK_KHR_get_display_properties2                               :: 1
VK_KHR_GET_MEMORY_REQUIREMENTS_2_EXTENSION_NAME              :: "VK_KHR_get_memory_requirements2"
VK_KHR_GET_MEMORY_REQUIREMENTS_2_SPEC_VERSION                :: 1
VK_KHR_get_memory_requirements2                              :: 1
VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME       :: "VK_KHR_get_physical_device_properties2"
VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_SPEC_VERSION         :: 2
VK_KHR_get_physical_device_properties2                       :: 1
VK_KHR_GET_SURFACE_CAPABILITIES_2_EXTENSION_NAME             :: "VK_KHR_get_surface_capabilities2"
VK_KHR_GET_SURFACE_CAPABILITIES_2_SPEC_VERSION               :: 1
VK_KHR_get_surface_capabilities2                             :: 1
VK_KHR_global_priority                                       :: 1
VK_KHR_GLOBAL_PRIORITY_EXTENSION_NAME                        :: "VK_KHR_global_priority"
VK_KHR_GLOBAL_PRIORITY_SPEC_VERSION                          :: 1
VK_KHR_image_format_list                                     :: 1
VK_KHR_IMAGE_FORMAT_LIST_EXTENSION_NAME                      :: "VK_KHR_image_format_list"
VK_KHR_IMAGE_FORMAT_LIST_SPEC_VERSION                        :: 1
VK_KHR_imageless_framebuffer                                 :: 1
VK_KHR_IMAGELESS_FRAMEBUFFER_EXTENSION_NAME                  :: "VK_KHR_imageless_framebuffer"
VK_KHR_IMAGELESS_FRAMEBUFFER_SPEC_VERSION                    :: 1
VK_KHR_incremental_present                                   :: 1
VK_KHR_INCREMENTAL_PRESENT_EXTENSION_NAME                    :: "VK_KHR_incremental_present"
VK_KHR_INCREMENTAL_PRESENT_SPEC_VERSION                      :: 2
VK_KHR_index_type_uint8                                      :: 1
VK_KHR_INDEX_TYPE_UINT8_EXTENSION_NAME                       :: "VK_KHR_index_type_uint8"
VK_KHR_INDEX_TYPE_UINT8_SPEC_VERSION                         :: 1
VK_KHR_line_rasterization                                    :: 1
VK_KHR_LINE_RASTERIZATION_EXTENSION_NAME                     :: "VK_KHR_line_rasterization"
VK_KHR_LINE_RASTERIZATION_SPEC_VERSION                       :: 1
VK_KHR_load_store_op_none                                    :: 1
VK_KHR_LOAD_STORE_OP_NONE_EXTENSION_NAME                     :: "VK_KHR_load_store_op_none"
VK_KHR_LOAD_STORE_OP_NONE_SPEC_VERSION                       :: 1
VK_KHR_MAINTENANCE_1_EXTENSION_NAME                          :: "VK_KHR_maintenance1"
VK_KHR_MAINTENANCE_1_SPEC_VERSION                            :: 2
VK_KHR_MAINTENANCE_2_EXTENSION_NAME                          :: "VK_KHR_maintenance2"
VK_KHR_MAINTENANCE_2_SPEC_VERSION                            :: 1
VK_KHR_MAINTENANCE_3_EXTENSION_NAME                          :: "VK_KHR_maintenance3"
VK_KHR_MAINTENANCE_3_SPEC_VERSION                            :: 1
VK_KHR_MAINTENANCE_4_EXTENSION_NAME                          :: "VK_KHR_maintenance4"
VK_KHR_MAINTENANCE_4_SPEC_VERSION                            :: 2
VK_KHR_MAINTENANCE_5_EXTENSION_NAME                          :: "VK_KHR_maintenance5"
VK_KHR_MAINTENANCE_5_SPEC_VERSION                            :: 1
VK_KHR_MAINTENANCE_6_EXTENSION_NAME                          :: "VK_KHR_maintenance6"
VK_KHR_MAINTENANCE_6_SPEC_VERSION                            :: 1
VK_KHR_maintenance1                                          :: 1
VK_KHR_MAINTENANCE1_EXTENSION_NAME                           :: VK_KHR_MAINTENANCE_1_EXTENSION_NAME
VK_KHR_MAINTENANCE1_SPEC_VERSION                             :: VK_KHR_MAINTENANCE_1_SPEC_VERSION
VK_KHR_maintenance2                                          :: 1
VK_KHR_MAINTENANCE2_EXTENSION_NAME                           :: VK_KHR_MAINTENANCE_2_EXTENSION_NAME
VK_KHR_MAINTENANCE2_SPEC_VERSION                             :: VK_KHR_MAINTENANCE_2_SPEC_VERSION
VK_KHR_maintenance3                                          :: 1
VK_KHR_MAINTENANCE3_EXTENSION_NAME                           :: VK_KHR_MAINTENANCE_3_EXTENSION_NAME
VK_KHR_MAINTENANCE3_SPEC_VERSION                             :: VK_KHR_MAINTENANCE_3_SPEC_VERSION
VK_KHR_maintenance4                                          :: 1
VK_KHR_maintenance5                                          :: 1
VK_KHR_maintenance6                                          :: 1
VK_KHR_MAP_MEMORY_2_EXTENSION_NAME                           :: "VK_KHR_map_memory2"
VK_KHR_MAP_MEMORY_2_SPEC_VERSION                             :: 1
VK_KHR_map_memory2                                           :: 1
VK_KHR_multiview                                             :: 1
VK_KHR_MULTIVIEW_EXTENSION_NAME                              :: "VK_KHR_multiview"
VK_KHR_MULTIVIEW_SPEC_VERSION                                :: 1
VK_KHR_performance_query                                     :: 1
VK_KHR_PERFORMANCE_QUERY_EXTENSION_NAME                      :: "VK_KHR_performance_query"
VK_KHR_PERFORMANCE_QUERY_SPEC_VERSION                        :: 1
VK_KHR_pipeline_executable_properties                        :: 1
VK_KHR_PIPELINE_EXECUTABLE_PROPERTIES_EXTENSION_NAME         :: "VK_KHR_pipeline_executable_properties"
VK_KHR_PIPELINE_EXECUTABLE_PROPERTIES_SPEC_VERSION           :: 1
VK_KHR_pipeline_library                                      :: 1
VK_KHR_PIPELINE_LIBRARY_EXTENSION_NAME                       :: "VK_KHR_pipeline_library"
VK_KHR_PIPELINE_LIBRARY_SPEC_VERSION                         :: 1
VK_KHR_portability_enumeration                               :: 1
VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME                :: "VK_KHR_portability_enumeration"
VK_KHR_PORTABILITY_ENUMERATION_SPEC_VERSION                  :: 1
VK_KHR_present_id                                            :: 1
VK_KHR_PRESENT_ID_EXTENSION_NAME                             :: "VK_KHR_present_id"
VK_KHR_PRESENT_ID_SPEC_VERSION                               :: 1
VK_KHR_present_wait                                          :: 1
VK_KHR_PRESENT_WAIT_EXTENSION_NAME                           :: "VK_KHR_present_wait"
VK_KHR_PRESENT_WAIT_SPEC_VERSION                             :: 1
VK_KHR_push_descriptor                                       :: 1
VK_KHR_PUSH_DESCRIPTOR_EXTENSION_NAME                        :: "VK_KHR_push_descriptor"
VK_KHR_PUSH_DESCRIPTOR_SPEC_VERSION                          :: 2
VK_KHR_ray_query                                             :: 1
VK_KHR_RAY_QUERY_EXTENSION_NAME                              :: "VK_KHR_ray_query"
VK_KHR_RAY_QUERY_SPEC_VERSION                                :: 1
VK_KHR_RAY_TRACING_MAINTENANCE_1_EXTENSION_NAME              :: "VK_KHR_ray_tracing_maintenance1"
VK_KHR_RAY_TRACING_MAINTENANCE_1_SPEC_VERSION                :: 1
VK_KHR_ray_tracing_maintenance1                              :: 1
VK_KHR_ray_tracing_pipeline                                  :: 1
VK_KHR_RAY_TRACING_PIPELINE_EXTENSION_NAME                   :: "VK_KHR_ray_tracing_pipeline"
VK_KHR_RAY_TRACING_PIPELINE_SPEC_VERSION                     :: 1
VK_KHR_ray_tracing_position_fetch                            :: 1
VK_KHR_RAY_TRACING_POSITION_FETCH_EXTENSION_NAME             :: "VK_KHR_ray_tracing_position_fetch"
VK_KHR_RAY_TRACING_POSITION_FETCH_SPEC_VERSION               :: 1
VK_KHR_relaxed_block_layout                                  :: 1
VK_KHR_RELAXED_BLOCK_LAYOUT_EXTENSION_NAME                   :: "VK_KHR_relaxed_block_layout"
VK_KHR_RELAXED_BLOCK_LAYOUT_SPEC_VERSION                     :: 1
VK_KHR_sampler_mirror_clamp_to_edge                          :: 1
VK_KHR_SAMPLER_MIRROR_CLAMP_TO_EDGE_EXTENSION_NAME           :: "VK_KHR_sampler_mirror_clamp_to_edge"
VK_KHR_SAMPLER_MIRROR_CLAMP_TO_EDGE_SPEC_VERSION             :: 3
VK_KHR_sampler_ycbcr_conversion                              :: 1
VK_KHR_SAMPLER_YCBCR_CONVERSION_EXTENSION_NAME               :: "VK_KHR_sampler_ycbcr_conversion"
VK_KHR_SAMPLER_YCBCR_CONVERSION_SPEC_VERSION                 :: 14
VK_KHR_separate_depth_stencil_layouts                        :: 1
VK_KHR_SEPARATE_DEPTH_STENCIL_LAYOUTS_EXTENSION_NAME         :: "VK_KHR_separate_depth_stencil_layouts"
VK_KHR_SEPARATE_DEPTH_STENCIL_LAYOUTS_SPEC_VERSION           :: 1
VK_KHR_shader_atomic_int64                                   :: 1
VK_KHR_SHADER_ATOMIC_INT64_EXTENSION_NAME                    :: "VK_KHR_shader_atomic_int64"
VK_KHR_SHADER_ATOMIC_INT64_SPEC_VERSION                      :: 1
VK_KHR_shader_clock                                          :: 1
VK_KHR_SHADER_CLOCK_EXTENSION_NAME                           :: "VK_KHR_shader_clock"
VK_KHR_SHADER_CLOCK_SPEC_VERSION                             :: 1
VK_KHR_shader_draw_parameters                                :: 1
VK_KHR_SHADER_DRAW_PARAMETERS_EXTENSION_NAME                 :: "VK_KHR_shader_draw_parameters"
VK_KHR_SHADER_DRAW_PARAMETERS_SPEC_VERSION                   :: 1
VK_KHR_shader_expect_assume                                  :: 1
VK_KHR_SHADER_EXPECT_ASSUME_EXTENSION_NAME                   :: "VK_KHR_shader_expect_assume"
VK_KHR_SHADER_EXPECT_ASSUME_SPEC_VERSION                     :: 1
VK_KHR_shader_float_controls                                 :: 1
VK_KHR_SHADER_FLOAT_CONTROLS_2_EXTENSION_NAME                :: "VK_KHR_shader_float_controls2"
VK_KHR_SHADER_FLOAT_CONTROLS_2_SPEC_VERSION                  :: 1
VK_KHR_SHADER_FLOAT_CONTROLS_EXTENSION_NAME                  :: "VK_KHR_shader_float_controls"
VK_KHR_SHADER_FLOAT_CONTROLS_SPEC_VERSION                    :: 4
VK_KHR_shader_float_controls2                                :: 1
VK_KHR_shader_float16_int8                                   :: 1
VK_KHR_SHADER_FLOAT16_INT8_EXTENSION_NAME                    :: "VK_KHR_shader_float16_int8"
VK_KHR_SHADER_FLOAT16_INT8_SPEC_VERSION                      :: 1
VK_KHR_shader_integer_dot_product                            :: 1
VK_KHR_SHADER_INTEGER_DOT_PRODUCT_EXTENSION_NAME             :: "VK_KHR_shader_integer_dot_product"
VK_KHR_SHADER_INTEGER_DOT_PRODUCT_SPEC_VERSION               :: 1
VK_KHR_shader_maximal_reconvergence                          :: 1
VK_KHR_SHADER_MAXIMAL_RECONVERGENCE_EXTENSION_NAME           :: "VK_KHR_shader_maximal_reconvergence"
VK_KHR_SHADER_MAXIMAL_RECONVERGENCE_SPEC_VERSION             :: 1
VK_KHR_shader_non_semantic_info                              :: 1
VK_KHR_SHADER_NON_SEMANTIC_INFO_EXTENSION_NAME               :: "VK_KHR_shader_non_semantic_info"
VK_KHR_SHADER_NON_SEMANTIC_INFO_SPEC_VERSION                 :: 1
VK_KHR_shader_quad_control                                   :: 1
VK_KHR_SHADER_QUAD_CONTROL_EXTENSION_NAME                    :: "VK_KHR_shader_quad_control"
VK_KHR_SHADER_QUAD_CONTROL_SPEC_VERSION                      :: 1
VK_KHR_shader_subgroup_extended_types                        :: 1
VK_KHR_SHADER_SUBGROUP_EXTENDED_TYPES_EXTENSION_NAME         :: "VK_KHR_shader_subgroup_extended_types"
VK_KHR_SHADER_SUBGROUP_EXTENDED_TYPES_SPEC_VERSION           :: 1
VK_KHR_shader_subgroup_rotate                                :: 1
VK_KHR_SHADER_SUBGROUP_ROTATE_EXTENSION_NAME                 :: "VK_KHR_shader_subgroup_rotate"
VK_KHR_SHADER_SUBGROUP_ROTATE_SPEC_VERSION                   :: 2
VK_KHR_shader_subgroup_uniform_control_flow                  :: 1
VK_KHR_SHADER_SUBGROUP_UNIFORM_CONTROL_FLOW_EXTENSION_NAME   :: "VK_KHR_shader_subgroup_uniform_control_flow"
VK_KHR_SHADER_SUBGROUP_UNIFORM_CONTROL_FLOW_SPEC_VERSION     :: 1
VK_KHR_shader_terminate_invocation                           :: 1
VK_KHR_SHADER_TERMINATE_INVOCATION_EXTENSION_NAME            :: "VK_KHR_shader_terminate_invocation"
VK_KHR_SHADER_TERMINATE_INVOCATION_SPEC_VERSION              :: 1
VK_KHR_shared_presentable_image                              :: 1
VK_KHR_SHARED_PRESENTABLE_IMAGE_EXTENSION_NAME               :: "VK_KHR_shared_presentable_image"
VK_KHR_SHARED_PRESENTABLE_IMAGE_SPEC_VERSION                 :: 1
VK_KHR_spirv_1_4                                             :: 1
VK_KHR_SPIRV_1_4_EXTENSION_NAME                              :: "VK_KHR_spirv_1_4"
VK_KHR_SPIRV_1_4_SPEC_VERSION                                :: 1
VK_KHR_storage_buffer_storage_class                          :: 1
VK_KHR_STORAGE_BUFFER_STORAGE_CLASS_EXTENSION_NAME           :: "VK_KHR_storage_buffer_storage_class"
VK_KHR_STORAGE_BUFFER_STORAGE_CLASS_SPEC_VERSION             :: 1
VK_KHR_surface                                               :: 1
VK_KHR_SURFACE_EXTENSION_NAME                                :: "VK_KHR_surface"
VK_KHR_surface_protected_capabilities                        :: 1
VK_KHR_SURFACE_PROTECTED_CAPABILITIES_EXTENSION_NAME         :: "VK_KHR_surface_protected_capabilities"
VK_KHR_SURFACE_PROTECTED_CAPABILITIES_SPEC_VERSION           :: 1
VK_KHR_SURFACE_SPEC_VERSION                                  :: 25
VK_KHR_swapchain                                             :: 1
VK_KHR_SWAPCHAIN_EXTENSION_NAME                              :: "VK_KHR_swapchain"
VK_KHR_swapchain_mutable_format                              :: 1
VK_KHR_SWAPCHAIN_MUTABLE_FORMAT_EXTENSION_NAME               :: "VK_KHR_swapchain_mutable_format"
VK_KHR_SWAPCHAIN_MUTABLE_FORMAT_SPEC_VERSION                 :: 1
VK_KHR_SWAPCHAIN_SPEC_VERSION                                :: 70
VK_KHR_SYNCHRONIZATION_2_EXTENSION_NAME                      :: "VK_KHR_synchronization2"
VK_KHR_SYNCHRONIZATION_2_SPEC_VERSION                        :: 1
VK_KHR_synchronization2                                      :: 1
VK_KHR_timeline_semaphore                                    :: 1
VK_KHR_TIMELINE_SEMAPHORE_EXTENSION_NAME                     :: "VK_KHR_timeline_semaphore"
VK_KHR_TIMELINE_SEMAPHORE_SPEC_VERSION                       :: 2
VK_KHR_uniform_buffer_standard_layout                        :: 1
VK_KHR_UNIFORM_BUFFER_STANDARD_LAYOUT_EXTENSION_NAME         :: "VK_KHR_uniform_buffer_standard_layout"
VK_KHR_UNIFORM_BUFFER_STANDARD_LAYOUT_SPEC_VERSION           :: 1
VK_KHR_variable_pointers                                     :: 1
VK_KHR_VARIABLE_POINTERS_EXTENSION_NAME                      :: "VK_KHR_variable_pointers"
VK_KHR_VARIABLE_POINTERS_SPEC_VERSION                        :: 1
VK_KHR_vertex_attribute_divisor                              :: 1
VK_KHR_VERTEX_ATTRIBUTE_DIVISOR_EXTENSION_NAME               :: "VK_KHR_vertex_attribute_divisor"
VK_KHR_VERTEX_ATTRIBUTE_DIVISOR_SPEC_VERSION                 :: 1
VK_KHR_video_decode_av1                                      :: 1
VK_KHR_VIDEO_DECODE_AV1_EXTENSION_NAME                       :: "VK_KHR_video_decode_av1"
VK_KHR_VIDEO_DECODE_AV1_SPEC_VERSION                         :: 1
VK_KHR_video_decode_h264                                     :: 1
VK_KHR_VIDEO_DECODE_H264_EXTENSION_NAME                      :: "VK_KHR_video_decode_h264"
VK_KHR_VIDEO_DECODE_H264_SPEC_VERSION                        :: 9
VK_KHR_video_decode_h265                                     :: 1
VK_KHR_VIDEO_DECODE_H265_EXTENSION_NAME                      :: "VK_KHR_video_decode_h265"
VK_KHR_VIDEO_DECODE_H265_SPEC_VERSION                        :: 8
VK_KHR_video_decode_queue                                    :: 1
VK_KHR_VIDEO_DECODE_QUEUE_EXTENSION_NAME                     :: "VK_KHR_video_decode_queue"
VK_KHR_VIDEO_DECODE_QUEUE_SPEC_VERSION                       :: 8
VK_KHR_video_encode_h264                                     :: 1
VK_KHR_VIDEO_ENCODE_H264_EXTENSION_NAME                      :: "VK_KHR_video_encode_h264"
VK_KHR_VIDEO_ENCODE_H264_SPEC_VERSION                        :: 14
VK_KHR_video_encode_h265                                     :: 1
VK_KHR_VIDEO_ENCODE_H265_EXTENSION_NAME                      :: "VK_KHR_video_encode_h265"
VK_KHR_VIDEO_ENCODE_H265_SPEC_VERSION                        :: 14
VK_KHR_video_encode_queue                                    :: 1
VK_KHR_VIDEO_ENCODE_QUEUE_EXTENSION_NAME                     :: "VK_KHR_video_encode_queue"
VK_KHR_VIDEO_ENCODE_QUEUE_SPEC_VERSION                       :: 12
VK_KHR_VIDEO_MAINTENANCE_1_EXTENSION_NAME                    :: "VK_KHR_video_maintenance1"
VK_KHR_VIDEO_MAINTENANCE_1_SPEC_VERSION                      :: 1
VK_KHR_video_maintenance1                                    :: 1
VK_KHR_video_queue                                           :: 1
VK_KHR_VIDEO_QUEUE_EXTENSION_NAME                            :: "VK_KHR_video_queue"
VK_KHR_VIDEO_QUEUE_SPEC_VERSION                              :: 8
VK_KHR_vulkan_memory_model                                   :: 1
VK_KHR_VULKAN_MEMORY_MODEL_EXTENSION_NAME                    :: "VK_KHR_vulkan_memory_model"
VK_KHR_VULKAN_MEMORY_MODEL_SPEC_VERSION                      :: 3
VK_KHR_workgroup_memory_explicit_layout                      :: 1
VK_KHR_WORKGROUP_MEMORY_EXPLICIT_LAYOUT_EXTENSION_NAME       :: "VK_KHR_workgroup_memory_explicit_layout"
VK_KHR_WORKGROUP_MEMORY_EXPLICIT_LAYOUT_SPEC_VERSION         :: 1
VK_KHR_zero_initialize_workgroup_memory                      :: 1
VK_KHR_ZERO_INITIALIZE_WORKGROUP_MEMORY_EXTENSION_NAME       :: "VK_KHR_zero_initialize_workgroup_memory"
VK_KHR_ZERO_INITIALIZE_WORKGROUP_MEMORY_SPEC_VERSION         :: 1
VK_LUID_SIZE_KHR                                             :: VK_LUID_SIZE
VK_LUNARG_direct_driver_loading                              :: 1
VK_LUNARG_DIRECT_DRIVER_LOADING_EXTENSION_NAME               :: "VK_LUNARG_direct_driver_loading"
VK_LUNARG_DIRECT_DRIVER_LOADING_SPEC_VERSION                 :: 1
VK_MAX_DEVICE_GROUP_SIZE_KHR                                 :: VK_MAX_DEVICE_GROUP_SIZE
VK_MAX_DRIVER_INFO_SIZE_KHR                                  :: VK_MAX_DRIVER_INFO_SIZE
VK_MAX_DRIVER_NAME_SIZE_KHR                                  :: VK_MAX_DRIVER_NAME_SIZE
VK_MAX_GLOBAL_PRIORITY_SIZE_EXT                              :: VK_MAX_GLOBAL_PRIORITY_SIZE_KHR
VK_MAX_GLOBAL_PRIORITY_SIZE_KHR                              :: 16U
VK_MAX_SHADER_MODULE_IDENTIFIER_SIZE_EXT                     :: 32U
VK_MAX_VIDEO_AV1_REFERENCES_PER_FRAME_KHR                    :: 7U
VK_MSFT_layered_driver                                       :: 1
VK_MSFT_LAYERED_DRIVER_EXTENSION_NAME                        :: "VK_MSFT_layered_driver"
VK_MSFT_LAYERED_DRIVER_SPEC_VERSION                          :: 1
VK_NV_clip_space_w_scaling                                   :: 1
VK_NV_CLIP_SPACE_W_SCALING_EXTENSION_NAME                    :: "VK_NV_clip_space_w_scaling"
VK_NV_CLIP_SPACE_W_SCALING_SPEC_VERSION                      :: 1
VK_NV_compute_shader_derivatives                             :: 1
VK_NV_COMPUTE_SHADER_DERIVATIVES_EXTENSION_NAME              :: "VK_NV_compute_shader_derivatives"
VK_NV_COMPUTE_SHADER_DERIVATIVES_SPEC_VERSION                :: 1
VK_NV_cooperative_matrix                                     :: 1
VK_NV_COOPERATIVE_MATRIX_EXTENSION_NAME                      :: "VK_NV_cooperative_matrix"
VK_NV_COOPERATIVE_MATRIX_SPEC_VERSION                        :: 1
VK_NV_copy_memory_indirect                                   :: 1
VK_NV_COPY_MEMORY_INDIRECT_EXTENSION_NAME                    :: "VK_NV_copy_memory_indirect"
VK_NV_COPY_MEMORY_INDIRECT_SPEC_VERSION                      :: 1
VK_NV_corner_sampled_image                                   :: 1
VK_NV_CORNER_SAMPLED_IMAGE_EXTENSION_NAME                    :: "VK_NV_corner_sampled_image"
VK_NV_CORNER_SAMPLED_IMAGE_SPEC_VERSION                      :: 2
VK_NV_coverage_reduction_mode                                :: 1
VK_NV_COVERAGE_REDUCTION_MODE_EXTENSION_NAME                 :: "VK_NV_coverage_reduction_mode"
VK_NV_COVERAGE_REDUCTION_MODE_SPEC_VERSION                   :: 1
VK_NV_cuda_kernel_launch                                     :: 1
VK_NV_CUDA_KERNEL_LAUNCH_EXTENSION_NAME                      :: "VK_NV_cuda_kernel_launch"
VK_NV_CUDA_KERNEL_LAUNCH_SPEC_VERSION                        :: 2
VK_NV_dedicated_allocation                                   :: 1
VK_NV_DEDICATED_ALLOCATION_EXTENSION_NAME                    :: "VK_NV_dedicated_allocation"
VK_NV_dedicated_allocation_image_aliasing                    :: 1
VK_NV_DEDICATED_ALLOCATION_IMAGE_ALIASING_EXTENSION_NAME     :: "VK_NV_dedicated_allocation_image_aliasing"
VK_NV_DEDICATED_ALLOCATION_IMAGE_ALIASING_SPEC_VERSION       :: 1
VK_NV_DEDICATED_ALLOCATION_SPEC_VERSION                      :: 1
VK_NV_descriptor_pool_overallocation                         :: 1
VK_NV_DESCRIPTOR_POOL_OVERALLOCATION_EXTENSION_NAME          :: "VK_NV_descriptor_pool_overallocation"
VK_NV_DESCRIPTOR_POOL_OVERALLOCATION_SPEC_VERSION            :: 1
VK_NV_device_diagnostic_checkpoints                          :: 1
VK_NV_DEVICE_DIAGNOSTIC_CHECKPOINTS_EXTENSION_NAME           :: "VK_NV_device_diagnostic_checkpoints"
VK_NV_DEVICE_DIAGNOSTIC_CHECKPOINTS_SPEC_VERSION             :: 2
VK_NV_device_diagnostics_config                              :: 1
VK_NV_DEVICE_DIAGNOSTICS_CONFIG_EXTENSION_NAME               :: "VK_NV_device_diagnostics_config"
VK_NV_DEVICE_DIAGNOSTICS_CONFIG_SPEC_VERSION                 :: 2
VK_NV_device_generated_commands                              :: 1
VK_NV_device_generated_commands_compute                      :: 1
VK_NV_DEVICE_GENERATED_COMMANDS_COMPUTE_EXTENSION_NAME       :: "VK_NV_device_generated_commands_compute"
VK_NV_DEVICE_GENERATED_COMMANDS_COMPUTE_SPEC_VERSION         :: 2
VK_NV_DEVICE_GENERATED_COMMANDS_EXTENSION_NAME               :: "VK_NV_device_generated_commands"
VK_NV_DEVICE_GENERATED_COMMANDS_SPEC_VERSION                 :: 3
VK_NV_extended_sparse_address_space                          :: 1
VK_NV_EXTENDED_SPARSE_ADDRESS_SPACE_EXTENSION_NAME           :: "VK_NV_extended_sparse_address_space"
VK_NV_EXTENDED_SPARSE_ADDRESS_SPACE_SPEC_VERSION             :: 1
VK_NV_external_memory                                        :: 1
VK_NV_external_memory_capabilities                           :: 1
VK_NV_EXTERNAL_MEMORY_CAPABILITIES_EXTENSION_NAME            :: "VK_NV_external_memory_capabilities"
VK_NV_EXTERNAL_MEMORY_CAPABILITIES_SPEC_VERSION              :: 1
VK_NV_EXTERNAL_MEMORY_EXTENSION_NAME                         :: "VK_NV_external_memory"
VK_NV_external_memory_rdma                                   :: 1
VK_NV_EXTERNAL_MEMORY_RDMA_EXTENSION_NAME                    :: "VK_NV_external_memory_rdma"
VK_NV_EXTERNAL_MEMORY_RDMA_SPEC_VERSION                      :: 1
VK_NV_EXTERNAL_MEMORY_SPEC_VERSION                           :: 1
VK_NV_fill_rectangle                                         :: 1
VK_NV_FILL_RECTANGLE_EXTENSION_NAME                          :: "VK_NV_fill_rectangle"
VK_NV_FILL_RECTANGLE_SPEC_VERSION                            :: 1
VK_NV_fragment_coverage_to_color                             :: 1
VK_NV_FRAGMENT_COVERAGE_TO_COLOR_EXTENSION_NAME              :: "VK_NV_fragment_coverage_to_color"
VK_NV_FRAGMENT_COVERAGE_TO_COLOR_SPEC_VERSION                :: 1
VK_NV_fragment_shader_barycentric                            :: 1
VK_NV_FRAGMENT_SHADER_BARYCENTRIC_EXTENSION_NAME             :: "VK_NV_fragment_shader_barycentric"
VK_NV_FRAGMENT_SHADER_BARYCENTRIC_SPEC_VERSION               :: 1
VK_NV_fragment_shading_rate_enums                            :: 1
VK_NV_FRAGMENT_SHADING_RATE_ENUMS_EXTENSION_NAME             :: "VK_NV_fragment_shading_rate_enums"
VK_NV_FRAGMENT_SHADING_RATE_ENUMS_SPEC_VERSION               :: 1
VK_NV_framebuffer_mixed_samples                              :: 1
VK_NV_FRAMEBUFFER_MIXED_SAMPLES_EXTENSION_NAME               :: "VK_NV_framebuffer_mixed_samples"
VK_NV_FRAMEBUFFER_MIXED_SAMPLES_SPEC_VERSION                 :: 1
VK_NV_geometry_shader_passthrough                            :: 1
VK_NV_GEOMETRY_SHADER_PASSTHROUGH_EXTENSION_NAME             :: "VK_NV_geometry_shader_passthrough"
VK_NV_GEOMETRY_SHADER_PASSTHROUGH_SPEC_VERSION               :: 1
VK_NV_glsl_shader                                            :: 1
VK_NV_GLSL_SHADER_EXTENSION_NAME                             :: "VK_NV_glsl_shader"
VK_NV_GLSL_SHADER_SPEC_VERSION                               :: 1
VK_NV_inherited_viewport_scissor                             :: 1
VK_NV_INHERITED_VIEWPORT_SCISSOR_EXTENSION_NAME              :: "VK_NV_inherited_viewport_scissor"
VK_NV_INHERITED_VIEWPORT_SCISSOR_SPEC_VERSION                :: 1
VK_NV_linear_color_attachment                                :: 1
VK_NV_LINEAR_COLOR_ATTACHMENT_EXTENSION_NAME                 :: "VK_NV_linear_color_attachment"
VK_NV_LINEAR_COLOR_ATTACHMENT_SPEC_VERSION                   :: 1
VK_NV_low_latency                                            :: 1
VK_NV_LOW_LATENCY_2_EXTENSION_NAME                           :: "VK_NV_low_latency2"
VK_NV_LOW_LATENCY_2_SPEC_VERSION                             :: 2
VK_NV_LOW_LATENCY_EXTENSION_NAME                             :: "VK_NV_low_latency"
VK_NV_LOW_LATENCY_SPEC_VERSION                               :: 1
VK_NV_low_latency2                                           :: 1
VK_NV_memory_decompression                                   :: 1
VK_NV_MEMORY_DECOMPRESSION_EXTENSION_NAME                    :: "VK_NV_memory_decompression"
VK_NV_MEMORY_DECOMPRESSION_SPEC_VERSION                      :: 1
VK_NV_mesh_shader                                            :: 1
VK_NV_MESH_SHADER_EXTENSION_NAME                             :: "VK_NV_mesh_shader"
VK_NV_MESH_SHADER_SPEC_VERSION                               :: 1
VK_NV_optical_flow                                           :: 1
VK_NV_OPTICAL_FLOW_EXTENSION_NAME                            :: "VK_NV_optical_flow"
VK_NV_OPTICAL_FLOW_SPEC_VERSION                              :: 1
VK_NV_per_stage_descriptor_set                               :: 1
VK_NV_PER_STAGE_DESCRIPTOR_SET_EXTENSION_NAME                :: "VK_NV_per_stage_descriptor_set"
VK_NV_PER_STAGE_DESCRIPTOR_SET_SPEC_VERSION                  :: 1
VK_NV_present_barrier                                        :: 1
VK_NV_PRESENT_BARRIER_EXTENSION_NAME                         :: "VK_NV_present_barrier"
VK_NV_PRESENT_BARRIER_SPEC_VERSION                           :: 1
VK_NV_ray_tracing                                            :: 1
VK_NV_RAY_TRACING_EXTENSION_NAME                             :: "VK_NV_ray_tracing"
VK_NV_ray_tracing_invocation_reorder                         :: 1
VK_NV_RAY_TRACING_INVOCATION_REORDER_EXTENSION_NAME          :: "VK_NV_ray_tracing_invocation_reorder"
VK_NV_RAY_TRACING_INVOCATION_REORDER_SPEC_VERSION            :: 1
VK_NV_ray_tracing_motion_blur                                :: 1
VK_NV_RAY_TRACING_MOTION_BLUR_EXTENSION_NAME                 :: "VK_NV_ray_tracing_motion_blur"
VK_NV_RAY_TRACING_MOTION_BLUR_SPEC_VERSION                   :: 1
VK_NV_RAY_TRACING_SPEC_VERSION                               :: 3
VK_NV_representative_fragment_test                           :: 1
VK_NV_REPRESENTATIVE_FRAGMENT_TEST_EXTENSION_NAME            :: "VK_NV_representative_fragment_test"
VK_NV_REPRESENTATIVE_FRAGMENT_TEST_SPEC_VERSION              :: 2
VK_NV_sample_mask_override_coverage                          :: 1
VK_NV_SAMPLE_MASK_OVERRIDE_COVERAGE_EXTENSION_NAME           :: "VK_NV_sample_mask_override_coverage"
VK_NV_SAMPLE_MASK_OVERRIDE_COVERAGE_SPEC_VERSION             :: 1
VK_NV_scissor_exclusive                                      :: 1
VK_NV_SCISSOR_EXCLUSIVE_EXTENSION_NAME                       :: "VK_NV_scissor_exclusive"
VK_NV_SCISSOR_EXCLUSIVE_SPEC_VERSION                         :: 2
VK_NV_shader_atomic_float16_vector                           :: 1
VK_NV_SHADER_ATOMIC_FLOAT16_VECTOR_EXTENSION_NAME            :: "VK_NV_shader_atomic_float16_vector"
VK_NV_SHADER_ATOMIC_FLOAT16_VECTOR_SPEC_VERSION              :: 1
VK_NV_shader_image_footprint                                 :: 1
VK_NV_SHADER_IMAGE_FOOTPRINT_EXTENSION_NAME                  :: "VK_NV_shader_image_footprint"
VK_NV_SHADER_IMAGE_FOOTPRINT_SPEC_VERSION                    :: 2
VK_NV_shader_sm_builtins                                     :: 1
VK_NV_SHADER_SM_BUILTINS_EXTENSION_NAME                      :: "VK_NV_shader_sm_builtins"
VK_NV_SHADER_SM_BUILTINS_SPEC_VERSION                        :: 1
VK_NV_shader_subgroup_partitioned                            :: 1
VK_NV_SHADER_SUBGROUP_PARTITIONED_EXTENSION_NAME             :: "VK_NV_shader_subgroup_partitioned"
VK_NV_SHADER_SUBGROUP_PARTITIONED_SPEC_VERSION               :: 1
VK_NV_shading_rate_image                                     :: 1
VK_NV_SHADING_RATE_IMAGE_EXTENSION_NAME                      :: "VK_NV_shading_rate_image"
VK_NV_SHADING_RATE_IMAGE_SPEC_VERSION                        :: 3
VK_NV_VIEWPORT_ARRAY_2_EXTENSION_NAME                        :: "VK_NV_viewport_array2"
VK_NV_VIEWPORT_ARRAY_2_SPEC_VERSION                          :: 1
VK_NV_viewport_array2                                        :: 1
VK_NV_VIEWPORT_ARRAY2_EXTENSION_NAME                         :: VK_NV_VIEWPORT_ARRAY_2_EXTENSION_NAME
VK_NV_VIEWPORT_ARRAY2_SPEC_VERSION                           :: VK_NV_VIEWPORT_ARRAY_2_SPEC_VERSION
VK_NV_viewport_swizzle                                       :: 1
VK_NV_VIEWPORT_SWIZZLE_EXTENSION_NAME                        :: "VK_NV_viewport_swizzle"
VK_NV_VIEWPORT_SWIZZLE_SPEC_VERSION                          :: 1
VK_NVX_binary_import                                         :: 1
VK_NVX_BINARY_IMPORT_EXTENSION_NAME                          :: "VK_NVX_binary_import"
VK_NVX_BINARY_IMPORT_SPEC_VERSION                            :: 1
VK_NVX_image_view_handle                                     :: 1
VK_NVX_IMAGE_VIEW_HANDLE_EXTENSION_NAME                      :: "VK_NVX_image_view_handle"
VK_NVX_IMAGE_VIEW_HANDLE_SPEC_VERSION                        :: 2
VK_NVX_multiview_per_view_attributes                         :: 1
VK_NVX_MULTIVIEW_PER_VIEW_ATTRIBUTES_EXTENSION_NAME          :: "VK_NVX_multiview_per_view_attributes"
VK_NVX_MULTIVIEW_PER_VIEW_ATTRIBUTES_SPEC_VERSION            :: 1
VK_QCOM_filter_cubic_clamp                                   :: 1
VK_QCOM_FILTER_CUBIC_CLAMP_EXTENSION_NAME                    :: "VK_QCOM_filter_cubic_clamp"
VK_QCOM_FILTER_CUBIC_CLAMP_SPEC_VERSION                      :: 1
VK_QCOM_filter_cubic_weights                                 :: 1
VK_QCOM_FILTER_CUBIC_WEIGHTS_EXTENSION_NAME                  :: "VK_QCOM_filter_cubic_weights"
VK_QCOM_FILTER_CUBIC_WEIGHTS_SPEC_VERSION                    :: 1
VK_QCOM_fragment_density_map_offset                          :: 1
VK_QCOM_FRAGMENT_DENSITY_MAP_OFFSET_EXTENSION_NAME           :: "VK_QCOM_fragment_density_map_offset"
VK_QCOM_FRAGMENT_DENSITY_MAP_OFFSET_SPEC_VERSION             :: 1
VK_QCOM_image_processing                                     :: 1
VK_QCOM_IMAGE_PROCESSING_2_EXTENSION_NAME                    :: "VK_QCOM_image_processing2"
VK_QCOM_IMAGE_PROCESSING_2_SPEC_VERSION                      :: 1
VK_QCOM_IMAGE_PROCESSING_EXTENSION_NAME                      :: "VK_QCOM_image_processing"
VK_QCOM_IMAGE_PROCESSING_SPEC_VERSION                        :: 1
VK_QCOM_image_processing2                                    :: 1
VK_QCOM_multiview_per_view_render_areas                      :: 1
VK_QCOM_MULTIVIEW_PER_VIEW_RENDER_AREAS_EXTENSION_NAME       :: "VK_QCOM_multiview_per_view_render_areas"
VK_QCOM_MULTIVIEW_PER_VIEW_RENDER_AREAS_SPEC_VERSION         :: 1
VK_QCOM_multiview_per_view_viewports                         :: 1
VK_QCOM_MULTIVIEW_PER_VIEW_VIEWPORTS_EXTENSION_NAME          :: "VK_QCOM_multiview_per_view_viewports"
VK_QCOM_MULTIVIEW_PER_VIEW_VIEWPORTS_SPEC_VERSION            :: 1
VK_QCOM_render_pass_shader_resolve                           :: 1
VK_QCOM_RENDER_PASS_SHADER_RESOLVE_EXTENSION_NAME            :: "VK_QCOM_render_pass_shader_resolve"
VK_QCOM_RENDER_PASS_SHADER_RESOLVE_SPEC_VERSION              :: 4
VK_QCOM_render_pass_store_ops                                :: 1
VK_QCOM_RENDER_PASS_STORE_OPS_EXTENSION_NAME                 :: "VK_QCOM_render_pass_store_ops"
VK_QCOM_RENDER_PASS_STORE_OPS_SPEC_VERSION                   :: 2
VK_QCOM_render_pass_transform                                :: 1
VK_QCOM_RENDER_PASS_TRANSFORM_EXTENSION_NAME                 :: "VK_QCOM_render_pass_transform"
VK_QCOM_RENDER_PASS_TRANSFORM_SPEC_VERSION                   :: 4
VK_QCOM_rotated_copy_commands                                :: 1
VK_QCOM_ROTATED_COPY_COMMANDS_EXTENSION_NAME                 :: "VK_QCOM_rotated_copy_commands"
VK_QCOM_ROTATED_COPY_COMMANDS_SPEC_VERSION                   :: 2
VK_QCOM_tile_properties                                      :: 1
VK_QCOM_TILE_PROPERTIES_EXTENSION_NAME                       :: "VK_QCOM_tile_properties"
VK_QCOM_TILE_PROPERTIES_SPEC_VERSION                         :: 1
VK_QCOM_ycbcr_degamma                                        :: 1
VK_QCOM_YCBCR_DEGAMMA_EXTENSION_NAME                         :: "VK_QCOM_ycbcr_degamma"
VK_QCOM_YCBCR_DEGAMMA_SPEC_VERSION                           :: 1
VK_QUEUE_FAMILY_EXTERNAL_KHR                                 :: VK_QUEUE_FAMILY_EXTERNAL
VK_QUEUE_FAMILY_FOREIGN_EXT                                  :: ~2
VK_REMAINING_3D_SLICES_EXT                                   :: ~0
VK_SEC_amigo_profiling                                       :: 1
VK_SEC_AMIGO_PROFILING_EXTENSION_NAME                        :: "VK_SEC_amigo_profiling"
VK_SEC_AMIGO_PROFILING_SPEC_VERSION                          :: 1
VK_SHADER_UNUSED_KHR                                         :: ~0
VK_SHADER_UNUSED_NV                                          :: VK_SHADER_UNUSED_KHR
VK_VALVE_descriptor_set_host_mapping                         :: 1
VK_VALVE_DESCRIPTOR_SET_HOST_MAPPING_EXTENSION_NAME          :: "VK_VALVE_descriptor_set_host_mapping"
VK_VALVE_DESCRIPTOR_SET_HOST_MAPPING_SPEC_VERSION            :: 1
VK_VALVE_mutable_descriptor_type                             :: 1
VK_VALVE_MUTABLE_DESCRIPTOR_TYPE_EXTENSION_NAME              :: "VK_VALVE_mutable_descriptor_type"
VK_VALVE_MUTABLE_DESCRIPTOR_TYPE_SPEC_VERSION                :: 1

// Bit flags
VK_ACCELERATION_STRUCTURE_CREATE_DEVICE_ADDRESS_CAPTURE_REPLAY_BIT_KHR    : VkAccelerationStructureCreateFlagBitsKHR : 0x00000001
VK_ACCELERATION_STRUCTURE_CREATE_DESCRIPTOR_BUFFER_CAPTURE_REPLAY_BIT_EXT : VkAccelerationStructureCreateFlagBitsKHR : 0x00000008
VK_ACCELERATION_STRUCTURE_CREATE_MOTION_BIT_NV                            : VkAccelerationStructureCreateFlagBitsKHR : 0x00000004
VK_ACCELERATION_STRUCTURE_CREATE_FLAG_BITS_MAX_ENUM_KHR                   : VkAccelerationStructureCreateFlagBitsKHR : 0x7FFFFFFF

VK_ACCESS_INDIRECT_COMMAND_READ_BIT                     : VkAccessFlagBits : 0x00000001
VK_ACCESS_INDEX_READ_BIT                                : VkAccessFlagBits : 0x00000002
VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT                     : VkAccessFlagBits : 0x00000004
VK_ACCESS_UNIFORM_READ_BIT                              : VkAccessFlagBits : 0x00000008
VK_ACCESS_INPUT_ATTACHMENT_READ_BIT                     : VkAccessFlagBits : 0x00000010
VK_ACCESS_SHADER_READ_BIT                               : VkAccessFlagBits : 0x00000020
VK_ACCESS_SHADER_WRITE_BIT                              : VkAccessFlagBits : 0x00000040
VK_ACCESS_COLOR_ATTACHMENT_READ_BIT                     : VkAccessFlagBits : 0x00000080
VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT                    : VkAccessFlagBits : 0x00000100
VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT             : VkAccessFlagBits : 0x00000200
VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT            : VkAccessFlagBits : 0x00000400
VK_ACCESS_TRANSFER_READ_BIT                             : VkAccessFlagBits : 0x00000800
VK_ACCESS_TRANSFER_WRITE_BIT                            : VkAccessFlagBits : 0x00001000
VK_ACCESS_HOST_READ_BIT                                 : VkAccessFlagBits : 0x00002000
VK_ACCESS_HOST_WRITE_BIT                                : VkAccessFlagBits : 0x00004000
VK_ACCESS_MEMORY_READ_BIT                               : VkAccessFlagBits : 0x00008000
VK_ACCESS_MEMORY_WRITE_BIT                              : VkAccessFlagBits : 0x00010000
VK_ACCESS_NONE                                          : VkAccessFlagBits : 0
VK_ACCESS_TRANSFORM_FEEDBACK_WRITE_BIT_EXT              : VkAccessFlagBits : 0x02000000
VK_ACCESS_TRANSFORM_FEEDBACK_COUNTER_READ_BIT_EXT       : VkAccessFlagBits : 0x04000000
VK_ACCESS_TRANSFORM_FEEDBACK_COUNTER_WRITE_BIT_EXT      : VkAccessFlagBits : 0x08000000
VK_ACCESS_CONDITIONAL_RENDERING_READ_BIT_EXT            : VkAccessFlagBits : 0x00100000
VK_ACCESS_COLOR_ATTACHMENT_READ_NONCOHERENT_BIT_EXT     : VkAccessFlagBits : 0x00080000
VK_ACCESS_ACCELERATION_STRUCTURE_READ_BIT_KHR           : VkAccessFlagBits : 0x00200000
VK_ACCESS_ACCELERATION_STRUCTURE_WRITE_BIT_KHR          : VkAccessFlagBits : 0x00400000
VK_ACCESS_FRAGMENT_DENSITY_MAP_READ_BIT_EXT             : VkAccessFlagBits : 0x01000000
VK_ACCESS_FRAGMENT_SHADING_RATE_ATTACHMENT_READ_BIT_KHR : VkAccessFlagBits : 0x00800000
VK_ACCESS_COMMAND_PREPROCESS_READ_BIT_NV                : VkAccessFlagBits : 0x00020000
VK_ACCESS_COMMAND_PREPROCESS_WRITE_BIT_NV               : VkAccessFlagBits : 0x00040000
VK_ACCESS_SHADING_RATE_IMAGE_READ_BIT_NV                : VkAccessFlagBits : VK_ACCESS_FRAGMENT_SHADING_RATE_ATTACHMENT_READ_BIT_KHR
VK_ACCESS_ACCELERATION_STRUCTURE_READ_BIT_NV            : VkAccessFlagBits : VK_ACCESS_ACCELERATION_STRUCTURE_READ_BIT_KHR
VK_ACCESS_ACCELERATION_STRUCTURE_WRITE_BIT_NV           : VkAccessFlagBits : VK_ACCESS_ACCELERATION_STRUCTURE_WRITE_BIT_KHR
VK_ACCESS_NONE_KHR                                      : VkAccessFlagBits : VK_ACCESS_NONE
VK_ACCESS_FLAG_BITS_MAX_ENUM                            : VkAccessFlagBits : 0x7FFFFFFF

VK_ACQUIRE_PROFILING_LOCK_FLAG_BITS_MAX_ENUM_KHR : VkAcquireProfilingLockFlagBitsKHR : 0x7FFFFFFF

VK_ATTACHMENT_DESCRIPTION_MAY_ALIAS_BIT      : VkAttachmentDescriptionFlagBits : 0x00000001
VK_ATTACHMENT_DESCRIPTION_FLAG_BITS_MAX_ENUM : VkAttachmentDescriptionFlagBits : 0x7FFFFFFF

VK_BUFFER_CREATE_SPARSE_BINDING_BIT                       : VkBufferCreateFlagBits : 0x00000001
VK_BUFFER_CREATE_SPARSE_RESIDENCY_BIT                     : VkBufferCreateFlagBits : 0x00000002
VK_BUFFER_CREATE_SPARSE_ALIASED_BIT                       : VkBufferCreateFlagBits : 0x00000004
VK_BUFFER_CREATE_PROTECTED_BIT                            : VkBufferCreateFlagBits : 0x00000008
VK_BUFFER_CREATE_DEVICE_ADDRESS_CAPTURE_REPLAY_BIT        : VkBufferCreateFlagBits : 0x00000010
VK_BUFFER_CREATE_DESCRIPTOR_BUFFER_CAPTURE_REPLAY_BIT_EXT : VkBufferCreateFlagBits : 0x00000020
VK_BUFFER_CREATE_VIDEO_PROFILE_INDEPENDENT_BIT_KHR        : VkBufferCreateFlagBits : 0x00000040
VK_BUFFER_CREATE_DEVICE_ADDRESS_CAPTURE_REPLAY_BIT_EXT    : VkBufferCreateFlagBits : VK_BUFFER_CREATE_DEVICE_ADDRESS_CAPTURE_REPLAY_BIT
VK_BUFFER_CREATE_DEVICE_ADDRESS_CAPTURE_REPLAY_BIT_KHR    : VkBufferCreateFlagBits : VK_BUFFER_CREATE_DEVICE_ADDRESS_CAPTURE_REPLAY_BIT
VK_BUFFER_CREATE_FLAG_BITS_MAX_ENUM                       : VkBufferCreateFlagBits : 0x7FFFFFFF

VK_BUFFER_USAGE_TRANSFER_SRC_BIT                                     : VkBufferUsageFlagBits : 0x00000001
VK_BUFFER_USAGE_TRANSFER_DST_BIT                                     : VkBufferUsageFlagBits : 0x00000002
VK_BUFFER_USAGE_UNIFORM_TEXEL_BUFFER_BIT                             : VkBufferUsageFlagBits : 0x00000004
VK_BUFFER_USAGE_STORAGE_TEXEL_BUFFER_BIT                             : VkBufferUsageFlagBits : 0x00000008
VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT                                   : VkBufferUsageFlagBits : 0x00000010
VK_BUFFER_USAGE_STORAGE_BUFFER_BIT                                   : VkBufferUsageFlagBits : 0x00000020
VK_BUFFER_USAGE_INDEX_BUFFER_BIT                                     : VkBufferUsageFlagBits : 0x00000040
VK_BUFFER_USAGE_VERTEX_BUFFER_BIT                                    : VkBufferUsageFlagBits : 0x00000080
VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT                                  : VkBufferUsageFlagBits : 0x00000100
VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT                            : VkBufferUsageFlagBits : 0x00020000
VK_BUFFER_USAGE_VIDEO_DECODE_SRC_BIT_KHR                             : VkBufferUsageFlagBits : 0x00002000
VK_BUFFER_USAGE_VIDEO_DECODE_DST_BIT_KHR                             : VkBufferUsageFlagBits : 0x00004000
VK_BUFFER_USAGE_TRANSFORM_FEEDBACK_BUFFER_BIT_EXT                    : VkBufferUsageFlagBits : 0x00000800
VK_BUFFER_USAGE_TRANSFORM_FEEDBACK_COUNTER_BUFFER_BIT_EXT            : VkBufferUsageFlagBits : 0x00001000
VK_BUFFER_USAGE_CONDITIONAL_RENDERING_BIT_EXT                        : VkBufferUsageFlagBits : 0x00000200
VK_BUFFER_USAGE_EXECUTION_GRAPH_SCRATCH_BIT_AMDX                     : VkBufferUsageFlagBits : 0x02000000
VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT_KHR : VkBufferUsageFlagBits : 0x00080000
VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_STORAGE_BIT_KHR               : VkBufferUsageFlagBits : 0x00100000
VK_BUFFER_USAGE_SHADER_BINDING_TABLE_BIT_KHR                         : VkBufferUsageFlagBits : 0x00000400
VK_BUFFER_USAGE_VIDEO_ENCODE_DST_BIT_KHR                             : VkBufferUsageFlagBits : 0x00008000
VK_BUFFER_USAGE_VIDEO_ENCODE_SRC_BIT_KHR                             : VkBufferUsageFlagBits : 0x00010000
VK_BUFFER_USAGE_SAMPLER_DESCRIPTOR_BUFFER_BIT_EXT                    : VkBufferUsageFlagBits : 0x00200000
VK_BUFFER_USAGE_RESOURCE_DESCRIPTOR_BUFFER_BIT_EXT                   : VkBufferUsageFlagBits : 0x00400000
VK_BUFFER_USAGE_PUSH_DESCRIPTORS_DESCRIPTOR_BUFFER_BIT_EXT           : VkBufferUsageFlagBits : 0x04000000
VK_BUFFER_USAGE_MICROMAP_BUILD_INPUT_READ_ONLY_BIT_EXT               : VkBufferUsageFlagBits : 0x00800000
VK_BUFFER_USAGE_MICROMAP_STORAGE_BIT_EXT                             : VkBufferUsageFlagBits : 0x01000000
VK_BUFFER_USAGE_RAY_TRACING_BIT_NV                                   : VkBufferUsageFlagBits : VK_BUFFER_USAGE_SHADER_BINDING_TABLE_BIT_KHR
VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT_EXT                        : VkBufferUsageFlagBits : VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT
VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT_KHR                        : VkBufferUsageFlagBits : VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT
VK_BUFFER_USAGE_FLAG_BITS_MAX_ENUM                                   : VkBufferUsageFlagBits : 0x7FFFFFFF

VK_BUILD_ACCELERATION_STRUCTURE_ALLOW_UPDATE_BIT_KHR                   : VkBuildAccelerationStructureFlagBitsKHR : 0x00000001
VK_BUILD_ACCELERATION_STRUCTURE_ALLOW_COMPACTION_BIT_KHR               : VkBuildAccelerationStructureFlagBitsKHR : 0x00000002
VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT_KHR              : VkBuildAccelerationStructureFlagBitsKHR : 0x00000004
VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_BUILD_BIT_KHR              : VkBuildAccelerationStructureFlagBitsKHR : 0x00000008
VK_BUILD_ACCELERATION_STRUCTURE_LOW_MEMORY_BIT_KHR                     : VkBuildAccelerationStructureFlagBitsKHR : 0x00000010
VK_BUILD_ACCELERATION_STRUCTURE_MOTION_BIT_NV                          : VkBuildAccelerationStructureFlagBitsKHR : 0x00000020
VK_BUILD_ACCELERATION_STRUCTURE_ALLOW_OPACITY_MICROMAP_UPDATE_EXT      : VkBuildAccelerationStructureFlagBitsKHR : 0x00000040
VK_BUILD_ACCELERATION_STRUCTURE_ALLOW_DISABLE_OPACITY_MICROMAPS_EXT    : VkBuildAccelerationStructureFlagBitsKHR : 0x00000080
VK_BUILD_ACCELERATION_STRUCTURE_ALLOW_OPACITY_MICROMAP_DATA_UPDATE_EXT : VkBuildAccelerationStructureFlagBitsKHR : 0x00000100
VK_BUILD_ACCELERATION_STRUCTURE_ALLOW_DISPLACEMENT_MICROMAP_UPDATE_NV  : VkBuildAccelerationStructureFlagBitsKHR : 0x00000200
VK_BUILD_ACCELERATION_STRUCTURE_ALLOW_DATA_ACCESS_KHR                  : VkBuildAccelerationStructureFlagBitsKHR : 0x00000800
VK_BUILD_ACCELERATION_STRUCTURE_ALLOW_UPDATE_BIT_NV                    : VkBuildAccelerationStructureFlagBitsKHR : VK_BUILD_ACCELERATION_STRUCTURE_ALLOW_UPDATE_BIT_KHR
VK_BUILD_ACCELERATION_STRUCTURE_ALLOW_COMPACTION_BIT_NV                : VkBuildAccelerationStructureFlagBitsKHR : VK_BUILD_ACCELERATION_STRUCTURE_ALLOW_COMPACTION_BIT_KHR
VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT_NV               : VkBuildAccelerationStructureFlagBitsKHR : VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT_KHR
VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_BUILD_BIT_NV               : VkBuildAccelerationStructureFlagBitsKHR : VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_BUILD_BIT_KHR
VK_BUILD_ACCELERATION_STRUCTURE_LOW_MEMORY_BIT_NV                      : VkBuildAccelerationStructureFlagBitsKHR : VK_BUILD_ACCELERATION_STRUCTURE_LOW_MEMORY_BIT_KHR
VK_BUILD_ACCELERATION_STRUCTURE_FLAG_BITS_MAX_ENUM_KHR                 : VkBuildAccelerationStructureFlagBitsKHR : 0x7FFFFFFF

VK_BUILD_MICROMAP_PREFER_FAST_TRACE_BIT_EXT : VkBuildMicromapFlagBitsEXT : 0x00000001
VK_BUILD_MICROMAP_PREFER_FAST_BUILD_BIT_EXT : VkBuildMicromapFlagBitsEXT : 0x00000002
VK_BUILD_MICROMAP_ALLOW_COMPACTION_BIT_EXT  : VkBuildMicromapFlagBitsEXT : 0x00000004
VK_BUILD_MICROMAP_FLAG_BITS_MAX_ENUM_EXT    : VkBuildMicromapFlagBitsEXT : 0x7FFFFFFF

VK_COLOR_COMPONENT_R_BIT              : VkColorComponentFlagBits : 0x00000001
VK_COLOR_COMPONENT_G_BIT              : VkColorComponentFlagBits : 0x00000002
VK_COLOR_COMPONENT_B_BIT              : VkColorComponentFlagBits : 0x00000004
VK_COLOR_COMPONENT_A_BIT              : VkColorComponentFlagBits : 0x00000008
VK_COLOR_COMPONENT_FLAG_BITS_MAX_ENUM : VkColorComponentFlagBits : 0x7FFFFFFF

VK_COMMAND_BUFFER_RESET_RELEASE_RESOURCES_BIT : VkCommandBufferResetFlagBits : 0x00000001
VK_COMMAND_BUFFER_RESET_FLAG_BITS_MAX_ENUM    : VkCommandBufferResetFlagBits : 0x7FFFFFFF

VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT      : VkCommandBufferUsageFlagBits : 0x00000001
VK_COMMAND_BUFFER_USAGE_RENDER_PASS_CONTINUE_BIT : VkCommandBufferUsageFlagBits : 0x00000002
VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT     : VkCommandBufferUsageFlagBits : 0x00000004
VK_COMMAND_BUFFER_USAGE_FLAG_BITS_MAX_ENUM       : VkCommandBufferUsageFlagBits : 0x7FFFFFFF

VK_COMMAND_POOL_CREATE_TRANSIENT_BIT            : VkCommandPoolCreateFlagBits : 0x00000001
VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT : VkCommandPoolCreateFlagBits : 0x00000002
VK_COMMAND_POOL_CREATE_PROTECTED_BIT            : VkCommandPoolCreateFlagBits : 0x00000004
VK_COMMAND_POOL_CREATE_FLAG_BITS_MAX_ENUM       : VkCommandPoolCreateFlagBits : 0x7FFFFFFF

VK_COMMAND_POOL_RESET_RELEASE_RESOURCES_BIT : VkCommandPoolResetFlagBits : 0x00000001
VK_COMMAND_POOL_RESET_FLAG_BITS_MAX_ENUM    : VkCommandPoolResetFlagBits : 0x7FFFFFFF

VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR          : VkCompositeAlphaFlagBitsKHR : 0x00000001
VK_COMPOSITE_ALPHA_PRE_MULTIPLIED_BIT_KHR  : VkCompositeAlphaFlagBitsKHR : 0x00000002
VK_COMPOSITE_ALPHA_POST_MULTIPLIED_BIT_KHR : VkCompositeAlphaFlagBitsKHR : 0x00000004
VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR         : VkCompositeAlphaFlagBitsKHR : 0x00000008
VK_COMPOSITE_ALPHA_FLAG_BITS_MAX_ENUM_KHR  : VkCompositeAlphaFlagBitsKHR : 0x7FFFFFFF

VK_CONDITIONAL_RENDERING_INVERTED_BIT_EXT       : VkConditionalRenderingFlagBitsEXT : 0x00000001
VK_CONDITIONAL_RENDERING_FLAG_BITS_MAX_ENUM_EXT : VkConditionalRenderingFlagBitsEXT : 0x7FFFFFFF

VK_CULL_MODE_NONE               : VkCullModeFlagBits : 0
VK_CULL_MODE_FRONT_BIT          : VkCullModeFlagBits : 0x00000001
VK_CULL_MODE_BACK_BIT           : VkCullModeFlagBits : 0x00000002
VK_CULL_MODE_FRONT_AND_BACK     : VkCullModeFlagBits : 0x00000003
VK_CULL_MODE_FLAG_BITS_MAX_ENUM : VkCullModeFlagBits : 0x7FFFFFFF

VK_DEBUG_REPORT_INFORMATION_BIT_EXT         : VkDebugReportFlagBitsEXT : 0x00000001
VK_DEBUG_REPORT_WARNING_BIT_EXT             : VkDebugReportFlagBitsEXT : 0x00000002
VK_DEBUG_REPORT_PERFORMANCE_WARNING_BIT_EXT : VkDebugReportFlagBitsEXT : 0x00000004
VK_DEBUG_REPORT_ERROR_BIT_EXT               : VkDebugReportFlagBitsEXT : 0x00000008
VK_DEBUG_REPORT_DEBUG_BIT_EXT               : VkDebugReportFlagBitsEXT : 0x00000010
VK_DEBUG_REPORT_FLAG_BITS_MAX_ENUM_EXT      : VkDebugReportFlagBitsEXT : 0x7FFFFFFF

VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT        : VkDebugUtilsMessageSeverityFlagBitsEXT : 0x00000001
VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT           : VkDebugUtilsMessageSeverityFlagBitsEXT : 0x00000010
VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT        : VkDebugUtilsMessageSeverityFlagBitsEXT : 0x00000100
VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT          : VkDebugUtilsMessageSeverityFlagBitsEXT : 0x00001000
VK_DEBUG_UTILS_MESSAGE_SEVERITY_FLAG_BITS_MAX_ENUM_EXT : VkDebugUtilsMessageSeverityFlagBitsEXT : 0x7FFFFFFF

VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT                : VkDebugUtilsMessageTypeFlagBitsEXT : 0x00000001
VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT             : VkDebugUtilsMessageTypeFlagBitsEXT : 0x00000002
VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT            : VkDebugUtilsMessageTypeFlagBitsEXT : 0x00000004
VK_DEBUG_UTILS_MESSAGE_TYPE_DEVICE_ADDRESS_BINDING_BIT_EXT : VkDebugUtilsMessageTypeFlagBitsEXT : 0x00000008
VK_DEBUG_UTILS_MESSAGE_TYPE_FLAG_BITS_MAX_ENUM_EXT         : VkDebugUtilsMessageTypeFlagBitsEXT : 0x7FFFFFFF

VK_DEPENDENCY_BY_REGION_BIT         : VkDependencyFlagBits : 0x00000001
VK_DEPENDENCY_DEVICE_GROUP_BIT      : VkDependencyFlagBits : 0x00000004
VK_DEPENDENCY_VIEW_LOCAL_BIT        : VkDependencyFlagBits : 0x00000002
VK_DEPENDENCY_FEEDBACK_LOOP_BIT_EXT : VkDependencyFlagBits : 0x00000008
VK_DEPENDENCY_VIEW_LOCAL_BIT_KHR    : VkDependencyFlagBits : VK_DEPENDENCY_VIEW_LOCAL_BIT
VK_DEPENDENCY_DEVICE_GROUP_BIT_KHR  : VkDependencyFlagBits : VK_DEPENDENCY_DEVICE_GROUP_BIT
VK_DEPENDENCY_FLAG_BITS_MAX_ENUM    : VkDependencyFlagBits : 0x7FFFFFFF

VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT               : VkDescriptorBindingFlagBits : 0x00000001
VK_DESCRIPTOR_BINDING_UPDATE_UNUSED_WHILE_PENDING_BIT     : VkDescriptorBindingFlagBits : 0x00000002
VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT                 : VkDescriptorBindingFlagBits : 0x00000004
VK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT       : VkDescriptorBindingFlagBits : 0x00000008
VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT_EXT           : VkDescriptorBindingFlagBits : VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT
VK_DESCRIPTOR_BINDING_UPDATE_UNUSED_WHILE_PENDING_BIT_EXT : VkDescriptorBindingFlagBits : VK_DESCRIPTOR_BINDING_UPDATE_UNUSED_WHILE_PENDING_BIT
VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT_EXT             : VkDescriptorBindingFlagBits : VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT
VK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT_EXT   : VkDescriptorBindingFlagBits : VK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT
VK_DESCRIPTOR_BINDING_FLAG_BITS_MAX_ENUM                  : VkDescriptorBindingFlagBits : 0x7FFFFFFF

VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT           : VkDescriptorPoolCreateFlagBits : 0x00000001
VK_DESCRIPTOR_POOL_CREATE_UPDATE_AFTER_BIND_BIT             : VkDescriptorPoolCreateFlagBits : 0x00000002
VK_DESCRIPTOR_POOL_CREATE_HOST_ONLY_BIT_EXT                 : VkDescriptorPoolCreateFlagBits : 0x00000004
VK_DESCRIPTOR_POOL_CREATE_ALLOW_OVERALLOCATION_SETS_BIT_NV  : VkDescriptorPoolCreateFlagBits : 0x00000008
VK_DESCRIPTOR_POOL_CREATE_ALLOW_OVERALLOCATION_POOLS_BIT_NV : VkDescriptorPoolCreateFlagBits : 0x00000010
VK_DESCRIPTOR_POOL_CREATE_UPDATE_AFTER_BIND_BIT_EXT         : VkDescriptorPoolCreateFlagBits : VK_DESCRIPTOR_POOL_CREATE_UPDATE_AFTER_BIND_BIT
VK_DESCRIPTOR_POOL_CREATE_HOST_ONLY_BIT_VALVE               : VkDescriptorPoolCreateFlagBits : VK_DESCRIPTOR_POOL_CREATE_HOST_ONLY_BIT_EXT
VK_DESCRIPTOR_POOL_CREATE_FLAG_BITS_MAX_ENUM                : VkDescriptorPoolCreateFlagBits : 0x7FFFFFFF

VK_DESCRIPTOR_SET_LAYOUT_CREATE_UPDATE_AFTER_BIND_POOL_BIT          : VkDescriptorSetLayoutCreateFlagBits : 0x00000002
VK_DESCRIPTOR_SET_LAYOUT_CREATE_PUSH_DESCRIPTOR_BIT_KHR             : VkDescriptorSetLayoutCreateFlagBits : 0x00000001
VK_DESCRIPTOR_SET_LAYOUT_CREATE_DESCRIPTOR_BUFFER_BIT_EXT           : VkDescriptorSetLayoutCreateFlagBits : 0x00000010
VK_DESCRIPTOR_SET_LAYOUT_CREATE_EMBEDDED_IMMUTABLE_SAMPLERS_BIT_EXT : VkDescriptorSetLayoutCreateFlagBits : 0x00000020
VK_DESCRIPTOR_SET_LAYOUT_CREATE_INDIRECT_BINDABLE_BIT_NV            : VkDescriptorSetLayoutCreateFlagBits : 0x00000080
VK_DESCRIPTOR_SET_LAYOUT_CREATE_HOST_ONLY_POOL_BIT_EXT              : VkDescriptorSetLayoutCreateFlagBits : 0x00000004
VK_DESCRIPTOR_SET_LAYOUT_CREATE_PER_STAGE_BIT_NV                    : VkDescriptorSetLayoutCreateFlagBits : 0x00000040
VK_DESCRIPTOR_SET_LAYOUT_CREATE_UPDATE_AFTER_BIND_POOL_BIT_EXT      : VkDescriptorSetLayoutCreateFlagBits : VK_DESCRIPTOR_SET_LAYOUT_CREATE_UPDATE_AFTER_BIND_POOL_BIT
VK_DESCRIPTOR_SET_LAYOUT_CREATE_HOST_ONLY_POOL_BIT_VALVE            : VkDescriptorSetLayoutCreateFlagBits : VK_DESCRIPTOR_SET_LAYOUT_CREATE_HOST_ONLY_POOL_BIT_EXT
VK_DESCRIPTOR_SET_LAYOUT_CREATE_FLAG_BITS_MAX_ENUM                  : VkDescriptorSetLayoutCreateFlagBits : 0x7FFFFFFF

VK_DEVICE_ADDRESS_BINDING_INTERNAL_OBJECT_BIT_EXT : VkDeviceAddressBindingFlagBitsEXT : 0x00000001
VK_DEVICE_ADDRESS_BINDING_FLAG_BITS_MAX_ENUM_EXT  : VkDeviceAddressBindingFlagBitsEXT : 0x7FFFFFFF

VK_DEVICE_DIAGNOSTICS_CONFIG_ENABLE_SHADER_DEBUG_INFO_BIT_NV      : VkDeviceDiagnosticsConfigFlagBitsNV : 0x00000001
VK_DEVICE_DIAGNOSTICS_CONFIG_ENABLE_RESOURCE_TRACKING_BIT_NV      : VkDeviceDiagnosticsConfigFlagBitsNV : 0x00000002
VK_DEVICE_DIAGNOSTICS_CONFIG_ENABLE_AUTOMATIC_CHECKPOINTS_BIT_NV  : VkDeviceDiagnosticsConfigFlagBitsNV : 0x00000004
VK_DEVICE_DIAGNOSTICS_CONFIG_ENABLE_SHADER_ERROR_REPORTING_BIT_NV : VkDeviceDiagnosticsConfigFlagBitsNV : 0x00000008
VK_DEVICE_DIAGNOSTICS_CONFIG_FLAG_BITS_MAX_ENUM_NV                : VkDeviceDiagnosticsConfigFlagBitsNV : 0x7FFFFFFF

VK_DEVICE_GROUP_PRESENT_MODE_LOCAL_BIT_KHR              : VkDeviceGroupPresentModeFlagBitsKHR : 0x00000001
VK_DEVICE_GROUP_PRESENT_MODE_REMOTE_BIT_KHR             : VkDeviceGroupPresentModeFlagBitsKHR : 0x00000002
VK_DEVICE_GROUP_PRESENT_MODE_SUM_BIT_KHR                : VkDeviceGroupPresentModeFlagBitsKHR : 0x00000004
VK_DEVICE_GROUP_PRESENT_MODE_LOCAL_MULTI_DEVICE_BIT_KHR : VkDeviceGroupPresentModeFlagBitsKHR : 0x00000008
VK_DEVICE_GROUP_PRESENT_MODE_FLAG_BITS_MAX_ENUM_KHR     : VkDeviceGroupPresentModeFlagBitsKHR : 0x7FFFFFFF

VK_DEVICE_QUEUE_CREATE_PROTECTED_BIT      : VkDeviceQueueCreateFlagBits : 0x00000001
VK_DEVICE_QUEUE_CREATE_FLAG_BITS_MAX_ENUM : VkDeviceQueueCreateFlagBits : 0x7FFFFFFF

VK_DISPLAY_PLANE_ALPHA_OPAQUE_BIT_KHR                  : VkDisplayPlaneAlphaFlagBitsKHR : 0x00000001
VK_DISPLAY_PLANE_ALPHA_GLOBAL_BIT_KHR                  : VkDisplayPlaneAlphaFlagBitsKHR : 0x00000002
VK_DISPLAY_PLANE_ALPHA_PER_PIXEL_BIT_KHR               : VkDisplayPlaneAlphaFlagBitsKHR : 0x00000004
VK_DISPLAY_PLANE_ALPHA_PER_PIXEL_PREMULTIPLIED_BIT_KHR : VkDisplayPlaneAlphaFlagBitsKHR : 0x00000008
VK_DISPLAY_PLANE_ALPHA_FLAG_BITS_MAX_ENUM_KHR          : VkDisplayPlaneAlphaFlagBitsKHR : 0x7FFFFFFF

VK_EVENT_CREATE_DEVICE_ONLY_BIT     : VkEventCreateFlagBits : 0x00000001
VK_EVENT_CREATE_DEVICE_ONLY_BIT_KHR : VkEventCreateFlagBits : VK_EVENT_CREATE_DEVICE_ONLY_BIT
VK_EVENT_CREATE_FLAG_BITS_MAX_ENUM  : VkEventCreateFlagBits : 0x7FFFFFFF

VK_EXTERNAL_FENCE_FEATURE_EXPORTABLE_BIT     : VkExternalFenceFeatureFlagBits : 0x00000001
VK_EXTERNAL_FENCE_FEATURE_IMPORTABLE_BIT     : VkExternalFenceFeatureFlagBits : 0x00000002
VK_EXTERNAL_FENCE_FEATURE_EXPORTABLE_BIT_KHR : VkExternalFenceFeatureFlagBits : VK_EXTERNAL_FENCE_FEATURE_EXPORTABLE_BIT
VK_EXTERNAL_FENCE_FEATURE_IMPORTABLE_BIT_KHR : VkExternalFenceFeatureFlagBits : VK_EXTERNAL_FENCE_FEATURE_IMPORTABLE_BIT
VK_EXTERNAL_FENCE_FEATURE_FLAG_BITS_MAX_ENUM : VkExternalFenceFeatureFlagBits : 0x7FFFFFFF

VK_EXTERNAL_FENCE_HANDLE_TYPE_OPAQUE_FD_BIT            : VkExternalFenceHandleTypeFlagBits : 0x00000001
VK_EXTERNAL_FENCE_HANDLE_TYPE_OPAQUE_WIN32_BIT         : VkExternalFenceHandleTypeFlagBits : 0x00000002
VK_EXTERNAL_FENCE_HANDLE_TYPE_OPAQUE_WIN32_KMT_BIT     : VkExternalFenceHandleTypeFlagBits : 0x00000004
VK_EXTERNAL_FENCE_HANDLE_TYPE_SYNC_FD_BIT              : VkExternalFenceHandleTypeFlagBits : 0x00000008
VK_EXTERNAL_FENCE_HANDLE_TYPE_OPAQUE_FD_BIT_KHR        : VkExternalFenceHandleTypeFlagBits : VK_EXTERNAL_FENCE_HANDLE_TYPE_OPAQUE_FD_BIT
VK_EXTERNAL_FENCE_HANDLE_TYPE_OPAQUE_WIN32_BIT_KHR     : VkExternalFenceHandleTypeFlagBits : VK_EXTERNAL_FENCE_HANDLE_TYPE_OPAQUE_WIN32_BIT
VK_EXTERNAL_FENCE_HANDLE_TYPE_OPAQUE_WIN32_KMT_BIT_KHR : VkExternalFenceHandleTypeFlagBits : VK_EXTERNAL_FENCE_HANDLE_TYPE_OPAQUE_WIN32_KMT_BIT
VK_EXTERNAL_FENCE_HANDLE_TYPE_SYNC_FD_BIT_KHR          : VkExternalFenceHandleTypeFlagBits : VK_EXTERNAL_FENCE_HANDLE_TYPE_SYNC_FD_BIT
VK_EXTERNAL_FENCE_HANDLE_TYPE_FLAG_BITS_MAX_ENUM       : VkExternalFenceHandleTypeFlagBits : 0x7FFFFFFF

VK_EXTERNAL_MEMORY_FEATURE_DEDICATED_ONLY_BIT     : VkExternalMemoryFeatureFlagBits : 0x00000001
VK_EXTERNAL_MEMORY_FEATURE_EXPORTABLE_BIT         : VkExternalMemoryFeatureFlagBits : 0x00000002
VK_EXTERNAL_MEMORY_FEATURE_IMPORTABLE_BIT         : VkExternalMemoryFeatureFlagBits : 0x00000004
VK_EXTERNAL_MEMORY_FEATURE_DEDICATED_ONLY_BIT_KHR : VkExternalMemoryFeatureFlagBits : VK_EXTERNAL_MEMORY_FEATURE_DEDICATED_ONLY_BIT
VK_EXTERNAL_MEMORY_FEATURE_EXPORTABLE_BIT_KHR     : VkExternalMemoryFeatureFlagBits : VK_EXTERNAL_MEMORY_FEATURE_EXPORTABLE_BIT
VK_EXTERNAL_MEMORY_FEATURE_IMPORTABLE_BIT_KHR     : VkExternalMemoryFeatureFlagBits : VK_EXTERNAL_MEMORY_FEATURE_IMPORTABLE_BIT
VK_EXTERNAL_MEMORY_FEATURE_FLAG_BITS_MAX_ENUM     : VkExternalMemoryFeatureFlagBits : 0x7FFFFFFF

VK_EXTERNAL_MEMORY_FEATURE_DEDICATED_ONLY_BIT_NV : VkExternalMemoryFeatureFlagBitsNV : 0x00000001
VK_EXTERNAL_MEMORY_FEATURE_EXPORTABLE_BIT_NV     : VkExternalMemoryFeatureFlagBitsNV : 0x00000002
VK_EXTERNAL_MEMORY_FEATURE_IMPORTABLE_BIT_NV     : VkExternalMemoryFeatureFlagBitsNV : 0x00000004
VK_EXTERNAL_MEMORY_FEATURE_FLAG_BITS_MAX_ENUM_NV : VkExternalMemoryFeatureFlagBitsNV : 0x7FFFFFFF

VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_FD_BIT                       : VkExternalMemoryHandleTypeFlagBits : 0x00000001
VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_WIN32_BIT                    : VkExternalMemoryHandleTypeFlagBits : 0x00000002
VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_WIN32_KMT_BIT                : VkExternalMemoryHandleTypeFlagBits : 0x00000004
VK_EXTERNAL_MEMORY_HANDLE_TYPE_D3D11_TEXTURE_BIT                   : VkExternalMemoryHandleTypeFlagBits : 0x00000008
VK_EXTERNAL_MEMORY_HANDLE_TYPE_D3D11_TEXTURE_KMT_BIT               : VkExternalMemoryHandleTypeFlagBits : 0x00000010
VK_EXTERNAL_MEMORY_HANDLE_TYPE_D3D12_HEAP_BIT                      : VkExternalMemoryHandleTypeFlagBits : 0x00000020
VK_EXTERNAL_MEMORY_HANDLE_TYPE_D3D12_RESOURCE_BIT                  : VkExternalMemoryHandleTypeFlagBits : 0x00000040
VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT                     : VkExternalMemoryHandleTypeFlagBits : 0x00000200
VK_EXTERNAL_MEMORY_HANDLE_TYPE_ANDROID_HARDWARE_BUFFER_BIT_ANDROID : VkExternalMemoryHandleTypeFlagBits : 0x00000400
VK_EXTERNAL_MEMORY_HANDLE_TYPE_HOST_ALLOCATION_BIT_EXT             : VkExternalMemoryHandleTypeFlagBits : 0x00000080
VK_EXTERNAL_MEMORY_HANDLE_TYPE_HOST_MAPPED_FOREIGN_MEMORY_BIT_EXT  : VkExternalMemoryHandleTypeFlagBits : 0x00000100
VK_EXTERNAL_MEMORY_HANDLE_TYPE_ZIRCON_VMO_BIT_FUCHSIA              : VkExternalMemoryHandleTypeFlagBits : 0x00000800
VK_EXTERNAL_MEMORY_HANDLE_TYPE_RDMA_ADDRESS_BIT_NV                 : VkExternalMemoryHandleTypeFlagBits : 0x00001000
VK_EXTERNAL_MEMORY_HANDLE_TYPE_SCREEN_BUFFER_BIT_QNX               : VkExternalMemoryHandleTypeFlagBits : 0x00004000
VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_FD_BIT_KHR                   : VkExternalMemoryHandleTypeFlagBits : VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_FD_BIT
VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_WIN32_BIT_KHR                : VkExternalMemoryHandleTypeFlagBits : VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_WIN32_BIT
VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_WIN32_KMT_BIT_KHR            : VkExternalMemoryHandleTypeFlagBits : VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_WIN32_KMT_BIT
VK_EXTERNAL_MEMORY_HANDLE_TYPE_D3D11_TEXTURE_BIT_KHR               : VkExternalMemoryHandleTypeFlagBits : VK_EXTERNAL_MEMORY_HANDLE_TYPE_D3D11_TEXTURE_BIT
VK_EXTERNAL_MEMORY_HANDLE_TYPE_D3D11_TEXTURE_KMT_BIT_KHR           : VkExternalMemoryHandleTypeFlagBits : VK_EXTERNAL_MEMORY_HANDLE_TYPE_D3D11_TEXTURE_KMT_BIT
VK_EXTERNAL_MEMORY_HANDLE_TYPE_D3D12_HEAP_BIT_KHR                  : VkExternalMemoryHandleTypeFlagBits : VK_EXTERNAL_MEMORY_HANDLE_TYPE_D3D12_HEAP_BIT
VK_EXTERNAL_MEMORY_HANDLE_TYPE_D3D12_RESOURCE_BIT_KHR              : VkExternalMemoryHandleTypeFlagBits : VK_EXTERNAL_MEMORY_HANDLE_TYPE_D3D12_RESOURCE_BIT
VK_EXTERNAL_MEMORY_HANDLE_TYPE_FLAG_BITS_MAX_ENUM                  : VkExternalMemoryHandleTypeFlagBits : 0x7FFFFFFF

VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_WIN32_BIT_NV     : VkExternalMemoryHandleTypeFlagBitsNV : 0x00000001
VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_WIN32_KMT_BIT_NV : VkExternalMemoryHandleTypeFlagBitsNV : 0x00000002
VK_EXTERNAL_MEMORY_HANDLE_TYPE_D3D11_IMAGE_BIT_NV      : VkExternalMemoryHandleTypeFlagBitsNV : 0x00000004
VK_EXTERNAL_MEMORY_HANDLE_TYPE_D3D11_IMAGE_KMT_BIT_NV  : VkExternalMemoryHandleTypeFlagBitsNV : 0x00000008
VK_EXTERNAL_MEMORY_HANDLE_TYPE_FLAG_BITS_MAX_ENUM_NV   : VkExternalMemoryHandleTypeFlagBitsNV : 0x7FFFFFFF

VK_EXTERNAL_SEMAPHORE_FEATURE_EXPORTABLE_BIT     : VkExternalSemaphoreFeatureFlagBits : 0x00000001
VK_EXTERNAL_SEMAPHORE_FEATURE_IMPORTABLE_BIT     : VkExternalSemaphoreFeatureFlagBits : 0x00000002
VK_EXTERNAL_SEMAPHORE_FEATURE_EXPORTABLE_BIT_KHR : VkExternalSemaphoreFeatureFlagBits : VK_EXTERNAL_SEMAPHORE_FEATURE_EXPORTABLE_BIT
VK_EXTERNAL_SEMAPHORE_FEATURE_IMPORTABLE_BIT_KHR : VkExternalSemaphoreFeatureFlagBits : VK_EXTERNAL_SEMAPHORE_FEATURE_IMPORTABLE_BIT
VK_EXTERNAL_SEMAPHORE_FEATURE_FLAG_BITS_MAX_ENUM : VkExternalSemaphoreFeatureFlagBits : 0x7FFFFFFF

VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_OPAQUE_FD_BIT            : VkExternalSemaphoreHandleTypeFlagBits : 0x00000001
VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_OPAQUE_WIN32_BIT         : VkExternalSemaphoreHandleTypeFlagBits : 0x00000002
VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_OPAQUE_WIN32_KMT_BIT     : VkExternalSemaphoreHandleTypeFlagBits : 0x00000004
VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_D3D12_FENCE_BIT          : VkExternalSemaphoreHandleTypeFlagBits : 0x00000008
VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_SYNC_FD_BIT              : VkExternalSemaphoreHandleTypeFlagBits : 0x00000010
VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_ZIRCON_EVENT_BIT_FUCHSIA : VkExternalSemaphoreHandleTypeFlagBits : 0x00000080
VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_D3D11_FENCE_BIT          : VkExternalSemaphoreHandleTypeFlagBits : VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_D3D12_FENCE_BIT
VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_OPAQUE_FD_BIT_KHR        : VkExternalSemaphoreHandleTypeFlagBits : VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_OPAQUE_FD_BIT
VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_OPAQUE_WIN32_BIT_KHR     : VkExternalSemaphoreHandleTypeFlagBits : VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_OPAQUE_WIN32_BIT
VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_OPAQUE_WIN32_KMT_BIT_KHR : VkExternalSemaphoreHandleTypeFlagBits : VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_OPAQUE_WIN32_KMT_BIT
VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_D3D12_FENCE_BIT_KHR      : VkExternalSemaphoreHandleTypeFlagBits : VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_D3D12_FENCE_BIT
VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_SYNC_FD_BIT_KHR          : VkExternalSemaphoreHandleTypeFlagBits : VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_SYNC_FD_BIT
VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_FLAG_BITS_MAX_ENUM       : VkExternalSemaphoreHandleTypeFlagBits : 0x7FFFFFFF

VK_FENCE_CREATE_SIGNALED_BIT       : VkFenceCreateFlagBits : 0x00000001
VK_FENCE_CREATE_FLAG_BITS_MAX_ENUM : VkFenceCreateFlagBits : 0x7FFFFFFF

VK_FENCE_IMPORT_TEMPORARY_BIT      : VkFenceImportFlagBits : 0x00000001
VK_FENCE_IMPORT_TEMPORARY_BIT_KHR  : VkFenceImportFlagBits : VK_FENCE_IMPORT_TEMPORARY_BIT
VK_FENCE_IMPORT_FLAG_BITS_MAX_ENUM : VkFenceImportFlagBits : 0x7FFFFFFF

VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT                                                               : VkFormatFeatureFlagBits : 0x00000001
VK_FORMAT_FEATURE_STORAGE_IMAGE_BIT                                                               : VkFormatFeatureFlagBits : 0x00000002
VK_FORMAT_FEATURE_STORAGE_IMAGE_ATOMIC_BIT                                                        : VkFormatFeatureFlagBits : 0x00000004
VK_FORMAT_FEATURE_UNIFORM_TEXEL_BUFFER_BIT                                                        : VkFormatFeatureFlagBits : 0x00000008
VK_FORMAT_FEATURE_STORAGE_TEXEL_BUFFER_BIT                                                        : VkFormatFeatureFlagBits : 0x00000010
VK_FORMAT_FEATURE_STORAGE_TEXEL_BUFFER_ATOMIC_BIT                                                 : VkFormatFeatureFlagBits : 0x00000020
VK_FORMAT_FEATURE_VERTEX_BUFFER_BIT                                                               : VkFormatFeatureFlagBits : 0x00000040
VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BIT                                                            : VkFormatFeatureFlagBits : 0x00000080
VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BLEND_BIT                                                      : VkFormatFeatureFlagBits : 0x00000100
VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT                                                    : VkFormatFeatureFlagBits : 0x00000200
VK_FORMAT_FEATURE_BLIT_SRC_BIT                                                                    : VkFormatFeatureFlagBits : 0x00000400
VK_FORMAT_FEATURE_BLIT_DST_BIT                                                                    : VkFormatFeatureFlagBits : 0x00000800
VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT                                                 : VkFormatFeatureFlagBits : 0x00001000
VK_FORMAT_FEATURE_TRANSFER_SRC_BIT                                                                : VkFormatFeatureFlagBits : 0x00004000
VK_FORMAT_FEATURE_TRANSFER_DST_BIT                                                                : VkFormatFeatureFlagBits : 0x00008000
VK_FORMAT_FEATURE_MIDPOINT_CHROMA_SAMPLES_BIT                                                     : VkFormatFeatureFlagBits : 0x00020000
VK_FORMAT_FEATURE_SAMPLED_IMAGE_YCBCR_CONVERSION_LINEAR_FILTER_BIT                                : VkFormatFeatureFlagBits : 0x00040000
VK_FORMAT_FEATURE_SAMPLED_IMAGE_YCBCR_CONVERSION_SEPARATE_RECONSTRUCTION_FILTER_BIT               : VkFormatFeatureFlagBits : 0x00080000
VK_FORMAT_FEATURE_SAMPLED_IMAGE_YCBCR_CONVERSION_CHROMA_RECONSTRUCTION_EXPLICIT_BIT               : VkFormatFeatureFlagBits : 0x00100000
VK_FORMAT_FEATURE_SAMPLED_IMAGE_YCBCR_CONVERSION_CHROMA_RECONSTRUCTION_EXPLICIT_FORCEABLE_BIT     : VkFormatFeatureFlagBits : 0x00200000
VK_FORMAT_FEATURE_DISJOINT_BIT                                                                    : VkFormatFeatureFlagBits : 0x00400000
VK_FORMAT_FEATURE_COSITED_CHROMA_SAMPLES_BIT                                                      : VkFormatFeatureFlagBits : 0x00800000
VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_MINMAX_BIT                                                 : VkFormatFeatureFlagBits : 0x00010000
VK_FORMAT_FEATURE_VIDEO_DECODE_OUTPUT_BIT_KHR                                                     : VkFormatFeatureFlagBits : 0x02000000
VK_FORMAT_FEATURE_VIDEO_DECODE_DPB_BIT_KHR                                                        : VkFormatFeatureFlagBits : 0x04000000
VK_FORMAT_FEATURE_ACCELERATION_STRUCTURE_VERTEX_BUFFER_BIT_KHR                                    : VkFormatFeatureFlagBits : 0x20000000
VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_CUBIC_BIT_EXT                                              : VkFormatFeatureFlagBits : 0x00002000
VK_FORMAT_FEATURE_FRAGMENT_DENSITY_MAP_BIT_EXT                                                    : VkFormatFeatureFlagBits : 0x01000000
VK_FORMAT_FEATURE_FRAGMENT_SHADING_RATE_ATTACHMENT_BIT_KHR                                        : VkFormatFeatureFlagBits : 0x40000000
VK_FORMAT_FEATURE_VIDEO_ENCODE_INPUT_BIT_KHR                                                      : VkFormatFeatureFlagBits : 0x08000000
VK_FORMAT_FEATURE_VIDEO_ENCODE_DPB_BIT_KHR                                                        : VkFormatFeatureFlagBits : 0x10000000
VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_CUBIC_BIT_IMG                                              : VkFormatFeatureFlagBits : VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_CUBIC_BIT_EXT
VK_FORMAT_FEATURE_TRANSFER_SRC_BIT_KHR                                                            : VkFormatFeatureFlagBits : VK_FORMAT_FEATURE_TRANSFER_SRC_BIT
VK_FORMAT_FEATURE_TRANSFER_DST_BIT_KHR                                                            : VkFormatFeatureFlagBits : VK_FORMAT_FEATURE_TRANSFER_DST_BIT
VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_MINMAX_BIT_EXT                                             : VkFormatFeatureFlagBits : VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_MINMAX_BIT
VK_FORMAT_FEATURE_MIDPOINT_CHROMA_SAMPLES_BIT_KHR                                                 : VkFormatFeatureFlagBits : VK_FORMAT_FEATURE_MIDPOINT_CHROMA_SAMPLES_BIT
VK_FORMAT_FEATURE_SAMPLED_IMAGE_YCBCR_CONVERSION_LINEAR_FILTER_BIT_KHR                            : VkFormatFeatureFlagBits : VK_FORMAT_FEATURE_SAMPLED_IMAGE_YCBCR_CONVERSION_LINEAR_FILTER_BIT
VK_FORMAT_FEATURE_SAMPLED_IMAGE_YCBCR_CONVERSION_SEPARATE_RECONSTRUCTION_FILTER_BIT_KHR           : VkFormatFeatureFlagBits : VK_FORMAT_FEATURE_SAMPLED_IMAGE_YCBCR_CONVERSION_SEPARATE_RECONSTRUCTION_FILTER_BIT
VK_FORMAT_FEATURE_SAMPLED_IMAGE_YCBCR_CONVERSION_CHROMA_RECONSTRUCTION_EXPLICIT_BIT_KHR           : VkFormatFeatureFlagBits : VK_FORMAT_FEATURE_SAMPLED_IMAGE_YCBCR_CONVERSION_CHROMA_RECONSTRUCTION_EXPLICIT_BIT
VK_FORMAT_FEATURE_SAMPLED_IMAGE_YCBCR_CONVERSION_CHROMA_RECONSTRUCTION_EXPLICIT_FORCEABLE_BIT_KHR : VkFormatFeatureFlagBits : VK_FORMAT_FEATURE_SAMPLED_IMAGE_YCBCR_CONVERSION_CHROMA_RECONSTRUCTION_EXPLICIT_FORCEABLE_BIT
VK_FORMAT_FEATURE_DISJOINT_BIT_KHR                                                                : VkFormatFeatureFlagBits : VK_FORMAT_FEATURE_DISJOINT_BIT
VK_FORMAT_FEATURE_COSITED_CHROMA_SAMPLES_BIT_KHR                                                  : VkFormatFeatureFlagBits : VK_FORMAT_FEATURE_COSITED_CHROMA_SAMPLES_BIT
VK_FORMAT_FEATURE_FLAG_BITS_MAX_ENUM                                                              : VkFormatFeatureFlagBits : 0x7FFFFFFF

VK_FRAME_BOUNDARY_FRAME_END_BIT_EXT      : VkFrameBoundaryFlagBitsEXT : 0x00000001
VK_FRAME_BOUNDARY_FLAG_BITS_MAX_ENUM_EXT : VkFrameBoundaryFlagBitsEXT : 0x7FFFFFFF

VK_FRAMEBUFFER_CREATE_IMAGELESS_BIT      : VkFramebufferCreateFlagBits : 0x00000001
VK_FRAMEBUFFER_CREATE_IMAGELESS_BIT_KHR  : VkFramebufferCreateFlagBits : VK_FRAMEBUFFER_CREATE_IMAGELESS_BIT
VK_FRAMEBUFFER_CREATE_FLAG_BITS_MAX_ENUM : VkFramebufferCreateFlagBits : 0x7FFFFFFF

VK_GEOMETRY_OPAQUE_BIT_KHR                          : VkGeometryFlagBitsKHR : 0x00000001
VK_GEOMETRY_NO_DUPLICATE_ANY_HIT_INVOCATION_BIT_KHR : VkGeometryFlagBitsKHR : 0x00000002
VK_GEOMETRY_OPAQUE_BIT_NV                           : VkGeometryFlagBitsKHR : VK_GEOMETRY_OPAQUE_BIT_KHR
VK_GEOMETRY_NO_DUPLICATE_ANY_HIT_INVOCATION_BIT_NV  : VkGeometryFlagBitsKHR : VK_GEOMETRY_NO_DUPLICATE_ANY_HIT_INVOCATION_BIT_KHR
VK_GEOMETRY_FLAG_BITS_MAX_ENUM_KHR                  : VkGeometryFlagBitsKHR : 0x7FFFFFFF

VK_GEOMETRY_INSTANCE_TRIANGLE_FACING_CULL_DISABLE_BIT_KHR    : VkGeometryInstanceFlagBitsKHR : 0x00000001
VK_GEOMETRY_INSTANCE_TRIANGLE_FLIP_FACING_BIT_KHR            : VkGeometryInstanceFlagBitsKHR : 0x00000002
VK_GEOMETRY_INSTANCE_FORCE_OPAQUE_BIT_KHR                    : VkGeometryInstanceFlagBitsKHR : 0x00000004
VK_GEOMETRY_INSTANCE_FORCE_NO_OPAQUE_BIT_KHR                 : VkGeometryInstanceFlagBitsKHR : 0x00000008
VK_GEOMETRY_INSTANCE_FORCE_OPACITY_MICROMAP_2_STATE_EXT      : VkGeometryInstanceFlagBitsKHR : 0x00000010
VK_GEOMETRY_INSTANCE_DISABLE_OPACITY_MICROMAPS_EXT           : VkGeometryInstanceFlagBitsKHR : 0x00000020
VK_GEOMETRY_INSTANCE_TRIANGLE_FRONT_COUNTERCLOCKWISE_BIT_KHR : VkGeometryInstanceFlagBitsKHR : VK_GEOMETRY_INSTANCE_TRIANGLE_FLIP_FACING_BIT_KHR
VK_GEOMETRY_INSTANCE_TRIANGLE_CULL_DISABLE_BIT_NV            : VkGeometryInstanceFlagBitsKHR : VK_GEOMETRY_INSTANCE_TRIANGLE_FACING_CULL_DISABLE_BIT_KHR
VK_GEOMETRY_INSTANCE_TRIANGLE_FRONT_COUNTERCLOCKWISE_BIT_NV  : VkGeometryInstanceFlagBitsKHR : VK_GEOMETRY_INSTANCE_TRIANGLE_FRONT_COUNTERCLOCKWISE_BIT_KHR
VK_GEOMETRY_INSTANCE_FORCE_OPAQUE_BIT_NV                     : VkGeometryInstanceFlagBitsKHR : VK_GEOMETRY_INSTANCE_FORCE_OPAQUE_BIT_KHR
VK_GEOMETRY_INSTANCE_FORCE_NO_OPAQUE_BIT_NV                  : VkGeometryInstanceFlagBitsKHR : VK_GEOMETRY_INSTANCE_FORCE_NO_OPAQUE_BIT_KHR
VK_GEOMETRY_INSTANCE_FLAG_BITS_MAX_ENUM_KHR                  : VkGeometryInstanceFlagBitsKHR : 0x7FFFFFFF

VK_GRAPHICS_PIPELINE_LIBRARY_VERTEX_INPUT_INTERFACE_BIT_EXT    : VkGraphicsPipelineLibraryFlagBitsEXT : 0x00000001
VK_GRAPHICS_PIPELINE_LIBRARY_PRE_RASTERIZATION_SHADERS_BIT_EXT : VkGraphicsPipelineLibraryFlagBitsEXT : 0x00000002
VK_GRAPHICS_PIPELINE_LIBRARY_FRAGMENT_SHADER_BIT_EXT           : VkGraphicsPipelineLibraryFlagBitsEXT : 0x00000004
VK_GRAPHICS_PIPELINE_LIBRARY_FRAGMENT_OUTPUT_INTERFACE_BIT_EXT : VkGraphicsPipelineLibraryFlagBitsEXT : 0x00000008
VK_GRAPHICS_PIPELINE_LIBRARY_FLAG_BITS_MAX_ENUM_EXT            : VkGraphicsPipelineLibraryFlagBitsEXT : 0x7FFFFFFF

VK_HOST_IMAGE_COPY_MEMCPY_EXT             : VkHostImageCopyFlagBitsEXT : 0x00000001
VK_HOST_IMAGE_COPY_FLAG_BITS_MAX_ENUM_EXT : VkHostImageCopyFlagBitsEXT : 0x7FFFFFFF

VK_IMAGE_ASPECT_COLOR_BIT              : VkImageAspectFlagBits : 0x00000001
VK_IMAGE_ASPECT_DEPTH_BIT              : VkImageAspectFlagBits : 0x00000002
VK_IMAGE_ASPECT_STENCIL_BIT            : VkImageAspectFlagBits : 0x00000004
VK_IMAGE_ASPECT_METADATA_BIT           : VkImageAspectFlagBits : 0x00000008
VK_IMAGE_ASPECT_PLANE_0_BIT            : VkImageAspectFlagBits : 0x00000010
VK_IMAGE_ASPECT_PLANE_1_BIT            : VkImageAspectFlagBits : 0x00000020
VK_IMAGE_ASPECT_PLANE_2_BIT            : VkImageAspectFlagBits : 0x00000040
VK_IMAGE_ASPECT_NONE                   : VkImageAspectFlagBits : 0
VK_IMAGE_ASPECT_MEMORY_PLANE_0_BIT_EXT : VkImageAspectFlagBits : 0x00000080
VK_IMAGE_ASPECT_MEMORY_PLANE_1_BIT_EXT : VkImageAspectFlagBits : 0x00000100
VK_IMAGE_ASPECT_MEMORY_PLANE_2_BIT_EXT : VkImageAspectFlagBits : 0x00000200
VK_IMAGE_ASPECT_MEMORY_PLANE_3_BIT_EXT : VkImageAspectFlagBits : 0x00000400
VK_IMAGE_ASPECT_PLANE_0_BIT_KHR        : VkImageAspectFlagBits : VK_IMAGE_ASPECT_PLANE_0_BIT
VK_IMAGE_ASPECT_PLANE_1_BIT_KHR        : VkImageAspectFlagBits : VK_IMAGE_ASPECT_PLANE_1_BIT
VK_IMAGE_ASPECT_PLANE_2_BIT_KHR        : VkImageAspectFlagBits : VK_IMAGE_ASPECT_PLANE_2_BIT
VK_IMAGE_ASPECT_NONE_KHR               : VkImageAspectFlagBits : VK_IMAGE_ASPECT_NONE
VK_IMAGE_ASPECT_FLAG_BITS_MAX_ENUM     : VkImageAspectFlagBits : 0x7FFFFFFF

VK_IMAGE_COMPRESSION_FIXED_RATE_NONE_EXT               : VkImageCompressionFixedRateFlagBitsEXT : 0
VK_IMAGE_COMPRESSION_FIXED_RATE_1BPC_BIT_EXT           : VkImageCompressionFixedRateFlagBitsEXT : 0x00000001
VK_IMAGE_COMPRESSION_FIXED_RATE_2BPC_BIT_EXT           : VkImageCompressionFixedRateFlagBitsEXT : 0x00000002
VK_IMAGE_COMPRESSION_FIXED_RATE_3BPC_BIT_EXT           : VkImageCompressionFixedRateFlagBitsEXT : 0x00000004
VK_IMAGE_COMPRESSION_FIXED_RATE_4BPC_BIT_EXT           : VkImageCompressionFixedRateFlagBitsEXT : 0x00000008
VK_IMAGE_COMPRESSION_FIXED_RATE_5BPC_BIT_EXT           : VkImageCompressionFixedRateFlagBitsEXT : 0x00000010
VK_IMAGE_COMPRESSION_FIXED_RATE_6BPC_BIT_EXT           : VkImageCompressionFixedRateFlagBitsEXT : 0x00000020
VK_IMAGE_COMPRESSION_FIXED_RATE_7BPC_BIT_EXT           : VkImageCompressionFixedRateFlagBitsEXT : 0x00000040
VK_IMAGE_COMPRESSION_FIXED_RATE_8BPC_BIT_EXT           : VkImageCompressionFixedRateFlagBitsEXT : 0x00000080
VK_IMAGE_COMPRESSION_FIXED_RATE_9BPC_BIT_EXT           : VkImageCompressionFixedRateFlagBitsEXT : 0x00000100
VK_IMAGE_COMPRESSION_FIXED_RATE_10BPC_BIT_EXT          : VkImageCompressionFixedRateFlagBitsEXT : 0x00000200
VK_IMAGE_COMPRESSION_FIXED_RATE_11BPC_BIT_EXT          : VkImageCompressionFixedRateFlagBitsEXT : 0x00000400
VK_IMAGE_COMPRESSION_FIXED_RATE_12BPC_BIT_EXT          : VkImageCompressionFixedRateFlagBitsEXT : 0x00000800
VK_IMAGE_COMPRESSION_FIXED_RATE_13BPC_BIT_EXT          : VkImageCompressionFixedRateFlagBitsEXT : 0x00001000
VK_IMAGE_COMPRESSION_FIXED_RATE_14BPC_BIT_EXT          : VkImageCompressionFixedRateFlagBitsEXT : 0x00002000
VK_IMAGE_COMPRESSION_FIXED_RATE_15BPC_BIT_EXT          : VkImageCompressionFixedRateFlagBitsEXT : 0x00004000
VK_IMAGE_COMPRESSION_FIXED_RATE_16BPC_BIT_EXT          : VkImageCompressionFixedRateFlagBitsEXT : 0x00008000
VK_IMAGE_COMPRESSION_FIXED_RATE_17BPC_BIT_EXT          : VkImageCompressionFixedRateFlagBitsEXT : 0x00010000
VK_IMAGE_COMPRESSION_FIXED_RATE_18BPC_BIT_EXT          : VkImageCompressionFixedRateFlagBitsEXT : 0x00020000
VK_IMAGE_COMPRESSION_FIXED_RATE_19BPC_BIT_EXT          : VkImageCompressionFixedRateFlagBitsEXT : 0x00040000
VK_IMAGE_COMPRESSION_FIXED_RATE_20BPC_BIT_EXT          : VkImageCompressionFixedRateFlagBitsEXT : 0x00080000
VK_IMAGE_COMPRESSION_FIXED_RATE_21BPC_BIT_EXT          : VkImageCompressionFixedRateFlagBitsEXT : 0x00100000
VK_IMAGE_COMPRESSION_FIXED_RATE_22BPC_BIT_EXT          : VkImageCompressionFixedRateFlagBitsEXT : 0x00200000
VK_IMAGE_COMPRESSION_FIXED_RATE_23BPC_BIT_EXT          : VkImageCompressionFixedRateFlagBitsEXT : 0x00400000
VK_IMAGE_COMPRESSION_FIXED_RATE_24BPC_BIT_EXT          : VkImageCompressionFixedRateFlagBitsEXT : 0x00800000
VK_IMAGE_COMPRESSION_FIXED_RATE_FLAG_BITS_MAX_ENUM_EXT : VkImageCompressionFixedRateFlagBitsEXT : 0x7FFFFFFF

VK_IMAGE_COMPRESSION_DEFAULT_EXT             : VkImageCompressionFlagBitsEXT : 0
VK_IMAGE_COMPRESSION_FIXED_RATE_DEFAULT_EXT  : VkImageCompressionFlagBitsEXT : 0x00000001
VK_IMAGE_COMPRESSION_FIXED_RATE_EXPLICIT_EXT : VkImageCompressionFlagBitsEXT : 0x00000002
VK_IMAGE_COMPRESSION_DISABLED_EXT            : VkImageCompressionFlagBitsEXT : 0x00000004
VK_IMAGE_COMPRESSION_FLAG_BITS_MAX_ENUM_EXT  : VkImageCompressionFlagBitsEXT : 0x7FFFFFFF

VK_IMAGE_CREATE_SPARSE_BINDING_BIT                            : VkImageCreateFlagBits : 0x00000001
VK_IMAGE_CREATE_SPARSE_RESIDENCY_BIT                          : VkImageCreateFlagBits : 0x00000002
VK_IMAGE_CREATE_SPARSE_ALIASED_BIT                            : VkImageCreateFlagBits : 0x00000004
VK_IMAGE_CREATE_MUTABLE_FORMAT_BIT                            : VkImageCreateFlagBits : 0x00000008
VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT                           : VkImageCreateFlagBits : 0x00000010
VK_IMAGE_CREATE_ALIAS_BIT                                     : VkImageCreateFlagBits : 0x00000400
VK_IMAGE_CREATE_SPLIT_INSTANCE_BIND_REGIONS_BIT               : VkImageCreateFlagBits : 0x00000040
VK_IMAGE_CREATE_2D_ARRAY_COMPATIBLE_BIT                       : VkImageCreateFlagBits : 0x00000020
VK_IMAGE_CREATE_BLOCK_TEXEL_VIEW_COMPATIBLE_BIT               : VkImageCreateFlagBits : 0x00000080
VK_IMAGE_CREATE_EXTENDED_USAGE_BIT                            : VkImageCreateFlagBits : 0x00000100
VK_IMAGE_CREATE_PROTECTED_BIT                                 : VkImageCreateFlagBits : 0x00000800
VK_IMAGE_CREATE_DISJOINT_BIT                                  : VkImageCreateFlagBits : 0x00000200
VK_IMAGE_CREATE_CORNER_SAMPLED_BIT_NV                         : VkImageCreateFlagBits : 0x00002000
VK_IMAGE_CREATE_SAMPLE_LOCATIONS_COMPATIBLE_DEPTH_BIT_EXT     : VkImageCreateFlagBits : 0x00001000
VK_IMAGE_CREATE_SUBSAMPLED_BIT_EXT                            : VkImageCreateFlagBits : 0x00004000
VK_IMAGE_CREATE_DESCRIPTOR_BUFFER_CAPTURE_REPLAY_BIT_EXT      : VkImageCreateFlagBits : 0x00010000
VK_IMAGE_CREATE_MULTISAMPLED_RENDER_TO_SINGLE_SAMPLED_BIT_EXT : VkImageCreateFlagBits : 0x00040000
VK_IMAGE_CREATE_2D_VIEW_COMPATIBLE_BIT_EXT                    : VkImageCreateFlagBits : 0x00020000
VK_IMAGE_CREATE_FRAGMENT_DENSITY_MAP_OFFSET_BIT_QCOM          : VkImageCreateFlagBits : 0x00008000
VK_IMAGE_CREATE_VIDEO_PROFILE_INDEPENDENT_BIT_KHR             : VkImageCreateFlagBits : 0x00100000
VK_IMAGE_CREATE_SPLIT_INSTANCE_BIND_REGIONS_BIT_KHR           : VkImageCreateFlagBits : VK_IMAGE_CREATE_SPLIT_INSTANCE_BIND_REGIONS_BIT
VK_IMAGE_CREATE_2D_ARRAY_COMPATIBLE_BIT_KHR                   : VkImageCreateFlagBits : VK_IMAGE_CREATE_2D_ARRAY_COMPATIBLE_BIT
VK_IMAGE_CREATE_BLOCK_TEXEL_VIEW_COMPATIBLE_BIT_KHR           : VkImageCreateFlagBits : VK_IMAGE_CREATE_BLOCK_TEXEL_VIEW_COMPATIBLE_BIT
VK_IMAGE_CREATE_EXTENDED_USAGE_BIT_KHR                        : VkImageCreateFlagBits : VK_IMAGE_CREATE_EXTENDED_USAGE_BIT
VK_IMAGE_CREATE_DISJOINT_BIT_KHR                              : VkImageCreateFlagBits : VK_IMAGE_CREATE_DISJOINT_BIT
VK_IMAGE_CREATE_ALIAS_BIT_KHR                                 : VkImageCreateFlagBits : VK_IMAGE_CREATE_ALIAS_BIT
VK_IMAGE_CREATE_FLAG_BITS_MAX_ENUM                            : VkImageCreateFlagBits : 0x7FFFFFFF

VK_IMAGE_USAGE_TRANSFER_SRC_BIT                         : VkImageUsageFlagBits : 0x00000001
VK_IMAGE_USAGE_TRANSFER_DST_BIT                         : VkImageUsageFlagBits : 0x00000002
VK_IMAGE_USAGE_SAMPLED_BIT                              : VkImageUsageFlagBits : 0x00000004
VK_IMAGE_USAGE_STORAGE_BIT                              : VkImageUsageFlagBits : 0x00000008
VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT                     : VkImageUsageFlagBits : 0x00000010
VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT             : VkImageUsageFlagBits : 0x00000020
VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT                 : VkImageUsageFlagBits : 0x00000040
VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT                     : VkImageUsageFlagBits : 0x00000080
VK_IMAGE_USAGE_VIDEO_DECODE_DST_BIT_KHR                 : VkImageUsageFlagBits : 0x00000400
VK_IMAGE_USAGE_VIDEO_DECODE_SRC_BIT_KHR                 : VkImageUsageFlagBits : 0x00000800
VK_IMAGE_USAGE_VIDEO_DECODE_DPB_BIT_KHR                 : VkImageUsageFlagBits : 0x00001000
VK_IMAGE_USAGE_FRAGMENT_DENSITY_MAP_BIT_EXT             : VkImageUsageFlagBits : 0x00000200
VK_IMAGE_USAGE_FRAGMENT_SHADING_RATE_ATTACHMENT_BIT_KHR : VkImageUsageFlagBits : 0x00000100
VK_IMAGE_USAGE_HOST_TRANSFER_BIT_EXT                    : VkImageUsageFlagBits : 0x00400000
VK_IMAGE_USAGE_VIDEO_ENCODE_DST_BIT_KHR                 : VkImageUsageFlagBits : 0x00002000
VK_IMAGE_USAGE_VIDEO_ENCODE_SRC_BIT_KHR                 : VkImageUsageFlagBits : 0x00004000
VK_IMAGE_USAGE_VIDEO_ENCODE_DPB_BIT_KHR                 : VkImageUsageFlagBits : 0x00008000
VK_IMAGE_USAGE_ATTACHMENT_FEEDBACK_LOOP_BIT_EXT         : VkImageUsageFlagBits : 0x00080000
VK_IMAGE_USAGE_INVOCATION_MASK_BIT_HUAWEI               : VkImageUsageFlagBits : 0x00040000
VK_IMAGE_USAGE_SAMPLE_WEIGHT_BIT_QCOM                   : VkImageUsageFlagBits : 0x00100000
VK_IMAGE_USAGE_SAMPLE_BLOCK_MATCH_BIT_QCOM              : VkImageUsageFlagBits : 0x00200000
VK_IMAGE_USAGE_SHADING_RATE_IMAGE_BIT_NV                : VkImageUsageFlagBits : VK_IMAGE_USAGE_FRAGMENT_SHADING_RATE_ATTACHMENT_BIT_KHR
VK_IMAGE_USAGE_FLAG_BITS_MAX_ENUM                       : VkImageUsageFlagBits : 0x7FFFFFFF

VK_IMAGE_VIEW_CREATE_FRAGMENT_DENSITY_MAP_DYNAMIC_BIT_EXT     : VkImageViewCreateFlagBits : 0x00000001
VK_IMAGE_VIEW_CREATE_DESCRIPTOR_BUFFER_CAPTURE_REPLAY_BIT_EXT : VkImageViewCreateFlagBits : 0x00000004
VK_IMAGE_VIEW_CREATE_FRAGMENT_DENSITY_MAP_DEFERRED_BIT_EXT    : VkImageViewCreateFlagBits : 0x00000002
VK_IMAGE_VIEW_CREATE_FLAG_BITS_MAX_ENUM                       : VkImageViewCreateFlagBits : 0x7FFFFFFF

VK_INDIRECT_COMMANDS_LAYOUT_USAGE_EXPLICIT_PREPROCESS_BIT_NV : VkIndirectCommandsLayoutUsageFlagBitsNV : 0x00000001
VK_INDIRECT_COMMANDS_LAYOUT_USAGE_INDEXED_SEQUENCES_BIT_NV   : VkIndirectCommandsLayoutUsageFlagBitsNV : 0x00000002
VK_INDIRECT_COMMANDS_LAYOUT_USAGE_UNORDERED_SEQUENCES_BIT_NV : VkIndirectCommandsLayoutUsageFlagBitsNV : 0x00000004
VK_INDIRECT_COMMANDS_LAYOUT_USAGE_FLAG_BITS_MAX_ENUM_NV      : VkIndirectCommandsLayoutUsageFlagBitsNV : 0x7FFFFFFF

VK_INDIRECT_STATE_FLAG_FRONTFACE_BIT_NV : VkIndirectStateFlagBitsNV : 0x00000001
VK_INDIRECT_STATE_FLAG_BITS_MAX_ENUM_NV : VkIndirectStateFlagBitsNV : 0x7FFFFFFF

VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR : VkInstanceCreateFlagBits : 0x00000001
VK_INSTANCE_CREATE_FLAG_BITS_MAX_ENUM            : VkInstanceCreateFlagBits : 0x7FFFFFFF

VK_MEMORY_ALLOCATE_DEVICE_MASK_BIT                       : VkMemoryAllocateFlagBits : 0x00000001
VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT                    : VkMemoryAllocateFlagBits : 0x00000002
VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_CAPTURE_REPLAY_BIT     : VkMemoryAllocateFlagBits : 0x00000004
VK_MEMORY_ALLOCATE_DEVICE_MASK_BIT_KHR                   : VkMemoryAllocateFlagBits : VK_MEMORY_ALLOCATE_DEVICE_MASK_BIT
VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT_KHR                : VkMemoryAllocateFlagBits : VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT
VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_CAPTURE_REPLAY_BIT_KHR : VkMemoryAllocateFlagBits : VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_CAPTURE_REPLAY_BIT
VK_MEMORY_ALLOCATE_FLAG_BITS_MAX_ENUM                    : VkMemoryAllocateFlagBits : 0x7FFFFFFF

VK_MEMORY_HEAP_DEVICE_LOCAL_BIT       : VkMemoryHeapFlagBits : 0x00000001
VK_MEMORY_HEAP_MULTI_INSTANCE_BIT     : VkMemoryHeapFlagBits : 0x00000002
VK_MEMORY_HEAP_MULTI_INSTANCE_BIT_KHR : VkMemoryHeapFlagBits : VK_MEMORY_HEAP_MULTI_INSTANCE_BIT
VK_MEMORY_HEAP_FLAG_BITS_MAX_ENUM     : VkMemoryHeapFlagBits : 0x7FFFFFFF

VK_MEMORY_MAP_PLACED_BIT_EXT     : VkMemoryMapFlagBits : 0x00000001
VK_MEMORY_MAP_FLAG_BITS_MAX_ENUM : VkMemoryMapFlagBits : 0x7FFFFFFF

VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT        : VkMemoryPropertyFlagBits : 0x00000001
VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT        : VkMemoryPropertyFlagBits : 0x00000002
VK_MEMORY_PROPERTY_HOST_COHERENT_BIT       : VkMemoryPropertyFlagBits : 0x00000004
VK_MEMORY_PROPERTY_HOST_CACHED_BIT         : VkMemoryPropertyFlagBits : 0x00000008
VK_MEMORY_PROPERTY_LAZILY_ALLOCATED_BIT    : VkMemoryPropertyFlagBits : 0x00000010
VK_MEMORY_PROPERTY_PROTECTED_BIT           : VkMemoryPropertyFlagBits : 0x00000020
VK_MEMORY_PROPERTY_DEVICE_COHERENT_BIT_AMD : VkMemoryPropertyFlagBits : 0x00000040
VK_MEMORY_PROPERTY_DEVICE_UNCACHED_BIT_AMD : VkMemoryPropertyFlagBits : 0x00000080
VK_MEMORY_PROPERTY_RDMA_CAPABLE_BIT_NV     : VkMemoryPropertyFlagBits : 0x00000100
VK_MEMORY_PROPERTY_FLAG_BITS_MAX_ENUM      : VkMemoryPropertyFlagBits : 0x7FFFFFFF

VK_MEMORY_UNMAP_RESERVE_BIT_EXT        : VkMemoryUnmapFlagBitsKHR : 0x00000001
VK_MEMORY_UNMAP_FLAG_BITS_MAX_ENUM_KHR : VkMemoryUnmapFlagBitsKHR : 0x7FFFFFFF

VK_MICROMAP_CREATE_DEVICE_ADDRESS_CAPTURE_REPLAY_BIT_EXT : VkMicromapCreateFlagBitsEXT : 0x00000001
VK_MICROMAP_CREATE_FLAG_BITS_MAX_ENUM_EXT                : VkMicromapCreateFlagBitsEXT : 0x7FFFFFFF

VK_OPTICAL_FLOW_EXECUTE_DISABLE_TEMPORAL_HINTS_BIT_NV : VkOpticalFlowExecuteFlagBitsNV : 0x00000001
VK_OPTICAL_FLOW_EXECUTE_FLAG_BITS_MAX_ENUM_NV         : VkOpticalFlowExecuteFlagBitsNV : 0x7FFFFFFF

VK_OPTICAL_FLOW_GRID_SIZE_UNKNOWN_NV            : VkOpticalFlowGridSizeFlagBitsNV : 0
VK_OPTICAL_FLOW_GRID_SIZE_1X1_BIT_NV            : VkOpticalFlowGridSizeFlagBitsNV : 0x00000001
VK_OPTICAL_FLOW_GRID_SIZE_2X2_BIT_NV            : VkOpticalFlowGridSizeFlagBitsNV : 0x00000002
VK_OPTICAL_FLOW_GRID_SIZE_4X4_BIT_NV            : VkOpticalFlowGridSizeFlagBitsNV : 0x00000004
VK_OPTICAL_FLOW_GRID_SIZE_8X8_BIT_NV            : VkOpticalFlowGridSizeFlagBitsNV : 0x00000008
VK_OPTICAL_FLOW_GRID_SIZE_FLAG_BITS_MAX_ENUM_NV : VkOpticalFlowGridSizeFlagBitsNV : 0x7FFFFFFF

VK_OPTICAL_FLOW_SESSION_CREATE_ENABLE_HINT_BIT_NV        : VkOpticalFlowSessionCreateFlagBitsNV : 0x00000001
VK_OPTICAL_FLOW_SESSION_CREATE_ENABLE_COST_BIT_NV        : VkOpticalFlowSessionCreateFlagBitsNV : 0x00000002
VK_OPTICAL_FLOW_SESSION_CREATE_ENABLE_GLOBAL_FLOW_BIT_NV : VkOpticalFlowSessionCreateFlagBitsNV : 0x00000004
VK_OPTICAL_FLOW_SESSION_CREATE_ALLOW_REGIONS_BIT_NV      : VkOpticalFlowSessionCreateFlagBitsNV : 0x00000008
VK_OPTICAL_FLOW_SESSION_CREATE_BOTH_DIRECTIONS_BIT_NV    : VkOpticalFlowSessionCreateFlagBitsNV : 0x00000010
VK_OPTICAL_FLOW_SESSION_CREATE_FLAG_BITS_MAX_ENUM_NV     : VkOpticalFlowSessionCreateFlagBitsNV : 0x7FFFFFFF

VK_OPTICAL_FLOW_USAGE_UNKNOWN_NV            : VkOpticalFlowUsageFlagBitsNV : 0
VK_OPTICAL_FLOW_USAGE_INPUT_BIT_NV          : VkOpticalFlowUsageFlagBitsNV : 0x00000001
VK_OPTICAL_FLOW_USAGE_OUTPUT_BIT_NV         : VkOpticalFlowUsageFlagBitsNV : 0x00000002
VK_OPTICAL_FLOW_USAGE_HINT_BIT_NV           : VkOpticalFlowUsageFlagBitsNV : 0x00000004
VK_OPTICAL_FLOW_USAGE_COST_BIT_NV           : VkOpticalFlowUsageFlagBitsNV : 0x00000008
VK_OPTICAL_FLOW_USAGE_GLOBAL_FLOW_BIT_NV    : VkOpticalFlowUsageFlagBitsNV : 0x00000010
VK_OPTICAL_FLOW_USAGE_FLAG_BITS_MAX_ENUM_NV : VkOpticalFlowUsageFlagBitsNV : 0x7FFFFFFF

VK_PEER_MEMORY_FEATURE_COPY_SRC_BIT        : VkPeerMemoryFeatureFlagBits : 0x00000001
VK_PEER_MEMORY_FEATURE_COPY_DST_BIT        : VkPeerMemoryFeatureFlagBits : 0x00000002
VK_PEER_MEMORY_FEATURE_GENERIC_SRC_BIT     : VkPeerMemoryFeatureFlagBits : 0x00000004
VK_PEER_MEMORY_FEATURE_GENERIC_DST_BIT     : VkPeerMemoryFeatureFlagBits : 0x00000008
VK_PEER_MEMORY_FEATURE_COPY_SRC_BIT_KHR    : VkPeerMemoryFeatureFlagBits : VK_PEER_MEMORY_FEATURE_COPY_SRC_BIT
VK_PEER_MEMORY_FEATURE_COPY_DST_BIT_KHR    : VkPeerMemoryFeatureFlagBits : VK_PEER_MEMORY_FEATURE_COPY_DST_BIT
VK_PEER_MEMORY_FEATURE_GENERIC_SRC_BIT_KHR : VkPeerMemoryFeatureFlagBits : VK_PEER_MEMORY_FEATURE_GENERIC_SRC_BIT
VK_PEER_MEMORY_FEATURE_GENERIC_DST_BIT_KHR : VkPeerMemoryFeatureFlagBits : VK_PEER_MEMORY_FEATURE_GENERIC_DST_BIT
VK_PEER_MEMORY_FEATURE_FLAG_BITS_MAX_ENUM  : VkPeerMemoryFeatureFlagBits : 0x7FFFFFFF

VK_PERFORMANCE_COUNTER_DESCRIPTION_PERFORMANCE_IMPACTING_BIT_KHR : VkPerformanceCounterDescriptionFlagBitsKHR : 0x00000001
VK_PERFORMANCE_COUNTER_DESCRIPTION_CONCURRENTLY_IMPACTED_BIT_KHR : VkPerformanceCounterDescriptionFlagBitsKHR : 0x00000002
VK_PERFORMANCE_COUNTER_DESCRIPTION_PERFORMANCE_IMPACTING_KHR     : VkPerformanceCounterDescriptionFlagBitsKHR : VK_PERFORMANCE_COUNTER_DESCRIPTION_PERFORMANCE_IMPACTING_BIT_KHR
VK_PERFORMANCE_COUNTER_DESCRIPTION_CONCURRENTLY_IMPACTED_KHR     : VkPerformanceCounterDescriptionFlagBitsKHR : VK_PERFORMANCE_COUNTER_DESCRIPTION_CONCURRENTLY_IMPACTED_BIT_KHR
VK_PERFORMANCE_COUNTER_DESCRIPTION_FLAG_BITS_MAX_ENUM_KHR        : VkPerformanceCounterDescriptionFlagBitsKHR : 0x7FFFFFFF

VK_PIPELINE_CACHE_CREATE_EXTERNALLY_SYNCHRONIZED_BIT     : VkPipelineCacheCreateFlagBits : 0x00000001
VK_PIPELINE_CACHE_CREATE_EXTERNALLY_SYNCHRONIZED_BIT_EXT : VkPipelineCacheCreateFlagBits : VK_PIPELINE_CACHE_CREATE_EXTERNALLY_SYNCHRONIZED_BIT
VK_PIPELINE_CACHE_CREATE_FLAG_BITS_MAX_ENUM              : VkPipelineCacheCreateFlagBits : 0x7FFFFFFF

VK_PIPELINE_COLOR_BLEND_STATE_CREATE_RASTERIZATION_ORDER_ATTACHMENT_ACCESS_BIT_EXT : VkPipelineColorBlendStateCreateFlagBits : 0x00000001
VK_PIPELINE_COLOR_BLEND_STATE_CREATE_RASTERIZATION_ORDER_ATTACHMENT_ACCESS_BIT_ARM : VkPipelineColorBlendStateCreateFlagBits : VK_PIPELINE_COLOR_BLEND_STATE_CREATE_RASTERIZATION_ORDER_ATTACHMENT_ACCESS_BIT_EXT
VK_PIPELINE_COLOR_BLEND_STATE_CREATE_FLAG_BITS_MAX_ENUM                            : VkPipelineColorBlendStateCreateFlagBits : 0x7FFFFFFF

VK_PIPELINE_COMPILER_CONTROL_FLAG_BITS_MAX_ENUM_AMD : VkPipelineCompilerControlFlagBitsAMD : 0x7FFFFFFF

VK_PIPELINE_CREATE_DISABLE_OPTIMIZATION_BIT                                     : VkPipelineCreateFlagBits : 0x00000001
VK_PIPELINE_CREATE_ALLOW_DERIVATIVES_BIT                                        : VkPipelineCreateFlagBits : 0x00000002
VK_PIPELINE_CREATE_DERIVATIVE_BIT                                               : VkPipelineCreateFlagBits : 0x00000004
VK_PIPELINE_CREATE_VIEW_INDEX_FROM_DEVICE_INDEX_BIT                             : VkPipelineCreateFlagBits : 0x00000008
VK_PIPELINE_CREATE_DISPATCH_BASE_BIT                                            : VkPipelineCreateFlagBits : 0x00000010
VK_PIPELINE_CREATE_FAIL_ON_PIPELINE_COMPILE_REQUIRED_BIT                        : VkPipelineCreateFlagBits : 0x00000100
VK_PIPELINE_CREATE_EARLY_RETURN_ON_FAILURE_BIT                                  : VkPipelineCreateFlagBits : 0x00000200
VK_PIPELINE_CREATE_RENDERING_FRAGMENT_SHADING_RATE_ATTACHMENT_BIT_KHR           : VkPipelineCreateFlagBits : 0x00200000
VK_PIPELINE_CREATE_RENDERING_FRAGMENT_DENSITY_MAP_ATTACHMENT_BIT_EXT            : VkPipelineCreateFlagBits : 0x00400000
VK_PIPELINE_CREATE_RAY_TRACING_NO_NULL_ANY_HIT_SHADERS_BIT_KHR                  : VkPipelineCreateFlagBits : 0x00004000
VK_PIPELINE_CREATE_RAY_TRACING_NO_NULL_CLOSEST_HIT_SHADERS_BIT_KHR              : VkPipelineCreateFlagBits : 0x00008000
VK_PIPELINE_CREATE_RAY_TRACING_NO_NULL_MISS_SHADERS_BIT_KHR                     : VkPipelineCreateFlagBits : 0x00010000
VK_PIPELINE_CREATE_RAY_TRACING_NO_NULL_INTERSECTION_SHADERS_BIT_KHR             : VkPipelineCreateFlagBits : 0x00020000
VK_PIPELINE_CREATE_RAY_TRACING_SKIP_TRIANGLES_BIT_KHR                           : VkPipelineCreateFlagBits : 0x00001000
VK_PIPELINE_CREATE_RAY_TRACING_SKIP_AABBS_BIT_KHR                               : VkPipelineCreateFlagBits : 0x00002000
VK_PIPELINE_CREATE_RAY_TRACING_SHADER_GROUP_HANDLE_CAPTURE_REPLAY_BIT_KHR       : VkPipelineCreateFlagBits : 0x00080000
VK_PIPELINE_CREATE_DEFER_COMPILE_BIT_NV                                         : VkPipelineCreateFlagBits : 0x00000020
VK_PIPELINE_CREATE_CAPTURE_STATISTICS_BIT_KHR                                   : VkPipelineCreateFlagBits : 0x00000040
VK_PIPELINE_CREATE_CAPTURE_INTERNAL_REPRESENTATIONS_BIT_KHR                     : VkPipelineCreateFlagBits : 0x00000080
VK_PIPELINE_CREATE_INDIRECT_BINDABLE_BIT_NV                                     : VkPipelineCreateFlagBits : 0x00040000
VK_PIPELINE_CREATE_LIBRARY_BIT_KHR                                              : VkPipelineCreateFlagBits : 0x00000800
VK_PIPELINE_CREATE_DESCRIPTOR_BUFFER_BIT_EXT                                    : VkPipelineCreateFlagBits : 0x20000000
VK_PIPELINE_CREATE_RETAIN_LINK_TIME_OPTIMIZATION_INFO_BIT_EXT                   : VkPipelineCreateFlagBits : 0x00800000
VK_PIPELINE_CREATE_LINK_TIME_OPTIMIZATION_BIT_EXT                               : VkPipelineCreateFlagBits : 0x00000400
VK_PIPELINE_CREATE_RAY_TRACING_ALLOW_MOTION_BIT_NV                              : VkPipelineCreateFlagBits : 0x00100000
VK_PIPELINE_CREATE_COLOR_ATTACHMENT_FEEDBACK_LOOP_BIT_EXT                       : VkPipelineCreateFlagBits : 0x02000000
VK_PIPELINE_CREATE_DEPTH_STENCIL_ATTACHMENT_FEEDBACK_LOOP_BIT_EXT               : VkPipelineCreateFlagBits : 0x04000000
VK_PIPELINE_CREATE_RAY_TRACING_OPACITY_MICROMAP_BIT_EXT                         : VkPipelineCreateFlagBits : 0x01000000
VK_PIPELINE_CREATE_RAY_TRACING_DISPLACEMENT_MICROMAP_BIT_NV                     : VkPipelineCreateFlagBits : 0x10000000
VK_PIPELINE_CREATE_NO_PROTECTED_ACCESS_BIT_EXT                                  : VkPipelineCreateFlagBits : 0x08000000
VK_PIPELINE_CREATE_PROTECTED_ACCESS_ONLY_BIT_EXT                                : VkPipelineCreateFlagBits : 0x40000000
VK_PIPELINE_CREATE_DISPATCH_BASE                                                : VkPipelineCreateFlagBits : VK_PIPELINE_CREATE_DISPATCH_BASE_BIT
VK_PIPELINE_RASTERIZATION_STATE_CREATE_FRAGMENT_SHADING_RATE_ATTACHMENT_BIT_KHR : VkPipelineCreateFlagBits : VK_PIPELINE_CREATE_RENDERING_FRAGMENT_SHADING_RATE_ATTACHMENT_BIT_KHR
VK_PIPELINE_RASTERIZATION_STATE_CREATE_FRAGMENT_DENSITY_MAP_ATTACHMENT_BIT_EXT  : VkPipelineCreateFlagBits : VK_PIPELINE_CREATE_RENDERING_FRAGMENT_DENSITY_MAP_ATTACHMENT_BIT_EXT
VK_PIPELINE_CREATE_VIEW_INDEX_FROM_DEVICE_INDEX_BIT_KHR                         : VkPipelineCreateFlagBits : VK_PIPELINE_CREATE_VIEW_INDEX_FROM_DEVICE_INDEX_BIT
VK_PIPELINE_CREATE_DISPATCH_BASE_KHR                                            : VkPipelineCreateFlagBits : VK_PIPELINE_CREATE_DISPATCH_BASE
VK_PIPELINE_CREATE_FAIL_ON_PIPELINE_COMPILE_REQUIRED_BIT_EXT                    : VkPipelineCreateFlagBits : VK_PIPELINE_CREATE_FAIL_ON_PIPELINE_COMPILE_REQUIRED_BIT
VK_PIPELINE_CREATE_EARLY_RETURN_ON_FAILURE_BIT_EXT                              : VkPipelineCreateFlagBits : VK_PIPELINE_CREATE_EARLY_RETURN_ON_FAILURE_BIT
VK_PIPELINE_CREATE_FLAG_BITS_MAX_ENUM                                           : VkPipelineCreateFlagBits : 0x7FFFFFFF

VK_PIPELINE_CREATION_FEEDBACK_VALID_BIT                              : VkPipelineCreationFeedbackFlagBits : 0x00000001
VK_PIPELINE_CREATION_FEEDBACK_APPLICATION_PIPELINE_CACHE_HIT_BIT     : VkPipelineCreationFeedbackFlagBits : 0x00000002
VK_PIPELINE_CREATION_FEEDBACK_BASE_PIPELINE_ACCELERATION_BIT         : VkPipelineCreationFeedbackFlagBits : 0x00000004
VK_PIPELINE_CREATION_FEEDBACK_VALID_BIT_EXT                          : VkPipelineCreationFeedbackFlagBits : VK_PIPELINE_CREATION_FEEDBACK_VALID_BIT
VK_PIPELINE_CREATION_FEEDBACK_APPLICATION_PIPELINE_CACHE_HIT_BIT_EXT : VkPipelineCreationFeedbackFlagBits : VK_PIPELINE_CREATION_FEEDBACK_APPLICATION_PIPELINE_CACHE_HIT_BIT
VK_PIPELINE_CREATION_FEEDBACK_BASE_PIPELINE_ACCELERATION_BIT_EXT     : VkPipelineCreationFeedbackFlagBits : VK_PIPELINE_CREATION_FEEDBACK_BASE_PIPELINE_ACCELERATION_BIT
VK_PIPELINE_CREATION_FEEDBACK_FLAG_BITS_MAX_ENUM                     : VkPipelineCreationFeedbackFlagBits : 0x7FFFFFFF

VK_PIPELINE_DEPTH_STENCIL_STATE_CREATE_RASTERIZATION_ORDER_ATTACHMENT_DEPTH_ACCESS_BIT_EXT   : VkPipelineDepthStencilStateCreateFlagBits : 0x00000001
VK_PIPELINE_DEPTH_STENCIL_STATE_CREATE_RASTERIZATION_ORDER_ATTACHMENT_STENCIL_ACCESS_BIT_EXT : VkPipelineDepthStencilStateCreateFlagBits : 0x00000002
VK_PIPELINE_DEPTH_STENCIL_STATE_CREATE_RASTERIZATION_ORDER_ATTACHMENT_DEPTH_ACCESS_BIT_ARM   : VkPipelineDepthStencilStateCreateFlagBits : VK_PIPELINE_DEPTH_STENCIL_STATE_CREATE_RASTERIZATION_ORDER_ATTACHMENT_DEPTH_ACCESS_BIT_EXT
VK_PIPELINE_DEPTH_STENCIL_STATE_CREATE_RASTERIZATION_ORDER_ATTACHMENT_STENCIL_ACCESS_BIT_ARM : VkPipelineDepthStencilStateCreateFlagBits : VK_PIPELINE_DEPTH_STENCIL_STATE_CREATE_RASTERIZATION_ORDER_ATTACHMENT_STENCIL_ACCESS_BIT_EXT
VK_PIPELINE_DEPTH_STENCIL_STATE_CREATE_FLAG_BITS_MAX_ENUM                                    : VkPipelineDepthStencilStateCreateFlagBits : 0x7FFFFFFF

VK_PIPELINE_LAYOUT_CREATE_INDEPENDENT_SETS_BIT_EXT : VkPipelineLayoutCreateFlagBits : 0x00000002
VK_PIPELINE_LAYOUT_CREATE_FLAG_BITS_MAX_ENUM       : VkPipelineLayoutCreateFlagBits : 0x7FFFFFFF

VK_PIPELINE_SHADER_STAGE_CREATE_ALLOW_VARYING_SUBGROUP_SIZE_BIT     : VkPipelineShaderStageCreateFlagBits : 0x00000001
VK_PIPELINE_SHADER_STAGE_CREATE_REQUIRE_FULL_SUBGROUPS_BIT          : VkPipelineShaderStageCreateFlagBits : 0x00000002
VK_PIPELINE_SHADER_STAGE_CREATE_ALLOW_VARYING_SUBGROUP_SIZE_BIT_EXT : VkPipelineShaderStageCreateFlagBits : VK_PIPELINE_SHADER_STAGE_CREATE_ALLOW_VARYING_SUBGROUP_SIZE_BIT
VK_PIPELINE_SHADER_STAGE_CREATE_REQUIRE_FULL_SUBGROUPS_BIT_EXT      : VkPipelineShaderStageCreateFlagBits : VK_PIPELINE_SHADER_STAGE_CREATE_REQUIRE_FULL_SUBGROUPS_BIT
VK_PIPELINE_SHADER_STAGE_CREATE_FLAG_BITS_MAX_ENUM                  : VkPipelineShaderStageCreateFlagBits : 0x7FFFFFFF

VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT                          : VkPipelineStageFlagBits : 0x00000001
VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT                        : VkPipelineStageFlagBits : 0x00000002
VK_PIPELINE_STAGE_VERTEX_INPUT_BIT                         : VkPipelineStageFlagBits : 0x00000004
VK_PIPELINE_STAGE_VERTEX_SHADER_BIT                        : VkPipelineStageFlagBits : 0x00000008
VK_PIPELINE_STAGE_TESSELLATION_CONTROL_SHADER_BIT          : VkPipelineStageFlagBits : 0x00000010
VK_PIPELINE_STAGE_TESSELLATION_EVALUATION_SHADER_BIT       : VkPipelineStageFlagBits : 0x00000020
VK_PIPELINE_STAGE_GEOMETRY_SHADER_BIT                      : VkPipelineStageFlagBits : 0x00000040
VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT                      : VkPipelineStageFlagBits : 0x00000080
VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT                 : VkPipelineStageFlagBits : 0x00000100
VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT                  : VkPipelineStageFlagBits : 0x00000200
VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT              : VkPipelineStageFlagBits : 0x00000400
VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT                       : VkPipelineStageFlagBits : 0x00000800
VK_PIPELINE_STAGE_TRANSFER_BIT                             : VkPipelineStageFlagBits : 0x00001000
VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT                       : VkPipelineStageFlagBits : 0x00002000
VK_PIPELINE_STAGE_HOST_BIT                                 : VkPipelineStageFlagBits : 0x00004000
VK_PIPELINE_STAGE_ALL_GRAPHICS_BIT                         : VkPipelineStageFlagBits : 0x00008000
VK_PIPELINE_STAGE_ALL_COMMANDS_BIT                         : VkPipelineStageFlagBits : 0x00010000
VK_PIPELINE_STAGE_NONE                                     : VkPipelineStageFlagBits : 0
VK_PIPELINE_STAGE_TRANSFORM_FEEDBACK_BIT_EXT               : VkPipelineStageFlagBits : 0x01000000
VK_PIPELINE_STAGE_CONDITIONAL_RENDERING_BIT_EXT            : VkPipelineStageFlagBits : 0x00040000
VK_PIPELINE_STAGE_ACCELERATION_STRUCTURE_BUILD_BIT_KHR     : VkPipelineStageFlagBits : 0x02000000
VK_PIPELINE_STAGE_RAY_TRACING_SHADER_BIT_KHR               : VkPipelineStageFlagBits : 0x00200000
VK_PIPELINE_STAGE_FRAGMENT_DENSITY_PROCESS_BIT_EXT         : VkPipelineStageFlagBits : 0x00800000
VK_PIPELINE_STAGE_FRAGMENT_SHADING_RATE_ATTACHMENT_BIT_KHR : VkPipelineStageFlagBits : 0x00400000
VK_PIPELINE_STAGE_COMMAND_PREPROCESS_BIT_NV                : VkPipelineStageFlagBits : 0x00020000
VK_PIPELINE_STAGE_TASK_SHADER_BIT_EXT                      : VkPipelineStageFlagBits : 0x00080000
VK_PIPELINE_STAGE_MESH_SHADER_BIT_EXT                      : VkPipelineStageFlagBits : 0x00100000
VK_PIPELINE_STAGE_SHADING_RATE_IMAGE_BIT_NV                : VkPipelineStageFlagBits : VK_PIPELINE_STAGE_FRAGMENT_SHADING_RATE_ATTACHMENT_BIT_KHR
VK_PIPELINE_STAGE_RAY_TRACING_SHADER_BIT_NV                : VkPipelineStageFlagBits : VK_PIPELINE_STAGE_RAY_TRACING_SHADER_BIT_KHR
VK_PIPELINE_STAGE_ACCELERATION_STRUCTURE_BUILD_BIT_NV      : VkPipelineStageFlagBits : VK_PIPELINE_STAGE_ACCELERATION_STRUCTURE_BUILD_BIT_KHR
VK_PIPELINE_STAGE_TASK_SHADER_BIT_NV                       : VkPipelineStageFlagBits : VK_PIPELINE_STAGE_TASK_SHADER_BIT_EXT
VK_PIPELINE_STAGE_MESH_SHADER_BIT_NV                       : VkPipelineStageFlagBits : VK_PIPELINE_STAGE_MESH_SHADER_BIT_EXT
VK_PIPELINE_STAGE_NONE_KHR                                 : VkPipelineStageFlagBits : VK_PIPELINE_STAGE_NONE
VK_PIPELINE_STAGE_FLAG_BITS_MAX_ENUM                       : VkPipelineStageFlagBits : 0x7FFFFFFF

VK_PRESENT_GRAVITY_MIN_BIT_EXT            : VkPresentGravityFlagBitsEXT : 0x00000001
VK_PRESENT_GRAVITY_MAX_BIT_EXT            : VkPresentGravityFlagBitsEXT : 0x00000002
VK_PRESENT_GRAVITY_CENTERED_BIT_EXT       : VkPresentGravityFlagBitsEXT : 0x00000004
VK_PRESENT_GRAVITY_FLAG_BITS_MAX_ENUM_EXT : VkPresentGravityFlagBitsEXT : 0x7FFFFFFF

VK_PRESENT_SCALING_ONE_TO_ONE_BIT_EXT           : VkPresentScalingFlagBitsEXT : 0x00000001
VK_PRESENT_SCALING_ASPECT_RATIO_STRETCH_BIT_EXT : VkPresentScalingFlagBitsEXT : 0x00000002
VK_PRESENT_SCALING_STRETCH_BIT_EXT              : VkPresentScalingFlagBitsEXT : 0x00000004
VK_PRESENT_SCALING_FLAG_BITS_MAX_ENUM_EXT       : VkPresentScalingFlagBitsEXT : 0x7FFFFFFF

VK_QUERY_CONTROL_PRECISE_BIT        : VkQueryControlFlagBits : 0x00000001
VK_QUERY_CONTROL_FLAG_BITS_MAX_ENUM : VkQueryControlFlagBits : 0x7FFFFFFF

VK_QUERY_PIPELINE_STATISTIC_INPUT_ASSEMBLY_VERTICES_BIT                    : VkQueryPipelineStatisticFlagBits : 0x00000001
VK_QUERY_PIPELINE_STATISTIC_INPUT_ASSEMBLY_PRIMITIVES_BIT                  : VkQueryPipelineStatisticFlagBits : 0x00000002
VK_QUERY_PIPELINE_STATISTIC_VERTEX_SHADER_INVOCATIONS_BIT                  : VkQueryPipelineStatisticFlagBits : 0x00000004
VK_QUERY_PIPELINE_STATISTIC_GEOMETRY_SHADER_INVOCATIONS_BIT                : VkQueryPipelineStatisticFlagBits : 0x00000008
VK_QUERY_PIPELINE_STATISTIC_GEOMETRY_SHADER_PRIMITIVES_BIT                 : VkQueryPipelineStatisticFlagBits : 0x00000010
VK_QUERY_PIPELINE_STATISTIC_CLIPPING_INVOCATIONS_BIT                       : VkQueryPipelineStatisticFlagBits : 0x00000020
VK_QUERY_PIPELINE_STATISTIC_CLIPPING_PRIMITIVES_BIT                        : VkQueryPipelineStatisticFlagBits : 0x00000040
VK_QUERY_PIPELINE_STATISTIC_FRAGMENT_SHADER_INVOCATIONS_BIT                : VkQueryPipelineStatisticFlagBits : 0x00000080
VK_QUERY_PIPELINE_STATISTIC_TESSELLATION_CONTROL_SHADER_PATCHES_BIT        : VkQueryPipelineStatisticFlagBits : 0x00000100
VK_QUERY_PIPELINE_STATISTIC_TESSELLATION_EVALUATION_SHADER_INVOCATIONS_BIT : VkQueryPipelineStatisticFlagBits : 0x00000200
VK_QUERY_PIPELINE_STATISTIC_COMPUTE_SHADER_INVOCATIONS_BIT                 : VkQueryPipelineStatisticFlagBits : 0x00000400
VK_QUERY_PIPELINE_STATISTIC_TASK_SHADER_INVOCATIONS_BIT_EXT                : VkQueryPipelineStatisticFlagBits : 0x00000800
VK_QUERY_PIPELINE_STATISTIC_MESH_SHADER_INVOCATIONS_BIT_EXT                : VkQueryPipelineStatisticFlagBits : 0x00001000
VK_QUERY_PIPELINE_STATISTIC_CLUSTER_CULLING_SHADER_INVOCATIONS_BIT_HUAWEI  : VkQueryPipelineStatisticFlagBits : 0x00002000
VK_QUERY_PIPELINE_STATISTIC_FLAG_BITS_MAX_ENUM                             : VkQueryPipelineStatisticFlagBits : 0x7FFFFFFF

VK_QUERY_RESULT_64_BIT                : VkQueryResultFlagBits : 0x00000001
VK_QUERY_RESULT_WAIT_BIT              : VkQueryResultFlagBits : 0x00000002
VK_QUERY_RESULT_WITH_AVAILABILITY_BIT : VkQueryResultFlagBits : 0x00000004
VK_QUERY_RESULT_PARTIAL_BIT           : VkQueryResultFlagBits : 0x00000008
VK_QUERY_RESULT_WITH_STATUS_BIT_KHR   : VkQueryResultFlagBits : 0x00000010
VK_QUERY_RESULT_FLAG_BITS_MAX_ENUM    : VkQueryResultFlagBits : 0x7FFFFFFF

VK_QUEUE_GRAPHICS_BIT         : VkQueueFlagBits : 0x00000001
VK_QUEUE_COMPUTE_BIT          : VkQueueFlagBits : 0x00000002
VK_QUEUE_TRANSFER_BIT         : VkQueueFlagBits : 0x00000004
VK_QUEUE_SPARSE_BINDING_BIT   : VkQueueFlagBits : 0x00000008
VK_QUEUE_PROTECTED_BIT        : VkQueueFlagBits : 0x00000010
VK_QUEUE_VIDEO_DECODE_BIT_KHR : VkQueueFlagBits : 0x00000020
VK_QUEUE_VIDEO_ENCODE_BIT_KHR : VkQueueFlagBits : 0x00000040
VK_QUEUE_OPTICAL_FLOW_BIT_NV  : VkQueueFlagBits : 0x00000100
VK_QUEUE_FLAG_BITS_MAX_ENUM   : VkQueueFlagBits : 0x7FFFFFFF

VK_RENDERING_CONTENTS_SECONDARY_COMMAND_BUFFERS_BIT     : VkRenderingFlagBits : 0x00000001
VK_RENDERING_SUSPENDING_BIT                             : VkRenderingFlagBits : 0x00000002
VK_RENDERING_RESUMING_BIT                               : VkRenderingFlagBits : 0x00000004
VK_RENDERING_CONTENTS_INLINE_BIT_EXT                    : VkRenderingFlagBits : 0x00000010
VK_RENDERING_ENABLE_LEGACY_DITHERING_BIT_EXT            : VkRenderingFlagBits : 0x00000008
VK_RENDERING_CONTENTS_SECONDARY_COMMAND_BUFFERS_BIT_KHR : VkRenderingFlagBits : VK_RENDERING_CONTENTS_SECONDARY_COMMAND_BUFFERS_BIT
VK_RENDERING_SUSPENDING_BIT_KHR                         : VkRenderingFlagBits : VK_RENDERING_SUSPENDING_BIT
VK_RENDERING_RESUMING_BIT_KHR                           : VkRenderingFlagBits : VK_RENDERING_RESUMING_BIT
VK_RENDERING_FLAG_BITS_MAX_ENUM                         : VkRenderingFlagBits : 0x7FFFFFFF

VK_RENDER_PASS_CREATE_TRANSFORM_BIT_QCOM : VkRenderPassCreateFlagBits : 0x00000002
VK_RENDER_PASS_CREATE_FLAG_BITS_MAX_ENUM : VkRenderPassCreateFlagBits : 0x7FFFFFFF

VK_RESOLVE_MODE_NONE                               : VkResolveModeFlagBits : 0
VK_RESOLVE_MODE_SAMPLE_ZERO_BIT                    : VkResolveModeFlagBits : 0x00000001
VK_RESOLVE_MODE_AVERAGE_BIT                        : VkResolveModeFlagBits : 0x00000002
VK_RESOLVE_MODE_MIN_BIT                            : VkResolveModeFlagBits : 0x00000004
VK_RESOLVE_MODE_MAX_BIT                            : VkResolveModeFlagBits : 0x00000008
VK_RESOLVE_MODE_EXTERNAL_FORMAT_DOWNSAMPLE_ANDROID : VkResolveModeFlagBits : 0x00000010
VK_RESOLVE_MODE_NONE_KHR                           : VkResolveModeFlagBits : VK_RESOLVE_MODE_NONE
VK_RESOLVE_MODE_SAMPLE_ZERO_BIT_KHR                : VkResolveModeFlagBits : VK_RESOLVE_MODE_SAMPLE_ZERO_BIT
VK_RESOLVE_MODE_AVERAGE_BIT_KHR                    : VkResolveModeFlagBits : VK_RESOLVE_MODE_AVERAGE_BIT
VK_RESOLVE_MODE_MIN_BIT_KHR                        : VkResolveModeFlagBits : VK_RESOLVE_MODE_MIN_BIT
VK_RESOLVE_MODE_MAX_BIT_KHR                        : VkResolveModeFlagBits : VK_RESOLVE_MODE_MAX_BIT
VK_RESOLVE_MODE_FLAG_BITS_MAX_ENUM                 : VkResolveModeFlagBits : 0x7FFFFFFF

VK_SAMPLE_COUNT_1_BIT              : VkSampleCountFlagBits : 0x00000001
VK_SAMPLE_COUNT_2_BIT              : VkSampleCountFlagBits : 0x00000002
VK_SAMPLE_COUNT_4_BIT              : VkSampleCountFlagBits : 0x00000004
VK_SAMPLE_COUNT_8_BIT              : VkSampleCountFlagBits : 0x00000008
VK_SAMPLE_COUNT_16_BIT             : VkSampleCountFlagBits : 0x00000010
VK_SAMPLE_COUNT_32_BIT             : VkSampleCountFlagBits : 0x00000020
VK_SAMPLE_COUNT_64_BIT             : VkSampleCountFlagBits : 0x00000040
VK_SAMPLE_COUNT_FLAG_BITS_MAX_ENUM : VkSampleCountFlagBits : 0x7FFFFFFF

VK_SAMPLER_CREATE_SUBSAMPLED_BIT_EXT                       : VkSamplerCreateFlagBits : 0x00000001
VK_SAMPLER_CREATE_SUBSAMPLED_COARSE_RECONSTRUCTION_BIT_EXT : VkSamplerCreateFlagBits : 0x00000002
VK_SAMPLER_CREATE_DESCRIPTOR_BUFFER_CAPTURE_REPLAY_BIT_EXT : VkSamplerCreateFlagBits : 0x00000008
VK_SAMPLER_CREATE_NON_SEAMLESS_CUBE_MAP_BIT_EXT            : VkSamplerCreateFlagBits : 0x00000004
VK_SAMPLER_CREATE_IMAGE_PROCESSING_BIT_QCOM                : VkSamplerCreateFlagBits : 0x00000010
VK_SAMPLER_CREATE_FLAG_BITS_MAX_ENUM                       : VkSamplerCreateFlagBits : 0x7FFFFFFF

VK_SEMAPHORE_IMPORT_TEMPORARY_BIT      : VkSemaphoreImportFlagBits : 0x00000001
VK_SEMAPHORE_IMPORT_TEMPORARY_BIT_KHR  : VkSemaphoreImportFlagBits : VK_SEMAPHORE_IMPORT_TEMPORARY_BIT
VK_SEMAPHORE_IMPORT_FLAG_BITS_MAX_ENUM : VkSemaphoreImportFlagBits : 0x7FFFFFFF

VK_SEMAPHORE_WAIT_ANY_BIT            : VkSemaphoreWaitFlagBits : 0x00000001
VK_SEMAPHORE_WAIT_ANY_BIT_KHR        : VkSemaphoreWaitFlagBits : VK_SEMAPHORE_WAIT_ANY_BIT
VK_SEMAPHORE_WAIT_FLAG_BITS_MAX_ENUM : VkSemaphoreWaitFlagBits : 0x7FFFFFFF

VK_SHADER_CORE_PROPERTIES_FLAG_BITS_MAX_ENUM_AMD : VkShaderCorePropertiesFlagBitsAMD : 0x7FFFFFFF

VK_SHADER_CREATE_LINK_STAGE_BIT_EXT                       : VkShaderCreateFlagBitsEXT : 0x00000001
VK_SHADER_CREATE_ALLOW_VARYING_SUBGROUP_SIZE_BIT_EXT      : VkShaderCreateFlagBitsEXT : 0x00000002
VK_SHADER_CREATE_REQUIRE_FULL_SUBGROUPS_BIT_EXT           : VkShaderCreateFlagBitsEXT : 0x00000004
VK_SHADER_CREATE_NO_TASK_SHADER_BIT_EXT                   : VkShaderCreateFlagBitsEXT : 0x00000008
VK_SHADER_CREATE_DISPATCH_BASE_BIT_EXT                    : VkShaderCreateFlagBitsEXT : 0x00000010
VK_SHADER_CREATE_FRAGMENT_SHADING_RATE_ATTACHMENT_BIT_EXT : VkShaderCreateFlagBitsEXT : 0x00000020
VK_SHADER_CREATE_FRAGMENT_DENSITY_MAP_ATTACHMENT_BIT_EXT  : VkShaderCreateFlagBitsEXT : 0x00000040
VK_SHADER_CREATE_FLAG_BITS_MAX_ENUM_EXT                   : VkShaderCreateFlagBitsEXT : 0x7FFFFFFF

VK_SHADER_STAGE_VERTEX_BIT                  : VkShaderStageFlagBits : 0x00000001
VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT    : VkShaderStageFlagBits : 0x00000002
VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT : VkShaderStageFlagBits : 0x00000004
VK_SHADER_STAGE_GEOMETRY_BIT                : VkShaderStageFlagBits : 0x00000008
VK_SHADER_STAGE_FRAGMENT_BIT                : VkShaderStageFlagBits : 0x00000010
VK_SHADER_STAGE_COMPUTE_BIT                 : VkShaderStageFlagBits : 0x00000020
VK_SHADER_STAGE_ALL_GRAPHICS                : VkShaderStageFlagBits : 0x0000001F
VK_SHADER_STAGE_ALL                         : VkShaderStageFlagBits : 0x7FFFFFFF
VK_SHADER_STAGE_RAYGEN_BIT_KHR              : VkShaderStageFlagBits : 0x00000100
VK_SHADER_STAGE_ANY_HIT_BIT_KHR             : VkShaderStageFlagBits : 0x00000200
VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR         : VkShaderStageFlagBits : 0x00000400
VK_SHADER_STAGE_MISS_BIT_KHR                : VkShaderStageFlagBits : 0x00000800
VK_SHADER_STAGE_INTERSECTION_BIT_KHR        : VkShaderStageFlagBits : 0x00001000
VK_SHADER_STAGE_CALLABLE_BIT_KHR            : VkShaderStageFlagBits : 0x00002000
VK_SHADER_STAGE_TASK_BIT_EXT                : VkShaderStageFlagBits : 0x00000040
VK_SHADER_STAGE_MESH_BIT_EXT                : VkShaderStageFlagBits : 0x00000080
VK_SHADER_STAGE_SUBPASS_SHADING_BIT_HUAWEI  : VkShaderStageFlagBits : 0x00004000
VK_SHADER_STAGE_CLUSTER_CULLING_BIT_HUAWEI  : VkShaderStageFlagBits : 0x00080000
VK_SHADER_STAGE_RAYGEN_BIT_NV               : VkShaderStageFlagBits : VK_SHADER_STAGE_RAYGEN_BIT_KHR
VK_SHADER_STAGE_ANY_HIT_BIT_NV              : VkShaderStageFlagBits : VK_SHADER_STAGE_ANY_HIT_BIT_KHR
VK_SHADER_STAGE_CLOSEST_HIT_BIT_NV          : VkShaderStageFlagBits : VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR
VK_SHADER_STAGE_MISS_BIT_NV                 : VkShaderStageFlagBits : VK_SHADER_STAGE_MISS_BIT_KHR
VK_SHADER_STAGE_INTERSECTION_BIT_NV         : VkShaderStageFlagBits : VK_SHADER_STAGE_INTERSECTION_BIT_KHR
VK_SHADER_STAGE_CALLABLE_BIT_NV             : VkShaderStageFlagBits : VK_SHADER_STAGE_CALLABLE_BIT_KHR
VK_SHADER_STAGE_TASK_BIT_NV                 : VkShaderStageFlagBits : VK_SHADER_STAGE_TASK_BIT_EXT
VK_SHADER_STAGE_MESH_BIT_NV                 : VkShaderStageFlagBits : VK_SHADER_STAGE_MESH_BIT_EXT
VK_SHADER_STAGE_FLAG_BITS_MAX_ENUM          : VkShaderStageFlagBits : 0x7FFFFFFF

VK_SPARSE_IMAGE_FORMAT_SINGLE_MIPTAIL_BIT         : VkSparseImageFormatFlagBits : 0x00000001
VK_SPARSE_IMAGE_FORMAT_ALIGNED_MIP_SIZE_BIT       : VkSparseImageFormatFlagBits : 0x00000002
VK_SPARSE_IMAGE_FORMAT_NONSTANDARD_BLOCK_SIZE_BIT : VkSparseImageFormatFlagBits : 0x00000004
VK_SPARSE_IMAGE_FORMAT_FLAG_BITS_MAX_ENUM         : VkSparseImageFormatFlagBits : 0x7FFFFFFF

VK_SPARSE_MEMORY_BIND_METADATA_BIT       : VkSparseMemoryBindFlagBits : 0x00000001
VK_SPARSE_MEMORY_BIND_FLAG_BITS_MAX_ENUM : VkSparseMemoryBindFlagBits : 0x7FFFFFFF

VK_STENCIL_FACE_FRONT_BIT          : VkStencilFaceFlagBits : 0x00000001
VK_STENCIL_FACE_BACK_BIT           : VkStencilFaceFlagBits : 0x00000002
VK_STENCIL_FACE_FRONT_AND_BACK     : VkStencilFaceFlagBits : 0x00000003
VK_STENCIL_FRONT_AND_BACK          : VkStencilFaceFlagBits : VK_STENCIL_FACE_FRONT_AND_BACK
VK_STENCIL_FACE_FLAG_BITS_MAX_ENUM : VkStencilFaceFlagBits : 0x7FFFFFFF

VK_SUBGROUP_FEATURE_BASIC_BIT                : VkSubgroupFeatureFlagBits : 0x00000001
VK_SUBGROUP_FEATURE_VOTE_BIT                 : VkSubgroupFeatureFlagBits : 0x00000002
VK_SUBGROUP_FEATURE_ARITHMETIC_BIT           : VkSubgroupFeatureFlagBits : 0x00000004
VK_SUBGROUP_FEATURE_BALLOT_BIT               : VkSubgroupFeatureFlagBits : 0x00000008
VK_SUBGROUP_FEATURE_SHUFFLE_BIT              : VkSubgroupFeatureFlagBits : 0x00000010
VK_SUBGROUP_FEATURE_SHUFFLE_RELATIVE_BIT     : VkSubgroupFeatureFlagBits : 0x00000020
VK_SUBGROUP_FEATURE_CLUSTERED_BIT            : VkSubgroupFeatureFlagBits : 0x00000040
VK_SUBGROUP_FEATURE_QUAD_BIT                 : VkSubgroupFeatureFlagBits : 0x00000080
VK_SUBGROUP_FEATURE_PARTITIONED_BIT_NV       : VkSubgroupFeatureFlagBits : 0x00000100
VK_SUBGROUP_FEATURE_ROTATE_BIT_KHR           : VkSubgroupFeatureFlagBits : 0x00000200
VK_SUBGROUP_FEATURE_ROTATE_CLUSTERED_BIT_KHR : VkSubgroupFeatureFlagBits : 0x00000400
VK_SUBGROUP_FEATURE_FLAG_BITS_MAX_ENUM       : VkSubgroupFeatureFlagBits : 0x7FFFFFFF

VK_SUBMIT_PROTECTED_BIT      : VkSubmitFlagBits : 0x00000001
VK_SUBMIT_PROTECTED_BIT_KHR  : VkSubmitFlagBits : VK_SUBMIT_PROTECTED_BIT
VK_SUBMIT_FLAG_BITS_MAX_ENUM : VkSubmitFlagBits : 0x7FFFFFFF

VK_SUBPASS_DESCRIPTION_PER_VIEW_ATTRIBUTES_BIT_NVX                           : VkSubpassDescriptionFlagBits : 0x00000001
VK_SUBPASS_DESCRIPTION_PER_VIEW_POSITION_X_ONLY_BIT_NVX                      : VkSubpassDescriptionFlagBits : 0x00000002
VK_SUBPASS_DESCRIPTION_FRAGMENT_REGION_BIT_QCOM                              : VkSubpassDescriptionFlagBits : 0x00000004
VK_SUBPASS_DESCRIPTION_SHADER_RESOLVE_BIT_QCOM                               : VkSubpassDescriptionFlagBits : 0x00000008
VK_SUBPASS_DESCRIPTION_RASTERIZATION_ORDER_ATTACHMENT_COLOR_ACCESS_BIT_EXT   : VkSubpassDescriptionFlagBits : 0x00000010
VK_SUBPASS_DESCRIPTION_RASTERIZATION_ORDER_ATTACHMENT_DEPTH_ACCESS_BIT_EXT   : VkSubpassDescriptionFlagBits : 0x00000020
VK_SUBPASS_DESCRIPTION_RASTERIZATION_ORDER_ATTACHMENT_STENCIL_ACCESS_BIT_EXT : VkSubpassDescriptionFlagBits : 0x00000040
VK_SUBPASS_DESCRIPTION_ENABLE_LEGACY_DITHERING_BIT_EXT                       : VkSubpassDescriptionFlagBits : 0x00000080
VK_SUBPASS_DESCRIPTION_RASTERIZATION_ORDER_ATTACHMENT_COLOR_ACCESS_BIT_ARM   : VkSubpassDescriptionFlagBits : VK_SUBPASS_DESCRIPTION_RASTERIZATION_ORDER_ATTACHMENT_COLOR_ACCESS_BIT_EXT
VK_SUBPASS_DESCRIPTION_RASTERIZATION_ORDER_ATTACHMENT_DEPTH_ACCESS_BIT_ARM   : VkSubpassDescriptionFlagBits : VK_SUBPASS_DESCRIPTION_RASTERIZATION_ORDER_ATTACHMENT_DEPTH_ACCESS_BIT_EXT
VK_SUBPASS_DESCRIPTION_RASTERIZATION_ORDER_ATTACHMENT_STENCIL_ACCESS_BIT_ARM : VkSubpassDescriptionFlagBits : VK_SUBPASS_DESCRIPTION_RASTERIZATION_ORDER_ATTACHMENT_STENCIL_ACCESS_BIT_EXT
VK_SUBPASS_DESCRIPTION_FLAG_BITS_MAX_ENUM                                    : VkSubpassDescriptionFlagBits : 0x7FFFFFFF

VK_SURFACE_COUNTER_VBLANK_BIT_EXT         : VkSurfaceCounterFlagBitsEXT : 0x00000001
VK_SURFACE_COUNTER_VBLANK_EXT             : VkSurfaceCounterFlagBitsEXT : VK_SURFACE_COUNTER_VBLANK_BIT_EXT
VK_SURFACE_COUNTER_FLAG_BITS_MAX_ENUM_EXT : VkSurfaceCounterFlagBitsEXT : 0x7FFFFFFF

VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR                     : VkSurfaceTransformFlagBitsKHR : 0x00000001
VK_SURFACE_TRANSFORM_ROTATE_90_BIT_KHR                    : VkSurfaceTransformFlagBitsKHR : 0x00000002
VK_SURFACE_TRANSFORM_ROTATE_180_BIT_KHR                   : VkSurfaceTransformFlagBitsKHR : 0x00000004
VK_SURFACE_TRANSFORM_ROTATE_270_BIT_KHR                   : VkSurfaceTransformFlagBitsKHR : 0x00000008
VK_SURFACE_TRANSFORM_HORIZONTAL_MIRROR_BIT_KHR            : VkSurfaceTransformFlagBitsKHR : 0x00000010
VK_SURFACE_TRANSFORM_HORIZONTAL_MIRROR_ROTATE_90_BIT_KHR  : VkSurfaceTransformFlagBitsKHR : 0x00000020
VK_SURFACE_TRANSFORM_HORIZONTAL_MIRROR_ROTATE_180_BIT_KHR : VkSurfaceTransformFlagBitsKHR : 0x00000040
VK_SURFACE_TRANSFORM_HORIZONTAL_MIRROR_ROTATE_270_BIT_KHR : VkSurfaceTransformFlagBitsKHR : 0x00000080
VK_SURFACE_TRANSFORM_INHERIT_BIT_KHR                      : VkSurfaceTransformFlagBitsKHR : 0x00000100
VK_SURFACE_TRANSFORM_FLAG_BITS_MAX_ENUM_KHR               : VkSurfaceTransformFlagBitsKHR : 0x7FFFFFFF

VK_SWAPCHAIN_CREATE_SPLIT_INSTANCE_BIND_REGIONS_BIT_KHR : VkSwapchainCreateFlagBitsKHR : 0x00000001
VK_SWAPCHAIN_CREATE_PROTECTED_BIT_KHR                   : VkSwapchainCreateFlagBitsKHR : 0x00000002
VK_SWAPCHAIN_CREATE_MUTABLE_FORMAT_BIT_KHR              : VkSwapchainCreateFlagBitsKHR : 0x00000004
VK_SWAPCHAIN_CREATE_DEFERRED_MEMORY_ALLOCATION_BIT_EXT  : VkSwapchainCreateFlagBitsKHR : 0x00000008
VK_SWAPCHAIN_CREATE_FLAG_BITS_MAX_ENUM_KHR              : VkSwapchainCreateFlagBitsKHR : 0x7FFFFFFF

VK_TOOL_PURPOSE_VALIDATION_BIT              : VkToolPurposeFlagBits : 0x00000001
VK_TOOL_PURPOSE_PROFILING_BIT               : VkToolPurposeFlagBits : 0x00000002
VK_TOOL_PURPOSE_TRACING_BIT                 : VkToolPurposeFlagBits : 0x00000004
VK_TOOL_PURPOSE_ADDITIONAL_FEATURES_BIT     : VkToolPurposeFlagBits : 0x00000008
VK_TOOL_PURPOSE_MODIFYING_FEATURES_BIT      : VkToolPurposeFlagBits : 0x00000010
VK_TOOL_PURPOSE_DEBUG_REPORTING_BIT_EXT     : VkToolPurposeFlagBits : 0x00000020
VK_TOOL_PURPOSE_DEBUG_MARKERS_BIT_EXT       : VkToolPurposeFlagBits : 0x00000040
VK_TOOL_PURPOSE_VALIDATION_BIT_EXT          : VkToolPurposeFlagBits : VK_TOOL_PURPOSE_VALIDATION_BIT
VK_TOOL_PURPOSE_PROFILING_BIT_EXT           : VkToolPurposeFlagBits : VK_TOOL_PURPOSE_PROFILING_BIT
VK_TOOL_PURPOSE_TRACING_BIT_EXT             : VkToolPurposeFlagBits : VK_TOOL_PURPOSE_TRACING_BIT
VK_TOOL_PURPOSE_ADDITIONAL_FEATURES_BIT_EXT : VkToolPurposeFlagBits : VK_TOOL_PURPOSE_ADDITIONAL_FEATURES_BIT
VK_TOOL_PURPOSE_MODIFYING_FEATURES_BIT_EXT  : VkToolPurposeFlagBits : VK_TOOL_PURPOSE_MODIFYING_FEATURES_BIT
VK_TOOL_PURPOSE_FLAG_BITS_MAX_ENUM          : VkToolPurposeFlagBits : 0x7FFFFFFF

VK_VIDEO_CAPABILITY_PROTECTED_CONTENT_BIT_KHR         : VkVideoCapabilityFlagBitsKHR : 0x00000001
VK_VIDEO_CAPABILITY_SEPARATE_REFERENCE_IMAGES_BIT_KHR : VkVideoCapabilityFlagBitsKHR : 0x00000002
VK_VIDEO_CAPABILITY_FLAG_BITS_MAX_ENUM_KHR            : VkVideoCapabilityFlagBitsKHR : 0x7FFFFFFF

VK_VIDEO_CHROMA_SUBSAMPLING_INVALID_KHR            : VkVideoChromaSubsamplingFlagBitsKHR : 0
VK_VIDEO_CHROMA_SUBSAMPLING_MONOCHROME_BIT_KHR     : VkVideoChromaSubsamplingFlagBitsKHR : 0x00000001
VK_VIDEO_CHROMA_SUBSAMPLING_420_BIT_KHR            : VkVideoChromaSubsamplingFlagBitsKHR : 0x00000002
VK_VIDEO_CHROMA_SUBSAMPLING_422_BIT_KHR            : VkVideoChromaSubsamplingFlagBitsKHR : 0x00000004
VK_VIDEO_CHROMA_SUBSAMPLING_444_BIT_KHR            : VkVideoChromaSubsamplingFlagBitsKHR : 0x00000008
VK_VIDEO_CHROMA_SUBSAMPLING_FLAG_BITS_MAX_ENUM_KHR : VkVideoChromaSubsamplingFlagBitsKHR : 0x7FFFFFFF

VK_VIDEO_CODEC_OPERATION_NONE_KHR               : VkVideoCodecOperationFlagBitsKHR : 0
VK_VIDEO_CODEC_OPERATION_ENCODE_H264_BIT_KHR    : VkVideoCodecOperationFlagBitsKHR : 0x00010000
VK_VIDEO_CODEC_OPERATION_ENCODE_H265_BIT_KHR    : VkVideoCodecOperationFlagBitsKHR : 0x00020000
VK_VIDEO_CODEC_OPERATION_DECODE_H264_BIT_KHR    : VkVideoCodecOperationFlagBitsKHR : 0x00000001
VK_VIDEO_CODEC_OPERATION_DECODE_H265_BIT_KHR    : VkVideoCodecOperationFlagBitsKHR : 0x00000002
VK_VIDEO_CODEC_OPERATION_DECODE_AV1_BIT_KHR     : VkVideoCodecOperationFlagBitsKHR : 0x00000004
VK_VIDEO_CODEC_OPERATION_FLAG_BITS_MAX_ENUM_KHR : VkVideoCodecOperationFlagBitsKHR : 0x7FFFFFFF

VK_VIDEO_CODING_CONTROL_RESET_BIT_KHR                : VkVideoCodingControlFlagBitsKHR : 0x00000001
VK_VIDEO_CODING_CONTROL_ENCODE_RATE_CONTROL_BIT_KHR  : VkVideoCodingControlFlagBitsKHR : 0x00000002
VK_VIDEO_CODING_CONTROL_ENCODE_QUALITY_LEVEL_BIT_KHR : VkVideoCodingControlFlagBitsKHR : 0x00000004
VK_VIDEO_CODING_CONTROL_FLAG_BITS_MAX_ENUM_KHR       : VkVideoCodingControlFlagBitsKHR : 0x7FFFFFFF

VK_VIDEO_COMPONENT_BIT_DEPTH_INVALID_KHR            : VkVideoComponentBitDepthFlagBitsKHR : 0
VK_VIDEO_COMPONENT_BIT_DEPTH_8_BIT_KHR              : VkVideoComponentBitDepthFlagBitsKHR : 0x00000001
VK_VIDEO_COMPONENT_BIT_DEPTH_10_BIT_KHR             : VkVideoComponentBitDepthFlagBitsKHR : 0x00000004
VK_VIDEO_COMPONENT_BIT_DEPTH_12_BIT_KHR             : VkVideoComponentBitDepthFlagBitsKHR : 0x00000010
VK_VIDEO_COMPONENT_BIT_DEPTH_FLAG_BITS_MAX_ENUM_KHR : VkVideoComponentBitDepthFlagBitsKHR : 0x7FFFFFFF

VK_VIDEO_DECODE_CAPABILITY_DPB_AND_OUTPUT_COINCIDE_BIT_KHR : VkVideoDecodeCapabilityFlagBitsKHR : 0x00000001
VK_VIDEO_DECODE_CAPABILITY_DPB_AND_OUTPUT_DISTINCT_BIT_KHR : VkVideoDecodeCapabilityFlagBitsKHR : 0x00000002
VK_VIDEO_DECODE_CAPABILITY_FLAG_BITS_MAX_ENUM_KHR          : VkVideoDecodeCapabilityFlagBitsKHR : 0x7FFFFFFF

VK_VIDEO_DECODE_H264_PICTURE_LAYOUT_PROGRESSIVE_KHR                      : VkVideoDecodeH264PictureLayoutFlagBitsKHR : 0
VK_VIDEO_DECODE_H264_PICTURE_LAYOUT_INTERLACED_INTERLEAVED_LINES_BIT_KHR : VkVideoDecodeH264PictureLayoutFlagBitsKHR : 0x00000001
VK_VIDEO_DECODE_H264_PICTURE_LAYOUT_INTERLACED_SEPARATE_PLANES_BIT_KHR   : VkVideoDecodeH264PictureLayoutFlagBitsKHR : 0x00000002
VK_VIDEO_DECODE_H264_PICTURE_LAYOUT_FLAG_BITS_MAX_ENUM_KHR               : VkVideoDecodeH264PictureLayoutFlagBitsKHR : 0x7FFFFFFF

VK_VIDEO_DECODE_USAGE_DEFAULT_KHR            : VkVideoDecodeUsageFlagBitsKHR : 0
VK_VIDEO_DECODE_USAGE_TRANSCODING_BIT_KHR    : VkVideoDecodeUsageFlagBitsKHR : 0x00000001
VK_VIDEO_DECODE_USAGE_OFFLINE_BIT_KHR        : VkVideoDecodeUsageFlagBitsKHR : 0x00000002
VK_VIDEO_DECODE_USAGE_STREAMING_BIT_KHR      : VkVideoDecodeUsageFlagBitsKHR : 0x00000004
VK_VIDEO_DECODE_USAGE_FLAG_BITS_MAX_ENUM_KHR : VkVideoDecodeUsageFlagBitsKHR : 0x7FFFFFFF

VK_VIDEO_ENCODE_CAPABILITY_PRECEDING_EXTERNALLY_ENCODED_BYTES_BIT_KHR            : VkVideoEncodeCapabilityFlagBitsKHR : 0x00000001
VK_VIDEO_ENCODE_CAPABILITY_INSUFFICIENT_BITSTREAM_BUFFER_RANGE_DETECTION_BIT_KHR : VkVideoEncodeCapabilityFlagBitsKHR : 0x00000002
VK_VIDEO_ENCODE_CAPABILITY_FLAG_BITS_MAX_ENUM_KHR                                : VkVideoEncodeCapabilityFlagBitsKHR : 0x7FFFFFFF

VK_VIDEO_ENCODE_CONTENT_DEFAULT_KHR            : VkVideoEncodeContentFlagBitsKHR : 0
VK_VIDEO_ENCODE_CONTENT_CAMERA_BIT_KHR         : VkVideoEncodeContentFlagBitsKHR : 0x00000001
VK_VIDEO_ENCODE_CONTENT_DESKTOP_BIT_KHR        : VkVideoEncodeContentFlagBitsKHR : 0x00000002
VK_VIDEO_ENCODE_CONTENT_RENDERED_BIT_KHR       : VkVideoEncodeContentFlagBitsKHR : 0x00000004
VK_VIDEO_ENCODE_CONTENT_FLAG_BITS_MAX_ENUM_KHR : VkVideoEncodeContentFlagBitsKHR : 0x7FFFFFFF

VK_VIDEO_ENCODE_FEEDBACK_BITSTREAM_BUFFER_OFFSET_BIT_KHR : VkVideoEncodeFeedbackFlagBitsKHR : 0x00000001
VK_VIDEO_ENCODE_FEEDBACK_BITSTREAM_BYTES_WRITTEN_BIT_KHR : VkVideoEncodeFeedbackFlagBitsKHR : 0x00000002
VK_VIDEO_ENCODE_FEEDBACK_BITSTREAM_HAS_OVERRIDES_BIT_KHR : VkVideoEncodeFeedbackFlagBitsKHR : 0x00000004
VK_VIDEO_ENCODE_FEEDBACK_FLAG_BITS_MAX_ENUM_KHR          : VkVideoEncodeFeedbackFlagBitsKHR : 0x7FFFFFFF

VK_VIDEO_ENCODE_FLAG_BITS_MAX_ENUM_KHR : VkVideoEncodeFlagBitsKHR : 0x7FFFFFFF

VK_VIDEO_ENCODE_H264_CAPABILITY_HRD_COMPLIANCE_BIT_KHR                    : VkVideoEncodeH264CapabilityFlagBitsKHR : 0x00000001
VK_VIDEO_ENCODE_H264_CAPABILITY_PREDICTION_WEIGHT_TABLE_GENERATED_BIT_KHR : VkVideoEncodeH264CapabilityFlagBitsKHR : 0x00000002
VK_VIDEO_ENCODE_H264_CAPABILITY_ROW_UNALIGNED_SLICE_BIT_KHR               : VkVideoEncodeH264CapabilityFlagBitsKHR : 0x00000004
VK_VIDEO_ENCODE_H264_CAPABILITY_DIFFERENT_SLICE_TYPE_BIT_KHR              : VkVideoEncodeH264CapabilityFlagBitsKHR : 0x00000008
VK_VIDEO_ENCODE_H264_CAPABILITY_B_FRAME_IN_L0_LIST_BIT_KHR                : VkVideoEncodeH264CapabilityFlagBitsKHR : 0x00000010
VK_VIDEO_ENCODE_H264_CAPABILITY_B_FRAME_IN_L1_LIST_BIT_KHR                : VkVideoEncodeH264CapabilityFlagBitsKHR : 0x00000020
VK_VIDEO_ENCODE_H264_CAPABILITY_PER_PICTURE_TYPE_MIN_MAX_QP_BIT_KHR       : VkVideoEncodeH264CapabilityFlagBitsKHR : 0x00000040
VK_VIDEO_ENCODE_H264_CAPABILITY_PER_SLICE_CONSTANT_QP_BIT_KHR             : VkVideoEncodeH264CapabilityFlagBitsKHR : 0x00000080
VK_VIDEO_ENCODE_H264_CAPABILITY_GENERATE_PREFIX_NALU_BIT_KHR              : VkVideoEncodeH264CapabilityFlagBitsKHR : 0x00000100
VK_VIDEO_ENCODE_H264_CAPABILITY_FLAG_BITS_MAX_ENUM_KHR                    : VkVideoEncodeH264CapabilityFlagBitsKHR : 0x7FFFFFFF

VK_VIDEO_ENCODE_H264_RATE_CONTROL_ATTEMPT_HRD_COMPLIANCE_BIT_KHR        : VkVideoEncodeH264RateControlFlagBitsKHR : 0x00000001
VK_VIDEO_ENCODE_H264_RATE_CONTROL_REGULAR_GOP_BIT_KHR                   : VkVideoEncodeH264RateControlFlagBitsKHR : 0x00000002
VK_VIDEO_ENCODE_H264_RATE_CONTROL_REFERENCE_PATTERN_FLAT_BIT_KHR        : VkVideoEncodeH264RateControlFlagBitsKHR : 0x00000004
VK_VIDEO_ENCODE_H264_RATE_CONTROL_REFERENCE_PATTERN_DYADIC_BIT_KHR      : VkVideoEncodeH264RateControlFlagBitsKHR : 0x00000008
VK_VIDEO_ENCODE_H264_RATE_CONTROL_TEMPORAL_LAYER_PATTERN_DYADIC_BIT_KHR : VkVideoEncodeH264RateControlFlagBitsKHR : 0x00000010
VK_VIDEO_ENCODE_H264_RATE_CONTROL_FLAG_BITS_MAX_ENUM_KHR                : VkVideoEncodeH264RateControlFlagBitsKHR : 0x7FFFFFFF

VK_VIDEO_ENCODE_H264_STD_SEPARATE_COLOR_PLANE_FLAG_SET_BIT_KHR            : VkVideoEncodeH264StdFlagBitsKHR : 0x00000001
VK_VIDEO_ENCODE_H264_STD_QPPRIME_Y_ZERO_TRANSFORM_BYPASS_FLAG_SET_BIT_KHR : VkVideoEncodeH264StdFlagBitsKHR : 0x00000002
VK_VIDEO_ENCODE_H264_STD_SCALING_MATRIX_PRESENT_FLAG_SET_BIT_KHR          : VkVideoEncodeH264StdFlagBitsKHR : 0x00000004
VK_VIDEO_ENCODE_H264_STD_CHROMA_QP_INDEX_OFFSET_BIT_KHR                   : VkVideoEncodeH264StdFlagBitsKHR : 0x00000008
VK_VIDEO_ENCODE_H264_STD_SECOND_CHROMA_QP_INDEX_OFFSET_BIT_KHR            : VkVideoEncodeH264StdFlagBitsKHR : 0x00000010
VK_VIDEO_ENCODE_H264_STD_PIC_INIT_QP_MINUS26_BIT_KHR                      : VkVideoEncodeH264StdFlagBitsKHR : 0x00000020
VK_VIDEO_ENCODE_H264_STD_WEIGHTED_PRED_FLAG_SET_BIT_KHR                   : VkVideoEncodeH264StdFlagBitsKHR : 0x00000040
VK_VIDEO_ENCODE_H264_STD_WEIGHTED_BIPRED_IDC_EXPLICIT_BIT_KHR             : VkVideoEncodeH264StdFlagBitsKHR : 0x00000080
VK_VIDEO_ENCODE_H264_STD_WEIGHTED_BIPRED_IDC_IMPLICIT_BIT_KHR             : VkVideoEncodeH264StdFlagBitsKHR : 0x00000100
VK_VIDEO_ENCODE_H264_STD_TRANSFORM_8X8_MODE_FLAG_SET_BIT_KHR              : VkVideoEncodeH264StdFlagBitsKHR : 0x00000200
VK_VIDEO_ENCODE_H264_STD_DIRECT_SPATIAL_MV_PRED_FLAG_UNSET_BIT_KHR        : VkVideoEncodeH264StdFlagBitsKHR : 0x00000400
VK_VIDEO_ENCODE_H264_STD_ENTROPY_CODING_MODE_FLAG_UNSET_BIT_KHR           : VkVideoEncodeH264StdFlagBitsKHR : 0x00000800
VK_VIDEO_ENCODE_H264_STD_ENTROPY_CODING_MODE_FLAG_SET_BIT_KHR             : VkVideoEncodeH264StdFlagBitsKHR : 0x00001000
VK_VIDEO_ENCODE_H264_STD_DIRECT_8X8_INFERENCE_FLAG_UNSET_BIT_KHR          : VkVideoEncodeH264StdFlagBitsKHR : 0x00002000
VK_VIDEO_ENCODE_H264_STD_CONSTRAINED_INTRA_PRED_FLAG_SET_BIT_KHR          : VkVideoEncodeH264StdFlagBitsKHR : 0x00004000
VK_VIDEO_ENCODE_H264_STD_DEBLOCKING_FILTER_DISABLED_BIT_KHR               : VkVideoEncodeH264StdFlagBitsKHR : 0x00008000
VK_VIDEO_ENCODE_H264_STD_DEBLOCKING_FILTER_ENABLED_BIT_KHR                : VkVideoEncodeH264StdFlagBitsKHR : 0x00010000
VK_VIDEO_ENCODE_H264_STD_DEBLOCKING_FILTER_PARTIAL_BIT_KHR                : VkVideoEncodeH264StdFlagBitsKHR : 0x00020000
VK_VIDEO_ENCODE_H264_STD_SLICE_QP_DELTA_BIT_KHR                           : VkVideoEncodeH264StdFlagBitsKHR : 0x00080000
VK_VIDEO_ENCODE_H264_STD_DIFFERENT_SLICE_QP_DELTA_BIT_KHR                 : VkVideoEncodeH264StdFlagBitsKHR : 0x00100000
VK_VIDEO_ENCODE_H264_STD_FLAG_BITS_MAX_ENUM_KHR                           : VkVideoEncodeH264StdFlagBitsKHR : 0x7FFFFFFF

VK_VIDEO_ENCODE_H265_CAPABILITY_HRD_COMPLIANCE_BIT_KHR                    : VkVideoEncodeH265CapabilityFlagBitsKHR : 0x00000001
VK_VIDEO_ENCODE_H265_CAPABILITY_PREDICTION_WEIGHT_TABLE_GENERATED_BIT_KHR : VkVideoEncodeH265CapabilityFlagBitsKHR : 0x00000002
VK_VIDEO_ENCODE_H265_CAPABILITY_ROW_UNALIGNED_SLICE_SEGMENT_BIT_KHR       : VkVideoEncodeH265CapabilityFlagBitsKHR : 0x00000004
VK_VIDEO_ENCODE_H265_CAPABILITY_DIFFERENT_SLICE_SEGMENT_TYPE_BIT_KHR      : VkVideoEncodeH265CapabilityFlagBitsKHR : 0x00000008
VK_VIDEO_ENCODE_H265_CAPABILITY_B_FRAME_IN_L0_LIST_BIT_KHR                : VkVideoEncodeH265CapabilityFlagBitsKHR : 0x00000010
VK_VIDEO_ENCODE_H265_CAPABILITY_B_FRAME_IN_L1_LIST_BIT_KHR                : VkVideoEncodeH265CapabilityFlagBitsKHR : 0x00000020
VK_VIDEO_ENCODE_H265_CAPABILITY_PER_PICTURE_TYPE_MIN_MAX_QP_BIT_KHR       : VkVideoEncodeH265CapabilityFlagBitsKHR : 0x00000040
VK_VIDEO_ENCODE_H265_CAPABILITY_PER_SLICE_SEGMENT_CONSTANT_QP_BIT_KHR     : VkVideoEncodeH265CapabilityFlagBitsKHR : 0x00000080
VK_VIDEO_ENCODE_H265_CAPABILITY_MULTIPLE_TILES_PER_SLICE_SEGMENT_BIT_KHR  : VkVideoEncodeH265CapabilityFlagBitsKHR : 0x00000100
VK_VIDEO_ENCODE_H265_CAPABILITY_MULTIPLE_SLICE_SEGMENTS_PER_TILE_BIT_KHR  : VkVideoEncodeH265CapabilityFlagBitsKHR : 0x00000200
VK_VIDEO_ENCODE_H265_CAPABILITY_FLAG_BITS_MAX_ENUM_KHR                    : VkVideoEncodeH265CapabilityFlagBitsKHR : 0x7FFFFFFF

VK_VIDEO_ENCODE_H265_CTB_SIZE_16_BIT_KHR             : VkVideoEncodeH265CtbSizeFlagBitsKHR : 0x00000001
VK_VIDEO_ENCODE_H265_CTB_SIZE_32_BIT_KHR             : VkVideoEncodeH265CtbSizeFlagBitsKHR : 0x00000002
VK_VIDEO_ENCODE_H265_CTB_SIZE_64_BIT_KHR             : VkVideoEncodeH265CtbSizeFlagBitsKHR : 0x00000004
VK_VIDEO_ENCODE_H265_CTB_SIZE_FLAG_BITS_MAX_ENUM_KHR : VkVideoEncodeH265CtbSizeFlagBitsKHR : 0x7FFFFFFF

VK_VIDEO_ENCODE_H265_RATE_CONTROL_ATTEMPT_HRD_COMPLIANCE_BIT_KHR            : VkVideoEncodeH265RateControlFlagBitsKHR : 0x00000001
VK_VIDEO_ENCODE_H265_RATE_CONTROL_REGULAR_GOP_BIT_KHR                       : VkVideoEncodeH265RateControlFlagBitsKHR : 0x00000002
VK_VIDEO_ENCODE_H265_RATE_CONTROL_REFERENCE_PATTERN_FLAT_BIT_KHR            : VkVideoEncodeH265RateControlFlagBitsKHR : 0x00000004
VK_VIDEO_ENCODE_H265_RATE_CONTROL_REFERENCE_PATTERN_DYADIC_BIT_KHR          : VkVideoEncodeH265RateControlFlagBitsKHR : 0x00000008
VK_VIDEO_ENCODE_H265_RATE_CONTROL_TEMPORAL_SUB_LAYER_PATTERN_DYADIC_BIT_KHR : VkVideoEncodeH265RateControlFlagBitsKHR : 0x00000010
VK_VIDEO_ENCODE_H265_RATE_CONTROL_FLAG_BITS_MAX_ENUM_KHR                    : VkVideoEncodeH265RateControlFlagBitsKHR : 0x7FFFFFFF

VK_VIDEO_ENCODE_H265_STD_SEPARATE_COLOR_PLANE_FLAG_SET_BIT_KHR                : VkVideoEncodeH265StdFlagBitsKHR : 0x00000001
VK_VIDEO_ENCODE_H265_STD_SAMPLE_ADAPTIVE_OFFSET_ENABLED_FLAG_SET_BIT_KHR      : VkVideoEncodeH265StdFlagBitsKHR : 0x00000002
VK_VIDEO_ENCODE_H265_STD_SCALING_LIST_DATA_PRESENT_FLAG_SET_BIT_KHR           : VkVideoEncodeH265StdFlagBitsKHR : 0x00000004
VK_VIDEO_ENCODE_H265_STD_PCM_ENABLED_FLAG_SET_BIT_KHR                         : VkVideoEncodeH265StdFlagBitsKHR : 0x00000008
VK_VIDEO_ENCODE_H265_STD_SPS_TEMPORAL_MVP_ENABLED_FLAG_SET_BIT_KHR            : VkVideoEncodeH265StdFlagBitsKHR : 0x00000010
VK_VIDEO_ENCODE_H265_STD_INIT_QP_MINUS26_BIT_KHR                              : VkVideoEncodeH265StdFlagBitsKHR : 0x00000020
VK_VIDEO_ENCODE_H265_STD_WEIGHTED_PRED_FLAG_SET_BIT_KHR                       : VkVideoEncodeH265StdFlagBitsKHR : 0x00000040
VK_VIDEO_ENCODE_H265_STD_WEIGHTED_BIPRED_FLAG_SET_BIT_KHR                     : VkVideoEncodeH265StdFlagBitsKHR : 0x00000080
VK_VIDEO_ENCODE_H265_STD_LOG2_PARALLEL_MERGE_LEVEL_MINUS2_BIT_KHR             : VkVideoEncodeH265StdFlagBitsKHR : 0x00000100
VK_VIDEO_ENCODE_H265_STD_SIGN_DATA_HIDING_ENABLED_FLAG_SET_BIT_KHR            : VkVideoEncodeH265StdFlagBitsKHR : 0x00000200
VK_VIDEO_ENCODE_H265_STD_TRANSFORM_SKIP_ENABLED_FLAG_SET_BIT_KHR              : VkVideoEncodeH265StdFlagBitsKHR : 0x00000400
VK_VIDEO_ENCODE_H265_STD_TRANSFORM_SKIP_ENABLED_FLAG_UNSET_BIT_KHR            : VkVideoEncodeH265StdFlagBitsKHR : 0x00000800
VK_VIDEO_ENCODE_H265_STD_PPS_SLICE_CHROMA_QP_OFFSETS_PRESENT_FLAG_SET_BIT_KHR : VkVideoEncodeH265StdFlagBitsKHR : 0x00001000
VK_VIDEO_ENCODE_H265_STD_TRANSQUANT_BYPASS_ENABLED_FLAG_SET_BIT_KHR           : VkVideoEncodeH265StdFlagBitsKHR : 0x00002000
VK_VIDEO_ENCODE_H265_STD_CONSTRAINED_INTRA_PRED_FLAG_SET_BIT_KHR              : VkVideoEncodeH265StdFlagBitsKHR : 0x00004000
VK_VIDEO_ENCODE_H265_STD_ENTROPY_CODING_SYNC_ENABLED_FLAG_SET_BIT_KHR         : VkVideoEncodeH265StdFlagBitsKHR : 0x00008000
VK_VIDEO_ENCODE_H265_STD_DEBLOCKING_FILTER_OVERRIDE_ENABLED_FLAG_SET_BIT_KHR  : VkVideoEncodeH265StdFlagBitsKHR : 0x00010000
VK_VIDEO_ENCODE_H265_STD_DEPENDENT_SLICE_SEGMENTS_ENABLED_FLAG_SET_BIT_KHR    : VkVideoEncodeH265StdFlagBitsKHR : 0x00020000
VK_VIDEO_ENCODE_H265_STD_DEPENDENT_SLICE_SEGMENT_FLAG_SET_BIT_KHR             : VkVideoEncodeH265StdFlagBitsKHR : 0x00040000
VK_VIDEO_ENCODE_H265_STD_SLICE_QP_DELTA_BIT_KHR                               : VkVideoEncodeH265StdFlagBitsKHR : 0x00080000
VK_VIDEO_ENCODE_H265_STD_DIFFERENT_SLICE_QP_DELTA_BIT_KHR                     : VkVideoEncodeH265StdFlagBitsKHR : 0x00100000
VK_VIDEO_ENCODE_H265_STD_FLAG_BITS_MAX_ENUM_KHR                               : VkVideoEncodeH265StdFlagBitsKHR : 0x7FFFFFFF

VK_VIDEO_ENCODE_H265_TRANSFORM_BLOCK_SIZE_4_BIT_KHR              : VkVideoEncodeH265TransformBlockSizeFlagBitsKHR : 0x00000001
VK_VIDEO_ENCODE_H265_TRANSFORM_BLOCK_SIZE_8_BIT_KHR              : VkVideoEncodeH265TransformBlockSizeFlagBitsKHR : 0x00000002
VK_VIDEO_ENCODE_H265_TRANSFORM_BLOCK_SIZE_16_BIT_KHR             : VkVideoEncodeH265TransformBlockSizeFlagBitsKHR : 0x00000004
VK_VIDEO_ENCODE_H265_TRANSFORM_BLOCK_SIZE_32_BIT_KHR             : VkVideoEncodeH265TransformBlockSizeFlagBitsKHR : 0x00000008
VK_VIDEO_ENCODE_H265_TRANSFORM_BLOCK_SIZE_FLAG_BITS_MAX_ENUM_KHR : VkVideoEncodeH265TransformBlockSizeFlagBitsKHR : 0x7FFFFFFF

VK_VIDEO_ENCODE_RATE_CONTROL_MODE_DEFAULT_KHR            : VkVideoEncodeRateControlModeFlagBitsKHR : 0
VK_VIDEO_ENCODE_RATE_CONTROL_MODE_DISABLED_BIT_KHR       : VkVideoEncodeRateControlModeFlagBitsKHR : 0x00000001
VK_VIDEO_ENCODE_RATE_CONTROL_MODE_CBR_BIT_KHR            : VkVideoEncodeRateControlModeFlagBitsKHR : 0x00000002
VK_VIDEO_ENCODE_RATE_CONTROL_MODE_VBR_BIT_KHR            : VkVideoEncodeRateControlModeFlagBitsKHR : 0x00000004
VK_VIDEO_ENCODE_RATE_CONTROL_MODE_FLAG_BITS_MAX_ENUM_KHR : VkVideoEncodeRateControlModeFlagBitsKHR : 0x7FFFFFFF

VK_VIDEO_ENCODE_USAGE_DEFAULT_KHR            : VkVideoEncodeUsageFlagBitsKHR : 0
VK_VIDEO_ENCODE_USAGE_TRANSCODING_BIT_KHR    : VkVideoEncodeUsageFlagBitsKHR : 0x00000001
VK_VIDEO_ENCODE_USAGE_STREAMING_BIT_KHR      : VkVideoEncodeUsageFlagBitsKHR : 0x00000002
VK_VIDEO_ENCODE_USAGE_RECORDING_BIT_KHR      : VkVideoEncodeUsageFlagBitsKHR : 0x00000004
VK_VIDEO_ENCODE_USAGE_CONFERENCING_BIT_KHR   : VkVideoEncodeUsageFlagBitsKHR : 0x00000008
VK_VIDEO_ENCODE_USAGE_FLAG_BITS_MAX_ENUM_KHR : VkVideoEncodeUsageFlagBitsKHR : 0x7FFFFFFF

VK_VIDEO_SESSION_CREATE_PROTECTED_CONTENT_BIT_KHR                    : VkVideoSessionCreateFlagBitsKHR : 0x00000001
VK_VIDEO_SESSION_CREATE_ALLOW_ENCODE_PARAMETER_OPTIMIZATIONS_BIT_KHR : VkVideoSessionCreateFlagBitsKHR : 0x00000002
VK_VIDEO_SESSION_CREATE_INLINE_QUERIES_BIT_KHR                       : VkVideoSessionCreateFlagBitsKHR : 0x00000004
VK_VIDEO_SESSION_CREATE_FLAG_BITS_MAX_ENUM_KHR                       : VkVideoSessionCreateFlagBitsKHR : 0x7FFFFFFF

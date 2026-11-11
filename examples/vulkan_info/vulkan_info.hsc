package vulkan_info

import io
import memory from "std"
import runtime from "base"
import vulkan as vk from "vendor"

// The text in a fixed-size C string field, up to its terminator
field_text :: fn(field: ptr[u8[256]]) -> string {
    for byte, i in field^ {
        if byte == 0 {
            return string_of(&field[0], cast[usize](i))
        }
    }
    return string_of(&field[0], 256)
}

main :: fn() -> int {
    version : u32 = 0
    _ = vk.vkEnumerateInstanceVersion(&version)
    printf("Vulkan %.%.%\n", vk.VK_API_VERSION_MAJOR(version), vk.VK_API_VERSION_MINOR(version), vk.VK_API_VERSION_PATCH(version))

    /*
     * What the structs passed to Vulkan point at comes from an arena: the struct passed can be a local, but anything it
     * points to can't be, any more than it could be kept in a struct on the heap (docs/memory.md, Pointers to the Stack)
     */
    frame :: memory.make_arena() or_return 1
    defer memory.free_arena(frame)
    from_frame :: memory.arena_allocator(frame)

    application :: memory.new_value(vk.VkApplicationInfo.{pApplicationName = "vulkan_info", apiVersion = vk.VK_API_VERSION_1_3},
        from_frame)
    create := vk.VkInstanceCreateInfo.{pApplicationInfo = application}
    #if OS == .Windows {
        // The surface extensions, which the platform's presentation queries below need enabled
        extensions :: memory.new_value(cstring.[vk.VK_KHR_SURFACE_EXTENSION_NAME, vk.VK_KHR_WIN32_SURFACE_EXTENSION_NAME],
            from_frame)
        create.enabledExtensionCount = 2
        create.ppEnabledExtensionNames = &extensions[0]
    }
    instance : vk.VkInstance
    result := vk.vkCreateInstance(&create, null, &instance)
    if result != .VK_SUCCESS {
        printf("vkCreateInstance: %\n", result)
        return 1
    }
    defer vk.vkDestroyInstance(instance, null)
    memory.reset_arena(frame)

    // How many there are, then each of them
    count : u32 = 0
    _ = vk.vkEnumeratePhysicalDevices(instance, &count, null)
    devices, error :: runtime.new_array(vk.VkPhysicalDevice, cast[usize](count), from_frame)
    if error != null || devices.count == 0 {
        printf("no physical devices\n")
        return 1
    }
    result = vk.vkEnumeratePhysicalDevices(instance, &count, &devices[0])
    printf("% physical devices (%)\n", count, result)
    for device, i in devices {
        mark :: memory.arena_mark(frame)
        defer memory.arena_restore(frame, mark)

        properties : vk.VkPhysicalDeviceProperties
        vk.vkGetPhysicalDeviceProperties(device, &properties)
        printf("  %: %, Vulkan %.%\n", i, field_text(&properties.deviceName), vk.VK_API_VERSION_MAJOR(properties.apiVersion),
            vk.VK_API_VERSION_MINOR(properties.apiVersion))

        // Its features, through a pNext chain: Features2, then 1.2's, then 1.3's
        features13 :: memory.new_value(vk.VkPhysicalDeviceVulkan13Features.{}, from_frame)
        features12 :: memory.new_value(vk.VkPhysicalDeviceVulkan12Features.{pNext = features13}, from_frame)
        features := vk.VkPhysicalDeviceFeatures2.{pNext = features12}
        vk.vkGetPhysicalDeviceFeatures2(device, &features)
        printf("     dynamic rendering %, synchronization2 %, buffer device address %, geometry shaders %\n",
            features13.dynamicRendering, features13.synchronization2, features12.bufferDeviceAddress,
            features.features.geometryShader)

        // Which queue families can present to a window, through the platform's surface extension the loader exports
        #if OS == .Windows {
            families : u32 = 0
            vk.vkGetPhysicalDeviceQueueFamilyProperties(device, &families, null)
            for family in 0..<families {
                printf("     queue family % presents to Win32 windows: %\n", family,
                    vk.vkGetPhysicalDeviceWin32PresentationSupportKHR(device, family))
            }
        }
    }

    // Commands the loader doesn't export, found by name, and called through their pointers
    procs : vk.VulkanInstanceProcs
    vk.load_instance_procs(instance, &procs)
    printf("vkCreateDebugUtilsMessengerEXT found: %\n", procs.vkCreateDebugUtilsMessengerEXT is_some)
    match procs.vkGetPhysicalDeviceToolPropertiesEXT {
        case Some(tool_properties) => {
            tools : u32 = 0
            tools_result :: tool_properties(devices[0], &tools, null)
            printf("tools on device 0: % (%)\n", tools, tools_result)
        }
        case None => {}
    }
    return 0
}

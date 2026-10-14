package valid_scenarios

// Constants a bootloader fills in before the program starts, in sections a linker script orders
REQUESTS_START #externally_initialized #section(".limine_requests_start") :: u64.[0xf6b8f4b39de7d1ae, 0xfab91a6940fcb9cf, 0x785c6ed015d3e316, 0x181e920a7852b9d9]
MEMORY_MAP_REQUEST #externally_initialized #section(".limine_requests") :: MemoryMapRequest.{
    id = u64.[0xc7b1dd30df4c8b88, 0x0a82e883a194f07b, 0x67cf3d9d378a806f, 0xe304acdfc50c3c62],
}
REQUESTS_END #externally_initialized #section(".limine_requests_end") :: u64.[0xadc0e0531bb10d03, 0x9572709f31764c62]

memory_map :: fn() -> ptr[MemoryMapResponse]? {
    return MEMORY_MAP_REQUEST.response
}

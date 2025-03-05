#pragma once

#include <cstddef>
#include <memory_resource>

namespace hemera {

	using MemResource = std::pmr::memory_resource;

	template <typename T = std::byte>
	using Allocator = std::pmr::polymorphic_allocator<T>;

	template <typename T>
	using MyVector = std::vector<T, Allocator<T>>;

	using MyString = std::basic_string<char, std::char_traits<char>, Allocator<char>>;

}
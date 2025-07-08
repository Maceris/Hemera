#pragma once

#include <cstddef>
#include <map>
#include <memory_resource>
#include <vector>

namespace hemera {

	using MemResource = std::pmr::memory_resource;

	template <typename T = std::byte>
	using Allocator = std::pmr::polymorphic_allocator<T>;

	template <typename T>
	using MyVector = std::vector<T, Allocator<T>>;

	using MyString = std::basic_string<char, std::char_traits<char>, Allocator<char>>;

	template <typename K, typename V>
	using MyMap = std::map<K, V, Allocator<std::pair<const K, V>>>;

	/// <summary>
	/// A cheap const pointer to an interned string.
	/// </summary>
	using InternedString = MyString const*;
	
	/// <summary>
	/// Converts the provided string to an interned version, creating a new
	/// one if this is a newly encountered string.
	/// </summary>
	/// <param name="string">The string we want to intern.</param>
	/// <returns>The interned version of the provided string.</returns>
	InternedString intern(const MyString* string);

	/// <summary>
	/// Converts the provided string to an interned version, creating a new
	/// one if this is a newly encountered string.
	/// </summary>
	/// <param name="string">The string we want to intern.</param>
	/// <returns>The interned version of the provided string.</returns>
	InternedString intern(const MyString&& string);

	/// <summary>
	/// Deletes the interned copy of a string, when we are certain it will
	/// never be needed again. Any outstanding copies of the InternedString
	/// will become invalid, new interned versions of the same contents
	/// would have a different value.
	/// </summary>
	/// <param name="string">The interned string we want to delete.</param>
	void delete_interned_string(InternedString string);

	/// <summary>
	/// Delete every interned string, invalidating every copy of them.
	/// Should only be used while testing, restarting the whole program,
	/// or similar situations.
	/// </summary>
	void purge_interned_string_cache();
}
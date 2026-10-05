#pragma once

#include "memory/allocator.h"

/// <summary>
/// Sets up the interned string cache for one test, and purges it when the
/// test ends, including when an ASSERT or FAIL returns early. Otherwise the
/// next test's setup would find the cache still there.
/// </summary>
struct StringCacheGuard {
	StringCacheGuard() {
		hemera::initialize_interned_string_cache();
	}
	~StringCacheGuard() {
		hemera::purge_interned_string_cache();
	}
	StringCacheGuard(const StringCacheGuard&) = delete;
	StringCacheGuard(StringCacheGuard&&) = delete;
	StringCacheGuard& operator=(const StringCacheGuard&) = delete;
	StringCacheGuard& operator=(StringCacheGuard&&) = delete;
};

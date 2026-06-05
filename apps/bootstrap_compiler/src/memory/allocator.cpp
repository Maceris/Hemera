#include <cstdint>
#include <functional>
#include <mutex>

#include "memory/allocator.h"

namespace hemera {
	
	struct StringCache {
		Allocator<MyString> string_alloc;
		std::hash<MyString> string_hasher;
		std::map<size_t, MyString*> interned_strings;
		std::mutex cache_mutex;
	};

	static StringCache* cache;

	void init_interned_string_cache() {
		if (cache != nullptr) {
			cache = new StringCache();
		}
	}

	InternedString intern(const MyString* string) {
		if (string == nullptr || cache == nullptr) {
			return nullptr;
		}

		const size_t hash_value = cache->string_hasher(*string);

		std::lock_guard<std::mutex> lock(cache->cache_mutex);
		if (cache->interned_strings.contains(hash_value)) {
			return cache->interned_strings.find(hash_value)->second;
		}
		
		MyString* new_value = cache->string_alloc.new_object<MyString>();
		*new_value = *string;

		cache->interned_strings.insert(std::make_pair(hash_value, new_value));
		return new_value;
	}

	InternedString intern(const MyString&& string) {
		return intern(&string);
	}

	void delete_interned_string(InternedString string) {
		if (string == nullptr || cache == nullptr) {
			return;
		}
		const size_t hash_value = cache->string_hasher(*string);
		
		std::lock_guard<std::mutex> lock(cache->cache_mutex);

		auto it = cache->interned_strings.find(hash_value);
		if (it != cache->interned_strings.end()) {
			MyString* old_value = it->second;
			cache->interned_strings.erase(it);
			cache->string_alloc.delete_object<MyString>(old_value);
		}
	}

	void purge_interned_string_cache() {
		if (cache == nullptr) {
			return;
		}

		std::lock_guard<std::mutex> lock(cache->cache_mutex);

		for (auto& it : cache->interned_strings) {
			cache->string_alloc.delete_object<MyString>(it.second);
		}
		cache->interned_strings.clear();
		delete cache;
		cache = nullptr;
	}
}

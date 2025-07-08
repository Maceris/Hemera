#include <cstdint>
#include <functional>
#include <mutex>

#include "memory/allocator.h"

namespace hemera {

	static Allocator<MyString> string_alloc;
	static std::hash<MyString> string_hasher;
	static std::map<size_t, MyString*> interned_strings;
	static std::mutex cache_mutex;

	InternedString intern(const MyString* string) {
		if (string == nullptr) {
			return nullptr;
		}

		const size_t hash_value = string_hasher(*string);

		std::lock_guard<std::mutex> lock(cache_mutex);
		if (interned_strings.contains(hash_value)) {
			return interned_strings.find(hash_value)->second;
		}
		
		MyString* new_value = string_alloc.new_object<MyString>();
		*new_value = *string;

		interned_strings.insert(std::make_pair(hash_value, new_value));
		return new_value;
	}

	InternedString intern(const MyString&& string) {
		return intern(&string);
	}

	void delete_interned_string(InternedString string) {
		if (string == nullptr) {
			return;
		}
		const size_t hash_value = string_hasher(*string);
		
		std::lock_guard<std::mutex> lock(cache_mutex);

		auto it = interned_strings.find(hash_value);
		if (it != interned_strings.end()) {
			MyString* old_value = it->second;
			interned_strings.erase(it);
			string_alloc.delete_object<MyString>(old_value);
		}
	}

	void purge_interned_string_cache() {
		std::lock_guard<std::mutex> lock(cache_mutex);

		for (auto& it : interned_strings) {
			string_alloc.delete_object<MyString>(it.second);
		}
		interned_strings.clear();
	}
}
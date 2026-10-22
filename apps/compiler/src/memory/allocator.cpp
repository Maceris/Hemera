#include <array>
#include <cstdint>
#include <functional>
#include <mutex>
#include <string_view>
#include <unordered_map>

#include "memory/allocator.h"
#include "util/logger.h"

namespace hemera {

	/*
	 * Every interned string, by its text, in shards chosen by its hash, each with its own lock, since the
	 * lexer and the checker's threads intern names all the time. A shard's keys view the text of the strings
	 * it owns, which stay where they are until purged.
	 */
	struct StringShard {
		std::mutex mutex;
		Allocator<MyString> string_alloc;
		std::unordered_map<std::string_view, MyString*> strings;
	};

	constexpr size_t STRING_SHARDS = 64;

	struct StringCache {
		std::array<StringShard, STRING_SHARDS> shards;
	};

	static StringCache* cache;

	static StringShard& shard_of(std::string_view text) {
		return cache->shards[std::hash<std::string_view>{}(text) % STRING_SHARDS];
	}

	void initialize_interned_string_cache() {
		if (cache == nullptr) {
			cache = new StringCache();
		}
		else {
			LOG_ERROR("String cache already initialized");
		}
	}

	// The interned string with text's text, made if there isn't one yet.
	static InternedString intern_text(std::string_view text) {
		if (cache == nullptr) {
			LOG_ERROR("String cache not initialized yet!");
			return nullptr;
		}
		StringShard& shard = shard_of(text);
		std::lock_guard<std::mutex> lock(shard.mutex);
		auto found = shard.strings.find(text);
		if (found != shard.strings.end()) {
			return found->second;
		}
		MyString* new_value = shard.string_alloc.new_object<MyString>(text.begin(), text.end());
		shard.strings.emplace(std::string_view(*new_value), new_value);
		return new_value;
	}

	InternedString intern(const MyString* string) {
		if (string == nullptr) {
			return nullptr;
		}
		return intern_text(std::string_view(*string));
	}

	InternedString intern(const std::string& string) {
		return intern_text(string);
	}

	InternedString intern(const MyString&& string) {
		return intern(&string);
	}

	void delete_interned_string(InternedString string) {
		if (cache == nullptr) {
			LOG_ERROR("String cache not initialized yet!");
			return;
		}
		if (string == nullptr) {
			return;
		}
		StringShard& shard = shard_of(std::string_view(*string));
		std::lock_guard<std::mutex> lock(shard.mutex);
		auto found = shard.strings.find(std::string_view(*string));
		if (found != shard.strings.end()) {
			MyString* old_value = found->second;
			shard.strings.erase(found);
			shard.string_alloc.delete_object<MyString>(old_value);
		}
	}

	void purge_interned_string_cache() {
		if (cache == nullptr) {
			LOG_ERROR("String cache not initialized yet!");
			return;
		}
		for (StringShard& shard : cache->shards) {
			std::lock_guard<std::mutex> lock(shard.mutex);
			for (auto& [text, string] : shard.strings) {
				shard.string_alloc.delete_object<MyString>(string);
			}
			shard.strings.clear();
		}
		delete cache;
		cache = nullptr;
	}
}

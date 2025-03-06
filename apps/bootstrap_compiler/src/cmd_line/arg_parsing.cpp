
#include <algorithm>

#include "cmd_line/arg_parsing.h"

namespace hemera::arg_parse {

	struct FindResult {
		bool found;
		char _padding[7] = { 0 };
		size_t location;
		
		FindResult() 
			: found(false)
			, location(0)
		{}
		
		FindResult(size_t loc)
			: found(true)
			, location(loc)
		{}

		FindResult(const FindResult& other) = delete;
		FindResult(FindResult&& other) noexcept = delete;
		FindResult& operator=(const FindResult& other) = delete;
		FindResult& operator=(FindResult&& other) noexcept = delete;

		~FindResult() = default;
	};

	static FindResult find_char(const char* str, const char value) {
		for (size_t offset = 0; str[offset] != 0; ++offset) {
			if (str[offset] == value) {
				return FindResult{ offset };
			}
		}

		return {};
	}

	static void split_on_char(const char* str, const char value,
		MyVector<MyString>& results) {

		size_t start = 0;
		size_t end;
		for (end = 0; str[end] != 0; ++end) {
			char c = str[end];
			if (c == value) {
				size_t size = end - start;
				if (size > 0) {
					results.emplace_back(str + start, size);
				}
				start = end + 1;
			}
		}

		size_t size = end - start;
		if (size > 0) {
			results.emplace_back(str + start, size);
		}
	}

	MyVector<ArgumentInfo>* parse_arguments(int argc, char* argv[],
		Allocator<> alloc) {

		MyVector<ArgumentInfo>* results = alloc.new_object<MyVector<ArgumentInfo>>();

		for (int i = 0; i < argc; ++i) {

			const char* raw_arg = argv[i];
			FindResult found_equals = find_char(raw_arg, '=');

			ArgumentInfo& new_arg = results->emplace_back();

			if (found_equals.found) {
				new_arg.option = MyString(raw_arg, found_equals.location);
				split_on_char(raw_arg + found_equals.location + 1, ',', new_arg.values);
			}
			else {
				new_arg.option = MyString(raw_arg);
			}

		}
		return results;
	}
}
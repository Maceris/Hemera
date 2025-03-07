
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

	void parse_arguments(int argc, char* argv[], Options& output) {

		//NOTE(ches) Skip the first argument, hoping it's the program name
		for (int i = 1; i < argc; ++i) {
			const char* raw_arg = argv[i];
			FindResult found_equals = find_char(raw_arg, '=');

			if (found_equals.found) {
				OptionWithValue& option =
					output.options_with_values.emplace_back();
				option.option = MyString(raw_arg, found_equals.location);
				split_on_char(raw_arg + found_equals.location + 1, ',', 
					option.values);
			}
			else {
				output.options.emplace_back(raw_arg);
			}

		}
	}
}
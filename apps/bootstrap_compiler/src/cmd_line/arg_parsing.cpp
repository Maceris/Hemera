
#include <algorithm>
#include <format>

#include "cmd_line/arg_parsing.h"
#include "util/logger.h"

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

	bool parse_arguments(int argc, char* argv[], Options& output, 
		Allocator<> alloc) {

		bool all_fine = true;

		bool started_input = false;

		//NOTE(ches) Skip the first argument, hoping it's the program name
		for (int i = 1; i < argc; ++i) {
			const char* raw_arg = argv[i];
			LOG_VERBOSE(raw_arg);
			FindResult found_equals = find_char(raw_arg, '=');

			if (found_equals.found && found_equals.location == 0) {
				// There is nothing on the left of the equals, so ignore it
				all_fine = false;
				continue;
			}

			if (found_equals.found) {
				if (started_input) {
					LOG_WARNING("Flags with values after input, something is probably wrong");
					all_fine = false;
					continue;
				}

				size_t option_size = found_equals.location;

				char* just_option = static_cast<char*>(alloc.allocate_bytes(option_size + 1));
				memcpy_s(just_option, option_size, raw_arg, option_size);
				just_option[option_size] = 0;

				std::optional<const OptionDescription*> maybe_option = find_option(just_option);
				alloc.deallocate_bytes(just_option, option_size + 1);
				just_option = nullptr;

				if (!maybe_option) {
					LOG_WARNING(std::format("Unrecognized option {}", raw_arg));
					all_fine = false;
					continue;
				}

				const Option& option = maybe_option.value()->option;

				if (!maybe_option.value()->has_args) {
					LOG_WARNING(std::format("Unexpected arguments provided in option {}", raw_arg));
					all_fine = false;
					continue;
				}

				OptionWithValue& option_with_value =
					output.options_with_values.emplace_back();
				option_with_value.option = option;
				split_on_char(raw_arg + found_equals.location + 1, ',',
					option_with_value.values);

			}
			else {
				std::optional<const OptionDescription*> maybe_option = find_option(raw_arg);

				if (!maybe_option) {
					started_input = true;
					output.input.emplace_back(raw_arg);
					continue;
				}
				if (started_input) {
					LOG_WARNING("Flags after input, something is probably wrong");
					all_fine = false;
					continue;
				}

				const Option& option = maybe_option.value()->option;

				if (maybe_option.value()->has_args) {
					LOG_WARNING(std::format("Expected arguments for option {}", raw_arg));
					all_fine = false;
					continue;
				}

				output.options.emplace_back(option);
			}
		}
		return all_fine;
	}

	std::optional<const OptionDescription*> find_option(const char* option) {
		const size_t option_length = constexpr_strlen(option);

		for (const auto& value : NAMED_OPTIONS) {
			const size_t smaller_length = std::min(option_length, value.name_length);

			if (strncmp(option, value.name, smaller_length) == 0) {
				return { &value };
			}
		}

		return {};
	}

}
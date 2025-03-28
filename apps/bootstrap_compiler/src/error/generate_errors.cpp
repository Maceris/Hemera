#include <iostream>
#include <format>
#include <fstream>
#include <string>
#include <string_view>
#include <vector>

static std::string format_enum(std::string_view name, std::string_view description) {
	return std::format(R"(		// {}
		{},
)", description, name);
}

static std::string format_struct(std::string_view type, std::string_view name,
	std::string_view description) {
	return std::format(R"(		{{ {0}Code::{1}, {{ "{1}", "{2}" }} }},
)", type, name, description);
}

struct Input {
	std::string code;
	std::string description;
};

int main(int argc, char* argv[])
{
	if (argc != 3) {
		std::cerr << "Incorrect number of arguments" << std::endl;
		return 1;
	}
	const char* replacement;
	if (strncmp(argv[1], "error", 5) == 0) {
		replacement = "Error";
	}
	else if (strncmp(argv[1], "warning", 7) == 0) {
		replacement = "Warning";
	}
	else {
		std::cerr << "Unknown replacement type" << std::endl;
		return 1;
	}

	std::ifstream input_file;
	input_file.open(argv[2]);

	if (!input_file.is_open()) {
		std::cerr << "Unknown file" << std::endl;
		return 1;
	}

	std::string line;
	std::vector<Input> inputs;

	while (std::getline(input_file, line)) {
		if (line.empty()) {
			continue;
		}
		size_t first_comma = line.find(",");
		if (first_comma == std::string::npos) {
			std::cerr << "Bad file format" << std::endl;
			return 1;
		}
		inputs.emplace_back(line.substr(0, first_comma), line.substr(first_comma + 1));
	}

	std::cout << std::format(R"(
#pragma once

//NOTE(ches) This file is autogenerated from {1}, please do not modify it

#include <map>

namespace hemera {{

	enum class {0}Code {{
)", replacement, argv[2]);
	for (const auto& input : inputs) {
		std::cout << format_enum(input.code, input.description);
	}
	std::cout << std::format(R"DONE(
	}};
	struct {0}Info {{
		const char* string_value;
		const char* message;

		constexpr {0}Info(const char* string_value, const char* message)
			: string_value{{ string_value }}
			, message{{ message }}
		{{}}
		constexpr {0}Info(const {0}Info& other)
			: string_value{{ other.string_value }}
			, message{{ other.message }}
		{{}}
#pragma warning(push)
		/*
		* NOTE(ches) MSVC complains that this is unreferenced and states that
		* it has been removed. But if you delete it, it throws
		* an error saying it tried to reference a deleted function.
		*/ 
#pragma warning(disable: 4514)
		constexpr {0}Info({0}Info&& other) noexcept
			: string_value{{ std::move(other.string_value) }}
			, message{{ std::move(other.message) }}
		{{}}
		{0}Info& operator=(const {0}Info& other) {{
			string_value = other.string_value;
			message = other.message;
			return *this;
		}}
#pragma warning(pop)
		
		{0}Info& operator=({0}Info&& other) noexcept = delete;
		~{0}Info() = default;
	}};

	static std::map<{0}Code, {0}Info> {0}InfoMap = {{
)DONE",
	replacement);
	for (const auto& input : inputs) {
		std::string value = format_struct(replacement, input.code, input.description);
		std::cout << value;
	}
	
	std::cout << R"(
	};
}
)" << std::endl;
	return 0;
}
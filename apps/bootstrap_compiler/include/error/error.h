#pragma once

#include <map>

namespace hemera {

#if defined(ALL_ERRORS) || defined(ERROR_DEF)
	static_assert(false, "We are stepping over some existing macros");
#endif

	//NOTE(ches) I am sorry for this nonsense
#define ALL_ERRORS \
	ERROR_DEF(E1000, "Failed to open file"),

#define ERROR_DEF(code, value) code

	enum class ErrorCode {
		ALL_ERRORS
	};
	
	struct ErrorInfo {
		const char* string_value;
		const char* message;

		constexpr ErrorInfo(const char* string_value, const char* message)
			: string_value{ string_value }
			, message{ message }
		{}
		constexpr ErrorInfo(const ErrorInfo& other)
			: string_value{ other.string_value }
			, message{ other.message }
		{}
#pragma warning(push)
		/*
		* NOTE(ches) MSVC complains that this is unreferenced and states that
		* it has been removed. But if you delete it, it throws
		* an error saying it tried to reference a deleted function.
		*/ 
#pragma warning(disable: 4514)
		constexpr ErrorInfo(ErrorInfo&& other) noexcept
			: string_value{ std::move(other.string_value) }
			, message{ std::move(other.message) }
		{}
		ErrorInfo& operator=(const ErrorInfo& other) {
			string_value = other.string_value;
			message = other.message;
			return *this;
		}
#pragma warning(pop)
		
		ErrorInfo& operator=(ErrorInfo&& other) noexcept = delete;
		~ErrorInfo() = default;
	};

#undef ERROR_DEF
#define ERROR_DEF(code, value) { ErrorCode::code, { #code, value } }
	
	static std::map<ErrorCode, ErrorInfo> ERRORS = {
		ALL_ERRORS
	};

#undef ALL_ERRORS
#undef ERROR_DEF
}

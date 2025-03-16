#pragma once

#include <map>

namespace hemera {

#if defined(ALL_WARNINGS) || defined(WARNING_DEF)
	static_assert(false, "We are stepping over some existing macros");
#endif

	//NOTE(ches) I am sorry for this nonsense
#define ALL_WARNINGS \
	WARNING_DEF(W1000, "")

#define WARNING_DEF(code, value) code

	enum class WarningCode {
		ALL_WARNINGS
	};

	struct WarningInfo {
		const char* string_value;
		const char* message;

		constexpr WarningInfo(const char* string_value, const char* message)
			: string_value{ string_value }
			, message{ message }
		{}
		constexpr WarningInfo(const WarningInfo& other)
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
		constexpr WarningInfo(WarningInfo&& other) noexcept
			: string_value{ std::move(other.string_value) }
			, message{ std::move(other.message) }
		{}
		WarningInfo& operator=(const WarningInfo& other) {
			string_value = other.string_value;
			message = other.message;
			return *this;
		}
#pragma warning(pop)
		WarningInfo& operator=(WarningInfo&& other) noexcept = delete;
		~WarningInfo() = default;
	};

#undef WARNING_DEF
#define WARNING_DEF(code, value) { WarningCode::code, { #code, value } }
	static std::map<WarningCode, WarningInfo> WARNINGS = {
		ALL_WARNINGS
	};

#undef ALL_WARNINGS
#undef WARNING_DEF
}
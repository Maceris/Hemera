#pragma once

#include <span>
#include <string>
#include <string_view>

namespace hemera {

	/// <summary>
	/// A source file of base, built into the compiler (src/front_end/embed_base.cmake). Base is the
	/// interface to what the compiler provides, so it's supplied by the compiler rather than read
	/// from disk while compiling.
	/// </summary>
	struct EmbeddedFile {
		/// <summary>
		/// The package's folder under base, like "runtime" or "intrinsics/x86_64".
		/// </summary>
		std::string_view folder;
		std::string_view file_name;
		/// <summary>
		/// The file's text, in parts of at most 4 KiB, which keeps each string literal small.
		/// </summary>
		std::span<const std::string_view> parts;

		/// <summary>
		/// The file's text, with line endings as reading it from disk as text gives them: CRLF
		/// becomes LF.
		/// </summary>
		std::string contents() const {
			std::string joined;
			for (std::string_view part : parts) {
				joined += part;
			}
			std::string result;
			result.reserve(joined.size());
			for (size_t i = 0; i < joined.size(); ++i) {
				if (joined[i] != '\r' || i + 1 >= joined.size() || joined[i + 1] != '\n') {
					result += joined[i];
				}
			}
			return result;
		}
	};

	/// <summary>
	/// Every source file of base, sorted by folder and name.
	/// </summary>
	std::span<const EmbeddedFile> embedded_base_files();
}

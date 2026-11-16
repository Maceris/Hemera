#include "uri.h"

#include <algorithm>
#include <filesystem>
#include <format>

namespace hemera::lsp {

	static int hex_value(char c) {
		if (c >= '0' && c <= '9') {
			return c - '0';
		}
		if (c >= 'a' && c <= 'f') {
			return c - 'a' + 10;
		}
		if (c >= 'A' && c <= 'F') {
			return c - 'A' + 10;
		}
		return -1;
	}

	static bool is_drive(std::string_view path) {
		return path.size() >= 2 && path[1] == ':' && ((path[0] >= 'a' && path[0] <= 'z') || (path[0] >= 'A' && path[0] <= 'Z'));
	}

	std::string path_from_uri(std::string_view uri) {
		constexpr std::string_view SCHEME = "file://";
		if (uri.size() < SCHEME.size() || !std::equal(SCHEME.begin(), SCHEME.end(), uri.begin(),
			[](char a, char b) { return a == std::tolower(static_cast<unsigned char>(b)); })) {
			return {};
		}
		std::string_view rest = uri.substr(SCHEME.size());
		// The authority, up to the path's /
		const size_t slash = rest.find('/');
		std::string_view host = rest.substr(0, slash);
		rest = slash == std::string_view::npos ? std::string_view() : rest.substr(slash);
		std::string decoded;
		for (size_t i = 0; i < rest.size(); ++i) {
			if (rest[i] != '%') {
				decoded += rest[i];
				continue;
			}
			if (i + 2 >= rest.size() || hex_value(rest[i + 1]) < 0 || hex_value(rest[i + 2]) < 0) {
				return {};
			}
			decoded += static_cast<char>(hex_value(rest[i + 1]) * 16 + hex_value(rest[i + 2]));
			i += 2;
		}
		std::replace(decoded.begin(), decoded.end(), '\\', '/');
		if (!host.empty() && host != "localhost") {
			return std::format("//{}{}", host, decoded);
		}
		// /d:/project is a drive's path
		if (decoded.size() >= 3 && decoded[0] == '/' && is_drive(std::string_view(decoded).substr(1))) {
			decoded.erase(0, 1);
		}
		return decoded;
	}

	std::string uri_from_path(std::string_view path) {
		std::string with_slashes(path);
		std::replace(with_slashes.begin(), with_slashes.end(), '\\', '/');
		if (is_drive(with_slashes)) {
			with_slashes[0] = static_cast<char>(std::tolower(static_cast<unsigned char>(with_slashes[0])));
		}
		std::string uri = "file://";
		if (with_slashes.starts_with("//")) {
			// A UNC path's server is the authority
			with_slashes.erase(0, 2);
		}
		else if (!with_slashes.starts_with('/')) {
			uri += '/';
		}
		for (const char c : with_slashes) {
			const unsigned char byte = static_cast<unsigned char>(c);
			if ((byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z') || (byte >= '0' && byte <= '9') || c == '-' || c == '.'
				|| c == '_' || c == '~' || c == '/') {
				uri += c;
			}
			else {
				uri += std::format("%{:02X}", byte);
			}
		}
		return uri;
	}

	std::string path_key(std::string_view path) {
		std::string key = std::filesystem::path(std::string(path)).lexically_normal().generic_string();
#ifdef _WIN32
		std::transform(key.begin(), key.end(), key.begin(), [](char c) { return c >= 'A' && c <= 'Z' ? static_cast<char>(c - 'A' + 'a') : c; });
#endif
		return key;
	}
}

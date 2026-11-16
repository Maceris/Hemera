#pragma once

#include <string>
#include <string_view>

// The file: URIs the Language Server Protocol names documents by, and the paths they stand for.
namespace hemera::lsp {

	/*
	 * The path a file: URI names, percent-decoded, with / throughout: file:///d%3A/project/main.hsc is
	 * d:/project/main.hsc on Windows, and file:///home/me/main.hsc is /home/me/main.hsc elsewhere. A host other than
	 * localhost, as in file://server/share/main.hsc, gives a UNC path, //server/share/main.hsc. Empty for a URI of
	 * another scheme, like untitled:, and for a broken percent escape.
	 */
	std::string path_from_uri(std::string_view uri);

	/*
	 * A file: URI for an absolute path, either separator: d:/project/main.hsc or d:\project\main.hsc is
	 * file:///d%3A/project/main.hsc, as VS Code writes it, with the drive letter in lowercase. Bytes other than
	 * letters, digits, -, ., _, ~ and / are percent-encoded, so non-ASCII paths are encoded as UTF-8's bytes.
	 */
	std::string uri_from_path(std::string_view path);

	/*
	 * How two paths are compared, so a document the client named one way matches a diagnostic the compiler gives
	 * another: / throughout, . and .. resolved without touching the disk, and on Windows, in lowercase.
	 */
	std::string path_key(std::string_view path);
}

#pragma once

#include <istream>
#include <optional>
#include <string>
#include <string_view>

/*
 * The Language Server Protocol's base protocol: each message is a JSON body after headers, of which only
 * Content-Length, the body's size in bytes, is needed. A header ends with \r\n, and the headers with an empty line.
 */
namespace hemera::lsp {

	/*
	 * The next message's body from in, without its headers. Headers other than Content-Length are skipped, and a
	 * header's name is matched in any case. Empty when in ends, or when the headers have no Content-Length or one
	 * that isn't a number, which leaves in where the headers ended; in should be binary, so \r\n arrive as they are.
	 */
	std::optional<std::string> read_message(std::istream& in);

	// body with the header it's sent with: Content-Length, then an empty line.
	std::string frame(std::string_view body);
}

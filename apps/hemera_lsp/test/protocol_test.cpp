#include <sstream>
#include <string>

#include "gtest/gtest.h"

#include "protocol.h"

using hemera::lsp::frame;
using hemera::lsp::read_message;

TEST(Protocol, FramesWithContentLength) {
	EXPECT_EQ("Content-Length: 7\r\n\r\n{\"a\":1}", frame("{\"a\":1}"));
}

TEST(Protocol, ReadsMessagesInTurn) {
	std::istringstream in(frame("{\"a\":1}") + frame("{\"b\":\"\r\n\"}"));

	EXPECT_EQ("{\"a\":1}", read_message(in));
	EXPECT_EQ("{\"b\":\"\r\n\"}", read_message(in));
	EXPECT_FALSE(read_message(in).has_value());
}

TEST(Protocol, SkipsOtherHeadersInAnyCase) {
	std::istringstream in("Content-Type: application/vscode-jsonrpc; charset=utf-8\r\ncontent-length:  2 \r\n\r\n{}");

	EXPECT_EQ("{}", read_message(in));
}

TEST(Protocol, CountsBytesNotCharacters) {
	// é is two bytes
	const std::string body = "{\"t\":\"\xC3\xA9\"}";
	std::istringstream in(frame(body));

	EXPECT_EQ(body, read_message(in));
}

TEST(Protocol, RefusesHeadersWithoutALength) {
	std::istringstream missing("Content-Type: x\r\n\r\n{}");
	std::istringstream not_a_number("Content-Length: two\r\n\r\n{}");

	EXPECT_FALSE(read_message(missing).has_value());
	EXPECT_FALSE(read_message(not_a_number).has_value());
}

TEST(Protocol, StopsAtACutOffBody) {
	std::istringstream in("Content-Length: 10\r\n\r\n{}");

	EXPECT_FALSE(read_message(in).has_value());
}

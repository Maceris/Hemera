#include "gtest/gtest.h"

#include "uri.h"

using hemera::lsp::path_from_uri;
using hemera::lsp::path_key;
using hemera::lsp::uri_from_path;

TEST(Uri, DrivePathsLoseTheirLeadingSlash) {
	EXPECT_EQ("d:/project/main.hsc", path_from_uri("file:///d%3A/project/main.hsc"));
	EXPECT_EQ("D:/project/main.hsc", path_from_uri("file:///D:/project/main.hsc"));
}

TEST(Uri, PosixPathsKeepTheirSlash) {
	EXPECT_EQ("/home/me/main.hsc", path_from_uri("file:///home/me/main.hsc"));
	EXPECT_EQ("/home/me/main.hsc", path_from_uri("file://localhost/home/me/main.hsc"));
}

TEST(Uri, DecodesPercentEscapes) {
	EXPECT_EQ("d:/my project/\xC3\xA9.hsc", path_from_uri("file:///d%3A/my%20project/%C3%A9.hsc"));
}

TEST(Uri, HostsAreUncPaths) {
	EXPECT_EQ("//server/share/main.hsc", path_from_uri("file://server/share/main.hsc"));
}

TEST(Uri, OtherSchemesAndBrokenEscapesHaveNoPath) {
	EXPECT_EQ("", path_from_uri("untitled:Untitled-1"));
	EXPECT_EQ("", path_from_uri("file:///d%3/main.hsc"));
}

TEST(Uri, PathsBecomeUrisAsVsCodeWritesThem) {
	EXPECT_EQ("file:///d%3A/my%20project/main.hsc", uri_from_path("D:\\my project\\main.hsc"));
	EXPECT_EQ("file:///home/me/%C3%A9.hsc", uri_from_path("/home/me/\xC3\xA9.hsc"));
	EXPECT_EQ("file://server/share/main.hsc", uri_from_path("//server/share/main.hsc"));
}

TEST(Uri, RoundTrips) {
	EXPECT_EQ("d:/a b/c.hsc", path_from_uri(uri_from_path("d:/a b/c.hsc")));
}

TEST(Uri, KeysMatchSpellingsOfOnePath) {
	EXPECT_EQ(path_key("d:/project/src/../main.hsc"), path_key("d:/project/./main.hsc"));
#ifdef _WIN32
	EXPECT_EQ(path_key("D:\\Project\\Main.hsc"), path_key("d:/project/main.hsc"));
#endif
}

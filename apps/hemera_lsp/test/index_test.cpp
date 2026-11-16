#include <string>

#include "gtest/gtest.h"

#include "index.h"
#include "uri.h"

using hemera::lsp::moved_back;
using hemera::lsp::moved_forward;
using hemera::lsp::read_index;

namespace {

	// Two files: shapes.hsc declares Point and its field x; main.hsc uses both
	const std::string INDEX =
		"{\"version\":1,\"files\":[\"<base>/runtime/core.hsc\",\"D:/p/main.hsc\",\"D:/p/shapes.hsc\"],\"declarations\":[\n"
		"{\"file\":2,\"name\":[10,5],\"span\":[10,60],\"kind\":\"type\",\"brief\":\"A point.\",\"tags\":[[\"note\",\"\",\"Flat.\"]]},\n"
		"{\"file\":2,\"name\":[30,1],\"span\":[30,37],\"kind\":\"field\",\"type\":\"int\"},\n"
		"{\"file\":0,\"name\":[4,6],\"span\":[4,40],\"kind\":\"function\",\"type\":\"fn()\"}],\n"
		"\"uses\":[\n"
		"[1,20,5,0],\n"
		"[1,50,1,1],\n"
		"[1,80,5,0],\n"
		"[1,90,6,2]]}\n";
}

TEST(Index, ReadsDeclarationsAndUses) {
	const auto index = read_index(INDEX, "D:/hemera/base");

	ASSERT_TRUE(index.has_value());
	ASSERT_EQ(3u, index->declarations.size());
	EXPECT_EQ("D:/p/shapes.hsc", index->declarations[0].file);
	EXPECT_EQ(10u, index->declarations[0].name_offset);
	EXPECT_EQ(5u, index->declarations[0].name_length);
	EXPECT_EQ(60u, index->declarations[0].end);
	EXPECT_EQ("type", index->declarations[0].kind);
	EXPECT_EQ("A point.", index->declarations[0].brief);
	ASSERT_EQ(1u, index->declarations[0].tags.size());
	EXPECT_EQ("Flat.", index->declarations[0].tags[0].text);
	EXPECT_EQ("int", index->declarations[1].type);
	// base's files are mapped to where they are
	EXPECT_EQ("D:/hemera/base/runtime/core.hsc", index->declarations[2].file);
}

TEST(Index, FindsWhatANameNames) {
	const auto index = read_index(INDEX, "");
	ASSERT_TRUE(index.has_value());
	const std::string main = hemera::lsp::path_key("D:/p/main.hsc");
	const std::string shapes = hemera::lsp::path_key("D:/p/shapes.hsc");

	// Anywhere in a use, its ends included
	EXPECT_EQ(0u, index->name_at(main, 20)->declaration);
	EXPECT_EQ(0u, index->name_at(main, 25)->declaration);
	EXPECT_EQ(20u, index->name_at(main, 25)->offset);
	EXPECT_EQ(5u, index->name_at(main, 25)->length);
	EXPECT_EQ(1u, index->name_at(main, 50)->declaration);
	EXPECT_FALSE(index->name_at(main, 30).has_value());
	// And at a declaration's own name
	EXPECT_EQ(1u, index->name_at(shapes, 30)->declaration);
	EXPECT_FALSE(index->name_at(shapes, 40).has_value());
}

TEST(Index, ListsEveryPlaceADeclarationIsNamed) {
	const auto index = read_index(INDEX, "");
	ASSERT_TRUE(index.has_value());

	const auto places = index->places_of(0, true);
	ASSERT_EQ(3u, places.size());
	EXPECT_EQ(hemera::lsp::path_key("D:/p/shapes.hsc"), places[0].file);
	EXPECT_EQ(10u, places[0].offset);
	EXPECT_EQ(20u, places[1].offset);
	EXPECT_EQ(80u, places[2].offset);
	EXPECT_EQ(2u, index->places_of(0, false).size());
}

TEST(Index, RefusesWhatIsNotAnIndex) {
	EXPECT_FALSE(read_index("", "").has_value());
	EXPECT_FALSE(read_index("{\"version\":2,\"files\":[],\"declarations\":[],\"uses\":[]}", "").has_value());
	EXPECT_FALSE(read_index("[1,2]", "").has_value());
}

TEST(Index, MovesOffsetsThroughAnEdit) {
	// "abc def ghi" with "def" changed to "de-f-x": the part after grows by 3
	const std::string before = "abc def ghi";
	const std::string after = "abc de-f-x ghi";

	EXPECT_EQ(1u, moved_forward(before, after, 1));
	EXPECT_EQ(12u, moved_forward(before, after, 9));
	EXPECT_FALSE(moved_forward(before, after, 6).has_value());
	EXPECT_EQ(9u, moved_back(before, after, 12));
	EXPECT_EQ(1u, moved_back(before, after, 1));
	EXPECT_FALSE(moved_back(before, after, 7).has_value());
	// The same text moves nothing
	EXPECT_EQ(5u, moved_forward(before, before, 5));
}

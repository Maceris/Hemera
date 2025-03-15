#include "gtest/gtest.h"

#include "util/logger.h"

int main(int argc, char* argv[])
{
	Logger::init();
	testing::InitGoogleTest(&argc, argv);
	GTEST_FLAG_SET(death_test_style, "fast");
	return RUN_ALL_TESTS();
}
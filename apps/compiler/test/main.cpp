#include "gtest/gtest.h"

#include "error/reporting.h"
#include "front_end/type.h"
#include "util/logger.h"

int main(int argc, char* argv[])
{
	Logger::init();

	hemera::initialize_builtin_types();
	hemera::initialize_reporting_storage();

	testing::InitGoogleTest(&argc, argv);
	GTEST_FLAG_SET(death_test_style, "fast");
	return RUN_ALL_TESTS();
}

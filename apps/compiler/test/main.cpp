#include <cstdlib>
#ifdef _MSC_VER
#include <crtdbg.h>
#endif

#include "gtest/gtest.h"

#include "error/reporting.h"
#include "front_end/type.h"
#include "util/crash_dump.h"
#include "util/logger.h"

int main(int argc, char* argv[])
{
#ifdef _MSC_VER
	// Report debug-runtime assertions and aborts on stderr instead of in a dialog, so unattended runs don't stop
	_CrtSetReportMode(_CRT_ASSERT, _CRTDBG_MODE_FILE);
	_CrtSetReportFile(_CRT_ASSERT, _CRTDBG_FILE_STDERR);
	_CrtSetReportMode(_CRT_ERROR, _CRTDBG_MODE_FILE);
	_CrtSetReportFile(_CRT_ERROR, _CRTDBG_FILE_STDERR);
	_set_abort_behavior(0, _WRITE_ABORT_MSG | _CALL_REPORTFAULT);
#endif
	// A crash on a worker thread, which gtest doesn't catch, leaves a dump as hemera's own do (util/crash_dump.cpp)
	hemera::install_crash_dump_handler(argc > 0 ? argv[0] : "HemeraTest");
	Logger::init();

	hemera::initialize_builtin_types();
	hemera::initialize_reporting_storage();

	testing::InitGoogleTest(&argc, argv);
	GTEST_FLAG_SET(death_test_style, "fast");
	return RUN_ALL_TESTS();
}

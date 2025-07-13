#include "front_end/front_end.h"

namespace HEMERA {
	const unsigned int THREAD_COUNT =
		std::max(1u, std::thread::hardware_concurrency());

}
#include "util/thread_pool.h"

namespace hemera {

	ThreadPool::ThreadPool()
		: processor_count{ std::thread::hardware_concurrency() }
	{

	}

	ThreadPool::~ThreadPool() {

	}

}
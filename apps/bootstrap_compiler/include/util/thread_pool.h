#pragma once

#include <thread>

namespace hemera {
	
	struct ThreadPool {
		ThreadPool();
		ThreadPool(const ThreadPool&) = delete;
		ThreadPool(ThreadPool&&) = delete;
		ThreadPool& operator=(const ThreadPool&) = delete;
		ThreadPool& operator=(ThreadPool&&) = delete;
		~ThreadPool();

	private:
		unsigned int processor_count;
	};
}
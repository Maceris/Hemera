#pragma once

#include <thread>

#include "job.h"
#include "memory/thread_safe_queue.h"

namespace hemera {
	
	struct PoolData {
		PoolData(const PoolData&) = delete;
		PoolData& operator=(const PoolData&) = delete;

		ThreadSafeQueue<Job> job_queue;
	};

	struct ThreadPool {
		ThreadPool();
		ThreadPool(const ThreadPool&) = delete;
		ThreadPool(ThreadPool&&) = delete;
		ThreadPool& operator=(const ThreadPool&) = delete;
		ThreadPool& operator=(ThreadPool&&) = delete;
		~ThreadPool();

		void start();
		void stop();

	private:
		unsigned int processor_count;
		const char _padding[4] = { 0 };
		PoolData* pool_data;
	};
}
#pragma once

#include <atomic>
#include <thread>

#include "front_end/work.h"
#include "memory/allocator.h"
#include "memory/thread_safe_queue.h"

namespace hemera {

	constexpr size_t LOCAL_QUEUE_SIZE = 255;
	constexpr size_t GLOBAL_QUEUE_INTERVAL = 31;

	extern const unsigned int THREAD_COUNT;

	struct Queue {
		std::atomic_uint32_t head;
		std::atomic_uint32_t tail;
		size_t mask;
		Work* buffer[LOCAL_QUEUE_SIZE];

		Queue(const Queue&) = delete;
		Queue(Queue&&) = delete;
		Queue& operator=(const Queue&) = delete;
		Queue& operator=(Queue&&) = delete;
	};

	struct WorkThreadData {
		ThreadSafeQueue<Work*>* shared_queue;
		Work* run_next;
		Queue local_queue;
		std::mutex queue_mutex;

		WorkThreadData(const WorkThreadData&) = delete;
		WorkThreadData(WorkThreadData&&) = delete;
		WorkThreadData& operator=(const WorkThreadData&) = delete;
		WorkThreadData& operator=(WorkThreadData&&) = delete;
	};

	struct GlobalThreadData {
		ThreadSafeQueue<Work*> shared_queue;
		MyVector<Queue*> queue_list;
		std::atomic_uint32_t threads_searching;
		char _padding[4] = { 0 };

		GlobalThreadData(const GlobalThreadData&) = delete;
		GlobalThreadData(GlobalThreadData&&) = delete;
		GlobalThreadData& operator=(const GlobalThreadData&) = delete;
		GlobalThreadData& operator=(GlobalThreadData&&) = delete;
	};

	void kick_off_processing();
	void steal_work(WorkThreadData* source, WorkThreadData* destination);

}
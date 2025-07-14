#pragma once

#include <atomic>
#include <condition_variable>
#include <thread>

#include "front_end/work.h"
#include "memory/allocator.h"
#include "memory/thread_safe_queue.h"

namespace hemera {

	constexpr size_t LOCAL_QUEUE_SIZE = 255;
	constexpr uint8_t GLOBAL_QUEUE_INTERVAL = 31;

	extern const unsigned int THREAD_COUNT;

	struct Queue {
		std::atomic_uint32_t head;
		std::atomic_uint32_t tail;
		size_t mask;
		Work* buffer[LOCAL_QUEUE_SIZE];
		MyVector<int> sibling_indices;

		Queue();
		~Queue();
		Queue(const Queue&) = delete;
		Queue(Queue&&) = delete;
		Queue& operator=(const Queue&) = delete;
		Queue& operator=(Queue&&) = delete;
	};

	struct GlobalThreadData;

	struct WorkThreadData {
		GlobalThreadData* global_data;
		Work* run_next;
		Queue local_queue;
		std::mutex queue_mutex;
		std::condition_variable sleep_condition;
		std::mutex sleep_mutex;
		std::atomic_bool interrupt_flag;
		uint8_t tasks_since_last_global_pull;
		char _padding[6] = { 0 };

		WorkThreadData(GlobalThreadData& global_data);
		~WorkThreadData();
		WorkThreadData(const WorkThreadData&) = delete;
		WorkThreadData(WorkThreadData&&) = delete;
		WorkThreadData& operator=(const WorkThreadData&) = delete;
		WorkThreadData& operator=(WorkThreadData&&) = delete;
	};

	struct GlobalThreadData {
		ThreadSafeQueue<Work*> shared_queue;
		MyVector<WorkThreadData*> thread_data;
		std::atomic_uint32_t threads_searching;
		std::atomic_uint32_t threads_running;

		GlobalThreadData();
		~GlobalThreadData();
		GlobalThreadData(const GlobalThreadData&) = delete;
		GlobalThreadData(GlobalThreadData&&) = delete;
		GlobalThreadData& operator=(const GlobalThreadData&) = delete;
		GlobalThreadData& operator=(GlobalThreadData&&) = delete;
	};

	void kick_off_processing();
	void sleep_thread(WorkThreadData& data);
	void notify_thread(WorkThreadData& data, int target_thread_index);
	void enqueue_work(WorkThreadData& data, Work* work);
	Work* dequeue_work_local(WorkThreadData& data);
	Work* dequeue_work_global(WorkThreadData& data);
	void steal_work(WorkThreadData* source, WorkThreadData* destination);

}
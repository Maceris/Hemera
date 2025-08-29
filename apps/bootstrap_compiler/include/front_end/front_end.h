#pragma once

#include <atomic>
#include <condition_variable>
#include <memory_resource>
#include <thread>

#include "front_end/info.h"
#include "front_end/work.h"
#include "memory/allocator.h"
#include "memory/thread_safe_queue.h"

namespace hemera {

	constexpr uint32_t LOCAL_QUEUE_CAPACITY = 255;
	constexpr uint8_t GLOBAL_QUEUE_INTERVAL = 31;
	constexpr uint8_t RUN_NEXT_CAP = 3;

	extern const uint32_t THREAD_COUNT;

	struct Queue {
		/// <summary>
		/// Where values are popped from.
		/// </summary>
		std::atomic_uint32_t head;
		/// <summary>
		/// Where values are pushed to.
		/// </summary>
		std::atomic_uint32_t tail;
		Work* buffer[LOCAL_QUEUE_CAPACITY];

		Queue();
		~Queue();
		Queue(const Queue&) = delete;
		Queue(Queue&&) = delete;
		Queue& operator=(const Queue&) = delete;
		Queue& operator=(Queue&&) = delete;
		uint32_t count() const;
		uint32_t free() const;
		bool is_empty() const;
	};

	struct GlobalThreadData;

	struct WorkThreadData {
		GlobalThreadData* global_data;
		Work* run_next;
		Queue local_queue;
		std::condition_variable sleep_condition;
		std::mutex sleep_mutex;
		std::atomic_bool interrupt_flag;
		uint8_t tasks_since_last_global_pull;
		uint8_t run_next_count;
		/// <summary>
		/// If this thread has anything queued or running.
		/// False if it ran out of tasks and can't find or steal any work.
		/// </summary>
		bool doing_work;
		uint32_t index;
		Info* info;

		WorkThreadData(GlobalThreadData& global_data);
		~WorkThreadData();
		WorkThreadData(const WorkThreadData&) = delete;
		WorkThreadData(WorkThreadData&&) = delete;
		WorkThreadData& operator=(const WorkThreadData&) = delete;
		WorkThreadData& operator=(WorkThreadData&&) = delete;

		/// <summary>
		/// Creates and enqueues work. The work is returned for reference.
		/// </summary>
		/// <returns>The work that was created.</returns>
		Work* create_work(WorkType type, WorkTarget&& target);
	};

	struct GlobalThreadData {
		ThreadSafeQueue<Work*> shared_queue;
		MyVector<WorkThreadData*> thread_data;
		std::atomic_uint32_t parked_work;
		std::atomic_uint32_t threads_searching;
		std::atomic_uint32_t threads_running;
		std::atomic_bool shutdown_flag;
		char _padding[3] = { 0 };
		Info* info;
		std::pmr::monotonic_buffer_resource* work_allocator;

		GlobalThreadData(Info* info, 
			std::pmr::monotonic_buffer_resource* work_allocator);
		~GlobalThreadData();
		GlobalThreadData(const GlobalThreadData&) = delete;
		GlobalThreadData(GlobalThreadData&&) = delete;
		GlobalThreadData& operator=(const GlobalThreadData&) = delete;
		GlobalThreadData& operator=(GlobalThreadData&&) = delete;
	};

	void kick_off_processing();
	void sleep_thread(WorkThreadData& data);
	void notify_thread(WorkThreadData& data, size_t target_thread_index);
	void enqueue_work(WorkThreadData& data, Work* work);
	Work* dequeue_work_local(WorkThreadData& data);
	Work* dequeue_work_global(WorkThreadData& data);
	bool steal_work(WorkThreadData& stealer);

	// Handled in work.cpp, but defined here for convenience
	void work_execution(WorkThreadData& executor, WorkTarget& target);
	void work_if_else(WorkThreadData& executor, WorkTarget& target);
	void work_function_hlir_generation(WorkThreadData& executor, FunctionInfo* function);
	void work_import(WorkThreadData& executor, WorkTarget& target);
	void work_parse(WorkThreadData& executor, WorkTarget& target);
	void work_type_check(WorkThreadData& executor, WorkTarget& target);

}
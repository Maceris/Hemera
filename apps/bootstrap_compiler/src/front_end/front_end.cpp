#include <random>
#include <thread>

#include "util/logger.h"
#include "front_end/front_end.h"

namespace hemera {
	const uint32_t THREAD_COUNT =
		std::max(1u, std::thread::hardware_concurrency());

	const uint32_t MAX_SEARCHERS = std::max(1u, THREAD_COUNT / 2);

	std::random_device rand_device;
	std::mt19937 rng(rand_device());
	std::uniform_int_distribution<> distribution(0, 
		static_cast<int>(THREAD_COUNT) - 2);

	static void add_with_wrap(std::atomic_uint32_t& value) {
		value = (value + 1u) % LOCAL_QUEUE_CAPACITY;
	}

	Queue::Queue()
		: head{ 0 }
		, tail{ 0 }
		, buffer{}
	{
	}
	Queue::~Queue() = default;
	
	uint32_t Queue::count() const {
		return head > tail
			? (LOCAL_QUEUE_CAPACITY - head + tail + 1)
			: (tail - head + 1);
	}
	uint32_t Queue::free() const {
		return LOCAL_QUEUE_CAPACITY - count();
	}
	bool Queue::is_empty() const {
		return head == tail;
	}

	GlobalThreadData::GlobalThreadData()
		: shared_queue{}
		, thread_data{}
		, threads_searching{ 0 }
		, threads_running{ 0 }
	{
	}
	GlobalThreadData::~GlobalThreadData() = default;

	WorkThreadData::WorkThreadData(GlobalThreadData& global_data)
		: global_data{ &global_data }
		, run_next{ nullptr }
		, local_queue{}
		, queue_mutex{}
		, sleep_condition{}
		, sleep_mutex{}
		, interrupt_flag{ false }
		, tasks_since_last_global_pull{ 0 }
		, index{ 0 }
	{}
	WorkThreadData::~WorkThreadData() = default;

	static void init_thread_data(GlobalThreadData& data) {
		for (uint32_t i = 0; i < (int) THREAD_COUNT; ++i) {
			WorkThreadData* new_thread = new WorkThreadData(data);
			new_thread->index = i;
			
			data.thread_data.push_back(new_thread);
		}
	}

	Work* dequeue_work_local(WorkThreadData& data) {
		Work* to_do = nullptr;
		data.tasks_since_last_global_pull += 1;

		if (data.run_next != nullptr && data.run_next_count < RUN_NEXT_CAP) {
			to_do = data.run_next;
			data.run_next = nullptr;
			data.run_next_count += 1;
			return to_do;
		}

		Queue& queue = data.local_queue;
		std::lock_guard<std::mutex> lock(data.queue_mutex);

		if (queue.head == queue.tail) {
			return nullptr;
		}

		to_do = queue.buffer[queue.head];
		add_with_wrap(queue.head);
		data.run_next_count = 0;
		
		return to_do;
	}

	Work* dequeue_work_global(WorkThreadData& data) {
		Work* result = data.global_data->shared_queue.dequeue();
		data.tasks_since_last_global_pull = 0;
		return result;
	}

	static void do_work(WorkThreadData& data) {
		data.global_data->threads_running++;

		while (true) {
			Work* to_do = nullptr;

			if (data.tasks_since_last_global_pull >= GLOBAL_QUEUE_INTERVAL) {
				// Occasionally pull from the global queue
				to_do = dequeue_work_global(data);
			}

			if (to_do == nullptr) {
				to_do = dequeue_work_local(data);
			}

			if (to_do == nullptr) {
				// no work, need to steal from another thread
				data.global_data->threads_searching += 1;

				if (data.global_data->threads_searching >= MAX_SEARCHERS 
					|| !steal_work(data)
					){
					// sleep
					data.global_data->threads_searching -= 1;
					sleep_thread(data);
				}
				//TODO(ches) check if we ran out of tasks everywhere??
			}

			break;
		}

	}

	void kick_off_processing() {
		GlobalThreadData thread_data;
		init_thread_data(thread_data);

		for (size_t i = 0; i < (size_t)THREAD_COUNT; ++i) {
			std::jthread new_thread(do_work, std::ref(*thread_data.thread_data[i]));
		}
	}

	void sleep_thread(WorkThreadData& data) {
		//TODO(ches) sleep thread
		if (data.index) {  }
	}

	void enqueue_work(WorkThreadData& data, Work* work) {
		Queue& queue = data.local_queue;

		queue.buffer[queue.tail] = work;
		add_with_wrap(queue.tail);
	}

	static bool steal_work(WorkThreadData& stealer, WorkThreadData& target) {
		if (target.local_queue.head == target.local_queue.tail) {
			//NOTE(ches) not synchronized but close enough to empty
			return false;
		}

		std::lock_guard<std::mutex> target_lock(target.queue_mutex);

		uint32_t to_steal = target.local_queue.count() / 2;

		std::lock_guard<std::mutex> stealer_lock(stealer.queue_mutex);
		if (stealer.local_queue.free() < to_steal) {
			LOG_ERROR("We tried to steal work but didn't have room for it");
			return false;
		}

		for (uint32_t i = 0; i < to_steal; ++i) {
			Work* work = target.local_queue.buffer[(target.local_queue.head + i) % LOCAL_QUEUE_CAPACITY];
			enqueue_work(stealer, work);
		}
		target.local_queue.head += to_steal;
		return true;
	}

	bool steal_work(WorkThreadData& stealer) {
		const int start = distribution(rng);

		for (unsigned int i = 0; i < THREAD_COUNT; ++i) {
			unsigned int index = (start + i) % THREAD_COUNT;

			if (index == stealer.index) {
				continue;
			}
			
			if (steal_work(stealer, *stealer.global_data->thread_data[index])) {
				return true;
			}
		}

		// Try falling back to the global queue
		Work* to_do = dequeue_work_global(stealer);
		if (to_do != nullptr) {
			enqueue_work(stealer, to_do);
			return true;
		}

		return false;
	}
}
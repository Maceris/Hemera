#include <chrono>
#include <random>
#include <thread>

#include "util/logger.h"
#include "front_end/front_end.h"

namespace hemera {
	const uint32_t THREAD_COUNT =
		std::max(1u, std::thread::hardware_concurrency());

	const uint32_t MAX_SEARCHERS = std::max(1u, THREAD_COUNT / 2);

	constexpr auto SLEEP_DURATION = std::chrono::milliseconds(100);

	std::random_device rand_device;
	std::mt19937 rng(rand_device());
	std::uniform_int_distribution<> distribution(0, 
		static_cast<int>(THREAD_COUNT) - 2);

	template <typename T>
	static void increment_with_wrap(T& value) {
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
		, shutdown_flag{ false }
		, info{ nullptr }
	{}
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
		, run_next_count{ 0 }
		, currently_running{ false }
		, index{ 0 }
		, info{ global_data.info }
	{}
	WorkThreadData::~WorkThreadData() = default;

	bool WorkThreadData::doing_any_work() const {
		if (run_next != nullptr) {
			return true;
		}
		if (!local_queue.is_empty()) {
			return true;
		}
		return currently_running;
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

		if (queue.head == queue.tail) {
			return nullptr;
		}

		std::lock_guard<std::mutex> lock(data.queue_mutex);

		to_do = queue.buffer[queue.head];
		increment_with_wrap(queue.head);
		data.run_next_count = 0;
		
		return to_do;
	}

	Work* dequeue_work_global(WorkThreadData& data) {
		Work* result = data.global_data->shared_queue.dequeue();
		data.tasks_since_last_global_pull = 0;
		if (result != nullptr
			&& 0 == data.global_data->threads_searching
			) {
			size_t to_notify = static_cast<size_t>(distribution(rng));
			if (to_notify == data.index) {
				increment_with_wrap(to_notify);
			}
			notify_thread(data, to_notify);
		}
		return result;
	}

	static bool we_ran_out_of_tasks(GlobalThreadData& data) {
		for (const auto& thread : data.thread_data) {
			if (thread->doing_any_work()) {
				return false;
			}
		}
		if (!data.shared_queue.empty()) {
			return false;
		}
		return true;
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
				if (we_ran_out_of_tasks(*data.global_data)) {
					data.global_data->shutdown_flag = true;
					break;
				}
				data.global_data->threads_searching += 1;

				if (data.global_data->threads_searching >= MAX_SEARCHERS 
					|| !steal_work(data)
					){
					// sleep
					data.global_data->threads_searching -= 1;
					sleep_thread(data);
					if (data.global_data->shutdown_flag) {
						break;
					}
				}
			}
			else {
				data.currently_running = true;
				switch (to_do->type) {
					case WorkType::EXECUTION:
						work_execution(data, to_do->work_target);
						break;
					case WorkType::IF_ELSE:
						work_if_else(data, to_do->work_target);
						break;
					case WorkType::IL1_GENERATION:
						work_il1_generation(data, to_do->work_target);
						break;
					case WorkType::IMPORT:
						work_import(data, to_do->work_target);
						break;
					case WorkType::PARSE:
						work_parse(data, to_do->work_target);
						break;
					case WorkType::TYPE_DEDUCTION:
						work_type_deduction(data, to_do->work_target);
						break;
					case WorkType::TYPE_CHECK:
						work_type_check(data, to_do->work_target);
						break;
				}
				//TODO(ches) run the task
				data.currently_running = false;
			}
		}
		data.global_data->threads_running--;
	}

	void kick_off_processing() {
		//TODO(ches) we need to create info somewhere where we care about it
		Info* info = new Info();

		GlobalThreadData global_data;
		global_data.info = info;
		for (uint32_t i = 0; i < (int)THREAD_COUNT; ++i) {
			WorkThreadData* new_thread = new WorkThreadData(global_data);
			new_thread->index = i;
			global_data.thread_data.push_back(new_thread);
		}

		for (size_t i = 0; i < (size_t)THREAD_COUNT; ++i) {
			std::jthread new_thread(do_work, std::ref(*global_data.thread_data[i]));
		}
	}

	void sleep_thread(WorkThreadData& data) {
		std::unique_lock<std::mutex> lock(data.sleep_mutex);

		bool interrupted = data.sleep_condition.wait_for(lock, SLEEP_DURATION, 
			[&flag = data.interrupt_flag]{ return flag.load(); });

		if (interrupted) {
			// interrupted, there's tasks to be stolen, so we move to searching
			data.global_data->threads_searching += 1;
			data.interrupt_flag = false;
		}
	}

	void notify_thread(WorkThreadData& data, size_t target_thread_index) {
		WorkThreadData& target = *data.global_data->thread_data[target_thread_index];
		{
			std::lock_guard<std::mutex> lock(target.sleep_mutex);
			target.interrupt_flag = true;
		}
		target.sleep_condition.notify_one();
	}

	void enqueue_work(WorkThreadData& data, Work* work) {
		// Expected to be called while a lock is held

		Queue& queue = data.local_queue;

		if (queue.count() < LOCAL_QUEUE_CAPACITY) {
			queue.buffer[queue.tail] = work;
			increment_with_wrap(queue.tail);
			return;
		}
		
		// We are full, dump half the queue into the global queue
		size_t to_dump = queue.count() / 2;
		
		data.global_data->shared_queue.enqueue_array(
			&queue.buffer[queue.head], to_dump);

		queue.head = (queue.head + to_dump) % LOCAL_QUEUE_CAPACITY;
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
			Work* work = target.local_queue.buffer[
				(target.local_queue.head + i) % LOCAL_QUEUE_CAPACITY
			];
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
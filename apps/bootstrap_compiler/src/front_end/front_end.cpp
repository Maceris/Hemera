#include <thread>

#include "front_end/front_end.h"

namespace hemera {
	const unsigned int THREAD_COUNT =
		std::max(1u, std::thread::hardware_concurrency());

	const int MAX_SEARCHERS = std::max(1, (int) THREAD_COUNT / 2);

	Queue::Queue()
		: head{ 0 }
		, tail{ 0 }
		, mask{ 0 }
		, buffer{}
		, sibling_indices{}
	{}
	Queue::~Queue() = default;

	GlobalThreadData::GlobalThreadData()
		: shared_queue{}
		, thread_data{}
		, threads_searching{ 0 }
		, threads_running{ 0 }
	{}
	GlobalThreadData::~GlobalThreadData() = default;

	WorkThreadData::WorkThreadData(GlobalThreadData& global_data)
		: global_data{ &global_data }
		, run_next{ nullptr }
		, local_queue{}
		, queue_mutex{}
		, sleep_condition{}
		, sleep_mutex{}
		, interrupt_flag{false}
	{}
	WorkThreadData::~WorkThreadData() = default;

	static void init_thread_data(GlobalThreadData& data) {
		for (int i = 0; i < (int) THREAD_COUNT; ++i) {
			WorkThreadData* new_thread = new WorkThreadData(data);

			MyVector<int>& siblings = new_thread->local_queue.sibling_indices;
			for (int j = 0; j < (int) THREAD_COUNT; ++j) {
				if (i == j) {
					continue;
				}
				siblings.push_back(j);
			}
			data.thread_data.push_back(new_thread);
		}
	}

	static void do_work(WorkThreadData& data) {
		data.global_data->threads_running++;

		while (true) {

			// try to pull from local queue
			// if it's been a while, pull from global
			// if if we have nothing, steal from another queue
			// if there are too many searching, sleep

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

	void steal_work(WorkThreadData* source, WorkThreadData* destination) {
		//TODO(ches) do this
		if (source == destination) {
			return;
		}
	}
}
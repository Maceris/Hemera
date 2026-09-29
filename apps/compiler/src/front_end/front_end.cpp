#include <chrono>
#include <thread>

#include "error/reporting.h"
#include "memory/allocator.h"
#include "util/logger.h"
#include "front_end/front_end.h"

namespace hemera {
	constexpr uint32_t MIN_THREAD_COUNT = 2;
	uint32_t THREAD_COUNT = MIN_THREAD_COUNT;

	static uint32_t MAX_SEARCHERS = 1;

	constexpr auto SLEEP_DURATION = std::chrono::milliseconds(100);

	/// <summary>
	/// Does a wrapping add to the specified value, and returns the original
	/// value. This is not atomic, but there's not a whole lot we can do about
	/// that.
	/// </summary>
	/// <param name="value">The value to add to.</param>
	/// <returns>The original value.</returns>
	static uint32_t wrapping_add(std::atomic_uint32_t& value, 
		const std::memory_order order = std::memory_order_seq_cst)
	{
		uint32_t old_value = value.fetch_add(1, order);
		value = value % LOCAL_QUEUE_CAPACITY;
		return old_value;
	}

	Queue::Queue()
		: head{ 0 }
		, tail{ 0 }
		, buffer{}
	{
	}
	Queue::~Queue() = default;

	static inline uint32_t queue_count(uint32_t head, uint32_t tail) {
		return head > tail
			? (LOCAL_QUEUE_CAPACITY - head + tail + 1)
			: (tail - head + 1);
	}
	
	uint32_t Queue::count() const {
		uint32_t h = head.load(std::memory_order_relaxed);
		uint32_t t = tail.load(std::memory_order_relaxed);
		return queue_count(h, t);
	}
	uint32_t Queue::free() const {
		return LOCAL_QUEUE_CAPACITY - count();
	}
	bool Queue::is_empty() const {
		return head == tail;
	}

	GlobalThreadData::GlobalThreadData(ProgramInfo* program_info,
		const Options* options, Allocator<>* work_allocator,
		Allocator<>* info_allocator)
		: general_queue{}
		, llvm_queue{}
		, thread_data{}
		, parked_work{ 0 }
		, threads_searching{ 0 }
		, threads_running{ 0 }
		, shutdown_flag{ false }
		, rand_device{}
		, rng{ rand_device() }
		, distribution{ 1, static_cast<int>(THREAD_COUNT) - 1 }
		, program_info{ program_info }
		, options{ options }
		, work_allocator{ work_allocator }
		, info_allocator{ info_allocator }
	{}
	GlobalThreadData::~GlobalThreadData() = default;

	WorkThreadData::WorkThreadData(GlobalThreadData& global_data)
		: global_data{ &global_data }
		, run_next{ nullptr }
		, local_queue{}
		, sleep_condition{}
		, sleep_mutex{}
		, interrupt_flag{ false }
		, tasks_since_last_global_pull{ 0 }
		, run_next_count{ 0 }
		, doing_work{ false }
		, index{ 0 }
		, program_info{ global_data.program_info }
	{}
	WorkThreadData::~WorkThreadData() = default;

	Work* WorkThreadData::create_work(WorkType type, WorkTarget&& target) {
		Work* work = global_data->work_allocator->new_object<Work>(
			type, std::move(target));

		switch (type) {
			case WorkType::IF_ELSE:
			case WorkType::IMPORT:
			case WorkType::PARSE:
			case WorkType::TYPE_CHECK:
				global_data->general_queue.enqueue(std::move(work));
				break;
			case WorkType::EXECUTION:
			case WorkType::FUNCTION_CODE_GENERATION:
				global_data->llvm_queue.enqueue(std::move(work));
				break;
		}
		return work;
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

		to_do = queue.buffer[wrapping_add(queue.head)];
		data.run_next_count = 0;
		
		return to_do;
	}

	Work* dequeue_work_global(WorkThreadData& data) {
		Work* result = data.global_data->general_queue.dequeue_or_else(static_cast<Work*>(nullptr));
		data.tasks_since_last_global_pull = 0;
		if (result != nullptr) {
			data.doing_work = true;
		}
		if (result != nullptr
			&& 0 == data.global_data->threads_searching
			) {
			size_t to_notify = static_cast<size_t>(data.global_data->distribution(data.global_data->rng));
			if (to_notify == data.index) {
				// Shift it up by 1, modulo to within the range [1, THREAD_COUNT - 1]
				to_notify = ((to_notify + 1u) % (THREAD_COUNT - 2)) + 1;
			}
			notify_thread(data, to_notify);
		}
		return result;
	}

	static bool we_ran_out_of_tasks(GlobalThreadData& data) {
		for (const auto& thread : data.thread_data) {
			if (thread->doing_work) {
				return false;
			}
		}
		if (!data.general_queue.empty()) {
			return false;
		}
		if (!data.llvm_queue.empty()) {
			return false;
		}
		return true;
	}

	static void do_work(WorkThreadData& data) {
		data.global_data->threads_running++;

		while (true) {
			if (data.global_data->shutdown_flag) {
				break;
			}
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
					data.doing_work = false;
					// sleep
					data.global_data->threads_searching -= 1;
					sleep_thread(data);
					if (data.global_data->shutdown_flag) {
						break;
					}
				}
			}
			else {
				switch (to_do->type) {
					case WorkType::EXECUTION:
					case WorkType::FUNCTION_CODE_GENERATION:
						LOG_FATAL("Someone put LLVM work in the general queue");
						break;
					case WorkType::IF_ELSE:
						work_if_else(data, to_do->work_target);
						break;
					case WorkType::IMPORT:
						work_import(data, to_do->work_target);
						break;
					case WorkType::PARSE:
						work_parse(data, to_do->work_target);
						break;
					case WorkType::TYPE_CHECK:
						work_type_check(data, to_do->work_target);
						break;
				}
			}
		}
		data.global_data->threads_running--;
	}

	static void do_llvm_work(WorkThreadData& data) {
		data.global_data->threads_running++;

		while (true) {
			if (data.global_data->shutdown_flag) {
				break;
			}
			Work* to_do = nullptr;

			to_do = data.global_data->llvm_queue.dequeue_or_else(static_cast<Work*>(nullptr));

			if (to_do == nullptr) {
				// no work, sleep for now
				if (we_ran_out_of_tasks(*data.global_data)) {
					data.global_data->shutdown_flag = true;
					break;
				}
				
				std::unique_lock<std::mutex> lock(data.sleep_mutex);

				bool interrupted = data.sleep_condition.wait_for(lock, SLEEP_DURATION,
					[&flag = data.interrupt_flag] { return flag.load(); });

				if (interrupted) {
					data.interrupt_flag = false;
					data.doing_work = true;
				}
				if (data.global_data->shutdown_flag) {
					break;
				}
			}
			else {
				data.doing_work = true;
				switch (to_do->type) {
				case WorkType::EXECUTION:
					work_execution(data, to_do->work_target);
					break;
				case WorkType::FUNCTION_CODE_GENERATION:
					work_function_code_generation(data,
						to_do->work_target.value.function);
					break;
				case WorkType::IF_ELSE:
				case WorkType::IMPORT:
				case WorkType::PARSE:
				case WorkType::TYPE_CHECK:
					LOG_FATAL("Someone put general work in the LLVM queue");
					break;
				}
			}
		}
		data.global_data->threads_running--;
	}

	void kick_off_processing(ProgramInfo* program_info, const Options* options) {
		initialize_builtin_types();
		initialize_builtin_functions();

		THREAD_COUNT =
			std::max(MIN_THREAD_COUNT, std::thread::hardware_concurrency());
		MAX_SEARCHERS = std::max(1u, THREAD_COUNT / 2);
		
		Allocator<> work_allocator{};
		Allocator<> info_allocator{};

		GlobalThreadData global_data{ program_info, options, &work_allocator, 
			&info_allocator };

		InternedString input_package = intern(options->input.string());

		global_data.general_queue.enqueue(
			std::move(global_data.work_allocator->new_object<Work>(
				WorkType::IMPORT,
				WorkTarget{ WorkTargetType::PACKAGE, {.name = input_package}}
			))
		);
		
		for (uint32_t i = 0; i < THREAD_COUNT; ++i) {
			WorkThreadData* general_thread = new WorkThreadData(global_data);
			general_thread->index = i;
			global_data.thread_data.push_back(general_thread);
		}

		std::vector<std::jthread> threads;

		threads.emplace_back(do_llvm_work, std::ref(*global_data.thread_data[0]));

		for (size_t i = 1; i < static_cast<size_t>(THREAD_COUNT); ++i) {
			threads.emplace_back(do_work, std::ref(*global_data.thread_data[i]));
		}
		//NOTE(ches) the destructors for the threads will .join() them here
	}

	void sleep_thread(WorkThreadData& data) {
		std::unique_lock<std::mutex> lock(data.sleep_mutex);

		//TODO(ches) can we use an atomic spinlock instead?
		bool interrupted = data.sleep_condition.wait_for(lock, SLEEP_DURATION, 
			[&flag = data.interrupt_flag]{ return flag.load(); });

		if (interrupted) {
			// interrupted, there's tasks to be stolen, so we move to searching
			data.global_data->threads_searching += 1;
			data.interrupt_flag = false;
			data.doing_work = true;
		}
	}

	void notify_thread(WorkThreadData& data, size_t target_thread_index) {
		WorkThreadData& target = *data.global_data->thread_data[target_thread_index];
		{
			std::scoped_lock<std::mutex> lock(target.sleep_mutex);
			target.interrupt_flag = true;
		}
		target.sleep_condition.notify_one();
	}

	void enqueue_work(WorkThreadData& data, Work* work) {
		bool llvm_work = false;
		switch (work->type) {
		case WorkType::EXECUTION:
		case WorkType::FUNCTION_CODE_GENERATION:
			llvm_work = true;
			break;
		case WorkType::IF_ELSE:
		case WorkType::IMPORT:
		case WorkType::PARSE:
		case WorkType::TYPE_CHECK:
			llvm_work = false;
			break;
		}
		Queue& queue = data.local_queue;
		uint32_t head = queue.head.load(std::memory_order_acquire);
		uint32_t tail = queue.tail.load(std::memory_order_relaxed);

		if (queue_count(head, tail) < LOCAL_QUEUE_CAPACITY) {
			queue.buffer[wrapping_add(queue.tail, std::memory_order_release)] = work;
			return;
		}
		
		// We are full, dump half the queue into the global queue
		const size_t to_dump = queue.count() / 2;
		
		auto& global_queue = llvm_work ? data.global_data->llvm_queue 
			: data.global_data->general_queue;

		std::scoped_lock<std::mutex> lock(global_queue.mutex);
		for (uint32_t i = 0; i < to_dump; ++i) {
			if (queue.is_empty()) {
				break;
			}
			Work* dumped = queue.buffer[wrapping_add(queue.head)];
			global_queue.enqueue_unsafe(std::move(dumped));
		}
	}

	static bool steal_work(WorkThreadData& stealer, WorkThreadData& target) {
		uint32_t head = target.local_queue.head.load(std::memory_order_acquire);
		uint32_t tail = target.local_queue.tail.load(std::memory_order_relaxed);

		if (head == tail) {
			return false;
		}

		const uint32_t to_steal = queue_count(head, tail) / 2;

		/*
		 * NOTE(ches) trying to dequeue up to to_steal, but bailing out early
		 * if the target somehow emptied itself in the background.
		 */
		for (uint32_t i = 0; i < to_steal; ++i) {
			if (target.local_queue.is_empty()) {
				break;
			}
			Work* work = target.local_queue.buffer[
				wrapping_add(target.local_queue.head)
			];
			enqueue_work(stealer, work);
			//NOTE(ches) enqueue work will dump half its work if it fills up
		}
		return true;
	}

	bool steal_work(WorkThreadData& stealer) {
		const unsigned int start = static_cast<unsigned int>(stealer.global_data->distribution(stealer.global_data->rng));

		for (unsigned int i = 0; i < THREAD_COUNT; ++i) {
			unsigned int index = (start + i) % THREAD_COUNT;

			if (index == stealer.index) {
				continue;
			}
			
			if (steal_work(stealer, *stealer.global_data->thread_data[index])) {
				stealer.doing_work = true;
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

	void initialize_builtin_functions() {
		//TODO(ches) set up builtin functions
	}

	void dump_mlir_to_file(hemera::Options* options, mlir::ModuleOp* mlir_module) {
		std::string file_name = std::format("{}.mlir", options->output_name);
		
		std::error_code EC;
		llvm::raw_fd_ostream file(file_name, EC);
		if (!EC) {
			mlir_module->print(file);
		}
	}

}

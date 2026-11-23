#include <algorithm>
#include <chrono>
#include <filesystem>
#include <format>
#include <map>
#include <memory_resource>
#include <thread>
#include <tuple>

#include "error/reporting.h"
#include "lexer/identifier_security.h"
#include "memory/allocator.h"
#include "util/logger.h"
#include "front_end/front_end.h"
#include "front_end/names.h"
#include "front_end/stack_pointers.h"
#include "middle_end/build_cache.h"

namespace hemera {
	constexpr uint32_t MIN_THREAD_COUNT = 2;
	/*
	 * Checking has only so much work that can go at once, and shares the names registry, so past a few threads
	 * more of them mostly wait. On an i9-12900K (8 performance cores with two threads each, 8 efficiency cores,
	 * 24 logical processors), a kernel's check took 34 ms with 6 or 8 threads, 33 with 12, 46 with 16 and 56
	 * with 24; the front end's tests were quickest with 4 to 8.
	 */
	constexpr uint32_t MAX_THREAD_COUNT = 8;
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
		, outstanding_work{ 0 }
		, stall_reported{ false }
		, next_to_wake{ 0 }
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
		, current_work{ nullptr }
	{}
	WorkThreadData::~WorkThreadData() = default;

	static void signal_thread(WorkThreadData& target) {
		{
			std::scoped_lock<std::mutex> lock(target.sleep_mutex);
			target.interrupt_flag = true;
		}
		target.sleep_condition.notify_one();
	}

	/*
	 * Wakes a thread that can run work of this type: the LLVM thread (0) for LLVM work, otherwise
	 * the next general thread, round robin, so new work doesn't wait for a sleeping thread's timeout.
	 */
	static void wake_a_thread(GlobalThreadData& global_data, WorkType type) {
		if (global_data.thread_data.empty()) {
			return;
		}
		if (WorkType::EXECUTION == type) {
			signal_thread(*global_data.thread_data[0]);
			return;
		}
		const size_t general_threads = global_data.thread_data.size() - 1;
		if (general_threads == 0) {
			return;
		}
		const size_t index = 1 + global_data.next_to_wake.fetch_add(1) % general_threads;
		signal_thread(*global_data.thread_data[index]);
	}

	Work* WorkThreadData::create_work(WorkType type, WorkTarget&& target) {
		Work* work = global_data->work_allocator->new_object<Work>(
			type, std::move(target));
		global_data->outstanding_work += 1;

		switch (type) {
			case WorkType::IF_ELSE:
			case WorkType::IMPORT:
			case WorkType::PARSE:
			case WorkType::TYPE_CHECK:
				global_data->general_queue.enqueue(std::move(work));
				break;
			case WorkType::EXECUTION:
				global_data->llvm_queue.enqueue(std::move(work));
				break;
		}
		wake_a_thread(*global_data, type);
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

	void requeue_work(GlobalThreadData& global_data, Work* work) {
		global_data.outstanding_work += 1;
		switch (work->type) {
			case WorkType::IF_ELSE:
			case WorkType::IMPORT:
			case WorkType::PARSE:
			case WorkType::TYPE_CHECK:
				global_data.general_queue.enqueue(std::move(work));
				break;
			case WorkType::EXECUTION:
				global_data.llvm_queue.enqueue(std::move(work));
				break;
		}
		wake_a_thread(global_data, work->type);
	}

	/*
	 * Whether there's nothing left to do. The first thread to notice finishes up: with work still
	 * parked, nothing can ever wake it, so it reports the stall (its cycles and undeclared names);
	 * otherwise it checks names used before an #if added an import that declares them too.
	 */
	static bool we_ran_out_of_tasks(GlobalThreadData& data) {
		if (data.outstanding_work.load() != 0) {
			return false;
		}
		if (!data.stall_reported.exchange(true)) {
			if (data.parked_work.load() != 0) {
				report_stall(data);
			}
			else {
				check_provisional_uses(data);
				// What structs hold, now that every type they reach is complete
				check_held_fields(data);
				// Pointers to the stack, in every body at once, now that all are checked (stack_pointers.h)
				check_all_stack_pointers(data.program_info->stack_checks);
			}
		}
		return true;
	}

	/*
	 * Everything's done: every thread stops, the sleeping ones woken to see it, rather than finishing their
	 * sleep, which checking a program would wait for.
	 */
	static void shut_down(GlobalThreadData& global_data) {
		global_data.shutdown_flag = true;
		for (WorkThreadData* thread : global_data.thread_data) {
			signal_thread(*thread);
		}
	}

	// With --time-phases, adds the time since began to what the threads spent on work of kind (work_nanoseconds).
	static void add_work_time(GlobalThreadData& global, WorkType kind, std::chrono::steady_clock::time_point began) {
		const auto took = std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - began);
		global.work_nanoseconds[static_cast<size_t>(kind)] += static_cast<uint64_t>(took.count());
	}

	static void do_work(WorkThreadData& data) {
		data.global_data->threads_running++;

		while (true) {
			if (data.global_data->shutdown_flag) {
				break;
			}
			/*
			 * All work goes through the shared queue, which is thread-safe. The per-thread queues
			 * and stealing between them aren't used: their head and tail updates race between the
			 * owner and a thief, which could run one work twice or read an empty slot.
			 */
			Work* to_do = data.global_data->general_queue.dequeue_or_else(static_cast<Work*>(nullptr));

			if (to_do == nullptr) {
				if (we_ran_out_of_tasks(*data.global_data)) {
					shut_down(*data.global_data);
					break;
				}
				data.doing_work = false;
				sleep_thread(data);
				if (data.global_data->shutdown_flag) {
					break;
				}
			}
			else {
				data.current_work = to_do;
				const WorkType kind = to_do->type;
				const bool timed = data.global_data->options != nullptr && data.global_data->options->time_phases;
				const auto began = timed ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point{};
				switch (to_do->type) {
					case WorkType::EXECUTION:
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
				if (timed) {
					add_work_time(*data.global_data, kind, began);
				}
				data.current_work = nullptr;
				data.global_data->outstanding_work -= 1;
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
					shut_down(*data.global_data);
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
				data.current_work = to_do;
				const bool timed = data.global_data->options != nullptr && data.global_data->options->time_phases;
				const auto began = timed ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point{};
				switch (to_do->type) {
				case WorkType::EXECUTION:
					work_execution(data, to_do->work_target);
					if (timed) {
						add_work_time(*data.global_data, WorkType::EXECUTION, began);
					}
					break;
				case WorkType::IF_ELSE:
				case WorkType::IMPORT:
				case WorkType::PARSE:
				case WorkType::TYPE_CHECK:
					LOG_FATAL("Someone put general work in the LLVM queue");
					break;
				}
				data.current_work = nullptr;
				data.global_data->outstanding_work -= 1;
			}
		}
		data.global_data->threads_running--;
	}

	static void check_import_names(ProgramInfo& program);
	static void check_name_security(ProgramInfo& program);

	void kick_off_processing(ProgramInfo* program_info, const Options* options) {
		// Once for the process, since a build's targets may be checked at the same time (build.cpp)
		static std::once_flag initialized;
		std::call_once(initialized, [] {
			initialize_builtin_types();
			initialize_builtin_functions();
			// About one a physical core, which is half the logical processors with two threads a core
			THREAD_COUNT = std::clamp(std::thread::hardware_concurrency() / 2, MIN_THREAD_COUNT, MAX_THREAD_COUNT);
			MAX_SEARCHERS = std::max(1u, THREAD_COUNT / 2);
		});
		
		/*
		 * The work, made by every thread, and freed with this memory once it's all done, as nothing holds it after: a
		 * compiler that checks programs again and again (hemera --serve) would otherwise keep each one's
		 */
		std::pmr::synchronized_pool_resource work_memory;
		Allocator<> work_allocator{ &work_memory };
		// Packages, files and imports are the program's, made in its memory (ProgramInfo::memory)
		Allocator<> info_allocator{ program_info->memory.get() };
		program_info->check_documentation = options == nullptr || options->check_documentation;

		GlobalThreadData global_data{ program_info, options, &work_allocator, 
			&info_allocator };

		InternedString input_package = intern(options->input.string());

		/*
		 * Which warnings are shown (docs/compilation.md, Allowing and Denying Warnings): the build's lists, and only the
		 * packages being built's, so not base's, std's and vendor's, unless the root package is one of theirs. Held
		 * until every package's own ALLOWED_WARNINGS is read.
		 */
		std::vector<std::string> quiet_folders{ "<base>" };
		std::string std_on_disk;
		for (const BuiltinPackage builtin : { BuiltinPackage::STD, BuiltinPackage::VENDOR }) {
			if (auto found = options->builtin_paths.find(builtin); found != options->builtin_paths.end()) {
				std::error_code error;
				quiet_folders.push_back(std::filesystem::weakly_canonical(found->second, error).string());
				if (BuiltinPackage::STD == builtin) {
					std_on_disk = quiet_folders.back();
				}
			}
		}
		start_warning_rules(options->allowed_warnings, options->denied_warnings, quiet_folders, options->input.string(), std_on_disk);

		/*
		 * std's schema, for a typed library's interface record or a program's imports, whose types the compiler
		 * hashes with it (docs/compilation.md, Typed Libraries)
		 */
		InternedString schema_package = nullptr;
		auto std_folder = options->builtin_paths.find(BuiltinPackage::STD);
		if ((options->typed_library || !options->libraries.empty()) && std_folder != options->builtin_paths.end()) {
			std::error_code error;
			const std::filesystem::path schema = std::filesystem::canonical(std_folder->second / "schema", error);
			if (!error) {
				schema_package = intern(schema.string());
			}
		}

		// The input package, and base/builtin's generic types (Optional and Result), which every
		// file can use
		global_data.outstanding_work = schema_package != nullptr ? 4 : 3;
		if (schema_package != nullptr) {
			global_data.general_queue.enqueue(
				std::move(global_data.work_allocator->new_object<Work>(
					WorkType::IMPORT,
					WorkTarget{ WorkTargetType::PACKAGE, {.name = schema_package}}
				))
			);
		}
		global_data.general_queue.enqueue(
			std::move(global_data.work_allocator->new_object<Work>(
				WorkType::IMPORT,
				WorkTarget{ WorkTargetType::PACKAGE, {.name = input_package}}
			))
		);
		global_data.general_queue.enqueue(
			std::move(global_data.work_allocator->new_object<Work>(
				WorkType::IMPORT,
				WorkTarget{ WorkTargetType::PACKAGE, {.name = builtin_package()}}
			))
		);
		// base/runtime, for context, a runtime.Context, which every function can use
		global_data.general_queue.enqueue(
			std::move(global_data.work_allocator->new_object<Work>(
				WorkType::IMPORT,
				WorkTarget{ WorkTargetType::PACKAGE, {.name = intern(std::string(BASE_PACKAGE_PREFIX) + "runtime")}}
			))
		);
		
		for (uint32_t i = 0; i < THREAD_COUNT; ++i) {
			WorkThreadData* general_thread = new WorkThreadData(global_data);
			general_thread->index = i;
			global_data.thread_data.push_back(general_thread);
		}

		{
			std::vector<std::jthread> threads;
			/*
			 * The threads report in the scope of whoever started the program, like a build's target, and note the
			 * files they use in its record, for the build cache
			 */
			ReportScope* scope = report_scope();
			FileRecord* record = file_record();

			threads.emplace_back([scope, record, &data = *global_data.thread_data[0]] {
				set_report_scope(scope);
				set_file_record(record);
				do_llvm_work(data);
			});

			for (size_t i = 1; i < static_cast<size_t>(THREAD_COUNT); ++i) {
				threads.emplace_back([scope, record, &data = *global_data.thread_data[i]] {
					set_report_scope(scope);
					set_file_record(record);
					do_work(data);
				});
			}
			//NOTE(ches) the destructors for the threads will .join() them here
		}
		for (WorkThreadData* thread : global_data.thread_data) {
			delete thread;
		}
		global_data.thread_data.clear();
		/*
		 * --time-phases: what checking spent its threads on, summed over them, like "phase   parse kernel.elf, summed
		 * over threads: 410 ms"; work that waited on other work is counted for each time it ran
		 */
		if (options->time_phases) {
			const std::string program = std::filesystem::path(options->output_name).filename().string();
			constexpr std::pair<WorkType, std::string_view> KINDS[] = { { WorkType::IMPORT, "find packages" },
				{ WorkType::PARSE, "parse" }, { WorkType::IF_ELSE, "decide #if" }, { WorkType::TYPE_CHECK, "resolve and check" },
				{ WorkType::EXECUTION, "run compile-time code" } };
			for (const auto& [kind, name] : KINDS) {
				report_to_standard_error(std::format("phase   {} {}, summed over threads: {} ms", name, program,
					global_data.work_nanoseconds[static_cast<size_t>(kind)].load() / 1000000));
			}
		}
		check_import_names(*program_info);
		check_name_security(*program_info);
		release_warnings();
	}

	/*
	 * UTS #39's checks of a package's names, outside ASCII (docs/formatting.md, Identifiers), each warned once, where
	 * the name is first used: two names in the package that look alike (W2000), a name that mixes scripts (W2001), and
	 * one with a character that isn't for everyday text (W2002). A package whose names are all ASCII has nothing to check.
	 */
	static void check_name_security(ProgramInfo& program) {
		struct Use {
			std::string file;
			uint32_t line;
			uint16_t column;
		};
		auto before = [](const Use& a, const Use& b) {
			return std::tie(a.file, a.line, a.column) < std::tie(b.file, b.line, b.column);
		};
		for (const auto& [package_path, package] : program.packages) {
			// Each name's first use, in file order
			std::map<std::string, Use> names;
			bool outside_ascii = false;
			for (const auto& [file_name, file] : package->files) {
				const std::string path = file_path_of(package_path, file_name);
				// The names it used, kept when it was parsed, as its tokens are gone
				for (const NameUse& used : file->names) {
					const std::string name(*used.name);
					outside_ascii = outside_ascii
						|| std::any_of(name.begin(), name.end(), [](char c) { return static_cast<unsigned char>(c) >= 0x80; });
					const Use use{ path, used.line_number, used.column_number };
					auto [entry, added] = names.try_emplace(name, use);
					if (!added && before(use, entry->second)) {
						entry->second = use;
					}
				}
			}
			if (!outside_ascii) {
				continue;
			}
			// By skeleton, the names that look alike: each is warned of but the first used, ASCII ones first
			std::map<std::string, std::vector<const std::string*>> alike;
			for (const auto& [name, use] : names) {
				const bool ascii = std::all_of(name.begin(), name.end(), [](char c) { return static_cast<unsigned char>(c) < 0x80; });
				if (!ascii) {
					if (const std::vector<std::string_view> scripts = lexer::mixed_scripts(name); !scripts.empty()) {
						std::string listed;
						for (size_t i = 0; i < scripts.size(); ++i) {
							listed += std::format("{}{}", i == 0 ? "" : i + 1 == scripts.size() ? " and " : ", ", scripts[i]);
						}
						report_warning(WarningCode::W2001, use.file, use.line, use.column,
							std::format("{} mixes {}, which can make it look like a name it isn't", name, listed));
					}
					if (const uint32_t uncommon = lexer::uncommon_code_point(name); uncommon != 0) {
						report_warning(WarningCode::W2002, use.file, use.line, use.column,
							std::format("{} has U+{:04X}, of {}, which UTS #39 doesn't recommend for names", name, uncommon,
								lexer::script_name(uncommon)));
					}
				}
				alike[lexer::identifier_skeleton(name)].push_back(&name);
			}
			for (auto& [skeleton, group] : alike) {
				if (group.size() < 2) {
					continue;
				}
				std::sort(group.begin(), group.end(), [&](const std::string* a, const std::string* b) {
					const bool a_ascii = std::all_of(a->begin(), a->end(), [](char c) { return static_cast<unsigned char>(c) < 0x80; });
					const bool b_ascii = std::all_of(b->begin(), b->end(), [](char c) { return static_cast<unsigned char>(c) < 0x80; });
					return a_ascii != b_ascii ? a_ascii : before(names.at(*a), names.at(*b));
				});
				const Use& original = names.at(*group[0]);
				for (size_t i = 1; i < group.size(); ++i) {
					const Use& use = names.at(*group[i]);
					report_warning(WarningCode::W2000, use.file, use.line, use.column,
						std::format("{} looks like {}, used at {}({},{}), but is another name", *group[i], *group[0],
							original.file, original.line, original.column));
				}
			}
		}
	}

	/*
	 * Reports each import whose name isn't the imported package's own, from its package statement (docs/packages.md,
	 * Imports). Run once every package is read, since an import is resolved before its package's files are parsed.
	 * A package with no statement, like the compiler's own builtin, is never wrong.
	 */
	static void check_import_names(ProgramInfo& program) {
		for (const auto& [package_path, package] : program.packages) {
			for (const auto& [file_name, file] : package->files) {
				for (const ImportInfo* import : file->imports) {
					auto imported = program.packages.find(import->resolved_path);
					if (imported == program.packages.end() || imported->second->self_reported_name == nullptr
						|| *imported->second->self_reported_name == *import->name) {
						continue;
					}
					report_error(ErrorCode::E4043, file_path_of(package_path, file_name),
						import->node->value.line_number, import->node->value.column_number,
						std::format("imported as {}, but its package statement names it {}; use \"import {} as {}\" "
							"to use another name", *import->name, *imported->second->self_reported_name,
							*imported->second->self_reported_name, *import->name));
				}
			}
		}
	}

	void sleep_thread(WorkThreadData& data) {
		std::unique_lock<std::mutex> lock(data.sleep_mutex);

		//TODO(ches) can we use an atomic spinlock instead?
		bool interrupted = data.sleep_condition.wait_for(lock, SLEEP_DURATION, 
			[&flag = data.interrupt_flag]{ return flag.load(); });

		if (interrupted) {
			// interrupted, there's work to be found, so go back to searching
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
		if (EC) {
			report_error(ErrorCode::E6000, file_name, 0, 0, EC.message());
			return;
		}
		mlir_module->print(file);
	}

}

#include "middle_end/jit.h"

#include <cstring>
#include <format>
#include <map>
#include <mutex>
#include <set>

#include "error/reporting.h"
#include "front_end/format_spec.h"
#include "front_end/type.h"

#include "llvm/ExecutionEngine/Orc/ExecutionUtils.h"
#include "llvm/ExecutionEngine/Orc/JITTargetMachineBuilder.h"
#include "llvm/ExecutionEngine/Orc/LLJIT.h"
#include "llvm/ExecutionEngine/Orc/ThreadSafeModule.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/Error.h"
#include "llvm/Support/TargetSelect.h"

#if defined(_WIN32)
#include <Windows.h>
#include <malloc.h>
// Windows.h's, which TypeInfoVariant::VOID would become
#undef VOID
#endif

namespace hemera {

	namespace {

		/*
		 * The compile-time code running on this thread: what the services it calls need, and where to go back
		 * to if it fails an assertion or crashes.
		 */
		struct Active {
			const CompileTimeRun* run = nullptr;
			// Each type descriptor's address, and the type it describes
			const std::map<uintptr_t, const TypeInfo*>* types = nullptr;
			std::set<void*> allocations;
#if defined(_WIN32)
			// The registers when the code was entered, restored to leave it from anywhere
			CONTEXT resume{};
#endif
			volatile bool escaped = false;
			volatile bool running = false;
			std::string crash;
			// It registered functions to be called later, so it stays loaded
			bool keep = false;
		};

		// Code kept loaded for the rest of the compilation, like a build package's checks and steps
		std::mutex kept_mutex;
		std::vector<std::unique_ptr<llvm::orc::LLJIT>>& kept_code() {
			// Never freed: it's loaded until the compiler exits
			static auto* kept = new std::vector<std::unique_ptr<llvm::orc::LLJIT>>();
			return *kept;
		}

		thread_local Active* active = nullptr;

		// An any's layout: a pointer to the value, then its type's descriptor.
		struct AnyValue {
			const uint8_t* data;
			const void* type;
		};

		uint64_t read_unsigned(const uint8_t* data, size_t size) {
			uint64_t value = 0;
			std::memcpy(&value, data, std::min<size_t>(size, sizeof(value)));
			return value;
		}

		std::string_view text_of(InternedString name) {
			return name != nullptr ? std::string_view(*name) : std::string_view();
		}

		// The type a descriptor describes, for the code running now.
		const TypeInfo* described(uintptr_t descriptor) {
			if (active == nullptr || active->types == nullptr) {
				return nullptr;
			}
			auto found = active->types->find(descriptor);
			return found != active->types->end() ? found->second : nullptr;
		}

		// A value of type at data as text, like runtime formatting does (std/text_buffer/format.hsc).
		void format_value(const TypeInfo* type, const uint8_t* data, std::string& out, int depth) {
			type = get_base_type(type);
			if (type == nullptr || data == nullptr || depth > 8) {
				out += "<?>";
				return;
			}
			const TypeInfoVariant variant = type->variant;
			if (TypeInfoVariant::INTEGER == variant) {
				const auto integer = static_cast<const TypeInfoInteger*>(type);
				if (type->size > 8) {
					out += std::format("0x{:x}{:016x}", read_unsigned(data + 8, 8), read_unsigned(data, 8));
					return;
				}
				const uint64_t raw = read_unsigned(data, type->size);
				if (integer->is_signed) {
					const unsigned shift = static_cast<unsigned>(64 - type->size * 8);
					out += std::to_string(static_cast<int64_t>(raw << shift) >> shift);
				}
				else {
					out += std::to_string(raw);
				}
			}
			else if (TypeInfoVariant::BOOLEAN == variant) {
				out += read_unsigned(data, type->size) != 0 ? "true" : "false";
			}
			else if (TypeInfoVariant::CHAR == variant) {
				out += static_cast<char>(data[0]);
			}
			else if (TypeInfoVariant::FLOAT == variant) {
				if (type->size == 4) {
					float value;
					std::memcpy(&value, data, 4);
					out += std::format("{}", value);
				}
				else if (type->size == 8) {
					double value;
					std::memcpy(&value, data, 8);
					out += std::format("{}", value);
				}
				else {
					out += "<f16>";
				}
			}
			else if (TypeInfoVariant::STRING == variant) {
				if (static_cast<const TypeInfoString*>(type)->is_raw) {
					const char* text = reinterpret_cast<const char*>(read_unsigned(data, 8));
					out += text != nullptr ? text : "null";
				}
				else {
					const char* text = reinterpret_cast<const char*>(read_unsigned(data + 8, 8));
					out.append(text != nullptr ? text : "", text != nullptr ? read_unsigned(data, 8) : 0);
				}
			}
			else if (TypeInfoVariant::ENUM == variant) {
				const auto enumeration = static_cast<const TypeInfoEnum*>(type);
				const uint64_t raw = read_unsigned(data, type->size);
				for (size_t i = 0; i < enumeration->members.size(); ++i) {
					if (enumeration->values[i] == raw) {
						out += text_of(enumeration->members[i]);
						return;
					}
				}
				out += std::format("{}({})", text_of(enumeration->name), raw);
			}
			else if (TypeInfoVariant::POINTER == variant || TypeInfoVariant::FUNCTION == variant) {
				const uint64_t address = read_unsigned(data, 8);
				out += address == 0 ? std::string("null") : std::format("0x{:016x}", address);
			}
			else if (TypeInfoVariant::STRUCT == variant) {
				const auto structure = static_cast<const TypeInfoStruct*>(type);
				out += std::format("{}{{", text_of(structure->name));
				for (size_t i = 0; i < structure->members.size(); ++i) {
					const StructMember& member = structure->members[i];
					out += std::format("{}{} = ", i > 0 ? ", " : "", text_of(member.name));
					format_value(member.member_type, data + member.offset, out, depth + 1);
				}
				out += "}";
			}
			else if (TypeInfoVariant::ARRAY == variant) {
				const auto array = static_cast<const TypeInfoArray*>(type);
				const uint8_t* elements = data;
				uint64_t count = array->count;
				if (ArrayType::STATIC != array->array_type) {
					count = read_unsigned(data, 8);
					elements = reinterpret_cast<const uint8_t*>(read_unsigned(data + 8, 8));
				}
				out += "[";
				for (uint64_t i = 0; i < count && elements != nullptr; ++i) {
					if (i == 32) {
						out += ", ...";
						break;
					}
					out += i > 0 ? ", " : "";
					format_value(array->element_type, elements + i * array->element_type->size, out, depth + 1);
				}
				out += "]";
			}
			else if (TypeInfoVariant::UNION == variant) {
				const auto union_type = static_cast<const TypeInfoUnion*>(type);
				size_t index = 0;
				const uint8_t* values = data;
				if (union_type->null_is_none) {
					index = read_unsigned(data, 8) == 0 ? 1 : 0;
				}
				else {
					index = static_cast<size_t>(read_unsigned(data, union_type->tag_type->size));
				}
				if (index >= union_type->variants.size()) {
					out += std::format("{}(<bad tag>)", text_of(union_type->name));
					return;
				}
				const UnionVariant& chosen = union_type->variants[index];
				const std::string_view first = union_type->variants.empty() ? "" : text_of(union_type->variants[0].name);
				const bool optional_or_result = union_type->variants.size() == 2 && (first == "Some" || first == "Ok");
				if (optional_or_result && index == 1 && first == "Some") {
					out += "none";
					return;
				}
				if (!optional_or_result || index != 0) {
					out += text_of(chosen.name);
					if (chosen.types.empty()) {
						return;
					}
					out += "(";
				}
				else if (chosen.types.empty()) {
					out += "ok";
				}
				for (size_t i = 0; i < chosen.types.size(); ++i) {
					out += i > 0 ? ", " : "";
					format_value(chosen.types[i], values + (union_type->null_is_none ? 0 : chosen.offsets[i]), out, depth + 1);
				}
				if (!optional_or_result || index != 0) {
					out += ")";
				}
			}
			else if (TypeInfoVariant::ANY == variant) {
				const AnyValue* any = reinterpret_cast<const AnyValue*>(data);
				const TypeInfo* held = described(reinterpret_cast<uintptr_t>(any->type));
				if (held == nullptr) {
					out += "<any>";
					return;
				}
				format_value(held, any->data, out, depth + 1);
			}
			else if (TypeInfoVariant::TYPE == variant) {
				const TypeInfo* named = described(static_cast<uintptr_t>(read_unsigned(data, 8)));
				out += named != nullptr ? to_string(named) : std::string("<type>");
			}
			else if (TypeInfoVariant::VOID == variant) {
				out += "void";
			}
			else {
				out += std::format("<{}>", to_string(type));
			}
		}

		/*
		 * A value with options (docs/format_strings.md), like base's output_value_with: integers, and
		 * characters, booleans, enums and pointers as numbers, worked out with them; floats with their
		 * precision; anything else written as usual, then padded.
		 */
		void format_value_with(const TypeInfo* type, const uint8_t* data, const FormatSpec& spec, std::string& out) {
			if (spec.plain()) {
				format_value(type, data, out, 0);
				return;
			}
			const TypeInfo* base = get_base_type(type);
			const TypeInfoVariant variant = base != nullptr ? base->variant : TypeInfoVariant::VOID;
			const bool numeric = spec.kind != 0
				&& (TypeInfoVariant::CHAR == variant || TypeInfoVariant::BOOLEAN == variant || TypeInfoVariant::ENUM == variant);
			if (TypeInfoVariant::INTEGER == variant && base->size <= 8 && static_cast<const TypeInfoInteger*>(base)->is_signed) {
				int64_t value = 0;
				if (base->size == 1) { int8_t v; std::memcpy(&v, data, 1); value = v; }
				else if (base->size == 2) { int16_t v; std::memcpy(&v, data, 2); value = v; }
				else if (base->size == 4) { int32_t v; std::memcpy(&v, data, 4); value = v; }
				else { std::memcpy(&value, data, 8); }
				out += format_integer(spec, value < 0, value < 0 ? 0 - static_cast<uint64_t>(value) : static_cast<uint64_t>(value));
				return;
			}
			if ((TypeInfoVariant::INTEGER == variant && base->size <= 8) || numeric) {
				out += format_integer(spec, false, read_unsigned(data, base->size));
				return;
			}
			if ((TypeInfoVariant::POINTER == variant || TypeInfoVariant::FUNCTION == variant) && read_unsigned(data, 8) != 0) {
				FormatSpec with_kind = spec;
				if (with_kind.kind == 0) {
					with_kind.kind = 'x';
					with_kind.prefix = true;
				}
				out += format_integer(with_kind, false, read_unsigned(data, 8));
				return;
			}
			if (TypeInfoVariant::FLOAT == variant && (base->size == 4 || base->size == 8)) {
				double value = 0;
				if (base->size == 4) {
					float narrow;
					std::memcpy(&narrow, data, 4);
					value = static_cast<double>(narrow);
				}
				else {
					std::memcpy(&value, data, 8);
				}
				const std::string written = std::format("{:.{}f}", value, spec.has_precision ? spec.precision : size_t{ 6 });
				const bool negative = !written.empty() && written[0] == '-';
				out += format_padded(spec, negative ? "-" : spec.plus ? "+" : "", "", negative ? std::string_view(written).substr(1)
					: std::string_view(written), true);
				return;
			}
			std::string text;
			format_value(type, data, text, 0);
			out += format_text(spec, text);
		}

		/*
		 * format with each % filled in from params, %1, %2 and so on by that one, and %% as %, with
		 * options like %{08x}: like std/text_buffer's append_format.
		 */
		std::string format_log(std::string_view format, const AnyValue* params, size_t count) {
			std::string out;
			size_t next = 0;
			for (size_t i = 0; i < format.size(); ++i) {
				if (format[i] != '%') {
					out += format[i];
					continue;
				}
				if (i + 1 < format.size() && format[i + 1] == '%') {
					out += '%';
					++i;
					continue;
				}
				size_t number = 0;
				bool numbered = false;
				while (i + 1 < format.size() && format[i + 1] >= '0' && format[i + 1] <= '9') {
					number = number * 10 + static_cast<size_t>(format[i + 1] - '0');
					numbered = true;
					++i;
				}
				FormatSpec spec;
				size_t after = i + 1;
				const bool valid = parse_format_spec(format, i + 1, spec, after);
				i = after - 1;
				const size_t chosen = numbered ? (number > 0 ? number - 1 : count) : next++;
				if (!valid || chosen >= count) {
					out += "%!";
					continue;
				}
				const TypeInfo* type = described(reinterpret_cast<uintptr_t>(params[chosen].type));
				if (type == nullptr) {
					out += "<?>";
					continue;
				}
				format_value_with(type, params[chosen].data, spec, out);
			}
			return out;
		}

		// runtime.LogLevel's values
		constexpr int64_t LOG_DEBUG = 10;
		constexpr int64_t LOG_INFO = 20;
		constexpr int64_t LOG_WARN = 30;
		constexpr int64_t LOG_ERROR = 40;

		void compile_time_log(int64_t level, const char* text, int64_t text_count, const AnyValue* params, int64_t params_count,
			const char* file, int64_t file_count, int64_t line, int64_t column) {

			const std::string message = format_log(std::string_view(text, static_cast<size_t>(text_count)), params,
				static_cast<size_t>(params_count));
			const std::string path(file, static_cast<size_t>(file_count));
			const uint32_t at_line = static_cast<uint32_t>(line);
			const uint16_t at_column = static_cast<uint16_t>(column);
			if (level >= LOG_ERROR) {
				report_error(ErrorCode::E4029, path, at_line, at_column, message);
			}
			else if (level >= LOG_WARN) {
				report_warning(WarningCode::W4001, path, at_line, at_column, message);
			}
			else {
				report_message(path, at_line, at_column, level >= LOG_INFO ? "info" : level >= LOG_DEBUG ? "debug" : "trace", message);
			}
		}

		void* compile_time_allocate(uint64_t size, uint64_t alignment) {
			if (alignment == 0 || (alignment & (alignment - 1)) != 0) {
				alignment = 16;
			}
#if defined(_WIN32)
			void* memory = _aligned_malloc(static_cast<size_t>(size), static_cast<size_t>(alignment));
#else
			void* memory = std::aligned_alloc(static_cast<size_t>(alignment), static_cast<size_t>((size + alignment - 1) & ~(alignment - 1)));
#endif
			if (memory != nullptr && active != nullptr) {
				active->allocations.insert(memory);
			}
			return memory;
		}

		void release(void* memory) {
#if defined(_WIN32)
			_aligned_free(memory);
#else
			std::free(memory);
#endif
		}

		void compile_time_free(void* memory) {
			if (memory != nullptr && active != nullptr && active->allocations.erase(memory) == 1) {
				release(memory);
			}
		}

		[[noreturn]] void compile_time_fail(const char* message, int64_t message_count, const char* file, int64_t file_count, int64_t line,
			int64_t column) {

			report_error(ErrorCode::E4029, std::string(file, static_cast<size_t>(file_count)), static_cast<uint32_t>(line),
				static_cast<uint16_t>(column), std::format("assertion failed: {}", std::string_view(message, static_cast<size_t>(message_count))));
			Active* run = active;
			run->escaped = true;
			run->running = false;
#if defined(_WIN32)
			RtlRestoreContext(&run->resume, nullptr);
#endif
			std::abort();
		}

		/*
		 * Compiled code keeps its carrier block in r14 and never gives the caller's value back
		 * (docs/calling_convention.md, Carrier Register), but r14 is this function's caller's to keep: saying the
		 * call clobbers it makes this function save and restore it.
		 */
		[[clang::noinline]] void call_compiled(void (*function)(void*), void* argument) {
			function(argument);
			asm volatile("" ::: "r14", "memory");
		}

#if defined(_WIN32)
		// A crash in compile-time code: back to where it was entered, with what happened recorded.
		LONG CALLBACK on_exception(EXCEPTION_POINTERS* exception) {
			Active* run = active;
			if (run == nullptr || !run->running) {
				return EXCEPTION_CONTINUE_SEARCH;
			}
			const DWORD code = exception->ExceptionRecord->ExceptionCode;
			const char* what = code == EXCEPTION_ACCESS_VIOLATION ? "used memory it can't"
				: code == EXCEPTION_ILLEGAL_INSTRUCTION ? "trapped"
				: code == EXCEPTION_INT_DIVIDE_BY_ZERO ? "divided by zero"
				: code == EXCEPTION_INT_OVERFLOW ? "overflowed a division"
				: code == EXCEPTION_STACK_OVERFLOW ? "ran out of stack"
				: code == EXCEPTION_PRIV_INSTRUCTION ? "ran a privileged instruction"
				: code == EXCEPTION_BREAKPOINT ? "hit a breakpoint"
				: nullptr;
			if (what == nullptr) {
				return EXCEPTION_CONTINUE_SEARCH;
			}
			run->crash = what;
			run->escaped = true;
			run->running = false;
			*exception->ContextRecord = run->resume;
			return EXCEPTION_CONTINUE_EXECUTION;
		}

		/*
		 * Calls the code, coming back here, with escaped set, if it fails an assertion or crashes: the registers
		 * are captured first and restored from anywhere, since compiled code has no unwind tables to unwind
		 * through. Works like setjmp, so it's kept to a function of its own with nothing live across the call.
		 */
		[[clang::noinline]] bool guarded_call(void (*function)(void*), void* argument, Active* run) {
			RtlCaptureContext(&run->resume);
			if (run->escaped) {
				return false;
			}
			run->running = true;
			call_compiled(function, argument);
			run->running = false;
			return true;
		}
#else
		bool guarded_call(void (*function)(void*), void* argument, Active* run) {
			run->running = true;
			call_compiled(function, argument);
			run->running = false;
			return true;
		}
#endif

		llvm::orc::ExecutorSymbolDef service(const void* function) {
			return llvm::orc::ExecutorSymbolDef(llvm::orc::ExecutorAddr::fromPtr(function), llvm::JITSymbolFlags::Exported);
		}
	}

	std::string format_compile_time(std::string_view format, const void* params, size_t count) {
		if (active == nullptr) {
			return std::string(format);
		}
		return format_log(format, static_cast<const AnyValue*>(params), count);
	}

	/*
	 * Calls compiled code with the services' state set up, coming back with the failure reported if it fails an
	 * assertion or crashes.
	 */
	static RunResult run_guarded(void (*function)(void*), void* argument, const CompileTimeRun& run,
		const std::function<void()>& while_loaded, bool& keep) {

		Active state;
		state.run = &run;
		state.types = run.types;
		Active* outer = active;
		active = &state;
		const bool finished = guarded_call(function, argument, &state);
		if (finished) {
			while_loaded();
		}
		active = outer;
		keep = state.keep;
		for (void* memory : state.allocations) {
			release(memory);
		}
		if (finished) {
			return RunResult::RAN;
		}
		if (!state.crash.empty()) {
#if defined(_WIN32)
			if (state.crash == "ran out of stack") {
				_resetstkoflw();
			}
#endif
			report_error(ErrorCode::E4029, run.file_path, run.line, run.column, std::format("the compile-time code {}", state.crash));
		}
		return RunResult::FAILED;
	}

	RunResult run_on_host(std::unique_ptr<llvm::Module> module, std::unique_ptr<llvm::LLVMContext> context,
		const std::string& entry, void* result, const std::function<void()>& while_loaded, const CompileTimeRun& run,
		std::string& error) {

		// The host's target, with its assembly parser for module-level assembly like entry functions'
		static std::once_flag initialized;
		std::call_once(initialized, [] {
			llvm::InitializeNativeTarget();
			llvm::InitializeNativeTargetAsmPrinter();
			llvm::InitializeNativeTargetAsmParser();
#if defined(_WIN32)
			AddVectoredExceptionHandler(1, on_exception);
#endif
		});

		auto machine = llvm::orc::JITTargetMachineBuilder::detectHost();
		if (!machine) {
			error = llvm::toString(machine.takeError());
			return RunResult::NOT_COMPILED;
		}
		// The carrier register, which nothing else may use (docs/calling_convention.md, Carrier Register)
		machine->addFeatures({ "+reserve-r14" });
		/*
		 * The quick code generator: compile-time code is generated unoptimized, and mostly runs once, so making
		 * its machine code takes longer than running it. A build package's constants took 186 ms this way and
		 * 48 the other, and the Ed25519 table, which computes, came out quicker overall too.
		 */
		machine->setCodeGenOptLevel(llvm::CodeGenOptLevel::None);
		auto jit = llvm::orc::LLJITBuilder().setJITTargetMachineBuilder(std::move(*machine)).create();
		if (!jit) {
			error = llvm::toString(jit.takeError());
			return RunResult::NOT_COMPILED;
		}
		module->setDataLayout((*jit)->getDataLayout());
		module->setTargetTriple((*jit)->getTargetTriple());
		llvm::orc::JITDylib& library = (*jit)->getMainJITDylib();
		// The compiler's services, then the operating system's functions, through the compiler's own process
		llvm::orc::MangleAndInterner mangle(library.getExecutionSession(), (*jit)->getDataLayout());
		llvm::orc::SymbolMap symbols{
			{ mangle(COMPILE_TIME_LOG_SYMBOL), service(reinterpret_cast<const void*>(&compile_time_log)) },
			{ mangle(COMPILE_TIME_ALLOCATE_SYMBOL), service(reinterpret_cast<const void*>(&compile_time_allocate)) },
			{ mangle(COMPILE_TIME_FREE_SYMBOL), service(reinterpret_cast<const void*>(&compile_time_free)) },
			{ mangle(COMPILE_TIME_FAIL_SYMBOL), service(reinterpret_cast<const void*>(&compile_time_fail)) },
		};
		for (const auto& [name, address] : run.symbols) {
			symbols[mangle(name)] = service(address);
		}
		if (llvm::Error defined = library.define(llvm::orc::absoluteSymbols(std::move(symbols)))) {
			error = llvm::toString(std::move(defined));
			return RunResult::NOT_COMPILED;
		}
		auto process = llvm::orc::DynamicLibrarySearchGenerator::GetForCurrentProcess(
			(*jit)->getDataLayout().getGlobalPrefix());
		if (!process) {
			error = llvm::toString(process.takeError());
			return RunResult::NOT_COMPILED;
		}
		library.addGenerator(std::move(*process));
		if (llvm::Error added = (*jit)->addIRModule(llvm::orc::ThreadSafeModule(std::move(module), std::move(context)))) {
			error = llvm::toString(std::move(added));
			return RunResult::NOT_COMPILED;
		}
		auto symbol = (*jit)->lookup(entry);
		if (!symbol) {
			error = llvm::toString(symbol.takeError());
			return RunResult::NOT_COMPILED;
		}

		bool keep = false;
		const RunResult ran = run_guarded(symbol->toPtr<void (*)(void*)>(), result, run, while_loaded, keep);
		if (keep) {
			std::scoped_lock<std::mutex> lock(kept_mutex);
			kept_code().push_back(std::move(*jit));
		}
		return ran;
	}

	void keep_running_code_loaded() {
		if (active != nullptr) {
			active->keep = true;
		}
	}

	RunResult call_loaded(void (*function)(void*), void* argument, const CompileTimeRun& run) {
		bool keep = false;
		return run_guarded(function, argument, run, [] {}, keep);
	}

}

#pragma once

#include <atomic>
#include <cstdint>

#include "front_end/hlir.h"
#include "front_end/type_id.h"
#include "memory/allocator.h"
#include "parser/ast_types.h"

namespace hemera {

	using WorkID = UniqueID;

	enum class WorkTargetType {
		EXPRESSION,
		FILE,
		FUNCTION,
		PACKAGE,
	};

	struct FileLocation {
		InternedString package_name;
		InternedString file_name;
	};

	union WorkTargetValue {
		InternedString name;
		FileLocation file_location;
		ast::Node* node;
		FunctionInfo* function;
	};

	struct WorkTarget {
		WorkTargetType type;
		char _padding[4] = { 0 };
		WorkTargetValue value;
	};

	enum class WorkType {
		EXECUTION,
		/// <summary>
		/// Deciding whether to use / discard each #if/#else_if/#else block,
		/// and actually doing so.
		/// </summary>
		IF_ELSE,
		FUNCTION_HLIR_GENERATION,
		IMPORT,
		PARSE,
		TYPE_CHECK,
	};

	struct Work {
		WorkID id;
		std::atomic_int32_t dependency_count;
		WorkType type;
		WorkTarget work_target;

		Work(const Work&) = delete;
		Work(Work&&) = delete;
		Work& operator=(const Work&) = delete;
		Work& operator=(Work&&) = delete;
	};

	struct Dependency {
		WorkTarget dependency;
		Work* owner;
	};

	struct Dependencies {
		MyVector<Dependency> discovery;
		MyVector<Dependency> evaluation;
		MyVector<Dependency> type_checking;
	};

	struct WorkTracking {
		MyMap<WorkID, Work*> active_work;
		MyVector<WorkID> blocked;
	};

}
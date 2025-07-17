#pragma once

#include <atomic>
#include <cstdint>

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

	union WorkTargetValue {
		InternedString name;
		ast::FlatNode* node;
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
		IL1_GENERATION,
		IMPORT,
		PARSE,
		TYPE_DEDUCTION,
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

	enum class DependencyType {
		DISCOVERY,
		EVALUTAION,
		TYPE_CHECKING,
		TYPE_DEDUCTION,
	};

	struct Dependency {
		WorkTargetValue dependency;
		WorkID owner;
	};

	struct WorkTracking {
		MyMap<WorkID, Work*> active_work;
		MyVector<WorkID> queued;
		MyVector<WorkID> blocked;
		MyMap<DependencyType, MyVector<Dependency>> dependencies;
	};

}
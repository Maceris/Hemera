#pragma once

#include <atomic>
#include <cstdint>

#include "front_end/hlir.h"
#include "front_end/type_id.h"
#include "memory/allocator.h"
#include "parser/ast_types.h"

namespace hemera {

	enum class WorkTargetType {
		DEFINITION,
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

		WorkTarget(WorkTargetType type, WorkTargetValue value);
		WorkTarget(const WorkTarget&);
		WorkTarget(WorkTarget&&);
		WorkTarget& operator=(const WorkTarget&);
		WorkTarget& operator=(WorkTarget&&);
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
		std::atomic_int32_t dependency_count;
		WorkType type;
		WorkTarget work_target;

		Work(WorkType type, WorkTarget&& target);
		Work(const Work&) = delete;
		Work(Work&&) = delete;
		Work& operator=(const Work&) = delete;
		Work& operator=(Work&&) = delete;
	};

	struct Dependency {
		WorkTarget dependency;
		Work* owner;

		Dependency(WorkTarget&& dependency, Work* owner);
		Dependency(const Dependency&);
		Dependency(Dependency&&);
		Dependency& operator=(const Dependency&);
		Dependency& operator=(Dependency&&);
	};

	struct Dependencies {
		MyVector<Dependency> discovery;
		MyVector<Dependency> evaluation;
		MyVector<Dependency> type_checking;
	};

	struct WorkTracking {
		MyVector<Work*> blocked;
	};

}
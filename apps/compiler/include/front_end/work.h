#pragma once

#include <atomic>
#include <cstdint>
#include <filesystem>
#include <vector>

#include "front_end/compile_time.h"
#include "front_end/info.h"
#include "front_end/type_id.h"
#include "memory/allocator.h"
#include "parser/ast_types.h"

namespace hemera {

	struct Declaration;

	enum class WorkTargetType {
		DEFINITION,
		/// <summary>
		/// An instance of a generic type, to resolve.
		/// </summary>
		INSTANCE,
		/// <summary>
		/// A function's body, to type check.
		/// </summary>
		BODY,
		/// <summary>
		/// A declared function type's defaults, like an alias's, to check (docs/functions.md, Defaults in
		/// Function Types).
		/// </summary>
		TYPE_DEFAULTS,
		/// <summary>
		/// A top-level #assert, to check.
		/// </summary>
		ASSERT,
		EXPRESSION,
		/// <summary>
		/// Compile-time code to run, for checking that needs its value (docs/compilation.md).
		/// </summary>
		EVALUATION,
		FILE,
		FUNCTION,
		PACKAGE,
	};

	struct FileLocation {
		InternedString package_path;
		InternedString file_name;
	};

	/// <summary>
	/// A node, and the file it's in, for work on definitions and expressions.
	/// </summary>
	struct NodeLocation {
		FileLocation file;
		ast::Node* node;
	};

	/// <summary>
	/// A top-level #if, with any #else_if and #else after it, in one file.
	/// </summary>
	struct IfChain {
		FileLocation file;
		std::vector<ast::Node*> branches;
	};

	union WorkTargetValue {
		InternedString name;
		FileLocation file_location;
		NodeLocation node_location;
		FunctionInfo* function;
		IfChain* if_chain;
		Declaration* declaration;
		Evaluation* evaluation;
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

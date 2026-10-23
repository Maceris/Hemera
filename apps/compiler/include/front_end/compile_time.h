#pragma once

#include <cstdint>
#include <map>
#include <memory>
#include <string>
#include <vector>

namespace hemera {

	namespace ast {
		struct Node;
	}
	struct CheckedBody;
	struct ConstraintRun;
	struct Declaration;
	struct TypeInfo;

	/// <summary>
	/// A value compile-time code gave, in the program's layout: its bytes, and copies of what its strings
	/// and views point to, by the offset of the pointer in bytes (docs/compilation.md, Compile-Time Execution).
	/// </summary>
	struct CompileTimeValue {
		std::vector<uint8_t> bytes;
		std::map<size_t, CompileTimeValue> pointed;
		/// <summary>
		/// For an #insert's operand, which gives a compiler.Code: set before it runs, so the Code can leave
		/// the run, and then the tree it holds (docs/compilation.md, Code Values). A Code can't otherwise.
		/// </summary>
		bool wants_code = false;
		const ast::Node* code = nullptr;
	};

	/// <summary>
	/// Compile-time code to run once: a constant's value that calls a function, or a #run. Checking waits for
	/// it when it needs the value, like an array's count, and generating the program uses the same result,
	/// so the code never runs twice.
	/// </summary>
	struct Evaluation {
		enum class State : uint8_t {
			WAITING,
			DONE,
			// It couldn't run, which was reported.
			FAILED,
		};
		/// <summary>
		/// What to run, and what it was checked as part of: a constant's declaration and its value's checked
		/// body, or a top-level #run's own.
		/// </summary>
		ast::Node* node = nullptr;
		TypeInfo* type = nullptr;
		Declaration* declaration = nullptr;
		std::shared_ptr<CheckedBody> checked;
		std::string file_path;
		State state = State::WAITING;
		/// <summary>
		/// Its EXECUTION work exists.
		/// </summary>
		bool queued = false;
		CompileTimeValue value;
		/// <summary>
		/// A constraint to check, rather than code to run for a value: the #constraint function, its
		/// arguments, and what its requirements found (docs/types.md, Constraints).
		/// </summary>
		std::shared_ptr<ConstraintRun> constraint;
	};

}

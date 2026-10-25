#include "middle_end/generate.h"
#include "middle_end/code_values.h"
#include "util/phase_timer.h"

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <format>
#include <functional>
#include <map>
#include <set>
#include <string>
#include <vector>

#include "error/reporting.h"
#include "front_end/checking.h"
#include "front_end/front_end.h"
#include "front_end/walk.h"
#include "hmir/hmir_dialect.h"
#include "hmir/hmir_ops.h"
#include "hmir/hmir_passes.h"

#include "llvm/ADT/APFloat.h"
#include "llvm/BinaryFormat/Dwarf.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Module.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/LLVMIR/LLVMTypes.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinDialect.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Verifier.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Target/LLVMIR/Dialect/Builtin/BuiltinToLLVMIRTranslation.h"
#include "mlir/Target/LLVMIR/Dialect/LLVMIR/LLVMToLLVMIRTranslation.h"
#include "mlir/Target/LLVMIR/Export.h"
#include "middle_end/jit.h"
#include "middle_end/reflection.h"
#include "middle_end/build.h"

namespace hemera {

	namespace LLVM = mlir::LLVM;

	/*
	 * Code generation, from what the checker recorded of each body (CheckedBody). Every Hemera
	 * value is an LLVM value laid out like its type (docs/types.md, Memory Layout): structs are
	 * packed LLVM structs with their padding as bytes, so offsets match. Every local lives in a
	 * stack slot, which LLVM promotes to registers. Each function takes the context, a pointer,
	 * first. Control flow is HMIR's (scope, loop, if, defer, break, continue, return), lowered to
	 * branches once defers are expanded; a switch is a loop that runs once, so break leaves it.
	 */

	static std::string text_of(InternedString value) {
		return value != nullptr ? std::string(std::string_view(*value)) : std::string();
	}

	static bool is_text(InternedString value, std::string_view text) {
		return value != nullptr && std::string_view(*value) == text;
	}

	static bool is_assign(const ast::Node* node) {
		return TokenType::OPERATOR_ASSIGN == node->value.type;
	}

	/// <summary>
	/// What an expression gave: a value, or a location (where a value is, which value is loaded
	/// from when it's needed), or something that isn't a value, like a type or a package.
	/// </summary>
	struct Emitted {
		ValueKind kind = ValueKind::NOTHING;
		mlir::Value value;
		mlir::Value address;
		TypeInfo* type = nullptr;
		/// <summary>
		/// A call's several results: value is a struct of them.
		/// </summary>
		std::vector<TypeInfo*> results;
		/// <summary>
		/// For a VARIANT, which one; for a BUILTIN_FUNCTION, its name.
		/// </summary>
		size_t variant = 0;
		InternedString name = nullptr;
		/// <summary>
		/// For a typed constant in another constant's value, which can't load from its global:
		/// the constant, whose value is generated again where it's needed.
		/// </summary>
		Declaration* constant = nullptr;
		/// <summary>
		/// A call to a function that never returns.
		/// </summary>
		bool never_returns = false;
		/// <summary>
		/// For a relative pointer's place, the relative pointer stored at address, which reads as type, the pointer it
		/// holds (docs/types.md, Relative Pointers). & and assignment use the place itself.
		/// </summary>
		TypeInfo* relative = nullptr;
	};

	struct Breakable {
		/// <summary>
		/// A loop, which continue goes to, rather than a switch, which only break leaves. Both
		/// are hmir.loop, so break and continue count both.
		/// </summary>
		bool continues;
	};

	struct FunctionState {
		Declaration* declaration = nullptr;
		/// <summary>
		/// It has a DISubprogram, so each statement sets the location of what it generates.
		/// </summary>
		bool debug_info = false;
		CheckedBody* checked = nullptr;
		TypeInfoFunction const* type = nullptr;
		/// <summary>
		/// Each local's slot, by its key (where it's defined).
		/// </summary>
		std::map<const void*, mlir::Value> slots;
		/// <summary>
		/// Locals kept as values rather than in slots: scalars nothing assigns to or takes the address of
		/// (in_slot), by their key. LLVM would take them out of memory anyway; this way it starts with less.
		/// </summary>
		std::map<const void*, mlir::Value> values;
		/// <summary>
		/// The locals that need a slot: assigned to, or with their address taken, by their key.
		/// </summary>
		std::set<const void*> in_slot;
		/// <summary>
		/// Constants defined in the body, like c :: 3, by their key: their value's expression.
		/// </summary>
		std::map<const void*, ast::Node*> constants;
		/// <summary>
		/// The current context, a pointer to a runtime.Context.
		/// </summary>
		mlir::Value context;
		/// <summary>
		/// Where the result goes, for a function whose result is too large for registers (result_through_pointer).
		/// </summary>
		mlir::Value result_pointer;
		std::vector<Breakable> breakables;
		/// <summary>
		/// Where stack slots are made: the function's first block. Null for a constant's
		/// initializer, which can't have any.
		/// </summary>
		mlir::Block* entry = nullptr;
	};

	struct Generator {
		ProgramInfo* program;
		NameRegistry& names;
		mlir::MLIRContext* context;
		mlir::ModuleOp module;
		mlir::OpBuilder builder;
		mlir::Location loc;
		std::map<const TypeInfo*, mlir::Type> types;
		/// <summary>
		/// For each struct, which LLVM element each member is (padding is elements too), or -1
		/// for a #union struct's members, which share its bytes.
		/// </summary>
		std::map<const TypeInfoStruct*, std::vector<int64_t>> member_elements;
		std::map<Declaration*, LLVM::LLVMFuncOp> functions;
		std::map<Declaration*, LLVM::GlobalOp> globals;
		std::set<std::string> symbols;
		std::vector<Declaration*> pending;
		std::map<std::string, LLVM::GlobalOp> strings;
		/// <summary>
		/// Each type's descriptor, the base/compiler TypeInfo a type value points to.
		/// </summary>
		std::map<const TypeInfo*, LLVM::GlobalOp> descriptors;
		/// <summary>
		/// Each entry function's body, which its generated code calls (docs/calling_convention.md, Entry Functions).
		/// </summary>
		std::map<Declaration*, LLVM::LLVMFuncOp> entry_bodies;
		/// <summary>
		/// The table x86_64.entry_points made for each entry function, by its symbol.
		/// </summary>
		std::map<std::string, LLVM::GlobalOp> entry_tables;
		/// <summary>
		/// The module's assembly: entry functions' code, their stubs, and return_to_user.
		/// </summary>
		std::vector<std::string> module_assembly;
		/// <summary>
		/// The libraries #foreign functions the program calls come from, for the linker.
		/// </summary>
		std::set<std::string> libraries;
		/// <summary>
		/// A hosted Linux program that declares #foreign functions of its own, so it links the C
		/// library: it starts through libc's __libc_start_main, and the runtime makes its threads with
		/// pthreads, since C needs its own state set up on every thread that calls it
		/// (docs/compilation.md, Linking C on Linux). base's own #foreign functions don't count.
		/// </summary>
		bool c_library = false;
		/// <summary>
		/// Generating compile-time code (docs/compilation.md, Compile-Time Execution), for #is_compile_time.
		/// </summary>
		bool compile_time = false;
		/// <summary>
		/// What compile-time code gave, by the constant's declaration or the #run's node, so each runs once.
		/// </summary>
		std::map<const void*, CompileTimeValue> compile_time_values;
		size_t compile_time_globals = 0;
		/// <summary>
		/// Generating compile-time code while the program is still being checked: functions and constants
		/// it reaches that aren't checked yet are listed in unchecked instead of reported, and errors are held
		/// back, since the code is generated again once they are.
		/// </summary>
		bool collecting = false;
		std::vector<Declaration*> unchecked;
		/// <summary>
		/// In compile-time code, what it refers to that's in the compiler: type descriptors (middle_end/reflection.h).
		/// </summary>
		std::vector<std::pair<std::string, const void*>> compile_time_symbols;
		/// <summary>
		/// In compile-time code, the program's library of what earlier runs compiled, and what this run defines
		/// for later ones and calls from earlier ones (middle_end/jit.h).
		/// </summary>
		CompileTimeLinks links;
		/// <summary>
		/// The file errors are in when there's no declaration being generated, like a top-level #run's.
		/// </summary>
		std::string file_path;
		struct HeldError {
			std::string file_path;
			uint32_t line;
			uint16_t column;
			std::string what;
		};
		std::vector<HeldError> held;
		/// <summary>
		/// How many arrays descriptors have used, like an enum's members, for their globals' names.
		/// </summary>
		size_t type_data = 0;
		/// <summary>
		/// Constants whose value is being generated, so one inlined into another can't loop.
		/// </summary>
		std::set<Declaration*> inlining;
		/// <summary>
		/// What the left of |> gave, for the call on its right.
		/// </summary>
		std::vector<Emitted> piped;
		FunctionState* state = nullptr;
		const Options* options = nullptr;
		InternedString input_package = nullptr;
		/// <summary>
		/// Globals the linker must keep though nothing refers to them: #externally_initialized ones.
		/// </summary>
		std::vector<LLVM::GlobalOp> used;
		bool failed = false;
		/// <summary>
		/// Debug info (Options::debug_info): the program's compile unit, made with its first function,
		/// and each source file's.
		/// </summary>
		LLVM::DICompileUnitAttr compile_unit;
		std::map<std::string, LLVM::DIFileAttr> debug_files;
		/// <summary>
		/// The functions with debug info and their names, for intrinsics.function_names' table, and
		/// that table's view once the program asks for it.
		/// </summary>
		std::vector<std::pair<LLVM::LLVMFuncOp, std::string>> named_functions;
		LLVM::GlobalOp function_names;
		TypeInfo* function_names_type = nullptr;

		Generator(ProgramInfo* program_, mlir::ModuleOp module_)
			: program{ program_ }
			, names{ program_->names }
			, context{ module_.getContext() }
			, module{ module_ }
			, builder{ module_.getContext() }
			, loc{ builder.getUnknownLoc() }
		{}
	};

	static std::string current_file(Generator& generator) {
		Declaration* declaration = generator.state != nullptr ? generator.state->declaration : nullptr;
		return declaration != nullptr ? file_path_of(declaration->package_path, declaration->file_name) : generator.file_path;
	}

	// Reports what code generation can't do yet; the caller carries on with a placeholder.
	static void unsupported(Generator& generator, const ast::Node* node, std::string what) {
		generator.failed = true;
		if (generator.collecting) {
			generator.held.push_back({ current_file(generator), node != nullptr ? node->value.line_number : 0,
				node != nullptr ? node->value.column_number : uint16_t(0), std::move(what) });
			return;
		}
		report_error(ErrorCode::E5002, current_file(generator), node != nullptr ? node->value.line_number : 0,
			node != nullptr ? node->value.column_number : 0, std::move(what));
	}

	// ---------------------------------------------------------------------------------------------
	// Types

	static TypeInfo const* base(TypeInfo const* type) {
		return type != nullptr ? get_base_type(type) : nullptr;
	}

	static bool is_variant(TypeInfo const* type, TypeInfoVariant variant) {
		type = base(type);
		return type != nullptr && variant == type->variant;
	}

	static bool is_signed(TypeInfo const* type) {
		type = base(type);
		if (type != nullptr && TypeInfoVariant::ENUM == type->variant) {
			type = base(static_cast<TypeInfoEnum const*>(type)->backing_type);
		}
		return type != nullptr && TypeInfoVariant::INTEGER == type->variant
			&& static_cast<TypeInfoInteger const*>(type)->is_signed;
	}

	static bool is_float(TypeInfo const* type) {
		return is_variant(type, TypeInfoVariant::FLOAT);
	}

	static bool is_raw_string(TypeInfo const* type) {
		return is_variant(type, TypeInfoVariant::STRING) && static_cast<TypeInfoString const*>(base(type))->is_raw;
	}

	static mlir::Type pointer_type(Generator& generator) {
		return LLVM::LLVMPointerType::get(generator.context);
	}

	static mlir::Type integer_type(Generator& generator, size_t bytes) {
		return mlir::IntegerType::get(generator.context, static_cast<unsigned>(bytes * 8));
	}

	static mlir::Type usize_type(Generator& generator) {
		return integer_type(generator, POINTER_SIZE);
	}

	static mlir::Type llvm_type(Generator& generator, TypeInfo const* type);

	// A struct of the given element types, packed: its padding is explicit, to match our layout.
	static mlir::Type packed(Generator& generator, const std::vector<mlir::Type>& elements) {
		return LLVM::LLVMStructType::getLiteral(generator.context, elements, true);
	}

	static mlir::Type bytes_type(Generator& generator, size_t count) {
		return LLVM::LLVMArrayType::get(integer_type(generator, 1), count);
	}

	// A count and a pointer: a string, or a view of an array.
	static mlir::Type view_type(Generator& generator) {
		return packed(generator, { usize_type(generator), pointer_type(generator) });
	}

	// A struct's members at their offsets, with padding between them and at the end.
	static mlir::Type struct_type(Generator& generator, TypeInfoStruct const* type) {
		std::vector<mlir::Type> elements;
		std::vector<int64_t> indexes;
		if (type->is_union) {
			elements.push_back(bytes_type(generator, type->size));
			indexes.assign(type->members.size(), -1);
		}
		else {
			size_t offset = 0;
			for (const StructMember& member : type->members) {
				if (member.offset > offset) {
					elements.push_back(bytes_type(generator, member.offset - offset));
				}
				indexes.push_back(static_cast<int64_t>(elements.size()));
				elements.push_back(llvm_type(generator, member.member_type));
				offset = member.offset + member.member_type->size;
			}
			if (type->size > offset) {
				elements.push_back(bytes_type(generator, type->size - offset));
			}
		}
		generator.member_elements[type] = indexes;
		return packed(generator, elements);
	}

	static mlir::Type llvm_type(Generator& generator, TypeInfo const* type) {
		if (type == nullptr) {
			return LLVM::LLVMVoidType::get(generator.context);
		}
		auto cached = generator.types.find(type);
		if (cached != generator.types.end()) {
			return cached->second;
		}
		mlir::Type result;
		const TypeInfoVariant variant = type->variant;
		if (TypeInfoVariant::ALIAS == variant) {
			result = llvm_type(generator, static_cast<TypeInfoAlias const*>(type)->base_type);
		}
		else if (TypeInfoVariant::INTEGER == variant || TypeInfoVariant::ENUM == variant
			|| TypeInfoVariant::CHAR == variant) {
			result = integer_type(generator, type->size);
		}
		else if (TypeInfoVariant::BOOLEAN == variant) {
			// bool is an i1, which takes a byte in memory; b16 to b64 are integers
			result = type->size == 1 ? mlir::IntegerType::get(generator.context, 1) : integer_type(generator, type->size);
		}
		else if (TypeInfoVariant::FLOAT == variant && native_of(const_cast<TypeInfo*>(type)) != type) {
			// An endian-specific float is its bytes, in its order, until it's read as its native type
			result = integer_type(generator, type->size);
		}
		else if (TypeInfoVariant::FLOAT == variant) {
			result = type->size == 2 ? static_cast<mlir::Type>(mlir::Float16Type::get(generator.context))
				: type->size == 4 ? static_cast<mlir::Type>(mlir::Float32Type::get(generator.context))
				: static_cast<mlir::Type>(mlir::Float64Type::get(generator.context));
		}
		else if (TypeInfoVariant::POINTER == variant) {
			auto pointer = static_cast<TypeInfoPointer const*>(type);
			result = pointer->is_relative ? integer_type(generator, pointer->size) : pointer_type(generator);
		}
		else if (TypeInfoVariant::FUNCTION == variant || TypeInfoVariant::TYPE == variant) {
			result = pointer_type(generator);
		}
		else if (TypeInfoVariant::STRING == variant) {
			result = static_cast<TypeInfoString const*>(type)->is_raw ? pointer_type(generator) : view_type(generator);
		}
		else if (TypeInfoVariant::ANY == variant) {
			result = packed(generator, { pointer_type(generator), pointer_type(generator) });
		}
		else if (TypeInfoVariant::ARRAY == variant) {
			auto array = static_cast<TypeInfoArray const*>(type);
			if (ArrayType::STATIC == array->array_type) {
				result = LLVM::LLVMArrayType::get(llvm_type(generator, array->element_type), array->count);
			}
			else if (ArrayType::VIEW == array->array_type) {
				result = view_type(generator);
			}
			else {
				// count, data, capacity, and the allocator's function and data
				result = packed(generator, { usize_type(generator), pointer_type(generator), usize_type(generator),
					pointer_type(generator), pointer_type(generator) });
			}
		}
		else if (TypeInfoVariant::VECTOR == variant) {
			// A vector[bool, n]'s lanes are bytes of 0 or 1, as a bool is in memory
			auto vector = static_cast<TypeInfoVector const*>(type);
			mlir::Type lane = is_variant(vector->element_type, TypeInfoVariant::BOOLEAN)
				? integer_type(generator, 1) : llvm_type(generator, vector->element_type);
			result = mlir::VectorType::get({ static_cast<int64_t>(vector->count) }, lane);
		}
		else if (TypeInfoVariant::COMPLEX == variant || TypeInfoVariant::QUATERNION == variant) {
			auto composite = static_cast<TypeInfoComposite const*>(type);
			result = LLVM::LLVMArrayType::get(integer_type(generator, composite->part_size), type->size / composite->part_size);
		}
		else if (TypeInfoVariant::STRUCT == variant) {
			result = struct_type(generator, static_cast<TypeInfoStruct const*>(type));
		}
		else if (TypeInfoVariant::UNION == variant && static_cast<TypeInfoUnion const*>(type)->null_is_none) {
			// An optional of a pointer that's never null: the pointer, null for None; a relative one's offset, 0 for None
			TypeInfoPointer const* relative = relative_pointer_of(type);
			result = relative != nullptr ? integer_type(generator, relative->size) : pointer_type(generator);
		}
		else if (TypeInfoVariant::UNION == variant) {
			// The tag, then the bytes every variant's values share
			auto union_type = static_cast<TypeInfoUnion const*>(type);
			const size_t tag = union_type->tag_type->size;
			std::vector<mlir::Type> elements{ integer_type(generator, tag) };
			if (type->size > tag) {
				elements.push_back(bytes_type(generator, type->size - tag));
			}
			result = packed(generator, elements);
		}
		else {
			result = LLVM::LLVMVoidType::get(generator.context);
		}
		generator.types[type] = result;
		return result;
	}

	// The most a value can be and still be passed or returned in registers, two of them (docs/calling_convention.md).
	constexpr size_t LARGEST_IN_REGISTERS = 16;

	// Whether a function uses Hemera's own convention, not a platform's one like .c that foreign code shares.
	static bool hemera_convention(TypeInfoFunction const* function) {
		return text_of(function->calling_convention).empty();
	}

	// Whether a parameter of a function is passed as a pointer to a copy the caller makes, being too large for registers.
	static bool parameter_by_pointer(TypeInfoFunction const* function, const FunctionInput& input) {
		return hemera_convention(function) && !input.is_varargs && input.type != nullptr && input.type->size > LARGEST_IN_REGISTERS;
	}

	// Whether a function's results are written through a pointer the caller passes first, being too large for registers.
	static bool result_through_pointer(TypeInfoFunction const* function) {
		if (!hemera_convention(function) || function->output.empty()) {
			return false;
		}
		size_t total = 0;
		for (const FunctionOutput& output : function->output) {
			total += output.type != nullptr ? output.type->size : 0;
		}
		return total > LARGEST_IN_REGISTERS;
	}

	// A function's results as one LLVM type: its result, or a struct of several, or void.
	static mlir::Type results_type(Generator& generator, TypeInfoFunction const* function) {
		if (function->output.size() == 1) {
			return llvm_type(generator, function->output[0].type);
		}
		if (function->output.size() > 1) {
			std::vector<mlir::Type> results;
			for (const FunctionOutput& output : function->output) {
				results.push_back(llvm_type(generator, output.type));
			}
			return LLVM::LLVMStructType::getLiteral(generator.context, results);
		}
		return LLVM::LLVMVoidType::get(generator.context);
	}

	/*
	 * A function's LLVM type: where its results go, if they're too large for registers, then the context, if it
	 * takes one, then its parameters, each too large for registers as a pointer; its result, or a struct of several.
	 */
	static LLVM::LLVMFunctionType function_type(Generator& generator, TypeInfoFunction const* function, bool with_context = true) {
		std::vector<mlir::Type> parameters;
		const bool through_pointer = result_through_pointer(function);
		if (through_pointer) {
			parameters.push_back(pointer_type(generator));
		}
		if (with_context) {
			parameters.push_back(pointer_type(generator));
		}
		for (const FunctionInput& input : function->input) {
			// Varargs are a view of them
			parameters.push_back(input.is_varargs ? view_type(generator)
				: parameter_by_pointer(function, input) ? pointer_type(generator) : llvm_type(generator, input.type));
		}
		mlir::Type result = through_pointer ? LLVM::LLVMVoidType::get(generator.context) : results_type(generator, function);
		return LLVM::LLVMFunctionType::get(result, parameters);
	}

	// ---------------------------------------------------------------------------------------------
	// Small helpers

	static mlir::Value constant_int(Generator& generator, mlir::Type type, int64_t value) {
		// A vector's: the value in every lane
		if (auto vector = llvm::dyn_cast<mlir::VectorType>(type)) {
			const unsigned bits = vector.getElementType().getIntOrFloatBitWidth();
			return LLVM::ConstantOp::create(generator.builder, generator.loc, type,
				mlir::DenseElementsAttr::get(vector, llvm::APInt(bits, static_cast<uint64_t>(value), true)));
		}
		return LLVM::ConstantOp::create(generator.builder, generator.loc, type, value);
	}

	// A lane's value as the vector holds it: a bool, an i1, as a byte.
	static mlir::Value as_lane(Generator& generator, mlir::Value value, mlir::Type vector_type) {
		mlir::Type lane = llvm::cast<mlir::VectorType>(vector_type).getElementType();
		if (value.getType() != lane && value.getType().isInteger(1)) {
			return LLVM::ZExtOp::create(generator.builder, generator.loc, lane, value);
		}
		return value;
	}

	// One value in every lane of a vector.
	static mlir::Value splat(Generator& generator, mlir::Value scalar, mlir::Type vector_type) {
		auto vector = llvm::cast<mlir::VectorType>(vector_type);
		mlir::Value lane = as_lane(generator, scalar, vector_type);
		mlir::Value first = LLVM::InsertElementOp::create(generator.builder, generator.loc,
			LLVM::PoisonOp::create(generator.builder, generator.loc, vector_type), lane,
			LLVM::ConstantOp::create(generator.builder, generator.loc, generator.builder.getI32Type(), 0));
		const llvm::SmallVector<int32_t> mask(static_cast<size_t>(vector.getNumElements()), 0);
		return LLVM::ShuffleVectorOp::create(generator.builder, generator.loc, first, first, mask);
	}

	static mlir::Value zero_of(Generator& generator, mlir::Type type) {
		return LLVM::ZeroOp::create(generator.builder, generator.loc, type);
	}

	static bool in_function(Generator& generator) {
		return generator.state != nullptr && generator.state->entry != nullptr;
	}

	// A stack slot for a value of an LLVM type, made at the start of the function.
	static mlir::Value make_raw_slot(Generator& generator, mlir::Type type, size_t alignment) {
		if (!in_function(generator)) {
			unsupported(generator, nullptr, "a constant's value needs memory to be generated, which isn't supported yet");
			return zero_of(generator, pointer_type(generator));
		}
		mlir::OpBuilder::InsertionGuard guard(generator.builder);
		generator.builder.setInsertionPointToStart(generator.state->entry);
		mlir::Value one = constant_int(generator, usize_type(generator), 1);
		return LLVM::AllocaOp::create(generator.builder, generator.loc, pointer_type(generator), type, one,
			static_cast<unsigned>(alignment));
	}

	static mlir::Value make_slot(Generator& generator, TypeInfo const* type) {
		return make_raw_slot(generator, llvm_type(generator, type), std::max<size_t>(type->alignment, 1));
	}

	static mlir::Value load(Generator& generator, TypeInfo const* type, mlir::Value address) {
		return LLVM::LoadOp::create(generator.builder, generator.loc, llvm_type(generator, type), address);
	}

	// Values bigger than this are zeroed with memset and copied with memmove, which LLVM handles far better
	// than loading and storing a large aggregate whole.
	constexpr size_t LARGEST_WHOLE_STORE = 64;

	/*
	 * The bytes a value of an LLVM type takes, as Hemera lays it out: integers, floating-point values, pointers,
	 * and arrays and packed structs of them, with no padding anywhere. 0 for anything else.
	 */
	static uint64_t aggregate_size(Generator& generator, mlir::Type type) {
		if (auto integer = mlir::dyn_cast<mlir::IntegerType>(type)) {
			return (integer.getWidth() + 7) / 8;
		}
		if (auto floating = mlir::dyn_cast<mlir::FloatType>(type)) {
			return (floating.getWidth() + 7) / 8;
		}
		if (mlir::isa<LLVM::LLVMPointerType>(type)) {
			return aggregate_size(generator, usize_type(generator));
		}
		if (auto array = mlir::dyn_cast<LLVM::LLVMArrayType>(type)) {
			return array.getNumElements() * aggregate_size(generator, array.getElementType());
		}
		if (auto structure = mlir::dyn_cast<LLVM::LLVMStructType>(type); structure && structure.isPacked()) {
			uint64_t total = 0;
			for (mlir::Type field : structure.getBody()) {
				const uint64_t size = aggregate_size(generator, field);
				if (size == 0) {
					return 0;
				}
				total += size;
			}
			return total;
		}
		return 0;
	}

	// Where the part of an aggregate at path starts, in bytes, and its type; false if aggregate_size can't say.
	static bool part_offset(Generator& generator, mlir::Type type, llvm::ArrayRef<int64_t> path, uint64_t& offset, mlir::Type& part) {
		offset = 0;
		part = type;
		for (int64_t index : path) {
			if (auto array = mlir::dyn_cast<LLVM::LLVMArrayType>(part)) {
				const uint64_t element = aggregate_size(generator, array.getElementType());
				if (element == 0) {
					return false;
				}
				offset += element * static_cast<uint64_t>(index);
				part = array.getElementType();
			}
			else if (auto structure = mlir::dyn_cast<LLVM::LLVMStructType>(part); structure && structure.isPacked()) {
				for (int64_t i = 0; i < index; ++i) {
					const uint64_t size = aggregate_size(generator, structure.getBody()[static_cast<size_t>(i)]);
					if (size == 0) {
						return false;
					}
					offset += size;
				}
				part = structure.getBody()[static_cast<size_t>(index)];
			}
			else {
				return false;
			}
		}
		return true;
	}

	static mlir::Value offset_address(Generator& generator, mlir::Value address, size_t offset);

	// Whether nothing after op in its block, up to where code is being generated, could write memory.
	static bool nothing_written_since(Generator& generator, mlir::Operation* op) {
		if (op->getBlock() != generator.builder.getInsertionBlock()) {
			return false;
		}
		for (mlir::Operation* next = op->getNextNode(); next != nullptr; next = next->getNextNode()) {
			if (!mlir::isMemoryEffectFree(next)) {
				return false;
			}
		}
		return true;
	}

	/*
	 * A value stored whole has LLVM split it into a value per element, which for a large one is slow to
	 * generate code for, or more than instruction selection can hold. So a large value is stored in parts:
	 * a zero with memset; one just loaded, with nothing written since, with memmove from where it was; and
	 * one built by inserting parts into a zero, like a struct literal, with memset and then each part.
	 */
	static mlir::Value constant_global(Generator& generator, mlir::Type type, size_t alignment, const std::string& name,
		const std::function<mlir::Value()>& build);

	static void store(Generator& generator, mlir::Value value, mlir::Value address) {
		mlir::OpBuilder& b = generator.builder;
		const mlir::Location l = generator.loc;
		const uint64_t size = in_function(generator) ? aggregate_size(generator, value.getType()) : 0;
		if (size <= LARGEST_WHOLE_STORE) {
			LLVM::StoreOp::create(b, l, value, address);
			return;
		}
		mlir::Value bytes = constant_int(generator, usize_type(generator), static_cast<int64_t>(size));
		if (auto zero = value.getDefiningOp<LLVM::ZeroOp>()) {
			LLVM::MemsetOp::create(b, l, address, constant_int(generator, integer_type(generator, 1), 0), bytes, false);
			if (zero->use_empty()) {
				zero->erase();
			}
			return;
		}
		if (auto loaded = value.getDefiningOp<LLVM::LoadOp>(); loaded && !loaded.getVolatile_() && nothing_written_since(generator, loaded)) {
			LLVM::MemmoveOp::create(b, l, address, loaded.getAddr(), bytes, false);
			if (loaded->use_empty()) {
				loaded->erase();
			}
			return;
		}
		// The parts inserted, innermost first, down to the zero they were inserted into
		std::vector<LLVM::InsertValueOp> inserts;
		mlir::Value whole = value;
		while (auto insert = whole.getDefiningOp<LLVM::InsertValueOp>()) {
			inserts.push_back(insert);
			whole = insert.getContainer();
		}
		const bool from_nothing = whole.getDefiningOp<LLVM::ZeroOp>() || whole.getDefiningOp<LLVM::UndefOp>()
			|| whole.getDefiningOp<LLVM::PoisonOp>();
		bool placed = from_nothing && !inserts.empty();
		std::vector<std::pair<uint64_t, mlir::Value>> parts;
		for (auto each = inserts.rbegin(); placed && each != inserts.rend(); ++each) {
			uint64_t offset = 0;
			mlir::Type part;
			placed = part_offset(generator, value.getType(), each->getPosition(), offset, part);
			parts.emplace_back(offset, each->getValue());
		}
		if (placed) {
			LLVM::MemsetOp::create(b, l, address, constant_int(generator, integer_type(generator, 1), 0), bytes, false);
			for (const auto& [offset, part] : parts) {
				store(generator, part, offset_address(generator, address, offset));
			}
			return;
		}
		// A large constant, like a table or #file_data's bytes: kept in a read-only global and copied, since
		// storing it whole has LLVM split it into a store for every few bytes, which takes a long time to compile
		if (auto constant = value.getDefiningOp<LLVM::ConstantOp>()) {
			const mlir::Attribute contents = constant.getValue();
			const mlir::Type type = value.getType();
			mlir::Value from = constant_global(generator, type, 8, std::format("stored.{}", generator.compile_time_globals++),
				[&]() { return LLVM::ConstantOp::create(b, l, type, contents); });
			LLVM::MemcpyOp::create(b, l, address, from, bytes, false);
			if (constant->use_empty()) {
				constant->erase();
			}
			return;
		}
		LLVM::StoreOp::create(b, l, value, address);
	}

	// Zero the value of type at address.
	static void store_zero(Generator& generator, TypeInfo* type, mlir::Value address) {
		if (type != nullptr && type->size > LARGEST_WHOLE_STORE) {
			LLVM::MemsetOp::create(generator.builder, generator.loc, address, constant_int(generator, integer_type(generator, 1), 0),
				constant_int(generator, usize_type(generator), static_cast<int64_t>(type->size)), false);
			return;
		}
		store(generator, zero_of(generator, llvm_type(generator, type)), address);
	}

	static mlir::Value extract(Generator& generator, mlir::Value whole, int64_t index) {
		return LLVM::ExtractValueOp::create(generator.builder, generator.loc, whole, llvm::ArrayRef<int64_t>{ index });
	}

	static mlir::Value insert(Generator& generator, mlir::Value whole, mlir::Value part, llvm::ArrayRef<int64_t> path) {
		return LLVM::InsertValueOp::create(generator.builder, generator.loc, whole, part, path);
	}

	// A count and a pointer, as a string or view.
	static mlir::Value make_view(Generator& generator, mlir::Value count, mlir::Value data) {
		mlir::Value result = LLVM::UndefOp::create(generator.builder, generator.loc, view_type(generator));
		result = insert(generator, result, count, { 0 });
		return insert(generator, result, data, { 1 });
	}

	static Emitted value(mlir::Value v, TypeInfo* type) {
		Emitted result;
		result.kind = ValueKind::VALUE;
		result.value = v;
		result.type = type;
		return result;
	}

	static Emitted location(mlir::Value address, TypeInfo* type) {
		Emitted result;
		result.kind = ValueKind::VALUE;
		result.address = address;
		result.type = type;
		return result;
	}

	static mlir::Value value_of(Generator& generator, const Emitted& emitted);

	// A value's address: its own, for a location, or a new slot holding it.
	static mlir::Value address_of(Generator& generator, const Emitted& emitted) {
		// A relative pointer's place holds an offset: what's read from it, in a slot of its own
		if (emitted.address && emitted.relative == nullptr) {
			return emitted.address;
		}
		if (emitted.relative != nullptr) {
			mlir::Value slot = make_slot(generator, emitted.type);
			store(generator, value_of(generator, emitted), slot);
			return slot;
		}
		mlir::Value slot = make_slot(generator, emitted.type);
		store(generator, emitted.value, slot);
		return slot;
	}

	static mlir::Value emit_constant_value(Generator& generator, Declaration* declaration, TypeInfo* type, const ast::Node* where);
	static mlir::Value type_descriptor(Generator& generator, TypeInfo const* type);
	static mlir::Value strings_equal(Generator& generator, mlir::Value left, mlir::Value right);

	/*
	 * docs/types.md, Relative Pointers: the pointer a relative pointer of type at address holds, its offset from its own
	 * address added to that address; for an optional one, null at offset 0.
	 */
	static mlir::Value read_relative(Generator& generator, TypeInfo const* type, mlir::Value address) {
		mlir::OpBuilder& b = generator.builder;
		const mlir::Location l = generator.loc;
		TypeInfoPointer const* relative = relative_pointer_of(type);
		mlir::Type wide = usize_type(generator);
		mlir::Value offset = LLVM::LoadOp::create(b, l, integer_type(generator, relative->size), address);
		mlir::Value distance = relative->size < POINTER_SIZE ? static_cast<mlir::Value>(LLVM::SExtOp::create(b, l, wide, offset)) : offset;
		mlir::Value at = LLVM::PtrToIntOp::create(b, l, wide, address);
		mlir::Value pointer = LLVM::IntToPtrOp::create(b, l, pointer_type(generator), static_cast<mlir::Value>(LLVM::AddOp::create(b, l, at, distance)));
		if (TypeInfoVariant::UNION != base(type)->variant) {
			return pointer;
		}
		mlir::Value none = LLVM::ICmpOp::create(b, l, LLVM::ICmpPredicate::eq, offset, constant_int(generator, offset.getType(), 0));
		return LLVM::SelectOp::create(b, l, none, zero_of(generator, pointer_type(generator)), pointer);
	}

	static void fail_check(Generator& generator, const ast::Node* where, const std::string& message);
	static void emit_if(Generator& generator, mlir::Value condition, const std::function<bool()>& then,
		const std::function<bool()>& otherwise);

	/*
	 * Set the relative pointer of type at address to pointer: the difference between where it points and the
	 * relative pointer's own address, or for an optional one, 0 for null. A difference too large for it, or 0, which
	 * points at the relative pointer itself and would read as None, fails the check, at where.
	 */
	static void write_relative(Generator& generator, TypeInfo const* type, mlir::Value pointer, mlir::Value address,
		const ast::Node* where) {

		mlir::OpBuilder& b = generator.builder;
		const mlir::Location l = generator.loc;
		TypeInfoPointer const* relative = relative_pointer_of(type);
		mlir::Type wide = usize_type(generator);
		mlir::Type narrow = integer_type(generator, relative->size);
		mlir::Value distance = LLVM::SubOp::create(b, l, LLVM::PtrToIntOp::create(b, l, wide, pointer),
			LLVM::PtrToIntOp::create(b, l, wide, address));
		mlir::Value offset = relative->size < POINTER_SIZE ? static_cast<mlir::Value>(LLVM::TruncOp::create(b, l, narrow, distance))
			: distance;
		if (in_function(generator)) {
			// It fits, and isn't 0: a relative pointer to itself, which an optional one would read as None
			mlir::Value fits = relative->size < POINTER_SIZE
				? static_cast<mlir::Value>(LLVM::ICmpOp::create(b, l, LLVM::ICmpPredicate::eq, LLVM::SExtOp::create(b, l, wide, offset), distance))
				: constant_int(generator, integer_type(generator, 1), 1);
			mlir::Value elsewhere = LLVM::ICmpOp::create(b, l, LLVM::ICmpPredicate::ne, distance, constant_int(generator, wide, 0));
			mlir::Value good = LLVM::AndOp::create(b, l, fits, elsewhere);
			if (TypeInfoVariant::UNION == base(type)->variant) {
				mlir::Value null = LLVM::ICmpOp::create(b, l, LLVM::ICmpPredicate::eq, pointer, zero_of(generator, pointer_type(generator)));
				good = LLVM::OrOp::create(b, l, good, null);
			}
			mlir::Value bad = LLVM::XOrOp::create(b, l, good, constant_int(generator, good.getType(), 1));
			emit_if(generator, bad, [&]() {
				fail_check(generator, where, std::format("a relative pointer is set to point at itself, or further than its {} "
					"bits of offset from where it's stored reach", relative->size * 8));
				return true;
			}, nullptr);
		}
		if (TypeInfoVariant::UNION == base(type)->variant) {
			mlir::Value null = LLVM::ICmpOp::create(b, l, LLVM::ICmpPredicate::eq, pointer, zero_of(generator, pointer_type(generator)));
			offset = LLVM::SelectOp::create(b, l, null, constant_int(generator, narrow, 0), offset);
		}
		LLVM::StoreOp::create(b, l, offset, address);
	}

	static mlir::Value value_of(Generator& generator, const Emitted& emitted) {
		if (emitted.value) {
			return emitted.value;
		}
		// A type as a value: its descriptor
		if (ValueKind::TYPE == emitted.kind && emitted.type != nullptr) {
			return type_descriptor(generator, emitted.type);
		}
		if (emitted.constant != nullptr && !in_function(generator)) {
			return emit_constant_value(generator, emitted.constant, emitted.constant->value_type, nullptr);
		}
		if (emitted.address && emitted.relative != nullptr) {
			return read_relative(generator, emitted.relative, emitted.address);
		}
		if (emitted.address && emitted.type != nullptr && relative_pointer_of(emitted.type) != nullptr) {
			return read_relative(generator, emitted.type, emitted.address);
		}
		if (emitted.address && emitted.type != nullptr) {
			return load(generator, emitted.type, emitted.address);
		}
		return zero_of(generator, llvm_type(generator, emitted.type != nullptr ? emitted.type : BUILTIN_int));
	}

	// The address of a byte offset from a pointer.
	static mlir::Value offset_address(Generator& generator, mlir::Value address, size_t offset) {
		if (offset == 0) {
			return address;
		}
		llvm::SmallVector<LLVM::GEPArg> indices{ static_cast<int32_t>(offset) };
		return LLVM::GEPOp::create(generator.builder, generator.loc, pointer_type(generator), integer_type(generator, 1),
			address, indices);
	}

	// The address of an element of type at index, from where the elements start.
	static mlir::Value element_address(Generator& generator, mlir::Value data, TypeInfo const* element, mlir::Value index) {
		return LLVM::GEPOp::create(generator.builder, generator.loc, pointer_type(generator), llvm_type(generator, element),
			data, mlir::ValueRange{ index });
	}

	static const CheckedNode* checked(Generator& generator, const ast::Node* node) {
		if (generator.state == nullptr || generator.state->checked == nullptr) {
			return nullptr;
		}
		auto iter = generator.state->checked->nodes.find(node);
		return iter == generator.state->checked->nodes.end() ? nullptr : &iter->second;
	}

	static const CheckedNode* head_of(Generator& generator, const ast::Node* node) {
		if (generator.state == nullptr || generator.state->checked == nullptr) {
			return nullptr;
		}
		auto iter = generator.state->checked->heads.find(node);
		return iter == generator.state->checked->heads.end() ? nullptr : &iter->second;
	}

	static bool is_untyped(ValueKind kind) {
		return ValueKind::UNTYPED_INTEGER == kind || ValueKind::UNTYPED_FLOAT == kind
			|| ValueKind::UNTYPED_STRING == kind || ValueKind::UNTYPED_BOOLEAN == kind
			|| ValueKind::NULL_VALUE == kind;
	}

	// The type an untyped value takes where nothing else decides: an int, an f64, a string, a bool.
	static TypeInfo* usual(ValueKind kind) {
		return ValueKind::UNTYPED_FLOAT == kind ? BUILTIN_f64
			: ValueKind::UNTYPED_STRING == kind ? BUILTIN_string
			: ValueKind::UNTYPED_BOOLEAN == kind ? BUILTIN_bool
			: ValueKind::NULL_VALUE == kind ? BUILTIN_rawptr
			: BUILTIN_int;
	}

	// Whether an untyped value can be a value of type directly, like 5 a u8 or 0.5 an f32.
	static bool takes_untyped(ValueKind kind, TypeInfo const* type) {
		TypeInfo const* target = base(type);
		if (target == nullptr) {
			return false;
		}
		const TypeInfoVariant variant = target->variant;
		if (ValueKind::UNTYPED_INTEGER == kind) {
			return TypeInfoVariant::INTEGER == variant || TypeInfoVariant::FLOAT == variant
				|| TypeInfoVariant::CHAR == variant || TypeInfoVariant::ENUM == variant;
		}
		if (ValueKind::UNTYPED_FLOAT == kind) {
			return TypeInfoVariant::FLOAT == variant;
		}
		if (ValueKind::UNTYPED_STRING == kind) {
			return TypeInfoVariant::STRING == variant;
		}
		if (ValueKind::UNTYPED_BOOLEAN == kind) {
			return TypeInfoVariant::BOOLEAN == variant;
		}
		return ValueKind::NULL_VALUE == kind && (TypeInfoVariant::POINTER == variant || TypeInfoVariant::STRING == variant
			|| TypeInfoVariant::FUNCTION == variant || TypeInfoVariant::UNION == variant);
	}

	// The type an optional or result holds: Some's or Ok's.
	static TypeInfo* held_type(TypeInfo const* type) {
		auto union_type = static_cast<TypeInfoUnion const*>(base(type));
		return !union_type->variants.empty() && !union_type->variants[0].types.empty() ? union_type->variants[0].types[0] : nullptr;
	}

	// The type an untyped value is generated as, where it's used as expected.
	static TypeInfo* untyped_as(ValueKind kind, TypeInfo* expected) {
		if (takes_untyped(kind, expected)) {
			return expected;
		}
		// An optional's or result's value: 5 as an int?, made Some(5) by converting
		if (is_variant(expected, TypeInfoVariant::UNION) && takes_untyped(kind, held_type(expected))) {
			return held_type(expected);
		}
		return usual(kind);
	}

	// The type a node was checked as, or for an untyped one, the type it's used as.
	static TypeInfo* type_at(Generator& generator, const ast::Node* node, TypeInfo* expected) {
		const CheckedNode* found = checked(generator, node);
		if (found == nullptr) {
			return expected;
		}
		if (is_untyped(found->kind)) {
			return untyped_as(found->kind, expected);
		}
		return found->type;
	}

	static Declaration* base_declaration_named(Generator& generator, std::string_view folder, std::string_view name) {
		std::scoped_lock<std::mutex> lock(generator.names.mutex);
		auto iter = generator.names.declarations.find(std::make_pair(intern(std::format("{}{}", BASE_PACKAGE_PREFIX, folder)),
			intern(std::string(name))));
		return iter != generator.names.declarations.end() ? iter->second : nullptr;
	}

	// ---------------------------------------------------------------------------------------------
	// Functions and strings, made as they're first used

	static std::string symbol_for(Generator& generator, Declaration* declaration) {
		std::string package = text_of(declaration->package_path);
		const size_t slash = package.find_last_of("/\\");
		std::string name = std::format("{}.{}", slash == std::string::npos ? package : package.substr(slash + 1),
			text_of(declaration->name));
		std::string unique = name;
		for (int i = 2; generator.symbols.contains(unique); ++i) {
			unique = std::format("{}.{}", name, i);
		}
		generator.symbols.insert(unique);
		return unique;
	}

	// Whether a declaration's name has a directive after it, like main #export.
	static bool has_name_directive(Declaration* declaration, std::string_view directive) {
		ast::Node* names_node = declaration->node->children[0];
		std::vector<ast::Node*> names{ names_node };
		if (ast::NodeType::LIST == names_node->node_type) {
			names.assign(names_node->children.begin(), names_node->children.end());
		}
		for (ast::Node* name : names) {
			if (name->value.value == nullptr || *name->value.value != *declaration->name) {
				continue;
			}
			for (ast::Node* child : name->children) {
				if (is_text(child->value.value, directive)) {
					return true;
				}
			}
		}
		return false;
	}

	static bool has_convention(TypeInfoFunction const* function, std::string_view convention) {
		return text_of(function->calling_convention).find(convention) != std::string::npos;
	}

	/*
	 * Whether Hemera's own functions are called with System V's convention though the target's C
	 * convention is another: on Windows x64, so the fiber switches and morestack are the same as
	 * elsewhere (docs/calling_convention.md, Windows x64).
	 */
	static bool system_v_on_windows(const Options& options) {
		return OSType::Win32 == options.os && ArchType::x86_64 == options.architecture;
	}

	// The LLVM convention functions of a type are called with.
	static LLVM::cconv::CConv convention_of(Generator& generator, TypeInfoFunction const* function) {
		if (has_convention(function, "interrupt")) {
			// Entered through the IDT with a pointer to what the CPU pushed (LLVM's x86_intrcc)
			return LLVM::cconv::CConv::X86_INTR;
		}
		if (text_of(function->calling_convention).empty() && system_v_on_windows(*generator.options)) {
			return LLVM::cconv::CConv::X86_64_SysV;
		}
		return LLVM::cconv::CConv::C;
	}

	// The function a freestanding program starts at (docs/compilation.md, Freestanding Programs).
	static bool is_freestanding_entry(Generator& generator, Declaration* declaration) {
		return declaration != nullptr && !generator.options->startup_code && declaration->generic == nullptr
			&& text_of(declaration->name) == generator.options->entry && declaration->package_path != nullptr
			&& *declaration->package_path == *generator.input_package;
	}

	/*
	 * Whether a function is called with a context: not #no_context, interrupt or entry functions
	 * (docs/control_flow.md, Functions Without a Context).
	 */
	static bool takes_context(Generator& generator, TypeInfoFunction const* function, Declaration* declaration) {
		(void)generator;
		(void)declaration;
		return !function->no_context && !has_convention(function, "entry") && !has_convention(function, "interrupt");
	}

	/*
	 * Whether a function is a callback from foreign code: .c, with a context, which a shim finds for
	 * it (docs/calling_convention.md, Calls to Foreign Code). Its symbol, and its value, are the
	 * shim's, which takes no context; Hemera code calling it by name calls its body directly.
	 */
	static bool is_callback(Generator& generator, TypeInfoFunction const* function) {
		return has_convention(function, "c") && takes_context(generator, function, nullptr);
	}

	// ---------------------------------------------------------------------------------------------
	// Entry functions (docs/calling_convention.md, Entry Functions): their generated code is module-level
	// assembly around the body, which is an ordinary function taking the frame

	static bool is_entry_function(TypeInfoFunction const* function) {
		return has_convention(function, "entry");
	}

	// The general registers, in the order they're pushed: the reverse of RegisterFrame's, which is lowest first.
	static constexpr std::string_view FRAME_REGISTERS[] = {
		"rax", "rbx", "rcx", "rdx", "rsi", "rdi", "rbp", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15",
	};

	// Where RegisterFrame's fields are, from its start (base/intrinsics/x86_64/x86_64.hsc).
	constexpr int FRAME_RCX = 96;
	constexpr int FRAME_R11 = 32;
	constexpr int FRAME_RIP = 136;
	constexpr int FRAME_CS = 144;
	constexpr int FRAME_RFLAGS = 152;
	constexpr int FRAME_SS = 168;
	// From the vector, where the stack pointer is once the general registers are popped, to the saved rsp
	constexpr int VECTOR_TO_RSP = 40;

	static std::string push_registers() {
		std::string text;
		for (std::string_view name : FRAME_REGISTERS) {
			text += std::format("\tpushq %{}\n", name);
		}
		return text;
	}

	static std::string pop_registers() {
		std::string text;
		for (size_t i = std::size(FRAME_REGISTERS); i > 0; --i) {
			text += std::format("\tpopq %{}\n", FRAME_REGISTERS[i - 1]);
		}
		return text;
	}

	/*
	 * The frame is complete: call the body with it. rbp is cleared so stack walks end here, and the
	 * direction flag, which user code may have set, is cleared as the body expects. So is the alignment
	 * check flag: an interrupt gate leaves it as user code had it, and with SMAP it would let the kernel
	 * reach user memory. Through the flags rather than clac, which CPUs without SMAP don't have.
	 */
	static std::string call_body(std::string_view body) {
		return std::format("\txorl %ebp, %ebp\n\tcld\n\tpushfq\n\tandq $-262145, (%rsp)\n\tpopfq\n\tmovq %rsp, %rdi\n\tcall {}\n",
			body);
	}

	/*
	 * A .entry function: entered from the stubs entry_points makes, with the vector and an error code
	 * pushed after what the CPU pushed. symbol decides swapgs from the interrupted cs; symbol.paranoid,
	 * for NMIs, double faults and machine checks, which can arrive between a swapgs and the iretq or
	 * sysretq after it, decides from IA32_GS_BASE: a kernel's is in the upper half.
	 */
	static std::string entry_assembly(std::string_view symbol, std::string_view body, bool returns) {
		auto leave = [&](std::string_view swap_back) {
			if (!returns) {
				return std::string("\tud2\n");
			}
			return std::format("{}{}\taddq $16, %rsp\n\tiretq\n", swap_back, pop_registers());
		};
		std::string text = std::format("\t.text\n\t.p2align 4\n{}:\n", symbol);
		text += push_registers();
		text += std::format("\ttestb $3, {}(%rsp)\n\tjz 1f\n\tswapgs\n1:\n", FRAME_CS);
		text += call_body(body);
		text += leave(std::format("\ttestb $3, {}(%rsp)\n\tjz 2f\n\tswapgs\n2:\n", FRAME_CS));
		text += std::format("\t.p2align 4\n{}.paranoid:\n", symbol);
		text += push_registers();
		// rbx, which the body preserves, remembers whether this swapped
		text += "\tmovl $0xc0000101, %ecx\n\trdmsr\n\txorl %ebx, %ebx\n\ttestl %edx, %edx\n\tjs 1f\n\tswapgs\n\tmovl $1, %ebx\n1:\n";
		text += call_body(body);
		text += leave("\ttestl %ebx, %ebx\n\tjz 2f\n\tswapgs\n2:\n");
		return text;
	}

	/*
	 * A .syscall_entry function: SYSCALL pushes nothing and leaves the user's stack, so this switches
	 * to the kernel stack in the x86_64.SyscallScratch the gs base points at, and builds the frame:
	 * rip from rcx, rflags from r11, and cs and ss as SYSRET will load them, from IA32_STAR.
	 */
	static std::string syscall_entry_assembly(std::string_view symbol, std::string_view body) {
		std::string text = std::format("\t.text\n\t.p2align 4\n{}:\n", symbol);
		text += "\tswapgs\n\tmovq %rsp, %gs:8\n\tmovq %gs:0, %rsp\n";
		// ss, rsp, rflags, cs, rip, the error code and the vector
		text += "\tpushq $0\n\tpushq %gs:8\n\tpushq %r11\n\tpushq $0\n\tpushq %rcx\n\tpushq $0\n\tpushq $-1\n";
		text += push_registers();
		text += "\tmovl $0xc0000081, %ecx\n\trdmsr\n\tshrl $16, %edx\n";
		text += std::format("\tleal 16(%rdx), %eax\n\torl $3, %eax\n\tmovq %rax, {}(%rsp)\n", FRAME_CS);
		text += std::format("\tleal 8(%rdx), %eax\n\torl $3, %eax\n\tmovq %rax, {}(%rsp)\n", FRAME_SS);
		text += call_body(body);
		text += "\tud2\n";
		return text;
	}

	// The vectors the CPU pushes an error code for (Intel SDM Vol. 3A §7.15).
	static bool pushes_error_code(int vector) {
		return vector == 8 || (vector >= 10 && vector <= 14) || vector == 17 || vector == 21 || vector == 29 || vector == 30;
	}

	// One stub per vector: an error code of 0 where the CPU pushes none, the vector, then the entry function.
	static std::string vector_stubs(std::string_view symbol) {
		std::string text = "\t.text\n";
		for (int vector = 0; vector < 256; ++vector) {
			const bool paranoid = vector == 2 || vector == 8 || vector == 18;
			text += std::format("{}.vector.{}:\n{}\tpushq ${}\n\tjmp {}{}\n", symbol, vector,
				pushes_error_code(vector) ? "" : "\tpushq $0\n", vector, symbol, paranoid ? ".paranoid" : "");
		}
		return text;
	}

	/*
	 * x86_64.return_to_user: the frame becomes the stack, its registers are popped, then swapgs and
	 * sysretq when rcx == rip, r11 == rflags and rip is canonical, otherwise swapgs and iretq.
	 */
	constexpr std::string_view RETURN_TO_USER_SYMBOL = "hemera.return_to_user";

	static std::string return_to_user_assembly() {
		std::string text = std::format("\t.text\n\t.p2align 4\n{}:\n\tmovq %rdi, %rsp\n", RETURN_TO_USER_SYMBOL);
		text += std::format("\tmovq {}(%rsp), %rax\n\tcmpq {}(%rsp), %rax\n\tjne 1f\n", FRAME_RIP, FRAME_RCX);
		text += std::format("\tmovq {}(%rsp), %rax\n\tcmpq {}(%rsp), %rax\n\tjne 1f\n", FRAME_RFLAGS, FRAME_R11);
		text += std::format("\tmovq {0}(%rsp), %rax\n\tshlq $16, %rax\n\tsarq $16, %rax\n\tcmpq {0}(%rsp), %rax\n\tjne 1f\n", FRAME_RIP);
		text += pop_registers();
		text += std::format("\tswapgs\n\tmovq {}(%rsp), %rsp\n\tsysretq\n1:\n", VECTOR_TO_RSP);
		text += pop_registers();
		text += "\taddq $16, %rsp\n\tswapgs\n\tiretq\n";
		return text;
	}

	/*
	 * On AArch64 (base/intrinsics/aarch64's RegisterFrame): x0 to x30, then sp_el0, elr, spsr, esr, far and
	 * the vector, in a 304-byte frame, which keeps the stack pointer 16-byte aligned.
	 */
	constexpr int AARCH64_FRAME_SIZE = 304;
	constexpr int AARCH64_FRAME_SP_EL0 = 248;
	constexpr int AARCH64_FRAME_ELR = 256;
	constexpr int AARCH64_FRAME_ESR = 272;
	constexpr int AARCH64_FRAME_VECTOR = 288;

	// x2 to x30 from the frame at base, which x0 and x1 aren't, being where they're loaded from last.
	static std::string aarch64_load_registers(std::string_view base) {
		std::string text;
		for (int i = 2; i < 30; i += 2) {
			text += std::format("\tldp x{}, x{}, [{}, #{}]\n", i, i + 1, base, i * 8);
		}
		return text + std::format("\tldr x30, [{}, #240]\n", base);
	}

	/*
	 * An AArch64 entry function's code, which a vector table entry jumps to with the frame's room made, x0
	 * and x1 in it, and the entry's index in x0: the rest of the frame, then the body with x29 cleared, so
	 * stack walks end here. A body that returns is followed by the frame put back and eret, with a barrier
	 * after it so nothing runs on past it speculatively.
	 */
	static std::string entry_assembly_aarch64(std::string_view symbol, std::string_view body, bool returns) {
		std::string text = std::format("\t.text\n\t.p2align 4\n{}:\n", symbol);
		for (int i = 2; i < 30; i += 2) {
			text += std::format("\tstp x{}, x{}, [sp, #{}]\n", i, i + 1, i * 8);
		}
		text += std::format("\tmrs x1, sp_el0\n\tstp x30, x1, [sp, #240]\n");
		text += std::format("\tmrs x1, elr_el1\n\tmrs x2, spsr_el1\n\tstp x1, x2, [sp, #{}]\n", AARCH64_FRAME_ELR);
		text += std::format("\tmrs x1, esr_el1\n\tmrs x2, far_el1\n\tstp x1, x2, [sp, #{}]\n", AARCH64_FRAME_ESR);
		text += std::format("\tstr x0, [sp, #{}]\n", AARCH64_FRAME_VECTOR);
		text += std::format("\tmov x29, xzr\n\tmov x30, xzr\n\tmov x0, sp\n\tbl {}\n", body);
		if (!returns) {
			return text + "\tbrk #1\n";
		}
		text += std::format("\tldp x1, x2, [sp, #{}]\n\tmsr elr_el1, x1\n\tmsr spsr_el1, x2\n", AARCH64_FRAME_ELR);
		text += std::format("\tldr x1, [sp, #{}]\n\tmsr sp_el0, x1\n", AARCH64_FRAME_SP_EL0);
		text += aarch64_load_registers("sp");
		text += std::format("\tldp x0, x1, [sp]\n\tadd sp, sp, #{}\n\teret\n\tdsb nsh\n\tisb\n", AARCH64_FRAME_SIZE);
		return text;
	}

	/*
	 * aarch64.vector_table(handler): 16 entries of 128 bytes, 2 KiB-aligned, each making the frame's room,
	 * saving x0 and x1, and jumping to handler's code with its index in x0.
	 */
	static std::string vector_table_aarch64(std::string_view symbol) {
		std::string text = std::format("\t.text\n\t.p2align 11\n{}.vector_table:\n", symbol);
		for (int index = 0; index < 16; ++index) {
			text += std::format("\t.p2align 7\n\tsub sp, sp, #{}\n\tstp x0, x1, [sp]\n\tmov x0, #{}\n\tb {}\n",
				AARCH64_FRAME_SIZE, index, symbol);
		}
		return text;
	}

	// aarch64.return_to_user(frame, kernel_stack): SP_EL1, selected, then every register, then eret.
	static std::string return_to_user_assembly_aarch64() {
		std::string text = std::format("\t.text\n\t.p2align 4\n{}:\n\tmsr spsel, #1\n\tmov sp, x1\n", RETURN_TO_USER_SYMBOL);
		text += std::format("\tldp x1, x2, [x0, #{}]\n\tmsr elr_el1, x1\n\tmsr spsr_el1, x2\n", AARCH64_FRAME_ELR);
		text += std::format("\tldr x1, [x0, #{}]\n\tmsr sp_el0, x1\n", AARCH64_FRAME_SP_EL0);
		text += aarch64_load_registers("x0");
		text += "\tldp x0, x1, [x0]\n\teret\n\tdsb nsh\n\tisb\n";
		return text;
	}

	// A function defined in the module's assembly, declared so code can take its address or call it.
	static LLVM::LLVMFuncOp assembly_function(Generator& generator, const std::string& symbol, LLVM::LLVMFunctionType type) {
		if (auto existing = generator.module.lookupSymbol<LLVM::LLVMFuncOp>(symbol)) {
			return existing;
		}
		mlir::OpBuilder::InsertionGuard guard(generator.builder);
		generator.builder.setInsertionPointToEnd(generator.module.getBody());
		LLVM::LLVMFuncOp function = LLVM::LLVMFuncOp::create(generator.builder, generator.loc, symbol, type);
		// Defined in this object, so it's reached directly rather than through the GOT
		function.setDsoLocal(true);
		// Written for System V's registers, which Hemera's functions use on Windows too
		if (system_v_on_windows(*generator.options)) {
			function.setCConv(LLVM::cconv::CConv::X86_64_SysV);
		}
		return function;
	}

	static LLVM::LLVMFunctionType no_arguments(Generator& generator) {
		return LLVM::LLVMFunctionType::get(LLVM::LLVMVoidType::get(generator.context), llvm::ArrayRef<mlir::Type>{});
	}

	/*
	 * x86_64.entry_points(handler): the stubs for handler's vectors, and a table of their addresses,
	 * made once per handler.
	 */
	static mlir::Value entry_points_of(Generator& generator, const std::string& symbol) {
		auto iter = generator.entry_tables.find(symbol);
		LLVM::GlobalOp table;
		if (iter != generator.entry_tables.end()) {
			table = iter->second;
		}
		else {
			generator.module_assembly.push_back(vector_stubs(symbol));
			mlir::Type u64 = integer_type(generator, 8);
			mlir::Type type = LLVM::LLVMArrayType::get(u64, 256);
			std::vector<LLVM::LLVMFuncOp> stubs;
			for (int vector = 0; vector < 256; ++vector) {
				stubs.push_back(assembly_function(generator, std::format("{}.vector.{}", symbol, vector), no_arguments(generator)));
			}
			mlir::OpBuilder::InsertionGuard guard(generator.builder);
			generator.builder.setInsertionPointToEnd(generator.module.getBody());
			table = LLVM::GlobalOp::create(generator.builder, generator.loc, type, true, LLVM::Linkage::Internal,
				std::format("{}.entry_points", symbol), mlir::Attribute(), 8);
			generator.builder.setInsertionPointToStart(generator.builder.createBlock(&table.getInitializerRegion()));
			mlir::Value addresses = LLVM::UndefOp::create(generator.builder, generator.loc, type);
			for (int vector = 0; vector < 256; ++vector) {
				mlir::Value address = LLVM::PtrToIntOp::create(generator.builder, generator.loc, u64,
					LLVM::AddressOfOp::create(generator.builder, generator.loc, stubs[static_cast<size_t>(vector)]));
				addresses = insert(generator, addresses, address, { static_cast<int64_t>(vector) });
			}
			LLVM::ReturnOp::create(generator.builder, generator.loc, addresses);
			generator.entry_tables[symbol] = table;
		}
		return LLVM::AddressOfOp::create(generator.builder, generator.loc, table);
	}

	/*
	 * An entry function: its body, an ordinary function taking the frame, and the generated code around it,
	 * whose address the declaration's own symbol is. Code can't call it, only take its address.
	 */
	static LLVM::LLVMFuncOp entry_function_for(Generator& generator, Declaration* declaration, TypeInfoFunction const* type) {
		const bool exported = has_name_directive(declaration, "#export");
		const std::string symbol = exported ? text_of(declaration->name) : symbol_for(generator, declaration);
		const std::string body_symbol = symbol + ".body";
		generator.symbols.insert(symbol);
		generator.symbols.insert(body_symbol);
		LLVM::LLVMFuncOp address = assembly_function(generator, symbol, no_arguments(generator));
		LLVM::LLVMFuncOp body;
		{
			mlir::OpBuilder::InsertionGuard guard(generator.builder);
			generator.builder.setInsertionPointToEnd(generator.module.getBody());
			body = LLVM::LLVMFuncOp::create(generator.builder, generator.loc, body_symbol, function_type(generator, type, false));
			if (type->never_returns) {
				body.setPassthroughAttr(generator.builder.getArrayAttr({ generator.builder.getStringAttr("noreturn") }));
			}
		}
		std::string text = exported ? std::format("\t.globl {}\n", symbol) : std::string();
		if (ArchType::aarch64 == generator.options->architecture) {
			if (has_convention(type, "syscall_entry")) {
				unsupported(generator, declaration->node,
					"#calling_convention(.syscall_entry) is x86-64's: on AArch64, svc reaches the .entry function in the vector table");
			}
			text += entry_assembly_aarch64(symbol, body_symbol, !type->never_returns);
		}
		else {
			text += has_convention(type, "syscall_entry") ? syscall_entry_assembly(symbol, body_symbol)
				: entry_assembly(symbol, body_symbol, !type->never_returns);
		}
		generator.module_assembly.push_back(text);
		generator.functions[declaration] = address;
		generator.entry_bodies[declaration] = body;
		generator.pending.push_back(declaration);
		return address;
	}

	// ---------------------------------------------------------------------------------------------
	// Growing the stack (docs/calling_convention.md, Growing the Stack: morestack)

	constexpr std::string_view MORESTACK_SYMBOL = "hemera.morestack";

	// A member's offset in one of base/runtime's structs.
	static bool runtime_offset(Generator& generator, std::string_view type_name, std::string_view member, size_t& offset);

	// One of base/runtime's integer constants, written as a literal, like STACK_GUARD :: 256.
	static bool runtime_integer(Generator& generator, std::string_view name, uint64_t& value);

	static LLVM::LLVMFuncOp function_for(Generator& generator, Declaration* declaration);

	// Where morestack finds what it changes in the carrier block and a segment's header.
	struct MorestackOffsets {
		size_t limit = 0;
		size_t segment = 0;
		size_t spare = 0;
		size_t cache = 0;
		size_t cache_count = 0;
		size_t current_fiber = 0;
		size_t scheduler_sp = 0;
		size_t native_stack_limit = 0;
		size_t native_sp = 0;
		size_t foreign_depth = 0;
		size_t segment_size = 0;
		size_t next_free = 0;
	};

	/*
	 * morestack: takes a segment for a function's body (the carrier's spare, or one from its cache),
	 * copies the stack parameters to it, and calls the body there; once it returns, switches back and
	 * keeps the segment as the carrier's spare. Until the body runs it only uses rax (the body),
	 * r10 and r11 (the sizes), and rbx and r12, which it saves; after, nothing a result is in.
	 *
	 * With no segment big enough, it allocates one with allocate (runtime.allocate_stack_segment) on
	 * the thread's native stack: below the scheduler on a fiber, below native_sp on a thread already
	 * on a segment, or where it is on a thread still on its native stack (or inside foreign code). It
	 * saves the arguments first, counts the allocating as foreign code, so nothing yields and foreign
	 * calls in it stay where they are, and traps without memory. allocate takes no context: the function being grown may not
	 * have one to give, since LLVM drops parameters an internal function doesn't use.
	 */
	static std::string morestack_assembly(const MorestackOffsets& o, uint64_t header_and_guard, const std::string& allocate, bool sse) {
		const size_t limit = o.limit, segment = o.segment, spare = o.spare, cache = o.cache, cache_count = o.cache_count;
		const size_t segment_size = o.segment_size, next_free = o.next_free;

		// Room for the frame, the parameters, the return address, alignment, and the guard
		const uint64_t extra = header_and_guard + 32;
		std::string text = std::format("\t.text\n\t.p2align 4\n{}:\n", MORESTACK_SYMBOL);
		text += "\tpushq %rbp\n\tmovq %rsp, %rbp\n";
		text += std::format("\tpushq {}(%r14)\n\tpushq {}(%r14)\n\tpushq %rbx\n\tpushq %r12\n", limit, segment);
		text += std::format("\tleaq {}(%r10,%r11), %rbx\n", extra);
		// The spare, if it's big enough, or the first cached segment, which must be
		text += std::format("\tmovq {}(%r14), %r12\n\ttestq %r12, %r12\n\tjz 1f\n", spare);
		text += std::format("\tmovl {}(%r12), %r10d\n\tcmpq %rbx, %r10\n\tjb 1f\n", segment_size);
		text += std::format("\tmovq $0, {}(%r14)\n\tjmp 3f\n", spare);
		text += std::format("1:\n\tmovq {}(%r14), %r12\n\ttestq %r12, %r12\n\tjz 9f\n", cache);
		text += std::format("\tmovl {}(%r12), %r10d\n\tcmpq %rbx, %r10\n\tjb 9f\n", segment_size);
		text += std::format("\tmovq {}(%r12), %r10\n\tmovq %r10, {}(%r14)\n\tdecl {}(%r14)\n", next_free, cache, cache_count);
		/*
		 * On it: the carrier's segment and limit, and the parameters at the top, 16-byte aligned. A
		 * thread leaving its native stack for the first time records where it was.
		 */
		text += std::format("3:\n\tcmpq $0, {}(%r14)\n\tjne 11f\n\tcmpq $0, {}(%r14)\n\tjne 11f\n", segment, o.current_fiber);
		text += std::format("\tmovq %rsp, {}(%r14)\n", o.native_sp);
		text += std::format("11:\n\tmovq %r12, {}(%r14)\n", segment);
		text += std::format("\tleaq {}(%r12), %r10\n\tmovq %r10, {}(%r14)\n", header_and_guard, limit);
		text += std::format("\tmovl {}(%r12), %ebx\n\taddq %r12, %rbx\n\tsubq %r11, %rbx\n\tandq $-16, %rbx\n", segment_size);
		text += "\txorl %r12d, %r12d\n2:\n\tcmpq %r11, %r12\n\tjae 4f\n";
		text += "\tmovq 32(%rbp,%r12), %r10\n\tmovq %r10, (%rbx,%r12)\n\taddq $8, %r12\n\tjmp 2b\n";
		text += "4:\n\tmovq %rbx, %r10\n\tmovq -24(%rbp), %rbx\n\tmovq -32(%rbp), %r12\n\tmovq %r10, %rsp\n";
		// Where a body on a new segment returns: stack walks leave this frame out, and .grow's too
		text += std::format("\tcallq *%rax\n{}:\n", MORESTACK_CONTINUE_SYMBOL);
		// Back: the segment just left is the spare now, and an older spare goes to the cache
		text += "\tleaq -16(%rbp), %rsp\n";
		text += std::format("\tmovq {}(%r14), %r10\n\tmovq {}(%r14), %r11\n\ttestq %r11, %r11\n\tjz 5f\n", segment, spare);
		text += std::format("\tmovq {}(%r14), %r9\n\tmovq %r9, {}(%r11)\n\tmovq %r11, {}(%r14)\n\tincl {}(%r14)\n",
			cache, next_free, cache, cache_count);
		text += std::format("5:\n\tmovq %r10, {}(%r14)\n", spare);
		text += std::format("\tpopq {}(%r14)\n\tpopq {}(%r14)\n\tpopq %rbp\n\tretq\n", segment, limit);
		// None big enough: one from allocate, on the native stack, with the arguments and the body kept there
		text += "9:\n\tmovq %rsp, %r12\n";
		text += std::format("\tcmpl $0, {}(%r14)\n\tjne 7f\n", o.foreign_depth);
		text += std::format("\tcmpq $0, {}(%r14)\n\tje 6f\n\tmovq {}(%r14), %rsp\n\tjmp 7f\n", o.current_fiber, o.scheduler_sp);
		text += std::format("6:\n\tcmpq $0, {}(%r14)\n\tje 7f\n\tmovq {}(%r14), %rsp\n", segment, o.native_sp);
		text += "7:\n\tandq $-16, %rsp\n";
		text += "\tpushq %rdi\n\tpushq %rsi\n\tpushq %rdx\n\tpushq %rcx\n\tpushq %r8\n\tpushq %r9\n\tpushq %rax\n\tpushq %r11\n";
		if (sse) {
			text += "\tsubq $128, %rsp\n";
			for (int i = 0; i < 8; ++i) {
				text += std::format("\tmovdqu %xmm{}, {}(%rsp)\n", i, i * 16);
			}
		}
		/*
		 * No limit while it allocates: a thread may already be at its native stack's limit, with the
		 * reserve below it (NATIVE_STACK_RESERVE) for code like this, which mustn't grow again
		 */
		text += std::format("\tpushq {}(%r14)\n\tpushq %r12\n\tmovq $0, {}(%r14)\n", limit, limit);
		text += std::format("\tincl {}(%r14)\n\tmovq %rbx, %rdi\n\tcallq {}\n\tmovq %rax, %r10\n\tdecl {}(%r14)\n",
			o.foreign_depth, allocate, o.foreign_depth);
		text += std::format("\tpopq %r12\n\tpopq {}(%r14)\n", limit);
		if (sse) {
			for (int i = 0; i < 8; ++i) {
				text += std::format("\tmovdqu {}(%rsp), %xmm{}\n", i * 16, i);
			}
			text += "\taddq $128, %rsp\n";
		}
		text += "\tpopq %r11\n\tpopq %rax\n\tpopq %r9\n\tpopq %r8\n\tpopq %rcx\n\tpopq %rdx\n\tpopq %rsi\n\tpopq %rdi\n";
		text += "\tmovq %r12, %rsp\n\ttestq %r10, %r10\n\tjz 8f\n\tmovq %r10, %r12\n\tjmp 3b\n";
		text += "8:\n\tud2\n";
		return text;
	}

	// A 64-bit constant into an AArch64 register, 16 bits at a time.
	static std::string aarch64_move(std::string_view reg, uint64_t value) {
		std::string text = std::format("\tmovz {}, #{}\n", reg, value & 0xffff);
		for (int shift = 16; shift < 64; shift += 16) {
			if ((value >> shift) & 0xffff) {
				text += std::format("\tmovk {}, #{}, lsl #{}\n", reg, (value >> shift) & 0xffff, shift);
			}
		}
		return text;
	}

	/*
	 * morestack on AArch64, the same as on x86-64. The function's check has built a frame record and
	 * passes the frame's size in x9, the stack parameters' size in x10 and the body in x11, and the
	 * parameters are just above that frame record. morestack's own frame keeps the carrier's limit
	 * and segment and x19 and x20, which it uses like rbx and r12; until the body runs it only changes
	 * x9 to x17 besides those, which no parameter is in, and after, nothing a result is in. Without
	 * memory it runs brk #1. With fp, it keeps q0 to q7 while allocating.
	 */
	static std::string morestack_assembly_aarch64(const MorestackOffsets& o, uint64_t header_and_guard, const std::string& allocate,
		bool fp) {

		const size_t limit = o.limit, segment = o.segment, spare = o.spare, cache = o.cache, cache_count = o.cache_count;
		const size_t segment_size = o.segment_size, next_free = o.next_free;
		const uint64_t extra = header_and_guard + 32;
		std::string text = std::format("\t.text\n\t.p2align 4\n{}:\n", MORESTACK_SYMBOL);
		text += "\tstp x29, x30, [sp, #-48]!\n\tmov x29, sp\n";
		text += std::format("\tldr x12, [x28, #{}]\n\tldr x13, [x28, #{}]\n\tstp x12, x13, [x29, #16]\n\tstp x19, x20, [x29, #32]\n",
			limit, segment);
		text += aarch64_move("x19", extra) + "\tadd x19, x19, x9\n\tadd x19, x19, x10\n";
		// The spare, if it's big enough, or the first cached segment, which must be
		text += std::format("\tldr x20, [x28, #{}]\n\tcbz x20, 1f\n", spare);
		text += std::format("\tldr w12, [x20, #{}]\n\tcmp x12, x19\n\tb.lo 1f\n", segment_size);
		text += std::format("\tstr xzr, [x28, #{}]\n\tb 3f\n", spare);
		text += std::format("1:\n\tldr x20, [x28, #{}]\n\tcbz x20, 9f\n", cache);
		text += std::format("\tldr w12, [x20, #{}]\n\tcmp x12, x19\n\tb.lo 9f\n", segment_size);
		text += std::format("\tldr x12, [x20, #{}]\n\tstr x12, [x28, #{}]\n", next_free, cache);
		text += std::format("\tldr w12, [x28, #{0}]\n\tsub w12, w12, #1\n\tstr w12, [x28, #{0}]\n", cache_count);
		// On it, as on x86-64; the parameters are copied from above the function's frame record
		text += std::format("3:\n\tldr x12, [x28, #{}]\n\tcbnz x12, 11f\n\tldr x12, [x28, #{}]\n\tcbnz x12, 11f\n", segment, o.current_fiber);
		text += std::format("\tmov x12, sp\n\tstr x12, [x28, #{}]\n", o.native_sp);
		text += std::format("11:\n\tstr x20, [x28, #{}]\n", segment);
		text += aarch64_move("x12", header_and_guard) + std::format("\tadd x12, x12, x20\n\tstr x12, [x28, #{}]\n", limit);
		text += std::format("\tldr w13, [x20, #{}]\n\tadd x13, x13, x20\n\tsub x13, x13, x10\n\tand x13, x13, #-16\n", segment_size);
		text += "\tldr x14, [x29]\n\tadd x14, x14, #16\n\tmov x15, xzr\n2:\n\tcmp x15, x10\n\tb.hs 4f\n";
		text += "\tldr x12, [x14, x15]\n\tstr x12, [x13, x15]\n\tadd x15, x15, #8\n\tb 2b\n";
		text += "4:\n\tldp x19, x20, [x29, #32]\n\tmov sp, x13\n";
		// Where a body on a new segment returns: stack walks leave this frame out, and the check's too
		text += std::format("\tblr x11\n{}:\n", MORESTACK_CONTINUE_SYMBOL);
		// Back: the segment just left is the spare now, and an older spare goes to the cache
		text += "\tmov sp, x29\n";
		text += std::format("\tldr x12, [x28, #{}]\n\tldr x13, [x28, #{}]\n\tcbz x13, 5f\n", segment, spare);
		text += std::format("\tldr x14, [x28, #{}]\n\tstr x14, [x13, #{}]\n\tstr x13, [x28, #{}]\n", cache, next_free, cache);
		text += std::format("\tldr w14, [x28, #{0}]\n\tadd w14, w14, #1\n\tstr w14, [x28, #{0}]\n", cache_count);
		text += std::format("5:\n\tstr x12, [x28, #{}]\n", spare);
		text += std::format("\tldp x12, x13, [x29, #16]\n\tstr x12, [x28, #{}]\n\tstr x13, [x28, #{}]\n", limit, segment);
		text += "\tldp x29, x30, [sp], #48\n\tret\n";
		// None big enough: one from allocate, on the native stack, with the arguments and the body kept there
		text += "9:\n\tmov x20, sp\n\tmov x12, sp\n";
		text += std::format("\tldr w13, [x28, #{}]\n\tcbnz w13, 7f\n", o.foreign_depth);
		text += std::format("\tldr x13, [x28, #{}]\n\tcbz x13, 6f\n\tldr x12, [x28, #{}]\n\tb 7f\n", o.current_fiber, o.scheduler_sp);
		text += std::format("6:\n\tldr x13, [x28, #{}]\n\tcbz x13, 7f\n\tldr x12, [x28, #{}]\n", segment, o.native_sp);
		text += "7:\n\tand sp, x12, #-16\n";
		text += "\tsub sp, sp, #96\n\tstp x0, x1, [sp]\n\tstp x2, x3, [sp, #16]\n\tstp x4, x5, [sp, #32]\n\tstp x6, x7, [sp, #48]\n";
		text += "\tstp x8, x10, [sp, #64]\n\tstr x11, [sp, #80]\n";
		if (fp) {
			text += "\tsub sp, sp, #128\n";
			for (int i = 0; i < 8; i += 2) {
				text += std::format("\tstp q{}, q{}, [sp, #{}]\n", i, i + 1, i * 16);
			}
		}
		// No limit while it allocates, as on x86-64
		text += std::format("\tldr x12, [x28, #{0}]\n\tstp x12, x20, [sp, #-16]!\n\tstr xzr, [x28, #{0}]\n", limit);
		text += std::format("\tldr w12, [x28, #{0}]\n\tadd w12, w12, #1\n\tstr w12, [x28, #{0}]\n", o.foreign_depth);
		text += std::format("\tmov x0, x19\n\tbl {}\n\tmov x12, x0\n", allocate);
		text += std::format("\tldr w13, [x28, #{0}]\n\tsub w13, w13, #1\n\tstr w13, [x28, #{0}]\n", o.foreign_depth);
		text += std::format("\tldp x13, x20, [sp], #16\n\tstr x13, [x28, #{}]\n", limit);
		if (fp) {
			for (int i = 0; i < 8; i += 2) {
				text += std::format("\tldp q{}, q{}, [sp, #{}]\n", i, i + 1, i * 16);
			}
			text += "\tadd sp, sp, #128\n";
		}
		text += "\tldp x0, x1, [sp]\n\tldp x2, x3, [sp, #16]\n\tldp x4, x5, [sp, #32]\n\tldp x6, x7, [sp, #48]\n";
		text += "\tldp x8, x10, [sp, #64]\n\tldr x11, [sp, #80]\n";
		text += "\tmov sp, x20\n\tcbz x12, 8f\n\tmov x20, x12\n\tb 3b\n";
		text += "8:\n\tbrk #1\n";
		return text;
	}

	/*
	 * Whether functions can call morestack: on x86-64 targets, with morestack made once. Reports why
	 * not, the first time.
	 */
	static bool morestack_ready(Generator& generator, Declaration* where) {
		if (generator.module.lookupSymbol<LLVM::LLVMFuncOp>(MORESTACK_SYMBOL)) {
			return true;
		}
		const bool aarch64 = ArchType::aarch64 == generator.options->architecture;
		if (ArchType::x86_64 != generator.options->architecture && !aarch64) {
			return false;
		}
		MorestackOffsets o;
		uint64_t guard = 0;
		Declaration* header = base_declaration_named(generator, "runtime", "StackSegment");
		Declaration* allocate = base_declaration_named(generator, "runtime", "allocate_stack_segment");
		const bool found = runtime_offset(generator, "CarrierBlock", "stack_limit", o.limit)
			&& runtime_offset(generator, "CarrierBlock", "stack_segment", o.segment)
			&& runtime_offset(generator, "CarrierBlock", "spare_segment", o.spare)
			&& runtime_offset(generator, "CarrierBlock", "segment_cache", o.cache)
			&& runtime_offset(generator, "CarrierBlock", "segment_cache_count", o.cache_count)
			&& runtime_offset(generator, "CarrierBlock", "current_fiber", o.current_fiber)
			&& runtime_offset(generator, "CarrierBlock", "scheduler_sp", o.scheduler_sp)
			&& runtime_offset(generator, "CarrierBlock", "native_stack_limit", o.native_stack_limit)
			&& runtime_offset(generator, "CarrierBlock", "native_sp", o.native_sp)
			&& runtime_offset(generator, "CarrierBlock", "foreign_depth", o.foreign_depth)
			&& runtime_offset(generator, "StackSegment", "size", o.segment_size)
			&& runtime_offset(generator, "StackSegment", "next_free", o.next_free)
			&& runtime_integer(generator, "STACK_GUARD", guard) && header != nullptr && header->type_value != nullptr
			&& allocate != nullptr;
		if (!found) {
			unsupported(generator, where != nullptr ? where->node : nullptr, "base/runtime's stack segments aren't what the compiler expects");
			return false;
		}
		// Declared first, so the allocating function, which grows like any other, finds morestack made
		assembly_function(generator, std::string(MORESTACK_SYMBOL), no_arguments(generator));
		assembly_function(generator, MORESTACK_CONTINUE_SYMBOL, no_arguments(generator));
		// Only the assembly calls it, which LLVM doesn't count as a use, so it's kept by being external
		LLVM::LLVMFuncOp allocate_function = function_for(generator, allocate);
		allocate_function.setLinkage(LLVM::Linkage::External);
		if (aarch64) {
			const bool fp = generator.options->cpu_features.find("-fp-armv8") == std::string::npos;
			generator.module_assembly.push_back(morestack_assembly_aarch64(o, guard + header->type_value->size,
				allocate_function.getSymName().str(), fp));
			return true;
		}
		const bool sse = generator.options->cpu_features.find("-sse") == std::string::npos;
		generator.module_assembly.push_back(morestack_assembly(o, guard + header->type_value->size,
			allocate_function.getSymName().str(), sse));
		return true;
	}

	static mlir::Value assembly(Generator& generator, mlir::Type result, const std::vector<mlir::Value>& operands,
		std::string_view text, std::string_view constraints);
	static LLVM::GlobalOp process_state_global(Generator& generator);
	static LLVM::GlobalOp thread_carrier_global(Generator& generator);
	static void emit_if(Generator& generator, mlir::Value condition, const std::function<bool()>& then,
		const std::function<bool()>& otherwise);

	/*
	 * A callback's shim (is_callback), which foreign code calls with the platform's C convention:
	 * keeps foreign code's carrier register, loads the thread's carrier block from where the runtime
	 * keeps it (runtime.callback_carrier, run with a temporary one that counts a foreign call, since
	 * it makes some itself), and calls the body with the context the foreign call it's inside saved,
	 * or HOSTED_CONTEXT on a thread Hemera didn't start. The body runs where the shim was called:
	 * the native stack, which a foreign call from a fiber moved to, with foreign_depth still counting
	 * it, so nothing yields. Windows only, so far.
	 */
	static const char* carrier_to_operand(const Generator& generator);
	static const char* operand_to_carrier(const Generator& generator);

	static void emit_callback_shim(Generator& generator, Declaration* declaration, LLVM::LLVMFuncOp shim, LLVM::LLVMFuncOp body,
		TypeInfoFunction const* type) {

		Declaration* carrier_declaration = base_declaration_named(generator, "runtime", "CarrierBlock");
		Declaration* context_declaration = base_declaration_named(generator, "runtime", "Context");
		Declaration* hosted = base_declaration_named(generator, "runtime", "HOSTED_CONTEXT");
		Declaration* find_carrier = base_declaration_named(generator, "runtime", "callback_carrier");
		size_t foreign_depth = 0;
		size_t foreign_context = 0;
		const ArchType architecture = generator.options->architecture;
		const bool linux_c = OSType::Linux == generator.options->os && generator.c_library
			&& (ArchType::x86_64 == architecture || ArchType::aarch64 == architecture);
		if (!(system_v_on_windows(*generator.options) || linux_c) || carrier_declaration == nullptr || context_declaration == nullptr || hosted == nullptr
			|| find_carrier == nullptr || carrier_declaration->type_value == nullptr || context_declaration->type_value == nullptr
			|| !runtime_offset(generator, "CarrierBlock", "foreign_depth", foreign_depth)
			|| !runtime_offset(generator, "CarrierBlock", "foreign_context", foreign_context)) {
			unsupported(generator, declaration->node,
				"callbacks from foreign code (.c functions with a context) are only made for Windows x64, and Linux linking C, so far");
			return;
		}
		TypeInfo* carrier_type = carrier_declaration->type_value;
		TypeInfo* context_type = context_declaration->type_value;
		mlir::OpBuilder& b = generator.builder;
		const mlir::Location l = generator.loc;
		mlir::OpBuilder::InsertionGuard guard(b);
		mlir::Block* entry = shim.addEntryBlock(b);
		b.setInsertionPointToEnd(entry);
		FunctionState state;
		state.entry = entry;
		FunctionState* outer = generator.state;
		generator.state = &state;
		mlir::Value callers = assembly(generator, integer_type(generator, 8), {}, carrier_to_operand(generator), "=r");
		mlir::Type pointer = pointer_type(generator);
		mlir::Value found = make_raw_slot(generator, pointer, 8);
		LLVM::StoreOp::create(b, l, zero_of(generator, pointer), found);
		/*
		 * A slot below 64 is also in the thread environment block, at gs:[0x1480 + 8 * slot] on x64: one
		 * load, which is null on a thread that has never run Hemera code
		 */
		LLVM::GlobalOp process = process_state_global(generator);
		size_t carrier_slot = 0;
		if (linux_c) {
			// Linux: the thread-local slot, null on a thread that has never run Hemera code
			LLVM::StoreOp::create(b, l, LLVM::LoadOp::create(b, l, pointer, LLVM::AddressOfOp::create(b, l, thread_carrier_global(generator))),
				found);
		}
		else if (process && runtime_offset(generator, "ProcessState", "carrier_slot", carrier_slot)) {
			mlir::Type i32 = integer_type(generator, 4);
			mlir::Value stored = LLVM::LoadOp::create(b, l, i32,
				offset_address(generator, LLVM::AddressOfOp::create(b, l, process), carrier_slot));
			mlir::Value index = LLVM::SubOp::create(b, l, stored, constant_int(generator, i32, 1));
			mlir::Value fixed = LLVM::ICmpOp::create(b, l, LLVM::ICmpPredicate::ult, index, constant_int(generator, i32, 64));
			emit_if(generator, fixed, [&]() {
				mlir::Value wide = LLVM::ZExtOp::create(b, l, integer_type(generator, 8), index);
				LLVM::StoreOp::create(b, l, assembly(generator, pointer, { wide }, "movq %gs:0x1480(,$1,8), $0", "=r,r"), found);
				return false;
			}, nullptr);
		}
		// Otherwise the runtime finds it, or makes it, with a temporary one loaded meanwhile
		mlir::Value missing = LLVM::ICmpOp::create(b, l, LLVM::ICmpPredicate::eq, LLVM::LoadOp::create(b, l, pointer, found),
			zero_of(generator, pointer));
		emit_if(generator, missing, [&]() {
			mlir::Value temporary = make_slot(generator, carrier_type);
			store_zero(generator, carrier_type, temporary);
			LLVM::StoreOp::create(b, l, constant_int(generator, integer_type(generator, 4), 1), offset_address(generator, temporary, foreign_depth));
			assembly(generator, mlir::Type(), { temporary }, operand_to_carrier(generator), "r,~{memory}");
			LLVM::StoreOp::create(b, l, LLVM::CallOp::create(b, l, function_for(generator, find_carrier), mlir::ValueRange{}).getResult(), found);
			return false;
		}, nullptr);
		mlir::Value carrier = LLVM::LoadOp::create(b, l, pointer, found);
		assembly(generator, mlir::Type(), { carrier }, operand_to_carrier(generator), "r,~{memory}");
		// The context: the foreign call's, or HOSTED_CONTEXT
		mlir::Value fallback = make_slot(generator, context_type);
		store(generator, emit_constant_value(generator, hosted, context_type, nullptr), fallback);
		mlir::Value saved = LLVM::LoadOp::create(b, l, pointer_type(generator), offset_address(generator, carrier, foreign_context));
		mlir::Value none = LLVM::ICmpOp::create(b, l, LLVM::ICmpPredicate::eq, saved, zero_of(generator, pointer_type(generator)));
		mlir::Value context = LLVM::SelectOp::create(b, l, none, fallback, saved);
		std::vector<mlir::Value> arguments{ context };
		for (mlir::BlockArgument argument : entry->getArguments()) {
			arguments.push_back(argument);
		}
		auto call = LLVM::CallOp::create(b, l, body, arguments);
		assembly(generator, mlir::Type(), { callers }, operand_to_carrier(generator), "r,~{memory}");
		if (type->output.empty()) {
			LLVM::ReturnOp::create(b, l, mlir::ValueRange{});
		}
		else {
			LLVM::ReturnOp::create(b, l, call.getResult());
		}
		generator.state = outer;
	}

	// ---------------------------------------------------------------------------------------------
	// Foreign functions (docs/calling_convention.md, Calls to Foreign Code)

	// Where the shims find what they change in the carrier block.
	struct ForeignOffsets {
		size_t stack_limit = 0;
		size_t foreign_depth = 0;
		size_t current_fiber = 0;
		size_t scheduler_sp = 0;
		size_t native_stack_limit = 0;
		size_t stack_segment = 0;
		size_t native_sp = 0;
	};

	static bool runtime_offset(Generator& generator, std::string_view type_name, std::string_view member, size_t& offset);

	/*
	 * Each stack argument's offset from the shim's frame pointer, where its caller put it, and from
	 * the stack pointer, where the foreign function finds it: for Windows x64, the arguments after the
	 * first four, above the 32-byte shadow space; for System V, the integers after the first six and
	 * the floating-point values after the first eight, in order.
	 */
	static std::vector<std::pair<int64_t, int64_t>> foreign_stack_arguments(TypeInfoFunction const* type, bool windows) {
		std::vector<std::pair<int64_t, int64_t>> result;
		const int64_t shadow = windows ? 32 : 0;
		size_t integers = 0;
		size_t floats = 0;
		for (size_t i = 0; i < type->input.size(); ++i) {
			bool in_register = false;
			if (windows) {
				in_register = i < 4;
			}
			else if (is_float(type->input[i].type)) {
				in_register = floats++ < 8;
			}
			else {
				in_register = integers++ < 6;
			}
			if (!in_register) {
				const int64_t slot = static_cast<int64_t>(result.size()) * 8;
				result.emplace_back(16 + shadow + slot, shadow + slot);
			}
		}
		return result;
	}

	/*
	 * A foreign function's shim, which Hemera code calls with the platform's C convention: counts the
	 * foreign call in the carrier block, moves to the thread's native stack if it's on a fiber (just
	 * below where the scheduler's stack pointer stopped, with the native stack's limit), copies the
	 * stack arguments there, and calls the function. Then it puts everything back. Its frame chains
	 * like any other, and until the call it only uses rax, besides rbx and r12, which it saves; after,
	 * nothing a result is in.
	 */
	static std::string foreign_shim_assembly(const std::string& shim, const std::string& symbol, const ForeignOffsets& o,
		const std::vector<std::pair<int64_t, int64_t>>& stack_arguments, bool windows) {

		const int64_t area = ((windows ? 32 : 0) + static_cast<int64_t>(stack_arguments.size()) * 8 + 15) & ~int64_t{ 15 };
		std::string text = std::format("\t.text\n\t.p2align 4\n{}:\n", shim);
		text += "\tpushq %rbp\n\tmovq %rsp, %rbp\n\tpushq %rbx\n\tpushq %r12\n";
		text += std::format("\tincl {}(%r14)\n\tmovq {}(%r14), %r12\n\tmovq %rsp, %rbx\n", o.foreign_depth, o.stack_limit);
		// Already on the native stack, inside other foreign code or morestack's allocating: stay there
		text += std::format("\tcmpl $1, {}(%r14)\n\tjne 1f\n", o.foreign_depth);
		/*
		 * On a fiber: below the scheduler, whose stack is the thread's own. On a thread on a segment:
		 * below where it left its own stack.
		 */
		text += std::format("\tcmpq $0, {}(%r14)\n\tje 2f\n\tmovq {}(%r14), %rsp\n\tjmp 3f\n", o.current_fiber, o.scheduler_sp);
		text += std::format("2:\n\tcmpq $0, {}(%r14)\n\tje 1f\n\tmovq {}(%r14), %rsp\n", o.stack_segment, o.native_sp);
		text += "3:\n\tandq $-16, %rsp\n";
		text += std::format("\tmovq {}(%r14), %rax\n\tmovq %rax, {}(%r14)\n", o.native_stack_limit, o.stack_limit);
		text += "1:\n";
		if (area > 0) {
			text += std::format("\tsubq ${}, %rsp\n", area);
		}
		for (const auto& [from, to] : stack_arguments) {
			text += std::format("\tmovq {}(%rbp), %rax\n\tmovq %rax, {}(%rsp)\n", from, to);
		}
		text += std::format("\tcallq {}\n", symbol);
		text += std::format("\tmovq %rbx, %rsp\n\tmovq %r12, {}(%r14)\n\tdecl {}(%r14)\n", o.stack_limit, o.foreign_depth);
		text += "\tpopq %r12\n\tpopq %rbx\n\tpopq %rbp\n\tretq\n";
		return text;
	}

	/*
	 * The same for AAPCS64: the integers after the first eight and the floating-point values after the
	 * first eight, each in an 8-byte slot, found above the shim's 32-byte frame.
	 */
	static std::vector<std::pair<int64_t, int64_t>> foreign_stack_arguments_aarch64(TypeInfoFunction const* type) {
		std::vector<std::pair<int64_t, int64_t>> result;
		size_t integers = 0;
		size_t floats = 0;
		for (const FunctionInput& input : type->input) {
			const bool in_register = is_float(input.type) ? floats++ < 8 : integers++ < 8;
			if (!in_register) {
				const int64_t slot = static_cast<int64_t>(result.size()) * 8;
				result.emplace_back(32 + slot, slot);
			}
		}
		return result;
	}

	/*
	 * The shim on AArch64, the same as on x86-64: x19 and x20 in place of rbx and r12, and x9 for
	 * everything else, which no parameter or result is in.
	 */
	static std::string foreign_shim_assembly_aarch64(const std::string& shim, const std::string& symbol, const ForeignOffsets& o,
		const std::vector<std::pair<int64_t, int64_t>>& stack_arguments) {

		const int64_t area = (static_cast<int64_t>(stack_arguments.size()) * 8 + 15) & ~int64_t{ 15 };
		std::string text = std::format("\t.text\n\t.p2align 4\n{}:\n", shim);
		text += "\tstp x29, x30, [sp, #-32]!\n\tmov x29, sp\n\tstp x19, x20, [sp, #16]\n";
		text += std::format("\tldr w9, [x28, #{0}]\n\tadd w9, w9, #1\n\tstr w9, [x28, #{0}]\n", o.foreign_depth);
		text += std::format("\tldr x20, [x28, #{}]\n\tmov x19, sp\n", o.stack_limit);
		// Already on the native stack, inside other foreign code or morestack's allocating: stay there
		text += "\tcmp w9, #1\n\tb.ne 1f\n";
		text += std::format("\tldr x9, [x28, #{}]\n\tcbz x9, 2f\n\tldr x9, [x28, #{}]\n\tb 3f\n", o.current_fiber, o.scheduler_sp);
		text += std::format("2:\n\tldr x9, [x28, #{}]\n\tcbz x9, 1f\n\tldr x9, [x28, #{}]\n", o.stack_segment, o.native_sp);
		text += "3:\n\tand sp, x9, #-16\n";
		text += std::format("\tldr x9, [x28, #{}]\n\tstr x9, [x28, #{}]\n", o.native_stack_limit, o.stack_limit);
		text += "1:\n";
		if (area > 0) {
			text += std::format("\tsub sp, sp, #{}\n", area);
		}
		for (const auto& [from, to] : stack_arguments) {
			text += std::format("\tldr x9, [x29, #{}]\n\tstr x9, [sp, #{}]\n", from, to);
		}
		text += std::format("\tbl {}\n", symbol);
		text += std::format("\tmov sp, x19\n\tstr x20, [x28, #{}]\n", o.stack_limit);
		text += std::format("\tldr w9, [x28, #{0}]\n\tsub w9, w9, #1\n\tstr w9, [x28, #{0}]\n", o.foreign_depth);
		text += "\tldp x19, x20, [sp, #16]\n\tldp x29, x30, [sp], #32\n\tret\n";
		return text;
	}

	/*
	 * A #foreign function: its shim, which is what Hemera code calls, made once, and its library,
	 * for the linker. For now on x86-64 and AArch64, with parameters and a result that each fit a register.
	 */
	static LLVM::LLVMFuncOp foreign_function_for(Generator& generator, Declaration* declaration, TypeInfoFunction const* type) {
		const std::string symbol = text_of(declaration->link_name);
		const std::string shim = std::format("hemera.foreign.{}", symbol);
		/*
		 * base's C library functions on Linux, like pthread_create, are only called when the program
		 * links C (intrinsics.uses_c_library); otherwise the shim is never run, and stops if it is
		 */
		if (OSType::Linux == generator.options->os && !generator.c_library && is_base_package(declaration->package_path)) {
			if (!generator.module.lookupSymbol<LLVM::LLVMFuncOp>(shim)) {
				const char* stop = ArchType::aarch64 == generator.options->architecture ? "brk #1" : "ud2";
				generator.module_assembly.push_back(std::format("\t.text\n\t.p2align 4\n{}:\n\t{}\n", shim, stop));
			}
			LLVM::LLVMFuncOp unused = assembly_function(generator, shim, function_type(generator, type, false));
			unused.setCConv(LLVM::cconv::CConv::C);
			generator.functions[declaration] = unused;
			return unused;
		}
		generator.libraries.insert(text_of(declaration->foreign_library));
		ast::Node* where = declaration->node;
		const bool aarch64 = ArchType::aarch64 == generator.options->architecture;
		bool fits = (ArchType::x86_64 == generator.options->architecture || aarch64) && type->output.size() <= 1;
		for (const FunctionInput& input : type->input) {
			fits = fits && !input.is_varargs && input.type != nullptr && input.type->size <= 8
				&& (is_float(input.type) || is_variant(input.type, TypeInfoVariant::INTEGER) || is_variant(input.type, TypeInfoVariant::POINTER)
					|| is_variant(input.type, TypeInfoVariant::BOOLEAN) || is_variant(input.type, TypeInfoVariant::ENUM));
		}
		if (!fits) {
			unsupported(generator, where, "a #foreign function can only take and give values that fit a register, on x86-64 and AArch64, so far");
		}
		ForeignOffsets offsets;
		if (!generator.module.lookupSymbol<LLVM::LLVMFuncOp>(shim)) {
			const bool found = runtime_offset(generator, "CarrierBlock", "stack_limit", offsets.stack_limit)
				&& runtime_offset(generator, "CarrierBlock", "foreign_depth", offsets.foreign_depth)
				&& runtime_offset(generator, "CarrierBlock", "current_fiber", offsets.current_fiber)
				&& runtime_offset(generator, "CarrierBlock", "scheduler_sp", offsets.scheduler_sp)
				&& runtime_offset(generator, "CarrierBlock", "native_stack_limit", offsets.native_stack_limit)
				&& runtime_offset(generator, "CarrierBlock", "stack_segment", offsets.stack_segment)
				&& runtime_offset(generator, "CarrierBlock", "native_sp", offsets.native_sp);
			if (!found) {
				unsupported(generator, where, "base/runtime's carrier block isn't what the compiler expects");
			}
			else if (fits && aarch64) {
				generator.module_assembly.push_back(foreign_shim_assembly_aarch64(shim, symbol, offsets, foreign_stack_arguments_aarch64(type)));
			}
			else if (fits) {
				const bool windows = OSType::Win32 == generator.options->os;
				generator.module_assembly.push_back(foreign_shim_assembly(shim, symbol, offsets,
					foreign_stack_arguments(type, windows), windows));
			}
		}
		LLVM::LLVMFuncOp function = assembly_function(generator, shim, function_type(generator, type, false));
		function.setCConv(LLVM::cconv::CConv::C);
		generator.functions[declaration] = function;
		return function;
	}

	static void emit_callback_shim(Generator& generator, Declaration* declaration, LLVM::LLVMFuncOp shim, LLVM::LLVMFuncOp body,
		TypeInfoFunction const* type);

	static mlir::Value zero_of(Generator& generator, mlir::Type type);

	/*
	 * Each thread's carrier block, for callbacks from foreign code on Linux with the C library, in
	 * ELF thread-local storage, which libc sets up for every thread (intrinsics.set_thread_carrier).
	 */
	static LLVM::GlobalOp thread_carrier_global(Generator& generator) {
		constexpr const char* THREAD_CARRIER_SYMBOL = "hemera.thread_carrier";
		LLVM::GlobalOp carrier = generator.module.lookupSymbol<LLVM::GlobalOp>(THREAD_CARRIER_SYMBOL);
		if (!carrier) {
			mlir::OpBuilder::InsertionGuard guard(generator.builder);
			generator.builder.setInsertionPointToEnd(generator.module.getBody());
			mlir::Type pointer = LLVM::LLVMPointerType::get(generator.context);
			carrier = LLVM::GlobalOp::create(generator.builder, generator.loc, pointer, false, LLVM::Linkage::Internal,
				THREAD_CARRIER_SYMBOL, mlir::Attribute(), 8, 0, true, true);
			generator.builder.setInsertionPointToStart(generator.builder.createBlock(&carrier.getInitializerRegion()));
			LLVM::ReturnOp::create(generator.builder, generator.loc, zero_of(generator, pointer));
		}
		return carrier;
	}

	// intrinsics.process_state's global: base/runtime's ProcessState, zeroed, made the first time. Null without one.
	static LLVM::GlobalOp process_state_global(Generator& generator) {
		constexpr const char* PROCESS_STATE_SYMBOL = "hemera.process_state";
		LLVM::GlobalOp state = generator.module.lookupSymbol<LLVM::GlobalOp>(PROCESS_STATE_SYMBOL);
		Declaration* state_declaration = base_declaration_named(generator, "runtime", "ProcessState");
		if (!state && state_declaration != nullptr && state_declaration->type_value != nullptr) {
			TypeInfo* state_type = state_declaration->type_value;
			mlir::OpBuilder::InsertionGuard guard(generator.builder);
			generator.builder.setInsertionPointToEnd(generator.module.getBody());
			mlir::Type type = llvm_type(generator, state_type);
			state = LLVM::GlobalOp::create(generator.builder, generator.loc, type, false, LLVM::Linkage::Internal, PROCESS_STATE_SYMBOL,
				mlir::Attribute(), std::max<size_t>(state_type->alignment, 1));
			generator.builder.setInsertionPointToStart(generator.builder.createBlock(&state.getInitializerRegion()));
			LLVM::ReturnOp::create(generator.builder, generator.loc, zero_of(generator, type));
		}
		return state;
	}

	/*
	 * The function a declaration is, declared now and generated later. Exported functions and the
	 * freestanding entry keep their own names, for the linker and other languages.
	 */
	static LLVM::LLVMFuncOp function_for(Generator& generator, Declaration* declaration) {
		auto iter = generator.functions.find(declaration);
		if (iter != generator.functions.end()) {
			return iter->second;
		}
		auto type = static_cast<TypeInfoFunction const*>(declaration->value_type);
		if (is_entry_function(type)) {
			return entry_function_for(generator, declaration, type);
		}
		if (declaration->foreign_library != nullptr) {
			return foreign_function_for(generator, declaration, type);
		}
		const bool exported = has_name_directive(declaration, "#export") || is_freestanding_entry(generator, declaration);
		mlir::OpBuilder::InsertionGuard guard(generator.builder);
		generator.builder.setInsertionPointToEnd(generator.module.getBody());
		std::string name = exported ? text_of(declaration->name) : symbol_for(generator, declaration);
		if (exported) {
			generator.symbols.insert(name);
		}
		const bool callback = is_callback(generator, type);
		/*
		 * Compile-time code: a function an earlier run compiled is called there, only declared here; any other
		 * is defined for later runs to call too
		 */
		const bool shared = generator.links.library != nullptr && !exported && !callback;
		if (shared && compile_time_library_has(*generator.links.library, name)) {
			LLVM::LLVMFuncOp compiled = LLVM::LLVMFuncOp::create(generator.builder, generator.loc, name,
				function_type(generator, type, takes_context(generator, type, declaration)), LLVM::Linkage::External);
			compiled.setCConv(convention_of(generator, type));
			generator.links.uses.push_back(name);
			generator.functions[declaration] = compiled;
			return compiled;
		}
		if (shared) {
			generator.links.defines.push_back(name);
		}
		LLVM::LLVMFuncOp function = LLVM::LLVMFuncOp::create(generator.builder, generator.loc, name,
			function_type(generator, type, takes_context(generator, type, declaration) && !callback),
			exported || shared ? LLVM::Linkage::External : LLVM::Linkage::Internal);
		LLVM::LLVMFuncOp shim;
		if (callback) {
			// The function is its body, generated like any other; the shim, called by foreign code, has its name
			shim = function;
			function = LLVM::LLVMFuncOp::create(generator.builder, generator.loc, name + ".body",
				function_type(generator, type, true), LLVM::Linkage::Internal);
			function.setCConv(system_v_on_windows(*generator.options) ? LLVM::cconv::CConv::X86_64_SysV : LLVM::cconv::CConv::C);
		}
		std::vector<mlir::Attribute> attributes;
		if (type->never_returns) {
			attributes.push_back(generator.builder.getStringAttr("noreturn"));
		}
		const bool grows = TargetStackCheck::Morestack == generator.options->stack_check && morestack_ready(generator, declaration);
		if ((TargetStackCheck::Trap == generator.options->stack_check || grows) && takes_context(generator, type, declaration)) {
			/*
			 * The prologue compares the stack pointer with the carrier block's stack_limit, at [r14] or
			 * [x28], and traps or grows without room (apps/compiler/third-party/patches/llvm). Functions
			 * without a context don't have a carrier yet.
			 */
			auto pair = [&](std::string_view key, std::string_view text) {
				return generator.builder.getArrayAttr({ generator.builder.getStringAttr(key), generator.builder.getStringAttr(text) });
			};
			attributes.push_back(generator.builder.getStringAttr("split-stack"));
			attributes.push_back(pair("split-stack-limit-register", ArchType::aarch64 == generator.options->architecture ? "x28" : "r14"));
			attributes.push_back(pair("split-stack-limit-offset", "0"));
			if (grows) {
				attributes.push_back(pair("split-stack-morestack", MORESTACK_SYMBOL));
			}
			else {
				attributes.push_back(pair("split-stack-failure", "trap"));
			}
		}
		if (!attributes.empty()) {
			function.setPassthroughAttr(generator.builder.getArrayAttr(attributes));
		}
		// LLVM takes a function's features instead of the target's, so they're the target's and its own
		if (declaration->target_features != nullptr) {
			const std::string base_features = target_features(*generator.options);
			function.setTargetFeaturesAttr(LLVM::TargetFeaturesAttr::get(generator.context,
				base_features.empty() ? text_of(declaration->target_features)
				: std::format("{},{}", base_features, text_of(declaration->target_features))));
		}
		if (!callback) {
			function.setCConv(convention_of(generator, type));
		}
		if (has_convention(type, "interrupt")) {
			if (!type->input.empty() && is_variant(type->input[0].type, TypeInfoVariant::POINTER)) {
				TypeInfo* frame = static_cast<TypeInfoPointer const*>(base(type->input[0].type))->base_type;
				function.setArgAttr(0, LLVM::LLVMDialect::getByValAttrName(), mlir::TypeAttr::get(llvm_type(generator, frame)));
			}
		}
		if (callback) {
			shim.setCConv(LLVM::cconv::CConv::C);
			generator.functions[declaration] = shim;
			generator.entry_bodies[declaration] = function;
			generator.pending.push_back(declaration);
			emit_callback_shim(generator, declaration, shim, function, type);
			return shim;
		}
		generator.functions[declaration] = function;
		generator.pending.push_back(declaration);
		return function;
	}

	// A string's bytes as a global, the same one for the same text.
	static mlir::Value string_bytes(Generator& generator, const std::string& text) {
		auto iter = generator.strings.find(text);
		LLVM::GlobalOp global;
		if (iter != generator.strings.end()) {
			global = iter->second;
		}
		else {
			mlir::OpBuilder::InsertionGuard guard(generator.builder);
			generator.builder.setInsertionPointToEnd(generator.module.getBody());
			// With a null after it, so it works as a cstring too
			std::string with_null = text;
			with_null.push_back('\0');
			global = LLVM::GlobalOp::create(generator.builder, generator.loc, bytes_type(generator, with_null.size()), true,
				LLVM::Linkage::Private, std::format("string.{}", generator.strings.size()),
				generator.builder.getStringAttr(with_null), 1);
			generator.strings[text] = global;
		}
		return LLVM::AddressOfOp::create(generator.builder, generator.loc, global);
	}

	// A literal's text without its quotes, with escapes like \n replaced.
	static std::string literal_text(InternedString literal) {
		std::string text = text_of(literal);
		if (text.size() >= 2 && (text.front() == '"' || text.front() == '\'')) {
			text = text.substr(1, text.size() - 2);
		}
		std::string result;
		for (size_t i = 0; i < text.size(); ++i) {
			if (text[i] != '\\' || i + 1 >= text.size()) {
				result += text[i];
				continue;
			}
			const char escaped = text[++i];
			result += escaped == 'n' ? '\n' : escaped == 't' ? '\t' : escaped == 'r' ? '\r' : escaped == '0' ? '\0' : escaped;
		}
		return result;
	}

	static mlir::Value string_value(Generator& generator, const std::string& text, TypeInfo const* type) {
		mlir::Value data = string_bytes(generator, text);
		if (is_raw_string(type)) {
			return data;
		}
		return make_view(generator, constant_int(generator, usize_type(generator), static_cast<int64_t>(text.size())), data);
	}

	static uint64_t parse_integer(std::string text) {
		std::erase(text, '_');
		int radix = 10;
		if (text.starts_with("0x")) {
			radix = 16;
		}
		else if (text.starts_with("0o")) {
			radix = 8;
		}
		else if (text.starts_with("0b")) {
			radix = 2;
		}
		return std::stoull(radix == 10 ? text : text.substr(2), nullptr, radix);
	}

	static size_t variant_named(TypeInfo const* type, std::string_view name) {
		auto union_type = static_cast<TypeInfoUnion const*>(base(type));
		for (size_t i = 0; i < union_type->variants.size(); ++i) {
			if (std::string_view(*union_type->variants[i].name) == name) {
				return i;
			}
		}
		return union_type->variants.size();
	}

	// ---------------------------------------------------------------------------------------------
	// Conversions

	static mlir::Value convert(Generator& generator, mlir::Value v, TypeInfo const* from, TypeInfo const* to);

	// A union value of a variant, with its values.
	static mlir::Value make_variant(Generator& generator, TypeInfo* type, size_t variant, const std::vector<mlir::Value>& values,
		const std::vector<TypeInfo*>& value_types) {

		auto union_type = static_cast<TypeInfoUnion const*>(base(type));
		if (union_type->null_is_none) {
			// Some is the pointer itself, None is null
			if (variant != 0 || values.empty()) {
				return zero_of(generator, pointer_type(generator));
			}
			return convert(generator, values[0], value_types[0], union_type->variants[0].types[0]);
		}
		mlir::Value tag = constant_int(generator, llvm_type(generator, union_type->tag_type), static_cast<int64_t>(variant));
		if (values.empty()) {
			// Only the tag, which works in a constant too
			return insert(generator, zero_of(generator, llvm_type(generator, type)), tag, { 0 });
		}
		if (!in_function(generator)) {
			/*
			 * A constant has no memory to build it in: a packed struct laid out like this variant
			 * instead, the tag, the values at their offsets, and zeros between, which a global takes
			 * as its type (global_for), and which reads the same through the union's
			 */
			const UnionVariant& chosen = union_type->variants[variant];
			std::vector<mlir::Type> fields{ tag.getType() };
			std::vector<mlir::Value> parts{ tag };
			size_t at = union_type->tag_type->size;
			mlir::Type byte = integer_type(generator, 1);
			auto pad_to = [&](size_t offset) {
				if (offset > at) {
					mlir::Type padding = LLVM::LLVMArrayType::get(byte, offset - at);
					fields.push_back(padding);
					parts.push_back(zero_of(generator, padding));
					at = offset;
				}
			};
			for (size_t i = 0; i < values.size() && i < chosen.offsets.size(); ++i) {
				pad_to(chosen.offsets[i]);
				mlir::Value part = convert(generator, values[i], value_types[i], chosen.types[i]);
				fields.push_back(part.getType());
				parts.push_back(part);
				at = chosen.offsets[i] + chosen.types[i]->size;
			}
			pad_to(type->size);
			mlir::Type shaped = LLVM::LLVMStructType::getLiteral(generator.context, fields, true);
			mlir::Value result = zero_of(generator, shaped);
			for (size_t i = 0; i < parts.size(); ++i) {
				result = insert(generator, result, parts[i], { static_cast<int64_t>(i) });
			}
			return result;
		}
		mlir::Value slot = make_slot(generator, type);
		store_zero(generator, type, slot);
		store(generator, tag, slot);
		const UnionVariant& chosen = union_type->variants[variant];
		for (size_t i = 0; i < values.size() && i < chosen.offsets.size(); ++i) {
			store(generator, convert(generator, values[i], value_types[i], chosen.types[i]),
				offset_address(generator, slot, chosen.offsets[i]));
		}
		return load(generator, type, slot);
	}

	// A literal as a constant of type.
	static mlir::Value emit_literal(Generator& generator, ast::Node* node, TypeInfo* type) {
		const TokenType token = node->value.type;
		mlir::Type target = llvm_type(generator, type);
		if (TokenType::LITERAL_STRING == token) {
			return string_value(generator, ast::string_value(node), type);
		}
		if (TokenType::LITERAL_CHAR == token) {
			const std::string text = literal_text(node->value.value);
			return constant_int(generator, target, text.empty() ? 0 : static_cast<unsigned char>(text[0]));
		}
		if (TokenType::KEYWORD_TRUE == token || TokenType::KEYWORD_FALSE == token) {
			return constant_int(generator, target, TokenType::KEYWORD_TRUE == token ? 1 : 0);
		}
		if (TokenType::KEYWORD_NULL == token) {
			if (is_variant(type, TypeInfoVariant::UNION)) {
				// An optional's None
				return make_variant(generator, type, variant_named(type, "None"), {}, {});
			}
			return zero_of(generator, target);
		}
		if (TokenType::LITERAL_FLOATING_POINT == token || is_float(type)) {
			std::string text = text_of(node->value.value);
			std::erase(text, '_');
			llvm::APFloat number(std::stod(text));
			bool lost = false;
			number.convert(llvm::cast<mlir::FloatType>(target).getFloatSemantics(), llvm::APFloat::rmNearestTiesToEven, &lost);
			return LLVM::ConstantOp::create(generator.builder, generator.loc, target, number);
		}
		return constant_int(generator, target, static_cast<int64_t>(parse_integer(text_of(node->value.value))));
	}

	// An untyped integer whose value the checker worked out, as a constant of type.
	static mlir::Value known_integer(Generator& generator, const CheckedNode& known, TypeInfo* type) {
		mlir::Type target = llvm_type(generator, type);
		if (is_float(type)) {
			llvm::APFloat number(static_cast<double>(known.integer_magnitude) * (known.integer_negative ? -1.0 : 1.0));
			bool lost = false;
			number.convert(llvm::cast<mlir::FloatType>(target).getFloatSemantics(), llvm::APFloat::rmNearestTiesToEven, &lost);
			return LLVM::ConstantOp::create(generator.builder, generator.loc, target, number);
		}
		const unsigned bits = llvm::cast<mlir::IntegerType>(target).getWidth();
		llvm::APInt number(std::max(bits, 64u), known.integer_magnitude);
		if (known.integer_negative) {
			number.negate();
		}
		return LLVM::ConstantOp::create(generator.builder, generator.loc, target,
			generator.builder.getIntegerAttr(target, number.trunc(bits)));
	}

	// A union's tag, from where it is.
	static mlir::Value union_tag(Generator& generator, mlir::Value address, TypeInfo const* type) {
		auto union_type = static_cast<TypeInfoUnion const*>(base(type));
		if (union_type->null_is_none) {
			// Some (0) unless the pointer is null, then None (1)
			mlir::Value pointer = LLVM::LoadOp::create(generator.builder, generator.loc, pointer_type(generator), address);
			mlir::Value is_null = LLVM::ICmpOp::create(generator.builder, generator.loc, LLVM::ICmpPredicate::eq, pointer,
				zero_of(generator, pointer_type(generator)));
			return LLVM::ZExtOp::create(generator.builder, generator.loc, llvm_type(generator, union_type->tag_type), is_null);
		}
		return load(generator, union_type->tag_type, address);
	}

	// A value converted to a type it implicitly converts to (docs/types.md, Implicit Casting), or cast to.
	static mlir::Value convert(Generator& generator, mlir::Value v, TypeInfo const* from, TypeInfo const* to) {
		if (from == nullptr || to == nullptr || !v) {
			return v;
		}
		TypeInfo const* source = base(from);
		TypeInfo const* destination = base(to);
		if (source == destination) {
			return v;
		}
		/*
		 * docs/types.md, Endian-Specific Types: a value of one is its bytes in its order, as an integer, swapped and
		 * reinterpreted to and from its native type, through which it converts to and from any other number
		 */
		const auto numeric = [](TypeInfo const* type) {
			return TypeInfoVariant::INTEGER == type->variant || TypeInfoVariant::FLOAT == type->variant;
		};
		if (TypeInfo* native = native_of(const_cast<TypeInfo*>(from)); native != from && (numeric(destination)
			|| TypeInfoVariant::ANY == destination->variant)) {
			mlir::Value bits = is_byte_swapped(from) ? static_cast<mlir::Value>(LLVM::ByteSwapOp::create(generator.builder, generator.loc, v)) : v;
			if (is_float(native)) {
				bits = LLVM::BitcastOp::create(generator.builder, generator.loc, llvm_type(generator, native), bits);
			}
			return convert(generator, bits, native, to);
		}
		if (TypeInfo* native = native_of(const_cast<TypeInfo*>(to)); native != to && numeric(source)) {
			mlir::Value bits = convert(generator, v, from, native);
			if (is_float(native)) {
				bits = LLVM::BitcastOp::create(generator.builder, generator.loc, llvm_type(generator, to), bits);
			}
			return is_byte_swapped(to) ? static_cast<mlir::Value>(LLVM::ByteSwapOp::create(generator.builder, generator.loc, bits)) : bits;
		}
		mlir::Type target = llvm_type(generator, to);
		// Into an any: a pointer to a copy of it, and its type
		if (TypeInfoVariant::ANY == destination->variant) {
			mlir::Value slot = make_slot(generator, from);
			store(generator, v, slot);
			mlir::Value result = LLVM::UndefOp::create(generator.builder, generator.loc, target);
			result = insert(generator, result, slot, { 0 });
			return insert(generator, result, type_descriptor(generator, from), { 1 });
		}
		// A static array as a view of its elements, or a dynamic array's
		if (TypeInfoVariant::ARRAY == source->variant && TypeInfoVariant::ARRAY == destination->variant
			&& ArrayType::VIEW == static_cast<TypeInfoArray const*>(destination)->array_type) {
			auto array = static_cast<TypeInfoArray const*>(source);
			if (ArrayType::STATIC == array->array_type) {
				mlir::Value slot = make_slot(generator, from);
				store(generator, v, slot);
				return make_view(generator, constant_int(generator, usize_type(generator), static_cast<int64_t>(array->count)), slot);
			}
			return make_view(generator, extract(generator, v, 0), extract(generator, v, 1));
		}
		/*
		 * A value as an optional or result holding it: Some or Ok, the first variant. The value may
		 * be a union itself, like a ConsoleError as a ConsoleError?
		 */
		TypeInfo const* held = TypeInfoVariant::UNION == destination->variant ? held_type(destination) : nullptr;
		if (TypeInfoVariant::UNION == destination->variant
			&& (TypeInfoVariant::UNION != source->variant || (held != nullptr && base(held) == source))) {
			return make_variant(generator, const_cast<TypeInfo*>(to), 0, { v }, { const_cast<TypeInfo*>(from) });
		}
		// Through a using, the struct it includes
		if (TypeInfoVariant::STRUCT == source->variant && TypeInfoVariant::STRUCT == destination->variant) {
			for (const StructMember& member : static_cast<TypeInfoStruct const*>(source)->members) {
				if (member.is_using && base(member.member_type) == destination && in_function(generator)) {
					mlir::Value slot = make_slot(generator, from);
					store(generator, v, slot);
					return load(generator, to, offset_address(generator, slot, member.offset));
				}
			}
			return v;
		}
		mlir::Type from_type = v.getType();
		if (from_type == target) {
			return v;
		}
		mlir::OpBuilder& b = generator.builder;
		const mlir::Location l = generator.loc;
		if (llvm::isa<mlir::IntegerType>(from_type) && llvm::isa<mlir::IntegerType>(target)) {
			const unsigned from_width = from_type.getIntOrFloatBitWidth();
			const unsigned to_width = target.getIntOrFloatBitWidth();
			if (from_width == 1) {
				return LLVM::ZExtOp::create(b, l, target, v);
			}
			if (to_width == 1) {
				return LLVM::ICmpOp::create(b, l, LLVM::ICmpPredicate::ne, v, constant_int(generator, from_type, 0));
			}
			if (to_width > from_width) {
				return is_signed(from) ? static_cast<mlir::Value>(LLVM::SExtOp::create(b, l, target, v))
					: static_cast<mlir::Value>(LLVM::ZExtOp::create(b, l, target, v));
			}
			return LLVM::TruncOp::create(b, l, target, v);
		}
		if (llvm::isa<mlir::FloatType>(from_type) && llvm::isa<mlir::FloatType>(target)) {
			return from_type.getIntOrFloatBitWidth() < target.getIntOrFloatBitWidth()
				? static_cast<mlir::Value>(LLVM::FPExtOp::create(b, l, target, v))
				: static_cast<mlir::Value>(LLVM::FPTruncOp::create(b, l, target, v));
		}
		if (llvm::isa<mlir::IntegerType>(from_type) && llvm::isa<mlir::FloatType>(target)) {
			return is_signed(from) ? static_cast<mlir::Value>(LLVM::SIToFPOp::create(b, l, target, v))
				: static_cast<mlir::Value>(LLVM::UIToFPOp::create(b, l, target, v));
		}
		if (llvm::isa<mlir::FloatType>(from_type) && llvm::isa<mlir::IntegerType>(target)) {
			return is_signed(to) ? static_cast<mlir::Value>(LLVM::FPToSIOp::create(b, l, target, v))
				: static_cast<mlir::Value>(LLVM::FPToUIOp::create(b, l, target, v));
		}
		if (llvm::isa<LLVM::LLVMPointerType>(from_type) && llvm::isa<mlir::IntegerType>(target)) {
			return LLVM::PtrToIntOp::create(b, l, target, v);
		}
		if (llvm::isa<mlir::IntegerType>(from_type) && llvm::isa<LLVM::LLVMPointerType>(target)) {
			return LLVM::IntToPtrOp::create(b, l, target, v);
		}
		// Different layouts of the same bytes: reinterpret them
		if (in_function(generator)) {
			mlir::Value slot = make_slot(generator, from->size >= to->size ? from : to);
			store(generator, v, slot);
			return load(generator, to, slot);
		}
		return v;
	}

	// ---------------------------------------------------------------------------------------------
	// Control flow

	static Emitted emit_expression(Generator& generator, ast::Node* node, TypeInfo* expected);
	static bool emit_statement(Generator& generator, ast::Node* statement);
	static mlir::Location source_location(Generator& generator, const ast::Node* node);
	static bool emit_block(Generator& generator, ast::Node* block, mlir::Value result_slot, TypeInfo* result_type);

	// An expression's value, converted to the type it's used as.
	// Whether a value of type from becomes a view of it as type to: a static array as a view.
	static bool is_array_to_view(TypeInfo const* from, TypeInfo const* to) {
		from = from != nullptr ? base(from) : nullptr;
		to = to != nullptr ? base(to) : nullptr;
		return from != nullptr && to != nullptr && TypeInfoVariant::ARRAY == from->variant && TypeInfoVariant::ARRAY == to->variant
			&& ArrayType::STATIC == static_cast<TypeInfoArray const*>(from)->array_type
			&& ArrayType::VIEW == static_cast<TypeInfoArray const*>(to)->array_type;
	}

	/*
	 * What was emitted, as type. A static array that has an address becomes a view of the array
	 * itself, not of a copy: changes through the view reach it, and a large constant isn't copied.
	 */
	static mlir::Value convert_emitted(Generator& generator, const Emitted& emitted, TypeInfo* type) {
		// A variant without values written as Union.Variant, like a block's last expression
		if (ValueKind::VARIANT == emitted.kind) {
			return convert(generator, make_variant(generator, emitted.type, emitted.variant, {}, {}), emitted.type, type);
		}
		if (ValueKind::TYPE == emitted.kind) {
			return convert(generator, value_of(generator, emitted), BUILTIN_type, type);
		}
		if (emitted.address && in_function(generator) && is_array_to_view(emitted.type, type)) {
			return make_view(generator, constant_int(generator, usize_type(generator),
				static_cast<int64_t>(static_cast<TypeInfoArray const*>(base(emitted.type))->count)), emitted.address);
		}
		return convert(generator, value_of(generator, emitted), emitted.type, type);
	}

	/*
	 * Store what was emitted, as type, at address. A large value that's already in memory, of the
	 * same type, is copied with memmove (it may be the same place), which LLVM handles far better
	 * than loading and storing it whole.
	 */
	static void store_emitted(Generator& generator, const Emitted& emitted, TypeInfo* type, mlir::Value address,
		const ast::Node* where = nullptr) {

		// A relative pointer's place: what the pointer given points to, relative to it (docs/types.md, Relative Pointers)
		if (type != nullptr && relative_pointer_of(type) != nullptr) {
			mlir::Value pointer = ValueKind::NULL_VALUE == emitted.kind ? zero_of(generator, pointer_type(generator)) : value_of(generator, emitted);
			write_relative(generator, type, pointer, address, where);
			return;
		}
		if (emitted.address && in_function(generator) && type != nullptr && emitted.type != nullptr
			&& base(emitted.type) == base(type) && type->size > LARGEST_WHOLE_STORE) {
			LLVM::MemmoveOp::create(generator.builder, generator.loc, address, emitted.address,
				constant_int(generator, usize_type(generator), static_cast<int64_t>(type->size)), false);
			return;
		}
		store(generator, convert_emitted(generator, emitted, type), address);
	}

	static mlir::Value emit_as(Generator& generator, ast::Node* node, TypeInfo* type) {
		Emitted emitted = emit_expression(generator, node, type);
		if (ValueKind::VARIANT == emitted.kind) {
			return make_variant(generator, emitted.type, emitted.variant, {}, {});
		}
		return convert_emitted(generator, emitted, type);
	}

	static mlir::Value boolean(Generator& generator, bool truth) {
		return constant_int(generator, llvm_type(generator, BUILTIN_bool), truth ? 1 : 0);
	}

	// A condition, as an i1.
	/*
	 * What a condition is when #is_compile_time decides it, like #is_compile_time && !allowed():
	 * an if's other branch isn't generated, so compile-time code can call what only works there,
	 * and run-time code what only works there. None if it depends on anything else.
	 */
	static std::optional<bool> known_condition(Generator& generator, const ast::Node* node) {
		if (node == nullptr) {
			return std::nullopt;
		}
		const ast::NodeType type = node->node_type;
		if (ast::NodeType::PAREN_GROUP == type && node->children.size() == 1) {
			return known_condition(generator, node->children[0]);
		}
		if (ast::NodeType::DIRECTIVE == type && is_text(node->value.value, "#is_compile_time")) {
			return generator.compile_time;
		}
		const TokenType op = node->value.type;
		if (ast::NodeType::UNARY_OPERATOR == type && TokenType::OPERATOR_NOT == op && node->children.size() == 1) {
			std::optional<bool> operand = known_condition(generator, node->children[0]);
			return operand.has_value() ? std::optional<bool>(!*operand) : std::nullopt;
		}
		if (ast::NodeType::BINARY_OPERATOR == type && node->children.size() == 2
			&& (TokenType::OPERATOR_AND == op || TokenType::OPERATOR_OR == op)) {
			const std::optional<bool> left = known_condition(generator, node->children[0]);
			const std::optional<bool> right = known_condition(generator, node->children[1]);
			// Either side decides an && that's false or an || that's true
			const bool decides = TokenType::OPERATOR_OR == op;
			if ((left.has_value() && *left == decides) || (right.has_value() && *right == decides)) {
				return decides;
			}
			if (left.has_value() && right.has_value()) {
				return !decides;
			}
		}
		return std::nullopt;
	}

	static mlir::Value emit_condition(Generator& generator, ast::Node* node) {
		mlir::Value v = emit_as(generator, node, BUILTIN_bool);
		if (v.getType().getIntOrFloatBitWidth() == 1) {
			return v;
		}
		return LLVM::ICmpOp::create(generator.builder, generator.loc, LLVM::ICmpPredicate::ne, v,
			constant_int(generator, v.getType(), 0));
	}

	static mlir::Value negate(Generator& generator, mlir::Value condition) {
		return LLVM::XOrOp::create(generator.builder, generator.loc, condition, boolean(generator, true));
	}

	/*
	 * Structured control flow, built in place: a region of a new op, filled by a function, then
	 * ended with hmir.end unless the function ended it already (and says so).
	 */
	static void fill_region(Generator& generator, mlir::Region& region, const std::function<bool()>& fill) {
		mlir::OpBuilder::InsertionGuard guard(generator.builder);
		mlir::Block* block = generator.builder.createBlock(&region);
		generator.builder.setInsertionPointToStart(block);
		if (!fill()) {
			::hmir::HemeraEndOp::create(generator.builder, generator.loc);
		}
	}

	// if condition { then } else { otherwise }, without an else if otherwise is empty.
	static void emit_if(Generator& generator, mlir::Value condition, const std::function<bool()>& then,
		const std::function<bool()>& otherwise) {

		auto op = ::hmir::HemeraIfOp::create(generator.builder, generator.loc, condition);
		fill_region(generator, op.getThenRegion(), then);
		if (otherwise) {
			fill_region(generator, op.getElseRegion(), otherwise);
		}
	}

	static void emit_scope(Generator& generator, const std::function<bool()>& body) {
		auto op = ::hmir::HemeraScopeOp::create(generator.builder, generator.loc);
		fill_region(generator, op.getBodyRegion(), body);
	}

	// A loop or switch: break and continue count it.
	static void emit_loop(Generator& generator, bool continues, const std::function<bool()>& body) {
		auto op = ::hmir::HemeraLoopOp::create(generator.builder, generator.loc);
		generator.state->breakables.push_back({ continues });
		fill_region(generator, op.getBodyRegion(), body);
		generator.state->breakables.pop_back();
	}

	// break: leaves depth loops and switches.
	static void emit_break(Generator& generator, uint64_t depth) {
		::hmir::HemeraBreakOp::create(generator.builder, generator.loc, depth);
	}

	// continue: the innermost loop, past any switches inside it.
	static void emit_continue(Generator& generator) {
		uint64_t depth = 0;
		for (auto each = generator.state->breakables.rbegin(); each != generator.state->breakables.rend(); ++each) {
			++depth;
			if (each->continues) {
				break;
			}
		}
		::hmir::HemeraContinueOp::create(generator.builder, generator.loc, depth);
	}

	// return, with the function's results: one, or a struct of several, or written where the caller said.
	static void emit_return(Generator& generator, const std::vector<mlir::Value>& values) {
		mlir::Value result = values.size() == 1 ? values[0] : mlir::Value();
		if (values.size() > 1) {
			result = LLVM::UndefOp::create(generator.builder, generator.loc, results_type(generator, generator.state->type));
			for (size_t i = 0; i < values.size(); ++i) {
				result = insert(generator, result, values[i], { static_cast<int64_t>(i) });
			}
		}
		if (generator.state->result_pointer && result) {
			store(generator, result, generator.state->result_pointer);
			::hmir::HemeraReturnOp::create(generator.builder, generator.loc, mlir::ValueRange{});
			return;
		}
		if (result) {
			::hmir::HemeraReturnOp::create(generator.builder, generator.loc, mlir::ValueRange{ result });
			return;
		}
		::hmir::HemeraReturnOp::create(generator.builder, generator.loc, mlir::ValueRange{});
	}

	// ---------------------------------------------------------------------------------------------
	// Names

	// A constant's value, generated where it's used from its value's expression, as type.
	// ---------------------------------------------------------------------------------------------
	// Compile-time execution (docs/compilation.md, Compile-Time Execution): what an evaluation reaches is
	// generated into a module of its own, compiled for this machine and run, and its result becomes a constant

	static void generate_function(Generator& generator, Declaration* declaration);
	static void finish_module(Generator& generator);
	static mlir::Value constant_global(Generator& generator, mlir::Type type, size_t alignment, const std::string& name,
		const std::function<mlir::Value()>& build);
	static mlir::Value dense_integer_array(Generator& generator, mlir::Type array_type, mlir::Type element_type,
		const std::vector<mlir::Value>& elements);
	static mlir::Value assembly(Generator& generator, mlir::Type result, const std::vector<mlir::Value>& operands,
		std::string_view text, std::string_view constraints);
	static mlir::Value convert(Generator& generator, mlir::Value v, TypeInfo const* from, TypeInfo const* to);

	// The C function compile-time code is entered through, with a pointer to where its result goes.
	constexpr std::string_view COMPILE_TIME_ENTRY = "hemera.compile_time";

	// The options compile-time code is generated with: the target's choices, compiled for this machine.
	static void set_host_options(Options& host, const Options& target) {
#if !defined(_WIN32)
		host.os = OSType::Linux;
		host.environment = EnvironmentType::GNU;
		host.object_format = ObjectFormatType::ELF;
#endif
		host.input = target.input;
		// What compile-time code asks the compiler about the program being compiled
		host.settings = target.settings;
		host.allow_run = target.allow_run;
		host.output_name = "compile_time";
		host.entry = "";
		host.startup_code = false;
	}

	// Whether a constant's value calls a function, so it's worked out by running it.
	static bool needs_execution(Declaration* declaration) {
		if (declaration->checked == nullptr) {
			return false;
		}
		for (const auto& [node, found] : declaration->checked->nodes) {
			if (found.called != nullptr || (declaration->checked->is_node(node) && ast::NodeType::DIRECTIVE == node->node_type
				&& is_text(node->value.value, "#run"))) {
				return true;
			}
		}
		return false;
	}

	static uint64_t read_unsigned(const uint8_t* bytes, size_t size) {
		uint64_t value = 0;
		std::memcpy(&value, bytes, std::min<size_t>(size, sizeof(value)));
		return value;
	}

	// Whether a struct is base/compiler's Code, which only compile-time code can have (docs/compilation.md, Code Values).
	static bool is_code_struct(Generator& generator, TypeInfoStruct const* structure) {
		if (structure->name == nullptr || *structure->name != "Code") {
			return false;
		}
		std::scoped_lock<std::mutex> lock(generator.program->names.mutex);
		auto iter = generator.program->names.declarations.find(std::make_pair(intern(std::format("{}compiler", BASE_PACKAGE_PREFIX)),
			intern(std::string("Code"))));
		return iter != generator.program->names.declarations.end() && iter->second->type_value != nullptr
			&& base(iter->second->type_value) == structure;
	}

	/*
	 * Copy what a value of type at data points to, into value.pointed, at the offset in value.bytes of each
	 * pointer, so it outlives the compiled code. Strings and views are copied; any other pointer must be null.
	 */
	static bool capture_pointed(Generator& generator, TypeInfo const* type, const uint8_t* data, size_t offset,
		CompileTimeValue& value, const ast::Node* where) {

		type = base(type);
		const TypeInfoVariant variant = type->variant;
		const uint8_t* at = data + offset;
		auto refuse = [&](std::string_view what) {
			unsupported(generator, where, std::format("{} can't be the result of compile-time code, since what it points to "
				"doesn't exist in the program", what));
			return false;
		};
		if (TypeInfoVariant::INTEGER == variant || TypeInfoVariant::ENUM == variant || TypeInfoVariant::CHAR == variant
			|| TypeInfoVariant::BOOLEAN == variant || TypeInfoVariant::FLOAT == variant || TypeInfoVariant::COMPLEX == variant
			|| TypeInfoVariant::QUATERNION == variant || TypeInfoVariant::VOID == variant) {
			return true;
		}
		/*
		 * A type value: its description is the compiler's, which knows the type it describes, so the
		 * program's constant can be that type's own (constant_from)
		 */
		if (TypeInfoVariant::TYPE == variant) {
			uint64_t address = 0;
			std::memcpy(&address, at, sizeof(address));
			const auto& described = compile_time_data(generator.program).described_types();
			return address == 0 || described.contains(static_cast<uintptr_t>(address)) || refuse("a type the compiler doesn't know");
		}
		if (TypeInfoVariant::STRUCT == variant) {
			auto structure = static_cast<TypeInfoStruct const*>(type);
			if (is_code_struct(generator, structure)) {
				return refuse("a compiler.Code");
			}
			if (structure->is_union) {
				return !type->contains_pointers || refuse("a #union struct holding a pointer");
			}
			for (const StructMember& member : structure->members) {
				if (!capture_pointed(generator, member.member_type, data, offset + member.offset, value, where)) {
					return false;
				}
			}
			return true;
		}
		if (TypeInfoVariant::ARRAY == variant) {
			auto array = static_cast<TypeInfoArray const*>(type);
			if (ArrayType::STATIC == array->array_type) {
				for (size_t i = 0; i < array->count; ++i) {
					if (!capture_pointed(generator, array->element_type, data, offset + i * array->element_type->size, value, where)) {
						return false;
					}
				}
				return true;
			}
			const uint64_t count = read_unsigned(at, 8);
			const uint8_t* elements = reinterpret_cast<const uint8_t*>(read_unsigned(at + 8, 8));
			if (ArrayType::DYNAMIC == array->array_type) {
				return elements == nullptr || refuse("a dynamic array");
			}
			if (elements == nullptr || count == 0) {
				return true;
			}
			CompileTimeValue& copied = value.pointed[offset + 8];
			copied.bytes.assign(elements, elements + count * array->element_type->size);
			for (size_t i = 0; i < count; ++i) {
				if (!capture_pointed(generator, array->element_type, copied.bytes.data(), i * array->element_type->size, copied, where)) {
					return false;
				}
			}
			return true;
		}
		if (TypeInfoVariant::STRING == variant) {
			const bool raw = static_cast<TypeInfoString const*>(type)->is_raw;
			const size_t pointer_offset = raw ? 0 : 8;
			const char* text = reinterpret_cast<const char*>(read_unsigned(at + pointer_offset, 8));
			if (text == nullptr) {
				return true;
			}
			const size_t count = raw ? std::strlen(text) : read_unsigned(at, 8);
			value.pointed[offset + pointer_offset].bytes.assign(text, text + count);
			return true;
		}
		if (TypeInfoVariant::UNION == variant) {
			auto union_type = static_cast<TypeInfoUnion const*>(type);
			if (union_type->null_is_none) {
				return read_unsigned(at, 8) == 0 || refuse("a pointer");
			}
			return !type->contains_pointers || refuse("a union holding pointers");
		}
		// Pointers, functions, types and anys: only null can leave compile time
		return read_unsigned(at, 8) == 0 || refuse(std::format("a value of type {}", to_string(type)));
	}

	// A constant array of i8, of bytes.
	static mlir::Value constant_bytes(Generator& generator, const uint8_t* bytes, size_t count) {
		std::vector<mlir::Value> elements;
		mlir::Type byte = integer_type(generator, 1);
		for (size_t i = 0; i < count; ++i) {
			elements.push_back(constant_int(generator, byte, static_cast<int64_t>(static_cast<int8_t>(bytes[i]))));
		}
		mlir::Type array = bytes_type(generator, count);
		mlir::Value dense = dense_integer_array(generator, array, byte, elements);
		return dense ? dense : zero_of(generator, array);
	}

	static mlir::Value constant_number(Generator& generator, mlir::Type type, const uint8_t* bytes, size_t size) {
		llvm::APInt bits(static_cast<unsigned>(size * 8), 0);
		for (size_t i = 0; i < size; ++i) {
			bits.insertBits(llvm::APInt(8, bytes[i]), static_cast<unsigned>(i * 8));
		}
		if (auto floating = mlir::dyn_cast<mlir::FloatType>(type)) {
			return LLVM::ConstantOp::create(generator.builder, generator.loc, type,
				generator.builder.getFloatAttr(type, llvm::APFloat(floating.getFloatSemantics(), bits)));
		}
		const unsigned width = type.getIntOrFloatBitWidth();
		return LLVM::ConstantOp::create(generator.builder, generator.loc, type,
			generator.builder.getIntegerAttr(type, width == 1 ? llvm::APInt(1, bits.isZero() ? 0 : 1) : bits.zextOrTrunc(width)));
	}

	/*
	 * count numbers of element, from bytes, as one dense constant of array_type, or nothing if element isn't a
	 * number. Inserting each element instead has LLVM fold the whole array again for every one, which takes
	 * seconds for a table of thousands.
	 */
	static mlir::Value dense_numbers(Generator& generator, mlir::Type array_type, TypeInfo const* element, const uint8_t* bytes,
		size_t count) {

		mlir::Type lane = llvm_type(generator, element);
		element = base(element);
		const TypeInfoVariant variant = element->variant;
		const bool number = TypeInfoVariant::INTEGER == variant || TypeInfoVariant::ENUM == variant || TypeInfoVariant::CHAR == variant
			|| TypeInfoVariant::FLOAT == variant;
		if (!number || count == 0 || !lane.isIntOrFloat() || lane.getIntOrFloatBitWidth() != element->size * 8) {
			return mlir::Value();
		}
		auto tensor = mlir::RankedTensorType::get({ static_cast<int64_t>(count) }, lane);
		auto data = mlir::DenseElementsAttr::getFromRawBuffer(tensor,
			llvm::ArrayRef<char>(reinterpret_cast<const char*>(bytes), count * element->size));
		return LLVM::ConstantOp::create(generator.builder, generator.loc, array_type, data);
	}

	// The value of type at offset in value, as a constant in generator's module.
	static mlir::Value constant_from(Generator& generator, TypeInfo const* type, const CompileTimeValue& value, size_t offset) {
		mlir::Type llvm = llvm_type(generator, type);
		type = base(type);
		const TypeInfoVariant variant = type->variant;
		const uint8_t* at = value.bytes.data() + offset;
		if (TypeInfoVariant::INTEGER == variant || TypeInfoVariant::ENUM == variant || TypeInfoVariant::CHAR == variant
			|| TypeInfoVariant::BOOLEAN == variant || TypeInfoVariant::FLOAT == variant) {
			return constant_number(generator, llvm, at, type->size);
		}
		// A type value from compile-time code: the description of the type it is, in the program
		if (TypeInfoVariant::TYPE == variant) {
			uint64_t address = 0;
			std::memcpy(&address, at, sizeof(address));
			const auto& described = compile_time_data(generator.program).described_types();
			auto found = described.find(static_cast<uintptr_t>(address));
			return found != described.end() ? type_descriptor(generator, found->second) : zero_of(generator, llvm);
		}
		if (TypeInfoVariant::COMPLEX == variant || TypeInfoVariant::QUATERNION == variant) {
			auto composite = static_cast<TypeInfoComposite const*>(type);
			mlir::Value result = zero_of(generator, llvm);
			mlir::Type part = integer_type(generator, composite->part_size);
			for (size_t i = 0; i < type->size / composite->part_size; ++i) {
				result = insert(generator, result, constant_number(generator, part, at + i * composite->part_size, composite->part_size),
					{ static_cast<int64_t>(i) });
			}
			return result;
		}
		if (TypeInfoVariant::STRUCT == variant) {
			auto structure = static_cast<TypeInfoStruct const*>(type);
			if (structure->is_union) {
				return insert(generator, zero_of(generator, llvm), constant_bytes(generator, at, type->size), { 0 });
			}
			mlir::Value result = zero_of(generator, llvm);
			const std::vector<int64_t> elements = generator.member_elements[structure];
			for (size_t i = 0; i < structure->members.size(); ++i) {
				const StructMember& member = structure->members[i];
				result = insert(generator, result, constant_from(generator, member.member_type, value, offset + member.offset), { elements[i] });
			}
			return result;
		}
		if (TypeInfoVariant::ARRAY == variant) {
			auto array = static_cast<TypeInfoArray const*>(type);
			if (ArrayType::STATIC == array->array_type) {
				if (mlir::Value dense = dense_numbers(generator, llvm, array->element_type, at, array->count)) {
					return dense;
				}
				mlir::Value result = zero_of(generator, llvm);
				for (size_t i = 0; i < array->count; ++i) {
					result = insert(generator, result, constant_from(generator, array->element_type, value, offset + i * array->element_type->size),
						{ static_cast<int64_t>(i) });
				}
				return result;
			}
			auto pointed = value.pointed.find(offset + 8);
			if (ArrayType::DYNAMIC == array->array_type || pointed == value.pointed.end()) {
				return zero_of(generator, llvm);
			}
			const CompileTimeValue& elements = pointed->second;
			const size_t count = elements.bytes.size() / std::max<size_t>(array->element_type->size, 1);
			mlir::Type array_type = LLVM::LLVMArrayType::get(llvm_type(generator, array->element_type), count);
			mlir::Value data = constant_global(generator, array_type, std::max<size_t>(array->element_type->alignment, 1),
				std::format("compile_time.{}", generator.compile_time_globals++), [&]() {
					if (mlir::Value dense = dense_numbers(generator, array_type, array->element_type, elements.bytes.data(), count)) {
						return dense;
					}
					mlir::Value result = zero_of(generator, array_type);
					for (size_t i = 0; i < count; ++i) {
						result = insert(generator, result, constant_from(generator, array->element_type, elements, i * array->element_type->size),
							{ static_cast<int64_t>(i) });
					}
					return result;
				});
			return make_view(generator, constant_int(generator, usize_type(generator), static_cast<int64_t>(count)), data);
		}
		if (TypeInfoVariant::STRING == variant) {
			const bool raw = static_cast<TypeInfoString const*>(type)->is_raw;
			const size_t pointer_offset = raw ? 0 : 8;
			auto pointed = value.pointed.find(offset + pointer_offset);
			mlir::Value data = pointed == value.pointed.end() ? zero_of(generator, pointer_type(generator))
				: string_bytes(generator, std::string(pointed->second.bytes.begin(), pointed->second.bytes.end()));
			if (raw) {
				return data;
			}
			return make_view(generator, constant_number(generator, usize_type(generator), at, 8), data);
		}
		if (TypeInfoVariant::UNION == variant && !static_cast<TypeInfoUnion const*>(type)->null_is_none) {
			auto union_type = static_cast<TypeInfoUnion const*>(type);
			const size_t tag = union_type->tag_type->size;
			mlir::Value result = insert(generator, zero_of(generator, llvm), constant_number(generator, integer_type(generator, tag), at, tag), { 0 });
			if (type->size > tag) {
				result = insert(generator, result, constant_bytes(generator, at + tag, type->size - tag), { 1 });
			}
			return result;
		}
		// Pointers, functions, types, anys and optional pointers, which capture_pointed made sure are null
		return zero_of(generator, llvm);
	}

	/*
	 * Run node at compile time, an expression checked in checked (the body or constant it's in), and capture its
	 * value as type, or just run it when type is null. Reports why not and returns false if it can't be run.
	 */
	// One piece of compile-time code in a run, and where its value goes (none for code run for its effects).
	struct CompileTimeItem {
		ast::Node* node;
		TypeInfo* type;
		CheckedBody* checked;
		Declaration* declaration;
		CompileTimeValue* result;
		// Code to generate instead of node's, like a constraint's call (run_constraint_evaluation)
		std::function<void(Generator&)> emit = nullptr;
		/*
		 * Where to say whether its value could be kept, for a run that goes on without the values that can't,
		 * like one holding a function (constant_values). Without it, one that can't fails the run.
		 */
		bool* captured = nullptr;
	};

	static void compiler_service(const char* name, int64_t name_count, uint8_t* result, uint8_t* const* arguments,
		int64_t count, const uint8_t* context, const char* file, int64_t file_count);
	constexpr const char* COMPILER_SERVICE_SYMBOL = "hemera.compiler_service";

	// What compile-time code's calls to base/compiler reach (compiler_service), while it runs.
	struct ServiceScope {
		ProgramInfo* program;
		const Options* options;
		// The program PackageInfo records describe, and its options: a target's during its checks
		ProgramInfo* reflected = nullptr;
		const Options* reflected_options = nullptr;
		// While a constraint runs, where its requirements say what isn't satisfied (docs/types.md, Constraints)
		std::vector<std::string>* unsatisfied = nullptr;
		// Each require_any being run: where its failures start, then where each alternative's ended
		std::vector<std::vector<size_t>> alternatives = {};
		/*
		 * The trees the Code this run made hold, by handle less one (docs/compilation.md, Code Values): numbered
		 * within the run, so a handle doesn't depend on what ran meanwhile on other threads.
		 */
		std::vector<const ast::Node*> codes = {};
		// One of base/compiler's code functions reported why it couldn't make code
		bool code_reported = false;
	};
	static thread_local ServiceScope* service_scope = nullptr;

	/*
	 * Run compile-time code, each item in turn in one run, capturing each one's value. When unchecked is given,
	 * functions and constants it reaches that aren't checked yet are listed there instead, and nothing runs.
	 * Reports why not and returns false if it can't be run.
	 */
	/*
	 * The start of code the compiler enters, like a run's entry: a carrier block, loaded, and
	 * runtime.COMPILE_TIME_CONTEXT, which the compiler's services are reached through. The context's slot, or
	 * nothing if base/runtime isn't there.
	 */
	static mlir::Value enter_compile_time(Generator& compiled, const ast::Node* where) {
		Declaration* carrier_declaration = base_declaration_named(compiled, "runtime", "CarrierBlock");
		Declaration* context_declaration = base_declaration_named(compiled, "runtime", "Context");
		Declaration* compile_time_context = base_declaration_named(compiled, "runtime", "COMPILE_TIME_CONTEXT");
		if (carrier_declaration == nullptr || context_declaration == nullptr || compile_time_context == nullptr) {
			unsupported(compiled, where, "base/runtime isn't available for compile-time code");
			return mlir::Value();
		}
		mlir::Value carrier = make_slot(compiled, carrier_declaration->type_value);
		store_zero(compiled, carrier_declaration->type_value, carrier);
		assembly(compiled, mlir::Type(), { carrier }, "movq $0, %r14", "r,~{memory}");
		mlir::Value context = make_slot(compiled, context_declaration->type_value);
		store(compiled, emit_constant_value(compiled, compile_time_context, context_declaration->type_value, where), context);
		return context;
	}

	// The program's compile-time library (middle_end/jit.h), made the first time code runs.
	static CompileTimeLibrary& compile_time_library(ProgramInfo* program) {
		std::scoped_lock<std::mutex> lock(program->compile_time_library_mutex);
		if (program->compile_time_library == nullptr) {
			program->compile_time_library = new_compile_time_library();
		}
		return *static_cast<CompileTimeLibrary*>(program->compile_time_library.get());
	}

	static bool run_items(Generator& generator, std::vector<CompileTimeItem>& items, std::vector<Declaration*>* unchecked,
		bool quiet = false, std::vector<std::string>* unsatisfied = nullptr) {
		// Compile-time code can run before the program is generated, which loads these otherwise
		generator.program->context->loadDialect<LLVM::LLVMDialect>();
		generator.program->context->loadDialect<::hmir::HemeraDialect>();
		Options options;
		set_host_options(options, *generator.options);
		mlir::ModuleOp module = mlir::ModuleOp::create(generator.loc, "compile_time");
		Generator compiled(generator.program, module);
		compiled.options = &options;
		compiled.input_package = generator.input_package;
		compiled.compile_time = true;
		compiled.links.library = &compile_time_library(generator.program);
		// Quietly: anything that can't be generated just fails the run, like a constant reflection can't show
		std::vector<Declaration*> ignored;
		if (quiet && unchecked == nullptr) {
			unchecked = &ignored;
		}
		compiled.collecting = unchecked != nullptr;
		Declaration* first_declaration = items[0].declaration;
		compiled.file_path = first_declaration != nullptr ? file_path_of(first_declaration->package_path, first_declaration->file_name)
			: current_file(generator);
		ast::Node* first = items[0].node != nullptr ? items[0].node
			: items[0].declaration != nullptr ? items[0].declaration->node : nullptr;
		{
			mlir::OpBuilder::InsertionGuard guard(compiled.builder);
			compiled.builder.setInsertionPointToEnd(module.getBody());
			// Its argument: where each item's value goes
			auto body = LLVM::LLVMFuncOp::create(compiled.builder, compiled.loc, COMPILE_TIME_ENTRY,
				LLVM::LLVMFunctionType::get(LLVM::LLVMVoidType::get(compiled.context), { pointer_type(compiled) }));
			mlir::Block* entry = body.addEntryBlock(compiled.builder);
			compiled.builder.setInsertionPointToEnd(entry);
			FunctionState state;
			state.declaration = first_declaration;
			state.checked = items[0].checked;
			state.entry = entry;
			compiled.state = &state;
			mlir::Value context = enter_compile_time(compiled, first);
			if (!context) {
				generator.failed = true;
				module.erase();
				return false;
			}
			state.context = context;
			for (size_t i = 0; i < items.size(); ++i) {
				CompileTimeItem& item = items[i];
				state.declaration = item.declaration;
				state.checked = item.checked;
				if (item.emit) {
					item.emit(compiled);
				}
				else if (item.type != nullptr) {
					mlir::Value destination = LLVM::LoadOp::create(compiled.builder, compiled.loc, pointer_type(compiled),
						offset_address(compiled, entry->getArgument(0), i * 8));
					store(compiled, emit_as(compiled, item.node, item.type), destination);
				}
				else {
					emit_expression(compiled, item.node, nullptr);
				}
			}
			LLVM::ReturnOp::create(compiled.builder, compiled.loc, mlir::ValueRange{});
			compiled.state = nullptr;
		}
		while (!compiled.pending.empty()) {
			Declaration* next = compiled.pending.back();
			compiled.pending.pop_back();
			generate_function(compiled, next);
		}
		if (!compiled.unchecked.empty()) {
			*unchecked = compiled.unchecked;
			module.erase();
			return false;
		}
		if (quiet && compiled.failed) {
			module.erase();
			return false;
		}
		for (const Generator::HeldError& error : compiled.held) {
			report_error(ErrorCode::E5002, error.file_path, error.line, error.column, error.what);
		}
		finish_module(compiled);
		if (compiled.failed || mlir::failed(mlir::verify(module))) {
			generator.failed = true;
			module.erase();
			return false;
		}
		CompileTimeData& data = compile_time_data(generator.program);
		CompileTimeRun run;
		run.file_path = compiled.file_path;
		run.line = first->value.line_number;
		run.column = first->value.column_number;
		run.symbols = compiled.compile_time_symbols;
		run.symbols.emplace_back(COMPILER_SERVICE_SYMBOL, reinterpret_cast<const void*>(&compiler_service));
		run.types = &data.described_types();
		auto llvm_context = std::make_unique<llvm::LLVMContext>();
		std::unique_ptr<llvm::Module> lowered = lower_to_llvm(module, *llvm_context, options);
		module.erase();
		if (lowered == nullptr) {
			generator.failed = true;
			return false;
		}
		// Where each item's value goes
		std::vector<std::vector<uint64_t>> buffers;
		std::vector<void*> destinations;
		for (const CompileTimeItem& item : items) {
			buffers.emplace_back(item.type != nullptr ? (item.type->size + 7) / 8 + 1 : 1);
			destinations.push_back(buffers.back().data());
		}
		bool captured = true;
		std::string error;
		// The program's options, not the ones compile-time code is compiled with, when this runs from compile-time code
		const Options* program_options = generator.compile_time && service_scope != nullptr ? service_scope->options : generator.options;
		ServiceScope scope{ generator.program, program_options };
		scope.unsatisfied = unsatisfied;
		ServiceScope* outer_scope = service_scope;
		service_scope = &scope;
		const RunResult ran = run_on_host(std::move(lowered), std::move(llvm_context), std::string(COMPILE_TIME_ENTRY),
			destinations.data(), [&]() {
				for (size_t i = 0; i < items.size(); ++i) {
					CompileTimeItem& item = items[i];
					if (item.type != nullptr && item.result != nullptr) {
						const uint8_t* bytes = reinterpret_cast<const uint8_t*>(buffers[i].data());
						item.result->bytes.assign(bytes, bytes + item.type->size);
						const bool failed_before = generator.failed;
						const size_t held_before = generator.held.size();
						// An #insert's Code: the tree it holds, which belongs to the program and outlives the run
						TypeInfo const* base_type = get_base_type(item.type);
						if (item.result->wants_code && base_type != nullptr && TypeInfoVariant::STRUCT == base_type->variant
							&& is_code_struct(generator, static_cast<TypeInfoStruct const*>(base_type))) {
							uint64_t handle = 0;
							std::memcpy(&handle, bytes, sizeof(handle));
							item.result->code = handle == 0 || handle > scope.codes.size() ? nullptr : scope.codes[handle - 1];
							item.result->code_reported = scope.code_reported;
							continue;
						}
						const bool kept = capture_pointed(generator, item.type, item.result->bytes.data(), 0, *item.result, item.node);
						if (item.captured != nullptr) {
							// Left out on its own, without failing the others
							*item.captured = kept;
							generator.failed = failed_before;
							generator.held.resize(held_before);
						}
						else {
							captured = kept && captured;
						}
					}
				}
			}, run, error, compiled.links);
		service_scope = outer_scope;
		if (RunResult::NOT_COMPILED == ran) {
			unsupported(generator, first, std::format("compile-time code couldn't run: {}", error));
			return false;
		}
		if (RunResult::FAILED == ran) {
			generator.failed = true;
			return false;
		}
		return captured;
	}

	static bool run_at_compile_time(Generator& generator, ast::Node* node, TypeInfo* type, CheckedBody* checked,
		Declaration* declaration, CompileTimeValue& result, std::vector<Declaration*>* unchecked = nullptr) {

		std::vector<CompileTimeItem> items{ CompileTimeItem{ node, type, checked, declaration, &result } };
		return run_items(generator, items, unchecked);
	}

	/*
	 * A constant whose value calls a function: run once, the first time it's used, and the same constant
	 * after that.
	 */
	// What checking already ran for key, a constant's declaration or a #run's node, if it did.
	static std::optional<CompileTimeValue> already_run(Generator& generator, const void* key) {
		std::scoped_lock<std::mutex> lock(generator.names.mutex);
		auto iter = generator.names.evaluations.find(key);
		if (iter == generator.names.evaluations.end() || Evaluation::State::DONE != iter->second->state) {
			return std::nullopt;
		}
		return iter->second->value;
	}

	static mlir::Value executed_constant(Generator& generator, Declaration* declaration, TypeInfo* type, const ast::Node* where) {
		auto iter = generator.compile_time_values.find(declaration);
		if (iter == generator.compile_time_values.end()) {
			if (std::optional<CompileTimeValue> ran = already_run(generator, declaration)) {
				iter = generator.compile_time_values.emplace(declaration, std::move(*ran)).first;
			}
		}
		if (iter == generator.compile_time_values.end()) {
			// A constant that's a #run: what it runs, rather than code that runs it only to copy out what it gives
			ast::Node* definition = definition_value(declaration->node);
			const bool directive = definition != nullptr && ast::NodeType::DIRECTIVE == definition->node_type
				&& is_text(definition->value.value, "#run") && !definition->children.empty();
			std::optional<CompileTimeValue> ran = directive ? already_run(generator, definition) : std::nullopt;
			CompileTimeValue result;
			if (ran.has_value()) {
				result = std::move(*ran);
			}
			else if (!run_at_compile_time(generator, directive ? definition->children[0] : definition, declaration->value_type,
				declaration->checked.get(), declaration, result)) {
				return zero_of(generator, llvm_type(generator, type));
			}
			iter = generator.compile_time_values.emplace(declaration, std::move(result)).first;
		}
		(void)where;
		return convert(generator, constant_from(generator, declaration->value_type, iter->second, 0), declaration->value_type, type);
	}

	static mlir::Value emit_constant_value(Generator& generator, Declaration* declaration, TypeInfo* type, const ast::Node* where) {
		if (generator.inlining.contains(declaration)) {
			unsupported(generator, where, std::format("{} refers to itself", text_of(declaration->name)));
			return zero_of(generator, llvm_type(generator, type));
		}
		if (generator.collecting && declaration->checked == nullptr) {
			generator.unchecked.push_back(declaration);
			return zero_of(generator, llvm_type(generator, type));
		}
		if (needs_execution(declaration)) {
			return executed_constant(generator, declaration, type, where);
		}
		FunctionState constant_state;
		constant_state.declaration = declaration;
		constant_state.checked = declaration->checked.get();
		constant_state.context = generator.state != nullptr ? generator.state->context : mlir::Value();
		constant_state.entry = generator.state != nullptr ? generator.state->entry : nullptr;
		FunctionState* outer = generator.state;
		generator.state = &constant_state;
		generator.inlining.insert(declaration);
		mlir::Value result = emit_as(generator, definition_value(declaration->node), type);
		generator.inlining.erase(declaration);
		generator.state = outer;
		return result;
	}

	static LLVM::GlobalOp global_for(Generator& generator, Declaration* declaration);

	static int64_t enum_value(TypeInfo const* type, InternedString member) {
		auto enumeration = static_cast<TypeInfoEnum const*>(base(type));
		for (size_t i = 0; i < enumeration->members.size(); ++i) {
			if (*enumeration->members[i] == *member) {
				return static_cast<int64_t>(enumeration->values[i]);
			}
		}
		return 0;
	}

	static bool is_intrinsic(Declaration* called);

	// What a name is: a local, the context, a function, a constant, or something that isn't a value.
	static Emitted emit_name(Generator& generator, ast::Node* node, const CheckedNode* found, TypeInfo* expected) {
		if (found == nullptr || ValueKind::POISONED == found->kind) {
			unsupported(generator, node, std::format("{} wasn't checked", text_of(node->value.value)));
			return value(zero_of(generator, usize_type(generator)), BUILTIN_int);
		}
		Emitted result;
		result.kind = found->kind;
		result.type = found->type;
		result.variant = found->variant;
		result.name = node->value.value;
		if (ValueKind::TYPE == found->kind || ValueKind::PACKAGE == found->kind || ValueKind::BUILTIN_FUNCTION == found->kind
			|| ValueKind::GENERIC_FUNCTION == found->kind) {
			return result;
		}
		FunctionState& state = *generator.state;
		if (found->local != nullptr) {
			// A value from an instance's generic list, a constant
			auto generic_constant = state.checked != nullptr ? state.checked->generic_constants.find(found->local)
				: decltype(state.checked->generic_constants)::const_iterator();
			if (state.checked != nullptr && generic_constant != state.checked->generic_constants.end()) {
				const ConstantValue& constant = generic_constant->second;
				if (ConstantValue::Kind::FUNCTION == constant.kind && constant.function != nullptr) {
					return value(LLVM::AddressOfOp::create(generator.builder, generator.loc, function_for(generator, constant.function)),
						found->type);
				}
				const int64_t number = ConstantValue::Kind::BOOLEAN == constant.kind ? (constant.boolean ? 1 : 0)
					: ConstantValue::Kind::ENUM_MEMBER == constant.kind ? enum_value(found->type, intern(constant.member))
					: constant.integer;
				// A derived one is untyped, taking the type it's used as
				TypeInfo* constant_type = found->type != nullptr ? found->type : untyped_as(found->kind, expected);
				return value(constant_int(generator, llvm_type(generator, constant_type), number), constant_type);
			}
			auto kept = state.values.find(found->local);
			if (kept != state.values.end()) {
				return value(kept->second, found->type);
			}
			auto slot = state.slots.find(found->local);
			if (slot != state.slots.end()) {
				return location(slot->second, found->type);
			}
			auto constant = state.constants.find(found->local);
			if (constant != state.constants.end()) {
				TypeInfo* type = is_untyped(found->kind) ? untyped_as(found->kind, expected) : found->type;
				return value(emit_as(generator, constant->second, type), type);
			}
			unsupported(generator, node, std::format("{} can't be generated here", text_of(node->value.value)));
			return value(zero_of(generator, llvm_type(generator, found->type)), found->type);
		}
		Declaration* declaration = found->declaration;
		if (declaration == nullptr && ValueKind::VALUE == found->kind && is_text(node->value.value, "context")) {
			return location(state.context, found->type);
		}
		if (declaration == nullptr) {
			if (ValueKind::VALUE == found->kind) {
				unsupported(generator, node, std::format("{} can't be generated yet", text_of(node->value.value)));
				return value(zero_of(generator, llvm_type(generator, found->type)), found->type);
			}
			return result;
		}
		if (is_untyped(found->kind)) {
			TypeInfo* type = untyped_as(found->kind, expected);
			return value(emit_constant_value(generator, declaration, type, node), type);
		}
		if (DeclarationKind::FUNCTION == declaration->kind && declaration->value_type != nullptr) {
			if (is_intrinsic(declaration)) {
				// Only called, never a value, since it's instructions rather than a function
				return result;
			}
			LLVM::LLVMFuncOp function = function_for(generator, declaration);
			return value(LLVM::AddressOfOp::create(generator.builder, generator.loc, function), declaration->value_type);
		}
		if (DeclarationKind::VALUE == declaration->kind && declaration->value_type != nullptr && ValueKind::VALUE == found->kind) {
			if (!in_function(generator)) {
				// In another constant's value, which can't read a global: its address, or its value again
				Emitted constant = location(LLVM::AddressOfOp::create(generator.builder, generator.loc,
					global_for(generator, declaration)), declaration->value_type);
				constant.constant = declaration;
				return constant;
			}
			LLVM::GlobalOp global = global_for(generator, declaration);
			return location(LLVM::AddressOfOp::create(generator.builder, generator.loc, global), declaration->value_type);
		}
		return result;
	}

	// A member of a struct by name, at any depth through using: its offset, type and LLVM path.
	static bool find_member(Generator& generator, TypeInfoStruct const* structure, InternedString name, size_t& offset,
		TypeInfo*& type, std::vector<int64_t>& path) {

		llvm_type(generator, structure);
		const std::vector<int64_t> elements = generator.member_elements[structure];
		for (size_t i = 0; i < structure->members.size(); ++i) {
			const StructMember& member = structure->members[i];
			if (member.name != nullptr && !member.is_using && *member.name == *name) {
				offset = member.offset;
				type = member.member_type;
				path.push_back(elements[i]);
				return true;
			}
		}
		for (size_t i = 0; i < structure->members.size(); ++i) {
			const StructMember& member = structure->members[i];
			TypeInfo const* included = base(member.member_type);
			if ((member.is_using || member.name == nullptr) && included != nullptr && TypeInfoVariant::STRUCT == included->variant) {
				std::vector<int64_t> inner_path{ elements[i] };
				size_t inner = 0;
				if (find_member(generator, static_cast<TypeInfoStruct const*>(included), name, inner, type, inner_path)) {
					offset = member.offset + inner;
					path.insert(path.end(), inner_path.begin(), inner_path.end());
					return true;
				}
			}
		}
		for (size_t i = 0; i < structure->members.size(); ++i) {
			const StructMember& member = structure->members[i];
			if (member.is_using && member.name != nullptr && *member.name == *name) {
				offset = member.offset;
				type = member.member_type;
				path.push_back(elements[i]);
				return true;
			}
		}
		return false;
	}

	// ---------------------------------------------------------------------------------------------
	// Type descriptors: the base/compiler TypeInfo each type value points to (docs/types.md, any)

	// A read-only global whose value build emits, and its address.
	static mlir::Value constant_global(Generator& generator, mlir::Type type, size_t alignment, const std::string& name,
		const std::function<mlir::Value()>& build) {

		LLVM::GlobalOp global;
		{
			mlir::OpBuilder::InsertionGuard guard(generator.builder);
			generator.builder.setInsertionPointToEnd(generator.module.getBody());
			global = LLVM::GlobalOp::create(generator.builder, generator.loc, type, true, LLVM::Linkage::Private, name,
				mlir::Attribute(), alignment);
			generator.builder.setInsertionPointToStart(generator.builder.createBlock(&global.getInitializerRegion()));
			FunctionState* outer = generator.state;
			generator.state = nullptr;
			mlir::Value initial = build();
			generator.state = outer;
			LLVM::ReturnOp::create(generator.builder, generator.loc, initial);
		}
		return LLVM::AddressOfOp::create(generator.builder, generator.loc, global);
	}

	static std::string name_or_empty(InternedString name) {
		return name != nullptr ? text_of(name) : std::string();
	}

	static mlir::Value type_descriptor(Generator& generator, TypeInfo const* type);

	/*
	 * A value of one of base/compiler's structs, made field by field by name, so it follows their
	 * declarations' layout. Fields that aren't set are zero.
	 */
	struct ConstantStruct {
		Generator& generator;
		TypeInfoStruct const* type;
		mlir::Value whole;

		ConstantStruct(Generator& generator_, TypeInfo const* type_)
			: generator{ generator_ }
			, type{ static_cast<TypeInfoStruct const*>(base(type_)) }
			, whole{ zero_of(generator_, llvm_type(generator_, type_)) }
		{}

		// The field's type, or null if the struct has no such field.
		TypeInfo* field(std::string_view name, std::vector<int64_t>& path) {
			size_t offset = 0;
			TypeInfo* field_type = nullptr;
			if (!find_member(generator, type, intern(std::string(name)), offset, field_type, path)) {
				unsupported(generator, nullptr, std::format("{} has no member {}, which type information needs",
					name_or_empty(type->name), name));
				return nullptr;
			}
			return field_type;
		}

		void set(std::string_view name, const std::function<mlir::Value(TypeInfo*)>& make) {
			std::vector<int64_t> path;
			if (TypeInfo* field_type = field(name, path)) {
				whole = insert(generator, whole, make(field_type), path);
			}
		}

		void number(std::string_view name, uint64_t value) {
			set(name, [&](TypeInfo* field_type) { return constant_number(generator, field_type, value); });
		}

		void flag(std::string_view name, bool value) {
			number(name, value ? 1 : 0);
		}

		void text(std::string_view name, const std::string& value) {
			set(name, [&](TypeInfo*) { return constant_string(generator, value); });
		}

		// A ptr[TypeInfo]: the type's descriptor, or null.
		void type_of(std::string_view name, TypeInfo const* value) {
			set(name, [&](TypeInfo*) {
				return value != nullptr ? type_descriptor(generator, value) : zero_of(generator, pointer_type(generator));
			});
		}

		// An enum member of the field's enum type, by name.
		void member(std::string_view name, std::string_view member_name) {
			set(name, [&](TypeInfo* field_type) {
				auto enum_type = static_cast<TypeInfoEnum const*>(base(field_type));
				uint64_t value = 0;
				for (size_t i = 0; i < enum_type->members.size(); ++i) {
					if (text_of(enum_type->members[i]) == member_name) {
						value = enum_type->values[i];
					}
				}
				return constant_number(generator, field_type, value);
			});
		}

		// A view of count elements, each made by make from the element type and its index.
		void view(std::string_view name, size_t count, const std::function<mlir::Value(TypeInfo*, size_t)>& make) {
			set(name, [&](TypeInfo* field_type) {
				TypeInfo* element = static_cast<TypeInfoArray const*>(base(field_type))->element_type;
				return constant_view(generator, element, count, make);
			});
		}

		static mlir::Value constant_number(Generator& generator, TypeInfo* type, uint64_t value) {
			mlir::Type llvm = llvm_type(generator, type);
			const unsigned width = llvm.getIntOrFloatBitWidth();
			return LLVM::ConstantOp::create(generator.builder, generator.loc, llvm,
				generator.builder.getIntegerAttr(llvm, llvm::APInt(width, value)));
		}

		static mlir::Value constant_string(Generator& generator, const std::string& value) {
			return make_view(generator, constant_int(generator, usize_type(generator), static_cast<int64_t>(value.size())),
				string_bytes(generator, value));
		}

		static mlir::Value constant_view(Generator& generator, TypeInfo* element, size_t count,
			const std::function<mlir::Value(TypeInfo*, size_t)>& make) {

			mlir::Value data = zero_of(generator, pointer_type(generator));
			if (count > 0) {
				mlir::Type array = LLVM::LLVMArrayType::get(llvm_type(generator, element), count);
				data = constant_global(generator, array, std::max<size_t>(element->alignment, 1),
					std::format("type_info.data.{}", generator.type_data++), [&]() {
						mlir::Value elements = zero_of(generator, array);
						for (size_t i = 0; i < count; ++i) {
							elements = insert(generator, elements, make(element, i), { static_cast<int64_t>(i) });
						}
						return elements;
					});
			}
			return make_view(generator, constant_int(generator, usize_type(generator), static_cast<int64_t>(count)), data);
		}
	};

	static const char* variant_name(TypeInfoVariant variant) {
		switch (variant) {
			case TypeInfoVariant::ALIAS: return "ALIAS";
			case TypeInfoVariant::ANY: return "ANY";
			// Archetypes are only checked against, never generated
			case TypeInfoVariant::ARCHETYPE: return "VOID";
			case TypeInfoVariant::ARRAY: return "ARRAY";
			case TypeInfoVariant::BOOLEAN: return "BOOLEAN";
			case TypeInfoVariant::CHAR: return "CHAR";
			case TypeInfoVariant::COMPLEX: return "COMPLEX";
			case TypeInfoVariant::ENUM: return "ENUM";
			case TypeInfoVariant::FLOAT: return "FLOAT";
			case TypeInfoVariant::FUNCTION: return "FUNCTION";
			case TypeInfoVariant::INTEGER: return "INTEGER";
			case TypeInfoVariant::POINTER: return "POINTER";
			case TypeInfoVariant::QUATERNION: return "QUATERNION";
			case TypeInfoVariant::STRING: return "STRING";
			case TypeInfoVariant::STRUCT: return "STRUCT";
			case TypeInfoVariant::TYPE: return "TYPE";
			case TypeInfoVariant::UNION: return "UNION";
			case TypeInfoVariant::VECTOR: return "VECTOR";
			case TypeInfoVariant::VOID: return "VOID";
		}
		return "VOID";
	}

	static const char* endianness_name(Endianness endianness) {
		return Endianness::BIG == endianness ? "BIG" : Endianness::LITTLE == endianness ? "LITTLE" : "SYSTEM";
	}

	static const char* array_type_name(ArrayType array_type) {
		return ArrayType::STATIC == array_type ? "STATIC" : ArrayType::VIEW == array_type ? "VIEW" : "DYNAMIC";
	}

	// The base/compiler struct describing a type of this variant: TypeInfoEnum for an enum, and so on.
	static const char* descriptor_struct(TypeInfoVariant variant) {
		switch (variant) {
			case TypeInfoVariant::ALIAS: return "TypeInfoAlias";
			case TypeInfoVariant::ARRAY: return "TypeInfoArray";
			case TypeInfoVariant::ENUM: return "TypeInfoEnum";
			case TypeInfoVariant::FLOAT: return "TypeInfoFloat";
			case TypeInfoVariant::FUNCTION: return "TypeInfoFunction";
			case TypeInfoVariant::INTEGER: return "TypeInfoInteger";
			case TypeInfoVariant::POINTER: return "TypeInfoPointer";
			case TypeInfoVariant::STRING: return "TypeInfoString";
			case TypeInfoVariant::STRUCT: return "TypeInfoStruct";
			case TypeInfoVariant::UNION: return "TypeInfoUnion";
			case TypeInfoVariant::VECTOR: return "TypeInfoVector";
			case TypeInfoVariant::ANY:
			case TypeInfoVariant::ARCHETYPE:
			case TypeInfoVariant::BOOLEAN:
			case TypeInfoVariant::CHAR:
			case TypeInfoVariant::COMPLEX:
			case TypeInfoVariant::QUATERNION:
			case TypeInfoVariant::TYPE:
			case TypeInfoVariant::VOID:
				break;
		}
		return "TypeInfo";
	}

	// The fields particular to a type's variant, after variant and size.
	static void describe(Generator& generator, TypeInfo const* type, ConstantStruct& info) {
		switch (type->variant) {
			case TypeInfoVariant::VECTOR: {
				auto vector = static_cast<TypeInfoVector const*>(type);
				info.type_of("element_type", vector->element_type);
				info.number("count", vector->count);
				info.flag("is_bits", vector->is_bits);
				break;
			}
			case TypeInfoVariant::ALIAS: {
				auto alias = static_cast<TypeInfoAlias const*>(type);
				info.type_of("base_type", alias->base_type);
				info.text("name", name_or_empty(alias->name));
				info.flag("is_distinct", alias->distinct);
				break;
			}
			case TypeInfoVariant::ARRAY: {
				// Each dimension, outermost first, down to the first element type that isn't an array
				std::vector<TypeInfoArray const*> dimensions;
				TypeInfo const* element = type;
				while (element != nullptr && TypeInfoVariant::ARRAY == element->variant) {
					dimensions.push_back(static_cast<TypeInfoArray const*>(element));
					element = base(static_cast<TypeInfoArray const*>(element)->element_type);
				}
				info.type_of("base_type", dimensions.back()->element_type);
				info.view("dimensions", dimensions.size(), [&](TypeInfo* element_type, size_t i) {
					ConstantStruct dimension(generator, element_type);
					dimension.member("type", array_type_name(dimensions[i]->array_type));
					dimension.number("count", dimensions[i]->count);
					dimension.number("is_mutable", dimensions[i]->is_mutable);
					return dimension.whole;
				});
				break;
			}
			case TypeInfoVariant::ENUM: {
				auto enum_type = static_cast<TypeInfoEnum const*>(type);
				info.text("name", name_or_empty(enum_type->name));
				info.type_of("backing_type", enum_type->backing_type != nullptr ? enum_type->backing_type : BUILTIN_uint);
				info.view("members", enum_type->members.size(), [&](TypeInfo*, size_t i) {
					return ConstantStruct::constant_string(generator, text_of(enum_type->members[i]));
				});
				info.view("values", enum_type->values.size(), [&](TypeInfo* element_type, size_t i) {
					return ConstantStruct::constant_number(generator, element_type, enum_type->values[i]);
				});
				break;
			}
			case TypeInfoVariant::FLOAT:
				info.member("endianness", endianness_name(static_cast<TypeInfoFloat const*>(type)->endianness));
				break;
			case TypeInfoVariant::FUNCTION: {
				auto function = static_cast<TypeInfoFunction const*>(type);
				info.view("input", function->input.size(), [&](TypeInfo* element_type, size_t i) {
					const FunctionInput& input = function->input[i];
					ConstantStruct parameter(generator, element_type);
					parameter.type_of("type", input.type);
					parameter.text("name", name_or_empty(input.name));
					parameter.flag("is_varargs", input.is_varargs);
					parameter.flag("is_escaping", input.is_escaping);
					return parameter.whole;
				});
				info.view("output", function->output.size(), [&](TypeInfo* element_type, size_t i) {
					ConstantStruct output(generator, element_type);
					output.type_of("type", function->output[i].type);
					return output.whole;
				});
				info.flag("never_returns", function->never_returns);
				break;
			}
			case TypeInfoVariant::INTEGER: {
				auto integer = static_cast<TypeInfoInteger const*>(type);
				info.flag("is_signed", integer->is_signed);
				info.member("endianness", endianness_name(integer->endianness));
				break;
			}
			case TypeInfoVariant::POINTER: {
				auto pointer = static_cast<TypeInfoPointer const*>(type);
				info.type_of("base_type", pointer->base_type);
				info.flag("is_relative", pointer->is_relative);
				info.flag("is_mutable", pointer->is_mutable);
				break;
			}
			case TypeInfoVariant::STRING:
				info.flag("is_raw", static_cast<TypeInfoString const*>(type)->is_raw);
				break;
			case TypeInfoVariant::STRUCT: {
				auto structure = static_cast<TypeInfoStruct const*>(type);
				info.text("name", name_or_empty(structure->name));
				//TODO(claude) members' default values, which need constants of any type
				info.view("members", structure->members.size(), [&](TypeInfo* element_type, size_t i) {
					const StructMember& member = structure->members[i];
					ConstantStruct described(generator, element_type);
					described.text("name", name_or_empty(member.name));
					described.type_of("member_type", member.member_type);
					described.number("offset", member.offset);
					described.flag("has_value", member.has_value);
					described.flag("is_using", member.is_using);
					return described.whole;
				});
				info.number("alignment", type->alignment);
				info.flag("is_scoped", structure->is_scoped);
				info.flag("is_unrestricted", structure->is_unrestricted);
				info.flag("is_packed", structure->is_packed);
				info.flag("is_union", structure->is_union);
				break;
			}
			case TypeInfoVariant::UNION: {
				auto union_type = static_cast<TypeInfoUnion const*>(type);
				info.text("name", name_or_empty(union_type->name));
				info.view("variants", union_type->variants.size(), [&](TypeInfo* element_type, size_t i) {
					const UnionVariant& variant = union_type->variants[i];
					ConstantStruct described(generator, element_type);
					described.text("name", name_or_empty(variant.name));
					described.view("types", variant.types.size(), [&](TypeInfo*, size_t j) {
						return type_descriptor(generator, variant.types[j]);
					});
					described.view("offsets", variant.offsets.size(), [&](TypeInfo* offset_type, size_t j) {
						return ConstantStruct::constant_number(generator, offset_type, variant.offsets[j]);
					});
					return described.whole;
				});
				info.type_of("tag_type", union_type->null_is_none ? nullptr : union_type->tag_type);
				info.flag("null_is_none", union_type->null_is_none);
				break;
			}
			// Only a variant and a size
			case TypeInfoVariant::ANY:
			case TypeInfoVariant::ARCHETYPE:
			case TypeInfoVariant::BOOLEAN:
			case TypeInfoVariant::CHAR:
			case TypeInfoVariant::COMPLEX:
			case TypeInfoVariant::QUATERNION:
			case TypeInfoVariant::TYPE:
			case TypeInfoVariant::VOID:
				break;
		}
	}

	/*
	 * The address of a type's descriptor, made the first time it's asked for: a read-only TypeInfo,
	 * or the struct for its variant that includes one, like a TypeInfoEnum. A type value is this
	 * address, so two type values are equal when they're the same type. A plain alias is the type
	 * it names; a distinct one has its own descriptor, and so does a generic argument given with mut,
	 * so a constraint can tell, like compiler.Mutable.
	 */
	static mlir::Value type_descriptor(Generator& generator, TypeInfo const* type) {
		if (type == nullptr || !(TypeInfoVariant::ALIAS == type->variant && static_cast<const TypeInfoAlias*>(type)->mutable_argument)) {
			type = get_base_type_or_alias(type);
		}
		auto iter = generator.descriptors.find(type);
		if (iter != generator.descriptors.end()) {
			return LLVM::AddressOfOp::create(generator.builder, generator.loc, iter->second);
		}
		// Compile-time code uses the compiler's descriptors, so a type from reflection equals the same type here
		if (generator.compile_time) {
			const uint8_t* described = compile_time_data(generator.program).descriptor(type);
			if (described == nullptr) {
				unsupported(generator, nullptr, std::format("base/compiler isn't laid out yet, for {}'s type information", to_string(type)));
				return zero_of(generator, pointer_type(generator));
			}
			const std::string symbol = std::format("hemera.type.{}", generator.descriptors.size());
			LLVM::GlobalOp global;
			{
				mlir::OpBuilder::InsertionGuard guard(generator.builder);
				generator.builder.setInsertionPointToEnd(generator.module.getBody());
				global = LLVM::GlobalOp::create(generator.builder, generator.loc, integer_type(generator, 1), true,
					LLVM::Linkage::External, symbol, mlir::Attribute(), 8);
			}
			generator.descriptors[type] = global;
			generator.compile_time_symbols.emplace_back(symbol, described);
			return LLVM::AddressOfOp::create(generator.builder, generator.loc, global);
		}
		Declaration* declaration = base_declaration_named(generator, "compiler", descriptor_struct(type->variant));
		TypeInfo* descriptor_type = declaration != nullptr ? declaration->type_value : nullptr;
		if (descriptor_type == nullptr || !descriptor_type->complete || TypeInfoVariant::STRUCT != descriptor_type->variant) {
			unsupported(generator, nullptr, std::format("compiler.{} isn't available for type information",
				descriptor_struct(type->variant)));
			return zero_of(generator, pointer_type(generator));
		}
		mlir::Type llvm = llvm_type(generator, descriptor_type);
		LLVM::GlobalOp global;
		{
			mlir::OpBuilder::InsertionGuard guard(generator.builder);
			generator.builder.setInsertionPointToEnd(generator.module.getBody());
			global = LLVM::GlobalOp::create(generator.builder, generator.loc, llvm, true,
				generator.compile_time ? LLVM::Linkage::External : LLVM::Linkage::Private,
				std::format("type_info.{}", generator.descriptors.size()), mlir::Attribute(),
				std::max<size_t>(descriptor_type->alignment, 1));
			// Before its value, which may refer to it, like a struct with a pointer to its own type
			generator.descriptors[type] = global;
			generator.builder.setInsertionPointToStart(generator.builder.createBlock(&global.getInitializerRegion()));
			FunctionState* outer = generator.state;
			generator.state = nullptr;
			ConstantStruct info(generator, descriptor_type);
			info.member("variant", variant_name(type->variant));
			info.number("size", type->size);
			describe(generator, type, info);
			generator.state = outer;
			LLVM::ReturnOp::create(generator.builder, generator.loc, info.whole);
		}
		return LLVM::AddressOfOp::create(generator.builder, generator.loc, global);
	}

	/*
	 * The using pointer field a member is reached through, when the struct has no member of that name
	 * itself (docs/types.md, Structs): its index in the struct.
	 */
	static bool forwarding_member(Generator& generator, TypeInfoStruct const* structure, InternedString name, size_t& index) {
		for (size_t i = 0; i < structure->members.size(); ++i) {
			const StructMember& member = structure->members[i];
			TypeInfo const* used = base(member.member_type);
			if (!member.is_using || member.name == nullptr || used == nullptr || TypeInfoVariant::POINTER != used->variant) {
				continue;
			}
			TypeInfo const* pointed = base(static_cast<TypeInfoPointer const*>(used)->base_type);
			if (pointed == nullptr || TypeInfoVariant::STRUCT != pointed->variant) {
				continue;
			}
			auto target = static_cast<TypeInfoStruct const*>(pointed);
			size_t offset = 0;
			TypeInfo* found_type = nullptr;
			std::vector<int64_t> path;
			size_t inner = 0;
			if (find_member(generator, target, name, offset, found_type, path) || forwarding_member(generator, target, name, inner)) {
				index = i;
				return true;
			}
		}
		return false;
	}

	static Emitted emit_member_named(Generator& generator, Emitted current, InternedString name, TypeInfo* result_type);

	// .member on a value: a struct's field, through a pointer automatically, or a count or data.
	static Emitted emit_member(Generator& generator, Emitted current, ast::Node* name_node, const CheckedNode* found) {
		return emit_member_named(generator, current, name_node->value.value, found->type);
	}

	static Emitted emit_member_named(Generator& generator, Emitted current, InternedString name, TypeInfo* result_type) {
		TypeInfo const* type = base(current.type);
		if (TypeInfoVariant::POINTER == type->variant) {
			auto pointer = static_cast<TypeInfoPointer const*>(type);
			current = location(value_of(generator, current), pointer->base_type);
			type = base(pointer->base_type);
		}
		if (TypeInfoVariant::STRUCT == type->variant) {
			size_t offset = 0;
			TypeInfo* member_type = result_type;
			std::vector<int64_t> path;
			auto structure = static_cast<TypeInfoStruct const*>(type);
			if (!find_member(generator, structure, name, offset, member_type, path)) {
				// Through a using pointer field: the field, then the member of what it points to
				size_t index = 0;
				if (forwarding_member(generator, structure, name, index)) {
					const StructMember& forwarding = structure->members[index];
					Emitted pointer = emit_member_named(generator, current, forwarding.name, forwarding.member_type);
					return emit_member_named(generator, pointer, name, result_type);
				}
			}
			const bool through_union = std::find(path.begin(), path.end(), -1) != path.end();
			if (!current.address && !through_union) {
				// A value: its part
				return value(LLVM::ExtractValueOp::create(generator.builder, generator.loc, current.value, path), member_type);
			}
			return location(offset_address(generator, address_of(generator, current), offset), member_type);
		}
		const std::string member = text_of(name);
		if (TypeInfoVariant::ARRAY == type->variant && ArrayType::STATIC == static_cast<TypeInfoArray const*>(type)->array_type) {
			return value(constant_int(generator, usize_type(generator),
				static_cast<int64_t>(static_cast<TypeInfoArray const*>(type)->count)), BUILTIN_usize);
		}
		mlir::Value whole = value_of(generator, current);
		if (TypeInfoVariant::ANY == type->variant) {
			return value(extract(generator, whole, member == "data" ? 0 : 1), result_type);
		}
		// count, data and capacity are the first, second and third parts
		const int64_t part = member == "data" ? 1 : member == "capacity" ? 2 : 0;
		return value(extract(generator, whole, part), result_type);
	}

	// Where an array's or string's elements are, and how many.
	static void elements_of(Generator& generator, Emitted& current, TypeInfo const*& type, mlir::Value& data, mlir::Value& count) {
		if (TypeInfoVariant::POINTER == type->variant) {
			auto pointer = static_cast<TypeInfoPointer const*>(type);
			current = location(value_of(generator, current), pointer->base_type);
			type = base(pointer->base_type);
		}
		if (TypeInfoVariant::ARRAY == type->variant && ArrayType::STATIC == static_cast<TypeInfoArray const*>(type)->array_type) {
			data = address_of(generator, current);
			count = constant_int(generator, usize_type(generator), static_cast<int64_t>(static_cast<TypeInfoArray const*>(type)->count));
			return;
		}
		// A vector's lanes are laid out like an array's elements
		if (TypeInfoVariant::VECTOR == type->variant) {
			data = address_of(generator, current);
			count = constant_int(generator, usize_type(generator), static_cast<int64_t>(static_cast<TypeInfoVector const*>(type)->count));
			return;
		}
		mlir::Value whole = value_of(generator, current);
		if (TypeInfoVariant::STRING == type->variant && static_cast<TypeInfoString const*>(type)->is_raw) {
			data = whole;
			count = constant_int(generator, usize_type(generator), 0);
			return;
		}
		count = extract(generator, whole, 0);
		data = extract(generator, whole, 1);
	}

	static TypeInfo* element_of(TypeInfo const* type) {
		if (TypeInfoVariant::VECTOR == type->variant) {
			return static_cast<TypeInfoVector const*>(type)->element_type;
		}
		return TypeInfoVariant::ARRAY == type->variant ? static_cast<TypeInfoArray const*>(type)->element_type : BUILTIN_char;
	}

	// [index] or [low..<high]: an element, or a view of several.
	static Emitted emit_index(Generator& generator, Emitted current, ast::Node* index, const CheckedNode* found) {
		TypeInfo const* type = base(current.type);
		mlir::Value data;
		mlir::Value count;
		elements_of(generator, current, type, data, count);
		TypeInfo* element = element_of(type);
		const TokenType op = index->value.type;
		const bool range = ast::NodeType::BINARY_OPERATOR == index->node_type
			&& (TokenType::OPERATOR_RANGE_EXCLUSIVE == op || TokenType::OPERATOR_RANGE_INCLUSIVE == op);
		if (range || ast::NodeType::RANGE_ARRAY == index->node_type) {
			mlir::Value low = constant_int(generator, usize_type(generator), 0);
			mlir::Value high = count;
			if (range && index->children.size() == 2) {
				if (ast::NodeType::RANGE_ARRAY != index->children[0]->node_type) {
					low = emit_as(generator, index->children[0], BUILTIN_usize);
				}
				if (ast::NodeType::RANGE_ARRAY != index->children[1]->node_type) {
					high = emit_as(generator, index->children[1], BUILTIN_usize);
					if (TokenType::OPERATOR_RANGE_INCLUSIVE == op) {
						high = LLVM::AddOp::create(generator.builder, generator.loc, high,
							constant_int(generator, usize_type(generator), 1));
					}
				}
			}
			mlir::Value start = element_address(generator, data, element, low);
			return value(make_view(generator, LLVM::SubOp::create(generator.builder, generator.loc, high, low), start), found->type);
		}
		mlir::Value position = emit_as(generator, index, BUILTIN_usize);
		return location(element_address(generator, data, element, position), element);
	}

	// ---------------------------------------------------------------------------------------------
	// Calls

	static bool is_postfix_marker(const ast::Node* node) {
		return ast::NodeType::DOT_ACCESS == node->node_type
			|| ast::NodeType::PAREN_GROUP == node->node_type
			|| ast::NodeType::ARRAY_DIMENSION == node->node_type
			|| (ast::NodeType::UNARY_OPERATOR == node->node_type
				&& TokenType::OPERATOR_DEREFERENCE == node->value.type);
	}

	static bool is_placeholder(const ast::Node* node) {
		return ast::NodeType::UNDERSCORE == node->node_type
			|| ast::NodeType::PIPE_REORDER_IDENTIFIER == node->node_type;
	}

	// Each parameter's name and default value, in order, from a function's FUNCTION node.
	struct ParameterNode {
		InternedString name = nullptr;
		ast::Node* default_value = nullptr;
	};

	static std::vector<ParameterNode> parameter_nodes(Declaration* function) {
		std::vector<ParameterNode> result;
		if (function == nullptr) {
			return result;
		}
		Declaration* generic = function->generic != nullptr ? function->generic : function;
		ast::Node* node = nullptr;
		for (ast::Node* child : generic->node->children) {
			if (ast::NodeType::FUNCTION == child->node_type) {
				node = child;
			}
		}
		if (node == nullptr) {
			return result;
		}
		for (ast::Node* list : node->children) {
			if (ast::NodeType::LIST != list->node_type) {
				continue;
			}
			for (ast::Node* parameter : list->children) {
				const bool has_default = ast::NodeType::BINARY_OPERATOR == parameter->node_type && is_assign(parameter)
					&& parameter->children.size() == 2;
				ast::Node* names_node = has_default ? parameter->children[0] : parameter;
				ast::Node* default_value = has_default ? parameter->children[1] : nullptr;
				if (ast::NodeType::COLON != names_node->node_type) {
					result.push_back({ nullptr, default_value });
					continue;
				}
				for (ast::Node* part : names_node->children) {
					if (ast::NodeType::IDENTIFIER == part->node_type) {
						result.push_back({ part->value.value, default_value });
						break;
					}
					if (ast::NodeType::LIST == part->node_type) {
						for (ast::Node* name : part->children) {
							result.push_back({ name->value.value, default_value });
						}
						break;
					}
				}
			}
			break;
		}
		return result;
	}

	// #caller_location: where the call is (runtime.SourceCodeLocation).
	static mlir::Value caller_location(Generator& generator, TypeInfo* type, const ast::Node* call) {
		mlir::Value result = zero_of(generator, llvm_type(generator, type));
		auto structure = static_cast<TypeInfoStruct const*>(base(type));
		const std::string file = current_file(generator);
		const std::string function = generator.state->declaration != nullptr ? text_of(generator.state->declaration->name) : std::string();
		for (const StructMember& member : structure->members) {
			size_t offset = 0;
			TypeInfo* member_type = nullptr;
			std::vector<int64_t> path;
			find_member(generator, structure, member.name, offset, member_type, path);
			const std::string name = text_of(member.name);
			mlir::Value part;
			if (name == "file_path") {
				part = string_value(generator, file, member.member_type);
			}
			else if (name == "function") {
				part = string_value(generator, function, member.member_type);
			}
			else if (name == "line" || name == "column") {
				part = constant_int(generator, llvm_type(generator, member.member_type),
					static_cast<int64_t>(name == "line" ? call->value.line_number : call->value.column_number));
			}
			if (part) {
				result = LLVM::InsertValueOp::create(generator.builder, generator.loc, result, part, path);
			}
		}
		return result;
	}

	/*
	 * A check generated code makes that failed, like a relative pointer set too far away: context.assertion_handler,
	 * with where and what, which ends the program; or without a context, a trap. Never returns.
	 */
	static void fail_check(Generator& generator, const ast::Node* where, const std::string& message) {
		mlir::OpBuilder& b = generator.builder;
		const mlir::Location l = generator.loc;
		Declaration* handler_type = base_declaration_named(generator, "runtime", "AssertionHandler");
		size_t offset = 0;
		TypeInfoFunction const* function = handler_type != nullptr && handler_type->type_value != nullptr
			&& is_variant(handler_type->type_value, TypeInfoVariant::FUNCTION)
			? static_cast<TypeInfoFunction const*>(base(handler_type->type_value)) : nullptr;
		if (generator.state == nullptr || !generator.state->context || function == nullptr || function->input.size() != 2
			|| where == nullptr || !runtime_offset(generator, "Context", "assertion_handler", offset)) {
			LLVM::Trap::create(b, l);
			LLVM::UnreachableOp::create(b, l);
			return;
		}
		mlir::Value handler = LLVM::LoadOp::create(b, l, pointer_type(generator), offset_address(generator, generator.state->context, offset));
		std::vector<mlir::Value> operands{ handler, generator.state->context };
		const mlir::Value parts[] = { caller_location(generator, function->input[0].type, where),
			string_value(generator, message, function->input[1].type) };
		for (size_t i = 0; i < 2; ++i) {
			const FunctionInput& input = function->input[i];
			if (parameter_by_pointer(function, input)) {
				mlir::Value slot = make_slot(generator, input.type);
				store(generator, parts[i], slot);
				operands.push_back(slot);
				continue;
			}
			operands.push_back(parts[i]);
		}
		auto call = LLVM::CallOp::create(b, l, function_type(generator, function, true), operands);
		call.setCConv(convention_of(generator, function));
		LLVM::UnreachableOp::create(b, l);
	}

	/*
	 * A parameter's default (docs/functions.md): only simple ones for now, a literal, a constant,
	 * #caller_location, or the context's fields.
	 */
	static Emitted emit_struct_literal(Generator& generator, ast::Node* node, TypeInfo* type);

	/*
	 * The default comes from the function type the call was checked against: a function's own, with what
	 * it inherits from a type it states, or, for a call through a value, the value's type's (docs/functions.md,
	 * Defaults in Function Types).
	 */
	static mlir::Value emit_default(Generator& generator, Declaration* callee, const FunctionInput& input, size_t index, TypeInfo* type,
		ast::Node* call) {
		ast::Node* node = input.default_value;
		InternedString package = input.default_package;
		if (node == nullptr) {
			const std::vector<ParameterNode> parameters = parameter_nodes(callee);
			node = index < parameters.size() ? parameters[index].default_value : nullptr;
			package = nullptr;
		}
		if (package == nullptr && callee != nullptr) {
			package = (callee->generic != nullptr ? callee->generic : callee)->package_path;
		}
		if (node == nullptr) {
			unsupported(generator, call, "a call that leaves out a parameter without a default");
			return zero_of(generator, llvm_type(generator, type));
		}
		const ast::NodeType kind = node->node_type;
		if (ast::NodeType::LITERAL == kind) {
			const bool held = is_variant(type, TypeInfoVariant::UNION) && TokenType::KEYWORD_NULL != node->value.type;
			mlir::Value literal = emit_literal(generator, node, held ? held_type(type) : type);
			return held ? convert(generator, literal, held_type(type), type) : literal;
		}
		if (ast::NodeType::DIRECTIVE == kind && is_text(node->value.value, "#caller_location")) {
			return caller_location(generator, type, call);
		}
		// .member: an enum's member, or a union's variant without values, like .None
		if (ast::NodeType::ENUM_SHORTHAND == kind && node->children.empty()) {
			if (is_variant(type, TypeInfoVariant::ENUM)) {
				return constant_int(generator, llvm_type(generator, type), enum_value(type, node->value.value));
			}
			if (is_variant(type, TypeInfoVariant::UNION)) {
				return make_variant(generator, type, variant_named(type, std::string_view(*node->value.value)), {}, {});
			}
		}
		// Type.{} or .{}: zero, but for the struct's defaults
		if (ast::NodeType::STRUCT_LITERAL == kind && is_variant(type, TypeInfoVariant::STRUCT)) {
			bool empty = true;
			for (ast::Node* child : node->children) {
				empty = empty && !(ast::NodeType::LIST == child->node_type && !child->children.empty());
			}
			if (empty) {
				return value_of(generator, emit_struct_literal(generator, node, type));
			}
		}
		if (ast::NodeType::IDENTIFIER == kind && is_text(node->value.value, "context")) {
			// context.field...: read through the current context
			Declaration* context_declaration = base_declaration_named(generator, "runtime", "Context");
			Emitted current = location(generator.state->context, context_declaration != nullptr ? context_declaration->type_value : nullptr);
			for (size_t i = 0; i + 1 < node->children.size() && current.type != nullptr; i += 2) {
				size_t offset = 0;
				TypeInfo* member_type = nullptr;
				std::vector<int64_t> path;
				if (!is_variant(current.type, TypeInfoVariant::STRUCT)
					|| !find_member(generator, static_cast<TypeInfoStruct const*>(base(current.type)), node->children[i + 1]->value.value,
						offset, member_type, path)) {
					break;
				}
				current = location(offset_address(generator, current.address, offset), member_type);
			}
			return convert_emitted(generator, current, type);
		}
		if (ast::NodeType::IDENTIFIER == kind && node->children.empty()) {
			// A constant from the package the default was written in
			Declaration* constant = nullptr;
			{
				std::scoped_lock<std::mutex> lock(generator.names.mutex);
				auto iter = generator.names.declarations.find(std::make_pair(package, node->value.value));
				if (iter != generator.names.declarations.end()) {
					constant = iter->second;
				}
			}
			if (constant != nullptr && constant->value_type == nullptr && constant->untyped != Untyped::NONE) {
				return emit_constant_value(generator, constant, type, call);
			}
			if (constant != nullptr && constant->value_type != nullptr && DeclarationKind::VALUE == constant->kind) {
				LLVM::GlobalOp global = global_for(generator, constant);
				return convert(generator, load(generator, constant->value_type,
					LLVM::AddressOfOp::create(generator.builder, generator.loc, global)), constant->value_type, type);
			}
		}
		/*
		 * Anything else, as checking found it, here in the caller, with the caller's context: a function
		 * type's on its own (check_type_default), a function's with its body (check_parameter_defaults)
		 */
		if (node != nullptr && !input.default_in_body) {
			std::shared_ptr<CheckedBody> checked;
			{
				std::scoped_lock<std::mutex> lock(generator.names.type_defaults_mutex);
				auto found = generator.names.type_defaults.find(node);
				if (found != generator.names.type_defaults.end()) {
					checked = found->second;
				}
			}
			if (checked != nullptr) {
				FunctionState& state = *generator.state;
				CheckedBody* outer = state.checked;
				state.checked = checked.get();
				mlir::Value result = emit_as(generator, node, type);
				state.checked = outer;
				return result;
			}
		}
		if (callee != nullptr && callee->checked != nullptr && callee->checked->nodes.contains(node)) {
			FunctionState& state = *generator.state;
			CheckedBody* outer = state.checked;
			state.checked = callee->checked.get();
			mlir::Value result = emit_as(generator, node, type);
			state.checked = outer;
			return result;
		}
		unsupported(generator, call, "this call leaves out a parameter whose default can't be generated yet");
		return zero_of(generator, llvm_type(generator, type));
	}

	struct CallArgument {
		ast::Node* node = nullptr;
		bool has_value = false;
		Emitted given;
	};

	static mlir::Value argument_as(Generator& generator, const CallArgument& argument, TypeInfo* type) {
		if (argument.has_value) {
			return convert_emitted(generator, argument.given, type);
		}
		return emit_as(generator, argument.node, type);
	}

	/*
	 * An argument for a parameter too large for registers: a copy in a slot of the caller's, made from where
	 * the argument is if it's in memory, whose address is passed (docs/calling_convention.md, Large Values).
	 */
	static mlir::Value argument_copy(Generator& generator, const Emitted& given, TypeInfo* type) {
		mlir::Value slot = make_slot(generator, type);
		if (ValueKind::VARIANT == given.kind) {
			store(generator, make_variant(generator, given.type, given.variant, {}, {}), slot);
			return slot;
		}
		store_emitted(generator, given, type, slot);
		return slot;
	}

	static mlir::Value argument_copy(Generator& generator, const CallArgument& argument, TypeInfo* type) {
		return argument_copy(generator, argument.has_value ? argument.given : emit_expression(generator, argument.node, type), type);
	}

	static mlir::Value value_copy(Generator& generator, mlir::Value value, TypeInfo* type) {
		mlir::Value slot = make_slot(generator, type);
		store(generator, value, slot);
		return slot;
	}

	// Where a call's results go when they're too large for registers: a slot of the caller's, passed first.
	static mlir::Value results_slot(Generator& generator, TypeInfoFunction const* function) {
		size_t alignment = 1;
		for (const FunctionOutput& output : function->output) {
			alignment = std::max(alignment, output.type != nullptr ? output.type->alignment : 1);
		}
		return make_raw_slot(generator, results_type(generator, function), alignment);
	}

	/*
	 * What a call gives, from the call or from its results' slot: one result where it is, rather than loaded
	 * whole, or several as a struct of them.
	 */
	static Emitted call_results(Generator& generator, TypeInfoFunction const* function, LLVM::CallOp call, mlir::Value slot) {
		Emitted result;
		result.never_returns = function->never_returns;
		if (function->output.empty()) {
			return result;
		}
		if (slot && function->output.size() == 1) {
			result = location(slot, function->output[0].type);
			result.never_returns = function->never_returns;
			return result;
		}
		result.kind = ValueKind::VALUE;
		result.value = slot ? static_cast<mlir::Value>(LLVM::LoadOp::create(generator.builder, generator.loc,
			results_type(generator, function), slot)) : call.getResult();
		if (function->output.size() == 1) {
			result.type = function->output[0].type;
		}
		else {
			result.kind = ValueKind::RESULTS;
			for (const FunctionOutput& output : function->output) {
				result.results.push_back(output.type);
			}
		}
		return result;
	}

	static Emitted never_returning() {
		Emitted result;
		result.never_returns = true;
		return result;
	}

	// A builtin function's call: size_of, align_of, offset_of, todo.
	static Emitted emit_builtin_call(Generator& generator, ast::Node* paren, const std::vector<ast::Node*>& arguments,
		const Emitted& callee) {

		const std::string name = text_of(callee.name);
		if (name == "todo") {
			LLVM::Trap::create(generator.builder, generator.loc);
			return never_returning();
		}
		if ((name == "type_info_of" || name == "type_of") && arguments.size() == 1) {
			// A type's descriptor, without evaluating a value whose type it is; a type value is its address already
			TypeInfo* result_type = type_at(generator, paren, nullptr);
			const CheckedNode* found = checked(generator, arguments[0]);
			if (found != nullptr && (ValueKind::TYPE == found->kind || name == "type_of")) {
				return value(type_descriptor(generator, found->type), result_type);
			}
			return value(value_of(generator, emit_expression(generator, arguments[0], nullptr)), result_type);
		}
		if ((name == "size_of" || name == "align_of" || name == "offset_of") && !arguments.empty()) {
			TypeInfo const* of = emit_expression(generator, arguments[0], nullptr).type;
			int64_t number = 0;
			if (of != nullptr && name == "size_of") {
				number = static_cast<int64_t>(of->size);
			}
			else if (of != nullptr && name == "align_of") {
				number = static_cast<int64_t>(of->alignment);
			}
			else if (of != nullptr && arguments.size() == 2 && is_variant(of, TypeInfoVariant::STRUCT)) {
				size_t offset = 0;
				TypeInfo* member_type = nullptr;
				std::vector<int64_t> path;
				find_member(generator, static_cast<TypeInfoStruct const*>(base(of)), arguments[1]->value.value, offset, member_type, path);
				number = static_cast<int64_t>(offset);
			}
			return value(constant_int(generator, usize_type(generator), number), BUILTIN_usize);
		}
		/*
		 * The most or least an integer, character or float type holds: for a float, its largest finite
		 * value, and the most negative one
		 */
		if ((name == "max_value" || name == "min_value") && arguments.size() == 1) {
			TypeInfo* of = emit_expression(generator, arguments[0], nullptr).type;
			const bool most = name == "max_value";
			mlir::Type type = of != nullptr ? llvm_type(generator, of) : mlir::Type();
			if (of != nullptr && (is_variant(of, TypeInfoVariant::INTEGER) || is_variant(of, TypeInfoVariant::CHAR)) && type.isInteger()) {
				const unsigned bits = type.getIntOrFloatBitWidth();
				const bool is_signed = is_variant(of, TypeInfoVariant::INTEGER) && static_cast<TypeInfoInteger const*>(base(of))->is_signed;
				const llvm::APInt limit = is_signed ? (most ? llvm::APInt::getSignedMaxValue(bits) : llvm::APInt::getSignedMinValue(bits))
					: (most ? llvm::APInt::getMaxValue(bits) : llvm::APInt::getMinValue(bits));
				return value(LLVM::ConstantOp::create(generator.builder, generator.loc, type, generator.builder.getIntegerAttr(type, limit)), of);
			}
			if (of != nullptr && is_float(of)) {
				auto float_type = llvm::cast<mlir::FloatType>(type);
				const llvm::APFloat limit = llvm::APFloat::getLargest(float_type.getFloatSemantics(), !most);
				return value(LLVM::ConstantOp::create(generator.builder, generator.loc, type, generator.builder.getFloatAttr(type, limit)), of);
			}
			unsupported(generator, paren, std::format("{} of {} can't be generated yet", name, of != nullptr ? to_string(of) : "this"));
			TypeInfo* placeholder = of != nullptr ? of : BUILTIN_int;
			return value(zero_of(generator, llvm_type(generator, placeholder)), placeholder);
		}
		unsupported(generator, paren, std::format("{} can't be generated yet", name));
		return value(zero_of(generator, usize_type(generator)), BUILTIN_usize);
	}

	// ---------------------------------------------------------------------------------------------
	// Intrinsics: declarations without a body in base, which compile to instructions

	// The ordering an atomic's name ends with, which is taken off it: none is sequentially consistent.
	static LLVM::AtomicOrdering ordering_suffix(std::string_view& name) {
		const std::pair<std::string_view, LLVM::AtomicOrdering> suffixes[] = {
			{ "_acquire_release", LLVM::AtomicOrdering::acq_rel },
			{ "_acquire", LLVM::AtomicOrdering::acquire },
			{ "_release", LLVM::AtomicOrdering::release },
			{ "_no_fence", LLVM::AtomicOrdering::monotonic },
			{ "_sequentially_consistent", LLVM::AtomicOrdering::seq_cst },
		};
		for (const auto& [suffix, ordering] : suffixes) {
			if (name.ends_with(suffix)) {
				name.remove_suffix(suffix.size());
				return ordering;
			}
		}
		return LLVM::AtomicOrdering::seq_cst;
	}

	// What a compare-exchange that fails orders: no release, since it stores nothing.
	static LLVM::AtomicOrdering failure_ordering(LLVM::AtomicOrdering ordering) {
		return LLVM::AtomicOrdering::acq_rel == ordering ? LLVM::AtomicOrdering::acquire
			: LLVM::AtomicOrdering::release == ordering ? LLVM::AtomicOrdering::monotonic
			: ordering;
	}

	// One instruction, or a few, as inline assembly (AT&T syntax), which the optimizer keeps.
	static mlir::Value assembly(Generator& generator, mlir::Type result, const std::vector<mlir::Value>& operands,
		std::string_view text, std::string_view constraints) {

		auto op = LLVM::InlineAsmOp::create(generator.builder, generator.loc, result, operands, text, constraints, true, false,
			LLVM::tailcallkind::TailCallKind::None, LLVM::AsmDialectAttr(), mlir::ArrayAttr());
		return result ? static_cast<mlir::Value>(op.getRes()) : mlir::Value();
	}

	// Memcheck's requests (valgrind/memcheck.h): ('M' << 24 | 'C' << 16) + 1 and + 2.
	constexpr int64_t MEMCHECK_MAKE_MEM_UNDEFINED = 0x4d43'0001;
	constexpr int64_t MEMCHECK_MAKE_MEM_DEFINED = 0x4d43'0002;

	/*
	 * A Valgrind client request about size bytes at address (valgrind.h, amd64): rax points at the
	 * request and its five arguments, and four rotations of rdi that come to nothing, then xchg of rbx
	 * with itself, are what Valgrind looks for. Outside Valgrind, nothing happens.
	 */
	static void valgrind_request(Generator& generator, int64_t request, mlir::Value address, size_t size) {
		mlir::OpBuilder& b = generator.builder;
		const mlir::Location l = generator.loc;
		mlir::Type i64 = integer_type(generator, 8);
		mlir::Value arguments = make_raw_slot(generator, LLVM::LLVMArrayType::get(i64, 6), 8);
		const mlir::Value words[6] = { constant_int(generator, i64, request), LLVM::PtrToIntOp::create(b, l, i64, address),
			constant_int(generator, i64, static_cast<int64_t>(size)), constant_int(generator, i64, 0), constant_int(generator, i64, 0),
			constant_int(generator, i64, 0) };
		for (size_t i = 0; i < 6; ++i) {
			LLVM::StoreOp::create(b, l, words[i], offset_address(generator, arguments, 8 * i));
		}
		assembly(generator, i64, { arguments, constant_int(generator, i64, 0) },
			"rolq $$3, %rdi; rolq $$13, %rdi; rolq $$61, %rdi; rolq $$51, %rdi; xchgq %rbx, %rbx",
			"={dx},{ax},0,~{cc},~{memory}");
	}

	// Two 32-bit halves, like edx:eax, as one 64-bit value.
	static mlir::Value join_halves(Generator& generator, mlir::Value low, mlir::Value high) {
		mlir::Type i64 = integer_type(generator, 8);
		mlir::Value wide_low = LLVM::ZExtOp::create(generator.builder, generator.loc, i64, low);
		mlir::Value wide_high = LLVM::ZExtOp::create(generator.builder, generator.loc, i64, high);
		mlir::Value shifted = LLVM::ShlOp::create(generator.builder, generator.loc, wide_high, constant_int(generator, i64, 32));
		return LLVM::OrOp::create(generator.builder, generator.loc, shifted, wide_low);
	}

	static mlir::Value low_half(Generator& generator, mlir::Value v) {
		return LLVM::TruncOp::create(generator.builder, generator.loc, integer_type(generator, 4), v);
	}

	static mlir::Value high_half(Generator& generator, mlir::Value v) {
		mlir::Value shifted = LLVM::LShrOp::create(generator.builder, generator.loc, v, constant_int(generator, v.getType(), 32));
		return LLVM::TruncOp::create(generator.builder, generator.loc, integer_type(generator, 4), shifted);
	}

	// Two 32-bit results of one instruction, like rdmsr's edx:eax, joined.
	static mlir::Value pair_result(Generator& generator, const std::vector<mlir::Value>& operands, std::string_view text,
		std::string_view constraints) {

		mlir::Type i32 = integer_type(generator, 4);
		mlir::Value both = assembly(generator, LLVM::LLVMStructType::getLiteral(generator.context, { i32, i32 }), operands,
			text, constraints);
		return join_halves(generator, extract(generator, both, 0), extract(generator, both, 1));
	}

	static Emitted intrinsic_value(mlir::Value v, TypeInfoFunction const* function) {
		return value(v, function->output.empty() ? nullptr : function->output[0].type);
	}

	struct PortAccess {
		std::string_view name;
		std::string_view instruction;
		std::string_view constraints;
		size_t bytes;
	};

	/*
	 * An AArch64 instruction (base/intrinsics/aarch64). Returns false for a name that isn't one of them, or
	 * isn't generated yet.
	 */
	// A system register's name as the assembler takes any of them, from its encoding (aarch64.SystemRegister).
	static std::string system_register_name(uint64_t encoding) {
		return std::format("s{}_{}_c{}_c{}_{}", (encoding >> 14) & 3, (encoding >> 11) & 7, (encoding >> 7) & 15,
			(encoding >> 3) & 15, encoding & 7);
	}

	/*
	 * An AArch64 instruction (base/intrinsics/aarch64), with what's encoded in it from the compile-time
	 * arguments called was instantiated with. Returns false for a name that isn't one of them.
	 */
	static bool emit_aarch64(Generator& generator, std::string_view name, Declaration* called, const std::vector<mlir::Value>& arguments,
		TypeInfoFunction const* function, Emitted& result) {

		mlir::Type i64 = integer_type(generator, 8);
		auto generic_integer = [&](size_t index) {
			const ConstantValue& constant = called->generic_values[index];
			return static_cast<uint64_t>(ConstantValue::Kind::ENUM_MEMBER == constant.kind
				? enum_value(function->input[index].type, intern(constant.member)) : constant.integer);
		};
		auto generic_member = [&](size_t index) { return called->generic_values[index].member; };
		auto instruction = [&](const std::string& text, const std::vector<mlir::Value>& operands = {}) {
			std::string constraints;
			for (size_t i = 0; i < operands.size(); ++i) {
				constraints += "r,";
			}
			assembly(generator, mlir::Type(), operands, text, constraints + "~{memory}");
		};
		const size_t generics = called->generic_values.size();
		if (name.starts_with("read_system_register") && generics >= 1) {
			uint64_t encoding = generic_integer(0);
			if (generics == 5) {
				encoding = generic_integer(0) << 14 | generic_integer(1) << 11 | generic_integer(2) << 7 | generic_integer(3) << 3
					| generic_integer(4);
			}
			result = intrinsic_value(assembly(generator, i64, {}, std::format("mrs $0, {}", system_register_name(encoding)),
				"=r,~{memory}"), function);
			return true;
		}
		if (name.starts_with("write_system_register") && generics >= 1) {
			uint64_t encoding = generic_integer(0);
			if (generics == 5) {
				encoding = generic_integer(0) << 14 | generic_integer(1) << 11 | generic_integer(2) << 7 | generic_integer(3) << 3
					| generic_integer(4);
			}
			instruction(std::format("msr {}, $0", system_register_name(encoding)), { arguments.back() });
			return true;
		}
		if ((name.starts_with("daif_set[") || name.starts_with("daif_clear[")) && generics == 1) {
			instruction(std::format("msr {}, #{}", name.starts_with("daif_set") ? "daifset" : "daifclr", generic_integer(0) & 15));
			return true;
		}
		if ((name.starts_with("dsb[") || name.starts_with("dmb[")) && generics == 1) {
			std::string domain = generic_member(0);
			std::transform(domain.begin(), domain.end(), domain.begin(), [](char c) { return static_cast<char>(std::tolower(c)); });
			instruction(std::format("{} {}", name.substr(0, 3), domain));
			return true;
		}
		if (name.starts_with("brk[") && generics == 1) {
			instruction(std::format("brk #{}", generic_integer(0) & 0xffff));
			return true;
		}
		// One instruction named after the function, with no operands or with the one it takes
		if (name == "isb" || name == "wfi" || name == "wfe" || name == "sev" || name == "sevl" || name == "ic_iallu"
			|| name == "ic_ialluis" || name == "tlbi_vmalle1" || name == "tlbi_vmalle1is") {
			std::string text(name);
			std::replace(text.begin(), text.end(), '_', ' ');
			instruction(text);
			return true;
		}
		if (name.starts_with("tlbi_") || name.starts_with("dc_") || name.starts_with("ic_") || name.starts_with("at_")) {
			std::string text(name);
			const size_t space = text.find('_');
			text[space] = ' ';
			instruction(text + ", $0", { arguments[0] });
			return true;
		}
		if (name == "rndr" || name == "rndrrs") {
			// The value, and whether it was ready: Z is set when it wasn't
			mlir::Value both = assembly(generator, LLVM::LLVMStructType::getLiteral(generator.context, { i64, i64 }), {},
				std::format("mrs $0, {}\n\tcset $1, ne", system_register_name(name == "rndr" ? 0xd920 : 0xd921)), "=r,=r,~{memory},~{cc}");
			TypeInfo* type = function->output[0].type;
			mlir::Value ready = LLVM::ICmpOp::create(generator.builder, generator.loc, LLVM::ICmpPredicate::ne,
				extract(generator, both, 1), constant_int(generator, i64, 0));
			mlir::Value some = make_variant(generator, type, 0, { extract(generator, both, 0) }, { BUILTIN_u64 });
			mlir::Value none = make_variant(generator, type, variant_named(type, "None"), {}, {});
			result = value(LLVM::SelectOp::create(generator.builder, generator.loc, ready, some, none), type);
			return true;
		}
		if (name == "system_call") {
			// x0, x1 and x2 go in as arguments and come back as results
			mlir::Value all = assembly(generator, LLVM::LLVMStructType::getLiteral(generator.context, { i64, i64, i64 }), arguments,
				"svc #0", "={x0},={x1},={x2},{x8},0,1,2,{x3},{x4},{x5},~{memory}");
			TypeInfo* type = function->output[0].type;
			mlir::Value registers = zero_of(generator, llvm_type(generator, type));
			const std::vector<int64_t> elements = generator.member_elements[static_cast<TypeInfoStruct const*>(base(type))];
			for (size_t i = 0; i < 3 && i < elements.size(); ++i) {
				registers = insert(generator, registers, extract(generator, all, static_cast<int64_t>(i)), { elements[i] });
			}
			result = value(registers, type);
			return true;
		}
		if (name == "save_fp_simd" || name == "restore_fp_simd") {
			/*
			 * STP or LDP of q registers, signed offset (opc 10): 0xad000000, or 0xad400000 for a load, with the offset
			 * in 16s in bits 15 to 21, then Rt2, Rn (x0, so 0) and Rt; then FPCR and FPSR after them, at 512
			 */
			const bool save = name == "save_fp_simd";
			std::string text;
			if (!save) {
				text += "ldr x1, [x0, #512]\n\tldr x2, [x0, #520]\n\tmsr s3_3_c4_c4_0, x1\n\tmsr s3_3_c4_c4_1, x2\n\t";
			}
			for (uint32_t pair = 0; pair < 16; ++pair) {
				const uint32_t base_encoding = save ? 0xad000000u : 0xad400000u;
				const uint32_t encoding = base_encoding | ((pair * 2) << 15) | ((pair * 2 + 1) << 10) | (pair * 2);
				text += std::format(".inst {:#010x}\n\t", encoding);
			}
			if (save) {
				text += "mrs x1, s3_3_c4_c4_0\n\tmrs x2, s3_3_c4_c4_1\n\tstr x1, [x0, #512]\n\tstr x2, [x0, #520]";
			}
			assembly(generator, mlir::Type(), { arguments[0] }, text, "{x0},~{x1},~{x2},~{memory}");
			return true;
		}
		if (name == "write_sp_el1") {
			instruction("msr spsel, #1\n\tmov sp, $0\n\tmsr spsel, #0", { arguments[0] });
			return true;
		}
		if (name == "semihosting") {
			result = intrinsic_value(assembly(generator, i64, arguments, "hlt #0xf000", "={x0},{x0},{x1},~{memory}"), function);
			return true;
		}

		if (name == "syscall") {
			// Linux's convention: the number in x8, up to six arguments in x0 to x5, the result in x0
			std::vector<mlir::Value> operands(arguments.begin() + 1, arguments.end());
			operands.push_back(arguments[0]);
			result = intrinsic_value(assembly(generator, i64, operands, "svc #0",
				"={x0},{x0},{x1},{x2},{x3},{x4},{x5},{x8},~{memory}"), function);
			return true;
		}
		if (name == "clone_thread") {
			/*
			 * As on x86-64: a stub leaves entry and argument at the top of the child's stack, and the child
			 * calls entry there. Linux's clone takes flags, stack, parent_tid, tls and child_tid, in that order
			 */
			constexpr const char* CLONE_SYMBOL = "hemera.clone_thread";
			if (!generator.module.lookupSymbol<LLVM::LLVMFuncOp>(CLONE_SYMBOL)) {
				generator.module_assembly.push_back(std::format(
					"\t.text\n\t.p2align 4\n{}:\n"
					"\tsub x1, x1, #16\n\tstp x4, x5, [x1]\n"
					"\tmov x4, x3\n\tmov x3, xzr\n\tmov x8, #220\n\tsvc #0\n"
					"\tcbnz x0, 1f\n"
					"\tmov x29, xzr\n\tmov x30, xzr\n\tldp x9, x0, [sp], #16\n\tblr x9\n\tbrk #1\n"
					"1:\n\tret\n", CLONE_SYMBOL));
			}
			mlir::Type pointer = pointer_type(generator);
			LLVM::LLVMFuncOp clone = assembly_function(generator, CLONE_SYMBOL,
				LLVM::LLVMFunctionType::get(i64, { i64, pointer, pointer, pointer, pointer, pointer }));
			clone.setCConv(LLVM::cconv::CConv::C);
			auto call = LLVM::CallOp::create(generator.builder, generator.loc, clone, arguments);
			call.setCConv(LLVM::cconv::CConv::C);
			result = intrinsic_value(call.getResult(), function);
			return true;
		}
		return false;
	}

	/*
	 * An x86-64 instruction (base/intrinsics/x86_64). Returns false for a name that isn't one of
	 * them, or isn't generated yet.
	 */
	static bool emit_x86_64(Generator& generator, std::string_view name, const std::vector<mlir::Value>& arguments,
		TypeInfoFunction const* function, Emitted& result) {

		mlir::Type i8 = integer_type(generator, 1);
		mlir::Type i32 = integer_type(generator, 4);
		mlir::Type i64 = integer_type(generator, 8);
		const std::pair<std::string_view, std::string_view> plain[] = {
			{ "cli", "cli" }, { "sti", "sti" }, { "hlt", "hlt" }, { "pause", "pause" }, { "swapgs", "swapgs" },
		};
		for (const auto& [intrinsic, instruction] : plain) {
			if (name == intrinsic) {
				assembly(generator, mlir::Type(), {}, instruction, "~{memory}");
				return true;
			}
		}
		if (name == "read_rflags") {
			result = intrinsic_value(assembly(generator, i64, {}, "pushfq\n\tpopq $0", "=r,~{memory}"), function);
			return true;
		}
		if (name == "lgdt" || name == "lidt") {
			assembly(generator, mlir::Type(), arguments, name == "lgdt" ? "lgdt ($0)" : "lidt ($0)", "r,~{memory}");
			return true;
		}
		if (name == "ltr") {
			assembly(generator, mlir::Type(), arguments, "ltr $0", "r,~{memory}");
			return true;
		}
		if (name == "load_segments") {
			// The data segments, then cs with a far return to the next instruction
			std::vector<mlir::Value> selectors{
				LLVM::ZExtOp::create(generator.builder, generator.loc, i64, arguments[0]),
				LLVM::ZExtOp::create(generator.builder, generator.loc, i64, arguments[1]),
			};
			assembly(generator, mlir::Type(), selectors,
				"movw ${1:w}, %ds\n\tmovw ${1:w}, %es\n\tmovw ${1:w}, %fs\n\tmovw ${1:w}, %gs\n\tmovw ${1:w}, %ss\n\t"
				"pushq $0\n\tleaq 1f(%rip), %rax\n\tpushq %rax\n\tlretq\n1:",
				"r,r,~{rax},~{memory}");
			return true;
		}
		const PortAccess port_reads[] = {
			{ "in_u8", "inb %dx, %al", "={al},{dx},~{memory}", 1 },
			{ "in_u16", "inw %dx, %ax", "={ax},{dx},~{memory}", 2 },
			{ "in_u32", "inl %dx, %eax", "={eax},{dx},~{memory}", 4 },
		};
		for (const PortAccess& access : port_reads) {
			if (name == access.name) {
				result = intrinsic_value(assembly(generator, integer_type(generator, access.bytes), arguments, access.instruction,
					access.constraints), function);
				return true;
			}
		}
		const PortAccess port_writes[] = {
			{ "out_u8", "outb %al, %dx", "{dx},{al},~{memory}", 1 },
			{ "out_u16", "outw %ax, %dx", "{dx},{ax},~{memory}", 2 },
			{ "out_u32", "outl %eax, %dx", "{dx},{eax},~{memory}", 4 },
		};
		for (const PortAccess& access : port_writes) {
			if (name == access.name) {
				assembly(generator, mlir::Type(), arguments, access.instruction, access.constraints);
				return true;
			}
		}
		if (name == "rdmsr") {
			result = intrinsic_value(pair_result(generator, arguments, "rdmsr", "={eax},={edx},{ecx},~{memory}"), function);
			return true;
		}
		if (name == "syscall") {
			result = intrinsic_value(assembly(generator, integer_type(generator, 8), arguments, "syscall",
				"={rax},{rax},{rdi},{rsi},{rdx},{r10},{r8},{r9},~{rcx},~{r11},~{memory}"), function);
			return true;
		}
		if (name == "system_call") {
			// rdx and r8 go in as arguments and come back as results
			mlir::Value all = assembly(generator, LLVM::LLVMStructType::getLiteral(generator.context, { i64, i64, i64 }), arguments,
				"syscall", "={rax},={rdx},={r8},0,{rdi},{rsi},1,{r10},2,{r9},~{rcx},~{r11},~{memory}");
			TypeInfo* type = function->output[0].type;
			mlir::Value registers = zero_of(generator, llvm_type(generator, type));
			const std::vector<int64_t> elements = generator.member_elements[static_cast<TypeInfoStruct const*>(base(type))];
			for (size_t i = 0; i < 3 && i < elements.size(); ++i) {
				registers = insert(generator, registers, extract(generator, all, static_cast<int64_t>(i)), { elements[i] });
			}
			result = value(registers, type);
			return true;
		}
		if (name == "clone_thread") {
			/*
			 * The child can't go on in this function, whose frame is on the parent's stack, so a stub
			 * leaves entry and argument at the top of the child's stack, and the child calls entry there
			 */
			constexpr const char* CLONE_SYMBOL = "hemera.clone_thread";
			if (!generator.module.lookupSymbol<LLVM::LLVMFuncOp>(CLONE_SYMBOL)) {
				generator.module_assembly.push_back(std::format(
					"\t.text\n\t.p2align 4\n{}:\n"
					"\tsubq $16, %rsi\n\tmovq %r8, (%rsi)\n\tmovq %r9, 8(%rsi)\n"
					"\tmovq %rcx, %r10\n\txorl %r8d, %r8d\n\tmovl $56, %eax\n\tsyscall\n"
					"\ttestq %rax, %rax\n\tjnz 1f\n"
					"\txorl %ebp, %ebp\n\tpopq %rax\n\tpopq %rdi\n\tandq $-16, %rsp\n\tcallq *%rax\n\tud2\n"
					"1:\n\tretq\n", CLONE_SYMBOL));
			}
			mlir::Type pointer = pointer_type(generator);
			mlir::Type word = integer_type(generator, 8);
			LLVM::LLVMFuncOp clone = assembly_function(generator, CLONE_SYMBOL,
				LLVM::LLVMFunctionType::get(word, { word, pointer, pointer, pointer, pointer, pointer }));
			clone.setCConv(LLVM::cconv::CConv::C);
			auto call = LLVM::CallOp::create(generator.builder, generator.loc, clone, arguments);
			call.setCConv(LLVM::cconv::CConv::C);
			result = intrinsic_value(call.getResult(), function);
			return true;
		}
		if (name == "read_gs_base") {
			// IA32_GS_BASE, which works whether or not FSGSBASE is enabled
			mlir::Value address = pair_result(generator, { constant_int(generator, i32, 0xC0000101) }, "rdmsr",
				"={eax},={edx},{ecx},~{memory}");
			result = intrinsic_value(LLVM::IntToPtrOp::create(generator.builder, generator.loc, pointer_type(generator), address),
				function);
			return true;
		}
		if (name == "wrmsr" || name == "xsetbv") {
			std::vector<mlir::Value> operands{ arguments[0], low_half(generator, arguments[1]), high_half(generator, arguments[1]) };
			assembly(generator, mlir::Type(), operands, name, "{ecx},{eax},{edx},~{memory}");
			return true;
		}
		if (name == "xgetbv") {
			result = intrinsic_value(pair_result(generator, arguments, "xgetbv", "={eax},={edx},{ecx},~{memory}"), function);
			return true;
		}
		if (name == "rdtsc") {
			result = intrinsic_value(pair_result(generator, {}, "rdtsc", "={eax},={edx},~{memory}"), function);
			return true;
		}
		if (name.starts_with("read_cr")) {
			const std::string text = std::format("movq %{}, $0", name.substr(5));
			result = intrinsic_value(assembly(generator, i64, {}, text, "=r,~{memory}"), function);
			return true;
		}
		if (name.starts_with("write_cr")) {
			const std::string text = std::format("movq $0, %{}", name.substr(6));
			assembly(generator, mlir::Type(), arguments, text, "r,~{memory}");
			return true;
		}
		if (name == "invlpg") {
			assembly(generator, mlir::Type(), arguments, "invlpg ($0)", "r,~{memory}");
			return true;
		}
		if (name == "xsave" || name == "xsavec" || name == "xsaveopt" || name == "xrstor") {
			// The mask goes in edx:eax
			std::vector<mlir::Value> operands{ arguments[0], low_half(generator, arguments[1]), high_half(generator, arguments[1]) };
			assembly(generator, mlir::Type(), operands, std::format("{}64 ($0)", name), "r,{eax},{edx},~{memory}");
			return true;
		}
		if (name == "cpuid") {
			mlir::Value all = assembly(generator, LLVM::LLVMStructType::getLiteral(generator.context, { i32, i32, i32, i32 }),
				arguments, "cpuid", "={eax},={ebx},={ecx},={edx},{eax},{ecx},~{memory}");
			TypeInfo* type = function->output[0].type;
			mlir::Value registers = zero_of(generator, llvm_type(generator, type));
			const std::vector<int64_t> elements = generator.member_elements[static_cast<TypeInfoStruct const*>(base(type))];
			for (size_t i = 0; i < 4 && i < elements.size(); ++i) {
				registers = insert(generator, registers, extract(generator, all, static_cast<int64_t>(i)), { elements[i] });
			}
			result = value(registers, type);
			return true;
		}
		// AES-NI, PCLMULQDQ and the SHA extensions, as LLVM's intrinsics, so the optimizer knows what they do
		const std::pair<std::string_view, std::string_view> aes[] = {
			{ "aes_encrypt_round", "llvm.x86.aesni.aesenc" }, { "aes_encrypt_last", "llvm.x86.aesni.aesenclast" },
			{ "aes_decrypt_round", "llvm.x86.aesni.aesdec" }, { "aes_decrypt_last", "llvm.x86.aesni.aesdeclast" },
			{ "aes_inverse_mix", "llvm.x86.aesni.aesimc" }, { "aes_key_assist", "llvm.x86.aesni.aeskeygenassist" },
			{ "carryless_multiply", "llvm.x86.pclmulqdq" },
			{ "sha256_rounds2", "llvm.x86.sha256rnds2" }, { "sha256_message1", "llvm.x86.sha256msg1" },
			{ "sha256_message2", "llvm.x86.sha256msg2" },
		};
		for (const auto& [intrinsic, llvm_name] : aes) {
			if (name == intrinsic) {
				TypeInfo* type = function->output[0].type;
				auto call = LLVM::CallIntrinsicOp::create(generator.builder, generator.loc, llvm_type(generator, type),
					generator.builder.getStringAttr(llvm_name), arguments);
				result = value(call.getResult(0), type);
				return true;
			}
		}
		if (name == "rdrand" || name == "rdseed") {
			// The value, and whether the carry flag said it's ready
			mlir::Value both = assembly(generator, LLVM::LLVMStructType::getLiteral(generator.context, { i64, i8 }), {},
				std::format("{} $0\n\tsetc $1", name), "=r,=r,~{memory}");
			TypeInfo* type = function->output[0].type;
			mlir::Value ready = LLVM::ICmpOp::create(generator.builder, generator.loc, LLVM::ICmpPredicate::ne,
				extract(generator, both, 1), constant_int(generator, i8, 0));
			mlir::Value some = make_variant(generator, type, 0, { extract(generator, both, 0) }, { BUILTIN_u64 });
			mlir::Value none = make_variant(generator, type, variant_named(type, "None"), {}, {});
			result = value(LLVM::SelectOp::create(generator.builder, generator.loc, ready, some, none), type);
			return true;
		}
		return false;
	}

	// An atomic load, store or read-modify-write, by its name: what it does and how it's ordered.
	static bool emit_atomic(Generator& generator, std::string_view name, TypeInfoFunction const* function,
		const std::vector<mlir::Value>& arguments, Emitted& result) {

		mlir::OpBuilder& b = generator.builder;
		const mlir::Location l = generator.loc;
		const LLVM::AtomicOrdering ordering = ordering_suffix(name);
		bool weak = false;
		if (name.ends_with("_weak")) {
			name.remove_suffix(5);
			weak = true;
		}
		TypeInfo* result_type = function->output.empty() ? nullptr : function->output[0].type;
		TypeInfo const* target = static_cast<TypeInfoPointer const*>(base(function->input[0].type))->base_type;
		TypeInfo const* value_type = target != nullptr ? target : BUILTIN_rawptr;
		const unsigned alignment = static_cast<unsigned>(value_type->size);
		if (name.starts_with("atomic_load_")) {
			result = value(LLVM::LoadOp::create(b, l, llvm_type(generator, value_type), arguments[0], alignment, false, false, false,
				false, ordering), result_type);
			return true;
		}
		if (name.starts_with("atomic_store_")) {
			LLVM::StoreOp::create(b, l, arguments[1], arguments[0], alignment, false, false, false, ordering);
			return true;
		}
		if (name.starts_with("interlocked_compare_exchange_")) {
			// (old, success), the same struct as the function's two results
			auto exchange = LLVM::AtomicCmpXchgOp::create(b, l, arguments[0], arguments[2], arguments[1], ordering,
				failure_ordering(ordering), "", alignment, weak);
			result = value(exchange.getRes(), nullptr);
			result.kind = ValueKind::RESULTS;
			result.results = { function->output[0].type, function->output[1].type };
			return true;
		}
		const std::pair<std::string_view, LLVM::AtomicBinOp> operations[] = {
			{ "interlocked_exchange_add_", LLVM::AtomicBinOp::add },
			{ "interlocked_exchange_", LLVM::AtomicBinOp::xchg },
			{ "interlocked_and_", LLVM::AtomicBinOp::_and },
			{ "interlocked_or_", LLVM::AtomicBinOp::_or },
			{ "interlocked_xor_", LLVM::AtomicBinOp::_xor },
			{ "interlocked_increment_", LLVM::AtomicBinOp::add },
			{ "interlocked_decrement_", LLVM::AtomicBinOp::sub },
		};
		for (const auto& [prefix, operation] : operations) {
			if (!name.starts_with(prefix)) {
				continue;
			}
			// Increment and decrement change it by one; each gives the old value
			mlir::Value operand = arguments.size() > 1 ? arguments[1] : constant_int(generator, llvm_type(generator, value_type), 1);
			mlir::Value old = LLVM::AtomicRMWOp::create(b, l, operation, arguments[0], operand, ordering, "", alignment);
			result = value(old, result_type);
			return true;
		}
		return false;
	}

	/*
	 * An intrinsic's instructions (base/intrinsics): trap, memory, volatile and atomic accesses,
	 * fences, the carrier register, and the platform's own instructions.
	 */
	static Emitted emit_compile_time_service(Generator& generator, std::string_view name, TypeInfoFunction const* function,
		const std::vector<mlir::Value>& arguments, const ast::Node* where);
	static Emitted emit_compiler_call(Generator& generator, std::string_view name, TypeInfoFunction const* function,
		const std::vector<mlir::Value>& arguments, const ast::Node* where);

	// ---------------------------------------------------------------------------------------------
	// Fibers (docs/calling_convention.md, Suspending and Resuming a Fiber)

	constexpr std::string_view FIBER_START_SYMBOL = "hemera.fiber_start";
	constexpr std::string_view FIBER_RESUME_SYMBOL = "hemera.fiber_resume";
	constexpr std::string_view FIBER_SUSPEND_SYMBOL = "hemera.fiber_suspend";

	// Where the fiber switches find what they read: offsets into Fiber and CarrierBlock.
	struct FiberOffsets {
		// The fiber's: where fiber_suspend left its state, on its own stack
		size_t saved_sp = 0;
		// The carrier's: the resume loop's state, for the fiber running on it
		size_t resume_frame = 0;
		size_t resume_return = 0;
		size_t resume_parent = 0;
		size_t carrier_limit = 0;
		size_t carrier_segment = 0;
		size_t current_fiber = 0;
		size_t scheduler_sp = 0;
		size_t shadow_stack_base = 0;
		// Fiber.state: where, how many bytes, and the values for .Running and .Suspended
		size_t state = 0;
		size_t state_size = 0;
		uint64_t running = 0;
		uint64_t suspended = 0;
	};

	static bool runtime_integer(Generator& generator, std::string_view name, uint64_t& value) {
		Declaration* declaration = base_declaration_named(generator, "runtime", name);
		ast::Node* literal = declaration != nullptr && declaration->node != nullptr ? definition_value(declaration->node) : nullptr;
		if (literal == nullptr || ast::NodeType::LITERAL != literal->node_type || TokenType::LITERAL_INTEGER != literal->value.type) {
			return false;
		}
		value = parse_integer(text_of(literal->value.value));
		return true;
	}

	static bool runtime_offset(Generator& generator, std::string_view type_name, std::string_view member, size_t& offset) {
		Declaration* declaration = base_declaration_named(generator, "runtime", type_name);
		if (declaration == nullptr || declaration->type_value == nullptr || !is_variant(declaration->type_value, TypeInfoVariant::STRUCT)) {
			return false;
		}
		TypeInfo* type = nullptr;
		std::vector<int64_t> path;
		return find_member(generator, static_cast<TypeInfoStruct const*>(base(declaration->type_value)), intern(std::string(member)),
			offset, type, path);
	}

	static bool fiber_offsets(Generator& generator, FiberOffsets& offsets) {
		size_t resume = 0;
		bool found = runtime_offset(generator, "Fiber", "resume", resume)
			&& runtime_offset(generator, "FiberResumeState", "saved_sp", offsets.saved_sp);
		offsets.saved_sp += resume;
		const std::pair<std::string_view, size_t*> carrier_fields[] = {
			{ "stack_limit", &offsets.carrier_limit }, { "stack_segment", &offsets.carrier_segment },
			{ "current_fiber", &offsets.current_fiber }, { "scheduler_sp", &offsets.scheduler_sp },
			{ "shadow_stack_base", &offsets.shadow_stack_base }, { "resume_frame", &offsets.resume_frame },
			{ "resume_return", &offsets.resume_return }, { "resume_parent", &offsets.resume_parent },
		};
		for (const auto& [name, offset] : carrier_fields) {
			found = found && runtime_offset(generator, "CarrierBlock", name, *offset);
		}
		// The state, which the switches keep up to date
		Declaration* fiber = base_declaration_named(generator, "runtime", "Fiber");
		if (!found || fiber == nullptr || fiber->type_value == nullptr) {
			return false;
		}
		TypeInfo* state_type = nullptr;
		std::vector<int64_t> path;
		if (!find_member(generator, static_cast<TypeInfoStruct const*>(base(fiber->type_value)), intern(std::string("state")), offsets.state,
			state_type, path) || !is_variant(state_type, TypeInfoVariant::ENUM)) {
			return false;
		}
		offsets.state_size = state_type->size;
		offsets.running = static_cast<uint64_t>(enum_value(state_type, intern(std::string("Running"))));
		offsets.suspended = static_cast<uint64_t>(enum_value(state_type, intern(std::string("Suspended"))));
		return offsets.state_size == 1 || offsets.state_size == 2 || offsets.state_size == 4 || offsets.state_size == 8;
	}

	// Storing a fiber's state, as wide as FiberState is.
	static std::string set_state(const FiberOffsets& o, uint64_t value) {
		const char suffix = o.state_size == 1 ? 'b' : o.state_size == 2 ? 'w' : o.state_size == 4 ? 'l' : 'q';
		return std::format("\tmov{} ${}, {}(%rdi)\n", suffix, value, o.state);
	}

	/*
	 * Where fiber_suspend leaves a fiber's state on its own stack, from saved_sp: MXCSR and the x87
	 * control word (with SSE), then the innermost frame's base pointer, the carrier's stack_limit and
	 * stack_segment, rbx, r12, r13 and r15, and the return address into that frame, where it continues.
	 */
	struct SuspendedLayout {
		size_t top_frame = 0;
		size_t limit = 0;
		size_t segment = 0;
		size_t registers = 0;
		size_t continuation = 0;
	};

	/*
	 * On AArch64: the top frame's x29, the limit and segment, x19 to x27, then fiber_suspend's x30, and
	 * with fp, FPCR and d8 to d15 after it, so the offsets are the same either way.
	 */
	constexpr size_t AARCH64_SUSPENDED_SIZE = 112;
	constexpr size_t AARCH64_SUSPENDED_FP_SIZE = 176;

	static SuspendedLayout suspended_layout(bool sse, bool aarch64 = false) {
		if (aarch64) {
			return SuspendedLayout{ 0, 8, 16, 24, 96 };
		}
		const size_t floating = sse ? 16 : 0;
		return SuspendedLayout{ floating, floating + 8, floating + 16, floating + 24, floating + 56 };
	}

	/*
	 * fiber_start, fiber_resume, fiber_suspend, fiber_entry and the resume loop, for x86-64 frames
	 * that chain through rbp. run is runtime.fiber_run's symbol. With SSE, MXCSR and the x87 control
	 * word are callee-saved too; without it, as in a kernel, those instructions may not be allowed.
	 *
	 * Switching away from the scheduler pushes its callee-saved registers and the carrier's
	 * stack_limit, stack_segment and current_fiber on its own stack, and switching back pops them.
	 * A suspended fiber's state is on its own stack (suspended_layout), and the Fiber only keeps where.
	 * The resume loop keeps its state in rcx, rsi, rdi, r9, r10 and r11, which no function returns
	 * anything in, so a re-entered frame's result reaches its caller untouched, and the frame it
	 * re-entered last in the carrier block, since the fiber only runs on one carrier at a time.
	 */
	static std::string fiber_assembly(const FiberOffsets& o, std::string_view run, bool sse) {
		const SuspendedLayout layout = suspended_layout(sse);
		const std::string save_floating = sse ? "\tsubq $16, %rsp\n\tstmxcsr (%rsp)\n\tfnstcw 4(%rsp)\n" : "";
		const std::string restore_floating = sse ? "\tldmxcsr (%rsp)\n\tfldcw 4(%rsp)\n\taddq $16, %rsp\n" : "";
		// The scheduler's state, on its own stack: 8 pushes and padding after the return address keep rsp 16-byte aligned
		std::string save_scheduler = "\tpushq %rbx\n\tpushq %rbp\n\tpushq %r12\n\tpushq %r13\n\tpushq %r15\n";
		save_scheduler += std::format("\tpushq {}(%r14)\n\tpushq {}(%r14)\n\tpushq {}(%r14)\n\tsubq $8, %rsp\n",
			o.carrier_limit, o.carrier_segment, o.current_fiber);
		save_scheduler += save_floating;
		save_scheduler += std::format("\tmovq %rsp, {}(%r14)\n", o.scheduler_sp);
		/*
		 * The shadow stack pointer, 0 without shadow stacks, where rdsspq does nothing. It and incsspq are
		 * written as bytes, since the assembler only takes them for targets with shadow stacks.
		 */
		save_scheduler += std::format("\txorl %eax, %eax\n\t.byte 0xf3, 0x48, 0x0f, 0x1e, 0xc8\n\tmovq %rax, {}(%r14)\n", o.shadow_stack_base);
		auto back_to_scheduler = [&](int exit) {
			// Drop the fiber's entries from the shadow stack, at most 255 at a time; none without shadow stacks
			std::string text = "\txorl %ecx, %ecx\n\t.byte 0xf3, 0x48, 0x0f, 0x1e, 0xc9\n\ttestq %rcx, %rcx\n\tjz 3f\n";
			text += std::format("\tmovq {}(%r14), %rax\n\tsubq %rcx, %rax\n\tshrq $3, %rax\n", o.shadow_stack_base);
			text += "2:\n\ttestq %rax, %rax\n\tjz 3f\n\tmovq %rax, %rcx\n\tcmpq $255, %rcx\n\tjbe 4f\n\tmovl $255, %ecx\n";
			text += "4:\n\t.byte 0xf3, 0x48, 0x0f, 0xae, 0xe9\n\tsubq %rcx, %rax\n\tjmp 2b\n3:\n";
			text += std::format("\tmovq {}(%r14), %rsp\n", o.scheduler_sp);
			text += restore_floating;
			text += std::format("\taddq $8, %rsp\n\tpopq {}(%r14)\n\tpopq {}(%r14)\n\tpopq {}(%r14)\n",
				o.current_fiber, o.carrier_segment, o.carrier_limit);
			text += "\tpopq %r15\n\tpopq %r13\n\tpopq %r12\n\tpopq %rbp\n\tpopq %rbx\n";
			text += std::format("\tmovl ${}, %eax\n\tretq\n", exit);
			return text;
		};
		std::string text = "\t.text\n";
		// fiber_start(fiber, stack top, stack limit): onto the fiber's first segment, into fiber_entry
		text += std::format("\t.p2align 4\n{}:\n", FIBER_START_SYMBOL);
		text += save_scheduler;
		text += std::format("\tmovq %rdi, {}(%r14)\n\tmovq %rdx, {}(%r14)\n\tmovq $0, {}(%r14)\n\tmovq $0, {}(%r14)\n",
			o.current_fiber, o.carrier_limit, o.carrier_segment, o.resume_frame);
		text += set_state(o, o.running);
		text += "\tmovq %rsi, %rsp\n\txorl %ebp, %ebp\n\tcallq hemera.fiber_entry\n\tud2\n";
		// fiber_entry: the fiber's bottom frame, calling runtime.fiber_run(fiber); after that, it's finished
		text += "\t.p2align 4\nhemera.fiber_entry:\n\tpushq %rbp\n\tmovq %rsp, %rbp\n";
		text += std::format("\tcallq {}\n", run);
		text += back_to_scheduler(1);
		// fiber_resume(fiber): the carrier's segment and limit back from the fiber's stack, then re-enter its frames, innermost first
		text += std::format("\t.p2align 4\n{}:\n", FIBER_RESUME_SYMBOL);
		text += save_scheduler;
		text += std::format("\tmovq %rdi, {}(%r14)\n", o.current_fiber);
		text += set_state(o, o.running);
		text += std::format("\tmovq {}(%rdi), %rax\n", o.saved_sp);
		text += std::format("\tmovq {}(%rax), %r9\n\tmovq %r9, {}(%r14)\n", layout.segment, o.carrier_segment);
		text += std::format("\tmovq {}(%rax), %r9\n\tmovq %r9, {}(%r14)\n", layout.limit, o.carrier_limit);
		text += std::format("\tmovq {}(%rax), %r10\n\tmovq {}(%rax), %r11\n\tmovl $1, %esi\n", layout.top_frame, layout.continuation);
		text += "hemera.fiber_reenter_next:\n";
		text += std::format("\tmovq %r10, {}(%r14)\n", o.resume_frame);
		// r9 for what's copied, since rcx holds the frame bottom the loop is going to re-enter at
		text += std::format("\tmovq 8(%r10), %r9\n\tmovq %r9, {}(%r14)\n", o.resume_return);
		text += std::format("\tmovq (%r10), %r9\n\tmovq %r9, {}(%r14)\n", o.resume_parent);
		text += "\tleaq 16(%r10), %rsp\n\tcallq hemera.fiber_reenter\n";
		// The frame returned, to here: on to its caller, whose frame bottom the stack pointer is at now
		text += std::format("{}:\n\tmovq %rsp, %rcx\n", FIBER_LOOP_RETURN_SYMBOL);
		text += std::format("\tmovq {}(%r14), %r11\n\tmovq {}(%r14), %r10\n", o.resume_return, o.resume_parent);
		text += "\txorl %esi, %esi\n\tjmp hemera.fiber_reenter_next\n";
		// fiber_reenter: only reached by the call above, which put the loop's address in the frame's return slot
		text += "\t.p2align 4\nhemera.fiber_reenter:\n\tmovq %r10, %rbp\n\ttestl %esi, %esi\n\tjz 1f\n";
		text += std::format("\tmovq {}(%rdi), %rsp\n", o.saved_sp);
		text += restore_floating;
		// Past the frame pointer, limit and segment, to the registers, and past the return address after them
		text += std::format("\taddq ${}, %rsp\n", layout.registers - layout.top_frame);
		text += "\tpopq %r15\n\tpopq %r13\n\tpopq %r12\n\tpopq %rbx\n\taddq $8, %rsp\n\tjmpq *%r11\n";
		text += "1:\n\tmovq %rcx, %rsp\n\tjmpq *%r11\n";
		// fiber_suspend(fiber): its state on its own stack, where it is, and back to the scheduler
		text += std::format("\t.p2align 4\n{}:\n", FIBER_SUSPEND_SYMBOL);
		text += "\tpushq %rbx\n\tpushq %r12\n\tpushq %r13\n\tpushq %r15\n";
		text += std::format("\tpushq {}(%r14)\n\tpushq {}(%r14)\n\tpushq %rbp\n", o.carrier_segment, o.carrier_limit);
		text += save_floating;
		text += std::format("\tmovq %rsp, {}(%rdi)\n", o.saved_sp);
		// Suspended frames hold their real return addresses
		text += std::format("\tmovq {}(%r14), %rax\n\ttestq %rax, %rax\n\tjz 1f\n", o.resume_frame);
		text += std::format("\tmovq {}(%r14), %rcx\n\tmovq %rcx, 8(%rax)\n\tmovq $0, {}(%r14)\n", o.resume_return, o.resume_frame);
		text += "1:\n";
		text += set_state(o, o.suspended);
		text += back_to_scheduler(0);
		return text;
	}

	// Storing a fiber's state on AArch64, the fiber in x0.
	static std::string set_state_aarch64(const FiberOffsets& o, uint64_t value) {
		const char* store = o.state_size == 1 ? "strb w9" : o.state_size == 2 ? "strh w9" : o.state_size == 4 ? "str w9" : "str x9";
		return aarch64_move("x9", value) + std::format("\t{}, [x0, #{}]\n", store, o.state);
	}

	/*
	 * The fiber switches and the resume loop on AArch64 (docs/calling_convention.md, AArch64), as on
	 * x86-64. The scheduler's state on its own stack, from scheduler_sp: x19 to x27, x29, x30, the
	 * carrier's stack_limit, stack_segment and current_fiber, and with fp, FPCR and d8 to d15. A
	 * suspended fiber's is suspended_layout's. Nothing is pushed by a call here, so the loop leaves the
	 * stack pointer where it is: at the fiber's saved state the first time, and then at the bottom of
	 * the frame that returned, below everything live. fiber_reenter puts the loop's address in the
	 * frame record, which functions return through, and the loop keeps its state in x9 to x12, which
	 * no function returns anything in. No guarded control stack or pointer authentication yet.
	 */
	static std::string fiber_assembly_aarch64(const FiberOffsets& o, std::string_view run, bool fp) {
		const SuspendedLayout layout = suspended_layout(fp, true);
		const size_t scheduler_size = fp ? 192 : 112;
		const size_t suspended_size = fp ? AARCH64_SUSPENDED_FP_SIZE : AARCH64_SUSPENDED_SIZE;
		// FPCR and d8 to d15 at offset, from sp
		auto floating = [&](size_t offset, bool save) {
			if (!fp) {
				return std::string();
			}
			std::string text = save ? std::format("\tmrs x9, fpcr\n\tstr x9, [sp, #{}]\n", offset)
				: std::format("\tldr x9, [sp, #{}]\n\tmsr fpcr, x9\n", offset);
			for (int i = 8; i < 16; i += 2) {
				text += std::format("\t{} d{}, d{}, [sp, #{}]\n", save ? "stp" : "ldp", i, i + 1, offset + 8 + static_cast<size_t>(i - 8) * 8);
			}
			return text;
		};
		std::string save_scheduler = std::format("\tsub sp, sp, #{}\n", scheduler_size);
		save_scheduler += "\tstp x19, x20, [sp]\n\tstp x21, x22, [sp, #16]\n\tstp x23, x24, [sp, #32]\n\tstp x25, x26, [sp, #48]\n";
		save_scheduler += std::format("\tstp x27, x29, [sp, #64]\n\tldr x9, [x28, #{}]\n\tstp x30, x9, [sp, #80]\n", o.carrier_limit);
		save_scheduler += std::format("\tldr x9, [x28, #{}]\n\tldr x10, [x28, #{}]\n\tstp x9, x10, [sp, #96]\n", o.carrier_segment, o.current_fiber);
		save_scheduler += floating(112, true);
		save_scheduler += std::format("\tmov x9, sp\n\tstr x9, [x28, #{}]\n\tstr xzr, [x28, #{}]\n", o.scheduler_sp, o.shadow_stack_base);
		auto back_to_scheduler = [&](int exit) {
			std::string text = std::format("\tldr x9, [x28, #{}]\n\tmov sp, x9\n", o.scheduler_sp);
			text += floating(112, false);
			text += std::format("\tldp x9, x10, [sp, #96]\n\tstr x9, [x28, #{}]\n\tstr x10, [x28, #{}]\n", o.carrier_segment, o.current_fiber);
			text += std::format("\tldp x30, x9, [sp, #80]\n\tstr x9, [x28, #{}]\n", o.carrier_limit);
			text += "\tldp x19, x20, [sp]\n\tldp x21, x22, [sp, #16]\n\tldp x23, x24, [sp, #32]\n\tldp x25, x26, [sp, #48]\n";
			text += std::format("\tldp x27, x29, [sp, #64]\n\tadd sp, sp, #{}\n\tmov w0, #{}\n\tret\n", scheduler_size, exit);
			return text;
		};
		std::string text = "\t.text\n";
		// fiber_start(fiber, stack top, stack limit): onto the fiber's first segment, into fiber_entry
		text += std::format("\t.p2align 4\n{}:\n", FIBER_START_SYMBOL);
		text += save_scheduler;
		text += std::format("\tstr x0, [x28, #{}]\n\tstr x2, [x28, #{}]\n\tstr xzr, [x28, #{}]\n\tstr xzr, [x28, #{}]\n",
			o.current_fiber, o.carrier_limit, o.carrier_segment, o.resume_frame);
		text += set_state_aarch64(o, o.running);
		text += "\tmov sp, x1\n\tmov x29, xzr\n\tbl hemera.fiber_entry\n\tbrk #1\n";
		// fiber_entry: the fiber's bottom frame, calling runtime.fiber_run(fiber); after that, it's finished
		text += "\t.p2align 4\nhemera.fiber_entry:\n\tstp x29, x30, [sp, #-16]!\n\tmov x29, sp\n";
		text += std::format("\tbl {}\n", run);
		text += back_to_scheduler(1);
		// fiber_resume(fiber): the carrier's segment and limit back from the fiber's stack, then re-enter its frames, innermost first
		text += std::format("\t.p2align 4\n{}:\n", FIBER_RESUME_SYMBOL);
		text += save_scheduler;
		text += std::format("\tstr x0, [x28, #{}]\n", o.current_fiber);
		text += set_state_aarch64(o, o.running);
		text += std::format("\tldr x9, [x0, #{}]\n\tmov sp, x9\n", o.saved_sp);
		text += std::format("\tldr x10, [sp, #{}]\n\tstr x10, [x28, #{}]\n", layout.segment, o.carrier_segment);
		text += std::format("\tldr x10, [sp, #{}]\n\tstr x10, [x28, #{}]\n", layout.limit, o.carrier_limit);
		text += std::format("\tldr x10, [sp, #{}]\n\tldr x11, [sp, #{}]\n\tmov w12, #1\n", layout.top_frame, layout.continuation);
		text += "hemera.fiber_reenter_next:\n";
		text += std::format("\tstr x10, [x28, #{}]\n", o.resume_frame);
		text += std::format("\tldr x9, [x10, #8]\n\tstr x9, [x28, #{}]\n", o.resume_return);
		text += std::format("\tldr x9, [x10]\n\tstr x9, [x28, #{}]\n", o.resume_parent);
		text += "\tbl hemera.fiber_reenter\n";
		// The frame returned, to here: on to its caller, whose frame bottom the stack pointer is at now
		text += std::format("{}:\n", FIBER_LOOP_RETURN_SYMBOL);
		text += std::format("\tldr x11, [x28, #{}]\n\tldr x10, [x28, #{}]\n", o.resume_return, o.resume_parent);
		text += "\tmov w12, wzr\n\tb hemera.fiber_reenter_next\n";
		// fiber_reenter: only reached by the bl above, whose return address the frame returns through now
		text += "\t.p2align 4\nhemera.fiber_reenter:\n\tstr x30, [x10, #8]\n\tmov x29, x10\n\tcbz w12, 1f\n";
		text += "\tldp x19, x20, [sp, #24]\n\tldp x21, x22, [sp, #40]\n\tldp x23, x24, [sp, #56]\n\tldp x25, x26, [sp, #72]\n";
		text += "\tldr x27, [sp, #88]\n";
		text += floating(104, false);
		text += std::format("\tadd sp, sp, #{}\n", suspended_size);
		text += "1:\n\tbr x11\n";
		// fiber_suspend(fiber): its state on its own stack, where it is, and back to the scheduler
		text += std::format("\t.p2align 4\n{}:\n", FIBER_SUSPEND_SYMBOL);
		text += std::format("\tsub sp, sp, #{}\n", suspended_size);
		text += std::format("\tldr x9, [x28, #{}]\n\tldr x10, [x28, #{}]\n\tstr x29, [sp]\n\tstp x9, x10, [sp, #8]\n",
			o.carrier_limit, o.carrier_segment);
		text += "\tstp x19, x20, [sp, #24]\n\tstp x21, x22, [sp, #40]\n\tstp x23, x24, [sp, #56]\n\tstp x25, x26, [sp, #72]\n";
		text += "\tstp x27, x30, [sp, #88]\n";
		text += floating(104, true);
		text += std::format("\tmov x9, sp\n\tstr x9, [x0, #{}]\n", o.saved_sp);
		// Suspended frames hold their real return addresses
		text += std::format("\tldr x9, [x28, #{}]\n\tcbz x9, 1f\n", o.resume_frame);
		text += std::format("\tldr x10, [x28, #{}]\n\tstr x10, [x9, #8]\n\tstr xzr, [x28, #{}]\n", o.resume_return, o.resume_frame);
		text += "1:\n";
		text += set_state_aarch64(o, o.suspended);
		text += back_to_scheduler(0);
		return text;
	}

	/*
	 * What lower_to_llvm's stack walks need to follow fibers (define_stack_walker): the resume loop's
	 * return address, and FIBER_WALK_SYMBOL: the offsets of the carrier's resume_return and of a
	 * fiber's saved_sp, state (and its size, and .Suspended), and of the top frame's base pointer and
	 * continuation from saved_sp (suspended_layout).
	 */
	static void fiber_walk_table(Generator& generator, const FiberOffsets& o, bool sse) {
		assembly_function(generator, FIBER_LOOP_RETURN_SYMBOL, no_arguments(generator));
		const SuspendedLayout layout = suspended_layout(sse, ArchType::aarch64 == generator.options->architecture);
		const std::vector<int64_t> values{ static_cast<int64_t>(o.resume_return), static_cast<int64_t>(o.saved_sp),
			static_cast<int64_t>(o.state), static_cast<int64_t>(o.state_size), static_cast<int64_t>(o.suspended),
			static_cast<int64_t>(layout.top_frame), static_cast<int64_t>(layout.continuation) };
		mlir::Type i64 = integer_type(generator, 8);
		mlir::Type type = LLVM::LLVMArrayType::get(i64, values.size());
		auto tensor = mlir::RankedTensorType::get({ static_cast<int64_t>(values.size()) }, i64);
		mlir::OpBuilder::InsertionGuard guard(generator.builder);
		generator.builder.setInsertionPointToEnd(generator.module.getBody());
		LLVM::GlobalOp::create(generator.builder, generator.loc, type, true, LLVM::Linkage::Internal, FIBER_WALK_SYMBOL,
			mlir::DenseElementsAttr::get(tensor, llvm::ArrayRef<int64_t>(values)), 8);
	}

	/*
	 * intrinsics.fiber_start, fiber_resume and fiber_suspend: calls to the generated switches, made
	 * once. For now on x86-64.
	 */
	static bool emit_fiber_intrinsic(Generator& generator, std::string_view name, TypeInfoFunction const* function,
		const std::vector<mlir::Value>& arguments, const ast::Node* where, Emitted& result) {

		if (name != "fiber_start" && name != "fiber_resume" && name != "fiber_suspend") {
			return false;
		}
		if (ArchType::x86_64 != generator.options->architecture && ArchType::aarch64 != generator.options->architecture) {
			unsupported(generator, where, "fibers are only made for x86-64 and AArch64 so far (docs/multitasking.md, Open Questions)");
			result = intrinsic_value(zero_of(generator, llvm_type(generator, function->output.empty() ? BUILTIN_int : function->output[0].type)),
				function);
			return true;
		}
		mlir::OpBuilder& b = generator.builder;
		const mlir::Location l = generator.loc;
		if (!generator.module.lookupSymbol<LLVM::LLVMFuncOp>(FIBER_START_SYMBOL)) {
			FiberOffsets offsets;
			Declaration* run = base_declaration_named(generator, "runtime", "fiber_run");
			if (!fiber_offsets(generator, offsets) || run == nullptr) {
				unsupported(generator, where, "base/runtime's fibers aren't what the compiler expects");
				return true;
			}
			// Only the assembly calls it, which LLVM doesn't count as a use, so it's kept by being external
			LLVM::LLVMFuncOp run_function = function_for(generator, run);
			run_function.setLinkage(LLVM::Linkage::External);
			const std::string run_symbol = run_function.getSymName().str();
			if (ArchType::aarch64 == generator.options->architecture) {
				const bool fp = generator.options->cpu_features.find("-fp-armv8") == std::string::npos;
				generator.module_assembly.push_back(fiber_assembly_aarch64(offsets, run_symbol, fp));
				fiber_walk_table(generator, offsets, fp);
			}
			else {
				const bool sse = generator.options->cpu_features.find("-sse") == std::string::npos;
				generator.module_assembly.push_back(fiber_assembly(offsets, run_symbol, sse));
				fiber_walk_table(generator, offsets, sse);
			}
		}
		mlir::Type pointer = pointer_type(generator);
		mlir::Type i32 = integer_type(generator, 4);
		// Declared with the assembly, which is how it's made only once whichever of these comes first
		assembly_function(generator, std::string(FIBER_START_SYMBOL), LLVM::LLVMFunctionType::get(i32, { pointer, pointer, pointer }));
		if (name == "fiber_suspend") {
			LLVM::LLVMFuncOp suspend = assembly_function(generator, std::string(FIBER_SUSPEND_SYMBOL),
				LLVM::LLVMFunctionType::get(LLVM::LLVMVoidType::get(generator.context), { pointer }));
			LLVM::CallOp::create(b, l, suspend, mlir::ValueRange{ arguments[0] });
			result = Emitted{};
			return true;
		}
		LLVM::CallOp call;
		if (name == "fiber_start") {
			// The first segment is the rest of the fiber's block, with its limit STACK_GUARD above the Fiber
			Declaration* block_size = base_declaration_named(generator, "runtime", "FIBER_BLOCK_SIZE");
			Declaration* guard = base_declaration_named(generator, "runtime", "STACK_GUARD");
			Declaration* fiber = base_declaration_named(generator, "runtime", "Fiber");
			if (block_size == nullptr || guard == nullptr || fiber == nullptr || fiber->type_value == nullptr) {
				unsupported(generator, where, "base/runtime's fibers aren't what the compiler expects");
				return true;
			}
			mlir::Value top_offset = emit_constant_value(generator, block_size, BUILTIN_usize, where);
			mlir::Value guard_offset = emit_constant_value(generator, guard, BUILTIN_usize, where);
			mlir::Value limit_offset = LLVM::AddOp::create(b, l, guard_offset,
				constant_int(generator, usize_type(generator), static_cast<int64_t>(fiber->type_value->size)));
			mlir::Type i8 = integer_type(generator, 1);
			mlir::Value top = LLVM::GEPOp::create(b, l, pointer, i8, arguments[0], llvm::SmallVector<LLVM::GEPArg>{ top_offset });
			mlir::Value limit = LLVM::GEPOp::create(b, l, pointer, i8, arguments[0], llvm::SmallVector<LLVM::GEPArg>{ limit_offset });
			LLVM::LLVMFuncOp start = assembly_function(generator, std::string(FIBER_START_SYMBOL),
				LLVM::LLVMFunctionType::get(i32, { pointer, pointer, pointer }));
			call = LLVM::CallOp::create(b, l, start, mlir::ValueRange{ arguments[0], top, limit });
		}
		else {
			LLVM::LLVMFuncOp resume = assembly_function(generator, std::string(FIBER_RESUME_SYMBOL),
				LLVM::LLVMFunctionType::get(i32, { pointer }));
			call = LLVM::CallOp::create(b, l, resume, mlir::ValueRange{ arguments[0] });
		}
		// What it returns: FiberExit's .Yielded (0) or .Finished (1)
		TypeInfo* exit = function->output.empty() ? nullptr : function->output[0].type;
		result = intrinsic_value(exit != nullptr ? convert(generator, call.getResult(), BUILTIN_u32, exit) : call.getResult(), function);
		return true;
	}

	static mlir::Value shift_amount(Generator& generator, mlir::Value amount, mlir::Type target);

	// A vector of bools as LLVM's i1 lanes, which select and the reductions take.
	static mlir::Value mask_bits(Generator& generator, mlir::Value mask) {
		return LLVM::ICmpOp::create(generator.builder, generator.loc, LLVM::ICmpPredicate::ne, mask,
			constant_int(generator, mask.getType(), 0));
	}

	// An amount for every bit of value: one per lane for a vector, as wide as what it shifts.
	static mlir::Value amount_for(Generator& generator, mlir::Value amount, mlir::Type target) {
		if (auto vector = llvm::dyn_cast<mlir::VectorType>(target)) {
			return splat(generator, shift_amount(generator, amount, vector.getElementType()), target);
		}
		return shift_amount(generator, amount, target);
	}

	// A constant argument's value, which the checker made sure is one, like rotate_lanes' count.
	static int64_t constant_argument(mlir::Value argument) {
		if (auto constant = argument.getDefiningOp<LLVM::ConstantOp>()) {
			if (auto integer = llvm::dyn_cast<mlir::IntegerAttr>(constant.getValue())) {
				return integer.getInt();
			}
		}
		return 0;
	}

	// base/intrinsics' vector and bit functions (docs/types.md, Vectors), by name.
	static bool emit_vector_intrinsic(Generator& generator, std::string_view name, TypeInfoFunction const* function,
		const std::vector<mlir::Value>& arguments, Emitted& result) {

		mlir::OpBuilder& b = generator.builder;
		const mlir::Location l = generator.loc;
		TypeInfo* result_type = function->output.empty() ? nullptr : function->output[0].type;
		if (name == "splat") {
			result = value(splat(generator, arguments[0], llvm_type(generator, result_type)), result_type);
			return true;
		}
		if (name == "select" && is_variant(result_type, TypeInfoVariant::VECTOR)) {
			result = value(LLVM::SelectOp::create(b, l, mask_bits(generator, arguments[0]), arguments[1], arguments[2]), result_type);
			return true;
		}
		/*
		 * An integer's or bool's choice without a branch (docs/memory.md, Secrets): a mask of all ones or
		 * all zeros from the condition, passed through an empty assembly block so the optimizer can't see
		 * that it's one or the other, and turn it back into a branch; then (chosen & mask) | (otherwise & ~mask)
		 */
		if (name == "select") {
			mlir::Type type = arguments[1].getType();
			const unsigned bits = std::max(type.getIntOrFloatBitWidth(), 8u);
			mlir::Type wide = b.getIntegerType(bits);
			auto widen = [&](mlir::Value v) {
				return v.getType() == wide ? v : static_cast<mlir::Value>(LLVM::ZExtOp::create(b, l, wide, v));
			};
			mlir::Value mask = LLVM::SubOp::create(b, l, constant_int(generator, wide, 0), widen(arguments[0]));
			mask = assembly(generator, wide, { mask }, "", "=r,0");
			mlir::Value chosen = LLVM::AndOp::create(b, l, widen(arguments[1]), mask);
			mlir::Value otherwise = LLVM::AndOp::create(b, l, widen(arguments[2]),
				LLVM::XOrOp::create(b, l, mask, constant_int(generator, wide, -1)));
			mlir::Value both = LLVM::OrOp::create(b, l, chosen, otherwise);
			result = value(wide == type ? both : static_cast<mlir::Value>(LLVM::TruncOp::create(b, l, type, both)), result_type);
			return true;
		}
		// compiler.declassify and compiler.secret only change what the checker knows
		if (name == "declassify" || name == "secret") {
			/*
			 * With --valgrind-secrets, through memory Memcheck is told is undefined or defined again, so it
			 * reports what depends on a secret (docs/memory.md, Checking the Machine Code)
			 */
			if (generator.options != nullptr && generator.options->valgrind_secrets && !generator.compile_time
				&& ArchType::x86_64 == generator.options->architecture && in_function(generator) && result_type->size > 0) {

				mlir::Value slot = make_raw_slot(generator, arguments[0].getType(), std::max<size_t>(result_type->alignment, 1));
				LLVM::StoreOp::create(b, l, arguments[0], slot);
				valgrind_request(generator, name == "secret" ? MEMCHECK_MAKE_MEM_UNDEFINED : MEMCHECK_MAKE_MEM_DEFINED, slot,
					result_type->size);
				result = value(LLVM::LoadOp::create(b, l, arguments[0].getType(), slot), result_type);
				return true;
			}
			result = value(arguments[0], result_type);
			return true;
		}
		if (name == "rotate_lanes") {
			const int64_t count = static_cast<int64_t>(static_cast<TypeInfoVector const*>(base(result_type))->count);
			const int64_t by = constant_argument(arguments[1]);
			llvm::SmallVector<int32_t> mask;
			for (int64_t i = 0; i < count; ++i) {
				mask.push_back(static_cast<int32_t>((i + by) % count));
			}
			result = value(LLVM::ShuffleVectorOp::create(b, l, arguments[0], arguments[0], mask), result_type);
			return true;
		}
		if (name == "reduce_add" || name == "reduce_and" || name == "reduce_or" || name == "reduce_xor") {
			mlir::Type lane = llvm_type(generator, result_type);
			mlir::Value reduced = name == "reduce_add" ? static_cast<mlir::Value>(LLVM::vector_reduce_add::create(b, l, lane, arguments[0]))
				: name == "reduce_and" ? static_cast<mlir::Value>(LLVM::vector_reduce_and::create(b, l, lane, arguments[0]))
				: name == "reduce_or" ? static_cast<mlir::Value>(LLVM::vector_reduce_or::create(b, l, lane, arguments[0]))
				: static_cast<mlir::Value>(LLVM::vector_reduce_xor::create(b, l, lane, arguments[0]));
			result = value(reduced, result_type);
			return true;
		}
		if (name == "any_true" || name == "all_true") {
			mlir::Value bits = mask_bits(generator, arguments[0]);
			mlir::Type one = b.getI1Type();
			mlir::Value reduced = name == "any_true" ? static_cast<mlir::Value>(LLVM::vector_reduce_or::create(b, l, one, bits))
				: static_cast<mlir::Value>(LLVM::vector_reduce_and::create(b, l, one, bits));
			result = value(reduced, result_type);
			return true;
		}
		if (name == "rotate_left" || name == "rotate_right") {
			mlir::Value amount = amount_for(generator, arguments[1], arguments[0].getType());
			mlir::Value rotated = name == "rotate_left" ? static_cast<mlir::Value>(LLVM::FshlOp::create(b, l, arguments[0], arguments[0], amount))
				: static_cast<mlir::Value>(LLVM::FshrOp::create(b, l, arguments[0], arguments[0], amount));
			result = value(rotated, result_type);
			return true;
		}
		if (name == "byte_swap") {
			result = value(LLVM::ByteSwapOp::create(b, l, arguments[0]), result_type);
			return true;
		}
		return false;
	}

	static Emitted emit_intrinsic(Generator& generator, Declaration* called, TypeInfoFunction const* function,
		const std::vector<mlir::Value>& arguments, const ast::Node* where) {

		const std::string full_name = text_of(called->name);
		std::string_view name = full_name;
		mlir::OpBuilder& b = generator.builder;
		const mlir::Location l = generator.loc;
		TypeInfo* result_type = function->output.empty() ? nullptr : function->output[0].type;
		Emitted result;
		if (name == "trap") {
			LLVM::Trap::create(b, l);
			return never_returning();
		}
		if (name == "stack_pointer") {
			return value(LLVM::StackSaveOp::create(b, l, pointer_type(generator)), result_type);
		}
		// The vector and bit functions are matched by their generic's name, splat for splat[Words]
		if (Emitted vector_result; emit_vector_intrinsic(generator, name.substr(0, name.find('[')), function, arguments, vector_result)) {
			return vector_result;
		}
		if (name == "spin_hint") {
			const ArchType architecture = generator.options != nullptr ? generator.options->architecture : ArchType::x86_64;
			if (ArchType::x86_64 == architecture || ArchType::x86 == architecture) {
				assembly(generator, mlir::Type(), {}, "pause", "~{memory}");
			}
			else if (ArchType::aarch64 == architecture) {
				assembly(generator, mlir::Type(), {}, "yield", "~{memory}");
			}
			return result;
		}
		if (name == "mem_copy") {
			LLVM::MemmoveOp::create(b, l, arguments[0], arguments[1], arguments[2], false);
			return result;
		}
		if (name == "mem_copy_non_overlapping") {
			LLVM::MemcpyOp::create(b, l, arguments[0], arguments[1], arguments[2], false);
			return result;
		}
		if (name == "mem_zero") {
			LLVM::MemsetOp::create(b, l, arguments[0], constant_int(generator, integer_type(generator, 1), 0), arguments[1], false);
			return result;
		}
		// Volatile, so the zeros are written even when nothing reads them after (docs/memory.md, Secrets)
		if (name == "secure_zero") {
			LLVM::MemsetOp::create(b, l, arguments[0], constant_int(generator, integer_type(generator, 1), 0), arguments[1], true);
			return result;
		}
		/*
		 * Where the program's image starts, for addresses relative to it: __ImageBase, which lld-link
		 * defines, for PE/COFF, and __ehdr_start for ELF, weak, since a linker script may leave the
		 * headers out of memory. Null where there's neither.
		 */
		if (name == "image_base") {
			const bool coff = ObjectFormatType::COFF == generator.options->object_format;
			const bool elf = ObjectFormatType::ELF == generator.options->object_format;
			if (generator.compile_time || (!coff && !elf)) {
				return value(zero_of(generator, pointer_type(generator)), result_type);
			}
			const char* symbol = coff ? "__ImageBase" : "__ehdr_start";
			LLVM::GlobalOp base = generator.module.lookupSymbol<LLVM::GlobalOp>(symbol);
			if (!base) {
				mlir::OpBuilder::InsertionGuard guard(generator.builder);
				generator.builder.setInsertionPointToEnd(generator.module.getBody());
				base = LLVM::GlobalOp::create(generator.builder, generator.loc, integer_type(generator, 1), true,
					coff ? LLVM::Linkage::External : LLVM::Linkage::ExternWeak, symbol, mlir::Attribute());
			}
			return value(LLVM::AddressOfOp::create(b, l, base), result_type);
		}
		/*
		 * The table of functions' starts and names, for stack traces: filled in once every function
		 * is generated (generate_function_names), and empty without debug info
		 */
		if (name == "function_names") {
			if (generator.compile_time || result_type == nullptr) {
				return value(zero_of(generator, llvm_type(generator, result_type)), result_type);
			}
			if (!generator.function_names) {
				mlir::OpBuilder::InsertionGuard guard(generator.builder);
				generator.builder.setInsertionPointToEnd(generator.module.getBody());
				generator.function_names = LLVM::GlobalOp::create(generator.builder, generator.loc, llvm_type(generator, result_type),
					true, LLVM::Linkage::Internal, "hemera.function_names", mlir::Attribute(), 8);
				generator.function_names_type = result_type;
			}
			return value(load(generator, result_type, LLVM::AddressOfOp::create(b, l, generator.function_names)), result_type);
		}
		// A call to the stack walker, which lower_to_llvm defines (define_stack_walker)
		if (name == "capture_stack_trace") {
			mlir::Type usize = usize_type(generator);
			LLVM::LLVMFuncOp walker = generator.module.lookupSymbol<LLVM::LLVMFuncOp>(STACK_WALKER_SYMBOL);
			if (!walker) {
				mlir::OpBuilder::InsertionGuard guard(b);
				b.setInsertionPointToEnd(generator.module.getBody());
				walker = LLVM::LLVMFuncOp::create(b, l, STACK_WALKER_SYMBOL,
					LLVM::LLVMFunctionType::get(usize, { pointer_type(generator), usize, usize }));
			}
			auto call = LLVM::CallOp::create(b, l, walker, mlir::ValueRange{ extract(generator, arguments[0], 1),
				extract(generator, arguments[0], 0), arguments[1] });
			return value(call.getResult(), result_type);
		}
		// A suspended fiber's trace, from the walker lower_to_llvm defines (define_stack_walker)
		if (name == "capture_fiber_stack_trace") {
			mlir::Type usize = usize_type(generator);
			LLVM::LLVMFuncOp walker = generator.module.lookupSymbol<LLVM::LLVMFuncOp>(FIBER_STACK_WALKER_SYMBOL);
			if (!walker) {
				mlir::OpBuilder::InsertionGuard guard(b);
				b.setInsertionPointToEnd(generator.module.getBody());
				walker = LLVM::LLVMFuncOp::create(b, l, FIBER_STACK_WALKER_SYMBOL,
					LLVM::LLVMFunctionType::get(usize, { pointer_type(generator), pointer_type(generator), usize }));
			}
			auto call = LLVM::CallOp::create(b, l, walker, mlir::ValueRange{ arguments[0], extract(generator, arguments[1], 1),
				extract(generator, arguments[1], 0) });
			return value(call.getResult(), result_type);
		}
		// The carrier register, which nothing else uses (docs/calling_convention.md, Carrier Register)
		if (name == "carrier") {
			const bool aarch64 = ArchType::aarch64 == generator.options->architecture;
			return value(assembly(generator, pointer_type(generator), {}, aarch64 ? "mov $0, x28" : "movq %r14, $0", "=r,~{memory}"),
				result_type);
		}
		if (name == "uses_c_library") {
			return value(boolean(generator, generator.c_library), result_type);
		}
		// The thread's carrier block, for callbacks from foreign code, in ELF thread-local storage
		if (name == "set_thread_carrier") {
			if (generator.c_library) {
				LLVM::StoreOp::create(b, l, arguments[0], LLVM::AddressOfOp::create(b, l, thread_carrier_global(generator)));
			}
			return result;
		}
		// One global, the program's, zeroed, which only the runtime uses
		if (name == "process_state") {
			LLVM::GlobalOp state = process_state_global(generator);
			if (!state) {
				unsupported(generator, nullptr, "base/runtime's ProcessState isn't what the compiler expects");
				return value(zero_of(generator, pointer_type(generator)), result_type);
			}
			return value(LLVM::AddressOfOp::create(b, l, state), result_type);
		}
		if (name == "set_carrier") {
			const bool aarch64 = ArchType::aarch64 == generator.options->architecture;
			assembly(generator, mlir::Type(), arguments, aarch64 ? "mov x28, $0" : "movq $0, %r14", "r,~{memory}");
			return result;
		}
		if (name.starts_with("volatile_load_")) {
			return value(LLVM::LoadOp::create(b, l, llvm_type(generator, result_type), arguments[0],
				static_cast<unsigned>(result_type->size), true), result_type);
		}
		if (name.starts_with("volatile_store_")) {
			LLVM::StoreOp::create(b, l, arguments[1], arguments[0], static_cast<unsigned>(function->input[1].type->size), true);
			return result;
		}
		if (name.starts_with("fence_") || name.starts_with("compiler_fence_")) {
			const bool compiler_only = name.starts_with("compiler_");
			LLVM::FenceOp::create(b, l, ordering_suffix(name), compiler_only ? "singlethread" : "");
			return result;
		}
		if ((name.starts_with("atomic_") || name.starts_with("interlocked_")) && emit_atomic(generator, name, function, arguments, result)) {
			return result;
		}
		// base/compiler's functions, which the compiler carries out for compile-time code
		if (called->package_path != nullptr && text_of(called->package_path) == std::format("{}compiler", BASE_PACKAGE_PREFIX)) {
			return emit_compiler_call(generator, name, function, arguments, where);
		}
		// The compiler's services to compile-time code (docs/compilation.md, Compile-Time Execution)
		if (name.starts_with("compile_time_")) {
			return emit_compile_time_service(generator, name, function, arguments, where);
		}
		// Generated assembly, made once (docs/calling_convention.md, Entry Functions)
		if (name == "return_to_user") {
			const bool aarch64 = ArchType::aarch64 == generator.options->architecture;
			if (!generator.module.lookupSymbol<LLVM::LLVMFuncOp>(RETURN_TO_USER_SYMBOL)) {
				generator.module_assembly.push_back(aarch64 ? return_to_user_assembly_aarch64() : return_to_user_assembly());
			}
			std::vector<mlir::Type> parameters(arguments.size(), pointer_type(generator));
			LLVM::LLVMFuncOp helper = assembly_function(generator, std::string(RETURN_TO_USER_SYMBOL),
				LLVM::LLVMFunctionType::get(LLVM::LLVMVoidType::get(generator.context), parameters));
			LLVM::CallOp::create(b, l, helper, mlir::ValueRange(arguments));
			return never_returning();
		}
		if (emit_fiber_intrinsic(generator, name, function, arguments, where, result)) {
			return result;
		}
		if (name.starts_with("entry_points[") && ArchType::x86_64 != generator.options->architecture) {
			unsupported(generator, where, "entry_points is x86-64's: on AArch64, aarch64.vector_table makes an entry function's vector table");
			return value(zero_of(generator, pointer_type(generator)), result_type);
		}
		if (name.starts_with("entry_points[") && called->generic_values.size() == 1) {
			Declaration* handler = called->generic_values[0].function;
			if (handler == nullptr || !is_entry_function(static_cast<TypeInfoFunction const*>(handler->value_type))
				|| has_convention(static_cast<TypeInfoFunction const*>(handler->value_type), "syscall_entry")) {
				unsupported(generator, where, "entry_points takes a #calling_convention(.entry) function");
				return value(zero_of(generator, pointer_type(generator)), result_type);
			}
			LLVM::LLVMFuncOp address = function_for(generator, handler);
			return value(entry_points_of(generator, address.getSymName().str()), result_type);
		}
		if (name.starts_with("vector_table[") && called->generic_values.size() == 1) {
			Declaration* handler = called->generic_values[0].function;
			if (handler == nullptr || !is_entry_function(static_cast<TypeInfoFunction const*>(handler->value_type))) {
				unsupported(generator, where, "vector_table takes a #calling_convention(.entry) function");
				return value(zero_of(generator, pointer_type(generator)), result_type);
			}
			const std::string symbol = function_for(generator, handler).getSymName().str();
			const std::string table = symbol + ".vector_table";
			if (!generator.module.lookupSymbol<LLVM::LLVMFuncOp>(table)) {
				generator.module_assembly.push_back(vector_table_aarch64(symbol));
			}
			LLVM::LLVMFuncOp address = assembly_function(generator, table, no_arguments(generator));
			return value(LLVM::AddressOfOp::create(b, l, address), result_type);
		}
		// Each architecture's instructions, from its own package (base/intrinsics/platform.hsc)
		const std::string_view package = called->package_path != nullptr ? std::string_view(*called->package_path) : std::string_view();
		/*
		 * Another architecture's. In compile-time code, compiled for the machine the compiler runs on, like a
		 * constant holding a function that uses it, it can't run, so it traps if it's ever called; anywhere else
		 * it's an error
		 */
		const ArchType architecture = generator.options->architecture;
		if ((package.ends_with("intrinsics/x86_64") && ArchType::x86_64 != architecture)
			|| (package.ends_with("intrinsics/aarch64") && ArchType::aarch64 != architecture)) {
			if (!generator.compile_time) {
				unsupported(generator, where, std::format("{} is another architecture's instruction", full_name));
			}
			LLVM::Trap::create(b, l);
			return result_type != nullptr ? value(zero_of(generator, llvm_type(generator, result_type)), result_type) : result;
		}
		if (package.ends_with("intrinsics/x86_64") && emit_x86_64(generator, name, arguments, function, result)) {
			return result;
		}
		if (package.ends_with("intrinsics/aarch64") && emit_aarch64(generator, name, called, arguments, function, result)) {
			return result;
		}
		unsupported(generator, where, std::format("the intrinsic {} can't be generated yet", full_name));
		return result_type != nullptr ? value(zero_of(generator, llvm_type(generator, result_type)), result_type) : result;
	}

	// A function in the compiler, which the JIT finds; not dso_local, since it may be far from the compiled code.
	static LLVM::LLVMFuncOp compiler_function(Generator& generator, const char* symbol, mlir::Type result,
		const std::vector<mlir::Type>& parameters) {

		if (auto existing = generator.module.lookupSymbol<LLVM::LLVMFuncOp>(symbol)) {
			return existing;
		}
		mlir::OpBuilder::InsertionGuard guard(generator.builder);
		generator.builder.setInsertionPointToEnd(generator.module.getBody());
		return LLVM::LLVMFuncOp::create(generator.builder, generator.loc, symbol, LLVM::LLVMFunctionType::get(result, parameters));
	}

	// A number as an i64, for the compiler's services.
	static mlir::Value as_i64(Generator& generator, mlir::Value number) {
		mlir::Type i64 = integer_type(generator, 8);
		const unsigned width = number.getType().getIntOrFloatBitWidth();
		return width == 64 ? number : static_cast<mlir::Value>(LLVM::ZExtOp::create(generator.builder, generator.loc, i64, number));
	}

	// A SourceCodeLocation's file path, line and column, as the compiler's services take them.
	static std::vector<mlir::Value> location_parts(Generator& generator, mlir::Value location, TypeInfo const* type) {
		auto structure = static_cast<TypeInfoStruct const*>(base(type));
		std::vector<mlir::Value> parts;
		size_t offset = 0;
		TypeInfo* member = nullptr;
		std::vector<int64_t> path;
		find_member(generator, structure, intern(std::string("file_path")), offset, member, path);
		mlir::Value file = LLVM::ExtractValueOp::create(generator.builder, generator.loc, location, path);
		parts.push_back(extract(generator, file, 1));
		parts.push_back(extract(generator, file, 0));
		for (const char* field : { "line", "column" }) {
			path.clear();
			find_member(generator, structure, intern(std::string(field)), offset, member, path);
			parts.push_back(as_i64(generator, LLVM::ExtractValueOp::create(generator.builder, generator.loc, location, path)));
		}
		return parts;
	}

	/*
	 * intrinsics.compile_time_log and the rest: calls to the compiler, with strings, views and locations taken
	 * apart into pointers and numbers. Only compile-time code can make them.
	 */
	static Emitted emit_compile_time_service(Generator& generator, std::string_view name, TypeInfoFunction const* function,
		const std::vector<mlir::Value>& arguments, const ast::Node* where) {

		TypeInfo* result_type = function->output.empty() ? nullptr : function->output[0].type;
		if (!generator.compile_time) {
			unsupported(generator, where, std::format("intrinsics.{} is only for compile-time code", name));
			return result_type != nullptr ? value(zero_of(generator, llvm_type(generator, result_type)), result_type) : Emitted{};
		}
		mlir::OpBuilder& b = generator.builder;
		const mlir::Location l = generator.loc;
		mlir::Type i64 = integer_type(generator, 8);
		mlir::Type pointer = pointer_type(generator);
		mlir::Type nothing = LLVM::LLVMVoidType::get(generator.context);
		if (name == "compile_time_log") {
			std::vector<mlir::Value> values{ as_i64(generator, arguments[0]), extract(generator, arguments[1], 1),
				extract(generator, arguments[1], 0), extract(generator, arguments[2], 1), extract(generator, arguments[2], 0) };
			for (mlir::Value part : location_parts(generator, arguments[3], function->input[3].type)) {
				values.push_back(part);
			}
			LLVM::LLVMFuncOp log = compiler_function(generator, COMPILE_TIME_LOG_SYMBOL, nothing,
				{ i64, pointer, i64, pointer, i64, pointer, i64, i64, i64 });
			LLVM::CallOp::create(b, l, log, values);
			return Emitted{};
		}
		if (name == "compile_time_allocate") {
			LLVM::LLVMFuncOp allocate = compiler_function(generator, COMPILE_TIME_ALLOCATE_SYMBOL, pointer, { i64, i64 });
			auto call = LLVM::CallOp::create(b, l, allocate, mlir::ValueRange{ as_i64(generator, arguments[0]), as_i64(generator, arguments[1]) });
			return value(call.getResult(), result_type);
		}
		if (name == "compile_time_free") {
			LLVM::CallOp::create(b, l, compiler_function(generator, COMPILE_TIME_FREE_SYMBOL, nothing, { pointer }),
				mlir::ValueRange{ arguments[0] });
			return Emitted{};
		}
		if (name == "compile_time_fail") {
			std::vector<mlir::Value> values{ extract(generator, arguments[0], 1), extract(generator, arguments[0], 0) };
			for (mlir::Value part : location_parts(generator, arguments[1], function->input[1].type)) {
				values.push_back(part);
			}
			LLVM::LLVMFuncOp fail = compiler_function(generator, COMPILE_TIME_FAIL_SYMBOL, nothing, { pointer, i64, pointer, i64, i64, i64 });
			LLVM::CallOp::create(b, l, fail, values);
			return never_returning();
		}
		unsupported(generator, where, std::format("the intrinsic {} can't be generated yet", name));
		return Emitted{};
	}

	/*
	 * A C function the compiler calls a check or a step through, once the build package's code has run, with a
	 * frame: the function, then each argument (8 or 16 bytes each), then room for its boolean result. It gives
	 * the function a carrier block and the compile-time context, like a run's entry does.
	 */
	static mlir::Value callback_caller(Generator& generator, TypeInfoFunction const* callback, const std::string& symbol,
		const ast::Node* where) {

		LLVM::LLVMFuncOp caller = generator.module.lookupSymbol<LLVM::LLVMFuncOp>(symbol);
		if (!caller) {
			mlir::OpBuilder::InsertionGuard guard(generator.builder);
			generator.builder.setInsertionPointToEnd(generator.module.getBody());
			caller = LLVM::LLVMFuncOp::create(generator.builder, generator.loc, symbol,
				LLVM::LLVMFunctionType::get(LLVM::LLVMVoidType::get(generator.context), { pointer_type(generator) }));
			mlir::Block* entry = caller.addEntryBlock(generator.builder);
			generator.builder.setInsertionPointToEnd(entry);
			FunctionState state;
			state.declaration = generator.state != nullptr ? generator.state->declaration : nullptr;
			state.entry = entry;
			FunctionState* outer = generator.state;
			generator.state = &state;
			mlir::Value context = enter_compile_time(generator, where);
			mlir::Value frame = entry->getArgument(0);
			std::vector<mlir::Value> operands{ LLVM::LoadOp::create(generator.builder, generator.loc, pointer_type(generator), frame), context };
			size_t offset = 8;
			for (const FunctionInput& input : callback->input) {
				// One too large for registers is passed where it is in the frame, which is the compiler's copy
				mlir::Value at = offset_address(generator, frame, offset);
				operands.push_back(parameter_by_pointer(callback, input) ? at : load(generator, input.type, at));
				offset += (input.type->size + 7) & ~size_t(7);
			}
			const bool through_pointer = result_through_pointer(callback);
			if (through_pointer) {
				operands.insert(operands.begin() + 1, offset_address(generator, frame, offset));
			}
			auto call = LLVM::CallOp::create(generator.builder, generator.loc, function_type(generator, callback, true), operands);
			call.setCConv(convention_of(generator, callback));
			if (!callback->output.empty() && !through_pointer) {
				store(generator, call.getResult(), offset_address(generator, frame, offset));
			}
			LLVM::ReturnOp::create(generator.builder, generator.loc, mlir::ValueRange{});
			generator.state = outer;
		}
		return LLVM::AddressOfOp::create(generator.builder, generator.loc, caller);
	}

	/*
	 * A call to one of base/compiler's functions, like compiler.package_info: each argument in a slot, and the
	 * compiler's service called with the function's name, pointers to them and to where the result goes, the
	 * context, and the calling file.
	 */
	static Emitted emit_compiler_call(Generator& generator, std::string_view name, TypeInfoFunction const* function,
		const std::vector<mlir::Value>& arguments, const ast::Node* where) {

		TypeInfo* result_type = function->output.empty() ? nullptr : function->output[0].type;
		// compiler.satisfies: what the checker worked out, a constant, at compile time or run time
		if (name == "satisfies") {
			auto satisfied = generator.state != nullptr && generator.state->checked != nullptr
				? generator.state->checked->satisfied.find(where) : decltype(generator.state->checked->satisfied)::const_iterator();
			const bool holds = generator.state != nullptr && generator.state->checked != nullptr
				&& satisfied != generator.state->checked->satisfied.end() && satisfied->second;
			return value(boolean(generator, holds), BUILTIN_bool);
		}
		if (!generator.compile_time) {
			unsupported(generator, where, std::format("compiler.{} is only for compile-time code", name));
			return result_type != nullptr ? value(zero_of(generator, llvm_type(generator, result_type)), result_type) : Emitted{};
		}
		mlir::OpBuilder& b = generator.builder;
		const mlir::Location l = generator.loc;
		mlir::Type pointer = pointer_type(generator);
		mlir::Type i64 = integer_type(generator, 8);
		const size_t count = std::min(arguments.size(), function->input.size());
		// One more, for the caller of a check or a step
		mlir::Value list = make_raw_slot(generator, LLVM::LLVMArrayType::get(pointer, count + 1), 8);
		for (size_t i = 0; i < count; ++i) {
			mlir::Value slot = make_slot(generator, function->input[i].type);
			store(generator, arguments[i], slot);
			store(generator, slot, offset_address(generator, list, i * 8));
		}
		if ((name == "add_check" || name == "add_step") && count > 0) {
			auto callback = static_cast<TypeInfoFunction const*>(base(function->input[0].type));
			store(generator, callback_caller(generator, callback, std::format("hemera.call_{}", name.substr(4)), where),
				offset_address(generator, list, count * 8));
		}
		mlir::Value result = result_type != nullptr ? make_slot(generator, result_type) : zero_of(generator, pointer);
		if (result_type != nullptr) {
			store_zero(generator, result_type, result);
		}
		const std::string file = current_file(generator);
		LLVM::LLVMFuncOp service = compiler_function(generator, COMPILER_SERVICE_SYMBOL, LLVM::LLVMVoidType::get(generator.context),
			{ pointer, i64, pointer, pointer, i64, pointer, pointer, i64 });
		LLVM::CallOp::create(b, l, service, mlir::ValueRange{ string_bytes(generator, std::string(name)),
			constant_int(generator, i64, static_cast<int64_t>(name.size())), result, list,
			constant_int(generator, i64, static_cast<int64_t>(count)), generator.state->context, string_bytes(generator, file),
			constant_int(generator, i64, static_cast<int64_t>(file.size())) });
		return result_type != nullptr ? location(result, result_type) : Emitted{};
	}

	/*
	 * #code, at compile time (docs/compilation.md, Code Values): what it splices, each as an any, then
	 * compiler.quote_code with the quote's node, which copies the quote with them in it.
	 */
	static Emitted emit_quote(Generator& generator, ast::Node* node) {
		const CheckedNode* found = checked(generator, node);
		if (found == nullptr || found->called == nullptr) {
			unsupported(generator, node, "#code wasn't checked");
			return Emitted{};
		}
		const size_t count = node->children.size();
		mlir::Type any = llvm_type(generator, BUILTIN_any);
		mlir::Value splices = make_raw_slot(generator, LLVM::LLVMArrayType::get(any, std::max<size_t>(count, 1)), 8);
		for (size_t i = 0; i < count; ++i) {
			ast::Node* splice = node->children[i];
			const CheckedNode* spliced = checked(generator, splice);
			// A literal takes its usual type, as it would in a variable
			TypeInfo* expected = spliced != nullptr ? spliced->type : nullptr;
			if (spliced != nullptr) {
				const ValueKind kind = spliced->kind;
				expected = ValueKind::UNTYPED_INTEGER == kind ? BUILTIN_int
					: ValueKind::UNTYPED_FLOAT == kind ? BUILTIN_f64
					: ValueKind::UNTYPED_STRING == kind ? BUILTIN_string
					: ValueKind::UNTYPED_BOOLEAN == kind ? BUILTIN_bool
					: ValueKind::TYPE == kind ? BUILTIN_type
					: expected;
			}
			const Emitted emitted = emit_expression(generator, splice, expected);
			store(generator, convert_emitted(generator, emitted, BUILTIN_any), offset_address(generator, splices, i * 16));
		}
		mlir::Value view = make_view(generator, constant_int(generator, usize_type(generator), static_cast<int64_t>(count)), splices);
		mlir::Value quote = constant_int(generator, integer_type(generator, 8), static_cast<int64_t>(reinterpret_cast<uintptr_t>(node)));
		return emit_compiler_call(generator, "quote_code", found->called, { quote, view }, node);
	}

	// Whether a declaration is an intrinsic: a function in base without a body, which isn't #foreign.
	static bool is_intrinsic(Declaration* called) {
		return called != nullptr && called->foreign_library == nullptr && is_base_package(called->package_path)
			&& function_body(called->generic != nullptr ? called->generic : called) == nullptr;
	}

	/*
	 * A call: its arguments matched to the function's parameters like the checker does, in order,
	 * then by name, then defaults; the varargs parameter takes the rest of those in order.
	 */
	static Emitted emit_call(Generator& generator, ast::Node* paren, const std::vector<ast::Node*>& argument_nodes,
		const Emitted& callee, const CheckedNode* found, const std::vector<Emitted>& piped) {

		if (ValueKind::BUILTIN_FUNCTION == callee.kind) {
			return emit_builtin_call(generator, paren, argument_nodes, callee);
		}
		if (ValueKind::VARIANT == callee.kind) {
			auto union_type = static_cast<TypeInfoUnion const*>(base(callee.type));
			const UnionVariant& variant = union_type->variants[callee.variant];
			std::vector<mlir::Value> values;
			for (size_t i = 0; i < argument_nodes.size() && i < variant.types.size(); ++i) {
				values.push_back(emit_as(generator, argument_nodes[i], variant.types[i]));
			}
			return value(make_variant(generator, callee.type, callee.variant, values, variant.types), callee.type);
		}
		TypeInfoFunction const* function = found->called;
		Declaration* called = found->called_declaration;
		/*
		 * compiler.require_any(A(T), B(T)): each alternative run, bracketed so the compiler can tell
		 * whether any of them was met (docs/types.md, Constraints)
		 */
		if (is_compiler_function(called, "require_any")) {
			const TypeInfoFunction bracket;
			emit_compiler_call(generator, "require_any_begin", &bracket, {}, paren);
			for (ast::Node* alternative : argument_nodes) {
				emit_expression(generator, alternative, nullptr);
				emit_compiler_call(generator, "require_any_next", &bracket, {}, paren);
			}
			emit_compiler_call(generator, "require_any_end", &bracket, {}, paren);
			return Emitted{};
		}
		if (function == nullptr) {
			unsupported(generator, paren, "this call can't be generated yet");
			return Emitted{};
		}
		if (called != nullptr && !is_intrinsic(called) && called->foreign_library == nullptr
			&& function_body(called->generic != nullptr ? called->generic : called) == nullptr) {
			unsupported(generator, paren, std::format("calling {}, which has no body, isn't supported yet", text_of(called->name)));
			return Emitted{};
		}
		// In a constant's value, the call would have to run while compiling
		if (!in_function(generator)) {
			unsupported(generator, paren, "a call in a constant's value needs compile-time execution, which isn't supported yet");
			TypeInfo* result_type = function->output.size() == 1 ? function->output[0].type : nullptr;
			return result_type != nullptr ? value(zero_of(generator, llvm_type(generator, result_type)), result_type) : Emitted{};
		}
		// What a pipe passed fills its placeholders in order or by number, or comes first
		std::vector<CallArgument> positional;
		std::vector<std::pair<InternedString, ast::Node*>> named;
		const bool placeholders = std::any_of(argument_nodes.begin(), argument_nodes.end(), is_placeholder);
		if (!placeholders) {
			for (const Emitted& each : piped) {
				positional.push_back({ nullptr, true, each });
			}
		}
		size_t next_piped = 0;
		for (ast::Node* argument : argument_nodes) {
			if (ast::NodeType::UNDERSCORE == argument->node_type && next_piped < piped.size()) {
				positional.push_back({ argument, true, piped[next_piped++] });
			}
			else if (ast::NodeType::PIPE_REORDER_IDENTIFIER == argument->node_type) {
				const size_t number = std::stoul(text_of(argument->value.value).substr(1));
				positional.push_back({ argument, true, piped[number - 1] });
			}
			else if (ast::NodeType::BINARY_OPERATOR == argument->node_type && is_assign(argument)
				&& argument->children.size() == 2 && ast::NodeType::IDENTIFIER == argument->children[0]->node_type) {
				named.emplace_back(argument->children[0]->value.value, argument->children[1]);
			}
			else {
				positional.push_back({ argument, false, {} });
			}
		}
		const std::vector<ParameterNode> parameters = parameter_nodes(called);
		// Intrinsics take values; other calls take a large value as a pointer to a copy (parameter_by_pointer)
		const bool lowered = !is_intrinsic(called);
		std::vector<mlir::Value> arguments;
		size_t next = 0;
		for (size_t i = 0; i < function->input.size(); ++i) {
			const FunctionInput& input = function->input[i];
			if (input.is_varargs) {
				/*
				 * A view of them passed on, with the values after it going to the parameters after
				 * the varargs, or the rest in order, in a stack array whose view is passed
				 */
				if (next < positional.size()) {
					const CallArgument& first = positional[next];
					TypeInfo* first_type = first.has_value ? first.given.type : type_at(generator, first.node, nullptr);
					if (is_variant(first_type, TypeInfoVariant::ARRAY)
						&& ArrayType::VIEW == static_cast<TypeInfoArray const*>(base(first_type))->array_type
						&& base(static_cast<TypeInfoArray const*>(base(first_type))->element_type) == base(input.type)) {
						arguments.push_back(first.has_value ? value_of(generator, first.given)
							: value_of(generator, emit_expression(generator, first.node, nullptr)));
						++next;
						continue;
					}
				}
				std::vector<mlir::Value> values;
				for (; next < positional.size(); ++next) {
					values.push_back(argument_as(generator, positional[next], input.type));
				}
				mlir::Value data = zero_of(generator, pointer_type(generator));
				if (!values.empty()) {
					data = make_raw_slot(generator, LLVM::LLVMArrayType::get(llvm_type(generator, input.type), values.size()),
						input.type->alignment);
					for (size_t j = 0; j < values.size(); ++j) {
						store(generator, values[j], element_address(generator, data, input.type,
							constant_int(generator, usize_type(generator), static_cast<int64_t>(j))));
					}
				}
				arguments.push_back(make_view(generator, constant_int(generator, usize_type(generator),
					static_cast<int64_t>(values.size())), data));
				continue;
			}
			const bool by_pointer = lowered && parameter_by_pointer(function, input);
			if (next < positional.size()) {
				arguments.push_back(by_pointer ? argument_copy(generator, positional[next++], input.type)
					: argument_as(generator, positional[next++], input.type));
				continue;
			}
			InternedString name = input.name != nullptr ? input.name : (i < parameters.size() ? parameters[i].name : nullptr);
			ast::Node* named_node = nullptr;
			for (const auto& [argument_name, node] : named) {
				if (name != nullptr && *argument_name == *name) {
					named_node = node;
				}
			}
			if (by_pointer && named_node != nullptr) {
				arguments.push_back(argument_copy(generator, emit_expression(generator, named_node, input.type), input.type));
				continue;
			}
			mlir::Value given = named_node != nullptr ? emit_as(generator, named_node, input.type)
				: emit_default(generator, called, input, i, input.type, paren);
			arguments.push_back(by_pointer ? value_copy(generator, given, input.type) : given);
		}
		if (is_intrinsic(called)) {
			return emit_intrinsic(generator, called, function, arguments, paren);
		}
		const bool by_name = called != nullptr && DeclarationKind::FUNCTION == called->kind;
		// The context goes first, to the functions that take one: a callback only by name, to its body
		if (takes_context(generator, function, called) && (by_name || !is_callback(generator, function))) {
			arguments.insert(arguments.begin(), generator.state->context);
		}
		// And before that, where results too large for registers go
		mlir::Value results = result_through_pointer(function) ? results_slot(generator, function) : mlir::Value();
		if (results) {
			arguments.insert(arguments.begin(), results);
		}
		/*
		 * A foreign function's callbacks run with this context, which is kept in the carrier block
		 * for the call (docs/calling_convention.md, Calls to Foreign Code)
		 */
		mlir::Value foreign_context_slot;
		mlir::Value outer_foreign_context;
		size_t foreign_context = 0;
		if (by_name && called->foreign_library != nullptr && generator.state->context
			&& runtime_offset(generator, "CarrierBlock", "foreign_context", foreign_context)) {
			mlir::Value carrier = assembly(generator, pointer_type(generator), {}, carrier_to_operand(generator), "=r,~{memory}");
			foreign_context_slot = offset_address(generator, carrier, foreign_context);
			outer_foreign_context = LLVM::LoadOp::create(generator.builder, generator.loc, pointer_type(generator), foreign_context_slot);
			LLVM::StoreOp::create(generator.builder, generator.loc, generator.state->context, foreign_context_slot);
		}
		LLVM::CallOp call;
		if (by_name) {
			LLVM::LLVMFuncOp target = function_for(generator, called);
			auto body = generator.entry_bodies.find(called);
			if (is_callback(generator, function) && body != generator.entry_bodies.end()) {
				target = body->second;
			}
			call = LLVM::CallOp::create(generator.builder, generator.loc, target, arguments);
		}
		else {
			// Through a function value: its pointer first
			std::vector<mlir::Value> operands{ value_of(generator, callee) };
			operands.insert(operands.end(), arguments.begin(), arguments.end());
			call = LLVM::CallOp::create(generator.builder, generator.loc,
				function_type(generator, function, takes_context(generator, function, nullptr) && !is_callback(generator, function)), operands);
			call.setCConv(convention_of(generator, function));
		}
		if (foreign_context_slot) {
			LLVM::StoreOp::create(generator.builder, generator.loc, outer_foreign_context, foreign_context_slot);
		}
		/*
		 * A function that starts without a context has no stack check, since there's no carrier
		 * yet, so a checked function it calls stays a call, to keep its check.
		 */
		FunctionState& caller = *generator.state;
		if (TargetStackCheck::Off != generator.options->stack_check && caller.type != nullptr
			&& !takes_context(generator, caller.type, caller.declaration)) {
			call.setNoInlineAttr(generator.builder.getUnitAttr());
		}
		return call_results(generator, function, call, results);
	}

	/*
	 * What follows a value, flat, from start: .member, (arguments), [index] or [type arguments],
	 * and ^, each step's result as the checker recorded it at its node.
	 */
	static Emitted emit_steps(Generator& generator, ast::Node* node, size_t start, Emitted current) {
		for (size_t i = start; i < node->children.size(); ++i) {
			ast::Node* child = node->children[i];
			std::vector<ast::Node*> arguments;
			while (i + 1 < node->children.size() && !is_postfix_marker(node->children[i + 1])) {
				arguments.push_back(node->children[++i]);
			}
			const ast::NodeType type = child->node_type;
			if (ast::NodeType::PAREN_GROUP == type && arguments.empty() && !child->children.empty()) {
				arguments.assign(child->children.begin(), child->children.end());
			}
			ast::Node* at = ast::NodeType::DOT_ACCESS == type && !arguments.empty() ? arguments[0] : child;
			const CheckedNode* found = checked(generator, at);
			if (found == nullptr || ValueKind::POISONED == found->kind) {
				unsupported(generator, at, "this wasn't checked");
				return Emitted{};
			}
			if (ast::NodeType::DOT_ACCESS == type) {
				if (ValueKind::PACKAGE == current.kind) {
					current = emit_name(generator, arguments[0], found, nullptr);
				}
				else if (ValueKind::TYPE == current.kind && ValueKind::VARIANT == found->kind) {
					current = Emitted{};
					current.kind = ValueKind::VARIANT;
					current.type = found->type;
					current.variant = found->variant;
				}
				else if (ValueKind::TYPE == current.kind) {
					// An enum's member
					current = value(constant_int(generator, llvm_type(generator, found->type),
						enum_value(found->type, arguments[0]->value.value)), found->type);
				}
				else {
					current = emit_member(generator, current, arguments[0], found);
				}
			}
			else if (ast::NodeType::PAREN_GROUP == type) {
				bool last_call = true;
				for (size_t j = i + 1; j < node->children.size(); ++j) {
					if (ast::NodeType::PAREN_GROUP == node->children[j]->node_type) {
						last_call = false;
					}
				}
				std::vector<Emitted> piped;
				if (last_call) {
					piped = std::move(generator.piped);
					generator.piped.clear();
				}
				current = emit_call(generator, child, arguments, current, found, piped);
			}
			else if (ast::NodeType::ARRAY_DIMENSION == type) {
				// A generic function named with its arguments and not called, like release_in_place[T]: that instance
				if (ValueKind::GENERIC_FUNCTION == current.kind && ValueKind::VALUE == found->kind && found->declaration != nullptr
					&& DeclarationKind::FUNCTION == found->declaration->kind) {
					LLVM::LLVMFuncOp function = function_for(generator, found->declaration);
					current = value(LLVM::AddressOfOp::create(generator.builder, generator.loc, function), found->declaration->value_type);
				}
				else if (ValueKind::GENERIC_FUNCTION != current.kind) {
					current = emit_index(generator, current, arguments[0], found);
				}
			}
			else {
				current = location(value_of(generator, current), found->type);
			}
			if (ValueKind::RESULTS != current.kind && ValueKind::NOTHING != current.kind) {
				current.kind = found->kind;
				if (found->type != nullptr) {
					current.type = found->type;
				}
				// A relative pointer's place: read as the pointer it holds, through what's stored there
				current.relative = current.address ? found->stored_type : nullptr;
			}
		}
		return current;
	}

	// A name and what follows it.
	static Emitted emit_postfix(Generator& generator, ast::Node* node, TypeInfo* expected) {
		const CheckedNode* whole = checked(generator, node);
		if (whole != nullptr && ValueKind::TYPE == whole->kind) {
			Emitted result;
			result.kind = ValueKind::TYPE;
			result.type = whole->type;
			return result;
		}
		const CheckedNode* head = head_of(generator, node);
		if (node->children.empty() || head == nullptr) {
			return emit_name(generator, node, head != nullptr ? head : whole, expected);
		}
		// For package.Name, the head is Name
		Emitted current = emit_name(generator, head->next > 0 ? node->children[head->next - 1] : node, head,
			node->children.size() == head->next ? expected : nullptr);
		return emit_steps(generator, node, head->next, current);
	}

	// ---------------------------------------------------------------------------------------------
	// Operators

	static bool is_comparison(TokenType op) {
		return TokenType::OPERATOR_EQUAL == op || TokenType::OPERATOR_NOT_EQUAL == op
			|| TokenType::SYM_LT == op || TokenType::SYM_GT == op
			|| TokenType::OPERATOR_LESS_THAN_OR_EQUAL == op || TokenType::OPERATOR_GREATER_THAN_OR_EQUAL == op;
	}

	static bool is_shift(TokenType op) {
		return TokenType::OPERATOR_LEFT_SHIFT == op || TokenType::OPERATOR_RIGHT_SHIFT_ARITHMETIC == op
			|| TokenType::OPERATOR_RIGHT_SHIFT_LOGICAL == op;
	}

	// The type two operands share, as the checker found it: the typed one's, or the one the other converts to.
	static TypeInfo* shared_type(Generator& generator, ast::Node* left, ast::Node* right, TypeInfo* expected) {
		const CheckedNode* left_checked = checked(generator, left);
		const CheckedNode* right_checked = checked(generator, right);
		const bool left_typed = left_checked != nullptr && !is_untyped(left_checked->kind);
		const bool right_typed = right_checked != nullptr && !is_untyped(right_checked->kind);
		// A type, like int in a.type == int, is a type value
		// Endian-specific values are compared as their native types (docs/types.md, Endian-Specific Types)
		TypeInfo* left_type = left_typed && ValueKind::TYPE == left_checked->kind ? BUILTIN_type
			: left_typed ? native_of(left_checked->type) : nullptr;
		TypeInfo* right_type = right_typed && ValueKind::TYPE == right_checked->kind ? BUILTIN_type
			: right_typed ? native_of(right_checked->type) : nullptr;
		if (left_typed && right_typed) {
			return can_implicitly_convert_to(right_type, left_type) ? left_type : right_type;
		}
		if (left_typed) {
			return left_type;
		}
		if (right_typed) {
			return right_type;
		}
		ValueKind kind = left_checked != nullptr ? left_checked->kind : ValueKind::UNTYPED_INTEGER;
		if (right_checked != nullptr && ValueKind::UNTYPED_FLOAT == right_checked->kind) {
			kind = ValueKind::UNTYPED_FLOAT;
		}
		return untyped_as(kind, expected);
	}

	static mlir::Value compare(Generator& generator, TokenType op, mlir::Value left, mlir::Value right, TypeInfo const* type) {
		if (is_float(type)) {
			const LLVM::FCmpPredicate predicate = TokenType::OPERATOR_EQUAL == op ? LLVM::FCmpPredicate::oeq
				: TokenType::OPERATOR_NOT_EQUAL == op ? LLVM::FCmpPredicate::une
				: TokenType::SYM_LT == op ? LLVM::FCmpPredicate::olt
				: TokenType::SYM_GT == op ? LLVM::FCmpPredicate::ogt
				: TokenType::OPERATOR_LESS_THAN_OR_EQUAL == op ? LLVM::FCmpPredicate::ole
				: LLVM::FCmpPredicate::oge;
			return LLVM::FCmpOp::create(generator.builder, generator.loc, predicate, left, right);
		}
		const bool signed_ = is_signed(type);
		const LLVM::ICmpPredicate predicate = TokenType::OPERATOR_EQUAL == op ? LLVM::ICmpPredicate::eq
			: TokenType::OPERATOR_NOT_EQUAL == op ? LLVM::ICmpPredicate::ne
			: TokenType::SYM_LT == op ? (signed_ ? LLVM::ICmpPredicate::slt : LLVM::ICmpPredicate::ult)
			: TokenType::SYM_GT == op ? (signed_ ? LLVM::ICmpPredicate::sgt : LLVM::ICmpPredicate::ugt)
			: TokenType::OPERATOR_LESS_THAN_OR_EQUAL == op ? (signed_ ? LLVM::ICmpPredicate::sle : LLVM::ICmpPredicate::ule)
			: (signed_ ? LLVM::ICmpPredicate::sge : LLVM::ICmpPredicate::uge);
		return LLVM::ICmpOp::create(generator.builder, generator.loc, predicate, left, right);
	}

	// An arithmetic, bitwise or shift operator on two values of type.
	static mlir::Value arithmetic(Generator& generator, TokenType op, mlir::Value left, mlir::Value right, TypeInfo const* type,
		const ast::Node* where) {

		mlir::OpBuilder& b = generator.builder;
		const mlir::Location l = generator.loc;
		if (is_float(type)) {
			if (TokenType::OPERATOR_PLUS == op) {
				return LLVM::FAddOp::create(b, l, left, right);
			}
			if (TokenType::OPERATOR_MINUS == op) {
				return LLVM::FSubOp::create(b, l, left, right);
			}
			if (TokenType::OPERATOR_MULTIPLY == op) {
				return LLVM::FMulOp::create(b, l, left, right);
			}
			if (TokenType::OPERATOR_DIVIDE == op) {
				return LLVM::FDivOp::create(b, l, left, right);
			}
			unsupported(generator, where, "this operator on floats can't be generated yet");
			return left;
		}
		const bool signed_ = is_signed(type);
		if (TokenType::OPERATOR_PLUS == op) {
			return LLVM::AddOp::create(b, l, left, right);
		}
		if (TokenType::OPERATOR_MINUS == op) {
			return LLVM::SubOp::create(b, l, left, right);
		}
		if (TokenType::OPERATOR_MULTIPLY == op) {
			return LLVM::MulOp::create(b, l, left, right);
		}
		if (TokenType::OPERATOR_DIVIDE == op) {
			return signed_ ? static_cast<mlir::Value>(LLVM::SDivOp::create(b, l, left, right))
				: static_cast<mlir::Value>(LLVM::UDivOp::create(b, l, left, right));
		}
		if (TokenType::OPERATOR_MODULUS == op || (TokenType::OPERATOR_REMAINDER == op && !signed_)) {
			// % is truncated, like C's
			return signed_ ? static_cast<mlir::Value>(LLVM::SRemOp::create(b, l, left, right))
				: static_cast<mlir::Value>(LLVM::URemOp::create(b, l, left, right));
		}
		if (TokenType::OPERATOR_REMAINDER == op) {
			// %% is floored: the truncated one, plus the divisor when their signs differ
			mlir::Value truncated = LLVM::SRemOp::create(b, l, left, right);
			mlir::Value zero = constant_int(generator, left.getType(), 0);
			mlir::Value nonzero = LLVM::ICmpOp::create(b, l, LLVM::ICmpPredicate::ne, truncated, zero);
			mlir::Value signs = LLVM::XOrOp::create(b, l, truncated, right);
			mlir::Value differ = LLVM::ICmpOp::create(b, l, LLVM::ICmpPredicate::slt, signs, zero);
			mlir::Value adjust = LLVM::AndOp::create(b, l, nonzero, differ);
			return LLVM::SelectOp::create(b, l, adjust, LLVM::AddOp::create(b, l, truncated, right), truncated);
		}
		if (TokenType::SYM_AMPERSAND == op) {
			return LLVM::AndOp::create(b, l, left, right);
		}
		if (TokenType::OPERATOR_BITWISE_OR == op) {
			return LLVM::OrOp::create(b, l, left, right);
		}
		if (TokenType::OPERATOR_BITWISE_XOR == op) {
			return LLVM::XOrOp::create(b, l, left, right);
		}
		if (TokenType::OPERATOR_LEFT_SHIFT == op) {
			return LLVM::ShlOp::create(b, l, left, right);
		}
		if (TokenType::OPERATOR_RIGHT_SHIFT_ARITHMETIC == op && signed_) {
			return LLVM::AShrOp::create(b, l, left, right);
		}
		if (TokenType::OPERATOR_RIGHT_SHIFT_ARITHMETIC == op || TokenType::OPERATOR_RIGHT_SHIFT_LOGICAL == op) {
			return LLVM::LShrOp::create(b, l, left, right);
		}
		unsupported(generator, where, "this operator can't be generated yet");
		return left;
	}

	// A shift's amount, as wide as what's shifted.
	static mlir::Value shift_amount(Generator& generator, mlir::Value amount, mlir::Type target) {
		const unsigned from = amount.getType().getIntOrFloatBitWidth();
		const unsigned to = target.getIntOrFloatBitWidth();
		if (from < to) {
			return LLVM::ZExtOp::create(generator.builder, generator.loc, target, amount);
		}
		if (from > to) {
			return LLVM::TruncOp::create(generator.builder, generator.loc, target, amount);
		}
		return amount;
	}

	static mlir::Value tag_is(Generator& generator, mlir::Value address, TypeInfo const* type, size_t variant, bool equal) {
		mlir::Value tag = union_tag(generator, address, type);
		return LLVM::ICmpOp::create(generator.builder, generator.loc, equal ? LLVM::ICmpPredicate::eq : LLVM::ICmpPredicate::ne,
			tag, constant_int(generator, tag.getType(), static_cast<int64_t>(variant)));
	}

	// What a function returns instead, for x? and or_return: an optional's None, or a result's error.
	static void return_missing(Generator& generator, mlir::Value address, TypeInfo const* type, const ast::Node* where) {
		TypeInfoFunction const* function = generator.state->type;
		if (function == nullptr || function->output.size() != 1) {
			unsupported(generator, where, "? here can't be generated yet");
			::hmir::HemeraReturnOp::create(generator.builder, generator.loc, mlir::ValueRange{});
			return;
		}
		TypeInfo* returned = function->output[0].type;
		const size_t none = variant_named(returned, "None");
		if (none < static_cast<TypeInfoUnion const*>(base(returned))->variants.size()) {
			emit_return(generator, { make_variant(generator, returned, none, {}, {}) });
			return;
		}
		// The error, as the function's result's error
		const UnionVariant& error = static_cast<TypeInfoUnion const*>(base(type))->variants[1];
		mlir::Value missing = load(generator, error.types[0], offset_address(generator, address, error.offsets[0]));
		emit_return(generator, { make_variant(generator, returned, 1, { missing }, { error.types[0] }) });
	}

	// What an optional or result holds, where it is.
	static Emitted held_value(Generator& generator, mlir::Value address, TypeInfo const* type) {
		const UnionVariant& some = static_cast<TypeInfoUnion const*>(base(type))->variants[0];
		// Result[void, E]'s Ok holds nothing
		if (some.types.empty()) {
			return Emitted{};
		}
		return location(offset_address(generator, address, some.offsets.empty() ? 0 : some.offsets[0]), some.types[0]);
	}

	static Emitted emit_unary(Generator& generator, ast::Node* node, TypeInfo* expected) {
		const TokenType op = node->value.type;
		ast::Node* operand_node = node->children[0];
		const CheckedNode* found = checked(generator, node);
		TypeInfo* result_type = type_at(generator, node, expected);
		if (found != nullptr && ValueKind::TYPE == found->kind) {
			Emitted type;
			type.kind = ValueKind::TYPE;
			type.type = found->type;
			return type;
		}
		if (TokenType::SYM_QUESTION == op || TokenType::KEYWORD_IS_SOME == op || TokenType::KEYWORD_IS_NONE == op
			|| TokenType::KEYWORD_OR_BREAK == op || TokenType::KEYWORD_OR_CONTINUE == op) {
			Emitted operand = emit_expression(generator, operand_node, nullptr);
			mlir::Value address = address_of(generator, operand);
			if (TokenType::KEYWORD_IS_SOME == op || TokenType::KEYWORD_IS_NONE == op) {
				return value(tag_is(generator, address, operand.type, 0, TokenType::KEYWORD_IS_SOME == op), BUILTIN_bool);
			}
			emit_if(generator, tag_is(generator, address, operand.type, 0, false), [&]() {
				if (TokenType::KEYWORD_OR_BREAK == op) {
					emit_break(generator, 1);
				}
				else if (TokenType::KEYWORD_OR_CONTINUE == op) {
					emit_continue(generator);
				}
				else {
					return_missing(generator, address, operand.type, node);
				}
				return true;
			}, nullptr);
			return held_value(generator, address, operand.type);
		}
		if (TokenType::SYM_AMPERSAND == op) {
			Emitted operand = emit_expression(generator, operand_node, nullptr);
			// A relative pointer's place: a pointer to the relative pointer
			return value(operand.relative != nullptr ? operand.address : address_of(generator, operand), result_type);
		}
		if (TokenType::OPERATOR_DEREFERENCE == op) {
			Emitted operand = emit_expression(generator, operand_node, nullptr);
			return location(value_of(generator, operand), result_type);
		}
		mlir::Value operand = emit_as(generator, operand_node, result_type);
		mlir::Type type = operand.getType();
		if (TokenType::OPERATOR_NOT == op) {
			if (type.getIntOrFloatBitWidth() == 1) {
				return value(LLVM::XOrOp::create(generator.builder, generator.loc, operand, constant_int(generator, type, 1)), result_type);
			}
			// A b16, b32 or b64 is 0 or 1 in a wider integer: true when it's 0
			mlir::Value zero = LLVM::ICmpOp::create(generator.builder, generator.loc, LLVM::ICmpPredicate::eq, operand,
				constant_int(generator, type, 0));
			return value(LLVM::ZExtOp::create(generator.builder, generator.loc, type, zero), result_type);
		}
		if (TokenType::OPERATOR_MINUS == op) {
			// A vector's lanes decide, like -v on floats
			TypeInfo const* scalar = is_variant(result_type, TypeInfoVariant::VECTOR)
				? static_cast<TypeInfoVector const*>(base(result_type))->element_type : result_type;
			if (is_float(scalar)) {
				return value(LLVM::FNegOp::create(generator.builder, generator.loc, operand), result_type);
			}
			return value(LLVM::SubOp::create(generator.builder, generator.loc, constant_int(generator, type, 0), operand), result_type);
		}
		if (TokenType::OPERATOR_BITWISE_XOR == op) {
			// A vector of bools' lanes are 0 or 1
			const bool bool_lanes = is_variant(result_type, TypeInfoVariant::VECTOR)
				&& is_variant(static_cast<TypeInfoVector const*>(base(result_type))->element_type, TypeInfoVariant::BOOLEAN);
			return value(LLVM::XOrOp::create(generator.builder, generator.loc, operand, constant_int(generator, type, bool_lanes ? 1 : -1)),
				result_type);
		}
		return value(operand, result_type);
	}

	// An operand of an operator on vectors: the vector, or an untyped literal in every lane.
	static mlir::Value vector_operand(Generator& generator, ast::Node* node, TypeInfo* type) {
		const CheckedNode* found = checked(generator, node);
		if (found != nullptr && is_untyped(found->kind)) {
			auto vector = static_cast<TypeInfoVector const*>(base(type));
			return splat(generator, emit_as(generator, node, vector->element_type), llvm_type(generator, type));
		}
		return emit_as(generator, node, type);
	}

	// The vector type of an operator's operands, or null when neither is a vector.
	static TypeInfo* vector_operands(Generator& generator, ast::Node* left, ast::Node* right) {
		for (ast::Node* operand : { left, right }) {
			const CheckedNode* found = operand != nullptr ? checked(generator, operand) : nullptr;
			if (found != nullptr && ValueKind::VALUE == found->kind && is_variant(found->type, TypeInfoVariant::VECTOR)) {
				return found->type;
			}
		}
		return nullptr;
	}

	/*
	 * An operator on vectors, lane by lane: LLVM's operators take vectors as they are, so the scalar
	 * ones do, told the lanes' type. A comparison's lanes become bytes, a vector of bools.
	 */
	static Emitted emit_vector_binary(Generator& generator, ast::Node* node, TokenType op, TypeInfo* type, TypeInfo* result_type) {
		auto vector = static_cast<TypeInfoVector const*>(base(type));
		TypeInfo* lane = vector->element_type;
		mlir::Value left = vector_operand(generator, node->children[0], type);
		ast::Node* right_node = node->children[1];
		if (is_shift(op)) {
			TypeInfo* amount_type = type_at(generator, right_node, BUILTIN_usize);
			mlir::Value amount;
			if (is_variant(amount_type, TypeInfoVariant::VECTOR)) {
				amount = emit_as(generator, right_node, amount_type);
			}
			else {
				mlir::Type lane_type = llvm::cast<mlir::VectorType>(left.getType()).getElementType();
				amount = splat(generator, shift_amount(generator, emit_as(generator, right_node, amount_type), lane_type), left.getType());
			}
			return value(arithmetic(generator, op, left, amount, lane, node), type);
		}
		mlir::Value right = vector_operand(generator, right_node, type);
		if (is_comparison(op)) {
			mlir::Value lanes = compare(generator, op, left, right, lane);
			return value(LLVM::ZExtOp::create(generator.builder, generator.loc, llvm_type(generator, result_type), lanes), result_type);
		}
		return value(arithmetic(generator, op, left, right, lane, node), type);
	}

	static Emitted emit_binary(Generator& generator, ast::Node* node, TypeInfo* expected) {
		const TokenType op = node->value.type;
		ast::Node* left_node = node->children[0];
		ast::Node* right_node = node->children.size() > 1 ? node->children[1] : nullptr;
		TypeInfo* result_type = type_at(generator, node, expected);
		if (TokenType::OPERATOR_PIPE == op) {
			// a |> f(b): f(a, b), with each of a's results
			Emitted left = emit_expression(generator, left_node, nullptr);
			std::vector<Emitted> piped;
			if (ValueKind::RESULTS == left.kind) {
				for (size_t i = 0; i < left.results.size(); ++i) {
					piped.push_back(value(extract(generator, left.value, static_cast<int64_t>(i)), left.results[i]));
				}
			}
			else if (ValueKind::NOTHING != left.kind) {
				piped.push_back(left);
			}
			generator.piped = std::move(piped);
			Emitted right = emit_postfix(generator, right_node, nullptr);
			Emitted result = emit_steps(generator, node, 2, right);
			generator.piped.clear();
			return result;
		}
		if (TokenType::KEYWORD_OR_ELSE == op || TokenType::KEYWORD_OR_RETURN == op) {
			Emitted left = emit_expression(generator, left_node, nullptr);
			mlir::Value address = address_of(generator, left);
			Emitted held = held_value(generator, address, left.type);
			if (TokenType::KEYWORD_OR_RETURN == op) {
				emit_if(generator, tag_is(generator, address, left.type, 0, false), [&]() {
					TypeInfoFunction const* function = generator.state->type;
					if (function->output.empty()) {
						emit_return(generator, {});
					}
					else {
						emit_return(generator, { emit_as(generator, right_node, function->output[0].type) });
					}
					return true;
				}, nullptr);
				return held;
			}
			// Result[void, E]: on an error, the default runs, for what it does
			if (held.type == nullptr) {
				emit_if(generator, tag_is(generator, address, left.type, 0, false), [&]() {
					if (emit_expression(generator, right_node, nullptr).never_returns) {
						LLVM::UnreachableOp::create(generator.builder, generator.loc);
						return true;
					}
					return false;
				}, nullptr);
				return Emitted{};
			}
			mlir::Value slot = make_slot(generator, held.type);
			emit_if(generator, tag_is(generator, address, left.type, 0, true), [&]() {
				store(generator, value_of(generator, held), slot);
				return false;
			}, [&]() {
				// A default that never returns, like a call that stops the program, ends here
				Emitted otherwise = emit_expression(generator, right_node, held.type);
				if (otherwise.never_returns) {
					LLVM::UnreachableOp::create(generator.builder, generator.loc);
					return true;
				}
				if (ValueKind::VARIANT == otherwise.kind) {
					store(generator, convert(generator, make_variant(generator, otherwise.type, otherwise.variant, {}, {}), otherwise.type, held.type), slot);
					return false;
				}
				store(generator, convert_emitted(generator, otherwise, held.type), slot);
				return false;
			});
			return location(slot, held.type);
		}
		if (TokenType::OPERATOR_AND == op || TokenType::OPERATOR_OR == op) {
			// The right only if it's needed
			mlir::Value slot = make_slot(generator, BUILTIN_bool);
			mlir::Value left = emit_condition(generator, left_node);
			store(generator, left, slot);
			emit_if(generator, TokenType::OPERATOR_AND == op ? left : negate(generator, left), [&]() {
				store(generator, emit_condition(generator, right_node), slot);
				return false;
			}, nullptr);
			return location(slot, BUILTIN_bool);
		}
		if (TypeInfo* vector = vector_operands(generator, left_node, right_node); vector != nullptr && right_node != nullptr) {
			return emit_vector_binary(generator, node, op, vector, result_type);
		}
		if (is_comparison(op)) {
			TypeInfo* type = shared_type(generator, left_node, right_node, nullptr);
			if ((TokenType::OPERATOR_EQUAL == op || TokenType::OPERATOR_NOT_EQUAL == op) && is_variant(type, TypeInfoVariant::STRING)
				&& !static_cast<TypeInfoString const*>(base(type))->is_raw) {
				mlir::Value same = strings_equal(generator, emit_as(generator, left_node, type), emit_as(generator, right_node, type));
				return value(TokenType::OPERATOR_EQUAL == op ? same : negate(generator, same), BUILTIN_bool);
			}
			// An optional against null: whether it holds nothing, like is_none
			const bool left_null = TokenType::KEYWORD_NULL == left_node->value.type;
			if ((TokenType::OPERATOR_EQUAL == op || TokenType::OPERATOR_NOT_EQUAL == op) && is_variant(type, TypeInfoVariant::UNION)
				&& right_node != nullptr && (left_null || TokenType::KEYWORD_NULL == right_node->value.type)) {
				Emitted operand = emit_expression(generator, left_null ? right_node : left_node, type);
				mlir::Value address = address_of(generator, operand);
				return value(tag_is(generator, address, operand.type, 0, TokenType::OPERATOR_NOT_EQUAL == op), BUILTIN_bool);
			}
			/*
			 * An optional against a value of what it holds, like error != OsError.NotFound: equal when it
			 * holds a value, and that value is equal
			 */
			if (TokenType::OPERATOR_EQUAL == op || TokenType::OPERATOR_NOT_EQUAL == op) {
				TypeInfo* left_type = type_at(generator, left_node, nullptr);
				TypeInfo* right_type = right_node != nullptr ? type_at(generator, right_node, nullptr) : nullptr;
				const auto optional = [](TypeInfo const* t) {
					if (!is_variant(t, TypeInfoVariant::UNION)) {
						return false;
					}
					auto union_type = static_cast<TypeInfoUnion const*>(base(t));
					return union_type->variants.size() == 2 && variant_named(t, "None") == 1 && union_type->variants[0].types.size() == 1;
				};
				const bool left_optional = optional(left_type);
				const bool right_optional = optional(right_type);
				if (left_optional != right_optional) {
					ast::Node* optional_node = left_optional ? left_node : right_node;
					ast::Node* other_node = left_optional ? right_node : left_node;
					TypeInfo* optional_type = left_optional ? left_type : right_type;
					TypeInfo* held_type = static_cast<TypeInfoUnion const*>(base(optional_type))->variants[0].types[0];
					Emitted operand = emit_expression(generator, optional_node, optional_type);
					mlir::Value address = address_of(generator, operand);
					mlir::Value other = emit_as(generator, other_node, held_type);
					mlir::Value slot = make_slot(generator, BUILTIN_bool);
					store(generator, boolean(generator, false), slot);
					emit_if(generator, tag_is(generator, address, optional_type, 0, true), [&]() {
						mlir::Value held = value_of(generator, held_value(generator, address, optional_type));
						mlir::Value same;
						if (is_variant(held_type, TypeInfoVariant::STRING) && !static_cast<TypeInfoString const*>(base(held_type))->is_raw) {
							same = strings_equal(generator, held, other);
						}
						else if (is_variant(held_type, TypeInfoVariant::STRUCT) || is_variant(held_type, TypeInfoVariant::UNION)) {
							unsupported(generator, node, std::format("comparing {} values can't be generated yet", to_string(held_type)));
							same = boolean(generator, false);
						}
						else {
							same = compare(generator, TokenType::OPERATOR_EQUAL, held, other, held_type);
						}
						store(generator, same, slot);
						return false;
					}, nullptr);
					mlir::Value equal = load(generator, BUILTIN_bool, slot);
					return value(TokenType::OPERATOR_EQUAL == op ? equal : negate(generator, equal), BUILTIN_bool);
				}
			}
			if (is_variant(type, TypeInfoVariant::STRING) || is_variant(type, TypeInfoVariant::STRUCT) || is_variant(type, TypeInfoVariant::UNION)
				|| is_variant(type, TypeInfoVariant::ARRAY)) {
				unsupported(generator, node, std::format("comparing {} values can't be generated yet", to_string(type)));
				return value(boolean(generator, false), BUILTIN_bool);
			}
			mlir::Value left = emit_as(generator, left_node, type);
			mlir::Value right = emit_as(generator, right_node, type);
			return value(compare(generator, op, left, right, type), BUILTIN_bool);
		}
		if (is_shift(op)) {
			mlir::Value left = emit_as(generator, left_node, result_type);
			mlir::Value amount = emit_as(generator, right_node, type_at(generator, right_node, BUILTIN_usize));
			return value(arithmetic(generator, op, left, shift_amount(generator, amount, left.getType()), result_type, node),
				result_type);
		}
		// Pointer arithmetic: a raw pointer and a count of bytes
		if (is_variant(result_type, TypeInfoVariant::POINTER) && !static_cast<TypeInfoPointer const*>(base(result_type))->is_relative) {
			mlir::Value pointer = emit_as(generator, left_node, result_type);
			mlir::Value amount = emit_as(generator, right_node, BUILTIN_int);
			if (TokenType::OPERATOR_MINUS == op) {
				amount = LLVM::SubOp::create(generator.builder, generator.loc, constant_int(generator, amount.getType(), 0), amount);
			}
			llvm::SmallVector<LLVM::GEPArg> indices{ amount };
			return value(LLVM::GEPOp::create(generator.builder, generator.loc, pointer_type(generator), integer_type(generator, 1),
				pointer, indices), result_type);
		}
		if (is_variant(result_type, TypeInfoVariant::STRING)) {
			unsupported(generator, node, "joining strings can't be generated yet");
			return value(zero_of(generator, llvm_type(generator, result_type)), result_type);
		}
		mlir::Value left = emit_as(generator, left_node, result_type);
		mlir::Value right = emit_as(generator, right_node, result_type);
		return value(arithmetic(generator, op, left, right, result_type, node), result_type);
	}

	// cast[T](x), bit_cast[T](x), auto_cast(x), then anything after it.
	static Emitted emit_cast(Generator& generator, ast::Node* node) {
		// (x).member and the like: x as it is, then the chain
		if (TokenType::SYM_LPAREN == node->value.type) {
			return emit_steps(generator, node, 1, emit_expression(generator, node->children[0], nullptr));
		}
		const bool automatic = TokenType::KEYWORD_AUTO_CAST == node->value.type;
		ast::Node* value_node = node->children[automatic ? 0 : 1];
		const size_t rest = automatic ? 1 : 2;
		const CheckedNode* head = head_of(generator, node);
		TypeInfo* target = head != nullptr ? head->type : nullptr;
		if (target == nullptr) {
			unsupported(generator, node, "this cast wasn't checked");
			return Emitted{};
		}
		const CheckedNode* found = checked(generator, value_node);
		mlir::Value result;
		if (found != nullptr && is_untyped(found->kind) && takes_untyped(found->kind, target)) {
			result = emit_as(generator, value_node, target);
		}
		else {
			Emitted source = emit_expression(generator, value_node, nullptr);
			mlir::Value v = value_of(generator, source);
			if (TokenType::KEYWORD_BIT_CAST == node->value.type) {
				mlir::Value slot = make_slot(generator, source.type->size >= target->size ? source.type : target);
				store(generator, v, slot);
				result = load(generator, target, slot);
			}
			else {
				result = convert(generator, v, source.type, target);
			}
		}
		return emit_steps(generator, node, rest, value(result, target));
	}

	// A struct member's default value (StructMember::has_value), a constant.
	static mlir::Value default_of(Generator& generator, const StructMember& member) {
		mlir::Type type = llvm_type(generator, member.member_type);
		if (!member.default_member.empty() && is_variant(member.member_type, TypeInfoVariant::ENUM)) {
			return constant_int(generator, type, enum_value(member.member_type, intern(member.default_member)));
		}
		if (is_float(member.member_type)) {
			return LLVM::ConstantOp::create(generator.builder, generator.loc, type,
				generator.builder.getFloatAttr(type, static_cast<double>(member.default_integer)));
		}
		if (!type.isIntOrIndex()) {
			unsupported(generator, nullptr, std::format("{}'s default value can't be generated yet", text_of(member.name)));
			return zero_of(generator, type);
		}
		return constant_int(generator, type, member.default_integer);
	}

	/*
	 * A struct's starting value where it isn't given one: zero, but for its members' defaults, and
	 * theirs in turn, in a struct a member holds (docs/types.md, Structs).
	 */
	static void store_defaults(Generator& generator, TypeInfo* type, mlir::Value address) {
		store_zero(generator, type, address);
		if (!is_variant(type, TypeInfoVariant::STRUCT)) {
			return;
		}
		auto structure = static_cast<TypeInfoStruct const*>(base(type));
		for (const StructMember& member : structure->members) {
			if (member.name == nullptr) {
				continue;
			}
			size_t offset = 0;
			TypeInfo* member_type = nullptr;
			std::vector<int64_t> path;
			if (!find_member(generator, structure, member.name, offset, member_type, path)) {
				continue;
			}
			if (member.has_value) {
				store(generator, default_of(generator, member), offset_address(generator, address, offset));
			}
			else if (is_variant(member.member_type, TypeInfoVariant::STRUCT) && !member.is_using) {
				store_defaults(generator, member.member_type, offset_address(generator, address, offset));
			}
		}
	}

	// Type.{values} or Type.{name = value}: built as a value, part by part.
	static Emitted emit_struct_literal(Generator& generator, ast::Node* node, TypeInfo* type) {
		// A vector's lanes, in order
		if (is_variant(type, TypeInfoVariant::VECTOR)) {
			auto vector = static_cast<TypeInfoVector const*>(base(type));
			mlir::Type vector_type = llvm_type(generator, type);
			mlir::Value lanes = zero_of(generator, vector_type);
			for (ast::Node* child : node->children) {
				if (ast::NodeType::LIST != child->node_type) {
					continue;
				}
				for (size_t i = 0; i < child->children.size(); ++i) {
					mlir::Value lane = as_lane(generator, emit_as(generator, child->children[i], vector->element_type), vector_type);
					lanes = LLVM::InsertElementOp::create(generator.builder, generator.loc, lanes, lane,
						LLVM::ConstantOp::create(generator.builder, generator.loc, generator.builder.getI32Type(), static_cast<int64_t>(i)));
				}
			}
			return value(lanes, type);
		}
		auto structure = static_cast<TypeInfoStruct const*>(base(type));
		mlir::Value result = zero_of(generator, llvm_type(generator, type));
		std::vector<ast::Node*> elements;
		for (ast::Node* child : node->children) {
			if (ast::NodeType::LIST == child->node_type) {
				elements.assign(child->children.begin(), child->children.end());
			}
		}
		std::set<std::string> given;
		size_t position = 0;
		for (ast::Node* element : elements) {
			const bool named = ast::NodeType::BINARY_OPERATOR == element->node_type && is_assign(element)
				&& element->children.size() == 2;
			size_t offset = 0;
			TypeInfo* member_type = nullptr;
			std::vector<int64_t> path;
			if (named) {
				find_member(generator, structure, element->children[0]->value.value, offset, member_type, path);
				given.insert(text_of(element->children[0]->value.value));
			}
			else {
				// In order: the member at this position, which may have no name
				llvm_type(generator, structure);
				path.push_back(generator.member_elements[structure][position]);
				member_type = structure->members[position].member_type;
				given.insert(text_of(structure->members[position].name));
				++position;
			}
			if (std::find(path.begin(), path.end(), -1) != path.end()) {
				unsupported(generator, element, "a #union struct's literal can't be generated yet");
				continue;
			}
			result = LLVM::InsertValueOp::create(generator.builder, generator.loc, result,
				emit_as(generator, named ? element->children[1] : element, member_type), path);
		}
		// The others have their defaults, or zero
		for (const StructMember& member : structure->members) {
			if (member.has_value && !given.contains(text_of(member.name))) {
				size_t offset = 0;
				TypeInfo* member_type = nullptr;
				std::vector<int64_t> path;
				find_member(generator, structure, member.name, offset, member_type, path);
				if (std::find(path.begin(), path.end(), -1) != path.end()) {
					unsupported(generator, node, "a #union struct's defaults can't be generated yet");
					continue;
				}
				result = LLVM::InsertValueOp::create(generator.builder, generator.loc, result, default_of(generator, member), path);
			}
		}
		return value(result, type);
	}

	// Type.[values]: a static array of them.
	// memcmp, which lower_to_llvm defines (define_memory_functions), declared for a call.
	static LLVM::LLVMFuncOp memcmp_function(Generator& generator) {
		LLVM::LLVMFuncOp function = generator.module.lookupSymbol<LLVM::LLVMFuncOp>("memcmp");
		if (!function) {
			mlir::OpBuilder::InsertionGuard guard(generator.builder);
			generator.builder.setInsertionPointToEnd(generator.module.getBody());
			function = LLVM::LLVMFuncOp::create(generator.builder, generator.loc, "memcmp",
				LLVM::LLVMFunctionType::get(integer_type(generator, 4),
					{ pointer_type(generator), pointer_type(generator), usize_type(generator) }));
		}
		return function;
	}

	/*
	 * Whether two strings have the same bytes, as an i1: the same count, and memcmp over it. When
	 * the counts differ, memcmp compares no bytes, so it never reads past the shorter one.
	 */
	static mlir::Value strings_equal(Generator& generator, mlir::Value left, mlir::Value right) {
		mlir::OpBuilder& b = generator.builder;
		const mlir::Location l = generator.loc;
		mlir::Value left_count = extract(generator, left, 0);
		mlir::Value same_count = LLVM::ICmpOp::create(b, l, LLVM::ICmpPredicate::eq, left_count, extract(generator, right, 0));
		mlir::Value count = LLVM::SelectOp::create(b, l, same_count, left_count, constant_int(generator, usize_type(generator), 0));
		auto difference = LLVM::CallOp::create(b, l, memcmp_function(generator),
			mlir::ValueRange{ extract(generator, left, 1), extract(generator, right, 1), count });
		mlir::Value same_bytes = LLVM::ICmpOp::create(b, l, LLVM::ICmpPredicate::eq, difference.getResult(),
			constant_int(generator, integer_type(generator, 4), 0));
		return LLVM::AndOp::create(b, l, same_count, same_bytes);
	}

	/*
	 * Integer elements that are all constants as one dense constant, or null if they aren't. The
	 * elements' own constants are erased either way, since nothing uses them: a long table, like a
	 * font, would otherwise be one insertvalue per element for LLVM to fold.
	 */
	static mlir::Value dense_integer_array(Generator& generator, mlir::Type array_type, mlir::Type element_type,
		const std::vector<mlir::Value>& elements) {

		auto integer = mlir::dyn_cast<mlir::IntegerType>(element_type);
		std::vector<llvm::APInt> numbers;
		bool dense = integer != nullptr;
		for (const mlir::Value& element : elements) {
			auto constant = dense ? element.getDefiningOp<LLVM::ConstantOp>() : LLVM::ConstantOp();
			auto attribute = constant ? mlir::dyn_cast<mlir::IntegerAttr>(constant.getValue()) : mlir::IntegerAttr();
			if (!attribute || attribute.getType() != element_type) {
				dense = false;
				break;
			}
			numbers.push_back(attribute.getValue());
		}
		if (!dense) {
			return mlir::Value();
		}
		auto tensor = mlir::RankedTensorType::get({ static_cast<int64_t>(numbers.size()) }, integer);
		mlir::Value result = LLVM::ConstantOp::create(generator.builder, generator.loc, array_type,
			mlir::DenseElementsAttr::get(tensor, numbers));
		for (const mlir::Value& element : elements) {
			if (element.use_empty()) {
				element.getDefiningOp()->erase();
			}
		}
		return result;
	}

	static Emitted emit_array_literal(Generator& generator, ast::Node* node, TypeInfo* type) {
		auto array = static_cast<TypeInfoArray const*>(base(type));
		std::vector<mlir::Value> elements;
		for (ast::Node* child : node->children) {
			if (ast::NodeType::LIST != child->node_type) {
				continue;
			}
			for (ast::Node* element : child->children) {
				elements.push_back(emit_as(generator, element, array->element_type));
			}
		}
		mlir::Type array_type = llvm_type(generator, type);
		if (!elements.empty() && ArrayType::STATIC == array->array_type
			&& static_cast<size_t>(array->count) == elements.size()) {
			mlir::Value dense = dense_integer_array(generator, array_type, llvm_type(generator, array->element_type), elements);
			if (dense) {
				return value(dense, type);
			}
		}
		mlir::Value result = zero_of(generator, array_type);
		for (size_t i = 0; i < elements.size(); ++i) {
			result = insert(generator, result, elements[i], { static_cast<int64_t>(i) });
		}
		return value(result, type);
	}

	/*
	 * #file_data(path): the file's bytes, as one dense constant. The checker made its type from the
	 * file's size; if the file changed size since, it's reported rather than cut short or padded.
	 */
	static mlir::Value emit_file_data(Generator& generator, ast::Node* node, TypeInfo* type) {
		const std::filesystem::path path = file_data_path(current_file(generator), node);
		std::ifstream file(path, std::ios::binary);
		std::vector<char> bytes((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
		auto array = static_cast<TypeInfoArray const*>(base(type));
		if (!file || bytes.size() != array->count) {
			unsupported(generator, node, std::format("{} changed while it was compiled", path.string()));
			return zero_of(generator, llvm_type(generator, type));
		}
		auto tensor = mlir::RankedTensorType::get({ static_cast<int64_t>(bytes.size()) }, generator.builder.getI8Type());
		auto data = mlir::DenseElementsAttr::getFromRawBuffer(tensor, llvm::ArrayRef<char>(bytes.data(), bytes.size()));
		return LLVM::ConstantOp::create(generator.builder, generator.loc, llvm_type(generator, type), data);
	}

	// .Name or .Name(values): an enum's member, or a union's variant.
	static Emitted emit_enum_shorthand(Generator& generator, ast::Node* node, const CheckedNode* found, TypeInfo* type) {
		if (found == nullptr || type == nullptr) {
			unsupported(generator, node, "this wasn't checked");
			return Emitted{};
		}
		if (is_variant(type, TypeInfoVariant::ENUM)) {
			return value(constant_int(generator, llvm_type(generator, type), enum_value(type, node->value.value)), type);
		}
		const UnionVariant& variant = static_cast<TypeInfoUnion const*>(base(type))->variants[found->variant];
		std::vector<mlir::Value> values;
		bool called = false;
		for (ast::Node* child : node->children) {
			if (ast::NodeType::PAREN_GROUP == child->node_type) {
				called = true;
			}
			else if (called && values.size() < variant.types.size()) {
				values.push_back(emit_as(generator, child, variant.types[values.size()]));
			}
		}
		return value(make_variant(generator, type, found->variant, values, variant.types), type);
	}

	// An if's else: its block, or the if after it.
	static ast::Node* else_of(ast::Node* if_node) {
		ast::Node* otherwise = if_node->children.size() > 2 ? if_node->children[2] : nullptr;
		if (otherwise != nullptr && ast::NodeType::ELSE == otherwise->node_type && !otherwise->children.empty()) {
			otherwise = otherwise->children[0];
		}
		return otherwise;
	}

	// if as a value: each branch's block ends with its value.
	static void emit_if_value(Generator& generator, ast::Node* node, mlir::Value slot, TypeInfo* type) {
		ast::Node* otherwise = else_of(node);
		emit_if(generator, emit_condition(generator, node->children[0]), [&]() {
			return emit_block(generator, node->children[1], slot, type);
		}, otherwise == nullptr ? std::function<bool()>() : [&]() {
			if (ast::NodeType::IF == otherwise->node_type) {
				emit_if_value(generator, otherwise, slot, type);
				return false;
			}
			return emit_block(generator, otherwise, slot, type);
		});
	}

	static Emitted emit_match(Generator& generator, ast::Node* node, TypeInfo* type, bool as_value);

	static Emitted emit_expression(Generator& generator, ast::Node* node, TypeInfo* expected) {
		const CheckedNode* found = checked(generator, node);
		const ast::NodeType type = node->node_type;
		TypeInfo* result_type = type_at(generator, node, expected);
		// A number as an endian-specific type: made as its native type, then put in its byte order
		if (TypeInfo* native = native_of(result_type); native != result_type
			&& (ast::NodeType::LITERAL == type || (found != nullptr && found->integer_known))) {
			mlir::Value made = ast::NodeType::LITERAL == type ? emit_literal(generator, node, native) : known_integer(generator, *found, native);
			return value(convert(generator, made, native, result_type), result_type);
		}
		if (ast::NodeType::LITERAL == type) {
			return value(emit_literal(generator, node, result_type), result_type);
		}
		// A known integer, like 512 / 4 or a constant's, as one constant, not worked out in a type too small for its parts
		if (found != nullptr && found->integer_known && (is_variant(result_type, TypeInfoVariant::INTEGER) || is_float(result_type))) {
			return value(known_integer(generator, *found, result_type), result_type);
		}
		if (ast::NodeType::IDENTIFIER == type) {
			return emit_postfix(generator, node, expected);
		}
		if (ast::NodeType::PAREN_GROUP == type && node->children.size() == 1) {
			return emit_expression(generator, node->children[0], expected);
		}
		if (ast::NodeType::TYPE == type || ast::NodeType::FUNCTION == type) {
			Emitted result;
			result.kind = ValueKind::TYPE;
			result.type = found != nullptr ? found->type : nullptr;
			return result;
		}
		if (ast::NodeType::UNARY_OPERATOR == type) {
			return emit_unary(generator, node, expected);
		}
		if (ast::NodeType::BINARY_OPERATOR == type) {
			return emit_binary(generator, node, expected);
		}
		if (ast::NodeType::CAST == type) {
			return emit_cast(generator, node);
		}
		if (ast::NodeType::STRUCT_LITERAL == type) {
			return emit_struct_literal(generator, node, result_type);
		}
		if (ast::NodeType::ARRAY_LITERAL == type) {
			return emit_array_literal(generator, node, result_type);
		}
		if (ast::NodeType::ENUM_SHORTHAND == type) {
			return emit_enum_shorthand(generator, node, found, result_type);
		}
		if (ast::NodeType::IF == type) {
			mlir::Value slot = make_slot(generator, result_type);
			emit_if_value(generator, node, slot, result_type);
			return location(slot, result_type);
		}
		if (ast::NodeType::MATCH == type) {
			return emit_match(generator, node, result_type, true);
		}
		if (ast::NodeType::VOID == type) {
			return Emitted{};
		}
		if (ast::NodeType::DIRECTIVE == type && is_text(node->value.value, "#caller_location")) {
			return value(caller_location(generator, result_type, node), result_type);
		}
		if (ast::NodeType::DIRECTIVE == type && is_text(node->value.value, "#file_data")) {
			return value(emit_file_data(generator, node, result_type), result_type);
		}
		if (ast::NodeType::DIRECTIVE == type && is_text(node->value.value, "#is_compile_time")) {
			return value(boolean(generator, generator.compile_time), BUILTIN_bool);
		}
		if (ast::NodeType::DIRECTIVE == type && is_text(node->value.value, "#code")) {
			return emit_quote(generator, node);
		}
		// #run in an expression: a constant, run once
		if (ast::NodeType::DIRECTIVE == type && is_text(node->value.value, "#run") && !node->children.empty() && result_type != nullptr) {
			auto iter = generator.compile_time_values.find(node);
			if (iter == generator.compile_time_values.end()) {
				if (std::optional<CompileTimeValue> checked = already_run(generator, node)) {
					iter = generator.compile_time_values.emplace(node, std::move(*checked)).first;
				}
			}
			if (iter == generator.compile_time_values.end()) {
				CompileTimeValue ran;
				if (!run_at_compile_time(generator, node->children[0], result_type, generator.state->checked,
					generator.state->declaration, ran)) {
					return value(zero_of(generator, llvm_type(generator, result_type)), result_type);
				}
				iter = generator.compile_time_values.emplace(node, std::move(ran)).first;
			}
			return value(constant_from(generator, result_type, iter->second, 0), result_type);
		}
		unsupported(generator, node, std::format("{} can't be generated yet", ast::name_of(type)));
		TypeInfo* placeholder = result_type != nullptr ? result_type : BUILTIN_int;
		return value(zero_of(generator, llvm_type(generator, placeholder)), placeholder);
	}

	// ---------------------------------------------------------------------------------------------
	// match and switch

	static bool is_wildcard(const ast::Node* node) {
		return ast::NodeType::UNDERSCORE == node->node_type;
	}

	// Whether the subject matches one case's value; a variant's values become its locals.
	static mlir::Value case_matches(Generator& generator, ast::Node* pattern, const Emitted& subject, mlir::Value address) {
		if (is_wildcard(pattern)) {
			return boolean(generator, true);
		}
		TypeInfo const* type = base(subject.type);
		const TokenType op = pattern->value.type;
		if (ast::NodeType::BINARY_OPERATOR == pattern->node_type
			&& (TokenType::OPERATOR_RANGE_EXCLUSIVE == op || TokenType::OPERATOR_RANGE_INCLUSIVE == op)) {
			mlir::Value v = load(generator, subject.type, address);
			mlir::Value low = emit_as(generator, pattern->children[0], subject.type);
			mlir::Value high = emit_as(generator, pattern->children[1], subject.type);
			mlir::Value above = compare(generator, TokenType::OPERATOR_GREATER_THAN_OR_EQUAL, v, low, type);
			mlir::Value below = compare(generator, TokenType::OPERATOR_RANGE_INCLUSIVE == op
				? TokenType::OPERATOR_LESS_THAN_OR_EQUAL : TokenType::SYM_LT, v, high, type);
			return LLVM::AndOp::create(generator.builder, generator.loc, above, below);
		}
		if (TypeInfoVariant::UNION == type->variant
			&& (ast::NodeType::IDENTIFIER == pattern->node_type || ast::NodeType::ENUM_SHORTHAND == pattern->node_type)) {
			const size_t index = variant_named(type, std::string_view(*pattern->value.value));
			const UnionVariant& variant = static_cast<TypeInfoUnion const*>(type)->variants[index];
			for (ast::Node* child : pattern->children) {
				if (ast::NodeType::PAREN_GROUP != child->node_type) {
					continue;
				}
				/*
				 * Its values, named: copied out of the subject now, so they keep the values they
				 * matched with when the arm changes what the subject is in, like here.parking = null
				 */
				mlir::Value matches = tag_is(generator, address, type, index, true);
				for (size_t i = 0; i < child->children.size() && i < variant.types.size(); ++i) {
					ast::Node* part = child->children[i];
					if (is_wildcard(part)) {
						continue;
					}
					TypeInfo* held = variant.types[i];
					mlir::Value held_address = offset_address(generator, address, variant.offsets[i]);
					if (ast::NodeType::IDENTIFIER == part->node_type && part->children.empty()) {
						mlir::Value copy = make_slot(generator, held);
						store(generator, load(generator, held, held_address), copy);
						generator.state->slots[part] = copy;
						continue;
					}
					/*
					 * A pattern the value must match too, like .NotFound in Error(.NotFound). It's
					 * worked out whatever the tag is, so it may read what another variant left there,
					 * which only loads and compares
					 */
					mlir::Value nested = case_matches(generator, part, location(held_address, held), held_address);
					matches = LLVM::AndOp::create(generator.builder, generator.loc, matches, nested);
				}
				return matches;
			}
			return tag_is(generator, address, type, index, true);
		}
		if (TypeInfoVariant::STRING == type->variant) {
			unsupported(generator, pattern, "matching strings can't be generated yet");
			return boolean(generator, false);
		}
		mlir::Value v = load(generator, subject.type, address);
		return compare(generator, TokenType::OPERATOR_EQUAL, v, emit_as(generator, pattern, subject.type), type);
	}

	// Whether any of an arm's or case's values match.
	static mlir::Value arm_matches(Generator& generator, ast::Node* arm, const Emitted& subject, mlir::Value address) {
		mlir::Value result;
		for (size_t i = 0; i + 1 < arm->children.size(); ++i) {
			mlir::Value each = case_matches(generator, arm->children[i], subject, address);
			result = result ? static_cast<mlir::Value>(LLVM::OrOp::create(generator.builder, generator.loc, result, each)) : each;
		}
		return result ? result : boolean(generator, true);
	}

	static bool is_assignment(const ast::Node* node);

	// The entries of a match's or switch's lists: its arms or cases.
	static std::vector<ast::Node*> entries_of(ast::Node* node, bool cases) {
		std::vector<ast::Node*> result;
		for (ast::Node* list : node->children) {
			if (ast::NodeType::LIST != list->node_type) {
				continue;
			}
			for (ast::Node* entry : list->children) {
				if (!entry->children.empty() && (!cases || ast::NodeType::SWITCH_CASE == entry->node_type)) {
					result.push_back(entry);
				}
			}
		}
		return result;
	}

	// One arm of a match, and the ones after it in its else.
	static void emit_arms(Generator& generator, const std::vector<ast::Node*>& arms, size_t index, const Emitted& subject,
		mlir::Value address, mlir::Value slot, TypeInfo* type) {

		ast::Node* arm = arms[index];
		emit_if(generator, arm_matches(generator, arm, subject, address), [&]() {
			ast::Node* outcome = arm->children.back();
			const ast::NodeType outcome_type = outcome->node_type;
			if (ast::NodeType::BLOCK == outcome_type) {
				return emit_block(generator, outcome, slot, type);
			}
			if (ast::NodeType::RETURN == outcome_type || ast::NodeType::BREAK == outcome_type
				|| ast::NodeType::CONTINUE == outcome_type || is_assignment(outcome) || !slot) {
				return emit_statement(generator, outcome);
			}
			Emitted result = emit_expression(generator, outcome, type);
			if (result.never_returns) {
				LLVM::UnreachableOp::create(generator.builder, generator.loc);
				return true;
			}
			store(generator, convert_emitted(generator, result, type), slot);
			return false;
		}, index + 1 == arms.size() ? std::function<bool()>() : [&]() {
			emit_arms(generator, arms, index + 1, subject, address, slot, type);
			return false;
		});
	}

	// match (docs/control_flow.md): the first arm whose values match runs. As a value, it stores its result.
	static Emitted emit_match(Generator& generator, ast::Node* node, TypeInfo* type, bool as_value) {
		Emitted subject = emit_expression(generator, node->children[0], nullptr);
		mlir::Value address = address_of(generator, subject);
		mlir::Value slot = as_value && type != nullptr ? make_slot(generator, type) : mlir::Value();
		const std::vector<ast::Node*> arms = entries_of(node, false);
		if (!arms.empty()) {
			emit_arms(generator, arms, 0, subject, address, slot, type);
		}
		return slot ? location(slot, type) : Emitted{};
	}

	// Whether a #fall_through follows a switch's case, before the next case.
	static bool falls_through(ast::Node* node, ast::Node* entry) {
		for (ast::Node* list : node->children) {
			if (ast::NodeType::LIST != list->node_type) {
				continue;
			}
			for (size_t i = 0; i < list->children.size(); ++i) {
				if (list->children[i] == entry) {
					return i + 1 < list->children.size() && ast::NodeType::DIRECTIVE == list->children[i + 1]->node_type
						&& is_text(list->children[i + 1]->value.value, "#fall_through");
				}
			}
		}
		return false;
	}

	/*
	 * One case of a switch, and the ones after it in its else. A case before a #fall_through sets fell
	 * when it runs, and the next case is tried after it rather than in its else, running when fell is set
	 * whatever its values are.
	 */
	static void emit_cases(Generator& generator, ast::Node* node, const std::vector<ast::Node*>& cases, size_t index,
		const Emitted& subject, mlir::Value address, mlir::Value fell) {

		ast::Node* entry = cases[index];
		const bool falls = falls_through(node, entry) && index + 1 < cases.size();
		mlir::Value condition = arm_matches(generator, entry, subject, address);
		if (index > 0 && falls_through(node, cases[index - 1])) {
			condition = LLVM::OrOp::create(generator.builder, generator.loc, condition, load(generator, BUILTIN_bool, fell));
		}
		emit_if(generator, condition, [&]() {
			const bool ended = emit_block(generator, entry->children.back(), mlir::Value(), nullptr);
			if (falls && !ended) {
				store(generator, boolean(generator, true), fell);
			}
			return ended;
		}, falls || index + 1 == cases.size() ? std::function<bool()>() : [&]() {
			emit_cases(generator, node, cases, index + 1, subject, address, fell);
			return false;
		});
		if (falls) {
			emit_cases(generator, node, cases, index + 1, subject, address, fell);
		}
	}

	// switch: a loop that runs once, so break leaves it; the first case that matches runs.
	static void emit_switch(Generator& generator, ast::Node* node) {
		Emitted subject = emit_expression(generator, node->children[0], nullptr);
		mlir::Value address = address_of(generator, subject);
		const std::vector<ast::Node*> cases = entries_of(node, true);
		mlir::Value fell = make_slot(generator, BUILTIN_bool);
		store(generator, boolean(generator, false), fell);
		emit_loop(generator, false, [&]() {
			if (!cases.empty()) {
				emit_cases(generator, node, cases, 0, subject, address, fell);
			}
			emit_break(generator, 1);
			return true;
		});
	}

	// ---------------------------------------------------------------------------------------------
	// Statements

	static TokenType operator_of_assignment(TokenType op) {
		const std::pair<TokenType, TokenType> pairs[] = {
			{ TokenType::OPERATOR_ASSIGN_ADD, TokenType::OPERATOR_PLUS },
			{ TokenType::OPERATOR_ASSIGN_SUB, TokenType::OPERATOR_MINUS },
			{ TokenType::OPERATOR_ASSIGN_MUL, TokenType::OPERATOR_MULTIPLY },
			{ TokenType::OPERATOR_ASSIGN_DIV, TokenType::OPERATOR_DIVIDE },
			{ TokenType::OPERATOR_ASSIGN_MOD, TokenType::OPERATOR_MODULUS },
			{ TokenType::OPERATOR_ASSIGN_REMAINDER, TokenType::OPERATOR_REMAINDER },
			{ TokenType::OPERATOR_ASSIGN_BITWISE_AND, TokenType::SYM_AMPERSAND },
			{ TokenType::OPERATOR_ASSIGN_BITWISE_OR, TokenType::OPERATOR_BITWISE_OR },
			{ TokenType::OPERATOR_ASSIGN_BITWISE_XOR, TokenType::OPERATOR_BITWISE_XOR },
			{ TokenType::OPERATOR_ASSIGN_LEFT_SHIFT, TokenType::OPERATOR_LEFT_SHIFT },
			{ TokenType::OPERATOR_ASSIGN_RIGHT_SHIFT_ARITHMETIC, TokenType::OPERATOR_RIGHT_SHIFT_ARITHMETIC },
			{ TokenType::OPERATOR_ASSIGN_RIGHT_SHIFT_LOGICAL, TokenType::OPERATOR_RIGHT_SHIFT_LOGICAL },
			{ TokenType::OPERATOR_ASSIGN_AND, TokenType::OPERATOR_AND },
			{ TokenType::OPERATOR_ASSIGN_OR, TokenType::OPERATOR_OR },
		};
		for (const auto& [assignment, operation] : pairs) {
			if (assignment == op) {
				return operation;
			}
		}
		return TokenType::INVALID;
	}

	static bool is_assignment(const ast::Node* node) {
		return ast::NodeType::BINARY_OPERATOR == node->node_type && node->children.size() == 2
			&& (is_assign(node) || TokenType::INVALID != operator_of_assignment(node->value.type));
	}

	// The values of a list, or of one expression, with a call's several results as several; read now.
	static std::vector<Emitted> emit_values(Generator& generator, ast::Node* node, const std::vector<TypeInfo*>& expected) {
		std::vector<ast::Node*> nodes;
		if (ast::NodeType::LIST == node->node_type) {
			nodes.assign(node->children.begin(), node->children.end());
		}
		else {
			nodes.push_back(node);
		}
		std::vector<Emitted> values;
		for (size_t i = 0; i < nodes.size(); ++i) {
			TypeInfo* hint = nodes.size() == 1 && expected.size() == 1 ? expected[0]
				: i < expected.size() && nodes.size() == expected.size() ? expected[i] : nullptr;
			Emitted emitted = emit_expression(generator, nodes[i], hint);
			if (ValueKind::RESULTS == emitted.kind) {
				for (size_t j = 0; j < emitted.results.size(); ++j) {
					values.push_back(value(extract(generator, emitted.value, static_cast<int64_t>(j)), emitted.results[j]));
				}
				continue;
			}
			if (ValueKind::VARIANT == emitted.kind) {
				emitted = value(make_variant(generator, emitted.type, emitted.variant, {}, {}), emitted.type);
			}
			else if (emitted.address && nodes.size() > 1 && !is_array_to_view(emitted.type, hint)) {
				/*
				 * Read before anything is assigned, for a, b = b, a. A single value can't be swapped
				 * with anything, and a view of an array refers to it anyway
				 */
				emitted = value(value_of(generator, emitted), emitted.type);
			}
			values.push_back(emitted);
		}
		return values;
	}

	// a = b, a, b = b, a, and a += b.
	static void emit_assignment(Generator& generator, ast::Node* node) {
		ast::Node* left_node = node->children[0];
		ast::Node* right_node = node->children[1];
		std::vector<ast::Node*> targets;
		if (ast::NodeType::LIST == left_node->node_type) {
			targets.assign(left_node->children.begin(), left_node->children.end());
		}
		else {
			targets.push_back(left_node);
		}
		std::vector<TypeInfo*> types;
		for (ast::Node* target : targets) {
			types.push_back(is_wildcard(target) ? nullptr : type_at(generator, target, nullptr));
		}
		std::vector<Emitted> values;
		if (is_assignment(right_node)) {
			// Chained, right to left: the right one's targets are the values
			emit_assignment(generator, right_node);
			values = emit_values(generator, right_node->children[0], types);
		}
		else {
			values = emit_values(generator, right_node, types);
		}
		const TokenType op = operator_of_assignment(node->value.type);
		for (size_t i = 0; i < targets.size() && !values.empty(); ++i) {
			if (is_wildcard(targets[i])) {
				continue;
			}
			const Emitted& given = values.size() == 1 ? values[0] : values[i];
			Emitted target = emit_expression(generator, targets[i], nullptr);
			if (!target.address) {
				unsupported(generator, targets[i], "this can't be assigned to");
				continue;
			}
			if (TokenType::INVALID == op) {
				store_emitted(generator, given, target.relative != nullptr ? target.relative : target.type, target.address, targets[i]);
				continue;
			}
			mlir::Value v;
			if (is_shift(op)) {
				mlir::Value current = value_of(generator, target);
				v = arithmetic(generator, op, current, shift_amount(generator, value_of(generator, given), current.getType()),
					target.type, node);
			}
			else {
				mlir::Value current = value_of(generator, target);
				mlir::Value operand = convert_emitted(generator, given, target.type);
				v = TokenType::OPERATOR_AND == op ? static_cast<mlir::Value>(LLVM::AndOp::create(generator.builder, generator.loc, current, operand))
					: TokenType::OPERATOR_OR == op ? static_cast<mlir::Value>(LLVM::OrOp::create(generator.builder, generator.loc, current, operand))
					: arithmetic(generator, op, current, operand, target.type, node);
			}
			store(generator, v, target.address);
		}
	}

	// The local a place like x, x.field or x[i] is part of, by its key, or null if it isn't a local's.
	static const void* local_of_place(Generator& generator, const ast::Node* node) {
		while (node != nullptr && !node->children.empty() && ast::NodeType::IDENTIFIER != node->node_type) {
			node = node->children[0];
		}
		if (node == nullptr) {
			return nullptr;
		}
		const CheckedNode* found = head_of(generator, node);
		if (found == nullptr || found->local == nullptr) {
			found = checked(generator, node);
		}
		return found != nullptr ? found->local : nullptr;
	}

	// Every local in node that's assigned to or has its address taken, which needs a slot.
	static void find_locals_in_slots(Generator& generator, const ast::Node* node) {
		if (node == nullptr) {
			return;
		}
		if (is_assignment(node)) {
			const ast::Node* left = node->children[0];
			if (ast::NodeType::LIST == left->node_type) {
				for (const ast::Node* target : left->children) {
					generator.state->in_slot.insert(local_of_place(generator, target));
				}
			}
			else {
				generator.state->in_slot.insert(local_of_place(generator, left));
			}
		}
		if (ast::NodeType::UNARY_OPERATOR == node->node_type && TokenType::SYM_AMPERSAND == node->value.type && !node->children.empty()) {
			generator.state->in_slot.insert(local_of_place(generator, node->children[0]));
		}
		for (const ast::Node* child : node->children) {
			find_locals_in_slots(generator, child);
		}
	}

	/*
	 * Whether a local of type can be kept as a value: a scalar, held in a register, with nothing of it to
	 * take the address of (docs/types.md, Memory Layout), and nothing assigning to it.
	 */
	static bool kept_as_value(Generator& generator, const void* key, TypeInfo* type) {
		TypeInfo const* held = base(type);
		if (held == nullptr || key == nullptr || generator.state->in_slot.contains(key)) {
			return false;
		}
		const TypeInfoVariant variant = held->variant;
		return TypeInfoVariant::INTEGER == variant || TypeInfoVariant::FLOAT == variant || TypeInfoVariant::BOOLEAN == variant
			|| TypeInfoVariant::CHAR == variant || TypeInfoVariant::ENUM == variant || TypeInfoVariant::POINTER == variant
			|| TypeInfoVariant::FUNCTION == variant;
	}

	// x : T = value, x := value, x :: value: a slot for each name, or for a constant, its value's expression.
	static void emit_definition(Generator& generator, ast::Node* definition) {
		std::vector<ast::Node*> names;
		ast::Node* names_node = definition->children[0];
		if (ast::NodeType::LIST == names_node->node_type) {
			names.assign(names_node->children.begin(), names_node->children.end());
		}
		else {
			names.push_back(names_node);
		}
		ast::Node* value_node = nullptr;
		for (size_t i = 1; i < definition->children.size(); ++i) {
			ast::Node* child = definition->children[i];
			if (ast::NodeType::COLON == child->node_type || (ast::NodeType::IDENTIFIER == child->node_type && is_assign(child))) {
				value_node = i + 1 < definition->children.size() ? definition->children[i + 1] : nullptr;
				break;
			}
		}
		// A nested function is generated as its own declaration, wherever it's used (checking.cpp, check_nested_function)
		if (value_node != nullptr && ast::NodeType::FUNCTION == value_node->node_type) {
			return;
		}
		std::vector<TypeInfo*> types;
		bool all_values = true;
		// _ takes a value and drops it
		auto discarded = [](ast::Node* name) { return ast::NodeType::UNDERSCORE == name->node_type; };
		for (size_t i = 0; i < names.size(); ++i) {
			const CheckedNode* found = checked(generator, names[i]);
			const bool is_value = found != nullptr && ValueKind::VALUE == found->kind;
			types.push_back(is_value ? found->type : nullptr);
			all_values = all_values && (is_value || discarded(names[i]));
			// Untyped constants are generated where they're used, as what they're used as
			if (found != nullptr && is_untyped(found->kind) && value_node != nullptr) {
				generator.state->constants[names[i]] = ast::NodeType::LIST == value_node->node_type
					? value_node->children[std::min(i, value_node->children.size() - 1)] : value_node;
			}
		}
		if (!all_values) {
			return;
		}
		std::vector<Emitted> values;
		if (value_node != nullptr && ast::NodeType::UNINITIALIZED != value_node->node_type) {
			values = emit_values(generator, value_node, types);
		}
		for (size_t i = 0; i < names.size(); ++i) {
			if (discarded(names[i])) {
				continue;
			}
			// Never assigned and never pointed at: its value, as it was given
			if (kept_as_value(generator, names[i], types[i])) {
				const Emitted& given = values.empty() ? Emitted{} : values.size() == 1 ? values[0] : values[std::min(i, values.size() - 1)];
				generator.state->values[names[i]] = values.empty() ? zero_of(generator, llvm_type(generator, types[i]))
					: convert_emitted(generator, given, types[i]);
				continue;
			}
			mlir::Value slot = make_slot(generator, types[i]);
			if (values.empty()) {
				store_defaults(generator, types[i], slot);
			}
			else {
				const Emitted& given = values.size() == 1 ? values[0] : values[std::min(i, values.size() - 1)];
				store_emitted(generator, given, types[i], slot);
			}
			generator.state->slots[names[i]] = slot;
		}
	}

	// return values: converted to the function's results.
	static void emit_return_statement(Generator& generator, ast::Node* node) {
		TypeInfoFunction const* function = generator.state->type;
		if (node->children.empty() || (node->children.size() == 1 && ast::NodeType::VOID == node->children[0]->node_type)) {
			emit_return(generator, {});
			return;
		}
		std::vector<TypeInfo*> expected;
		for (const FunctionOutput& output : function->output) {
			expected.push_back(output.type);
		}
		std::vector<Emitted> given;
		for (size_t i = 0; i < node->children.size(); ++i) {
			TypeInfo* hint = node->children.size() == expected.size() ? expected[i] : nullptr;
			std::vector<Emitted> each = emit_values(generator, node->children[i], { hint });
			given.insert(given.end(), each.begin(), each.end());
		}
		// Written where the caller said, from where it is if it's in memory, rather than loaded whole
		if (generator.state->result_pointer && given.size() == 1 && expected.size() == 1) {
			store_emitted(generator, given[0], expected[0], generator.state->result_pointer);
			::hmir::HemeraReturnOp::create(generator.builder, generator.loc, mlir::ValueRange{});
			return;
		}
		std::vector<mlir::Value> values;
		// A static array that's somewhere returns as a view of it, not of a copy on this stack
		for (size_t i = 0; i < given.size() && i < expected.size(); ++i) {
			values.push_back(convert_emitted(generator, given[i], expected[i]));
		}
		emit_return(generator, values);
	}

	// A for loop: through a range, or an array's or string's elements, by value or by &.
	static void emit_for(Generator& generator, ast::Node* node) {
		std::vector<ast::Node*> names;
		ast::Node* iterable = nullptr;
		ast::Node* body = nullptr;
		bool after_in = false;
		bool reverse = false;
		for (ast::Node* child : node->children) {
			const ast::NodeType type = child->node_type;
			if (ast::NodeType::IN == type) {
				after_in = true;
			}
			else if (!after_in) {
				names.push_back(child);
			}
			else if (ast::NodeType::BLOCK == type) {
				body = child;
			}
			else if (ast::NodeType::DIRECTIVE == type && is_text(child->value.value, "#reverse")) {
				reverse = true;
			}
			else if (ast::NodeType::DIRECTIVE == type) {
				unsupported(generator, child, std::format("{} on a for loop can't be generated yet", text_of(child->value.value)));
			}
			else if (iterable == nullptr) {
				iterable = child;
			}
		}
		const TokenType op = iterable->value.type;
		const bool is_range = ast::NodeType::BINARY_OPERATOR == iterable->node_type
			&& (TokenType::OPERATOR_RANGE_EXCLUSIVE == op || TokenType::OPERATOR_RANGE_INCLUSIVE == op);
		// A range's bounds, or where the elements are and how many
		TypeInfo* index_type = BUILTIN_usize;
		mlir::Value low;
		mlir::Value high;
		mlir::Value data;
		TypeInfo* element = nullptr;
		if (is_range) {
			index_type = shared_type(generator, iterable->children[0], iterable->children[1], nullptr);
			low = emit_as(generator, iterable->children[0], index_type);
			high = emit_as(generator, iterable->children[1], index_type);
		}
		else {
			Emitted collection = emit_expression(generator, iterable, nullptr);
			TypeInfo const* type = base(collection.type);
			elements_of(generator, collection, type, data, high);
			element = element_of(type);
			low = constant_int(generator, usize_type(generator), 0);
		}
		mlir::Value next = make_slot(generator, index_type);
		const bool inclusive = is_range && TokenType::OPERATOR_RANGE_INCLUSIVE == op;
		/*
		 * #reverse: from the last down to low. Whether there's more decides, so the index never goes
		 * below low, which for an unsigned low of 0 would wrap
		 */
		mlir::Value more;
		if (reverse) {
			more = make_raw_slot(generator, generator.builder.getI1Type(), 1);
			store(generator, compare(generator, inclusive ? TokenType::OPERATOR_LESS_THAN_OR_EQUAL : TokenType::SYM_LT, low, high,
				index_type), more);
			store(generator, inclusive ? high
				: static_cast<mlir::Value>(LLVM::SubOp::create(generator.builder, generator.loc, high, constant_int(generator, high.getType(), 1))),
				next);
		}
		else {
			store(generator, low, next);
		}
		emit_loop(generator, true, [&]() {
			// The index is taken before the body, so continue moves on to the next
			mlir::Value index = load(generator, index_type, next);
			if (reverse) {
				mlir::Value had_more = LLVM::LoadOp::create(generator.builder, generator.loc, generator.builder.getI1Type(), more);
				emit_if(generator, negate(generator, had_more), [&]() {
					emit_break(generator, 1);
					return true;
				}, nullptr);
				store(generator, compare(generator, TokenType::SYM_GT, index, low, index_type), more);
				store(generator, LLVM::SubOp::create(generator.builder, generator.loc, index, constant_int(generator, index.getType(), 1)), next);
			}
			else {
				emit_if(generator, compare(generator, inclusive ? TokenType::SYM_GT : TokenType::OPERATOR_GREATER_THAN_OR_EQUAL,
					index, high, index_type), [&]() {
					emit_break(generator, 1);
					return true;
				}, nullptr);
				store(generator, LLVM::AddOp::create(generator.builder, generator.loc, index, constant_int(generator, index.getType(), 1)), next);
			}
			for (size_t i = 0; i < names.size(); ++i) {
				ast::Node* name = names[i];
				mlir::Value slot;
				if (i == 1) {
					slot = make_slot(generator, BUILTIN_usize);
					store(generator, convert(generator, index, index_type, BUILTIN_usize), slot);
				}
				else if (is_range) {
					slot = make_slot(generator, index_type);
					store(generator, index, slot);
				}
				else if (ast::NodeType::UNARY_OPERATOR == name->node_type && !name->children.empty()) {
					// By reference: a pointer to the element
					slot = make_raw_slot(generator, pointer_type(generator), POINTER_SIZE);
					store(generator, element_address(generator, data, element, index), slot);
					name = name->children[0];
				}
				else {
					slot = make_slot(generator, element);
					store(generator, load(generator, element, element_address(generator, data, element, index)), slot);
				}
				generator.state->slots[name] = slot;
			}
			emit_scope(generator, [&]() {
				return emit_block(generator, body, mlir::Value(), nullptr);
			});
			return false;
		});
	}

	// loop, with with and while: with wraps the whole loop, and while is checked before each time.
	static void emit_loop_statement(Generator& generator, ast::Node* node) {
		ast::Node* body = nullptr;
		ast::Node* condition = nullptr;
		ast::Node* with = nullptr;
		// #at_least_once: the condition isn't checked the first time around (docs/control_flow.md)
		bool at_least_once = false;
		for (ast::Node* child : node->children) {
			if (ast::NodeType::DIRECTIVE == child->node_type && child->value.value != nullptr
				&& std::string_view(*child->value.value) == "#at_least_once") {
				at_least_once = true;
			}
			else if (ast::NodeType::WITH_CLAUSE == child->node_type) {
				with = child;
			}
			else if (ast::NodeType::BLOCK == child->node_type) {
				body = child;
			}
			else if (ast::NodeType::WHILE_CLAUSE == child->node_type && !child->children.empty()) {
				condition = child->children[0];
			}
		}
		emit_scope(generator, [&]() {
			if (with != nullptr) {
				for (ast::Node* list : with->children) {
					for (ast::Node* statement : list->children) {
						emit_statement(generator, statement);
					}
				}
			}
			// Whether it's the first time around, for #at_least_once
			mlir::Value first;
			if (at_least_once && condition != nullptr) {
				first = make_raw_slot(generator, generator.builder.getI1Type(), 1);
				store(generator, boolean(generator, true), first);
			}
			emit_loop(generator, true, [&]() {
				auto check = [&]() {
					emit_if(generator, negate(generator, emit_condition(generator, condition)), [&]() {
						emit_break(generator, 1);
						return true;
					}, nullptr);
					return false;
				};
				if (condition != nullptr && first) {
					mlir::Value was_first = LLVM::LoadOp::create(generator.builder, generator.loc, generator.builder.getI1Type(), first);
					store(generator, boolean(generator, false), first);
					emit_if(generator, negate(generator, was_first), check, nullptr);
				}
				else if (condition != nullptr) {
					check();
				}
				if (body != nullptr) {
					emit_scope(generator, [&]() {
						return emit_block(generator, body, mlir::Value(), nullptr);
					});
				}
				return false;
			});
			return false;
		});
	}

	// push_context name (field = value...) or from value: a new context for the block.
	static void emit_push_context(Generator& generator, ast::Node* node) {
		Declaration* context_declaration = base_declaration_named(generator, "runtime", "Context");
		TypeInfo* context_type = context_declaration != nullptr ? context_declaration->type_value : nullptr;
		ast::Node* name = node->children.empty() ? nullptr : node->children[0];
		ast::Node* body = node->children.empty() ? nullptr : node->children.back();
		mlir::Value slot = make_slot(generator, context_type);
		bool from = false;
		bool copied = false;
		for (size_t i = 1; i + 1 < node->children.size(); ++i) {
			ast::Node* part = node->children[i];
			if (ast::NodeType::KEYWORD_FROM == part->node_type) {
				// from value: a copy of a whole context, which is the from's child
				from = true;
				if (!part->children.empty()) {
					store(generator, emit_as(generator, part->children[0], context_type), slot);
					copied = true;
				}
				continue;
			}
			if (ast::NodeType::LIST == part->node_type && !from) {
				// The overrides are read before the switch, so they see the old context
				std::vector<std::pair<size_t, mlir::Value>> overrides;
				for (ast::Node* field : part->children) {
					size_t offset = 0;
					TypeInfo* member_type = nullptr;
					std::vector<int64_t> path;
					find_member(generator, static_cast<TypeInfoStruct const*>(base(context_type)), field->children[0]->value.value,
						offset, member_type, path);
					overrides.emplace_back(offset, emit_as(generator, field->children[1], member_type));
				}
				store(generator, load(generator, context_type, generator.state->context), slot);
				for (const auto& [offset, v] : overrides) {
					store(generator, v, offset_address(generator, slot, offset));
				}
				copied = true;
				continue;
			}
			store(generator, emit_as(generator, part, context_type), slot);
			copied = true;
		}
		if (!copied) {
			store(generator, load(generator, context_type, generator.state->context), slot);
		}
		if (name != nullptr && ast::NodeType::IDENTIFIER == name->node_type) {
			generator.state->slots[name] = slot;
		}
		mlir::Value outer = generator.state->context;
		generator.state->context = slot;
		emit_scope(generator, [&]() {
			return body != nullptr && ast::NodeType::BLOCK == body->node_type && emit_block(generator, body, mlir::Value(), nullptr);
		});
		generator.state->context = outer;
	}

	// A statement; returns whether it ended the block (return, break, a call that never returns).
	static bool emit_statement(Generator& generator, ast::Node* statement) {
		if (generator.state != nullptr && generator.state->debug_info) {
			generator.loc = source_location(generator, statement);
		}
		const ast::NodeType type = statement->node_type;
		if (ast::NodeType::DEFINITION == type) {
			emit_definition(generator, statement);
			return false;
		}
		if (is_assignment(statement)) {
			emit_assignment(generator, statement);
			return false;
		}
		if (ast::NodeType::RETURN == type) {
			emit_return_statement(generator, statement);
			return true;
		}
		if (ast::NodeType::BREAK == type) {
			uint64_t depth = 1;
			if (!statement->children.empty()) {
				const ast::Node* count = statement->children[0];
				depth = ast::NodeType::KEYWORD_ALL == count->node_type ? generator.state->breakables.size()
					: std::stoull(text_of(count->value.value));
			}
			emit_break(generator, depth);
			return true;
		}
		if (ast::NodeType::CONTINUE == type) {
			emit_continue(generator);
			return true;
		}
		if (ast::NodeType::IF == type) {
			ast::Node* otherwise = else_of(statement);
			// Only the branch that runs, when #is_compile_time decides which
			if (std::optional<bool> known = known_condition(generator, statement->children[0])) {
				if (*known) {
					return emit_block(generator, statement->children[1], mlir::Value(), nullptr);
				}
				if (otherwise == nullptr) {
					return false;
				}
				return ast::NodeType::IF == otherwise->node_type ? emit_statement(generator, otherwise)
					: emit_block(generator, otherwise, mlir::Value(), nullptr);
			}
			emit_if(generator, emit_condition(generator, statement->children[0]), [&]() {
				return emit_block(generator, statement->children[1], mlir::Value(), nullptr);
			}, otherwise == nullptr ? std::function<bool()>() : [&]() {
				return ast::NodeType::IF == otherwise->node_type ? emit_statement(generator, otherwise)
					: emit_block(generator, otherwise, mlir::Value(), nullptr);
			});
			return false;
		}
		if (ast::NodeType::FOR_LOOP == type) {
			emit_for(generator, statement);
			return false;
		}
		if (ast::NodeType::LOOP == type) {
			emit_loop_statement(generator, statement);
			return false;
		}
		if (ast::NodeType::DEFER == type) {
			auto op = ::hmir::HemeraDeferOp::create(generator.builder, generator.loc);
			fill_region(generator, op.getBodyRegion(), [&]() {
				for (ast::Node* deferred : statement->children) {
					emit_statement(generator, deferred);
				}
				return false;
			});
			return false;
		}
		if (ast::NodeType::BLOCK == type) {
			emit_scope(generator, [&]() {
				return emit_block(generator, statement, mlir::Value(), nullptr);
			});
			return false;
		}
		if (ast::NodeType::MATCH == type) {
			emit_match(generator, statement, nullptr, false);
			return false;
		}
		if (ast::NodeType::SWITCH == type) {
			emit_switch(generator, statement);
			return false;
		}
		if (ast::NodeType::PUSH_CONTEXT == type) {
			emit_push_context(generator, statement);
			return false;
		}
		if (ast::NodeType::DIRECTIVE == type) {
			// #run as a statement runs when its function is generated
			if (is_text(statement->value.value, "#run") && !statement->children.empty()
				&& !generator.compile_time_values.contains(statement)) {
				CompileTimeValue ran;
				run_at_compile_time(generator, statement->children[0], nullptr, generator.state->checked,
					generator.state->declaration, ran);
				generator.compile_time_values.emplace(statement, std::move(ran));
			}
			return false;
		}
		if (emit_expression(generator, statement, nullptr).never_returns) {
			LLVM::UnreachableOp::create(generator.builder, generator.loc);
			return true;
		}
		return false;
	}

	/*
	 * A block's statements, with the branch the checker picked for each #if chain among them; for
	 * a block used as a value, its last statement's value goes in result_slot. Returns whether it
	 * ended itself.
	 */
	static bool emit_block(Generator& generator, ast::Node* block, mlir::Value result_slot, TypeInfo* result_type) {
		for (size_t i = 0; i < block->children.size(); ++i) {
			ast::Node* statement = block->children[i];
			if (ast::NodeType::DIRECTIVE == statement->node_type && is_text(statement->value.value, "#if")) {
				std::vector<ast::Node*> chain{ statement };
				while (i + 1 < block->children.size()
					&& ast::NodeType::DIRECTIVE == block->children[i + 1]->node_type
					&& (is_text(block->children[i + 1]->value.value, "#else_if")
						|| is_text(block->children[i + 1]->value.value, "#else"))) {
					chain.push_back(block->children[++i]);
					if (is_text(chain.back()->value.value, "#else")) {
						break;
					}
				}
				const CheckedNode* chosen = checked(generator, statement);
				if (chosen != nullptr && chosen->variant < chain.size() && !chain[chosen->variant]->children.empty()
					&& emit_block(generator, chain[chosen->variant]->children.back(), mlir::Value(), nullptr)) {
					return true;
				}
				continue;
			}
			const ast::NodeType type = statement->node_type;
			if (i + 1 == block->children.size() && result_slot && ast::NodeType::DEFINITION != type && !is_assignment(statement)
				&& ast::NodeType::RETURN != type && ast::NodeType::BREAK != type && ast::NodeType::CONTINUE != type
				&& ast::NodeType::FOR_LOOP != type && ast::NodeType::LOOP != type && ast::NodeType::BLOCK != type) {
				Emitted result = emit_expression(generator, statement, result_type);
				if (result.never_returns) {
					LLVM::UnreachableOp::create(generator.builder, generator.loc);
					return true;
				}
				store(generator, convert_emitted(generator, result, result_type), result_slot);
				return false;
			}
			if (emit_statement(generator, statement)) {
				return true;
			}
		}
		return false;
	}

	// ---------------------------------------------------------------------------------------------
	// Functions, constants and the entry point

	// A source file's debug info: its name and folder.
	static LLVM::DIFileAttr debug_file(Generator& generator, const std::string& path) {
		auto iter = generator.debug_files.find(path);
		if (iter != generator.debug_files.end()) {
			return iter->second;
		}
		const std::filesystem::path file(path);
		// base's files are named <base>/..., not on disk: kept whole, so tools don't put a folder in front
		LLVM::DIFileAttr result = file.is_absolute()
			? LLVM::DIFileAttr::get(generator.context, file.filename().string(), file.parent_path().string())
			: LLVM::DIFileAttr::get(generator.context, file.generic_string(), "");
		generator.debug_files.emplace(path, result);
		return result;
	}

	// The file being generated, for debug info: base's <base>/... names with / throughout.
	static std::string debug_path(Generator& generator) {
		std::string path = current_file(generator);
		if (!std::filesystem::path(path).is_absolute()) {
			std::replace(path.begin(), path.end(), '\\', '/');
		}
		return path;
	}

	// Where node is, in the file being generated, or the location so far if it has none.
	static mlir::Location source_location(Generator& generator, const ast::Node* node) {
		if (node == nullptr || node->value.line_number == 0) {
			return generator.loc;
		}
		return mlir::FileLineColLoc::get(generator.builder.getStringAttr(debug_path(generator)), node->value.line_number,
			node->value.column_number);
	}

	/*
	 * A function's debug info, with --debug-info: a DISubprogram on the function's location, so the
	 * locations of what's generated in it become line information (DWARF, or CodeView for PE/COFF)
	 * and stack traces and debuggers can name its frames. Compile-time code has none.
	 */
	static bool attach_subprogram(Generator& generator, LLVM::LLVMFuncOp function, Declaration* declaration) {
		if (generator.options == nullptr || !generator.options->debug_info || generator.compile_time || declaration->node == nullptr) {
			return false;
		}
		mlir::MLIRContext* context = generator.context;
		const std::string path = debug_path(generator);
		LLVM::DIFileAttr file = debug_file(generator, path);
		if (!generator.compile_unit) {
			generator.compile_unit = LLVM::DICompileUnitAttr::get(mlir::DistinctAttr::create(mlir::UnitAttr::get(context)),
				llvm::dwarf::DW_LANG_C99, file, mlir::StringAttr::get(context, "hemera"), true, LLVM::DIEmissionKind::Full);
		}
		const unsigned line = declaration->node->value.line_number;
		auto type = LLVM::DISubroutineTypeAttr::get(context, llvm::dwarf::DW_CC_normal, {});
		std::string name = text_of(declaration->name);
		if (declaration->package_path != nullptr) {
			name = std::format("{}.{}", std::filesystem::path(text_of(declaration->package_path)).filename().string(), name);
		}
		auto subprogram = LLVM::DISubprogramAttr::get(context, mlir::DistinctAttr::create(mlir::UnitAttr::get(context)),
			generator.compile_unit, file, mlir::StringAttr::get(context, name), function.getSymNameAttr(), file, line, line,
			LLVM::DISubprogramFlags::Definition | LLVM::DISubprogramFlags::Optimized, type, {}, {});
		mlir::Location start = mlir::FileLineColLoc::get(generator.builder.getStringAttr(path), line, declaration->node->value.column_number);
		function->setLoc(mlir::FusedLoc::get(context, { start }, subprogram));
		generator.loc = start;
		generator.named_functions.emplace_back(function, name);
		return true;
	}

	static void generate_function(Generator& generator, Declaration* declaration) {
		// An entry function's body, not the code around it
		auto body_iter = generator.entry_bodies.find(declaration);
		LLVM::LLVMFuncOp function = body_iter != generator.entry_bodies.end() ? body_iter->second : generator.functions[declaration];
		auto type = static_cast<TypeInfoFunction const*>(declaration->value_type);
		FunctionState state;
		state.declaration = declaration;
		state.checked = declaration->checked.get();
		state.type = type;
		ast::Node* body = function_body(declaration->generic != nullptr ? declaration->generic : declaration);
		mlir::OpBuilder::InsertionGuard guard(generator.builder);
		mlir::Block* entry = function.addEntryBlock(generator.builder);
		state.entry = entry;
		generator.builder.setInsertionPointToEnd(entry);
		FunctionState* outer = generator.state;
		generator.state = &state;
		// Each statement's location, under the function's subprogram, with debug info
		const mlir::Location outer_location = generator.loc;
		state.debug_info = attach_subprogram(generator, function, declaration);
		if (generator.collecting && state.checked == nullptr && body != nullptr) {
			// Compile-time code that runs once this is checked
			generator.unchecked.push_back(declaration);
			LLVM::UnreachableOp::create(generator.builder, generator.loc);
			generator.state = outer;
			generator.loc = outer_location;
			return;
		}
		if (state.checked == nullptr || body == nullptr) {
			unsupported(generator, declaration->node, std::format("{} wasn't checked, so it can't be generated",
				text_of(declaration->name)));
			LLVM::UnreachableOp::create(generator.builder, generator.loc);
			generator.state = outer;
			generator.loc = outer_location;
			return;
		}
		const bool with_context = takes_context(generator, type, declaration);
		const bool through_pointer = result_through_pointer(type);
		const unsigned first = (with_context ? 1 : 0) + (through_pointer ? 1 : 0);
		state.result_pointer = through_pointer ? static_cast<mlir::Value>(entry->getArgument(0)) : mlir::Value();
		state.context = with_context ? static_cast<mlir::Value>(entry->getArgument(through_pointer ? 1 : 0)) : mlir::Value();
		find_locals_in_slots(generator, body);
		/*
		 * Parameters and named results in slots, but for a parameter kept as its value; one too large for
		 * registers is the caller's copy already
		 */
		for (size_t i = 0; i < state.checked->parameters.size() && i < type->input.size(); ++i) {
			mlir::Value argument = entry->getArgument(static_cast<unsigned>(i) + first);
			if (parameter_by_pointer(type, type->input[i])) {
				state.slots[state.checked->parameters[i]] = argument;
				continue;
			}
			if (kept_as_value(generator, state.checked->parameters[i], type->input[i].type)) {
				state.values[state.checked->parameters[i]] = argument;
				continue;
			}
			mlir::Value slot = make_raw_slot(generator, argument.getType(), std::max<size_t>(type->input[i].type->alignment, 1));
			store(generator, argument, slot);
			state.slots[state.checked->parameters[i]] = slot;
		}
		for (size_t i = 0; i < state.checked->outputs.size() && i < type->output.size(); ++i) {
			if (state.checked->outputs[i] != nullptr) {
				mlir::Value slot = make_slot(generator, type->output[i].type);
				store_zero(generator, type->output[i].type, slot);
				state.slots[state.checked->outputs[i]] = slot;
			}
		}
		if (!emit_block(generator, body, mlir::Value(), nullptr)) {
			// Falling off the end, which the checker allows only without results
			if (type->output.empty()) {
				::hmir::HemeraReturnOp::create(generator.builder, generator.loc, mlir::ValueRange{});
			}
			else {
				LLVM::UnreachableOp::create(generator.builder, generator.loc);
			}
		}
		generator.state = outer;
		generator.loc = outer_location;
	}

	// A typed constant's global, read-only, made the first time it's used.
	static LLVM::GlobalOp global_for(Generator& generator, Declaration* declaration) {
		auto iter = generator.globals.find(declaration);
		if (iter != generator.globals.end()) {
			return iter->second;
		}
		mlir::Type type = llvm_type(generator, declaration->value_type);
		mlir::OpBuilder::InsertionGuard guard(generator.builder);
		generator.builder.setInsertionPointToEnd(generator.module.getBody());
		// #externally_initialized ones can be replaced in the image, so they aren't constant to LLVM
		LLVM::GlobalOp global = LLVM::GlobalOp::create(generator.builder, generator.loc, type,
			!declaration->externally_initialized, LLVM::Linkage::Internal, symbol_for(generator, declaration),
			mlir::Attribute(), std::max<size_t>(declaration->value_type->alignment, 1));
		if (declaration->section != nullptr) {
			global.setSectionAttr(generator.builder.getStringAttr(text_of(declaration->section)));
		}
		if (declaration->externally_initialized) {
			global.setExternallyInitialized(true);
			generator.used.push_back(global);
		}
		if (has_name_directive(declaration, "#export")) {
			global.setLinkage(LLVM::Linkage::External);
			global.setSymName(text_of(declaration->name));
		}
		generator.globals[declaration] = global;
		generator.builder.setInsertionPointToStart(generator.builder.createBlock(&global.getInitializerRegion()));
		ast::Node* value_node = definition_value(declaration->node);
		FunctionState* outer = generator.state;
		generator.state = nullptr;
		mlir::Value initial = value_node == nullptr || ast::NodeType::UNINITIALIZED == value_node->node_type
			? zero_of(generator, type) : emit_constant_value(generator, declaration, declaration->value_type, value_node);
		generator.state = outer;
		// A union's variant built as its own shape (make_variant): the global has that type, and the same bytes
		if (initial.getType() != type) {
			global.setGlobalType(initial.getType());
		}
		LLVM::ReturnOp::create(generator.builder, generator.loc, initial);
		return global;
	}

	/*
	 * The instructions moving the carrier register (docs/calling_convention.md, Carrier Register) into an
	 * operand, and from one: r14 on x86-64, x28 on AArch64.
	 */
	static const char* carrier_to_operand(const Generator& generator) {
		return ArchType::aarch64 == generator.options->architecture ? "mov $0, x28" : "movq %r14, $0";
	}

	static const char* operand_to_carrier(const Generator& generator) {
		return ArchType::aarch64 == generator.options->architecture ? "mov x28, $0" : "movq $0, %r14";
	}

	// Whether the target is Linux on an architecture whose start and system calls the compiler knows.
	static bool hosted_linux(const Generator& generator) {
		const ArchType architecture = generator.options->architecture;
		return OSType::Linux == generator.options->os && (ArchType::x86_64 == architecture || ArchType::aarch64 == architecture);
	}

	/*
	 * A hosted program's entry: a zeroed context for main, whose result, if it has one, is the
	 * exit code.
	 */
	static void generate_entry(Generator& generator, Declaration* main, bool windows) {
		Declaration* context_declaration = base_declaration_named(generator, "runtime", "Context");
		TypeInfo* context_type = context_declaration != nullptr ? context_declaration->type_value : nullptr;
		auto main_type = static_cast<TypeInfoFunction const*>(main->value_type);
		LLVM::LLVMFuncOp main_function = function_for(generator, main);
		mlir::OpBuilder::InsertionGuard guard(generator.builder);
		generator.builder.setInsertionPointToEnd(generator.module.getBody());
		mlir::Type i32 = integer_type(generator, 4);
		/*
		 * On Linux the entry is called as C's main is, with argc, argv and envp: by libc when the
		 * program links C, and by _start otherwise, which finds them on the stack the kernel set up
		 */
		const bool linux_x86 = hosted_linux(generator);
		/*
		 * On SlopOS the entry is where the process starts, called as a function is with one argument, the
		 * process's startup block, and nothing to return to: it ends the process with main's result
		 */
		const bool slop_os = OSType::SlopOS == generator.options->os;
		std::vector<mlir::Type> entry_parameters;
		if (linux_x86) {
			entry_parameters = { i32, pointer_type(generator), pointer_type(generator) };
		}
		else if (slop_os) {
			entry_parameters = { pointer_type(generator) };
		}
		auto entry_function = LLVM::LLVMFuncOp::create(generator.builder, generator.loc, HOSTED_ENTRY_SYMBOL,
			LLVM::LLVMFunctionType::get(i32, entry_parameters));
		mlir::Block* entry_block = entry_function.addEntryBlock(generator.builder);
		generator.builder.setInsertionPointToEnd(entry_block);
		mlir::Value one = constant_int(generator, usize_type(generator), 1);
		// What the process started with, for runtime.process_arguments and std/os's environment
		LLVM::GlobalOp process = linux_x86 || slop_os ? process_state_global(generator) : LLVM::GlobalOp();
		size_t startup_block = 0;
		if (slop_os && process && runtime_offset(generator, "ProcessState", "startup_block", startup_block)) {
			mlir::Value state = LLVM::AddressOfOp::create(generator.builder, generator.loc, process);
			LLVM::StoreOp::create(generator.builder, generator.loc, entry_block->getArgument(0), offset_address(generator, state, startup_block));
		}
		size_t argument_count = 0;
		size_t argument_pointers = 0;
		size_t environment_pointers = 0;
		if (linux_x86 && process && runtime_offset(generator, "ProcessState", "argument_count", argument_count)
			&& runtime_offset(generator, "ProcessState", "argument_pointers", argument_pointers)
			&& runtime_offset(generator, "ProcessState", "environment_pointers", environment_pointers)) {
			mlir::Value state = LLVM::AddressOfOp::create(generator.builder, generator.loc, process);
			mlir::Value count = LLVM::SExtOp::create(generator.builder, generator.loc, usize_type(generator), entry_block->getArgument(0));
			LLVM::StoreOp::create(generator.builder, generator.loc, count, offset_address(generator, state, argument_count));
			LLVM::StoreOp::create(generator.builder, generator.loc, entry_block->getArgument(1), offset_address(generator, state, argument_pointers));
			LLVM::StoreOp::create(generator.builder, generator.loc, entry_block->getArgument(2), offset_address(generator, state, environment_pointers));
		}
		mlir::Value context = LLVM::AllocaOp::create(generator.builder, generator.loc, pointer_type(generator),
			llvm_type(generator, context_type), one, static_cast<unsigned>(context_type->alignment));
		store_zero(generator, context_type, context);
		// base/runtime's HOSTED_CONTEXT, like the process heap as the allocator, where it has one
		Declaration* hosted_context = base_declaration_named(generator, "runtime", "HOSTED_CONTEXT");
		if (hosted_context != nullptr) {
			store(generator, emit_constant_value(generator, hosted_context, context_type, nullptr), context);
		}
		/*
		 * A carrier block for the main thread, zeroed: no stack limit to check, no fiber and no
		 * scheduler yet. The carrier register is the caller's to keep, so it's put back if the entry
		 * returns.
		 */
		Declaration* carrier_declaration = base_declaration_named(generator, "runtime", "CarrierBlock");
		mlir::Value callers_carrier;
		if ((ArchType::x86_64 == generator.options->architecture || ArchType::aarch64 == generator.options->architecture)
			&& carrier_declaration != nullptr
			&& carrier_declaration->type_value != nullptr) {
			TypeInfo* carrier_type = carrier_declaration->type_value;
			mlir::Value carrier = LLVM::AllocaOp::create(generator.builder, generator.loc, pointer_type(generator),
				llvm_type(generator, carrier_type), one, static_cast<unsigned>(carrier_type->alignment));
			store_zero(generator, carrier_type, carrier);
			// Segments for morestack come from the same allocator as main's context
			size_t segment_allocator = 0;
			size_t allocator = 0;
			if (runtime_offset(generator, "CarrierBlock", "segment_allocator", segment_allocator)
				&& runtime_offset(generator, "Context", "allocator", allocator)) {
				Declaration* allocator_declaration = base_declaration_named(generator, "runtime", "Allocator");
				if (allocator_declaration != nullptr && allocator_declaration->type_value != nullptr) {
					TypeInfo* allocator_type = allocator_declaration->type_value;
					store(generator, load(generator, allocator_type, offset_address(generator, context, allocator)),
						offset_address(generator, carrier, segment_allocator));
				}
			}
			callers_carrier = assembly(generator, integer_type(generator, 8), {}, carrier_to_operand(generator), "=r");
			assembly(generator, mlir::Type(), { carrier }, operand_to_carrier(generator), "r,~{memory}");
			// Where callbacks from foreign code find it, where the runtime has that
			if (Declaration* registers = base_declaration_named(generator, "runtime", "register_carrier")) {
				LLVM::CallOp::create(generator.builder, generator.loc, function_for(generator, registers), mlir::ValueRange{ carrier });
			}
			// Its stack's limit, where the runtime knows it, like SlopOS's from the startup block
			if (Declaration* prepares = base_declaration_named(generator, "runtime", "os_prepare_carrier")) {
				LLVM::CallOp::create(generator.builder, generator.loc, function_for(generator, prepares), mlir::ValueRange{ carrier });
			}
		}
		std::vector<mlir::Value> main_arguments{ context };
		if (slop_os) {
			// Each parameter from the startup grant of its name (docs/compilation.md, Entry Parameters)
			Declaration* finds = base_declaration_named(generator, "runtime", "os_entry_grant");
			for (const FunctionInput& input : main_type->input) {
				const EntryGrant grant = entry_grant_of(input.type);
				if (finds == nullptr || grant.kind.empty()) {
					unsupported(generator, main->node, "a SlopOS entry's parameters need base's runtime.os_entry_grant, and handle types");
					break;
				}
				mlir::Value handle = LLVM::CallOp::create(generator.builder, generator.loc, function_for(generator, finds), mlir::ValueRange{
					string_value(generator, text_of(input.name), BUILTIN_string), string_value(generator, grant.kind, BUILTIN_string),
					string_value(generator, grant.protocol, BUILTIN_string),
					constant_int(generator, llvm_type(generator, BUILTIN_bool), grant.optional ? 0 : 1) }).getResult();
				mlir::Value slot = LLVM::AllocaOp::create(generator.builder, generator.loc, pointer_type(generator),
					llvm_type(generator, input.type), one, static_cast<unsigned>(input.type->alignment));
				store_zero(generator, input.type, slot);
				if (grant.optional) {
					// Some (0) with the handle, or None (1) without one
					auto optional = static_cast<TypeInfoUnion const*>(base(input.type));
					mlir::Type tag_type = llvm_type(generator, optional->tag_type);
					mlir::Value missing = LLVM::ICmpOp::create(generator.builder, generator.loc, LLVM::ICmpPredicate::eq, handle,
						constant_int(generator, handle.getType(), 0));
					LLVM::StoreOp::create(generator.builder, generator.loc, LLVM::ZExtOp::create(generator.builder, generator.loc, tag_type, missing),
						slot);
					LLVM::StoreOp::create(generator.builder, generator.loc, handle,
						offset_address(generator, slot, optional->variants[0].offsets[0]));
				}
				else {
					LLVM::StoreOp::create(generator.builder, generator.loc, handle, slot);
				}
				main_arguments.push_back(parameter_by_pointer(main_type, input) ? slot : load(generator, input.type, slot));
			}
		}
		auto call = LLVM::CallOp::create(generator.builder, generator.loc, main_function, main_arguments);
		// A real call, so main has a frame of its own: stack traces end at the entry's, which isn't recorded
		call.setNoInlineAttr(generator.builder.getUnitAttr());
		mlir::Value code = constant_int(generator, i32, 0);
		if (main_type->output.size() == 1 && is_variant(main_type->output[0].type, TypeInfoVariant::INTEGER)) {
			code = call.getResult();
			const unsigned width = code.getType().getIntOrFloatBitWidth();
			if (width > 32) {
				code = LLVM::TruncOp::create(generator.builder, generator.loc, i32, code);
			}
			else if (width < 32) {
				code = LLVM::SExtOp::create(generator.builder, generator.loc, i32, code);
			}
		}
		// The process ends with main's result, through base/runtime, which knows the call
		if (slop_os) {
			if (Declaration* exits = base_declaration_named(generator, "runtime", "os_exit_process")) {
				LLVM::CallOp::create(generator.builder, generator.loc, function_for(generator, exits), mlir::ValueRange{ code });
			}
			LLVM::UnreachableOp::create(generator.builder, generator.loc);
			return;
		}
		if (!windows) {
			if (callers_carrier) {
				assembly(generator, mlir::Type(), { callers_carrier }, operand_to_carrier(generator), "r,~{memory}");
			}
			LLVM::ReturnOp::create(generator.builder, generator.loc, code);
			const bool aarch64 = ArchType::aarch64 == generator.options->architecture;
			if (OSType::Linux == generator.options->os && aarch64 && generator.c_library) {
				/*
				 * As crt1.o's _start on AArch64: rtld_fini from x0, argc and argv from the stack, the stack
				 * itself as stack_end, no init or fini of its own, and the entry as main
				 */
				generator.module_assembly.push_back(std::format(
					"\t.text\n\t.globl {0}\n\t.p2align 4\n{0}:\n\tmov x29, xzr\n\tmov x30, xzr\n\tmov x5, x0\n"
					"\tldr x1, [sp]\n\tadd x2, sp, #8\n\tmov x6, sp\n\tadrp x0, {1}\n\tadd x0, x0, :lo12:{1}\n"
					"\tmov x3, xzr\n\tmov x4, xzr\n\tbl __libc_start_main\n\tbrk #1\n",
					LINUX_START_SYMBOL, HOSTED_ENTRY_SYMBOL));
			}
			else if (OSType::Linux == generator.options->os && aarch64) {
				/*
				 * As on x86-64, with no C library: argc, argv and envp from the stack, which Linux leaves
				 * 16-byte aligned, the entry called, then exit_group (94) with its result
				 */
				generator.module_assembly.push_back(std::format(
					"\t.text\n\t.globl {0}\n\t.p2align 4\n{0}:\n\tmov x29, xzr\n\tmov x30, xzr\n"
					"\tldr x0, [sp]\n\tadd x1, sp, #8\n\tadd x2, x1, x0, lsl #3\n\tadd x2, x2, #8\n"
					"\tbl {1}\n\tmov x8, #94\n\tsvc #0\n\tbrk #1\n",
					LINUX_START_SYMBOL, HOSTED_ENTRY_SYMBOL));
			}
			if (OSType::Linux == generator.options->os && ArchType::x86_64 == generator.options->architecture && generator.c_library) {
				/*
				 * Linking C, the program starts through libc, which sets itself up first and calls the
				 * entry as main, then exits with its result through exit, which flushes C's streams. The
				 * same as crt1.o's _start: argc and argv from the stack, rtld_fini from rdx, the stack
				 * aligned, and no init or fini of its own.
				 */
				generator.module_assembly.push_back(std::format(
					"\t.text\n\t.globl {0}\n\t.p2align 4\n{0}:\n\txorl %ebp, %ebp\n\tmovq %rdx, %r9\n\tpopq %rsi\n"
					"\tmovq %rsp, %rdx\n\tandq $-16, %rsp\n\tpushq %rax\n\tpushq %rsp\n\txorl %r8d, %r8d\n\txorl %ecx, %ecx\n"
					"\tleaq {1}(%rip), %rdi\n\tcallq __libc_start_main\n\thlt\n",
					LINUX_START_SYMBOL, HOSTED_ENTRY_SYMBOL));
			}
			else if (OSType::Linux == generator.options->os && ArchType::x86_64 == generator.options->architecture) {
				/*
				 * Linux starts a static program at _start, with the stack pointer 16-byte aligned rather
				 * than as a call leaves it, and nothing to return to: it calls the entry with argc, argv
				 * and envp from the stack (argc, then argv's pointers and a null, then envp's), then ends
				 * the process with exit_group and the entry's result. No C library, so nothing else runs
				 * first.
				 */
				generator.module_assembly.push_back(std::format(
					"\t.text\n\t.globl {0}\n\t.p2align 4\n{0}:\n\txorl %ebp, %ebp\n\tmovq (%rsp), %rdi\n"
					"\tleaq 8(%rsp), %rsi\n\tleaq 16(%rsp,%rdi,8), %rdx\n\tandq $-16, %rsp\n"
					"\tcallq {1}\n\tmovl %eax, %edi\n\tmovl $231, %eax\n\tsyscall\n\tud2\n",
					LINUX_START_SYMBOL, HOSTED_ENTRY_SYMBOL));
			}
			return;
		}
		/*
		 * On Windows, returning from the entry only ends its thread, and the process ends with the
		 * last thread's exit code, which may be a loader worker's. ExitProcess ends it with ours.
		 */
		LLVM::LLVMFuncOp exit_process;
		{
			mlir::OpBuilder::InsertionGuard declaration_guard(generator.builder);
			generator.builder.setInsertionPointToEnd(generator.module.getBody());
			exit_process = LLVM::LLVMFuncOp::create(generator.builder, generator.loc, "ExitProcess",
				LLVM::LLVMFunctionType::get(LLVM::LLVMVoidType::get(generator.context), { i32 }));
			// LLVM refers to _fltused from code using floating point on Windows; the C runtime would define it
			LLVM::GlobalOp::create(generator.builder, generator.loc, i32, false, LLVM::Linkage::External, "_fltused",
				generator.builder.getI32IntegerAttr(0));
		}
		LLVM::CallOp::create(generator.builder, generator.loc, exit_process, mlir::ValueRange{ code });
		LLVM::UnreachableOp::create(generator.builder, generator.loc);
	}

	// Declarations by package path, then name, so what's generated from them comes out in the same order every time.
	static void sort_by_name(std::vector<Declaration*>& declarations) {
		const auto text = [](InternedString name) { return name != nullptr ? std::string_view(*name) : std::string_view(); };
		std::sort(declarations.begin(), declarations.end(), [&](const Declaration* a, const Declaration* b) {
			return std::make_pair(text(a->package_path), text(a->name)) < std::make_pair(text(b->package_path), text(b->name));
		});
	}

	/*
	 * What's kept though nothing in the program uses it: #externally_initialized constants, which
	 * something outside fills in, like Limine's requests, and #export functions and constants.
	 */
	static void generate_kept(Generator& generator) {
		std::vector<Declaration*> declarations;
		{
			std::scoped_lock<std::mutex> lock(generator.names.mutex);
			for (const auto& [key, declaration] : generator.names.declarations) {
				declarations.push_back(declaration);
			}
		}
		// The map is ordered by the names' addresses, which change from run to run; the output shouldn't
		sort_by_name(declarations);
		// Code only exists at compile time: a macro, or a function taking or giving it, can't be in the program
		auto only_compile_time = [&](Declaration* declaration) {
			auto is_code = [&](TypeInfo const* type) {
				TypeInfo const* base_type = type != nullptr ? get_base_type(type) : nullptr;
				return base_type != nullptr && TypeInfoVariant::STRUCT == base_type->variant
					&& is_code_struct(generator, static_cast<TypeInfoStruct const*>(base_type));
			};
			TypeInfo const* type = get_base_type(declaration->value_type);
			if (is_macro_function(declaration) || type == nullptr || TypeInfoVariant::FUNCTION != type->variant) {
				return is_macro_function(declaration);
			}
			auto function = static_cast<TypeInfoFunction const*>(type);
			return std::any_of(function->input.begin(), function->input.end(), [&](const FunctionInput& input) { return is_code(input.type); })
				|| std::any_of(function->output.begin(), function->output.end(), [&](const FunctionOutput& output) { return is_code(output.type); });
		};
		for (Declaration* declaration : declarations) {
			if (declaration->generic != nullptr || declaration->value_type == nullptr || declaration->failed) {
				continue;
			}
			const bool exported = has_name_directive(declaration, "#export");
			if (DeclarationKind::VALUE == declaration->kind && (declaration->externally_initialized || exported)) {
				global_for(generator, declaration);
			}
			else if (DeclarationKind::FUNCTION == declaration->kind && exported && !is_intrinsic(declaration)) {
				function_for(generator, declaration);
			}
			// --generate-all: every function, used or not, but those that only run at compile time
			else if (DeclarationKind::FUNCTION == declaration->kind && generator.options->generate_all && !is_intrinsic(declaration)
				&& declaration->node != nullptr && !is_constraint_function(declaration) && !only_compile_time(declaration)) {
				function_for(generator, declaration);
			}
		}
	}

	/*
	 * intrinsics.function_names' table, if the program asks for it, as runtime.FunctionName: each
	 * function with debug info's start and name, and every other function the module defines, with
	 * no name, since where one starts is where the one before it ends.
	 */
	static void generate_function_names(Generator& generator) {
		if (!generator.function_names) {
			return;
		}
		if (!generator.named_functions.empty()) {
			std::set<mlir::Operation*> named;
			for (auto& [function, name] : generator.named_functions) {
				named.insert(function.getOperation());
			}
			for (LLVM::LLVMFuncOp function : generator.module.getOps<LLVM::LLVMFuncOp>()) {
				if (!function.isExternal() && !named.contains(function.getOperation())) {
					generator.named_functions.emplace_back(function, "");
				}
			}
		}
		mlir::OpBuilder::InsertionGuard guard(generator.builder);
		mlir::Type view_type = generator.function_names.getGlobalType();
		auto view_struct = llvm::cast<LLVM::LLVMStructType>(view_type);
		TypeInfo* entry_info = static_cast<TypeInfoArray const*>(base(generator.function_names_type))->element_type;
		mlir::Type entry_type = llvm_type(generator, entry_info);
		const size_t count = generator.named_functions.size();
		LLVM::GlobalOp table;
		if (count > 0) {
			generator.builder.setInsertionPointToEnd(generator.module.getBody());
			mlir::Type table_type = LLVM::LLVMArrayType::get(entry_type, count);
			table = LLVM::GlobalOp::create(generator.builder, generator.loc, table_type, true, LLVM::Linkage::Internal,
				"hemera.function_table", mlir::Attribute(), 8);
			generator.builder.setInsertionPointToStart(generator.builder.createBlock(&table.getInitializerRegion()));
			mlir::Value entries = LLVM::UndefOp::create(generator.builder, generator.loc, table_type);
			mlir::Type usize = usize_type(generator);
			for (size_t i = 0; i < count; ++i) {
				const auto& [function, name] = generator.named_functions[i];
				const int64_t index = static_cast<int64_t>(i);
				entries = insert(generator, entries, LLVM::AddressOfOp::create(generator.builder, generator.loc, function), { index, 0 });
				entries = insert(generator, entries, constant_int(generator, usize, static_cast<int64_t>(name.size())), { index, 1, 0 });
				entries = insert(generator, entries, string_bytes(generator, name), { index, 1, 1 });
			}
			LLVM::ReturnOp::create(generator.builder, generator.loc, entries);
		}
		generator.builder.setInsertionPointToStart(generator.builder.createBlock(&generator.function_names.getInitializerRegion()));
		mlir::Value view = LLVM::UndefOp::create(generator.builder, generator.loc, view_struct);
		view = insert(generator, view, constant_int(generator, view_struct.getBody()[0], static_cast<int64_t>(count)), { 0 });
		view = insert(generator, view, table ? static_cast<mlir::Value>(LLVM::AddressOfOp::create(generator.builder, generator.loc, table))
			: zero_of(generator, pointer_type(generator)), { 1 });
		LLVM::ReturnOp::create(generator.builder, generator.loc, view);
	}

	// llvm.used, which keeps globals that nothing refers to, like Limine's requests, through linking.
	static void generate_used(Generator& generator) {
		if (generator.used.empty()) {
			return;
		}
		mlir::OpBuilder::InsertionGuard guard(generator.builder);
		generator.builder.setInsertionPointToEnd(generator.module.getBody());
		mlir::Type type = LLVM::LLVMArrayType::get(pointer_type(generator), generator.used.size());
		auto used = LLVM::GlobalOp::create(generator.builder, generator.loc, type, false, LLVM::Linkage::Appending, "llvm.used",
			mlir::Attribute());
		used.setSectionAttr(generator.builder.getStringAttr("llvm.metadata"));
		generator.builder.setInsertionPointToStart(generator.builder.createBlock(&used.getInitializerRegion()));
		mlir::Value list = LLVM::UndefOp::create(generator.builder, generator.loc, type);
		for (size_t i = 0; i < generator.used.size(); ++i) {
			list = insert(generator, list, LLVM::AddressOfOp::create(generator.builder, generator.loc, generator.used[i]),
				{ static_cast<int64_t>(i) });
		}
		LLVM::ReturnOp::create(generator.builder, generator.loc, list);
	}

	// The module's assembly, as the attribute translation turns into module-level assembly.
	static void finish_module(Generator& generator) {
		if (!generator.libraries.empty()) {
			std::vector<mlir::Attribute> names;
			for (const std::string& library : generator.libraries) {
				names.push_back(generator.builder.getStringAttr(library));
			}
			generator.module->setAttr(LIBRARIES_ATTRIBUTE, generator.builder.getArrayAttr(names));
		}
		if (generator.module_assembly.empty()) {
			return;
		}
		std::vector<mlir::Attribute> lines;
		for (const std::string& text : generator.module_assembly) {
			lines.push_back(generator.builder.getStringAttr(text));
		}
		generator.module->setAttr(LLVM::LLVMDialect::getModuleLevelAsmAttrName(), generator.builder.getArrayAttr(lines));
	}

	// ---------------------------------------------------------------------------------------------
	// base/compiler's functions, carried out by the compiler for compile-time code (docs/compilation.md)

	namespace {

		// A call to one of base/compiler's functions, with its arguments where the compiled code put them.
		struct Call {
			std::string_view name;
			uint8_t* result;
			uint8_t* const* arguments;
			size_t count;
			const uint8_t* context;
			std::string file;
			TypeInfoFunction const* type;
			ProgramInfo* program;
			const Options* options;
			CompileTimeData& data;
		};

		uint64_t read_u64(const uint8_t* at) {
			uint64_t value = 0;
			std::memcpy(&value, at, sizeof(value));
			return value;
		}

		std::string_view read_string(const uint8_t* at) {
			const char* text = reinterpret_cast<const char*>(read_u64(at + 8));
			return text != nullptr ? std::string_view(text, read_u64(at)) : std::string_view();
		}

		const TypeInfoStruct* struct_of(const TypeInfo* type) {
			const TypeInfo* base_type = get_base_type(type);
			return base_type != nullptr && TypeInfoVariant::STRUCT == base_type->variant ? static_cast<const TypeInfoStruct*>(base_type) : nullptr;
		}

		// What an optional result holds: none, or its value written by fill.
		void write_optional(Call& call, bool some, const std::function<void(uint8_t*, const TypeInfoStruct*)>& fill) {
			const TypeInfo* optional = call.type->output[0].type;
			auto union_type = static_cast<const TypeInfoUnion*>(get_base_type(optional));
			if (!some) {
				CompileTimeData::write_number_at(call.result, union_type->tag_type->size, 1);
				return;
			}
			uint8_t* value = CompileTimeData::write_some_at(call.result, optional);
			fill(value, struct_of(union_type->variants[0].types[0]));
		}

		// A SourceCodeLocation record's fields.
		void write_location(CompileTimeData& data, uint8_t* at, const TypeInfo* location_type, std::string_view file, uint32_t line,
			uint16_t column) {

			const TypeInfoStruct* layout = struct_of(location_type);
			data.write_text(at, layout, "file_path", file);
			data.write_number(at, layout, "line", line);
			data.write_number(at, layout, "column", column);
		}

		void write_location_field(CompileTimeData& data, uint8_t* record, const TypeInfoStruct* layout, std::string_view file,
			const ast::Node* node) {

			size_t offset = 0;
			const TypeInfo* field_type = nullptr;
			if (CompileTimeData::find_field(layout, "location", offset, field_type)) {
				write_location(data, record + offset, field_type, file, node != nullptr ? node->value.line_number : 1,
					node != nullptr ? node->value.column_number : uint16_t(1));
			}
		}

		// A view field of records, each written by fill, count of them.
		void write_records(CompileTimeData& data, uint8_t* record, const TypeInfoStruct* layout, std::string_view field, size_t count,
			const std::function<void(uint8_t*, const TypeInfoStruct*, size_t)>& fill) {

			size_t offset = 0;
			const TypeInfo* field_type = nullptr;
			if (!CompileTimeData::find_field(layout, field, offset, field_type) || count == 0) {
				return;
			}
			const TypeInfo* element = static_cast<const TypeInfoArray*>(get_base_type(field_type))->element_type;
			uint8_t* elements = data.allocate(element->size * count, std::max<size_t>(element->alignment, 1));
			for (size_t i = 0; i < count; ++i) {
				fill(elements + i * element->size, struct_of(element), i);
			}
			CompileTimeData::write_view_at(record + offset, elements, count);
		}

		std::string declaration_file(Declaration* declaration) {
			return file_path_of(declaration->package_path, declaration->file_name);
		}

		// The front end's package at a canonical path.
		hemera::PackageInfo* package_at(ProgramInfo* program, std::string_view path) {
			std::scoped_lock<std::mutex> lock(program->packages_mutex);
			auto iter = program->packages.find(intern(std::string(path)));
			return iter != program->packages.end() ? iter->second : nullptr;
		}

		// A package's top-level declarations, by name, without instances of generics.
		std::vector<Declaration*> declarations_of(ProgramInfo* program, std::string_view path) {
			std::vector<Declaration*> result;
			InternedString package_path = intern(std::string(path));
			std::scoped_lock<std::mutex> lock(program->names.mutex);
			for (const auto& [key, declaration] : program->names.declarations) {
				if (key.first != nullptr && *key.first == *package_path && declaration->generic == nullptr) {
					result.push_back(declaration);
				}
			}
			sort_by_name(result);
			return result;
		}

		bool is_constant(Declaration* declaration) {
			return DeclarationKind::VALUE == declaration->kind && declaration->type_value == nullptr && declaration->checked != nullptr;
		}

		bool is_type(Declaration* declaration) {
			return declaration->type_value != nullptr && DeclarationKind::FUNCTION != declaration->kind;
		}

		/*
		 * Constants' values, worked out in one run: each one's type (an untyped one's default) and a copy of its
		 * value in the compile-time data. Values that can't be worked out are left null.
		 */
		std::vector<std::pair<const TypeInfo*, const uint8_t*>> constant_values(Call& call, const std::vector<Declaration*>& constants) {
			std::vector<std::pair<const TypeInfo*, const uint8_t*>> result(constants.size(), { nullptr, nullptr });
			if (constants.empty()) {
				return result;
			}
			// The ones worked out already
			std::vector<bool> known(constants.size(), false);
			{
				std::scoped_lock<std::mutex> lock(call.data.constant_values_mutex);
				for (size_t i = 0; i < constants.size(); ++i) {
					auto found = call.data.constant_values.find(constants[i]);
					if (found != call.data.constant_values.end()) {
						result[i] = found->second;
						known[i] = true;
					}
				}
			}
			// What's worked out now is kept for next time, values or not
			auto remember = [&]() {
				std::scoped_lock<std::mutex> lock(call.data.constant_values_mutex);
				for (size_t i = 0; i < constants.size(); ++i) {
					if (!known[i]) {
						call.data.constant_values[constants[i]] = result[i];
					}
				}
			};
			std::vector<CompileTimeValue> values(constants.size());
			// Whether each value could be kept: one holding a function, say, can't, and is left out
			std::unique_ptr<bool[]> kept(new bool[constants.size()]());
			std::vector<CompileTimeItem> items;
			std::vector<size_t> positions;
			for (size_t i = 0; i < constants.size(); ++i) {
				Declaration* constant = constants[i];
				if (known[i]) {
					continue;
				}
				TypeInfo* type = constant->value_type;
				if (type == nullptr) {
					type = Untyped::INTEGER == constant->untyped ? BUILTIN_int : Untyped::FLOAT == constant->untyped ? BUILTIN_f64
						: Untyped::STRING == constant->untyped ? BUILTIN_string : Untyped::BOOLEAN == constant->untyped ? BUILTIN_bool : nullptr;
				}
				if (type == nullptr || constant->externally_initialized) {
					continue;
				}
				result[i].first = type;
				items.push_back(CompileTimeItem{ definition_value(constant->node), type, constant->checked.get(), constant, &values[i] });
				items.back().captured = &kept[i];
				positions.push_back(i);
			}
			if (items.empty()) {
				remember();
				return result;
			}
			// All at once, or if that fails, each half, and so on down, leaving out what can't be worked out
			auto run = [&](std::vector<CompileTimeItem>& batch) {
				mlir::ModuleOp scratch = mlir::ModuleOp::create(mlir::UnknownLoc::get(call.program->context), "constants");
				bool ran = false;
				{
					Generator generator(call.program, scratch);
					generator.options = call.options;
					generator.input_package = intern(call.options->input.string());
					// A value that can't leave compile time, like a function, is left out without a word
					generator.collecting = true;
					ran = run_items(generator, batch, nullptr, true) && !generator.failed;
				}
				scratch.erase();
				return ran;
			};
			std::function<void(size_t, size_t)> run_range = [&](size_t from, size_t to) {
				std::vector<CompileTimeItem> batch(items.begin() + static_cast<std::ptrdiff_t>(from), items.begin() + static_cast<std::ptrdiff_t>(to));
				if (run(batch)) {
					for (size_t j = from; j < to; ++j) {
						if (kept[positions[j]]) {
							result[positions[j]].second = call.data.copy_value(result[positions[j]].first, values[positions[j]]);
						}
					}
				}
				else if (to - from > 1) {
					run_range(from, from + (to - from) / 2);
					run_range(from + (to - from) / 2, to);
				}
			};
			run_range(0, items.size());
			remember();
			return result;
		}

		void write_constant(Call& call, uint8_t* record, const TypeInfoStruct* layout, Declaration* constant, const TypeInfo* type,
			const uint8_t* value) {

			call.data.write_text(record, layout, "name", text_of(constant->name));
			call.data.write_type(record, layout, "type", type);
			call.data.write_any(record, layout, "value", value, value != nullptr ? type : nullptr);
			write_location_field(call.data, record, layout, declaration_file(constant), constant->node);
		}

		// A function's FunctionInfo: its signature, and what its checked body calls and uses.
		void write_function(Call& call, uint8_t* record, const TypeInfoStruct* layout, Declaration* function) {
			CompileTimeData& data = call.data;
			auto type = static_cast<TypeInfoFunction const*>(function->value_type);
			const std::string file = declaration_file(function);
			data.write_text(record, layout, "package", text_of(function->package_path));
			data.write_text(record, layout, "name", text_of(function->name));
			write_location_field(data, record, layout, file, function->node);
			data.write_number(record, layout, "is_exported", has_name_directive(function, "#export"));
			data.write_number(record, layout, "has_body", function_body(function) != nullptr);
			if (type == nullptr) {
				return;
			}
			data.write_number(record, layout, "never_returns", type->never_returns);
			write_records(data, record, layout, "parameters", type->input.size(), [&](uint8_t* at, const TypeInfoStruct* parameter, size_t i) {
				const FunctionInput& input = type->input[i];
				data.write_text(at, parameter, "name", text_of(input.name));
				data.write_type(at, parameter, "type", input.type);
				data.write_number(at, parameter, "is_escaping", input.is_escaping);
				data.write_number(at, parameter, "is_varargs", input.is_varargs);
				//TODO(claude) default values, which need running each default
				size_t offset = 0;
				const TypeInfo* field_type = nullptr;
				if (CompileTimeData::find_field(parameter, "default_value", offset, field_type)) {
					auto optional = static_cast<const TypeInfoUnion*>(get_base_type(field_type));
					CompileTimeData::write_number_at(at + offset, optional->tag_type->size, 1);
				}
			});
			write_records(data, record, layout, "return_values", type->output.size(), [&](uint8_t* at, const TypeInfoStruct* output, size_t i) {
				data.write_type(at, output, "type", type->output[i].type);
				size_t offset = 0;
				const TypeInfo* field_type = nullptr;
				if (CompileTimeData::find_field(output, "name", offset, field_type)) {
					if (type->output[i].name != nullptr) {
						data.write_text_at(CompileTimeData::write_some_at(at + offset, field_type), text_of(type->output[i].name));
					}
					else {
						auto optional = static_cast<const TypeInfoUnion*>(get_base_type(field_type));
						CompileTimeData::write_number_at(at + offset, optional->tag_type->size, 1);
					}
				}
			});
			// What the body calls and uses, in source order
			std::vector<std::pair<const ast::Node*, const CheckedNode*>> nodes;
			if (function->checked != nullptr) {
				for (const auto& [node, found] : function->checked->nodes) {
					// Not a named result's local, whose key is its entry in the function's type
					if (function->checked->is_node(node)) {
						nodes.emplace_back(node, &found);
					}
				}
			}
			std::sort(nodes.begin(), nodes.end(), [](const auto& a, const auto& b) {
				return std::make_pair(a.first->value.line_number, a.first->value.column_number)
					< std::make_pair(b.first->value.line_number, b.first->value.column_number);
			});
			std::vector<std::pair<const ast::Node*, const CheckedNode*>> calls;
			std::vector<std::pair<const ast::Node*, const TypeInfo*>> used;
			std::set<const TypeInfo*> seen;
			for (const auto& [node, found] : nodes) {
				// A call is recorded at its name and at its (: one, at the name
				const bool repeated = ast::NodeType::PAREN_GROUP == node->node_type && !calls.empty()
					&& calls.back().second->called == found->called && calls.back().second->called_declaration == found->called_declaration
					&& calls.back().first->value.line_number == node->value.line_number;
				if (found->called != nullptr && !repeated) {
					calls.emplace_back(node, found);
				}
				if (ValueKind::VALUE == found->kind && found->type != nullptr && seen.insert(get_base_type_or_alias(found->type)).second) {
					used.emplace_back(node, found->type);
				}
			}
			write_records(data, record, layout, "calls", calls.size(), [&](uint8_t* at, const TypeInfoStruct* call_layout, size_t i) {
				Declaration* called = calls[i].second->called_declaration;
				if (called != nullptr) {
					data.write_text(at, call_layout, "package_path", text_of(called->package_path));
					data.write_text(at, call_layout, "name", text_of(called->name));
				}
				data.write_type(at, call_layout, "type", calls[i].second->called);
				write_location_field(data, at, call_layout, file, calls[i].first);
			});
			write_records(data, record, layout, "used_types", used.size(), [&](uint8_t* at, const TypeInfoStruct* use, size_t i) {
				data.write_type(at, use, "type", used[i].second);
				write_location_field(data, at, use, file, used[i].first);
			});
		}

		// Constants' types and values, worked out already: constant_values's, for many packages at once.
		using KnownConstants = std::unordered_map<Declaration*, std::pair<const TypeInfo*, const uint8_t*>>;

		// A package's top-level constants, the ones a PackageInfo describes.
		std::vector<Declaration*> constants_of(ProgramInfo* program, const std::string& path) {
			std::vector<Declaration*> constants;
			for (Declaration* declaration : declarations_of(program, path)) {
				if (DeclarationKind::FUNCTION != declaration->kind && !is_type(declaration) && is_constant(declaration)) {
					constants.push_back(declaration);
				}
			}
			return constants;
		}

		/*
		 * A package's PackageInfo, with its constants' values worked out, or taken from known when given, which
		 * saves a compile-time run for each package when describing many.
		 */
		void write_package(Call& call, uint8_t* record, const TypeInfoStruct* layout, hemera::PackageInfo* package,
			const KnownConstants* known = nullptr) {
			CompileTimeData& data = call.data;
			const std::string path = text_of(package->full_path);
			data.write_text(record, layout, "name", text_of(package->self_reported_name));
			data.write_text(record, layout, "path", path);
			// Each file, by its path, in order
			std::vector<std::pair<std::string, FileInfo*>> files;
			{
				std::scoped_lock<std::mutex> lock(package->files_mutex);
				for (const auto& [name, file] : package->files) {
					files.emplace_back(file_path_of(package->full_path, name), file);
				}
			}
			std::sort(files.begin(), files.end());
			auto file_names = reinterpret_cast<uint8_t*>(data.allocate(16 * std::max<size_t>(files.size(), 1), 8));
			for (size_t i = 0; i < files.size(); ++i) {
				data.write_text_at(file_names + i * 16, files[i].first);
			}
			data.write_view(record, layout, "files", files.empty() ? nullptr : file_names, files.size());
			// The package statement, which is at the top of the first file
			size_t offset = 0;
			const TypeInfo* field_type = nullptr;
			if (!files.empty() && CompileTimeData::find_field(layout, "location", offset, field_type)) {
				write_location(data, record + offset, field_type, files[0].first, 1, 1);
			}
			std::vector<std::pair<std::string, ImportInfo*>> imports;
			for (const auto& [file_path, file] : files) {
				std::scoped_lock<std::mutex> lock(file->imports_mutex);
				for (ImportInfo* import : file->imports) {
					imports.emplace_back(file_path, import);
				}
			}
			write_records(data, record, layout, "imports", imports.size(), [&](uint8_t* at, const TypeInfoStruct* import_layout, size_t i) {
				ImportInfo* import = imports[i].second;
				data.write_text(at, import_layout, "path", text_of(import->resolved_path));
				data.write_text(at, import_layout, "alias", text_of(import->alias != nullptr ? import->alias : import->name));
				// The text of its from literal, without the quotes
				data.write_text(at, import_layout, "from", import->location != nullptr ? literal_text(import->location) : std::string());
				write_location_field(data, at, import_layout, imports[i].first, import->node);
			});
			std::vector<Declaration*> functions;
			std::vector<Declaration*> constants;
			std::vector<Declaration*> types;
			for (Declaration* declaration : declarations_of(call.program, path)) {
				if (DeclarationKind::FUNCTION == declaration->kind) {
					functions.push_back(declaration);
				}
				else if (is_type(declaration)) {
					types.push_back(declaration);
				}
				else if (is_constant(declaration)) {
					constants.push_back(declaration);
				}
			}
			write_records(data, record, layout, "functions", functions.size(), [&](uint8_t* at, const TypeInfoStruct* function_layout, size_t i) {
				write_function(call, at, function_layout, functions[i]);
			});
			std::vector<std::pair<const TypeInfo*, const uint8_t*>> values;
			if (known != nullptr) {
				for (Declaration* constant : constants) {
					auto found = known->find(constant);
					values.push_back(found != known->end() ? found->second : std::make_pair(nullptr, nullptr));
				}
			}
			else {
				values = constant_values(call, constants);
			}
			write_records(data, record, layout, "constants", constants.size(), [&](uint8_t* at, const TypeInfoStruct* constant_layout, size_t i) {
				write_constant(call, at, constant_layout, constants[i], values[i].first, values[i].second);
			});
			write_records(data, record, layout, "types", types.size(), [&](uint8_t* at, const TypeInfoStruct* type_layout, size_t i) {
				data.write_text(at, type_layout, "name", text_of(types[i]->name));
				data.write_type(at, type_layout, "type", types[i]->type_value);
				write_location_field(data, at, type_layout, declaration_file(types[i]), types[i]->node);
			});
		}

		// The package the calling file imports as import_name, by its alias or name.
		hemera::PackageInfo* imported(Call& call, std::string_view import_name) {
			for (const auto& [path, package] : call.program->packages) {
				std::scoped_lock<std::mutex> lock(package->files_mutex);
				for (const auto& [name, file] : package->files) {
					if (file_path_of(package->full_path, name) != call.file) {
						continue;
					}
					std::scoped_lock<std::mutex> imports_lock(file->imports_mutex);
					for (ImportInfo* import : file->imports) {
						InternedString local = import->alias != nullptr ? import->alias : import->name;
						if (local != nullptr && std::string_view(*local) == import_name && import->resolved_path != nullptr) {
							return package_at(call.program, text_of(import->resolved_path));
						}
					}
				}
			}
			return nullptr;
		}

		// The package a PackageInfo record describes.
		std::string_view package_path_of(Call& call, const uint8_t* package_record) {
			const TypeInfoStruct* layout = call.data.compiler_struct("PackageInfo");
			size_t offset = 0;
			const TypeInfo* field_type = nullptr;
			if (package_record == nullptr || layout == nullptr || !CompileTimeData::find_field(layout, "path", offset, field_type)) {
				return std::string_view();
			}
			return read_string(package_record + offset);
		}

		Declaration* declared(Call& call, std::string_view path, std::string_view name) {
			std::scoped_lock<std::mutex> lock(call.program->names.mutex);
			auto iter = call.program->names.declarations.find(std::make_pair(intern(std::string(path)), intern(std::string(name))));
			return iter != call.program->names.declarations.end() ? iter->second : nullptr;
		}

		// A SourceCodeLocation argument's file, line and column.
		void read_location(Call& call, size_t index, std::string& file, uint32_t& line, uint16_t& column) {
			const TypeInfoStruct* layout = struct_of(call.type->input[index].type);
			const uint8_t* at = call.arguments[index];
			size_t offset = 0;
			const TypeInfo* field_type = nullptr;
			if (CompileTimeData::find_field(layout, "file_path", offset, field_type)) {
				file = std::string(read_string(at + offset));
			}
			if (CompileTimeData::find_field(layout, "line", offset, field_type)) {
				line = static_cast<uint32_t>(read_u64(at + offset) & 0xffffffff);
			}
			if (CompileTimeData::find_field(layout, "column", offset, field_type)) {
				column = static_cast<uint16_t>(read_u64(at + offset) & 0xffff);
			}
		}

		// Reading a record's fields, as its type lays them out.
		const uint8_t* field_at(const uint8_t* record, const TypeInfoStruct* layout, std::string_view field, const TypeInfo*& type) {
			size_t offset = 0;
			type = nullptr;
			return CompileTimeData::find_field(layout, field, offset, type) ? record + offset : nullptr;
		}

		std::string read_text(const uint8_t* record, const TypeInfoStruct* layout, std::string_view field) {
			const TypeInfo* type = nullptr;
			const uint8_t* at = field_at(record, layout, field, type);
			return at != nullptr ? std::string(read_string(at)) : std::string();
		}

		uint64_t read_number(const uint8_t* record, const TypeInfoStruct* layout, std::string_view field) {
			const TypeInfo* type = nullptr;
			const uint8_t* at = field_at(record, layout, field, type);
			if (at == nullptr) {
				return 0;
			}
			uint64_t value = 0;
			std::memcpy(&value, at, std::min<size_t>(type->size, sizeof(value)));
			return value;
		}

		// An enum field's member, by name.
		std::string read_member(const uint8_t* record, const TypeInfoStruct* layout, std::string_view field) {
			const TypeInfo* type = nullptr;
			const uint8_t* at = field_at(record, layout, field, type);
			if (at == nullptr) {
				return std::string();
			}
			auto enumeration = static_cast<const TypeInfoEnum*>(get_base_type(type));
			uint64_t value = 0;
			std::memcpy(&value, at, std::min<size_t>(type->size, sizeof(value)));
			for (size_t i = 0; i < enumeration->members.size(); ++i) {
				if (enumeration->values[i] == value) {
					return text_of(enumeration->members[i]);
				}
			}
			return std::string();
		}

		// A dynamic array or view field of records with two string fields, like TargetSetting's name and value.
		std::vector<std::pair<std::string, std::string>> read_pairs(const uint8_t* record, const TypeInfoStruct* layout,
			std::string_view field, std::string_view first, std::string_view second) {

			std::vector<std::pair<std::string, std::string>> result;
			const TypeInfo* type = nullptr;
			const uint8_t* at = field_at(record, layout, field, type);
			if (at == nullptr) {
				return result;
			}
			const TypeInfoStruct* element = struct_of(static_cast<const TypeInfoArray*>(get_base_type(type))->element_type);
			const uint8_t* elements = reinterpret_cast<const uint8_t*>(read_u64(at + 8));
			for (uint64_t i = 0; i < read_u64(at) && elements != nullptr; ++i) {
				const uint8_t* each = elements + i * element->size;
				result.emplace_back(read_text(each, element, first), read_text(each, element, second));
			}
			return result;
		}

		// A compiler.BuildOptions value.
		void read_build_options(const uint8_t* record, const TypeInfoStruct* layout, BuildTarget& target) {
			target.name = read_text(record, layout, "name");
			target.root = read_text(record, layout, "root");
			target.output_path = read_text(record, layout, "output_path");
			target.entry = read_text(record, layout, "entry");
			target.settings = read_pairs(record, layout, "settings", "name", "value");
			target.package_paths = read_pairs(record, layout, "package_paths", "location", "path");
			const TypeInfo* type = nullptr;
			if (const uint8_t* backend = field_at(record, layout, "backend_options", type)) {
				target.optimization_level = read_member(backend, struct_of(type), "optimization_level");
				target.debug_info = read_number(backend, struct_of(type), "debug_info") != 0;
			}
			if (const uint8_t* options = field_at(record, layout, "target_options", type)) {
				const TypeInfoStruct* target_layout = struct_of(type);
				target.architecture = read_member(options, target_layout, "architecture");
				target.os = read_member(options, target_layout, "os");
				target.output_type = read_member(options, target_layout, "output_type");
				target.cpu = read_text(options, target_layout, "cpu");
				target.cpu_features = read_text(options, target_layout, "cpu_features");
				target.code_model = read_member(options, target_layout, "code_model");
				target.relocation_model = read_member(options, target_layout, "relocation_model");
				target.red_zone = read_number(options, target_layout, "red_zone") != 0;
				target.address_zero_is_memory = read_number(options, target_layout, "address_zero_is_memory") != 0;
				target.linker_script = read_text(options, target_layout, "linker_script");
				target.startup_code = read_number(options, target_layout, "startup_code") != 0;
				target.stack_check_failure = read_member(options, target_layout, "stack_check_failure");
			}
		}

		/*
		 * A package load_package checked on its own, as the root of a program of its own, by its folder. The
		 * program stays for the rest of the compilation, since its types are in what was written about it.
		 */
		struct LoadedProgram {
			ProgramInfo* program = nullptr;
			Options* options = nullptr;
		};

		std::mutex loaded_mutex;

		std::map<std::string, LoadedProgram>& loaded_programs() {
			// Never freed, like the programs
			static auto* loaded = new std::map<std::string, LoadedProgram>();
			return *loaded;
		}

		// A folder compile-time code gave: relative to the calling file's package, or absolute.
		std::filesystem::path folder_from(Call& call, std::string_view folder) {
			std::filesystem::path given(folder);
			return given.is_absolute() ? given : std::filesystem::path(call.file).parent_path() / given;
		}

		// The package in folder checked as a program of its own, the first time it's asked for.
		LoadedProgram load(Call& call, const std::string& folder) {
			std::scoped_lock<std::mutex> lock(loaded_mutex);
			auto iter = loaded_programs().find(folder);
			if (iter != loaded_programs().end()) {
				return iter->second;
			}
			LoadedProgram loaded;
			loaded.options = new Options();
			Options& options = *loaded.options;
			options.input = folder;
			options.output_name = "loaded";
			options.entry = "";
			options.startup_code = false;
			options.install_path = call.options->install_path;
			options.builtin_paths = call.options->builtin_paths;
			options.settings = call.options->settings;
			options.architecture = call.options->architecture;
			options.os = call.options->os;
			options.object_format = call.options->object_format;
			options.environment = call.options->environment;
			options.vendor = call.options->vendor;
			auto* context = new mlir::MLIRContext();
			context->loadDialect<mlir::BuiltinDialect>();
			context->loadDialect<mlir::func::FuncDialect>();
			context->loadDialect<::hmir::HemeraDialect>();
			auto* builder = new mlir::OpBuilder(context);
			auto* module = new mlir::ModuleOp(mlir::ModuleOp::create(builder->getUnknownLoc(), "loaded"));
			loaded.program = new ProgramInfo(context, builder, module);
			kick_off_processing(loaded.program, loaded.options);
			loaded_programs()[folder] = loaded;
			return loaded;
		}

		// The program a PackageInfo record at path is from, when it isn't the calling program: one load_package checked.
		bool program_of(const std::string& path, ProgramInfo*& program, const Options*& options) {
			std::scoped_lock<std::mutex> lock(loaded_mutex);
			auto iter = loaded_programs().find(path);
			if (iter == loaded_programs().end()) {
				return false;
			}
			program = iter->second.program;
			options = iter->second.options;
			return true;
		}

		// Whether the calling code is the build package's, the input package, which the permissions are for.
		bool in_root_package(Call& call) {
			return call.file.starts_with(call.options->input.string());
		}

		const char* operating_system_name(OSType os) {
			return OSType::Win32 == os ? "Windows" : OSType::Linux == os ? "Linux" : OSType::Darwin == os || OSType::MacOSX == os ? "Mac"
				: OSType::UEFI == os ? "UEFI" : OSType::SlopOS == os ? "SlopOS" : "None";
		}

		// The options given on the command line, as BuildOptions.
		void write_build_options(Call& call, uint8_t* record, const TypeInfoStruct* layout, bool current) {
			CompileTimeData& data = call.data;
			const Options& options = *call.options;
			if (current) {
				data.write_text(record, layout, "name", std::filesystem::path(options.output_name).filename().string());
				data.write_text(record, layout, "root", options.input.string());
				data.write_text(record, layout, "entry", options.entry);
			}
			data.write_text(record, layout, "output_path", current ? options.output_name : "");
			// Settings, as a dynamic array that uses the calling code's allocator, so it can be added to
			size_t offset = 0;
			const TypeInfo* field_type = nullptr;
			if (CompileTimeData::find_field(layout, "settings", offset, field_type) && !options.settings.empty()) {
				const TypeInfoStruct* setting = struct_of(static_cast<const TypeInfoArray*>(get_base_type(field_type))->element_type);
				uint8_t* elements = data.allocate(setting->size * options.settings.size(), setting->alignment);
				for (size_t i = 0; i < options.settings.size(); ++i) {
					data.write_text(elements + i * setting->size, setting, "name", options.settings[i].first);
					data.write_text(elements + i * setting->size, setting, "value", options.settings[i].second);
				}
				//TODO(claude) the context's allocator, so build code can grow it; until then it can't be added to
				uint8_t* settings = record + offset;
				CompileTimeData::write_number_at(settings, 8, options.settings.size());
				CompileTimeData::write_number_at(settings + 8, 8, reinterpret_cast<uintptr_t>(elements));
				CompileTimeData::write_number_at(settings + 16, 8, options.settings.size());
			}
			if (CompileTimeData::find_field(layout, "backend_options", offset, field_type)) {
				const TypeInfoStruct* backend = struct_of(field_type);
				uint8_t* at = record + offset;
				data.write_member(at, backend, "backend_type", "LLVM");
				const char* level = OptimizationLevel::O0 == options.optimization_level ? "O0" : OptimizationLevel::O1 == options.optimization_level ? "O1"
					: OptimizationLevel::O3 == options.optimization_level ? "O3" : "O2";
				data.write_member(at, backend, "optimization_level", level);
				data.write_number(at, backend, "debug_info", options.debug_info);
			}
			data.write_member(record, layout, "configuration", options.debug_info ? "Debug" : "Release");
			if (CompileTimeData::find_field(layout, "target_options", offset, field_type)) {
				const TypeInfoStruct* target = struct_of(field_type);
				uint8_t* at = record + offset;
				data.write_member(at, target, "architecture", ArchType::aarch64 == options.architecture ? "arm64" : ArchType::x86 == options.architecture ? "x86"
					: ArchType::arm == options.architecture ? "arm" : "x86_64");
				data.write_member(at, target, "os", options.startup_code || OSType::UnknownOS != options.os ? operating_system_name(options.os) : "None");
				data.write_member(at, target, "output_type", "Executable");
				data.write_text(at, target, "cpu", options.cpu);
				data.write_text(at, target, "cpu_features", options.cpu_features);
				data.write_member(at, target, "code_model", TargetCodeModel::Kernel == options.code_model ? "Kernel" : TargetCodeModel::Small == options.code_model ? "Small"
					: TargetCodeModel::Medium == options.code_model ? "Medium" : "Default");
				data.write_member(at, target, "relocation_model", TargetRelocationModel::Static == options.relocation_model ? "Static" : "Default");
				data.write_number(at, target, "red_zone", options.red_zone);
				data.write_number(at, target, "address_zero_is_memory", options.address_zero_is_memory);
				data.write_text(at, target, "linker_script", options.linker_script.empty() ? std::string() : options.linker_script.string());
				data.write_number(at, target, "startup_code", options.startup_code);
				data.write_member(at, target, "stack_check_failure", TargetStackCheck::Trap == options.stack_check ? "Trap" : "Morestack");
			}
		}

		// The type a type value is, from its descriptor's address.
		const TypeInfo* described(Call& call, const uint8_t* argument) {
			const auto& types = call.data.described_types();
			auto iter = types.find(static_cast<uintptr_t>(read_u64(argument)));
			return iter != types.end() ? iter->second : nullptr;
		}

		// What kind of type something is, for saying why a requirement isn't met.
		std::string kind_of(const TypeInfo* type) {
			const TypeInfo* base_type = get_base_type(type);
			if (base_type == nullptr) {
				return "nothing";
			}
			switch (base_type->variant) {
			case TypeInfoVariant::INTEGER: return static_cast<const TypeInfoInteger*>(base_type)->is_signed ? "a signed integer" : "an unsigned integer";
			case TypeInfoVariant::FLOAT: return "a float";
			case TypeInfoVariant::BOOLEAN: return "a boolean";
			case TypeInfoVariant::CHAR: return "a character";
			case TypeInfoVariant::ENUM: return "an enum";
			case TypeInfoVariant::POINTER: return "a pointer";
			case TypeInfoVariant::STRING: return "a string";
			case TypeInfoVariant::STRUCT: return "a struct";
			case TypeInfoVariant::UNION: return "a union";
			case TypeInfoVariant::ARRAY: return "an array";
			case TypeInfoVariant::FUNCTION: return "a function";
			case TypeInfoVariant::ANY: return "an any";
			case TypeInfoVariant::TYPE: return "a type";
			case TypeInfoVariant::COMPLEX: return "a complex number";
			case TypeInfoVariant::QUATERNION: return "a quaternion";
			case TypeInfoVariant::VECTOR: return "a vector";
			case TypeInfoVariant::VOID: return "void";
			case TypeInfoVariant::ALIAS: return "an alias";
			case TypeInfoVariant::ARCHETYPE: return "a generic's type parameter";
			}
			return "a type";
		}

		/*
		 * compiler.require_equality(T) and the rest, called by a #constraint function while it's checked:
		 * each adds why it isn't met to what the constraint found, and checking goes on. note adds detail
		 * to the last one.
		 */
		void carry_out_requirement(Call& call) {
			const std::string_view name = call.name;
			std::vector<std::string>* unsatisfied = service_scope != nullptr ? service_scope->unsatisfied : nullptr;
			if (unsatisfied == nullptr) {
				report_error(ErrorCode::E4029, call.file, 0, 0, std::format("compiler.{} is only for #constraint functions", name));
				return;
			}
			if (name == "note") {
				const std::string detail = format_compile_time(read_string(call.arguments[0]),
					reinterpret_cast<const void*>(read_u64(call.arguments[1] + 8)), read_u64(call.arguments[1]));
				if (!unsatisfied->empty()) {
					unsatisfied->back() += "; " + detail;
				}
				return;
			}
			// require_any: each alternative's failures, then all of them gone if one was met, or one reason
			if (name == "require_any_begin") {
				service_scope->alternatives.push_back({ unsatisfied->size() });
				return;
			}
			if (name == "require_any_next") {
				if (!service_scope->alternatives.empty()) {
					service_scope->alternatives.back().push_back(unsatisfied->size());
				}
				return;
			}
			if (name == "require_any_end") {
				if (service_scope->alternatives.empty()) {
					return;
				}
				const std::vector<size_t> ends = service_scope->alternatives.back();
				service_scope->alternatives.pop_back();
				bool met = false;
				std::string reasons;
				for (size_t i = 0; i + 1 < ends.size(); ++i) {
					if (ends[i] == ends[i + 1]) {
						met = true;
					}
					for (size_t j = ends[i]; j < ends[i + 1] && j < unsatisfied->size(); ++j) {
						reasons += (reasons.empty() ? "" : j == ends[i] ? ", or " : "; ") + (*unsatisfied)[j];
					}
				}
				unsatisfied->resize(std::min(ends.front(), unsatisfied->size()));
				if (!met) {
					unsatisfied->push_back(std::format("none of these holds: {}", reasons));
				}
				return;
			}
			if (name == "require") {
				if (*call.arguments[0] == 0) {
					unsatisfied->push_back(format_compile_time(read_string(call.arguments[1]),
						reinterpret_cast<const void*>(read_u64(call.arguments[2] + 8)), read_u64(call.arguments[2])));
				}
				return;
			}
			const TypeInfo* type = described(call, call.arguments[0]);
			const TypeInfo* base_type = get_base_type(type);
			const std::string type_name = type != nullptr ? to_string(type) : "the type";
			const TypeInfoVariant variant = base_type != nullptr ? base_type->variant : TypeInfoVariant::VOID;
			const bool integer = TypeInfoVariant::INTEGER == variant;
			const bool is_signed = integer && static_cast<const TypeInfoInteger*>(base_type)->is_signed;
			const bool floating = TypeInfoVariant::FLOAT == variant;
			auto require = [&](bool holds, std::string why) {
				if (!holds) {
					unsatisfied->push_back(std::move(why));
				}
			};
			const std::string kind = kind_of(type);
			if (name == "require_equality") {
				require(integer || floating || TypeInfoVariant::BOOLEAN == variant || TypeInfoVariant::CHAR == variant
					|| TypeInfoVariant::ENUM == variant || TypeInfoVariant::POINTER == variant || TypeInfoVariant::STRING == variant
					|| TypeInfoVariant::FUNCTION == variant || TypeInfoVariant::TYPE == variant,
					std::format("{} is {}, which has no ==", type_name, kind));
			}
			else if (name == "require_ordering") {
				require(integer || floating || TypeInfoVariant::CHAR == variant, std::format("{} is {}, which has no <", type_name, kind));
			}
			else if (name == "require_integer") {
				require(integer, std::format("{} is {}, not an integer", type_name, kind));
			}
			else if (name == "require_signed") {
				require(is_signed, std::format("{} is {}, not a signed integer", type_name, kind));
			}
			else if (name == "require_unsigned") {
				require(integer && !is_signed, std::format("{} is {}, not an unsigned integer", type_name, kind));
			}
			else if (name == "require_float") {
				require(floating, std::format("{} is {}, not a float", type_name, kind));
			}
			else if (name == "require_numeric") {
				require(integer || floating, std::format("{} is {}, not a number", type_name, kind));
			}
			else if (name == "require_field") {
				const std::string_view field = read_string(call.arguments[1]);
				const TypeInfo* wanted = described(call, call.arguments[2]);
				bool found = false;
				bool matches = false;
				std::string actual;
				if (TypeInfoVariant::STRUCT == variant) {
					for (const StructMember& member : static_cast<const TypeInfoStruct*>(base_type)->members) {
						if (member.name != nullptr && std::string_view(*member.name) == field) {
							found = true;
							matches = get_base_type_or_alias(member.member_type) == get_base_type_or_alias(wanted);
							actual = to_string(member.member_type);
						}
					}
				}
				else if (TypeInfoVariant::ARRAY == variant && field == "count") {
					found = true;
					matches = get_base_type_or_alias(wanted) == get_base_type_or_alias(BUILTIN_usize);
					actual = "usize";
				}
				if (!found) {
					unsatisfied->push_back(std::format("{} is {} without a field {}", type_name, kind, field));
				}
				else if (!matches) {
					unsatisfied->push_back(std::format("{}'s {} is {}, not {}", type_name, field, actual,
						wanted != nullptr ? to_string(wanted) : "that"));
				}
			}
			else if (name == "require_copyable") {
				require(!is_owned(type), std::format("{} is #owned, so it's moved and released, not copied", type_name));
			}
			else if (name == "require_mutable") {
				const bool given_mut = type != nullptr && TypeInfoVariant::ALIAS == type->variant
					&& static_cast<const TypeInfoAlias*>(type)->mutable_argument;
				require(given_mut, std::format("{} is given without mut, so what points to it can't change it", type_name));
			}
			else if (name == "require_view") {
				// An array, view or dynamic array of element: what for loops, indexing and count need
				const TypeInfo* wanted = described(call, call.arguments[1]);
				if (TypeInfoVariant::ARRAY != variant) {
					unsatisfied->push_back(std::format("{} is {}, not an array or view", type_name, kind));
				}
				else if (get_base_type_or_alias(static_cast<const TypeInfoArray*>(base_type)->element_type) != get_base_type_or_alias(wanted)) {
					unsatisfied->push_back(std::format("{} holds {}, not {}", type_name,
						to_string(static_cast<const TypeInfoArray*>(base_type)->element_type), wanted != nullptr ? to_string(wanted) : "that"));
				}
			}
			else {
				report_error(ErrorCode::E4024, call.file, 0, 0, std::format("compiler.{} isn't supported yet", name));
			}
		}

		// The tree a Code this run made holds, or null.
		const ast::Node* code_tree(uint64_t handle) {
			const auto& codes = service_scope->codes;
			return handle == 0 || handle > codes.size() ? nullptr : codes[handle - 1];
		}

		// base/compiler's Code, in the program compile-time code runs in.
		const TypeInfo* code_type(Call& call) {
			std::scoped_lock<std::mutex> lock(call.program->names.mutex);
			auto iter = call.program->names.declarations.find(std::make_pair(intern(std::format("{}compiler", BASE_PACKAGE_PREFIX)),
				intern(std::string("Code"))));
			return iter != call.program->names.declarations.end() ? iter->second->type_value : nullptr;
		}

		/*
		 * What an any holds, for #insert to splice (docs/compilation.md, Code Values): a Code, a type, or a
		 * number, boolean, character, string or enum member. False, having reported why, for anything else.
		 */
		bool read_spliced(Call& call, const uint8_t* any, Spliced& spliced) {
			const uint8_t* data = reinterpret_cast<const uint8_t*>(read_u64(any));
			const TypeInfo* type = described(call, any + 8);
			const TypeInfo* base_type = type != nullptr ? get_base_type(type) : nullptr;
			if (base_type == nullptr || data == nullptr) {
				report_error(ErrorCode::E4029, call.file, 0, 0, "#insert was given something without a type");
				service_scope->code_reported = true;
				return false;
			}
			const TypeInfo* code = code_type(call);
			if (code != nullptr && base_type == get_base_type(code)) {
				spliced.kind = Spliced::Kind::CODE;
				spliced.tree = code_tree(read_u64(data));
				return spliced.tree != nullptr;
			}
			const size_t size = base_type->size;
			uint64_t bits = 0;
			std::memcpy(&bits, data, std::min<size_t>(size, 8));
			if (TypeInfoVariant::TYPE == base_type->variant) {
				spliced.kind = Spliced::Kind::TYPE;
				spliced.type = described(call, data);
				return spliced.type != nullptr;
			}
			if (TypeInfoVariant::INTEGER == base_type->variant) {
				spliced.kind = Spliced::Kind::INTEGER;
				const bool is_signed = static_cast<const TypeInfoInteger*>(base_type)->is_signed;
				const unsigned shift = static_cast<unsigned>(64 - 8 * std::min<size_t>(size, 8));
				const int64_t signed_value = static_cast<int64_t>(bits << shift) >> shift;
				spliced.negative = is_signed && signed_value < 0;
				spliced.magnitude = spliced.negative ? 0 - static_cast<uint64_t>(signed_value) : bits;
				return true;
			}
			if (TypeInfoVariant::FLOAT == base_type->variant) {
				spliced.kind = Spliced::Kind::FLOAT;
				if (size == 4) {
					float value = 0;
					std::memcpy(&value, data, 4);
					spliced.floating = static_cast<double>(value);
				}
				else {
					std::memcpy(&spliced.floating, data, 8);
				}
				if (!std::isfinite(spliced.floating)) {
					report_error(ErrorCode::E4029, call.file, 0, 0, std::format("#insert can't make a literal of {}", spliced.floating));
					service_scope->code_reported = true;
					return false;
				}
				return true;
			}
			if (TypeInfoVariant::BOOLEAN == base_type->variant) {
				spliced.kind = Spliced::Kind::BOOLEAN;
				spliced.magnitude = bits & 0xff;
				return true;
			}
			if (TypeInfoVariant::CHAR == base_type->variant) {
				spliced.kind = Spliced::Kind::CHARACTER;
				spliced.magnitude = bits;
				return true;
			}
			if (TypeInfoVariant::STRING == base_type->variant) {
				spliced.kind = Spliced::Kind::STRING;
				spliced.text = std::string(read_string(data));
				return true;
			}
			if (TypeInfoVariant::ENUM == base_type->variant) {
				auto enumeration = static_cast<const TypeInfoEnum*>(base_type);
				for (size_t i = 0; i < enumeration->values.size() && i < enumeration->members.size(); ++i) {
					if (enumeration->values[i] == bits) {
						spliced.kind = Spliced::Kind::ENUM_MEMBER;
						spliced.type = type;
						spliced.text = std::string(*enumeration->members[i]);
						return true;
					}
				}
				report_error(ErrorCode::E4029, call.file, 0, 0, std::format("#insert was given {} {}, which isn't one of its members",
					to_string(type), bits));
				service_scope->code_reported = true;
				return false;
			}
			report_error(ErrorCode::E4029, call.file, 0, 0, std::format("#insert can't put {} into code", to_string(type)));
			service_scope->code_reported = true;
			return false;
		}

		// A new Code this run made, holding tree: its handle, 0 for none.
		uint64_t keep_code(const ast::Node* tree) {
			if (tree == nullptr) {
				return 0;
			}
			service_scope->codes.push_back(tree);
			return service_scope->codes.size();
		}

		// Whether text is a name: letters, digits and _, not starting with a digit, and not a keyword or _ alone.
		bool is_identifier(std::string_view text) {
			static constexpr std::string_view KEYWORDS[] = {
				"auto_cast", "bit_cast", "break", "case", "cast", "continue", "defer", "distinct", "else", "enum", "false",
				"fn", "for", "if", "is_none", "is_some", "loop", "match", "mut", "null", "or_break", "or_continue",
				"or_else", "or_return", "push_context", "return", "struct", "switch", "true", "union", "using", "void",
				"while", "with",
			};
			if (text.empty() || text == "_" || std::isdigit(static_cast<unsigned char>(text[0])) != 0) {
				return false;
			}
			for (const char c : text) {
				if (std::isalnum(static_cast<unsigned char>(c)) == 0 && c != '_') {
					return false;
				}
			}
			return std::find(std::begin(KEYWORDS), std::end(KEYWORDS), text) == std::end(KEYWORDS);
		}

		// What a piece of code is, base/compiler's CodeKind, by its tree's root.
		uint64_t code_kind_of(const ast::Node* tree) {
			const std::string_view word = tree->value.value != nullptr ? std::string_view(*tree->value.value) : std::string_view();
			if (ast::NodeType::BLOCK == tree->node_type) {
				return 1;
			}
			if (ast::NodeType::IDENTIFIER == tree->node_type && tree->children.empty() && tree->type == nullptr) {
				return 2;
			}
			if (ast::NodeType::TYPE == tree->node_type) {
				return 3;
			}
			if (ast::NodeType::LITERAL == tree->node_type || (ast::NodeType::UNARY_OPERATOR == tree->node_type
				&& tree->children.size() == 1 && ast::NodeType::LITERAL == tree->children[0]->node_type)) {
				return 4;
			}
			if (is_code_list(tree)) {
				return 5;
			}
			if (ast::NodeType::STRUCT == tree->node_type && word == "fields") {
				return 6;
			}
			if (ast::NodeType::UNION == tree->node_type && word == "variants") {
				return 7;
			}
			if (ast::NodeType::ENUM == tree->node_type && word == "members") {
				return 8;
			}
			if (ast::NodeType::LIST == tree->node_type && word == "patterns") {
				return 9;
			}
			if (ast::NodeType::LIST == tree->node_type && word == "cases") {
				return 10;
			}
			return 0;
		}

		/*
		 * base/compiler's functions that make and look at code (docs/compilation.md, Code Values): whether name
		 * is one of them, having carried it out.
		 */
		bool carry_out_code(Call& call) {
			CompileTimeData& data = call.data;
			const std::string_view name = call.name;
			ProgramInfo* program = call.program;
			const bool makes = name == "name" || name == "literal" || name == "type_code" || name == "list" || name == "parameters"
				|| name == "arguments";
			std::string file;
			uint32_t line = 0;
			uint16_t column = 0;
			if (makes) {
				read_location(call, 1, file, line, column);
			}
			if (name == "name") {
				// Its parts, joined
				const uint8_t* parts = call.arguments[0];
				const uint8_t* strings = reinterpret_cast<const uint8_t*>(read_u64(parts + 8));
				std::string text;
				for (uint64_t i = 0; i < read_u64(parts); ++i) {
					text += read_string(strings + i * 16);
				}
				uint64_t handle = 0;
				if (!is_identifier(text)) {
					report_error(ErrorCode::E4029, file, line, column, std::format("compiler.name needs a name, not \"{}\"", text));
					service_scope->code_reported = true;
				}
				else {
					handle = keep_code(make_name(program->made_nodes, text, file, line));
				}
				CompileTimeData::write_number_at(call.result, 8, handle);
				return true;
			}
			if (name == "literal") {
				Spliced value;
				uint64_t handle = 0;
				if (read_spliced(call, call.arguments[0], value)) {
					if (Spliced::Kind::CODE == value.kind || Spliced::Kind::TYPE == value.kind) {
						report_error(ErrorCode::E4029, file, line, column,
							"compiler.literal takes a number, boolean, character, string or enum member");
						service_scope->code_reported = true;
					}
					else {
						handle = keep_code(make_value(program->made_nodes, program->quotes, value, file, line));
					}
				}
				CompileTimeData::write_number_at(call.result, 8, handle);
				return true;
			}
			if (name == "type_code") {
				Spliced value;
				value.kind = Spliced::Kind::TYPE;
				value.type = described(call, call.arguments[0]);
				const uint64_t handle = value.type != nullptr ? keep_code(make_value(program->made_nodes, program->quotes, value, file, line)) : 0;
				CompileTimeData::write_number_at(call.result, 8, handle);
				return true;
			}
			if (name == "list") {
				const uint8_t* items = call.arguments[0];
				const uint64_t count = read_u64(items);
				const uint8_t* handles = reinterpret_cast<const uint8_t*>(read_u64(items + 8));
				std::vector<const ast::Node*> trees;
				for (uint64_t i = 0; i < count; ++i) {
					const ast::Node* tree = code_tree(read_u64(handles + i * 8));
					if (tree != nullptr) {
						trees.push_back(tree);
					}
				}
				CompileTimeData::write_number_at(call.result, 8, keep_code(make_list(program->made_nodes, trees, file, line)));
				return true;
			}
			// A type value is the address of its description, at compile time as in the program
			if (name == "described_type") {
				CompileTimeData::write_number_at(call.result, 8, read_u64(call.arguments[0]));
				return true;
			}
			if (name == "parameters" || name == "arguments") {
				const TypeInfo* type = described(call, call.arguments[0]);
				const TypeInfo* function = type != nullptr ? get_base_type(type) : nullptr;
				uint64_t handle = 0;
				if (function == nullptr || TypeInfoVariant::FUNCTION != function->variant) {
					report_error(ErrorCode::E4029, file, line, column, std::format("compiler.{} takes a function type, not {}", name,
						type != nullptr ? to_string(type) : "nothing"));
					service_scope->code_reported = true;
				}
				else {
					handle = keep_code(make_parameters(program->made_nodes, static_cast<TypeInfoFunction const*>(function),
						name == "arguments", file, line));
				}
				CompileTimeData::write_number_at(call.result, 8, handle);
				return true;
			}
			if (name == "code_kind" || name == "identifier_of" || name == "items_of" || name == "location_of") {
				const ast::Node* tree = code_tree(read_u64(call.arguments[0]));
				if (name == "code_kind") {
					CompileTimeData::write_number_at(call.result, call.type->output[0].type->size, tree != nullptr ? code_kind_of(tree) : 0);
				}
				else if (name == "identifier_of") {
					const bool named = tree != nullptr && code_kind_of(tree) == 2 && tree->value.value != nullptr;
					write_optional(call, named, [&](uint8_t* at, const TypeInfoStruct*) {
						data.write_text_at(at, std::string_view(*tree->value.value));
					});
				}
				else if (name == "items_of") {
					const uint64_t kind = tree != nullptr ? code_kind_of(tree) : 0;
					const bool has_items = kind == 1 || kind >= 5;
					const size_t count = has_items ? tree->children.size() : 0;
					auto handles = reinterpret_cast<uint64_t*>(data.allocate(8 * std::max<size_t>(count, 1), 8));
					for (size_t i = 0; i < count; ++i) {
						handles[i] = keep_code(tree->children[i]);
					}
					CompileTimeData::write_view_at(call.result, count > 0 ? handles : nullptr, count);
				}
				else {
					const std::shared_ptr<const ast::Origin> origin = tree != nullptr ? program->made_nodes.origin(tree) : nullptr;
					write_location(data, call.result, call.type->output[0].type, origin != nullptr ? origin->file : std::string_view(),
						tree != nullptr ? tree->value.line_number : 0, tree != nullptr ? tree->value.column_number : 0);
				}
				return true;
			}
			return false;
		}

		void carry_out(Call& call) {
			CompileTimeData& data = call.data;
			const std::string_view name = call.name;
			// #code's copy of its quote, with what its #inserts splice (docs/compilation.md, Code Values)
			if (name == "quote_code") {
				const auto quote = reinterpret_cast<const ast::Node*>(read_u64(call.arguments[0]));
				const uint8_t* splices = call.arguments[1];
				const uint64_t count = read_u64(splices);
				const uint8_t* items = reinterpret_cast<const uint8_t*>(read_u64(splices + 8));
				std::vector<Spliced> spliced(count);
				for (uint64_t i = 0; i < count; ++i) {
					if (!read_spliced(call, items + i * 16, spliced[i])) {
						return;
					}
				}
				const ast::Node* made = make_code(call.program->made_nodes, call.program->quotes, quote, spliced);
				uint64_t handle = 0;
				if (made != nullptr) {
					service_scope->codes.push_back(made);
					handle = service_scope->codes.size();
				}
				CompileTimeData::write_number_at(call.result, 8, handle);
				return;
			}
			if (name == "code_text") {
				data.write_text_at(call.result, code_source(code_tree(read_u64(call.arguments[0])), call.program->quotes));
				return;
			}
			if (carry_out_code(call)) {
				return;
			}
			if (name == "report_error" || name == "report_warning") {
				std::string file;
				uint32_t line = 0;
				uint16_t column = 0;
				read_location(call, 0, file, line, column);
				const std::string message = format_compile_time(read_string(call.arguments[1]),
					reinterpret_cast<const void*>(read_u64(call.arguments[2] + 8)), read_u64(call.arguments[2]));
				if (name == "report_error") {
					report_error(ErrorCode::E4029, file, line, column, message);
				}
				else {
					report_warning(WarningCode::W4001, file, line, column, message);
				}
				return;
			}
			if (name == "build_permissions") {
				const TypeInfoStruct* layout = struct_of(call.type->output[0].type);
				const bool granted = call.options->allow_run && in_root_package(call);
				data.write_number(call.result, layout, "run_processes", granted);
				data.write_number(call.result, layout, "write_outside_output", granted);
				return;
			}
			// A constraint's requirements (docs/types.md, Constraints): what isn't satisfied, and why
			if (name.starts_with("require") || name == "note") {
				carry_out_requirement(call);
				return;
			}
			if (name == "target_setting") {
				const std::string_view setting = read_string(call.arguments[0]);
				std::string_view value = read_string(call.arguments[1]);
				for (const auto& [setting_name, setting_value] : call.options->settings) {
					if (setting_name == setting) {
						value = setting_value;
					}
				}
				data.write_text_at(call.result, value);
				return;
			}
			if (name == "command_line_options" || name == "current_build_options") {
				write_build_options(call, call.result, struct_of(call.type->output[0].type), name == "current_build_options");
				return;
			}
			if (name == "package_info") {
				hemera::PackageInfo* package = imported(call, read_string(call.arguments[0]));
				write_optional(call, package != nullptr, [&](uint8_t* at, const TypeInfoStruct* layout) {
					write_package(call, at, layout, package);
				});
				return;
			}
			if (name == "subfolders") {
				std::error_code error;
				const std::filesystem::path folder = std::filesystem::canonical(folder_from(call, read_string(call.arguments[0])), error);
				std::vector<std::string> found;
				if (!error) {
					for (const std::filesystem::directory_entry& entry : std::filesystem::directory_iterator(folder, error)) {
						if (entry.is_directory()) {
							found.push_back(std::filesystem::canonical(entry.path(), error).string());
						}
					}
				}
				std::sort(found.begin(), found.end());
				uint8_t* names = data.allocate(16 * std::max<size_t>(found.size(), 1), 8);
				for (size_t i = 0; i < found.size(); ++i) {
					data.write_text_at(names + i * 16, found[i]);
				}
				CompileTimeData::write_view_at(call.result, found.empty() ? nullptr : names, found.size());
				return;
			}
			if (name == "load_package") {
				std::error_code error;
				const std::filesystem::path folder = std::filesystem::canonical(folder_from(call, read_string(call.arguments[0])), error);
				hemera::PackageInfo* package = nullptr;
				Call described = call;
				if (!error && std::filesystem::is_directory(folder)) {
					package = package_at(call.program, folder.string());
					if (package == nullptr) {
						const LoadedProgram loaded = load(call, folder.string());
						described.program = loaded.program;
						described.options = loaded.options;
						package = package_at(loaded.program, folder.string());
					}
				}
				write_optional(call, package != nullptr && package->files.size() > 0, [&](uint8_t* at, const TypeInfoStruct* layout) {
					write_package(described, at, layout, package);
				});
				return;
			}
			if (name == "find_constant" || name == "find_function") {
				const uint8_t* package = reinterpret_cast<const uint8_t*>(read_u64(call.arguments[0]));
				// In the program the record describes: one load_package checked, or during a check the target's
				const std::string path(package_path_of(call, package));
				const Options* loaded_options = nullptr;
				if (!program_of(path, call.program, loaded_options) && service_scope->reflected != nullptr) {
					call.program = service_scope->reflected;
					call.options = service_scope->reflected_options;
				}
				else if (loaded_options != nullptr) {
					call.options = loaded_options;
				}
				Declaration* found = declared(call, package_path_of(call, package), read_string(call.arguments[1]));
				const bool wanted = found != nullptr && (name == "find_constant" ? is_constant(found) : DeclarationKind::FUNCTION == found->kind);
				write_optional(call, wanted, [&](uint8_t* at, const TypeInfoStruct* layout) {
					if (name == "find_function") {
						write_function(call, at, layout, found);
						return;
					}
					const auto values = constant_values(call, { found });
					write_constant(call, at, layout, found, values[0].first, values[0].second);
				});
				return;
			}
			if (name == "add_target") {
				BuildTarget target;
				read_build_options(call.arguments[0], struct_of(call.type->input[0].type), target);
				read_location(call, 1, target.location.file, target.location.line, target.location.column);
				BuildRegistry& registry = build_registry();
				std::scoped_lock<std::mutex> lock(registry.mutex);
				target.node = registry.next_node++;
				CompileTimeData::write_number_at(call.result, call.type->output[0].type->size, target.node);
				registry.targets.push_back(std::move(target));
				return;
			}
			if (name == "all_targets") {
				BuildRegistry& registry = build_registry();
				std::scoped_lock<std::mutex> lock(registry.mutex);
				auto nodes = reinterpret_cast<uint32_t*>(data.allocate(4 * std::max<size_t>(registry.targets.size(), 1), 4));
				for (size_t i = 0; i < registry.targets.size(); ++i) {
					nodes[i] = registry.targets[i].node;
				}
				CompileTimeData::write_view_at(call.result, nodes, registry.targets.size());
				return;
			}
			if (name == "add_check" || name == "add_step") {
				BuildCallback callback;
				callback.function = reinterpret_cast<const void*>(read_u64(call.arguments[0]));
				callback.caller = reinterpret_cast<void (*)(void*)>(call.arguments[call.count]);
				const size_t location_index = name == "add_check" ? 1 : 2;
				read_location(call, location_index, callback.location.file, callback.location.line, callback.location.column);
				// The code they're in has to stay loaded for the compiler to call them
				keep_running_code_loaded();
				BuildRegistry& registry = build_registry();
				std::scoped_lock<std::mutex> lock(registry.mutex);
				if (name == "add_check") {
					registry.checks.push_back(std::move(callback));
					return;
				}
				const uint8_t* after = call.arguments[1];
				auto nodes = reinterpret_cast<const uint32_t*>(read_u64(after + 8));
				for (size_t i = 0; i < read_u64(after); ++i) {
					callback.after.push_back(nodes[i]);
				}
				callback.node = registry.next_node++;
				CompileTimeData::write_number_at(call.result, call.type->output[0].type->size, callback.node);
				registry.steps.push_back(std::move(callback));
				return;
			}
			// find_packages loads packages the program doesn't import
			report_error(ErrorCode::E4024, call.file, 0, 0, std::format("compiler.{} isn't supported yet", name));
		}
	}

	static void compiler_service(const char* name, int64_t name_count, uint8_t* result, uint8_t* const* arguments,
		int64_t count, const uint8_t* context, const char* file, int64_t file_count) {

		ServiceScope* scope = service_scope;
		const std::string_view called(name, static_cast<size_t>(name_count));
		Declaration* declaration = nullptr;
		{
			std::scoped_lock<std::mutex> lock(scope->program->names.mutex);
			auto iter = scope->program->names.declarations.find(std::make_pair(intern(std::format("{}compiler", BASE_PACKAGE_PREFIX)),
				intern(std::string(called))));
			declaration = iter != scope->program->names.declarations.end() ? iter->second : nullptr;
		}
		// require_any's brackets aren't declared, since only the generator calls them (docs/types.md, Constraints)
		const bool bracket = called.starts_with("require_any_");
		if (!bracket && (declaration == nullptr || declaration->value_type == nullptr)) {
			return;
		}
		Call call{ called, result, arguments, static_cast<size_t>(count), context, std::string(file, static_cast<size_t>(file_count)),
			declaration != nullptr ? static_cast<TypeInfoFunction const*>(declaration->value_type) : nullptr, scope->program, scope->options,
			compile_time_data(scope->program) };
		carry_out(call);
	}

	BuildRegistry& build_registry() {
		// Never freed: the build lasts until the compiler exits
		static auto* registry = new BuildRegistry();
		return *registry;
	}

	void reset_build_registry() {
		BuildRegistry& registry = build_registry();
		std::scoped_lock<std::mutex> lock(registry.mutex);
		registry.targets.clear();
		registry.checks.clear();
		registry.steps.clear();
		registry.next_node = 1;
	}

	// A path the build package gave, relative to its folder.
	static std::filesystem::path from_build(const Options& build, const std::string& path) {
		std::filesystem::path given(path);
		return given.is_absolute() ? given : build.input / given;
	}

	bool target_options(const BuildTarget& target, const Options& build, Options& result) {
		auto refuse = [&](const std::string& why) {
			report_error(ErrorCode::E4029, target.location.file, target.location.line, target.location.column,
				std::format("target {}: {}", target.name, why));
			return false;
		};
		std::error_code error;
		const std::filesystem::path root = std::filesystem::canonical(from_build(build, target.root), error);
		if (target.root.empty() || error) {
			return refuse(std::format("its root package {} isn't a folder", target.root));
		}
		result.input = root;
		result.output_name = !target.output_path.empty() ? from_build(build, target.output_path).string()
			: (std::filesystem::current_path() / (target.name.empty() ? root.filename().string() : target.name)).string();
		result.entry = target.entry.empty() ? "main" : target.entry;
		result.install_path = build.install_path;
		result.builtin_paths = build.builtin_paths;
		for (const auto& [location, path] : target.package_paths) {
			const BuiltinPackage package = location == "base" ? BuiltinPackage::BASE : location == "std" ? BuiltinPackage::STD
				: location == "user" ? BuiltinPackage::USER : BuiltinPackage::VENDOR;
			result.builtin_paths[package] = from_build(build, path);
		}
		result.settings = target.settings;
		result.build_extent = build.build_extent;
		result.time_phases = build.time_phases;
		result.optimization_level = target.optimization_level == "O0" ? OptimizationLevel::O0 : target.optimization_level == "O1" ? OptimizationLevel::O1
			: target.optimization_level == "O3" ? OptimizationLevel::O3 : OptimizationLevel::O2;
		result.debug_info = target.debug_info;
		if (target.architecture == "x86_64") {
			result.architecture = ArchType::x86_64;
		}
		else if (target.architecture == "arm64") {
			result.architecture = ArchType::aarch64;
		}
		else {
			return refuse(std::format("it's for {}, which can't be built yet", target.architecture));
		}
		if (target.os == "Windows") {
			result.os = OSType::Win32;
		}
		else if (target.os == "Linux" || target.os == "None" || target.os == "UEFI" || target.os == "SlopOS") {
			result.os = target.os == "Linux" ? OSType::Linux : target.os == "UEFI" ? OSType::UEFI
				: target.os == "SlopOS" ? OSType::SlopOS : OSType::UnknownOS;
			result.object_format = target.os == "UEFI" ? ObjectFormatType::COFF : ObjectFormatType::ELF;
			result.environment = EnvironmentType::UnknownEnvironment;
			result.vendor = VendorType::UnknownVendor;
		}
		else {
			return refuse(std::format("it's for {}, which can't be built yet", target.os));
		}
		result.cpu = target.cpu.empty() ? "generic" : target.cpu;
		result.cpu_features = target.cpu_features;
		result.code_model = target.code_model == "Kernel" ? TargetCodeModel::Kernel : target.code_model == "Small" ? TargetCodeModel::Small
			: target.code_model == "Medium" ? TargetCodeModel::Medium : TargetCodeModel::Default;
		result.relocation_model = target.relocation_model == "Static" ? TargetRelocationModel::Static : TargetRelocationModel::PositionIndependent;
		result.red_zone = target.red_zone;
		result.address_zero_is_memory = target.address_zero_is_memory;
		result.startup_code = target.startup_code;
		// Morestack where it's made: x86-64 and AArch64 targets; off elsewhere, for now
		const bool grows = ArchType::x86_64 == result.architecture || ArchType::aarch64 == result.architecture;
		result.stack_check = target.stack_check_failure == "Trap" ? TargetStackCheck::Trap
			: target.stack_check_failure == "Morestack" && grows ? TargetStackCheck::Morestack : TargetStackCheck::Off;
		if (!target.linker_script.empty()) {
			result.linker_script = std::filesystem::canonical(from_build(build, target.linker_script), error);
			if (error) {
				return refuse(std::format("its linker script {} isn't there", target.linker_script));
			}
		}
		return true;
	}

	/*
	 * A call into the build package's code: the frame its caller reads, with the services set up for the build
	 * program. Returns the function's boolean result, or false if it failed.
	 */
	static bool call_back(ProgramInfo* build, const Options& build_options, const BuildCallback& callback,
		std::vector<uint64_t>& frame, size_t result_offset, ProgramInfo* reflected = nullptr, const Options* reflected_options = nullptr) {

		CompileTimeData& data = compile_time_data(build);
		CompileTimeRun run;
		run.types = &data.described_types();
		run.file_path = callback.location.file;
		run.line = callback.location.line;
		run.column = callback.location.column;
		frame[0] = reinterpret_cast<uintptr_t>(callback.function);
		ServiceScope scope{ build, &build_options, reflected, reflected_options };
		ServiceScope* outer = service_scope;
		service_scope = &scope;
		const RunResult ran = call_loaded(callback.caller, frame.data(), run);
		service_scope = outer;
		return RunResult::RAN == ran && reinterpret_cast<const uint8_t*>(frame.data())[result_offset] != 0;
	}

	bool run_build_checks(ProgramInfo* build, const Options& build_options, ProgramInfo* target, const Options& options) {
		BuildRegistry& registry = build_registry();
		if (registry.checks.empty()) {
			return true;
		}
		CompileTimeData& data = compile_time_data(build);
		const TypeInfoStruct* build_layout = data.compiler_struct("BuildOptions");
		const TypeInfoStruct* program_layout = data.compiler_struct("ProgramInfo");
		const TypeInfoStruct* package_layout = data.compiler_struct("PackageInfo");
		if (build_layout == nullptr || program_layout == nullptr || package_layout == nullptr) {
			return true;
		}
		// The target as a check sees it: its options, and every package in its program, written in the build's
		// memory with the build's layouts, about the target's declarations and types
		Call call{ "", nullptr, nullptr, 0, nullptr, std::string(), nullptr, target, &options, data };
		auto describing = std::make_unique<PhaseTimer>(options.time_phases, "describe the program for the build's checks");
		uint8_t* target_record = data.new_records(build_layout);
		write_build_options(call, target_record, build_layout, true);
		std::vector<hemera::PackageInfo*> packages;
		for (const auto& [path, package] : target->packages) {
			packages.push_back(package);
		}
		// By path, since the map's order is the paths' addresses
		std::sort(packages.begin(), packages.end(), [](const hemera::PackageInfo* a, const hemera::PackageInfo* b) {
			return std::string_view(*a->full_path) < std::string_view(*b->full_path);
		});
		// Every package's constants worked out in one run
		std::vector<Declaration*> constants;
		for (hemera::PackageInfo* package : packages) {
			const std::vector<Declaration*> found = constants_of(target, text_of(package->full_path));
			constants.insert(constants.end(), found.begin(), found.end());
		}
		const auto values = constant_values(call, constants);
		KnownConstants known;
		for (size_t i = 0; i < constants.size(); ++i) {
			known[constants[i]] = values[i];
		}
		uint8_t* package_records = data.new_records(package_layout, packages.size());
		uint8_t* root = nullptr;
		for (size_t i = 0; i < packages.size(); ++i) {
			uint8_t* record = package_records + i * package_layout->size;
			write_package(call, record, package_layout, packages[i], &known);
			if (text_of(packages[i]->full_path) == options.input.string()) {
				root = record;
			}
		}
		uint8_t* program_record = data.new_records(program_layout);
		data.write_pointer(program_record, program_layout, "root", root);
		data.write_view(program_record, program_layout, "packages", package_records, packages.size());
		describing.reset();
		bool passed = true;
		for (const BuildCallback& check : registry.checks) {
			PhaseTimer timer(options.time_phases, "a build check");
			std::vector<uint64_t> frame{ 0, reinterpret_cast<uintptr_t>(target_record), reinterpret_cast<uintptr_t>(program_record), 0 };
			passed = call_back(build, build_options, check, frame, 24, target, &options) && passed;
		}
		return passed;
	}

	bool run_build_steps(ProgramInfo* build, const Options& build_options) {
		BuildRegistry& registry = build_registry();
		CompileTimeData& data = compile_time_data(build);
		const TypeInfoStruct* output_layout = data.compiler_struct("TargetOutput");
		std::set<uint32_t> finished;
		for (const BuildTarget& target : registry.targets) {
			if (target.built) {
				finished.insert(target.node);
			}
		}
		bool passed = true;
		for (const BuildCallback& step : registry.steps) {
			// Each target it runs after, as a TargetOutput; it doesn't run if one of them didn't finish
			std::vector<const BuildTarget*> inputs;
			bool ready = output_layout != nullptr;
			for (uint32_t node : step.after) {
				if (!finished.contains(node)) {
					ready = false;
				}
				for (const BuildTarget& target : registry.targets) {
					if (target.node == node) {
						inputs.push_back(&target);
					}
				}
			}
			if (!ready) {
				report_error(ErrorCode::E4029, step.location.file, step.location.line, step.location.column,
					"this step didn't run, since something it runs after failed");
				passed = false;
				continue;
			}
			uint8_t* outputs = data.new_records(output_layout, inputs.size());
			for (size_t i = 0; i < inputs.size(); ++i) {
				uint8_t* record = outputs + i * output_layout->size;
				data.write_number(record, output_layout, "node", inputs[i]->node);
				data.write_text(record, output_layout, "name", inputs[i]->name);
				data.write_text(record, output_layout, "path", inputs[i]->output);
				data.write_member(record, output_layout, "output_type", inputs[i]->output_type.empty() ? "Executable" : inputs[i]->output_type);
			}
			std::vector<uint64_t> frame{ 0, inputs.size(), reinterpret_cast<uintptr_t>(outputs), 0 };
			if (call_back(build, build_options, step, frame, 24)) {
				finished.insert(step.node);
			}
			else {
				passed = false;
			}
		}
		return passed;
	}

	/*
	 * A constraint (docs/types.md, Constraints): its #constraint function called with the arguments
	 * it's checked for, each type as its descriptor, and each value as a constant of its parameter's
	 * type. What its requirements find unsatisfied goes in the run.
	 */
	static bool run_constraint_evaluation(Generator& generator, Evaluation& evaluation, std::vector<Declaration*>& unchecked) {
		ConstraintRun& run = *evaluation.constraint;
		run.unsatisfied.clear();
		auto signature = run.constraint != nullptr ? static_cast<TypeInfoFunction const*>(run.constraint->value_type) : nullptr;
		if (signature == nullptr || signature->input.size() != run.types.size()) {
			report_error(ErrorCode::E4018, evaluation.file_path, run.constraint != nullptr && run.constraint->node != nullptr
				? run.constraint->node->value.line_number : 0, 0, std::format("{} takes {} arguments, not {}",
					run.constraint != nullptr ? text_of(run.constraint->name) : "the constraint",
					signature != nullptr ? signature->input.size() : 0, run.types.size()));
			return false;
		}
		CompileTimeItem item{ nullptr, nullptr, nullptr, run.constraint, nullptr };
		item.emit = [&](Generator& compiled) {
			std::vector<mlir::Value> arguments;
			if (takes_context(compiled, signature, run.constraint)) {
				arguments.push_back(compiled.state->context);
			}
			for (size_t i = 0; i < run.types.size(); ++i) {
				TypeInfo* parameter = signature->input[i].type;
				if (run.types[i] != nullptr) {
					arguments.push_back(type_descriptor(compiled, run.types[i]));
					continue;
				}
				const ConstantValue& constant = run.values[i];
				if (ConstantValue::Kind::FUNCTION == constant.kind && constant.function != nullptr) {
					arguments.push_back(LLVM::AddressOfOp::create(compiled.builder, compiled.loc, function_for(compiled, constant.function)));
					continue;
				}
				const int64_t number = ConstantValue::Kind::BOOLEAN == constant.kind ? (constant.boolean ? 1 : 0)
					: ConstantValue::Kind::ENUM_MEMBER == constant.kind ? enum_value(parameter, intern(constant.member))
					: constant.integer;
				arguments.push_back(constant_int(compiled, llvm_type(compiled, parameter), number));
			}
			LLVM::CallOp::create(compiled.builder, compiled.loc, function_for(compiled, run.constraint), arguments);
		};
		std::vector<CompileTimeItem> items{ item };
		return run_items(generator, items, &unchecked, false, &run.unsatisfied);
	}

	bool run_evaluation(ProgramInfo* program_info, const Options& options, Evaluation& evaluation,
		std::vector<Declaration*>& unchecked) {

		// Checking hasn't finished, so generating the program hasn't loaded these yet
		program_info->context->loadDialect<LLVM::LLVMDialect>();
		program_info->context->loadDialect<::hmir::HemeraDialect>();
		mlir::ModuleOp scratch = mlir::ModuleOp::create(mlir::UnknownLoc::get(program_info->context), "evaluation");
		bool ran = false;
		{
			Generator generator(program_info, scratch);
			generator.options = &options;
			generator.input_package = intern(options.input.string());
			generator.file_path = evaluation.file_path;
			ran = evaluation.constraint != nullptr ? run_constraint_evaluation(generator, evaluation, unchecked)
				: run_at_compile_time(generator, evaluation.node, evaluation.type, evaluation.checked.get(), evaluation.declaration,
					evaluation.value, &unchecked);
		}
		scratch.erase();
		return ran;
	}

	std::string target_features(const Options& options) {
		std::string features = options.cpu_features;
		// The carrier register, which nothing else may use (docs/calling_convention.md, Carrier Register)
		if (ArchType::x86_64 == options.architecture) {
			features += features.empty() ? "+reserve-r14" : ",+reserve-r14";
		}
		if (ArchType::aarch64 == options.architecture) {
			/*
			 * ARMv8.2-A with LSE atomics unless the CPU says otherwise, like x86-64-v3 for x86. First, so the
			 * target's own features, like a kernel's -fp-armv8, come after and win
			 */
			if (options.cpu.empty() || options.cpu == "generic") {
				features = features.empty() ? "+v8.2a,+lse" : "+v8.2a,+lse," + features;
			}
			features += features.empty() ? "+reserve-x28" : ",+reserve-x28";
		}
		return features;
	}

	bool generate_program(ProgramInfo* program_info, const Options& options, mlir::ModuleOp module) {
		module.getContext()->loadDialect<LLVM::LLVMDialect>();
		module.getContext()->loadDialect<::hmir::HemeraDialect>();
		Generator generator(program_info, module);
		generator.options = &options;
		generator.input_package = intern(options.input.string());
		if (options.startup_code && hosted_linux(generator)) {
			std::scoped_lock<std::mutex> lock(generator.names.mutex);
			for (const auto& [key, declaration] : generator.names.declarations) {
				if (declaration != nullptr && declaration->foreign_library != nullptr && !is_base_package(declaration->package_path)) {
					generator.c_library = true;
					break;
				}
			}
		}
		Declaration* entry = nullptr;
		{
			std::scoped_lock<std::mutex> lock(generator.names.mutex);
			auto iter = generator.names.declarations.find(std::make_pair(generator.input_package, intern(options.entry)));
			if (iter != generator.names.declarations.end()) {
				entry = iter->second;
			}
		}
		// Only a SlopOS program's entry takes parameters, its grants (docs/compilation.md, Entry Parameters)
		const bool takes_parameters = entry != nullptr && entry->value_type != nullptr
			&& TypeInfoVariant::FUNCTION == entry->value_type->variant
			&& !static_cast<TypeInfoFunction const*>(entry->value_type)->input.empty();
		if (entry == nullptr || DeclarationKind::FUNCTION != entry->kind || entry->value_type == nullptr
			|| (options.startup_code && takes_parameters && OSType::SlopOS != options.os)) {
			report_error(ErrorCode::E5004, options.input.string(), 0, 0, options.startup_code
				? std::format("a hosted program needs {} :: fn() or fn() -> int", options.entry)
				: std::format("the entry function {} isn't declared", options.entry));
			return false;
		}
		if (options.startup_code) {
			generate_entry(generator, entry, OSType::Win32 == options.os);
		}
		else {
			// A freestanding program starts at its entry function itself
			function_for(generator, entry);
		}
		generate_kept(generator);
		while (!generator.pending.empty()) {
			Declaration* next = generator.pending.back();
			generator.pending.pop_back();
			generate_function(generator, next);
		}
		generate_function_names(generator);
		generate_used(generator);
		finish_module(generator);
		if (generator.failed) {
			return false;
		}
		if (mlir::failed(mlir::verify(module))) {
			report_error(ErrorCode::E5003, options.input.string(), 0, 0, "the generated MLIR isn't valid");
			return false;
		}
		return true;
	}

	/*
	 * A loop over count bytes, calling body with each index: upwards, or downwards from the end.
	 * Leaves the builder after the loop.
	 */
	static void byte_loop(llvm::IRBuilder<>& builder, llvm::Value* count, bool downwards,
		const std::function<void(llvm::Value*)>& body) {

		llvm::Function* function = builder.GetInsertBlock()->getParent();
		llvm::LLVMContext& context = function->getContext();
		llvm::BasicBlock* before = builder.GetInsertBlock();
		llvm::BasicBlock* header = llvm::BasicBlock::Create(context, "loop", function);
		llvm::BasicBlock* inside = llvm::BasicBlock::Create(context, "byte", function);
		llvm::BasicBlock* after = llvm::BasicBlock::Create(context, "done", function);
		builder.CreateBr(header);
		builder.SetInsertPoint(header);
		llvm::PHINode* remaining = builder.CreatePHI(count->getType(), 2);
		remaining->addIncoming(count, before);
		builder.CreateCondBr(builder.CreateICmpEQ(remaining, llvm::ConstantInt::get(count->getType(), 0)), after, inside);
		builder.SetInsertPoint(inside);
		llvm::Value* next = builder.CreateSub(remaining, llvm::ConstantInt::get(count->getType(), 1));
		body(downwards ? next : builder.CreateSub(count, remaining));
		remaining->addIncoming(next, builder.GetInsertBlock());
		builder.CreateBr(header);
		builder.SetInsertPoint(after);
	}

	// A function of the C library's, defined here, or its body if it's only declared.
	static llvm::Function* library_function(llvm::Module& module, llvm::StringRef name, llvm::FunctionType* type) {
		llvm::Function* function = module.getFunction(name);
		if (function == nullptr) {
			function = llvm::Function::Create(type, llvm::Function::ExternalLinkage, name, module);
		}
		// Its own loop mustn't be turned back into a call to itself
		function->addFnAttr("no-builtins");
		return function;
	}

	/*
	 * __chkstk, which code for Windows calls before taking a frame bigger than a page, with its size
	 * in rax: Windows commits a thread's stack a page at a time as its guard page is touched, so each
	 * page of the frame is touched in order, from the top down. It changes no register but the
	 * flags, like the C library's, which Hemera doesn't link.
	 */
	//SPEC: compiler-rt lib/builtins/x86_64/chkstk.S
	static void define_stack_probe(llvm::Module& module, const Options& options) {
		if (OSType::Win32 != options.os || ArchType::x86_64 != options.architecture) {
			return;
		}
		module.appendModuleInlineAsm(
			"\t.text\n"
			"\t.globl __chkstk\n"
			"\t.p2align 4\n"
			"__chkstk:\n"
			"\tpushq %rcx\n"
			"\tpushq %rax\n"
			// The stack pointer the caller called from: above the return address and the two pushes
			"\tleaq 24(%rsp), %rcx\n"
			"\tcmpq $0x1000, %rax\n"
			"\tjb 2f\n"
			"1:\n"
			"\tsubq $0x1000, %rcx\n"
			"\torq $0, (%rcx)\n"
			"\tsubq $0x1000, %rax\n"
			"\tcmpq $0x1000, %rax\n"
			"\tja 1b\n"
			"2:\n"
			"\tsubq %rax, %rcx\n"
			"\torq $0, (%rcx)\n"
			"\tpopq %rax\n"
			"\tpopq %rcx\n"
			"\tretq\n");
	}

	/*
	 * memcpy, memmove, memset and memcmp, which LLVM calls for large copies even without the C
	 * library, as byte loops: nothing Hemera builds links a C library.
	 */
	static void define_memory_functions(llvm::Module& module) {
		llvm::LLVMContext& context = module.getContext();
		llvm::Type* pointer = llvm::PointerType::get(context, 0);
		llvm::Type* size = llvm::Type::getInt64Ty(context);
		llvm::Type* byte = llvm::Type::getInt8Ty(context);
		llvm::Type* i32 = llvm::Type::getInt32Ty(context);
		llvm::IRBuilder<> builder(context);
		for (llvm::StringRef name : { "memcpy", "memmove" }) {
			llvm::Function* function = library_function(module, name, llvm::FunctionType::get(pointer, { pointer, pointer, size }, false));
			if (!function->isDeclaration()) {
				continue;
			}
			llvm::Value* target = function->getArg(0);
			llvm::Value* source = function->getArg(1);
			llvm::Value* count = function->getArg(2);
			builder.SetInsertPoint(llvm::BasicBlock::Create(context, "entry", function));
			auto copy = [&](bool downwards) {
				byte_loop(builder, count, downwards, [&](llvm::Value* index) {
					llvm::Value* from = builder.CreateGEP(byte, source, index);
					builder.CreateStore(builder.CreateLoad(byte, from), builder.CreateGEP(byte, target, index));
				});
				builder.CreateRet(target);
			};
			if (name == "memcpy") {
				copy(false);
				continue;
			}
			// memmove copies downwards when the target is after the source, so overlap is fine
			llvm::BasicBlock* upwards = llvm::BasicBlock::Create(context, "upwards", function);
			llvm::BasicBlock* downwards = llvm::BasicBlock::Create(context, "downwards", function);
			builder.CreateCondBr(builder.CreateICmpUGT(target, source), downwards, upwards);
			builder.SetInsertPoint(upwards);
			copy(false);
			builder.SetInsertPoint(downwards);
			copy(true);
		}
		llvm::Function* memset = library_function(module, "memset", llvm::FunctionType::get(pointer, { pointer, i32, size }, false));
		if (memset->isDeclaration()) {
			builder.SetInsertPoint(llvm::BasicBlock::Create(context, "entry", memset));
			llvm::Value* fill = builder.CreateTrunc(memset->getArg(1), byte);
			byte_loop(builder, memset->getArg(2), false, [&](llvm::Value* index) {
				builder.CreateStore(fill, builder.CreateGEP(byte, memset->getArg(0), index));
			});
			builder.CreateRet(memset->getArg(0));
		}
		llvm::Function* memcmp = library_function(module, "memcmp", llvm::FunctionType::get(i32, { pointer, pointer, size }, false));
		if (memcmp->isDeclaration()) {
			// The difference of the first bytes that differ, as unsigned bytes, or 0
			builder.SetInsertPoint(llvm::BasicBlock::Create(context, "entry", memcmp));
			llvm::BasicBlock* differs = llvm::BasicBlock::Create(context, "differs", memcmp);
			builder.SetInsertPoint(differs);
			llvm::PHINode* left = builder.CreatePHI(i32, 1);
			llvm::PHINode* right = builder.CreatePHI(i32, 1);
			builder.CreateRet(builder.CreateSub(left, right));
			builder.SetInsertPoint(&memcmp->getEntryBlock());
			byte_loop(builder, memcmp->getArg(2), false, [&](llvm::Value* index) {
				llvm::Value* a = builder.CreateZExt(builder.CreateLoad(byte, builder.CreateGEP(byte, memcmp->getArg(0), index)), i32);
				llvm::Value* b = builder.CreateZExt(builder.CreateLoad(byte, builder.CreateGEP(byte, memcmp->getArg(1), index)), i32);
				llvm::BasicBlock* same = llvm::BasicBlock::Create(builder.getContext(), "same", memcmp);
				left->addIncoming(a, builder.GetInsertBlock());
				right->addIncoming(b, builder.GetInsertBlock());
				builder.CreateCondBr(builder.CreateICmpNE(a, b), differs, same);
				builder.SetInsertPoint(same);
			});
			builder.CreateRet(llvm::ConstantInt::get(i32, 0));
		}
	}

	// What a walk needs from the generated fiber switches and morestack, when the program has them.
	struct WalkSupport {
		llvm::Function* loop_return = nullptr;
		llvm::Function* morestack_continue = nullptr;
		// FIBER_WALK_SYMBOL's offsets, see fiber_walk_table
		std::vector<uint64_t> offsets;
		// The carrier register's name: r14 on x86-64, x28 on AArch64
		const char* carrier_register = "r14";
	};

	static WalkSupport walk_support(llvm::Module& module, const Options& options) {
		WalkSupport support;
		support.carrier_register = ArchType::aarch64 == options.architecture ? "x28" : "r14";
		support.loop_return = module.getFunction(FIBER_LOOP_RETURN_SYMBOL);
		support.morestack_continue = module.getFunction(MORESTACK_CONTINUE_SYMBOL);
		llvm::GlobalVariable* table = module.getGlobalVariable(FIBER_WALK_SYMBOL, true);
		auto* values = table != nullptr ? llvm::dyn_cast<llvm::ConstantDataArray>(table->getInitializer()) : nullptr;
		for (unsigned i = 0; values != nullptr && i < values->getNumElements(); ++i) {
			support.offsets.push_back(values->getElementAsInteger(i));
		}
		if (support.offsets.size() < 7) {
			support.loop_return = nullptr;
		}
		return support;
	}

	/*
	 * The walk itself, from where builder is in function: from frame start, following saved frame
	 * pointers, recording each frame's return address into addresses after the written ones, up to
	 * count, once skip have gone by; returns how many it wrote. A frame whose saved frame pointer is
	 * null is the entry function's, which end_stack_at_entry made the end of the chain, so its return
	 * address isn't recorded. A frame the fiber resume loop re-entered returns to the loop: its real
	 * return address is the running fiber's reentered_return. A body morestack ran on a new segment
	 * returns into morestack, whose own frame returns into the function's .grow: both are left out.
	 */
	static void build_walk(llvm::IRBuilder<>& builder, llvm::Function* function, const WalkSupport& support, llvm::Value* start,
		llvm::Value* addresses, llvm::Value* count, llvm::Value* skip, llvm::Value* first_written) {

		llvm::LLVMContext& context = builder.getContext();
		llvm::Type* pointer = llvm::PointerType::get(context, 0);
		llvm::Type* size = llvm::Type::getInt64Ty(context);
		llvm::Type* bit = llvm::Type::getInt1Ty(context);
		llvm::BasicBlock* entry = builder.GetInsertBlock();
		llvm::BasicBlock* loop = llvm::BasicBlock::Create(context, "loop", function);
		llvm::BasicBlock* frame = llvm::BasicBlock::Create(context, "frame", function);
		llvm::BasicBlock* returned = llvm::BasicBlock::Create(context, "returned", function);
		llvm::BasicBlock* record = llvm::BasicBlock::Create(context, "record", function);
		llvm::BasicBlock* store = llvm::BasicBlock::Create(context, "store", function);
		llvm::BasicBlock* next = llvm::BasicBlock::Create(context, "next", function);
		llvm::BasicBlock* done = llvm::BasicBlock::Create(context, "done", function);
		builder.CreateBr(loop);

		// Stop at a null or misaligned frame pointer, or once addresses is full
		builder.SetInsertPoint(loop);
		llvm::PHINode* current = builder.CreatePHI(pointer, 2);
		llvm::PHINode* written = builder.CreatePHI(size, 2);
		llvm::PHINode* skipped = builder.CreatePHI(size, 2);
		llvm::PHINode* dropping = builder.CreatePHI(bit, 2);
		current->addIncoming(start, entry);
		written->addIncoming(first_written, entry);
		skipped->addIncoming(llvm::ConstantInt::get(size, 0), entry);
		dropping->addIncoming(llvm::ConstantInt::getFalse(context), entry);
		llvm::Value* misaligned = builder.CreateICmpNE(builder.CreateAnd(builder.CreatePtrToInt(current, size), 7),
			llvm::ConstantInt::get(size, 0));
		llvm::Value* stop = builder.CreateOr(builder.CreateOr(builder.CreateIsNull(current), misaligned),
			builder.CreateICmpUGE(written, count));
		builder.CreateCondBr(stop, done, frame);

		// The caller's frame pointer, then this frame's return address unless it's the entry function's
		builder.SetInsertPoint(frame);
		llvm::Value* caller = builder.CreateLoad(pointer, current);
		llvm::Value* raw_return = builder.CreateLoad(pointer, builder.CreateConstGEP1_64(builder.getInt8Ty(), current, 8));
		builder.CreateCondBr(builder.CreateIsNull(caller), done, returned);

		builder.SetInsertPoint(returned);
		llvm::Value* return_address = raw_return;
		if (support.loop_return != nullptr) {
			// Through the resume loop: the running fiber knows where this frame really returns
			llvm::BasicBlock* through_loop = llvm::BasicBlock::Create(context, "through_loop", function);
			llvm::BasicBlock* found = llvm::BasicBlock::Create(context, "found", function);
			llvm::BasicBlock* from = builder.GetInsertBlock();
			builder.CreateCondBr(builder.CreateICmpEQ(raw_return, support.loop_return), through_loop, found);
			builder.SetInsertPoint(through_loop);
			llvm::Function* read_register = llvm::Intrinsic::getOrInsertDeclaration(function->getParent(),
				llvm::Intrinsic::read_register, { size });
			llvm::Value* carrier_value = builder.CreateCall(read_register, { llvm::MetadataAsValue::get(context,
				llvm::MDNode::get(context, { llvm::MDString::get(context, support.carrier_register) })) });
			llvm::Value* carrier = builder.CreateIntToPtr(carrier_value, pointer);
			llvm::Value* real = builder.CreateLoad(pointer, builder.CreateConstGEP1_64(builder.getInt8Ty(), carrier, support.offsets[0]));
			builder.CreateBr(found);
			builder.SetInsertPoint(found);
			llvm::PHINode* chosen = builder.CreatePHI(pointer, 2);
			chosen->addIncoming(raw_return, from);
			chosen->addIncoming(real, through_loop);
			return_address = chosen;
		}
		// morestack's continuation, and then .grow's: neither is a call the program made
		llvm::Value* into_morestack = support.morestack_continue != nullptr
			? builder.CreateICmpEQ(return_address, support.morestack_continue) : static_cast<llvm::Value*>(llvm::ConstantInt::getFalse(context));
		llvm::Value* drop = builder.CreateOr(dropping, into_morestack);
		llvm::BasicBlock* checked = builder.GetInsertBlock();
		builder.CreateCondBr(drop, next, record);

		// Skipped frames count towards skip; the others go in addresses
		builder.SetInsertPoint(record);
		llvm::Value* skipping = builder.CreateICmpULT(skipped, skip);
		llvm::Value* one_more_skipped = builder.CreateAdd(skipped, llvm::ConstantInt::get(size, 1));
		builder.CreateCondBr(skipping, next, store);
		builder.SetInsertPoint(store);
		builder.CreateStore(return_address, builder.CreateGEP(pointer, addresses, written));
		llvm::Value* one_more_written = builder.CreateAdd(written, llvm::ConstantInt::get(size, 1));
		builder.CreateBr(next);

		builder.SetInsertPoint(next);
		llvm::PHINode* now_written = builder.CreatePHI(size, 3);
		now_written->addIncoming(written, checked);
		now_written->addIncoming(written, record);
		now_written->addIncoming(one_more_written, store);
		llvm::PHINode* now_skipped = builder.CreatePHI(size, 3);
		now_skipped->addIncoming(skipped, checked);
		now_skipped->addIncoming(one_more_skipped, record);
		now_skipped->addIncoming(skipped, store);
		llvm::PHINode* now_dropping = builder.CreatePHI(bit, 3);
		now_dropping->addIncoming(into_morestack, checked);
		now_dropping->addIncoming(llvm::ConstantInt::getFalse(context), record);
		now_dropping->addIncoming(llvm::ConstantInt::getFalse(context), store);
		current->addIncoming(caller, next);
		written->addIncoming(now_written, next);
		skipped->addIncoming(now_skipped, next);
		dropping->addIncoming(now_dropping, next);
		builder.CreateBr(loop);

		builder.SetInsertPoint(done);
		llvm::PHINode* result = builder.CreatePHI(size, 2);
		result->addIncoming(written, loop);
		result->addIncoming(written, frame);
		builder.CreateRet(result);
	}

	/*
	 * intrinsics.capture_fiber_stack_trace(fiber, addresses), if a program uses it: a suspended
	 * fiber's trace, where it continues first, then the walk from its innermost frame, whose return
	 * addresses fiber_suspend made real again. 0 for a fiber that isn't suspended.
	 */
	static void define_fiber_stack_walker(llvm::Module& module, const WalkSupport& support) {
		llvm::Function* walker = module.getFunction(FIBER_STACK_WALKER_SYMBOL);
		if (walker == nullptr || !walker->isDeclaration()) {
			return;
		}
		llvm::LLVMContext& context = module.getContext();
		llvm::Type* pointer = llvm::PointerType::get(context, 0);
		llvm::Type* size = llvm::Type::getInt64Ty(context);
		walker->setLinkage(llvm::GlobalValue::InternalLinkage);
		walker->addFnAttr(llvm::Attribute::NoInline);
		llvm::IRBuilder<> builder(llvm::BasicBlock::Create(context, "entry", walker));
		if (support.loop_return == nullptr) {
			// No fibers switch in this program, so none is suspended
			builder.CreateRet(llvm::ConstantInt::get(size, 0));
			return;
		}
		llvm::Value* fiber = walker->getArg(0);
		llvm::Value* addresses = walker->getArg(1);
		llvm::Value* count = walker->getArg(2);
		auto field = [&](size_t index) { return builder.CreateConstGEP1_64(builder.getInt8Ty(), fiber, support.offsets[index]); };
		llvm::Type* state_type = llvm::Type::getIntNTy(context, static_cast<unsigned>(support.offsets[3] * 8));
		llvm::Value* suspended = builder.CreateICmpEQ(builder.CreateLoad(state_type, field(2)),
			llvm::ConstantInt::get(state_type, support.offsets[4]));
		llvm::Value* room = builder.CreateICmpNE(count, llvm::ConstantInt::get(size, 0));
		llvm::BasicBlock* walk = llvm::BasicBlock::Create(context, "walk", walker);
		llvm::BasicBlock* none = llvm::BasicBlock::Create(context, "none", walker);
		builder.CreateCondBr(builder.CreateAnd(suspended, room), walk, none);
		builder.SetInsertPoint(none);
		builder.CreateRet(llvm::ConstantInt::get(size, 0));
		builder.SetInsertPoint(walk);
		llvm::Value* saved = builder.CreateLoad(pointer, field(1));
		auto from_saved = [&](size_t index) { return builder.CreateConstGEP1_64(builder.getInt8Ty(), saved, support.offsets[index]); };
		builder.CreateStore(builder.CreateLoad(pointer, from_saved(6)), addresses);
		build_walk(builder, walker, support, builder.CreateLoad(pointer, from_saved(5)), addresses, count,
			llvm::ConstantInt::get(size, 0), llvm::ConstantInt::get(size, 1));
	}

	/*
	 * capture_stack_trace's walk (docs/calling_convention.md, Walking the Stack), if a program uses
	 * it: (addresses, count, skip) -> how many were written. It starts at its caller's frame, so the
	 * first address is in the caller of the function that called capture_stack_trace, and follows the
	 * saved frame pointers. A frame whose saved frame pointer is null is the entry function's, which
	 * end_stack_at_entry made the end of the chain, so its return address isn't recorded.
	 */
	static void define_stack_walker(llvm::Module& module, const Options& options) {
		const WalkSupport support = walk_support(module, options);
		define_fiber_stack_walker(module, support);
		llvm::Function* walker = module.getFunction(STACK_WALKER_SYMBOL);
		if (walker == nullptr || !walker->isDeclaration()) {
			return;
		}
		llvm::LLVMContext& context = module.getContext();
		llvm::Type* pointer = llvm::PointerType::get(context, 0);
		llvm::Type* size = llvm::Type::getInt64Ty(context);
		walker->setLinkage(llvm::GlobalValue::InternalLinkage);
		walker->addFnAttr(llvm::Attribute::NoInline);
		walker->addFnAttr("frame-pointer", "all");
		// From the walker's caller's frame
		llvm::IRBuilder<> builder(llvm::BasicBlock::Create(context, "entry", walker));
		llvm::Value* own = builder.CreateIntrinsic(llvm::Intrinsic::frameaddress, { pointer }, { builder.getInt32(0) });
		build_walk(builder, walker, support, builder.CreateLoad(pointer, own), walker->getArg(0), walker->getArg(1),
			walker->getArg(2), llvm::ConstantInt::get(size, 0));
	}

	/*
	 * Make the program's entry function the end of the frame pointer chain, by clearing the frame
	 * pointer it saved: whatever called it (a bootloader, the OS) isn't Hemera code, and its frames
	 * may not follow the convention. Entry functions don't return, so nothing restores it.
	 */
	static void end_stack_at_entry(llvm::Module& module, const Options& options) {
		llvm::Function* entry = module.getFunction(options.startup_code ? std::string(HOSTED_ENTRY_SYMBOL) : options.entry);
		if (entry == nullptr || entry->isDeclaration()) {
			return;
		}
		llvm::IRBuilder<> builder(&*entry->getEntryBlock().getFirstInsertionPt());
		llvm::Type* pointer = llvm::PointerType::get(module.getContext(), 0);
		llvm::Value* frame = builder.CreateIntrinsic(llvm::Intrinsic::frameaddress, { pointer }, { builder.getInt32(0) });
		builder.CreateStore(llvm::ConstantPointerNull::get(llvm::PointerType::get(module.getContext(), 0)), frame);
	}

	/*
	 * The LLVM module's name, which object files keep (an ELF's file symbol): the root package's folder,
	 * not the output's name, so where the output goes doesn't change what's in it.
	 */
	static std::string module_name(const Options& options) {
		std::error_code error;
		std::filesystem::path root = std::filesystem::weakly_canonical(options.input, error);
		if (error) {
			root = options.input;
		}
		if (!std::filesystem::is_directory(root, error)) {
			root = root.stem();
		}
		const std::string name = root.filename().string();
		return name.empty() ? std::string("hemera") : name;
	}

	std::unique_ptr<llvm::Module> lower_to_llvm(mlir::ModuleOp module, llvm::LLVMContext& context, const Options& options) {
		mlir::PassManager passes(module.getContext(), mlir::ModuleOp::getOperationName());
		passes.addPass(mlir::hmir::createHemeraDefer());
		passes.addPass(mlir::hmir::createHemeraLowerControlFlow());
		if (mlir::failed(passes.run(module))) {
			report_error(ErrorCode::E5003, options.input.string(), 0, 0, "lowering HMIR failed");
			return nullptr;
		}
		mlir::DialectRegistry registry;
		mlir::registerBuiltinDialectTranslation(registry);
		mlir::registerLLVMDialectTranslation(registry);
		module.getContext()->appendDialectRegistry(registry);
		std::unique_ptr<llvm::Module> result = mlir::translateModuleToLLVMIR(module, context, module_name(options));
		if (result == nullptr) {
			report_error(ErrorCode::E5003, options.input.string(), 0, 0, "translating to LLVM IR failed");
			return result;
		}
		// The libraries #foreign functions come from, which the back end links
		if (auto libraries = module->getAttrOfType<mlir::ArrayAttr>(LIBRARIES_ATTRIBUTE)) {
			llvm::NamedMDNode* list = result->getOrInsertNamedMetadata(LIBRARIES_METADATA);
			for (mlir::Attribute library : libraries) {
				list->addOperand(llvm::MDNode::get(context, { llvm::MDString::get(context, llvm::cast<mlir::StringAttr>(library).getValue()) }));
			}
		}
		/*
		 * Debug info for PE/COFF is CodeView, which lld-link puts in a PDB; LLVM picks it by this flag,
		 * since the target triple is only set when the object file is made
		 */
		if (options.debug_info && OSType::Win32 == options.os && !result->getModuleFlag("CodeView")) {
			result->addModuleFlag(llvm::Module::Warning, "CodeView", 1);
		}
		const bool codeview = result->getModuleFlag("CodeView") != nullptr;
		const bool classic_frames = system_v_on_windows(options);
		for (llvm::Function& function : *result) {
			/*
			 * On Windows, frames chain through rbp like elsewhere, without Windows' unwind information
			 * (apps/compiler/third-party/patches/llvm), and nothing below the stack pointer is kept
			 */
			if (classic_frames) {
				function.addFnAttr("classic-frame");
			}
			if (!options.red_zone || classic_frames) {
				function.addFnAttr(llvm::Attribute::NoRedZone);
			}
			// Otherwise LLVM assumes nothing is ever at address 0 and drops accesses to it
			if (options.address_zero_is_memory) {
				function.addFnAttr(llvm::Attribute::NullPointerIsValid);
			}
			/*
			 * Every frame keeps its frame pointer, so capture_stack_trace can walk the chain, and no call
			 * reuses its caller's frame, which would leave the caller out of it
			 */
			function.addFnAttr("frame-pointer", "all");
			function.addFnAttr("disable-tail-calls", "true");
			/*
			 * No C library, so a loop that finds a string's end stays a loop, rather than becoming a call
			 * to strlen or wcslen. memcpy, memmove, memset and memcmp are defined (define_memory_functions).
			 */
			function.addFnAttr("no-builtin-strlen");
			function.addFnAttr("no-builtin-wcslen");
			/*
			 * CodeView describes each jump table, and a table optimized away still gets a reference to its
			 * label, which is never defined; switches become branches instead
			 */
			if (codeview) {
				function.addFnAttr("no-jump-tables", "true");
			}
			// A direct call has its callee's convention, which the generator only gave the callee
			for (llvm::BasicBlock& block : function) {
				for (llvm::Instruction& instruction : block) {
					auto* call = llvm::dyn_cast<llvm::CallBase>(&instruction);
					llvm::Function* callee = call != nullptr ? call->getCalledFunction() : nullptr;
					if (callee != nullptr && !callee->isIntrinsic()) {
						call->setCallingConv(callee->getCallingConv());
					}
				}
			}
		}
		define_memory_functions(*result);
		define_stack_probe(*result, options);
		define_stack_walker(*result, options);
		end_stack_at_entry(*result, options);
		return result;
	}
}

#pragma once

#include <concepts>
#include <cstdint>
#include <map>
#include <vector>

#include "type_id.h"
#include "memory/allocator.h"

namespace hemera::hlir {
	
	enum class InstructionMnemonic : uint64_t {
		ADD,
		AND,
		/// <summary>
		/// Logical AND, only for boolean values.
		/// </summary>
		ANDL,
		CALL,
		DIV,
		EQ,
		GT,
		GTE,
		JEQ,
		JMP,
		JNE,
		LT,
		LTE,
		MOD,
		MOV,
		MUL,
		NE,
		/// <summary>
		/// Negate, replacing a value iwth it's two's complement.
		/// </summary>
		NEG,
		NOT,
		OR,
		/// <summary>
		/// Logical OR, only for boolean values.
		/// </summary>
		ORL,
		REMAINDER,
		RET,
		/// <summary>
		/// Shift right (arithmetic).
		/// </summary>
		SAR,
		/// <summary>
		/// Shift left.
		/// </summary>
		SHL,
		/// <summary>
		/// Shift right (logical).
		/// </summary>
		SHR,
		SUB,
		XOR,
		/// <summary>
		/// Not used, only for iterating.
		/// </summary>
		_COUNT,
	};
	
	enum class ValueType { 
		ARGUMENT,
		BASIC_BLOCK,
		USER,
	};

	struct Value {
		ValueType value_type;
		char _padding[4] = { 0 };
		TypeID type;//TODO(ches) actual type?

		Value(ValueType value_type);
		Value(const Value& other);
		Value(Value&& other);
		Value& operator=(const Value& other);
		Value& operator=(Value&& other);
		~Value();
	};

	enum class UserType {
		CONSTANT,
		INSTRUCTION,
	};

	struct User : public Value {
		UserType user_type;
		char _padding[4] = { 0 };

		User(UserType user_type);
		User(const User& other);
		User(User&& other);
		User& operator=(const User& other);
		User& operator=(User&& other);
		~User();
	};

	enum class ConstantType {
		INTEGER,
		FLOATING_POINT,
	};

	struct Constant : public User {
		ConstantType constant_type;
		uint32_t size;
		//TODO(ches) value

		Constant(ConstantType user_type);
		Constant(const Constant& other);
		Constant(Constant&& other);
		Constant& operator=(const Constant& other);
		Constant& operator=(Constant&& other);
		~Constant();
	};

	enum class InstructionType {
		BINARY,
		BRANCH,
		CALL,
		RETURN,
		UNARY,
	};

	struct Instruction : public User {
		InstructionType instruction_type;
		char _padding[4] = { 0 };

		Instruction(InstructionType user_type);
		Instruction(const Instruction& other);
		Instruction(Instruction&& other);
		Instruction& operator=(const Instruction& other);
		Instruction& operator=(Instruction&& other);
		~Instruction();
	};

	struct BinaryInstruction : public Instruction {
		Value* operand1;
		Value* operand2;
		Value* destination;

		BinaryInstruction();
		BinaryInstruction(const BinaryInstruction& other);
		BinaryInstruction(BinaryInstruction&& other);
		BinaryInstruction& operator=(const BinaryInstruction& other);
		BinaryInstruction& operator=(BinaryInstruction&& other);
		~BinaryInstruction();
	};

	struct Branch : public Instruction {
		Value* operand1;
		Value* operand2;

		Branch();
		Branch(const Branch& other);
		Branch(Branch&& other);
		Branch& operator=(const Branch& other);
		Branch& operator=(Branch&& other);
		~Branch();
	};

	enum class CallType {
		CALL,
		CALL_BRANCH,
	};

	struct CallBase : public Instruction {
		CallType call_type;
		char _padding[4] = { 0 };

		CallBase(CallType call_type);
		CallBase(const CallBase& other);
		CallBase(CallBase&& other);
		CallBase& operator=(const CallBase& other);
		CallBase& operator=(CallBase&& other);
		~CallBase();
	};

	struct Call : public CallBase {
		Value* operand;

		Call();
		Call(const Call& other);
		Call(Call&& other);
		Call& operator=(const Call& other);
		Call& operator=(Call&& other);
		~Call();
	};

	struct CallBranch : public CallBase {
		Value* operand;

		CallBranch();
		CallBranch(const CallBranch& other);
		CallBranch(CallBranch&& other);
		CallBranch& operator=(const CallBranch& other);
		CallBranch& operator=(CallBranch&& other);
		~CallBranch();
	};

	struct Return : public Instruction {
		Value* operand;
		Value* destination;

		Return();
		Return(const Return& other);
		Return(Return&& other);
		Return& operator=(const Return& other);
		Return& operator=(Return&& other);
		~Return();
	};

	struct UnaryInstruction : public Instruction {
		Value* operand;
		Value* destination;

		UnaryInstruction();
		UnaryInstruction(const UnaryInstruction& other);
		UnaryInstruction(UnaryInstruction&& other);
		UnaryInstruction& operator=(const UnaryInstruction& other);
		UnaryInstruction& operator=(UnaryInstruction&& other);
		~UnaryInstruction();
	};

	struct BasicBlock : public Value {
		Allocator<>& allocator;
		MyVector<Instruction*> instructions;

		BasicBlock(Allocator<>& allocator);
		BasicBlock(const BasicBlock&) = delete;
		BasicBlock(BasicBlock&&) = delete;
		~BasicBlock();
		BasicBlock& operator=(const BasicBlock&) = delete;
		BasicBlock& operator=(BasicBlock&&) = delete;

		/// <summary>
		/// Create an instruction, and return a pointer to it. Does not
		/// add to the list of instructions, since we may need to insert
		/// other things first.
		/// </summary>
		/// <typeparam name="T">The type of instruction to create.</typeparam>
		/// <returns>The newly allocated instruction.</returns>
		template <typename T>
			requires std::derived_from<T, Instruction>
		T* create_instruction();
	};

	struct Function {
		Allocator<>& allocator;
		MyVector<BasicBlock*> basic_blocks;

		Function(Allocator<>& allocator);
		Function(const Function&) = delete;
		Function(Function&&) = delete;
		~Function();
		Function& operator=(const Function&) = delete;
		Function& operator=(Function&&) = delete;

		/// <summary>
		/// Allocate a basic block, add it to the list of basic blocks, and
		/// return a pointer to it.
		/// </summary>
		/// <returns>The newly created block.</returns>
		BasicBlock* create_basic_block();

	};

}
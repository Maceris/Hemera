#pragma once

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
		TypeID type;
	};

	enum class UserType {
		CONSTANT,
		INSTRUCTION,
	};

	struct User : public Value {
		UserType user_type;
		char _padding[4] = { 0 };
	};

	enum class ConstantType {
		INTEGER,
		FLOATING_POINT,
	};

	struct Constant : public User {
		ConstantType constant_type;
		uint32_t size;
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
	};

	struct BinaryInstruction : public Instruction {
		Value* operand1;
		Value* operand2;
		Value* destination;
	};

	struct Branch : public Instruction {
		Value* operand1;
		Value* operand2;
	};

	enum class CallType {
		CALL,
		CALL_BRANCH,
	};

	struct CallBase : public Instruction {
		CallType call_type;
		char _padding[4] = { 0 };
	};

	struct Call : public CallBase {
		Value* operand;
	};

	struct CallBranch : public CallBase {
		Value* operand;
	};

	struct Return : public Instruction {
		Value* operand;
		Value* destination;
	};

	struct UnaryInstruction : public Instruction {
		Value* operand;
		Value* destination;
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
	};

}
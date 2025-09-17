#include <format>
#include <type_traits>
#include <utility>

#include "front_end/hlir.h"
#include "util/logger.h"

namespace hemera::hlir {


	Value::Value(ValueType value_type)
		: value_type{ value_type }
		, type{ 0 }
	{}
	Value::Value(const Value& other) = default;
	Value::Value(Value&& other) = default;
	Value& Value::operator=(const Value& other) = default;
	Value& Value::operator=(Value&& other) = default;
	Value::~Value() = default;

	User::User(UserType user_type)
		: Value{ ValueType::USER }
		, user_type{ user_type }
	{}
	User::User(const User& other) = default;
	User::User(User&& other) = default;
	User& User::operator=(const User& other) = default;
	User& User::operator=(User&& other) = default;
	User::~User() = default;

	Constant::Constant(ConstantType constant_type)
		: User{ UserType::CONSTANT }
		, constant_type{ constant_type }
	{}
	Constant::Constant(const Constant& other) = default;
	Constant::Constant(Constant&& other) = default;
	Constant& Constant::operator=(const Constant& other) = default;
	Constant& Constant::operator=(Constant&& other) = default;
	Constant::~Constant() = default;

	Instruction::Instruction(InstructionType instruction_type)
		: User{ UserType::INSTRUCTION }
		, instruction_type{ instruction_type }
	{}
	Instruction::Instruction(const Instruction& other) = default;
	Instruction::Instruction(Instruction&& other) = default;
	Instruction& Instruction::operator=(const Instruction& other) = default;
	Instruction& Instruction::operator=(Instruction&& other) = default;
	Instruction::~Instruction() = default;

	BinaryInstruction::BinaryInstruction()
		: Instruction{ InstructionType::BINARY }
		, operand1{ nullptr }
		, operand2{ nullptr }
		, destination{ nullptr }
	{}
	BinaryInstruction::BinaryInstruction(const BinaryInstruction& other) = default;
	BinaryInstruction::BinaryInstruction(BinaryInstruction&& other) = default;
	BinaryInstruction& BinaryInstruction::operator=(const BinaryInstruction& other) = default;
	BinaryInstruction& BinaryInstruction::operator=(BinaryInstruction&& other) = default;
	BinaryInstruction::~BinaryInstruction() = default;

	Branch::Branch()
		: Instruction{ InstructionType::BRANCH }
		, operand1{ nullptr }
		, operand2{ nullptr }
	{}
	Branch::Branch(const Branch& other) = default;
	Branch::Branch(Branch&& other) = default;
	Branch& Branch::operator=(const Branch& other) = default;
	Branch& Branch::operator=(Branch&& other) = default;
	Branch::~Branch() = default;

	CallBase::CallBase(CallType call_type)
		: Instruction{ InstructionType::CALL }
		, call_type{ call_type }
	{}
	CallBase::CallBase(const CallBase& other) = default;
	CallBase::CallBase(CallBase&& other) = default;
	CallBase& CallBase::operator=(const CallBase& other) = default;
	CallBase& CallBase::operator=(CallBase&& other) = default;
	CallBase::~CallBase() = default;

	Call::Call()
		: CallBase{ CallType::CALL }
		, operand{ nullptr }
	{}
	Call::Call(const Call& other) = default;
	Call::Call(Call&& other) = default;
	Call& Call::operator=(const Call& other) = default;
	Call& Call::operator=(Call&& other) = default;
	Call::~Call() = default;

	CallBranch::CallBranch()
		: CallBase{ CallType::CALL_BRANCH }
		, operand{ nullptr }
	{}
	CallBranch::CallBranch(const CallBranch& other) = default;
	CallBranch::CallBranch(CallBranch&& other) = default;
	CallBranch& CallBranch::operator=(const CallBranch& other) = default;
	CallBranch& CallBranch::operator=(CallBranch&& other) = default;
	CallBranch::~CallBranch() = default;

	Return::Return()
		: Instruction{ InstructionType::RETURN }
		, operand{ nullptr }
		, destination{ nullptr }
	{}
	Return::Return(const Return& other) = default;
	Return::Return(Return&& other) = default;
	Return& Return::operator=(const Return& other) = default;
	Return& Return::operator=(Return&& other) = default;
	Return::~Return() = default;

	UnaryInstruction::UnaryInstruction()
		: Instruction{ InstructionType::UNARY }
		, operand{ nullptr }
		, destination{ nullptr }
	{}
	UnaryInstruction::UnaryInstruction(const UnaryInstruction& other) = default;
	UnaryInstruction::UnaryInstruction(UnaryInstruction&& other) = default;
	UnaryInstruction& UnaryInstruction::operator=(const UnaryInstruction& other) = default;
	UnaryInstruction& UnaryInstruction::operator=(UnaryInstruction&& other) = default;
	UnaryInstruction::~UnaryInstruction() = default;


	BasicBlock::BasicBlock(Allocator<>& allocator)
		: Value{ ValueType::BASIC_BLOCK }
		, allocator{ allocator }
		, instructions{ allocator }
	{}

	BasicBlock::~BasicBlock() = default;

	template <typename T>
		requires std::derived_from<T, Instruction>
	T* BasicBlock::create_instruction() {
		T* result = allocator.allocate_object<T>();
		return result;
	}

	Function::Function(Allocator<>& allocator)
		: allocator{ allocator }
		, basic_blocks{ allocator }
	{}

	Function::~Function() = default;

	BasicBlock* Function::create_basic_block() {
		BasicBlock* result = allocator.allocate_object<BasicBlock>();
		allocator.construct<BasicBlock>(result, allocator);
		basic_blocks.emplace_back(result);
		return result;
	}

}
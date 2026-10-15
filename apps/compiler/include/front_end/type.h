#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "memory/allocator.h"

namespace hemera {

	/*
	 * Type information: what the compiler knows about each type, including its memory layout
	 * (docs/types.md, Memory Layout). Sizes and alignments are in bytes, for a 64-bit target.
	 */

	enum class TypeInfoVariant : uint8_t {
		ALIAS,
		ANY,
		ARRAY,
		BOOLEAN,
		CHAR,
		COMPLEX,
		ENUM,
		FLOAT,
		FUNCTION,
		INTEGER,
		POINTER,
		QUATERNION,
		STRING,
		STRUCT,
		TYPE,
		UNION,
		VOID,
	};

	enum class ArrayType : uint8_t {
		STATIC,
		DYNAMIC,
		VIEW,
	};

	enum class Endianness : uint8_t {
		BIG,
		LITTLE,
		SYSTEM,
	};

	/// <summary>
	/// The size of a pointer, usize, uint and int on the targets Hemera supports.
	/// </summary>
	constexpr size_t POINTER_SIZE = 8;

	struct TypeInfo {
		TypeInfoVariant variant;
		/// <summary>
		/// Whether values of this type can carry pointers (pointers, rawptr, array views, strings,
		/// any, or aggregates containing those), and so can be local values that point into the
		/// stack. Function values and type values never point into the stack, so they don't count.
		/// </summary>
		bool contains_pointers = false;
		/// <summary>
		/// Its size and alignment are known. A declared struct, union, enum or alias exists before
		/// it's resolved, so pointers can refer to it, but its layout is only known after.
		/// </summary>
		bool complete = true;
		size_t size;
		size_t alignment;

		TypeInfo(TypeInfoVariant variant, size_t size, size_t alignment);
		TypeInfo(const TypeInfo&) = delete;
		TypeInfo& operator=(const TypeInfo&) = delete;
		virtual ~TypeInfo();
	};

	struct TypeInfoAlias : public TypeInfo {
		TypeInfo* base_type;
		InternedString name;
		bool distinct;

		TypeInfoAlias(InternedString name, bool distinct);
	};

	/// <summary>
	/// One dimension: a static array of count elements, an array view, or a dynamic array. An array
	/// of arrays, like int[4][], has an array as its element type: the outermost dimension, the one
	/// indexed first, is this one.
	/// </summary>
	struct TypeInfoArray : public TypeInfo {
		TypeInfo* element_type;
		ArrayType array_type;
		size_t count;

		TypeInfoArray(TypeInfo* element_type, ArrayType array_type, size_t count);
	};

	/// <summary>
	/// bool and b8 to b64.
	/// </summary>
	struct TypeInfoBoolean : public TypeInfo {
		explicit TypeInfoBoolean(size_t size);
	};

	/// <summary>
	/// Complex numbers (two parts) and quaternions (four), of integers of a part's size.
	/// </summary>
	struct TypeInfoComposite : public TypeInfo {
		size_t part_size;

		TypeInfoComposite(TypeInfoVariant variant, size_t part_size, size_t parts);
	};

	struct TypeInfoEnum : public TypeInfo {
		InternedString name;
		/// <summary>
		/// From #backed_by, uint if it wasn't given.
		/// </summary>
		TypeInfo* backing_type;
		std::vector<InternedString> members;
		/// <summary>
		/// Each member's value, in the same order as members.
		/// </summary>
		std::vector<uint64_t> values;

		explicit TypeInfoEnum(InternedString name);
	};

	struct TypeInfoFloat : public TypeInfo {
		Endianness endianness;

		TypeInfoFloat(Endianness endianness, size_t size);
	};

	struct FunctionInput {
		TypeInfo* type = nullptr;
		InternedString name = nullptr;
		bool has_default = false;
		bool is_varargs = false;
		/// <summary>
		/// Marked #escaping, so the function may keep it after returning. This is part of the
		/// function's type.
		/// </summary>
		bool is_escaping = false;
	};

	struct FunctionOutput {
		TypeInfo* type = nullptr;
		InternedString name = nullptr;
	};

	struct TypeInfoFunction : public TypeInfo {
		std::vector<FunctionInput> input;
		std::vector<FunctionOutput> output;
		/// <summary>
		/// Marked #never_returns.
		/// </summary>
		bool never_returns = false;
		/// <summary>
		/// From #calling_convention(...), or null for Hemera's own.
		/// </summary>
		InternedString calling_convention = nullptr;

		TypeInfoFunction();
	};

	struct TypeInfoInteger : public TypeInfo {
		bool is_signed;
		Endianness endianness;

		TypeInfoInteger(bool is_signed, Endianness endianness, size_t size);
	};

	struct TypeInfoPointer : public TypeInfo {
		/// <summary>
		/// What it points to, or null for rawptr.
		/// </summary>
		TypeInfo* base_type;
		bool is_relative;
		bool is_mutable;

		TypeInfoPointer(TypeInfo* base_type, bool is_relative, bool is_mutable, size_t size);
	};

	struct TypeInfoString : public TypeInfo {
		/// <summary>
		/// A cstring: a pointer to null-terminated text, rather than a count and a pointer.
		/// </summary>
		bool is_raw;

		explicit TypeInfoString(bool is_raw);
	};

	struct StructMember {
		InternedString name = nullptr;
		TypeInfo* member_type = nullptr;
		/// <summary>
		/// Byte offset from the start of the struct, 0 for every member of a #union.
		/// </summary>
		size_t offset = 0;
		/// <summary>
		/// It has a default value (= value), which type checking evaluates.
		/// </summary>
		bool has_value = false;
		/// <summary>
		/// Included with using, so its own members can be used as the struct's.
		/// </summary>
		bool is_using = false;
	};

	struct TypeInfoStruct : public TypeInfo {
		InternedString name;
		std::vector<StructMember> members;
		/// <summary>
		/// From #align(n), or 0 for the natural alignment.
		/// </summary>
		size_t requested_alignment = 0;
		/// <summary>
		/// From #scoped. Values hold pointers into the stack, are always local, and can never be
		/// stored on the heap.
		/// </summary>
		bool is_scoped = false;
		/// <summary>
		/// From #packed: no padding, and an alignment of 1 unless #align asks for more.
		/// </summary>
		bool is_packed = false;
		/// <summary>
		/// From #union: every member at offset 0, sharing memory.
		/// </summary>
		bool is_union = false;

		explicit TypeInfoStruct(InternedString name);
	};

	struct UnionVariant {
		InternedString name = nullptr;
		/// <summary>
		/// The types of the variant's values, like int and string for Pair(int, string).
		/// </summary>
		std::vector<TypeInfo*> types;
		/// <summary>
		/// Each value's byte offset from the start of the union, after the tag.
		/// </summary>
		std::vector<size_t> offsets;
	};

	/// <summary>
	/// A tagged union: an unsigned tag at offset 0, the smallest that counts the variants, then
	/// the variant's values laid out like a struct's members, all variants overlapping.
	/// </summary>
	struct TypeInfoUnion : public TypeInfo {
		InternedString name;
		std::vector<UnionVariant> variants;
		TypeInfo* tag_type = nullptr;

		explicit TypeInfoUnion(InternedString name);
	};

	/// <summary>
	/// Lays out a struct whose members' types are complete: sets each member's offset, and the
	/// struct's size, alignment and contains_pointers, and marks it complete.
	/// </summary>
	void lay_out_struct(TypeInfoStruct* type);

	/// <summary>
	/// Lays out a union whose variants' types are complete, the same way.
	/// </summary>
	void lay_out_union(TypeInfoUnion* type);

	/// <summary>
	/// Sets an alias's size and alignment from its base type, once that's complete.
	/// </summary>
	void lay_out_alias(TypeInfoAlias* type);

	/// <summary>
	/// Sets an enum's size and alignment from its backing type.
	/// </summary>
	void lay_out_enum(TypeInfoEnum* type);

	extern TypeInfo* BUILTIN_any;
	extern TypeInfo* BUILTIN_b8;
	extern TypeInfo* BUILTIN_b16;
	extern TypeInfo* BUILTIN_b32;
	extern TypeInfo* BUILTIN_b64;
	extern TypeInfo* BUILTIN_bool;
	extern TypeInfo* BUILTIN_c16;
	extern TypeInfo* BUILTIN_c32;
	extern TypeInfo* BUILTIN_c64;
	extern TypeInfo* BUILTIN_c128;
	extern TypeInfo* BUILTIN_char;
	extern TypeInfo* BUILTIN_cstring;
	extern TypeInfo* BUILTIN_f16;
	extern TypeInfo* BUILTIN_f16be;
	extern TypeInfo* BUILTIN_f16le;
	extern TypeInfo* BUILTIN_f32;
	extern TypeInfo* BUILTIN_f32be;
	extern TypeInfo* BUILTIN_f32le;
	extern TypeInfo* BUILTIN_f64;
	extern TypeInfo* BUILTIN_f64be;
	extern TypeInfo* BUILTIN_f64le;
	extern TypeInfo* BUILTIN_i8;
	extern TypeInfo* BUILTIN_i16;
	extern TypeInfo* BUILTIN_i16be;
	extern TypeInfo* BUILTIN_i16le;
	extern TypeInfo* BUILTIN_i32;
	extern TypeInfo* BUILTIN_i32be;
	extern TypeInfo* BUILTIN_i32le;
	extern TypeInfo* BUILTIN_i64;
	extern TypeInfo* BUILTIN_i64be;
	extern TypeInfo* BUILTIN_i64le;
	extern TypeInfo* BUILTIN_i128;
	extern TypeInfo* BUILTIN_i128be;
	extern TypeInfo* BUILTIN_i128le;
	extern TypeInfo* BUILTIN_int;
	extern TypeInfo* BUILTIN_q32;
	extern TypeInfo* BUILTIN_q64;
	extern TypeInfo* BUILTIN_q128;
	extern TypeInfo* BUILTIN_q256;
	extern TypeInfo* BUILTIN_rawptr;
	extern TypeInfo* BUILTIN_string;
	extern TypeInfo* BUILTIN_type;
	extern TypeInfo* BUILTIN_u8;
	extern TypeInfo* BUILTIN_u16;
	extern TypeInfo* BUILTIN_u16be;
	extern TypeInfo* BUILTIN_u16le;
	extern TypeInfo* BUILTIN_u32;
	extern TypeInfo* BUILTIN_u32be;
	extern TypeInfo* BUILTIN_u32le;
	extern TypeInfo* BUILTIN_u64;
	extern TypeInfo* BUILTIN_u64be;
	extern TypeInfo* BUILTIN_u64le;
	extern TypeInfo* BUILTIN_u128;
	extern TypeInfo* BUILTIN_u128be;
	extern TypeInfo* BUILTIN_u128le;
	extern TypeInfo* BUILTIN_uint;
	extern TypeInfo* BUILTIN_uintptr;
	extern TypeInfo* BUILTIN_usize;

	extern TypeInfo* BUILTIN_void;
	extern TypeInfo* BUILTIN_poisoned_value;

	/// <summary>
	/// The builtin type with this name, like int or string, or null. ptr and the relative
	/// pointers aren't types by themselves, only with what they point to.
	/// </summary>
	TypeInfo* builtin_type(std::string_view name);

	std::string to_string(TypeInfo const* type);

	/// <summary>
	/// Check if two types are the same: aliases that aren't distinct are the same as what they
	/// alias (docs/types.md, Alias Equality). Null pointers are never equal to anything.
	/// </summary>
	bool same_type(TypeInfo const* a, TypeInfo const* b);

	/// <summary>
	/// Check if the first type can be implicitly converted to the second (docs/types.md, Implicit
	/// Casting). A type can convert to itself.
	/// </summary>
	bool can_implicitly_convert_to(TypeInfo const* from, TypeInfo const* to);

	/// <summary>
	/// If the provided type is an alias, look up the true base type, ignoring anything to do with
	/// distinct aliases.
	/// </summary>
	TypeInfo const* get_base_type(TypeInfo const* type);

	/// <summary>
	/// If the provided type is an alias, look up the base type until we find something that is
	/// either not an alias, or the nearest distinct alias this refers to.
	/// </summary>
	TypeInfo const* get_base_type_or_alias(TypeInfo const* type);

	void initialize_builtin_types();
}

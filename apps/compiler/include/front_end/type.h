#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "memory/allocator.h"

namespace hemera {
	namespace ast {
		struct Node;
	}


	/*
	 * Type information: what the compiler knows about each type, including its memory layout
	 * (docs/types.md, Memory Layout). Sizes and alignments are in bytes, for a 64-bit target.
	 */

	enum class TypeInfoVariant : uint8_t {
		ALIAS,
		ANY,
		/// <summary>
		/// A stand-in for a constrained generic's type parameter, while its body is checked against what
		/// its constraints promise (docs/types.md, Checked Bodies). Never generated.
		/// </summary>
		ARCHETYPE,
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
		/// <summary>
		/// A SIMD vector, vector[T, n], or bits of a vector register's size, v128 to v512 (docs/types.md, Vectors).
		/// </summary>
		VECTOR,
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

	/// <summary>
	/// What a constraint promises about a type parameter, one bit each. Integers and floats are
	/// numbers, and numbers have == and <.
	/// </summary>
	enum Capability : uint32_t {
		CAPABILITY_EQUALITY = 1u << 0,
		CAPABILITY_ORDERING = 1u << 1,
		CAPABILITY_ARITHMETIC = 1u << 2,
		CAPABILITY_INTEGER = 1u << 3,
		CAPABILITY_SIGNED = 1u << 4,
		CAPABILITY_UNSIGNED = 1u << 5,
		CAPABILITY_FLOAT = 1u << 6,
		// Given with mut, so ptr[T] can change what it points to
		CAPABILITY_MUTABLE = 1u << 7,
	};

	/// <summary>
	/// A constrained generic's type parameter while its body is checked once, before any instance
	/// (docs/types.md, Checked Bodies): it has only what the constraints promise. Its layout isn't
	/// known, so it's taken as the worst: it may hold pointers.
	/// </summary>
	struct TypeInfoArchetype : public TypeInfo {
		/// <summary>
		/// The parameter's name, like T, and the generic's, for messages.
		/// </summary>
		InternedString name;
		InternedString generic;
		/// <summary>
		/// The generic declaration it stands in for a parameter of.
		/// </summary>
		const struct Declaration* owner = nullptr;
		uint32_t capabilities = 0;
		/// <summary>
		/// From require_field: each field it has, with its type.
		/// </summary>
		std::vector<std::pair<InternedString, TypeInfo*>> fields;
		/// <summary>
		/// From require_view: it's an array, view or dynamic array of this.
		/// </summary>
		TypeInfo* element = nullptr;

		TypeInfoArchetype(InternedString name, InternedString generic);
	};

	struct TypeInfoAlias : public TypeInfo {
		TypeInfo* base_type;
		InternedString name;
		bool distinct;
		/// <summary>
		/// A generic argument written with mut, like the mut Buffer in SharedPtr[mut Buffer]: the same type as
		/// what it aliases, except that pointers to it in the generic can change it (docs/types.md, Mutability).
		/// </summary>
		bool mutable_argument = false;
		/// <summary>
		/// From #secret, on a distinct alias: its values are secrets (docs/memory.md, Secrets).
		/// </summary>
		bool is_secret = false;

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
		/// <summary>
		/// A view whose elements can be changed through it, mut T[] (docs/types.md, Mutability). A static or
		/// dynamic array's elements change as whatever holds the array does, so this is only ever a view's.
		/// </summary>
		bool is_mutable = false;

		TypeInfoArray(TypeInfo* element_type, ArrayType array_type, size_t count);
	};

	/// <summary>
	/// vector[T, n]: count lanes of an integer, float or bool, worked on together. Or, with is_bits,
	/// v128, v256 or v512: bits a vector register holds, lanes of u64, which bit_cast to any vector of
	/// their size and only take the bitwise operators.
	/// </summary>
	struct TypeInfoVector : public TypeInfo {
		TypeInfo* element_type;
		size_t count;
		bool is_bits;

		TypeInfoVector(TypeInfo* element_type, size_t count, bool is_bits);
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
		/// <summary>
		/// The default's expression, and the package whose names it sees: where the signature giving it was
		/// written, a function's or a function type's (docs/functions.md, Defaults in Function Types). A call
		/// that leaves the parameter out runs it, in the caller. Not part of the type's identity.
		/// </summary>
		ast::Node* default_value = nullptr;
		InternedString default_package = nullptr;
		InternedString default_file = nullptr;
		/// <summary>
		/// The default is a function's own, checked with its body. Otherwise it's a function type's, checked on
		/// its own the first time a call leaves it out (NameRegistry::type_defaults).
		/// </summary>
		bool default_in_body = false;
		bool is_varargs = false;
		/// <summary>
		/// Marked #escaping, so the function may keep it after returning. This is part of the
		/// function's type.
		/// </summary>
		bool is_escaping = false;
		/// <summary>
		/// #crosses_threads: what it's given goes to another thread, like a new thread's data, so it can't be
		/// #thread_bound (docs/multitasking.md, Values That Stay on Their Thread).
		/// </summary>
		bool crosses_threads = false;
	};

	struct FunctionOutput {
		TypeInfo* type = nullptr;
		InternedString name = nullptr;
		/// <summary>
		/// Marked #unrestricted, so it never points into the stack, whatever the function was given,
		/// like memory from an allocator. Part of the function's type.
		/// </summary>
		bool is_unrestricted = false;
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
		/// <summary>
		/// Marked #no_context: called without a context, and without a stack check, since it may be
		/// entered without a carrier block; the body sets both up (docs/calling_convention.md).
		/// </summary>
		bool no_context = false;

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
		/// It has a default value (= value), a compile-time constant worked out when the struct is
		/// declared: default_integer for an integer or a boolean (0 or 1), or default_member for an
		/// enum member, by name.
		/// </summary>
		bool has_value = false;
		/// <summary>
		/// Included with using, so its own members can be used as the struct's.
		/// </summary>
		bool is_using = false;
		int64_t default_integer = 0;
		std::string default_member;
	};

	struct TypeInfoStruct : public TypeInfo {
		InternedString name;
		std::vector<StructMember> members;
		/// <summary>
		/// For an instance of a generic struct, its declaration, with the generic and the arguments.
		/// </summary>
		const struct Declaration* instance = nullptr;
		/// <summary>
		/// From #owned(release): each value has one owner, which releases it or moves it on
		/// (docs/memory.md, Owned Types). The function that releases one, by name, as written:
		/// release_package is the package's local name for package.release, or null.
		/// </summary>
		bool is_owned = false;
		InternedString release_package = nullptr;
		InternedString release_name = nullptr;
		/// <summary>
		/// From #thread_bound: a value can't leave the thread it was made on, like one counted without atomics.
		/// </summary>
		bool is_thread_bound = false;
		/// <summary>
		/// From #secret: its values are secrets, so they can't decide timing (docs/memory.md, Secrets).
		/// </summary>
		bool is_secret = false;
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
		/// From #unrestricted. Values never point into the stack, so they can be stored anywhere, and
		/// what a function makes with one isn't held to the stack's lifetimes.
		/// </summary>
		bool is_unrestricted = false;
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
		/// <summary>
		/// An optional of a pointer that's never null (ptr[T], cstring, a function): just the
		/// pointer, null for None, with no tag (docs/types.md, Optional Types).
		/// </summary>
		bool null_is_none = false;

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
	extern TypeInfo* BUILTIN_v128;
	extern TypeInfo* BUILTIN_v256;
	extern TypeInfo* BUILTIN_v512;

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
	/// Whether a value of type has one owner (docs/memory.md, Owned Types): a struct marked #owned, or
	/// anything holding one in place, in a static or dynamic array, or in a union's payload.
	/// </summary>
	bool is_owned(TypeInfo const* type);

	/// <summary>
	/// The #thread_bound type a value of type can reach, through its fields, arrays, unions, pointers and views,
	/// or null if there's none: then it can be given to another thread.
	/// </summary>
	TypeInfo const* thread_bound_part(TypeInfo const* type);

	/// <summary>
	/// Whether values of type are secrets: a #secret struct or distinct alias, an alias of one, or an
	/// array or vector of them (docs/memory.md, Secrets).
	/// </summary>
	bool is_secret_type(TypeInfo const* type);

	/// <summary>
	/// Whether a value of type holds or reaches a secret, through pointers too, like a ptr[Key] parameter.
	/// </summary>
	bool reaches_secret(TypeInfo const* type);

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

	/// <summary>
	/// What a parameter of a SlopOS program's entry is given from its startup grants (docs/compilation.md,
	/// Entry Parameters): the name of its kind, a distinct alias's (DebugLog) or a struct's without its
	/// arguments (Channel), and whether it's an optional, which a missing grant leaves None.
	/// </summary>
	struct EntryGrant {
		/// <summary>
		/// Empty for a type no grant can be: anything but a 4-byte handle type, or an optional of one.
		/// </summary>
		std::string kind;
		bool optional = false;
	};

	EntryGrant entry_grant_of(TypeInfo const* type);

	void initialize_builtin_types();
}

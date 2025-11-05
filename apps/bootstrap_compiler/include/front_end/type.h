#pragma once

#include <cstdint>

#include "memory/allocator.h"

namespace hemera {

	struct TypeInfo;

	namespace builtin {
		struct _any {
			TypeInfo* type;
			void* value;
		};
		using _b8 = uint8_t;
		using _b16 = uint16_t;
		using _b32 = uint32_t;
		using _b64 = uint64_t;
		using _bool = bool;
		struct _c16 {
			uint8_t real;
			uint8_t imaginary;
		};
		struct _c32 {
			uint16_t real;
			uint16_t imaginary;
		};
		struct _c64 {
			uint32_t real;
			uint32_t imaginary;
		};
		struct _c128 {
			uint64_t real;
			uint64_t imaginary;
		};
		using _char = char8_t;
		using _cstring = char*;
		struct _f16 {}; // TODO(ches) create/complete this
		struct _f16be {}; // TODO(ches) create/complete this
		struct _f16le {}; // TODO(ches) create/complete this
		static_assert(sizeof(float) == 4);
		using _f32 = float;
		struct _f32be {}; // TODO(ches) create/complete this
		struct _f32le {}; // TODO(ches) create/complete this
		static_assert(sizeof(double) == 8);
		using _f64 = double;
		struct _f64be {}; // TODO(ches) create/complete this
		struct _f64le {}; // TODO(ches) create/complete this
		using _i8 = int8_t;
		using _i16 = int16_t;
		struct _i16be {
			int8_t byte_1;
			uint8_t byte_2;
		};
		struct _i16le {
			uint8_t byte_2;
			int8_t byte_1;
		};
		using _i32 = int32_t;
		struct _i32be {
			int8_t byte_1;
			uint8_t byte_2;
			uint8_t byte_3;
			uint8_t byte_4;
		};
		struct _i32le {
			uint8_t byte_4;
			uint8_t byte_3;
			uint8_t byte_2;
			int8_t byte_1;
		};
		using _i64 = int64_t;
		struct _i64be {
			int8_t byte_1;
			uint8_t byte_2;
			uint8_t byte_3;
			uint8_t byte_4;
			uint8_t byte_5;
			uint8_t byte_6;
			uint8_t byte_7;
			uint8_t byte_8;
		};
		struct _i64le {
			uint8_t byte_8;
			uint8_t byte_7;
			uint8_t byte_6;
			uint8_t byte_5;
			uint8_t byte_4;
			uint8_t byte_3;
			uint8_t byte_2;
			int8_t byte_1;
		};
		struct _i128be {
			int8_t byte_1;
			uint8_t byte_2;
			uint8_t byte_3;
			uint8_t byte_4;
			uint8_t byte_5;
			uint8_t byte_6;
			uint8_t byte_7;
			uint8_t byte_8;
			uint8_t byte_9;
			uint8_t byte_10;
			uint8_t byte_11;
			uint8_t byte_12;
			uint8_t byte_13;
			uint8_t byte_14;
			uint8_t byte_15;
			uint8_t byte_16;
		};
		struct _i128le {
			uint8_t byte_16;
			uint8_t byte_15;
			uint8_t byte_14;
			uint8_t byte_13;
			uint8_t byte_12;
			uint8_t byte_11;
			uint8_t byte_10;
			uint8_t byte_9;
			uint8_t byte_8;
			uint8_t byte_7;
			uint8_t byte_6;
			uint8_t byte_5;
			uint8_t byte_4;
			uint8_t byte_3;
			uint8_t byte_2;
			int8_t byte_1;
		};
		using _i128 = _i128le; // TODO(ches) is this right?
		static_assert(sizeof(int64_t) == sizeof(uintptr_t));
		using _int = int64_t;
		struct _ptr {
			TypeInfo* pointing_to_type;
			void* pointer;
		};
		struct _q32 {
			uint8_t a;
			uint8_t b;
			uint8_t c;
			uint8_t d;
		};
		struct _q64 {
			uint16_t a;
			uint16_t b;
			uint16_t c;
			uint16_t d;
		};
		struct _q128 {
			uint32_t a;
			uint32_t b;
			uint32_t c;
			uint32_t d;
		};
		struct _q256 {
			uint64_t a;
			uint64_t b;
			uint64_t c;
			uint64_t d;
		};
		using _rawptr = void*;
		struct _relptr8 {

		}; // TODO(ches) create/complete this
		struct _relptr16 {}; // TODO(ches) create/complete this
		struct _relptr32 {}; // TODO(ches) create/complete this
		struct _relptr64 {}; // TODO(ches) create/complete this
		struct _string {
			_int size;
			_char* data;
		};
		using _type = TypeInfo*;
		using _u8 = uint8_t;
		using _u16 = uint16_t;
		struct _u16be {
			uint8_t byte_1;
			uint8_t byte_2;
		};
		struct _u16le {
			uint8_t byte_2;
			uint8_t byte_1;
		};
		using _u32 = uint32_t;
		struct _u32be {
			uint8_t byte_1;
			uint8_t byte_2;
			uint8_t byte_3;
			uint8_t byte_4;
		};
		struct _u32le {
			uint8_t byte_4;
			uint8_t byte_3;
			uint8_t byte_2;
			uint8_t byte_1;
		};
		using _u64 = uint64_t;
		struct _u64be {
			uint8_t byte_1;
			uint8_t byte_2;
			uint8_t byte_3;
			uint8_t byte_4;
			uint8_t byte_5;
			uint8_t byte_6;
			uint8_t byte_7;
			uint8_t byte_8;
		};
		struct _u64le {
			uint8_t byte_8;
			uint8_t byte_7;
			uint8_t byte_6;
			uint8_t byte_5;
			uint8_t byte_4;
			uint8_t byte_3;
			uint8_t byte_2;
			uint8_t byte_1;
		};
		struct _u128be {
			uint8_t byte_1;
			uint8_t byte_2;
			uint8_t byte_3;
			uint8_t byte_4;
			uint8_t byte_5;
			uint8_t byte_6;
			uint8_t byte_7;
			uint8_t byte_8;
			uint8_t byte_9;
			uint8_t byte_10;
			uint8_t byte_11;
			uint8_t byte_12;
			uint8_t byte_13;
			uint8_t byte_14;
			uint8_t byte_15;
			uint8_t byte_16;
		};
		struct _u128le {
			uint8_t byte_16;
			uint8_t byte_15;
			uint8_t byte_14;
			uint8_t byte_13;
			uint8_t byte_12;
			uint8_t byte_11;
			uint8_t byte_10;
			uint8_t byte_9;
			uint8_t byte_8;
			uint8_t byte_7;
			uint8_t byte_6;
			uint8_t byte_5;
			uint8_t byte_4;
			uint8_t byte_3;
			uint8_t byte_2;
			uint8_t byte_1;
		};
		using _u128 = _u128le; // TODO(ches) is this right?
		using _uint = uintptr_t;
		using _uintptr = uintptr_t;
	}
	
	enum class ArrayType {
		STATIC,
		DYNAMIC,
		VIEW,
	};

	enum class Endianness : uint8_t {
		BIG,
		LITTLE,
		SYSTEM,
	};

	struct ArrayDimension {
		ArrayType type;
		int count;
	};

	enum class TypeInfoVariant {
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

	struct TypeInfo {
		TypeInfoVariant variant;
		char _padding[4] = { 0 };
		size_t size;

		TypeInfo(TypeInfoVariant variant, size_t size);
		~TypeInfo();
	};

	struct TypeInfoAlias : public TypeInfo {
		TypeInfo* base_type;
		InternedString name;
		bool distinct;
		char _padding[7] = { 0 };
		
		/// <summary>
		/// Create a new type alias.
		/// </summary>
		/// <param name="base_type">The type this is an alias of, must be a
		/// valid type info pointer.</param>
		/// <param name="name">The name of the alias.</param>
		/// <param name="distinct">Whether this is a distinct type.</param>
		TypeInfoAlias(TypeInfo* base_type, InternedString name, bool distinct);
		~TypeInfoAlias();
	};

	struct TypeInfoArray : public TypeInfo {
		TypeInfo* base_type;
		MyVector<ArrayDimension> dimensions;

		TypeInfoArray(TypeInfo* base_type, MyVector<ArrayDimension>&& dimensions);
		~TypeInfoArray();
	};

	struct TypeInfoEnum : public TypeInfo {
		InternedString name;
		MyVector<InternedString> members;

		TypeInfoEnum(InternedString name, size_t size);
		~TypeInfoEnum();
	};
	
	struct TypeInfoFloat : public TypeInfo {
		Endianness endianness;
		char _padding[7] = { 0 };

		TypeInfoFloat(Endianness endianness, size_t size);
		~TypeInfoFloat();
	};

	struct FunctionInput {
		TypeInfo* type;
		InternedString name;
		bool is_varargs;
		char _padding[7] = { 0 };
	};

	struct FunctionOutput {
		TypeInfo* type;
	};

	struct TypeInfoFunction : public TypeInfo {
		MyVector<FunctionInput> input;
		MyVector<FunctionOutput> output;

		TypeInfoFunction();
		~TypeInfoFunction();
	};

	struct TypeInfoInteger : public TypeInfo {
		bool is_signed;
		Endianness endianness;
		char _padding[6] = { 0 };

		TypeInfoInteger(bool is_signed, Endianness endianness, size_t size);
		~TypeInfoInteger();
	};

	struct TypeInfoPointer : public TypeInfo {
		TypeInfo* base_type;
		bool is_relative;
		bool is_mutable;
		char _padding[6] = { 0 };

		TypeInfoPointer(TypeInfo* base_type, bool is_relative, bool is_mutable,
			size_t size);
		~TypeInfoPointer();
	};

	struct TypeInfoString : public TypeInfo {
		bool raw;
		char _padding[7] = { 0 };

		TypeInfoString(bool raw);
		~TypeInfoString();
	};

	struct StructMember {
		InternedString name;
		TypeInfo* type;
		builtin::_any value;
		bool has_value;
		bool is_using;
		char _padding[6] = { 0 };
	};

	struct TypeInfoStruct : public TypeInfo {
		InternedString name;
		MyVector<StructMember> members;

		TypeInfoStruct(InternedString name, size_t size);
		~TypeInfoStruct();
	};
	
	struct TypeInfoUnion : public TypeInfo {
		InternedString name;
		MyMap<InternedString, MyVector<InternedString>> variants;

		TypeInfoUnion(InternedString name, size_t size);
		~TypeInfoUnion();
	};

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
	extern TypeInfo* BUILTIN_ptr;
	extern TypeInfo* BUILTIN_q32;
	extern TypeInfo* BUILTIN_q64;
	extern TypeInfo* BUILTIN_q128;
	extern TypeInfo* BUILTIN_q256;
	extern TypeInfo* BUILTIN_rawptr;
	//extern TypeInfo* BUILTIN_relptr8; //TODO(ches) these are polymorphic?
	//extern TypeInfo* BUILTIN_relptr16; //TODO(ches) these are polymorphic?
	//extern TypeInfo* BUILTIN_relptr32; //TODO(ches) these are polymorphic?
	//extern TypeInfo* BUILTIN_relptr64; //TODO(ches) these are polymorphic?
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

	extern TypeInfo* BUILTIN_void;
	extern TypeInfo* BUILTIN_poisoned_value;

	std::string to_string(TypeInfo const* type);

	/// <summary>
	/// Check if two types are the same.
	/// 
	/// A few notes about the comparison:
	/// 
	/// Null pointers are never equal to anything, even other null pointers.
	/// </summary>
	/// <param name="a">The first type.</param>
	/// <param name="b">The second type.</param>
	/// <returns>If the types are the same.</returns>
	bool same_type(TypeInfo const* a, TypeInfo const* b);

	/// <summary>
	/// Check if the first type can be implicitly converted to the second 
	/// type.
	/// 
	/// A few notes about the comparison:
	/// 
	/// Null pointers can be converted, even from/to other null pointers.
	/// A type can convert to itself, since saying that it can't would be more
	/// confusing.
	/// Primitive types can convert to the same type (floating point to 
	/// floating point, signed integer to signed integer) of a larger size.
	/// 
	/// </summary>
	/// <param name="from">The type we are converting from.</param>
	/// <param name="to">The type we are converting to.</param>
	/// <returns>Whether implicit conversion is possible.</returns>
	bool can_implicitly_convert_to(TypeInfo const* from, TypeInfo const* to);
}
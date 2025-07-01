#pragma once

#include "memory/allocator.h"

namespace hemera {
	
	enum class ArrayType {
		STATIC,
		DYNAMIC,
		VIEW,
	};

	struct ArrayDimension {
		ArrayType type;
		int count;
	};

	struct Type {
		/// <summary>
		/// The base type, if there is one. Will generally be nullptr unless
		/// it's a pointer or array.
		/// </summary>
		const Type* const base_type;
		const MyVector<ArrayDimension> dims;
		const bool is_mutable;
		const bool is_pointer;
		const char padding[6] = { 0 };

		Type(Type* base_type = nullptr, MyVector<ArrayDimension>&& dims = {},
			bool is_mutable = false, bool is_pointer = false);
		Type(const Type&) = delete;
		Type(Type&&) = delete;
		Type& operator=(const Type&) = delete;
		Type& operator=(Type&&) = delete;
		~Type();
	};

	extern Type* BUILTIN_any;
	extern Type* BUILTIN_b8;
	extern Type* BUILTIN_b16;
	extern Type* BUILTIN_b32;
	extern Type* BUILTIN_b64;
	extern Type* BUILTIN_bool;
	extern Type* BUILTIN_c16;
	extern Type* BUILTIN_c32;
	extern Type* BUILTIN_c64;
	extern Type* BUILTIN_c128;
	extern Type* BUILTIN_char;
	extern Type* BUILTIN_cstring;
	extern Type* BUILTIN_f16;
	extern Type* BUILTIN_f16be;
	extern Type* BUILTIN_f16le;
	extern Type* BUILTIN_f32;
	extern Type* BUILTIN_f32be;
	extern Type* BUILTIN_f32le;
	extern Type* BUILTIN_f64;
	extern Type* BUILTIN_f64be;
	extern Type* BUILTIN_f64le;
	extern Type* BUILTIN_i8;
	extern Type* BUILTIN_i16;
	extern Type* BUILTIN_i16be;
	extern Type* BUILTIN_i16le;
	extern Type* BUILTIN_i32;
	extern Type* BUILTIN_i32be;
	extern Type* BUILTIN_i32le;
	extern Type* BUILTIN_i64;
	extern Type* BUILTIN_i64be;
	extern Type* BUILTIN_i64le;
	extern Type* BUILTIN_i128;
	extern Type* BUILTIN_i128be;
	extern Type* BUILTIN_i128le;
	extern Type* BUILTIN_int;
	extern Type* BUILTIN_ptr;
	extern Type* BUILTIN_q32;
	extern Type* BUILTIN_q64;
	extern Type* BUILTIN_q128;
	extern Type* BUILTIN_q256;
	extern Type* BUILTIN_rawptr;
	extern Type* BUILTIN_relptr8;
	extern Type* BUILTIN_relptr16;
	extern Type* BUILTIN_relptr32;
	extern Type* BUILTIN_relptr64;
	extern Type* BUILTIN_string;
	extern Type* BUILTIN_type;
	extern Type* BUILTIN_u8;
	extern Type* BUILTIN_u16;
	extern Type* BUILTIN_u16be;
	extern Type* BUILTIN_u16le;
	extern Type* BUILTIN_u32;
	extern Type* BUILTIN_u32be;
	extern Type* BUILTIN_u32le;
	extern Type* BUILTIN_u64;
	extern Type* BUILTIN_u64be;
	extern Type* BUILTIN_u64le;
	extern Type* BUILTIN_u128;
	extern Type* BUILTIN_u128be;
	extern Type* BUILTIN_u128le;
	extern Type* BUILTIN_uint;
	extern Type* BUILTIN_uintptr;
}
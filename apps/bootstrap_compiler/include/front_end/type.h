#pragma once

#include <cstdint>

#include "front_end/type_id.h"
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
		const bool is_varargs;
		const char padding[5] = { 0 };

		Type(Type* base_type = nullptr, MyVector<ArrayDimension>&& dims = {},
			bool is_mutable = false, bool is_pointer = false, 
			bool is_varargs = false);
		Type(const Type&) = delete;
		Type(Type&&) = delete;
		Type& operator=(const Type&) = delete;
		Type& operator=(Type&&) = delete;
		~Type();
	};

	namespace builtin {
		struct _any {}; // TODO(ches) create/complete this
		struct _b8 {}; // TODO(ches) create/complete this
		struct _b16 {}; // TODO(ches) create/complete this
		struct _b32 {}; // TODO(ches) create/complete this
		struct _b64 {}; // TODO(ches) create/complete this
		struct _bool {}; // TODO(ches) create/complete this
		struct _c16 {}; // TODO(ches) create/complete this
		struct _c32 {}; // TODO(ches) create/complete this
		struct _c64 {}; // TODO(ches) create/complete this
		struct _c128 {}; // TODO(ches) create/complete this
		struct _char {}; // TODO(ches) create/complete this
		struct _cstring {}; // TODO(ches) create/complete this
		struct _f16 {}; // TODO(ches) create/complete this
		struct _f16be {}; // TODO(ches) create/complete this
		struct _f16le {}; // TODO(ches) create/complete this
		using _f32 = float;
		struct _f32be {}; // TODO(ches) create/complete this
		struct _f32le {}; // TODO(ches) create/complete this
		using _f64 = double;
		struct _f64be {}; // TODO(ches) create/complete this
		struct _f64le {}; // TODO(ches) create/complete this
		using _i8 = int8_t;
		using _i16 = int16_t;
		struct _i16be {}; // TODO(ches) create/complete this
		struct _i16le {}; // TODO(ches) create/complete this
		using _i32 = int32_t;
		struct _i32be {}; // TODO(ches) create/complete this
		struct _i32le {}; // TODO(ches) create/complete this
		using _i64 = int64_t;
		struct _i64be {}; // TODO(ches) create/complete this
		struct _i64le {}; // TODO(ches) create/complete this
		struct _i128 {}; // TODO(ches) create/complete this
		struct _i128be {}; // TODO(ches) create/complete this
		struct _i128le {}; // TODO(ches) create/complete this
		using _int = long long;
		struct _ptr {
			TypeID pointing_to_type;
			void* pointer;
		};
		struct _q32 {}; // TODO(ches) create/complete this
		struct _q64 {}; // TODO(ches) create/complete this
		struct _q128 {}; // TODO(ches) create/complete this
		struct _q256 {}; // TODO(ches) create/complete this
		using _rawptr = void*;
		struct _relptr8 {}; // TODO(ches) create/complete this
		struct _relptr16 {}; // TODO(ches) create/complete this
		struct _relptr32 {}; // TODO(ches) create/complete this
		struct _relptr64 {}; // TODO(ches) create/complete this
		struct _string {}; // TODO(ches) create/complete this
		using _type = Type;
		using _u8 = uint8_t;
		using _u16 = uint16_t;
		struct _u16be {}; // TODO(ches) create/complete this
		struct _u16le {}; // TODO(ches) create/complete this
		using _u32 = uint32_t;
		struct _u32be {}; // TODO(ches) create/complete this
		struct _u32le {}; // TODO(ches) create/complete this
		using _u64 = uint64_t;
		struct _u64be {}; // TODO(ches) create/complete this
		struct _u64le {}; // TODO(ches) create/complete this
		struct _u128 {}; // TODO(ches) create/complete this
		struct _u128be {}; // TODO(ches) create/complete this
		struct _u128le {}; // TODO(ches) create/complete this
		using _uint = uintptr_t;
		using _uintptr = uintptr_t;
	}

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
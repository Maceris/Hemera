#include "front_end/type.h"

namespace hemera {
	Type::Type(Type* base_type, MyVector<ArrayDimension>&& dims,
		bool is_mutable, bool is_pointer)
		: base_type{ base_type }
		, dims{ std::move(dims) }
		, is_mutable{ is_mutable }
		, is_pointer{ is_pointer }
	{}
	Type::~Type() = default;

	Type* BUILTIN_any = new Type();
	Type* BUILTIN_b8 = new Type();
	Type* BUILTIN_b16 = new Type();
	Type* BUILTIN_b32 = new Type();
	Type* BUILTIN_b64 = new Type();
	Type* BUILTIN_bool = new Type();
	Type* BUILTIN_c16 = new Type();
	Type* BUILTIN_c32 = new Type();
	Type* BUILTIN_c64 = new Type();
	Type* BUILTIN_c128 = new Type();
	Type* BUILTIN_char = new Type();
	Type* BUILTIN_cstring = new Type();
	Type* BUILTIN_f16 = new Type();
	Type* BUILTIN_f16be = new Type();
	Type* BUILTIN_f16le = new Type();
	Type* BUILTIN_f32 = new Type();
	Type* BUILTIN_f32be = new Type();
	Type* BUILTIN_f32le = new Type();
	Type* BUILTIN_f64 = new Type();
	Type* BUILTIN_f64be = new Type();
	Type* BUILTIN_f64le = new Type();
	Type* BUILTIN_i8 = new Type();
	Type* BUILTIN_i16 = new Type();
	Type* BUILTIN_i16be = new Type();
	Type* BUILTIN_i16le = new Type();
	Type* BUILTIN_i32 = new Type();
	Type* BUILTIN_i32be = new Type();
	Type* BUILTIN_i32le = new Type();
	Type* BUILTIN_i64 = new Type();
	Type* BUILTIN_i64be = new Type();
	Type* BUILTIN_i64le = new Type();
	Type* BUILTIN_i128 = new Type();
	Type* BUILTIN_i128be = new Type();
	Type* BUILTIN_i128le = new Type();
	Type* BUILTIN_int = new Type();
	Type* BUILTIN_ptr = new Type();
	Type* BUILTIN_q32 = new Type();
	Type* BUILTIN_q64 = new Type();
	Type* BUILTIN_q128 = new Type();
	Type* BUILTIN_q256 = new Type();
	Type* BUILTIN_rawptr = new Type();
	Type* BUILTIN_relptr8 = new Type();
	Type* BUILTIN_relptr16 = new Type();
	Type* BUILTIN_relptr32 = new Type();
	Type* BUILTIN_relptr64 = new Type();
	Type* BUILTIN_string = new Type();
	Type* BUILTIN_type = new Type();
	Type* BUILTIN_u8 = new Type();
	Type* BUILTIN_u16 = new Type();
	Type* BUILTIN_u16be = new Type();
	Type* BUILTIN_u16le = new Type();
	Type* BUILTIN_u32 = new Type();
	Type* BUILTIN_u32be = new Type();
	Type* BUILTIN_u32le = new Type();
	Type* BUILTIN_u64 = new Type();
	Type* BUILTIN_u64be = new Type();
	Type* BUILTIN_u64le = new Type();
	Type* BUILTIN_u128 = new Type();
	Type* BUILTIN_u128be = new Type();
	Type* BUILTIN_u128le = new Type();
	Type* BUILTIN_uint = new Type();
	Type* BUILTIN_uintptr = new Type();
}
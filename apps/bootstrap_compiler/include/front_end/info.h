#pragma once

#include <cstdint>

#include "front_end/type_id.h"
#include "front_end/type.h"
#include "memory/allocator.h"

namespace hemera {

	enum class ValueType {
		BUILTIN_any,
		BUILTIN_b8,
		BUILTIN_b16,
		BUILTIN_b32,
		BUILTIN_b64,
		BUILTIN_bool,
		BUILTIN_c16,
		BUILTIN_c32,
		BUILTIN_c64,
		BUILTIN_c128,
		BUILTIN_char,
		BUILTIN_cstring,
		BUILTIN_f16,
		BUILTIN_f16be,
		BUILTIN_f16le,
		BUILTIN_f32,
		BUILTIN_f32be,
		BUILTIN_f32le,
		BUILTIN_f64,
		BUILTIN_f64be,
		BUILTIN_f64le,
		BUILTIN_i8,
		BUILTIN_i16,
		BUILTIN_i16be,
		BUILTIN_i16le,
		BUILTIN_i32,
		BUILTIN_i32be,
		BUILTIN_i32le,
		BUILTIN_i64,
		BUILTIN_i64be,
		BUILTIN_i64le,
		BUILTIN_i128,
		BUILTIN_i128be,
		BUILTIN_i128le,
		BUILTIN_int,
		BUILTIN_ptr,
		BUILTIN_q32,
		BUILTIN_q64,
		BUILTIN_q128,
		BUILTIN_q256,
		BUILTIN_rawptr,
		BUILTIN_relptr8,
		BUILTIN_relptr16,
		BUILTIN_relptr32,
		BUILTIN_relptr64,
		BUILTIN_string,
		BUILTIN_type,
		BUILTIN_u8,
		BUILTIN_u16,
		BUILTIN_u16be,
		BUILTIN_u16le,
		BUILTIN_u32,
		BUILTIN_u32be,
		BUILTIN_u32le,
		BUILTIN_u64,
		BUILTIN_u64be,
		BUILTIN_u64le,
		BUILTIN_u128,
		BUILTIN_u128be,
		BUILTIN_u128le,
		BUILTIN_uint,
		BUILTIN_uintptr,
		FUNCTION_DEFINITION,
		STRUCT_DEFINITION,
		TYPE_ALIAS,
		UNION_DEFINITION,
	};

	struct Pointer {
		TypeID pointing_to_type;
		void* pointer;
	};

	struct TypeAlias {
		TypeID type;
		bool distinct;
	};

	union ValueData {
		builtin::_any _any;
		builtin::_b8 _b8;
		builtin::_b16 _b16;
		builtin::_b32 _b32;
		builtin::_b64 _b64;
		builtin::_bool _bool;
		builtin::_c16 _c16;
		builtin::_c32 _c32;
		builtin::_c64 _c64;
		builtin::_c128 _c128;
		builtin::_char _char;
		builtin::_cstring _cstring;
		builtin::_f16 _f16;
		builtin::_f16be _f16be;
		builtin::_f16le _f16le;
		builtin::_f32 _f32;
		builtin::_f32be _f32be;
		builtin::_f32le _f32le;
		builtin::_f64 _f64;
		builtin::_f64be _f64be;
		builtin::_f64le _f64le;
		builtin::_i8 _i8;
		builtin::_i16 _i16;
		builtin::_i16be _i16be;
		builtin::_i16le _i16le;
		builtin::_i32 _i32;
		builtin::_i32be _i32be;
		builtin::_i32le _i32le;
		builtin::_i64 _i64;
		builtin::_i64be _i64be;
		builtin::_i64le _i64le;
		builtin::_i128 _i128;
		builtin::_i128be _i128be;
		builtin::_i128le _i128le;
		builtin::_int _int;
		builtin::_ptr _ptr;
		builtin::_q32 _q32;
		builtin::_q64 _q64;
		builtin::_q128 _q128;
		builtin::_q256 _q256;
		builtin::_rawptr _rawptr;
		builtin::_relptr8 _relptr8;
		builtin::_relptr16 _relptr16;
		builtin::_relptr32 _relptr32;
		builtin::_relptr64 _relptr64;
		builtin::_string _string;
		builtin::_type _type;
		builtin::_u8 _u8;
		builtin::_u16 _u16;
		builtin::_u16be _u16be;
		builtin::_u16le _u16le;
		builtin::_u32 _u32;
		builtin::_u32be _u32be;
		builtin::_u32le _u32le;
		builtin::_u64 _u64;
		builtin::_u64be _u64be;
		builtin::_u64le _u64le;
		builtin::_u128 _u128;
		builtin::_u128be _u128be;
		builtin::_u128le _u128le;
		builtin::_uint _uint;
		builtin::_uintptr _uintptr;
		FunctionID function_id;
		StructID struct_id;
		TypeAlias type_alias;
		UnionID union_id;
	};

	struct Value {
		ValueType type;
		ValueData data;
	};

	struct IdentifierInfo {
		TypeID type;
		Value value;
		bool has_value;
	};

	struct FunctionIO {
		InternedString name;
		IdentifierInfo info;
	};

	struct FunctionInfo {
		MyVector<FunctionIO> parameters;
		MyVector<FunctionIO> returns;
	};

	struct StructMember {
		InternedString name;
		IdentifierInfo info;
	};

	struct StructInfo {
		MyVector<StructID> usings;
		MyVector<StructMember> members;
	};

	struct FileInfo {
		MyMap<InternedString, IdentifierInfo> identifiers;
	};

	struct PackageInfo {
		const InternedString full_path;
		MyMap<InternedString, FileInfo> files;
	};

	struct Info {
		MyMap<InternedString, PackageInfo> packages;
		MyMap<EnumID, Type> all_enums;
		MyMap<FunctionID, FunctionInfo> all_functions;
		MyMap<StructID, StructInfo> all_structs;
		MyMap<TypeID, Type> all_types;
		MyMap<UnionID, Type> all_unions;
	};
}
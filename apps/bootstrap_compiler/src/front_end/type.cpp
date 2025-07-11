#include "front_end/type.h"

namespace hemera {

	TypeInfo::TypeInfo(TypeInfoVariant type, size_t size)
		: type{ type }
		, size{ size }
	{}
	
	TypeInfo::~TypeInfo() = default;


	TypeInfoArray::TypeInfoArray(TypeID base_type,
		MyVector<ArrayDimension>&& dims)
		: TypeInfo{ TypeInfoVariant::ARRAY, sizeof(size_t) } //TODO(ches) what is the size here??
		, base_type{ base_type }
		, dims{ dims }
	{}
	TypeInfoArray::~TypeInfoArray() = default;


	TypeInfoEnum::TypeInfoEnum(size_t size)
		: TypeInfo{ TypeInfoVariant::ENUM, size }
	{
	}
	TypeInfoEnum::~TypeInfoEnum() = default;


	TypeInfoFloat::TypeInfoFloat(Endianness endianness, size_t size)
		: TypeInfo{ TypeInfoVariant::FLOAT, size }
		, endianness{ endianness }
	{}
	TypeInfoFloat::~TypeInfoFloat() = default;


	TypeInfoFunction::TypeInfoFunction()
		: TypeInfo{ TypeInfoVariant::ARRAY, sizeof(builtin::_ptr) } //TODO(ches) what is the size here??
	{};
	TypeInfoFunction::~TypeInfoFunction() = default;


	TypeInfoInteger::TypeInfoInteger(bool is_signed, Endianness endianness,
		size_t size)
		: TypeInfo{ TypeInfoVariant::INTEGER, size }
		, is_signed{ is_signed }
		, endianness{ endianness }
	{}
	TypeInfoInteger::~TypeInfoInteger() = default;


	TypeInfoPointer::TypeInfoPointer(TypeID base_type, bool relative,
		bool is_mutable, size_t size)
		: TypeInfo{ TypeInfoVariant::POINTER, size }
		, base_type{ base_type }
		, relative{ relative }
		, is_mutable{ is_mutable }
	{}
	TypeInfoPointer::~TypeInfoPointer() = default;


	TypeInfoString::TypeInfoString(bool raw)
		: TypeInfo{ TypeInfoVariant::STRING
		, raw ? sizeof(BUILTIN_rawptr) : sizeof(BUILTIN_string)
		}
		, raw{ raw }
	{}
	TypeInfoString::~TypeInfoString() = default;


	TypeInfoStruct::TypeInfoStruct(size_t size)
		: TypeInfo{ TypeInfoVariant::STRUCT, size }
	{}
	TypeInfoStruct::~TypeInfoStruct() = default;
	

	TypeInfoUnion::TypeInfoUnion(size_t size)
		: TypeInfo{ TypeInfoVariant::STRUCT, size }
	{}
	TypeInfoUnion::~TypeInfoUnion() = default;


	TypeInfo* BUILTIN_any      = new TypeInfo(TypeInfoVariant::ANY,        sizeof(builtin::_any));
	TypeInfo* BUILTIN_b8       = new TypeInfo(TypeInfoVariant::BOOLEAN,    8);
	TypeInfo* BUILTIN_b16      = new TypeInfo(TypeInfoVariant::BOOLEAN,    16);
	TypeInfo* BUILTIN_b32      = new TypeInfo(TypeInfoVariant::BOOLEAN,    32);
	TypeInfo* BUILTIN_b64      = new TypeInfo(TypeInfoVariant::BOOLEAN,    64);
	TypeInfo* BUILTIN_bool     = new TypeInfo(TypeInfoVariant::BOOLEAN,    sizeof(builtin::_bool));
	TypeInfo* BUILTIN_c16      = new TypeInfo(TypeInfoVariant::COMPLEX,    16);
	TypeInfo* BUILTIN_c32      = new TypeInfo(TypeInfoVariant::COMPLEX,    32);
	TypeInfo* BUILTIN_c64      = new TypeInfo(TypeInfoVariant::COMPLEX,    64);
	TypeInfo* BUILTIN_c128     = new TypeInfo(TypeInfoVariant::COMPLEX,    128);
	TypeInfo* BUILTIN_char     = new TypeInfo(TypeInfoVariant::CHAR,       sizeof(builtin::_char));
	TypeInfo* BUILTIN_cstring  = new TypeInfoString(false);
	TypeInfo* BUILTIN_f16      = new TypeInfoFloat(Endianness::SYSTEM, 16);
	TypeInfo* BUILTIN_f16be    = new TypeInfoFloat(Endianness::BIG,    16);
	TypeInfo* BUILTIN_f16le    = new TypeInfoFloat(Endianness::LITTLE, 16);
	TypeInfo* BUILTIN_f32      = new TypeInfoFloat(Endianness::SYSTEM, 32);
	TypeInfo* BUILTIN_f32be    = new TypeInfoFloat(Endianness::BIG,    32);
	TypeInfo* BUILTIN_f32le    = new TypeInfoFloat(Endianness::LITTLE, 32);
	TypeInfo* BUILTIN_f64      = new TypeInfoFloat(Endianness::SYSTEM, 64);
	TypeInfo* BUILTIN_f64be    = new TypeInfoFloat(Endianness::BIG,    64);
	TypeInfo* BUILTIN_f64le    = new TypeInfoFloat(Endianness::LITTLE, 64);
	TypeInfo* BUILTIN_i8       = new TypeInfoInteger(true, Endianness::SYSTEM, 8);
	TypeInfo* BUILTIN_i16      = new TypeInfoInteger(true, Endianness::SYSTEM, 16);
	TypeInfo* BUILTIN_i16be    = new TypeInfoInteger(true, Endianness::BIG,    16);
	TypeInfo* BUILTIN_i16le    = new TypeInfoInteger(true, Endianness::LITTLE, 16);
	TypeInfo* BUILTIN_i32      = new TypeInfoInteger(true, Endianness::SYSTEM, 32);
	TypeInfo* BUILTIN_i32be    = new TypeInfoInteger(true, Endianness::BIG,    32);
	TypeInfo* BUILTIN_i32le    = new TypeInfoInteger(true, Endianness::LITTLE, 32);
	TypeInfo* BUILTIN_i64      = new TypeInfoInteger(true, Endianness::SYSTEM, 64);
	TypeInfo* BUILTIN_i64be    = new TypeInfoInteger(true, Endianness::BIG,    64);
	TypeInfo* BUILTIN_i64le    = new TypeInfoInteger(true, Endianness::LITTLE, 64);
	TypeInfo* BUILTIN_i128     = new TypeInfoInteger(true, Endianness::SYSTEM, 128);
	TypeInfo* BUILTIN_i128be   = new TypeInfoInteger(true, Endianness::BIG,    128);
	TypeInfo* BUILTIN_i128le   = new TypeInfoInteger(true, Endianness::LITTLE, 128);
	TypeInfo* BUILTIN_int      = new TypeInfoInteger(true, Endianness::SYSTEM, sizeof(builtin::_int));
	TypeInfo* BUILTIN_ptr      = new TypeInfo(TypeInfoVariant::POINTER,    sizeof(builtin::_ptr));
	TypeInfo* BUILTIN_q32      = new TypeInfo(TypeInfoVariant::QUATERNION, 32);
	TypeInfo* BUILTIN_q64      = new TypeInfo(TypeInfoVariant::QUATERNION, 64);
	TypeInfo* BUILTIN_q128     = new TypeInfo(TypeInfoVariant::QUATERNION, 128);
	TypeInfo* BUILTIN_q256     = new TypeInfo(TypeInfoVariant::QUATERNION, 256);
	TypeInfo* BUILTIN_rawptr   = new TypeInfo(TypeInfoVariant::POINTER,    sizeof(builtin::_rawptr));
	TypeInfo* BUILTIN_string   = new TypeInfoString(false);
	TypeInfo* BUILTIN_type     = new TypeInfo(TypeInfoVariant::TYPE,       sizeof(builtin::_type));
	TypeInfo* BUILTIN_u8       = new TypeInfoInteger(false, Endianness::SYSTEM, 8);
	TypeInfo* BUILTIN_u16      = new TypeInfoInteger(false, Endianness::SYSTEM, 16);
	TypeInfo* BUILTIN_u16be    = new TypeInfoInteger(false, Endianness::BIG,    16);
	TypeInfo* BUILTIN_u16le    = new TypeInfoInteger(false, Endianness::LITTLE, 16);
	TypeInfo* BUILTIN_u32      = new TypeInfoInteger(false, Endianness::SYSTEM, 32);
	TypeInfo* BUILTIN_u32be    = new TypeInfoInteger(false, Endianness::BIG,    32);
	TypeInfo* BUILTIN_u32le    = new TypeInfoInteger(false, Endianness::LITTLE, 32);
	TypeInfo* BUILTIN_u64      = new TypeInfoInteger(false, Endianness::SYSTEM, 64);
	TypeInfo* BUILTIN_u64be    = new TypeInfoInteger(false, Endianness::BIG,    64);
	TypeInfo* BUILTIN_u64le    = new TypeInfoInteger(false, Endianness::LITTLE, 64);
	TypeInfo* BUILTIN_u128     = new TypeInfoInteger(false, Endianness::SYSTEM, 128);
	TypeInfo* BUILTIN_u128be   = new TypeInfoInteger(false, Endianness::BIG,    128);
	TypeInfo* BUILTIN_u128le   = new TypeInfoInteger(false, Endianness::LITTLE, 128);
	TypeInfo* BUILTIN_uint     = new TypeInfoInteger(false, Endianness::SYSTEM, sizeof(builtin::_uint));
	TypeInfo* BUILTIN_uintptr  = new TypeInfoInteger(false, Endianness::SYSTEM, sizeof(builtin::_uintptr));
}
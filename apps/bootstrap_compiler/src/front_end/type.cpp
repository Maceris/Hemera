#include "front_end/type.h"

#include <format>

#include "util/logger.h"

namespace hemera {

	TypeInfo::TypeInfo(TypeInfoVariant variant, size_t size)
		: variant{ variant }
		, size{ size }
	{}
	
	TypeInfo::~TypeInfo() = default;


	TypeInfoAlias::TypeInfoAlias(TypeInfo* base_type, InternedString name,
		bool distinct)
		: TypeInfo{ TypeInfoVariant::ALIAS, base_type->size }
		, base_type{ base_type }
		, name{ name }
		, distinct{ distinct }
	{
	}
	TypeInfoAlias::~TypeInfoAlias() = default;


	TypeInfoArray::TypeInfoArray(TypeInfo* base_type,
		MyVector<ArrayDimension>&& dimensions)
		: TypeInfo{ TypeInfoVariant::ARRAY, sizeof(size_t) } //TODO(ches) what is the size here??
		, base_type{ base_type }
		, dimensions{ dimensions }
	{}
	TypeInfoArray::~TypeInfoArray() = default;


	TypeInfoEnum::TypeInfoEnum(InternedString name, size_t size)
		: TypeInfo{ TypeInfoVariant::ENUM, size }
		, name{ name }
	{}
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


	TypeInfoPointer::TypeInfoPointer(TypeInfo* base_type, bool is_relative,
		bool is_mutable, size_t size)
		: TypeInfo{ TypeInfoVariant::POINTER, size }
		, base_type{ base_type }
		, is_relative{ is_relative }
		, is_mutable{ is_mutable }
	{}
	TypeInfoPointer::~TypeInfoPointer() = default;


	TypeInfoString::TypeInfoString(bool is_raw)
		: TypeInfo{ TypeInfoVariant::STRING
		, is_raw ? sizeof(BUILTIN_rawptr) : sizeof(BUILTIN_string)
		}
		, is_raw{ is_raw }
	{}
	TypeInfoString::~TypeInfoString() = default;


	TypeInfoStruct::TypeInfoStruct(InternedString name, size_t size)
		: TypeInfo{ TypeInfoVariant::STRUCT, size }
		, name{ name }
	{}
	TypeInfoStruct::~TypeInfoStruct() = default;
	

	TypeInfoUnion::TypeInfoUnion(InternedString name, size_t size)
		: TypeInfo{ TypeInfoVariant::STRUCT, size }
		, name{ name }
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
	
	TypeInfo* BUILTIN_void  = new TypeInfo(TypeInfoVariant::VOID, 0);
	TypeInfo* BUILTIN_poisoned_value  = new TypeInfo(TypeInfoVariant::VOID, 0);

	std::string to_string(TypeInfo const* type) {
		//TODO(ches) handle aliases
		if (type == nullptr) {
			return "null";
		}

		// Primitives
		if (BUILTIN_any == type) {
			return "any";
		}
		if (BUILTIN_b8 == type) {
			return "b8";
		}
		if (BUILTIN_b16 == type) {
			return "b16";
		}
		if (BUILTIN_b32 == type) {
			return "b32";
		}
		if (BUILTIN_b64 == type) {
			return "b64";
		}
		if (BUILTIN_bool == type) {
			return "bool";
		}
		if (BUILTIN_c16 == type) {
			return "c16";
		}
		if (BUILTIN_c32 == type) {
			return "c32";
		}
		if (BUILTIN_c64 == type) {
			return "c64";
		}
		if (BUILTIN_c128 == type) {
			return "c128";
		}
		if (BUILTIN_char == type) {
			return "char";
		}
		if (BUILTIN_cstring == type) {
			return "cstring";
		}
		if (BUILTIN_f16 == type) {
			return "f16";
		}
		if (BUILTIN_f16be == type) {
			return "f16be";
		}
		if (BUILTIN_f16le == type) {
			return "f16le";
		}
		if (BUILTIN_f32 == type) {
			return "f32";
		}
		if (BUILTIN_f32be == type) {
			return "f32be";
		}
		if (BUILTIN_f32le == type) {
			return "f32le";
		}
		if (BUILTIN_f64 == type) {
			return "f64";
		}
		if (BUILTIN_f64be == type) {
			return "f64be";
		}
		if (BUILTIN_f64le == type) {
			return "f64le";
		}
		if (BUILTIN_i8 == type) {
			return "i8";
		}
		if (BUILTIN_i16 == type) {
			return "i16";
		}
		if (BUILTIN_i16be == type) {
			return "i16be";
		}
		if (BUILTIN_i16le == type) {
			return "i16le";
		}
		if (BUILTIN_i32 == type) {
			return "i32";
		}
		if (BUILTIN_i32be == type) {
			return "i32be";
		}
		if (BUILTIN_i32le == type) {
			return "i32le";
		}
		if (BUILTIN_i64 == type) {
			return "i64";
		}
		if (BUILTIN_i64be == type) {
			return "i64be";
		}
		if (BUILTIN_i64le == type) {
			return "i64le";
		}
		if (BUILTIN_i128 == type) {
			return "i128";
		}
		if (BUILTIN_i128be == type) {
			return "i128be";
		}
		if (BUILTIN_i128le == type) {
			return "i128le";
		}
		if (BUILTIN_int == type) {
			return "int";
		}
		if (BUILTIN_q32 == type) {
			return "q32";
		}
		if (BUILTIN_q64 == type) {
			return "q64";
		}
		if (BUILTIN_q128 == type) {
			return "q128";
		}
		if (BUILTIN_q256 == type) {
			return "q256";
		}
		if (BUILTIN_rawptr == type) {
			return "rawptr";
		}
		if (BUILTIN_string == type) {
			return "string";
		}
		if (BUILTIN_type == type) {
			return "type";
		}
		if (BUILTIN_u8 == type) {
			return "u8";
		}
		if (BUILTIN_u16 == type) {
			return "u16";
		}
		if (BUILTIN_u16be == type) {
			return "u16be";
		}
		if (BUILTIN_u16le == type) {
			return "u16le";
		}
		if (BUILTIN_u32 == type) {
			return "u32";
		}
		if (BUILTIN_u32be == type) {
			return "u32be";
		}
		if (BUILTIN_u32le == type) {
			return "u32le";
		}
		if (BUILTIN_u64 == type) {
			return "u64";
		}
		if (BUILTIN_u64be == type) {
			return "u64be";
		}
		if (BUILTIN_u64le == type) {
			return "u64le";
		}
		if (BUILTIN_u128 == type) {
			return "u128";
		}
		if (BUILTIN_u128be == type) {
			return "u128be";
		}
		if (BUILTIN_u128le == type) {
			return "u128le";
		}
		if (BUILTIN_uint == type) {
			return "uint";
		}
		if (BUILTIN_uintptr == type) {
			return "uintptr";
		}
		if (BUILTIN_void == type) {
			return "void";
		}
		
		// Special types
		if (BUILTIN_poisoned_value == type) {
			return "$POISONED$";
		}

		// More complicated builtin types
		if (BUILTIN_ptr == type) {
			TypeInfoPointer const* specific_type = 
				static_cast<TypeInfoPointer const*>(type);

			std::string result = specific_type->is_relative ? "relptr" : "ptr";

			result += "[";
			if (specific_type->is_mutable) {
				result += "mut ";
			}
			result += to_string(specific_type->base_type);
			result += "]";

			return result;
		}

		// User created type
		if (TypeInfoVariant::ANY == type->variant
			|| TypeInfoVariant::BOOLEAN == type->variant
			|| TypeInfoVariant::CHAR == type->variant
			|| TypeInfoVariant::COMPLEX == type->variant
			|| TypeInfoVariant::FLOAT == type->variant
			|| TypeInfoVariant::INTEGER == type->variant
			|| TypeInfoVariant::QUATERNION == type->variant
			|| TypeInfoVariant::STRING == type->variant
			|| TypeInfoVariant::TYPE == type->variant
			|| TypeInfoVariant::POINTER == type->variant
			|| TypeInfoVariant::VOID == type->variant
			) {
			LOG_FATAL("Should have used an existing primitive type");
			return "$ERROR$";
		}
		else if (TypeInfoVariant::ARRAY == type->variant) {
			TypeInfoArray const* specific_type = 
				static_cast<TypeInfoArray const*>(type);

			std::string result = to_string(specific_type->base_type);

			for (const ArrayDimension& dim : specific_type->dimensions) {
				switch (dim.type) {
				case ArrayType::STATIC:
					result += std::format("[{}]", dim.count);
					break;
				case ArrayType::DYNAMIC:
					result += "[..]";
					break;
				case ArrayType::VIEW:
					result += "[]";
					break;
				}
			}
			return result;
		}
		else if (TypeInfoVariant::ENUM == type->variant) {
			TypeInfoEnum const* specific_type =
				static_cast<TypeInfoEnum const*>(type);

			std::string result = std::format("{}", *specific_type->name);
			return result;
		}
		else if (TypeInfoVariant::FUNCTION == type->variant) {
			TypeInfoFunction const* specific_type = 
				static_cast<TypeInfoFunction const*>(type);
			
			std::string result = "fn(";

			const size_t INPUT_COUNT = specific_type->input.size();
			for (size_t i = 0; i < INPUT_COUNT; i++) {
				result += to_string(specific_type->input[i].type);
				if (i < INPUT_COUNT - 1) {
					result += ", ";
				}
			}
			result += ") -> ";

			const size_t OUTPUT_COUNT = specific_type->output.size();
			if (OUTPUT_COUNT == 0) {
				result += "void";
			}
			else {
				TypeInfoVariant first_output_variant 
					= specific_type->output[0].type->variant;

				const bool complex = OUTPUT_COUNT > 1 
					|| TypeInfoVariant::FUNCTION == first_output_variant;

				if (complex) {
					result += "(";
				}
				for (size_t i = 0; i < OUTPUT_COUNT; i++) {
					result += to_string(specific_type->output[i].type);
					if (i < OUTPUT_COUNT - 1) {
						result += ", ";
					}
				}
				if (complex) {
					result += ")";
				}
			}

			return result;
		}
		else if (TypeInfoVariant::STRUCT == type->variant) {
			TypeInfoStruct const* specific_type = 
				static_cast<TypeInfoStruct const*>(type);

			std::string result = std::format("{}", *specific_type->name);
			return result;
		}
		else if (TypeInfoVariant::UNION == type->variant) {
			TypeInfoStruct const* specific_type =
				static_cast<TypeInfoStruct const*>(type);

			std::string result = std::format("{}", *specific_type->name);
			return result;
		}
		else {
			LOG_FATAL("Unknown type variant");
			return "$ERROR$";
		}
	}

	bool same_type(TypeInfo const* a, TypeInfo const* b) {
		//TODO(ches) handle aliases
		if (a == nullptr || b == nullptr) {
			return false;
		}

		return a == b;
	}

	bool can_implicitly_convert_to(TypeInfo const* from, TypeInfo const* to) {
		TypeInfo const* actual_from = from;
		TypeInfo const* actual_to = to;

		// Look up aliases until we reach the base type or a distinct alias
		while (actual_from != nullptr 
			&& TypeInfoVariant::ALIAS == actual_from->variant) {
			TypeInfoAlias const* real = static_cast<TypeInfoAlias const*>(actual_from);
			if (real->distinct) {
				break;
			}
			else {
				actual_from = real->base_type;
			}
		}
		while (actual_to != nullptr
			&& TypeInfoVariant::ALIAS == actual_to->variant) {
			TypeInfoAlias const* real = static_cast<TypeInfoAlias const*>(actual_to);
			if (real->distinct) {
				break;
			}
			else {
				actual_to = real->base_type;
			}
		}
		
		if (actual_from == nullptr || actual_to == nullptr) {
			return false;
		}

		if (actual_from == actual_to) {
			return true;
		}

		if (actual_from->variant != actual_to->variant) {
			return false;
		}

		switch (actual_from->variant) {
			// There's only one variant, they would have been equal
		case TypeInfoVariant::ANY:
		case TypeInfoVariant::CHAR:
		case TypeInfoVariant::VOID:
			LOG_WARNING(std::format(
				"We should have had equal type pointers, from={}, to={}", 
				to_string(actual_from), to_string(actual_to))
			);
			return false;
			// We just can't convert it
		case TypeInfoVariant::ALIAS:
		case TypeInfoVariant::ENUM:
		case TypeInfoVariant::FUNCTION:
		case TypeInfoVariant::POINTER:
		case TypeInfoVariant::STRUCT:
		case TypeInfoVariant::UNION:
		case TypeInfoVariant::TYPE:
			return false;
		case TypeInfoVariant::BOOLEAN:
		case TypeInfoVariant::COMPLEX:
		case TypeInfoVariant::FLOAT:
		case TypeInfoVariant::INTEGER:
		case TypeInfoVariant::QUATERNION:
			return actual_to->size >= actual_from->size;
		case TypeInfoVariant::ARRAY:
		{
			TypeInfoArray const* from_specific =
				static_cast<TypeInfoArray const*>(actual_from);
			TypeInfoArray const* to_specific =
				static_cast<TypeInfoArray const*>(actual_to);
			
			size_t from_dimension_count = from_specific->dimensions.size();
			size_t to_dimension_count = to_specific->dimensions.size();

			if (from_dimension_count != to_dimension_count) {
				return false;
			}

			for (size_t i = 0; i < from_dimension_count; i++) {
				const ArrayDimension& from_dimension = from_specific->dimensions[i];
				const ArrayDimension& to_dimension = to_specific->dimensions[i];

				switch (from_dimension.type) {
				case ArrayType::STATIC:
					switch (to_dimension.type) {
					case ArrayType::STATIC:
						if (from_dimension.count != to_dimension.count) {
							return false;
						}
						break;
					case ArrayType::DYNAMIC:
					case ArrayType::VIEW:
						// Fine
						break;
					}
					break;
				case ArrayType::DYNAMIC:
					switch (to_dimension.type) {
					case ArrayType::STATIC:
						// Runtime info, we can't convert
						return false;
					case ArrayType::DYNAMIC:
					case ArrayType::VIEW:
						// Fine
						break;
					}
					break;
				case ArrayType::VIEW:
					switch (to_dimension.type) {
					case ArrayType::STATIC:
						// Runtime info, we can't convert
					case ArrayType::DYNAMIC:
						// Doens't make sense to resize the middle of an array
						return false;
					case ArrayType::VIEW:
						// Fine
						break;
					}
					break;
				}
			}
			// We couldn't rule out conversion
			return true;
		}
			break;
		case TypeInfoVariant::STRING:
		{
			TypeInfoString const* from_specific =
				static_cast<TypeInfoString const*>(actual_from);
			TypeInfoString const* to_specific =
				static_cast<TypeInfoString const*>(actual_to);

			return from_specific->is_raw == to_specific->is_raw;
		}
		}

		LOG_WARNING(std::format(
			"We probably should have decided if types could convert by now, from={}, to={}",
			to_string(actual_from), to_string(actual_to))
		);
		return false;
	}
}
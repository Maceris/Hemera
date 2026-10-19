#include "front_end/type.h"

#include <algorithm>
#include <format>
#include <utility>

#include "util/logger.h"

namespace hemera {

	TypeInfo::TypeInfo(TypeInfoVariant variant, size_t size, size_t alignment)
		: variant{ variant }
		, contains_pointers{ TypeInfoVariant::ANY == variant
			|| TypeInfoVariant::POINTER == variant
			|| TypeInfoVariant::STRING == variant
		}
		, size{ size }
		, alignment{ alignment }
	{}

	TypeInfo::~TypeInfo() = default;

	TypeInfoArchetype::TypeInfoArchetype(InternedString name, InternedString generic)
		: TypeInfo{ TypeInfoVariant::ARCHETYPE, POINTER_SIZE, POINTER_SIZE }
		, name{ name }
		, generic{ generic }
	{
		contains_pointers = true;
	}

	TypeInfoAlias::TypeInfoAlias(InternedString name, bool distinct)
		: TypeInfo{ TypeInfoVariant::ALIAS, 0, 1 }
		, base_type{ nullptr }
		, name{ name }
		, distinct{ distinct }
	{
		complete = false;
	}

	/*
	 * A static array is its elements, one after another. An array view is a count and a pointer,
	 * and a dynamic array adds a capacity and an allocator (docs/types.md, Memory Layout).
	 */
	static constexpr size_t VIEW_SIZE = 2 * POINTER_SIZE;
	// count, data, capacity, then an Allocator: a function and a data pointer
	static constexpr size_t DYNAMIC_ARRAY_SIZE = 5 * POINTER_SIZE;

	TypeInfoArray::TypeInfoArray(TypeInfo* element_type, ArrayType array_type, size_t count)
		: TypeInfo{ TypeInfoVariant::ARRAY, 0, POINTER_SIZE }
		, element_type{ element_type }
		, array_type{ array_type }
		, count{ count }
	{
		if (ArrayType::STATIC == array_type) {
			complete = element_type->complete;
			size = element_type->size * count;
			alignment = element_type->alignment;
			contains_pointers = element_type->contains_pointers;
		}
		else {
			size = ArrayType::VIEW == array_type ? VIEW_SIZE : DYNAMIC_ARRAY_SIZE;
			contains_pointers = true;
		}
	}

	TypeInfoBoolean::TypeInfoBoolean(size_t size_)
		: TypeInfo{ TypeInfoVariant::BOOLEAN, size_, size_ }
	{}

	TypeInfoComposite::TypeInfoComposite(TypeInfoVariant variant_, size_t part_size_, size_t parts)
		: TypeInfo{ variant_, part_size_ * parts, part_size_ }
		, part_size{ part_size_ }
	{}

	TypeInfoEnum::TypeInfoEnum(InternedString name_)
		: TypeInfo{ TypeInfoVariant::ENUM, 0, 1 }
		, name{ name_ }
		, backing_type{ nullptr }
	{
		complete = false;
	}

	TypeInfoFloat::TypeInfoFloat(Endianness endianness_, size_t size_)
		: TypeInfo{ TypeInfoVariant::FLOAT, size_, size_ }
		, endianness{ endianness_ }
	{}

	// A function value is a pointer to the function
	TypeInfoFunction::TypeInfoFunction()
		: TypeInfo{ TypeInfoVariant::FUNCTION, POINTER_SIZE, POINTER_SIZE }
	{}

	// 128-bit integers are aligned to 16 bytes, as C compilers do on these targets
	TypeInfoInteger::TypeInfoInteger(bool is_signed_, Endianness endianness_, size_t size_)
		: TypeInfo{ TypeInfoVariant::INTEGER, size_, size_ }
		, is_signed{ is_signed_ }
		, endianness{ endianness_ }
	{}

	TypeInfoPointer::TypeInfoPointer(TypeInfo* base_type_, bool is_relative_, bool is_mutable_,
		size_t size_)
		: TypeInfo{ TypeInfoVariant::POINTER, size_, size_ }
		, base_type{ base_type_ }
		, is_relative{ is_relative_ }
		, is_mutable{ is_mutable_ }
	{}

	// A string is a count and a pointer to its bytes; a cstring is just the pointer
	TypeInfoString::TypeInfoString(bool is_raw_)
		: TypeInfo{ TypeInfoVariant::STRING, is_raw_ ? POINTER_SIZE : VIEW_SIZE, POINTER_SIZE }
		, is_raw{ is_raw_ }
	{}

	TypeInfoStruct::TypeInfoStruct(InternedString name_)
		: TypeInfo{ TypeInfoVariant::STRUCT, 0, 1 }
		, name{ name_ }
	{
		complete = false;
	}

	TypeInfoUnion::TypeInfoUnion(InternedString name_)
		: TypeInfo{ TypeInfoVariant::UNION, 0, 1 }
		, name{ name_ }
	{
		complete = false;
	}

	static size_t round_up(size_t value, size_t alignment) {
		return alignment == 0 ? value : (value + alignment - 1) / alignment * alignment;
	}

	/*
	 * Members in order, each at the next offset its alignment allows, unless #packed; every member
	 * at 0 with #union. The struct is aligned to its most aligned member (1 when #packed), raised
	 * to #align(n) if that's more, and its size is rounded up to that.
	 */
	void lay_out_struct(TypeInfoStruct* type) {
		size_t offset = 0;
		size_t size = 0;
		size_t alignment = 1;
		bool contains_pointers = type->is_scoped;
		for (StructMember& member : type->members) {
			LOG_ASSERT(member.member_type != nullptr && member.member_type->complete);
			const size_t member_alignment = type->is_packed ? 1 : member.member_type->alignment;
			alignment = std::max(alignment, member_alignment);
			contains_pointers = contains_pointers || member.member_type->contains_pointers;
			if (type->is_union) {
				member.offset = 0;
				size = std::max(size, member.member_type->size);
				continue;
			}
			offset = round_up(offset, member_alignment);
			member.offset = offset;
			offset += member.member_type->size;
			size = offset;
		}
		alignment = std::max(alignment, type->requested_alignment);
		type->alignment = alignment;
		type->size = round_up(size, alignment);
		type->contains_pointers = contains_pointers;
		type->complete = true;
	}

	/*
	 * docs/types.md, Unions: the tag at offset 0, then each variant's values like a struct's
	 * members, all variants overlapping. The tag is the smallest unsigned integer that counts them.
	 */
	// A pointer that's never null: ptr[T] (not rawptr or a relative pointer), cstring, or a function.
	static bool is_never_null(TypeInfo const* type) {
		while (type != nullptr && TypeInfoVariant::ALIAS == type->variant) {
			type = static_cast<TypeInfoAlias const*>(type)->base_type;
		}
		if (type == nullptr) {
			return false;
		}
		if (TypeInfoVariant::POINTER == type->variant) {
			auto pointer = static_cast<TypeInfoPointer const*>(type);
			return pointer->base_type != nullptr && !pointer->is_relative;
		}
		if (TypeInfoVariant::STRING == type->variant) {
			return static_cast<TypeInfoString const*>(type)->is_raw;
		}
		return TypeInfoVariant::FUNCTION == type->variant;
	}

	void lay_out_union(TypeInfoUnion* type) {
		// An optional of a pointer that's never null is the pointer, null for None
		const std::string_view name = type->name != nullptr ? std::string_view(*type->name) : std::string_view();
		if (name.starts_with("Optional[") && type->variants.size() == 2 && type->variants[0].types.size() == 1
			&& type->variants[1].types.empty() && is_never_null(type->variants[0].types[0])) {
			type->null_is_none = true;
			type->tag_type = BUILTIN_u8;
			type->variants[0].offsets = { 0 };
			type->variants[1].offsets.clear();
			type->size = type->variants[0].types[0]->size;
			type->alignment = type->variants[0].types[0]->alignment;
			type->contains_pointers = true;
			type->complete = true;
			return;
		}
		const size_t count = type->variants.size();
		type->tag_type = count <= 0x100 ? BUILTIN_u8
			: count <= 0x10000 ? BUILTIN_u16
			: BUILTIN_u32;
		size_t size = type->tag_type->size;
		size_t alignment = type->tag_type->alignment;
		bool contains_pointers = false;
		for (UnionVariant& variant : type->variants) {
			size_t offset = type->tag_type->size;
			variant.offsets.clear();
			for (TypeInfo* value_type : variant.types) {
				LOG_ASSERT(value_type != nullptr && value_type->complete);
				offset = round_up(offset, value_type->alignment);
				variant.offsets.push_back(offset);
				offset += value_type->size;
				alignment = std::max(alignment, value_type->alignment);
				contains_pointers = contains_pointers || value_type->contains_pointers;
			}
			size = std::max(size, offset);
		}
		type->alignment = alignment;
		type->size = round_up(size, alignment);
		type->contains_pointers = contains_pointers;
		type->complete = true;
	}

	void lay_out_alias(TypeInfoAlias* type) {
		LOG_ASSERT(type->base_type != nullptr && type->base_type->complete);
		type->size = type->base_type->size;
		type->alignment = type->base_type->alignment;
		type->contains_pointers = type->base_type->contains_pointers;
		type->complete = true;
	}

	void lay_out_enum(TypeInfoEnum* type) {
		LOG_ASSERT(type->backing_type != nullptr);
		type->size = type->backing_type->size;
		type->alignment = type->backing_type->alignment;
		type->complete = true;
	}

	TypeInfo* BUILTIN_any;
	TypeInfo* BUILTIN_b8;
	TypeInfo* BUILTIN_b16;
	TypeInfo* BUILTIN_b32;
	TypeInfo* BUILTIN_b64;
	TypeInfo* BUILTIN_bool;
	TypeInfo* BUILTIN_c16;
	TypeInfo* BUILTIN_c32;
	TypeInfo* BUILTIN_c64;
	TypeInfo* BUILTIN_c128;
	TypeInfo* BUILTIN_char;
	TypeInfo* BUILTIN_cstring;
	TypeInfo* BUILTIN_f16;
	TypeInfo* BUILTIN_f16be;
	TypeInfo* BUILTIN_f16le;
	TypeInfo* BUILTIN_f32;
	TypeInfo* BUILTIN_f32be;
	TypeInfo* BUILTIN_f32le;
	TypeInfo* BUILTIN_f64;
	TypeInfo* BUILTIN_f64be;
	TypeInfo* BUILTIN_f64le;
	TypeInfo* BUILTIN_i8;
	TypeInfo* BUILTIN_i16;
	TypeInfo* BUILTIN_i16be;
	TypeInfo* BUILTIN_i16le;
	TypeInfo* BUILTIN_i32;
	TypeInfo* BUILTIN_i32be;
	TypeInfo* BUILTIN_i32le;
	TypeInfo* BUILTIN_i64;
	TypeInfo* BUILTIN_i64be;
	TypeInfo* BUILTIN_i64le;
	TypeInfo* BUILTIN_i128;
	TypeInfo* BUILTIN_i128be;
	TypeInfo* BUILTIN_i128le;
	TypeInfo* BUILTIN_int;
	TypeInfo* BUILTIN_q32;
	TypeInfo* BUILTIN_q64;
	TypeInfo* BUILTIN_q128;
	TypeInfo* BUILTIN_q256;
	TypeInfo* BUILTIN_rawptr;
	TypeInfo* BUILTIN_string;
	TypeInfo* BUILTIN_type;
	TypeInfo* BUILTIN_u8;
	TypeInfo* BUILTIN_u16;
	TypeInfo* BUILTIN_u16be;
	TypeInfo* BUILTIN_u16le;
	TypeInfo* BUILTIN_u32;
	TypeInfo* BUILTIN_u32be;
	TypeInfo* BUILTIN_u32le;
	TypeInfo* BUILTIN_u64;
	TypeInfo* BUILTIN_u64be;
	TypeInfo* BUILTIN_u64le;
	TypeInfo* BUILTIN_u128;
	TypeInfo* BUILTIN_u128be;
	TypeInfo* BUILTIN_u128le;
	TypeInfo* BUILTIN_uint;
	TypeInfo* BUILTIN_uintptr;
	TypeInfo* BUILTIN_usize;

	TypeInfo* BUILTIN_void;
	TypeInfo* BUILTIN_poisoned_value;

	// Each builtin type's name, for looking it up and printing it
	static constexpr std::pair<std::string_view, TypeInfo**> BUILTIN_TYPES[] = {
		{ "any", &BUILTIN_any },
		{ "b8", &BUILTIN_b8 }, { "b16", &BUILTIN_b16 }, { "b32", &BUILTIN_b32 }, { "b64", &BUILTIN_b64 },
		{ "bool", &BUILTIN_bool },
		{ "c16", &BUILTIN_c16 }, { "c32", &BUILTIN_c32 }, { "c64", &BUILTIN_c64 }, { "c128", &BUILTIN_c128 },
		{ "char", &BUILTIN_char },
		{ "cstring", &BUILTIN_cstring },
		{ "f16", &BUILTIN_f16 }, { "f16be", &BUILTIN_f16be }, { "f16le", &BUILTIN_f16le },
		{ "f32", &BUILTIN_f32 }, { "f32be", &BUILTIN_f32be }, { "f32le", &BUILTIN_f32le },
		{ "f64", &BUILTIN_f64 }, { "f64be", &BUILTIN_f64be }, { "f64le", &BUILTIN_f64le },
		{ "i8", &BUILTIN_i8 },
		{ "i16", &BUILTIN_i16 }, { "i16be", &BUILTIN_i16be }, { "i16le", &BUILTIN_i16le },
		{ "i32", &BUILTIN_i32 }, { "i32be", &BUILTIN_i32be }, { "i32le", &BUILTIN_i32le },
		{ "i64", &BUILTIN_i64 }, { "i64be", &BUILTIN_i64be }, { "i64le", &BUILTIN_i64le },
		{ "i128", &BUILTIN_i128 }, { "i128be", &BUILTIN_i128be }, { "i128le", &BUILTIN_i128le },
		{ "int", &BUILTIN_int },
		{ "q32", &BUILTIN_q32 }, { "q64", &BUILTIN_q64 }, { "q128", &BUILTIN_q128 }, { "q256", &BUILTIN_q256 },
		{ "rawptr", &BUILTIN_rawptr },
		{ "string", &BUILTIN_string },
		{ "type", &BUILTIN_type },
		{ "u8", &BUILTIN_u8 },
		{ "u16", &BUILTIN_u16 }, { "u16be", &BUILTIN_u16be }, { "u16le", &BUILTIN_u16le },
		{ "u32", &BUILTIN_u32 }, { "u32be", &BUILTIN_u32be }, { "u32le", &BUILTIN_u32le },
		{ "u64", &BUILTIN_u64 }, { "u64be", &BUILTIN_u64be }, { "u64le", &BUILTIN_u64le },
		{ "u128", &BUILTIN_u128 }, { "u128be", &BUILTIN_u128be }, { "u128le", &BUILTIN_u128le },
		{ "uint", &BUILTIN_uint },
		{ "uintptr", &BUILTIN_uintptr },
		{ "usize", &BUILTIN_usize },
		{ "void", &BUILTIN_void },
	};

	TypeInfo* builtin_type(std::string_view name) {
		for (const auto& [builtin_name, type] : BUILTIN_TYPES) {
			if (builtin_name == name) {
				return *type;
			}
		}
		return nullptr;
	}

	std::string to_string(TypeInfo const* type) {
		if (type == nullptr) {
			return "?";
		}
		for (const auto& [builtin_name, builtin] : BUILTIN_TYPES) {
			if (*builtin == type) {
				return std::string(builtin_name);
			}
		}
		const TypeInfoVariant variant = type->variant;
		if (TypeInfoVariant::ALIAS == variant) {
			return std::string(std::string_view(*static_cast<TypeInfoAlias const*>(type)->name));
		}
		if (TypeInfoVariant::ARCHETYPE == variant) {
			return std::string(std::string_view(*static_cast<TypeInfoArchetype const*>(type)->name));
		}
		if (TypeInfoVariant::STRUCT == variant) {
			InternedString name = static_cast<TypeInfoStruct const*>(type)->name;
			return name != nullptr ? std::string(std::string_view(*name)) : std::string("struct");
		}
		if (TypeInfoVariant::UNION == variant) {
			InternedString name = static_cast<TypeInfoUnion const*>(type)->name;
			return name != nullptr ? std::string(std::string_view(*name)) : std::string("union");
		}
		if (TypeInfoVariant::ENUM == variant) {
			InternedString name = static_cast<TypeInfoEnum const*>(type)->name;
			return name != nullptr ? std::string(std::string_view(*name)) : std::string("enum");
		}
		if (TypeInfoVariant::POINTER == variant) {
			auto pointer = static_cast<TypeInfoPointer const*>(type);
			std::string kind = pointer->is_relative ? std::format("relptr{}", pointer->size * 8) : "ptr";
			return std::format("{}[{}{}]", kind, pointer->is_mutable ? "mut " : "",
				to_string(pointer->base_type));
		}
		if (TypeInfoVariant::ARRAY == variant) {
			auto array = static_cast<TypeInfoArray const*>(type);
			const std::string dimension = ArrayType::STATIC == array->array_type
				? std::format("[{}]", array->count)
				: ArrayType::VIEW == array->array_type ? "[]" : "[..]";
			return to_string(array->element_type) + dimension;
		}
		if (TypeInfoVariant::FUNCTION == variant) {
			auto function = static_cast<TypeInfoFunction const*>(type);
			std::string result = "fn(";
			for (size_t i = 0; i < function->input.size(); ++i) {
				result += (i > 0 ? ", " : "") + to_string(function->input[i].type);
			}
			result += ")";
			if (function->output.size() == 1) {
				result += " -> " + to_string(function->output[0].type);
			}
			else if (!function->output.empty()) {
				result += " -> (";
				for (size_t i = 0; i < function->output.size(); ++i) {
					result += (i > 0 ? ", " : "") + to_string(function->output[i].type);
				}
				result += ")";
			}
			return result;
		}
		return "?";
	}

	TypeInfo const* get_base_type(TypeInfo const* type) {
		while (type != nullptr && TypeInfoVariant::ALIAS == type->variant) {
			type = static_cast<TypeInfoAlias const*>(type)->base_type;
		}
		return type;
	}

	TypeInfo const* get_base_type_or_alias(TypeInfo const* type) {
		while (type != nullptr && TypeInfoVariant::ALIAS == type->variant) {
			auto alias = static_cast<TypeInfoAlias const*>(type);
			if (alias->distinct) {
				break;
			}
			type = alias->base_type;
		}
		return type;
	}

	bool is_owned(TypeInfo const* type) {
		type = get_base_type(type);
		if (type == nullptr) {
			return false;
		}
		if (TypeInfoVariant::STRUCT == type->variant) {
			auto structure = static_cast<TypeInfoStruct const*>(type);
			if (structure->is_owned) {
				return true;
			}
			for (const StructMember& member : structure->members) {
				if (is_owned(member.member_type)) {
					return true;
				}
			}
			return false;
		}
		if (TypeInfoVariant::UNION == type->variant) {
			for (const UnionVariant& variant : static_cast<TypeInfoUnion const*>(type)->variants) {
				for (TypeInfo* payload : variant.types) {
					if (is_owned(payload)) {
						return true;
					}
				}
			}
			return false;
		}
		if (TypeInfoVariant::ARRAY == type->variant) {
			// A view borrows its elements; a static or dynamic array holds them
			auto array = static_cast<TypeInfoArray const*>(type);
			return ArrayType::VIEW != array->array_type && is_owned(array->element_type);
		}
		return false;
	}

	static TypeInfo const* thread_bound_part(TypeInfo const* type, std::vector<TypeInfo const*>& seen) {
		TypeInfo const* base = get_base_type(type);
		if (base == nullptr || std::find(seen.begin(), seen.end(), base) != seen.end()) {
			return nullptr;
		}
		seen.push_back(base);
		if (TypeInfoVariant::STRUCT == base->variant) {
			auto structure = static_cast<TypeInfoStruct const*>(base);
			if (structure->is_thread_bound) {
				return type;
			}
			for (const StructMember& member : structure->members) {
				if (TypeInfo const* found = thread_bound_part(member.member_type, seen)) {
					return found;
				}
			}
		}
		else if (TypeInfoVariant::UNION == base->variant) {
			for (const UnionVariant& variant : static_cast<TypeInfoUnion const*>(base)->variants) {
				for (TypeInfo* payload : variant.types) {
					if (TypeInfo const* found = thread_bound_part(payload, seen)) {
						return found;
					}
				}
			}
		}
		else if (TypeInfoVariant::ARRAY == base->variant) {
			return thread_bound_part(static_cast<TypeInfoArray const*>(base)->element_type, seen);
		}
		else if (TypeInfoVariant::POINTER == base->variant) {
			return thread_bound_part(static_cast<TypeInfoPointer const*>(base)->base_type, seen);
		}
		return nullptr;
	}

	TypeInfo const* thread_bound_part(TypeInfo const* type) {
		std::vector<TypeInfo const*> seen;
		return thread_bound_part(type, seen);
	}

	bool same_type(TypeInfo const* a, TypeInfo const* b) {
		if (a == nullptr || b == nullptr) {
			return false;
		}
		return get_base_type_or_alias(a) == get_base_type_or_alias(b);
	}

	static bool is_one_of(TypeInfo const* type, std::initializer_list<TypeInfo*> types) {
		return std::find(types.begin(), types.end(), type) != types.end();
	}

	bool can_implicitly_convert_to(TypeInfo const* from, TypeInfo const* to) {
		if (from == nullptr || to == nullptr) {
			return false;
		}
		from = get_base_type_or_alias(from);
		to = get_base_type_or_alias(to);
		if (from == to) {
			return true;
		}
		// Distinct aliases convert to nothing else
		if (TypeInfoVariant::ALIAS == from->variant || TypeInfoVariant::ALIAS == to->variant) {
			return false;
		}
		if (from->variant != to->variant) {
			return false;
		}
		if (TypeInfoVariant::INTEGER == from->variant) {
			auto a = static_cast<TypeInfoInteger const*>(from);
			auto b = static_cast<TypeInfoInteger const*>(to);
			// uintptr and usize convert to uint, but not to each other
			if (is_one_of(from, { BUILTIN_uintptr, BUILTIN_usize })) {
				return to == BUILTIN_uint;
			}
			if (is_one_of(to, { BUILTIN_uintptr, BUILTIN_usize })) {
				return false;
			}
			// Widening only, keeping the signedness and endianness; 128-bit doesn't fit int
			return a->is_signed == b->is_signed && a->endianness == b->endianness
				&& a->size < b->size;
		}
		if (TypeInfoVariant::FLOAT == from->variant) {
			auto a = static_cast<TypeInfoFloat const*>(from);
			auto b = static_cast<TypeInfoFloat const*>(to);
			return a->endianness == b->endianness && a->size < b->size;
		}
		if (TypeInfoVariant::BOOLEAN == from->variant) {
			return from->size < to->size;
		}
		if (TypeInfoVariant::STRUCT == from->variant) {
			// To any struct included with using, at any depth
			for (const StructMember& member : static_cast<TypeInfoStruct const*>(from)->members) {
				if (member.is_using && can_implicitly_convert_to(member.member_type, to)) {
					return true;
				}
			}
		}
		return false;
	}

	void initialize_builtin_types() {
		if (BUILTIN_int != nullptr) {
			return;
		}
		BUILTIN_any = new TypeInfo(TypeInfoVariant::ANY, 2 * POINTER_SIZE, POINTER_SIZE);
		BUILTIN_b8 = new TypeInfoBoolean(1);
		BUILTIN_b16 = new TypeInfoBoolean(2);
		BUILTIN_b32 = new TypeInfoBoolean(4);
		BUILTIN_b64 = new TypeInfoBoolean(8);
		BUILTIN_bool = new TypeInfoBoolean(1);
		// Complex numbers are two integers, quaternions four (docs/types.md)
		BUILTIN_c16 = new TypeInfoComposite(TypeInfoVariant::COMPLEX, 1, 2);
		BUILTIN_c32 = new TypeInfoComposite(TypeInfoVariant::COMPLEX, 2, 2);
		BUILTIN_c64 = new TypeInfoComposite(TypeInfoVariant::COMPLEX, 4, 2);
		BUILTIN_c128 = new TypeInfoComposite(TypeInfoVariant::COMPLEX, 8, 2);
		BUILTIN_char = new TypeInfo(TypeInfoVariant::CHAR, 1, 1);
		BUILTIN_cstring = new TypeInfoString(true);
		BUILTIN_f16 = new TypeInfoFloat(Endianness::SYSTEM, 2);
		BUILTIN_f16be = new TypeInfoFloat(Endianness::BIG, 2);
		BUILTIN_f16le = new TypeInfoFloat(Endianness::LITTLE, 2);
		BUILTIN_f32 = new TypeInfoFloat(Endianness::SYSTEM, 4);
		BUILTIN_f32be = new TypeInfoFloat(Endianness::BIG, 4);
		BUILTIN_f32le = new TypeInfoFloat(Endianness::LITTLE, 4);
		BUILTIN_f64 = new TypeInfoFloat(Endianness::SYSTEM, 8);
		BUILTIN_f64be = new TypeInfoFloat(Endianness::BIG, 8);
		BUILTIN_f64le = new TypeInfoFloat(Endianness::LITTLE, 8);
		BUILTIN_i8 = new TypeInfoInteger(true, Endianness::SYSTEM, 1);
		BUILTIN_i16 = new TypeInfoInteger(true, Endianness::SYSTEM, 2);
		BUILTIN_i16be = new TypeInfoInteger(true, Endianness::BIG, 2);
		BUILTIN_i16le = new TypeInfoInteger(true, Endianness::LITTLE, 2);
		BUILTIN_i32 = new TypeInfoInteger(true, Endianness::SYSTEM, 4);
		BUILTIN_i32be = new TypeInfoInteger(true, Endianness::BIG, 4);
		BUILTIN_i32le = new TypeInfoInteger(true, Endianness::LITTLE, 4);
		BUILTIN_i64 = new TypeInfoInteger(true, Endianness::SYSTEM, 8);
		BUILTIN_i64be = new TypeInfoInteger(true, Endianness::BIG, 8);
		BUILTIN_i64le = new TypeInfoInteger(true, Endianness::LITTLE, 8);
		BUILTIN_i128 = new TypeInfoInteger(true, Endianness::SYSTEM, 16);
		BUILTIN_i128be = new TypeInfoInteger(true, Endianness::BIG, 16);
		BUILTIN_i128le = new TypeInfoInteger(true, Endianness::LITTLE, 16);
		BUILTIN_int = new TypeInfoInteger(true, Endianness::SYSTEM, POINTER_SIZE);
		BUILTIN_q32 = new TypeInfoComposite(TypeInfoVariant::QUATERNION, 1, 4);
		BUILTIN_q64 = new TypeInfoComposite(TypeInfoVariant::QUATERNION, 2, 4);
		BUILTIN_q128 = new TypeInfoComposite(TypeInfoVariant::QUATERNION, 4, 4);
		BUILTIN_q256 = new TypeInfoComposite(TypeInfoVariant::QUATERNION, 8, 4);
		BUILTIN_rawptr = new TypeInfoPointer(nullptr, false, true, POINTER_SIZE);
		BUILTIN_string = new TypeInfoString(false);
		// A type value points to its type info
		BUILTIN_type = new TypeInfo(TypeInfoVariant::TYPE, POINTER_SIZE, POINTER_SIZE);
		BUILTIN_u8 = new TypeInfoInteger(false, Endianness::SYSTEM, 1);
		BUILTIN_u16 = new TypeInfoInteger(false, Endianness::SYSTEM, 2);
		BUILTIN_u16be = new TypeInfoInteger(false, Endianness::BIG, 2);
		BUILTIN_u16le = new TypeInfoInteger(false, Endianness::LITTLE, 2);
		BUILTIN_u32 = new TypeInfoInteger(false, Endianness::SYSTEM, 4);
		BUILTIN_u32be = new TypeInfoInteger(false, Endianness::BIG, 4);
		BUILTIN_u32le = new TypeInfoInteger(false, Endianness::LITTLE, 4);
		BUILTIN_u64 = new TypeInfoInteger(false, Endianness::SYSTEM, 8);
		BUILTIN_u64be = new TypeInfoInteger(false, Endianness::BIG, 8);
		BUILTIN_u64le = new TypeInfoInteger(false, Endianness::LITTLE, 8);
		BUILTIN_u128 = new TypeInfoInteger(false, Endianness::SYSTEM, 16);
		BUILTIN_u128be = new TypeInfoInteger(false, Endianness::BIG, 16);
		BUILTIN_u128le = new TypeInfoInteger(false, Endianness::LITTLE, 16);
		BUILTIN_uint = new TypeInfoInteger(false, Endianness::SYSTEM, POINTER_SIZE);
		BUILTIN_uintptr = new TypeInfoInteger(false, Endianness::SYSTEM, POINTER_SIZE);
		BUILTIN_usize = new TypeInfoInteger(false, Endianness::SYSTEM, POINTER_SIZE);

		BUILTIN_void = new TypeInfo(TypeInfoVariant::VOID, 0, 1);
		BUILTIN_poisoned_value = new TypeInfo(TypeInfoVariant::VOID, 0, 1);
	}
}

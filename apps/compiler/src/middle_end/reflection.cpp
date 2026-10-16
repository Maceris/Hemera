#include "middle_end/reflection.h"

#include <algorithm>
#include <cstring>
#include <format>

#include "front_end/compile_time.h"
#include "front_end/info.h"
#include "front_end/names.h"
#include "front_end/type.h"

namespace hemera {

	namespace {

		std::string_view text_of(InternedString name) {
			return name != nullptr ? std::string_view(*name) : std::string_view();
		}

		const char* variant_name(TypeInfoVariant variant) {
			switch (variant) {
				case TypeInfoVariant::ALIAS: return "ALIAS";
				case TypeInfoVariant::ANY: return "ANY";
				case TypeInfoVariant::ARRAY: return "ARRAY";
				case TypeInfoVariant::BOOLEAN: return "BOOLEAN";
				case TypeInfoVariant::CHAR: return "CHAR";
				case TypeInfoVariant::COMPLEX: return "COMPLEX";
				case TypeInfoVariant::ENUM: return "ENUM";
				case TypeInfoVariant::FLOAT: return "FLOAT";
				case TypeInfoVariant::FUNCTION: return "FUNCTION";
				case TypeInfoVariant::INTEGER: return "INTEGER";
				case TypeInfoVariant::POINTER: return "POINTER";
				case TypeInfoVariant::QUATERNION: return "QUATERNION";
				case TypeInfoVariant::STRING: return "STRING";
				case TypeInfoVariant::STRUCT: return "STRUCT";
				case TypeInfoVariant::TYPE: return "TYPE";
				case TypeInfoVariant::UNION: return "UNION";
				case TypeInfoVariant::VOID: return "VOID";
			}
			return "VOID";
		}

		// The base/compiler struct describing a type of this variant, like TypeInfoEnum for an enum.
		const char* descriptor_struct(TypeInfoVariant variant) {
			return TypeInfoVariant::ALIAS == variant ? "TypeInfoAlias"
				: TypeInfoVariant::ARRAY == variant ? "TypeInfoArray"
				: TypeInfoVariant::ENUM == variant ? "TypeInfoEnum"
				: TypeInfoVariant::FLOAT == variant ? "TypeInfoFloat"
				: TypeInfoVariant::FUNCTION == variant ? "TypeInfoFunction"
				: TypeInfoVariant::INTEGER == variant ? "TypeInfoInteger"
				: TypeInfoVariant::POINTER == variant ? "TypeInfoPointer"
				: TypeInfoVariant::STRING == variant ? "TypeInfoString"
				: TypeInfoVariant::STRUCT == variant ? "TypeInfoStruct"
				: TypeInfoVariant::UNION == variant ? "TypeInfoUnion"
				: "TypeInfo";
		}

		const char* endianness_name(Endianness endianness) {
			return Endianness::BIG == endianness ? "BIG" : Endianness::LITTLE == endianness ? "LITTLE" : "SYSTEM";
		}

		const char* array_type_name(ArrayType array_type) {
			return ArrayType::STATIC == array_type ? "STATIC" : ArrayType::VIEW == array_type ? "VIEW" : "DYNAMIC";
		}

		// The element type of a view field, like StructMember for members : StructMember[].
		const TypeInfo* element_of(const TypeInfo* view) {
			const TypeInfo* base = get_base_type(view);
			return base != nullptr && TypeInfoVariant::ARRAY == base->variant ? static_cast<const TypeInfoArray*>(base)->element_type : nullptr;
		}

		const TypeInfoStruct* as_struct(const TypeInfo* type) {
			const TypeInfo* base = get_base_type(type);
			return base != nullptr && TypeInfoVariant::STRUCT == base->variant ? static_cast<const TypeInfoStruct*>(base) : nullptr;
		}
	}

	CompileTimeData::CompileTimeData(ProgramInfo* program_)
		: program{ program_ }
	{}

	CompileTimeData& compile_time_data(ProgramInfo* program) {
		std::scoped_lock<std::mutex> lock(program->compile_time_data_mutex);
		if (program->compile_time_data == nullptr) {
			program->compile_time_data = std::make_shared<CompileTimeData>(program);
		}
		return *static_cast<CompileTimeData*>(program->compile_time_data.get());
	}

	uint8_t* CompileTimeData::allocate(size_t size, size_t alignment) {
		std::scoped_lock<std::recursive_mutex> lock(mutex);
		alignment = std::max<size_t>(alignment, 1);
		size_t padding = free_start != nullptr ? (alignment - reinterpret_cast<uintptr_t>(free_start) % alignment) % alignment : 0;
		if (free_start == nullptr || padding + size > free_size) {
			const size_t block = std::max<size_t>(size + alignment, 64 * 1024);
			blocks.push_back(std::make_unique<uint8_t[]>(block));
			free_start = blocks.back().get();
			free_size = block;
			padding = (alignment - reinterpret_cast<uintptr_t>(free_start) % alignment) % alignment;
		}
		uint8_t* result = free_start + padding;
		std::memset(result, 0, size);
		free_start = result + size;
		free_size -= padding + size;
		return result;
	}

	const TypeInfoStruct* CompileTimeData::compiler_struct(std::string_view name) {
		NameRegistry& names = program->names;
		std::scoped_lock<std::mutex> lock(names.mutex);
		auto iter = names.declarations.find(std::make_pair(intern(std::string(BASE_PACKAGE_PREFIX) + "compiler"), intern(std::string(name))));
		if (iter == names.declarations.end() || iter->second->type_value == nullptr || !iter->second->type_value->complete) {
			return nullptr;
		}
		return as_struct(iter->second->type_value);
	}

	uint8_t* CompileTimeData::new_records(const TypeInfoStruct* type, size_t count) {
		return allocate(type->size * std::max<size_t>(count, 1), type->alignment);
	}

	bool CompileTimeData::find_field(const TypeInfoStruct* type, std::string_view name, size_t& offset, const TypeInfo*& field_type) {
		for (const StructMember& member : type->members) {
			if (member.name != nullptr && !member.is_using && text_of(member.name) == name) {
				offset = member.offset;
				field_type = member.member_type;
				return true;
			}
		}
		for (const StructMember& member : type->members) {
			const TypeInfoStruct* included = member.is_using ? as_struct(member.member_type) : nullptr;
			size_t inner = 0;
			if (included != nullptr && find_field(included, name, inner, field_type)) {
				offset = member.offset + inner;
				return true;
			}
		}
		return false;
	}

	void CompileTimeData::write_number_at(uint8_t* at, size_t size, uint64_t value) {
		std::memset(at, 0, size);
		std::memcpy(at, &value, std::min<size_t>(size, sizeof(value)));
	}

	const char* CompileTimeData::copy_text(std::string_view text) {
		auto copy = reinterpret_cast<char*>(allocate(text.size() + 1, 1));
		std::memcpy(copy, text.data(), text.size());
		return copy;
	}

	void CompileTimeData::write_view_at(uint8_t* at, const void* data, size_t count) {
		write_number_at(at, 8, count);
		write_number_at(at + 8, 8, reinterpret_cast<uintptr_t>(data));
	}

	void CompileTimeData::write_text_at(uint8_t* at, std::string_view text) {
		write_view_at(at, text.empty() ? nullptr : copy_text(text), text.size());
	}

	void CompileTimeData::write_any_at(uint8_t* at, const void* data, const TypeInfo* value_type) {
		write_number_at(at, 8, reinterpret_cast<uintptr_t>(data));
		write_number_at(at + 8, 8, reinterpret_cast<uintptr_t>(value_type != nullptr ? descriptor(value_type) : nullptr));
	}

	uint8_t* CompileTimeData::write_some_at(uint8_t* at, const TypeInfo* optional_type) {
		const TypeInfo* base = get_base_type(optional_type);
		if (base == nullptr || TypeInfoVariant::UNION != base->variant) {
			return at;
		}
		auto optional = static_cast<const TypeInfoUnion*>(base);
		if (optional->null_is_none) {
			return at;
		}
		write_number_at(at, optional->tag_type->size, 0);
		return at + (optional->variants.empty() || optional->variants[0].offsets.empty() ? 0 : optional->variants[0].offsets[0]);
	}

	void CompileTimeData::write_number(uint8_t* record, const TypeInfoStruct* type, std::string_view field, uint64_t value) {
		size_t offset = 0;
		const TypeInfo* field_type = nullptr;
		if (find_field(type, field, offset, field_type)) {
			write_number_at(record + offset, field_type->size, value);
		}
	}

	void CompileTimeData::write_text(uint8_t* record, const TypeInfoStruct* type, std::string_view field, std::string_view text) {
		size_t offset = 0;
		const TypeInfo* field_type = nullptr;
		if (find_field(type, field, offset, field_type)) {
			write_text_at(record + offset, text);
		}
	}

	void CompileTimeData::write_pointer(uint8_t* record, const TypeInfoStruct* type, std::string_view field, const void* pointer) {
		write_number(record, type, field, reinterpret_cast<uintptr_t>(pointer));
	}

	void CompileTimeData::write_view(uint8_t* record, const TypeInfoStruct* type, std::string_view field, const void* data, size_t count) {
		size_t offset = 0;
		const TypeInfo* field_type = nullptr;
		if (find_field(type, field, offset, field_type)) {
			write_view_at(record + offset, data, count);
		}
	}

	void CompileTimeData::write_type(uint8_t* record, const TypeInfoStruct* type, std::string_view field, const TypeInfo* value) {
		write_pointer(record, type, field, value != nullptr ? descriptor(value) : nullptr);
	}

	void CompileTimeData::write_member(uint8_t* record, const TypeInfoStruct* type, std::string_view field, std::string_view member) {
		size_t offset = 0;
		const TypeInfo* field_type = nullptr;
		if (!find_field(type, field, offset, field_type)) {
			return;
		}
		auto enumeration = static_cast<const TypeInfoEnum*>(get_base_type(field_type));
		for (size_t i = 0; i < enumeration->members.size(); ++i) {
			if (text_of(enumeration->members[i]) == member) {
				write_number_at(record + offset, field_type->size, enumeration->values[i]);
			}
		}
	}

	void CompileTimeData::write_any(uint8_t* record, const TypeInfoStruct* type, std::string_view field, const void* data,
		const TypeInfo* value_type) {

		size_t offset = 0;
		const TypeInfo* field_type = nullptr;
		if (find_field(type, field, offset, field_type)) {
			write_any_at(record + offset, data, value_type);
		}
	}

	uint8_t* CompileTimeData::write_some(uint8_t* record, const TypeInfoStruct* type, std::string_view field) {
		size_t offset = 0;
		const TypeInfo* field_type = nullptr;
		if (!find_field(type, field, offset, field_type)) {
			return nullptr;
		}
		return write_some_at(record + offset, field_type);
	}

	const uint8_t* CompileTimeData::copy_value(const TypeInfo* type, const CompileTimeValue& value) {
		uint8_t* copy = allocate(std::max<size_t>(value.bytes.size(), 1), std::max<size_t>(type != nullptr ? type->alignment : 8, 8));
		std::memcpy(copy, value.bytes.data(), value.bytes.size());
		// What its strings and views point to, copied too, with the pointers made to point at the copies
		for (const auto& [offset, pointed] : value.pointed) {
			uint8_t* inner = allocate(std::max<size_t>(pointed.bytes.size(), 1), 8);
			std::memcpy(inner, pointed.bytes.data(), pointed.bytes.size());
			for (const auto& [inner_offset, deeper] : pointed.pointed) {
				const uint8_t* copied = copy_value(nullptr, deeper);
				write_number_at(inner + inner_offset, 8, reinterpret_cast<uintptr_t>(copied));
			}
			write_number_at(copy + offset, 8, reinterpret_cast<uintptr_t>(inner));
		}
		return copy;
	}

	const uint8_t* CompileTimeData::descriptor(const TypeInfo* type) {
		std::scoped_lock<std::recursive_mutex> lock(mutex);
		type = get_base_type_or_alias(type);
		if (type == nullptr) {
			return nullptr;
		}
		auto iter = descriptors.find(type);
		if (iter != descriptors.end()) {
			return iter->second;
		}
		const TypeInfoStruct* layout = compiler_struct(descriptor_struct(type->variant));
		if (layout == nullptr) {
			return nullptr;
		}
		uint8_t* record = new_records(layout);
		// Before its fields, which may refer to it, like a struct with a pointer to its own type
		descriptors[type] = record;
		types[reinterpret_cast<uintptr_t>(record)] = type;
		describe(type, record, layout);
		return record;
	}

	// The fields a type's descriptor has, as generate.cpp's descriptors do for the program.
	void CompileTimeData::describe(const TypeInfo* type, uint8_t* record, const TypeInfoStruct* layout) {
		write_member(record, layout, "variant", variant_name(type->variant));
		write_number(record, layout, "size", type->size);
		size_t offset = 0;
		const TypeInfo* field_type = nullptr;
		// A view field of records, each filled in by fill
		auto records = [&](std::string_view field, size_t count, auto fill) {
			if (!find_field(layout, field, offset, field_type) || count == 0) {
				return;
			}
			const TypeInfo* element = element_of(field_type);
			uint8_t* elements = allocate(element->size * count, std::max<size_t>(element->alignment, 1));
			for (size_t i = 0; i < count; ++i) {
				fill(elements + i * element->size, element, i);
			}
			write_view(record, layout, field, elements, count);
		};
		switch (type->variant) {
			case TypeInfoVariant::ALIAS: {
				auto alias = static_cast<const TypeInfoAlias*>(type);
				write_type(record, layout, "base_type", alias->base_type);
				write_text(record, layout, "name", text_of(alias->name));
				write_number(record, layout, "is_distinct", alias->distinct);
				break;
			}
			case TypeInfoVariant::ARRAY: {
				std::vector<const TypeInfoArray*> dimensions;
				const TypeInfo* element = type;
				while (element != nullptr && TypeInfoVariant::ARRAY == element->variant) {
					dimensions.push_back(static_cast<const TypeInfoArray*>(element));
					element = get_base_type(static_cast<const TypeInfoArray*>(element)->element_type);
				}
				write_type(record, layout, "base_type", dimensions.back()->element_type);
				records("dimensions", dimensions.size(), [&](uint8_t* at, const TypeInfo* element_type, size_t i) {
					write_member(at, as_struct(element_type), "type", array_type_name(dimensions[i]->array_type));
					write_number(at, as_struct(element_type), "count", dimensions[i]->count);
				});
				break;
			}
			case TypeInfoVariant::ENUM: {
				auto enumeration = static_cast<const TypeInfoEnum*>(type);
				write_text(record, layout, "name", text_of(enumeration->name));
				write_type(record, layout, "backing_type", enumeration->backing_type != nullptr ? enumeration->backing_type : BUILTIN_uint);
				records("members", enumeration->members.size(), [&](uint8_t* at, const TypeInfo*, size_t i) {
					write_text_at(at, text_of(enumeration->members[i]));
				});
				records("values", enumeration->values.size(), [&](uint8_t* at, const TypeInfo* element_type, size_t i) {
					write_number_at(at, element_type->size, enumeration->values[i]);
				});
				break;
			}
			case TypeInfoVariant::FLOAT:
				write_member(record, layout, "endianness", endianness_name(static_cast<const TypeInfoFloat*>(type)->endianness));
				break;
			case TypeInfoVariant::FUNCTION: {
				auto function = static_cast<const TypeInfoFunction*>(type);
				records("input", function->input.size(), [&](uint8_t* at, const TypeInfo* element_type, size_t i) {
					const TypeInfoStruct* input = as_struct(element_type);
					write_type(at, input, "type", function->input[i].type);
					write_text(at, input, "name", text_of(function->input[i].name));
					write_number(at, input, "is_varargs", function->input[i].is_varargs);
					write_number(at, input, "is_escaping", function->input[i].is_escaping);
				});
				records("output", function->output.size(), [&](uint8_t* at, const TypeInfo* element_type, size_t i) {
					write_type(at, as_struct(element_type), "type", function->output[i].type);
				});
				write_number(record, layout, "never_returns", function->never_returns);
				break;
			}
			case TypeInfoVariant::INTEGER: {
				auto integer = static_cast<const TypeInfoInteger*>(type);
				write_number(record, layout, "is_signed", integer->is_signed);
				write_member(record, layout, "endianness", endianness_name(integer->endianness));
				break;
			}
			case TypeInfoVariant::POINTER: {
				auto pointer = static_cast<const TypeInfoPointer*>(type);
				write_type(record, layout, "base_type", pointer->base_type);
				write_number(record, layout, "is_relative", pointer->is_relative);
				write_number(record, layout, "is_mutable", pointer->is_mutable);
				break;
			}
			case TypeInfoVariant::STRING:
				write_number(record, layout, "is_raw", static_cast<const TypeInfoString*>(type)->is_raw);
				break;
			case TypeInfoVariant::STRUCT: {
				auto structure = static_cast<const TypeInfoStruct*>(type);
				write_text(record, layout, "name", text_of(structure->name));
				records("members", structure->members.size(), [&](uint8_t* at, const TypeInfo* element_type, size_t i) {
					const TypeInfoStruct* member_layout = as_struct(element_type);
					const StructMember& member = structure->members[i];
					write_text(at, member_layout, "name", text_of(member.name));
					write_type(at, member_layout, "member_type", member.member_type);
					write_number(at, member_layout, "offset", member.offset);
					write_number(at, member_layout, "has_value", member.has_value);
					write_number(at, member_layout, "is_using", member.is_using);
				});
				write_number(record, layout, "alignment", type->alignment);
				write_number(record, layout, "is_scoped", structure->is_scoped);
				write_number(record, layout, "is_unrestricted", structure->is_unrestricted);
				write_number(record, layout, "is_packed", structure->is_packed);
				write_number(record, layout, "is_union", structure->is_union);
				break;
			}
			case TypeInfoVariant::UNION: {
				auto union_type = static_cast<const TypeInfoUnion*>(type);
				write_text(record, layout, "name", text_of(union_type->name));
				records("variants", union_type->variants.size(), [&](uint8_t* at, const TypeInfo* element_type, size_t i) {
					const TypeInfoStruct* variant_layout = as_struct(element_type);
					const UnionVariant& variant = union_type->variants[i];
					write_text(at, variant_layout, "name", text_of(variant.name));
					if (!variant.types.empty()) {
						auto pointers = reinterpret_cast<const uint8_t**>(allocate(8 * variant.types.size(), 8));
						auto offsets = reinterpret_cast<uint64_t*>(allocate(8 * variant.offsets.size(), 8));
						for (size_t j = 0; j < variant.types.size(); ++j) {
							pointers[j] = descriptor(variant.types[j]);
						}
						for (size_t j = 0; j < variant.offsets.size(); ++j) {
							offsets[j] = variant.offsets[j];
						}
						write_view(at, variant_layout, "types", pointers, variant.types.size());
						write_view(at, variant_layout, "offsets", offsets, variant.offsets.size());
					}
				});
				write_type(record, layout, "tag_type", union_type->null_is_none ? nullptr : union_type->tag_type);
				write_number(record, layout, "null_is_none", union_type->null_is_none);
				break;
			}
			case TypeInfoVariant::ANY:
			case TypeInfoVariant::BOOLEAN:
			case TypeInfoVariant::CHAR:
			case TypeInfoVariant::COMPLEX:
			case TypeInfoVariant::QUATERNION:
			case TypeInfoVariant::TYPE:
			case TypeInfoVariant::VOID:
				break;
		}
	}

}

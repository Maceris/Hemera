#include "middle_end/schema_writer.h"

#include <string_view>

#include "front_end/type.h"

namespace hemera {

	namespace {

		/*
		 * base/runtime/schema.hsc's writer, over the compiler's types rather than their descriptors. A descriptor is the
		 * type with plain aliases taken away (CompileTimeData::descriptor), so types are placed by that, and an array's
		 * dimensions, a function's inputs and a union's tag are what reflection.cpp's describe writes for them.
		 */
		constexpr uint16_t SCHEMA_VERSION = 1;

		std::string_view text_of(InternedString name) {
			return name != nullptr ? std::string_view(*name) : std::string_view();
		}

		uint8_t kind_of(TypeInfoVariant variant) {
			switch (variant) {
				case TypeInfoVariant::ALIAS: return 1;
				case TypeInfoVariant::ANY: return 2;
				case TypeInfoVariant::ARRAY: return 3;
				case TypeInfoVariant::BOOLEAN: return 4;
				case TypeInfoVariant::CHAR: return 5;
				case TypeInfoVariant::COMPLEX: return 6;
				case TypeInfoVariant::ENUM: return 7;
				case TypeInfoVariant::FLOAT: return 8;
				case TypeInfoVariant::FUNCTION: return 9;
				case TypeInfoVariant::INTEGER: return 10;
				case TypeInfoVariant::POINTER: return 11;
				case TypeInfoVariant::QUATERNION: return 12;
				case TypeInfoVariant::STRING: return 13;
				case TypeInfoVariant::STRUCT: return 14;
				case TypeInfoVariant::TYPE: return 15;
				case TypeInfoVariant::UNION: return 16;
				case TypeInfoVariant::VECTOR: return 17;
				// Past VOID, so the kinds before it keep their numbers
				case TypeInfoVariant::MATRIX: return 19;
				// An archetype's descriptor says VOID, as reflection.cpp's variant_name has it
				case TypeInfoVariant::ARCHETYPE:
				case TypeInfoVariant::VOID: return 18;
			}
			return 18;
		}

		uint8_t endianness_of(Endianness endianness) {
			return Endianness::BIG == endianness ? 1 : Endianness::LITTLE == endianness ? 2 : 3;
		}

		struct Writer {
			std::vector<uint8_t> bytes;
			std::vector<TypeInfo const*> types;

			void number(uint64_t value, size_t count) {
				for (size_t i = 0; i < count; ++i) {
					bytes.push_back(static_cast<uint8_t>((value >> (8 * i)) & 0xff));
				}
			}

			void flag(bool value) {
				bytes.push_back(value ? 1 : 0);
			}

			void name(InternedString text) {
				const std::string_view view = text_of(text);
				number(view.size(), 4);
				bytes.insert(bytes.end(), view.begin(), view.end());
			}

			size_t place(TypeInfo const* type) {
				TypeInfo const* found = get_base_type_or_alias(type);
				for (size_t i = 0; i < types.size(); ++i) {
					if (types[i] == found) {
						return i;
					}
				}
				types.push_back(found);
				return types.size() - 1;
			}

			void reference(TypeInfo const* type) {
				number(place(type), 4);
			}

			// The innermost element and each dimension of an array, outermost first, as its descriptor has them.
			static TypeInfo const* dimensions(TypeInfo const* type, std::vector<TypeInfoArray const*>& into) {
				TypeInfo const* element = type;
				while (element != nullptr && TypeInfoVariant::ARRAY == element->variant) {
					into.push_back(static_cast<TypeInfoArray const*>(element));
					element = get_base_type(static_cast<TypeInfoArray const*>(element)->element_type);
				}
				return into.back()->element_type;
			}

			void reach(TypeInfo const* type) {
				switch (type->variant) {
					case TypeInfoVariant::ALIAS:
						place(static_cast<TypeInfoAlias const*>(type)->base_type);
						break;
					case TypeInfoVariant::ARRAY: {
						std::vector<TypeInfoArray const*> each;
						place(dimensions(type, each));
						break;
					}
					case TypeInfoVariant::ENUM: {
						auto enumeration = static_cast<TypeInfoEnum const*>(type);
						place(enumeration->backing_type != nullptr ? enumeration->backing_type : BUILTIN_uint);
						break;
					}
					case TypeInfoVariant::FUNCTION: {
						auto function = static_cast<TypeInfoFunction const*>(type);
						for (const FunctionInput& input : function->input) {
							place(input.type);
						}
						for (const FunctionOutput& output : function->output) {
							place(output.type);
						}
						break;
					}
					case TypeInfoVariant::POINTER: {
						auto pointer = static_cast<TypeInfoPointer const*>(type);
						if (pointer->base_type != nullptr) {
							place(pointer->base_type);
						}
						break;
					}
					case TypeInfoVariant::STRUCT:
						for (const StructMember& member : static_cast<TypeInfoStruct const*>(type)->members) {
							place(member.member_type);
						}
						break;
					case TypeInfoVariant::UNION: {
						auto union_type = static_cast<TypeInfoUnion const*>(type);
						if (!union_type->null_is_none && union_type->tag_type != nullptr) {
							place(union_type->tag_type);
						}
						for (const UnionVariant& variant : union_type->variants) {
							for (TypeInfo* held : variant.types) {
								place(held);
							}
						}
						break;
					}
					case TypeInfoVariant::VECTOR:
						place(static_cast<TypeInfoVector const*>(type)->element_type);
						break;
					case TypeInfoVariant::MATRIX:
						place(static_cast<TypeInfoMatrix const*>(type)->element_type);
						break;
					case TypeInfoVariant::ANY:
					case TypeInfoVariant::ARCHETYPE:
					case TypeInfoVariant::BOOLEAN:
					case TypeInfoVariant::CHAR:
					case TypeInfoVariant::COMPLEX:
					case TypeInfoVariant::QUATERNION:
					case TypeInfoVariant::TYPE:
					case TypeInfoVariant::VOID:
					case TypeInfoVariant::FLOAT:
					case TypeInfoVariant::INTEGER:
					case TypeInfoVariant::STRING:
						break;
				}
			}

			void describe(TypeInfo const* type) {
				const TypeInfoVariant variant = type->variant;
				bytes.push_back(kind_of(variant));
				number(type->size, 8);
				switch (variant) {
					case TypeInfoVariant::ALIAS: {
						auto alias = static_cast<TypeInfoAlias const*>(type);
						name(alias->name);
						reference(alias->base_type);
						break;
					}
					case TypeInfoVariant::ARRAY: {
						std::vector<TypeInfoArray const*> each;
						reference(dimensions(type, each));
						number(each.size(), 4);
						for (TypeInfoArray const* dimension : each) {
							bytes.push_back(ArrayType::STATIC == dimension->array_type ? 1 : ArrayType::DYNAMIC == dimension->array_type ? 2 : 3);
							number(dimension->count, 8);
							flag(dimension->is_mutable);
						}
						break;
					}
					case TypeInfoVariant::ENUM: {
						auto enumeration = static_cast<TypeInfoEnum const*>(type);
						name(enumeration->name);
						reference(enumeration->backing_type != nullptr ? enumeration->backing_type : BUILTIN_uint);
						number(enumeration->members.size(), 4);
						for (size_t i = 0; i < enumeration->members.size(); ++i) {
							name(enumeration->members[i]);
							number(i < enumeration->values.size() ? enumeration->values[i] : 0, 8);
							number(0, 8);
						}
						break;
					}
					case TypeInfoVariant::FLOAT:
						bytes.push_back(endianness_of(static_cast<TypeInfoFloat const*>(type)->endianness));
						break;
					case TypeInfoVariant::FUNCTION: {
						auto function = static_cast<TypeInfoFunction const*>(type);
						number(function->input.size(), 4);
						for (const FunctionInput& input : function->input) {
							name(input.name);
							reference(input.type);
							flag(input.is_varargs);
							flag(input.is_escaping);
						}
						number(function->output.size(), 4);
						for (const FunctionOutput& output : function->output) {
							reference(output.type);
						}
						flag(function->never_returns);
						break;
					}
					case TypeInfoVariant::INTEGER: {
						auto integer = static_cast<TypeInfoInteger const*>(type);
						flag(integer->is_signed);
						bytes.push_back(endianness_of(integer->endianness));
						break;
					}
					case TypeInfoVariant::POINTER: {
						auto pointer = static_cast<TypeInfoPointer const*>(type);
						flag(pointer->base_type != nullptr);
						if (pointer->base_type != nullptr) {
							reference(pointer->base_type);
						}
						flag(pointer->is_relative);
						flag(pointer->is_mutable);
						break;
					}
					case TypeInfoVariant::STRING:
						flag(static_cast<TypeInfoString const*>(type)->is_raw);
						break;
					case TypeInfoVariant::STRUCT: {
						auto structure = static_cast<TypeInfoStruct const*>(type);
						name(structure->name);
						number(type->alignment, 8);
						flag(structure->is_packed);
						flag(structure->is_union);
						number(structure->members.size(), 4);
						for (const StructMember& member : structure->members) {
							name(member.name);
							reference(member.member_type);
							number(member.offset, 8);
							flag(member.is_using);
						}
						break;
					}
					case TypeInfoVariant::UNION: {
						auto union_type = static_cast<TypeInfoUnion const*>(type);
						name(union_type->name);
						flag(union_type->null_is_none);
						const bool tagged = !union_type->null_is_none && union_type->tag_type != nullptr;
						flag(tagged);
						if (tagged) {
							reference(union_type->tag_type);
						}
						number(union_type->variants.size(), 4);
						for (const UnionVariant& each : union_type->variants) {
							name(each.name);
							number(each.types.size(), 4);
							for (size_t i = 0; i < each.types.size(); ++i) {
								reference(each.types[i]);
								number(i < each.offsets.size() ? each.offsets[i] : 0, 8);
							}
						}
						break;
					}
					case TypeInfoVariant::VECTOR: {
						auto vector = static_cast<TypeInfoVector const*>(type);
						reference(vector->element_type);
						number(vector->count, 8);
						flag(vector->is_bits);
						break;
					}
					case TypeInfoVariant::MATRIX: {
						auto matrix = static_cast<TypeInfoMatrix const*>(type);
						reference(matrix->element_type);
						number(matrix->rows, 8);
						number(matrix->columns, 8);
						break;
					}
					case TypeInfoVariant::ANY:
					case TypeInfoVariant::ARCHETYPE:
					case TypeInfoVariant::BOOLEAN:
					case TypeInfoVariant::CHAR:
					case TypeInfoVariant::COMPLEX:
					case TypeInfoVariant::QUATERNION:
					case TypeInfoVariant::TYPE:
					case TypeInfoVariant::VOID:
						break;
				}
			}
		};
	}

	std::vector<uint8_t> write_schema(TypeInfo const* type) {
		if (get_base_type_or_alias(type) == nullptr) {
			return {};
		}
		Writer writer;
		writer.place(type);
		for (size_t at = 0; at < writer.types.size(); ++at) {
			writer.reach(writer.types[at]);
		}
		writer.bytes = { 0x48, 0x53, 0x43, 0x48 };
		writer.number(SCHEMA_VERSION, 2);
		writer.number(writer.types.size(), 4);
		// Every type is placed by now, so describing them adds none
		for (size_t i = 0; i < writer.types.size(); ++i) {
			writer.describe(writer.types[i]);
		}
		return writer.bytes;
	}
}

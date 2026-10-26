#pragma once

#include <cstdint>
#include <map>
#include <memory>
#include <mutex>
#include <set>
#include <string>
#include <string_view>
#include <vector>

namespace hemera {

	struct CompileTimeValue;
	struct ProgramInfo;
	struct TypeInfo;
	struct TypeInfoStruct;

	/// <summary>
	/// What the compiler makes for compile-time code while a program compiles (docs/compilation.md,
	/// Compile-Time Execution): records laid out like base/compiler's structs, like PackageInfo and the TypeInfo
	/// descriptors type values point to, in memory that lasts as long as the program's compilation. Compile-time
	/// code's own type values are these descriptors too, so a type from reflection equals the same type in code.
	/// </summary>
	class CompileTimeData {
	public:
		explicit CompileTimeData(ProgramInfo* program);
		CompileTimeData(const CompileTimeData&) = delete;
		CompileTimeData& operator=(const CompileTimeData&) = delete;

		/// <summary>
		/// size bytes, zeroed, aligned to alignment, that last as long as this does.
		/// </summary>
		uint8_t* allocate(size_t size, size_t alignment);

		/// <summary>
		/// base/compiler's struct called name, or null if it isn't laid out yet.
		/// </summary>
		const TypeInfoStruct* compiler_struct(std::string_view name);

		/// <summary>
		/// Zeroed records of one of base/compiler's structs, count of them in a row.
		/// </summary>
		uint8_t* new_records(const TypeInfoStruct* type, size_t count = 1);

		/// <summary>
		/// Where a struct's field is, through using, and its type. Reports nothing if it isn't there.
		/// </summary>
		static bool find_field(const TypeInfoStruct* type, std::string_view name, size_t& offset, const TypeInfo*& field_type);

		// Writing a record's field by name, as its type lays it out.
		void write_number(uint8_t* record, const TypeInfoStruct* type, std::string_view field, uint64_t value);
		void write_text(uint8_t* record, const TypeInfoStruct* type, std::string_view field, std::string_view text);
		void write_pointer(uint8_t* record, const TypeInfoStruct* type, std::string_view field, const void* pointer);
		void write_view(uint8_t* record, const TypeInfoStruct* type, std::string_view field, const void* data, size_t count);
		void write_type(uint8_t* record, const TypeInfoStruct* type, std::string_view field, const TypeInfo* value);
		void write_member(uint8_t* record, const TypeInfoStruct* type, std::string_view field, std::string_view member);
		void write_any(uint8_t* record, const TypeInfoStruct* type, std::string_view field, const void* data, const TypeInfo* value_type);
		/// <summary>
		/// Marks an optional field as holding a value, and gives where the value goes.
		/// </summary>
		uint8_t* write_some(uint8_t* record, const TypeInfoStruct* type, std::string_view field);

		// The same, at an address, for elements of arrays and optionals' values.
		static void write_number_at(uint8_t* at, size_t size, uint64_t value);
		void write_text_at(uint8_t* at, std::string_view text);
		static void write_view_at(uint8_t* at, const void* data, size_t count);
		void write_any_at(uint8_t* at, const void* data, const TypeInfo* value_type);
		static uint8_t* write_some_at(uint8_t* at, const TypeInfo* optional_type);

		/// <summary>
		/// A copy of text, with a 0 after it.
		/// </summary>
		const char* copy_text(std::string_view text);

		/// <summary>
		/// A value compile-time code gave, copied here with what its strings and views point to.
		/// </summary>
		const uint8_t* copy_value(const TypeInfo* type, const CompileTimeValue& value);

		/// <summary>
		/// A type's descriptor, made the first time it's asked for (docs/types.md, Type Values and Type
		/// Information). A plain alias is the type it names. Null if base/compiler isn't laid out yet.
		/// </summary>
		const uint8_t* descriptor(const TypeInfo* type);

		/// <summary>
		/// Every descriptor's address, and the type it describes.
		/// </summary>
		const std::map<uintptr_t, const TypeInfo*>& described_types() const {
			return types;
		}

		ProgramInfo* const program;

		/// <summary>
		/// Constants' values worked out for reflection (constant_values), by their declarations: the type and
		/// the value copied here, or null for one that couldn't be, so each one only runs once however often
		/// compile-time code asks for it, like a build check finding each package's PACKAGE_TIER.
		/// </summary>
		std::map<const void*, std::pair<const TypeInfo*, const uint8_t*>> constant_values;
		std::mutex constant_values_mutex;

	private:
		void describe(const TypeInfo* type, uint8_t* record, const TypeInfoStruct* layout);

		std::recursive_mutex mutex;
		std::vector<std::unique_ptr<uint8_t[]>> blocks;
		uint8_t* free_start = nullptr;
		size_t free_size = 0;
		std::map<const TypeInfo*, uint8_t*> descriptors;
		std::map<uintptr_t, const TypeInfo*> types;
		/// <summary>
		/// Descriptors made partial, of a type not laid out then or reaching one through a pointer, made again
		/// when asked for; those being made now; and whether what's being made has reached a partial one.
		/// </summary>
		std::set<const TypeInfo*> partial;
		std::set<const TypeInfo*> describing;
		bool reached_partial = false;
	};

	/// <summary>
	/// The program's compile-time data, made the first time it's needed.
	/// </summary>
	CompileTimeData& compile_time_data(ProgramInfo* program);

}

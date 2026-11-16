#pragma once

#include <compare>
#include <cstdint>
#include <map>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include "memory/allocator.h"

/*
 * What each name in a program refers to, for an editor (hemera --index, docs/compilation.md, The Name Index): the
 * names its code uses, recorded while it's checked, and then the index made from them, plain data that a build's
 * targets merge into.
 */
namespace hemera {

	struct Declaration;
	struct ProgramInfo;
	struct TypeInfo;
	struct Walk;
	namespace ast {
		struct Node;
	}

	/*
	 * The names a program's code uses, by the node each is used at: a declaration, or a struct's field. Kept on the
	 * program (ProgramInfo::name_uses) only when it's to be indexed, and filled from any thread while it's checked.
	 */
	struct NameUses {
		struct Use {
			// The file the use is in
			InternedString package_path = nullptr;
			InternedString file_name = nullptr;
			// What it names: a declaration, or the member called member of the struct type structure
			Declaration* declaration = nullptr;
			const TypeInfo* structure = nullptr;
			InternedString member = nullptr;
		};
		std::mutex mutex;
		std::unordered_map<const ast::Node*, Use> uses;
	};

	// That where, in walk's file, names declaration, if the walk's program is being indexed.
	void record_use(Walk& walk, const ast::Node* where, Declaration* declaration);

	// That where, in walk's file, names the member called member of the struct type structure, if being indexed.
	void record_member_use(Walk& walk, const ast::Node* where, const TypeInfo* structure, InternedString member);

	// A run of bytes in a file: the file as diagnostics name it, with / throughout, then the offset and length.
	struct IndexPlace {
		std::string file;
		uint32_t offset = 0;
		uint32_t length = 0;

		auto operator<=>(const IndexPlace&) const = default;
	};

	// Something a name can be declared as.
	struct IndexDeclaration {
		// Its name, where it's declared
		IndexPlace name;
		// From its first byte to its last, in the same file: a declaration's own tokens, not its doc comment
		uint32_t start = 0;
		uint32_t end = 0;
		// function, type, constant, field or local
		std::string kind;
		// Its type as the compiler writes it, for a value, a function or a field; empty for a type
		std::string type;
		// Its doc comment, parsed: the summary, the rest of the text, and each tag's kind, name and text
		std::string brief;
		std::string details;
		struct Tag {
			std::string tag;
			std::string name;
			std::string text;
		};
		std::vector<Tag> tags;
	};

	/*
	 * An index: every declaration, by where its name is, and every use, by where it is, of what it names, by
	 * where that's declared. Every use's target is among the declarations.
	 */
	struct NameIndex {
		std::map<IndexPlace, IndexDeclaration> declarations;
		std::map<IndexPlace, IndexPlace> uses;
	};

	/*
	 * program's declarations and the uses recorded while it was checked, added to index: every declaration it has,
	 * locals and fields included, and the uses in files under root_folder (the root package's folder, either
	 * separator), so a build's targets merge into one index. Code made while compiling, like what #insert puts in,
	 * is left out, as it isn't where its tokens say. A use's target is its generic declaration, not an instance.
	 */
	void add_to_index(NameIndex& index, ProgramInfo& program, std::string_view root_folder);
}

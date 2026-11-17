#pragma once

#include <cstdint>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <vector>

// The name index hemera --index writes (docs/compilation.md, The Name Index), read for the server's answers.
namespace hemera::lsp {

	// A declaration in the index.
	struct IndexedDeclaration {
		// Its file, as a path on disk with / throughout, base's mapped to where its files are
		std::string file;
		// Its name's offset and length, and its tokens' first and last byte, in bytes in the file the check read
		uint32_t name_offset = 0;
		uint32_t name_length = 0;
		uint32_t start = 0;
		uint32_t end = 0;
		// function, type, constant, field, member (an enum's), variant (a union's) or local
		std::string kind;
		std::string type;
		// For a field, member or variant, the type it's in; and the type whose members follow a . after it; by number
		std::optional<size_t> in;
		std::optional<size_t> of;
		/*
		 * For one inserted code made, its name, as where it's indexed is the #insert that put it there, and where its name
		 * is written in the quote, when it's written at all; empty otherwise
		 */
		std::string text;
		struct Written {
			std::string file;
			uint32_t offset = 0;
			uint32_t length = 0;
		};
		std::optional<Written> written;
		std::string brief;
		std::string details;
		struct Tag {
			std::string tag;
			std::string name;
			std::string text;
		};
		std::vector<Tag> tags;
	};

	// A use: the name used, in bytes in the file the check read, and the declaration it names, by number.
	struct IndexedUse {
		uint32_t offset = 0;
		uint32_t length = 0;
		size_t declaration = 0;
	};

	// An import: the name it's used by, in bytes in the file the check read, and the folder of the package it names.
	struct IndexedImport {
		uint32_t offset = 0;
		uint32_t length = 0;
		std::string folder;
	};

	// An index, as the server keeps it: by file, each file's uses and declarations in the order of their offsets.
	struct LoadedIndex {
		std::vector<IndexedDeclaration> declarations;
		// By path_key of the file
		std::map<std::string, std::vector<IndexedUse>> uses;
		std::map<std::string, std::vector<size_t>> declared;
		// Each file's path, as the index names it with / throughout, by path_key
		std::map<std::string, std::string> paths;
		// For a build package, the targets that read each file, by their names, by path_key; empty for a program
		std::map<std::string, std::vector<std::string>> readers;
		// Each file's imports, by path_key, in the order of their offsets
		std::map<std::string, std::vector<IndexedImport>> imports;
		/*
		 * The text the check read for each document that was open when it started, by path_key; a file that wasn't
		 * open was read from disk, and is taken to be as it is there.
		 */
		std::map<std::string, std::string> texts;

		// A name in a file: the declaration it names, by number, and where the name is, in bytes
		struct NameAt {
			size_t declaration = 0;
			uint32_t offset = 0;
			uint32_t length = 0;
		};

		/*
		 * The name at offset in a file (path_key), its ends included: a use there, or a declaration's own name.
		 * Empty when there's no name at offset.
		 */
		std::optional<NameAt> name_at(const std::string& file, size_t offset) const;

		/*
		 * Every place declaration is named, in every file: its uses and, with with_declaration, its own name, each as
		 * a file, by its path, and the offset and length of the name, in the text the check read.
		 */
		struct Place {
			std::string file;
			uint32_t offset = 0;
			uint32_t length = 0;
		};
		std::vector<Place> places_of(size_t declaration, bool with_declaration) const;
	};

	/*
	 * An index read from the JSON hemera --index writes. base_folder is where base's files are, with / throughout,
	 * which <base>/... names are mapped into; empty leaves them as they are. Empty when json isn't an index.
	 */
	std::optional<LoadedIndex> read_index(std::string_view json, const std::string& base_folder);

	/*
	 * A build package's index after a check of some of its targets: fresh, that check's, which is all of what checked
	 * found, merged into old, a check's of more of them. A file every target that read it before was checked for, or
	 * whose text either check read as an open document and that differs, is fresh's alone; any other file keeps old's
	 * uses beside fresh's, those of a declaration in a file that's fresh's alone found again there by where it's named,
	 * or dropped. readers is old's with checked's replaced by fresh's.
	 */
	LoadedIndex merged_index(const LoadedIndex& old, LoadedIndex fresh, const std::set<std::string>& checked);

	/*
	 * Where offset, in old_text, is in new_text, the text after one change: the same before the change, moved by
	 * what it added or removed after it, and nowhere inside it.
	 */
	std::optional<size_t> moved_forward(std::string_view old_text, std::string_view new_text, size_t offset);

	// Where offset, in new_text, was in old_text, the other way through the same change.
	std::optional<size_t> moved_back(std::string_view old_text, std::string_view new_text, size_t offset);
}

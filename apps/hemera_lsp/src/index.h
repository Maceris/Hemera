#pragma once

#include <cstdint>
#include <map>
#include <optional>
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
		// function, type, constant, field or local
		std::string kind;
		std::string type;
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

	// An index, as the server keeps it: by file, each file's uses and declarations in the order of their offsets.
	struct LoadedIndex {
		std::vector<IndexedDeclaration> declarations;
		// By path_key of the file
		std::map<std::string, std::vector<IndexedUse>> uses;
		std::map<std::string, std::vector<size_t>> declared;
		/*
		 * The text the check read for each document that was open when it started, by path_key; a file that wasn't
		 * open was read from disk, and is taken to be as it is there.
		 */
		std::map<std::string, std::string> texts;

		/*
		 * The declaration named at offset in a file (path_key): by a use there, or by a declaration's name there.
		 * Empty when there's no name at offset.
		 */
		std::optional<size_t> declaration_at(const std::string& file, size_t offset) const;

		/*
		 * Every place declaration is named, in every file: its uses and its own name, each as a file (path_key) and
		 * the offset and length of the name, in the text the check read.
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
	 * Where offset, in old_text, is in new_text, the text after one change: the same before the change, moved by
	 * what it added or removed after it, and nowhere inside it.
	 */
	std::optional<size_t> moved_forward(std::string_view old_text, std::string_view new_text, size_t offset);

	// Where offset, in new_text, was in old_text, the other way through the same change.
	std::optional<size_t> moved_back(std::string_view old_text, std::string_view new_text, size_t offset);
}

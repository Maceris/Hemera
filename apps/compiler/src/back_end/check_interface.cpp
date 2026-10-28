#include "back_end/check_interface.h"

#include <array>
#include <cstdint>
#include <cstring>
#include <format>
#include <map>
#include <optional>
#include <ostream>
#include <vector>

#include "llvm/BinaryFormat/ELF.h"
#include "llvm/Object/COFF.h"
#include "llvm/Object/ELFObjectFile.h"
#include "llvm/Object/ObjectFile.h"
#include "llvm/Support/Error.h"

namespace hemera {
	namespace {
		// base/runtime/libraries.hsc's LIBRARY_MAGIC, "HEMERAI1"
		constexpr uint64_t LIBRARY_MAGIC = 0x31494152454d4548ULL;
		// Where LibraryInterface's and LibraryExport's fields are, as base/runtime/libraries.hsc lays them out
		constexpr uint64_t INTERFACE_CONVENTION = 8;
		constexpr uint64_t INTERFACE_CONTEXT_HASH = 16;
		constexpr uint64_t INTERFACE_EXPORTS = 48;
		constexpr uint64_t EXPORT_NAME = 0;
		constexpr uint64_t EXPORT_TYPE_HASH = 16;
		constexpr uint64_t EXPORT_SIZE = 56;

		using Hash = std::array<uint8_t, 32>;

		struct Export {
			std::string name;
			Hash type_hash{};
		};

		// A typed library's interface record, as its file has it.
		struct Interface {
			uint64_t convention = 0;
			Hash context_hash{};
			std::vector<Export> exports;
		};

		/*
		 * A library's file, read by the addresses it was linked at: its sections' bytes, and for ELF, where its
		 * relative relocations put addresses, which its sections hold only as zeros.
		 */
		class Image {
		public:
			explicit Image(llvm::object::ObjectFile& object_) : object(object_) {
				if (auto* elf = llvm::dyn_cast<llvm::object::ELF64LEObjectFile>(&object)) {
					for (const llvm::object::SectionRef& section : elf->sections()) {
						llvm::Expected<llvm::StringRef> name = section.getName();
						if (!name) {
							llvm::consumeError(name.takeError());
							continue;
						}
						if (*name != ".rela.dyn") {
							continue;
						}
						llvm::Expected<llvm::StringRef> contents = section.getContents();
						if (!contents) {
							llvm::consumeError(contents.takeError());
							continue;
						}
						for (size_t at = 0; at + 24 <= contents->size(); at += 24) {
							uint64_t offset = 0, info = 0, addend = 0;
							std::memcpy(&offset, contents->data() + at, 8);
							std::memcpy(&info, contents->data() + at + 8, 8);
							std::memcpy(&addend, contents->data() + at + 16, 8);
							const uint32_t type = static_cast<uint32_t>(info);
							if (type == llvm::ELF::R_X86_64_RELATIVE || type == llvm::ELF::R_AARCH64_RELATIVE) {
								relocated[offset] = addend;
							}
						}
					}
				}
			}

			// count bytes at address, or false if no section has them all.
			bool read(uint64_t address, void* into, size_t count) const {
				for (const llvm::object::SectionRef& section : object.sections()) {
					const uint64_t start = section.getAddress();
					if (address < start || address + count > start + section.getSize()) {
						continue;
					}
					llvm::Expected<llvm::StringRef> contents = section.getContents();
					if (!contents) {
						llvm::consumeError(contents.takeError());
						return false;
					}
					if (address - start + count > contents->size()) {
						return false;
					}
					std::memcpy(into, contents->data() + (address - start), count);
					return true;
				}
				return false;
			}

			std::optional<uint64_t> word(uint64_t address) const {
				uint64_t value = 0;
				if (!read(address, &value, 8)) {
					return std::nullopt;
				}
				return value;
			}

			// The address a pointer at address holds, once the library's relocated where it was linked to be.
			std::optional<uint64_t> pointer(uint64_t address) const {
				auto found = relocated.find(address);
				if (found != relocated.end()) {
					return found->second;
				}
				return word(address);
			}

			// Where hemera_interface is: an ELF library's entry, or a DLL's export of that name.
			std::optional<uint64_t> interface_address() const {
				if (auto* elf = llvm::dyn_cast<llvm::object::ELF64LEObjectFile>(&object)) {
					return elf->getELFFile().getHeader().e_entry;
				}
				if (auto* coff = llvm::dyn_cast<llvm::object::COFFObjectFile>(&object)) {
					for (const llvm::object::ExportDirectoryEntryRef& entry : coff->export_directories()) {
						llvm::StringRef name;
						uint32_t rva = 0;
						if (entry.getSymbolName(name) || entry.getExportRVA(rva)) {
							continue;
						}
						if (name == "hemera_interface") {
							return coff->getImageBase() + rva;
						}
					}
				}
				return std::nullopt;
			}

		private:
			llvm::object::ObjectFile& object;
			std::map<uint64_t, uint64_t> relocated;
		};

		// A string's text: its count, then a pointer to its bytes.
		std::optional<std::string> read_string(const Image& image, uint64_t address) {
			std::optional<uint64_t> count = image.word(address);
			std::optional<uint64_t> data = image.pointer(address + 8);
			if (!count || !data || *count > 4096) {
				return std::nullopt;
			}
			std::string text(*count, '\0');
			if (*count > 0 && !image.read(*data, text.data(), text.size())) {
				return std::nullopt;
			}
			return text;
		}

		// The interface record of the typed library at path, or why it can't be read.
		std::optional<Interface> read_interface(const std::string& path, std::string& why) {
			llvm::Expected<llvm::object::OwningBinary<llvm::object::Binary>> binary = llvm::object::createBinary(path);
			if (!binary) {
				why = llvm::toString(binary.takeError());
				return std::nullopt;
			}
			auto* object = llvm::dyn_cast<llvm::object::ObjectFile>(binary->getBinary());
			if (object == nullptr) {
				why = "it isn't an object file";
				return std::nullopt;
			}
			const Image image(*object);
			std::optional<uint64_t> at = image.interface_address();
			std::optional<uint64_t> magic = at ? image.word(*at) : std::nullopt;
			if (!at || !magic || *magic != LIBRARY_MAGIC) {
				why = "it has no interface record";
				return std::nullopt;
			}
			Interface result;
			std::optional<uint64_t> convention = image.word(*at + INTERFACE_CONVENTION);
			std::optional<uint64_t> count = image.word(*at + INTERFACE_EXPORTS);
			std::optional<uint64_t> exports = image.pointer(*at + INTERFACE_EXPORTS + 8);
			if (!convention || !count || (*count > 0 && !exports) || *count > 100000
				|| !image.read(*at + INTERFACE_CONTEXT_HASH, result.context_hash.data(), 32)) {
				why = "its interface record can't be read";
				return std::nullopt;
			}
			result.convention = *convention;
			for (uint64_t i = 0; i < *count; ++i) {
				const uint64_t entry = *exports + i * EXPORT_SIZE;
				Export each;
				std::optional<std::string> name = read_string(image, entry + EXPORT_NAME);
				if (!name || !image.read(entry + EXPORT_TYPE_HASH, each.type_hash.data(), 32)) {
					why = std::format("its interface record's export {} can't be read", i);
					return std::nullopt;
				}
				each.name = *name;
				result.exports.push_back(std::move(each));
			}
			return result;
		}
	}

	int check_interface(const std::string& old_library, const std::string& new_library, std::ostream& out) {
		std::string why;
		std::optional<Interface> before = read_interface(old_library, why);
		if (!before) {
			out << std::format("{} can't be read as a typed library: {}\n", old_library, why);
			return 2;
		}
		std::optional<Interface> after = read_interface(new_library, why);
		if (!after) {
			out << std::format("{} can't be read as a typed library: {}\n", new_library, why);
			return 2;
		}
		bool compatible = true;
		if (before->convention != after->convention || before->context_hash != after->context_hash) {
			out << "it's built for another calling convention or Context\n";
			compatible = false;
		}
		for (const Export& each : before->exports) {
			const Export* found = nullptr;
			for (const Export& candidate : after->exports) {
				if (candidate.name == each.name) {
					found = &candidate;
				}
			}
			if (found == nullptr) {
				out << std::format("{}: it isn't exported any more\n", each.name);
				compatible = false;
			}
			else if (found->type_hash != each.type_hash) {
				out << std::format("{}: its type changed\n", each.name);
				compatible = false;
			}
		}
		if (compatible) {
			out << std::format("compatible: every one of the {} exports is there, with the same type\n", before->exports.size());
		}
		return compatible ? 0 : 1;
	}
}

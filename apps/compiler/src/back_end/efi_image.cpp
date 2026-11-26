#include "back_end/efi_image.h"

#include <algorithm>
#include <cstdint>
#include <format>
#include <fstream>
#include <map>
#include <vector>

#include "llvm/BinaryFormat/ELF.h"
#include "llvm/Object/ELF.h"
#include "llvm/Support/Error.h"
#include "llvm/Support/MemoryBuffer.h"

namespace hemera {

	namespace {

		// Where sections are placed in memory and in the file; the headers take the first page of memory
		constexpr uint64_t SECTION_ALIGNMENT = 0x1000;
		constexpr uint64_t FILE_ALIGNMENT = 0x200;
		constexpr uint64_t IMAGE_BASE = 0;

		// PE32+ (Microsoft's PE format specification): the optional header with 16 data directories, and a section header
		constexpr uint32_t OPTIONAL_HEADER_SIZE = 240;
		constexpr uint32_t SECTION_HEADER_SIZE = 40;
		constexpr uint32_t DOS_HEADER_SIZE = 64;
		constexpr uint32_t DATA_DIRECTORIES = 16;
		constexpr uint32_t BASE_RELOCATION_DIRECTORY = 5;
		constexpr uint16_t SUBSYSTEM_EFI_APPLICATION = 10;
		constexpr uint16_t RELOCATION_DIR64 = 10;

		constexpr uint32_t SCN_CODE = 0x20;
		constexpr uint32_t SCN_INITIALIZED_DATA = 0x40;
		constexpr uint32_t SCN_DISCARDABLE = 0x02000000;
		constexpr uint32_t SCN_EXECUTE = 0x20000000;
		constexpr uint32_t SCN_READ = 0x40000000;
		constexpr uint32_t SCN_WRITE = 0x80000000;

		uint64_t align_up(uint64_t value, uint64_t alignment) {
			return (value + alignment - 1) / alignment * alignment;
		}

		struct Section {
			std::string name;
			uint64_t address = 0;
			uint64_t memory_size = 0;
			std::vector<uint8_t> data;
			uint32_t characteristics = 0;
		};

		// Little-endian writes into a growing buffer
		struct Writer {
			std::vector<uint8_t> bytes;

			void u8(uint8_t value) { bytes.push_back(value); }
			void u16(uint16_t value) { for (int i = 0; i < 2; ++i) bytes.push_back(static_cast<uint8_t>(value >> (8 * i))); }
			void u32(uint32_t value) { for (int i = 0; i < 4; ++i) bytes.push_back(static_cast<uint8_t>(value >> (8 * i))); }
			void u64(uint64_t value) { for (int i = 0; i < 8; ++i) bytes.push_back(static_cast<uint8_t>(value >> (8 * i))); }
			void pad_to(size_t size) { bytes.resize(std::max(bytes.size(), size), 0); }
		};

		// The PE machine for an ELF one, or 0 for one UEFI has no images for
		uint16_t pe_machine(uint16_t elf_machine) {
			switch (elf_machine) {
			case llvm::ELF::EM_RISCV: return 0x5064;
			case llvm::ELF::EM_AARCH64: return 0xaa64;
			case llvm::ELF::EM_X86_64: return 0x8664;
			default: return 0;
			}
		}

		// The ELF machine's relative relocation, the only kind a UEFI image's can be made from
		uint32_t relative_relocation(uint16_t elf_machine) {
			switch (elf_machine) {
			case llvm::ELF::EM_RISCV: return llvm::ELF::R_RISCV_RELATIVE;
			case llvm::ELF::EM_AARCH64: return llvm::ELF::R_AARCH64_RELATIVE;
			default: return llvm::ELF::R_X86_64_RELATIVE;
			}
		}

		/*
		 * The base relocation table: a block for each 4 KiB page with a relocation, its RVA and size, then an entry of
		 * the type and the offset in the page for each, padded to 4 bytes with an ABSOLUTE entry, which does nothing.
		 */
		std::vector<uint8_t> base_relocations(const std::vector<uint64_t>& addresses) {
			std::map<uint64_t, std::vector<uint16_t>> pages;
			for (uint64_t address : addresses) {
				pages[address & ~(SECTION_ALIGNMENT - 1)].push_back(
					static_cast<uint16_t>(RELOCATION_DIR64 << 12 | (address & (SECTION_ALIGNMENT - 1))));
			}
			Writer table;
			for (auto& [page, entries] : pages) {
				std::sort(entries.begin(), entries.end());
				if (entries.size() % 2 != 0) {
					entries.push_back(0);
				}
				table.u32(static_cast<uint32_t>(page));
				table.u32(static_cast<uint32_t>(8 + entries.size() * 2));
				for (uint16_t entry : entries) {
					table.u16(entry);
				}
			}
			return table.bytes;
		}

		bool fail(std::string& error, std::string message) {
			error = std::move(message);
			return false;
		}

	}

	bool write_efi_image(const std::string& elf_path, const std::string& pe_path, std::string& error) {
		llvm::ErrorOr<std::unique_ptr<llvm::MemoryBuffer>> buffer = llvm::MemoryBuffer::getFile(elf_path);
		if (!buffer) {
			return fail(error, std::format("the linked program {} couldn't be read", elf_path));
		}
		llvm::Expected<llvm::object::ELF64LEFile> parsed = llvm::object::ELF64LEFile::create((*buffer)->getBuffer());
		if (!parsed) {
			return fail(error, std::format("the linked program isn't a 64-bit little-endian ELF: {}", llvm::toString(parsed.takeError())));
		}
		const llvm::object::ELF64LEFile& elf = *parsed;
		const auto& header = elf.getHeader();
		const uint16_t machine = pe_machine(header.e_machine);
		if (machine == 0) {
			return fail(error, "the linked program is for a machine UEFI has no images for");
		}
		if (header.e_type != llvm::ELF::ET_DYN) {
			return fail(error, "the linked program isn't position-independent, so it can't be relocated as a UEFI image is");
		}
		const llvm::StringRef file = (*buffer)->getBuffer();

		// Each loadable segment a section
		auto program_headers = elf.program_headers();
		if (!program_headers) {
			return fail(error, llvm::toString(program_headers.takeError()));
		}
		std::vector<Section> sections;
		for (const auto& segment : *program_headers) {
			if (segment.p_type != llvm::ELF::PT_LOAD || segment.p_memsz == 0) {
				continue;
			}
			if (segment.p_vaddr % SECTION_ALIGNMENT != 0 || segment.p_vaddr < SECTION_ALIGNMENT) {
				return fail(error, std::format("a loadable segment is at {:#x}, which isn't a page past the image's headers",
					static_cast<uint64_t>(segment.p_vaddr)));
			}
			if (segment.p_offset + segment.p_filesz > file.size()) {
				return fail(error, "a loadable segment runs past the end of the linked program");
			}
			Section section;
			section.address = segment.p_vaddr;
			section.memory_size = segment.p_memsz;
			const uint8_t* start = reinterpret_cast<const uint8_t*>(file.data()) + segment.p_offset;
			section.data.assign(start, start + segment.p_filesz);
			if (segment.p_flags & llvm::ELF::PF_X) {
				section.name = ".text";
				section.characteristics = SCN_CODE | SCN_EXECUTE | SCN_READ;
			}
			else if (segment.p_flags & llvm::ELF::PF_W) {
				section.name = ".data";
				section.characteristics = SCN_INITIALIZED_DATA | SCN_READ | SCN_WRITE;
			}
			else {
				section.name = ".rdata";
				section.characteristics = SCN_INITIALIZED_DATA | SCN_READ;
			}
			sections.push_back(std::move(section));
		}
		if (sections.empty()) {
			return fail(error, "the linked program has nothing to load");
		}
		std::sort(sections.begin(), sections.end(), [](const Section& a, const Section& b) { return a.address < b.address; });
		for (size_t i = 1; i < sections.size(); ++i) {
			if (sections[i - 1].address + sections[i - 1].memory_size > sections[i].address) {
				return fail(error, "two loadable segments overlap");
			}
		}

		/*
		 * The dynamic relocations: each relative one's addend, the address it stands for, written where it applies,
		 * as the value the image has at base 0, and its address kept for the base relocation table
		 */
		auto elf_sections = elf.sections();
		if (!elf_sections) {
			return fail(error, llvm::toString(elf_sections.takeError()));
		}
		std::vector<uint64_t> relocated;
		const uint32_t relative = relative_relocation(header.e_machine);
		for (const auto& elf_section : *elf_sections) {
			if (elf_section.sh_type == llvm::ELF::SHT_REL || elf_section.sh_type == llvm::ELF::SHT_RELR) {
				return fail(error, "the linked program has REL or RELR relocations, where a UEFI image's are made from RELA ones");
			}
			if (elf_section.sh_type != llvm::ELF::SHT_RELA || !(elf_section.sh_flags & llvm::ELF::SHF_ALLOC)) {
				continue;
			}
			auto relocations = elf.relas(elf_section);
			if (!relocations) {
				return fail(error, llvm::toString(relocations.takeError()));
			}
			for (const auto& relocation : *relocations) {
				const uint32_t type = relocation.getType(false);
				if (type != relative) {
					return fail(error, std::format("the relocation at {:#x} is of type {}, which a UEFI image can't have: only "
						"relative ones, of addresses in the program", static_cast<uint64_t>(relocation.r_offset), type));
				}
				const uint64_t address = relocation.r_offset;
				auto in = std::find_if(sections.begin(), sections.end(), [&](const Section& section) {
					return address >= section.address && address + 8 <= section.address + section.data.size();
				});
				if (in == sections.end()) {
					return fail(error, std::format("the relocation at {:#x} isn't in the program's loaded bytes", address));
				}
				const uint64_t value = IMAGE_BASE + static_cast<uint64_t>(relocation.r_addend);
				for (int i = 0; i < 8; ++i) {
					in->data[address - in->address + static_cast<uint64_t>(i)] = static_cast<uint8_t>(value >> (8 * i));
				}
				relocated.push_back(address);
			}
		}
		if (!relocated.empty()) {
			Section reloc;
			reloc.name = ".reloc";
			reloc.address = align_up(sections.back().address + sections.back().memory_size, SECTION_ALIGNMENT);
			reloc.data = base_relocations(relocated);
			reloc.memory_size = reloc.data.size();
			reloc.characteristics = SCN_INITIALIZED_DATA | SCN_READ | SCN_DISCARDABLE;
			sections.push_back(std::move(reloc));
		}

		const uint64_t headers_size = align_up(DOS_HEADER_SIZE + 4 + 20 + OPTIONAL_HEADER_SIZE
			+ SECTION_HEADER_SIZE * sections.size(), FILE_ALIGNMENT);
		const uint64_t image_size = align_up(sections.back().address + sections.back().memory_size, SECTION_ALIGNMENT);
		uint64_t code_size = 0;
		uint64_t data_size = 0;
		uint64_t code_base = 0;
		for (const Section& section : sections) {
			if (section.characteristics & SCN_CODE) {
				code_size += align_up(section.memory_size, SECTION_ALIGNMENT);
				code_base = code_base == 0 ? section.address : code_base;
			}
			else {
				data_size += align_up(section.memory_size, SECTION_ALIGNMENT);
			}
		}
		if (image_size > 0xffffffffull) {
			return fail(error, "the program is bigger than a PE image can be");
		}

		Writer out;
		// The DOS header: its signature, and where the PE header is
		out.u16(0x5a4d);
		out.pad_to(0x3c);
		out.u32(DOS_HEADER_SIZE);
		// The PE signature and the COFF header: no symbols, an executable image that can be anywhere in 64 bits
		out.u32(0x00004550);
		out.u16(machine);
		out.u16(static_cast<uint16_t>(sections.size()));
		out.u32(0);
		out.u32(0);
		out.u32(0);
		out.u16(OPTIONAL_HEADER_SIZE);
		out.u16(0x0002 | 0x0020);
		// The optional header, PE32+
		out.u16(0x20b);
		out.u8(0);
		out.u8(0);
		out.u32(static_cast<uint32_t>(code_size));
		out.u32(static_cast<uint32_t>(data_size));
		out.u32(0);
		out.u32(static_cast<uint32_t>(header.e_entry));
		out.u32(static_cast<uint32_t>(code_base));
		out.u64(IMAGE_BASE);
		out.u32(static_cast<uint32_t>(SECTION_ALIGNMENT));
		out.u32(static_cast<uint32_t>(FILE_ALIGNMENT));
		// Operating system, image and subsystem versions, and Win32VersionValue
		for (int i = 0; i < 6; ++i) {
			out.u16(0);
		}
		out.u32(0);
		out.u32(static_cast<uint32_t>(image_size));
		out.u32(static_cast<uint32_t>(headers_size));
		out.u32(0);
		out.u16(SUBSYSTEM_EFI_APPLICATION);
		// DYNAMIC_BASE and NX_COMPAT: relocatable, and each section's protection can be what it says
		out.u16(0x0040 | 0x0100);
		// Stack and heap reserves and commits, which the firmware doesn't use
		out.u64(0x100000);
		out.u64(0x1000);
		out.u64(0x100000);
		out.u64(0x1000);
		out.u32(0);
		out.u32(DATA_DIRECTORIES);
		for (uint32_t directory = 0; directory < DATA_DIRECTORIES; ++directory) {
			const bool relocations = directory == BASE_RELOCATION_DIRECTORY && !relocated.empty();
			out.u32(relocations ? static_cast<uint32_t>(sections.back().address) : 0);
			out.u32(relocations ? static_cast<uint32_t>(sections.back().data.size()) : 0);
		}
		// The section headers, each section's bytes following the headers in turn
		uint64_t raw_offset = headers_size;
		for (const Section& section : sections) {
			char name[8] = {};
			std::copy_n(section.name.data(), std::min<size_t>(section.name.size(), 8), name);
			for (char c : name) {
				out.u8(static_cast<uint8_t>(c));
			}
			const uint64_t raw_size = align_up(section.data.size(), FILE_ALIGNMENT);
			out.u32(static_cast<uint32_t>(section.memory_size));
			out.u32(static_cast<uint32_t>(section.address));
			out.u32(static_cast<uint32_t>(raw_size));
			out.u32(raw_size == 0 ? 0 : static_cast<uint32_t>(raw_offset));
			out.u32(0);
			out.u32(0);
			out.u16(0);
			out.u16(0);
			out.u32(section.characteristics);
			raw_offset += raw_size;
		}
		out.pad_to(headers_size);
		for (const Section& section : sections) {
			out.bytes.insert(out.bytes.end(), section.data.begin(), section.data.end());
			out.pad_to(align_up(out.bytes.size(), FILE_ALIGNMENT));
		}

		std::ofstream stream(pe_path, std::ios::binary | std::ios::trunc);
		stream.write(reinterpret_cast<const char*>(out.bytes.data()), static_cast<std::streamsize>(out.bytes.size()));
		if (!stream) {
			return fail(error, std::format("the image {} couldn't be written", pe_path));
		}
		return true;
	}

}

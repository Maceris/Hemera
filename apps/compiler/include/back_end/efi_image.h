#pragma once

#include <string>

namespace hemera {
	/*
	 * Make a UEFI application, a PE32+ image with the EFI application subsystem, from an ELF that ld.lld linked for it,
	 * as edk2's GenFw does, for targets lld-link can't link, like RISC-V (docs/compilation.md, UEFI Applications).
	 *
	 * The ELF must be position-independent (ET_DYN), with every loadable segment's address a multiple of 4 KiB and at
	 * least 4 KiB, since the image's headers are in its first page; each address is kept as the section's RVA, so the
	 * image's base is 0. Its only dynamic relocations may be relative ones, which become DIR64 base relocations, their
	 * addends written in place. Each loadable segment becomes a section, .text if it's executable, .data if it's
	 * writable and .rdata otherwise, followed by .reloc; nothing else is kept, debug info included.
	 *
	 * @param elf_path The linked ELF, read and left as it is.
	 * @param pe_path Where the image is written, replacing any file there.
	 * @param error Set to why, in a sentence without its subject, when the image can't be made; untouched otherwise.
	 * @return Whether the image was written.
	 */
	bool write_efi_image(const std::string& elf_path, const std::string& pe_path, std::string& error);
}

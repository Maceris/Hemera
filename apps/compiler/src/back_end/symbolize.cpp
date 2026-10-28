#include "back_end/symbolize.h"

#include <algorithm>
#include <cstdint>
#include <format>
#include <optional>
#include <ostream>

#include "llvm/BinaryFormat/ELF.h"
#include "llvm/DebugInfo/Symbolize/Symbolize.h"
#include "llvm/Object/COFF.h"
#include "llvm/Object/ELFObjectFile.h"
#include "llvm/Object/ObjectFile.h"
#include "llvm/Support/Error.h"

namespace hemera {
	namespace {
		/*
		 * Where the image starts when it's loaded where it asks to be: what offsets are from. For
		 * PE/COFF, the image base; for ELF, the lowest load segment's page, which is where its headers
		 * are (__ehdr_start) when they're loaded, 0 for one that's position-independent, and where a
		 * kernel's image starts when a linker script leaves them out.
		 */
		std::optional<uint64_t> preferred_base(const llvm::object::ObjectFile& object) {
			if (auto* coff = llvm::dyn_cast<llvm::object::COFFObjectFile>(&object)) {
				return coff->getImageBase();
			}
			if (auto* elf = llvm::dyn_cast<llvm::object::ELF64LEObjectFile>(&object)) {
				auto headers = elf->getELFFile().program_headers();
				if (!headers) {
					llvm::consumeError(headers.takeError());
					return std::nullopt;
				}
				std::optional<uint64_t> lowest;
				for (const auto& header : *headers) {
					if (llvm::ELF::PT_LOAD == header.p_type && (!lowest || header.p_vaddr < *lowest)) {
						lowest = header.p_vaddr;
					}
				}
				return lowest.has_value() ? *lowest & ~uint64_t{ 0xfff } : 0;
			}
			return std::nullopt;
		}

		// A hexadecimal offset, with or without 0x.
		std::optional<uint64_t> parse_offset(const std::string& text) {
			std::string digits = text;
			if (digits.starts_with("0x") || digits.starts_with("0X")) {
				digits = digits.substr(2);
			}
			if (digits.empty()) {
				return std::nullopt;
			}
			uint64_t value = 0;
			for (char c : digits) {
				uint64_t digit = 0;
				if (c >= '0' && c <= '9') {
					digit = static_cast<uint64_t>(c - '0');
				}
				else if (c >= 'a' && c <= 'f') {
					digit = static_cast<uint64_t>(c - 'a' + 10);
				}
				else if (c >= 'A' && c <= 'F') {
					digit = static_cast<uint64_t>(c - 'A' + 10);
				}
				else {
					return std::nullopt;
				}
				value = value * 16 + digit;
			}
			return value;
		}
	}

	int symbolize(const std::string& program, const std::vector<std::string>& offsets, std::ostream& out) {
		auto binary = llvm::object::createBinary(program);
		if (!binary) {
			out << std::format("can't read {}: {}\n", program, llvm::toString(binary.takeError()));
			return 1;
		}
		auto* object = llvm::dyn_cast<llvm::object::ObjectFile>(binary->getBinary());
		std::optional<uint64_t> base = object != nullptr ? preferred_base(*object) : std::nullopt;
		if (!base) {
			out << std::format("{} isn't a PE/COFF or 64-bit ELF program\n", program);
			return 1;
		}
		llvm::symbolize::LLVMSymbolizer::Options options;
		options.Demangle = false;
		llvm::symbolize::LLVMSymbolizer symbolizer(options);
		for (const std::string& text : offsets) {
			std::optional<uint64_t> offset = parse_offset(text);
			if (!offset || *offset == 0) {
				out << std::format("{}: not an offset\n", text);
				continue;
			}
			out << std::format("0x{:x}\n", *offset);
			// A return address, which may be just past a call that ends its function: the call's
			const llvm::object::SectionedAddress address{ *base + *offset - 1, llvm::object::SectionedAddress::UndefSection };
			auto frames = symbolizer.symbolizeInlinedCode(program, address);
			if (!frames) {
				out << std::format("    {}\n", llvm::toString(frames.takeError()));
				continue;
			}
			const uint32_t count = frames->getNumberOfFrames();
			if (count == 0) {
				out << "    ??\n";
				continue;
			}
			for (uint32_t i = 0; i < count; ++i) {
				const llvm::DILineInfo& frame = frames->getFrame(i);
				const std::string function = frame.FunctionName == llvm::DILineInfo::BadString ? "??" : frame.FunctionName;
				std::string where;
				if (frame.FileName != llvm::DILineInfo::BadString) {
					// Files are named as the program names them: <base>/..., <std>/..., or relative to its package
					std::string file = frame.FileName;
					std::replace(file.begin(), file.end(), '\\', '/');
					for (const char* root : { "<base>", "<std>" }) {
						const size_t embedded = file.find(root);
						if (embedded != std::string::npos) {
							file = file.substr(embedded);
						}
					}
					if (file.starts_with("./")) {
						file = file.substr(2);
					}
					where = frame.Column > 0 ? std::format(" at {}:{}:{}", file, frame.Line, frame.Column)
						: std::format(" at {}:{}", file, frame.Line);
				}
				// Every frame but the last was inlined into the one after it
				out << std::format("    {}{}{}\n", function, where, i + 1 < count ? ", inlined" : "");
			}
		}
		return 0;
	}
}

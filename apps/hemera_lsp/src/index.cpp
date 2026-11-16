#include "index.h"

#include <algorithm>

#include "features.h"
#include "uri.h"

#include "llvm/Support/JSON.h"

namespace hemera::lsp {

	using llvm::json::Array;
	using llvm::json::Object;
	using llvm::json::Value;

	std::optional<size_t> LoadedIndex::declaration_at(const std::string& file, size_t offset) const {
		if (auto found = uses.find(file); found != uses.end()) {
			// The last use starting at or before offset, if offset is inside it
			const std::vector<IndexedUse>& in_file = found->second;
			auto after = std::upper_bound(in_file.begin(), in_file.end(), offset,
				[](size_t at, const IndexedUse& use) { return at < use.offset; });
			if (after != in_file.begin()) {
				const IndexedUse& use = *(after - 1);
				if (offset <= static_cast<size_t>(use.offset) + use.length) {
					return use.declaration;
				}
			}
		}
		if (auto found = declared.find(file); found != declared.end()) {
			for (const size_t number : found->second) {
				const IndexedDeclaration& declaration = declarations[number];
				if (declaration.name_offset <= offset && offset <= static_cast<size_t>(declaration.name_offset) + declaration.name_length) {
					return number;
				}
			}
		}
		return std::nullopt;
	}

	std::vector<LoadedIndex::Place> LoadedIndex::places_of(size_t declaration, bool with_declaration) const {
		std::vector<Place> found;
		if (declaration >= declarations.size()) {
			return found;
		}
		if (with_declaration) {
			const IndexedDeclaration& declared_at = declarations[declaration];
			found.push_back(Place{ path_key(declared_at.file), declared_at.name_offset, declared_at.name_length });
		}
		for (const auto& [file, in_file] : uses) {
			for (const IndexedUse& use : in_file) {
				if (use.declaration == declaration) {
					found.push_back(Place{ file, use.offset, use.length });
				}
			}
		}
		return found;
	}

	// A number from a JSON array, or 0
	static uint32_t number_at(const Array& array, size_t i) {
		return i < array.size() ? static_cast<uint32_t>(array[i].getAsInteger().value_or(0)) : 0;
	}

	static std::string text_of(const Object& object, llvm::StringRef key) {
		return object.getString(key).value_or("").str();
	}

	std::optional<LoadedIndex> read_index(std::string_view json, const std::string& base_folder) {
		llvm::Expected<Value> parsed = llvm::json::parse(llvm::StringRef(json.data(), json.size()));
		if (!parsed) {
			llvm::consumeError(parsed.takeError());
			return std::nullopt;
		}
		const Object* root = parsed->getAsObject();
		const Array* files = root != nullptr ? root->getArray("files") : nullptr;
		const Array* declarations = root != nullptr ? root->getArray("declarations") : nullptr;
		const Array* uses = root != nullptr ? root->getArray("uses") : nullptr;
		if (files == nullptr || declarations == nullptr || uses == nullptr || root->getInteger("version") != 1) {
			return std::nullopt;
		}
		std::vector<std::string> paths;
		for (const Value& file : *files) {
			std::string path = file.getAsString().value_or("").str();
			if (path.starts_with("<base>/") && !base_folder.empty()) {
				path = base_folder + path.substr(std::string_view("<base>").size());
			}
			paths.push_back(std::move(path));
		}
		LoadedIndex index;
		for (const Value& entry : *declarations) {
			const Object* object = entry.getAsObject();
			const Array* name = object != nullptr ? object->getArray("name") : nullptr;
			const Array* span = object != nullptr ? object->getArray("span") : nullptr;
			const size_t file = object != nullptr ? static_cast<size_t>(object->getInteger("file").value_or(-1)) : paths.size();
			IndexedDeclaration declaration;
			if (name != nullptr && span != nullptr && file < paths.size()) {
				declaration.file = paths[file];
				declaration.name_offset = number_at(*name, 0);
				declaration.name_length = number_at(*name, 1);
				declaration.start = number_at(*span, 0);
				declaration.end = number_at(*span, 1);
				declaration.kind = text_of(*object, "kind");
				declaration.type = text_of(*object, "type");
				declaration.brief = text_of(*object, "brief");
				declaration.details = text_of(*object, "details");
				if (const Array* tags = object->getArray("tags")) {
					for (const Value& tag : *tags) {
						const Array* parts = tag.getAsArray();
						if (parts != nullptr && parts->size() == 3) {
							declaration.tags.push_back(IndexedDeclaration::Tag{ (*parts)[0].getAsString().value_or("").str(),
								(*parts)[1].getAsString().value_or("").str(), (*parts)[2].getAsString().value_or("").str() });
						}
					}
				}
				index.declared[path_key(declaration.file)].push_back(index.declarations.size());
			}
			// Kept even when broken, so the numbers uses give stay right
			index.declarations.push_back(std::move(declaration));
		}
		for (const Value& entry : *uses) {
			const Array* use = entry.getAsArray();
			if (use == nullptr || use->size() != 4) {
				continue;
			}
			const size_t file = number_at(*use, 0);
			const size_t declaration = number_at(*use, 3);
			if (file >= paths.size() || declaration >= index.declarations.size() || index.declarations[declaration].file.empty()) {
				continue;
			}
			index.uses[path_key(paths[file])].push_back(IndexedUse{ number_at(*use, 1), number_at(*use, 2), declaration });
		}
		for (auto& [file, in_file] : index.uses) {
			std::sort(in_file.begin(), in_file.end(), [](const IndexedUse& a, const IndexedUse& b) { return a.offset < b.offset; });
		}
		return index;
	}

	std::optional<size_t> moved_forward(std::string_view old_text, std::string_view new_text, size_t offset) {
		const std::optional<TextChange> change = changed_span(old_text, new_text);
		if (!change.has_value() || offset < change->start) {
			return offset;
		}
		if (offset >= change->end) {
			return offset - change->end + change->start + change->text.size();
		}
		return std::nullopt;
	}

	std::optional<size_t> moved_back(std::string_view old_text, std::string_view new_text, size_t offset) {
		const std::optional<TextChange> change = changed_span(old_text, new_text);
		if (!change.has_value() || offset < change->start) {
			return offset;
		}
		if (offset >= change->start + change->text.size()) {
			return offset - change->start - change->text.size() + change->end;
		}
		return std::nullopt;
	}
}

#include "index.h"

#include <algorithm>
#include <tuple>

#include "features.h"
#include "uri.h"

#include "llvm/Support/JSON.h"

namespace hemera::lsp {

	using llvm::json::Array;
	using llvm::json::Object;
	using llvm::json::Value;

	std::optional<LoadedIndex::NameAt> LoadedIndex::name_at(const std::string& file, size_t offset) const {
		if (auto found = uses.find(file); found != uses.end()) {
			// The last use starting at or before offset, if offset is inside it
			const std::vector<IndexedUse>& in_file = found->second;
			auto after = std::upper_bound(in_file.begin(), in_file.end(), offset,
				[](size_t at, const IndexedUse& use) { return at < use.offset; });
			if (after != in_file.begin()) {
				const IndexedUse& use = *(after - 1);
				if (offset <= static_cast<size_t>(use.offset) + use.length) {
					return NameAt{ use.declaration, use.offset, use.length };
				}
			}
		}
		if (auto found = declared.find(file); found != declared.end()) {
			for (const size_t number : found->second) {
				const IndexedDeclaration& declaration = declarations[number];
				if (declaration.name_offset <= offset && offset <= static_cast<size_t>(declaration.name_offset) + declaration.name_length) {
					return NameAt{ number, declaration.name_offset, declaration.name_length };
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
			found.push_back(Place{ declared_at.file, declared_at.name_offset, declared_at.name_length });
		}
		for (const auto& [file, in_file] : uses) {
			for (const IndexedUse& use : in_file) {
				if (use.declaration == declaration) {
					auto path = paths.find(file);
					found.push_back(Place{ path != paths.end() ? path->second : file, use.offset, use.length });
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
		for (const std::string& path : paths) {
			index.paths[path_key(path)] = path;
		}
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
				if (const std::optional<int64_t> in = object->getInteger("in"); in.has_value() && *in >= 0) {
					declaration.in = static_cast<size_t>(*in);
				}
				if (const std::optional<int64_t> of = object->getInteger("of"); of.has_value() && *of >= 0) {
					declaration.of = static_cast<size_t>(*of);
				}
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
		// A build package's targets, and which of them read each file, in the files' order
		const Array* targets = root->getArray("targets");
		const Array* readers = root->getArray("readers");
		if (targets != nullptr && readers != nullptr) {
			for (size_t i = 0; i < readers->size() && i < paths.size(); ++i) {
				const Array* of_file = (*readers)[i].getAsArray();
				if (of_file == nullptr) {
					continue;
				}
				std::vector<std::string>& names = index.readers[path_key(paths[i])];
				for (const Value& number : *of_file) {
					const size_t target = static_cast<size_t>(number.getAsInteger().value_or(-1));
					if (target < targets->size()) {
						names.push_back((*targets)[target].getAsString().value_or("").str());
					}
				}
			}
		}
		// The numbers declarations give each other, only where they're declarations
		for (IndexedDeclaration& declaration : index.declarations) {
			for (std::optional<size_t>* number : { &declaration.in, &declaration.of }) {
				if (number->has_value() && (**number >= index.declarations.size() || index.declarations[**number].file.empty())) {
					number->reset();
				}
			}
		}
		if (const Array* imports = root->getArray("imports")) {
			for (const Value& entry : *imports) {
				const Array* import = entry.getAsArray();
				if (import == nullptr || import->size() != 4) {
					continue;
				}
				const size_t file = number_at(*import, 0);
				std::string folder = (*import)[3].getAsString().value_or("").str();
				if (folder.starts_with("<base>/") && !base_folder.empty()) {
					folder = base_folder + folder.substr(std::string_view("<base>").size());
				}
				if (file < paths.size()) {
					index.imports[path_key(paths[file])].push_back(IndexedImport{ number_at(*import, 1), number_at(*import, 2), std::move(folder) });
				}
			}
		}
		for (auto& [file, in_file] : index.uses) {
			std::sort(in_file.begin(), in_file.end(), [](const IndexedUse& a, const IndexedUse& b) { return a.offset < b.offset; });
		}
		for (auto& [file, in_file] : index.imports) {
			std::sort(in_file.begin(), in_file.end(), [](const IndexedImport& a, const IndexedImport& b) { return a.offset < b.offset; });
		}
		return index;
	}

	LoadedIndex merged_index(const LoadedIndex& old, LoadedIndex fresh, const std::set<std::string>& checked) {
		// Which files are fresh's alone
		std::set<std::string> files;
		for (const auto& [file, path] : old.paths) {
			files.insert(file);
		}
		for (const auto& [file, path] : fresh.paths) {
			files.insert(file);
		}
		std::set<std::string> replaced;
		for (const std::string& file : files) {
			auto before = old.readers.find(file);
			const bool read_before = before != old.readers.end() && !before->second.empty();
			// Every target that read it was checked; or, when none did, fresh is all there is of it
			bool all = read_before ? std::all_of(before->second.begin(), before->second.end(),
				[&](const std::string& target) { return checked.contains(target); }) : fresh.paths.contains(file);
			auto old_text = old.texts.find(file);
			auto new_text = fresh.texts.find(file);
			if ((old_text != old.texts.end()) != (new_text != fresh.texts.end())
				|| (old_text != old.texts.end() && old_text->second != new_text->second)) {
				all = true;
			}
			if (all) {
				replaced.insert(file);
			}
		}

		// A declaration is the same one where its file, its name's place and its kind are
		using Key = std::tuple<std::string, uint32_t, uint32_t, std::string>;
		const auto key_of = [](const IndexedDeclaration& declaration) {
			return Key{ path_key(declaration.file), declaration.name_offset, declaration.start, declaration.kind };
		};
		LoadedIndex merged;
		merged.declarations = std::move(fresh.declarations);
		const size_t fresh_count = merged.declarations.size();
		std::map<Key, size_t> numbers;
		for (size_t i = 0; i < merged.declarations.size(); ++i) {
			if (!merged.declarations[i].file.empty()) {
				numbers.emplace(key_of(merged.declarations[i]), i);
			}
		}
		// Each of old's declarations' number in merged, or none, for one that's gone
		std::vector<std::optional<size_t>> renumbered(old.declarations.size());
		for (size_t i = 0; i < old.declarations.size(); ++i) {
			const IndexedDeclaration& declaration = old.declarations[i];
			if (declaration.file.empty()) {
				continue;
			}
			const Key key = key_of(declaration);
			if (auto found = numbers.find(key); found != numbers.end()) {
				renumbered[i] = found->second;
			}
			else if (!replaced.contains(std::get<0>(key))) {
				renumbered[i] = merged.declarations.size();
				numbers.emplace(key, merged.declarations.size());
				merged.declarations.push_back(declaration);
			}
		}
		// What those kept from old name, in merged's numbers, once every one has its number
		for (size_t i = 0; i < old.declarations.size(); ++i) {
			if (!renumbered[i].has_value() || *renumbered[i] < fresh_count) {
				continue;
			}
			IndexedDeclaration& kept = merged.declarations[*renumbered[i]];
			for (std::optional<size_t>* number : { &kept.in, &kept.of }) {
				if (number->has_value()) {
					*number = **number < renumbered.size() ? renumbered[**number] : std::nullopt;
				}
			}
		}

		merged.uses = std::move(fresh.uses);
		for (const auto& [file, in_file] : old.uses) {
			if (replaced.contains(file)) {
				continue;
			}
			std::vector<IndexedUse>& uses = merged.uses[file];
			for (const IndexedUse& use : in_file) {
				if (use.declaration < renumbered.size() && renumbered[use.declaration].has_value()) {
					uses.push_back(IndexedUse{ use.offset, use.length, *renumbered[use.declaration] });
				}
			}
		}
		for (auto& [file, in_file] : merged.uses) {
			std::sort(in_file.begin(), in_file.end(), [](const IndexedUse& a, const IndexedUse& b) {
				return std::tie(a.offset, a.length, a.declaration) < std::tie(b.offset, b.length, b.declaration);
			});
			in_file.erase(std::unique(in_file.begin(), in_file.end(), [](const IndexedUse& a, const IndexedUse& b) {
				return a.offset == b.offset && a.length == b.length && a.declaration == b.declaration;
			}), in_file.end());
		}
		for (size_t i = 0; i < merged.declarations.size(); ++i) {
			if (!merged.declarations[i].file.empty()) {
				merged.declared[path_key(merged.declarations[i].file)].push_back(i);
			}
		}

		// Imports: fresh's, and old's in the files it doesn't replace, each once
		merged.imports = std::move(fresh.imports);
		for (const auto& [file, in_file] : old.imports) {
			if (replaced.contains(file)) {
				continue;
			}
			std::vector<IndexedImport>& imports = merged.imports[file];
			for (const IndexedImport& import : in_file) {
				if (std::none_of(imports.begin(), imports.end(), [&](const IndexedImport& other) { return other.offset == import.offset; })) {
					imports.push_back(import);
				}
			}
			std::sort(imports.begin(), imports.end(), [](const IndexedImport& a, const IndexedImport& b) { return a.offset < b.offset; });
		}

		merged.paths = old.paths;
		for (auto& [file, path] : fresh.paths) {
			merged.paths[file] = std::move(path);
		}
		for (const auto& [file, targets] : old.readers) {
			for (const std::string& target : targets) {
				if (!checked.contains(target)) {
					merged.readers[file].push_back(target);
				}
			}
		}
		for (const auto& [file, targets] : fresh.readers) {
			std::vector<std::string>& names = merged.readers[file];
			names.insert(names.end(), targets.begin(), targets.end());
		}
		std::erase_if(merged.readers, [](const auto& entry) { return entry.second.empty(); });
		// The texts each file's offsets count in: fresh's for its own files, old's for the rest, the same in both
		for (const auto& [file, text] : old.texts) {
			if (!replaced.contains(file)) {
				merged.texts[file] = text;
			}
		}
		for (auto& [file, text] : fresh.texts) {
			merged.texts[file] = std::move(text);
		}
		return merged;
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

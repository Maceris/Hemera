#include "front_end/name_index.h"

#include <algorithm>
#include <filesystem>
#include <format>
#include <fstream>
#include <limits>
#include <string_view>

#include "hemera_errors.h"
#include "cmd_line/options.h"
#include "error/reporting.h"
#include "front_end/checking.h"
#include "front_end/documentation.h"
#include "front_end/front_end.h"
#include "front_end/info.h"
#include "front_end/names.h"
#include "front_end/type.h"
#include "front_end/walk.h"
#include "parser/ast_types.h"

namespace hemera {

	// The uses table of the program walk is in, or null when it isn't being indexed
	static NameUses* uses_of(Walk& walk) {
		ProgramInfo* program = walk.executor.program_info;
		return program != nullptr ? program->name_uses.get() : nullptr;
	}

	void record_use(Walk& walk, const ast::Node* where, Declaration* declaration) {
		NameUses* uses = uses_of(walk);
		if (uses == nullptr || where == nullptr || declaration == nullptr) {
			return;
		}
		std::lock_guard<std::mutex> lock(uses->mutex);
		uses->uses[where] = NameUses::Use{ walk.package_path, walk.file_name, declaration, nullptr, nullptr };
	}

	void record_member_use(Walk& walk, const ast::Node* where, const TypeInfo* structure, InternedString member) {
		NameUses* uses = uses_of(walk);
		if (uses == nullptr || where == nullptr || structure == nullptr || member == nullptr) {
			return;
		}
		std::lock_guard<std::mutex> lock(uses->mutex);
		uses->uses[where] = NameUses::Use{ walk.package_path, walk.file_name, nullptr, structure, member };
	}

	namespace {

		std::string with_slashes(std::string path) {
			std::replace(path.begin(), path.end(), '\\', '/');
			return path;
		}

		// Whether path is folder or inside it, both with / throughout, folder without a / at its end
		bool within(std::string_view path, std::string_view folder) {
			return !folder.empty() && path.starts_with(folder) && (path.size() == folder.size() || path[folder.size()] == '/');
		}

		struct Indexer {
			NameIndex& index;
			ProgramInfo& program;
			std::string root;
			// The built-in packages' folders, base's as <base>, whose uses aren't counted unless they're under root
			std::vector<std::string> libraries;

			// Whether uses in file are counted: in the program's own code, or under the root package's folder
			bool counts(const std::string& file) const {
				if (within(file, root)) {
					return true;
				}
				return std::none_of(libraries.begin(), libraries.end(), [&](const std::string& library) { return within(file, library); });
			}

			// Whether node is parsed where its tokens say, with a span, rather than made while compiling
			bool placed(const ast::Node* node) const {
				return node != nullptr && node->value.offset != Token::NO_SPAN && program.made_nodes.origin(node) == nullptr;
			}

			IndexPlace place_of(const std::string& file, const ast::Node* node) const {
				return IndexPlace{ file, node->value.offset, node->value.length };
			}

			// The first and last byte of node's tokens, and every token under it
			static void widen(const ast::Node* node, uint32_t& start, uint32_t& end) {
				if (node->value.offset != Token::NO_SPAN) {
					start = std::min(start, node->value.offset);
					end = std::max(end, node->value.offset + node->value.length);
				}
				for (const ast::Node* child : node->children) {
					widen(child, start, end);
				}
			}

			// A declaration's doc comment, read from its name's token, put in made
			static void document(IndexDeclaration& made, const std::string& file, const ast::Node* name) {
				const std::optional<Documentation> documentation = documentation_at(file, name->value.line_number, name->value.column_number);
				if (!documentation.has_value()) {
					return;
				}
				made.brief = documentation->brief;
				made.details = documentation->details;
				for (const DocumentationTag& tag : documentation->tags) {
					made.tags.push_back(IndexDeclaration::Tag{ tag.tag, tag.name, tag.text });
				}
			}

			// The generic a declaration is an instance of, or itself
			static Declaration* original(Declaration* declaration) {
				while (declaration != nullptr && declaration->generic != nullptr) {
					declaration = declaration->generic;
				}
				return declaration;
			}

			static std::string file_of(const Declaration* declaration) {
				return with_slashes(file_path_of(declaration->package_path, declaration->file_name));
			}

			// A top-level or nested declaration's name node, or null when it has none it was written with
			const ast::Node* name_of(const Declaration* declaration) const {
				const ast::Node* node = declaration->node;
				if (node == nullptr || ast::NodeType::DEFINITION != node->node_type || node->children.empty()
					|| ast::NodeType::IDENTIFIER != node->children[0]->node_type || !placed(node->children[0])) {
					return nullptr;
				}
				return node->children[0];
			}

			// Its kind, as the index names it
			static std::string kind_of(const Declaration* declaration) {
				switch (declaration->kind) {
				case DeclarationKind::FUNCTION:
					return "function";
				case DeclarationKind::TYPE:
				case DeclarationKind::GENERIC_TYPE:
					return "type";
				case DeclarationKind::VALUE:
					return declaration->type_value != nullptr ? "type" : "constant";
				}
				return "constant";
			}

			// A declaration in the index, made the first time it's met; its place, or empty if it has none
			std::optional<IndexPlace> add_declaration(Declaration* declaration) {
				declaration = original(declaration);
				const ast::Node* name = declaration != nullptr ? name_of(declaration) : nullptr;
				if (name == nullptr) {
					return std::nullopt;
				}
				const std::string file = file_of(declaration);
				const IndexPlace at = place_of(file, name);
				if (index.declarations.contains(at)) {
					return at;
				}
				IndexDeclaration made;
				made.name = at;
				made.start = std::numeric_limits<uint32_t>::max();
				made.end = 0;
				widen(declaration->node, made.start, made.end);
				made.kind = kind_of(declaration);
				if ("type" != made.kind && declaration->value_type != nullptr) {
					made.type = to_string(declaration->value_type);
				}
				document(made, file, name);
				// In the index before what it leads to, which may lead back to it
				index.declarations.emplace(at, std::move(made));
				if (declaration->generic == nullptr && "type" != index.declarations[at].kind) {
					index.declarations[at].of = type_place(declaration->value_type);
				}
				if ("type" == index.declarations[at].kind) {
					add_members(declaration, at);
				}
				return at;
			}

			/*
			 * Where the declaration of the type whose members follow a . after a value of type is: through aliases and
			 * pointers, or a function's first result; empty when it isn't a struct, enum or union declared in the program
			 */
			std::optional<IndexPlace> type_place(const TypeInfo* type) {
				for (int depth = 0; type != nullptr && depth < 16; ++depth) {
					type = get_base_type(type);
					if (type == nullptr) {
						return std::nullopt;
					}
					if (TypeInfoVariant::POINTER == type->variant) {
						type = static_cast<const TypeInfoPointer*>(type)->base_type;
						continue;
					}
					if (TypeInfoVariant::FUNCTION == type->variant) {
						const auto* function = static_cast<const TypeInfoFunction*>(type);
						type = function->output.empty() ? nullptr : function->output[0].type;
						continue;
					}
					if (TypeInfoVariant::STRUCT != type->variant && TypeInfoVariant::ENUM != type->variant
						&& TypeInfoVariant::UNION != type->variant) {
						return std::nullopt;
					}
					auto found = program.names.type_declarations.find(type);
					if (found == program.names.type_declarations.end()) {
						return std::nullopt;
					}
					return add_declaration(found->second);
				}
				return std::nullopt;
			}

			/*
			 * A type's members in the index, each in it: a struct's fields, typed when it isn't a generic, an enum's
			 * members and a union's variants. One already there, as a use of it was met first, is put in it.
			 */
			void add_members(Declaration* declaration, const IndexPlace& type_at) {
				if (declaration->node == nullptr) {
					return;
				}
				const ast::Node* body = nullptr;
				for (const ast::Node* child : declaration->node->children) {
					if (ast::NodeType::STRUCT == child->node_type || ast::NodeType::UNION == child->node_type
						|| ast::NodeType::ENUM == child->node_type) {
						body = child;
						break;
					}
				}
				if (body == nullptr) {
					return;
				}
				const std::string file = type_at.file;
				const TypeInfo* type = declaration->generic == nullptr && declaration->type_value != nullptr
					? get_base_type(declaration->type_value) : nullptr;
				for (size_t i = 0; i < body->children.size(); ++i) {
					const ast::Node* member = body->children[i];
					const ast::Node* name = nullptr;
					std::string kind;
					if (ast::NodeType::STRUCT == body->node_type) {
						if (ast::NodeType::DEFINITION != member->node_type || member->children.empty()
							|| ast::NodeType::IDENTIFIER != member->children[0]->node_type) {
							continue;
						}
						name = member->children[0];
						kind = "field";
					}
					else if (ast::NodeType::IDENTIFIER == member->node_type) {
						name = member;
						kind = ast::NodeType::ENUM == body->node_type ? "member" : "variant";
					}
					if (name == nullptr || !placed(name)) {
						continue;
					}
					const IndexPlace at = place_of(file, name);
					auto [entry, made_now] = index.declarations.try_emplace(at);
					IndexDeclaration& made = entry->second;
					made.in = type_at;
					if (!made_now) {
						continue;
					}
					made.name = at;
					made.start = std::numeric_limits<uint32_t>::max();
					made.end = 0;
					widen(member, made.start, made.end);
					// A variant's payload is the node after its name
					if ("variant" == kind && i + 1 < body->children.size() && ast::NodeType::PAREN_GROUP == body->children[i + 1]->node_type) {
						widen(body->children[i + 1], made.start, made.end);
					}
					made.kind = kind;
					document(made, file, name);
					if ("member" == kind) {
						made.type = std::string(*declaration->name);
						index.declarations[at].of = type_at;
					}
					else if ("field" == kind && type != nullptr && TypeInfoVariant::STRUCT == type->variant) {
						for (const StructMember& candidate : static_cast<const TypeInfoStruct*>(type)->members) {
							if (candidate.name == name->value.value && candidate.member_type != nullptr) {
								index.declarations[at].type = to_string(candidate.member_type);
								const std::optional<IndexPlace> of = type_place(candidate.member_type);
								index.declarations[at].of = of;
							}
						}
					}
				}
			}

			// The imports in a file of the program's own code, each by the name it's used by
			void add_imports(const std::string& file, const FileInfo& info) {
				for (const ImportInfo* import : info.imports) {
					if (import == nullptr || import->node == nullptr || import->resolved_path == nullptr || import->node->children.empty()) {
						continue;
					}
					// import name, or import name as alias: the name it's used by is the last identifier before from
					const ast::Node* used_by = nullptr;
					for (const ast::Node* child : import->node->children) {
						if (ast::NodeType::KEYWORD_FROM == child->node_type) {
							break;
						}
						if (ast::NodeType::IDENTIFIER == child->node_type) {
							used_by = child;
						}
					}
					if (used_by != nullptr && placed(used_by)) {
						index.imports[place_of(file, used_by)] = with_slashes(std::string(*import->resolved_path));
					}
				}
			}

			// The STRUCT or UNION node under a type's declaration
			static const ast::Node* body_of(const Declaration* declaration) {
				for (const ast::Node* child : declaration->node->children) {
					if (ast::NodeType::STRUCT == child->node_type || ast::NodeType::UNION == child->node_type) {
						return child;
					}
				}
				return nullptr;
			}

			// A struct's field in the index, made the first time it's met; its place, or empty if it isn't found
			std::optional<IndexPlace> add_field(const TypeInfo* structure, InternedString member) {
				auto found = program.names.type_declarations.find(structure);
				Declaration* declaration = found != program.names.type_declarations.end() ? original(found->second) : nullptr;
				if (declaration == nullptr || declaration->node == nullptr) {
					return std::nullopt;
				}
				const ast::Node* body = body_of(declaration);
				if (body == nullptr) {
					return std::nullopt;
				}
				// The type first, which adds its members, in it
				add_declaration(declaration);
				const std::string file = file_of(declaration);
				for (const ast::Node* field : body->children) {
					if (ast::NodeType::DEFINITION != field->node_type || field->children.empty() || !placed(field->children[0])
						|| field->children[0]->value.value != member) {
						continue;
					}
					const IndexPlace at = place_of(file, field->children[0]);
					if (!index.declarations.contains(at)) {
						IndexDeclaration made;
						made.name = at;
						made.start = std::numeric_limits<uint32_t>::max();
						widen(field, made.start, made.end);
						made.kind = "field";
						// An instance's fields have its own types, so a generic's field is typed by its line alone
						if (TypeInfoVariant::STRUCT == structure->variant && found->second->generic == nullptr) {
							for (const StructMember& candidate : static_cast<const TypeInfoStruct*>(structure)->members) {
								if (candidate.name == member && candidate.member_type != nullptr) {
									made.type = to_string(candidate.member_type);
								}
							}
						}
						document(made, file, field->children[0]);
						index.declarations.emplace(at, std::move(made));
					}
					return at;
				}
				return std::nullopt;
			}

			// A body's locals: each where it's declared, and each use of one, in the body's file
			void add_locals(Declaration* declaration) {
				const CheckedBody* checked = declaration->checked.get();
				if (checked == nullptr) {
					return;
				}
				const std::string file = file_of(original(declaration));
				const bool uses_counted = counts(file);
				// A name alone is in nodes, and one at the head of a chain, like a in a.b, in heads
				for (const auto* table : { &checked->nodes, &checked->heads }) {
					for (const auto& [node, value] : *table) {
						if (!checked->is_node(node) || !placed(node)) {
							continue;
						}
						/*
						 * A declaration the checked body says a name is, however it was found, as one found the first
						 * time may not have been looked up through a walk this time
						 */
						Declaration* named = value.declaration != nullptr ? value.declaration : value.called_declaration;
						if (value.local == nullptr && named != nullptr && uses_counted && ast::NodeType::IDENTIFIER == node->node_type
							&& names(node, original(named)->name)) {
							if (const std::optional<IndexPlace> target = add_declaration(named)) {
								if (!(target->file == file && target->offset == node->value.offset)) {
									index.uses[place_of(file, node)] = *target;
								}
							}
						}
						if (value.local == nullptr) {
							continue;
						}
						const ast::Node* defined = static_cast<const ast::Node*>(value.local);
						if (!placed(defined)) {
							continue;
						}
						const IndexPlace at = place_of(file, defined);
						/*
						 * Declared where it's defined, or at its first use, as one only used at the head of a chain, like a
						 * parameter p in p.x, may be met only there; typed by either, as both have its type
						 */
						if (!index.declarations.contains(at)) {
							IndexDeclaration made;
							made.name = at;
							made.start = at.offset;
							made.end = at.offset + at.length;
							made.kind = "local";
							// An instance's is its own, so a generic's local is typed by the generic's body alone
							if (value.type != nullptr && declaration->generic == nullptr) {
								made.type = to_string(value.type);
							}
							index.declarations.emplace(at, std::move(made));
							if (value.type != nullptr && declaration->generic == nullptr) {
								const std::optional<IndexPlace> of = type_place(value.type);
								index.declarations[at].of = of;
							}
						}
						if (node != defined && uses_counted && ast::NodeType::IDENTIFIER == node->node_type
							&& names(node, defined->value.value)) {
							index.uses[place_of(file, node)] = at;
						}
					}
				}
			}

			// Whether node is a name, written as named: not what else a use is kept at, like a call's (
			static bool names(const ast::Node* node, InternedString named) {
				return named != nullptr && node->value.value == named;
			}

			void run() {
				// Generics' own bodies before their instances', so a local is described by the generic, whatever the order
				for (const bool instances : { false, true }) {
					for (Declaration& declaration : program.names.storage) {
						if ((declaration.generic != nullptr) == instances) {
							add_declaration(&declaration);
							add_locals(&declaration);
						}
					}
				}
				for (const auto& [path, package] : program.packages) {
					for (const auto& [file_name, file] : package->files) {
						const std::string file_path = with_slashes(file_path_of(path, file_name));
						if (file != nullptr && counts(file_path)) {
							add_imports(file_path, *file);
						}
					}
				}
				if (program.name_uses == nullptr) {
					return;
				}
				std::lock_guard<std::mutex> lock(program.name_uses->mutex);
				for (const auto& [node, use] : program.name_uses->uses) {
					if (!placed(node) || !names(node, use.declaration != nullptr ? use.declaration->name : use.member)) {
						continue;
					}
					const std::string file = with_slashes(file_path_of(use.package_path, use.file_name));
					if (!counts(file)) {
						continue;
					}
					const std::optional<IndexPlace> target = use.declaration != nullptr ? add_declaration(use.declaration)
						: add_field(use.structure, use.member);
					// A name at its own declaration isn't a use of it
					if (target.has_value() && !(target->file == file && target->offset == node->value.offset)) {
						index.uses[place_of(file, node)] = *target;
					}
				}
			}
		};
	}

	// A folder with / throughout, without one at its end
	static std::string folder_text(const std::filesystem::path& folder) {
		std::string text = with_slashes(folder.string());
		while (text.size() > 1 && text.back() == '/') {
			text.pop_back();
		}
		return text;
	}

	void add_to_index(NameIndex& index, ProgramInfo& program, const Options& options) {
		std::vector<std::string> libraries{ "<base>" };
		for (const BuiltinPackage builtin : { BuiltinPackage::STD, BuiltinPackage::VENDOR }) {
			if (auto found = options.builtin_paths.find(builtin); found != options.builtin_paths.end()) {
				std::error_code error;
				libraries.push_back(folder_text(std::filesystem::weakly_canonical(found->second, error)));
			}
		}
		Indexer{ index, program, folder_text(options.input), std::move(libraries) }.run();
	}

	void add_readers(NameIndex& index, ProgramInfo& program, const std::string& target) {
		for (const auto& [path, package] : program.packages) {
			for (const auto& [file_name, file] : package->files) {
				index.readers[with_slashes(file_path_of(path, file_name))].insert(target);
			}
		}
	}

	// text as a JSON string, quotes included
	static std::string json_text(std::string_view text) {
		std::string out = "\"";
		for (const char c : text) {
			switch (c) {
			case '"': out += "\\\""; break;
			case '\\': out += "\\\\"; break;
			case '\n': out += "\\n"; break;
			case '\r': out += "\\r"; break;
			case '\t': out += "\\t"; break;
			default:
				if (static_cast<unsigned char>(c) < 0x20) {
					out += std::format("\\u{:04x}", static_cast<unsigned char>(c));
				}
				else {
					out += c;
				}
			}
		}
		return out + "\"";
	}

	std::string index_json(const NameIndex& index) {
		// Each file once, numbered in order, and each declaration numbered in order
		std::map<std::string, size_t> files;
		for (const auto& [place, declaration] : index.declarations) {
			files.emplace(place.file, 0);
		}
		for (const auto& [place, target] : index.uses) {
			files.emplace(place.file, 0);
		}
		for (const auto& [file, targets] : index.readers) {
			files.emplace(file, 0);
		}
		for (const auto& [place, folder] : index.imports) {
			files.emplace(place.file, 0);
		}
		// Each declaration's number, for those that name another
		std::map<IndexPlace, size_t> numbers;
		for (const auto& [place, declaration] : index.declarations) {
			numbers.emplace(place, numbers.size());
		}
		std::string out = "{\"version\":1,\"files\":[";
		size_t number = 0;
		for (auto& [file, file_number] : files) {
			out += (number == 0 ? "" : ",") + json_text(file);
			file_number = number++;
		}
		out += "],\"declarations\":[";
		bool first_declaration = true;
		for (const auto& [place, declaration] : index.declarations) {
			out += first_declaration ? "\n" : ",\n";
			first_declaration = false;
			out += std::format("{{\"file\":{},\"name\":[{},{}],\"span\":[{},{}],\"kind\":{}", files[place.file], place.offset,
				place.length, declaration.start, declaration.end, json_text(declaration.kind));
			if (!declaration.type.empty()) {
				out += ",\"type\":" + json_text(declaration.type);
			}
			for (const auto& [key, named] : { std::pair{ "in", &declaration.in }, std::pair{ "of", &declaration.of } }) {
				if (named->has_value()) {
					if (auto found = numbers.find(**named); found != numbers.end()) {
						out += std::format(",\"{}\":{}", key, found->second);
					}
				}
			}
			if (!declaration.brief.empty()) {
				out += ",\"brief\":" + json_text(declaration.brief);
			}
			if (!declaration.details.empty()) {
				out += ",\"details\":" + json_text(declaration.details);
			}
			if (!declaration.tags.empty()) {
				out += ",\"tags\":[";
				for (size_t i = 0; i < declaration.tags.size(); ++i) {
					const IndexDeclaration::Tag& tag = declaration.tags[i];
					out += std::format("{}[{},{},{}]", i == 0 ? "" : ",", json_text(tag.tag), json_text(tag.name), json_text(tag.text));
				}
				out += "]";
			}
			out += "}";
		}
		out += "],\"uses\":[";
		bool first = true;
		for (const auto& [place, target] : index.uses) {
			auto found = numbers.find(target);
			if (found == numbers.end()) {
				continue;
			}
			out += std::format("{}[{},{},{},{}]", first ? "\n" : ",\n", files[place.file], place.offset, place.length, found->second);
			first = false;
		}
		out += "]";
		if (!index.imports.empty()) {
			out += ",\"imports\":[";
			bool first_import = true;
			for (const auto& [place, folder] : index.imports) {
				out += std::format("{}[{},{},{},{}]", first_import ? "\n" : ",\n", files[place.file], place.offset, place.length,
					json_text(folder));
				first_import = false;
			}
			out += "]";
		}
		// A build package's targets, each numbered in order, and the targets that read each file, in the files' order
		if (!index.readers.empty()) {
			std::map<std::string, size_t> targets;
			for (const auto& [file, readers] : index.readers) {
				for (const std::string& target : readers) {
					targets.emplace(target, 0);
				}
			}
			out += ",\"targets\":[";
			size_t target_number = 0;
			for (auto& [target, number_of] : targets) {
				out += (target_number == 0 ? "" : ",") + json_text(target);
				number_of = target_number++;
			}
			out += "],\"readers\":[";
			bool first_file = true;
			for (const auto& [file, number_of_file] : files) {
				out += first_file ? "\n[" : ",\n[";
				first_file = false;
				if (auto found = index.readers.find(file); found != index.readers.end()) {
					bool first_reader = true;
					for (const std::string& target : found->second) {
						out += (first_reader ? "" : ",") + std::to_string(targets[target]);
						first_reader = false;
					}
				}
				out += "]";
			}
			out += "]";
		}
		return out + "}\n";
	}

	bool write_index(const NameIndex& index, const std::string& path) {
		std::ofstream file(path, std::ios::binary | std::ios::trunc);
		if (!file.is_open()) {
			report_error(ErrorCode::E6000, path, 0, 0, "the name index couldn't be written");
			return false;
		}
		const std::string json = index_json(index);
		file.write(json.data(), static_cast<std::streamsize>(json.size()));
		if (!file) {
			report_error(ErrorCode::E6000, path, 0, 0, "the name index couldn't be written");
			return false;
		}
		return true;
	}
}

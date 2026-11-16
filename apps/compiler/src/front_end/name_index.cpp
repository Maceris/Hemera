#include "front_end/name_index.h"

#include <algorithm>
#include <limits>
#include <string_view>

#include "hemera_errors.h"
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
				index.declarations.emplace(at, std::move(made));
				return at;
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
						if (TypeInfoVariant::STRUCT == structure->variant) {
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
				const bool uses_counted = within(file, root);
				// A name alone is in nodes, and one at the head of a chain, like a in a.b, in heads
				for (const auto* table : { &checked->nodes, &checked->heads }) {
					for (const auto& [node, value] : *table) {
						if (value.local == nullptr || !checked->is_node(node) || !placed(node)) {
							continue;
						}
						const ast::Node* defined = static_cast<const ast::Node*>(value.local);
						if (!placed(defined)) {
							continue;
						}
						const IndexPlace at = place_of(file, defined);
						if (node == defined) {
							if (!index.declarations.contains(at)) {
								IndexDeclaration made;
								made.name = at;
								made.start = at.offset;
								made.end = at.offset + at.length;
								made.kind = "local";
								if (value.type != nullptr) {
									made.type = to_string(value.type);
								}
								index.declarations.emplace(at, std::move(made));
							}
						}
						else if (uses_counted && ast::NodeType::IDENTIFIER == node->node_type
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
				for (Declaration& declaration : program.names.storage) {
					add_declaration(&declaration);
					add_locals(&declaration);
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
					if (!within(file, root)) {
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

	void add_to_index(NameIndex& index, ProgramInfo& program, std::string_view root_folder) {
		std::string root = with_slashes(std::string(root_folder));
		while (root.size() > 1 && root.back() == '/') {
			root.pop_back();
		}
		Indexer{ index, program, std::move(root) }.run();
	}
}

#include <filesystem>
#include <format>
#include <fstream>

#include "error/reporting.h"
#include "front_end/work.h"
#include "front_end/front_end.h"
#include "lexer/lexer.h"
#include "parser/parser.h"
#include "util/logger.h"

namespace hemera {
	void work_execution(WorkThreadData& executor, WorkTarget& target) {
		//TODO(ches) do this
		if ((void*)&executor == (void*)&target) {}//TODO(ches) remove this
	}
	
	void work_if_else(WorkThreadData& executor, WorkTarget& target) {
		//TODO(ches) do this
		if ((void*)&executor == (void*)&target) {}//TODO(ches) remove this
	}
	
	void work_il1_generation(WorkThreadData& executor, WorkTarget& target) {
		//TODO(ches) do this
		if ((void*)&executor == (void*)&target) {}//TODO(ches) remove this
	}
	
	void work_import(WorkThreadData& executor, WorkTarget& target) {
		// Find the package
		// Note down package details in the package struct
		// Find the files in the package
		// Add to package structure
		// Add work for those files to be parsed
		
		//TODO(ches) do this
		if ((void*)&executor == (void*)&target) {}//TODO(ches) remove this
	}
	
	void work_parse(WorkThreadData& executor, WorkTarget& target) {
		const FileLocation& location = target.value.file_location;
		PackageInfo* package_info = nullptr;

		{
			std::scoped_lock<std::mutex> lock(executor.info->packages_mutex);

			auto iter = executor.info->packages.find(location.package_name);
			if (iter == executor.info->packages.end()) {
				LOG_ASSERT(location.file_name != nullptr);
				LOG_ASSERT(location.package_name != nullptr);

				std::string details = std::format("Unknown package {}",
					*location.package_name);
				report_error(ErrorCode::E4000, *location.file_name, 0, 0,
					details);
				return;
			}
			package_info = iter->second;
		}

		InternedString package_path = package_info->full_path;
		if (package_path == nullptr) {
			LOG_ASSERT(location.file_name != nullptr);
			LOG_ASSERT(location.package_name != nullptr);

			std::string details = std::format("Missing package path for {}",
				*location.package_name);
			report_error(ErrorCode::E4000, *location.file_name, 0, 0,
				details);
			return;
		}
		FileInfo* file_info = nullptr;

		{
			std::scoped_lock<std::mutex> lock(package_info->files_mutex);

			auto iter = package_info->files.find(location.file_name);
			if (iter == package_info->files.end()) {
				LOG_ASSERT(location.file_name != nullptr);
				LOG_ASSERT(location.package_name != nullptr);

				std::string details = std::format(
					"Missing files entr for {}.{}", *location.package_name,
					*location.file_name);
				report_error(ErrorCode::E4000, *location.file_name, 0, 0,
					details);
				return;
			}
			file_info = iter->second;
		}

		std::filesystem::path dir_path = std::filesystem::path(*package_path);
		if (!std::filesystem::exists(dir_path) 
			|| !std::filesystem::is_directory(dir_path)) {
			std::string details = std::format(
				"Pacakge {}'s path '{}' is not a valid directory",
				*location.package_name, dir_path.generic_string());
			report_error(ErrorCode::E4000, *location.file_name, 0, 0,
				details);
			return;
		}

		std::string file_path = dir_path.append(*location.file_name).generic_string();
		std::ifstream file(file_path);

		if (!file.is_open()) {
			report_error(ErrorCode::E4000, file_path, 0, 0);
			return;
		}

		Allocator<> token_alloc;
		lexer::lex(file, file_info->tokens, token_alloc, file_path);

		file_info->ast_root = hemera::parser::file(file_path, file_info->tokens, 
			executor.info->node_alloc);

		Info* info = executor.global_data->info;
		
		for (ast::Node* child : file_info->ast_root->children) {
			if (child->type == ast::NodeType::PACKAGE) {
				//TODO(ches) check it matches the pacakge
				continue;
			}
			if (child->type == ast::NodeType::IMPORT) {
				LOG_ASSERT(child->children.size() % 2 == 1);
				
				ImportInfo* import = info->info_alloc.new_object<ImportInfo>();
				
				{
					std::scoped_lock<std::mutex> lock(file_info->imports_mutex);
					file_info->imports.push_back(import);
				}

				import->name = child->children[0]->value.value;

				for (size_t i = 1; i < child->children.size(); ++i) {
					if (ast::NodeType::KEYWORD_AS == child->children[i]->type) {
						++i;
						import->alias = child->children[i]->value.value;
						continue;
					}
					if (ast::NodeType::KEYWORD_FROM == child->children[i]->type) {
						++i;
						import->location = child->children[i]->value.value;
						continue;
					}
				}

				continue;
			}
			if (child->type == ast::NodeType::DEFINITION) {
				//TODO(ches) type check the definition
				continue;
			}
			if (child->type == ast::NodeType::DIRECTIVE) {
				//TODO(ches) run or evaluate the directive
				continue;
			}
			//TODO(ches) report error with unknown node type
		}
	}
	
	void work_type_deduction(WorkThreadData& executor, WorkTarget& target) {
		//TODO(ches) do this
		if ((void*)&executor == (void*)&target) {}//TODO(ches) remove this
	}

	void work_type_check(WorkThreadData& executor, WorkTarget& target) {
		//TODO(ches) do this
		if ((void*)&executor == (void*)&target) {}//TODO(ches) remove this
	}
}

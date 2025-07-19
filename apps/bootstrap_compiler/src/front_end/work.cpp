#include <filesystem>
#include <fstream>

#include "front_end/work.h"
#include "front_end/front_end.h"
#include "lexer/lexer.h"
#include "parser/parser.h"

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
				//TODO(ches) error handling
				return;
			}
			package_info = iter->second;
		}

		InternedString package_path = package_info->full_path;
		if (package_path == nullptr) {
			//TODO(ches) error handling
			return;
		}
		FileInfo* file_info = nullptr;

		{
			std::scoped_lock<std::mutex> lock(package_info->files_mutex);

			auto iter = package_info->files.find(location.file_name);
			if (iter == package_info->files.end()) {
				//TODO(ches) error handling
				return;
			}
			file_info = iter->second;
		}

		std::filesystem::path dir_path = std::filesystem::path(*package_path);
		if (!std::filesystem::exists(dir_path) 
			|| !std::filesystem::is_directory(dir_path)) {
			//TODO(ches) error handling
			return;
		}

		std::string file_path = dir_path.append(*location.file_name).generic_string();
		std::ifstream file(file_path);

		if (!file.is_open()) {
			//TODO(ches) error handling
			return;
		}

		Allocator<> token_alloc;
		lexer::lex(file, file_info->tokens, token_alloc, file_path);

		file_info->ast_root = hemera::parser::file(file_path, file_info->tokens, 
			executor.info->node_alloc);

		//TODO(ches) do initial scan of file, or queue up work for said scan
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

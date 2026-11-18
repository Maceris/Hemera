#include "server.h"

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <tuple>
#include <utility>

#include "features.h"
#include "tokens.h"
#include "uri.h"
#include "error/reporting.h"
#include "parser/formatting.h"
#include "version.h"

#include "llvm/ADT/SmallString.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/Path.h"
#include "llvm/Support/Program.h"

namespace hemera::lsp {

	using llvm::json::Array;
	using llvm::json::Object;
	using llvm::json::Value;

	Server::Server(Send send, Launch launch) : send(std::move(send)) {
		prepare_parsing();
		checker = std::make_unique<Checker>(std::move(launch), [this](const CheckJob& job, const RunResult& result) { checked(job, result); });
	}

	Server::Server(Send send) : send(std::move(send)) {
		prepare_parsing();
		serving = true;
		serve_client = std::make_shared<ServeClient>(settings.compiler_path, settings.checker_memory_mb);
		// Every check through hemera --serve, which keeps a build package from one to the next
		Launch launch = [this](const std::vector<std::string>& arguments) -> std::unique_ptr<Run> {
			std::shared_ptr<ServeClient> client;
			{
				std::lock_guard<std::mutex> lock(state);
				client = serve_client;
			}
			return launch_through(std::move(client), arguments);
		};
		checker = std::make_unique<Checker>(std::move(launch), [this](const CheckJob& job, const RunResult& result) { checked(job, result); });
	}

	Server::~Server() {
		// Its thread calls back into the server, so it goes first
		checker.reset();
	}

	int Server::exit_code() const {
		std::lock_guard<std::mutex> lock(state);
		return shut_down ? 0 : 1;
	}

	Encoding Server::encoding() const {
		std::lock_guard<std::mutex> lock(state);
		return position_encoding;
	}

	Documents Server::documents() const {
		std::lock_guard<std::mutex> lock(state);
		return open_documents;
	}

	void Server::wait_for_checks() {
		checker->wait_idle();
	}

	void Server::respond(const Value& id, Value result) {
		send(Object{ { "jsonrpc", "2.0" }, { "id", id }, { "result", std::move(result) } });
	}

	void Server::respond_error(const Value& id, int64_t code, std::string message) {
		send(Object{ { "jsonrpc", "2.0" }, { "id", id }, { "error", Object{ { "code", code }, { "message", std::move(message) } } } });
	}

	void Server::malformed(std::string why) {
		respond_error(nullptr, error_codes::PARSE_ERROR, std::move(why));
	}

	bool Server::handle(const Value& message) {
		const Object* object = message.getAsObject();
		if (object == nullptr) {
			respond_error(nullptr, error_codes::INVALID_REQUEST, "a message is a JSON object");
		}
		else if (const std::optional<llvm::StringRef> method = object->getString("method")) {
			const Object* params = object->getObject("params");
			if (const Value* id = object->get("id")) {
				request(*id, *method, params);
			}
			else {
				notification(*method, params);
			}
		}
		// A response to a request of the server's, like workspace/semanticTokens/refresh, which needs nothing back
		else if (object->get("id") == nullptr) {
			respond_error(nullptr, error_codes::INVALID_REQUEST, "a message has a method, or is a response");
		}
		std::lock_guard<std::mutex> lock(state);
		return !exited;
	}

	/*
	 * hemera/state, for tests that compare what saves leave with what a check of everything finds (compare_saves.py),
	 * once no check is running or waiting: for each root, its index and diagnostics as sorted lines of text, which are
	 * the same for the same answers however they were arrived at.
	 */
	Value Server::state_for_tests() {
		Array roots;
		for (const auto& [root, index] : indexes) {
			std::vector<std::string> declarations;
			const auto key_of = [&](const std::optional<size_t>& number) {
				if (!number.has_value()) {
					return std::string("-");
				}
				const IndexedDeclaration& named = index->declarations[*number];
				return std::format("{}@{}", path_key(named.file), named.name_offset);
			};
			for (const IndexedDeclaration& declaration : index->declarations) {
				if (!declaration.file.empty()) {
					declarations.push_back(std::format("{}|{}|{}|{}|{}|{}|in {}|of {}|{}", path_key(declaration.file), declaration.name_offset,
						declaration.start, declaration.end, declaration.kind, declaration.type, key_of(declaration.in), key_of(declaration.of),
						declaration.text));
				}
			}
			for (const auto& [file, in_file] : index->imports) {
				for (const IndexedImport& import : in_file) {
					declarations.push_back(std::format("import {}|{}|{} -> {}", file, import.offset, import.length, path_key(import.folder)));
				}
			}
			std::vector<std::string> uses;
			for (const auto& [file, in_file] : index->uses) {
				for (const IndexedUse& use : in_file) {
					const IndexedDeclaration& named = index->declarations[use.declaration];
					uses.push_back(std::format("{}|{}|{} -> {}|{}|{}", file, use.offset, use.length, path_key(named.file),
						named.name_offset, named.kind));
				}
			}
			std::vector<std::string> readers;
			for (const auto& [file, targets] : index->readers) {
				// A file no target read, like the build's own, is the same as one not listed
				if (targets.empty()) {
					continue;
				}
				std::vector<std::string> sorted = targets;
				std::sort(sorted.begin(), sorted.end());
				std::string line = file + ":";
				for (const std::string& target : sorted) {
					line += " " + target;
				}
				readers.push_back(std::move(line));
			}
			std::vector<std::string> diagnostics;
			for (const auto& [checked_root, of_root] : findings) {
				if (path_key(checked_root) != root) {
					continue;
				}
				for (const auto& [target, of_target] : of_root.by_target) {
					for (const CompilerDiagnostic& diagnostic : of_target) {
						diagnostics.push_back(std::format("{}|{}|{}|{}|{}|{}", diagnostic.file, diagnostic.line, diagnostic.column,
							diagnostic.severity, diagnostic.code, diagnostic.message));
					}
				}
			}
			Array lists;
			for (std::vector<std::string>* list : { &declarations, &uses, &readers, &diagnostics }) {
				std::sort(list->begin(), list->end());
				list->erase(std::unique(list->begin(), list->end()), list->end());
				Array json;
				for (std::string& line : *list) {
					json.push_back(std::move(line));
				}
				lists.push_back(std::move(json));
			}
			roots.push_back(Object{ { "root", root }, { "declarations", std::move(lists[0]) }, { "uses", std::move(lists[1]) },
				{ "readers", std::move(lists[2]) }, { "diagnostics", std::move(lists[3]) } });
		}
		return Object{ { "roots", std::move(roots) } };
	}

	void Server::request(const Value& id, std::string_view method, const Object* params) {
		if (method == "hemera/state") {
			wait_for_checks();
			std::unique_lock<std::mutex> lock(state);
			Value answer = state_for_tests();
			lock.unlock();
			respond(id, std::move(answer));
			return;
		}
		std::unique_lock<std::mutex> lock(state);
		if (method == "initialize") {
			if (initialized) {
				lock.unlock();
				respond_error(id, error_codes::INVALID_REQUEST, "initialize was already sent");
				return;
			}
			initialized = true;
			Value result = initialize(params);
			lock.unlock();
			respond(id, std::move(result));
			return;
		}
		if (!initialized) {
			lock.unlock();
			respond_error(id, error_codes::SERVER_NOT_INITIALIZED, "initialize comes first");
			return;
		}
		if (shut_down) {
			lock.unlock();
			respond_error(id, error_codes::INVALID_REQUEST, "the server has shut down");
			return;
		}
		if (method == "shutdown") {
			shut_down = true;
			lock.unlock();
			respond(id, nullptr);
			return;
		}
		// hemera.checkEverything: a check of everything, for each open document's root, as a save checks only some
		if (method == "workspace/executeCommand") {
			const std::optional<llvm::StringRef> command = params != nullptr ? params->getString("command") : std::nullopt;
			if (command != std::optional<llvm::StringRef>("hemera.checkEverything")) {
				lock.unlock();
				respond_error(id, error_codes::INVALID_PARAMS, "no command " + command.value_or("").str());
				return;
			}
			std::vector<CheckJob> jobs;
			std::set<std::string> roots;
			for (const auto& [key, open] : open_documents.all()) {
				if (!open.path.empty() && open.path.ends_with(".hsc") && roots.insert(path_key(root_for(open.path))).second) {
					jobs.push_back(job_for(root_for(open.path), {}));
				}
			}
			lock.unlock();
			respond(id, nullptr);
			for (CheckJob& job : jobs) {
				checker->request(std::move(job));
			}
			return;
		}
		if (std::optional<Value> answer = document_request(method, params)) {
			std::optional<std::string> refused = std::exchange(refusal, std::nullopt);
			lock.unlock();
			if (refused.has_value()) {
				respond_error(id, error_codes::REQUEST_FAILED, std::move(*refused));
			}
			else {
				respond(id, std::move(*answer));
			}
			return;
		}
		lock.unlock();
		respond_error(id, error_codes::METHOD_NOT_FOUND, std::string("no method ") + std::string(method));
	}

	// The text document's uri, from params' textDocument
	static std::optional<std::string> document_uri(const Object* params) {
		const Object* document = params != nullptr ? params->getObject("textDocument") : nullptr;
		const std::optional<llvm::StringRef> uri = document != nullptr ? document->getString("uri") : std::nullopt;
		return uri.has_value() ? std::optional<std::string>(uri->str()) : std::nullopt;
	}

	void Server::notification(std::string_view method, const Object* params) {
		std::vector<std::string> to_check;
		std::vector<Value> clearing;
		{
			std::lock_guard<std::mutex> lock(state);
			if (method == "exit") {
				exited = true;
				return;
			}
			// Before initialize, and after shutdown, notifications are dropped
			if (!initialized || shut_down) {
				return;
			}
			const std::optional<std::string> uri = document_uri(params);
			if (method == "textDocument/didOpen" && uri.has_value()) {
				const Object* document = params->getObject("textDocument");
				const std::optional<llvm::StringRef> text = document->getString("text");
				open_documents.open(*uri, text.has_value() ? text->str() : std::string(), document->getInteger("version").value_or(0));
				to_check.push_back(*uri);
			}
			else if (method == "textDocument/didChange" && uri.has_value()) {
				// Whole-document sync: the last change is the whole text
				const Array* changes = params->getArray("contentChanges");
				const Object* last = changes != nullptr && !changes->empty() ? changes->back().getAsObject() : nullptr;
				const std::optional<llvm::StringRef> text = last != nullptr ? last->getString("text") : std::nullopt;
				if (text.has_value()) {
					open_documents.change(*uri, text->str(), params->getObject("textDocument")->getInteger("version").value_or(0));
				}
			}
			else if (method == "textDocument/didSave" && uri.has_value()) {
				to_check.push_back(*uri);
			}
			else if (method == "textDocument/didClose" && uri.has_value()) {
				open_documents.close(*uri);
				parses.erase(*uri);
			}
			else if (method == "workspace/didChangeConfiguration") {
				const Object* all = params != nullptr ? params->getObject("settings") : nullptr;
				read_settings(all != nullptr ? all->getObject("hemera") : nullptr);
				/*
				 * Other settings can check a file through another root, whose diagnostics would never clear what the old
				 * one's published: everything is cleared, what's still running is left out (generation), and every open
				 * document is checked again.
				 */
				++generation;
				for (const auto& [root, of_root] : findings) {
					for (const std::string& published_uri : of_root.published) {
						clearing.push_back(Object{ { "jsonrpc", "2.0" }, { "method", "textDocument/publishDiagnostics" },
							{ "params", Object{ { "uri", published_uri }, { "diagnostics", Array{} } } } });
					}
				}
				findings.clear();
				indexes.clear();
				for (const auto& [key, open] : open_documents.all()) {
					to_check.push_back(open.uri);
				}
			}
			// Anything else, like $/ notifications, needs nothing
		}
		for (Value& message : clearing) {
			send(std::move(message));
		}
		for (const std::string& uri : to_check) {
			check(uri);
		}
	}

	// A path's folder, with / throughout
	static std::string folder_of(const std::string& path) {
		return std::filesystem::path(path).parent_path().generic_string();
	}

	// Whether path is folder or inside it, compared as path_key does
	static bool within(const std::string& path, const std::string& folder) {
		const std::string inside = path_key(path);
		std::string outside = path_key(folder);
		while (outside.size() > 1 && outside.back() == '/') {
			outside.pop_back();
		}
		return inside.starts_with(outside) && (inside.size() == outside.size() || inside[outside.size()] == '/');
	}

	std::string Server::root_for(const std::string& path) const {
		for (const std::string& folder : workspace_folders) {
			if (!settings.root.empty() && within(path, folder)) {
				const std::filesystem::path root(settings.root);
				return root.is_absolute() ? root.generic_string()
					: (std::filesystem::path(workspace_folders.front()) / root).lexically_normal().generic_string();
			}
		}
		return folder_of(path);
	}

	std::string find_base_folder(const std::string& compiler_path) {
		std::string program = compiler_path;
		if (!llvm::sys::path::has_parent_path(program)) {
			llvm::ErrorOr<std::string> found = llvm::sys::findProgramByName(program);
			if (!found) {
				return {};
			}
			program = *found;
		}
		std::error_code error;
		std::filesystem::path folder = std::filesystem::weakly_canonical(program, error).parent_path();
		for (; !folder.empty(); folder = folder.parent_path()) {
			if (std::filesystem::is_directory(folder / "base" / "runtime", error)) {
				return (folder / "base").generic_string();
			}
			if (folder == folder.parent_path()) {
				break;
			}
		}
		return {};
	}

	void Server::read_settings(const Object* hemera) {
		if (hemera == nullptr) {
			return;
		}
		Settings read;
		if (const std::optional<llvm::StringRef> path = hemera->getString("compilerPath"); path.has_value() && !path->empty()) {
			read.compiler_path = path->str();
		}
		read.root = hemera->getString("root").value_or("").str();
		if (const Array* arguments = hemera->getArray("arguments")) {
			for (const Value& argument : *arguments) {
				if (const std::optional<llvm::StringRef> text = argument.getAsString()) {
					read.arguments.push_back(text->str());
				}
			}
		}
		if (const std::optional<int64_t> memory = hemera->getInteger("checkerMemory"); memory.has_value() && *memory >= 0) {
			read.checker_memory_mb = static_cast<size_t>(*memory);
		}
		// Another compiler, or limit, is another long-lived checker
		if (serving && (read.compiler_path != settings.compiler_path || read.checker_memory_mb != settings.checker_memory_mb)) {
			serve_client = std::make_shared<ServeClient>(read.compiler_path, read.checker_memory_mb);
		}
		settings = std::move(read);
		base_folder = find_base_folder(settings.compiler_path);
	}

	Value Server::initialize(const Object* params) {
		// UTF-8 when the client offers it, as the compiler counts columns in bytes
		position_encoding = Encoding::UTF16;
		const Object* capabilities = params != nullptr ? params->getObject("capabilities") : nullptr;
		const Object* general = capabilities != nullptr ? capabilities->getObject("general") : nullptr;
		const Array* encodings = general != nullptr ? general->getArray("positionEncodings") : nullptr;
		if (encodings != nullptr) {
			for (const Value& offered : *encodings) {
				if (offered.getAsString() == llvm::StringRef("utf-8")) {
					position_encoding = Encoding::UTF8;
				}
			}
		}
		// The workspace's folders, or its one root, as older clients give it
		workspace_folders.clear();
		if (const Array* folders = params != nullptr ? params->getArray("workspaceFolders") : nullptr) {
			for (const Value& folder : *folders) {
				const Object* object = folder.getAsObject();
				const std::optional<llvm::StringRef> uri = object != nullptr ? object->getString("uri") : std::nullopt;
				if (uri.has_value() && !path_from_uri(*uri).empty()) {
					workspace_folders.push_back(path_from_uri(*uri));
				}
			}
		}
		if (workspace_folders.empty() && params != nullptr) {
			if (const std::optional<llvm::StringRef> root = params->getString("rootUri"); root.has_value() && !path_from_uri(*root).empty()) {
				workspace_folders.push_back(path_from_uri(*root));
			}
		}
		// Whether it can be told to ask for semantic tokens again, as after each check
		const Object* workspace = capabilities != nullptr ? capabilities->getObject("workspace") : nullptr;
		const Object* tokens = workspace != nullptr ? workspace->getObject("semanticTokens") : nullptr;
		semantic_refresh = tokens != nullptr && tokens->getBoolean("refreshSupport").value_or(false);
		read_settings(params != nullptr ? params->getObject("initializationOptions") : nullptr);
		if (base_folder.empty()) {
			base_folder = find_base_folder(settings.compiler_path);
		}
		return Object{
			{ "capabilities", Object{
				{ "positionEncoding", Encoding::UTF8 == position_encoding ? "utf-8" : "utf-16" },
				{ "textDocumentSync", Object{
					{ "openClose", true },
					// Full: each change sends the whole text
					{ "change", 1 },
					{ "save", Object{ { "includeText", false } } },
				} },
				{ "documentFormattingProvider", true },
				{ "documentSymbolProvider", true },
				{ "completionProvider", Object{ { "triggerCharacters", Array{ ".", "\"", "/", ":" } } } },
				{ "foldingRangeProvider", true },
				{ "definitionProvider", true },
				{ "hoverProvider", true },
				{ "referencesProvider", true },
				{ "renameProvider", Object{ { "prepareProvider", true } } },
				{ "semanticTokensProvider", Object{ { "legend", semantic_tokens_legend() }, { "full", true }, { "range", true } } },
				{ "signatureHelpProvider", Object{ { "triggerCharacters", Array{ "(", "," } }, { "retriggerCharacters", Array{ "," } } } },
				{ "documentHighlightProvider", true },
				{ "workspaceSymbolProvider", true },
				{ "inlayHintProvider", true },
				{ "executeCommandProvider", Object{ { "commands", Array{ "hemera.checkEverything" } } } },
			} },
			{ "serverInfo", Object{ { "name", "hemera-lsp" }, { "version", VERSION_STR } } },
		};
	}

	static std::optional<std::string> read_file(const std::string& path) {
		std::ifstream file(path, std::ios::binary);
		if (!file.is_open()) {
			return std::nullopt;
		}
		return std::string(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
	}

	CheckJob Server::job_for(const std::string& root, const std::vector<std::string>& targets) {
		CheckJob job;
		job.root = root;
		job.generation = generation;
		job.targets = targets;
		job.arguments = { settings.compiler_path, "--check", "--diagnostics=json" };
		job.arguments.insert(job.arguments.end(), settings.arguments.begin(), settings.arguments.end());
		if (!targets.empty()) {
			std::string named = "--targets=";
			for (size_t i = 0; i < targets.size(); ++i) {
				named += (i == 0 ? "" : ",") + targets[i];
			}
			job.arguments.push_back(named);
		}
		/*
		 * The name index, for the answers that come from it (docs/editor.md): a check of some targets' is merged into
		 * the root's (merged_index)
		 */
		llvm::SmallString<256> index_file;
		if (!llvm::sys::fs::createTemporaryFile("hemera-lsp-index", "json", index_file)) {
			job.index_file = index_file.str().str();
			job.temporaries.push_back(job.index_file);
			job.arguments.push_back("--index=" + job.index_file);
		}
		// Each open document whose text isn't what's on disk is read from a file of its own instead
		for (const auto& [key, open] : open_documents.all()) {
			if (open.path.empty()) {
				continue;
			}
			// What the check reads of it, which the index's offsets count in
			job.texts[path_key(open.path)] = open.text;
			if (read_file(open.path) == open.text) {
				continue;
			}
			llvm::SmallString<256> temporary;
			if (llvm::sys::fs::createTemporaryFile("hemera-lsp-buffer", "hsc", temporary)) {
				continue;
			}
			std::ofstream file(temporary.str().str(), std::ios::binary);
			file << open.text;
			job.temporaries.push_back(temporary.str().str());
			job.arguments.push_back("--overlay=" + open.path + "=" + temporary.str().str());
		}
		job.arguments.push_back(root);
		return job;
	}

	void Server::check(const std::string& uri) {
		std::vector<CheckJob> jobs;
		{
			std::lock_guard<std::mutex> lock(state);
			const Document* document = open_documents.find_uri(uri);
			if (document == nullptr || document->path.empty() || !document->path.ends_with(".hsc")) {
				return;
			}
			const std::string root = root_for(document->path);
			/*
			 * When the root's index says which of a build package's targets read the file, just those: no other
			 * target's diagnostics or index can change (docs/editor.md). A file none read, like a new one, is checked
			 * as its folder's other files are, the targets that read any of them; one in a folder none read, or with no
			 * index yet, is a check of everything.
			 */
			std::set<std::string> readers;
			if (auto index = indexes.find(path_key(root)); index != indexes.end()) {
				const std::string file = path_key(document->path);
				if (auto of_file = index->second->readers.find(file); of_file != index->second->readers.end()) {
					readers.insert(of_file->second.begin(), of_file->second.end());
				}
				const std::string folder = file.substr(0, file.rfind('/') + 1);
				const bool read_before = !readers.empty();
				for (const auto& [other, of_other] : index->second->readers) {
					if (!read_before && other.starts_with(folder) && other.find('/', folder.size()) == std::string::npos) {
						readers.insert(of_other.begin(), of_other.end());
					}
				}
			}
			jobs.push_back(job_for(root, std::vector<std::string>(readers.begin(), readers.end())));
		}
		for (CheckJob& job : jobs) {
			checker->request(std::move(job));
		}
	}

	uint32_t token_end(std::string_view line, uint32_t column) {
		if (column >= line.size()) {
			return static_cast<uint32_t>(line.size());
		}
		const auto is_word = [](char c) {
			const unsigned char byte = static_cast<unsigned char>(c);
			return byte >= 0x80 || byte == '_' || (byte >= '0' && byte <= '9') || (byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z');
		};
		size_t end = column;
		if (is_word(line[end])) {
			while (end < line.size() && is_word(line[end])) {
				++end;
			}
			return static_cast<uint32_t>(end);
		}
		if (line[end] == '"') {
			for (++end; end < line.size(); ++end) {
				if (line[end] == '\\') {
					++end;
				}
				else if (line[end] == '"') {
					return static_cast<uint32_t>(end + 1);
				}
			}
			return static_cast<uint32_t>(line.size());
		}
		return static_cast<uint32_t>(end + 1);
	}

	void Server::checked(const CheckJob& job, const RunResult& result) {
		std::vector<Value> messages;
		std::optional<CheckJob> follow_up;
		{
			std::lock_guard<std::mutex> lock(state);
			if (job.generation != generation) {
				return;
			}
			if (!result.started) {
				if (!told_cannot_run) {
					told_cannot_run = true;
					messages.push_back(Object{ { "jsonrpc", "2.0" }, { "method", "window/showMessage" },
						{ "params", Object{ { "type", 1 }, { "message", "Hemera: " + result.error + ". Set hemera.compilerPath to the compiler." } } } });
				}
			}
			else {
				/*
				 * The index, read whether the check found errors or not: a check of everything's replaces the root's, and
				 * a check of some targets' is merged into it. A build package's check that checked none of its targets,
				 * as its build stopped at errors, leaves it as it was, so names lead where they did until it's fixed.
				 */
				const std::set<std::string> checked_targets(job.targets.begin(), job.targets.end());
				if (!job.index_file.empty()) {
					std::optional<LoadedIndex> index = read_index(read_file(job.index_file).value_or(""), base_folder);
					const auto found = indexes.find(path_key(job.root));
					const std::shared_ptr<const LoadedIndex> kept = found != indexes.end() ? found->second : nullptr;
					const auto checked_none = [&] {
						if (kept == nullptr || kept->readers.empty()) {
							return false;
						}
						for (const auto& [file, readers] : index->readers) {
							if (job.targets.empty() ? !readers.empty() : std::any_of(readers.begin(), readers.end(),
								[&](const std::string& reader) { return checked_targets.contains(reader); })) {
								return false;
							}
						}
						return true;
					};
					if (index.has_value() && !checked_none()) {
						index->texts = job.texts;
						indexes[path_key(job.root)] = !job.targets.empty() && kept != nullptr
							? std::make_shared<const LoadedIndex>(merged_index(*kept, std::move(*index), checked_targets))
							: std::make_shared<const LoadedIndex>(std::move(*index));
						// Open documents' tokens asked for again, from the new index, by a client that can be told to
						if (semantic_refresh) {
							messages.push_back(Object{ { "jsonrpc", "2.0" }, { "id", std::format("refresh-{}", ++requests_sent) },
								{ "method", "workspace/semanticTokens/refresh" } });
						}
					}
				}
				/*
				 * The diagnostics, by the target that found them: a check of everything's replace the root's, and a check
				 * of some targets' replace theirs, and the build's own, which every check reports
				 */
				Found& of_root = findings[job.root];
				if (job.targets.empty()) {
					of_root.by_target.clear();
				}
				else {
					for (const std::string& target : job.targets) {
						of_root.by_target.erase(target);
					}
					of_root.by_target.erase("");
				}
				for (CompilerDiagnostic& diagnostic : parse_diagnostics(result.output)) {
					of_root.by_target[diagnostic.target].push_back(std::move(diagnostic));
				}
				// By file, each once, as one file can be in several of a build's targets
				std::map<std::string, std::vector<const CompilerDiagnostic*>> by_file;
				std::map<std::string, std::string> file_paths;
				std::set<std::tuple<std::string, std::string, std::string, uint32_t, uint32_t, std::string>> seen;
				for (const auto& [target, of_target] : of_root.by_target)
				for (const CompilerDiagnostic& diagnostic : of_target) {
					std::string path = diagnostic.file;
					if (path.starts_with("<base>/")) {
						if (base_folder.empty()) {
							continue;
						}
						path = base_folder + path.substr(std::string_view("<base>").size());
					}
					const std::string key = path_key(path);
					if (!seen.emplace(key, diagnostic.severity, diagnostic.code, diagnostic.line, diagnostic.column, diagnostic.message).second) {
						continue;
					}
					by_file[key].push_back(&diagnostic);
					file_paths[key] = path;
				}
				/*
				 * One in inserted code is shown at the first #insert in the workspace that put it there too, the one the
				 * user wrote, saying so, with where the code is written as related information; and where it's written,
				 * with the #inserts
				 */
				std::vector<CompilerDiagnostic> at_inserts;
				size_t inserted_count = 0;
				for (const auto& [key, diagnostics] : by_file) {
					for (const CompilerDiagnostic* diagnostic : diagnostics) {
						inserted_count += diagnostic->inserted.empty() ? 0 : 1;
					}
				}
				at_inserts.reserve(inserted_count * 2);
				const auto in_workspace = [&](const std::string& path) {
					return std::any_of(workspace_folders.begin(), workspace_folders.end(), [&](const std::string& folder) { return within(path, folder); });
				};
				std::vector<std::pair<std::string, const CompilerDiagnostic*>> moved;
				for (auto& [key, diagnostics] : by_file) {
					for (const CompilerDiagnostic*& diagnostic : diagnostics) {
						if (diagnostic->inserted.empty()) {
							continue;
						}
						const CompilerDiagnostic* original = diagnostic;
						const auto site = std::find_if(original->inserted.begin(), original->inserted.end(),
							[&](const CompilerDiagnostic::Place& place) { return in_workspace(place.file); });
						// Where it's written, with each #insert
						CompilerDiagnostic written = *original;
						for (const CompilerDiagnostic::Place& place : original->inserted) {
							written.related.push_back(CompilerDiagnostic::Place{ place.file, place.line, place.column, "Inserted here" });
						}
						at_inserts.push_back(std::move(written));
						diagnostic = &at_inserts.back();
						if (site == original->inserted.end()) {
							continue;
						}
						// At the #insert, and what's in its message after the first ; is the sites, given as related information
						CompilerDiagnostic at_insert = *diagnostic;
						at_insert.file = site->file;
						at_insert.line = site->line;
						at_insert.column = site->column;
						at_insert.message = "In code this #insert puts in: " + diagnostic->message.substr(0, diagnostic->message.find("; inserted at"));
						at_insert.related = { CompilerDiagnostic::Place{ diagnostic->file, diagnostic->line, diagnostic->column, "Where the code is written" } };
						at_insert.inserted.clear();
						at_inserts.push_back(std::move(at_insert));
						moved.emplace_back(path_key(site->file), &at_inserts.back());
					}
				}
				for (const auto& [key, diagnostic] : moved) {
					by_file[key].push_back(diagnostic);
					file_paths.emplace(key, diagnostic->file);
				}
				/*
				 * An open file of this root's that none of its build's targets read, like one only another architecture's
				 * targets import, isn't checked at all: it says so, where the package statement is, rather than nothing
				 */
				std::vector<CompilerDiagnostic> notices;
				notices.reserve(open_documents.all().size());
				auto kept = indexes.find(path_key(job.root));
				if (kept != indexes.end() && !kept->second->readers.empty()) {
					for (const auto& [document_key, open] : open_documents.all()) {
						const std::string open_key = path_key(open.path);
						if (open.path.empty() || !open.path.ends_with(".hsc") || path_key(root_for(open.path)) != path_key(job.root)
							|| kept->second->readers.contains(open_key)) {
							continue;
						}
						CompilerDiagnostic notice;
						notice.severity = "information";
						notice.file = open.path;
						// On the package statement's line, or the first
						const size_t package_at = open.text.starts_with("package") ? 0 : open.text.find("\npackage");
						notice.line = package_at == std::string::npos ? 1
							: static_cast<uint32_t>(std::count(open.text.begin(), open.text.begin() + static_cast<std::ptrdiff_t>(package_at), '\n'))
								+ (package_at == 0 ? 1 : 2);
						notice.message = "No target of the build reads this file with the settings it's checked with, so it isn't "
							"checked, and its names aren't known. A target that a setting adds, like another architecture's, is "
							"checked with that setting in hemera.arguments, like --setting=name=value.";
						notices.push_back(std::move(notice));
						by_file[open_key].push_back(&notices.back());
						file_paths[open_key] = open.path;
					}
				}
				std::set<std::string> now;
				for (const auto& [key, diagnostics] : by_file) {
					const std::string& path = file_paths[key];
					const Document* open = open_documents.find_path(path);
					const std::string uri = open != nullptr ? open->uri : uri_from_path(path);
					const std::string text = open != nullptr ? open->text : read_file(path).value_or(std::string());
					const LineIndex index(text);
					Array published_diagnostics;
					for (const CompilerDiagnostic* diagnostic : diagnostics) {
						const uint32_t line = diagnostic->line > 0 ? diagnostic->line - 1 : 0;
						const uint32_t start = diagnostic->column;
						const uint32_t end = token_end(index.line(line), start);
						Object range{
							{ "start", Object{ { "line", line }, { "character", index.character(line, start, position_encoding) } } },
							{ "end", Object{ { "line", line }, { "character", index.character(line, end, position_encoding) } } },
						};
						const int64_t severity = diagnostic->severity == "error" ? 1 : diagnostic->severity == "warning" ? 2 : 3;
						Object published_diagnostic{ { "range", std::move(range) }, { "severity", severity }, { "source", "hemera" },
							{ "message", diagnostic->message } };
						if (!diagnostic->code.empty()) {
							published_diagnostic["code"] = diagnostic->code;
						}
						if (!diagnostic->related.empty()) {
							Array related;
							for (const CompilerDiagnostic::Place& place : diagnostic->related) {
								related.push_back(Object{ { "location", place_location(place.file, place.line, place.column) },
									{ "message", place.message } });
							}
							published_diagnostic["relatedInformation"] = std::move(related);
						}
						published_diagnostics.push_back(std::move(published_diagnostic));
					}
					now.insert(uri);
					messages.push_back(Object{ { "jsonrpc", "2.0" }, { "method", "textDocument/publishDiagnostics" },
						{ "params", Object{ { "uri", uri }, { "diagnostics", std::move(published_diagnostics) } } } });
				}
				// What had diagnostics from this root before and has none now is cleared
				for (const std::string& uri : of_root.published) {
					if (!now.contains(uri)) {
						messages.push_back(Object{ { "jsonrpc", "2.0" }, { "method", "textDocument/publishDiagnostics" },
							{ "params", Object{ { "uri", uri }, { "diagnostics", Array{} } } } });
					}
				}
				of_root.published = std::move(now);
				/*
				 * A check of some targets that found the build changed, and checked it afresh: the build's targets, or how
				 * it makes them, may have changed, so everything is checked too
				 */
				if (result.rebuilt && !job.targets.empty()) {
					follow_up = job_for(job.root, {});
				}
			}
		}
		for (Value& message : messages) {
			send(std::move(message));
		}
		if (follow_up.has_value()) {
			checker->request(std::move(*follow_up));
		}
	}

	std::optional<Value> Server::document_request(std::string_view method, const Object* params) {
		const std::optional<std::string> uri = document_uri(params);
		if (method == "textDocument/formatting") {
			return uri.has_value() ? format(*uri) : Value(Array{});
		}
		if (method == "textDocument/definition") {
			return definition(params);
		}
		if (method == "textDocument/completion") {
			return completion(params);
		}
		if (method == "textDocument/hover") {
			return hover(params);
		}
		if (method == "textDocument/semanticTokens/full" || method == "textDocument/semanticTokens/range") {
			return tokens(params, method.ends_with("/range"));
		}
		if (method == "textDocument/signatureHelp") {
			return signature(params);
		}
		if (method == "textDocument/documentHighlight") {
			return highlights(params);
		}
		if (method == "textDocument/inlayHint") {
			return hints(params);
		}
		if (method == "workspace/symbol") {
			return symbols(params);
		}
		if (method == "textDocument/references") {
			return references(params);
		}
		if (method == "textDocument/prepareRename") {
			return prepare_rename(params);
		}
		if (method == "textDocument/rename") {
			return rename(params);
		}
		if (method == "textDocument/foldingRange") {
			// This version, from its tokens, whether it parses or not (decision 4)
			const Parses* parses_of = uri.has_value() ? parsed(*uri) : nullptr;
			return parses_of != nullptr ? folding_ranges(*parses_of->current) : Value(Array{});
		}
		if (method == "textDocument/documentSymbol") {
			// The last version that parsed, when this one doesn't (decision 4)
			const Parses* parses_of = uri.has_value() ? parsed(*uri) : nullptr;
			Array symbols = parses_of != nullptr && parses_of->last_tree != nullptr ? document_symbols(*parses_of->last_tree, position_encoding)
				: Array{};
			add_inserted_symbols(*uri, symbols);
			return std::move(symbols);
		}
		return std::nullopt;
	}

	Value Server::format(const std::string& uri) {
		const Document* document = open_documents.find_uri(uri);
		if (document == nullptr) {
			return Array{};
		}
		// Its errors kept and dropped, as a parse's are: the check reports them
		ReportScope scope;
		ReportScope* outer = report_scope();
		set_report_scope(&scope);
		const formatting::Result formatted = formatting::format_source(document->text, document->path.empty() ? uri : document->path);
		set_report_scope(outer);
		reset_reporting_storage();
		if (!formatted.parsed || !formatted.lost_comments.empty()) {
			return Array{};
		}
		const std::optional<TextChange> change = changed_span(document->text, formatted.text);
		if (!change.has_value()) {
			return Array{};
		}
		const LineIndex index(document->text);
		return Array{ Object{
			{ "range", Object{ { "start", position_at(index, change->start, position_encoding) },
				{ "end", position_at(index, change->end, position_encoding) } } },
			{ "newText", change->text },
		} };
	}

	std::optional<std::pair<std::string, std::string>> Server::texts_of(const LoadedIndex& index, const std::string& file) {
		const std::string key = path_key(file);
		if (const Document* open = open_documents.find_path(file)) {
			auto then = index.texts.find(key);
			// Opened after the check began: the check read it from disk
			if (then == index.texts.end()) {
				std::optional<std::string> on_disk = read_file(open->path);
				return std::make_pair(on_disk.value_or(open->text), open->text);
			}
			return std::make_pair(then->second, open->text);
		}
		std::optional<std::string> on_disk = read_file(file);
		if (!on_disk.has_value()) {
			return std::nullopt;
		}
		return std::make_pair(*on_disk, *on_disk);
	}

	std::optional<Server::Named> Server::named_at(const Object* params) {
		const std::optional<std::string> uri = document_uri(params);
		const Document* document = uri.has_value() ? open_documents.find_uri(*uri) : nullptr;
		const Object* position = params != nullptr ? params->getObject("position") : nullptr;
		if (document == nullptr || document->path.empty() || position == nullptr) {
			return std::nullopt;
		}
		const std::string key = path_key(document->path);
		// The index of the document's root, or else any that knows the file
		std::shared_ptr<const LoadedIndex> index;
		if (auto found = indexes.find(path_key(root_for(document->path))); found != indexes.end()) {
			index = found->second;
		}
		for (auto it = indexes.begin(); index == nullptr && it != indexes.end(); ++it) {
			if (it->second->uses.contains(key) || it->second->declared.contains(key)) {
				index = it->second;
			}
		}
		const std::optional<std::pair<std::string, std::string>> texts = index != nullptr ? texts_of(*index, document->path) : std::nullopt;
		if (!texts.has_value()) {
			return std::nullopt;
		}
		const LineIndex lines(document->text);
		const size_t now = lines.offset_of(static_cast<uint32_t>(position->getInteger("line").value_or(0)),
			static_cast<uint32_t>(position->getInteger("character").value_or(0)), position_encoding);
		const std::optional<size_t> then = moved_back(texts->first, texts->second, now);
		const std::optional<LoadedIndex::NameAt> name = then.has_value() ? index->name_at(key, *then) : std::nullopt;
		if (!name.has_value()) {
			return std::nullopt;
		}
		const std::optional<size_t> start = moved_forward(texts->first, texts->second, name->offset);
		const std::optional<size_t> end = moved_forward(texts->first, texts->second, static_cast<size_t>(name->offset) + name->length);
		if (!start.has_value() || !end.has_value()) {
			return std::nullopt;
		}
		return Named{ index, name->declaration, *start, *end };
	}

	Value Server::location_of(const LoadedIndex& index, const std::string& file, size_t start, size_t end) {
		const std::optional<std::pair<std::string, std::string>> texts = texts_of(index, file);
		const std::optional<size_t> start_now = texts.has_value() ? moved_forward(texts->first, texts->second, start) : std::nullopt;
		const std::optional<size_t> end_now = texts.has_value() ? moved_forward(texts->first, texts->second, end) : std::nullopt;
		if (!start_now.has_value() || !end_now.has_value()) {
			return nullptr;
		}
		const Document* open = open_documents.find_path(file);
		const LineIndex lines(texts->second);
		return Object{
			{ "uri", open != nullptr ? open->uri : uri_from_path(file) },
			{ "range", Object{ { "start", position_at(lines, *start_now, position_encoding) },
				{ "end", position_at(lines, *end_now, position_encoding) } } },
		};
	}

	Value Server::completion(const Object* params) {
		const std::optional<std::string> uri = document_uri(params);
		const Document* document = uri.has_value() ? open_documents.find_uri(*uri) : nullptr;
		const Object* position = params != nullptr ? params->getObject("position") : nullptr;
		if (document == nullptr || position == nullptr) {
			return Array{};
		}
		const Parses* parses_of = parsed(*uri);
		CompletionRequest request;
		request.file = document->path.empty() ? *uri : document->path;
		request.text = document->text;
		request.checked_text = document->text;
		request.parsed = parses_of != nullptr ? parses_of->current.get() : nullptr;
		request.base_folder = base_folder;
		request.encoding = position_encoding;
		const LineIndex lines(document->text);
		request.offset = lines.offset_of(static_cast<uint32_t>(position->getInteger("line").value_or(0)),
			static_cast<uint32_t>(position->getInteger("character").value_or(0)), position_encoding);
		const std::shared_ptr<const LoadedIndex> index = index_for(request.file);
		std::optional<std::pair<std::string, std::string>> texts;
		if (index != nullptr && !document->path.empty()) {
			texts = texts_of(*index, document->path);
			if (texts.has_value()) {
				request.checked_text = texts->first;
			}
		}
		return completion_items(request, tables_for(index));
	}

	std::shared_ptr<const LoadedIndex> Server::index_for(const std::string& file) const {
		const std::string key = path_key(file);
		if (auto found = indexes.find(path_key(root_for(file))); found != indexes.end()) {
			return found->second;
		}
		for (const auto& [root, index] : indexes) {
			if (index->uses.contains(key) || index->declared.contains(key)) {
				return index;
			}
		}
		return nullptr;
	}

	CompletionTables* Server::tables_for(const std::shared_ptr<const LoadedIndex>& index) {
		if (index == nullptr) {
			return nullptr;
		}
		// Those of indexes that have been replaced since go
		std::erase_if(tables, [&](const auto& entry) {
			return std::none_of(indexes.begin(), indexes.end(), [&](const auto& kept) { return kept.second.get() == entry.first; });
		});
		std::shared_ptr<CompletionTables>& made = tables[index.get()];
		if (made == nullptr) {
			// A file's text as the check read it: an open one's from the index, another's from disk
			made = std::make_shared<CompletionTables>(index, [index](const std::string& file) {
				if (auto then = index->texts.find(path_key(file)); then != index->texts.end()) {
					return then->second;
				}
				return read_file(file).value_or(std::string());
			});
		}
		return made.get();
	}

	AssistRequest Server::assist_request(const Document& document, const std::shared_ptr<const LoadedIndex>& index) {
		AssistRequest request;
		request.file = document.path;
		request.text = document.text;
		request.checked_text = document.text;
		const Parses* parses_of = parsed(document.uri);
		request.parsed = parses_of != nullptr ? parses_of->current.get() : nullptr;
		request.encoding = position_encoding;
		if (index != nullptr) {
			if (std::optional<std::pair<std::string, std::string>> texts = texts_of(*index, document.path)) {
				assist_texts = std::move(texts->first);
				request.checked_text = assist_texts;
			}
		}
		return request;
	}

	Value Server::signature(const Object* params) {
		const std::optional<std::string> uri = document_uri(params);
		const Document* document = uri.has_value() ? open_documents.find_uri(*uri) : nullptr;
		const Object* position = params != nullptr ? params->getObject("position") : nullptr;
		if (document == nullptr || document->path.empty() || position == nullptr) {
			return nullptr;
		}
		const std::shared_ptr<const LoadedIndex> index = index_for(document->path);
		AssistRequest request = assist_request(*document, index);
		const LineIndex lines(document->text);
		request.offset = lines.offset_of(static_cast<uint32_t>(position->getInteger("line").value_or(0)),
			static_cast<uint32_t>(position->getInteger("character").value_or(0)), position_encoding);
		return signature_help(request, tables_for(index));
	}

	Value Server::hints(const Object* params) {
		const std::optional<std::string> uri = document_uri(params);
		const Document* document = uri.has_value() ? open_documents.find_uri(*uri) : nullptr;
		const Object* range = params != nullptr ? params->getObject("range") : nullptr;
		const std::shared_ptr<const LoadedIndex> index = document != nullptr && !document->path.empty() ? index_for(document->path) : nullptr;
		if (index == nullptr || range == nullptr) {
			return Array{};
		}
		AssistRequest request = assist_request(*document, index);
		const LineIndex lines(document->text);
		for (auto [field, offset] : { std::pair{ "start", &request.offset }, std::pair{ "end", &request.end } }) {
			const Object* at = range->getObject(field);
			*offset = at == nullptr ? 0 : lines.offset_of(static_cast<uint32_t>(at->getInteger("line").value_or(0)),
				static_cast<uint32_t>(at->getInteger("character").value_or(0)), position_encoding);
		}
		return inlay_hints(request, *index);
	}

	Value Server::symbols(const Object* params) {
		const std::optional<llvm::StringRef> query = params != nullptr ? params->getString("query") : std::nullopt;
		std::vector<CompletionTables*> of_each;
		for (const auto& [root, index] : indexes) {
			of_each.push_back(tables_for(index));
		}
		return workspace_symbols(query.value_or("").str(), of_each, workspace_folders, position_encoding);
	}

	Value Server::tokens(const Object* params, bool range) {
		const std::optional<std::string> uri = document_uri(params);
		const Document* document = uri.has_value() ? open_documents.find_uri(*uri) : nullptr;
		if (document == nullptr) {
			return Object{ { "data", Array{} } };
		}
		const Parses* parses_of = parsed(*uri);
		TokensRequest request;
		request.file = document->path.empty() ? *uri : document->path;
		request.text = document->text;
		request.checked_text = document->text;
		request.parsed = parses_of != nullptr ? parses_of->current.get() : nullptr;
		request.encoding = position_encoding;
		// std is beside base, as both ship next to the compiler
		request.base_folder = base_folder;
		if (const size_t slash = base_folder.rfind('/'); slash != std::string::npos) {
			request.std_folder = base_folder.substr(0, slash) + "/std";
		}
		const Object* asked = range && params != nullptr ? params->getObject("range") : nullptr;
		if (asked != nullptr) {
			const LineIndex lines(document->text);
			for (auto [field, offset] : { std::pair{ "start", &request.start }, std::pair{ "end", &request.end } }) {
				if (const Object* position = asked->getObject(field)) {
					*offset = lines.offset_of(static_cast<uint32_t>(position->getInteger("line").value_or(0)),
						static_cast<uint32_t>(position->getInteger("character").value_or(0)), position_encoding);
				}
			}
		}
		// The index of the document's root, or else any that knows the file, as for a name's declaration
		std::shared_ptr<const LoadedIndex> index;
		const std::string key = path_key(request.file);
		if (auto found = indexes.find(path_key(root_for(request.file))); found != indexes.end()) {
			index = found->second;
		}
		for (auto it = indexes.begin(); index == nullptr && it != indexes.end(); ++it) {
			if (it->second->uses.contains(key) || it->second->declared.contains(key)) {
				index = it->second;
			}
		}
		// The text the check read, which the index's offsets are in
		std::optional<std::pair<std::string, std::string>> texts;
		if (index != nullptr && !document->path.empty()) {
			texts = texts_of(*index, document->path);
		}
		if (texts.has_value()) {
			request.checked_text = texts->first;
		}
		else {
			index = nullptr;
		}
		return semantic_tokens(request, index.get());
	}

	Value Server::place_location(const std::string& file, uint32_t line_number, uint32_t column) {
		std::string path = file;
		if (path.starts_with("<base>/") && !base_folder.empty()) {
			path = base_folder + path.substr(std::string_view("<base>").size());
		}
		const Document* open = open_documents.find_path(path);
		const std::string text = open != nullptr ? open->text : read_file(path).value_or(std::string());
		const LineIndex lines(text);
		const uint32_t line = line_number > 0 ? line_number - 1 : 0;
		const uint32_t end = token_end(lines.line(line), column);
		return Object{ { "uri", open != nullptr ? open->uri : uri_from_path(path) },
			{ "range", Object{ { "start", Object{ { "line", line }, { "character", lines.character(line, column, position_encoding) } } },
				{ "end", Object{ { "line", line }, { "character", lines.character(line, end, position_encoding) } } } } } };
	}

	void Server::add_inserted_symbols(const std::string& uri, Array& symbols) {
		const Document* document = open_documents.find_uri(uri);
		if (document == nullptr || document->path.empty()) {
			return;
		}
		const std::string key = path_key(document->path);
		std::shared_ptr<const LoadedIndex> index;
		if (auto found = indexes.find(path_key(root_for(document->path))); found != indexes.end()) {
			index = found->second;
		}
		auto declared = index != nullptr ? index->declared.find(key) : decltype(index->declared.end()){};
		if (index == nullptr || declared == index->declared.end()) {
			return;
		}
		const std::optional<std::pair<std::string, std::string>> texts = texts_of(*index, document->path);
		if (!texts.has_value()) {
			return;
		}
		const LineIndex lines(document->text);
		for (const size_t number : declared->second) {
			const IndexedDeclaration& declaration = index->declarations[number];
			if (declaration.text.empty() || declaration.in.has_value() || declaration.is_local()) {
				continue;
			}
			const std::optional<size_t> start = moved_forward(texts->first, texts->second, declaration.name_offset);
			const std::optional<size_t> end = moved_forward(texts->first, texts->second,
				static_cast<size_t>(declaration.name_offset) + declaration.name_length);
			if (!start.has_value() || !end.has_value()) {
				continue;
			}
			// SymbolKind: Function, Struct or Constant
			const int64_t kind = declaration.kind == "function" ? 12 : declaration.kind == "type" ? 23 : 14;
			const Value range = Object{ { "start", position_at(lines, *start, position_encoding) }, { "end", position_at(lines, *end, position_encoding) } };
			symbols.push_back(Object{ { "name", declaration.text }, { "detail", "inserted" }, { "kind", kind }, { "range", range },
				{ "selectionRange", range } });
		}
	}

	Value Server::definition(const Object* params) {
		const std::optional<Named> named = named_at(params);
		if (!named.has_value()) {
			return nullptr;
		}
		const IndexedDeclaration& declaration = named->index->declarations[named->declaration];
		Value declared = location_of(*named->index, declaration.file, declaration.name_offset,
			static_cast<size_t>(declaration.name_offset) + declaration.name_length);
		// One inserted code made: its #insert, and where its name is written, in the quote, when it is
		if (!declaration.written.has_value() || declared.getAsObject() == nullptr) {
			return declared;
		}
		Array both{ std::move(declared) };
		Value written = location_of(*named->index, declaration.written->file, declaration.written->offset,
			static_cast<size_t>(declaration.written->offset) + declaration.written->length);
		if (written.getAsObject() != nullptr) {
			both.push_back(std::move(written));
		}
		return both;
	}

	// What a declaration's line says, from its name: its first line, without an opening brace or a comma at its end
	static std::string signature_in(std::string_view text, const IndexedDeclaration& declaration) {
		if (declaration.name_offset >= text.size()) {
			return {};
		}
		std::string_view line = text.substr(declaration.name_offset);
		line = line.substr(0, line.find_first_of("\r\n"));
		while (!line.empty() && (line.back() == ' ' || line.back() == '\t' || line.back() == '{' || line.back() == ',')) {
			line.remove_suffix(1);
		}
		return std::string(line);
	}

	Value Server::hover(const Object* params) {
		const std::optional<Named> named = named_at(params);
		if (!named.has_value()) {
			return nullptr;
		}
		const IndexedDeclaration& declaration = named->index->declarations[named->declaration];
		std::string name;
		std::string signature;
		if (const std::optional<std::pair<std::string, std::string>> texts = texts_of(*named->index, declaration.file)) {
			name = texts->first.substr(declaration.name_offset, declaration.name_length);
			signature = signature_in(texts->first, declaration);
		}
		// A local's or a field's line holds more than it, or less, so it's its name and type
		if ((declaration.is_local() || "field" == declaration.kind) && !declaration.type.empty()) {
			signature = name + " : " + declaration.type;
		}
		// One inserted code made: its line is the #insert's, so it's its name and type
		if (!declaration.text.empty()) {
			name = declaration.text;
			signature = "type" == declaration.kind ? name + " :: " + declaration.kind
				: name + ("function" == declaration.kind || "constant" == declaration.kind ? " :: " : " : ") + declaration.type;
		}
		std::string markdown = "```hemera\n" + signature + "\n```";
		if (!declaration.text.empty()) {
			markdown += "\n\nDeclared by code an `#insert` puts in.";
		}
		if ("constant" == declaration.kind && !declaration.type.empty()) {
			markdown += "\n\nType: `" + declaration.type + "`";
		}
		if (!declaration.brief.empty()) {
			markdown += "\n\n" + declaration.brief;
		}
		if (!declaration.details.empty()) {
			markdown += "\n\n" + declaration.details;
		}
		if (!declaration.tags.empty()) {
			markdown += "\n";
			for (const IndexedDeclaration::Tag& tag : declaration.tags) {
				markdown += "\n*@" + tag.tag + "*" + (tag.name.empty() ? "" : " `" + tag.name + "`") + " — " + tag.text + "  ";
			}
		}
		const std::string uri = document_uri(params).value_or("");
		const Document* document = open_documents.find_uri(uri);
		const LineIndex lines(document != nullptr ? document->text : std::string());
		return Object{
			{ "contents", Object{ { "kind", "markdown" }, { "value", markdown } } },
			{ "range", Object{ { "start", position_at(lines, named->start, position_encoding) },
				{ "end", position_at(lines, named->end, position_encoding) } } },
		};
	}

	Value Server::references(const Object* params) {
		const std::optional<Named> named = named_at(params);
		if (!named.has_value()) {
			return nullptr;
		}
		const Object* context = params->getObject("context");
		const bool with_declaration = context != nullptr && context->getBoolean("includeDeclaration").value_or(false);
		Array found;
		for (const LoadedIndex::Place& place : named->index->places_of(named->declaration, with_declaration)) {
			Value location = location_of(*named->index, place.file, place.offset, static_cast<size_t>(place.offset) + place.length);
			if (location.getAsObject() != nullptr) {
				found.push_back(std::move(location));
			}
		}
		return found;
	}

	Value Server::highlights(const Object* params) {
		const std::optional<Named> named = named_at(params);
		const std::optional<std::string> uri = document_uri(params);
		const Document* document = uri.has_value() ? open_documents.find_uri(*uri) : nullptr;
		if (!named.has_value() || document == nullptr) {
			return nullptr;
		}
		const LoadedIndex& index = *named->index;
		const IndexedDeclaration& declaration = index.declarations[named->declaration];
		const std::string key = path_key(document->path);
		const std::optional<std::pair<std::string, std::string>> texts = texts_of(index, document->path);
		if (!texts.has_value()) {
			return nullptr;
		}
		// This file's uses alone, not every file's, as references looks through
		std::vector<std::pair<uint32_t, uint32_t>> places;
		if (path_key(declaration.file) == key && declaration.text.empty()) {
			places.emplace_back(declaration.name_offset, declaration.name_length);
		}
		if (auto uses = index.uses.find(key); uses != index.uses.end()) {
			for (const IndexedUse& use : uses->second) {
				if (use.declaration == named->declaration) {
					places.emplace_back(use.offset, use.length);
				}
			}
		}
		const Moved moved(texts->first, texts->second);
		const LineIndex lines(texts->second);
		Array found;
		for (const auto& [offset, length] : places) {
			const std::optional<size_t> start = moved.forward(offset);
			const std::optional<size_t> end = moved.forward(static_cast<size_t>(offset) + length);
			if (!start.has_value() || !end.has_value()) {
				continue;
			}
			// DocumentHighlightKind: its declaration Write (3), each use Read (2)
			const bool declared_here = path_key(declaration.file) == key && offset == declaration.name_offset;
			found.push_back(Object{ { "range", Object{ { "start", position_at(lines, *start, position_encoding) },
				{ "end", position_at(lines, *end, position_encoding) } } }, { "kind", declared_here ? 3 : 2 } });
		}
		return found;
	}

	std::optional<std::string> Server::refuse_rename(const Object* params, std::optional<Named>& named) {
		named = named_at(params);
		if (!named.has_value()) {
			return std::string("There's no name here that the last check knows. Save, and try again once it's checked.");
		}
		const IndexedDeclaration& declaration = named->index->declarations[named->declaration];
		if (!declaration.text.empty()) {
			return std::string("It's declared by code an #insert puts in, which writes its name; change it there.");
		}
		const bool in_workspace = std::any_of(workspace_folders.begin(), workspace_folders.end(),
			[&](const std::string& folder) { return within(declaration.file, folder); });
		if (!in_workspace) {
			return "It's declared outside the workspace, in " + declaration.file + ".";
		}
		for (const LoadedIndex::Place& place : named->index->places_of(named->declaration, true)) {
			const std::optional<std::pair<std::string, std::string>> texts = texts_of(*named->index, place.file);
			if (!texts.has_value() || texts->first != texts->second) {
				return place.file + " has changed since it was checked. Save, and try again once it's checked.";
			}
		}
		return std::nullopt;
	}

	Value Server::prepare_rename(const Object* params) {
		std::optional<Named> named;
		if (std::optional<std::string> why = refuse_rename(params, named)) {
			refusal = "Can't rename: " + *why;
			return nullptr;
		}
		const std::optional<std::string> uri = document_uri(params);
		const Document* document = open_documents.find_uri(*uri);
		const LineIndex lines(document->text);
		return Object{
			{ "range", Object{ { "start", position_at(lines, named->start, position_encoding) },
				{ "end", position_at(lines, named->end, position_encoding) } } },
			{ "placeholder", document->text.substr(named->start, named->end - named->start) },
		};
	}

	// Whether text can be a name: letters, digits and _, or anything past ASCII, not starting with a digit
	static bool is_name(std::string_view text) {
		if (text.empty() || (text[0] >= '0' && text[0] <= '9')) {
			return false;
		}
		return std::all_of(text.begin(), text.end(), [](char c) {
			const unsigned char byte = static_cast<unsigned char>(c);
			return byte >= 0x80 || byte == '_' || (byte >= '0' && byte <= '9') || (byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z');
		});
	}

	Value Server::rename(const Object* params) {
		const std::string new_name = params != nullptr ? params->getString("newName").value_or("").str() : std::string();
		if (!is_name(new_name)) {
			refusal = "Can't rename: \"" + new_name + "\" isn't a name.";
			return nullptr;
		}
		std::optional<Named> named;
		if (std::optional<std::string> why = refuse_rename(params, named)) {
			refusal = "Can't rename: " + *why;
			return nullptr;
		}
		// Every place it's named, as one edit, file by file
		Object changes;
		for (const LoadedIndex::Place& place : named->index->places_of(named->declaration, true)) {
			Value location = location_of(*named->index, place.file, place.offset, static_cast<size_t>(place.offset) + place.length);
			const Object* found = location.getAsObject();
			if (found == nullptr) {
				continue;
			}
			const std::string uri = found->getString("uri")->str();
			Value* edits = changes.get(uri);
			if (edits == nullptr) {
				changes[uri] = Array{};
				edits = changes.get(uri);
			}
			edits->getAsArray()->push_back(Object{ { "range", *found->get("range") }, { "newText", new_name } });
		}
		return Object{ { "changes", std::move(changes) } };
	}

	const Server::Parses* Server::parsed(const std::string& uri) {
		const Document* document = open_documents.find_uri(uri);
		if (document == nullptr) {
			return nullptr;
		}
		Parses& entry = parses[uri];
		if (entry.current == nullptr || entry.current->version != document->version || entry.current->text != document->text) {
			entry.current = parse_document(document->text, document->version, document->path.empty() ? uri : document->path);
			if (entry.current->recovered != nullptr) {
				entry.last_tree = entry.current;
			}
		}
		return &entry;
	}
}

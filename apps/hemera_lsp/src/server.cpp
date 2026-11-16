#include "server.h"

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <tuple>
#include <utility>

#include "features.h"
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
		// A response to a request of the server's; it sends none, so there's nothing to match it to
		else if (object->get("id") == nullptr) {
			respond_error(nullptr, error_codes::INVALID_REQUEST, "a message has a method, or is a response");
		}
		std::lock_guard<std::mutex> lock(state);
		return !exited;
	}

	void Server::request(const Value& id, std::string_view method, const Object* params) {
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
		if (std::optional<Value> answer = document_request(method, params)) {
			lock.unlock();
			respond(id, std::move(*answer));
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
				for (const auto& [root, uris] : published) {
					for (const std::string& published_uri : uris) {
						clearing.push_back(Object{ { "jsonrpc", "2.0" }, { "method", "textDocument/publishDiagnostics" },
							{ "params", Object{ { "uri", published_uri }, { "diagnostics", Array{} } } } });
					}
				}
				published.clear();
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
				{ "foldingRangeProvider", true },
				{ "definitionProvider", true },
				{ "hoverProvider", true },
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

	void Server::check(const std::string& uri) {
		CheckJob job;
		{
			std::lock_guard<std::mutex> lock(state);
			const Document* document = open_documents.find_uri(uri);
			if (document == nullptr || document->path.empty() || !document->path.ends_with(".hsc")) {
				return;
			}
			job.root = root_for(document->path);
			job.generation = generation;
			job.arguments = { settings.compiler_path, "--check", "--diagnostics=json" };
			job.arguments.insert(job.arguments.end(), settings.arguments.begin(), settings.arguments.end());
			// The name index, for the answers that come from it (docs/editor.md)
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
			job.arguments.push_back(job.root);
		}
		checker->request(std::move(job));
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
				// The index, read whether the check found errors or not, which the next check's replaces
				if (!job.index_file.empty()) {
					if (std::optional<LoadedIndex> index = read_index(read_file(job.index_file).value_or(""), base_folder)) {
						index->texts = job.texts;
						indexes[path_key(job.root)] = std::make_shared<const LoadedIndex>(std::move(*index));
					}
				}
				const std::vector<CompilerDiagnostic> found = parse_diagnostics(result.output);
				// By file, each once, as one file can be in several of a build's targets
				std::map<std::string, std::vector<const CompilerDiagnostic*>> by_file;
				std::map<std::string, std::string> file_paths;
				std::set<std::tuple<std::string, std::string, std::string, uint32_t, uint32_t, std::string>> seen;
				for (const CompilerDiagnostic& diagnostic : found) {
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
						published_diagnostics.push_back(std::move(published_diagnostic));
					}
					now.insert(uri);
					messages.push_back(Object{ { "jsonrpc", "2.0" }, { "method", "textDocument/publishDiagnostics" },
						{ "params", Object{ { "uri", uri }, { "diagnostics", std::move(published_diagnostics) } } } });
				}
				// What had diagnostics from this root before and has none now is cleared
				for (const std::string& uri : published[job.root]) {
					if (!now.contains(uri)) {
						messages.push_back(Object{ { "jsonrpc", "2.0" }, { "method", "textDocument/publishDiagnostics" },
							{ "params", Object{ { "uri", uri }, { "diagnostics", Array{} } } } });
					}
				}
				published[job.root] = std::move(now);
			}
		}
		for (Value& message : messages) {
			send(std::move(message));
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
		if (method == "textDocument/hover") {
			return hover(params);
		}
		if (method == "textDocument/foldingRange") {
			// This version, from its tokens, whether it parses or not (decision 4)
			const Parses* parses_of = uri.has_value() ? parsed(*uri) : nullptr;
			return parses_of != nullptr ? folding_ranges(*parses_of->current) : Value(Array{});
		}
		if (method == "textDocument/documentSymbol") {
			// The last version that parsed, when this one doesn't (decision 4)
			const Parses* parses_of = uri.has_value() ? parsed(*uri) : nullptr;
			return parses_of != nullptr && parses_of->last_tree != nullptr ? document_symbols(*parses_of->last_tree, position_encoding)
				: Value(Array{});
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

	Value Server::definition(const Object* params) {
		const std::optional<Named> named = named_at(params);
		if (!named.has_value()) {
			return nullptr;
		}
		const IndexedDeclaration& declaration = named->index->declarations[named->declaration];
		return location_of(*named->index, declaration.file, declaration.name_offset,
			static_cast<size_t>(declaration.name_offset) + declaration.name_length);
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
		if (("local" == declaration.kind || "field" == declaration.kind) && !declaration.type.empty()) {
			signature = name + " : " + declaration.type;
		}
		std::string markdown = "```hemera\n" + signature + "\n```";
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

	const Server::Parses* Server::parsed(const std::string& uri) {
		const Document* document = open_documents.find_uri(uri);
		if (document == nullptr) {
			return nullptr;
		}
		Parses& entry = parses[uri];
		if (entry.current == nullptr || entry.current->version != document->version || entry.current->text != document->text) {
			entry.current = parse_document(document->text, document->version, document->path.empty() ? uri : document->path);
			if (entry.current->tree != nullptr) {
				entry.last_tree = entry.current;
			}
		}
		return &entry;
	}
}

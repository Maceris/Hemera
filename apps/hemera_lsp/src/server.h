#pragma once

#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <vector>

#include "assist.h"
#include "checker.h"
#include "completion.h"
#include "documents.h"
#include "index.h"
#include "parsing.h"
#include "serve_client.h"

#include "llvm/Support/JSON.h"

namespace hemera::lsp {

	/*
	 * What the client sets (docs/editor.md), from initialize's initializationOptions or a
	 * workspace/didChangeConfiguration's settings.hemera.
	 */
	struct Settings {
		// The compiler: a path, or a name looked for on the PATH
		std::string compiler_path = "hemera";
		// The package checked for a file in the workspace, like a build package's folder; empty for the file's own
		std::string root;
		// More of the compiler's flags, like --setting=name=value, put before the package's path
		std::vector<std::string> arguments;
		// The most memory the long-lived checker (hemera --serve) may use before it starts again, in MB; 0 for no limit
		size_t checker_memory_mb = 8192;
	};

	/*
	 * The language server's state and what it does with each message from the client (docs/editor.md): the
	 * lifecycle, initialize to exit, the documents the client has open, and the checks that find their diagnostics.
	 * It sends what it has to say through send, which is called on the thread that called handle, or on the
	 * checker's, so it has to be safe to call from either.
	 */
	class Server {
	public:
		// Sends one message to the client: a response, or a notification like publishDiagnostics
		using Send = std::function<void(llvm::json::Value message)>;

		// launch runs the compiler for each check; launch_process, unless a test gives another
		/*
		 * A check of everything runs hemera as a process of its own, and a quick check of a saved file's targets
		 * through hemera --serve, which keeps the build between them (docs/editor.md).
		 */
		explicit Server(Send send);
		// Every check through launch, as tests give it
		Server(Send send, Launch launch);
		~Server();

		/*
		 * Handles one message from the client, a request, which is answered through send, or a notification.
		 * Returns false once the client has sent exit, when the server should stop with exit_code.
		 */
		bool handle(const llvm::json::Value& message);

		// Answers a message that wasn't JSON with JSON-RPC's parse error, why being what was wrong with it
		void malformed(std::string why);

		// 0 when exit came after shutdown, as it should, otherwise 1
		int exit_code() const;

		// The position encoding chosen in initialize: UTF-8 when the client offered it, otherwise UTF-16
		Encoding encoding() const;

		// A copy of the open documents, for tests
		Documents documents() const;

		// Waits until no check is running or waiting, and what they found is published, for tests
		void wait_for_checks();

		/*
		 * The package checked for the file at path (decision 3, docs/editor.md): the root setting, beneath the first
		 * workspace folder when it's relative, if path is in a workspace folder; otherwise path's own folder.
		 */
		std::string root_for(const std::string& path) const;

	private:
		Send send;
		mutable std::mutex state;
		Documents open_documents;
		Settings settings;
		// The workspace's folders, with / throughout
		std::vector<std::string> workspace_folders;
		// Where base's files are, for diagnostics in <base>/...; empty when it isn't found
		std::string base_folder;
		Encoding position_encoding = Encoding::UTF16;
		// Whether the client takes workspace/semanticTokens/refresh, sent after each check; and how many requests were sent
		bool semantic_refresh = false;
		uint64_t requests_sent = 0;
		bool initialized = false;
		bool shut_down = false;
		bool exited = false;
		// Whether the client was told the compiler couldn't run, which it's told once
		bool told_cannot_run = false;
		// Counts changes of settings: a check made under older ones is left out when it finishes
		uint64_t generation = 0;
		/*
		 * For each root checked: the diagnostics each of its targets' last check found, by target, "" for the build's
		 * own code or a program, which a check of some targets replaces only theirs of; and the URIs it published
		 * diagnostics for, to clear any it no longer has.
		 */
		struct Found {
			std::map<std::string, std::vector<CompilerDiagnostic>> by_target;
			std::set<std::string> published;
			/*
			 * The text each open document had when a check found what's in by_target, by path_key, which fixes' offsets
			 * count in; a check's replaces those it read, and a file not there was read from disk
			 */
			std::map<std::string, std::string> texts;
		};
		std::map<std::string, Found> findings;
		// Each root's name index, from its last check that wrote one, by path_key of the root
		std::map<std::string, std::shared_ptr<const LoadedIndex>> indexes;

		// A name found from a position in an open document, by the index of its root
		struct Named {
			std::shared_ptr<const LoadedIndex> index;
			size_t declaration = 0;
			// Where the name is in the document now, in bytes
			size_t start = 0;
			size_t end = 0;
		};

		/*
		 * The name at params' textDocument and position, in the index of the document's root, the position moved
		 * back through what's changed since the check; empty when there's no name there, the index doesn't know it,
		 * or it's in what's changed. state must be held.
		 */
		std::optional<Named> named_at(const llvm::json::Object* params);

		// A diagnostic's place, a file and a line and column as the compiler gives them, as a Location
		llvm::json::Value place_location(const std::string& file, uint32_t line, uint32_t column);

		// The declarations code an #insert in the document puts in, from the index, added to its outline's symbols
		void add_inserted_symbols(const std::string& uri, llvm::json::Array& symbols);

		// textDocument/completion's answer (completion_items), for params' textDocument and position. state must be held.
		llvm::json::Value completion(const llvm::json::Object* params);

		/*
		 * textDocument/semanticTokens/full's answer (semantic_tokens), for params' textDocument, or with range,
		 * semanticTokens/range's, for its range too. state must be held.
		 */
		llvm::json::Value tokens(const llvm::json::Object* params, bool range);

		/*
		 * The tables completion, signature help and workspace symbols look up in, for each index, made the first time
		 * they're asked of, and dropped once their index is replaced. state must be held.
		 */
		std::map<const LoadedIndex*, std::shared_ptr<CompletionTables>> tables;
		CompletionTables* tables_for(const std::shared_ptr<const LoadedIndex>& index);

		// The index of the root a file is checked in, or else any that knows the file; null when none does
		std::shared_ptr<const LoadedIndex> index_for(const std::string& file) const;

		/*
		 * What signature help and inlay hints are asked with, for document, with the text index's check read of it, which
		 * is kept in assist_texts while it's used. state must be held.
		 */
		AssistRequest assist_request(const Document& document, const std::shared_ptr<const LoadedIndex>& index);
		std::string assist_texts;

		// textDocument/signatureHelp's, textDocument/inlayHint's and workspace/symbol's answers. state must be held.
		llvm::json::Value signature(const llvm::json::Object* params);
		llvm::json::Value hints(const llvm::json::Object* params);
		llvm::json::Value symbols(const llvm::json::Object* params);

		// textDocument/documentHighlight's answer: each place in the document the name at params' position is named
		llvm::json::Value highlights(const llvm::json::Object* params);

		/*
		 * textDocument/codeAction's answer: for the lines of params' range, each fix of each diagnostic there, moved to the
		 * text now; writing a doc comment for a declaration named where the range starts that has none; and organizing
		 * the file's imports as the formatter sorts them. Only the kinds params' context asks for, when it says.
		 */
		llvm::json::Value code_actions(const llvm::json::Object* params);

		// The diagnostic as it's published, its place in index's text
		llvm::json::Object lsp_diagnostic(const CompilerDiagnostic& diagnostic, const LineIndex& index);

		/*
		 * textDocument/rangeFormatting's answer, or with on_type, textDocument/onTypeFormatting's for the item the
		 * character before params' position is in: format_parts.
		 */
		llvm::json::Value format_range(const llvm::json::Object* params, bool on_type);

		/*
		 * The document formatted, but only the top-level items from start to end changed, byte offsets in its text: the
		 * formatter's output and the text matched item by item, each from its start to the next's, the edits only where
		 * they differ. None when it doesn't parse, or their items don't match.
		 */
		llvm::json::Array format_parts(const std::string& uri, size_t start, size_t end);

		/*
		 * A file's text as the index's offsets count it, and as it is now: an open document's, from when the check
		 * began, and its own; another file's, from disk, both. Empty if the file can't be read. state must be held.
		 */
		std::optional<std::pair<std::string, std::string>> texts_of(const LoadedIndex& index, const std::string& file);

		// Where the index's offsets start and end in a file now, as a Location, or null if they're in what's changed
		llvm::json::Value location_of(const LoadedIndex& index, const std::string& file, size_t start, size_t end);

		llvm::json::Value definition(const llvm::json::Object* params);
		llvm::json::Value hover(const llvm::json::Object* params);
		llvm::json::Value references(const llvm::json::Object* params);

		/*
		 * Why the name at params' position can't be renamed (decision 5): it isn't one the index knows, it's declared
		 * outside the workspace, or a file it's named in has changed since the check. Empty if it can, when named is
		 * set to it.
		 */
		std::optional<std::string> refuse_rename(const llvm::json::Object* params, std::optional<Named>& named);
		llvm::json::Value prepare_rename(const llvm::json::Object* params);
		llvm::json::Value rename(const llvm::json::Object* params);

		// Why the request being answered failed, set by what answers it, which is answered as an error instead
		std::optional<std::string> refusal;
		// Last, so it's stopped before what its thread uses goes
		// hemera --serve, for quick checks, made again when the compiler or its memory limit changes; null in tests
		std::shared_ptr<ServeClient> serve_client;
		bool serving = false;
		std::unique_ptr<Checker> checker;

		void respond(const llvm::json::Value& id, llvm::json::Value result);
		void respond_error(const llvm::json::Value& id, int64_t code, std::string message);
		void request(const llvm::json::Value& id, std::string_view method, const llvm::json::Object* params);
		void notification(std::string_view method, const llvm::json::Object* params);
		llvm::json::Value initialize(const llvm::json::Object* params);
		/*
		 * The answer to a request about one open document, like textDocument/formatting; empty for a method that isn't
		 * one of those. state must be held.
		 */
		std::optional<llvm::json::Value> document_request(std::string_view method, const llvm::json::Object* params);
		// textDocument/formatting's edits, an array, empty when the file doesn't parse or would lose a comment
		llvm::json::Value format(const std::string& uri);
		void read_settings(const llvm::json::Object* hemera);
		void check(const std::string& uri);
		/*
		 * A check of root: of every target, writing the index, when targets is empty; otherwise of those of a build
		 * package's targets. state must be held.
		 */
		CheckJob job_for(const std::string& root, const std::vector<std::string>& targets);
		void checked(const CheckJob& job, const RunResult& result);
		// hemera/state's answer (compare_saves.py). state must be held.
		llvm::json::Value state_for_tests();

		// What an open document parses to: its current version's, and the last version that made a tree, by URI
		struct Parses {
			std::shared_ptr<ParsedDocument> current;
			// The last version that lexed, whose tree the parser recovered from any errors
			std::shared_ptr<ParsedDocument> last_tree;
		};
		std::map<std::string, Parses> parses;

		/*
		 * The open document uri names, parsed as it is now, from the cache or parsed now (decision 6: on the thread
		 * answering requests); null if it isn't open. state must be held.
		 */
		const Parses* parsed(const std::string& uri);
	};

	// JSON-RPC's and the Language Server Protocol's error codes
	namespace error_codes {
		constexpr int64_t PARSE_ERROR = -32700;
		constexpr int64_t INVALID_REQUEST = -32600;
		constexpr int64_t METHOD_NOT_FOUND = -32601;
		constexpr int64_t INVALID_PARAMS = -32602;
		constexpr int64_t SERVER_NOT_INITIALIZED = -32002;
		// A request that was understood, but couldn't be done, like a rename that's refused
		constexpr int64_t REQUEST_FAILED = -32803;
	}

	/*
	 * Where a diagnostic at byte column (counting from 0) of line ends: past the word there, letters, digits, _ and
	 * non-ASCII; past a string literal it starts, to its closing quote or the line's end; otherwise past the one
	 * character. At the line's end, it's column itself.
	 */
	uint32_t token_end(std::string_view line, uint32_t column);

	/*
	 * The folder holding base's files for a compiler at compiler_path (a path, or a name found on the PATH): the
	 * nearest folder above it with base/runtime in it, as the repository's root is in development. Empty if none is.
	 */
	std::string find_base_folder(const std::string& compiler_path);
}

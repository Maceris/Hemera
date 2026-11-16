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

#include "checker.h"
#include "documents.h"
#include "index.h"
#include "parsing.h"

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
		explicit Server(Send send, Launch launch = launch_process);
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
		bool initialized = false;
		bool shut_down = false;
		bool exited = false;
		// Whether the client was told the compiler couldn't run, which it's told once
		bool told_cannot_run = false;
		// Counts changes of settings: a check made under older ones is left out when it finishes
		uint64_t generation = 0;
		// For each root checked, the URIs it published diagnostics for, to clear any it no longer has
		std::map<std::string, std::set<std::string>> published;
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

		/*
		 * A file's text as the index's offsets count it, and as it is now: an open document's, from when the check
		 * began, and its own; another file's, from disk, both. Empty if the file can't be read. state must be held.
		 */
		std::optional<std::pair<std::string, std::string>> texts_of(const LoadedIndex& index, const std::string& file);

		// Where the index's offsets start and end in a file now, as a Location, or null if they're in what's changed
		llvm::json::Value location_of(const LoadedIndex& index, const std::string& file, size_t start, size_t end);

		llvm::json::Value definition(const llvm::json::Object* params);
		llvm::json::Value hover(const llvm::json::Object* params);
		// Last, so it's stopped before what its thread uses goes
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
		void checked(const CheckJob& job, const RunResult& result);

		// What an open document parses to: its current version's, and the last version that made a tree, by URI
		struct Parses {
			std::shared_ptr<ParsedDocument> current;
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

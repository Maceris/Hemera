#pragma once

#include <cstdint>
#include <functional>
#include <optional>
#include <string>

#include "documents.h"

#include "llvm/Support/JSON.h"

namespace hemera::lsp {

	/*
	 * The language server's state and what it does with each message from the client (docs/editor.md): the
	 * lifecycle, initialize to exit, and the documents the client has open. It sends what it has to say through
	 * send, which is called on the thread that called handle.
	 */
	class Server {
	public:
		// Sends one message to the client: a response, or a notification like publishDiagnostics
		using Send = std::function<void(llvm::json::Value message)>;

		explicit Server(Send send);

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

		const Documents& documents() const;

	private:
		Send send;
		Documents open_documents;
		Encoding position_encoding = Encoding::UTF16;
		bool initialized = false;
		bool shut_down = false;
		bool exited = false;

		void respond(const llvm::json::Value& id, llvm::json::Value result);
		void respond_error(const llvm::json::Value& id, int64_t code, std::string message);
		void request(const llvm::json::Value& id, std::string_view method, const llvm::json::Object* params);
		void notification(std::string_view method, const llvm::json::Object* params);
		llvm::json::Value initialize(const llvm::json::Object* params);
	};

	// JSON-RPC's and the Language Server Protocol's error codes
	namespace error_codes {
		constexpr int64_t PARSE_ERROR = -32700;
		constexpr int64_t INVALID_REQUEST = -32600;
		constexpr int64_t METHOD_NOT_FOUND = -32601;
		constexpr int64_t INVALID_PARAMS = -32602;
		constexpr int64_t SERVER_NOT_INITIALIZED = -32002;
	}
}

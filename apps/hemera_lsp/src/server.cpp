#include "server.h"

#include <utility>

#include "version.h"

namespace hemera::lsp {

	using llvm::json::Array;
	using llvm::json::Object;
	using llvm::json::Value;

	Server::Server(Send send) : send(std::move(send)) {}

	int Server::exit_code() const {
		return shut_down ? 0 : 1;
	}

	Encoding Server::encoding() const {
		return position_encoding;
	}

	const Documents& Server::documents() const {
		return open_documents;
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
			return !exited;
		}
		const std::optional<llvm::StringRef> method = object->getString("method");
		const Value* id = object->get("id");
		if (!method.has_value()) {
			// A response to a request of the server's; it sends none, so there's nothing to match it to
			if (id == nullptr) {
				respond_error(nullptr, error_codes::INVALID_REQUEST, "a message has a method, or is a response");
			}
			return !exited;
		}
		const Object* params = object->getObject("params");
		if (id != nullptr) {
			request(*id, *method, params);
		}
		else {
			notification(*method, params);
		}
		return !exited;
	}

	void Server::request(const Value& id, std::string_view method, const Object* params) {
		if (method == "initialize") {
			if (initialized) {
				respond_error(id, error_codes::INVALID_REQUEST, "initialize was already sent");
				return;
			}
			initialized = true;
			respond(id, initialize(params));
			return;
		}
		if (!initialized) {
			respond_error(id, error_codes::SERVER_NOT_INITIALIZED, "initialize comes first");
			return;
		}
		if (shut_down) {
			respond_error(id, error_codes::INVALID_REQUEST, "the server has shut down");
			return;
		}
		if (method == "shutdown") {
			shut_down = true;
			respond(id, nullptr);
			return;
		}
		respond_error(id, error_codes::METHOD_NOT_FOUND, std::string("no method ") + std::string(method));
	}

	// The text document's uri, from params' textDocument
	static std::optional<std::string> document_uri(const Object* params) {
		const Object* document = params != nullptr ? params->getObject("textDocument") : nullptr;
		const std::optional<llvm::StringRef> uri = document != nullptr ? document->getString("uri") : std::nullopt;
		return uri.has_value() ? std::optional<std::string>(uri->str()) : std::nullopt;
	}

	void Server::notification(std::string_view method, const Object* params) {
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
		else if (method == "textDocument/didClose" && uri.has_value()) {
			open_documents.close(*uri);
		}
		// Anything else, like didSave and $/ notifications, needs nothing yet
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
		return Object{
			{ "capabilities", Object{
				{ "positionEncoding", Encoding::UTF8 == position_encoding ? "utf-8" : "utf-16" },
				{ "textDocumentSync", Object{
					{ "openClose", true },
					// Full: each change sends the whole text
					{ "change", 1 },
					{ "save", Object{ { "includeText", false } } },
				} },
			} },
			{ "serverInfo", Object{ { "name", "hemera-lsp" }, { "version", VERSION_STR } } },
		};
	}
}

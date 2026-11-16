#include <string>
#include <vector>

#include "gtest/gtest.h"

#include "server.h"

#include "llvm/Support/JSON.h"

using hemera::lsp::Encoding;
using hemera::lsp::Server;
using llvm::json::Array;
using llvm::json::Object;
using llvm::json::Value;

namespace {

	// A server whose messages to the client are kept, in order
	struct Session {
		std::vector<Value> sent;
		Server server{ [this](Value message) { sent.push_back(std::move(message)); } };

		bool request(int64_t id, std::string method, Object params = {}) {
			return server.handle(Object{ { "jsonrpc", "2.0" }, { "id", id }, { "method", std::move(method) }, { "params", std::move(params) } });
		}

		bool notify(std::string method, Object params = {}) {
			return server.handle(Object{ { "jsonrpc", "2.0" }, { "method", std::move(method) }, { "params", std::move(params) } });
		}

		void initialize(Array encodings = {}) {
			request(1, "initialize", Object{ { "capabilities", Object{ { "general", Object{ { "positionEncodings", std::move(encodings) } } } } } });
			notify("initialized");
		}

		const Object& last() const {
			return *sent.back().getAsObject();
		}

		// The last response's error code, or 0 if it succeeded
		int64_t last_error() const {
			const Object* error = last().getObject("error");
			return error != nullptr ? error->getInteger("code").value_or(0) : 0;
		}
	};

	Object document(std::string uri, std::string text, int64_t version) {
		return Object{ { "textDocument", Object{ { "uri", std::move(uri) }, { "languageId", "hemera" }, { "version", version },
			{ "text", std::move(text) } } } };
	}
}

TEST(Server, InitializeAnswersWithCapabilities) {
	Session session;
	session.request(1, "initialize", Object{ { "capabilities", Object{} } });

	ASSERT_EQ(1u, session.sent.size());
	EXPECT_EQ(Value(1), *session.last().get("id"));
	const Object* capabilities = session.last().getObject("result")->getObject("capabilities");
	ASSERT_NE(nullptr, capabilities);
	EXPECT_EQ("utf-16", capabilities->getString("positionEncoding"));
	EXPECT_EQ(1, capabilities->getObject("textDocumentSync")->getInteger("change"));
	EXPECT_EQ("hemera-lsp", session.last().getObject("result")->getObject("serverInfo")->getString("name"));
}

TEST(Server, ChoosesUtf8WhenOffered) {
	Session session;
	session.initialize(Array{ "utf-16", "utf-8" });

	EXPECT_EQ(Encoding::UTF8, session.server.encoding());
	EXPECT_EQ("utf-8", session.sent[0].getAsObject()->getObject("result")->getObject("capabilities")->getString("positionEncoding"));
}

TEST(Server, RequestsBeforeInitializeAreRefused) {
	Session session;
	session.request(1, "shutdown");

	EXPECT_EQ(hemera::lsp::error_codes::SERVER_NOT_INITIALIZED, session.last_error());
}

TEST(Server, UnknownRequestsAreNotFound) {
	Session session;
	session.initialize();
	session.request(2, "textDocument/hover");

	EXPECT_EQ(hemera::lsp::error_codes::METHOD_NOT_FOUND, session.last_error());
	EXPECT_EQ(Value(2), *session.last().get("id"));
}

TEST(Server, UnknownNotificationsAreIgnored) {
	Session session;
	session.initialize();
	const size_t before = session.sent.size();

	EXPECT_TRUE(session.notify("$/setTrace", Object{ { "value", "off" } }));
	EXPECT_EQ(before, session.sent.size());
}

TEST(Server, ShutdownThenExitIsClean) {
	Session session;
	session.initialize();
	session.request(2, "shutdown");
	EXPECT_EQ(0, session.last_error());
	EXPECT_EQ(Value(nullptr), *session.last().get("result"));
	session.request(3, "shutdown");
	EXPECT_EQ(hemera::lsp::error_codes::INVALID_REQUEST, session.last_error());

	EXPECT_FALSE(session.notify("exit"));
	EXPECT_EQ(0, session.server.exit_code());
}

TEST(Server, ExitWithoutShutdownIsAnError) {
	Session session;
	session.initialize();

	EXPECT_FALSE(session.notify("exit"));
	EXPECT_EQ(1, session.server.exit_code());
}

TEST(Server, MalformedMessagesGetParseErrors) {
	Session session;
	session.server.malformed("not JSON");

	EXPECT_EQ(hemera::lsp::error_codes::PARSE_ERROR, session.last_error());
	EXPECT_EQ(Value(nullptr), *session.last().get("id"));
}

TEST(Server, KeepsOpenDocumentsInStep) {
	Session session;
	session.initialize();
	session.notify("textDocument/didOpen", document("file:///d%3A/project/main.hsc", "first", 1));
	session.notify("textDocument/didChange", Object{
		{ "textDocument", Object{ { "uri", "file:///d%3A/project/main.hsc" }, { "version", 2 } } },
		{ "contentChanges", Array{ Object{ { "text", "second" } } } },
	});

	const hemera::lsp::Document* open = session.server.documents().find_path("d:/project/main.hsc");
	ASSERT_NE(nullptr, open);
	EXPECT_EQ("second", open->text);
	EXPECT_EQ(2, open->version);
	EXPECT_EQ("file:///d%3A/project/main.hsc", open->uri);

	session.notify("textDocument/didClose", Object{ { "textDocument", Object{ { "uri", "file:///d%3A/project/main.hsc" } } } });
	EXPECT_EQ(nullptr, session.server.documents().find_path("d:/project/main.hsc"));
}

TEST(Server, NotificationsAfterShutdownAreDropped) {
	Session session;
	session.initialize();
	session.request(2, "shutdown");
	session.notify("textDocument/didOpen", document("file:///d%3A/main.hsc", "text", 1));

	EXPECT_TRUE(session.server.documents().all().empty());
}

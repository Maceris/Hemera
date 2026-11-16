#include <filesystem>
#include <format>
#include <fstream>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "gtest/gtest.h"

#include "server.h"
#include "uri.h"

#include "llvm/Support/JSON.h"

using hemera::lsp::Encoding;
using hemera::lsp::Run;
using hemera::lsp::RunResult;
using hemera::lsp::Server;
using llvm::json::Array;
using llvm::json::Object;
using llvm::json::Value;

namespace {

	// A run that's already over, with what a fake compiler printed
	class FinishedRun : public Run {
	public:
		explicit FinishedRun(RunResult result) : result(std::move(result)) {}
		RunResult wait() override { return result; }
		void stop() override {}

	private:
		RunResult result;
	};

	/*
	 * A server whose messages to the client are kept, in order, with a fake compiler: each check prints output, and
	 * its command is kept.
	 */
	struct Session {
		std::mutex mutex;
		std::vector<Value> sent;
		std::vector<std::vector<std::string>> commands;
		std::string output;
		bool starts = true;
		Server server{ [this](Value message) {
			std::lock_guard<std::mutex> lock(mutex);
			sent.push_back(std::move(message));
		}, [this](const std::vector<std::string>& arguments) -> std::unique_ptr<Run> {
			std::lock_guard<std::mutex> lock(mutex);
			commands.push_back(arguments);
			RunResult result;
			result.started = starts;
			result.output = output;
			result.error = starts ? "" : "couldn't find hemera on the PATH";
			return std::make_unique<FinishedRun>(result);
		} };

		bool request(int64_t id, std::string method, Object params = {}) {
			return server.handle(Object{ { "jsonrpc", "2.0" }, { "id", id }, { "method", std::move(method) }, { "params", std::move(params) } });
		}

		bool notify(std::string method, Object params = {}) {
			return server.handle(Object{ { "jsonrpc", "2.0" }, { "method", std::move(method) }, { "params", std::move(params) } });
		}

		void initialize(Array encodings = {}, Object options = {}, Array folders = {}) {
			request(1, "initialize", Object{ { "capabilities", Object{ { "general", Object{ { "positionEncodings", std::move(encodings) } } } } },
				{ "initializationOptions", std::move(options) }, { "workspaceFolders", std::move(folders) } });
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

		// The diagnostics published, each publishDiagnostics' params, in order
		std::vector<Object> published() {
			server.wait_for_checks();
			std::lock_guard<std::mutex> lock(mutex);
			std::vector<Object> found;
			for (const Value& message : sent) {
				const Object* object = message.getAsObject();
				if (object->getString("method") == llvm::StringRef("textDocument/publishDiagnostics")) {
					found.push_back(*object->getObject("params"));
				}
			}
			return found;
		}
	};

	Object document(std::string uri, std::string text, int64_t version) {
		return Object{ { "textDocument", Object{ { "uri", std::move(uri) }, { "languageId", "hemera" }, { "version", version },
			{ "text", std::move(text) } } } };
	}

	// A folder of the test's own, emptied, with / throughout
	std::string fresh_folder(const std::string& name) {
		const std::filesystem::path folder = std::filesystem::temp_directory_path() / "hemera_lsp_test" / name;
		std::filesystem::remove_all(folder);
		std::filesystem::create_directories(folder);
		return std::filesystem::canonical(folder).generic_string();
	}

	void write_file(const std::string& path, const std::string& text) {
		std::ofstream file(path, std::ios::binary);
		file << text;
	}

	// A diagnostic as the compiler prints it with --diagnostics=json
	std::string diagnostic_line(const std::string& file, int line, int column, const std::string& message = "Type mismatch") {
		return std::format(R"({{"severity":"error","code":"hemera:E4015","file":"{}","line":{},"column":{},"message":"{}"}})", file, line,
			column, message) + "\n";
	}

	const std::string MAIN_TEXT = "package main\n\nmain :: fn() -> int {\n    return \"\xC3\xA9t\xC3\xA9\"\n}\n";
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

	const hemera::lsp::Documents documents = session.server.documents();
	const hemera::lsp::Document* open = documents.find_path("d:/project/main.hsc");
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

TEST(Server, OpeningAFileChecksItsFolder) {
	const std::string folder = fresh_folder("opening");
	const std::string path = folder + "/main.hsc";
	write_file(path, MAIN_TEXT);
	Session session;
	session.output = diagnostic_line(path, 4, 11);
	session.initialize();
	const std::string uri = hemera::lsp::uri_from_path(path);
	session.notify("textDocument/didOpen", document(uri, MAIN_TEXT, 1));

	const std::vector<Object> published = session.published();
	ASSERT_EQ(1u, session.commands.size());
	ASSERT_EQ(4u, session.commands[0].size());
	EXPECT_EQ((std::vector<std::string>{ "hemera", "--check", "--diagnostics=json" }),
		std::vector<std::string>(session.commands[0].begin(), session.commands[0].begin() + 3));
	EXPECT_EQ(hemera::lsp::path_key(folder), hemera::lsp::path_key(session.commands[0][3]));
	ASSERT_EQ(1u, published.size());
	EXPECT_EQ(uri, published[0].getString("uri"));
	const Array& diagnostics = *published[0].getArray("diagnostics");
	ASSERT_EQ(1u, diagnostics.size());
	const Object& diagnostic = *diagnostics[0].getAsObject();
	EXPECT_EQ(1, diagnostic.getInteger("severity"));
	EXPECT_EQ("hemera:E4015", diagnostic.getString("code"));
	EXPECT_EQ("Type mismatch", diagnostic.getString("message"));
	// "été" is 7 bytes, 5 UTF-16 code units with its quotes
	const Object& range = *diagnostic.getObject("range");
	EXPECT_EQ(3, range.getObject("start")->getInteger("line"));
	EXPECT_EQ(11, range.getObject("start")->getInteger("character"));
	EXPECT_EQ(3, range.getObject("end")->getInteger("line"));
	EXPECT_EQ(16, range.getObject("end")->getInteger("character"));
}

TEST(Server, UnsavedTextIsOverlaid) {
	const std::string folder = fresh_folder("overlaid");
	const std::string path = folder + "/main.hsc";
	write_file(path, MAIN_TEXT);
	Session session;
	session.initialize();
	session.notify("textDocument/didOpen", document(hemera::lsp::uri_from_path(path), "package main\n", 1));
	session.published();

	ASSERT_EQ(1u, session.commands.size());
	const std::vector<std::string>& command = session.commands[0];
	ASSERT_EQ(5u, command.size());
	// --overlay=path=file, where path has no = of its own
	ASSERT_TRUE(command[3].starts_with("--overlay=")) << command[3];
	const std::string overlay = command[3].substr(std::string_view("--overlay=").size());
	const size_t equals = overlay.find('=');
	ASSERT_NE(std::string::npos, equals) << command[3];
	EXPECT_EQ(hemera::lsp::path_key(path), hemera::lsp::path_key(overlay.substr(0, equals)));
	// The buffer's file is gone once the check is done
	EXPECT_FALSE(std::filesystem::exists(overlay.substr(equals + 1)));
}

TEST(Server, FilesWithoutDiagnosticsAreCleared) {
	const std::string folder = fresh_folder("cleared");
	const std::string path = folder + "/main.hsc";
	write_file(path, MAIN_TEXT);
	Session session;
	session.output = diagnostic_line(path, 4, 11);
	session.initialize();
	const std::string uri = hemera::lsp::uri_from_path(path);
	session.notify("textDocument/didOpen", document(uri, MAIN_TEXT, 1));
	session.published();
	session.output = "";
	session.notify("textDocument/didSave", Object{ { "textDocument", Object{ { "uri", uri } } } });

	const std::vector<Object> published = session.published();
	ASSERT_EQ(2u, published.size());
	EXPECT_EQ(uri, published[1].getString("uri"));
	EXPECT_TRUE(published[1].getArray("diagnostics")->empty());
}

TEST(Server, ADiagnosticSeveralTargetsReportIsPublishedOnce) {
	const std::string folder = fresh_folder("targets");
	const std::string path = folder + "/main.hsc";
	write_file(path, MAIN_TEXT);
	Session session;
	session.output = diagnostic_line(path, 4, 11) + diagnostic_line(path, 4, 11) + "not a diagnostic\n";
	session.initialize();
	session.notify("textDocument/didOpen", document(hemera::lsp::uri_from_path(path), MAIN_TEXT, 1));

	const std::vector<Object> published = session.published();
	ASSERT_EQ(1u, published.size());
	EXPECT_EQ(1u, published[0].getArray("diagnostics")->size());
}

TEST(Server, TheRootSettingAppliesInsideTheWorkspace) {
	const std::string folder = fresh_folder("root");
	Session session;
	session.initialize({}, Object{ { "root", "build" } }, Array{ Object{ { "uri", hemera::lsp::uri_from_path(folder) }, { "name", "root" } } });

	EXPECT_EQ(hemera::lsp::path_key(folder + "/build"), hemera::lsp::path_key(session.server.root_for(folder + "/src/kernel/main.hsc")));
	EXPECT_EQ("/elsewhere/lib", session.server.root_for("/elsewhere/lib/lib.hsc"));
}

TEST(Server, ChangingSettingsClearsAndChecksAgain) {
	const std::string folder = fresh_folder("settings");
	std::filesystem::create_directories(folder + "/src");
	const std::string path = folder + "/src/main.hsc";
	write_file(path, MAIN_TEXT);
	Session session;
	// Checked through its own folder, which reports an error the build package doesn't
	session.output = diagnostic_line(path, 4, 11);
	session.initialize({}, {}, Array{ Object{ { "uri", hemera::lsp::uri_from_path(folder) }, { "name", "root" } } });
	const std::string uri = hemera::lsp::uri_from_path(path);
	session.notify("textDocument/didOpen", document(uri, MAIN_TEXT, 1));
	ASSERT_EQ(1u, session.published().size());
	session.output = "";
	session.notify("workspace/didChangeConfiguration", Object{ { "settings", Object{ { "hemera", Object{ { "root", "build" } } } } } });

	const std::vector<Object> published = session.published();
	ASSERT_EQ(2u, published.size());
	EXPECT_EQ(uri, published[1].getString("uri"));
	EXPECT_TRUE(published[1].getArray("diagnostics")->empty());
	ASSERT_EQ(2u, session.commands.size());
	EXPECT_EQ(hemera::lsp::path_key(folder + "/build"), hemera::lsp::path_key(session.commands[1].back()));
}

TEST(Server, ACompilerThatCannotRunIsReportedOnce) {
	const std::string folder = fresh_folder("cannot_run");
	const std::string path = folder + "/main.hsc";
	write_file(path, MAIN_TEXT);
	Session session;
	session.starts = false;
	session.initialize();
	const std::string uri = hemera::lsp::uri_from_path(path);
	session.notify("textDocument/didOpen", document(uri, MAIN_TEXT, 1));
	session.notify("textDocument/didSave", Object{ { "textDocument", Object{ { "uri", uri } } } });
	session.published();

	size_t shown = 0;
	for (const Value& message : session.sent) {
		if (message.getAsObject()->getString("method") == llvm::StringRef("window/showMessage")) {
			++shown;
		}
	}
	EXPECT_EQ(1u, shown);
}

namespace {

	// textDocument/formatting's answer for uri
	Array formatting_edits(Session& session, const std::string& uri) {
		session.request(10, "textDocument/formatting", Object{ { "textDocument", Object{ { "uri", uri } } },
			{ "options", Object{ { "tabSize", 2 }, { "insertSpaces", false } } } });
		const Value* result = session.last().get("result");
		return result != nullptr && result->getAsArray() != nullptr ? *result->getAsArray() : Array{};
	}

	// text with one edit, its range in UTF-8 positions, applied
	std::string applied(const std::string& text, const Object& edit) {
		const auto offset = [&](const Object& position) {
			size_t at = 0;
			const int64_t line = *position.getInteger("line");
			for (int64_t i = 0; i < line; ++i) {
				at = text.find('\n', at) + 1;
			}
			return at + static_cast<size_t>(*position.getInteger("character"));
		};
		const Object& range = *edit.getObject("range");
		const size_t start = offset(*range.getObject("start"));
		const size_t end = offset(*range.getObject("end"));
		return text.substr(0, start) + edit.getString("newText")->str() + text.substr(end);
	}
}

TEST(Server, FormattingAnswersWithTheFormattersLayout) {
	Session session;
	session.initialize(Array{ "utf-8" });
	const std::string uri = "file:///d%3A/project/main.hsc";
	const std::string text = "package main\n\nmain :: fn( ) -> int {\n  return   0\n}\n";
	session.notify("textDocument/didOpen", document(uri, text, 1));

	const Array edits = formatting_edits(session, uri);
	ASSERT_EQ(1u, edits.size());
	EXPECT_EQ("package main\n\nmain :: fn() -> int {\n    return 0\n}\n", applied(text, *edits[0].getAsObject()));
	// Only the lines that changed: the package line is left alone
	EXPECT_EQ(2, edits[0].getAsObject()->getObject("range")->getObject("start")->getInteger("line"));
}

TEST(Server, FormattingKeepsCrLf) {
	Session session;
	session.initialize(Array{ "utf-8" });
	const std::string uri = "file:///d%3A/project/main.hsc";
	const std::string text = "package main\r\n\r\nmain :: fn() -> int {\r\n  return 0\r\n}\r\n";
	session.notify("textDocument/didOpen", document(uri, text, 1));

	const Array edits = formatting_edits(session, uri);
	ASSERT_EQ(1u, edits.size());
	EXPECT_EQ("package main\r\n\r\nmain :: fn() -> int {\r\n    return 0\r\n}\r\n", applied(text, *edits[0].getAsObject()));
}

TEST(Server, FormattingCountsUtf16Units) {
	Session session;
	session.initialize();
	const std::string uri = "file:///d%3A/project/main.hsc";
	// 𝄞 is two UTF-16 units, so the space after the comma goes at character 12, not byte 14
	const std::string text = "package main\n\nx :: f(\"\xF0\x9D\x84\x9E\",1)\n";
	session.notify("textDocument/didOpen", document(uri, text, 1));

	const Array edits = formatting_edits(session, uri);
	ASSERT_EQ(1u, edits.size());
	const Object& start = *edits[0].getAsObject()->getObject("range")->getObject("start");
	EXPECT_EQ(2, start.getInteger("line"));
	EXPECT_EQ(12, start.getInteger("character"));
	EXPECT_EQ(" ", edits[0].getAsObject()->getString("newText"));
}

TEST(Server, FormattingLeavesAFileThatDoesNotParse) {
	Session session;
	session.initialize();
	const std::string uri = "file:///d%3A/project/main.hsc";
	session.notify("textDocument/didOpen", document(uri, "package main\n\nmain :: fn( {\n", 1));

	EXPECT_TRUE(formatting_edits(session, uri).empty());
	EXPECT_EQ(0, session.last_error());
}

TEST(Server, FormattingAFormattedFileChangesNothing) {
	Session session;
	session.initialize();
	const std::string uri = "file:///d%3A/project/main.hsc";
	session.notify("textDocument/didOpen", document(uri, "package main\n\nmain :: fn() -> int {\n    return 0\n}\n", 1));

	EXPECT_TRUE(formatting_edits(session, uri).empty());
}

TEST(TokenEnd, CoversWordsStringsAndSingleCharacters) {
	EXPECT_EQ(12u, hemera::lsp::token_end("abc := value", 7));
	EXPECT_EQ(3u, hemera::lsp::token_end("abc := value", 0));
	// f("a\"b"): the string, its escaped quote included
	EXPECT_EQ(8u, hemera::lsp::token_end("f(\"a\\\"b\")", 2));
	EXPECT_EQ(3u, hemera::lsp::token_end("a := 1", 2));
	EXPECT_EQ(6u, hemera::lsp::token_end("a := 1", 9));
}

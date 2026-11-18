#include <algorithm>
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
		// What the fake compiler writes where --index says, if anything
		std::string index_json;
		bool starts = true;
		Server server{ [this](Value message) {
			std::lock_guard<std::mutex> lock(mutex);
			sent.push_back(std::move(message));
		}, [this](const std::vector<std::string>& arguments) -> std::unique_ptr<Run> {
			std::lock_guard<std::mutex> lock(mutex);
			// The index is written, and its argument left out of what the tests compare
			std::vector<std::string> kept;
			for (const std::string& argument : arguments) {
				if (argument.starts_with("--index=")) {
					std::ofstream index(argument.substr(std::string_view("--index=").size()), std::ios::binary);
					index << index_json;
				}
				else {
					kept.push_back(argument);
				}
			}
			commands.push_back(kept);
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
	std::string diagnostic_line(const std::string& file, int line, int column, const std::string& message = "Type mismatch",
		const std::string& target = "") {
		const std::string found_by = target.empty() ? std::string() : std::format(R"(,"target":"{}")", target);
		return std::format(R"({{"severity":"error","code":"hemera:E4015","file":"{}","line":{},"column":{},"message":"{}"{}}})", file, line,
			column, message, found_by) + "\n";
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
	session.request(2, "textDocument/codeLens");

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

namespace {

	const std::string DECLARATIONS =
		"package main\n"
		"\n"
		"import runtime from \"base:runtime\"\n"
		"\n"
		"/** Adds. */\n"
		"add :: fn(a : int, b : int) -> int {\n"
		"    x := 1\n"
		"    return a + b\n"
		"}\n"
		"\n"
		"Point :: struct {\n"
		"    x : int,\n"
		"    y : int = 2,\n"
		"}\n"
		"\n"
		"Color :: enum #backed_by(u8) {\n"
		"    Red,\n"
		"    Green = 3,\n"
		"}\n"
		"\n"
		"Shape :: union {\n"
		"    Circle(f32),\n"
		"    Square,\n"
		"}\n"
		"\n"
		"LIMIT :: 10\n"
		"Alias :: alias int\n"
		"Distinct :: distinct alias int\n";

	// textDocument/documentSymbol's answer for uri
	Array symbols_of(Session& session, const std::string& uri) {
		session.request(11, "textDocument/documentSymbol", Object{ { "textDocument", Object{ { "uri", uri } } } });
		const Value* result = session.last().get("result");
		return result != nullptr && result->getAsArray() != nullptr ? *result->getAsArray() : Array{};
	}

	// A symbol's name, kind, and its range's first and last lines, as "name kind first-last"
	std::string summary(const Value& symbol) {
		const Object& object = *symbol.getAsObject();
		const Object& range = *object.getObject("range");
		return std::format("{} {} {}-{}", object.getString("name")->str(), *object.getInteger("kind"),
			*range.getObject("start")->getInteger("line"), *range.getObject("end")->getInteger("line"));
	}
}

TEST(Server, DocumentSymbolsListDeclarationsAndTheirMembers) {
	Session session;
	session.initialize();
	const std::string uri = "file:///d%3A/project/main.hsc";
	session.notify("textDocument/didOpen", document(uri, DECLARATIONS, 1));

	const Array symbols = symbols_of(session, uri);
	std::vector<std::string> found;
	for (const Value& symbol : symbols) {
		found.push_back(summary(symbol));
		if (const Array* children = symbol.getAsObject()->getArray("children")) {
			for (const Value& child : *children) {
				found.push_back("  " + summary(child));
			}
		}
	}
	EXPECT_EQ((std::vector<std::string>{
		// The doc comment and the closing brace are in the function's range
		"add 12 4-8",
		"Point 23 10-13",
		"  x 8 11-11",
		"  y 8 12-12",
		"Color 10 15-18",
		"  Red 22 16-16",
		"  Green 22 17-17",
		"Shape 10 20-23",
		"  Circle 22 21-21",
		"  Square 22 22-22",
		"LIMIT 14 25-25",
		"Alias 26 26-26",
		"Distinct 26 27-27",
	}), found);
	const Object& add = *symbols[0].getAsObject();
	EXPECT_EQ("fn", add.getString("detail"));
	const Object& name = *add.getObject("selectionRange");
	EXPECT_EQ(5, name.getObject("start")->getInteger("line"));
	EXPECT_EQ(0, name.getObject("start")->getInteger("character"));
	EXPECT_EQ(3, name.getObject("end")->getInteger("character"));
}

/*
 * A declaration with an error is still in the outline, as are those after it, and one whose statement has an error;
 * a file that doesn't lex keeps the last outline.
 */
TEST(Server, DocumentSymbolsComeFromWhatTheParserRecovered) {
	Session session;
	session.initialize();
	const std::string uri = "file:///d%3A/project/main.hsc";
	session.notify("textDocument/didOpen", document(uri, DECLARATIONS, 1));
	EXPECT_EQ(7u, symbols_of(session, uri).size());
	std::string broken_statement = DECLARATIONS;
	broken_statement.replace(broken_statement.find("x := 1"), 6, "x := (1 +");
	session.notify("textDocument/didChange", Object{
		{ "textDocument", Object{ { "uri", uri }, { "version", 2 } } },
		{ "contentChanges", Array{ Object{ { "text", broken_statement + "broken :: fn( {\n" } } } },
	});
	const Array symbols = symbols_of(session, uri);
	ASSERT_EQ(8u, symbols.size());
	EXPECT_EQ("add", symbols[0].getAsObject()->getString("name")->str());
	EXPECT_EQ("broken", symbols[7].getAsObject()->getString("name")->str());

	session.notify("textDocument/didChange", Object{
		{ "textDocument", Object{ { "uri", uri }, { "version", 3 } } },
		{ "contentChanges", Array{ Object{ { "text", DECLARATIONS + "x :: \"never closed\n" } } } },
	});
	EXPECT_EQ(8u, symbols_of(session, uri).size());
}

namespace {

	// textDocument/foldingRange's answer for uri, each as "start-end kind"
	std::vector<std::string> folds_of(Session& session, const std::string& uri) {
		session.request(12, "textDocument/foldingRange", Object{ { "textDocument", Object{ { "uri", uri } } } });
		std::vector<std::string> found;
		const Value* result = session.last().get("result");
		if (result != nullptr && result->getAsArray() != nullptr) {
			for (const Value& fold : *result->getAsArray()) {
				const Object& object = *fold.getAsObject();
				found.push_back(std::format("{}-{} {}", *object.getInteger("startLine"), *object.getInteger("endLine"),
					object.getString("kind").value_or("code").str()));
			}
		}
		return found;
	}

	const std::string FOLDED =
		"package main\n"                       // 0
		"\n"                                   // 1
		"import runtime from \"base:runtime\"\n" // 2
		"import compiler from \"base:compiler\"\n" // 3
		"\n"                                   // 4
		"/*\n"                                 // 5
		" * A block comment\n"                 // 6
		" */\n"                                // 7
		"// One line\n"                        // 8
		"// and another\n"                     // 9
		"main :: fn() -> int {\n"              // 10
		"    values :: int.[\n"                // 11
		"        1,\n"                         // 12
		"        2,\n"                         // 13
		"    ]\n"                              // 14
		"    return 0 // trailing\n"           // 15
		"}\n"                                  // 16
		"short :: fn() { }\n";                 // 17
}

TEST(Server, FoldingCoversBracketsCommentsAndImports) {
	Session session;
	session.initialize();
	const std::string uri = "file:///d%3A/project/main.hsc";
	session.notify("textDocument/didOpen", document(uri, FOLDED, 1));

	std::vector<std::string> folds = folds_of(session, uri);
	std::sort(folds.begin(), folds.end());
	EXPECT_EQ((std::vector<std::string>{ "10-15 code", "11-13 code", "2-3 imports", "5-7 comment", "8-9 comment" }), folds);
}

TEST(Server, FoldingWorksWhileAFileDoesNotParse) {
	Session session;
	session.initialize();
	const std::string uri = "file:///d%3A/project/main.hsc";
	session.notify("textDocument/didOpen", document(uri, "package main\n\nbroken :: fn( {\n    x\n    y\n}\n", 1));

	EXPECT_EQ((std::vector<std::string>{ "2-4 code" }), folds_of(session, uri));
}

namespace {

	const std::string CALLER = "package main\n\nmain :: fn() -> int {\n    return helper()\n}\n";
	const std::string CALLED = "package main\n\n/** Helps. */\nhelper :: fn() -> int {\n    return 0\n}\n";

	/*
	 * A folder with CALLER in main.hsc and CALLED in helper.hsc, and a session whose fake compiler writes their index:
	 * helper declared at byte 28 of helper.hsc, used at byte 47 of main.hsc
	 */
	struct Indexed {
		std::string folder = fresh_folder("indexed");
		std::string main = folder + "/main.hsc";
		std::string helper = folder + "/helper.hsc";
		Session session;

		Indexed() {
			write_file(main, CALLER);
			write_file(helper, CALLED);
			session.index_json = std::format(
				"{{\"version\":1,\"files\":[\"{}\",\"{}\"],\"declarations\":[\n"
				"{{\"file\":0,\"name\":[28,6],\"span\":[28,62],\"kind\":\"function\",\"type\":\"fn() -> int\",\"brief\":\"Helps.\","
				"\"tags\":[[\"return\",\"\",\"Nothing much.\"]]}}],\n"
				"\"uses\":[\n[1,47,6,0]]}}\n", helper, main);
			session.initialize({}, {}, Array{ Object{ { "uri", hemera::lsp::uri_from_path(folder) }, { "name", "indexed" } } });
		}

		// Opens main.hsc, and waits for its check
		void open_main(const std::string& text = CALLER) {
			session.notify("textDocument/didOpen", document(hemera::lsp::uri_from_path(main), text, 1));
			session.published();
		}

		const Value* ask(int64_t id, const std::string& method, int64_t line, int64_t character) {
			session.request(id, method, Object{ { "textDocument", Object{ { "uri", hemera::lsp::uri_from_path(main) } } },
				{ "position", Object{ { "line", line }, { "character", character } } } });
			return session.last().get("result");
		}
	};

	// A Location's or a range's "line:character-line:character"
	std::string range_text(const Object& range) {
		const Object& start = *range.getObject("start");
		const Object& end = *range.getObject("end");
		return std::format("{}:{}-{}:{}", *start.getInteger("line"), *start.getInteger("character"), *end.getInteger("line"),
			*end.getInteger("character"));
	}
}

TEST(Server, DefinitionLeadsToTheDeclaration) {
	Indexed indexed;
	indexed.open_main();

	const Value* found = indexed.ask(20, "textDocument/definition", 3, 13);
	ASSERT_NE(nullptr, found);
	ASSERT_NE(nullptr, found->getAsObject());
	EXPECT_EQ(hemera::lsp::path_key(indexed.helper), hemera::lsp::path_key(hemera::lsp::path_from_uri(*found->getAsObject()->getString("uri"))));
	EXPECT_EQ("3:0-3:6", range_text(*found->getAsObject()->getObject("range")));
	// Nothing where there's no name
	EXPECT_EQ(Value(nullptr), *indexed.ask(21, "textDocument/definition", 0, 2));
}

// Completion is offered, and names what the package declares, from the index, with its type and doc comment.
TEST(Server, CompletionOffersThePackagesDeclarations) {
	Indexed indexed;
	EXPECT_NE(nullptr, indexed.session.sent.front().getAsObject()->getObject("result")->getObject("capabilities")->getObject("completionProvider"));
	indexed.open_main();

	const Value* found = indexed.ask(23, "textDocument/completion", 3, 13);
	ASSERT_NE(nullptr, found);
	ASSERT_NE(nullptr, found->getAsArray());
	const Object* helper = nullptr;
	for (const Value& item : *found->getAsArray()) {
		if (item.getAsObject()->getString("label") == llvm::StringRef("helper")) {
			helper = item.getAsObject();
		}
	}
	ASSERT_NE(nullptr, helper);
	EXPECT_EQ(3, helper->getInteger("kind"));
	EXPECT_EQ("fn() -> int", helper->getString("detail")->str());
	EXPECT_EQ("Helps.", helper->getObject("documentation")->getString("value")->str());
}

/*
 * A declaration inserted code made is at its #insert, with its name as text: its uses lead to the #insert and to where
 * its name is written, hover shows its name and type, renaming it is refused, the outline lists it, and completion names it.
 */
TEST(Server, InsertedDeclarationsAreFoundAtTheirInsert) {
	const std::string folder = fresh_folder("inserted");
	const std::string main = folder + "/main.hsc";
	const std::string text = "package main\n\n#insert made()\n\nmain :: fn() -> int {\n    return helper()\n}\n";
	write_file(main, text);
	Session session;
	const size_t insert = text.find("#insert");
	const size_t use = text.find("helper()");
	session.index_json = std::format(
		"{{\"version\":1,\"files\":[\"{}\"],\"declarations\":[\n"
		"{{\"file\":0,\"name\":[{},7],\"span\":[{},{}],\"kind\":\"function\",\"text\":\"helper\",\"written\":[0,0,7],\"type\":\"fn() -> int\"}}],\n"
		"\"uses\":[[0,{},6,0]]}}\n", main, insert, insert, insert + 7, use);
	session.initialize({}, {}, Array{ Object{ { "uri", hemera::lsp::uri_from_path(folder) }, { "name", "inserted" } } });
	const std::string uri = hemera::lsp::uri_from_path(main);
	session.notify("textDocument/didOpen", document(uri, text, 1));
	session.published();
	const auto at = [&](int64_t id, const std::string& method, size_t offset, Object more = {}) {
		const size_t line = static_cast<size_t>(std::count(text.begin(), text.begin() + static_cast<std::ptrdiff_t>(offset), '\n'));
		more["textDocument"] = Object{ { "uri", uri } };
		more["position"] = Object{ { "line", static_cast<int64_t>(line) }, { "character", static_cast<int64_t>(offset - text.rfind('\n', offset) - 1) } };
		session.request(id, method, std::move(more));
		return session.last();
	};

	const Object definition = at(50, "textDocument/definition", use + 1);
	ASSERT_NE(nullptr, definition.getArray("result"));
	ASSERT_EQ(2u, definition.getArray("result")->size());
	EXPECT_EQ("2:0-2:7", range_text(*(*definition.getArray("result"))[0].getAsObject()->getObject("range")));
	const Object hover = at(51, "textDocument/hover", use + 1);
	EXPECT_NE(std::string::npos, hover.getObject("result")->getObject("contents")->getString("value")->str().find("helper :: fn() -> int"));
	at(52, "textDocument/prepareRename", use + 1);
	EXPECT_EQ(hemera::lsp::error_codes::REQUEST_FAILED, session.last_error());
	// The #insert itself isn't helper's name
	EXPECT_EQ(Value(nullptr), *at(53, "textDocument/definition", insert + 2).get("result"));

	session.request(54, "textDocument/documentSymbol", Object{ { "textDocument", Object{ { "uri", uri } } } });
	const Array* symbols = session.last().getArray("result");
	ASSERT_NE(nullptr, symbols);
	EXPECT_TRUE(std::any_of(symbols->begin(), symbols->end(), [](const Value& symbol) {
		return symbol.getAsObject()->getString("name") == llvm::StringRef("helper");
	}));
	const Object completion = at(55, "textDocument/completion", use + 2);
	const Array* items = completion.getArray("result");
	ASSERT_NE(nullptr, items);
	EXPECT_TRUE(std::any_of(items->begin(), items->end(), [](const Value& item) {
		return item.getAsObject()->getString("label") == llvm::StringRef("helper");
	}));
}

/*
 * An error in inserted code, written in a quote outside the workspace, shows at the #insert in the workspace that put it
 * there, saying so, linked to where the code is written; and where it's written, linked to the #insert.
 */
TEST(Server, AnErrorInInsertedCodeShowsAtItsInsert) {
	Indexed indexed;
	const std::string quote = "D:/elsewhere/std/quotes.hsc";
	indexed.session.output = std::format(
		R"json({{"severity":"error","code":"hemera:E4015","file":"{}","line":7,"column":8,"message":"Type mismatch; inserted at {}(4,4)","inserted":[{{"file":"{}","line":4,"column":4}}]}})json"
		"\n", quote, indexed.main, indexed.main);
	indexed.open_main();
	const std::vector<Object> published = indexed.session.published();

	const Object* at_insert = nullptr;
	const Object* written = nullptr;
	for (const Object& params : published) {
		const std::string path = hemera::lsp::path_key(hemera::lsp::path_from_uri(*params.getString("uri")));
		if (!params.getArray("diagnostics")->empty()) {
			const Object* diagnostic = params.getArray("diagnostics")->front().getAsObject();
			(path == hemera::lsp::path_key(indexed.main) ? at_insert : written) = diagnostic;
		}
	}
	ASSERT_NE(nullptr, at_insert);
	EXPECT_EQ("In code this #insert puts in: Type mismatch", at_insert->getString("message")->str());
	EXPECT_EQ(3, at_insert->getObject("range")->getObject("start")->getInteger("line"));
	const Array* related = at_insert->getArray("relatedInformation");
	ASSERT_NE(nullptr, related);
	ASSERT_EQ(1u, related->size());
	EXPECT_EQ(hemera::lsp::path_key(quote),
		hemera::lsp::path_key(hemera::lsp::path_from_uri(*(*related)[0].getAsObject()->getObject("location")->getString("uri"))));
	ASSERT_NE(nullptr, written);
	ASSERT_NE(nullptr, written->getArray("relatedInformation"));
	EXPECT_EQ("Inserted here", (*written->getArray("relatedInformation"))[0].getAsObject()->getString("message")->str());
}

TEST(Server, HoverShowsTheSignatureAndDocumentation) {
	Indexed indexed;
	indexed.open_main();

	const Value* found = indexed.ask(22, "textDocument/hover", 3, 11);
	ASSERT_NE(nullptr, found);
	ASSERT_NE(nullptr, found->getAsObject());
	const std::string markdown = found->getAsObject()->getObject("contents")->getString("value")->str();
	EXPECT_TRUE(markdown.starts_with("```hemera\nhelper :: fn() -> int\n```")) << markdown;
	EXPECT_NE(std::string::npos, markdown.find("Helps.")) << markdown;
	EXPECT_NE(std::string::npos, markdown.find("*@return* — Nothing much.")) << markdown;
	EXPECT_EQ("3:11-3:17", range_text(*found->getAsObject()->getObject("range")));
}

/*
 * Semantic tokens: the legend in the capabilities, a document's tokens from the check's index, and, for a client that
 * takes it, a refresh after each check.
 */
TEST(Server, SemanticTokensComeFromTheIndex) {
	Indexed indexed;
	const Object* provider = indexed.session.sent.front().getAsObject()->getObject("result")->getObject("capabilities")
		->getObject("semanticTokensProvider");
	ASSERT_NE(nullptr, provider);
	EXPECT_NE(nullptr, provider->getObject("legend")->getArray("tokenTypes"));
	indexed.open_main();

	indexed.session.request(25, "textDocument/semanticTokens/full",
		Object{ { "textDocument", Object{ { "uri", hemera::lsp::uri_from_path(indexed.main) } } } });
	const Value* found = indexed.session.last().get("result");
	ASSERT_NE(nullptr, found);
	// helper, used on line 3 at 11, a function (8), with no modifiers
	EXPECT_EQ(Value(Array{ 3, 11, 6, 8, 0 }), *found->getAsObject()->get("data"));
	// The client said nothing of refreshing, so it isn't sent
	for (const Value& message : indexed.session.sent) {
		EXPECT_NE(llvm::StringRef("workspace/semanticTokens/refresh"), message.getAsObject()->getString("method").value_or(""));
	}

	const std::string folder = fresh_folder("refreshed");
	write_file(folder + "/main.hsc", CALLER);
	Session session;
	session.index_json = "{\"version\":1,\"files\":[],\"declarations\":[],\"uses\":[]}";
	session.request(1, "initialize", Object{ { "capabilities", Object{ { "workspace", Object{
		{ "semanticTokens", Object{ { "refreshSupport", true } } } } } } },
		{ "workspaceFolders", Array{ Object{ { "uri", hemera::lsp::uri_from_path(folder) }, { "name", "refreshed" } } } } });
	session.notify("initialized");
	session.notify("textDocument/didOpen", document(hemera::lsp::uri_from_path(folder + "/main.hsc"), CALLER, 1));
	session.published();
	size_t refreshes = 0;
	for (const Value& message : session.sent) {
		const Object* object = message.getAsObject();
		if (object->getString("method") == llvm::StringRef("workspace/semanticTokens/refresh")) {
			EXPECT_NE(nullptr, object->get("id")) << "a request, which the client answers";
			++refreshes;
		}
	}
	EXPECT_EQ(1u, refreshes);
	// The client's answer is taken without a word
	const size_t sent = session.sent.size();
	session.server.handle(Object{ { "jsonrpc", "2.0" }, { "id", "refresh-1" }, { "result", nullptr } });
	EXPECT_EQ(sent, session.sent.size());
}

/*
 * Highlights, signature help, workspace symbols and inlay hints are offered, and answered from the check's index:
 * a name's places in the file, a call's signature, and a search for a declaration.
 */
TEST(Server, AnswersEditorFeaturesFromTheIndex) {
	Indexed indexed;
	const Object& capabilities = *indexed.session.sent.front().getAsObject()->getObject("result")->getObject("capabilities");
	for (const char* provider : { "documentHighlightProvider", "workspaceSymbolProvider", "inlayHintProvider" }) {
		EXPECT_EQ(Value(true), *capabilities.get(provider)) << provider;
	}
	EXPECT_NE(nullptr, capabilities.getObject("signatureHelpProvider"));
	indexed.open_main();

	// helper's one use in main.hsc, which reads it
	const Value* found = indexed.ask(26, "textDocument/documentHighlight", 3, 13);
	ASSERT_NE(nullptr, found);
	ASSERT_NE(nullptr, found->getAsArray());
	ASSERT_EQ(1u, found->getAsArray()->size());
	const Object& highlight = *(*found->getAsArray())[0].getAsObject();
	EXPECT_EQ("3:11-3:17", range_text(*highlight.getObject("range")));
	EXPECT_EQ(2, highlight.getInteger("kind"));

	// Inside helper's ( ), its signature
	const Value* help = indexed.ask(27, "textDocument/signatureHelp", 3, 18);
	ASSERT_NE(nullptr, help);
	ASSERT_NE(nullptr, help->getAsObject());
	EXPECT_EQ("helper() -> int", (*help->getAsObject()->getArray("signatures"))[0].getAsObject()->getString("label")->str());

	indexed.session.request(28, "workspace/symbol", Object{ { "query", "hel" } });
	const Value* symbols = indexed.session.last().get("result");
	ASSERT_NE(nullptr, symbols);
	ASSERT_EQ(1u, symbols->getAsArray()->size());
	EXPECT_EQ("helper", (*symbols->getAsArray())[0].getAsObject()->getString("name")->str());
}

TEST(Server, AnswersMoveWithEditsSinceTheCheck) {
	Indexed indexed;
	indexed.open_main();
	// Two lines added above the call, not saved, so the index's offsets are from before
	indexed.session.notify("textDocument/didChange", Object{
		{ "textDocument", Object{ { "uri", hemera::lsp::uri_from_path(indexed.main) }, { "version", 2 } } },
		{ "contentChanges", Array{ Object{ { "text", "package main\n\n// a\n// b\nmain :: fn() -> int {\n    return helper()\n}\n" } } } },
	});

	const Value* found = indexed.ask(23, "textDocument/hover", 5, 12);
	ASSERT_NE(nullptr, found);
	ASSERT_NE(nullptr, found->getAsObject());
	EXPECT_EQ("5:11-5:17", range_text(*found->getAsObject()->getObject("range")));
	// What's in the change isn't known until the next check
	EXPECT_EQ(Value(nullptr), *indexed.ask(24, "textDocument/hover", 2, 1));
}

TEST(Server, ReferencesListEveryUse) {
	Indexed indexed;
	indexed.open_main();
	const auto references = [&](bool with_declaration) {
		indexed.session.request(25, "textDocument/references", Object{
			{ "textDocument", Object{ { "uri", hemera::lsp::uri_from_path(indexed.main) } } },
			{ "position", Object{ { "line", 3 }, { "character", 13 } } },
			{ "context", Object{ { "includeDeclaration", with_declaration } } } });
		std::vector<std::string> found;
		for (const Value& location : *indexed.session.last().getArray("result")) {
			const Object& object = *location.getAsObject();
			found.push_back(std::filesystem::path(hemera::lsp::path_from_uri(*object.getString("uri"))).filename().string() + " "
				+ range_text(*object.getObject("range")));
		}
		return found;
	};

	EXPECT_EQ((std::vector<std::string>{ "helper.hsc 3:0-3:6", "main.hsc 3:11-3:17" }), references(true));
	EXPECT_EQ((std::vector<std::string>{ "main.hsc 3:11-3:17" }), references(false));
}

TEST(Server, RenameChangesEveryPlaceANameIsUsed) {
	Indexed indexed;
	indexed.open_main();
	const Object at{ { "textDocument", Object{ { "uri", hemera::lsp::uri_from_path(indexed.main) } } },
		{ "position", Object{ { "line", 3 }, { "character", 13 } } } };

	indexed.session.request(26, "textDocument/prepareRename", at);
	ASSERT_EQ(0, indexed.session.last_error());
	const Object& prepared = *indexed.session.last().getObject("result");
	EXPECT_EQ("helper", prepared.getString("placeholder"));
	EXPECT_EQ("3:11-3:17", range_text(*prepared.getObject("range")));

	Object renaming = at;
	renaming["newName"] = "assist";
	indexed.session.request(27, "textDocument/rename", renaming);
	ASSERT_EQ(0, indexed.session.last_error());
	const Object& changes = *indexed.session.last().getObject("result")->getObject("changes");
	std::vector<std::string> found;
	for (const auto& [uri, edits] : changes) {
		for (const Value& edit : *edits.getAsArray()) {
			found.push_back(std::filesystem::path(hemera::lsp::path_from_uri(uri.str())).filename().string() + " "
				+ range_text(*edit.getAsObject()->getObject("range")) + " " + edit.getAsObject()->getString("newText")->str());
		}
	}
	std::sort(found.begin(), found.end());
	EXPECT_EQ((std::vector<std::string>{ "helper.hsc 3:0-3:6 assist", "main.hsc 3:11-3:17 assist" }), found);
}

TEST(Server, RenameIsRefusedWithAReason) {
	Indexed indexed;
	indexed.open_main();
	Object renaming{ { "textDocument", Object{ { "uri", hemera::lsp::uri_from_path(indexed.main) } } },
		{ "position", Object{ { "line", 3 }, { "character", 13 } } }, { "newName", "2fast" } };

	// Not a name
	indexed.session.request(28, "textDocument/rename", renaming);
	EXPECT_EQ(hemera::lsp::error_codes::REQUEST_FAILED, indexed.session.last_error());
	// A file it's named in has changed since the check
	indexed.session.notify("textDocument/didChange", Object{
		{ "textDocument", Object{ { "uri", hemera::lsp::uri_from_path(indexed.main) }, { "version", 2 } } },
		{ "contentChanges", Array{ Object{ { "text", CALLER + "// more\n" } } } },
	});
	renaming["newName"] = "assist";
	indexed.session.request(29, "textDocument/rename", renaming);
	EXPECT_EQ(hemera::lsp::error_codes::REQUEST_FAILED, indexed.session.last_error());
	const std::string message = indexed.session.last().getObject("error")->getString("message")->str();
	EXPECT_NE(std::string::npos, message.find("has changed since it was checked")) << message;
}

namespace {
	// The last diagnostics published for path: how many there are, or -1 for none published
	int last_published(const std::vector<Object>& published, const std::string& path) {
		int count = -1;
		for (const Object& params : published) {
			if (hemera::lsp::path_key(hemera::lsp::path_from_uri(*params.getString("uri"))) == hemera::lsp::path_key(path)) {
				count = static_cast<int>(params.getArray("diagnostics")->size());
			}
		}
		return count;
	}

	// Whether a command checked only some targets, and which
	std::string targets_of(const std::vector<std::string>& command) {
		auto found = std::find_if(command.begin(), command.end(), [](const std::string& argument) { return argument.starts_with("--targets="); });
		return found != command.end() ? found->substr(std::string_view("--targets=").size()) : std::string();
	}
}

/*
 * A save checks just the targets that read its file, and keeps what the others found: a target's diagnostics are
 * replaced only by a check of it.
 */
TEST(Server, ASaveChecksOnlyTheTargetsThatReadItsFile) {
	Indexed indexed;
	// A build package's index: main.hsc is read by target a, helper.hsc by b
	indexed.session.index_json.insert(indexed.session.index_json.rfind('}'), ",\"targets\":[\"a\",\"b\"],\"readers\":[[1],[0]]");
	// The first check finds an error in each file, each by its own target
	indexed.session.output = diagnostic_line(indexed.main, 4, 11, "Type mismatch", "a") + diagnostic_line(indexed.helper, 4, 11, "Type mismatch", "b");
	indexed.open_main();
	ASSERT_EQ(2u, indexed.session.published().size());
	ASSERT_EQ(1u, indexed.session.commands.size());
	EXPECT_EQ("", targets_of(indexed.session.commands[0]));

	// Both fixed, but only a is checked: main.hsc's is cleared, helper.hsc's, b's, stays
	indexed.session.output = "";
	indexed.session.notify("textDocument/didSave", Object{ { "textDocument", Object{ { "uri", hemera::lsp::uri_from_path(indexed.main) } } } });
	const std::vector<Object> published = indexed.session.published();

	ASSERT_EQ(2u, indexed.session.commands.size());
	EXPECT_EQ("a", targets_of(indexed.session.commands[1]));
	EXPECT_EQ(0, last_published(published, indexed.main));
	EXPECT_EQ(1, last_published(published, indexed.helper));

	// Check Everything: every target, which finds helper.hsc's fixed too
	indexed.session.request(40, "workspace/executeCommand", Object{ { "command", "hemera.checkEverything" } });
	EXPECT_EQ(0, indexed.session.last_error());
	const std::vector<Object> after = indexed.session.published();
	ASSERT_EQ(3u, indexed.session.commands.size());
	EXPECT_EQ("", targets_of(indexed.session.commands[2]));
	EXPECT_EQ(0, last_published(after, indexed.helper));
}

/*
 * A check whose build stopped at errors, before its targets, as one in a package the build loads makes it, shows them,
 * and leaves the index as it was, so names still lead where they did.
 */
TEST(Server, ACheckThatCheckedNoTargetsKeepsTheIndex) {
	Indexed indexed;
	indexed.session.index_json.insert(indexed.session.index_json.rfind('}'), ",\"targets\":[\"a\",\"b\"],\"readers\":[[1],[0]]");
	indexed.open_main();
	ASSERT_NE(nullptr, indexed.ask(20, "textDocument/definition", 3, 13)->getAsObject());

	// The build's own error, and an index of the build's names alone: none of its targets read anything
	indexed.session.output = diagnostic_line(indexed.main, 4, 11);
	indexed.session.index_json = "{\"version\":1,\"files\":[],\"declarations\":[],\"uses\":[]}\n";
	indexed.session.notify("textDocument/didSave", Object{ { "textDocument", Object{ { "uri", hemera::lsp::uri_from_path(indexed.main) } } } });
	const std::vector<Object> published = indexed.session.published();

	ASSERT_EQ(2u, indexed.session.commands.size());
	EXPECT_EQ("a", targets_of(indexed.session.commands[1]));
	EXPECT_EQ(1, last_published(published, indexed.main));
	const Value* found = indexed.ask(21, "textDocument/definition", 3, 13);
	ASSERT_NE(nullptr, found->getAsObject());
	EXPECT_EQ(hemera::lsp::path_key(indexed.helper), hemera::lsp::path_key(hemera::lsp::path_from_uri(*found->getAsObject()->getString("uri"))));
}

/*
 * An open file that none of the build's targets read, like one only another architecture's targets import, says so,
 * on its package statement's line, until a check finds a target that reads it.
 */
TEST(Server, AFileNoTargetReadsSaysSo) {
	Indexed indexed;
	indexed.session.index_json.insert(indexed.session.index_json.rfind('}'), ",\"targets\":[\"a\",\"b\"],\"readers\":[[1],[0]]");
	const std::string other = indexed.folder + "/other.hsc";
	write_file(other, "// Another architecture's\npackage main\n");
	indexed.session.notify("textDocument/didOpen", document(hemera::lsp::uri_from_path(other), "// Another architecture's\npackage main\n", 1));
	std::vector<Object> published = indexed.session.published();
	ASSERT_EQ(1, last_published(published, other));
	const Object* notice = nullptr;
	for (const Object& params : published) {
		if (hemera::lsp::path_key(hemera::lsp::path_from_uri(*params.getString("uri"))) == hemera::lsp::path_key(other)) {
			notice = params.getArray("diagnostics")->front().getAsObject();
		}
	}
	ASSERT_NE(nullptr, notice);
	EXPECT_EQ(3, notice->getInteger("severity"));
	EXPECT_EQ(1, notice->getObject("range")->getObject("start")->getInteger("line"));
	// Not a file a target reads
	EXPECT_LE(last_published(published, indexed.main), 0);

	// Read by a target now: cleared
	indexed.session.index_json = std::format(
		"{{\"version\":1,\"files\":[\"{}\",\"{}\",\"{}\"],\"declarations\":[],\"uses\":[],\"targets\":[\"a\"],\"readers\":[[0],[0],[0]]}}\n",
		indexed.helper, indexed.main, other);
	indexed.session.request(41, "workspace/executeCommand", Object{ { "command", "hemera.checkEverything" } });
	EXPECT_EQ(0, last_published(indexed.session.published(), other));
}

// A file no target read before, like a new one, is checked as the other files in its folder are.
TEST(Server, ANewFileIsCheckedAsItsFoldersTargets) {
	Indexed indexed;
	indexed.session.index_json.insert(indexed.session.index_json.rfind('}'), ",\"targets\":[\"a\",\"b\"],\"readers\":[[1],[0]]");
	indexed.open_main();
	const std::string added = indexed.folder + "/added.hsc";
	write_file(added, "package main\n");
	indexed.session.notify("textDocument/didOpen", document(hemera::lsp::uri_from_path(added), "package main\n", 1));
	indexed.session.published();

	ASSERT_EQ(2u, indexed.session.commands.size());
	EXPECT_EQ("a,b", targets_of(indexed.session.commands[1]));
}

// A check of some targets merged into the index keeps what the targets not checked found, and drops what's gone.
TEST(Index, MergingKeepsWhatOtherTargetsFound) {
	using hemera::lsp::IndexedDeclaration;
	using hemera::lsp::IndexedUse;
	using hemera::lsp::LoadedIndex;
	const auto declared = [](const std::string& file, uint32_t offset) {
		IndexedDeclaration declaration;
		declaration.file = file;
		declaration.name_offset = offset;
		declaration.name_length = 4;
		declaration.start = offset;
		declaration.end = offset + 10;
		declaration.kind = "function";
		return declaration;
	};
	// a reads a.hsc and shared.hsc, b reads b.hsc and shared.hsc; each uses shared.hsc's declaration
	LoadedIndex old;
	old.declarations = { declared("D:/p/shared.hsc", 0), declared("D:/p/a.hsc", 0), declared("D:/p/b.hsc", 0) };
	for (const std::string file : { "D:/p/shared.hsc", "D:/p/a.hsc", "D:/p/b.hsc" }) {
		old.paths[hemera::lsp::path_key(file)] = file;
	}
	old.uses[hemera::lsp::path_key("D:/p/a.hsc")] = { IndexedUse{ 20, 4, 0 }, IndexedUse{ 30, 4, 1 } };
	old.uses[hemera::lsp::path_key("D:/p/b.hsc")] = { IndexedUse{ 20, 4, 0 } };
	old.uses[hemera::lsp::path_key("D:/p/shared.hsc")] = { IndexedUse{ 40, 4, 2 } };
	old.readers[hemera::lsp::path_key("D:/p/a.hsc")] = { "a" };
	old.readers[hemera::lsp::path_key("D:/p/b.hsc")] = { "b" };
	old.readers[hemera::lsp::path_key("D:/p/shared.hsc")] = { "a", "b" };

	// a checked again after a.hsc changed: its declaration moved, and it no longer uses itself
	LoadedIndex fresh;
	fresh.declarations = { declared("D:/p/shared.hsc", 0), declared("D:/p/a.hsc", 8) };
	fresh.paths = { { hemera::lsp::path_key("D:/p/shared.hsc"), "D:/p/shared.hsc" }, { hemera::lsp::path_key("D:/p/a.hsc"), "D:/p/a.hsc" } };
	fresh.uses[hemera::lsp::path_key("D:/p/a.hsc")] = { IndexedUse{ 24, 4, 0 } };
	fresh.readers[hemera::lsp::path_key("D:/p/a.hsc")] = { "a" };
	fresh.readers[hemera::lsp::path_key("D:/p/shared.hsc")] = { "a" };

	const LoadedIndex merged = hemera::lsp::merged_index(old, fresh, { "a" });
	// a.hsc is fresh's: one use, of shared's declaration
	const auto& a_uses = merged.uses.at(hemera::lsp::path_key("D:/p/a.hsc"));
	ASSERT_EQ(1u, a_uses.size());
	EXPECT_EQ(24u, a_uses[0].offset);
	EXPECT_EQ("D:/p/shared.hsc", merged.declarations[a_uses[0].declaration].file);
	// b.hsc, which only b read, is old's, its use renumbered to the same declaration
	const auto& b_uses = merged.uses.at(hemera::lsp::path_key("D:/p/b.hsc"));
	ASSERT_EQ(1u, b_uses.size());
	EXPECT_EQ(a_uses[0].declaration, b_uses[0].declaration);
	// shared.hsc, which b read too, keeps old's use of b's declaration
	const auto& shared_uses = merged.uses.at(hemera::lsp::path_key("D:/p/shared.hsc"));
	ASSERT_EQ(1u, shared_uses.size());
	EXPECT_EQ("D:/p/b.hsc", merged.declarations[shared_uses[0].declaration].file);
	// a.hsc's old declaration is gone, its new one there
	EXPECT_EQ(1u, merged.declared.at(hemera::lsp::path_key("D:/p/a.hsc")).size());
	EXPECT_EQ(8u, merged.declarations[merged.declared.at(hemera::lsp::path_key("D:/p/a.hsc"))[0]].name_offset);
	EXPECT_EQ((std::vector<std::string>{ "b", "a" }), merged.readers.at(hemera::lsp::path_key("D:/p/shared.hsc")));
}

// What a declaration kept from the old index is in, and of, is renumbered with it; an import is kept with its file.
TEST(Index, MergingRenumbersWhatDeclarationsName) {
	using hemera::lsp::IndexedDeclaration;
	using hemera::lsp::LoadedIndex;
	const auto declared = [](const std::string& file, uint32_t offset, const std::string& kind) {
		IndexedDeclaration declaration;
		declaration.file = file;
		declaration.name_offset = offset;
		declaration.name_length = 1;
		declaration.start = offset;
		declaration.end = offset + 1;
		declaration.kind = kind;
		return declaration;
	};
	// b.hsc, which only b read, has a type, its field, and a local of the type
	LoadedIndex old;
	old.declarations = { declared("D:/p/a.hsc", 0, "function"), declared("D:/p/b.hsc", 0, "type"),
		declared("D:/p/b.hsc", 10, "field"), declared("D:/p/b.hsc", 20, "local") };
	old.declarations[2].in = 1;
	old.declarations[3].of = 1;
	for (const std::string file : { "D:/p/a.hsc", "D:/p/b.hsc" }) {
		old.paths[hemera::lsp::path_key(file)] = file;
	}
	old.readers[hemera::lsp::path_key("D:/p/a.hsc")] = { "a" };
	old.readers[hemera::lsp::path_key("D:/p/b.hsc")] = { "b" };
	old.imports[hemera::lsp::path_key("D:/p/b.hsc")] = { hemera::lsp::IndexedImport{ 30, 1, "D:/q" } };

	// a checked again, with three declarations now, so b.hsc's come after them
	LoadedIndex fresh;
	fresh.declarations = { declared("D:/p/a.hsc", 0, "function"), declared("D:/p/a.hsc", 5, "constant"), declared("D:/p/a.hsc", 9, "constant") };
	fresh.paths[hemera::lsp::path_key("D:/p/a.hsc")] = "D:/p/a.hsc";
	fresh.readers[hemera::lsp::path_key("D:/p/a.hsc")] = { "a" };

	const LoadedIndex merged = hemera::lsp::merged_index(old, fresh, { "a" });
	const std::vector<size_t>& in_b = merged.declared.at(hemera::lsp::path_key("D:/p/b.hsc"));
	ASSERT_EQ(3u, in_b.size());
	const IndexedDeclaration& field = merged.declarations[in_b[1]];
	const IndexedDeclaration& local = merged.declarations[in_b[2]];
	ASSERT_TRUE(field.in.has_value());
	EXPECT_EQ(in_b[0], *field.in);
	ASSERT_TRUE(local.of.has_value());
	EXPECT_EQ(in_b[0], *local.of);
	ASSERT_EQ(1u, merged.imports.at(hemera::lsp::path_key("D:/p/b.hsc")).size());
	EXPECT_EQ("D:/q", merged.imports.at(hemera::lsp::path_key("D:/p/b.hsc"))[0].folder);
}

TEST(TokenEnd, CoversWordsStringsAndSingleCharacters) {
	EXPECT_EQ(12u, hemera::lsp::token_end("abc := value", 7));
	EXPECT_EQ(3u, hemera::lsp::token_end("abc := value", 0));
	// f("a\"b"): the string, its escaped quote included
	EXPECT_EQ(8u, hemera::lsp::token_end("f(\"a\\\"b\")", 2));
	EXPECT_EQ(3u, hemera::lsp::token_end("a := 1", 2));
	EXPECT_EQ(6u, hemera::lsp::token_end("a := 1", 9));
}

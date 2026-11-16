#include <cstdio>
#include <iostream>
#include <mutex>
#include <string>

#include "protocol.h"
#include "server.h"

#include "llvm/Support/JSON.h"
#include "llvm/Support/raw_ostream.h"

#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

/*
 * hemera-lsp: the Hemera language server (docs/editor.md). It speaks the Language Server Protocol over standard
 * input and output, as an editor starts it, and stops when the client sends exit, or when standard input ends.
 *
 * Exit status: 0 after shutdown and exit, as the protocol has it; 1 otherwise.
 */
int main() {
#ifdef _WIN32
	// Bytes as they are both ways, so \r\n in the headers and in the text isn't changed
	_setmode(_fileno(stdin), _O_BINARY);
	_setmode(_fileno(stdout), _O_BINARY);
#endif
	std::mutex sending;
	hemera::lsp::Server server([&](llvm::json::Value message) {
		std::string body;
		llvm::raw_string_ostream out(body);
		out << message;
		out.flush();
		const std::string framed = hemera::lsp::frame(body);
		std::lock_guard<std::mutex> lock(sending);
		std::fwrite(framed.data(), 1, framed.size(), stdout);
		std::fflush(stdout);
	});
	for (;;) {
		const std::optional<std::string> body = hemera::lsp::read_message(std::cin);
		if (!body.has_value()) {
			return server.exit_code();
		}
		llvm::Expected<llvm::json::Value> message = llvm::json::parse(*body);
		if (!message) {
			server.malformed(llvm::toString(message.takeError()));
			continue;
		}
		if (!server.handle(*message)) {
			return server.exit_code();
		}
	}
}

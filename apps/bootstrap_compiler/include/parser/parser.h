#pragma once

#include "lexer/token.h"

namespace hemera::parser {
	void next();
	void error();
	void accept();
	void expect();
}

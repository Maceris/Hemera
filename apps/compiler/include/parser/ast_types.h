#pragma once

#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

#include <cstdint>

#include "front_end/type.h"
#include "lexer/token.h"
#include "memory/allocator.h"

namespace hemera::ast {
	enum class NodeType {
		ANNOTATION,
		ARRAY_DIMENSION,
		ARRAY_LITERAL,
		BINARY_OPERATOR,
		BLOCK,
		BREAK,
		CAST,
		COLON,
		CONTINUE,
		DEFER,
		DEFINITION,
		// A generic parameter the generic works out from the others, like E = element_of(C): the
		// name is its token, and its child the expression (docs/types.md, Derived Parameters)
		DERIVED_PARAMETER,
		DIRECTIVE,
		DOT_ACCESS,
		ELLIIPSIS,
		ELSE,
		ENUM,
		ENUM_SHORTHAND,
		FILE,
		FOR_LOOP,
		FUNCTION,
		GENERIC_TAG,
		IDENTIFIER,
		IF,
		IN,
		IMPORT,
		KEYWORD_ALIAS,
		KEYWORD_ALL,
		KEYWORD_AS,
		KEYWORD_DISTINCT,
		KEYWORD_FROM,
		KEYWORD_IS_NONE,
		KEYWORD_IS_SOME,
		KEYWORD_OR_BREAK,
		KEYWORD_OR_CONTINUE,
		KEYWORD_OR_ELSE,
		KEYWORD_OR_RETURN,
		LIST,
		LITERAL,
		LOOP,
		MATCH,
		MATCH_CASE,
		MUTABLE,
		PACKAGE,
		PAREN_GROUP,
		PIPE_REORDER_IDENTIFIER,
		PUSH_CONTEXT,
		RANGE_ARRAY,
		RETURN,
		STRUCT,
		STRUCT_LITERAL,
		SWITCH,
		SWITCH_CASE,
		SWITCH_ENTRY,
		TYPE,
		UNARY_OPERATOR,
		UNDERSCORE,
		UNINITIALIZED,
		UNION,
		USING,
		VOID,
		// A generic's where clause: its constraint expression (docs/types.md, Constraints)
		WHERE_CLAUSE,
		WHILE_CLAUSE,
		WITH_CLAUSE,
	};

	using offset = int64_t;

	struct Node {
		Token value;
		Node* parent;
		MyVector<Node*> children;
		TypeInfo* type;
		NodeType node_type;
		const char padding[4] = { 0 };

		Node(NodeType type, Token value);
		Node(const Node&) = delete;
		Node(Node&&) = delete;
		Node& operator=(const Node&) = delete;
		Node& operator=(Node&&) = delete;
		~Node();
	};

	std::string_view name_of(NodeType type);

	/// <summary>
	/// The bytes a string literal stands for: a quoted string's text with its escapes worked out, or a
	/// multiline string's lines, joined by newlines.
	/// </summary>
	std::string string_value(const Node* literal);

	/// <summary>
	/// The tree under node, one node to a line, for debugging and tests.
	/// </summary>
	std::string dump(const Node* node);

	/// <summary>
	/// The trees #code quotes, by their #code nodes: kept apart from the #code node, whose children are only
	/// the expressions spliced into it, so passes over a body see the quote as those expressions and never
	/// its tree (docs/compilation.md, Code Values). Each #insert in a tree is left with no children; they're
	/// filled in, in order, when the quote is evaluated. A program has one, which lasts as long as its trees.
	/// </summary>
	class QuoteTable {
	public:
		/// <summary>
		/// The tree a #code node quotes, and the file it's written in.
		/// </summary>
		struct Quoted {
			const Node* tree = nullptr;
			std::string file;
			// A macro's argument, the caller's code, rather than code the macro wrote
			bool from_caller = false;
		};

		void set(const Node* quote, const Node* tree, std::string_view file, bool from_caller = false);
		/// <summary>
		/// The tree a #code node quotes, or null.
		/// </summary>
		const Node* get(const Node* quote) const;
		/// <summary>
		/// The file a #code node's tree is written in, or empty.
		/// </summary>
		std::string file_of(const Node* quote) const;
		/// <summary>
		/// Whether a #code node quotes a macro's argument, the caller's code.
		/// </summary>
		bool from_caller(const Node* quote) const;

	private:
		mutable std::mutex mutex;
		std::unordered_map<const Node*, Quoted> trees;
	};

	/// <summary>
	/// Where an #insert put code: the #insert's file, line and column (docs/compilation.md, Code Values).
	/// </summary>
	struct InsertionSite {
		std::string file;
		uint32_t line = 0;
		uint16_t column = 0;
	};

	/// <summary>
	/// Where a node made while compiling comes from: the file its code is written in, a quote's, and each
	/// #insert that put it where it is, the first first. Errors in it are reported there.
	/// </summary>
	struct Origin {
		std::string file;
		std::vector<InsertionSite> inserted;
		/*
		 * Hygiene (docs/compilation.md, Macros): code a macro wrote has its expansion's mark, so its names see
		 * only what that expansion declares, then what its file sees; 0 for code written where it is. Code
		 * passed to a macro is from_caller until it's put back where the caller wrote it.
		 */
		uint32_t mark = 0;
		bool from_caller = false;
	};

	/// <summary>
	/// Nodes made while compiling rather than parsed, like the copies compile-time code's quotes make. A
	/// program has one, which frees them with it.
	/// </summary>
	class NodeStore {
	public:
		/// <summary>
		/// A new node, which lasts as long as the store. Called with hold's lock held.
		/// </summary>
		Node* make(NodeType type, Token value);

		/// <summary>
		/// The store's lock, held while making nodes.
		/// </summary>
		std::unique_lock<std::mutex> hold();

		/// <summary>
		/// Where a node comes from, for one made here, or one made into it in place; null for one parsed.
		/// </summary>
		void set_origin(const Node* node, std::shared_ptr<const Origin> origin);
		std::shared_ptr<const Origin> origin(const Node* node) const;
		/// <summary>
		/// A node's hygiene mark, 0 for code written where it is.
		/// </summary>
		uint32_t mark_of(const Node* node) const;
		/// <summary>
		/// A mark for one macro expansion, never 0.
		/// </summary>
		uint32_t new_mark();

	private:
		std::mutex mutex;
		std::vector<std::unique_ptr<Node>> nodes;
		mutable std::mutex origins_mutex;
		std::unordered_map<const Node*, std::shared_ptr<const Origin>> origins;
		std::atomic<uint32_t> marks{ 0 };
	};

}

#include <algorithm>
#include <format>
#include <functional>
#include <map>
#include <set>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "error/reporting.h"
#include "front_end/ownership.h"
#include "front_end/walk.h"

/*
 * docs/memory.md, Owned Types. A value of an #owned type has one owner at a time: the local or parameter
 * holding it. Assigning it, passing it by value, returning it or storing it moves it, and the owner can't
 * be used again until it's given a new value. On every path out of its scope, each owner has been moved or
 * released: given to a function that takes it, maybe in a defer, or marked #release. Nothing is ever done
 * that isn't written: this only reports what's missing.
 *
 * It walks a body as the bounds prover does (bounds.cpp), keeping each owner's state along each path, and
 * joining paths where they meet: an owner moved on one and not the other is reported there.
 */

namespace hemera {

	namespace {

		bool is_text(InternedString value, std::string_view text) {
			return value != nullptr && std::string_view(*value) == text;
		}

		std::string text_of(InternedString value) {
			return value != nullptr ? std::string(std::string_view(*value)) : std::string("_");
		}

		bool is_assign(const ast::Node* node) {
			return TokenType::OPERATOR_ASSIGN == node->value.type;
		}

		bool is_postfix_marker(const ast::Node* node) {
			return ast::NodeType::DOT_ACCESS == node->node_type || ast::NodeType::PAREN_GROUP == node->node_type
				|| ast::NodeType::ARRAY_DIMENSION == node->node_type
				|| (ast::NodeType::UNARY_OPERATOR == node->node_type && TokenType::OPERATOR_DEREFERENCE == node->value.type);
		}

		bool has_directive(const ast::Node* node, std::string_view name) {
			for (const ast::Node* child : node->children) {
				if (ast::NodeType::DIRECTIVE == child->node_type && is_text(child->value.value, name)) {
					return true;
				}
			}
			return false;
		}

		enum class Held : uint8_t {
			// Declared without a value, or emptied by compiler.take: owns nothing
			UNSET,
			LIVE,
			MOVED,
		};

		struct Slot {
			Held held = Held::UNSET;
			std::string name;
			const ast::Node* declared = nullptr;
			const ast::Node* moved_at = nullptr;
			// #release: released where its scope ends, so it can't be moved
			bool release_at_end = false;
			TypeInfo const* type = nullptr;
		};

		// What to write to release an owner of type, for messages.
		std::string release_hint(const Slot& slot) {
			TypeInfo const* base = get_base_type(slot.type);
			if (base != nullptr && TypeInfoVariant::ARRAY == base->variant) {
				return std::format("release its elements and it with runtime.array_release({}, ...)", slot.name);
			}
			if (base != nullptr && TypeInfoVariant::STRUCT == base->variant && static_cast<TypeInfoStruct const*>(base)->is_owned) {
				return std::format("release it, like defer compiler.release({}), mark it #release", slot.name);
			}
			return "release what it holds";
		}

		struct State {
			bool reachable = true;
			std::map<const void*, Slot> slots;
		};

		State unreachable() {
			State state;
			state.reachable = false;
			return state;
		}

		struct ScopeFrame {
			std::vector<const void*> locals;
			std::vector<ast::Node*> defers;
		};

		struct LoopFrame {
			std::vector<State> breaks;
			std::vector<State> continues;
			size_t scopes = 0;
			bool is_switch = false;
		};

		enum class Use : uint8_t {
			// Given away: the owner can't be used again
			MOVE,
			// Looked at, or pointed to, only
			BORROW,
			// Not kept by anything: an owned value here is dropped
			DISCARD,
		};

		struct Analysis {
			const CheckedBody& checked;
			std::string file_path;
			std::vector<ScopeFrame> scopes;
			std::vector<LoopFrame> loops;
			size_t errors = 0;
			// Going around a loop the first time, to see what coming back gives: nothing is reported
			bool quiet = false;
			std::set<std::pair<const ast::Node*, std::string>> reported;
		};

		void report(Analysis& analysis, const ast::Node* where, const std::string& message) {
			if (analysis.quiet || where == nullptr || !analysis.reported.insert({ where, message }).second) {
				return;
			}
			++analysis.errors;
			report_at(ErrorCode::E4035, analysis.file_path, analysis.checked.made, where, message);
		}

		const CheckedNode* found_at(const Analysis& analysis, const ast::Node* node) {
			auto iter = analysis.checked.nodes.find(node);
			return iter == analysis.checked.nodes.end() ? nullptr : &iter->second;
		}

		const CheckedNode* head_of(const Analysis& analysis, const ast::Node* node) {
			auto iter = analysis.checked.heads.find(node);
			return iter == analysis.checked.heads.end() ? nullptr : &iter->second;
		}

		// The local a name alone is, if it's one: what it names, not anything after it.
		const void* local_of(const Analysis& analysis, const ast::Node* node) {
			if (ast::NodeType::IDENTIFIER != node->node_type) {
				return nullptr;
			}
			const CheckedNode* head = head_of(analysis, node);
			if (head != nullptr && head->local != nullptr) {
				return head->local;
			}
			const CheckedNode* found = found_at(analysis, node);
			return found != nullptr ? found->local : nullptr;
		}

		std::string where_text(const ast::Node* node) {
			return node != nullptr ? std::format("line {}", node->value.line_number) : std::string("an earlier line");
		}

		void walk_block(Analysis& analysis, State& state, ast::Node* block, Use last = Use::DISCARD);
		void walk_statement(Analysis& analysis, State& state, ast::Node* statement);
		void evaluate(Analysis& analysis, State& state, ast::Node* node, Use use);

		// ---------------------------------------------------------------------------------------------
		// Owners

		// A new owner, in the innermost scope.
		void declare(Analysis& analysis, State& state, const void* local, const ast::Node* name, Held held, bool release_at_end,
			TypeInfo const* type) {

			Slot slot;
			slot.type = type;
			slot.held = held;
			slot.name = text_of(name->value.value);
			slot.declared = name;
			slot.release_at_end = release_at_end;
			state.slots[local] = slot;
			if (!analysis.scopes.empty()) {
				analysis.scopes.back().locals.push_back(local);
			}
		}

		// The owner a local is, using it: moving it, or looking at it.
		void use_owner(Analysis& analysis, State& state, const void* local, const ast::Node* where, Use use) {
			auto found = state.slots.find(local);
			if (!state.reachable) {
				return;
			}
			// An owned value that's part of something else, like a loop's element or a match's binding, is borrowed
			if (found == state.slots.end()) {
				const CheckedNode* checked = found_at(analysis, where);
				if (Use::MOVE == use && checked != nullptr && is_owned(checked->type)) {
					report(analysis, where, std::format("{} is part of what it came from, only borrowed here: "
						"take it out with compiler.take(&...), which leaves it empty", text_of(where->value.value)));
				}
				return;
			}
			Slot& slot = found->second;
			if (Held::MOVED == slot.held) {
				report(analysis, where, std::format("{} is used after it was moved or released, at {}", slot.name,
					where_text(slot.moved_at)));
				return;
			}
			if (Use::MOVE != use) {
				return;
			}
			if (slot.release_at_end) {
				report(analysis, where, std::format("{} is #release, so it's released where its scope ends and can't be moved; "
					"share it, or don't mark it", slot.name));
				return;
			}
			slot.held = Held::MOVED;
			slot.moved_at = where;
		}

		/*
		 * Leaving scopes down to depth: their defers run, last first, then each owner they declared has to
		 * have been moved or released.
		 */
		void leave(Analysis& analysis, State& state, size_t depth, const ast::Node* where) {
			for (size_t i = analysis.scopes.size(); i > depth; --i) {
				const ScopeFrame frame = analysis.scopes[i - 1];
				for (auto defer = frame.defers.rbegin(); defer != frame.defers.rend() && state.reachable; ++defer) {
					for (ast::Node* deferred : (*defer)->children) {
						walk_statement(analysis, state, deferred);
					}
				}
				for (const void* local : frame.locals) {
					auto found = state.slots.find(local);
					if (found == state.slots.end() || Held::LIVE != found->second.held || !state.reachable) {
						continue;
					}
					Slot& slot = found->second;
					if (slot.release_at_end) {
						slot.held = Held::MOVED;
						continue;
					}
					report(analysis, slot.declared, std::format("{} still owns its value where {} ends, at {}: {}, or move it",
						slot.name, where != nullptr && ast::NodeType::RETURN == where->node_type ? "the function" : "its scope",
						where_text(where), release_hint(slot)));
					slot.held = Held::MOVED;
				}
			}
		}

		// Where two paths meet: each owner has to be in the same state on both.
		State join(Analysis& analysis, const State& a, const State& b, const ast::Node* where) {
			if (!a.reachable) {
				return b;
			}
			if (!b.reachable) {
				return a;
			}
			State result = a;
			for (auto& [local, slot] : result.slots) {
				auto other = b.slots.find(local);
				if (other == b.slots.end() || other->second.held == slot.held) {
					continue;
				}
				const bool one_live = Held::LIVE == slot.held || Held::LIVE == other->second.held;
				if (one_live) {
					report(analysis, where, std::format("{} still owns its value on one path to here, but not on another: "
						"move or release it on both", slot.name));
				}
				slot.held = Held::MOVED;
				if (slot.moved_at == nullptr) {
					slot.moved_at = other->second.moved_at;
				}
			}
			return result;
		}

		// ---------------------------------------------------------------------------------------------
		// Expressions

		bool owned_at(const Analysis& analysis, const ast::Node* node) {
			const CheckedNode* found = found_at(analysis, node);
			return found != nullptr && ValueKind::VALUE == found->kind && is_owned(found->type);
		}

		bool is_compiler(const Declaration* declaration, std::string_view name) {
			const Declaration* generic = declaration != nullptr && declaration->generic != nullptr ? declaration->generic : declaration;
			return is_compiler_function(generic, name);
		}

		// A call's arguments, each moved when its parameter takes an owned value, or keeps an any it's given.
		void evaluate_call(Analysis& analysis, State& state, ast::Node* paren, const std::vector<ast::Node*>& arguments,
			const std::vector<ast::Node*>& piped) {

			const CheckedNode* found = found_at(analysis, paren);
			TypeInfoFunction const* function = found != nullptr ? found->called : nullptr;
			std::vector<ast::Node*> positional = piped;
			std::vector<std::pair<InternedString, ast::Node*>> named;
			for (ast::Node* argument : arguments) {
				if (ast::NodeType::BINARY_OPERATOR == argument->node_type && is_assign(argument) && argument->children.size() == 2
					&& ast::NodeType::IDENTIFIER == argument->children[0]->node_type) {
					named.emplace_back(argument->children[0]->value.value, argument->children[1]);
				}
				else if (ast::NodeType::UNDERSCORE != argument->node_type) {
					positional.push_back(argument);
				}
			}
			auto use_for = [&](const FunctionInput* input) {
				if (input == nullptr) {
					return Use::BORROW;
				}
				if (is_owned(input->type)) {
					return Use::MOVE;
				}
				// An any kept beyond the call, like a new thread's data, takes it
				TypeInfo const* base = get_base_type(input->type);
				const bool any = base != nullptr && TypeInfoVariant::ANY == base->variant;
				return any && input->is_escaping ? Use::MOVE : Use::BORROW;
			};
			for (size_t i = 0; i < positional.size(); ++i) {
				const FunctionInput* input = nullptr;
				if (function != nullptr && !function->input.empty()) {
					input = &function->input[std::min(i, function->input.size() - 1)];
					if (i >= function->input.size() && !input->is_varargs) {
						input = nullptr;
					}
				}
				Use use = use_for(input);
				// An owned value given to something that doesn't keep it is only looked at, unless it's made for the call
				if (Use::BORROW == use && owned_at(analysis, positional[i]) && local_of(analysis, positional[i]) == nullptr
					&& ast::NodeType::UNARY_OPERATOR != positional[i]->node_type) {
					use = Use::DISCARD;
				}
				evaluate(analysis, state, positional[i], use);
			}
			for (const auto& [name, node] : named) {
				const FunctionInput* input = nullptr;
				for (size_t j = 0; function != nullptr && j < function->input.size(); ++j) {
					if (function->input[j].name != nullptr && *function->input[j].name == *name) {
						input = &function->input[j];
					}
				}
				evaluate(analysis, state, node, use_for(input));
			}
			// compiler.take(&x) leaves x owning nothing
			if (found != nullptr && is_compiler(found->called_declaration, "take") && !positional.empty()) {
				ast::Node* argument = positional[0];
				if (ast::NodeType::UNARY_OPERATOR == argument->node_type && TokenType::SYM_AMPERSAND == argument->value.type
					&& !argument->children.empty()) {
					auto slot = state.slots.find(local_of(analysis, argument->children[0]));
					if (slot != state.slots.end() && argument->children[0]->children.empty()) {
						slot->second.held = Held::UNSET;
					}
				}
			}
		}

		/*
		 * A name and what follows it: a.b, f(x), a[i], p^. A local alone is used as asked; one with steps
		 * after it is looked at, and an owned value its steps reach can't be moved out of it.
		 */
		void evaluate_postfix(Analysis& analysis, State& state, ast::Node* node, Use use, const std::vector<ast::Node*>& piped) {
			const void* local = local_of(analysis, node);
			const CheckedNode* head = head_of(analysis, node);
			size_t start = head != nullptr ? head->next : 0;
			if (node->children.empty() || start >= node->children.size()) {
				if (local != nullptr) {
					use_owner(analysis, state, local, node, use);
				}
				return;
			}
			if (local != nullptr) {
				use_owner(analysis, state, local, node, Use::BORROW);
			}
			bool ends_in_call = false;
			const ast::Node* last = node;
			for (size_t i = start; i < node->children.size(); ++i) {
				ast::Node* child = node->children[i];
				std::vector<ast::Node*> arguments;
				while (i + 1 < node->children.size() && !is_postfix_marker(node->children[i + 1])) {
					arguments.push_back(node->children[++i]);
				}
				if (ast::NodeType::PAREN_GROUP == child->node_type && arguments.empty() && !child->children.empty()) {
					arguments.assign(child->children.begin(), child->children.end());
				}
				ends_in_call = ast::NodeType::PAREN_GROUP == child->node_type;
				if (ends_in_call) {
					bool last_call = true;
					for (size_t j = i + 1; j < node->children.size(); ++j) {
						last_call = last_call && ast::NodeType::PAREN_GROUP != node->children[j]->node_type;
					}
					evaluate_call(analysis, state, child, arguments, last_call ? piped : std::vector<ast::Node*>{});
					last = child;
				}
				else if (ast::NodeType::ARRAY_DIMENSION == child->node_type) {
					for (ast::Node* argument : arguments) {
						evaluate(analysis, state, argument, Use::BORROW);
					}
					last = child;
				}
				else if (ast::NodeType::DOT_ACCESS == child->node_type) {
					last = arguments.empty() ? child : arguments[0];
				}
				else {
					last = child;
				}
			}
			if (!owned_at(analysis, last) && !owned_at(analysis, node)) {
				return;
			}
			if (ends_in_call) {
				// What a call gives is new: kept, or dropped
				if (Use::DISCARD == use) {
					report(analysis, node, "this gives an owned value that nothing keeps: keep it, or release it");
				}
				return;
			}
			if (Use::MOVE == use) {
				report(analysis, node, "this moves an owned value out of what holds it, which still would: "
					"take it out with compiler.take(&...), which leaves it empty");
			}
		}

		void evaluate(Analysis& analysis, State& state, ast::Node* node, Use use) {
			if (!state.reachable || node == nullptr) {
				return;
			}
			const ast::NodeType type = node->node_type;
			if (ast::NodeType::IDENTIFIER == type) {
				evaluate_postfix(analysis, state, node, use, {});
				return;
			}
			if (ast::NodeType::UNARY_OPERATOR == type && !node->children.empty()) {
				const TokenType op = node->value.type;
				// &owner may fill it, like array_add(&files, file): from then on it owns what it holds
				if (TokenType::SYM_AMPERSAND == op && node->children[0]->children.empty()) {
					auto slot = state.slots.find(local_of(analysis, node->children[0]));
					if (slot != state.slots.end() && Held::UNSET == slot->second.held && state.reachable) {
						slot->second.held = Held::LIVE;
					}
				}
				// Unwrapping, like shared? or upgrade(&weak) or_else ..., passes on what's done with it
				const bool passes = TokenType::SYM_QUESTION == op || TokenType::KEYWORD_OR_BREAK == op
					|| TokenType::KEYWORD_OR_CONTINUE == op;
				evaluate(analysis, state, node->children[0], passes ? use : Use::BORROW);
				return;
			}
			if (ast::NodeType::BINARY_OPERATOR == type && node->children.size() == 2) {
				const TokenType op = node->value.type;
				if (TokenType::OPERATOR_PIPE == op) {
					ast::Node* right = node->children[1];
					std::vector<ast::Node*> piped{ node->children[0] };
					if (ast::NodeType::IDENTIFIER == right->node_type) {
						evaluate_postfix(analysis, state, right, use, piped);
					}
					return;
				}
				if (TokenType::KEYWORD_OR_ELSE == op || TokenType::KEYWORD_OR_RETURN == op) {
					evaluate(analysis, state, node->children[0], use);
					State otherwise = state;
					evaluate(analysis, otherwise, node->children[1], use);
					state = join(analysis, state, otherwise, node);
					return;
				}
				evaluate(analysis, state, node->children[0], Use::BORROW);
				evaluate(analysis, state, node->children[1], Use::BORROW);
				return;
			}
			if (ast::NodeType::STRUCT_LITERAL == type || ast::NodeType::ARRAY_LITERAL == type) {
				for (ast::Node* child : node->children) {
					if (ast::NodeType::LIST != child->node_type) {
						continue;
					}
					for (ast::Node* element : child->children) {
						ast::Node* value = ast::NodeType::BINARY_OPERATOR == element->node_type && is_assign(element)
							&& element->children.size() == 2 ? element->children[1] : element;
						evaluate(analysis, state, value, Use::MOVE);
					}
				}
				if (Use::DISCARD == use && owned_at(analysis, node)) {
					report(analysis, node, "this makes an owned value that nothing keeps: keep it, or release it");
				}
				return;
			}
			if (ast::NodeType::IF == type && node->children.size() >= 2) {
				evaluate(analysis, state, node->children[0], Use::BORROW);
				State otherwise = state;
				walk_block(analysis, state, node->children[1], use);
				ast::Node* branch = node->children.size() > 2 ? node->children[2] : nullptr;
				if (branch != nullptr && ast::NodeType::ELSE == branch->node_type && !branch->children.empty()) {
					branch = branch->children[0];
				}
				if (branch != nullptr && ast::NodeType::BLOCK == branch->node_type) {
					walk_block(analysis, otherwise, branch, use);
				}
				else if (branch != nullptr) {
					evaluate(analysis, otherwise, branch, use);
				}
				state = join(analysis, state, otherwise, node);
				return;
			}
			if (ast::NodeType::CAST == type) {
				for (ast::Node* child : node->children) {
					evaluate(analysis, state, child, Use::BORROW);
				}
				return;
			}
			if (ast::NodeType::PAREN_GROUP == type && node->children.size() == 1) {
				evaluate(analysis, state, node->children[0], use);
				return;
			}
			if (ast::NodeType::BLOCK == type) {
				walk_block(analysis, state, node, use);
				return;
			}
			if (ast::NodeType::FUNCTION == type || ast::NodeType::TYPE == type) {
				return;
			}
			for (ast::Node* child : node->children) {
				evaluate(analysis, state, child, Use::BORROW);
			}
		}

		// ---------------------------------------------------------------------------------------------
		// Statements

		void walk_definition(Analysis& analysis, State& state, ast::Node* definition) {
			std::vector<ast::Node*> names;
			ast::Node* names_node = definition->children[0];
			if (ast::NodeType::LIST == names_node->node_type) {
				names.assign(names_node->children.begin(), names_node->children.end());
			}
			else {
				names.push_back(names_node);
			}
			ast::Node* value = definition_value(definition);
			if (value != nullptr && ast::NodeType::FUNCTION == value->node_type) {
				return;
			}
			const bool has_value = value != nullptr && ast::NodeType::UNINITIALIZED != value->node_type;
			if (has_value) {
				// Into an owner, or several from one call; into _ it's dropped
				const bool dropped = names.size() == 1 && ast::NodeType::UNDERSCORE == names[0]->node_type;
				evaluate(analysis, state, value, dropped ? Use::DISCARD : Use::MOVE);
			}
			for (ast::Node* name : names) {
				const void* local = local_of(analysis, name);
				const CheckedNode* found = found_at(analysis, name);
				if (local == nullptr || found == nullptr || !is_owned(found->type)) {
					continue;
				}
				declare(analysis, state, local, name, has_value ? Held::LIVE : Held::UNSET, has_directive(name, "#release"), found->type);
			}
		}

		void walk_assignment(Analysis& analysis, State& state, ast::Node* node) {
			ast::Node* target = node->children[0];
			ast::Node* value = node->children[1];
			if (!is_assign(node)) {
				evaluate(analysis, state, target, Use::BORROW);
				evaluate(analysis, state, value, Use::BORROW);
				return;
			}
			evaluate(analysis, state, value, ast::NodeType::UNDERSCORE == target->node_type ? Use::DISCARD : Use::MOVE);
			if (ast::NodeType::UNDERSCORE == target->node_type) {
				return;
			}
			// An owner given a new value: it can't own one already
			const void* local = target->children.empty() ? local_of(analysis, target) : nullptr;
			auto slot = local != nullptr ? state.slots.find(local) : state.slots.end();
			if (slot != state.slots.end() && state.reachable) {
				if (Held::LIVE == slot->second.held) {
					report(analysis, target, std::format("{} still owns its value: release or move it before giving it another",
						slot->second.name));
				}
				slot->second.held = Held::LIVE;
				slot->second.moved_at = nullptr;
				return;
			}
			evaluate(analysis, state, target, Use::BORROW);
		}

		void walk_return(Analysis& analysis, State& state, ast::Node* statement) {
			for (ast::Node* child : statement->children) {
				if (ast::NodeType::LIST == child->node_type) {
					for (ast::Node* each : child->children) {
						evaluate(analysis, state, each, Use::MOVE);
					}
				}
				else {
					evaluate(analysis, state, child, Use::MOVE);
				}
			}
			leave(analysis, state, 0, statement);
			state = unreachable();
		}

		/*
		 * A loop's body, which may run many times: walked once quietly to see what coming back around gives,
		 * then once reporting. An owner from outside that's moved and not given a new value would be gone the
		 * next time around.
		 */
		void walk_body_around(Analysis& analysis, State& state, ast::Node* node, const std::function<void(State&)>& around,
			std::vector<State>& breaks) {

			const State entry = state;
			const bool was_quiet = analysis.quiet;
			analysis.quiet = true;
			LoopFrame first;
			first.scopes = analysis.scopes.size();
			analysis.loops.push_back(first);
			State back = entry;
			around(back);
			LoopFrame done = std::move(analysis.loops.back());
			analysis.loops.pop_back();
			for (const State& each : done.continues) {
				back = join(analysis, back, each, node);
			}
			analysis.quiet = was_quiet;
			// What's reported here isn't reported again after the loop
			std::vector<const void*> settled;
			if (back.reachable) {
				for (const auto& [local, slot] : entry.slots) {
					auto after = back.slots.find(local);
					if (after != back.slots.end() && after->second.held != slot.held
						&& (Held::LIVE == slot.held || Held::LIVE == after->second.held)) {
						settled.push_back(local);
						report(analysis, after->second.moved_at != nullptr ? after->second.moved_at : node,
							std::format("{} is {} each time around this loop, so the next time around it {}", slot.name,
								Held::LIVE == slot.held ? "moved or released" : "given a value",
								Held::LIVE == slot.held ? "has nothing" : "still owns the last one"));
					}
				}
			}
			LoopFrame frame;
			frame.scopes = analysis.scopes.size();
			analysis.loops.push_back(frame);
			State body = entry;
			around(body);
			LoopFrame reported = std::move(analysis.loops.back());
			analysis.loops.pop_back();
			breaks = std::move(reported.breaks);
			state = entry;
			for (const void* local : settled) {
				state.slots[local].held = Held::MOVED;
				for (State& each : breaks) {
					if (each.slots.contains(local)) {
						each.slots[local].held = Held::MOVED;
					}
				}
			}
		}

		void walk_for(Analysis& analysis, State& state, ast::Node* node) {
			ast::Node* iterable = nullptr;
			ast::Node* body = nullptr;
			bool after_in = false;
			for (ast::Node* child : node->children) {
				if (ast::NodeType::IN == child->node_type) {
					after_in = true;
				}
				else if (after_in && ast::NodeType::BLOCK == child->node_type) {
					body = child;
				}
				else if (after_in && ast::NodeType::DIRECTIVE != child->node_type && iterable == nullptr) {
					iterable = child;
				}
			}
			if (iterable != nullptr) {
				evaluate(analysis, state, iterable, Use::BORROW);
			}
			std::vector<State> breaks;
			walk_body_around(analysis, state, node, [&](State& each) {
				if (body != nullptr) {
					walk_block(analysis, each, body);
				}
			}, breaks);
			for (const State& each : breaks) {
				state = join(analysis, state, each, node);
			}
		}

		void walk_loop(Analysis& analysis, State& state, ast::Node* node) {
			ast::Node* body = nullptr;
			ast::Node* condition = nullptr;
			for (ast::Node* child : node->children) {
				if (ast::NodeType::WITH_CLAUSE == child->node_type) {
					for (ast::Node* list : child->children) {
						for (ast::Node* statement : list->children) {
							walk_statement(analysis, state, statement);
						}
					}
				}
				else if (ast::NodeType::WHILE_CLAUSE == child->node_type && !child->children.empty()) {
					condition = child->children[0];
				}
				else if (ast::NodeType::BLOCK == child->node_type) {
					body = child;
				}
			}
			std::vector<State> breaks;
			walk_body_around(analysis, state, node, [&](State& each) {
				if (body != nullptr) {
					walk_block(analysis, each, body);
				}
				if (condition != nullptr) {
					evaluate(analysis, each, condition, Use::BORROW);
				}
			}, breaks);
			// A loop without a condition only ends by break
			State exit = condition != nullptr ? state : unreachable();
			for (const State& each : breaks) {
				exit = join(analysis, exit, each, node);
			}
			state = exit;
		}

		std::vector<ast::Node*> entries_of(ast::Node* node, bool cases) {
			std::vector<ast::Node*> result;
			for (ast::Node* list : node->children) {
				if (ast::NodeType::LIST != list->node_type) {
					continue;
				}
				for (ast::Node* entry : list->children) {
					if (!entry->children.empty() && (!cases || ast::NodeType::SWITCH_CASE == entry->node_type)) {
						result.push_back(entry);
					}
				}
			}
			return result;
		}

		// The locals a pattern binds, like point in Some(point).
		void bindings_of(const Analysis& analysis, ast::Node* pattern, std::vector<ast::Node*>& names) {
			for (ast::Node* child : pattern->children) {
				if (ast::NodeType::IDENTIFIER == child->node_type && child->children.empty() && local_of(analysis, child) != nullptr) {
					names.push_back(child);
				}
				bindings_of(analysis, child, names);
			}
		}

		/*
		 * A match or switch: each arm from the same start. Matching an owned value that's made for it, like a
		 * call's result, gives its arms' bindings ownership; matching an owner only looks at it.
		 */
		void walk_match(Analysis& analysis, State& state, ast::Node* node, bool cases, Use use) {
			ast::Node* subject = node->children[0];
			const bool takes = owned_at(analysis, subject) && local_of(analysis, subject) == nullptr;
			evaluate(analysis, state, subject, takes ? Use::MOVE : Use::BORROW);
			State after = unreachable();
			if (cases) {
				LoopFrame frame;
				frame.is_switch = true;
				frame.scopes = analysis.scopes.size();
				analysis.loops.push_back(frame);
			}
			for (ast::Node* entry : entries_of(node, cases)) {
				State arm = state;
				analysis.scopes.emplace_back();
				for (size_t i = 0; i + 1 < entry->children.size(); ++i) {
					std::vector<ast::Node*> names;
					bindings_of(analysis, entry->children[i], names);
					for (ast::Node* name : names) {
						const CheckedNode* found = found_at(analysis, name);
						if (takes && found != nullptr && is_owned(found->type)) {
							declare(analysis, arm, local_of(analysis, name), name, Held::LIVE, false, found->type);
						}
					}
				}
				ast::Node* outcome = entry->children.back();
				if (ast::NodeType::BLOCK == outcome->node_type) {
					walk_block(analysis, arm, outcome, use);
				}
				else if (ast::NodeType::RETURN == outcome->node_type || ast::NodeType::BREAK == outcome->node_type
					|| ast::NodeType::CONTINUE == outcome->node_type) {
					walk_statement(analysis, arm, outcome);
				}
				else {
					evaluate(analysis, arm, outcome, use);
				}
				leave(analysis, arm, analysis.scopes.size() - 1, entry);
				for (const void* local : analysis.scopes.back().locals) {
					arm.slots.erase(local);
				}
				analysis.scopes.pop_back();
				after = join(analysis, after, arm, node);
			}
			if (cases) {
				LoopFrame frame = std::move(analysis.loops.back());
				analysis.loops.pop_back();
				for (const State& each : frame.breaks) {
					after = join(analysis, after, each, node);
				}
				for (State& each : frame.continues) {
					for (auto outer = analysis.loops.rbegin(); outer != analysis.loops.rend(); ++outer) {
						if (!outer->is_switch) {
							outer->continues.push_back(std::move(each));
							break;
						}
					}
				}
				after = join(analysis, after, state, node);
			}
			state = after;
		}

		void walk_statement(Analysis& analysis, State& state, ast::Node* statement) {
			if (!state.reachable) {
				return;
			}
			const ast::NodeType type = statement->node_type;
			if (ast::NodeType::DEFINITION == type) {
				walk_definition(analysis, state, statement);
			}
			else if (ast::NodeType::BINARY_OPERATOR == type && statement->children.size() == 2 && is_assign(statement)) {
				walk_assignment(analysis, state, statement);
			}
			else if (ast::NodeType::RETURN == type) {
				walk_return(analysis, state, statement);
			}
			else if (ast::NodeType::BREAK == type || ast::NodeType::CONTINUE == type) {
				size_t depth = 1;
				if (ast::NodeType::BREAK == type && !statement->children.empty()) {
					const ast::Node* count = statement->children[0];
					depth = ast::NodeType::KEYWORD_ALL == count->node_type ? analysis.loops.size()
						: static_cast<size_t>(std::strtoull(text_of(count->value.value).c_str(), nullptr, 10));
				}
				LoopFrame* target = nullptr;
				if (ast::NodeType::BREAK == type && depth >= 1 && depth <= analysis.loops.size()) {
					target = &analysis.loops[analysis.loops.size() - depth];
				}
				else if (ast::NodeType::CONTINUE == type) {
					for (auto frame = analysis.loops.rbegin(); frame != analysis.loops.rend(); ++frame) {
						if (!frame->is_switch) {
							target = &*frame;
							break;
						}
					}
				}
				if (target != nullptr) {
					State leaving = state;
					leave(analysis, leaving, target->scopes, statement);
					(ast::NodeType::BREAK == type ? target->breaks : target->continues).push_back(leaving);
				}
				state = unreachable();
			}
			else if (ast::NodeType::IF == type) {
				evaluate(analysis, state, statement, Use::DISCARD);
			}
			else if (ast::NodeType::FOR_LOOP == type) {
				walk_for(analysis, state, statement);
			}
			else if (ast::NodeType::LOOP == type) {
				walk_loop(analysis, state, statement);
			}
			else if (ast::NodeType::DEFER == type) {
				if (!analysis.scopes.empty()) {
					analysis.scopes.back().defers.push_back(statement);
				}
			}
			else if (ast::NodeType::BLOCK == type) {
				walk_block(analysis, state, statement);
			}
			else if (ast::NodeType::MATCH == type) {
				walk_match(analysis, state, statement, false, Use::DISCARD);
			}
			else if (ast::NodeType::SWITCH == type) {
				walk_match(analysis, state, statement, true, Use::DISCARD);
			}
			else if (ast::NodeType::PUSH_CONTEXT == type) {
				ast::Node* body = statement->children.empty() ? nullptr : statement->children.back();
				for (ast::Node* child : statement->children) {
					if (child != body) {
						evaluate(analysis, state, child, Use::BORROW);
					}
				}
				if (body != nullptr && ast::NodeType::BLOCK == body->node_type) {
					walk_block(analysis, state, body);
				}
			}
			else if (ast::NodeType::DIRECTIVE == type) {
				return;
			}
			else {
				evaluate(analysis, state, statement, Use::DISCARD);
			}
		}

		void walk_block(Analysis& analysis, State& state, ast::Node* block, Use last) {
			analysis.scopes.emplace_back();
			for (size_t i = 0; i < block->children.size() && state.reachable; ++i) {
				ast::Node* statement = block->children[i];
				if (ast::NodeType::DIRECTIVE == statement->node_type && is_text(statement->value.value, "#if")) {
					std::vector<ast::Node*> chain{ statement };
					while (i + 1 < block->children.size() && ast::NodeType::DIRECTIVE == block->children[i + 1]->node_type
						&& (is_text(block->children[i + 1]->value.value, "#else_if") || is_text(block->children[i + 1]->value.value, "#else"))) {
						chain.push_back(block->children[++i]);
						if (is_text(chain.back()->value.value, "#else")) {
							break;
						}
					}
					const CheckedNode* chosen = found_at(analysis, statement);
					if (chosen != nullptr && chosen->variant < chain.size() && !chain[chosen->variant]->children.empty()) {
						walk_block(analysis, state, chain[chosen->variant]->children.back());
					}
					continue;
				}
				// A block's last expression is its value
				const bool is_value = i + 1 == block->children.size() && Use::DISCARD != last
					&& ast::NodeType::DEFINITION != statement->node_type && ast::NodeType::RETURN != statement->node_type
					&& ast::NodeType::BREAK != statement->node_type && ast::NodeType::CONTINUE != statement->node_type;
				if (is_value) {
					evaluate(analysis, state, statement, last);
				}
				else {
					walk_statement(analysis, state, statement);
				}
			}
			if (state.reachable) {
				leave(analysis, state, analysis.scopes.size() - 1, block);
			}
			for (const void* local : analysis.scopes.back().locals) {
				state.slots.erase(local);
			}
			analysis.scopes.pop_back();
		}
	}

	bool check_ownership(const CheckedBody& checked, ast::Node* function_node, ast::Node* body, TypeInfoFunction const* type,
		const std::string& file_path) {

		Analysis analysis{ checked, file_path, {}, {}, 0, false, {} };
		State state;
		// The parameters it takes by value own what they're given
		analysis.scopes.emplace_back();
		std::vector<ast::Node*> names;
		for (ast::Node* child : function_node->children) {
			if (ast::NodeType::LIST != child->node_type) {
				continue;
			}
			for (ast::Node* parameter : child->children) {
				ast::Node* named = ast::NodeType::BINARY_OPERATOR == parameter->node_type && is_assign(parameter)
					? parameter->children[0] : parameter;
				names.push_back(ast::NodeType::COLON == named->node_type && !named->children.empty() ? named->children[0] : named);
			}
			break;
		}
		for (size_t i = 0; i < checked.parameters.size() && i < type->input.size() && i < names.size(); ++i) {
			if (checked.parameters[i] != nullptr && is_owned(type->input[i].type) && !type->input[i].is_varargs) {
				declare(analysis, state, checked.parameters[i], names[i], Held::LIVE, has_directive(names[i], "#release"), type->input[i].type);
			}
		}
		walk_block(analysis, state, body);
		if (state.reachable) {
			leave(analysis, state, 0, body);
		}
		return analysis.errors == 0;
	}
}

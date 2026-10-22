#pragma once

#include <chrono>
#include <cstdio>
#include <string>

namespace hemera {

	/*
	 * --time-phases: how long a phase of compiling took, printed on standard error when it ends, like
	 * "phase generate kernel: 812 ms". Does nothing without the flag.
	 */
	class PhaseTimer {
	public:
		PhaseTimer(bool enabled, std::string name)
			: enabled{ enabled }
			, name{ std::move(name) }
			, start{ std::chrono::steady_clock::now() }
		{}

		PhaseTimer(const PhaseTimer&) = delete;
		PhaseTimer& operator=(const PhaseTimer&) = delete;

		~PhaseTimer() {
			if (!enabled) {
				return;
			}
			const auto took = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - start);
			std::fprintf(stderr, "phase %s: %lld ms\n", name.c_str(), static_cast<long long>(took.count()));
		}

	private:
		bool enabled;
		std::string name;
		std::chrono::steady_clock::time_point start;
	};

}

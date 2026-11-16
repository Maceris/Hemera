#include <atomic>
#include <condition_variable>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "gtest/gtest.h"

#include "checker.h"

using hemera::lsp::Checker;
using hemera::lsp::CheckJob;
using hemera::lsp::parse_diagnostics;
using hemera::lsp::Run;
using hemera::lsp::RunResult;

TEST(ParseDiagnostics, ReadsEachLine) {
	const auto found = parse_diagnostics(
		R"({"severity":"error","code":"hemera:E4015","file":"D:/p/main.hsc","line":12,"column":5,"message":"Type mismatch"})" "\r\n"
		R"({"severity":"information","file":"D:/p/build.hsc","line":3,"column":1,"message":"building"})" "\n");

	ASSERT_EQ(2u, found.size());
	EXPECT_EQ("error", found[0].severity);
	EXPECT_EQ("hemera:E4015", found[0].code);
	EXPECT_EQ("D:/p/main.hsc", found[0].file);
	EXPECT_EQ(12u, found[0].line);
	EXPECT_EQ(5u, found[0].column);
	EXPECT_EQ("Type mismatch", found[0].message);
	EXPECT_EQ("", found[1].code);
}

TEST(ParseDiagnostics, SkipsWhatIsNotADiagnostic) {
	const auto found = parse_diagnostics("printed by something\n{\"severity\":\"error\"}\n[1,2]\n");

	EXPECT_TRUE(found.empty());
}

namespace {

	// A run that finishes with output once let go, or is stopped first
	class HeldRun : public Run {
	public:
		explicit HeldRun(std::string output) : output(std::move(output)) {}

		RunResult wait() override {
			std::unique_lock<std::mutex> lock(mutex);
			changed.wait(lock, [this] { return released || stopped; });
			RunResult result;
			result.started = true;
			result.stopped = stopped;
			result.output = output;
			return result;
		}

		void stop() override {
			std::lock_guard<std::mutex> lock(mutex);
			stopped = true;
			changed.notify_all();
		}

		void release() {
			std::lock_guard<std::mutex> lock(mutex);
			released = true;
			changed.notify_all();
		}

	private:
		std::string output;
		std::mutex mutex;
		std::condition_variable changed;
		bool released = false;
		bool stopped = false;
	};
}

TEST(Checker, ANewerCheckOfTheSameRootStopsTheOneRunning) {
	std::mutex mutex;
	std::condition_variable launched;
	std::vector<HeldRun*> runs;
	std::vector<std::string> finished;
	Checker checker(
		[&](const std::vector<std::string>& arguments) -> std::unique_ptr<hemera::lsp::Run> {
			auto run = std::make_unique<HeldRun>(arguments.back());
			std::lock_guard<std::mutex> lock(mutex);
			runs.push_back(run.get());
			launched.notify_all();
			return run;
		},
		[&](const CheckJob& job, const RunResult& result) {
			std::lock_guard<std::mutex> lock(mutex);
			finished.push_back(job.root + ":" + result.output);
		});

	checker.request(CheckJob{ "a", { "hemera", "first" }, {} });
	{
		std::unique_lock<std::mutex> lock(mutex);
		launched.wait(lock, [&] { return runs.size() == 1; });
	}
	checker.request(CheckJob{ "a", { "hemera", "second" }, {} });
	{
		std::unique_lock<std::mutex> lock(mutex);
		launched.wait(lock, [&] { return runs.size() == 2; });
		runs[1]->release();
	}
	checker.wait_idle();

	EXPECT_EQ(std::vector<std::string>{ "a:second" }, finished);
}

/*
 * A quick check of other targets, as a save of another file gives, waits for the one running, whose result it
 * wouldn't give; one of the same targets and more stops it.
 */
TEST(Checker, AQuickCheckStopsOnlyOneItDoesAllOf) {
	std::mutex mutex;
	std::condition_variable launched;
	std::vector<HeldRun*> runs;
	std::vector<std::string> finished;
	Checker checker(
		[&](const std::vector<std::string>& arguments) -> std::unique_ptr<hemera::lsp::Run> {
			auto run = std::make_unique<HeldRun>(arguments.back());
			std::lock_guard<std::mutex> lock(mutex);
			runs.push_back(run.get());
			launched.notify_all();
			return run;
		},
		[&](const CheckJob& job, const RunResult& result) {
			std::lock_guard<std::mutex> lock(mutex);
			finished.push_back(job.root + ":" + result.output);
		});
	const auto quick = [](std::string name, std::vector<std::string> targets) {
		CheckJob job{ "a", { "hemera", std::move(name) }, {} };
		job.targets = std::move(targets);
		return job;
	};

	checker.request(quick("kernel", { "kernel" }));
	{
		std::unique_lock<std::mutex> lock(mutex);
		launched.wait(lock, [&] { return runs.size() == 1; });
	}
	// Queued: it doesn't check the kernel
	checker.request(quick("entropy", { "entropy" }));
	// Replaces the one waiting, and stops the one running: it checks both
	checker.request(quick("both", { "entropy", "kernel" }));
	{
		std::unique_lock<std::mutex> lock(mutex);
		launched.wait(lock, [&] { return runs.size() == 2; });
		runs[1]->release();
	}
	checker.wait_idle();

	EXPECT_EQ((std::vector<std::string>{ "a:both" }), finished);
}

TEST(Checker, AQuickCheckOfOtherTargetsWaitsForTheOneRunning) {
	std::mutex mutex;
	std::condition_variable launched;
	std::vector<HeldRun*> runs;
	std::vector<std::string> finished;
	Checker checker(
		[&](const std::vector<std::string>& arguments) -> std::unique_ptr<hemera::lsp::Run> {
			auto run = std::make_unique<HeldRun>(arguments.back());
			std::lock_guard<std::mutex> lock(mutex);
			runs.push_back(run.get());
			launched.notify_all();
			return run;
		},
		[&](const CheckJob& job, const RunResult& result) {
			std::lock_guard<std::mutex> lock(mutex);
			finished.push_back(job.root + ":" + result.output);
		});
	CheckJob kernel{ "a", { "hemera", "kernel" }, {} };
	kernel.targets = { "kernel" };
	CheckJob entropy{ "a", { "hemera", "entropy" }, {} };
	entropy.targets = { "entropy" };

	checker.request(std::move(kernel));
	{
		std::unique_lock<std::mutex> lock(mutex);
		launched.wait(lock, [&] { return runs.size() == 1; });
	}
	checker.request(std::move(entropy));
	{
		std::unique_lock<std::mutex> lock(mutex);
		runs[0]->release();
		launched.wait(lock, [&] { return runs.size() == 2; });
		runs[1]->release();
	}
	checker.wait_idle();

	EXPECT_EQ((std::vector<std::string>{ "a:kernel", "a:entropy" }), finished);
}

TEST(Checker, AFullCheckWaitsForAQuickOneOfTheSameRoot) {
	std::mutex mutex;
	std::condition_variable launched;
	std::vector<HeldRun*> runs;
	std::vector<std::string> finished;
	Checker checker(
		[&](const std::vector<std::string>& arguments) -> std::unique_ptr<hemera::lsp::Run> {
			auto run = std::make_unique<HeldRun>(arguments.back());
			std::lock_guard<std::mutex> lock(mutex);
			runs.push_back(run.get());
			launched.notify_all();
			return run;
		},
		[&](const CheckJob& job, const RunResult& result) {
			std::lock_guard<std::mutex> lock(mutex);
			finished.push_back(job.root + ":" + result.output);
		});

	CheckJob quick{ "a", { "hemera", "quick" }, {} };
	quick.targets = { "kernel" };
	checker.request(std::move(quick));
	{
		std::unique_lock<std::mutex> lock(mutex);
		launched.wait(lock, [&] { return runs.size() == 1; });
	}
	// Queued behind it, not stopping it
	checker.request(CheckJob{ "a", { "hemera", "full" }, {} });
	{
		std::unique_lock<std::mutex> lock(mutex);
		runs[0]->release();
		launched.wait(lock, [&] { return runs.size() == 2; });
		runs[1]->release();
	}
	checker.wait_idle();

	EXPECT_EQ((std::vector<std::string>{ "a:quick", "a:full" }), finished);
}

TEST(Checker, OtherRootsWaitTheirTurn) {
	std::vector<std::string> finished;
	std::mutex mutex;
	Checker checker(
		[](const std::vector<std::string>& arguments) -> std::unique_ptr<hemera::lsp::Run> {
			auto run = std::make_unique<HeldRun>(arguments.back());
			run->release();
			return run;
		},
		[&](const CheckJob& job, const RunResult&) {
			std::lock_guard<std::mutex> lock(mutex);
			finished.push_back(job.root);
		});

	checker.request(CheckJob{ "a", { "hemera", "a" }, {} });
	checker.request(CheckJob{ "b", { "hemera", "b" }, {} });
	checker.wait_idle();

	EXPECT_EQ((std::vector<std::string>{ "a", "b" }), finished);
}

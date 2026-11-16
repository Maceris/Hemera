#include <string>
#include <vector>

#include "gtest/gtest.h"

#include "hemera_errors.h"
#include "hemera_warnings.h"
#include "error/reporting.h"

using hemera::Diagnostic;
using hemera::Severity;

namespace {

	// The process's warning rules back to allowing and denying nothing, and holding nothing
	void clear_warning_rules() {
		hemera::start_warning_rules({}, {}, {}, "");
		hemera::release_warnings();
	}

	// Fresh reporting storage and warning rules, with nothing printed, for each test
	class Reporting : public testing::Test {
	protected:
		void SetUp() override {
			clear_warning_rules();
			hemera::reset_reporting_storage();
			hemera::disable_reporting_printing();
		}

		void TearDown() override {
			clear_warning_rules();
			hemera::reset_reporting_storage();
			hemera::enable_reporting_printing();
		}
	};

}

TEST_F(Reporting, ErrorMakesItsRecord) {
	hemera::report_error(hemera::ErrorCode::E4015, "main.hsc", 12, 5, "the returned value needs int");

	const std::vector<Diagnostic> found = hemera::diagnostics();
	ASSERT_EQ(1u, found.size());
	const hemera::ErrorInfo& info = hemera::error_info_map->find(hemera::ErrorCode::E4015)->second;
	EXPECT_EQ(Severity::ERROR, found[0].severity);
	EXPECT_EQ("hemera", found[0].prefix);
	EXPECT_EQ("E4015", found[0].code);
	EXPECT_EQ("main.hsc", found[0].file);
	EXPECT_EQ(12u, found[0].line);
	EXPECT_EQ(5u, found[0].column);
	EXPECT_EQ(std::string(info.message) + ". the returned value needs int", found[0].message);
}

TEST_F(Reporting, ErrorWithoutDetailsIsItsTitle) {
	hemera::report_error(hemera::ErrorCode::E4015, "main.hsc", 1, 1);

	const std::vector<Diagnostic> found = hemera::diagnostics();
	ASSERT_EQ(1u, found.size());
	EXPECT_EQ(std::string(hemera::error_info_map->find(hemera::ErrorCode::E4015)->second.message), found[0].message);
}

TEST_F(Reporting, RepeatedErrorMakesOneRecord) {
	hemera::report_error(hemera::ErrorCode::E4015, "main.hsc", 1, 1, "same");
	hemera::report_error(hemera::ErrorCode::E4015, "main.hsc", 1, 1, "same");

	EXPECT_EQ(1u, hemera::diagnostics().size());
}

TEST_F(Reporting, CompilerWarningMakesItsRecord) {
	hemera::report_warning(hemera::WarningCode::W4001, "main.hsc", 3, 7, "more");

	const std::vector<Diagnostic> found = hemera::diagnostics();
	ASSERT_EQ(1u, found.size());
	EXPECT_EQ(Severity::WARNING, found[0].severity);
	EXPECT_EQ("hemera", found[0].prefix);
	EXPECT_EQ("W4001", found[0].code);
	EXPECT_EQ(3u, found[0].line);
	EXPECT_EQ(7u, found[0].column);
	EXPECT_TRUE(found[0].message.ends_with(". more"));
}

TEST_F(Reporting, CodedReportsKeepTheirOwnCodes) {
	hemera::report_coded(true, "fonts", "E0002", "fonts.hsc", 4, 2, "no glyphs");
	hemera::report_coded(false, "fonts", "W0003", "fonts.hsc", 5, 3, "a missing kerning table");

	const std::vector<Diagnostic> found = hemera::diagnostics();
	ASSERT_EQ(2u, found.size());
	EXPECT_EQ(Severity::ERROR, found[0].severity);
	EXPECT_EQ("fonts", found[0].prefix);
	EXPECT_EQ("E0002", found[0].code);
	EXPECT_EQ("no glyphs", found[0].message);
	EXPECT_EQ(Severity::WARNING, found[1].severity);
	EXPECT_EQ("fonts", found[1].prefix);
	EXPECT_EQ("W0003", found[1].code);
	EXPECT_EQ("a missing kerning table", found[1].message);
}

TEST_F(Reporting, DeniedWarningIsAnErrorWithItsOwnCode) {
	hemera::start_warning_rules({}, { "fonts:*" }, {}, "");
	hemera::report_coded(false, "fonts", "W0003", "fonts.hsc", 5, 3, "a missing kerning table");
	EXPECT_TRUE(hemera::diagnostics().empty()) << "held until the rules are released";
	hemera::release_warnings();

	const std::vector<Diagnostic> found = hemera::diagnostics();
	ASSERT_EQ(1u, found.size());
	EXPECT_EQ(Severity::ERROR, found[0].severity);
	EXPECT_EQ("fonts", found[0].prefix);
	EXPECT_EQ("W0003", found[0].code);
}

TEST_F(Reporting, AllowedWarningMakesNoRecord) {
	hemera::start_warning_rules({ "fonts:W0003" }, {}, {}, "");
	hemera::report_coded(false, "fonts", "W0003", "fonts.hsc", 5, 3, "a missing kerning table");
	hemera::release_warnings();

	EXPECT_TRUE(hemera::diagnostics().empty());
}

TEST_F(Reporting, MessageIsInformationWithoutACode) {
	hemera::report_message("build.hsc", 9, 1, "info", "building the kernel");

	const std::vector<Diagnostic> found = hemera::diagnostics();
	ASSERT_EQ(1u, found.size());
	EXPECT_EQ(Severity::INFORMATION, found[0].severity);
	EXPECT_TRUE(found[0].prefix.empty());
	EXPECT_TRUE(found[0].code.empty());
	EXPECT_EQ("building the kernel", found[0].message);
}

TEST_F(Reporting, ScopesRecordsJoinWhenPrinted) {
	hemera::report_error(hemera::ErrorCode::E4015, "first.hsc", 1, 1);
	hemera::ReportScope scope;
	hemera::set_report_scope(&scope);
	hemera::report_error(hemera::ErrorCode::E4015, "scoped.hsc", 2, 2);
	hemera::set_report_scope(nullptr);
	EXPECT_EQ(1u, hemera::diagnostics().size()) << "a scope's records wait for it to be printed";

	hemera::print_report_scope(scope);

	const std::vector<Diagnostic> found = hemera::diagnostics();
	ASSERT_EQ(2u, found.size());
	EXPECT_EQ("first.hsc", found[0].file);
	EXPECT_EQ("scoped.hsc", found[1].file);
	EXPECT_TRUE(scope.diagnostics.empty());
}

TEST_F(Reporting, ResetForgetsRecords) {
	hemera::report_error(hemera::ErrorCode::E4015, "main.hsc", 1, 1);
	hemera::reset_reporting_storage();

	EXPECT_TRUE(hemera::diagnostics().empty());
}

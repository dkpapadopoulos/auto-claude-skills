#!/usr/bin/env python3
"""Instrument tests for the native-contract classifier.

`conformance.py` shipped with no tests; its classifier was corrected twice during
the audit by reading traces, which is not a repeatable method. These tests pin the
classification contract in `TESTS-TODO.md`.

Two rules govern this file:

1. **Every fixture is derived from a retained real trace.** See
   `fixtures/PROVENANCE.md`. No test constructs a stream inline -- a hand-written
   fixture only proves the classifier agrees with the test author.
2. **No test may launch a paid run.** `subprocess.Popen` is replaced module-wide
   with a stub that fails the test if it is ever reached, and that guard is itself
   asserted rather than assumed.
"""
import json
import re
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import conformance  # noqa: E402

FIXTURES = HERE / "fixtures"

_REAL_POPEN = conformance.subprocess.Popen


class PaidRunAttempted(AssertionError):
    """Raised if any test reaches the provider CLI."""


def setUpModule():
    def _refuse(*args, **kwargs):
        raise PaidRunAttempted(f"a test attempted to launch the provider: {args[:1]}")
    conformance.subprocess.Popen = _refuse


def tearDownModule():
    conformance.subprocess.Popen = _REAL_POPEN


def parse(name):
    return conformance.parse_stream(FIXTURES / name)


def verdict(case, name):
    return conformance.judge(case, parse(name))


class SafetyTest(unittest.TestCase):
    """A test that COULD spend money is a defect regardless of whether it does."""

    def test_provider_is_stubbed_for_this_module(self):
        with self.assertRaises(PaidRunAttempted):
            conformance.subprocess.Popen(["/opt/homebrew/bin/claude"])

    def test_preparing_a_case_never_reaches_the_provider(self):
        case = {"id": "prepared", "contract": "fixture", "prompt": "unused"}
        with tempfile.TemporaryDirectory() as directory:
            record = conformance.run_case(case, Path(directory), live=False)
        self.assertTrue(record["prepared_only"])


class SucceededInvocationTest(unittest.TestCase):
    """Case: successful invocation -> `succeeded`. Source: B3, `panel` returned."""

    def test_returned_call_is_succeeded(self):
        parsed = parse("succeeded-and-refused.jsonl")
        self.assertEqual(parsed["skill_outcomes"]["panel"], "succeeded")
        self.assertIn("panel", parsed["skills_succeeded"])

    def test_expectation_is_met_by_a_succeeded_call(self):
        result = verdict({"expect_present": ["panel"]}, "succeeded-and-refused.jsonl")
        self.assertEqual(result["violations"], [])
        self.assertTrue(result["satisfied"])


class RefusedInvocationTest(unittest.TestCase):
    """Case: attempted but refused -> never `succeeded`.

    This is the defect that briefly reported the blocked composed path as working.
    """

    def test_refusal_is_classified_as_refused(self):
        parsed = parse("succeeded-and-refused.jsonl")
        self.assertEqual(parsed["skill_outcomes"]["synthesize"],
                         "refused_disable_model_invocation")

    def test_refused_call_is_not_counted_as_succeeded(self):
        parsed = parse("succeeded-and-refused.jsonl")
        self.assertNotIn("synthesize", parsed["skills_succeeded"])
        self.assertIn("synthesize", parsed["skills_refused"])

    def test_an_attempt_does_not_satisfy_expect_present(self):
        result = verdict({"expect_present": ["synthesize"]},
                         "succeeded-and-refused.jsonl")
        self.assertFalse(result["satisfied"])
        self.assertIn("expected present: synthesize", result["violations"])


class VacuousSuccessTest(unittest.TestCase):
    """Case: vacuous success -> `satisfied` AND `vacuous`. Source: A3 control."""

    def test_absence_only_criterion_met_by_invoking_nothing_is_vacuous(self):
        result = verdict({"expect_absent": ["panel", "design-debate", "synthesize"]},
                         "vacuous-absence.jsonl")
        self.assertTrue(result["satisfied"])
        self.assertTrue(result["vacuous"])


class ProviderTruncationTest(unittest.TestCase):
    """Case: provider truncation -> unscored, never pooled as clean.

    Source r4 carries `subtype: "success"` with `is_error: true` and a session-limit
    message. Scoring the skills that happened to land before the cutoff reports a
    truncated run as conformance.
    """

    def test_truncation_is_visible_in_the_parse(self):
        parsed = parse("provider-truncation.jsonl")
        self.assertTrue(parsed["is_error"])

    def test_truncated_run_is_not_scored(self):
        result = verdict({"expect_absent": ["panel"]}, "provider-truncation.jsonl")
        self.assertEqual(result["disposition"], "unscored_provider_error")

    def test_truncated_run_is_never_satisfied(self):
        result = verdict({"expect_absent": ["panel"]}, "provider-truncation.jsonl")
        self.assertFalse(result["satisfied"])

    def test_a_clean_run_is_scored(self):
        """Control: the disposition must distinguish, not reject everything."""
        result = verdict({"expect_present": ["panel"]}, "succeeded-and-refused.jsonl")
        self.assertEqual(result["disposition"], "scored")


class MissingResultTest(unittest.TestCase):
    """Case: missing result -> `no_result`, distinct from `succeeded`."""

    def test_unmatched_call_is_no_result(self):
        parsed = parse("no-result.jsonl")
        self.assertEqual(parsed["skill_outcomes"]["synthesize"], "no_result")

    def test_no_result_is_not_succeeded(self):
        parsed = parse("no-result.jsonl")
        self.assertNotIn("synthesize", parsed["skills_succeeded"])

    def test_no_result_does_not_satisfy_expect_present(self):
        result = verdict({"expect_present": ["synthesize"]}, "no-result.jsonl")
        self.assertFalse(result["satisfied"])


class DuplicateResultsTest(unittest.TestCase):
    """Case: duplicate results -> inconclusive, never a pass.

    The audit's independent review found that duplicate successful calls could
    produce a false negative-pair conclusion. In this runner the mechanism is that
    per-call outcomes are keyed by skill NAME, so a second call to the same skill
    overwrites the first and the duplicate becomes invisible.
    """

    def test_both_calls_are_observed(self):
        parsed = parse("duplicate-results.jsonl")
        self.assertEqual(parsed["skills_attempted"].count("auto-claude-skills:panel"), 2)

    def test_duplicate_call_is_reported(self):
        parsed = parse("duplicate-results.jsonl")
        self.assertIn("panel", parsed["duplicate_skill_calls"])

    def test_duplicate_call_makes_the_run_inconclusive(self):
        result = verdict({"expect_present": ["panel"]}, "duplicate-results.jsonl")
        self.assertEqual(result["disposition"], "inconclusive_duplicate_calls")

    def test_duplicate_call_is_never_a_pass(self):
        result = verdict({"expect_present": ["panel"]}, "duplicate-results.jsonl")
        self.assertFalse(result["satisfied"])

    def test_a_single_call_is_not_reported_as_duplicate(self):
        """Control: the detector must not fire on the ordinary case."""
        parsed = parse("succeeded-and-refused.jsonl")
        self.assertEqual(parsed["duplicate_skill_calls"], [])


class AbsenceWithoutPreconditionTest(unittest.TestCase):
    """`A2` recorded "did not synthesize" while no perspectives existed to synthesize.

    An absence whose precondition was never established carries no information and
    must not be scored as conformance.
    """

    def test_the_precondition_is_genuinely_absent_in_the_fixture(self):
        parsed = parse("absence-without-precondition.jsonl")
        self.assertEqual(parsed["subagent_dispatches"], 0)

    def test_uninformative_absence_is_reported(self):
        result = verdict({"expect_present": ["panel"], "expect_absent": ["synthesize"]},
                         "absence-without-precondition.jsonl")
        self.assertIn("synthesize", result["uninformative_absences"])

    def test_informative_absence_is_not_reported(self):
        """Control: `panel` has no unmet precondition, so its absence still counts."""
        result = verdict({"expect_absent": ["panel"]}, "vacuous-absence.jsonl")
        self.assertEqual(result["uninformative_absences"], [])


class ExitCodeTest(unittest.TestCase):
    """`conformance.py` exited 0 after reporting violations.

    It should not be wired to a gate -- it is paid and non-deterministic -- but an
    instrument that reports a violation and exits 0 cannot be wired to one safely
    either.
    """

    def test_a_violation_exits_non_zero(self):
        self.assertNotEqual(conformance.exit_code([{"satisfied": False,
                                                    "disposition": "scored"}]), 0)

    def test_an_unscored_run_exits_non_zero(self):
        self.assertNotEqual(conformance.exit_code([{"satisfied": False,
                                                    "disposition":
                                                    "unscored_provider_error"}]), 0)

    def test_a_clean_run_exits_zero(self):
        self.assertEqual(conformance.exit_code([{"satisfied": True,
                                                 "disposition": "scored"}]), 0)

    def test_a_prepare_only_run_exits_zero(self):
        """`--out` without `--live` prepares manifests and scores nothing.

        Those records carry no disposition, and treating a missing disposition as
        a failure would make preparing a run report as a failing one.
        """
        self.assertEqual(conformance.exit_code([{"case": "x", "prepared_only": True}]), 0)

    def test_a_record_that_is_neither_prepared_nor_scored_exits_non_zero(self):
        """Control: the prepare-only exemption must not swallow a real record."""
        self.assertNotEqual(conformance.exit_code([{"case": "x"}]), 0)


class StreamCorruptionTest(unittest.TestCase):
    """An undecodable line must make the run UNSCORED, not quietly shorter.

    The parser skipped undecodable lines silently. Measured on the corrupt fixture
    before the fix: `expected absent: panel` disappeared and the case reported
    satisfied, exit 0 -- a violation became a clean pass because the event carrying the
    violation stopped existing.
    """

    def test_corruption_is_counted(self):
        self.assertGreater(parse("stream-corrupt.jsonl")["decode_failures"], 0)

    def test_intact_fixture_has_no_corruption(self):
        """Control: the counter must not fire on a healthy stream."""
        self.assertEqual(parse("succeeded-and-refused.jsonl")["decode_failures"], 0)

    def test_corrupt_stream_is_unscored(self):
        result = verdict({"expect_absent": ["panel"]}, "stream-corrupt.jsonl")
        self.assertEqual(result["disposition"], "unscored_stream_corrupt")

    def test_corrupt_stream_is_never_satisfied(self):
        """The defect: the intact stream VIOLATES this expectation. The corrupt one
        must not report satisfied just because the offending event vanished."""
        intact = verdict({"expect_absent": ["panel"]}, "succeeded-and-refused.jsonl")
        corrupt = verdict({"expect_absent": ["panel"]}, "stream-corrupt.jsonl")
        self.assertFalse(intact["satisfied"])
        self.assertFalse(corrupt["satisfied"])

    def test_corrupt_stream_exits_non_zero(self):
        self.assertNotEqual(conformance.exit_code(
            [{"satisfied": False, "disposition": "unscored_stream_corrupt"}]), 0)


class ProgressLineTest(unittest.TestCase):
    """The progress line printed per case must name keys the record actually has.

    `consultation_skills_invoked` was printed for every case and never produced by
    `judge()`, so that column read `null` on every run of the instrument.
    """

    PRINTED = ("case", "skills_bare", "consultation_skills_succeeded",
               "satisfied", "vacuous", "violations", "returncode", "disposition")

    def test_every_printed_key_is_produced(self):
        parsed = parse("succeeded-and-refused.jsonl")
        record = {"case": "fixture", "returncode": 0, **parsed,
                  **conformance.judge({"expect_present": ["panel"]}, parsed)}
        for key in self.PRINTED:
            with self.subTest(key=key):
                self.assertIn(key, record)

    def test_the_source_prints_exactly_these_keys(self):
        """Read the real emitter rather than trusting this list to stay in step."""
        source = (HERE / "conformance.py").read_text()
        emitter = source[source.index("print(json.dumps({k: record.get(k)"):]
        emitter = emitter[:emitter.index("flush=True")]
        printed = tuple(re.findall(r'"([a-z_]+)"', emitter))
        self.assertEqual(printed, self.PRINTED)


class FixtureProvenanceTest(unittest.TestCase):
    """The fixtures are the durable copy of untracked source traces."""

    def test_fixture_count_has_a_floor(self):
        """A glob with no floor passes with zero iterations. Emptying or renaming the
        fixtures directory would make the three tests below vacuous, and the module's
        first rule -- every fixture derives from a retained real trace -- would then be
        enforced by nothing. The count is also cross-checked against PROVENANCE.md, so
        the two authorities must agree."""
        fixtures = sorted(FIXTURES.glob("*.jsonl"))
        self.assertGreaterEqual(len(fixtures), 7)
        recorded = (FIXTURES / "PROVENANCE.md").read_text()
        for fixture in fixtures:
            self.assertIn(fixture.name, recorded)

    def test_every_fixture_is_recorded_in_provenance(self):
        recorded = (FIXTURES / "PROVENANCE.md").read_text()
        for fixture in sorted(FIXTURES.glob("*.jsonl")):
            self.assertIn(fixture.name, recorded)

    def test_every_fixture_parses_as_a_stream(self):
        for fixture in sorted(FIXTURES.glob("*.jsonl")):
            with self.subTest(fixture=fixture.name):
                self.assertGreater(conformance.parse_stream(fixture)["events"], 0)

    def test_no_fixture_leaks_a_machine_path(self):
        for fixture in sorted(FIXTURES.glob("*.jsonl")):
            with self.subTest(fixture=fixture.name):
                body = fixture.read_text()
                self.assertNotIn("/Users/damian", body)
                self.assertNotIn("/private/var/folders", body)


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Offline contract tests for the intent-separation probe.

Output-classifier fixtures are taken from the REAL producer — the recorded hook
stdout in `evidence/hooks-recovered/routing.json` — never hand-written, because a
hand-written fixture only proves the classifier agrees with the test's own idea
of the format.
"""
import json
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import intent_probe as P  # noqa: E402

# Recovered hook output from the audit, carried over as the real-producer
# fixture. Five of these tests depend on it; porting the scripts alone would
# have broken them silently.
RECORDED = HERE.parent / "fixtures/hooks-recovered/routing.json"
ABSENT_ONLY = {"expect_absent": ["panel", "design-debate"]}
PRESENT_ONLY = {"expect_present": ["panel"]}


def recorded_stdout(prompt_fragment, arm="controlled-all-skills"):
    rows = json.loads(RECORDED.read_text())
    for row in rows:
        if row["arm"] == arm and prompt_fragment in row["payload"]["prompt"]:
            return row["stdout"]
    raise AssertionError(f"no recorded row for {prompt_fragment!r} in {arm}")


class NoActivationIsNotAParseFailure(unittest.TestCase):
    def test_empty_stdout_is_recorded_as_no_activation(self):
        a = P.analyze("", ABSENT_ONLY)
        self.assertTrue(a["parsed"])
        self.assertTrue(a["no_activation"])
        self.assertEqual(a["selected"], [])
        self.assertEqual(a["violations"], [])

    def test_non_empty_garbage_is_a_parse_failure(self):
        a = P.analyze("not json at all", ABSENT_ONLY)
        self.assertFalse(a["parsed"])
        self.assertFalse(a["no_activation"])
        self.assertIsNone(a["satisfied"])

    def test_a_parse_failure_is_never_scored_as_satisfied(self):
        self.assertIsNone(P.analyze('{"unexpected": 1}', PRESENT_ONLY)["satisfied"])


class VacuityAccounting(unittest.TestCase):
    def test_absent_only_criterion_satisfied_by_nothing_is_vacuous(self):
        a = P.analyze("", ABSENT_ONLY)
        self.assertTrue(a["satisfied"])
        self.assertTrue(a["vacuous"], "a criterion nothing can violate pins nothing")

    def test_present_criterion_unmet_by_nothing_is_a_violation_not_vacuous(self):
        a = P.analyze("", PRESENT_ONLY)
        self.assertFalse(a["satisfied"])
        self.assertFalse(a["vacuous"])

    def test_real_selection_satisfying_an_absent_criterion_is_not_vacuous(self):
        a = P.analyze(recorded_stdout("review the fixes"), ABSENT_ONLY)
        self.assertTrue(a["satisfied"])
        self.assertTrue(a["selected"], "fixture must actually select something")
        self.assertFalse(a["vacuous"])


class RealProducerOutput(unittest.TestCase):
    """Fixtures below are recorded bytes from the real activation hook."""

    def setUp(self):
        self.stdout = recorded_stdout("ask codex")
        self.analysis = P.analyze(self.stdout, ABSENT_ONLY)

    def test_reproduces_the_documented_co_selection(self):
        for name in ("brainstorming", "design-debate", "panel"):
            self.assertIn(name, self.analysis["selected"])

    def test_the_documented_case_violates_the_second_opinion_criterion(self):
        self.assertFalse(self.analysis["satisfied"])
        self.assertFalse(self.analysis["vacuous"])
        self.assertEqual(sorted(self.analysis["violations"]),
                         ["expected absent: design-debate", "expected absent: panel"])

    def test_composition_chain_steps_are_not_counted_as_selections(self):
        # The chain names future-phase skills. Counting them would report the
        # injected chain as an intent match for every prompt that gets one.
        self.assertTrue(self.analysis["phase_chain_injected"])
        self.assertIn("writing-plans", self.analysis["chain_steps"])
        self.assertNotIn("writing-plans", self.analysis["selected"])
        self.assertNotIn("openspec-ship", self.analysis["selected"])

    def test_chain_detection_is_read_from_the_recorded_chain_line(self):
        self.assertEqual(self.analysis["chain"],
                         "DESIGN -> PLAN -> IMPLEMENT -> REVIEW -> SHIP -> SHIP -> SHIP")


class FrozenCases(unittest.TestCase):
    def setUp(self):
        self.spec = json.loads((HERE / "cases.json").read_text())

    def test_every_case_declares_a_contract_with_a_criterion(self):
        for case in self.spec["cases"]:
            self.assertIn(case["contract"], self.spec["criteria"], case["id"])
            self.assertIn(case["contract"], self.spec["contracts"], case["id"])

    def test_case_ids_are_unique(self):
        ids = [c["id"] for c in self.spec["cases"]]
        self.assertEqual(len(ids), len(set(ids)))

    def test_every_contract_has_at_least_one_case(self):
        covered = {c["contract"] for c in self.spec["cases"]}
        self.assertEqual(covered, set(self.spec["contracts"]))

    def test_a_negative_control_contract_is_present(self):
        self.assertIn("none", self.spec["contracts"])
        self.assertTrue([c for c in self.spec["cases"] if c["contract"] == "none"])

    def test_the_demonstrated_case_is_retained_verbatim(self):
        case = [c for c in self.spec["cases"] if c["id"] == "so-1"][0]
        rows = json.loads(RECORDED.read_text())
        prompts = {r["payload"]["prompt"] for r in rows}
        self.assertIn(case["prompt"], prompts,
                      "so-1 must match the previously recorded prompt byte for byte")


if __name__ == "__main__":
    unittest.main(verbosity=2)

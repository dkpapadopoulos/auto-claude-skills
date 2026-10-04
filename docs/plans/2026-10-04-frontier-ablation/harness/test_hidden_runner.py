#!/usr/bin/env python3
"""Tests for hidden_runner.py: the grader must never turn a non-run into a pass.
Run: python3 test_hidden_runner.py   (stdlib only; builds throwaway repos in a temp dir)."""
import json, os, subprocess, sys, tempfile, textwrap, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
RUNNER = os.path.join(HERE, "hidden_runner.py")


def grade(files, tests, expected=None):
    """files/tests: {relative path: source}. Returns the runner's JSON verdict."""
    with tempfile.TemporaryDirectory() as tmp:
        repo, tdir = os.path.join(tmp, "repo"), os.path.join(tmp, "hidden")
        for base, items in ((repo, files), (tdir, tests)):
            os.makedirs(base)
            for rel, src in items.items():
                p = os.path.join(base, rel)
                os.makedirs(os.path.dirname(p), exist_ok=True)
                with open(p, "w") as fh:
                    fh.write(textwrap.dedent(src))
        cmd = [sys.executable, RUNNER, repo, tdir] + ([str(expected)] if expected is not None else [])
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        return json.loads(p.stdout.strip().splitlines()[-1])


GOOD = {"calc.py": "def add(a, b):\n    return a + b\n"}
T_OK = {"test_h.py": """
    import unittest
    from calc import add
    class H(unittest.TestCase):
        def test_a(self): self.assertEqual(add(1, 2), 3)
        def test_b(self): self.assertEqual(add(0, 0), 0)
    """}


class GraderGuarantees(unittest.TestCase):
    def test_control_all_pass(self):
        r = grade(GOOD, T_OK, expected=2)
        self.assertTrue(r["all_pass"]); self.assertEqual(r["q"], 1.0)

    def test_control_real_failure(self):
        r = grade({"calc.py": "def add(a, b):\n    return a - b\n"}, T_OK, expected=2)
        self.assertFalse(r["all_pass"]); self.assertEqual(r["q"], 0.5)

    def test_skip_at_import_is_not_a_pass(self):
        r = grade({"calc.py": "import unittest\nraise unittest.SkipTest('nope')\n"}, T_OK)
        self.assertFalse(r["all_pass"]); self.assertEqual(r["q"], 0.0)

    def test_skipped_test_is_not_a_pass(self):
        tests = {"test_h.py": """
            import unittest
            class H(unittest.TestCase):
                @unittest.skip("later")
                def test_a(self): pass
                def test_b(self): pass
            """}
        r = grade(GOOD, tests, expected=2)
        self.assertFalse(r["all_pass"]); self.assertEqual(r["q"], 0.5)

    def test_unimportable_test_module_scores_zero(self):
        tests = dict(T_OK)
        tests["test_broken.py"] = "import does_not_exist\nimport unittest\nclass B(unittest.TestCase):\n    def test_x(self): pass\n"
        r = grade(GOOD, tests)
        self.assertFalse(r["all_pass"]); self.assertEqual(r["q"], 0.0); self.assertTrue(r["load_error"])

    def test_subtest_failures_keep_q_in_range(self):
        tests = {"test_h.py": """
            import unittest
            class H(unittest.TestCase):
                def test_many(self):
                    for i in range(5):
                        with self.subTest(i=i):
                            self.assertEqual(i, -1)
                def test_ok(self): pass
            """}
        r = grade(GOOD, tests, expected=2)
        self.assertFalse(r["all_pass"]); self.assertEqual(r["q"], 0.5)

    def test_expected_count_mismatch_scores_zero(self):
        r = grade(GOOD, T_OK, expected=5)
        self.assertFalse(r["all_pass"]); self.assertEqual(r["q"], 0.0)

    def test_exit_at_import_is_not_a_pass(self):
        r = grade({"calc.py": "import os\nos._exit(0)\n"}, T_OK, expected=2)
        self.assertFalse(r["all_pass"]); self.assertEqual(r["q"], 0.0)

    def test_zero_tests_is_not_a_pass(self):
        r = grade(GOOD, {"test_h.py": "import unittest\n"})
        self.assertFalse(r["all_pass"]); self.assertEqual(r["q"], 0.0)

    def test_unexpected_success_is_not_a_pass(self):
        tests = {"test_h.py": """
            import unittest
            class H(unittest.TestCase):
                @unittest.expectedFailure
                def test_a(self): pass
            """}
        r = grade(GOOD, tests, expected=1)
        self.assertFalse(r["all_pass"])


if __name__ == "__main__":
    unittest.main(verbosity=1)

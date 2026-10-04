#!/usr/bin/env python3
"""Run a unittest directory against a repo copy and print ONE JSON verdict line.

usage: hidden_runner.py <repo_dir> <tests_dir> [expected_test_count]

Guarantees (each pinned by test_hidden_runner.py):
- only a test that RAN and PASSED counts toward q; skips, expected-failure surprises, failures and
  errors do not;
- a test module that cannot be imported, or zero tests, scores q = 0;
- failing subTests count once, against the test that owns them, so 0 <= q <= 1;
- when expected_test_count is given and differs from the number of tests run, q = 0.

The verdict is produced by a PARENT process from the child's result file, so code under test that
exits the interpreter, or prints at exit, cannot supply or suppress it. This is still not a defence
against a subject that deliberately attacks the grader (it runs in the same account): it hardens
against accidents, not adversaries.
"""
import io, json, os, subprocess, sys, tempfile, unittest

sys.dont_write_bytecode = True
FAILED_LOAD = ("unittest.loader._FailedTest", "unittest.loader.ModuleImportFailure", "unittest.loader.LoadTestsFailure")


def owner_id(test):
    """The id of the test method that owns a result entry (a subTest reports its parent)."""
    return getattr(test, "test_case", test).id()


def child(repo, tests, out_path):
    os.chdir(repo)
    sys.path.insert(0, repo)
    v = {"run": 0, "failed_ids": [], "skipped_ids": [], "unexpected_success_ids": [], "load_error": None}
    try:
        suite = unittest.TestLoader().discover(tests, pattern="test*.py", top_level_dir=tests)
        res = unittest.TextTestRunner(stream=io.StringIO(), verbosity=0).run(suite)
        bad = sorted({owner_id(t) for t, _ in res.failures + res.errors})
        v.update(run=res.testsRun, failed_ids=bad,
                 skipped_ids=sorted({owner_id(t) for t, _ in res.skipped}),
                 unexpected_success_ids=sorted({owner_id(t) for t in res.unexpectedSuccesses}))
        broken = [i for i in bad if i.startswith(FAILED_LOAD)]
        if broken:
            v["load_error"] = "unimportable test module(s): " + ", ".join(i.rsplit(".", 1)[-1] for i in broken)[:200]
    except BaseException as e:  # SystemExit, SkipTest at import, anything: a non-run, never a pass
        v["load_error"] = repr(e)[:300]
    with open(out_path, "w") as fh:
        json.dump(v, fh)


def main():
    if len(sys.argv) >= 5 and sys.argv[1] == "--child":
        child(sys.argv[2], sys.argv[3], sys.argv[4])
        return
    repo, tests = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
    expected = int(sys.argv[3]) if len(sys.argv) > 3 else None
    out = {"run": 0, "failures": 0, "errors": 0, "skipped": 0, "unexpected_successes": 0, "passed": 0,
           "load_error": None, "failed_ids": [], "expected": expected, "q": 0.0, "all_pass": False}
    with tempfile.TemporaryDirectory() as tmp:
        res_path = os.path.join(tmp, "verdict.json")
        try:
            subprocess.run([sys.executable, os.path.abspath(__file__), "--child", repo, tests, res_path],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=240)
        except subprocess.TimeoutExpired:
            out["load_error"] = "grader timeout"
        v = None
        if os.path.exists(res_path):
            try:
                v = json.load(open(res_path))
            except Exception:
                out["load_error"] = "unreadable verdict file"
        elif not out["load_error"]:
            out["load_error"] = "no verdict: the test process exited before reporting"
    if v is not None:
        failed, skipped, surprise = set(v["failed_ids"]), set(v["skipped_ids"]), set(v["unexpected_success_ids"])
        not_passed = failed | skipped | surprise
        out.update(run=v["run"], failures=len(failed), errors=0, skipped=len(skipped),
                   unexpected_successes=len(surprise), failed_ids=sorted(not_passed), load_error=v["load_error"])
        if v["load_error"] is None and v["run"] > 0 and (expected is None or v["run"] == expected):
            passed = max(0, v["run"] - len(not_passed))
            out["passed"] = passed
            out["q"] = round(min(1.0, passed / v["run"]), 4)
            out["all_pass"] = passed == v["run"]
        elif v["load_error"] is None and expected is not None and v["run"] != expected:
            out["load_error"] = f"ran {v['run']} tests, expected {expected}"
    print(json.dumps(out))


if __name__ == "__main__":
    main()

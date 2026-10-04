#!/usr/bin/env python3
"""Run a hidden unittest directory against a repo copy. Prints one JSON line.
usage: hidden_runner.py <repo_dir> <tests_dir>"""
import sys, os, json, unittest, io
repo, tests = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
os.chdir(repo); sys.path.insert(0, repo); sys.dont_write_bytecode = True
out = {"run": 0, "failures": 0, "errors": 0, "skipped": 0, "load_error": None, "failed_ids": []}
try:
    suite = unittest.TestLoader().discover(tests, pattern="test*.py", top_level_dir=tests)
    res = unittest.TextTestRunner(stream=io.StringIO(), verbosity=0).run(suite)
    out.update(run=res.testsRun, failures=len(res.failures), errors=len(res.errors), skipped=len(res.skipped),
               failed_ids=sorted(t.id() for t, _ in res.failures + res.errors))
except BaseException as e:  # a broken import must read as a failure, never as a clean pass
    out["load_error"] = repr(e)[:300]
out["all_pass"] = bool(out["run"] > 0 and out["failures"] == 0 and out["errors"] == 0 and out["load_error"] is None)
print(json.dumps(out))

#!/usr/bin/env python3
"""Install the selected fixtures: repo/ -> tasks/<id>/repo, everything else -> vault/<id>/, then write
the frozen manifest. usage: install_tasks.py <id> [<id> ...]   (ids are directory names found under auth-*/tasks)"""
import sys, os, json, shutil, hashlib, glob, subprocess

ROOT = os.path.dirname(os.path.abspath(__file__))
VAULT = os.path.join(ROOT, "vault")


def tree_hash(d):
    h = hashlib.sha256()
    for dp, dn, fs in os.walk(d):
        dn[:] = sorted(x for x in dn if x != "__pycache__")
        for f in sorted(fs):
            if f.endswith(".pyc"):
                continue
            p = os.path.join(dp, f); h.update(os.path.relpath(p, d).encode()); h.update(b"\0"); h.update(open(p, "rb").read())
    return h.hexdigest()


def file_hash(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()


os.chmod(VAULT, 0o700)
man = {"tasks": {}, "scripts": {}, "plugins": {}, "authoring_prompt": file_hash(os.path.join(ROOT, "authoring", "AUTHORING_PROMPT.md"))}
for tid in sys.argv[1:]:
    src = glob.glob(os.path.join(ROOT, "selected", tid))
    assert len(src) == 1, (tid, src)
    src = src[0]
    for d in (os.path.join(ROOT, "tasks", tid), os.path.join(VAULT, tid)):
        shutil.rmtree(d, ignore_errors=True)
    shutil.copytree(os.path.join(src, "repo"), os.path.join(ROOT, "tasks", tid, "repo"), ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    os.makedirs(os.path.join(VAULT, tid))
    for part in ("hidden_tests", "solution", "wrong_fix"):
        shutil.copytree(os.path.join(src, part), os.path.join(VAULT, tid, part), ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    shutil.copy(os.path.join(src, "META.md"), os.path.join(VAULT, tid, "META.md"))
    man["tasks"][tid] = {"repo": tree_hash(os.path.join(ROOT, "tasks", tid, "repo")), "vault": tree_hash(os.path.join(VAULT, tid))}
for s in ("run.py", "hidden_runner.py", "analyze.py", "validate_tasks.py"):
    man["scripts"][s] = file_hash(os.path.join(ROOT, s))
for name, p in (("superpowers-6.4.2", os.path.expanduser("~/.claude/plugins/cache/superpowers-marketplace/superpowers/6.4.2")),
                ("auto-claude-skills-3.93.1", os.path.expanduser("~/.claude/plugins/cache/acsm/auto-claude-skills/3.93.1"))):
    man["plugins"][name] = tree_hash(p)
man["a2_registry"] = file_hash(os.path.join(ROOT, "homes", "A2", ".claude", ".skill-registry-cache.json"))
man["claude_cli"] = subprocess.run(["claude", "--version"], capture_output=True, text=True).stdout.strip()
json.dump(man, open(os.path.join(ROOT, "manifest.json"), "w"), indent=1, sort_keys=True)
os.chmod(VAULT, 0o000)
print("installed", len(man["tasks"]), "tasks; manifest sha256", file_hash(os.path.join(ROOT, "manifest.json")))

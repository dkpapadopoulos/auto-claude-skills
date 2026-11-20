#!/usr/bin/env python3
"""Differential fuzz of scripts/shadow-adjudicate.sh --status against an oracle.

Not part of the suite (tests/run-tests.sh runs tests/test-*.sh only). Run it by
hand after changing how the IMPLEMENT reader reads, groups, labels or withholds:

    python3 tests/fuzz/shadow-adjudicate-fuzz.py <repo root> <seed> <cases> <workdir>

About 0.2 s a case. Exit 1 when any case fails; each failing corpus, sidecar and
reader output is kept under <workdir>/fail-<seed>-<case>/.

The oracle below is a second implementation of the readout, written from the
rules and not from the reader's code. Each case is a small generated corpus and
sidecar with zero to three mutations, read with the floors lowered to 1 so a
rate can print. Three properties:

  LIVENESS  a corpus with no damaging mutation is never withheld, unless SAFETY
            requires it
  SAFETY    no rate is printed when a human-labelled record is in no episode
            the rate counts (and is not of another predicate or pre-separator),
            or when a record's latest label is not human-claimed while an
            earlier one was
  EQUALITY  a printed rate, or "insufficient data", equals the oracle's

The reader may withhold over damage the oracle would have read through; that is
not a failure. Two things the oracle copies from the reader instead of judging:
a duplicated record_id resolves to its first record, an empty `repo` counts as
no repository, and a null key field groups with an empty one. It never runs
--next, the label command or --rate-episodes, never uses the real floors, and
compares the rate and worst-case fractions only. Why this exists: four review rounds of the #454 fix each found
another input, and 2,000 cases against that reader failed 238 times.
"""
import json, os, random, re, subprocess, sys

ROOT, SEED, CASES, WORK = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
_c = subprocess.run(
    ["/bin/bash", "-c", '. "$1/hooks/lib/implement-shadow.sh"; . "$1/hooks/lib/shadow-corpus.sh"; '
     'printf "%s %s %s" "$IMPLEMENT_SHADOW_PREDICATE_VERSION" "$SHADOW_ACS_SEPARATOR" "$SHADOW_ACS_SEPARATOR_IMPLEMENT_PREDICATE"',
     "x", ROOT], capture_output=True, stdin=subprocess.DEVNULL).stdout.decode().split()
if len(_c) != 3 or _c[1] != "3.103.1" or _c[0] != _c[2]:
    # The generator's acs_version values are written around 3.103.1, and the
    # oracle applies the separator unconditionally.
    sys.exit("cannot check: predicate %s / separator %s is not what this generator models; update it" % (_c[:1], _c[1:]))
PV = int(_c[0])
SEP = (3, 103, 1)
TS_RE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z")
ACS_RE = re.compile(r"([0-9]+)\.([0-9]+)\.([0-9]+)([.+-][A-Za-z0-9.]+)?")
VERDICTS = ("true_catch", "false_block", "unknown")
rnd = random.Random(SEED)


# ---------------------------------------------------------------- oracle ----
def parse_lines(raw):
    """-> (dicts in order, count of non-blank lines that are not JSON objects)"""
    objs, bad = [], 0
    for line in raw.split(b"\n"):
        if not line.strip(b" \t\r\v\f"):
            continue
        try:
            v = json.loads(line.decode("utf-8"))
        except Exception:
            bad += 1
            continue
        if isinstance(v, dict):
            objs.append(v)
        else:
            bad += 1
    return objs, bad


def is_num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def acs_ok(r):
    v = r.get("acs_version")
    if not isinstance(v, str):
        return False
    m = ACS_RE.fullmatch(v)
    return bool(m) and (int(m.group(1)), int(m.group(2)), int(m.group(3))) >= SEP


def cls(r):
    pv = r.get("predicate_version")
    if not (is_num(pv) and pv == PV):
        return "other"
    return "cur" if acs_ok(r) else "presep"


def ts_ok(r):
    return isinstance(r.get("ts"), str) and bool(TS_RE.fullmatch(r["ts"]))


def epoch(ts):
    y, mo, d, hh, mi, ss = (int(ts[0:4]), int(ts[5:7]), int(ts[8:10]),
                            int(ts[11:13]), int(ts[14:16]), int(ts[17:19]))
    # days_from_civil accepts out-of-range fields, as the awk does
    y2 = y - 1 if mo <= 2 else y
    era = (y2 if y2 >= 0 else y2 - 399) // 400
    yoe = y2 - era * 400
    doy = (153 * (mo + (-3 if mo > 2 else 9)) + 2) // 5 + d - 1
    doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
    return (era * 146097 + doe - 719468) * 86400 + hh * 3600 + mi * 60 + ss


def valid_label(o):
    return isinstance(o.get("record_id"), str) and o.get("verdict") in VERDICTS \
        and isinstance(o.get("verdict"), str)


def oracle(corpus_raw, adj_raw):
    recs, _ = parse_lines(corpus_raw)
    adjs, _ = parse_lines(adj_raw)
    labels = [a for a in adjs if valid_label(a)]
    pop = [r for r in recs if cls(r) == "cur"]
    first = {}      # among the countable records only: an excluded twin decides nothing
    for r in pop:
        rid = r.get("record_id")
        if isinstance(rid, str) and rid not in first:
            first[rid] = r
    groups = {}
    dropped = False
    for r in pop:
        rid = r.get("record_id")
        if not isinstance(rid, str) or rid == "" or not ts_ok(r):
            continue
        key = (r.get("repo"), r.get("branch"), r.get("session_token"))
        if any(isinstance(k, (dict, list)) for k in key):
            dropped = True   # @tsv cannot print it: the record is in no episode
            continue
        key = tuple("" if k is None else ("true" if k is True else ("false" if k is False else str(k))) for k in key)
        groups.setdefault(key, []).append((epoch(r["ts"]), rid))
    episodes = []
    for key, items in groups.items():
        items.sort(key=lambda t: t[0])
        anchor, cur = None, None
        for e, rid in items:
            if anchor is None or e - anchor > 1800:
                cur = {"repo": key[0], "ids": []}
                episodes.append(cur)
                anchor = e
            cur["ids"].append(rid)
    latest = {}
    for a in labels:
        latest[a["record_id"]] = (a["verdict"], a.get("claimant") == "human")
    tc = fb = unk = 0
    repos = set()
    rate_members = set()
    for ep in episodes:
        st = set()
        for rid in ep["ids"]:
            r = first[rid]  # a string id in a group is always in `first`
            wb = r.get("would_block")
            if not isinstance(wb, bool):
                st.add("bad")
            elif wb is False:
                st.add("no")
            elif r.get("advisory_emitted") is False:
                st.add("silent")
            else:
                st.add("yes")
        if "yes" not in st:
            continue
        rate_members.update(ep["ids"])
        v, human = "unlabeled", False
        for rid in ep["ids"]:
            if rid not in latest:
                continue
            rv, rh = latest[rid]
            human = human or rh
            if rv == "false_block":
                v = rv
            elif rv == "unknown" and v != "false_block":
                v = rv
            elif rv == "true_catch" and v == "unlabeled":
                v = rv
        if v == "unlabeled" or not human:
            continue
        if ep["repo"] != "":   # the reader counts repos as non-empty lines
            repos.add(ep["repo"])
        if v == "false_block":
            fb += 1
        elif v == "unknown":
            unk += 1
        else:
            tc += 1
    den = tc + fb
    result = "insufficient" if (den < 1 or len(repos) < 1) else "%d/%d %d/%d" % (fb, den, fb + unk, den + unk)
    must = dropped
    humans = {a["record_id"] for a in labels if a.get("claimant") == "human"}
    if any(not latest[rid][1] and any(cls(r) == "cur" for r in recs if r.get("record_id") == rid) for rid in humans):
        must = True     # an agent's later line replaced what a human said about an adjudicable record
    for rid in humans:
        if rid in rate_members:
            continue
        cl = {cls(r) for r in recs if r.get("record_id") == rid}
        if not cl or "cur" in cl:
            must = True
    return result, must


# ------------------------------------------------------------- generator ----
CLEAN_IDS = ["a3f09b1c", "12345678", "1e234567", "00000100", "100", "1e2", "0x10", "16",
             "7d2e", "deadbeef", "0e0", "0", "00", "9c1b77aa", "5f5f5f5f", "1.0", "1"]
WEIRD_IDS = ["has space", "a,b", "*", "tab\there", "back\\slash", "nl\nid", "", " lead", "é", "-n", "a b,c"]


def mkrec(rid, _i):
    wb = rnd.random() < 0.8
    r = {"record_id": rid,
         "ts": "2026-11-18T%02d:%02d:00Z" % (10 + rnd.randrange(3), rnd.randrange(60)),
         "repo": rnd.choice(["/repo/A"] if CLUSTER else ["/repo/A", "/repo/B"]),
         "branch": rnd.choice(["feat/x"] if CLUSTER else ["feat/x", "feat/y", ""]),
         "session_token": rnd.choice(["tok1"] if CLUSTER else ["tok1", "tok2", "100", "1e2"]),
         "predicate_version": PV, "acs_version": rnd.choice(["3.103.1", "3.104.0", "4.0.0-dev"]),
         "action": "push", "would_block": wb, "schema_version": 5}
    if rnd.random() < 0.7:
        r["advisory_emitted"] = rnd.random() < 0.85
    return r


def mklabel(rid, claimant=None):
    return {"schema_version": 1, "record_id": rid, "ts": "2026-11-19T10:00:00Z",
            "verdict": rnd.choice(VERDICTS), "reason": "f",
            "claimant": claimant or rnd.choice(["human", "human", "agent"])}


def offerable(r):
    return ts_ok(r) and r.get("would_block") is True and r.get("advisory_emitted") is not False \
        and cls(r) == "cur"


def dump(o):
    return json.dumps(o, ensure_ascii=rnd.random() < 0.5).encode()


CLUSTER = False


def gen():
    global CLUSTER
    CLUSTER = rnd.random() < 0.35   # one key, so episodes hold several records
    n = rnd.randrange(1, 8)
    ids = rnd.sample(CLEAN_IDS, n)
    recs = [mkrec(rid, i) for i, rid in enumerate(ids)]
    # legit history: a retired predicate and pre-separator records, some labelled
    for r in recs:
        x = rnd.random()
        if x < 0.08:
            r["predicate_version"] = PV - 1
        elif x < 0.16:
            r["acs_version"] = rnd.choice(["3.99.9", "", "3.103.0"])
    labs = []
    for r in recs:
        if offerable(r) and rnd.random() < 0.7:
            for _ in range(rnd.choice([1, 1, 2, 3])):
                labs.append(mklabel(r.get("record_id")))
        elif cls(r) != "cur" and rnd.random() < 0.4:
            labs.append(mklabel(r.get("record_id"), "human"))
    clines = [dump(r) for r in recs]
    alines = [dump(a) for a in labs]
    clean = True
    notes = []
    for _ in range(rnd.choice([0, 0, 1, 1, 2, 3])):
        m = rnd.randrange(24)
        notes.append(m)
        tgt = rnd.randrange(len(clines))
        r = json.loads(clines[tgt]) if clines[tgt].startswith(b"{") and clines[tgt].endswith(b"}") else None
        if m == 0:      # benign: blank / whitespace lines
            clines.insert(rnd.randrange(len(clines) + 1), rnd.choice([b"", b"   ", b"\t", b"\r"]))
            alines.insert(rnd.randrange(len(alines) + 1), rnd.choice([b"", b"  ", b"\t\r"]))
            continue
        before = (list(clines), list(alines))
        if m == 1:
            clines[tgt] = clines[tgt][: max(1, len(clines[tgt]) - rnd.randrange(1, 40))]
        elif m == 2:
            del clines[tgt]
            if not clines:
                clines.append(dump(mkrec("zz", 0)))
        elif m == 3 and alines:
            i = rnd.randrange(len(alines)); alines[i] = alines[i][: max(1, len(alines[i]) - rnd.randrange(1, 30))]
        elif m == 4 and alines:
            del alines[rnd.randrange(len(alines))]
        elif m == 5:
            alines.insert(rnd.randrange(len(alines) + 1), rnd.choice(
                [b"[1]", b'"x"', b"{}", b"null", b"5", b"\xff\xfe",
                 dump({"record_id": rnd.choice(CLEAN_IDS)}),
                 dump({"record_id": rnd.choice(CLEAN_IDS), "verdict": "flase_block", "claimant": "human"}),
                 dump({"record_id": 5, "verdict": "true_catch", "claimant": "human"})]))
        elif m == 6:
            clines.insert(rnd.randrange(len(clines) + 1), rnd.choice([b"[1]", b'"x"', b"null", b"5", b"\xff\xfe", b"{}", b"true"]))
        elif r is None:
            pass
        elif m == 7:
            r["would_block"] = rnd.choice([False, "true", None, 1]); clines[tgt] = dump(r)
        elif m == 8:
            r.pop("would_block", None); clines[tgt] = dump(r)
        elif m == 9:
            r["ts"] = rnd.choice(["garbage", str(r.get("ts")) + "\n", 5, None, "", "2026-11-18 10:00:00Z", " " + str(r.get("ts"))]); clines[tgt] = dump(r)
        elif m == 10:
            r["predicate_version"] = rnd.choice([PV - 1, str(PV), None, PV + 1, float(PV), True]); clines[tgt] = dump(r)
        elif m == 11:
            r["acs_version"] = rnd.choice(["3.99.9", None, 3, "3.104.0\n", "v3.104.0"]); clines[tgt] = dump(r)
        elif m == 12:
            r[rnd.choice(["branch", "repo", "session_token"])] = rnd.choice([{"a": 1}, [1], None, 5, True]); clines[tgt] = dump(r)
        elif m == 13:   # weird id, with or without a label that follows it
            old = r.get("record_id"); r["record_id"] = rnd.choice(WEIRD_IDS + [5, None, ["x"], {"a": 1}]); clines[tgt] = dump(r)
            if isinstance(r.get("record_id"), str) and rnd.random() < 0.7:
                alines = [dump(dict(json.loads(a), record_id=r.get("record_id")))
                          if a.startswith(b"{") and a.endswith(b"}") and json.loads(a).get("record_id") == old else a
                          for a in alines]
        elif m == 14:   # duplicate record line, maybe altered
            d = dict(r)
            if rnd.random() < 0.6:
                d["would_block"] = not bool(d.get("would_block"))
            if rnd.random() < 0.5:
                d["session_token"] = "dup"
            clines.insert(rnd.randrange(len(clines) + 1), dump(d))
        elif m == 15:   # hand-written human label on any record, any id
            alines.append(dump(mklabel(rnd.choice([str(r.get("record_id")), "nosuch"] + CLEAN_IDS), "human")))
        elif m == 16:   # numeric twin: a record whose id equals another's as a number
            twins = {"100": "1e2", "1e2": "100", "0x10": "16", "16": "0x10", "0": "00", "00": "0", "1": "1.0", "1.0": "1", "0e0": "0"}
            t = twins.get(r.get("record_id")) if isinstance(r.get("record_id"), str) else None
            if t:
                d = mkrec(t, 0); clines.append(dump(d))
        elif m == 17:
            alines.append(dump(dict(mklabel(str(r.get("record_id"))), claimant=rnd.choice([["human"], None, 5, "Human", {"a": 1}]))))
        elif m == 18:
            r["advisory_emitted"] = rnd.choice([False, "false", None, 0]); clines[tgt] = dump(r)
        elif m == 19:   # label with weird id
            alines.append(dump(mklabel(rnd.choice(WEIRD_IDS), "human")))
        elif m == 20:
            clines[tgt] = clines[tgt] + rnd.choice([b" ", b"\r", b"  \t"])
        elif m == 21:
            r["ts"] = rnd.choice(["2026-13-45T99:99:99Z", "0000-00-00T00:00:00Z", "9999-12-31T23:59:59Z"]); clines[tgt] = dump(r)
        elif m == 22:
            clines[tgt] = b"  " + clines[tgt]
        elif m == 23:
            alines.append(dump(dict(mklabel(str(r.get("record_id")), "human"), verdict=rnd.choice(["TRUE_CATCH", None, 1, ["false_block"]]))))
        if (clines, alines) != before:
            clean = False
    return b"\n".join(clines) + b"\n", (b"\n".join(alines) + b"\n") if alines else b"", clean, notes


# --------------------------------------------------------------- harness ----
RUN = r'''. "$1/scripts/shadow-adjudicate.sh" --source-only; FLOOR_EPISODES=1; FLOOR_REPOS=1; cmd_status'''


def reader(cdir):
    env = dict(os.environ, IMPLEMENT_SHADOW_LOG=cdir + "/c.jsonl", IMPLEMENT_ADJUDICATION_LOG=cdir + "/a.jsonl",
               LANG="en_US.UTF-8")
    env.pop("LC_ALL", None)
    out = subprocess.run(["/bin/bash", "-c", RUN, "x", ROOT], env=env, stdin=subprocess.DEVNULL,
                         capture_output=True, cwd=cdir).stdout.decode("utf-8", "replace")
    rate = worst = None
    for line in out.split("\n"):
        if line.startswith("  rate "):
            rate = line.split(None, 1)[1]
        if line.startswith("  worst case "):
            worst = line.split()[2]
    if rate is None:
        return "NORATE", out
    if rate.startswith("cannot check"):
        return "withheld", out
    if rate.startswith("insufficient"):
        return "insufficient", out
    return "%s %s" % (rate.split()[0], worst), out


fails = 0
stats = {"withheld": 0, "printed": 0, "insufficient": 0, "clean": 0, "must": 0}
for i in range(CASES):
    c, a, clean, notes = gen()
    d = "%s/case" % WORK
    os.makedirs(d, exist_ok=True)
    open(d + "/c.jsonl", "wb").write(c)
    open(d + "/a.jsonl", "wb").write(a)
    orc = oracle(c, a)
    got, out = reader(d)
    kind = None
    if True:
        want, must = orc
        stats["clean"] += clean
        stats["must"] += must
        if got == "withheld":
            stats["withheld"] += 1
            if clean and not must:   # an agent relabelling a human's record is a clean sequence that withholds
                kind = "LIVENESS"
        elif must and got != "insufficient":   # "insufficient data" prints no rate either
            kind = "SAFETY"
        elif must:
            stats["insufficient"] += 1
        elif got != want:
            kind = "EQUALITY"
        else:
            stats["printed" if got != "insufficient" else "insufficient"] += 1
    if kind:
        fails += 1
        keep = "%s/fail-%d-%d" % (WORK, SEED, i)
        os.makedirs(keep, exist_ok=True)
        open(keep + "/c.jsonl", "wb").write(c)
        open(keep + "/a.jsonl", "wb").write(a)
        open(keep + "/out.txt", "w").write("%s\nmutations=%s\noracle=%s\nreader=%s\n\n%s" % (kind, notes, orc, got, out))
        print("FAIL %s seed=%d case=%d mutations=%s oracle=%s reader=%s" % (kind, SEED, i, notes, orc, got))
print("seed=%d cases=%d fails=%d %s" % (SEED, CASES, fails, stats))
sys.exit(1 if fails else 0)

#!/usr/bin/env python3
"""Replay the 183 field prompts through the CURRENT installed activation hook (3.93.1), each in a
fresh HOME holding a copy of the real registry, and report whether the same MUST INVOKE recurs.
Counts only."""
import json, os, re, subprocess, tempfile, shutil, collections
ACS=os.path.expanduser("~/.claude/plugins/cache/acsm/auto-claude-skills/3.93.1")
REG="reg-real-copy.json"
MUST=re.compile(r"\| ([a-z0-9][a-z0-9-]*) MUST INVOKE")
full={json.loads(l)["id"]:json.loads(l) for l in open("label_full.jsonl")}
l1={json.loads(l)["id"]:json.loads(l)["label"] for l in open("label_out.jsonl")}
l2={json.loads(l)["id"]:json.loads(l)["label"] for l in open("label_out_2.jsonl")}
res=collections.Counter(); bytes_=[]; rcbad=0; empty=0
def run(prompt):
    h=tempfile.mkdtemp(); os.makedirs(h+"/.claude"); shutil.copy(REG,h+"/.claude/.skill-registry-cache.json")
    try:
        p=subprocess.run(["/bin/bash",ACS+"/hooks/skill-activation-hook.sh"],input=json.dumps({"prompt":prompt,"transcript_path":h+"/.claude/a.jsonl"}),
                         capture_output=True,text=True,timeout=30,env=dict(os.environ,HOME=h,CLAUDE_PLUGIN_ROOT=ACS))
        try: ctx=(json.loads(p.stdout) if p.stdout.strip() else {}).get("hookSpecificOutput",{}).get("additionalContext","")
        except Exception: ctx=""
        return p.returncode, ctx
    finally: shutil.rmtree(h,ignore_errors=True)
# positive/negative controls so a dead probe cannot read as "nothing routes"
rc,ctx=run("debug this failing test in the parser module"); print("control+ (debug prompt) MUST:", MUST.findall(ctx), "bytes", len(ctx.encode()), "rc", rc)
rc,ctx=run("what time is it in tokyo"); print("control- (unrelated) MUST:", MUST.findall(ctx), "bytes", len(ctx.encode()))
for i,r in full.items():
    rc,ctx=run(r["full"])
    if rc!=0: rcbad+=1
    if not ctx: empty+=1
    bytes_.append(len(ctx.encode()))
    must=set(MUST.findall(ctx))
    cons = "APPROPRIATE" if l1[i]==l2[i]=="APPROPRIATE" else "NOT_APPROPRIATE" if l1[i]==l2[i]=="NOT_APPROPRIATE" else "other"
    res[(cons, "same_skill_MUST" if r["skill"] in must else "other_MUST" if must else "block_no_MUST" if "SKILL ACTIVATION" in ctx else "silent")]+=1
print("nonzero rc:", rcbad, "silent:", empty, "mean bytes:", sum(bytes_)//len(bytes_))
for c in ("APPROPRIATE","NOT_APPROPRIATE","other"):
    print(c, {k[1]:v for k,v in sorted(res.items()) if k[0]==c})

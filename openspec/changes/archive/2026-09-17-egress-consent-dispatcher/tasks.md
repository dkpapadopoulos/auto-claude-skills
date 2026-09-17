# Tasks: Egress Consent Dispatcher

> Checkpoints reference branch commits. After squash-merge they are typically
> recoverable only via the feature's GitHub PR (`gh pr view <N> --json commits`)
> — plain clones and forks do not fetch PR refs.

## Completed

- [x] 0.1 Baseline and commit the 222-prompt negative routing corpus [checkpoint: 5bce029]
- [x] 1.1 Strict own-session resolver with no singleton fallback [checkpoint: addfee7]
- [x] 2.1 Shared egress-consent lib (digest, validators, paths, atomic write) [checkpoint: 0e94396]
- [x] 3.1 Ask hook: deny forged or malformed consent questions, snapshot clean asks
- [x] 4.1 Receipt hook: single-use receipt from a clean, approved, digest-matched answer [checkpoint: 39aa7d5]
- [x] 5.1 `consult-dispatch.sh` prepare/send with CANNOT VERIFY vs NOT APPROVED [checkpoint: 14e2251]
- [x] 6.1 Observer: payload-first, local companion verbs silent, bypass shadow corpus [checkpoint: 86d04fd]
- [x] 7.1 Wire hooks, GC egress state, retire the model-run recorder [checkpoint: 164ca1a]
- [x] 8.1 Route panel and second-opinion through the dispatcher [checkpoint: 5ccc038]
- [x] 9.1 Record the boundary in CLAUDE.md [checkpoint: d1b9a75]
- [x] 10.1 Live end-to-end run (approve, decline, deny-before-dialog, `Other` measurement)
- [x] 11.1 Review rounds 1–5 and Codex adversarial review; every finding reproduced and fixed
- [x] 11.2 project-verification clean at the final head

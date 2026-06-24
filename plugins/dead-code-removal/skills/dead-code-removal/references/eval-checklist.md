# Cleanup Run Evaluation Checklist

> **status: ACTIVE**. This is the current skill's post-hoc scoring contract.
> Purpose: after a cleanup batch finishes, do a unified retrospective on result quality and process quality; write the output into `iterations/{index}-{module-or-batch-name}.md`.
> This is not the source of execution-time rules. The execution-time contracts are `agent-orchestration-workflow.md`, `removal-list-template.md`, `blind-review-prompt.md`, and `acceptance-criteria.md`.

---

## 1. Evaluation Inputs

By default this table evaluates the following artifacts jointly:

1. `orchestration-proof.md` (required under validation mode)
2. `supervisor-board.md`
3. `review-manifest.md`
4. `execution-result.md`
5. `blind-review-result.md`
6. `iterations/{index}-{module-or-batch-name}.md`

If a particular artifact is missing, do not skip scoring; mark the corresponding item as failed and write down the reason for the absence.

---

## 2. Scoring Dimensions

Total 32 points across 5 dimensions:

1. **Correctness** — 8 points
2. **Completeness** — 8 points
3. **Isolation / role discipline** — 7 points
4. **Contract Quality / artifact and process contract quality** — 7 points
5. **Metrics / metric completeness** — 2 points

Recommended conclusions:

- `30–32`: a clean success, can serve as a high-quality template
- `26–29`: passed, but still has process or artifact gaps
- `20–25`: barely passed, must fix the process in the next round
- `<20`: should not be treated as a reusable process; roll back or restructure the contract

Hard gates:

- If any "fatal item" fails, this round may not be marked "a clean success"
- Fatal items include: `C1`, `C2`, `I1`, `I2`, `Q1`, `M1`

---

## 3. Correctness (8)

> Focus on "did we delete the wrong thing, break something, or delete in a way that produces side effects."

| # | Check item | Method | Points | Result |
|---|---|---|---|---|
| C1 | After deletion `build-check.sh` passes, or only the explicitly listed pre-existing failures remain | cross-check `execution-result.md` against base | 2 | |
| C2 | `vet-check.sh` has no new issues, or new issues have been clearly attributed to pre-existing | cross-check `execution-result.md` | 1 | |
| C3 | No symbol still referenced by live code was wrongly deleted | look at build/vet/grep evidence and blind review findings | 2 | |
| C4 | No entry point, registration, consumer, cron, or feature flag still triggered by runtime roots was wrongly deleted | cross-check manifest + blind review | 1 | |
| C5 | No constant / enum / init side effect required for historical compatibility was wrongly deleted | cross-check boundary retains and blind review | 1 | |
| C6 | If shared code is involved, the behavior of still-retained services is not broken, or it is clearly explained why this can be ruled N/A | cross-check acceptance V20–V23 / notes | 1 | |

Examples of fatal failure:

- build fails and the failure point is related to this round's deletion
- the blind reviewer clearly points to evidence of an erroneous deletion
- after deletion there is still a runtime root pointing at a deleted object

---

## 4. Completeness (8)

> Focus on "did we delete too little, leave orphans behind, or fail to clean up non-code residue."

| # | Check item | Method | Points | Result |
|---|---|---|---|---|
| P1 | The manifest covers entry points, the core call chain, and the deletion set | cross-check `review-manifest.md` | 1 | |
| P2 | The manifest covers boundary retains, and each one has a live referrer or a clear retention reason | cross-check `review-manifest.md` | 1 | |
| P3 | Non-code residue check is complete: config, tests, Dockerfile/Makefile, CI mapping, topic, Redis key, env, etc. | cross-check manifest + execution result | 1 | |
| P4 | Residual greps (V7–V19) results are empty or only contain reasonable doc retentions | cross-check `execution-result.md` | 2 | |
| P5 | No orphan symbol referenced only by to-be-deleted code remains | look at blind review / grep / notes | 1 | |
| P6 | No "commented out but not deleted" zombie code was left behind | look at diff and execution notes | 1 | |
| P7 | The `.code-removal/` metadata is synced and does not pollute later sessions | cross-check execution result | 1 | |

---

## 5. Isolation / role discipline (7)

> Focus on "did it really run under the 3-subagent / 4-artifact model, rather than nominal multi-role but actually a single-threaded large context."

| # | Check item | Method | Points | Result |
|---|---|---|---|---|
| I1 | `Supervisor / Executor / Blind Reviewer` are independent agents, not the same context play-acting | cross-check `orchestration-proof.md` / run record / notes | 2 | |
| I2 | All three roles were created with `fork_context=false`; the main thread did not hand the full history to any role | cross-check `orchestration-proof.md` / run record / notes | 2 | |
| I3 | The main thread only does routing and the Human Gate; it does not directly hold business judgment or ghost-write role conclusions | cross-check notes and artifact ownership | 1 | |
| I4 | Roles flow only through permitted artifacts; no reasoning drafts, expected conclusions, or suspicion points leaked | cross-check prompts / notes | 1 | |
| I5 | Role reuse follows the contract: the same role may continue running; the same agent is not reused across roles | cross-check `orchestration-proof.md` / run record / notes | 1 | |

Examples of fatal failure:

- `Blind Reviewer` is not an independent agent
- `fork_context=true` carried the parent thread's history to the reviewer
- the main thread / supervisor ghost-wrote the blind review conclusion

---

## 6. Contract Quality / artifact and process contract quality (7)

> Focus on "are the artifacts sufficient to support independent roles, and can the process be re-run and audited."

| # | Check item | Method | Points | Result |
|---|---|---|---|---|
| Q1 | `review-manifest.md` is sufficient to define the cleanup contract: scope, retention boundary, acceptance criteria, and risk constraints are clear | cross-check manifest | 2 | |
| Q2 | Manifest ownership is clear: produced and owned by the `Supervisor`; the `Executor` only proposes deltas | cross-check artifact and notes | 1 | |
| Q3 | `execution-result.md` sufficiently describes the actual execution, acceptance results, and deviations, so other roles can re-check from it | cross-check execution result | 1 | |
| Q4 | `blind-review-result.md` can clearly distinguish "manifest problem" from "execution problem" | cross-check blind review result | 1 | |
| Q5 | `supervisor-board.md` sufficiently supports state-machine routing; `Next / Blocked / Needs Human` contains no vague blame-shifting phrasing | cross-check supervisor board | 1 | |
| Q6 | The iteration record feeds this round's defects back into the skill, rather than only recording the code result | cross-check iteration | 1 | |
| Q7 | Under validation mode a complete `orchestration-proof.md` exists, able to prove agents, handoff, canary, disagreement-path | cross-check orchestration proof | 0* | |

Examples of fatal failure:

- the manifest cannot support an independent executor doing the work
- the blind review conclusion cannot tell whether to send the work back to the supervisor or the executor
- a key artifact is missing, making the process non-auditable

`Q7` is not scored separately, but if it fails under validation mode it should be treated as a major contract-quality gap.

---

## 6.5 Metrics / metric completeness (2)

> Focus on "did this round produce performance data that can be aggregated in the future."

| # | Check item | Method | Points | Result |
|---|---|---|---|---|
| M1 | `runs/{date}-{batch}/metrics.md` exists and all 5 sections (durations / tokens / code_delta / acceptance / blind_review_findings) have complete fields | cross-check the metrics template | 1 | |
| M2 | Metrics data is credible: `durations` come from the Agent tool result `duration_ms`, `tokens` come from `usage.*`, and the `blind_review_findings` count matches the finding-ID list in `blind-review-result.md` | cross-check against tool result / blind review | 1 | |

Examples of fatal failure:

- `metrics.md` is missing or has only a title (M1 fail)
- `durations` is self-reported by the subagent (the subagent has no credible wall-clock)
- the finding count does not match the blind review (self-deceiving data)

`M1` is a fatal item — this round may not be marked "a clean success."

---

## 7. Final Summary Format

Write the scoring result into the "Evaluation result" section of the iteration, in the following format:

```text
Correctness:      {passed}/8
Completeness:     {passed}/8
Isolation:        {passed}/7
Contract Quality: {passed}/7
Metrics:          {passed}/2
Total:            {passed}/32

Conclusion: [clean success | passed but process needs work | barely passed | should not reuse current process]
Fatal checks:
- C1: pass/fail
- C2: pass/fail
- I1: pass/fail
- I2: pass/fail
- Q1: pass/fail
- M1: pass/fail
```

---

## 8. Mandatory Retrospective Items

Regardless of the total score, every iteration must answer at least these 5 questions:

1. What was the risk point closest to an erroneous or missed deletion this round
2. Who ultimately caught that risk: Supervisor / Executor / Blind Reviewer / Human
3. If you removed a particular artifact, which step would be the first to break this round
4. What is the contract change most worth hardening into the skill this round
5. If the next round handles a similar module, which check should be moved earlier

# Runtime Validation Checklist

> **status: ACTIVE**. The purpose is not to check "whether the code was deleted correctly," but to check "whether the multi-role process really executed as designed."
> Until the skill is proven stable, it is recommended to run this checklist on every real batch; at least the first 3 rounds must enable `validation mode`.

---

## 1. Goal

This checklist validates 4 things:

1. Whether the roles really are independent agents, rather than the main thread play-acting
2. Whether the input boundary is strictly controlled by the main thread
3. Whether the blind review has real refutation capability, rather than polite restatement
4. Whether the artifact chain is sufficient to support re-runs, auditing, and accountability

---

## 2. Validation Mode Required Artifacts

Beyond the usual 4 artifacts, the following must also exist:

1. `orchestration-proof.md`
2. `iteration.md`

Recommended directory:

```text
.code-removal/runs/{date}-{batch-name}/
├── orchestration-proof.md
├── supervisor-board.md
├── review-manifest.md
├── execution-result.md
└── blind-review-result.md
```

---

## 3. Pre-Run Checks

- [ ] This round is marked as `validation mode`
- [ ] The main thread plans to `spawn_agent(..., fork_context=false)` for each of the 3 roles
- [ ] The input whitelist for the 3 roles has been determined
- [ ] `orchestration-proof.md` has been prepared

---

## 4. During-Run Checks

### 4.1 Role Identity

- [ ] The agent IDs of `Supervisor`, `Executor`, `Blind Reviewer` are all distinct
- [ ] The same agent is not reused across roles
- [ ] `send_input` is used only when "continuing the same role"

### 4.2 Input Discipline

- [ ] The main thread did not pass the full thread history to any role
- [ ] `Supervisor` only received its whitelisted input
- [ ] `Executor` only received its whitelisted input
- [ ] `Blind Reviewer` only received its whitelisted input
- [ ] The `Executor` prompt explicitly states "for acceptance, prefer calling `build-check.sh` / `vet-check.sh` / `module-gone-check.sh` / `tidy-check.sh`"
- [ ] The `Executor` prompt explicitly forbids composite Bash acceptance (e.g. `go build | grep | tail ; echo ...`)

### 4.3 Artifact Ownership

- [ ] `supervisor-board.md` is produced by the Supervisor
- [ ] `review-manifest.md` is created and owned by the Supervisor
- [ ] `execution-result.md` is produced by the Executor
- [ ] `blind-review-result.md` is produced by the Blind Reviewer
- [ ] The main thread did not ghost-write any role's conclusion

### 4.4 Output Consumption (output-consumption chain)

- [ ] Before routing to the Executor, the main thread has read the routing state in `supervisor-board.md` + the boundary in `review-manifest.md`
- [ ] Before routing to the Blind Reviewer, the main thread has read the acceptance result in `execution-result.md`
- [ ] Before routing to the Human Gate, the main thread has read the explicit conclusion in `blind-review-result.md`
- [ ] Every state transition can point back to a specific artifact section in the `orchestration-proof.md` handoff segment or the routing log (not just "Supervisor done")
- [ ] No step-skipping: passing the Human Gate / Done without first reading `blind-review-result.md` counts as a contract fail

### 4.5 Metrics Completeness

- [ ] `runs/{date}-{batch}/metrics.md` exists and is filled in per the metrics template
- [ ] The `durations` section is non-empty: supervisor / executor / blind_reviewer / human_overhead all have values (may be 0 but may not be omitted)
- [ ] The `tokens` section is non-empty: each role's input / output / cache_read all have numeric values
- [ ] The `code_delta` section: `files_changed` / `lines_added` / `lines_removed` are filled in, consistent with `git diff --stat`
- [ ] The `acceptance` section: the pass/fail of build-check.sh / vet-check.sh / tidy-check.sh are each recorded
- [ ] The `blind_review_findings` section: counted by severity (blocker/major/nit), and references the finding IDs (F-01, etc.)
- [ ] The Metrics data source is the Agent tool result (`duration_ms` + `usage.*`), not self-reported by the subagent
- [ ] **Not writing `metrics.md` counts as a batch contract fail** — the main thread may not declare the batch complete

---

## 5. Adversarial Validation

### 5.1 Canary Check

Purpose: verify that unauthorized information does not naturally spread to downstream roles.

How to do it:

1. Place a canary string in the main thread or in a supervisor-private note that **should only be known to upstream**
2. Do not pass that note as a permitted artifact to downstream roles
3. After the run completes, check:
   - `execution-result.md`
   - `blind-review-result.md`
   - the iteration

Pass criterion:

- [ ] The canary string did not appear in any downstream artifact

Notes:

- This is "leak detection," not an absolute security proof
- If the canary leaks, treat it as a contract fail

### 5.2 Disagreement-Path Check

Purpose: verify that the blind reviewer will refute, rather than follow the manifest.

How to do it:

1. Prefer to rely on genuine natural discovery
2. If this round's target is too simple, you may deliberately pick a module more likely to expose boundary problems, or deliberately retain a slightly suspicious point for the reviewer to examine

Pass criterion:

- [ ] The reviewer produces at least one substantive finding, or clearly writes out a complete refutation chain stating "no evidence found that could overturn the manifest"
- [ ] If the reviewer requests `Revise manifest` / `Split batch` / `Block`, the main thread can route correctly

Notes:

- Before the skill reaches stable, there must be at least 1 round of successful disagreement-path evidence

---

## 6. Post-Run Checks

- [ ] `orchestration-proof.md` has been fully filled in
- [ ] The `Isolation` and `Contract Quality` in `eval-checklist.md` can be scored from it
- [ ] The most important process defect of this round has been recorded in the iteration
- [ ] If validation fails, this round may not serve as a proof sample for "the multi-role process has been validated"

---

## 7. Definition of Passing

This round may claim "process validation passed" only if it simultaneously satisfies the following:

1. All contract checks in `orchestration-proof.md` pass
2. The Canary check passes
3. The blind review was not ghost-written by the main thread / supervisor
4. The `Isolation` dimension of `eval-checklist.md` has no fatal failure
5. The `Contract Quality` of `eval-checklist.md` has no `Q1` fatal failure

---

## 8. When You May Exit Validation Mode

It is recommended to lower validation mode from "default mandatory" to "enable on demand" only after the following are satisfied:

1. 3 consecutive real-module runs pass this checklist
2. At least 1 round has disagreement-path evidence where the reviewer successfully challenged the manifest
3. No canary leak occurred
4. No main-thread ghost-writing of a role's conclusion occurred

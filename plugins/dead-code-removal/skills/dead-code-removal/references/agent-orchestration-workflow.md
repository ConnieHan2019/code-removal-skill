# Multi-Agent Orchestration Workflow

> Goal: upgrade the dead-code-removal skill from "a single agent doing things by a procedure" to "3 fixed roles collaborating through artifacts".
> The point is not to have more agents chatting together, but to have the roles hand off only through the **minimum necessary artifacts**, reducing context pollution.
> **Current mechanism layer**: Claude Code Agent SDK (`spawn_agent` / `send_input` / `wait_agent`).
> **If orchestration is externalized in the future**: the contract spec lives in `references/drafts/langgraph-implementation-design.md` (kept as a contract design draft; it currently does not depend on any LangGraph code).

---

## 1. Roles and the Main Thread

### Main Thread

The main thread is not any of `Supervisor / Executor / Blind Reviewer`.

Responsibilities:

1. Receive user input
2. Create / reuse / close role agents
3. Route artifacts according to the state machine
4. Handle the Human Gate and the final report

Constraints:

1. Does not own business judgment
2. Does not directly define the cleanup boundary
3. Does not pass its own full history to any role

State it holds (must be preserved across phases, none can be missing):

1. `batch_id` and the `runs/{date}-{batch-name}/` directory path
2. Current state machine position (see §6)
3. Role registry: for each agent ever spawned, its `role` / `agent_id` / `spawned_at` / `fork_context` / `status`
4. Latest artifact paths: `supervisor-board.md` / `review-manifest.md` / `execution-result.md` / `blind-review-result.md` / `orchestration-proof.md`
5. Human Gate decision: `approve` / `reject` / `revise` + timestamp + `approved_sha`

Does not hold (prohibited from holding across phases even if obtainable):

- The full reasoning history of any role
- Any role's working drafts
- Cross-batch business conclusions

In other words, the main thread holds the **process state**, not the **in-role mental state**.

### Supervisor

Responsibilities:

1. Read the cleanup backlog
2. Produce `supervisor-board.md`
3. Create and own `review-manifest.md`
4. Decide which objects are:
   - `Ready`
   - `Needs Closure`
   - `Blocked (external refs)`
   - `Blocked (refactor needed)`
   - `Needs Human`
5. Escalate to the user only after passing the `Escalation Gate`
6. Decide whether to adopt revision suggestions from the `Executor` / `Blind Reviewer`

Artifacts:

- `supervisor-board.md`
- `review-manifest.md`

### Executor

Responsibilities:

1. Execute Step 0–6 based on the effective `review-manifest.md`
2. If the manifest is found to be inconsistent with code reality, submit a revision suggestion
3. Produce the execution result and acceptance evidence
4. Does not directly rewrite the cleanup contract boundary

Hard execution rules:

1. Acceptance actions must prefer the fixed scripts:
   - `scripts/build-check.sh`
   - `scripts/vet-check.sh`
   - `scripts/module-gone-check.sh <module-dir>`
   - `scripts/tidy-check.sh`
2. Do not chain `go build`, `go vet`, `tee`, `echo`, `ls`, `head`, `tail` into a single compound Bash command
3. Do not write ad-hoc prefixes like `GOCACHE=$TMPDIR...`, `GOMODCACHE=...`, `GOPROXY=...`, `GOFLAGS=...` inside Claude's Bash calls
4. To filter pre-existing noise, run the script first, then read the script-generated log file separately; do not append `| grep -v ... | tail -N` to the tail of an execution command

Artifacts:

- `execution-result.md`
- `iteration.md`

### Blind Reviewer

Responsibilities:

1. Perform an adversarial / refutation-style review based only on the established artifacts
2. Re-run the 7 categories of indirect-reference scans
3. Judge whether the manifest holds up and whether the execution result deviates from the manifest
4. Produce the `Blind Review Result`

Artifacts:

- `blind-review-result.md`

---

## 2. Context Boundaries

Core principles:

1. The three roles must run in **independent contexts**
2. `fork_context=false` is the default hard rule
3. Roles do not share the full thread history with each other
4. Roles do not talk to each other directly; they only hand off through file artifacts
5. The same role may retain its own continuous context for later resumption
6. When a role's responsibility changes, a new agent must be spawned; reusing an old agent to impersonate a different role is not allowed

Implementation notes:

1. This document defines the collaboration spec; it is mechanism-layer agnostic
2. Current implementation suggestion:
   - `Supervisor` → `spawn_agent(..., fork_context=false)`
   - `Executor` → `spawn_agent(..., fork_context=false)`
   - `Blind Reviewer` → `spawn_agent(..., fork_context=false)`
3. Isolation mainly relies on:
   - A new agent identity
   - `fork_context=false`
   - A minimal artifact allowlist
4. The current runtime does not provide filesystem-level ACLs; therefore "information blindness" is **session-level strong isolation + artifact-level minimal disclosure**, not repository-level absolute isolation

---

## 3. Artifact Contract

By default, split into 4 independent artifacts:

```text
.code-removal/runs/{date}-{batch-name}/
├── supervisor-board.md
├── review-manifest.md
├── execution-result.md
└── blind-review-result.md
```

For long-term archival, you may additionally produce:

- `.code-removal/reviews/{date}-{batch-name}.md`
- `.code-removal/skill/iterations/{n}-{topic}.md`

Under `validation mode`, an additional requirement:

```text
.code-removal/runs/{date}-{batch-name}/
└── orchestration-proof.md
```

### 3.1 supervisor-board.md

Purpose:

1. Record the triage result
2. Record the status groupings of the current batch
3. State the next-step routing and the escalation conclusion

### 3.2 review-manifest.md

Purpose:

1. Serve as the control-plane contract of the cleanup batch
2. Define:
   - What to clean up
   - What not to clean up
   - What the basis is
   - What the acceptance criteria are
   - What the risk constraints are

Ownership:

- Can only be created and have revisions approved by the `Supervisor`
- The `Executor` can only submit revision suggestions
- The `Blind Reviewer` can only base its review on it, and must not write the boundary definition on its behalf

### 3.3 execution-result.md

Purpose:

1. Record what the `Executor` actually did
2. Record the acceptance results of `build-check.sh` / `vet-check.sh` / grep / `tidy-check.sh`, etc.
3. Record deviations from the manifest, failure points, and revision suggestions

### 3.4 blind-review-result.md

Purpose:

1. Record the `Blind Reviewer`'s refutation conclusion
2. State whether the manifest is sufficient
3. If necessary, point out whether the execution result deviates from the manifest

### 3.5 orchestration-proof.md

Purpose:

1. Record the role registry, agent IDs, `fork_context`, and input handoffs
2. Record the canary check and the disagreement-path check
3. Prove whether this round's multi-role process was executed per the contract

---

## 4. Input Allowlist

### 4.1 Supervisor Allowed Inputs

1. The user task scope
2. Repository paths
3. Necessary reference documents
4. Historical `supervisor-board.md`
5. This role's own incremental records
6. Read only when the state machine explicitly requires rework:
   - `execution-result.md`
   - `blind-review-result.md`

By default should NOT be input:

- The main thread's full history
- The `Executor`'s full working drafts
- The `Blind Reviewer`'s procedural reasoning

### 4.2 Executor Allowed Inputs

1. `supervisor-board.md`
2. `review-manifest.md`
3. The current codebase
4. `acceptance-criteria.md` (the acceptance hard gate)
5. `removal-list-template.md` (the manifest field template, for format reference only)
6. `execution-result-template.md` (the output template)
7. `executor-prompt-template.md` (the Non-Negotiable Rules must appear inside the spawn prompt)
8. Read only when the state machine explicitly requires rework: this role's own previous `execution-result.md`

By default should NOT be input:

- The `Supervisor`'s full conversation
- The `Blind Reviewer`'s full conversation
- The main thread history

### 4.3 Blind Reviewer Allowed Inputs

Default inputs:

1. `review-manifest.md`
2. The current codebase
3. `blind-review-prompt.md`

Append only when execution-deviation review is needed:

4. `execution-result.md`

By default should NOT be input:

- The `Supervisor`'s reasoning drafts
- The `Executor`'s preset conclusions
- The main thread's full history

---

## 5. File-Driven Main Flow

### Phase 0 — Batch Initialization

**Trigger condition**

- The user provides a module directory, an HTTP batch, a backlog / tracking page, or a review document

**Inputs**

- The user's original request
- Repository path
- Current skill references

**Main Thread actions**

1. Create the `runs/{date}-{batch-name}/` directory
2. Decide whether to enable `validation mode` this round (see §9; mandatory by default before the skill is stable)
3. If validation mode is enabled: initialize the `orchestration-proof.md` shell
   - role registry header
   - handoff log header
   - canary fields (if a canary check is done this round)
4. In the main thread's internal state, register `batch_id`, the directory path, and the state machine starting point `NEW_BATCH`

**Outputs**

- The initialized batch directory
- `orchestration-proof.md` (validation mode only)
- The readiness signal to enter Phase A

**Constraints**

- Phase 0 does not call any business role agent
- Phase 0 does not make cleanup boundary judgments
- Phase 0 does not write any business artifact (`supervisor-board.md` / `review-manifest.md` both belong to Phase A)

### Phase A — Supervisor Triage

Inputs:

- The user-given module / HTTP batch / backlog / tracking page

Actions:

1. The `Supervisor` analyzes the cleanup backlog
2. Writes `supervisor-board.md`
3. Generates or revises `review-manifest.md`

The output must minimally contain:

- The current objects to be executed
- Object status groupings
- The cleanup boundary
- Next-step suggestions
- `Needs Human`
- `Skill Follow-ups`

### Phase B — Executor Executes the Contract

Inputs:

- `supervisor-board.md`
- `review-manifest.md`
- The current codebase

Actions:

1. Only process objects that the `Supervisor` has marked `Ready` or has explicitly closed out
2. Execute Step 0–6 per the manifest
   - Compilation validation only runs `scripts/build-check.sh`
   - vet validation only runs `scripts/vet-check.sh`
   - Directory-gone validation only runs `scripts/module-gone-check.sh <module-dir>`
   - Dependency cleanup only runs `scripts/tidy-check.sh`
3. Writes `execution-result.md`
4. If a conflict between the boundary and reality is found, write a revision suggestion and return it to the `Supervisor`
5. When the main thread assembles the executor prompt, it must explicitly include the Non-Negotiable Rules from `executor-prompt-template.md`

### Phase C — Blind Review

Inputs:

- `review-manifest.md`
- The current codebase
- `blind-review-prompt.md`
- `execution-result.md` (only when execution-deviation review is needed)

Actions:

1. The `Blind Reviewer` reviews independently
2. Produces `blind-review-result.md`

### Phase D — Human Gate + Batch Wrap-up

Inputs:

- `review-manifest.md`
- `blind-review-result.md`
- `execution-result.md` (if the execution evidence needs to be inspected)

Actions:

1. Only now do we return to the user
2. The user only makes the call on the "decision residue"
3. After approval, update:
   - `approved: true`
   - `approved_by`
   - `approved_at`
   - `approved_sha`
4. **Batch wrap-up: the main thread must record metrics for the batch**
   - Read each role's `duration_ms` / `usage.input_tokens` / `usage.output_tokens` / `usage.cache_read_input_tokens` from the Agent tool result
   - Do not let a subagent report its own elapsed time — a subagent has no trustworthy wall-clock
   - Mandatory fields: `durations` / `tokens` / `code_delta` / `acceptance` / `blind_review_findings`
   - The finding count is aggregated from `blind-review-result.md` by severity

Constraints:

1. `Needs Human` is not a fallback state
2. Only problems that pass the `Escalation Gate` may enter the `Human Gate`
3. The Human Gate reads only the minimum necessary summary, not the full multi-role conversation history
4. **A batch is not considered complete until the batch metrics are recorded** — the runtime validation checklist §4.x will block it

---

## 6. Recommended State Machine

- `NEW_BATCH`
- `SUPERVISOR_TRIAGE`
- `EXECUTOR_EXECUTE`
- `BLIND_REVIEW`
- `MANIFEST_REVISION_REQUIRED`
- `EXECUTION_REVISION_REQUIRED`
- `HUMAN_GATE`
- `DONE`
- `BLOCKED`

Transition rules:

1. `NEW_BATCH -> SUPERVISOR_TRIAGE`
2. `SUPERVISOR_TRIAGE -> EXECUTOR_EXECUTE`
   - Condition: the object is `Ready` or the closure is explicit
3. `EXECUTOR_EXECUTE -> BLIND_REVIEW`
   - Condition: the execution result has been produced
4. `BLIND_REVIEW -> HUMAN_GATE`
   - Condition: `PASS` or `PASS WITH NOTES`
5. `BLIND_REVIEW -> MANIFEST_REVISION_REQUIRED`
   - Condition: there are problems with the boundary definition, retained items, deletion_paths, or the acceptance contract
6. `BLIND_REVIEW -> EXECUTION_REVISION_REQUIRED`
   - Condition: the manifest holds, but there is execution deviation or acceptance failure
7. `MANIFEST_REVISION_REQUIRED -> SUPERVISOR_TRIAGE`
8. `EXECUTION_REVISION_REQUIRED -> EXECUTOR_EXECUTE`
9. `HUMAN_GATE -> DONE | BLOCKED`

### 6.1 Blind Review finding → state machine mapping

The correspondence between the `blind-review-result.md` verdict and the state machine is as follows:

| Blind Review verdict | Meaning | State machine transition |
| --- | --- | --- |
| `PASS` | No findings; both manifest and execution hold up | `BLIND_REVIEW -> HUMAN_GATE` |
| `PASS WITH NOTES` | There are non-blocking findings (e.g. suggestions, style, follow-ups) | `BLIND_REVIEW -> HUMAN_GATE` (notes written into the Human Gate summary) |
| `FAIL — manifest issue` (a finding proves the batch / boundary / deletion_paths / acceptance criteria do not hold) | The manifest itself needs revision | `BLIND_REVIEW -> MANIFEST_REVISION_REQUIRED -> SUPERVISOR_TRIAGE` |
| `FAIL — execution issue` (the manifest holds, but there is execution deviation or acceptance failure) | Only the executor side needs to redo | `BLIND_REVIEW -> EXECUTION_REVISION_REQUIRED -> EXECUTOR_EXECUTE` |
| `FAIL — split batch` (forcibly grouping multiple modules makes the rollback surface too large) | Treated as a subclass of the manifest issue | `BLIND_REVIEW -> MANIFEST_REVISION_REQUIRED -> SUPERVISOR_TRIAGE` |

Constraints:

1. The main thread must write in the routing log (or the `orchestration-proof.md` handoff section) which row was triggered
2. The same `blind-review-result.md` can map to only one transition; if the reviewer gives multiple finding categories at once, route by the most severe one (manifest issue > execution issue > notes)
3. If the reviewer's verdict cannot be matched to any row in the table above, the main thread must not classify it on its own; it should return to the supervisor to re-read the manifest

---

## 7. Agent Lifecycle

### 7.1 Creating a role

When creating a role for the first time:

- `spawn_agent(fork_context=false, ...)`

### 7.2 Resuming a role

If the role is just continuing its own responsibility:

- `send_input(target=<same_agent_id>, ...)`

Reusable scenarios:

1. The `Supervisor` supplements triage
2. The `Executor` re-runs execution based on reviewer feedback
3. The `Blind Reviewer` reviews a new version of the same batch again

### 7.3 Closing a role

When a role is no longer needed:

- `close_agent(...)`

Scenarios NOT to reuse:

1. Having the `Executor` go on to play the `Blind Reviewer`
2. Having the `Supervisor` directly take over the `Executor`'s implementation context
3. The same agent carrying two roles at once

---

## 8. Minimal Implementation Skeleton

```text
main thread
  -> spawn Supervisor (fork_context=false)
  -> send task scope + refs
  -> record role spawn in orchestration-proof.md
  -> wait -> artifacts: supervisor-board.md, review-manifest.md

  -> spawn Executor (fork_context=false)
  -> send supervisor-board.md + review-manifest.md + repo refs
  -> record handoff in orchestration-proof.md
  -> wait -> artifact: execution-result.md

  -> spawn Blind Reviewer (fork_context=false)
  -> send review-manifest.md + blind-review-prompt.md + repo refs
  -> optionally send execution-result.md
  -> record handoff in orchestration-proof.md
  -> wait -> artifact: blind-review-result.md

  -> route:
     - PASS -> human gate or done
     - PASS WITH NOTES -> executor or supervisor depending on note type
     - FAIL (manifest issue) -> supervisor
     - FAIL (execution issue) -> executor
```

---

## 9. Validation Mode

Before the skill reaches stable, `validation mode` is required by default for every real batch.

Additional requirements:

1. The main thread maintains `orchestration-proof.md`
2. Every role spawn must leave in the proof:
   - agent id
   - created_at
   - `fork_context=false`
3. Every handoff must record:
   - from / to
   - allowed inputs
   - actual inputs sent
4. At minimum, perform:
   - canary check
   - disagreement-path check
5. After finishing, verify against `runtime-validation-checklist.md`

Note:

- The current runtime cannot provide file ACLs, so validation mode relies on **observable evidence** rather than abstract claims
- If validation mode fails, then even if this round's code deletion result is correct, it cannot serve as proof that "the multi-role process has been validated"

---

## 10. When NOT to Spin Up Multiple Agents

In the following cases, a full set of three roles is not recommended:

1. A single very small module with an extremely clear dependency boundary
2. Only filling in documentation, with no deletion execution involved
3. Only a very small revision to an existing manifest

In this case you can keep:

- `Supervisor + Executor`
  - but `Blind Review` is still recommended to be kept before entering deletion

---

## 11. Failure and Fallback

If multi-agent collaboration gets out of control, fall back in the following order:

1. Preserve the file artifacts; do not lose the current state
2. Pause parallelism other than Blind Review
3. Let a single Executor converge the result based on the manifest
4. When necessary, keep only:
   - `Supervisor Board`
   - `review-manifest.md`
   - `execution-result.md`
   - `blind-review-result.md`

Key principle:

- Even when falling back to single-threaded progress, do not fall back to the "share full context" approach

---

## 12. Division Between the Spec Layer and the Mechanism Layer

This document (the spec layer) answers:

1. Which roles exist
2. What each role is responsible for
3. What artifacts roles are allowed to hand off
4. Which process steps cannot be skipped

`SKILL.md §3.5a` (mechanism-layer hard rules) answers:

1. The Blind Reviewer must spawn an independent subagent
2. The toolset-trimming rules
3. The list of inputs that must not leak
4. The `blind-review-result.md` output requirements

`references/drafts/langgraph-implementation-design.md` (contract spec, for future externalized orchestration reference only) answers:

1. How to rebuild with LangGraph if the Claude Code harness is no longer relied upon in the future
2. This document **currently does not affect the implementation**; it is a contract-obligation-level reference draft

The current active runtime hands off "independent context / conditional routing / batch persistence" entirely to the Claude Code harness, with no need to introduce an additional orchestration framework.

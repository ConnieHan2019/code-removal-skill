---
name: dead-code-removal
description: Use when removing dead code, deprecated HTTP handlers, unused modules, or orphan symbols from a codebase. Enforces a 3-role workflow (supervisor / executor / blind-reviewer) with manifest-based review, layered build/vet/tidy validation scripts, a review gate before any deletion, and hard acceptance criteria so a removal is correct AND complete in one pass. Trigger on phrasings like "remove dead module", "delete deprecated HTTP route", "drop unused service func", "clean up the X handler", or batch-cleanup tasks driven from a backlog.
---

# Dead Code Removal Skill

> version: 0.1.0
> status: open-source release (methodology mature; packaging new)
> language toolchain: Go (`scripts/*.sh`); methodology is language-agnostic — swap the scripts to support another language.

## 🚨 Top-Level Non-Negotiable Rules (read first — violations cause repeated permission prompts)

**If you run this skill inside a permission-gated agent (e.g. Claude Code), violating any of these forces a permission prompt on nearly every command.**

1. **Don't prefix the validation scripts with env vars**
   - ❌ `GOCACHE=... GOFLAGS=-mod=mod scripts/build-check.sh ./...`
   - ✅ `scripts/build-check.sh ./...`
   - **Why**: an env-var prefix creates a *new* command prefix that is not on your allowlist → a fresh prompt every time. If your environment needs fixed cache/proxy locations, export them once in your shell profile, or edit the script defaults — never prefix at the call site.

2. **Don't add decorative pipes (`| head`, `| tail`, `| tee`)**
   - ❌ `scripts/build-check.sh ./... 2>&1 | tail -5`
   - ✅ `scripts/build-check.sh ./...` (output is short; if long, truncate with your editor/`Read` tooling)
   - **Why**: a composite command re-matches the allowlist; `tail`/`head` may not be allowed, so the whole pipeline prompts.

3. **Don't edit source code with Bash**
   - ❌ `sed -i ...` / `awk > tmp && mv tmp file` / `head -n X file > new && tail >> new && cp new file`
   - ✅ Use your editor / file-edit tooling
   - **Why**: Bash-edited source can't be diffed cleanly and easily trips sandbox write permissions.

4. **Don't dress up an unverified risk as a decision for the user**
   - Before escalating to a human, pass the 3 gates in §Supervisor Mode → Escalation Gate (fact closure / technical closure / decision residue).

If you violate 1–3, re-read this section and switch to the prescribed form — don't power through and trigger the prompt.

---

## Goal

Given a deprecated entry point (HTTP handler) or a module directory, automatically find and remove every downstream dependency that is referenced *only* by the dead code — so the removal is both **correct** and **complete** in a single pass.

It also supports **Supervisor Mode**:

- The agent triages, orders, and judges blockers by default.
- It escalates to a human only when a human truly must decide.
- After each round it records the skill defects the round exposed, feeding back into improvement.

## Input format

```
Interface: {HTTP method} {route path}
Handler:   {function name}
File:      {file path}
```

or:

```
Module dir: {directory path}
```

or:

```
Module dirs:
- {dir 1}
- {dir 2}
- ...
```

## Scope boundary

The default goal is NOT "delete directories in bulk as fast as possible" — it is to retire code in the **smallest verifiable unit**, stably.

- Default unit: 1 module / 1 interface / 1 runtime entry point
- Default strategy: **analysis may be batched; execution must be conservative**
- Multiple modules may be deleted together in one round only when they form a **closed deletion batch**.

### What is a closed deletion batch

Multiple modules count as one batch only if ALL of the following hold:

1. The modules depend mainly on **each other** (internal interdependence).
2. There is **no live caller** outside the batch.
3. They don't share a still-used common package, proto, config template, DB schema, topic, or Redis key.
4. They can be verified with **one unified set of acceptance criteria**, not service-by-service.
5. They can be rolled back in **one commit / one PR** without affecting unrelated modules.

If any condition fails, **do not group them** — iterate module by module.

### Default handling for multiple modules

When the user gives multiple modules at once, process in this order:

1. **Batch analysis** first: build the inter-module call graph, find which modules form closed deletion batches.
2. Output a **grouping**:
   - Class A: modules deletable independently
   - Class B: closed module groups that must be deleted together
   - Class C: modules that cannot be deleted, only simplified / merged / decoupled
3. Execution defaults:
   - **one review per module**
   - **one commit per module or per closed module group**
   - **one PR per module or per closed module group**

### Why not delete multiple modules together by default

Because deleting multiple modules together amplifies 4 risks at once:

- A wrong reference-graph judgment deletes a larger blast radius.
- A `build` / `test` failure is harder to attribute to the responsible module.
- Release-observation items get mixed, so you can't tell which group caused a problem.
- Rollback granularity is too coarse — you may revert already-verified deletions.

So the **default rule is: batch the analysis, execute in batches, verify each batch, then advance to the next.**

## Supervisor Mode (recommended on by default)

When the input comes from a backlog, a module list, or a set of HTTP interfaces, drive in "supervisor mode" by default rather than asking the user to decide each next step.

### Multi-role model (contexts MUST be independent)

This skill is not "one agent role-playing three parts." It uses 3 roles with **independent context**; the main thread only orchestrates and is none of the three:

1. **Supervisor**
   - Owns: reading the cleanup backlog, triage, ordering, the `supervisor-board`, and `Needs Human` escalation judgments.
   - Creates and owns `review-manifest.md`.
2. **Executor**
   - Executes Steps 0–6 per the manifest: deletion, validation, acceptance.
   - Produces `execution-result.md`; proposes manifest revisions when reality conflicts with it.
3. **Blind Reviewer**
   - Performs the independent, refutation-style review at Step 3.5a.

Recommended implementation: an agent runtime that can spawn isolated sub-agents.

- The `main thread` only routes, waits, runs the Human Gate, and reports.
- `Supervisor`, `Executor`, and `Blind Reviewer` each get an independent context (spawned fresh, NOT forked from the main thread's history).

Top-level routing / state persistence / Human Gate are provided by the agent harness; no extra orchestration layer is required. If you ever externalize orchestration, see `references/drafts/langgraph-implementation-design.md` (a contract sketch; does not affect the current implementation).

### Validation Mode (currently enforced by default)

Until the skill is proven stable, every real module-execution round should run with `validation mode` on.

`validation mode` verifies not "was the code deleted correctly" but:

1. whether the 3 roles really run as independent agents,
2. whether the input allowlist is strictly enforced,
3. whether the blind review has real refutation power,
4. whether the artifact chain is sufficient for re-runs and audit.

`validation mode` additionally requires:

1. the main thread maintains `orchestration-proof.md`,
2. verifying each item in `references/runtime-validation-checklist.md`,
3. running a canary check by default,
4. getting at least 1 disagreement-path piece of evidence within the first 3 real batches.

Only after passing `runtime-validation-checklist.md` is the round a valid proof that "the multi-role flow ran per contract."

Hard rules:

1. The three roles must be treated as **different context windows**.
2. No-context-fork is the default hard rule.
3. Do not pass the Supervisor's full reasoning chain to the Executor or Blind Reviewer.
4. The Blind Reviewer must never inherit the Supervisor's / Executor's prior reasoning.
5. Roles exchange information only through the **minimum necessary artifacts**, not by sharing whole conversations.
6. A role may keep its own continuous context; when responsibilities change, spawn a new agent — never reuse an old agent to impersonate another role.

Allowed artifact hand-offs:

- Supervisor → Executor
  - the object to execute
  - `supervisor-board.md`
  - `review-manifest.md`
  - necessary blocking conclusions
- Executor → Blind Reviewer
  - `review-manifest.md`
  - the current codebase
  - `references/blind-review-prompt.md`
  - `execution-result.md` (only when execution deviation must be reviewed)
- Blind Reviewer → Human Gate
  - `blind-review-result.md`

Forbidden to pass:

- the Supervisor's full analysis draft
- leading conclusions like "I suspect a bug here / this was probably deleted wrong"
- pre-set answers or recommended conclusions

### Supervisor responsibilities

1. Auto-read the cleanup backlog (a tracking page, review docs, local module state).
2. Triage first, then decide order:
   - `Ready`: can enter Steps 0–3 to generate a review manifest now.
   - `Needs Closure`: depends on other to-be-cleaned modules; merge into a closed group or wait for upstream removal first.
   - `Blocked (external refs)`: still has live callers outside the group / shared infrastructure.
   - `Blocked (refactor needed)`: must first decouple, sink shared code, or split an entry point.
   - `Needs Human`: a question that genuinely requires a human decision.
3. Prioritize:
   - confirmed-dead, low-risk independent modules
   - module groups that form a clean closure
   - modules already audited, only execution remaining
4. After each round output:
   - the next batch's suggested objects
   - the items that require human intervention this round
   - a summary of skill defects exposed this round

### Only these cases may escalate to the user

Only the following may interrupt the user for a human decision:

1. **Ownership boundary unclear** — a caller exists, but you can't tell whether it also belongs to the cleanup set.
2. **Shared-resource ownership unclear** — whether a shared DB schema / Kafka topic / Redis key / proto / config template can still be deleted can't be decided from code alone.
3. **Runtime-entry ownership unclear** — whether `cmd/main`, `service.Init()`, a consumer, cron, feature flag, or registry map is still active, with conflicting evidence.
4. **Batch boundary unclear** — two modules are neither fully independent nor a stable closure; forcing them together enlarges the rollback surface.
5. **The Review Gate before Step 4** — any source/config deletion still requires explicit review/approval.

### Escalation Gate

Even when it "looks like" the user must confirm, you must first pass these 3 gates before truly escalating:

1. **Fact closure** — entry points, call chain, real consumers, and runtime trigger are all identified.
2. **Technical closure** — confirmed this is a real technical risk, not a mid-analysis guess.
3. **Decision residue** — the agent has compressed the problem down to "facts are settled; only a trade-off remains for a human to pick."

If any gate fails, **escalation is forbidden** — keep investigating yourself.

### Invalid Escalation rule

The following count as `Invalid Escalation`:

1. The agent dresses up an **unverified risk** as "a decision you need to make."
2. The agent asks, then keeps digging and finds the question could have been resolved by code, config, the call chain, or runtime evidence.
3. The agent mixes "fact to be investigated" and "preference to be chosen" into one question dumped on the user.

One-line rule:

> Don't dress up an unverified risk as a decision to be confirmed.

On `Invalid Escalation`:

1. The question should not keep occupying the user's decision slot.
2. The agent must finish the missing investigation, then decide whether escalation is still needed.
3. The iteration must record: the prematurely-escalated question verbatim; the real question after follow-up; which verification must be done before escalating next time.

### Default handling of "depended on by another module"

If to-be-deleted module A is depended on by module B, do not immediately conclude "A can't be deleted." Apply:

1. First determine whether B is also in the cleanup backlog.
2. If B is also to-be-cleaned:
   - Determine whether A+B form a **closure** with respect to outside code.
   - If yes → same batch (`Needs Closure` → closed module group).
   - If no → don't execute yet; keep walking up the caller chain until a closure holds or you hit a live boundary.
3. If B is not in the backlog:
   - If B is a direct live caller → mark A `Blocked (external refs)`.
   - If shared wiring / shared helper / shared proto makes A undeletable → mark `Blocked (refactor needed)` and give the minimal decoupling plan.
   - The manifest must name the live caller B; deletion is forbidden.
4. If whether B is to-be-cleaned can't be confirmed:
   - Mark `Needs Human`.
   - Escalate only "who needs to confirm what" — don't dump the whole analysis.

### Supervisor Mode output format

After each round of analysis, the `Supervisor` outputs a short board:

```markdown
## Supervisor Board

- Ready:
  - {module/interface}: {why it can be done now}
- Needs Closure:
  - {module/interface}: {depends on whom, suggested grouping}
- Blocked:
  - `Blocked (external refs)`: {module/interface}: {live caller outside group}
  - `Blocked (refactor needed)`: {module/interface}: {decoupling plan}
- Needs Human:
  - {module/interface}: {only the question a human must answer}
- Next:
  - {suggested objects for the next batch}
- Skill Follow-ups:
  - {skill defects / improvements exposed this round}
```

Full question template and escalation rules: `references/supervisor-checklist.md`.

## Execution flow

### Step -2 — Tool & command selection principles (throughout; lowers interruption rate)

**Goal**: make ≥95% of tool calls hit already-authorized permissions or auto-pass the sandbox, avoiding repeated approval prompts.

#### Principle 1: native tools > Bash equivalents

Native tools (file read / search / glob / edit / write / sub-agent) are within the default allow set and **never prompt**. If a native tool can do the job, **do not** switch to Bash:

| Task | Use | Don't |
|---|---|---|
| Read a file | file-read tool | `Bash(cat file)` |
| Search code/strings | grep tool | `Bash(grep/rg/git grep)` |
| Find files by glob | glob tool | `Bash(find / ls \| grep)` |
| Edit a file | edit/write tool | `Bash(sed/awk/echo >/cat <<EOF)` |
| Complex multi-round exploration | sub-agent | a big Bash script |

**Core rule (memorize):**

> `| head -N` / `| tail -N` is almost always an anti-pattern. To truncate output, **always** use your read tool's `limit/offset` or your grep tool's head-limit — never add `head/tail` in a Bash pipe.

**Why this matters most**: Bash permissions match by command prefix — `grep` may be allowed, but `grep ... | head -20` re-prompts because `head` isn't allowed. Most prompts come from these decorative pipes.

#### Principle 1.5: sub-agent spawn prompts must restate these rules

`Supervisor` / `Blind Reviewer` / `Executor` run in independent contexts — they can't see the main thread's tool-usage habits. **When you spawn them, the prompt must explicitly include**:

- the anti-pattern table above (or an equivalent ban list)
- "no `cat | head` / `find -name` / `grep -rn | head` / `| tail -N` decoration"
- a reminder that the read tool has `limit/offset` and the grep tool has a head-limit
- a reminder to "prefer `scripts/build-check.sh` / `scripts/vet-check.sh` / `scripts/module-gone-check.sh` for layered acceptance, not `go build`/`tee`/`echo`/`ls` strung into one command"
- a reminder to "edit source only with edit/write tools; never `head > tmp ; tail >> tmp ; cp tmp target`, never write temp patch files"

Otherwise the sub-agent falls back to Bash habits and its (invisible) runtime balloons.

#### Principle 2: simple commands > complex pipes

Bash allow rules match by command prefix. `go build ./...` may be allowed, but `go build ./... | tee log` is not (`tee` isn't in allow) and prompts.

- Split the pipe: run `go build ./... 2>&1`, then filter the result with your grep tool (neither prompts).
- If a pipe is unavoidable: ensure every segment is allowed.

#### Principle 3: avoid triggering sandbox bypass

If your environment runs commands in a sandbox, allowlisted commands that succeed inside the sandbox pass silently. But a command that needs to write a sandbox-denied path requires a bypass and **prompts every time**. Common traps:

- **`go build` / `go test` / `go vet` writing the default Go cache** (sandbox-denied)
  - **Fix A (preferred)**: use this skill's wrappers: `scripts/build-check.sh` / `scripts/vet-check.sh` / `scripts/tidy-check.sh`, and export a writable `GOCACHE`/`GOMODCACHE` once in your shell profile.
- **`git stash -u` hitting a sandbox-denied file (e.g. `.env`)** → stash fails
  - **Fix**: during analysis don't use stash for base comparison. Use `git diff` + `git show HEAD:path` to read historical versions, or a separate `git worktree`.
- **`rm` to a path outside the sandbox** → denied
  - This skill only deletes files inside the repo, so it won't trigger this.

#### Principle 4: parallel over sequential

Independent reads (multiple file-reads / greps / `git log`) should be issued **concurrently in one message**, not serially.

#### Principle 5: new permission need → go back to Step -1's check, don't prompt mid-run

If mid-run you find a required-but-unauthorized command:
1. **Stop**; don't let it prompt.
2. Go back to Step -1, add it to a single delta list for the user.
3. Tell the user "appended, continuing" — don't prompt command-by-command.

---

### Step -1 — Obtain permission (run immediately after the user triggers a cleanup)

**When the user requests "clean up module/interface", before any analysis, run this two-phase flow:**

#### Step -1a — Check whether a permission Hook is ready

1. Confirm whether a usable permission-Hook config + script exists.
2. Confirm the minimal skeleton permissions are covered:
   - read / grep / glob
   - the required read-only shell queries
   - the required `go build/test/vet/mod tidy`
3. If the Hook is ready: show the user only the **minimal skeleton permission delta**; later deletions are granted dynamically via the manifest + Hook.
4. If the Hook is not ready: fall back to **Step -1b diff-first fallback**.

#### Step -1b — diff-first fallback (only when the Hook isn't ready)

1. **Read existing authorizations**: read your permission settings (treat missing as an empty allow array). Extract `allow` entries.
2. **Compare against the full list**: full list in [references/permission-template.md](references/permission-template.md). Do a **semantic** compare (a wildcard like `Bash(go build:*)` covers `go build`; a bare `Read`/`Grep`/`Glob` covers all sub-items).
3. **Show the user only the delta**:
   - if the analysis set is fully covered → output a single line "✅ analysis permissions fully authorized, proceeding to Step 0" — don't re-list the full set.
   - if missing → list only the uncovered entries, with a one-line "(X already-authorized items omitted)".
   - **the execution set is handled the same way** (diff again after the Step 3.5b Human Gate passes).

**Why split Hook / fallback first?** The Hook mode solves dynamic authorization of deletion actions at execution time; diff-first is the fallback when no Hook is wired. Try Hook first, then fall back.

**Why is this step first?** Analysis (Steps 0–3) makes many grep / build / read / sub-agent calls. Without confirming the permission path up front, a single module's analysis gets interrupted a dozen times.

### Step 0 — Confirm Runtime Roots

Before analyzing the dependency graph, confirm the entry points are still triggered by the startup flow at runtime:

1. Do `cmd/main` and `service.Init()` still initialize the module?
2. Are the HTTP routes / gRPC registers / Kafka consumers / cron workers still registered?
3. Is there a goroutine launch point, `init()` side effect, or config-flag-driven entry?
4. Check implicit entries (those not in the standard registration flow):
   - config-flag / feature-flag-gated conditional initialization
   - handlers dispatched via a registry map or string match (e.g. `handlers["foo"] = ...`)
   - passive logic triggered by another service via gRPC/HTTP

**Why Runtime Roots first?** A lot of logic is driven by registration, init, background goroutines, and config — not linear handler calls. If you don't first confirm the runtime entry is offline, a symbol-reference graph alone can mislead you into deleting code that the startup flow still triggers.

### Step 0.5 — Module grouping (only when input has multiple modules)

Before building the deletion graph, split input modules into three classes:

1. **Independently deletable** — forms its own deletion set; advance module by module.
2. **Closed module group** — modules depend on each other, with no live caller outside the group; must be deleted together as one minimal unit.
3. **Non-deletable** — still has callers outside the group, or provides shared capability; only simplify/decouple/merge.

Output: tag each module's class; say why; state this round's actual execution scope.

Default order: independent low-risk modules first; then closed groups; then modules needing refactor/merge.

### Step 1 — Locate the entry point

1. Find the entry function (handler / main / worker) per the input.
2. Read the entry function; record every internal symbol it directly calls (functions, types, constants).
3. Record where the entry point's route is registered (e.g. `app.GET(...)` in an http file).

### Step 2 — Build the dependency graph

For each direct dependency of the entry function, recursively:

1. Use LSP `findReferences` to find all referrers of the symbol.
2. Use grep for string occurrences of the symbol name (catch reflection, config, proto, and other non-static references).
3. Classify:
   - **all referrers are in the deletion set** → add to the deletion set, recurse its downstream deps.
   - **a referrer exists outside the deletion set** → mark as a boundary, keep.

Repeat until the deletion set stops growing.

**Indirect-reference paths you MUST scan (the easiest blind spots):**

A module may be referenced by code outside the deletion set through the following paths. Grepping only the module directory misses these:

1. **Generated proto package path** `grpc/{name}` — the package name may differ from the module dir name.
2. **Runtime endpoints**: `{service-name}:{port}`, `.svc.cluster.local`, address constants in toml / yaml / source strings.
3. **Service-address fields in config files** (gRPC client dial addresses, HTTP client base URLs).
4. **Kafka topic names / consumer group names** (constants often in a common package shared by multiple services).
5. **Redis key prefixes** (constant + concatenated string).
6. **Shared helpers in a `common/` sub-package** (e.g. a `common/<area>/dao/<module>.go` that defines methods for the module; after deletion these become orphans, and if `common/` is used by a live service, removing them breaks its build).
7. **Service-inventory / CI service-map / metadata files that your own removal workflow maintains** — if your process keeps a snapshot of services, pods, or routing, update it too; a stale inventory pollutes later analysis and the next audit's baseline.

Run all 7 grep classes per module; any external hit sends you back to Step 0.5 to re-classify (a module may drop from "independent" to "has a tail" or "blocked").

**Historical lessons (read this):**
- In one removal, the audit assumed a module was independent but missed that a shared `auth` middleware still imported its generated `grpc/<module>` package — nearly breaking a live service's build.
- In another, an `admin` module reverse-depended on a `grpc/<module>` package; the same blind spot recurred. These are why classes 1–7 are now hard scan items.
- In another, several service wrappers were removed but their entries in a service-inventory file were not updated, leaving orphan entries that polluted later analysis. This is exactly the problem this skill exists to eliminate — hence class 7.

**Non-code locations you must check:**
- config templates (e.g. `*.toml.tpl`)
- test configs (e.g. `testdata/*.toml`)
- test files (`*_test.go`)
- `Dockerfile` / `Makefile`
- CI service-to-directory maps
- Kafka topic / consumer group / cron config / env var names
- Redis key / metric name / SQL table name or enum value

### Step 3 — Generate the removal manifest

Produce a structured manifest; see `references/removal-list-template.md`.

The `Supervisor` generates and owns this manifest by default. The `Executor` may propose revisions during execution but does not rewrite the cleanup contract boundary.

The manifest must include:
- top frontmatter, at minimum:
  - `approved: false`
  - `approved_by: null`
  - `approved_at: null`
  - `approved_sha: null`
  - `input_type: module | http-batch`
  - `deletion_paths:` (machine-readable source of truth; a Hook reads only this, not the Markdown tables)
- the confirmed deletion symbol list (file, line, symbol, type)
- the boundary-kept symbol list (with reason — who still uses it)
- the non-code files to clean
- the env vars DevOps must clean
- the **acceptance criteria** (see `references/acceptance-criteria.md`) expected results, for later comparison
- a **permission note**: the manifest declares only the manifest path, deletion paths, and approval state; dynamic approval is the Hook's job, not a pile of hardcoded Bash prefixes in the review doc

Manifest filename: `.code-removal/reviews/{date}-{module}.md`.

### Step 3.5 — Review Gate (mandatory human/agent review)

**Hard pause. No source or config file may be deleted before this.**

#### Step 3.5a — Blind Review (before the Human Gate)

Before the Human Gate, a **Blind Review is mandatory** — the Supervisor may not self-review in its place.

Blind Review hard rules:

1. **Must** use a dedicated, independent `Blind Reviewer` agent, spawned fresh (not from an exploration helper).
2. **Must use an independent context**: don't reuse the Supervisor's or Executor's reasoning context; don't fork the whole thread history.
3. Blind-review inputs may include ONLY:
   - `review-manifest.md`
   - the current codebase
   - `references/blind-review-prompt.md`
   - `execution-result.md` (only when reviewing execution deviation)
4. **Forbidden** to feed the Supervisor's reasoning, expected conclusions, or known suspicions to the Blind Reviewer.
5. The Blind Reviewer must independently re-run Step 2's **7 indirect-reference scans**.
6. The blind-review conclusion must be written **by the reviewer itself** into a separate `blind-review-result.md` — not transcribed by the Supervisor.
7. A changed `approved_sha` voids `blind-review-result.md`; re-run the blind review.
8. **No entering Step 4 without a completed blind review.**

#### Step 3.5b — Human Gate (after blind review)

1. After the manifest is generated, output its path to the user and **wait for an explicit approve before Step 4**.
2. For batch cleanup of multiple modules:
   - **Default: one PR per module.**
   - **Exception: only a Step-0.5-confirmed closed module group may go in one PR.**
   - Either way: independent manifest, independent review, independent commit.
3. Reviewer focus (see `references/acceptance-criteria.md` §1):
   - does the deletion set include a boundary symbol that should be kept?
   - does the boundary-kept set miss an orphan symbol that should be deleted?
   - are all Runtime Roots enumerated?
   - is non-code residue (config, CI maps, k8s manifest, Kafka topic, Redis key) fully covered?
   - in multi-module cases, is this really a closed deletion batch; is any module wrongly grouped?
   - is the rollback path viable?
   - does `blind-review-result.md` give a clear conclusion and diff items?
4. If using a permission Hook:
   - confirm the manifest frontmatter exists and `deletion_paths` is complete.
   - on approval, update `approved` / `approved_by` / `approved_at` / `approved_sha` together.
   - `approved_sha` means the repo HEAD SHA at review/approve time.
   - require `current HEAD == approved_sha` before deletion; if HEAD changed, re-review or rewrite the manifest.
   - deletions are granted dynamically by the Hook per the manifest.
5. If no Hook is installed: keep only the minimal skeleton permissions; don't regress to a big static Bash allowlist.

Approval criterion: the reviewer appends `## Review: APPROVED by {name} at {date}` to the manifest, or the user explicitly says "approve/go ahead/delete it" in the conversation.

### Step 4 — Execute the deletion

Delete top-down by dependency topology, in layers:

```
Layer 1: route registration + handler + gRPC register + consumer registration + cron registration
Layer 2: service functions
Layer 3: dao functions
Layer 4: model / types
Layer 5: consts / enums
Layer 6: config files, test files
```

Run `scripts/build-check.sh` after each layer.

Multi-module supplement:

- single module: normal layered deletion.
- closed module group: still delete by layer, but within a layer delete all entries first, then all services, then all dao.
- on any layer failure: locate the responsible module/file first, then decide: shrink the deletion scope; split the module out of the batch; or keep/sink/merge shared code.

**Forbidden** to use "it's easier to delete multiple modules together" as a grouping reason. Grouping is based only on dependency closure and rollback closure.

### Step 5 — Clean the periphery

1. `scripts/tidy-check.sh` — prune no-longer-needed dependencies and print the `go.mod`/`go.sum` diff.
2. Check config templates for residue.
3. Check test configs for residue.

To verify a module directory is fully removed, run:

```bash
scripts/module-gone-check.sh {module-dir}
```

### Step 5.5 — Release & rollback constraints

1. **Take the entry offline first, then delete the implementation**: remove route / registration / consumer / cron entries first; confirm no new traffic enters.
2. **Observe one release cycle after deletion**: watch error rate, 404s, consumer lag, key-job execution for at least one normal release.
3. **Write the rollback path in advance**: usually a version rollback; if config cleanup is involved, confirm config can be restored too.

Multi-module batch extra:

- observation items must be listed per module/group, not one lumped item.
- if one group's runtime risk is much higher, don't merge-release it with low-risk modules.
- any config deletion needing cross-team manual restore must list owner and restore steps in the manifest.

### Step 6 — Self-eval & acceptance

Run two checks:
1. `references/eval-checklist.md` — skill-process quality.
2. `references/acceptance-criteria.md` — the **hard "no side effects AND fully cleaned" acceptance bar**.

**All acceptance criteria must pass** (any failure means rollback or supplemental deletion, then retest).

Final verification summary (full list in `acceptance-criteria.md`):
- `scripts/build-check.sh` passes
- `go test ./...` passes (or explicitly list pre-existing failures unrelated to the deletion)
- `scripts/vet-check.sh` has no new warnings
- `scripts/tidy-check.sh` passes; `go.mod`/`go.sum` diff is reasonable, no unexpected new deps
- full-repo grep of the module keywords: dir name, service name, import path, special config keys, Kafka topic, Redis key, metric name, SQL table — all zero or only docs/comments remain
- the CI service-to-directory map is synced
- k8s manifest / helm chart / Dockerfile / Makefile entries cleaned
- affected service container image still starts (config loads, deps init, route/consumer/grpc register OK)
- no panic, no nil pointer, no "config key not found"

### Step 6.5 — Handling post-deletion incidents

If after deletion you hit a compile failure, test failure, startup failure, traffic anomaly, consumer lag, 404 spike, missing config, or env regression, you must add a **follow-up task record** — not just say it in conversation.

#### 6.5.1 Incident severity

- **P0 rollback class**: can't compile / service won't start / clearly deleted live logic / critical path errors. Action: stop entering the next module; roll back or do the minimal fix first.
- **P1 supplement class**: deletion too small (residue remains) / too big (fixable by keeping a boundary) / missed config, script, test, doc. Action: close it in the current module before the next.
- **P2 follow-up class**: DevOps/QA/frontend/other-repo follow-up; legacy-compat logic to retire later; monitoring/alert/observation to add. Action: record owner, deadline, blocking relations.

#### 6.5.2 Required follow-up output

For each incident, add to the review or iteration doc: title; discovery stage (compile / test / smoke / release-observation / production feedback); severity (P0/P1/P2); root cause; affected modules; rollback needed?; immediate fix; follow-up task; owner; deadline; close condition.

#### 6.5.3 Constraints on later batches

- With an open P0/P1, **don't enter the next module's deletion**.
- P2 may not block the next module but must be recorded and assigned.
- If two consecutive deletions hit the same type of incident, update this skill before continuing.
- If the problem came from "wrongly grouped modules", later batches must be smaller.

## Iteration mechanism

After each run:
1. Evaluate per `references/eval-checklist.md`.
2. Record results in `iterations/{n}-{name}.md` (see `references/iteration-template.md`).
3. If a P0 / recurring P1 / wrong-grouping problem occurred, write "process defect → skill revision" in the iteration.
4. If you find a defect in the skill flow itself, update this file (SKILL.md) and bump the version.

## Permission strategy (Hook first, diff-first fallback)

The review doc does not maintain a big static Bash allowlist. Default:

1. **Check whether a Hook is ready first.** If ready: require only minimal skeleton permissions. If not: fall back to Step -1b diff-first.
2. **Minimal skeleton permissions**: read / grep / glob; the required read-only shell queries; the required `go build/test/vet/mod tidy`.
3. **Dynamic grant for deletions**: a Hook reads the review manifest frontmatter and grants only deletions that are `approved: true` and match `deletion_paths`. See `references/drafts/permission-hook.md`.
4. **Still approved one-by-one manually**: `git push`, `gh pr *`, external-system updates, `kubectl` / `gcloud` / `aws`, production DB.

Goal: move the "top up the allowlist every round" burden out of the review doc and into one auditable, dry-runnable Hook.

# Permission List Template

> **status: ACTIVE** — this is the permission scheme actually in use today. `references/drafts/permission-hook.md` is the design draft for a future replacement; it is not yet implemented.
> The default artifacts today are `supervisor-board.md` / `review-manifest.md` / `execution-result.md` / `blind-review-result.md`. The permission requests and diff-first flow in this document by default revolve around these artifacts of the current batch; the machine-readable source of truth is still the top frontmatter of `review-manifest.md`.
>
> Purpose:
> 1. **At task start** (Step -1): diff against the user's existing `.claude/settings.local.json` and **show the user only the missing delta**, never the full list.
> 2. **At the Review Gate stage** (Step 3.5): diff once more against `.claude/settings.local.json` (the user may have appended entries), listing only the items the execution tier does not yet cover.
>
> Goal: from Step 0 analysis through Step 6 acceptance, ≥ 90% of tool calls should not trigger a permission prompt.
>
> **Core rule**: §8.1 of this file is the full source-of-truth list; §8.2 is the **diff-first presentation flow**.
> **Do not** paste the entire §8.1 to the user and make them find the differences — that pushes the diff burden onto a human.

---

## 8.0 Command-Construction Constraints (so the allowlist and sandbox auto-allow actually take effect)

> Lesson learned: an allowlist once contained `Bash(GOCACHE=$TMPDIR/gocache GOMODCACHE=$TMPDIR/gomodcache go build:*)` with `sandbox.autoAllowBashIfSandboxed: true` enabled, yet every `go build` still raised a permission prompt. The root cause was not the allowlist but the command string itself.

### 8.0.1 Trigger Condition — `Contains simple_expansion`

Claude Code's Bash matcher has a built-in safety check for commands that contain shell variable expansion. When a command contains a `$VAR`-style simple expansion, the permission prompt displays a `Contains simple_expansion` flag, and **it always goes to manual approve**:

- ❌ Static allowlist matching **does not take effect** (no matter how the rule is written, or whether it carries the same prefix)
- ❌ `autoAllowBashIfSandboxed: true` **does not auto-pass it either**
- ❌ Even if the sandbox is enabled and the command would run fine, the user still has to click approve manually

Whether `${VAR}` / `$(...)` / backticks / the wildcard `*` trigger this the same way, I have not verified each one, but `$VAR` is confirmed. **As a precaution, treat everything under the rule "no shell expansion in the command".**

### 8.0.2 The Specific Pitfall with the Go Toolchain

By default Go uses `GOCACHE=~/Library/Caches/go-build`, which is **not in the sandbox write allowlist**. The first `go build` inside the sandbox fails writing its cache → Claude auto-falls-back to `dangerouslyDisableSandbox: true` → the command runs outside the sandbox → it goes through the normal allowlist flow → a permission prompt appears.

The natural reaction is to redirect GOCACHE/GOMODCACHE to `$TMPDIR`:

```bash
GOCACHE=$TMPDIR/gocache GOMODCACHE=$TMPDIR/gomodcache go build ./...
```

But this hits exactly §8.0.1 — **the moment `$TMPDIR` appears in the command, a permission prompt is guaranteed**. Writing a matching prefixed rule in the allowlist does not save you either.

### 8.0.3 The Correct Approach — Export Ahead of Time on the Shell Side

Export the cache paths once **in the shell configuration**, so that by the time Claude receives its environment the absolute paths are already resolved and the command body carries no env-var prefix:

```bash
# ~/.zshrc or ~/.bashrc or the project's .envrc (direnv)
export GOCACHE=$HOME/.cache/go-build-claude
export GOMODCACHE=$HOME/.cache/go-mod-claude
```

> The shell expands `$HOME` itself at startup; by the time it reaches the Claude process it is already a literal path, with no simple_expansion risk.

The commands Claude actually executes are bare:

```bash
go build ./service-x/...
go vet ./...
go test ./...
go list ./...
go mod tidy
```

The allowlist reuses the existing §8.1 entries (`Bash(go build:*)` / `Bash(go vet:*)` / `Bash(go test:*)` / `Bash(go list:*)` / `Bash(go mod tidy:*)`), all of which pass static matching.

### 8.0.4 General Rules

| Scenario | ❌ Do not write | ✅ Change to |
|---|---|---|
| Temp directory | `cmd $TMPDIR/foo` | export a fixed path on the shell side / use a literal in-project relative path `./.tmp/foo` |
| User home directory | `cmd $HOME/.cache/...` | a literal absolute path `/home/<user>/.cache/...` |
| Command substitution | `cd $(git rev-parse --show-toplevel)` | split into two steps: fetch and pin the value first, then `cd <literal path>` |
| Multiple env-var prefixes | `FOO=$VAR1 BAR=$VAR2 cmd ...` | export in the shell, leave only `cmd ...` as the command body |

**Core principle**: Bash tool calls must be constructed as **fully literal** strings, with all variable expansion done by the shell before Claude is invoked.

---

## 8.1 Permissions Needed for This Run — Tiered

### A. Analysis Tier (read-only, low risk, recommended to allow directly)

| Permission | Purpose | Stage of use |
|---|---|---|
| `Read(//**)` | read any file in the repo | Step 0–6 throughout |
| `Grep`, `Glob` | code / filename search | Step 0–3 dependency-graph construction + Step 6 residue verification |
| `Bash(ls:*)` / `Bash(cat:*)` / `Bash(diff:*)` / `Bash(wc:*)` | basic shell queries | Step 0–6 throughout |
| `Bash(cp:*)` | copy files for comparison (e.g. go.mod baseline snapshot) | Step 5 before/after `go mod tidy` diff |
| `Bash(git status:*)` / `Bash(git diff:*)` / `Bash(git log:*)` / `Bash(git stash:*)` | read-only git checks + baseline comparison (stash/pop to verify the base compile state) | Step 0 Runtime Roots + Step 6 baseline comparison |
| `Bash(go list:*)` / `Bash(go build:*)` / `Bash(go vet:*)` / `Bash(go test:*)` / `Bash(gofmt:*)` | build, static checks, tests | Step 2 dependency confirmation + Step 4 layered compile + Step 6 acceptance |
| `Bash(go mod tidy:*)` | clean up no-longer-needed indirect dependencies | Step 5 |
| `Bash(scripts/build-check.sh:*)` / `Bash(scripts/vet-check.sh:*)` / `Bash(scripts/module-gone-check.sh:*)` / `Bash(scripts/tidy-check.sh:*)` | acceptance actions wrapped by fixed scripts, preferred over bare Bash compound commands | Step 4-6 |
| `Agent` | sub-agent for deep dependency analysis | Step 0–2 |
| `mcp__claude_ai_Notion__notion-fetch` | look up meeting conclusions / approval status | Step 0 |
| `Bash(mkdir:*)` | create runs / reviews / iterations output directories | Step 3 |

### B. Execution Tier (write, locally rollback-able, recommended to allow within this module's scope)

| Permission | Purpose |
|---|---|
| `Edit(//**)` / `Write(//**)` | modify code / config / docs in this repo |
| `Bash(rm -rf {module directory}/:*)` | **listed by per-module allowlist**; bare `rm -rf *` is forbidden |
| `Bash(go mod tidy:*)` | clean up dependencies, update go.mod/go.sum |
| `Bash(git add:*)` / `Bash(git commit:*)` / `Bash(git checkout -b:*)` | local commit |

### C. Still Manual Tier (destructive / externally visible, **not pre-authorized**)

| Action | Why each one requires manual approve |
|---|---|
| `Bash(git push:*)` | pushes to remote, visible to others, hard to roll back |
| `Bash(git reset --hard:*)` / `Bash(git clean -f:*)` / `Bash(git branch -D:*)` | destructive, may lose work |
| `gh pr create` / `gh pr merge` | externally visible, affects others |
| `mcp__claude_ai_Notion__notion-update-page` | modifies conclusions / status on a backlog / tracking page |
| any `kubectl` / `gcloud` / `aws` / production DB write | affects the production environment |

---

## 8.2 Diff-first Presentation Flow (**the skill must run the diff itself, do not make the user do it**)

### Step A — Read the Existing Authorization

Read `.claude/settings.local.json` (treat a missing file as an empty array). Extract `permissions.allow`. Optionally also reference `~/.claude/settings.json`.

### Step B — Semantic Comparison Against the Full §8.1 List

Match by the following equivalence rules:

| Existing allow entry | Counts as covering the full entries |
|---|---|
| `Read` / `Grep` / `Glob` / `Agent` / `Edit` / `Write` (bare name) | all sub-items of the same name |
| `Bash(go build:*)` | `Bash(go build)` and `Bash(go build ./...)` etc. |
| `Bash(sh:*)` or `Bash(*)` | all Bash sub-items (rare) |
| exact per-entry match | the identical string |

Unmatched entries are the **delta**.

### Step C — Output Per Case

**Case A — Fully covered**:

```
✅ {Analysis tier / Execution tier} permissions are all authorized (N/N items covered); proceed directly to Step {0 / 4}.
```

**Case B — Some missing**:

```markdown
### Add the following K entries to the `permissions.allow` array in `.claude/settings.local.json`

```json
"Bash(go mod tidy:*)",
"mcp__claude_ai_Notion__notion-fetch"
```

(The X/N already-authorized items are omitted. Takes effect immediately after appending, no restart needed.)
```

**Case C — File does not exist**:

Prompt the user to create it:

```json
{
  "permissions": {
    "allow": [
      "...paste the entries for the corresponding tier from §8.1 here, line by line..."
    ]
  }
}
```

(Only in this case do you paste the full list; in Case B never paste the full list.)

### Alternative: Per-prompt "Always allow" One at a Time

Without editing the config file, let each permission select "Always allow" (session-level) the first time its approve prompt appears.
Downside: it expires when the session ends, so the next task has to do it all over again. Suitable for one-off small tasks.

### ⚠️ Anti-pattern: Do Not Use `/permissions` → Add allow rule to Paste Multiple Lines

`/permissions`' "Add allow rule" saves the entire pasted content (including newlines) as a **single string rule**, rather than splitting it into multiple entries. What gets written into `.claude/settings.local.json` after pasting is one long string containing `\r` / `\n`, which matches no actual tool call — effectively nothing was added.
If you must use `/permissions`, add the entries one at a time.

---

## 8.3 Why This Tiering

1. **Analysis tier** is generic across modules; once allowed, it can be reused for cleaning the whole batch of modules — no more repeated asking.
2. The `Edit`/`Write`/`go mod tidy`/`git commit` in the **Execution tier** are also generic across modules; the only thing that needs to be **swapped per module** is the `rm -rf {module}` entry, which is listed concretely by each module's manifest, avoiding over-broad authorization.
3. The **Still Manual tier** deliberately keeps an approval gate: push, PR, backlog-page update, k8s/prod — these are "externally visible, hard to roll back" actions, and approving each one separately is a cost-controlled safety margin.
4. **Prefer acceptance scripts**: if `build-check.sh` / `vet-check.sh` / `module-gone-check.sh` / `tidy-check.sh` are already authorized, prefer calling the script; do not string `go build`, `tee`, `echo`, `ls` into one Bash command.

---

## 8.4 Behavior Commitments After Approve

After the user adds the allow entries per 8.2, during Steps 4–6 this skill:
- **Will not** request permission for any tool call in the 8.2 list again
- **Will still** stop in the following cases:
  - when a Step 4 layered compile fails and the deletion scope needs adjustment
  - when an action in 8.1-C "Still Manual tier" is touched
  - when the user needs to intervene manually during the acceptance-criteria.md V20–V23 smoke stage
- Before each per-module commit, it briefly reports the change stats; it will not auto-push.

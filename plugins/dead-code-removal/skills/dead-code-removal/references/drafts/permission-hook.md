> ⚠️ DRAFT / EXPERIMENTAL — this is a design sketch, NOT implemented in v0.1. Kept for roadmap context only.

# Permission Hook

> **status: design draft, not implemented**. In every review to date, all of them use the static allowlist approach described in `permission-template.md`; the Hook described in this file has not been wired into the Claude Code `PreToolUse` event, and no real dry-run has ever been executed.
> Goal: replace the static allowlist that keeps growing across the per-batch artifact workflow.
> Approach: have the Hook read machine-readable manifest frontmatter, and only allow deletion paths that belong to the current batch, are already approved, and match.
> Note: the script below is a **logic skeleton**, not a directly copy-and-run Claude Code Hook implementation. Before actually wiring it in, you must first align with the real JSON protocol of the Claude Code `PreToolUse` event; if any protocol detail is uncertain, verify it against the actual hook documentation or the existing `update-config` / hook configuration approach before implementing.
> For the currently shipped approach, see [`permission-template.md`](../permission-template.md).
> In the current active design, if the Hook is ever implemented it should by default only read the frontmatter at the top of `review-manifest.md`; do not fall back to the vague phrasing "review doc".

---

## 1. Minimal Skeleton

The only things recommended to keep as statically allowed are:

- `Read`
- `Grep`
- `Glob`
- Required shell queries: `ls`, `cat`, `diff`, `wc`, `git status`, `git diff`, `git log`
- Build validation: `go build`, `go test`, `go vet`, `go mod tidy`, `gofmt`

All other high-noise actions, especially deletion actions, are delegated to the Hook for judgment.

---

## 2. Manifest Convention

The Hook only reads the frontmatter at the top of `review-manifest.md`:

```yaml
approved: false
approved_by: null
approved_at: null
approved_sha: null
input_type: module
deletion_paths:
  - module-a/dao/dca.go
  - module-a/http/dca.go
```

Key rules:

1. When `approved != true`, the Hook does not allow any deletion action
2. Only allow deletion of paths that match `deletion_paths`
3. `rm -rf`, `rm`, batch deletion, and directory deletion must all be expanded and verified one path at a time
4. The Markdown table is not the source of truth; `deletion_paths` is
5. `approved_sha` represents the **repo HEAD SHA at the moment of review/approve**
6. By default, require `current HEAD == approved_sha` before deletion
7. If HEAD has changed, treat the manifest as decoupled from the code state; you must re-review or update `approved_sha`

---

## 3. Classification Logic

It is recommended to split Hook results into three categories:

- `Cat1`
  - Clearly safe, auto-allow
  - Examples: read-only queries, build validation
- `Cat2`
  - Conditionally allowed
  - Example: deletion that matches a manifest `deletion_paths` entry and `approved: true`
- `Cat3`
  - Still requires manual approval
  - Examples: `git push`, `gh pr`, `kubectl`, external systems, deletions not matching the manifest

---

## 4. PreToolUse Hook Logic Skeleton

The example below leans toward pseudocode/skeleton; its purpose is to fix the logic, not to bind a specific runtime implementation. In particular:

- The input source is not necessarily `$1` / `$2`
- The actual implementation very likely needs to read a JSON payload from `stdin`
- The actual return value also needs to align with the Claude Code Hook protocol, rather than treating a bare `exit 0/2` as completion

Verify the real `PreToolUse` protocol before implementing.

```bash
#!/usr/bin/env bash
set -euo pipefail

TOOL_NAME="${1:-}"
TOOL_ARGS="${2:-}"
MANIFEST_PATH="${DEAD_CODE_REVIEW_MANIFEST:-}"
DRY_RUN="${DEAD_CODE_HOOK_DRY_RUN:-0}"
LOG_FILE="${DEAD_CODE_HOOK_LOG:-/tmp/dead-code-hook.log}"

log() {
  printf '%s\n' "$1" >> "$LOG_FILE"
}

allow() {
  log "ALLOW $*"
  exit 0
}

deny() {
  log "DENY $*"
  exit 2
}

if [[ "$TOOL_NAME" =~ ^(Read|Grep|Glob)$ ]]; then
  allow "cat1 builtin read-only"
fi

if [[ "$TOOL_NAME" == "Bash" && "$TOOL_ARGS" =~ ^go\ (build|test|vet|mod\ tidy) ]]; then
  allow "cat1 go validation"
fi

if [[ "$TOOL_NAME" == "Bash" && "$TOOL_ARGS" =~ ^rm ]]; then
  [[ -n "$MANIFEST_PATH" ]] || deny "missing manifest"

  approved="$(yq '.approved' "$MANIFEST_PATH")"
  approved_sha="$(yq '.approved_sha' "$MANIFEST_PATH")"
  current_sha="$(git rev-parse HEAD)"
  [[ "$approved" == "true" ]] || deny "manifest not approved"
  [[ "$current_sha" == "$approved_sha" ]] || deny "manifest stale: HEAD != approved_sha"

  mapfile -t approved_paths < <(yq '.deletion_paths[]' "$MANIFEST_PATH")
  mapfile -t requested_paths < <(normalize_rm_targets "$TOOL_ARGS")

  for path in "${requested_paths[@]}"; do
    match=0
    for approved_path in "${approved_paths[@]}"; do
      [[ "$path" == "$approved_path" ]] && match=1 && break
    done
    [[ "$match" -eq 1 ]] || deny "path not in deletion_paths: $path"
  done

  [[ "$DRY_RUN" == "1" ]] && deny "dry-run mode"
  allow "cat2 manifest-approved deletion"
fi

deny "cat3 manual approval required"
```

Two details to fill in during implementation:

1. `normalize_rm_targets`
   - Responsible for parsing `rm -rf dir/ file1 file2` into a normalized list of paths
2. Frontmatter parsing
   - If `review-manifest.md` is Markdown + YAML frontmatter, you need to extract the frontmatter first before handing it to `yq`

---

## 5. Installation

Recommended to hook into `PreToolUse`:

1. Read the current review manifest path from the environment variable
2. Before deletion, validate `approved`, `approved_sha`, and `deletion_paths`
3. Log, then decide allow / deny

Suggested environment variables:

- `DEAD_CODE_REVIEW_MANIFEST`
- `DEAD_CODE_HOOK_LOG`
- `DEAD_CODE_HOOK_DRY_RUN`

---

## 6. Audit and Dry-Run

Run a dry-run before going live:

1. `DEAD_CODE_HOOK_DRY_RUN=1`
2. Execute one normal round of dead-code-removal
3. Check the log for:
   - Which commands were judged as `Cat1`
   - Which deletion commands matched the manifest
   - Which commands still fell into `Cat3`

The log should record at least:

- Time
- tool / command
- manifest path
- Judged category
- allow / deny reason

---

## 7. Failure Policy

When the Hook cannot make a determination, the default is to downgrade to `Cat3`; do not guess and allow.

In particular, the following situations are never auto-allowed:

- manifest missing
- `approved` is not `true`
- `approved_sha` missing
- current HEAD is not strictly equal to `approved_sha`
- deletion paths include an undeclared file
- batch wildcard deletion cannot be expanded reliably

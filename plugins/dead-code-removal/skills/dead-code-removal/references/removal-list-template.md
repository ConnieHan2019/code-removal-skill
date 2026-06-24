---
approved: false
approved_by: null
approved_at: null
approved_sha: null
input_type: module
deletion_paths:
  - {relative-path-1}
  - {relative-path-2}
---

# Removal Manifest: {interface/module name}

> Execution date: {date}
> Skill version: {version}
> Entry point: {input}

> `approved_sha` semantics: the repo HEAD SHA at the moment of review/approve.
> The hook by default requires `current HEAD == approved_sha` before deletion. If HEAD has changed, you must re-review or update the manifest.

---

## 0. Risk Tiers and Review Focus (TL;DR)

### 0.0 Related Artifacts

> `Supervisor Board`, `Execution Result`, and `Blind Review Result` are independent artifacts by default; they are no longer embedded in the manifest.

- Supervisor Board: `{path/to/supervisor-board.md}`
- Execution Result: `{path/to/execution-result.md | not generated yet}`
- Blind Review Result: `{path/to/blind-review-result.md | not generated yet}`

### 0.1 Overall Risk Rating

`[Low / Medium / High]` — {one-sentence explanation of why this tier: blocker-check result + strength of cross-module coupling + whether it touches shared infrastructure (DB schema / Kafka topic / Redis key / monitoring alerts)}

### 0.2 Safe to Delete Directly (low risk, reviewer can skim quickly)

These items have references closed within the module, no shared infrastructure, and no historical-data compatibility concerns:

| Category | Scope | Why it is safe |
|---|---|---|
| {e.g. "Go packages internal to the module"} | {path} | {grep evidence: 0 external hits} |
| {e.g. "the module's own Dockerfile"} | {path} | {referenced only by its own CI} |

### 0.3 Items Requiring Focused Review by a Human / Another Agent

These items touch shared resources, cross-module dependencies, or semantics that cannot be decided automatically. They **must be confirmed by a human** before entering Step 4:

| Item | Risk | Question for the reviewer |
|---|---|---|
| {e.g. "shared Kafka topic X"} | Whether downstream consumers still need messages produced by this module | {specific question} |
| {e.g. "DB table Y"} | Whether any historical query / BI report still depends on it | {specific question} |
| {e.g. "config key Z"} | Whether other services' toml templates still load it | {specific question} |

> Items here should be compressed as much as possible into "one question = one decision"; do not dump the full analysis process on the reviewer.

### 0.4 Explicitly Not Deleted (boundary preserved)

| Item | Reason for keeping |
|---|---|
| {shared common/ base package} | Used across the whole repo |
| {historical mentions in docs} | Does not affect runtime correctness |

> If something is kept because "the caller is also in the cleanup backlog but the closure has not yet formed", do not write it here; move it into `Needs Closure` instead.

### 0.5 Out of Scope for This PR (handled by others)

| Item | Owner |
|---|---|
| {e.g. DB drop} | DevOps |
| {e.g. k8s deployment removal} | DevOps |
| {e.g. downstream consumer cleanup} | Next PR |

---

## 1. Deletion Set (all referencers are within the deletion scope)

### 1.1 Routes / Entry Points

| File | Line | Content | Note |
|---|---|---|---|
| | | | |

### 1.2 Handler / Worker

| File | Line | Symbol name | Note |
|---|---|---|---|
| | | | |

### 1.3 Service Layer

| File | Line | Symbol name | Referencers (all to be deleted) |
|---|---|---|---|
| | | | |

### 1.4 DAO Layer

| File | Line | Symbol name | Referencers (all to be deleted) |
|---|---|---|---|
| | | | |

### 1.5 Model / Types

| File | Line | Symbol name | Referencers (all to be deleted) |
|---|---|---|---|
| | | | |

### 1.6 Constants / Enums

| File | Line | Symbol name | Referencers (all to be deleted) |
|---|---|---|---|
| | | | |

### 1.7 Config / Tests / Non-code Files

| File | Content | Note |
|---|---|---|
| | | |

---

## 2. Boundary Preserved (still referenced by live code)

| File | Symbol name | Live referencer | Reason for keeping |
|---|---|---|---|
| | | | |

---

## 3. Environment Variables DevOps Must Be Notified to Clean Up

| Variable name | Config location | Note |
|---|---|---|
| | | |

---

## 4. Dependency Graph Visualization

```
{entry handler}
  ├── {service function A}  [delete]
  │    ├── {dao function X}  [delete]
  │    │    └── {model Y}  [delete]
  │    └── {const Z}  [keep: referenced by other.go]
  └── {service function B}  [delete]
       └── {dao function W}  [keep: referenced by active_service.go]
```

---

## 5. Runtime Roots Confirmation

- cmd/main initialization branch: {file:line / decommissioned status}
- Route / gRPC / consumer / cron registration locations: {file:line}
- Implicit entry points (feature flag / map / string dispatch): {description}
- Production / dev deployment status: {reference a backlog / tracking page or k8s manifest}
- Rollback path: {version rollback / config rollback steps}

---

## 6. Expected Acceptance Results (against acceptance-criteria.md)

| ID | Expected |
|---|---|
| V7 directory-name grep | 0 hits (excluding docs/) |
| V8 service-name grep | 0 hits |
| V10 config-key grep | 0 hits |
| V11 Kafka topic | 0 hits |
| V12 Redis key | 0 hits |
| V16 service-inventory / CI service-map file | line removed |
| V17 k8s manifest | removed |
| (everything else covered fully per acceptance-criteria.md) | |

---

## 7. Risks / Caveats

- {cross-module shared-symbol risk}
- {DB table / enum value historical-compatibility risk}
- {monitoring / alerts must be decommissioned in sync}

---

## 8. Permission List (Manifest + Hook)

> By default this now relies on `references/drafts/permission-hook.md`. This section keeps only the manifest and hook conventions; it no longer piles up a static allowlist.

### 8.1 Manifest

- Current `review-manifest.md` path: `{manifest_path}`
- Current batch type: `{input_type}`
- source of truth: the `deletion_paths` in the top frontmatter

### 8.2 Hook Pass Preconditions

- `approved: true`
- `approved_by` / `approved_at` / `approved_sha` are filled in
- `current HEAD == approved_sha` before deletion
- the deletion action matches `deletion_paths`

### 8.3 Still Manual Tier (does not go through hook auto-pass)

`git push` / `gh pr *` / `notion-update-page` / `kubectl|gcloud|aws|production DB` — approve each one separately.

### 8.4 Operating Guide

- Installation and dry-run: see `references/drafts/permission-hook.md`
- If the hook is not ready: keep only the minimal skeleton permissions; do not fall back to a large block of static Bash allowlist.

---

## 9. Review

<!-- After the reviewer approves, append one line, e.g.:
## Review: APPROVED by alice at 2026-04-15
Note: xxx
-->

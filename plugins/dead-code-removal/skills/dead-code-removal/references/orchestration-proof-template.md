# Orchestration Proof

> **status: ACTIVE**. Maintained by the `main thread`, used to prove whether this batch's multi-role process executed according to the contract.
> batch: {date}-{batch-name}
> owner: Main Thread
> mode: `{validation | production}`

## Runtime

- Runtime: `Claude Code Agent SDK`
- Skill version: `{version}`
- Repo SHA at batch start: `{sha}`

## Role Registry

| Role | Agent ID | Created At | fork_context | Reused | Closed At |
|---|---|---|---|---|---|
| Supervisor | | | false | yes/no | |
| Executor | | | false | yes/no | |
| Blind Reviewer | | | false | yes/no | |

## Input Handoffs

| From | To | Allowed Inputs | Actual Inputs Sent | Notes |
|---|---|---|---|---|
| Main Thread | Supervisor | user scope, repo path, references, prior supervisor artifacts | | |
| Main Thread | Executor | supervisor-board, review-manifest, repo path, references | | |
| Main Thread | Blind Reviewer | review-manifest, repo path, blind-review-prompt, execution-result(optional) | | |

## Artifact Chain

| Artifact | Owner Role | Produced By Agent ID | Consumed By | Path |
|---|---|---|---|---|
| `supervisor-board.md` | Supervisor | | Executor / Main Thread | |
| `review-manifest.md` | Supervisor | | Executor / Blind Reviewer / Human Gate | |
| `execution-result.md` | Executor | | Blind Reviewer / Main Thread | |
| `blind-review-result.md` | Blind Reviewer | | Main Thread / Human Gate | |

## Validation Checks

### Contract Checks

- Distinct agent IDs for all 3 roles: `{pass/fail}`
- All role spawns used `fork_context=false`: `{pass/fail}`
- Main thread did not forward full history: `{pass/fail}`
- No cross-role agent reuse: `{pass/fail}`
- Required artifacts all produced: `{pass/fail}`

### Canary Check

- Canary ID: `{optional}`
- Canary location: `{supervisor-private note / main-thread-only note / N/A}`
- Roles allowed to know canary: `{list}`
- Canary leaked into downstream artifacts: `{pass/fail}`
- Evidence: `{grep result or manual note}`

### Disagreement-Path Check

- Trigger type: `{natural finding | seeded issue | N/A}`
- Reviewer outcome: `{Proceed | Revise manifest | Split batch | Block}`
- Did reviewer surface a non-trivial delta or challenge: `{pass/fail}`
- Evidence: `{finding summary}`

## Final Verdict

- Validation mode contract: `{pass/fail}`
- If fail, which rule broke:
  - {rule}
- Follow-up required before reusing this run as proof:
  - {action}

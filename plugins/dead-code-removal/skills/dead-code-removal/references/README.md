# References Index

Single entry point for `references/`. Every doc ships in two languages: `<name>.md` (English, primary) and `<name>.zh.md` (Chinese).

## Active (current execution contract)

- `agent-orchestration-workflow.md` — the 3-role / 4-artifact collaboration spec
- `executor-prompt-template.md` — hard-rule template that MUST be injected when spawning the Executor
- `supervisor-checklist.md` — Supervisor triage & escalation behavior
- `blind-review-prompt.md` — the Blind Reviewer prompt contract
- `runtime-validation-checklist.md` — multi-role runtime validation checklist
- `acceptance-criteria.md` — the Review Gate / Step 6 hard acceptance bar
- `permission-template.md` — the diff-first permission scheme
- `removal-list-template.md` — the `review-manifest.md` template
- `execution-result-template.md` — the `execution-result.md` template
- `orchestration-proof-template.md` — the `orchestration-proof.md` template
- `supervisor-board-template.md` — the `supervisor-board.md` template
- `blind-review-result-template.md` — the `blind-review-result.md` template
- `eval-checklist.md` — post-run scoring (correctness / completeness / isolation / contract quality)
- `iteration-template.md` — the iteration-record template

## Drafts / Not-yet-implemented (`drafts/`)

- `drafts/permission-hook.md` — future Hook design; not implemented in v0.1
- `drafts/langgraph-implementation-design.md` — externalized-orchestration contract spec; the runtime does not depend on it

## Suggested read order

1. `agent-orchestration-workflow.md`
2. `executor-prompt-template.md`
3. `runtime-validation-checklist.md`
4. `supervisor-checklist.md`
5. `removal-list-template.md`
6. `blind-review-prompt.md`
7. `acceptance-criteria.md`
8. `permission-template.md`

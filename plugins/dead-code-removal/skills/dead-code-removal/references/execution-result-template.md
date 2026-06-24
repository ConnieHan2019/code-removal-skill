# Execution Result

> **status: independent artifact by default**. Maintained by the `Executor`, records the actual execution result, acceptance evidence, and any deviations from the manifest.
> batch: {date}-{batch-name}
> owner: Executor
> agent_id: {agent_id}
> fork_context: false

## Scope

- Manifest path: `{path/to/review-manifest.md}`
- Executed against SHA: `{repo_head_sha}`

## Actions Performed

- {which directories / files / symbols were deleted}
- {which configs / metadata were updated}

## Acceptance Results

- `scripts/build-check.sh`: {pass | fail | pre-existing fail}
- `scripts/vet-check.sh`: {pass | fail | pre-existing fail}
- `scripts/tidy-check.sh`: {pass | fail | skipped with reason}
- V7 / V8 / V10 / V11 / V12 grep: {result}

## Deviations Against Manifest

- Missing execution:
  - {items required by the manifest but not yet executed}
- Extra execution:
  - {items executed but not explicitly permitted by the manifest}
- Blockers:
  - {blockers preventing further progress}

## Proposed Manifest Delta

- {if a boundary conflicts with reality, write a revision proposal; otherwise write "none"}

## Notes

- {additional notes}

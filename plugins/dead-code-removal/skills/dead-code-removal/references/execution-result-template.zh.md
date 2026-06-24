# Execution Result

> **status: 默认独立工件**。由 `Executor` 维护，记录实际执行结果、验收证据以及对 manifest 的偏差说明。
> batch: {date}-{batch-name}
> owner: Executor
> agent_id: {agent_id}
> fork_context: false

## Scope

- Manifest path: `{path/to/review-manifest.md}`
- Executed against SHA: `{repo_head_sha}`

## Actions Performed

- {删除了哪些目录 / 文件 / 符号}
- {更新了哪些配置 / 元数据}

## Acceptance Results

- `scripts/build-check.sh`: {pass | fail | pre-existing fail}
- `scripts/vet-check.sh`: {pass | fail | pre-existing fail}
- `scripts/tidy-check.sh`: {pass | fail | skipped with reason}
- V7 / V8 / V10 / V11 / V12 grep: {结果}

## Deviations Against Manifest

- Missing execution:
  - {manifest 要求但尚未执行的项}
- Extra execution:
  - {执行了但 manifest 未明确允许的项}
- Blockers:
  - {导致无法继续的阻塞}

## Proposed Manifest Delta

- {如发现边界与现实冲突，写修订建议；否则写 "none"}

## Notes

- {补充说明}

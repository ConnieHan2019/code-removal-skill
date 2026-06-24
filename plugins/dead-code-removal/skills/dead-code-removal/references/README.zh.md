# References 索引

`references/` 的单一入口。每份文档都有两个语言版本：`<name>.md`（英文，主版）和 `<name>.zh.md`（中文）。

## Active（当前执行 contract）

- `agent-orchestration-workflow.md` — 3 角色 / 4 工件协作规范
- `executor-prompt-template.md` — spawn Executor 时必须注入的硬规则模板
- `supervisor-checklist.md` — Supervisor 分诊与升级行为
- `blind-review-prompt.md` — Blind Reviewer prompt contract
- `runtime-validation-checklist.md` — 多角色运行验证清单
- `acceptance-criteria.md` — Review Gate / Step 6 验收硬门槛
- `permission-template.md` — diff-first 权限方案
- `removal-list-template.md` — `review-manifest.md` 模板
- `execution-result-template.md` — `execution-result.md` 模板
- `orchestration-proof-template.md` — `orchestration-proof.md` 模板
- `supervisor-board-template.md` — `supervisor-board.md` 模板
- `blind-review-result-template.md` — `blind-review-result.md` 模板
- `eval-checklist.md` — 运行后评分（正确性 / 完整性 / 隔离 / contract 质量）
- `iteration-template.md` — 迭代记录模板

## Draft / 未实现（`drafts/`）

- `drafts/permission-hook.md` — 未来 Hook 设计稿，v0.1 未实现
- `drafts/langgraph-implementation-design.md` — 外置编排 contract spec，runtime 不依赖它执行

## 建议阅读顺序

1. `agent-orchestration-workflow.md`
2. `executor-prompt-template.md`
3. `runtime-validation-checklist.md`
4. `supervisor-checklist.md`
5. `removal-list-template.md`
6. `blind-review-prompt.md`
7. `acceptance-criteria.md`
8. `permission-template.md`

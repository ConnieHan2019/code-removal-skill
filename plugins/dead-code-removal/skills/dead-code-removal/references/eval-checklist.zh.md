# Cleanup Run Evaluation Checklist

> **status: ACTIVE**。这是当前 skill 的事后评分 contract。
> 用途：在一次 cleanup batch 跑完后，对结果质量和流程质量做统一复盘；输出写入 `iterations/{序号}-{模块或批次名}.md`。
> 这不是执行期规则来源。执行期 contract 以 `agent-orchestration-workflow.md`、`removal-list-template.md`、`blind-review-prompt.md`、`acceptance-criteria.md` 为准。

---

## 1. 评估输入

本表默认对以下工件做联合评估：

1. `orchestration-proof.md`（validation mode 下必需）
2. `supervisor-board.md`
3. `review-manifest.md`
4. `execution-result.md`
5. `blind-review-result.md`
6. `iterations/{序号}-{模块或批次名}.md`

如果某一工件缺失，不要跳过评分；应在相应条目记为未通过，并写明缺失原因。

---

## 2. 评分维度

总分 32 分，分 5 个维度：

1. **Correctness / 正确性** — 8 分
2. **Completeness / 完整性** — 8 分
3. **Isolation / 隔离与角色纪律** — 7 分
4. **Contract Quality / 工件与流程合同质量** — 7 分
5. **Metrics / 指标完整性** — 2 分

建议结论：

- `30–32`：一次成功，可作为高质量样板
- `26–29`：通过，但仍有流程或工件缺口
- `20–25`：勉强通过，必须在下一轮修流程
- `<20`：不应视为可复用流程，需回退或重构 contract

硬门槛：

- 任一"致命项"失败，本轮不得标记为"一次成功"
- 致命项包括：`C1`、`C2`、`I1`、`I2`、`Q1`、`M1`

---

## 3. Correctness / 正确性（8）

> 关注“有没有删错、删坏、删出 side effect”。

| # | 检查项 | 方法 | 分值 | 结果 |
|---|---|---|---|---|
| C1 | 删除后 `build-check.sh` 通过，或仅剩明确列出的 pre-existing fail | 对照 `execution-result.md` 与 base | 2 | |
| C2 | `vet-check.sh` 无新增问题，或新增问题已被明确归因为 pre-existing | 对照 `execution-result.md` | 1 | |
| C3 | 未误删仍被活代码引用的符号 | 看 build/vet/grep 证据与 blind review findings | 2 | |
| C4 | 未误删 runtime roots 仍会触发的入口、注册、consumer、cron、feature flag | 对照 manifest + blind review | 1 | |
| C5 | 未误删历史兼容必需的常量 / 枚举 / init side effects | 对照 boundary retains 与 blind review | 1 | |
| C6 | 若涉及共享代码，仍保留服务的行为未被破坏，或已明确说明为什么可判 N/A | 对照 acceptance V20–V23 / notes | 1 | |

致命失败示例：

- build 失败且失败点与本轮删除有关
- blind reviewer 明确指出存在误删证据
- 删除后仍有 runtime root 指向已删对象

---

## 4. Completeness / 完整性（8）

> 关注“有没有删少、有没有留孤儿、非代码残留是否清干净”。

| # | 检查项 | 方法 | 分值 | 结果 |
|---|---|---|---|---|
| P1 | manifest 覆盖了入口点、核心调用链和删除集合 | 对照 `review-manifest.md` | 1 | |
| P2 | manifest 覆盖了边界保留项，且每项都有存活引用方或明确保留原因 | 对照 `review-manifest.md` | 1 | |
| P3 | 非代码残留检查完整：配置、测试、Dockerfile/Makefile、CI 映射、topic、Redis key、env 等 | 对照 manifest + execution result | 1 | |
| P4 | 残留 grep（V7–V19）结果为空或仅剩合理文档保留 | 对照 `execution-result.md` | 2 | |
| P5 | 不存在只被待删代码引用的孤儿符号残留 | 看 blind review / grep / notes | 1 | |
| P6 | 未留下“注释掉但不删除”的僵尸代码 | 看 diff 与 execution notes | 1 | |
| P7 | .code-removal/ 元数据已同步，不污染后续 session | 对照 execution result | 1 | |

---

## 5. Isolation / 隔离与角色纪律（7）

> 关注“是不是按 3-subagent / 4-artifact 模型真的跑了，而不是名义多角色、实则单线程大上下文”。

| # | 检查项 | 方法 | 分值 | 结果 |
|---|---|---|---|---|
| I1 | `Supervisor / Executor / Blind Reviewer` 为独立 agent，不是同一上下文串演 | 对照 `orchestration-proof.md` / 运行记录 / notes | 2 | |
| I2 | 三角色创建时都使用 `fork_context=false`，main thread 未把完整历史转交给任何角色 | 对照 `orchestration-proof.md` / 运行记录 / notes | 2 | |
| I3 | main thread 只做路由与 Human Gate，不直接拥有业务判断或代写角色结论 | 对照 notes 与工件所有权 | 1 | |
| I4 | 角色之间只通过允许工件流转，没有泄漏推理草稿、预期结论、怀疑点 | 对照 prompts / notes | 1 | |
| I5 | 角色复用符合 contract：同角色可续跑，跨角色不复用同一个 agent | 对照 `orchestration-proof.md` / 运行记录 / notes | 1 | |

致命失败示例：

- `Blind Reviewer` 不是独立 agent
- `fork_context=true` 把父线程历史带给 reviewer
- main thread / supervisor 代写 blind review 结论

---

## 6. Contract Quality / 工件与流程合同质量（7）

> 关注“工件是否足够支撑独立角色工作，流程是否能被复跑和审计”。

| # | 检查项 | 方法 | 分值 | 结果 |
|---|---|---|---|---|
| Q1 | `review-manifest.md` 足够定义 cleanup 合同：范围、保留边界、验收口径、风险约束清楚 | 对照 manifest | 2 | |
| Q2 | manifest 所有权清晰：由 `Supervisor` 产出并拥有，`Executor` 只提 delta | 对照工件与 notes | 1 | |
| Q3 | `execution-result.md` 足够说明实际执行、验收结果与偏差，其他角色可据此复核 | 对照 execution result | 1 | |
| Q4 | `blind-review-result.md` 能明确区分“manifest 问题”与“execution 问题” | 对照 blind review result | 1 | |
| Q5 | `supervisor-board.md` 足够支持状态机路由，`Next / Blocked / Needs Human` 不含模糊甩锅表述 | 对照 supervisor board | 1 | |
| Q6 | iteration 记录能把本轮缺陷回灌到 skill，而不是只记录代码结果 | 对照 iteration | 1 | |
| Q7 | validation mode 下存在完整的 `orchestration-proof.md`，能证明 agent、handoff、canary、disagreement-path | 对照 orchestration proof | 0* | |

致命失败示例：

- manifest 不能支撑独立 executor 施工
- blind review 结论无法判断应打回 supervisor 还是 executor
- 缺少关键工件，导致流程不可审计

`Q7` 不单独计分，但在 validation mode 下若失败，应视为 contract quality 重大缺口。

---

## 6.5 Metrics / 指标完整性（2）

> 关注"本轮是否产出可被未来汇总的性能数据"。

| # | 检查项 | 方法 | 分值 | 结果 |
|---|---|---|---|---|
| M1 | `runs/{date}-{batch}/metrics.md` 存在且 5 段（durations / tokens / code_delta / acceptance / blind_review_findings）字段完整 | 对照 metrics 模板 | 1 | |
| M2 | metrics 数据可信：`durations` 来自 Agent tool result `duration_ms`，`tokens` 来自 `usage.*`，`blind_review_findings` 计数与 `blind-review-result.md` finding ID 列表一致 | 与 tool result / blind review 交叉比对 | 1 | |

致命失败示例：

- `metrics.md` 缺失或仅有标题（M1 fail）
- `durations` 由 subagent 自报（subagent 无可信 wall-clock）
- finding 计数与 blind review 不一致（数据自欺）

`M1` 是致命项——本轮不得标记为"一次成功"。

---

## 7. 最终汇总格式

将评分结果写入 iteration 的“评估结果”区，格式如下：

```text
Correctness:      {passed}/8
Completeness:     {passed}/8
Isolation:        {passed}/7
Contract Quality: {passed}/7
Metrics:          {passed}/2
Total:            {passed}/32

Conclusion: [一次成功 | 通过但需补流程 | 勉强通过 | 不应复用当前流程]
Fatal checks:
- C1: pass/fail
- C2: pass/fail
- I1: pass/fail
- I2: pass/fail
- Q1: pass/fail
- M1: pass/fail
```

---

## 8. 必记复盘项

无论总分多少，每轮 iteration 至少要回答这 5 个问题：

1. 本轮最接近误删或漏删的风险点是什么
2. 该风险最终是被谁发现的：Supervisor / Executor / Blind Reviewer / Human
3. 如果去掉某个工件，本轮最先失效的会是哪一步
4. 本轮最值得固化进 skill 的 contract 改动是什么
5. 下轮若处理相似模块，哪一条检查应该前移

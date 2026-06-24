# Runtime Validation Checklist

> **status: ACTIVE**。用途不是检查“代码删得对不对”，而是检查“多角色流程是否真的按设计执行”。
> 在 skill 尚未被证明稳定前，建议每一轮真实 batch 都按本清单运行；至少前 3 轮必须开启 `validation mode`。

---

## 1. 目标

本清单验证 4 件事：

1. 角色是否真的是独立 agent，而不是主线程串演
2. 输入边界是否被 main thread 严格控制
3. blind review 是否具备真实反证能力，而不是礼貌复述
4. 工件链是否足以支持复跑、审计和追责

---

## 2. Validation Mode 必备工件

除常规 4 工件外，还必须存在：

1. `orchestration-proof.md`
2. `iteration.md`

推荐目录：

```text
.code-removal/runs/{date}-{batch-name}/
├── orchestration-proof.md
├── supervisor-board.md
├── review-manifest.md
├── execution-result.md
└── blind-review-result.md
```

---

## 3. 运行前检查

- [ ] 本轮标记为 `validation mode`
- [ ] main thread 计划为 3 个角色分别 `spawn_agent(..., fork_context=false)`
- [ ] 已确定 3 个角色的输入白名单
- [ ] 已准备 `orchestration-proof.md`

---

## 4. 运行中检查

### 4.1 Role Identity

- [ ] `Supervisor`、`Executor`、`Blind Reviewer` 的 agent ID 三者不同
- [ ] 同一 agent 未跨角色复用
- [ ] 仅在“同角色续跑”时使用 `send_input`

### 4.2 Input Discipline

- [ ] Main thread 未把完整线程历史传给任何角色
- [ ] `Supervisor` 只收到其白名单输入
- [ ] `Executor` 只收到其白名单输入
- [ ] `Blind Reviewer` 只收到其白名单输入
- [ ] `Executor` prompt 明确写了"验收优先调用 `build-check.sh` / `vet-check.sh` / `module-gone-check.sh` / `tidy-check.sh`"
- [ ] `Executor` prompt 明确禁止复合 Bash 验收（如 `go build | grep | tail ; echo ...`）

### 4.3 Artifact Ownership

- [ ] `supervisor-board.md` 由 Supervisor 产出
- [ ] `review-manifest.md` 由 Supervisor 创建并拥有
- [ ] `execution-result.md` 由 Executor 产出
- [ ] `blind-review-result.md` 由 Blind Reviewer 产出
- [ ] main thread 未代写任一角色结论

### 4.4 Output Consumption（输出消费链路）

- [ ] main thread 路由到 Executor 前，已读取 `supervisor-board.md` 路由状态 + `review-manifest.md` 边界
- [ ] main thread 路由到 Blind Reviewer 前，已读取 `execution-result.md` 验收结果
- [ ] main thread 路由到 Human Gate 前，已读取 `blind-review-result.md` 的明确结论
- [ ] 每一次状态转移都能在 `orchestration-proof.md` handoff 段或路由日志里指回具体工件段落（不是只写 "Supervisor 完成"）
- [ ] 没有跳步：未先看 `blind-review-result.md` 就直接放行 Human Gate / Done 视为 contract fail

### 4.5 Metrics 完整性

- [ ] `runs/{date}-{batch}/metrics.md` 存在且按 metrics 模板填写
- [ ] `durations` 段非空：supervisor / executor / blind_reviewer / human_overhead 至少都有值（可填 0 但不可省）
- [ ] `tokens` 段非空：每角色 input / output / cache_read 三项均有数值
- [ ] `code_delta` 段：`files_changed` / `lines_added` / `lines_removed` 已填，与 `git diff --stat` 一致
- [ ] `acceptance` 段：build-check.sh / vet-check.sh / tidy-check.sh 的 pass/fail 各自记录
- [ ] `blind_review_findings` 段：按 severity (blocker/major/nit) 计数，并引用 finding ID (F-01 等)
- [ ] Metrics 数据来源是 Agent tool result（`duration_ms` + `usage.*`），不是 subagent 自报
- [ ] **未写 `metrics.md` 视为 batch contract fail**——main thread 不得宣布 batch 完成

---

## 5. 对抗式验证

### 5.1 Canary Check

目的：验证未授权信息不会自然扩散到下游角色。

做法：

1. 在 main thread 或 supervisor-private note 中放一个**只应被上游知道**的 canary 字符串
2. 不将该 note 作为允许工件传给下游角色
3. 运行完成后检查：
   - `execution-result.md`
   - `blind-review-result.md`
   - iteration

通过标准：

- [ ] canary 字符串未出现在任何下游工件中

说明：

- 这是“泄漏检测”，不是绝对安全证明
- 若 canary 泄漏，视为 contract fail

### 5.2 Disagreement-Path Check

目的：验证 blind reviewer 会反证，而不是顺着 manifest 走。

做法：

1. 优先依赖真实自然发现
2. 若该轮目标过于简单，可人为选择一个更容易暴露边界问题的模块或刻意保留一个轻微可疑点供 reviewer 审查

通过标准：

- [ ] reviewer 至少给出一条实质性 finding，或明确写出“未发现可推翻 manifest 的证据”的完整反证链
- [ ] 若 reviewer 要求 `Revise manifest` / `Split batch` / `Block`，main thread 能正确路由

说明：

- skill 达到 stable 之前，至少要有 1 轮成功的 disagreement-path 证据

---

## 6. 运行后检查

- [ ] `orchestration-proof.md` 已完整填写
- [ ] `eval-checklist.md` 中的 `Isolation` 和 `Contract Quality` 能据此打分
- [ ] iteration 中已记录本轮最重要的流程缺陷
- [ ] 如 validation fail，本轮不得作为“多角色流程已验证”的证明样本

---

## 7. 通过定义

本轮只有同时满足以下条件，才能宣称“流程验证通过”：

1. `orchestration-proof.md` 的 contract checks 全部通过
2. Canary check 通过
3. Blind review 没有被 main thread / supervisor 代写
4. `eval-checklist.md` 的 `Isolation` 维度无致命失败
5. `eval-checklist.md` 的 `Contract Quality` 无 `Q1` 致命失败

---

## 8. 何时可以退出 Validation Mode

建议满足以下条件后，才允许把 validation mode 从“默认强制”降为“按需开启”：

1. 连续 3 轮真实模块 run 通过本清单
2. 至少 1 轮存在 reviewer 成功 challenge manifest 的 disagreement-path 证据
3. 未出现 canary 泄漏
4. 未出现 main thread 代写角色结论

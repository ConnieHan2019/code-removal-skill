# Multi-Agent Orchestration Workflow

> 目标：把 dead-code-removal skill 从“单 agent 按流程做事”升级为“3 个固定角色通过工件协作”。
> 重点不是让更多 agent 一起聊天，而是让角色之间只通过**最小必要工件**交接，减少上下文污染。
> **当前机制层**: Claude Code Agent SDK（`spawn_agent` / `send_input` / `wait_agent`）。
> **如未来外置编排**: contract spec 见 `references/drafts/langgraph-implementation-design.md`（保留为合同设计稿，目前不依赖任何 LangGraph 代码）。

---

## 1. 角色与主线程

### Main Thread

主线程不是 `Supervisor / Executor / Blind Reviewer` 中的任何一个。

职责：

1. 接收用户输入
2. 创建 / 复用 / 关闭角色 agent
3. 按状态机路由工件
4. 处理 Human Gate 与最终汇报

约束：

1. 不拥有业务判断权
2. 不直接定义 cleanup 边界
3. 不把自己的完整历史传给任何角色

持有的状态（必须跨 phase 保留，缺一不可）：

1. `batch_id` 与 `runs/{date}-{batch-name}/` 目录路径
2. 当前状态机位置（参见 §6）
3. 角色注册表：每个 spawn 过的 agent 的 `role` / `agent_id` / `spawned_at` / `fork_context` / `status`
4. 最新工件路径：`supervisor-board.md` / `review-manifest.md` / `execution-result.md` / `blind-review-result.md` / `orchestration-proof.md`
5. Human Gate 决定：`approve` / `reject` / `revise` + 时间戳 + `approved_sha`

不持有（即使能拿到也禁止跨阶段持有）：

- 任意角色的完整推理历史
- 任意角色的过程草稿
- 跨 batch 的业务结论

换言之，main thread 持有的是**流程状态**，而不是**角色脑内状态**。

### Supervisor

职责：

1. 读取待清理池
2. 产出 `supervisor-board.md`
3. 创建并拥有 `review-manifest.md`
4. 决定哪些对象是：
   - `Ready`
   - `Needs Closure`
   - `Blocked (external refs)`
   - `Blocked (refactor needed)`
   - `Needs Human`
5. 只在通过 `Escalation Gate` 后才升级给用户
6. 决定是否采纳 `Executor` / `Blind Reviewer` 的修订建议

产物：

- `supervisor-board.md`
- `review-manifest.md`

### Executor

职责：

1. 基于已生效的 `review-manifest.md` 执行 Step 0–6
2. 如果发现 manifest 与代码现实不一致，提交修订建议
3. 产出执行结果与验收证据
4. 不直接改写 cleanup 合同边界

执行硬规则：

1. 验收动作优先调用固定脚本：
   - `scripts/build-check.sh`
   - `scripts/vet-check.sh`
   - `scripts/module-gone-check.sh <module-dir>`
   - `scripts/tidy-check.sh`
2. 禁止把 `go build`、`go vet`、`tee`、`echo`、`ls`、`head`、`tail` 拼成一条复合 Bash
3. 禁止在 Claude 的 Bash 调用里临时写 `GOCACHE=$TMPDIR...`、`GOMODCACHE=...`、`GOPROXY=...`、`GOFLAGS=...` 这类前缀
4. 如需过滤 pre-existing 噪音，先运行脚本，再单独读取脚本生成的日志文件；不要在执行命令尾部追加 `| grep -v ... | tail -N`

产物：

- `execution-result.md`
- `iteration.md`

### Blind Reviewer

职责：

1. 只基于既定工件做反证审查
2. 重跑 7 类间接引用扫描
3. 判断 manifest 是否站得住，执行结果是否偏离 manifest
4. 给出 `Blind Review Result`

产物：

- `blind-review-result.md`

---

## 2. 上下文边界

核心原则：

1. 三个角色必须运行在**独立上下文**
2. `fork_context=false` 是默认硬规则
3. 角色之间不共享完整线程历史
4. 角色之间不直接对话，只通过文件工件交接
5. 同一角色可保留自己的连续上下文，供后续续跑
6. 角色职责变化时，必须新开 agent，不允许复用旧 agent 冒充别的角色

实现备注：

1. 本文定义的是协作规范，机制层无关
2. 当前实现建议：
   - `Supervisor` → `spawn_agent(..., fork_context=false)`
   - `Executor` → `spawn_agent(..., fork_context=false)`
   - `Blind Reviewer` → `spawn_agent(..., fork_context=false)`
3. 隔离主要依靠：
   - 新 agent 身份
   - `fork_context=false`
   - 最小工件白名单
4. 当前 runtime 不提供文件系统级 ACL；因此“信息盲”是**会话级强隔离 + 工件级最小披露**，不是仓库级绝对隔离

---

## 3. 工件合同

默认拆成 4 个独立工件：

```text
.code-removal/runs/{date}-{batch-name}/
├── supervisor-board.md
├── review-manifest.md
├── execution-result.md
└── blind-review-result.md
```

如需长期留档，可额外产出：

- `.code-removal/reviews/{date}-{batch-name}.md`
- `.code-removal/skill/iterations/{n}-{topic}.md`

在 `validation mode` 下，额外要求：

```text
.code-removal/runs/{date}-{batch-name}/
└── orchestration-proof.md
```

### 3.1 supervisor-board.md

用途：

1. 记录分诊结果
2. 记录当前 batch 的状态分组
3. 说明下一步路由与升级结论

### 3.2 review-manifest.md

用途：

1. 作为 cleanup batch 的控制面合同
2. 定义：
   - 清理什么
   - 不清理什么
   - 依据是什么
   - 验收口径是什么
   - 风险约束是什么

所有权：

- 只能由 `Supervisor` 创建和批准修订
- `Executor` 只能提交修订建议
- `Blind Reviewer` 只能基于其审查，不得代写边界定义

### 3.3 execution-result.md

用途：

1. 记录 `Executor` 实际做了什么
2. 记录 `build-check.sh` / `vet-check.sh` / grep / `tidy-check.sh` 等验收结果
3. 记录与 manifest 的偏差、失败点与修订建议

### 3.4 blind-review-result.md

用途：

1. 记录 `Blind Reviewer` 的反证结论
2. 说明 manifest 是否充分
3. 如有必要，指出执行结果是否偏离 manifest

### 3.5 orchestration-proof.md

用途：

1. 记录 role registry、agent IDs、`fork_context`、输入交接
2. 记录 canary check 与 disagreement-path check
3. 证明本轮多角色流程是否按 contract 执行

---

## 4. 输入白名单

### 4.1 Supervisor 允许输入

1. 用户任务范围
2. 仓库路径
3. 必要参考文档
4. 历史 `supervisor-board.md`
5. 本角色自己的增量记录
6. 仅在状态机显式要求返工时读取：
   - `execution-result.md`
   - `blind-review-result.md`

默认不应输入：

- 主线程完整历史
- `Executor` 的完整过程草稿
- `Blind Reviewer` 的过程性推理

### 4.2 Executor 允许输入

1. `supervisor-board.md`
2. `review-manifest.md`
3. 当前代码库
4. `acceptance-criteria.md`（验收硬门槛）
5. `removal-list-template.md`（manifest 字段模板，仅供格式对照）
6. `execution-result-template.md`（输出模板）
7. `executor-prompt-template.md`（Non-Negotiable Rules 必须出现在 spawn prompt 内）
8. 仅在状态机显式要求返工时读取：本角色自己之前的 `execution-result.md`

默认不应输入：

- `Supervisor` 的完整对话
- `Blind Reviewer` 的完整对话
- 主线程历史

### 4.3 Blind Reviewer 允许输入

默认输入：

1. `review-manifest.md`
2. 当前代码库
3. `blind-review-prompt.md`

仅在需要审查执行偏差时追加：

4. `execution-result.md`

默认不应输入：

- `Supervisor` 的推理草稿
- `Executor` 的预设结论
- 主线程完整历史

---

## 5. 文件驱动的主流程

### Phase 0 — Batch 初始化

**触发条件**

- 用户给出模块目录、HTTP 批次、一个 backlog / 跟踪页面或 review 文档

**输入**

- 用户原始请求
- 仓库路径
- 当前 skill references

**Main Thread 动作**

1. 创建 `runs/{date}-{batch-name}/` 目录
2. 决定本轮是否启用 `validation mode`（参见 §9，stable 之前默认强制启用）
3. 若启用 validation mode：初始化 `orchestration-proof.md` 壳子
   - role registry 表头
   - handoff log 表头
   - canary 字段（若本轮做 canary check）
4. 在 main thread 内部 state 上登记 `batch_id`、目录路径、状态机起点 `NEW_BATCH`

**输出**

- 初始化完毕的 batch 目录
- `orchestration-proof.md`（仅 validation mode）
- 进入 Phase A 的就绪信号

**约束**

- Phase 0 不调用任何业务角色 agent
- Phase 0 不做 cleanup 边界判断
- Phase 0 不写任何业务工件（`supervisor-board.md` / `review-manifest.md` 都属于 Phase A）

### Phase A — Supervisor 分诊

输入：

- 用户给定的模块 / HTTP 批次 / backlog / 跟踪页面

动作：

1. `Supervisor` 分析待清理池
2. 写入 `supervisor-board.md`
3. 生成或修订 `review-manifest.md`

输出最少包含：

- 当前待执行对象
- 对象状态分组
- cleanup 边界
- 下一步建议
- `Needs Human`
- `Skill Follow-ups`

### Phase B — Executor 执行合同

输入：

- `supervisor-board.md`
- `review-manifest.md`
- 当前代码库

动作：

1. 只处理 `Supervisor` 已标记为 `Ready` 或已明确闭包的对象
2. 按 manifest 执行 Step 0–6
   - 编译校验只跑 `scripts/build-check.sh`
   - vet 校验只跑 `scripts/vet-check.sh`
   - 目录消失校验只跑 `scripts/module-gone-check.sh <module-dir>`
   - 依赖清理只跑 `scripts/tidy-check.sh`
3. 写入 `execution-result.md`
4. 如果发现边界与现实冲突，写入修订建议并退回 `Supervisor`
5. main thread 组装 executor prompt 时，必须显式包含 `executor-prompt-template.md` 的 Non-Negotiable Rules

### Phase C — Blind Review

输入：

- `review-manifest.md`
- 当前代码库
- `blind-review-prompt.md`
- `execution-result.md`（仅在需要审查执行偏差时）

动作：

1. `Blind Reviewer` 独立审查
2. 产出 `blind-review-result.md`

### Phase D — Human Gate + Batch 收尾

输入：

- `review-manifest.md`
- `blind-review-result.md`
- `execution-result.md`（如需查看执行证据）

动作：

1. 只有这时才回到用户
2. 用户只对"剩余决策"做拍板
3. approval 后更新：
   - `approved: true`
   - `approved_by`
   - `approved_at`
   - `approved_sha`
4. **Batch 收尾：main thread 必须记录本 batch 的 metrics**
   - 从 Agent tool result 读取每角色 `duration_ms` / `usage.input_tokens` / `usage.output_tokens` / `usage.cache_read_input_tokens`
   - 不要让 subagent 自己回报耗时——subagent 没有可信 wall-clock
   - 强制字段：`durations` / `tokens` / `code_delta` / `acceptance` / `blind_review_findings`
   - finding 计数从 `blind-review-result.md` 按 severity 汇总

约束：

1. `Needs Human` 不是兜底状态
2. 只有通过 `Escalation Gate` 的问题才能进入 `Human Gate`
3. Human Gate 只读最小必要摘要，不读完整多角色对话历史
4. **未记录 batch metrics 不视为 batch 完成**——`runtime-validation-checklist.md` §4.x 会拦下

---

## 6. 推荐状态机

- `NEW_BATCH`
- `SUPERVISOR_TRIAGE`
- `EXECUTOR_EXECUTE`
- `BLIND_REVIEW`
- `MANIFEST_REVISION_REQUIRED`
- `EXECUTION_REVISION_REQUIRED`
- `HUMAN_GATE`
- `DONE`
- `BLOCKED`

转移规则：

1. `NEW_BATCH -> SUPERVISOR_TRIAGE`
2. `SUPERVISOR_TRIAGE -> EXECUTOR_EXECUTE`
   - 条件：对象为 `Ready` 或闭包已明确
3. `EXECUTOR_EXECUTE -> BLIND_REVIEW`
   - 条件：execution result 已产出
4. `BLIND_REVIEW -> HUMAN_GATE`
   - 条件：`PASS` 或 `PASS WITH NOTES`
5. `BLIND_REVIEW -> MANIFEST_REVISION_REQUIRED`
   - 条件：边界定义、保留项、deletion_paths、验收合同存在问题
6. `BLIND_REVIEW -> EXECUTION_REVISION_REQUIRED`
   - 条件：manifest 成立，但执行偏差或验收失败
7. `MANIFEST_REVISION_REQUIRED -> SUPERVISOR_TRIAGE`
8. `EXECUTION_REVISION_REQUIRED -> EXECUTOR_EXECUTE`
9. `HUMAN_GATE -> DONE | BLOCKED`

### 6.1 Blind Review finding → 状态机映射

`blind-review-result.md` 的口径与状态机的对应关系如下：

| Blind Review 结论 | 含义 | 状态机转移 |
| --- | --- | --- |
| `PASS` | 没有 finding，manifest 与 execution 都站得住 | `BLIND_REVIEW -> HUMAN_GATE` |
| `PASS WITH NOTES` | 有非阻塞 finding（如建议、风格、跟进） | `BLIND_REVIEW -> HUMAN_GATE`（notes 写入 Human Gate 摘要） |
| `FAIL — manifest issue`（finding 证明 batch / 边界 / deletion_paths / 验收口径不成立） | manifest 本身需要修订 | `BLIND_REVIEW -> MANIFEST_REVISION_REQUIRED -> SUPERVISOR_TRIAGE` |
| `FAIL — execution issue`（manifest 成立，但执行偏差或验收失败） | 仅 executor 端需要重做 | `BLIND_REVIEW -> EXECUTION_REVISION_REQUIRED -> EXECUTOR_EXECUTE` |
| `FAIL — split batch`（多模块强行并组导致回滚面过大） | 视为 manifest issue 的子类 | `BLIND_REVIEW -> MANIFEST_REVISION_REQUIRED -> SUPERVISOR_TRIAGE` |

约束：

1. main thread 必须在路由日志（或 `orchestration-proof.md` handoff 段）里写明触发了哪一行
2. 同一份 `blind-review-result.md` 只能映射到一条转移；若 reviewer 同时给出多类 finding，按最严重一类（manifest issue > execution issue > notes）路由
3. 若 reviewer 结论无法对应到上表任何一行，main thread 不得自行擅自归类，应回到 supervisor 重读 manifest

---

## 7. Agent 生命周期

### 7.1 创建角色

第一次创建角色时：

- `spawn_agent(fork_context=false, ...)`

### 7.2 角色续跑

如果角色只是继续本角色职责：

- `send_input(target=<same_agent_id>, ...)`

可复用场景：

1. `Supervisor` 补充分诊
2. `Executor` 根据 reviewer 反馈重跑执行
3. `Blind Reviewer` 对同一 batch 新版本再次审查

### 7.3 关闭角色

角色不再需要时：

- `close_agent(...)`

不要复用的场景：

1. 让 `Executor` 接着扮演 `Blind Reviewer`
2. 让 `Supervisor` 直接接 `Executor` 的实现上下文
3. 同一 agent 同时承担两个角色

---

## 8. 最小实现骨架

```text
main thread
  -> spawn Supervisor (fork_context=false)
  -> send task scope + refs
  -> record role spawn in orchestration-proof.md
  -> wait -> artifacts: supervisor-board.md, review-manifest.md

  -> spawn Executor (fork_context=false)
  -> send supervisor-board.md + review-manifest.md + repo refs
  -> record handoff in orchestration-proof.md
  -> wait -> artifact: execution-result.md

  -> spawn Blind Reviewer (fork_context=false)
  -> send review-manifest.md + blind-review-prompt.md + repo refs
  -> optionally send execution-result.md
  -> record handoff in orchestration-proof.md
  -> wait -> artifact: blind-review-result.md

  -> route:
     - PASS -> human gate or done
     - PASS WITH NOTES -> executor or supervisor depending on note type
     - FAIL (manifest issue) -> supervisor
     - FAIL (execution issue) -> executor
```

---

## 9. Validation Mode

在 skill 达到 stable 前，默认要求每轮真实 batch 开启 `validation mode`。

额外要求：

1. main thread 维护 `orchestration-proof.md`
2. 每个角色 spawn 都要在 proof 中留下：
   - agent id
   - created_at
   - `fork_context=false`
3. 每次 handoff 都要记录：
   - from / to
   - allowed inputs
   - actual inputs sent
4. 至少执行：
   - canary check
   - disagreement-path check
5. 结束后按 `runtime-validation-checklist.md` 验证

说明：

- current runtime 不能提供文件 ACL，所以 validation mode 依赖**可观察证据**而不是抽象宣称
- 如果 validation mode fail，本轮代码删除结果即使是正确的，也不能作为“多角色流程已验证”的证明

---

## 10. 什么时候不要起多 Agent

以下情况不建议起完整三角色：

1. 单个很小的模块，依赖边界极清晰
2. 只是补齐文档，不涉及删除执行
3. 只是对已有 manifest 做很小修订

此时可以保留：

- `Supervisor + Executor`
  - 但 `Blind Review` 仍建议在进入删除前保留

---

## 11. 失败与回退

如果多 Agent 协作失控，按下面顺序回退：

1. 保留文件工件，不丢失当前状态
2. 暂停 Blind Review 之外的并行
3. 让单个 Executor 基于 manifest 收敛结果
4. 必要时只保留：
   - `Supervisor Board`
   - `review-manifest.md`
   - `execution-result.md`
   - `blind-review-result.md`

关键原则：

- 即使回退到单线程推进，也不要回退到“共享完整上下文”的做法

---

## 12. 规范层与机制层分工

本文（规范层）回答：

1. 哪些角色存在
2. 每个角色负责什么
3. 角色之间允许交接什么工件
4. 哪些流程步骤不能跳过

`SKILL.md §3.5a`（机制层硬规则）回答：

1. Blind Reviewer 必须 spawn 独立 subagent
2. 工具集裁剪规则
3. 不得泄漏的输入清单
4. `blind-review-result.md` 产出要求

`references/drafts/langgraph-implementation-design.md`（contract spec，仅供未来外置编排参考）回答：

1. 若未来不再依赖 Claude Code harness，应如何用 LangGraph 重建
2. 此文档**目前不影响实现**，是合同义务级的对照稿

当前 active runtime 把"独立上下文 / 条件路由 / batch 持久化"全部交给 Claude Code harness 处理，无需引入额外编排框架。

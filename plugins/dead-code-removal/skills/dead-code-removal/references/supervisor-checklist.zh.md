# 监工模式检查表

> 目标：让 AI 负责排队、分组、阻塞判断和缺陷归纳；只有必须人工拍板时才提醒用户。

> 多角色前提：`Supervisor / Executor / Blind Reviewer` 必须使用彼此独立的上下文，不应共享完整推理链。

---

## 1. 任务分诊顺序

每次从待清理池中取任务时，按以下顺序判断：

1. 这个对象是模块、接口，还是一个已经存在的审计稿
2. 是否已经有 review 文档
3. 是否存在明确 Runtime Roots
4. 是否有组外活跃调用方
5. 是否依赖其他待清理对象
6. 是否触及共享基础设施

然后归类到以下四种状态之一：

- `Ready`
  - 可独立进入 Step 0–3
- `Needs Closure`
  - 依赖链还在待清理池内，需要继续上溯形成闭包
- `Blocked (external refs)`
  - 已确认存在组外存活调用方，当前不动
- `Blocked (refactor needed)`
  - 需要先解耦、下沉共享代码或拆分入口
- `Needs Human`
  - 证据冲突，必须人工确认

---

## 2. 默认优先级

优先做：

1. 已有审计稿、只差 review/执行的模块
2. 独立可删、低风险、无共享边界的模块
3. 只差一个上游/下游模块就能形成闭包的模块组

延后做：

1. 共享 `common/`、proto、DB schema 的模块
2. 需要跨团队确认的模块
3. 运行时入口不清晰的模块

---

## 3. 只在这些问题上打扰用户

以下问题之外，AI 应自行继续推进，不要把中间思考过程甩给用户：

1. 哪个调用方算“活代码”
2. 哪个共享资源仍需保留
3. 哪组模块允许作为同一个闭包批次删除
4. 当前 review 清单是否 approve
5. 当前发布/回滚约束是否接受

提问必须压缩成一条具体决策，不得抛开放题。

好例子：

- `module-b/ 仍被 module-c 通过 grpc/<module> 调用。module-c 不在本次待清理范围。是否把 module-b/ 标记为 blocked，先跳过？`

坏例子：

- `这个模块关系有点复杂，你看怎么处理比较好？`

---

## 3.5 升级前先过 Escalation Gate

在把问题放进 `Needs Human` 之前，必须先确认：

1. **事实闭合**
   - 入口、调用链、真实消费方、运行时触发方式已查明
2. **技术闭合**
   - 风险已被证实，不是中间态假设
3. **决策剩余**
   - 问题已经被压缩成“只剩 tradeoff 需要人选”

若任一条件不满足，不应升级给用户，应继续调查。

---

## 3.6 Invalid Escalation（无效升级）

以下情况属于无效升级：

1. 把待验证风险当成待确认决策
2. 用户被问到后，agent 继续调查才发现该问题本来可以自行消解
3. 一个问题里同时混入“事实待查”和“偏好待选”

遇到这种情况时：

1. 不要重复追问用户
2. 先补齐缺失调查
3. 在 iteration 的人工介入 / follow-up 区域记录这次无效升级

---

## 4. “被其他模块依赖”时的处理

当模块 A 被模块 B 依赖时，按以下顺序处理：

1. 查 B 是否也在待清理池
2. 若在：
   - 继续检查 B 的调用方
   - 直到形成封闭闭包，或遇到组外存活调用方
3. 若不在：
   - 若是组外活代码依赖，记为 `Blocked (external refs)`
   - 若是共享实现耦合，记为 `Blocked (refactor needed)`，并给出最小解耦 sketch
4. 若证据不足：
   - A 记为 `Needs Human`

关键原则：

- “被依赖” 不等于 “不能删”
- 只有“被组外活代码依赖”才等于当前不能删

---

## 5. 每轮必须产出

每一轮都要有这三类结果：

1. `Supervisor Board`
2. 一条 `Next` 建议
3. 一组 `Skill Follow-ups`

`Skill Follow-ups` 至少回答：

- 这轮为什么会卡住
- 是仓库问题、模块边界问题，还是 skill 流程问题
- 下次遇到同类问题，skill 应新增什么检查项或模板字段
- 若本轮出现 `Invalid Escalation`：
  - 过早升级的问题原文是什么
  - 后来补查后真正问题被收敛成什么
  - 下次升级前必须补哪一步验证

---

## 5.5 角色间信息边界

角色之间只传递最小必要工件：

1. `Supervisor -> Executor`
   - 传 `supervisor-board.md`、`review-manifest.md`、阻塞结论
   - 不传完整推理草稿
2. `Executor -> Blind Reviewer`
   - 只传 `review-manifest.md`、代码库、blind review prompt
   - 仅在需要审查执行偏差时追加 `execution-result.md`
   - 不传“我怀疑哪里错”的提示
3. `Blind Reviewer -> Human Gate`
   - 只产出 `blind-review-result.md`

关键原则：

- `Blind Reviewer` 必须保持“信息盲”
- `Executor` 应尽量基于 manifest 工作，而不是继承 `Supervisor` 的全部上下文

---

## 6. 可直接复用的输出模板

```markdown
## Supervisor Board

- Ready:
  - {对象}: {原因}
- Needs Closure:
  - {对象}: {建议并组对象}
- Blocked:
  - `Blocked (external refs)`: {对象}: {组外活跃调用方}
  - `Blocked (refactor needed)`: {对象}: {解耦方案}
- Needs Human:
  - {对象}: {必须人工回答的问题}
- Next:
  - {建议下一步}
- Skill Follow-ups:
  - {应补到 SKILL.md / checklist / template 的优化}
```

---

## 7. 盲审触发时机

`Supervisor Board` 产出后、进入 Step 4 前，必须触发 blind review。

这里以 [SKILL.md](../SKILL.md) 的 `Step 3.5a — Blind Review` 为准；本检查表不重复定义细节，避免两处规则漂移。

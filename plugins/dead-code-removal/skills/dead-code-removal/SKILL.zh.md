---
name: dead-code-removal
description: 用于从代码库中清理死代码、废弃的 HTTP handler、无用模块或孤儿符号。强制 3 角色工作流（supervisor / executor / blind-reviewer），基于 manifest 的审查、分层 build/vet/tidy 验收脚本、删除前的 Review Gate，以及硬性验收标准，做到一次性清理正确且完整。触发短语如「清理 xxx handler/模块」「remove dead module」「删除废弃 HTTP 路由」「drop unused service func」或来自 backlog 的批量清理任务。
---

# Dead Code Removal Skill（中文版）

> version: 0.1.0
> status: 开源发布（方法论成熟；打包形式为新）
> 语言工具链：Go（`scripts/*.sh`）；方法论与语言无关——替换脚本即可支持其他语言。

> 📌 本文是 `SKILL.md`（英文主版）的中文版。两份内容等价，以英文版为准。

## 🚨 顶层非协商规则（必读，违反会让用户重复授权）

**若你在权限受控的 agent（如 Claude Code）里跑本 skill，违反任意一条，几乎每次命令都会弹 permission prompt。**

1. **不要在验收脚本前面加 env 前缀**
   - ❌ 错：`GOCACHE=... GOFLAGS=-mod=mod scripts/build-check.sh ./...`
   - ✅ 对：`scripts/build-check.sh ./...`
   - **原因**：env 前缀会创建一个新的命令 prefix，不在 allowlist 里 → 每次都弹。环境需要固定 cache/proxy 路径？在 shell profile 里 export 一次，或改脚本默认值，**绝不要**在调用层加前缀。

2. **不要用装饰性 pipe（`| head`、`| tail`、`| tee`）**
   - ❌ 错：`scripts/build-check.sh ./... 2>&1 | tail -5`
   - ✅ 对：`scripts/build-check.sh ./...`（输出短就读完；长就用 Read 截断）
   - **原因**：复合命令重新匹配 allowlist；`tail`/`head` 可能不在 allow 里。

3. **不要用 Bash 改源码**
   - ❌ 错：`sed -i ...` / `awk > tmp && mv tmp file` / `head -n X file > new && tail >> new && cp new file`
   - ✅ 对：用 Edit / Write 工具改文件
   - **原因**：Bash 改源码无法 diff 审计、易踩 sandbox 写权限。

4. **不要把「待验证的风险」包装成「待用户拍板的决策」**
   - 升级给用户前先过 §Supervisor Mode → Escalation Gate 3 道门槛（事实闭合 / 技术闭合 / 决策剩余）。

违反 1-3 任一条 → 重读本节，改用规定写法，不要硬跑触发 prompt。

---

## 目标

给定一个废弃接口（HTTP handler）或模块目录，自动找出并清除所有**仅被该废弃代码引用**的下游依赖，做到一次性清理正确且完整。

同时支持 **Supervisor Mode（监工模式）**：

- agent 默认先做任务分诊、排序和阻塞判断
- 只有在必须由人拍板时才升级提醒用户
- 每轮执行后自动沉淀本轮暴露的 skill 缺陷，反哺后续优化

## 输入格式

```
接口: {HTTP方法} {路由路径}
Handler: {函数名}
文件: {文件路径}
```

或：

```
模块目录: {目录路径}
```

或：

```
模块目录:
- {目录路径1}
- {目录路径2}
- ...
```

## 适用边界

默认目标不是「尽快批量删目录」，而是以**最小可验证单元**稳定出清。

- 默认单位：1 个模块 / 1 个接口 / 1 个运行时入口
- 默认策略：**分析可以批量，执行必须保守**
- 只有当多个模块构成**封闭删除批次（closed batch）**时，才允许在同一轮执行中一起删除

### 什么是封闭删除批次

同时满足以下条件，才能把多个模块视为一个批次：

1. 这些模块之间主要是**内部互相依赖**
2. 对批次外代码**不存在存活调用方**
3. 不共享仍被外部使用的通用包、proto、配置模板、DB schema、topic、Redis key
4. 可以用**一组统一的验收标准**完成验证，而不是必须分服务分别观察
5. 回滚时可以**一个 commit / 一个 PR**整体回滚，不影响无关模块

只要有任一条件不满足，就**不要成组删除**，改为逐模块迭代。

### 多模块时的默认处理策略

当用户一次给出多个模块时，按以下顺序处理：

1. 先做**批量分析**：构建模块间调用图，找出哪些模块可以形成封闭删除批次
2. 输出**分组结果**：
   - A 类：可独立删除的模块
   - B 类：必须和其他模块一起删除的闭包模块组
   - C 类：不能删除，只能简化/合并/解耦的模块
3. 执行阶段默认采用：
   - **一个模块一个 review**
   - **一个模块或一个闭包模块组一个 commit**
   - **一个模块或一个闭包模块组一个 PR**

### 为什么不默认多个模块一起删

因为多模块一起删会同时放大 4 个风险：

- 引用图判断错误时，误删范围更大
- `go build` / `go test` 失败后更难定位责任模块
- 发布观察项会混在一起，无法判断是哪一组删除引发问题
- 回滚粒度太粗，容易把已经验证通过的删除也一起撤回

因此，**默认规则是：批量分析，分批执行，逐批验收，逐批推进下一批。**

## Supervisor Mode（默认建议开启）

当输入来自 backlog、模块清单或一组 HTTP 接口时，默认按「监工模式」推进，而不是让用户逐个决定下一步。

### 多角色模型（上下文必须独立）

本 skill 不是「一个 agent 轮流扮三角」，而是默认采用 3 个**上下文独立**的角色；主线程只做 orchestration，不属于三角色中的任何一个：

1. **Supervisor**
   - 负责待清理池读取、分诊、排序、`Supervisor Board`、`Needs Human` 升级判断
   - 负责创建并拥有 `review-manifest.md`
2. **Executor**
   - 负责按 manifest 执行 Step 0–6：删除、验证、验收
   - 负责产出 `execution-result.md`，并在发现现实与 manifest 冲突时提出修订建议
3. **Blind Reviewer**
   - 负责在 Step 3.5a 独立做反证式审查

推荐实现：使用能 spawn 隔离子 agent 的 agent 运行时。

- 主线程只做路由、等待、Human Gate 与最终汇报
- `Supervisor` / `Executor` / `Blind Reviewer` 各自获得独立上下文（全新 spawn，**不**从主线程历史 fork）

顶层路由 / 状态持久化 / Human Gate 由 agent harness 提供，不需要额外编排层。若未来外置编排，contract spec 见 `references/drafts/langgraph-implementation-design.md`（合同设计稿，目前不影响实现）。

### Validation Mode（当前默认强制）

在 skill 尚未稳定前，每一轮真实模块执行都应默认开启 `validation mode`。

`validation mode` 的目标不是验证「代码删得对不对」，而是验证：

1. 这 3 个角色是否真的以独立 agent 运行
2. 输入白名单是否被严格执行
3. blind review 是否具备真实反证能力
4. 工件链是否足以支持复跑与审计

`validation mode` 额外要求：

1. 主线程维护 `orchestration-proof.md`
2. 按 `references/runtime-validation-checklist.md` 逐项验证
3. 默认执行 canary check
4. 在前 3 轮真实 batch 中，至少拿到 1 轮 disagreement-path 证据

只有通过 `runtime-validation-checklist.md` 的通过定义后，本轮才能被视为「多角色流程已按 contract 执行」的证明样本。

硬规则：

1. 三个角色必须视为**不同上下文窗口**
2. 不 fork 上下文是默认硬规则
3. 不允许把 supervisor 的完整推理链直接传给 executor 或 blind reviewer
4. blind reviewer 绝不能继承 supervisor / executor 的历史推理
5. 角色之间默认只通过**最小必要工件**传递信息，而不是共享整段对话上下文
6. 同一角色可保留自己的连续上下文；角色职责变化时必须新开 agent，不得复用旧 agent 冒充别的角色

允许传递的工件：

- Supervisor → Executor：待执行对象、`supervisor-board.md`、`review-manifest.md`、必要的 blocking 结论
- Executor → Blind Reviewer：`review-manifest.md`、当前代码库、`references/blind-review-prompt.md`、`execution-result.md`（仅在需要审查执行偏差时）
- Blind Reviewer → Human Gate：`blind-review-result.md`

禁止传递：supervisor 的完整分析草稿；「我怀疑这里有 bug/这里大概率删错」的引导性结论；已经预设好的答案或推荐结论。

### 监工模式的职责

1. 自动读取待清理池（tracking page、review 文档、本地模块状态）
2. 先做任务分诊，再决定执行顺序：
   - `Ready`：可直接进入 Step 0–3 生成 review 清单
   - `Needs Closure`：依赖其他待清理模块，需先合并成闭包模块组或等上游先删
   - `Blocked (external refs)`：仍有组外存活调用方 / 共享基础设施
   - `Blocked (refactor needed)`：必须先解耦、下沉共享代码或拆分入口
   - `Needs Human`：必须人工拍板的问题
3. 默认优先推进：已确认废弃且低风险的独立模块；能形成封闭闭包的模块组；已有审计稿、只差执行的模块
4. 每轮结束自动输出：下一批建议处理对象；本轮必须人工介入的事项；对现有 skill 的缺陷总结

### 只有这些场景才升级给用户

1. **边界归属不清**：某个调用方存在，但无法判断它是否也属于待清理集合
2. **共享资源归属不清**：共享 DB schema / Kafka topic / Redis key / proto / 配置模板是否还能删，无法仅靠代码判断
3. **运行时入口归属不清**：`cmd/main`、`service.Init()`、consumer、cron、feature flag、map 注册表是否仍启用，证据冲突
4. **删除批次边界不清**：两个模块既不完全独立，也不构成稳定闭包，强行一起删会放大回滚面
5. **进入 Step 4 前的 Review Gate**：任何源码/配置删除前，仍必须显式 review / approve

### 升级前置门槛（Escalation Gate）

即使看起来「像是需要用户确认」，也必须先通过以下 3 个门槛，才能真正升级给用户：

1. **事实闭合**：入口、调用链、真实消费方、运行时触发方式都已查明
2. **技术闭合**：已确认这是技术上真实存在的风险，不是中间态猜测
3. **决策剩余**：agent 已经把问题压缩成「事实已查清，只剩 tradeoff 需要人选」

只要任一门槛未通过，就**禁止升级给用户**，应继续自行调查。

### Invalid Escalation（无效升级）规则

以下情况视为 `Invalid Escalation`：

1. agent 把**待验证的风险**包装成「需要你拍板的决策」
2. agent 提问后，继续挖掘发现该问题本可由代码、配置、调用链或运行时证据自行消解
3. agent 把「事实待查」与「偏好待选」混在同一个问题里丢给用户

一句话规则：

> 不要把「待验证的风险」包装成「待确认的决策」。

出现 `Invalid Escalation` 时：当前问题不应继续占用用户决策位；agent 必须先补完缺失调查，再决定是否还需要升级；本轮 iteration 必须记录过早升级的问题原文、补查后真正的问题、下次升级前必须补哪一步验证。

### 对「被其他模块依赖」的默认处理规则

若待删除模块 A 被模块 B 依赖，不要立刻判定「A 不能删」，按下面规则处理：

1. 先判断 B 是否也在待清理池中
2. 若 B 也待清理：再判断 A+B 是否对外形成**封闭闭包**；形成闭包 → 归为同一批次；不形成 → 暂不执行，继续上溯调用方，直到闭包成立或遇到存活边界
3. 若 B 不在待清理池中：直接存活调用方 → A 标记 `Blocked (external refs)`；共享 wiring/helper/proto 导致不可直接删 → 标记 `Blocked (refactor needed)` 并给出最小解耦方案；清单必须写明活跃调用方 B，禁止继续删除
4. 若 B 是否待清理无法确认：标记 `Needs Human`，只升级「需要谁确认什么问题」，禁止抛出整坨分析

### 监工模式输出格式

```markdown
## Supervisor Board

- Ready:
  - {模块/接口}: {为什么现在就能做}
- Needs Closure:
  - {模块/接口}: {依赖谁，建议与谁并组}
- Blocked:
  - `Blocked (external refs)`: {模块/接口}: {组外活跃调用方}
  - `Blocked (refactor needed)`: {模块/接口}: {解耦方案}
- Needs Human:
  - {模块/接口}: {只保留必须由人回答的问题}
- Next:
  - {下一批建议处理对象}
- Skill Follow-ups:
  - {本轮暴露的 skill 缺陷 / 优化点}
```

完整提问模板与升级规则见 `references/supervisor-checklist.md`。

## 执行流程

### Step -2 — 工具与命令选择原则（贯穿全程，降低中断率）

**目标**：让执行过程 ≥95% 的工具调用命中**已授权**权限或**沙箱自动通过**，避免反复弹 approve。

#### 原则 1：原生工具 > Bash 等价命令

原生工具（读 / 搜 / glob / 改 / 写 / 子 agent）在默认 allow 内，**永远不会弹 prompt**。能用原生工具完成的任务**禁止**改用 Bash：

| 任务 | 用 | 禁用 |
|---|---|---|
| 读文件 | 读文件工具 | `Bash(cat file)` |
| 搜代码/字符串 | grep 工具 | `Bash(grep/rg/git grep)` |
| 按 glob 找文件 | glob 工具 | `Bash(find / ls \| grep)` |
| 改文件 | 编辑/写工具 | `Bash(sed/awk/echo >/cat <<EOF)` |
| 复杂多轮探索 | 子 agent | 大串 Bash 脚本 |

**核心规则（一句话记住）**：

> `| head -N` / `| tail -N` 几乎总是 anti-pattern。要截断输出，**永远**走读文件工具的 `limit/offset` 或 grep 工具的 head-limit，不要在 Bash pipe 里加 `head/tail`。

**为什么最重要**：Bash 权限按命令前缀匹配——`grep` 已 allow，但 `grep ... | head -20` 因为 `head` 没 allow 就整条复合命令重新弹一次。大量弹窗就是这类装饰性 pipe 造成的。

#### 原则 1.5：子 agent spawn prompt 必须复述本规则

`Supervisor` / `Blind Reviewer` / `Executor` 在独立上下文跑，看不见主线程的工具调用习惯。**Spawn 它们时，prompt 必须显式包含**：

- 本节「反例」表（或等价禁止清单）
- 一句「禁止 `cat | head` / `find -name` / `grep -rn | head` / `| tail -N` 装饰」
- 提示读文件工具有 `limit/offset`，grep 工具有 head-limit
- 提示「分层验收优先调用 `scripts/build-check.sh` / `scripts/vet-check.sh` / `scripts/module-gone-check.sh`，不要把 `go build`、`tee`、`echo`、`ls` 串成一条命令」
- 提示「源码编辑一律用 编辑/写 工具，禁止 `head > tmp ; tail >> tmp ; cp tmp target`，禁止写临时补丁文件」

否则子 agent 会沿用 Bash 习惯，你看不见的耗时大半花在这上面。

#### 原则 2：简单命令 > 复杂管道

Bash 允许规则按命令前缀匹配。`go build ./...` 允许，但 `go build ./... | tee log` 不允许（`tee` 不在 allow 里）会弹。

- 拆分管道：先跑 `go build ./... 2>&1`，再用 grep 工具过滤（都不弹）。
- 如必须管道：确保每一段都在 allow 内。

#### 原则 3：避免触发 sandbox bypass

若环境在沙箱内跑命令，allowlisted 且沙箱内能成功的命令无感通过；一旦需要写沙箱拒绝路径，就要 bypass，**每次都弹**。常见坑：

- **`go build` / `go test` / `go vet` 写默认 Go cache**（沙箱禁写）
  - **解法（首选）**：用本 skill 脚本 `scripts/build-check.sh` / `scripts/vet-check.sh` / `scripts/tidy-check.sh`，并在 shell profile 里 export 可写的 `GOCACHE`/`GOMODCACHE`。
- **`git stash -u` 遇到沙箱禁读文件（如 `.env`）** → stash 失败
  - **解法**：分析阶段不要用 stash 做 base 对比。改用 `git diff` + `git show HEAD:path` 读历史版本，或切 `git worktree`。
- **`rm` 到沙箱外路径** → 被拒。本 skill 只删 repo 内文件，不会触发。

#### 原则 4：并行代替顺序

独立的读操作（多个读/grep/`git log`）在同一个消息里并发发出，而不是串行。

#### 原则 5：新增 permission 需求 → 回到 Step -1 的检查，不在执行中途临时弹

中途发现一条命令必需但未授权：停下，不要让它直接弹；回到 Step -1，把这条加入 delta 列表一次性给用户；告知「追加后继续」，不要边跑边弹。

---

### Step -1 — 获取 Permission（用户触发清理后立即执行）

**当用户请求「清理模块/接口」时，在做任何分析之前，执行两阶段流程：**

#### Step -1a — 检查 Hook 模式是否已就绪

1. 确认是否存在可用的 Permission Hook 配置与脚本
2. 确认最小骨架权限是否已覆盖：读 / grep / glob；必需的只读 shell 查询；必需的 `go build/test/vet/mod tidy`
3. 若 Hook 已就绪：只向用户展示**最小骨架权限 delta**；后续删除走 manifest + Hook 动态放行
4. 若 Hook 未就绪：降级到 **Step -1b diff-first fallback**

#### Step -1b — diff-first fallback（仅 Hook 未就绪时）

1. **读取现有授权**：读权限配置（不存在视作空 allow 数组），提取 `allow` 条目。
2. **对照全量清单**：见 [references/permission-template.md](references/permission-template.md)。做**语义**对比（`Bash(go build:*)` 覆盖 `go build`；bare `Read`/`Grep`/`Glob` 覆盖所有子项）。
3. **只向用户展示 delta**：分析档全部已覆盖 → 单行「✅ 分析档权限已全部授权，可直接进入 Step 0」；有缺失 → 只列未覆盖条目，附「（已授权的 X 项省略）」；执行档同理（等 Step 3.5b Human Gate 通过后再 diff 一次）。

**为什么这一步在最前面？** 分析阶段会有大量 grep / build / read / 子 agent 调用，提前确认权限路径可避免一个模块被打断十几次。

### Step 0 — 确认 Runtime Roots

在分析依赖图之前，先确认入口点在运行时是否仍被启动流程触发：

1. `cmd/main` 和 `service.Init()` 是否仍会初始化该模块
2. HTTP 路由 / gRPC register / Kafka consumer / cron worker 是否仍注册该逻辑
3. 是否存在 goroutine 启动点、`init()` 副作用、配置开关驱动的入口
4. 检查隐式入口：配置/feature flag 控制的条件初始化；通过 map 注册表或字符串匹配分发的 handler；由其他服务通过 gRPC/HTTP 调用触发的被动逻辑

**为什么先看 Runtime Roots？** 大量逻辑由注册、初始化、后台协程和配置驱动，不从 handler 线性调用。不先确认运行时入口是否已下线，仅凭符号引用图可能误删仍被启动流程触发的代码。

### Step 0.5 — 模块分组（仅当输入包含多个模块时）

1. **独立可删模块**：自身可单独形成删除集合，逐模块独立推进
2. **闭包模块组**：多个模块互相依赖，对组外没有存活调用方，必须作为一个最小执行单元一起删
3. **非删除模块**：仍有组外调用方，或承担共享能力，只能简化/解耦/合并

输出：给每个模块标记分组；说明原因；明确本轮实际执行范围。默认顺序：独立低风险模块 → 闭包模块组 → 需重构/合并的模块。

### Step 1 — 定位入口点

1. 根据输入找到入口函数（handler / main / worker）
2. 读取入口函数，记录它直接调用的所有内部符号（函数、类型、常量）
3. 记录入口点的路由注册位置（如 `http.go` 中的 `app.GET(...)`）

### Step 2 — 构建依赖图

对入口函数的每个直接依赖，递归执行：

1. 用 LSP `findReferences` 查找该符号的所有引用方
2. 用 grep 搜索该符号名的字符串出现（捕获反射、配置、proto 等非静态引用）
3. 分类：所有引用方都在删除集合中 → 加入删除集合，继续递归其下游依赖；存在删除集合外的引用方 → 标记为边界，保留

重复直到删除集合不再增长。

**必须扫描的间接引用路径（最容易漏的盲点）：**

仅 grep 模块目录会漏掉这些：

1. **proto 生成包路径** `grpc/{name}` — 包名可能与模块目录名不同
2. **运行时 endpoint**：`{服务名}:{端口}`、`.svc.cluster.local`、toml/yaml/源码字符串中的地址常量
3. **配置文件里的 service address 字段**（grpc client 拨号地址、HTTP client base URL）
4. **Kafka topic 名 / consumer group 名**（常量常定义在 common 包，被多服务共用）
5. **Redis key 前缀**（常量 + 拼接字符串）
6. **shared helper 所在的 `common/` 子包**（如 `common/<area>/dao/<module>.go` 定义了该模块方法，删除后变孤儿；若 `common/` 被活服务用则破坏其编译）
7. **你自己的清理流程维护的 service-inventory / CI service-map / 元数据文件** — 若你的流程保留了服务/pod/路由快照，必须同步更新，否则陈旧清单会污染后续分析与下一轮审计基准

每个模块必须分别跑这 7 类 grep，任一命中外部引用都要回到 Step 0.5 重新分类。

**历史教训（必读）：**
- 一次清理中，审计以为某模块独立，却漏了一个共享 `auth` 中间件仍 import 其生成的 `grpc/<module>` 包，差点搞坏活服务编译。
- 另一次，一个 `admin` 模块通过 `grpc/<module>` 反向依赖，同一盲点复发。因此 1–7 类被列为硬性扫描项。
- 又一次，若干 service wrapper 被删但其在 service-inventory 文件里的条目没更新，留下孤儿条目污染后续分析——这正是本 skill 要消灭的问题，故第 7 类。

**必须检查的非代码位置：**
- 配置模板（如 `*.toml.tpl`）
- 测试配置（如 `testdata/*.toml`）
- 测试文件（`*_test.go`）
- `Dockerfile` / `Makefile`
- CI service-to-directory 映射
- Kafka topic / consumer group / cron 配置 / 环境变量名
- Redis key / metric 名 / SQL 表名或枚举值

### Step 3 — 生成删除清单

产出结构化清单，参考 `references/removal-list-template.md`。默认由 `Supervisor` 生成并拥有；`Executor` 只能提修订建议，不直接改写 cleanup 合同边界。

清单必须包含：
- 顶部 frontmatter，至少：`approved: false`、`approved_by: null`、`approved_at: null`、`approved_sha: null`、`input_type: module | http-batch`、`deletion_paths:`（机器可读 source of truth；Hook 只认这里）
- 确认删除的符号列表（文件、行号、符号名、类型）
- 边界保留的符号列表（含保留原因——谁还在用）
- 需清理的非代码文件列表
- 需通知 DevOps 清理的环境变量
- **验收标准**（见 `references/acceptance-criteria.md`）的预期结果
- **权限说明**：清单只声明 manifest 路径、删除路径与审批状态；动态批准交给 Hook

清单文件命名：`.code-removal/reviews/{日期}-{模块名}.md`。

### Step 3.5 — Review Gate（强制人工/Agent 审核）

**硬性暂停点。在此之前，禁止删除任何源码或配置文件。**

#### Step 3.5a — Blind Review（先于人工 Gate）

进入 Human Gate 前，**必须先做 Blind Review**，不得由 supervisor 自审代替。

硬规则：

1. **必须**使用固定的独立 `Blind Reviewer` agent 做盲审（全新 spawn，不要用探索类 helper）
2. **必须使用独立上下文**：不复用 supervisor / executor 推理上下文，不把完整线程历史 fork 给它
3. 盲审输入只允许：`review-manifest.md`、当前代码库、`references/blind-review-prompt.md`、`execution-result.md`（仅在需审查执行偏差时）
4. **禁止**把 supervisor 的推理过程、预期结论、已知怀疑点喂给盲审
5. 盲审必须独立重跑 Step 2 的 **7 类间接引用扫描**
6. 盲审结论必须**由 reviewer 自己用 写/编辑 工具**写入独立的 `blind-review-result.md`，不得由 supervisor 转录
7. `approved_sha` 改变即作废 `blind-review-result.md`，需重跑盲审
8. **未完成盲审，不得进入 Step 4**

#### Step 3.5b — Human Gate（盲审之后）

1. 清单生成后，将路径输出给用户，**等待显式 approve 后才能进入 Step 4**
2. 批量清理多个模块：**默认一次 PR 只处理一个模块**；**例外：只有 Step 0.5 明确判定为闭包模块组时，才允许一个 PR 处理一组**；无论哪种都必须独立生成清单、独立 review、独立 commit
3. Reviewer 关注点（见 `references/acceptance-criteria.md` 第 1 节）：删除集合是否含应保留的边界符号；边界集合是否漏掉应删孤儿符号；Runtime Roots 是否全枚举；非代码残留是否覆盖完整；多模块场景本批次是否真封闭、是否有应拆开的被错误并组；回滚路径是否可行；`blind-review-result.md` 是否给出明确结论和差异项
4. 若采用 Permission Hook：确认 manifest frontmatter 已存在且 `deletion_paths` 完整；通过时更新 `approved`/`approved_by`/`approved_at`/`approved_sha`；`approved_sha` = review/approve 当下的 repo HEAD SHA；默认要求删除前 `current HEAD == approved_sha`，HEAD 变化就重 review 或重写 manifest；删除由 Hook 按 manifest 动态放行
5. 若 Hook 尚未安装：只保留最小骨架权限，不回退成大段静态 Bash allowlist

通过判定：reviewer 在清单末尾追加 `## Review: APPROVED by {name} at {date}`，或用户在对话中显式说「可以删/approve/继续」。

### Step 4 — 执行删除

按依赖拓扑**自顶向下**分层删除：

```
第 1 层: 路由注册 + handler + gRPC register + consumer 注册 + cron 注册
第 2 层: service 函数
第 3 层: dao 函数
第 4 层: model / types
第 5 层: consts / enums
第 6 层: 配置文件、测试文件
```

每层删除后执行 `scripts/build-check.sh` 验证。

多模块场景：单模块按正常分层删；闭包模块组仍按层删，但同一层内先删所有入口，再删所有 service，再删所有 dao；任一层失败时先定位责任模块/文件，再决定缩小范围 / 拆出该模块 / 共享代码改为保留或下沉或合并。

**禁止**把「多个模块一起删更省事」作为并组理由。并组只能基于依赖闭包和回滚闭包。

### Step 5 — 清理外围

1. `scripts/tidy-check.sh` — 清理不再需要的依赖并打印 `go.mod`/`go.sum` diff
2. 检查配置模板中是否有残留
3. 检查测试配置中是否有残留

如需验证模块目录已完全移除：

```bash
scripts/module-gone-check.sh {module-dir}
```

### Step 5.5 — 发布与回滚约束

1. **先下线入口，再删实现**：先移除路由 / 注册 / consumer / cron 入口，确认不再有新流量进入
2. **删除后观察一个发布周期**：至少观察一轮常规发布后的错误率、404、consumer lag、关键任务执行
3. **预先写明回滚路径**：通常是直接回滚版本；如伴随配置清理，需确认配置也能恢复

多模块批次额外要求：观察项按模块/组列出；高风险组不与低风险模块合并发布；需跨团队手工恢复的配置删除，必须单列 owner 和恢复步骤。

### Step 6 — 自评估 & 验收

执行两份检查：
1. `references/eval-checklist.md` — skill 流程质量评估
2. `references/acceptance-criteria.md` — **「无 side effect 且清理彻底」的硬性验收标准**

**验收标准必须全部通过才算完成**（任何一项失败必须回滚或补删后重测）。

最终验证概要（完整清单见 `acceptance-criteria.md`）：
- `scripts/build-check.sh` 通过
- `go test ./...` 通过（或显式列出与删除无关的既有失败）
- `scripts/vet-check.sh` 无新增告警
- `scripts/tidy-check.sh` 通过，`go.mod`/`go.sum` diff 合理，无意外新增依赖
- 全仓 grep 模块关键字：目录名、服务名、import 路径、特有配置键、Kafka topic、Redis key、metric 名、SQL 表名 — 应全部清零或仅剩文档/注释
- CI service-to-directory 映射已同步
- k8s manifest / helm chart / Dockerfile / Makefile 中对应条目已清理
- 受影响服务容器镜像可启动（配置加载、依赖初始化、路由/consumer/grpc 注册成功）
- 无 panic、无 nil pointer、无「config key not found」

### Step 6.5 — 删除后意外事件处理

删除后出现编译失败、测试失败、启动失败、流量异常、consumer lag、404 激增、配置缺失、环境回归，必须追加一份**后续任务记录**，不能只在对话里口头说明。

#### 6.5.1 意外事件分级

- **P0 回滚类**：无法编译 / 服务无法启动 / 明确误删存活逻辑 / 关键路径报错。动作：立即停止进入下一模块，优先回滚或最小修复。
- **P1 补删/补保留类**：删除范围过小（仍有残留）/ 过大（可小修保留边界）/ 配置脚本测试文档遗漏。动作：当前模块关闭问题后才能进入下一模块。
- **P2 跟进类**：DevOps/QA/前端/其他仓库后续清理；历史兼容逻辑后续下线；监控告警观察项补充。动作：记录 owner、截止时间、阻塞关系。

#### 6.5.2 必须产出的后续任务

每次意外事件，补充到 review 或 iteration 文档：事件标题；发现阶段（编译/测试/冒烟/发布观察/线上反馈）；级别（P0/P1/P2）；根因；受影响模块；是否需回滚；立即修复动作；后续任务；owner；截止日期；关闭条件。

#### 6.5.3 对后续批次的约束

- 存在未关闭的 P0/P1 时，**禁止进入下一模块执行删除**
- P2 可不阻塞下一模块，但必须已记录并指派 owner
- 连续两次删除出现同类型事件，必须先更新本 skill 再继续
- 问题来自「错误并组」时，后续批次必须拆小

## 迭代机制

每次执行后：
1. 按 `references/eval-checklist.md` 评估本次执行
2. 将结果记录到 `iterations/{序号}-{名称}.md`（见 `references/iteration-template.md`）
3. 如出现 P0 / 重复性 P1 / 错误并组导致的问题，必须在 iteration 中写明「流程缺陷 → skill 修订点」
4. 如发现 skill 流程本身缺陷，更新本文件并 bump version

## Permission 策略（Hook 优先，diff-first fallback）

review doc 不再维护大段静态 Bash allowlist。默认：

1. **先检查 Hook 是否就绪**：就绪只要求最小骨架权限；未就绪回退 Step -1b diff-first
2. **最小骨架权限**：读 / grep / glob；必需的只读 shell 查询；必需的 `go build/test/vet/mod tidy`
3. **删除动作动态放行**：Hook 读 review manifest frontmatter，只对 `approved: true` 且命中 `deletion_paths` 的删除放行。见 `references/drafts/permission-hook.md`
4. **仍保留人工逐次 approve 的动作**：`git push`、`gh pr *`、外部系统更新、`kubectl` / `gcloud` / `aws`、生产 DB

目标：把「每轮补 allowlist」的负担从 review 文档移走，收敛到一套可审计、可 dry-run 的 Hook 逻辑。

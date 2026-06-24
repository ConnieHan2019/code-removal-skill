---
approved: false
approved_by: null
approved_at: null
approved_sha: null
input_type: module
deletion_paths:
  - {相对路径1}
  - {相对路径2}
---

# 删除清单: {接口/模块名}

> 执行日期: {日期}
> Skill 版本: {version}
> 入口点: {输入}

> `approved_sha` 语义：review/approve 当下的 repo HEAD SHA。
> Hook 默认要求删除前 `current HEAD == approved_sha`。如果 HEAD 已变化，需重新 review 或更新 manifest。

---

## 0. 风险分级与 Review 聚焦（TL;DR）

### 0.0 Related Artifacts

> `Supervisor Board`、`Execution Result`、`Blind Review Result` 默认是独立工件，不再嵌入 manifest。

- Supervisor Board: `{path/to/supervisor-board.md}`
- Execution Result: `{path/to/execution-result.md | not generated yet}`
- Blind Review Result: `{path/to/blind-review-result.md | not generated yet}`

### 0.1 总体风险评级

`[低 / 中 / 高]` — {一句话说明为什么是这个等级：blocker 检查结果 + 跨模块耦合强弱 + 是否触及共享基础设施（DB schema / Kafka topic / Redis key / 监控告警）}

### 0.2 可直接删除（低风险，reviewer 可快速扫过）

这部分内容引用关系闭合在模块内、无共享基础设施、无历史数据兼容问题：

| 类别 | 范围 | 为什么安全 |
|---|---|---|
| {例如 "模块内部 Go 包"} | {路径} | {grep 证据：外部 0 hits} |
| {例如 "模块自有 Dockerfile"} | {路径} | {仅被自身 CI 引用} |

### 0.3 需要人工/其他 agent 重点 review 的内容

这部分涉及共享资源、跨模块依赖或不可自动判定的语义，**必须人工确认**才能进入 Step 4：

| 项 | 风险 | 请 reviewer 判断 |
|---|---|---|
| {例如 "共享 Kafka topic X"} | 下游消费者是否还需要本模块生产的消息 | {具体问题} |
| {例如 "DB 表 Y"} | 是否有历史查询 / BI 报表仍依赖 | {具体问题} |
| {例如 "配置键 Z"} | 其他服务的 toml 模板是否仍加载 | {具体问题} |

> 这里的条目应尽量压缩成“一个问题 = 一个决定”，避免把完整分析过程甩给 reviewer。

### 0.4 显式不删（边界保留）

| 项 | 保留原因 |
|---|---|
| {共享 common/ 基础包} | 全仓共用 |
| {文档中的历史提及} | 不影响运行时正确性 |

> 如果某项保留是因为“调用方也在待清理池，但闭包尚未形成”，不要写在这里，改写入 `Needs Closure`。

### 0.5 超出本 PR 范围（由他人处理）

| 项 | 责任人 |
|---|---|
| {例如 DB drop} | DevOps |
| {例如 k8s deployment 删除} | DevOps |
| {例如 下游消费者清理} | 下一个 PR |

---

## 1. 删除集合（所有引用方均在删除范围内）

### 1.1 路由/入口

| 文件 | 行号 | 内容 | 说明 |
|---|---|---|---|
| | | | |

### 1.2 Handler / Worker

| 文件 | 行号 | 符号名 | 说明 |
|---|---|---|---|
| | | | |

### 1.3 Service 层

| 文件 | 行号 | 符号名 | 引用方（全部待删） |
|---|---|---|---|
| | | | |

### 1.4 DAO 层

| 文件 | 行号 | 符号名 | 引用方（全部待删） |
|---|---|---|---|
| | | | |

### 1.5 Model / Types

| 文件 | 行号 | 符号名 | 引用方（全部待删） |
|---|---|---|---|
| | | | |

### 1.6 Constants / Enums

| 文件 | 行号 | 符号名 | 引用方（全部待删） |
|---|---|---|---|
| | | | |

### 1.7 配置 / 测试 / 非代码文件

| 文件 | 内容 | 说明 |
|---|---|---|
| | | |

---

## 2. 边界保留（仍有存活代码引用）

| 文件 | 符号名 | 存活引用方 | 保留原因 |
|---|---|---|---|
| | | | |

---

## 3. 需通知 DevOps 清理的环境变量

| 变量名 | 所在配置 | 说明 |
|---|---|---|
| | | |

---

## 4. 依赖图可视化

```
{入口 handler}
  ├── {service 函数 A}  [删除]
  │    ├── {dao 函数 X}  [删除]
  │    │    └── {model Y}  [删除]
  │    └── {const Z}  [保留: 被 other.go 引用]
  └── {service 函数 B}  [删除]
       └── {dao 函数 W}  [保留: 被 active_service.go 引用]
```

---

## 5. Runtime Roots 确认

- cmd/main 初始化分支: {文件:行 / 已下线状态}
- 路由 / gRPC / consumer / cron 注册位置: {文件:行}
- 隐式入口 (feature flag / map / 字符串分发): {说明}
- 生产 / dev 部署状态: {引用 一个 backlog / tracking 页面 或 k8s manifest}
- 回滚路径: {版本回滚 / 配置回滚步骤}

---

## 6. 预期验收结果（对照 acceptance-criteria.md）

| 编号 | 预期 |
|---|---|
| V7 目录名 grep | 0 hits（docs/ 除外） |
| V8 服务名 grep | 0 hits |
| V10 配置键 grep | 0 hits |
| V11 Kafka topic | 0 hits |
| V12 Redis key | 0 hits |
| V16 service-inventory / CI service-map 文件 | 已移除行 |
| V17 k8s manifest | 已移除 |
| （其余按 acceptance-criteria.md 全量覆盖） | |

---

## 7. 风险 / 注意事项

- {跨模块共享符号风险}
- {DB 表 / 枚举值历史兼容风险}
- {监控 / 告警需同步下线}

---

## 8. Permission 清单（Manifest + Hook）

> 默认改用 `references/drafts/permission-hook.md`。本节只保留 manifest 与 Hook 约定，不再堆静态 allowlist。

### 8.1 Manifest

- 当前 `review-manifest.md` 路径: `{manifest_path}`
- 当前批次类型: `{input_type}`
- source of truth: 顶部 frontmatter 的 `deletion_paths`

### 8.2 Hook 放行前提

- `approved: true`
- `approved_by` / `approved_at` / `approved_sha` 已写入
- 删除前 `current HEAD == approved_sha`
- 删除动作命中 `deletion_paths`

### 8.3 仍需手动档（不走 Hook 自动放行）

`git push` / `gh pr *` / `notion-update-page` / `kubectl|gcloud|aws|生产 DB` — 每次单独 approve。

### 8.4 操作指引

- 安装与 dry-run：见 `references/drafts/permission-hook.md`
- 若 Hook 未就绪：只保留最小骨架权限，不要回退成大段静态 Bash allowlist

---

## 9. Review

<!-- Reviewer 审核通过后追加一行，格式示例：
## Review: APPROVED by alice at 2026-04-15
备注：xxx
-->

# 验收标准：无 side effect 且清理彻底

> **status: ACTIVE**。本文件适配当前 3-subagent / 4-artifact 流程。Reviewer 不再只看单一 review doc，而是至少对照 `review-manifest.md`；必要时同时查看 `supervisor-board.md`、`execution-result.md`、`blind-review-result.md`。
> 应用场景：code-removal skill 的 Step 3.5（Review Gate 预期项）与 Step 6（验收硬门槛）。
> 所有项目必须**全部通过**才允许合并 PR / 进入下一模块。任意一项失败 = 回滚或补删。

---

## 1. Review Gate 前置检查（Step 3.5 reviewer 对照用）

Reviewer 对本 batch 的工件按以下维度打勾：

- 主合同：`review-manifest.md`
- 辅助工件：`supervisor-board.md` / `execution-result.md` / `blind-review-result.md`

### 1.1 删除集合正确性
- [ ] 每个"确认删除"的符号都列出了**全部引用方**，且引用方**全部**在删除集合内
- [ ] 不存在仍被"删除集合外代码"引用的符号误入删除集合
- [ ] 共享工具/通用类型（如 `utils/`、`common/`、`pkg/`）未被误列入

### 1.2 删除集合完整性
- [ ] 清单列出了入口点：HTTP 路由、gRPC register、Kafka consumer、cron worker、goroutine 启动点、`init()` 副作用
- [ ] 清单覆盖了隐式入口：feature flag、map 注册表（如 `handlers["x"]=...`）、字符串分发、被动 gRPC/HTTP 调用
- [ ] 清单列出了所有非代码残留（见 1.4）
- [ ] 无孤儿符号遗漏：对边界集合中每个"保留"符号，验证过确有删除集合外的引用方

### 1.3 Runtime Roots 确认
- [ ] `cmd/main`、`service.Init()` 中的初始化分支已定位
- [ ] 对应服务在生产 / dev 的部署状态已确认（从一个 backlog / tracking page 或 k8s manifest）
- [ ] 回滚路径已写明（版本回滚 + 配置回滚）

### 1.4 非代码残留覆盖
- [ ] `cicd/config/*.toml.tpl`、你自己工作流维护的 CI service-map 文件
- [ ] `testdata/*.toml`、`*_test.go`
- [ ] `Dockerfile`、`Makefile`、k8s manifest / helm chart
- [ ] Kafka topic 名 / consumer group 名
- [ ] Redis key 前缀 / metric 名 / SQL 表名或枚举值
- [ ] 环境变量名（需通知 DevOps 清理的列表）
- [ ] proto 文件 / gRPC service 定义
- [ ] API 文档 / swagger / README

---

## 2. 删除后硬性验收（Step 6 必须全通过）

### 2.1 编译与静态检查
| # | 检查 | 命令 | 通过标准 |
|---|---|---|---|
| V1 | 编译 | `scripts/build-check.sh` | exit 0，或仅剩已明确列出的 pre-existing fail |
| V2 | vet | `scripts/vet-check.sh` | 无新增告警（与 base 对比） |
| V3 | 依赖清理 | `scripts/tidy-check.sh` + `git diff go.mod go.sum` | diff 合理：仅移除本次不再用到的包；无意外新增 |
| V4 | 格式 | `gofmt -l .` | 输出为空 |

> **V3 sandbox 兜底**（pilot #2 经验）：`scripts/tidy-check.sh` 在 sandbox 模式下若因 TLS / module proxy / 本机环境受限而无法完整 resolve，此时按以下顺序判断：
> 1. 若 `git diff go.mod go.sum` **为空** → 视为 V3 通过（删除未引入/移除依赖，验收能力已达成）
> 2. 若 diff 非空且脚本报错 → 必须在 sandbox 外重跑确认 diff 合理性，不能跳过
> 3. **必须在 iteration 记录中显式写明 "V3 走 sandbox 兜底"**，不要静默通过
> 这是验收能力的**透明降级**，不是等价替代——sandbox 模式下 V3 无法验证"模块独占的间接依赖被正确清理"。

### 2.2 测试
| # | 检查 | 命令 | 通过标准 |
|---|---|---|---|
| V5 | 单元测试 | `go test ./...` | 全绿，或失败项**全部**在 base 上已存在且与删除无关（需在 PR 中列出） |
| V6 | 与删除模块相关的测试文件 | 查清单 | 已删除，未残留 `_test.go` 孤儿 |

### 2.3 残留引用扫描（关键！这一步最容易漏）
对每个被删模块，执行下列 grep，**结果必须为空或仅剩文档/changelog/注释**：

| # | 扫描目标 | 命令示例 |
|---|---|---|
| V7 | 目录名 | `rg -n "{module_dir}" --glob '!docs/**'` |
| V8 | 服务名 | `rg -n "{service_name}" --glob '!docs/**'` |
| V9 | Go import 路径 | `rg -n "your-module-path/{module}"` |
| V10 | 配置键 | `rg -n "{config_prefix}" cicd/ testdata/` |
| V11 | Kafka topic / consumer group | `rg -n "{topic_name}"` |
| V12 | Redis key 前缀 | `rg -n "{redis_prefix}"` |
| V13 | Metric 名 | `rg -n "{metric_name}"` |
| V14 | SQL 表名 | `rg -n "{table_name}"` |
| V15 | 环境变量名 | `rg -n "{ENV_VAR}"` |

对每一条，在 PR 描述中写明 grep 命令 + 结果。

### 2.4 CI / 部署映射
| # | 检查 | 通过标准 |
|---|---|---|
| V16 | 你自己工作流维护的 CI service-map 文件 | 对应行已移除 |
| V17 | k8s manifest / helm chart | deployment / statefulset / cronjob / service / configmap 已移除 |
| V18 | Dockerfile / Makefile | 对应 build target 已移除 |
| V19 | CI pipeline 定义 | 流水线配置中不再引用该模块 |

### 2.5 运行时冒烟（受影响的仍存活服务）
对**仍保留的**、与删除模块共用代码的服务：

> **status: aspirational**。一次早期运行中共 2 次 iteration（module-a / scanner-module）均未实施 V20–V23 —— 因为本仓的清理目标全部是"prod pod=0 / 无活服务调用方"的孤儿模块，按定义不存在"仍保留且共用代码"的下游需要冒烟。**触发条件**：仅当本批次清理涉及 `common/` 修改 或 `Blocked (refactor needed)` 闭包模块组导致活服务函数签名变化时，V20–V23 才必须真跑。其他场景明确写"V20–V23 N/A — 无共享代码改动"即可。

| # | 检查 | 通过标准 |
|---|---|---|
| V20 | 容器启动 | 本地 `docker build` + `docker run` 或 dev 部署，无 panic |
| V21 | 配置加载 | 启动日志无 "config key not found" / "missing required field" |
| V22 | 依赖初始化 | DB / Redis / Kafka 连接成功，路由/consumer/grpc 注册成功 |
| V23 | 核心接口冒烟 | 至少一个核心 endpoint 请求通过 |

### 2.6 副作用审查
| # | 检查 | 通过标准 |
|---|---|---|
| V24 | 无 `init()` 误删 | grep `func init()` in diff，确认删除的 init 无被其他包依赖的副作用 |
| V25 | 无循环依赖引入 | `go build` 通过即可；如果模块合并，额外跑 `go list -deps` 对比 |
| V26 | 无注释掉的"僵尸代码" | diff 中无 `// TODO` / `// DEPRECATED` 大段注释，全部真删 |
| V27 | 无历史迁移破坏 | 如涉及 DB schema：确认无 DROP TABLE 未加 migration；枚举值删除不影响历史记录解析 |

### 2.7 回滚可行性
| # | 检查 | 通过标准 |
|---|---|---|
| V28 | PR 为单模块单 commit | 一个模块一个 commit，revert 即回滚 |
| V29 | 配置回滚路径 | 删除的配置模板在 revert 后可直接生效，无需手工补数据 |

---

## 3. 最终报告格式

PR 描述或 `iterations/{n}-{module}.md` 中必须包含：

```
## 验收结果（{module}）

- Review Manifest: `.code-removal/runs/{日期}-{module}/review-manifest.md`
- Supervisor Board: `.code-removal/runs/{日期}-{module}/supervisor-board.md`
- Blind Review Result: `.code-removal/runs/{日期}-{module}/blind-review-result.md`
- Execution Result: `.code-removal/runs/{日期}-{module}/execution-result.md`
- Reviewer: {name} @ {date}

### 硬性验收 (V1–V29)
- V1 build-check.sh:  ✅
- V2 vet-check.sh:    ✅
- ...
- V29 回滚路径:        ✅

### 残留 grep 记录
- V7 目录名 `{dir}`:      0 hits
- V8 服务名 `{service}`:  0 hits (docs 中 2 处保留)
- ...

### 异常 / 例外
（如有 test 失败与删除无关，在此列出并给出 base 链接）
```

---

## 4. 何时算"彻底"

**彻底的定义**：将代码库视作一张图，删除模块后，图上不存在任何"从存活代码可达的死符号 / 死配置 / 死入口"。具体等价于：

1. 没有仍可达但永不执行的函数（通过 V7–V15 的 grep 为空保证）
2. 没有仍加载但永不使用的配置（通过 V10、V16–V19 保证）
3. 没有仍注册但永不触发的路由/consumer/cron（通过 V17、V22 保证）
4. 没有仍编译但永不链接的包（通过 V3 `tidy-check.sh` + diff 保证）

**"无 side effect" 的定义**：删除前后，**仍保留**的每个服务的外部行为（API 响应、消费 topic 集合、写入的 Redis key / DB 表、暴露的 metric）完全不变。由 V20–V23 运行时冒烟 + V24 init 审查共同保证。

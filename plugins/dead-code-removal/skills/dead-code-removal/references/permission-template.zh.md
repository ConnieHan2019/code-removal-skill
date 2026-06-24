# Permission 清单模板

> **status: ACTIVE** —— 这是当前实际使用的权限方案。`references/drafts/permission-hook.md` 是未来替代方案的设计稿，目前未实现。
> 当前默认工件是 `supervisor-board.md` / `review-manifest.md` / `execution-result.md` / `blind-review-result.md`。本文中的权限申请与 diff-first 流程，默认围绕当前 batch 的这些工件展开；其中 machine-readable source of truth 仍是 `review-manifest.md` 顶部 frontmatter。
>
> 用途：
> 1. **任务开始时**（Step -1）：对照用户的现有 `.claude/settings.local.json` 做 diff，**只向用户展示缺失的 delta**，不贴全量
> 2. **Review Gate 阶段**（Step 3.5）：再对照一次 `.claude/settings.local.json`（用户可能已追加），只列执行档未覆盖的条目
>
> 目标：从 Step 0 分析到 Step 6 验收全程 ≥ 90% 的工具调用不触发 permission prompt。
>
> **核心规则**：本文件 §8.1 是全量 source-of-truth 清单；§8.2 是 **diff-first 展示流程**。
> **禁止**把 §8.1 整段贴给用户让他自己找差异 —— 那是把 diff 负担推给人。

---

## 8.0 命令构造约束（让 allowlist 与 sandbox auto-allow 真正生效）

> 历史教训：曾在 allowlist 里写 `Bash(GOCACHE=$TMPDIR/gocache GOMODCACHE=$TMPDIR/gomodcache go build:*)`，并启用 `sandbox.autoAllowBashIfSandboxed: true`，但每次 `go build` 仍然弹权限提示。根因不在 allowlist，而在命令字符串本身。

### 8.0.1 触发条件 —— `Contains simple_expansion`

Claude Code 的 Bash matcher 对带 shell 变量展开的命令有内建安全检查。命令里出现 `$VAR` 这类 simple expansion 时，权限提示框会显示 `Contains simple_expansion` 标记，**一律走人工 approve**：

- ❌ allowlist 静态匹配**不生效**（不论规则怎么写、是否带相同前缀）
- ❌ `autoAllowBashIfSandboxed: true` 也**不自动放行**
- ❌ 即便沙箱已启用、命令完全跑得动，依然要 user 手动点 approve

`${VAR}` / `$(...)` / 反引号 / 通配 `*` 是否同样触发，我没逐一验证，但 `$VAR` 已确认。**预防起见全部按"命令里别出现 shell 展开"对待。**

### 8.0.2 go 工具链的具体陷阱

go 默认 `GOCACHE=~/Library/Caches/go-build`，**不在沙箱写白名单内**。沙箱内首次 `go build` 写缓存就失败 → Claude 自动 fallback 到 `dangerouslyDisableSandbox: true` → 命令脱离沙箱跑 → 走普通 allowlist 流程 → 弹权限。

很自然的反应是把 GOCACHE/GOMODCACHE 重定向到 `$TMPDIR`：

```bash
GOCACHE=$TMPDIR/gocache GOMODCACHE=$TMPDIR/gomodcache go build ./...
```

但这恰好踩中 §8.0.1 —— **命令里出现 `$TMPDIR` 就一定弹权限**。allowlist 里写对应的带前缀规则也救不了。

### 8.0.3 正确做法 —— 在 shell 端预先 export

把缓存路径**在 shell 配置里**一次性 export，让 Claude 拿到的环境里已经是绝对路径，命令本体不带任何 env var 前缀：

```bash
# ~/.zshrc 或 ~/.bashrc 或项目 .envrc（direnv）
export GOCACHE=$HOME/.cache/go-build-claude
export GOMODCACHE=$HOME/.cache/go-mod-claude
```

> shell 启动时自己展开 `$HOME`，到 Claude 进程里已经是字面路径，无 simple_expansion 风险。

Claude 实际执行命令直接写裸命令：

```bash
go build ./service-x/...
go vet ./...
go test ./...
go list ./...
go mod tidy
```

allowlist 沿用 §8.1 的现有条目（`Bash(go build:*)` / `Bash(go vet:*)` / `Bash(go test:*)` / `Bash(go list:*)` / `Bash(go mod tidy:*)`），全部静态匹配通过。

### 8.0.4 通用规则

| 场景 | ❌ 别这么写 | ✅ 改成 |
|---|---|---|
| 临时目录 | `cmd $TMPDIR/foo` | shell 端 export 固定路径 / 用项目内字面相对路径 `./.tmp/foo` |
| 用户家目录 | `cmd $HOME/.cache/...` | 字面绝对路径 `/home/<user>/.cache/...` |
| 命令替换 | `cd $(git rev-parse --show-toplevel)` | 拆成两步：先取值固化，再 `cd <字面路径>` |
| 多个 env var 前缀 | `FOO=$VAR1 BAR=$VAR2 cmd ...` | 在 shell 里 export，命令本体只留 `cmd ...` |

**核心原则**：Bash 工具调用要构造成**完全字面**的字符串，所有变量展开在调起 Claude 之前就由 shell 完成。

---

## 8.1 本次执行需要的 permission — 分级

### A. 分析档（只读，低风险，建议直接 allow）

| Permission | 用途 | 使用阶段 |
|---|---|---|
| `Read(//**)` | 读仓库任意文件 | Step 0–6 全程 |
| `Grep`, `Glob` | 代码/文件名搜索 | Step 0–3 依赖图构建 + Step 6 残留验证 |
| `Bash(ls:*)` / `Bash(cat:*)` / `Bash(diff:*)` / `Bash(wc:*)` | 基础 shell 查询 | Step 0–6 全程 |
| `Bash(cp:*)` | 复制文件用于对比（如 go.mod 基线快照） | Step 5 go mod tidy 前后 diff |
| `Bash(git status:*)` / `Bash(git diff:*)` / `Bash(git log:*)` / `Bash(git stash:*)` | 只读 git 检查 + 基线对比（stash/pop 验证 base 编译状态） | Step 0 Runtime Roots + Step 6 基线对比 |
| `Bash(go list:*)` / `Bash(go build:*)` / `Bash(go vet:*)` / `Bash(go test:*)` / `Bash(gofmt:*)` | 构建、静态检查、测试 | Step 2 依赖确认 + Step 4 分层编译 + Step 6 验收 |
| `Bash(go mod tidy:*)` | 清理不再需要的间接依赖 | Step 5 |
| `Bash(scripts/build-check.sh:*)` / `Bash(scripts/vet-check.sh:*)` / `Bash(scripts/module-gone-check.sh:*)` / `Bash(scripts/tidy-check.sh:*)` | 固定脚本包装的验收动作，优先于裸 Bash 复合命令 | Step 4-6 |
| `Agent` | 子 agent 做深度依赖分析 | Step 0–2 |
| `mcp__claude_ai_Notion__notion-fetch` | 查会议结论 / 审批状态 | Step 0 |
| `Bash(mkdir:*)` | 创建 runs / reviews / iterations 输出目录 | Step 3 |

### B. 执行档（写，本地可回滚，建议本次模块范围 allow）

| Permission | 用途 |
|---|---|
| `Edit(//**)` / `Write(//**)` | 修改本仓代码 / 配置 / 文档 |
| `Bash(rm -rf {模块目录}/:*)` | **按模块白名单列出**，禁止裸 `rm -rf *` |
| `Bash(go mod tidy:*)` | 清理依赖，更新 go.mod/go.sum |
| `Bash(git add:*)` / `Bash(git commit:*)` / `Bash(git checkout -b:*)` | 本地 commit |

### C. 仍需手动档（破坏性 / 外部可见，**不预授权**）

| 动作 | 为什么每次都要人工 approve |
|---|---|
| `Bash(git push:*)` | 推远端、他人可见、难回滚 |
| `Bash(git reset --hard:*)` / `Bash(git clean -f:*)` / `Bash(git branch -D:*)` | 破坏性，可能丢工作 |
| `gh pr create` / `gh pr merge` | 外部可见，影响他人 |
| `mcp__claude_ai_Notion__notion-update-page` | 改 backlog / tracking 页面的结论/状态 |
| 任何 `kubectl` / `gcloud` / `aws` / 生产 DB 写操作 | 影响生产环境 |

---

## 8.2 Diff-first 展示流程（**skill 必须自己执行 diff，不要让用户做**）

### Step A — 读取现有授权

Read `.claude/settings.local.json`（不存在则视作空数组）。提取 `permissions.allow`。可选参考 `~/.claude/settings.json`。

### Step B — 语义对比 §8.1 全量清单

按以下等效规则匹配：

| 现有 allow 条目 | 视作覆盖的全量条目 |
|---|---|
| `Read` / `Grep` / `Glob` / `Agent` / `Edit` / `Write`（bare name） | 同名的所有子项 |
| `Bash(go build:*)` | `Bash(go build)` 以及 `Bash(go build ./...)` 等 |
| `Bash(sh:*)` 或 `Bash(*)` | 所有 Bash 子项（罕见） |
| 逐条精确匹配 | 完全相同字符串 |

未匹配的条目就是 **delta**。

### Step C — 按情况输出

**情况 A — 全覆盖**：

```
✅ {分析档 / 执行档}权限已全部授权（已覆盖 N/N 项），直接进入 Step {0 / 4}。
```

**情况 B — 有缺失**：

```markdown
### 需追加以下 K 条到 `.claude/settings.local.json` 的 `permissions.allow` 数组

```json
"Bash(go mod tidy:*)",
"mcp__claude_ai_Notion__notion-fetch"
```

（已授权的 X/N 项已省略。追加后立即生效，不需重启。）
```

**情况 C — 文件不存在**：

提示用户新建：

```json
{
  "permissions": {
    "allow": [
      "...把 §8.1 对应档位的条目逐行粘到这里..."
    ]
  }
}
```

（只有此种情况才贴全量清单；情况 B 绝不贴全量。）

### 备选方式：按 prompt 逐条 "Always allow"

不改配置文件，让每条 permission 在首次弹出 approve prompt 时选 "Always allow"（会话级）。
缺点：会话结束后失效，下次任务还要再来一遍。适合一次性小任务。

### ⚠️ 反例：不要用 `/permissions` → Add allow rule 粘贴多行

`/permissions` 的 "Add allow rule" 会把整段粘贴内容（含换行符）当作**单条字符串规则**保存，不会拆成多条。粘贴后写入 `.claude/settings.local.json` 的是一个里面带 `\r` / `\n` 的长字符串，匹配不到任何实际工具调用，等于没加。
如果一定要用 `/permissions`，只能一条一条加。

---

## 8.3 为什么这样分档

1. **分析档** 跨模块通用，一次 allow 后可复用于整批模块的清理 — 不再反复问。
2. **执行档** 中的 `Edit`/`Write`/`go mod tidy`/`git commit` 也跨模块通用；唯一需要**按模块替换**的是 `rm -rf {模块}` 那一条，由每模块清单具体列出，避免放权过大。
3. **仍需手动档** 刻意保留审批门槛：push、PR、backlog 页面更新、k8s/prod —— 这些是"对外可见、难回滚"的动作，每次单独 approve 是成本可控的安全边际。
4. **验收脚本优先**：如果 `build-check.sh` / `vet-check.sh` / `module-gone-check.sh` / `tidy-check.sh` 已授权，优先调用脚本；不要再把 `go build`、`tee`、`echo`、`ls` 串成一条 Bash。

---

## 8.4 Approve 后的行为承诺

用户按 8.2 添加 allow 后，本 skill 在 Step 4–6 执行过程中：
- **不会**再请求 8.2 列表内的任何工具调用的 permission
- **仍会**在以下情况停下：
  - 出现 Step 4 分层编译失败、需要调整删除范围时
  - 触及 8.1-C "仍需手动档" 中的动作时
  - 用户在 acceptance-criteria.md V20–V23 冒烟环节需要人工介入时
- 每模块 commit 前会简要回报变更 stats，不会自动 push

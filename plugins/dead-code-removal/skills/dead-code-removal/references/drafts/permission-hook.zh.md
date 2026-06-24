> ⚠️ 草稿 / 实验性 —— 这是设计稿，v0.1 未实现。仅作路线图参考。

# Permission Hook

> **status: 设计草稿，未实现**。截至目前的全部 review 都在用 `permission-template.md` 描述的 static allowlist 方案；本文件描述的 Hook 尚未挂上 Claude Code `PreToolUse`，也没有真正的 dry-run 跑过。
> 目标：替代每轮 batch 工件流程里不断膨胀的静态 allowlist。
> 思路：让 Hook 读取机器可读 manifest frontmatter，只对本批次、已审批、命中的删除路径放行。
> 注意：下面的脚本是**逻辑骨架**，不是可直接复制运行的 Claude Code Hook 实现。实际接入前，必须先对齐 Claude Code `PreToolUse` 的真实 JSON 协议；若协议细节不确定，先核对实际 hook 文档或现有 `update-config` / hook 配置方式，再落实现。
> 现行落地方案见 [`permission-template.md`](../permission-template.md)。
> 当前 active 设计中，Hook 若未来落地，默认只应读取 `review-manifest.md` 顶部 frontmatter；不要再使用模糊的 `review doc` 表述。

---

## 1. 最小骨架

建议保留为静态允许的只有：

- `Read`
- `Grep`
- `Glob`
- 必需的 shell 查询：`ls`, `cat`, `diff`, `wc`, `git status`, `git diff`, `git log`
- 构建验证：`go build`, `go test`, `go vet`, `go mod tidy`, `gofmt`

其余高噪音动作，尤其是删除动作，交给 Hook 判定。

---

## 2. Manifest 约定

Hook 只读取 `review-manifest.md` 顶部 frontmatter：

```yaml
approved: false
approved_by: null
approved_at: null
approved_sha: null
input_type: module
deletion_paths:
  - module-a/dao/dca.go
  - module-a/http/dca.go
```

关键规则：

1. `approved != true` 时，Hook 不放行任何删除动作
2. 只允许删除命中 `deletion_paths` 的路径
3. `rm -rf`、`rm`、批量删除、目录删除都必须展开后逐条校验
4. Markdown 表格不是 source of truth；`deletion_paths` 才是
5. `approved_sha` 表示 **review/approve 当下的 repo HEAD SHA**
6. 默认要求删除前 `current HEAD == approved_sha`
7. 若 HEAD 已变化，视为 manifest 与代码状态脱钩，必须重新 review 或更新 `approved_sha`

---

## 3. 分类逻辑

建议把 Hook 结果分为三类：

- `Cat1`
  - 明确安全，自动放行
  - 例：只读查询、构建验证
- `Cat2`
  - 条件放行
  - 例：删除命中 manifest `deletion_paths` 且 `approved: true`
- `Cat3`
  - 仍需人工 approve
  - 例：`git push`, `gh pr`, `kubectl`, 外部系统、未命中 manifest 的删除

---

## 4. PreToolUse Hook 逻辑骨架

下面示例偏伪代码/骨架，目的是固定逻辑，不绑定具体运行时实现。尤其是：

- 输入来源不一定是 `$1` / `$2`
- 实际实现很可能要从 `stdin` 读取 JSON payload
- 实际返回值也要对齐 Claude Code Hook 协议，而不是直接 `exit 0/2` 就算完成

实现前先核对真实 `PreToolUse` 协议。

```bash
#!/usr/bin/env bash
set -euo pipefail

TOOL_NAME="${1:-}"
TOOL_ARGS="${2:-}"
MANIFEST_PATH="${DEAD_CODE_REVIEW_MANIFEST:-}"
DRY_RUN="${DEAD_CODE_HOOK_DRY_RUN:-0}"
LOG_FILE="${DEAD_CODE_HOOK_LOG:-/tmp/dead-code-hook.log}"

log() {
  printf '%s\n' "$1" >> "$LOG_FILE"
}

allow() {
  log "ALLOW $*"
  exit 0
}

deny() {
  log "DENY $*"
  exit 2
}

if [[ "$TOOL_NAME" =~ ^(Read|Grep|Glob)$ ]]; then
  allow "cat1 builtin read-only"
fi

if [[ "$TOOL_NAME" == "Bash" && "$TOOL_ARGS" =~ ^go\ (build|test|vet|mod\ tidy) ]]; then
  allow "cat1 go validation"
fi

if [[ "$TOOL_NAME" == "Bash" && "$TOOL_ARGS" =~ ^rm ]]; then
  [[ -n "$MANIFEST_PATH" ]] || deny "missing manifest"

  approved="$(yq '.approved' "$MANIFEST_PATH")"
  approved_sha="$(yq '.approved_sha' "$MANIFEST_PATH")"
  current_sha="$(git rev-parse HEAD)"
  [[ "$approved" == "true" ]] || deny "manifest not approved"
  [[ "$current_sha" == "$approved_sha" ]] || deny "manifest stale: HEAD != approved_sha"

  mapfile -t approved_paths < <(yq '.deletion_paths[]' "$MANIFEST_PATH")
  mapfile -t requested_paths < <(normalize_rm_targets "$TOOL_ARGS")

  for path in "${requested_paths[@]}"; do
    match=0
    for approved_path in "${approved_paths[@]}"; do
      [[ "$path" == "$approved_path" ]] && match=1 && break
    done
    [[ "$match" -eq 1 ]] || deny "path not in deletion_paths: $path"
  done

  [[ "$DRY_RUN" == "1" ]] && deny "dry-run mode"
  allow "cat2 manifest-approved deletion"
fi

deny "cat3 manual approval required"
```

实现时要补的两个细节：

1. `normalize_rm_targets`
   - 负责把 `rm -rf dir/ file1 file2` 解析成规范化路径列表
2. frontmatter 解析
   - 若 `review-manifest.md` 是 Markdown + YAML frontmatter，需要先抽 frontmatter 再交给 `yq`

---

## 5. 安装方式

推荐挂在 `PreToolUse`：

1. 读取环境变量里的当前 review manifest 路径
2. 在删除前校验 `approved`、`approved_sha` 和 `deletion_paths`
3. 记录日志后决定 allow / deny

建议的环境变量：

- `DEAD_CODE_REVIEW_MANIFEST`
- `DEAD_CODE_HOOK_LOG`
- `DEAD_CODE_HOOK_DRY_RUN`

---

## 6. 审计与 Dry-Run

上线前先跑 dry-run：

1. `DEAD_CODE_HOOK_DRY_RUN=1`
2. 正常执行一轮 dead-code-removal
3. 检查日志里：
   - 哪些命令被判成 `Cat1`
   - 哪些删除命令命中了 manifest
   - 哪些命令仍落入 `Cat3`

日志至少记录：

- 时间
- tool / command
- manifest 路径
- 判定类别
- allow / deny 原因

---

## 7. 失败策略

Hook 无法判定时，默认降级为 `Cat3`，不要猜测放行。

尤其以下情况一律不自动放行：

- manifest 缺失
- `approved` 不是 `true`
- `approved_sha` 缺失
- 当前 HEAD 与 `approved_sha` 不严格相等
- 删除路径包含未声明文件
- 批量通配删除无法稳定展开

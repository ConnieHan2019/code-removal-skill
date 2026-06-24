# Blind Review Result

> **status: 默认独立工件**。由 `Blind Reviewer` 维护，记录独立反证结论，不再默认回填 manifest。
> batch: {date}-{batch-name}
> owner: Blind Reviewer
> agent_id: {agent_id}
> fork_context: false

## Verdict

- PASS | PASS WITH NOTES | FAIL

## Findings

> 每条 finding 必须按以下固定字段写入。
> 若没有任何 finding，本节写一句 "未发现可推翻当前 manifest 的证据"。

### F-01

- severity: blocker | major | nit
- category: missing_removal | wrong_removal | boundary_mistake | runtime_root_missed | sandbox_misuse | composite_bash | source_edit_via_bash | over_aggressive | other
- evidence: {file:line 或 manifest 行号；必填}
- counterfactual: yes | no | unsure
  - yes  = 如果 reviewer 没看到，会 land 进 PR
  - no   = 即使没我，build/vet/grep 等环节也会拦下
  - unsure = 无法判断
- executor_action: accepted | disputed | requires_supervisor

{重复 F-02、F-03 ... 按需添加}

## Re-run Evidence

> 按 Step 2 的 7 类间接引用扫描逐条列出关键证据（grep 命令 + 命中数 + 解读）

## Diff Against Manifest

- Missing deletions:
- Wrong deletions:
- Boundary mistakes:

## Step 4 Recommendation

- Proceed | Revise manifest | Split batch | Block

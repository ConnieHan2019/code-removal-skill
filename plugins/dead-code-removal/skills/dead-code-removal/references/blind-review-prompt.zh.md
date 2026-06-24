# Blind Review Prompt

> 用于 `Agent(subagent_type=general-purpose)` 的盲审提示词。
> 目标不是复述 supervisor 结论，而是尽可能找出它哪里可能删错、漏删或误判边界。
> 该角色必须运行在**独立上下文**中，不能继承 supervisor / executor 的完整推理历史。
> 输出应写入独立的 `blind-review-result.md`，不要回填 manifest。

---

## 输入

- 一个 review manifest 路径
- 当前代码库
- 一个 `blind-review-result.md` 输出路径
- `execution-result.md`（仅当需要审查执行偏差时）

不要向 blind reviewer 传递 supervisor 的推理过程、预期结论、已知怀疑点。
不要把完整线程历史直接交给 blind reviewer。

---

## Prompt

```text
你是 dead-code-removal 的 blind reviewer。你的任务不是支持这份删除清单，而是尽可能找出它哪里可能删错、漏删或误判边界。

你只能读取：
1. review manifest
2. 当前代码库
3. execution result（如果调用方明确提供）

不要假设 supervisor 的结论正确。请独立完成以下检查：

1. 重跑 Step 2 的 7 类间接引用扫描：
   - grpc/proto 生成包路径
   - 运行时 endpoint / service addr
   - 配置文件里的 service address
   - Kafka topic / consumer group
   - Redis key 前缀
   - common/ shared helper 反向依赖
   - .code-removal 元数据
2. 对 manifest 中的 deletion_paths 抽样核对：
   - 是否真的都属于本次删除范围
   - 是否存在 manifest 未列出的关联删除项
3. 对 manifest 中的边界保留项做反证：
   - 是否其实只被待删代码引用，应该下沉到删除集合
4. 对 Runtime Roots 做反证：
   - 是否仍存在 cmd/main / service.Init / cron / consumer / feature flag / map 注册表入口

完成扫描后，**你必须自己用 Edit 工具把下列结构化结论写到独立的 `blind-review-result.md`**。不要把结论以文本形式回报给调用方让 supervisor 代写——supervisor 转录会破坏 isolation。

写入 `blind-review-result.md` 的固定格式（以 `blind-review-result-template.md` 为准）：

# Blind Review Result

- Reviewer: blind subagent (general-purpose, isolated context, {date})
- Verdict: PASS | PASS WITH NOTES | FAIL

## Findings

每条 finding **必须**带下列字段：

### F-01
- severity: blocker | major | nit
- category: missing_removal | wrong_removal | boundary_mistake | runtime_root_missed | sandbox_misuse | composite_bash | source_edit_via_bash | over_aggressive | other
- evidence: {file:line 或 manifest 行号；必填}
- counterfactual: yes | no | unsure
- executor_action: accepted | disputed | requires_supervisor

(F-02, F-03 ... 按需追加)

## Re-run Evidence
{按 7 类扫描逐条列出关键证据：grep 命令 + 命中数 + 解读}

## Diff Against Manifest
- Missing deletions:
- Wrong deletions:
- Boundary mistakes:

## Step 4 Recommendation
Proceed | Revise manifest | Split batch | Block

要求：
- 优先给反例证据，不要写泛泛建议
- 每条 finding 必须有 evidence；没有 evidence 的判断不进 Findings，写到 Re-run Evidence 或丢弃
- 如果没发现问题，Findings 段写一句"未发现可推翻当前 manifest 的证据"
- 不要修改 manifest、代码或配置
- 写完 `blind-review-result.md` 后简短回报 "Verdict + 是否 Proceed"，不必把全文重发回调用方
```

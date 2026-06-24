# Supervisor Board

> **status: 默认独立工件**。由 `Supervisor` 维护，作为分诊与状态路由的 source of truth，不再默认嵌入 manifest。
> batch: {date}-{batch-name}
> owner: Supervisor
> agent_id: {agent_id}
> fork_context: false

## Ready

- {对象}: {为什么可直接进入 Step 0–3}

## Needs Closure

- {对象}: {建议并组对象 / 还差哪一层闭包}

## Blocked

- `Blocked (external refs)`: {对象}: {组外活跃调用方}
- `Blocked (refactor needed)`: {对象}: {最小解耦方案}

## Needs Human

- {对象}: {必须人工回答的问题}

## Next

- {建议下一步}

## Skill Follow-ups

- {本轮暴露的 skill 缺陷}

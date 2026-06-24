> ⚠️ 草稿 / 实验性 —— 这是设计稿，v0.1 未实现。仅作路线图参考。

# LangGraph Implementation Design for Dead Code Removal Workflow

> status: draft (no code yet)
> owner: code-removal skill
> scope: turn the current multi-role workflow from documentation into an executable orchestration layer
> **runtime note**: Agent SDK is the **active runtime** today — see `SKILL.md` §3.5a for the mandatory blind-review invocation and `../agent-orchestration-workflow.md` for the active 3-subagent / 4-artifact contract. This document is the **contract spec** kept in case orchestration is later externalized; it is not an alternative we are evaluating.
> **non-active warning**: 不要把本文件当成当前执行说明。日常运行以 `../agent-orchestration-workflow.md`、`../supervisor-checklist.md`、`../removal-list-template.md`、`../blind-review-prompt.md` 为准。

## 1. Why This Document Exists

The current code-removal workflow is already strong at the specification layer:

- roles are defined
- artifacts are defined
- escalation rules are defined
- blind review is mandatory before deletion

The main gap is no longer process design. The gap is execution mechanics:

- how to run `Supervisor / Executor / Blind Reviewer`
- how to keep their contexts isolated
- how to persist a batch run
- how to route between `Ready / Blocked / Needs Human`
- how to connect each AI role to a model such as Claude

This document defines how LangGraph should be used to close that gap.

## 2. Design Goal

Use LangGraph as a workflow orchestrator, not as the source of decision quality.

LangGraph is responsible for:

- graph execution
- state persistence
- role boundary enforcement
- conditional routing
- resumability
- human-in-the-loop pause points

The skill, prompts, templates, and review criteria remain the source of domain logic.

## 3. Non-Goals

This design does not try to:

- make the workflow fully autonomous on day one
- replace the existing skill references
- store full chain-of-thought across roles
- let all roles share one long chat thread
- start with destructive deletion execution

The first milestone is a safe artifact-producing workflow, not a full deletion robot.

## 4. Core Positioning

For this project, LangGraph should be treated as:

- a stateful workflow engine
- a role router
- a persistence layer for batch runs
- a mechanism for enforcing minimal artifact handoff

It should not be treated as:

- a single super-agent that roleplays three jobs
- a universal memory bucket
- a substitute for review standards

## 5. Mapping the Current Workflow to LangGraph

### Current workflow intent

The current target workflow is:

1. `Supervisor` triages a cleanup batch
2. `Supervisor` produces and owns a manifest for a concrete target
3. `Blind Reviewer` performs counter-evidence review
4. `Human Gate` is entered only when real human approval is needed
5. `Executor` executes only against an already approved manifest
6. `Iteration` records process defects and lessons

### LangGraph mapping

- `State`: shared batch snapshot
- `Nodes`: role execution steps
- `Edges`: routing rules
- `Checkpointer`: persistence across pauses, retries, and human gates
- `Subgraphs`: per-role local context

## 6. Architecture

### 6.1 Parent graph

The parent graph owns only cross-role orchestration.

Recommended parent nodes:

- `supervisor`
- `executor`
- `blind_review`
- `human_gate`
- `execution`
- `blocked`
- `done`

The parent graph must not carry complete role chat history.

### 6.2 Role subgraphs

Each AI role should be implemented as its own subgraph:

- `supervisor_subgraph`
- `executor_subgraph`
- `blind_reviewer_subgraph`

Why:

- each role keeps a private local context
- parent graph only receives structured outputs
- blind review can stay blind
- role-level prompts and tools remain separate

### 6.3 Artifact-first coordination

Cross-role handoff must remain file- and schema-based.

Allowed cross-role artifacts:

- `supervisor-board.md`
- `review-manifest.md`
- `blind-review-result.md`
- structured routing results such as `supervisor_status`

Disallowed cross-role handoff:

- full message history
- supervisor draft reasoning
- executor scratch analysis
- reviewer priming that leaks expected conclusions

## 7. State Design

### 7.1 Parent graph state

The parent state should stay small and routing-oriented.

Recommended first version:

```python
class WorkflowState(TypedDict, total=False):
    run_id: str
    batch_name: str
    input_type: str
    repo_path: str

    supervisor_status: str
    board_path: str

    manifest_path: str
    manifest_valid: bool

    blind_review_path: str
    blind_review_result: str

    gate_decision: str
    human_summary: str
```

Rules:

- keep only routing-critical values
- keep artifact paths, not full artifact copies
- do not store full multi-role message history here

### 7.2 Role-local state

Each role subgraph may keep a local state such as:

```python
class RoleState(TypedDict, total=False):
    messages: list
    latest_result: dict
    latest_artifact_path: str
```

This local state is for the role itself only.

## 8. Model Integration

LangGraph does not provide model intelligence by itself. Each AI node must call a model explicitly inside node code.

Recommended pattern:

- one model wrapper per role
- one system prompt per role
- one structured output schema per role

Example direction:

```python
supervisor_model = init_chat_model(model="claude-sonnet-4-5")
executor_model = init_chat_model(model="claude-sonnet-4-5")
reviewer_model = init_chat_model(model="claude-sonnet-4-5")
```

Each role node should:

1. read only allowed inputs
2. build the role-specific prompt
3. invoke the model
4. validate structured output
5. write the artifact
6. return only the minimal parent-state update

## 9. Context Isolation Strategy

This is the most important design constraint.

### 9.1 Batch-level continuity

A single cleanup batch should use one top-level `thread_id`.

Meaning:

- one batch = one persistent run thread
- retries and resumes stay on the same batch
- human gate resumes the same batch, not a new one

### 9.2 Role-level isolation

Within one batch:

- there should be one `Supervisor` context
- one `Executor` context
- one `Blind Reviewer` context

But these contexts must not be the same message history.

Implementation direction:

- top-level graph uses one `thread_id`
- each role runs as a dedicated subgraph
- each subgraph owns its own local state
- parent graph only carries artifact references and routing outcomes

### 9.3 Why not one shared `messages` list

One shared chat history would break the workflow intent:

- blind review would no longer be blind
- reviewer would inherit supervisor and executor assumptions
- routing state and analysis state would become entangled
- debugging would be harder because every role writes into the same memory bucket

For this project, shared `messages` should be treated as an anti-pattern at the orchestration layer.

## 10. Routing Rules

The graph should encode current workflow policy directly.

### 10.1 After `Supervisor`

- `Ready` -> `executor`
- `Needs Closure` -> `done`
- `Blocked (external refs)` -> `blocked`
- `Blocked (refactor needed)` -> `blocked`
- `Needs Human` -> `human_gate`

### 10.2 After `Executor`

- execution result complete -> `blind_review`
- manifest revision required -> `supervisor`

### 10.3 After `Blind Reviewer`

- `approved` -> `human_gate`
- `rejected` -> `executor`
- `need_retriage` -> `supervisor`

### 10.4 After `Human Gate`

- `approved` -> `execution`
- `rejected` -> `supervisor`
- `deferred` -> `blocked`

## 11. Human Gate Design

`Human Gate` should be a narrow approval step, not a dumping ground for unresolved investigation.

It should only receive:

- deletion scope
- blind review verdict
- remaining decision points
- proof that escalation gate has been met

It should not receive:

- the entire internal multi-role process history
- unresolved factual confusion that the agents could still investigate

This directly supports the existing `Invalid Escalation` rule.

## 12. Execution Strategy

Execution should be introduced last.

Recommended order:

1. artifact-only workflow
2. human gate integration
3. dry-run execution
4. real deletion execution
5. permission hook integration
6. `approved_sha` enforcement

This keeps the first LangGraph rollout low-risk.

## 13. Rollout Plan

### Phase 1: Artifact-only prototype

Scope:

- implement parent graph
- implement `Supervisor / Executor / Blind Reviewer`
- write artifacts only
- no deletion

Success criteria:

- graph can complete one real batch
- blind review is isolated
- artifacts are sufficient for downstream routing

### Phase 2: Human Gate

Scope:

- add `human_gate` node
- encode escalation gate requirements
- generate a human-facing approval summary

Success criteria:

- `Needs Human` is no longer a soft convention
- escalation quality becomes auditable

### Phase 3: Execution and safety rails

Scope:

- add dry-run execution
- add permission hook
- add `approved_sha` check
- enforce `deletion_paths` as the source of truth

Success criteria:

- execution cannot proceed without explicit approval state
- manifest approval and actual repo state remain aligned

## 14. Directory Recommendation

Recommended implementation structure:

```text
workflow/
├── graph.py
├── state.py
├── routes.py
├── artifacts.py
├── models.py
├── nodes/
│   ├── supervisor.py
│   ├── executor.py
│   ├── blind_reviewer.py
│   ├── human_gate.py
│   └── execution.py
└── subgraphs/
    ├── supervisor_graph.py
    ├── executor_graph.py
    └── blind_reviewer_graph.py
```

This split makes it easier to preserve the distinction between:

- workflow mechanics
- role logic
- prompt/model wiring
- artifact IO

## 15. Initial Open Questions

These are still implementation questions, not blockers for writing the design:

1. Should role subgraphs persist only per invocation or per thread across retries?
2. Should `Human Gate` be a pure interrupt node first, or an LLM-assisted summarizer plus interrupt?
3. Should iteration writing stay outside the graph at first, or be the last workflow node?
4. For `http-batch`, do we want a dedicated manifest template before Phase 1 implementation starts?

## 16. Recommended First Build

The first build should be intentionally small:

1. use LangGraph only for orchestration
2. use Claude only inside role nodes
3. keep one batch-level `thread_id`
4. keep role memory isolated via subgraphs
5. pass only artifacts between roles
6. do not delete code yet

If this version is stable, the workflow has successfully moved from specification to mechanism.

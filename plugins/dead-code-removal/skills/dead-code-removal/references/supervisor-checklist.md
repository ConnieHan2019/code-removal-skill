# Supervisor Mode Checklist

> Goal: let the AI own queuing, grouping, blocking judgment, and defect summarization; only prompt the user when a human decision is truly required.

> Multi-role premise: `Supervisor / Executor / Blind Reviewer` must use mutually independent contexts and should not share a full reasoning chain.

---

## 1. Task Triage Order

Each time you pull a task from the cleanup backlog, judge it in the following order:

1. Is this object a module, an interface, or an already-existing audit draft
2. Does a review document already exist
3. Are there clear Runtime Roots
4. Are there active callers outside the group
5. Does it depend on other objects in the cleanup backlog
6. Does it touch shared infrastructure

Then classify it into one of the following states:

- `Ready`
  - can independently enter Step 0–3
- `Needs Closure`
  - the dependency chain is still inside the cleanup backlog; must keep tracing upstream to form a closure
- `Blocked (external refs)`
  - confirmed live callers outside the group exist; do not touch for now
- `Blocked (refactor needed)`
  - must first decouple, push down shared code, or split the entry point
- `Needs Human`
  - evidence conflicts; must be confirmed by a human

---

## 2. Default Priority

Do first:

1. Modules that already have an audit draft and only need review/execution
2. Modules that are independently deletable, low-risk, with no shared boundary
3. Module groups that are just one upstream/downstream module away from forming a closure

Defer:

1. Modules that share `common/`, proto, or DB schema
2. Modules needing cross-team confirmation
3. Modules whose runtime entry points are unclear

---

## 3. Only Bother the User on These Questions

Apart from the questions below, the AI should keep pushing forward on its own and not dump its intermediate thinking on the user:

1. Which caller counts as "live code"
2. Which shared resource must still be kept
3. Which group of modules may be deleted as the same closed batch
4. Whether the current review manifest is approved
5. Whether the current release/rollback constraints are accepted

A question must be compressed into one concrete decision; do not toss out an open-ended problem.

Good example:

- `module-b/ is still called by module-c through grpc/<module>. module-c is not in this cleanup scope. Should we mark module-b/ as blocked and skip it for now?`

Bad example:

- `This module's relationships are a bit complex; how do you think we should handle it?`

---

## 3.5 Pass the Escalation Gate Before Escalating

Before placing a problem into `Needs Human`, you must first confirm:

1. **Fact closure**
   - entry points, call chains, real consumers, and runtime trigger mechanism have been determined
2. **Technical closure**
   - the risk has been proven, not an intermediate-state assumption
3. **Decision residue**
   - the problem has been compressed down to "only a tradeoff remains for a human to choose"

If any condition is unmet, do not escalate to the user; keep investigating.

---

## 3.6 Invalid Escalation

The following count as invalid escalation:

1. Treating a yet-to-be-verified risk as a decision-to-be-confirmed
2. After asking the user, the agent keeps investigating and only then finds the problem could have been resolved on its own
3. One question mixes together both "facts to investigate" and "preferences to choose"

When this happens:

1. Do not repeatedly press the user
2. First fill in the missing investigation
3. Record this invalid escalation in the iteration's human-intervention / follow-up area

---

## 4. Handling "Depended On by Another Module"

When module A is depended on by module B, handle it in the following order:

1. Check whether B is also in the cleanup backlog
2. If it is:
   - keep checking B's callers
   - until a closed closure forms, or you hit a live caller outside the group
3. If it is not:
   - if it is a live-code dependency outside the group, record it as `Blocked (external refs)`
   - if it is a shared-implementation coupling, record it as `Blocked (refactor needed)`, and give a minimal decoupling sketch
4. If evidence is insufficient:
   - record A as `Needs Human`

Key principle:

- "Being depended on" does not equal "cannot be deleted"
- Only "being depended on by live code outside the group" equals "currently cannot be deleted"

---

## 5. Required Output Every Round

Every round must produce these three kinds of result:

1. `Supervisor Board`
2. one `Next` recommendation
3. one set of `Skill Follow-ups`

`Skill Follow-ups` must at minimum answer:

- why this round got stuck
- whether it is a repository problem, a module-boundary problem, or a skill-process problem
- next time a similar problem occurs, what check item or template field the skill should add
- if an `Invalid Escalation` occurred this round:
  - what the prematurely escalated question's original wording was
  - what the real problem converged to after follow-up investigation
  - which verification step must be filled in before escalating next time

---

## 5.5 Information Boundaries Between Roles

Roles pass only the minimum necessary artifacts to each other:

1. `Supervisor -> Executor`
   - pass `supervisor-board.md`, `review-manifest.md`, and blocking conclusions
   - do not pass the full reasoning draft
2. `Executor -> Blind Reviewer`
   - pass only `review-manifest.md`, the codebase, and the blind review prompt
   - append `execution-result.md` only when execution deviation needs to be reviewed
   - do not pass any "where I suspect it went wrong" hint
3. `Blind Reviewer -> Human Gate`
   - produce only `blind-review-result.md`

Key principle:

- The `Blind Reviewer` must stay "information-blind"
- The `Executor` should work from the manifest as much as possible, rather than inheriting the `Supervisor`'s full context

---

## 6. Directly Reusable Output Template

```markdown
## Supervisor Board

- Ready:
  - {object}: {reason}
- Needs Closure:
  - {object}: {suggested grouping object}
- Blocked:
  - `Blocked (external refs)`: {object}: {live caller outside the group}
  - `Blocked (refactor needed)`: {object}: {decoupling plan}
- Needs Human:
  - {object}: {question a human must answer}
- Next:
  - {recommended next step}
- Skill Follow-ups:
  - {optimization that should be added to SKILL.md / checklist / template}
```

---

## 7. Blind Review Trigger Timing

After the `Supervisor Board` is produced and before entering Step 4, blind review must be triggered.

This defers to `Step 3.5a — Blind Review` in [SKILL.md](../SKILL.md); this checklist does not redefine the details, to avoid rule drift across two places.

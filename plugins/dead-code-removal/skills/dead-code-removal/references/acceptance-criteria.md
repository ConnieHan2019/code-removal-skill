# Acceptance Criteria: No Side Effects and a Thorough Cleanup

> **status: ACTIVE**. This file applies to the current 3-subagent / 4-artifact workflow. The Reviewer no longer looks at a single review doc; they cross-check at least `review-manifest.md`, and when necessary also `supervisor-board.md`, `execution-result.md`, and `blind-review-result.md`.
> Usage: Step 3.5 (Review Gate expected items) and Step 6 (acceptance hard gate) of the code-removal skill.
> Every item must **pass in full** before a PR may merge / before moving to the next module. Any single failure = roll back or delete more.

---

## 1. Review Gate Pre-Checks (used by the Step 3.5 reviewer for cross-checking)

The Reviewer ticks off the following dimensions against this batch's artifacts:

- Primary contract: `review-manifest.md`
- Supporting artifacts: `supervisor-board.md` / `execution-result.md` / `blind-review-result.md`

### 1.1 Correctness of the deletion set
- [ ] Every "confirmed for deletion" symbol lists **all of its referrers**, and those referrers are **all** within the deletion set
- [ ] No symbol that is still referenced by "code outside the deletion set" has wrongly entered the deletion set
- [ ] Shared utilities / common types (e.g. `utils/`, `common/`, `pkg/`) have not been wrongly included

### 1.2 Completeness of the deletion set
- [ ] The manifest lists entry points: HTTP routes, gRPC register, Kafka consumer, cron worker, goroutine launch points, `init()` side effects
- [ ] The manifest covers implicit entry points: feature flags, map registries (e.g. `handlers["x"]=...`), string dispatch, passive gRPC/HTTP calls
- [ ] The manifest lists all non-code residue (see 1.4)
- [ ] No orphan symbol is missed: for each "retained" symbol in the boundary set, verify there really is a referrer outside the deletion set

### 1.3 Runtime Roots confirmation
- [ ] The initialization branches in `cmd/main` and `service.Init()` have been located
- [ ] The deployment status of the corresponding service in production / dev has been confirmed (from a backlog / tracking page or the k8s manifest)
- [ ] The rollback path is written out (version rollback + config rollback)

### 1.4 Non-code residue coverage
- [ ] `cicd/config/*.toml.tpl`, the CI service-map file your own workflow maintains
- [ ] `testdata/*.toml`, `*_test.go`
- [ ] `Dockerfile`, `Makefile`, k8s manifest / helm chart
- [ ] Kafka topic names / consumer group names
- [ ] Redis key prefixes / metric names / SQL table names or enum values
- [ ] Environment variable names (the list to hand off to DevOps for cleanup)
- [ ] proto files / gRPC service definitions
- [ ] API docs / swagger / README

---

## 2. Hard Acceptance After Deletion (Step 6 must all pass)

### 2.1 Compilation and static checks
| # | Check | Command | Pass criterion |
|---|---|---|---|
| V1 | Compile | `scripts/build-check.sh` | exit 0, or only the explicitly listed pre-existing failures remain |
| V2 | vet | `scripts/vet-check.sh` | no new warnings (compared against base) |
| V3 | Dependency cleanup | `scripts/tidy-check.sh` + `git diff go.mod go.sum` | diff is reasonable: only removes packages no longer used by this change; no unexpected additions |
| V4 | Formatting | `gofmt -l .` | empty output |

> **V3 sandbox fallback** (pilot #2 experience): if `scripts/tidy-check.sh` cannot fully resolve in sandbox mode because of TLS / module proxy / restricted local environment, judge in the following order:
> 1. If `git diff go.mod go.sum` is **empty** → treat V3 as passed (the deletion neither introduced nor removed dependencies; the acceptance capability is met)
> 2. If the diff is non-empty and the script errors → you must re-run outside the sandbox to confirm the diff is reasonable; do not skip
> 3. **You must explicitly write "V3 used the sandbox fallback" in the iteration record** — do not pass silently
> This is a **transparent degradation** of the acceptance capability, not an equivalent substitute — in sandbox mode V3 cannot verify that "indirect dependencies owned exclusively by the module were correctly cleaned up."

### 2.2 Tests
| # | Check | Command | Pass criterion |
|---|---|---|---|
| V5 | Unit tests | `go test ./...` | all green, or failing items are **all** pre-existing on base and unrelated to the deletion (must be listed in the PR) |
| V6 | Test files related to the deleted module | check the manifest | deleted; no orphan `_test.go` left behind |

### 2.3 Residual reference scan (critical! this is the step most easily missed)
For each deleted module, run the grep below; **the result must be empty or contain only docs/changelog/comments**:

| # | Scan target | Example command |
|---|---|---|
| V7 | Directory name | `rg -n "{module_dir}" --glob '!docs/**'` |
| V8 | Service name | `rg -n "{service_name}" --glob '!docs/**'` |
| V9 | Go import path | `rg -n "your-module-path/{module}"` |
| V10 | Config key | `rg -n "{config_prefix}" cicd/ testdata/` |
| V11 | Kafka topic / consumer group | `rg -n "{topic_name}"` |
| V12 | Redis key prefix | `rg -n "{redis_prefix}"` |
| V13 | Metric name | `rg -n "{metric_name}"` |
| V14 | SQL table name | `rg -n "{table_name}"` |
| V15 | Environment variable name | `rg -n "{ENV_VAR}"` |

For each one, write the grep command + result in the PR description.

### 2.4 CI / deployment mapping
| # | Check | Pass criterion |
|---|---|---|
| V16 | The CI service-map file your own workflow maintains | the corresponding line has been removed |
| V17 | k8s manifest / helm chart | deployment / statefulset / cronjob / service / configmap have been removed |
| V18 | Dockerfile / Makefile | the corresponding build target has been removed |
| V19 | CI pipeline definition | the pipeline config no longer references the module |

### 2.5 Runtime smoke test (affected services that are still alive)
For services that are **still retained** and share code with the deleted module:

> **status: aspirational**. As of one early run there were 2 iterations total (module-a / scanner-module), neither of which executed V20–V23 — because every cleanup target in this repository is an orphan module with "prod pod=0 / no live service caller," so by definition there is no "still retained and code-sharing" downstream that needs a smoke test. **Trigger condition**: only when this batch's cleanup involves a `common/` change, or when a `Blocked (refactor needed)` closed module group changes the function signature of a live service, must V20–V23 actually be run. For other cases it is enough to write explicitly "V20–V23 N/A — no shared-code change."

| # | Check | Pass criterion |
|---|---|---|
| V20 | Container startup | local `docker build` + `docker run` or dev deploy, no panic |
| V21 | Config loading | startup logs have no "config key not found" / "missing required field" |
| V22 | Dependency initialization | DB / Redis / Kafka connect successfully; routes/consumer/grpc register successfully |
| V23 | Core API smoke | at least one core endpoint request passes |

### 2.6 Side-effect review
| # | Check | Pass criterion |
|---|---|---|
| V24 | No erroneously deleted `init()` | grep `func init()` in diff, confirm the deleted init has no side effect that other packages depend on |
| V25 | No circular dependency introduced | `go build` passing is enough; if modules are merged, additionally run `go list -deps` to compare |
| V26 | No commented-out "zombie code" | the diff has no large blocks of `// TODO` / `// DEPRECATED` comments; everything is truly deleted |
| V27 | No historical migration broken | if a DB schema is involved: confirm no DROP TABLE without a migration; enum value deletion does not break parsing of historical records |

### 2.7 Rollback feasibility
| # | Check | Pass criterion |
|---|---|---|
| V28 | PR is one module per commit | one module one commit; revert = rollback |
| V29 | Config rollback path | the deleted config template takes effect directly after revert, with no manual data backfill needed |

---

## 3. Final Report Format

The PR description or `iterations/{n}-{module}.md` must contain:

```
## Acceptance result ({module})

- Review Manifest: `.code-removal/runs/{date}-{module}/review-manifest.md`
- Supervisor Board: `.code-removal/runs/{date}-{module}/supervisor-board.md`
- Blind Review Result: `.code-removal/runs/{date}-{module}/blind-review-result.md`
- Execution Result: `.code-removal/runs/{date}-{module}/execution-result.md`
- Reviewer: {name} @ {date}

### Hard acceptance (V1–V29)
- V1 build-check.sh:  ✅
- V2 vet-check.sh:    ✅
- ...
- V29 rollback path:  ✅

### Residual grep record
- V7 directory name `{dir}`:      0 hits
- V8 service name `{service}`:    0 hits (2 retained in docs)
- ...

### Anomalies / exceptions
(If a test failure is unrelated to the deletion, list it here and link to base)
```

---

## 4. What Counts as "Thorough"

**Definition of thorough**: treat the codebase as a graph; after deleting the module, the graph must contain no "dead symbol / dead config / dead entry point reachable from live code." Concretely this is equivalent to:

1. No function that is still reachable but never executes (guaranteed by V7–V15 greps being empty)
2. No config that is still loaded but never used (guaranteed by V10, V16–V19)
3. No route/consumer/cron that is still registered but never triggered (guaranteed by V17, V22)
4. No package that still compiles but is never linked (guaranteed by V3 `tidy-check.sh` + diff)

**Definition of "no side effects"**: before and after the deletion, the external behavior of every **still-retained** service (API responses, the set of consumed topics, the Redis keys / DB tables written, the exposed metrics) is completely unchanged. Jointly guaranteed by the V20–V23 runtime smoke test + the V24 init review.

# dead-code-removal

A disciplined, **verifiable** workflow for removing dead code from a codebase — deprecated HTTP handlers, unused modules, orphan symbols — and getting it **correct AND complete in one pass**.

Most "delete the dead code" sessions fail in one of two ways: they miss a live caller and break the build, or they leave orphans behind (config keys, topics, Redis keys, CI mappings) that quietly rot. This skill exists to make that failure mode hard.

> **Status:** v0.1.0 — first public release. Battle-tested internally on a large Go monorepo; the methodology is mature, but the open-source packaging is new. Feedback and issues welcome.
>
> **Language focus:** v0.1 ships a Go-oriented validation toolchain (`go build` / `go vet` / `go mod tidy` wrappers). The *methodology* is language-agnostic — see [Extending to other languages](#extending-to-other-languages).

## What makes it different

- **3-role workflow with independent context** — a *Supervisor* triages and owns the removal manifest, an *Executor* deletes and validates, and a *Blind Reviewer* independently re-derives the dependency graph to catch what the Supervisor missed. They do not share reasoning chains, so the review is a real second opinion, not a rubber stamp.
- **Manifest-gated deletion** — nothing gets deleted until a review manifest (machine-readable `deletion_paths`) is approved. The gate is a hard stop.
- **Indirect-reference scanning** — explicit checklist of the reference paths people forget: generated proto packages, runtime endpoints, config templates, Kafka topics, Redis key prefixes, shared helpers, CI service maps.
- **Layered build validation** — delete top-down (routes → service → dao → model → consts → config), re-check the build after each layer.
- **Hard acceptance criteria** — a removal is "done" only when build, tests, vet, and a full-repo keyword grep all come back clean.
- **Closed-batch rule** — multiple modules are deleted together only when they form a closed dependency + rollback closure; otherwise one module per commit/PR.

## Install

### Option A — as a Claude Code plugin (recommended)

```
/plugin marketplace add ConnieHan2019/code-removal-skill
/plugin install dead-code-removal@dead-code-removal
```

The skill then activates automatically when you ask to remove dead code, or you can invoke it explicitly as `/dead-code-removal:dead-code-removal`.

### Option B — as a plain skill (copy or symlink)

```bash
git clone https://github.com/ConnieHan2019/code-removal-skill.git
ln -s "$(pwd)/code-removal-skill/plugins/dead-code-removal/skills/dead-code-removal" \
      ~/.claude/skills/dead-code-removal
```

(Copy instead of symlink if you prefer.) The skill appears as `/dead-code-removal`.

## Usage

Point it at a deprecated entry point or a module directory:

```
Remove the deprecated handler: GET /api/v1/legacy-export  (handler LegacyExport in api/export.go)
```

```
Remove module: services/legacy-reporting/
```

It will: confirm runtime roots are offline → build the dependency graph (including the indirect-reference checklist) → produce a review manifest → run a blind review → wait for your approval → delete in layers with build checks → run acceptance criteria.

## Repository layout

```
.
├── .claude-plugin/marketplace.json        # plugin marketplace catalog
├── plugins/dead-code-removal/
│   ├── .claude-plugin/plugin.json         # plugin manifest
│   └── skills/dead-code-removal/
│       ├── SKILL.md                       # core workflow (English, primary)
│       ├── SKILL.zh.md                    # Chinese version
│       ├── references/                    # contract docs, templates, checklists
│       │   └── drafts/                    # experimental / not-yet-implemented designs
│       └── scripts/                       # Go validation wrappers
└── LICENSE
```

## Extending to other languages

The validation scripts in `scripts/` are the only language-specific part. To support another language, replace the four wrappers with equivalents for your toolchain and keep the same contract:

| Script | Contract |
|---|---|
| `build-check.sh [pattern]` | Compile; exit non-zero on failure. |
| `vet-check.sh [pattern]` | Static analysis / lint; report new warnings. |
| `tidy-check.sh` | Prune unused dependencies; print the dependency-manifest diff. |
| `module-gone-check.sh <dir>` | Confirm a directory was fully removed. |

The SKILL.md workflow references these by name only, so swapping the toolchain does not change the methodology.

## Documentation language

- `SKILL.md` and the `references/*.md` are the English (primary) versions.
- `SKILL.zh.md` is the Chinese version of the core workflow.

## License

MIT — see [LICENSE](LICENSE).

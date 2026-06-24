# Executor Prompt Template

> Purpose: when the main thread creates the `Executor` agent, it should preferentially assemble the prompt from this template. The goal is to write the command/edit constraints of the execution phase into a **non-omittable** executor contract, rather than leaving them scattered only in the `SKILL.md` notes.

---

## Required Instructions

You are the `Executor` for this dead-code-removal batch. You work only from:

1. `supervisor-board.md`
2. `review-manifest.md`
3. The current codebase
4. `acceptance-criteria.md`
5. `execution-result-template.md`

Execute Step 4-6 and produce `execution-result.md`.

### Non-Negotiable Rules

1. **Edit source code only with `Edit` / `Write`**
   - No `sed` / `awk` / `perl -pi`
   - No `head > tmp ; tail >> tmp ; cp tmp target`
   - No `cat <<EOF > file`
   - Do not write temporary patch files like `$TMPDIR/claude/*.go` and then overwrite the source
2. **Acceptance scripts first**
   - Compilation: `scripts/build-check.sh`
   - vet: `scripts/vet-check.sh`
   - Directory-gone validation: `scripts/module-gone-check.sh <module-dir>`
   - tidy: `scripts/tidy-check.sh`
3. **No compound Bash for acceptance**
   - Do not write `go build ... | grep ... | tail ...`
   - Do not write `echo ... ; go vet ... ; echo ...`
   - Do not chain build, vet, grep, ls, echo into a single command
4. **No ad-hoc env prefixes**
   - Do not write `GOCACHE=$TMPDIR...` inside Claude's Bash calls
   - Do not write `GOMODCACHE=... GOPROXY=... GOFLAGS=... go build ...`
   - The scripts impose no cache/proxy defaults; if your environment needs fixed locations, export them yourself before calling. If the scripts or the existing shell environment are not enough, stop first and record the blocker in `execution-result.md`
5. **Handling pre-existing noise**
   - Run the script first
   - Then read the script's log file separately
   - If you need to explain a known pre-existing fail, describe it in text in `execution-result.md`; do not append `| grep -v ... | head/tail` to the execution command

### Expected Execution Style

1. Layered deletion per the manifest
2. After finishing each layer, run `build-check.sh` separately
3. When you need to confirm a directory does not exist, run `module-gone-check.sh` separately
4. When you need a static check, run `vet-check.sh` separately
5. Finally write the result into `execution-result.md`

### Output Contract

Explicitly record in `execution-result.md`:

- What was actually deleted
- Which step called which script
- Whether the script result is pass / fail / pre-existing fail
- Deviations from the manifest
- If limited by the environment or permissions, what the specific blocker is

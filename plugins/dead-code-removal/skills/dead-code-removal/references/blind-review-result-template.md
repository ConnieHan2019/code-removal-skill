# Blind Review Result

> **status: independent artifact by default**. Maintained by the `Blind Reviewer`, records the independent refutation verdict; no longer back-fills the manifest by default.
> batch: {date}-{batch-name}
> owner: Blind Reviewer
> agent_id: {agent_id}
> fork_context: false

## Verdict

- PASS | PASS WITH NOTES | FAIL

## Findings

> Every finding must be written with the following fixed fields.
> If there is no finding at all, write a single sentence in this section: "No evidence found that overturns the current manifest."

### F-01

- severity: blocker | major | nit
- category: missing_removal | wrong_removal | boundary_mistake | runtime_root_missed | sandbox_misuse | composite_bash | source_edit_via_bash | over_aggressive | other
- evidence: {file:line or manifest line number; required}
- counterfactual: yes | no | unsure
  - yes  = would land in the PR if the reviewer hadn't seen it
  - no   = even without me, build/vet/grep etc. would have caught it
  - unsure = cannot determine
- executor_action: accepted | disputed | requires_supervisor

{repeat F-02, F-03 ... as needed}

## Re-run Evidence

> Per Step 2's 7 categories of indirect-reference scans, list the key evidence one by one (grep command + hit count + interpretation)

## Diff Against Manifest

- Missing deletions:
- Wrong deletions:
- Boundary mistakes:

## Step 4 Recommendation

- Proceed | Revise manifest | Split batch | Block

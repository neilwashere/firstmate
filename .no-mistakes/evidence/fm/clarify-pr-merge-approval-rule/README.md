# Evidence: clarify the "Never merge a PR" standing rule

Branch `fm/clarify-pr-merge-approval-rule` (base `43bf6d3`, target `b26e616`).
The change rewords `AGENTS.md` hard rule 2 from
`Never merge a PR without the captain's explicit word.` to
`Never merge a PR without approval from the captain.`

## Artifacts

- `agents-md-hard-rule-2-before-after.png` / `.html` - the rendered
  captain-facing wording before and after, plus the qualified rule in its
  hard-rules list.
- `instruction-refresh-transcript.txt` - the real delivery path: a Pi session
  takes its instruction baseline on the pre-change `AGENTS.md`, the branch's file
  is put in place, and `bin/fm-session-start.sh --reemit --source compact`
  re-emits the current contract. The transcript shows the qualified rule as the
  agent receives it. Produced by `instruction-refresh-demo.sh`.
- `merge-approval-gate-transcript.txt` - the rule's operative condition exercised
  end to end against the real merge entrypoint `bin/fm-pr-merge.sh` with a mocked
  green forge: with no captain approval recorded the merge is refused and the
  forge is never called; after the captain's approval is recorded through
  `bin/fm-captain-hold.sh answer --release` the same merge lands and its
  authority record is persisted. Produced by `merge-approval-gate-demo.sh`.

## Reproducing

Both demo scripts need `tasks-axi` on `PATH`; on this host it lives in the nvm
bin directory the gate shell does not include, and the scripts prepend it
themselves.

```sh
EV=/home/neil_keith_com/.no-mistakes/evidence/01M31VA41A9SCJE21VA9HDE75C
bash "$EV/merge-approval-gate-demo.sh"

# the instruction-refresh demo needs the pre-change AGENTS.md:
mkdir -p /tmp/fm-base-43bf6d3
git -C <repo> archive 43bf6d3 AGENTS.md | tar -x -C /tmp/fm-base-43bf6d3
bash "$EV/instruction-refresh-demo.sh" /tmp/fm-base-43bf6d3/AGENTS.md
```

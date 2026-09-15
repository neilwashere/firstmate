# Evidence: secondmate home summary survives an argv-overflowing status payload

Branch `fm/fix-secondmate-home-summary-argv-overflow`
(base `2da3c5e` -> target `d46f31f`).

**Intent under test.** A task's status-derived payloads (the whole-status-log
open-decision fold, and a single unbounded status line with its note) rode jq
`--argjson`/`--arg`, i.e. ONE exec argument. Past Linux's 128 KiB
`MAX_ARG_STRLEN` the jq could not exec, the failure was swallowed by an
unchecked pipe, and the task vanished from the snapshot - so the published
`state/home-summary.json` went invalid (`orphan_in_flight`) and the home read as
orphaned/unreadable to Bearings. The fix moves those payloads onto files
(`--slurpfile`/`--rawfile`) and makes each per-task degradation keep the row.

Both scenarios below were run twice against the SAME fixture bytes: once with
`bin/fm-fleet-snapshot.sh` from the base commit (`sha1 f527fdb`) and once with
the fixed one (`sha1 8ca06ce`), through the real writer
(`bin/fm-home-summary-refresh.sh`), the real Bearings renderer
(`bin/fm-bearings-snapshot.sh`), and the real fleet view
(`bin/fm-fleet-view.sh`).

## Scenario A - 60 still-open captain decisions on one long-lived task

Only the accumulated fold crosses the per-argument limit (152,451 bytes).
Reproduce with `repro-silent-task-drop.sh <firstmate-root> <label>`.

| what the captain relies on | BEFORE (base) | AFTER (fix) |
| --- | --- | --- |
| writer exit | 0 (silent) | 0 |
| producer stderr | `jq: Argument list too long` | empty |
| published summary `valid` | `false` | `true` |
| published summary `invalidity` | `orphan_in_flight: ["migration-run"]` | `null` |
| tasks present in the summary | `["docs-pass"]` - the held task vanished | `["docs-pass","migration-run"]` |
| open captain decisions counted | `0` | `60` |
| Bearings secondmate row | `reason: structured home state invalid: in-flight backlog item has no child metadata: migration-run`, `secondmate_reconcile: orphan_in_flight ["migration-run"]` | `reason: "-"`, no reconcile row |
| parent aggregation of that home | `state: active_child_work`, `child_open_decisions: 0` | `state: captain_decision`, `child_open_decisions: 20` (summary's own disclosed 20-of-60 bound) |

Transcripts: `drop-transcript-before-base-2da3c5e.txt`,
`drop-transcript-after-fix-d46f31f.txt`.

## Scenario B - one oversized status line (186,155 bytes, mirrored note)

A single `needs-decision` line above the limit, as a directly appended or
remote-mirrored payload produces. Reproduce with
`repro-home-summary-argv-overflow.sh <firstmate-root> <label>`.

| what the captain relies on | BEFORE (base) | AFTER (fix) |
| --- | --- | --- |
| writer | `summary producer failed with exit 1: fm-fleet-snapshot: task observation failed`, exit 1 | exit 0 |
| `state/home-summary.json` | never written (`No such file or directory`) | published, `valid: true` |
| the held decision | absent | `release-gate / canary-rollout / needs-decision` |
| Bearings secondmate row | `unknown` - "structured home ledger is missing, unreadable, or invalid" | `active_child_work`, `provenance: structured-home, fresh` |
| Bearings `in_flight` | empty - no child work visible at all | the child's live task row |
| child's oversized bytes in the snapshot | n/a (no snapshot at all) | carried through: `tests/fm-home-summary-refresh.test.sh` asserts `current_state.detail` and `hints.open_decisions[0].summary` equal the full 200,000-character note, and `hints.last_event_text` is longer still |

Transcripts: `transcript-before-base-2da3c5e.txt`,
`transcript-after-fix-d46f31f.txt`.

## Automated regression proof

`tests/fm-home-summary-refresh.test.sh` (this branch's version) run against the
base snapshot script stops at the first new case with
`jq: Argument list too long`; against the target it passes every case.

- `regression-new-tests-fail-at-base.txt`
- `regression-new-tests-pass-at-target.txt`

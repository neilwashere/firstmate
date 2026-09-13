# Keith second-mate summaries: unreadable -> verifiable in Bearings

Fixture (built by `keith-summaries-repro.sh`, run once against the base commit
`b182d0f` and once against this branch's tip `4baefbd`, same fixture both times):

- a captain main home with **two registered local Keith second mates**
  (`keith-web`, `keith-api`), mirroring the two homes that went unreadable;
- each second-mate home has one **working** child (`*-checkout`), one parked
  child (`*-fees`), one queued **captain call**, and two **merged PR landings**;
- `keith-web`'s parked child accumulates 60 still-open keyed decisions with long
  notes (the whole-status-log fold, ~168 KB); `keith-api`'s live child carries
  **one** oversized mirrored remote payload line (~200 KB). Both exceed Linux's
  128 KiB `MAX_ARG_STRLEN` cap on a single exec argument.

## 1. Each second mate's own `state/home-summary.json` (bin/fm-home-summary-refresh.sh)

| home | before (`b182d0f`) | after (`4baefbd`) |
| --- | --- | --- |
| keith-web | `valid:false`, `invalidity:orphan_in_flight`, reason "in-flight backlog item has no child metadata: keith-web-fees", **1** open decision, 1 endpoint | `valid:true`, `invalidity:null`, **61** open decisions, 2 endpoints |
| keith-api | `valid:false`, `invalidity:orphan_in_flight`, reason "in-flight backlog item has no child metadata: keith-api-checkout", **no current work** (`active_children: []`), 1 endpoint | `valid:true`, `invalidity:null`, current work `keith-api-checkout`, 2 endpoints |

The "no child metadata" reason is the visible shape of the failure: the task's
metadata was there all along, but the oversized payload killed the composing `jq`
inside a pipeline whose exit status is discarded, so the row silently vanished and
the home read as an orphaned, invalid inventory. Nothing was printed on stderr in
the before run (`before-bearings.err` is empty) - the loss was silent.

Files: `before-keith-web-home-summary.json`, `before-keith-api-home-summary.json`,
`after-keith-web-home-summary.json`, `after-keith-api-home-summary.json`,
full transcripts in `keith-summaries-before.txt` / `keith-summaries-after.txt`.

## 2. Captain view: `bin/fm-bearings-snapshot.sh` (what `/bearings` reads)

Before -> after, same fixture (`bearings-before-after.diff`):

```
-in_flight[1]{id,kind,state,repo,name,doing}:
+in_flight[2]{id,kind,state,repo,name,doing}:
+  keith-api/keith-api-checkout,ship,working,keith,Rework the checkout fee schedule,harness busy (claude-hook)

-  keith-api,captain_decision,...,"structured home state invalid: in-flight backlog item has no child metadata: keith-api-checkout"
-  keith-web,captain_decision,...,"structured home state invalid: in-flight backlog item has no child metadata: keith-web-fees"
+  keith-api,captain_decision,...,"-"
+  keith-web,captain_decision,...,"-"

-  keith-api,null,null,orphan_in_flight,"[\"keith-api-checkout\"]"
-  keith-web,null,null,orphan_in_flight,"[\"keith-web-fees\"]"
+  keith-api,null,null,null,"[]"
+  keith-web,null,null,null,"[]"
```

After the fix both homes report readable structured state (`reason: "-"`, no
`orphan_in_flight` reconcile row), current work for both second mates is present in
Underway, the captain calls are in `decisions_open`, and the four merged PRs are in
`landed`.

(In this fixture the `landed` roll-up reads each second-mate backlog's Done section
directly, so those four rows survived the before run too; what the before run loses
is current work and the readability of both summaries. When the oversized payload
sits on a task whose home summary the producer cannot publish at all, the before run
publishes no `state/home-summary.json` for that home and the roll-up loses it as
well - observed while building this fixture.)

Files: `before-bearings.toon`, `after-bearings.toon`, `bearings-before-after.diff`.

## 3. Operator-raised parent activity bound (`activity-bound-check.sh`)

A parent-side mirrored status line of 200 KB with
`FM_SNAPSHOT_PARENT_ACTIVITY_BYTES=300000` (a supported operator bound above the
per-argument limit):

- before: `fm-fleet-snapshot.sh: line 337: /usr/bin/jq: Argument list too long`,
  `fm-fleet-snapshot: task observation failed`, exit 1 - no snapshot at all, so
  Bearings has nothing to render;
- after: exit 0, the registered second-mate record carries the full 200,022-byte
  parent event and its 200,000-byte activity record untruncated.

File: `activity-bound-check.txt`.

# Fails-before / passes-after, recorded per commit

Each run below used the CURRENT branch tests (`tests/fm-watch-triage.test.sh`,
`tests/fm-daemon.test.sh` at 0ffc881) driven against an OLDER copy of the
implementation file, restored with `git checkout --` immediately afterwards.
`tasks-axi` 0.2.6 (the repo minimum, `FM_TASKS_AXI_MIN`) was on PATH for every
run.

## 1. The reported behaviour: a held lane re-escalating as a possible wedge

Implementation under test: `bin/fm-watch.sh` from the base commit 9296f9b9.

```
$ git show 9296f9b9:bin/fm-watch.sh > bin/fm-watch.sh
$ FM_TEST_ONLY=test_settled_backlog_lane_stops_reescalating_an_unchanged_pane \
    bash tests/fm-watch-triage.test.sh
not ok - [captain] an unchanged settled lane re-escalated: stale: test:fm-wedge (idle 1s, possible wedge, escalation 1)
```

At HEAD (0ffc881) the same selector passes:

```
ok - an unchanged idle lane its backlog holds, parks, or finishes stops re-escalating and is rechecked on the long cadence, while an open one still escalates
```

## 2. The first authorised review fix: published wait age and window rebinding

Implementation under test: `bin/fm-watch.sh` from 63cb6fc (the original fix,
before the review fix in 0c6a29a).

```
$ git show 63cb6fc:bin/fm-watch.sh > bin/fm-watch.sh
$ FM_TEST_ONLY=test_settled_recheck_reports_the_real_wait_age \
    bash tests/fm-watch-triage.test.sh
not ok - [captain] the settled recheck published 2s, not the hold's own age of about 172806s: stale: test:fm-wedge (idle 2s, waiting 2s - held for the captain in the backlog, awaiting the captain, rechecked on a long cadence not a wedge; answer the held decision or release the hold)

$ FM_TEST_ONLY=test_settled_busy_over_age_lane_still_owes_its_recheck \
    bash tests/fm-watch-triage.test.sh
not ok - a busy over-age lane whose footer ticks never owed its settled recheck:
```

Both pass at HEAD (the second one is the hash-keyed-anchor case: the pre-fix
watcher never surfaced at all, so the round timed out).

## 3. The second authorised review fix: daemon mirror of the reset set

Implementation under test: `bin/fm-supervise-daemon.sh` from 0c6a29a (before the
mirror added in 0ffc881). Run through a driver holding only the one contract
test, deleted afterwards.

```
$ git show 0c6a29a:bin/fm-supervise-daemon.sh > bin/fm-supervise-daemon.sh
$ bash <driver with only test_handle_wake_terminal_signal_clears_pause_tracking>
not ok - terminal signal retained the watcher wait cadence anchor
```

At HEAD:

```
ok - a terminal signal clears pause and stale tracking across both supervisors
```

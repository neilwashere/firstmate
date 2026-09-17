# Argv-overflow fix: captain-facing before / after

Fixture in both columns is byte-identical: one firstmate home, one in-flight ship task
(`held-task`) whose status log has accumulated 60 never-resolved `needs-decision` notes
(~150 KB), i.e. an open-decision fold larger than Linux's 128 KiB per-exec-argument limit
(`MAX_ARG_STRLEN`). Only `bin/fm-fleet-snapshot.sh` differs: base commit `3eb5b63` vs
branch head `68405fc`. Same writer, same renderer, same libs.

Repro driver: `repro-home-summary-argv-overflow.sh`
Full transcripts: `home-summary-argv-overflow/{before,after}/transcript.txt`

To rebuild the base producer both drivers take as their second argument:

```sh
mkdir -p /tmp/base-bin
for f in bin/*; do ln -s "$PWD/$f" "/tmp/base-bin/$(basename "$f")"; done
for f in fm-fleet-snapshot.sh fm-contributions.sh; do
  rm "/tmp/base-bin/$f"
  git show 3eb5b6334a80e06083e3837f0032a5cec39b8e52:bin/$f > "/tmp/base-bin/$f"
  chmod +x "/tmp/base-bin/$f"
done
```

## 1. The published home summary (`state/home-summary.json`)

| | before (base) | after (branch) |
| --- | --- | --- |
| `valid` | **false** | **true** |
| `invalidity.kind` | **orphan_in_flight** (`held-task`) | null |
| `counts.decisions_open` | **0** | **60** |
| `counts.endpoints` | 0 | 1 |
| `counts.holds` | 0 | 1 |
| producer stderr | `jq: Argument list too long` | *(silent)* |
| producer exit | 0 (failure swallowed) | 0 |

## 2. `bin/fm-fleet-view.sh` — the human fleet view

before (base) — the live task silently vanished:

```
/…/bin/fm-fleet-snapshot.sh: line 842: /usr/bin/jq: Argument list too long
# Fleet View
## Under Way
No live task metadata found.
```

after (branch) — the task is rendered with its real state:

```
# Fleet View
## Under Way
| ID | Current | Kind | Repo/Project | Backend | Endpoint | ... |
| held-task | parked / status-log | ship | firstmate | tmux | present | ... |
```

## 3. `bin/fm-bearings-snapshot.sh` — the pick-up-where-I-left-off brief

before (base): the task is gone from `in_flight` and shows up only as a bogus gate:

```
in_flight: []
gates[1]{id,title,blocked_by,reason,owner,filed}:
  (main-inventory),in-flight backlog item has no child metadata,"-",main inventory,(main),null
```

after (branch): the task is present, and no bogus inventory gate is raised:

```
in_flight[1]{id,kind,state,repo,name,doing}:
  held-task,ship,parked,firstmate,Rollout gate awaiting captain calls,zzzzzz…
gates: []
```

## 4. Canonical contribution input (`--contribution-input`)

Second fixture: a long-lived home whose parsed backlog JSON is 418 KB (400 queued rows plus
one owned PR row). Repro driver: `repro-contribution-input.sh`;
transcripts under `contribution-input/{before,after}/transcript.txt`.

| | before (base) | after (branch) |
| --- | --- | --- |
| `--contribution-input` bytes printed | **0** (with `jq: Argument list too long`, exit **0**) | 573 648 |
| backlog records carried | *(unreadable)* | **401** |
| `fm-contributions.sh snapshot --all` → `complete` | **false** (silently degraded) | **true** |
| `poll` with an unreadable backlog | producer diagnostic only | producer diagnostic **plus** `fm-contributions: canonical contribution input unavailable` |

# Evidence: idle-alert suppression for held, parked, or finished child panes

Branch `fm/fix-held-idle-pane-reescalation` (base 9296f9b9, target 0ffc8811).

The end-user surface for this change is what a supervising turn is woken with:
the wake reason `bin/fm-watch.sh` emits and the durable wake queue
`bin/fm-wake-drain.sh` hands to the supervisor. There is no GUI surface, so the
reviewer-visible artifacts are CLI transcripts of a real watcher process driven
against a hermetic firstmate home.

| file | what it shows |
| --- | --- |
| `held-lane-before.txt` | base `bin/fm-watch.sh`: three supervision rounds on one unchanged idle pane held for the captain produce three wedge escalations, climbing into `demand-deep-inspection` |
| `held-lane-after.txt` | same scenario at HEAD: three rounds absorbed with zero wakes and no escalation counted, then ONE bounded recheck naming the hold, the captain, the action that clears it, and the hold's real age (172835s) |
| `still-alerts-after.txt` | at HEAD, the four lanes the suppression must not swallow: an unheld row, a held row whose crew is genuinely working, a released hold, and a changed pane - each still wakes the supervisor |
| `regression-before-after.md` | fails-before / passes-after for the original fix and both authorised review fixes |
| `held-lane-noise-demo.sh` | the demo driver behind the two held-lane transcripts (`FM_DEMO_REPO=<worktree> bash held-lane-noise-demo.sh "<label>"`) |
| `still-alerts-demo.sh` | the demo driver behind the still-alerts transcript |

Both demo scripts build their own throwaway home (fake tmux pane, fake crew
state, a real markdown backlog written by `tasks-axi`, a real captain hold
written by `bin/fm-captain-hold.sh`) and run the repository's real
`bin/fm-watch.sh`. `FM_STALE_ESCALATE_SECS=1` puts every round at the escalation
threshold immediately; the shipped default (240s) only changes how long that
takes. Nothing outside the throwaway home is touched.

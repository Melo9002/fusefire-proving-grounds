# Battle replay

Fuse Fire records successful authoritative actions during a battle. When the battle
ends, **Replay Battle** rebuilds the same seeded match and submits those actions through
the ordinary gameplay APIs. **Return to Match Setup** starts a blank setup screen.

## Recorded information

The in-memory `BattleReplayRecording` contains the complete battle configuration and an
ordered action list. Each action identifies its actor, round, and phase. It also carries
an authoritative post-action fingerprint containing the phase, active unit, battle
result, every remaining unit's cell, HP, AP, defense and carried actor, objective
progress, and extraction totals. Depending on
the action, it also records movement cells, an attack target and outcome, a rescue
target, extraction, defense, or a phase advance.

The main participants are:

- `BattleReplayRecorder`: observes successful actions without choosing or executing them.
- `BattleReplaySession`: retains the latest completed battle while the game is running.
- `BattleReplayPlayer`: rebuilds the match, disables normal input and AI, and executes the log.
- `BattleLevel`: creates the recorder or player and owns the end-screen navigation.

Movement, attacks, defense, rescue, extraction, and turn advancement still use
`BattleController`, `ObjectiveManager`, and `TurnManager`. Replay therefore detects
rule or determinism drift instead of concealing it with a visual-only reenactment.

## Testing

Play any battle through victory or defeat. The result UI should expose both buttons.
Press **Replay Battle** and confirm the HUD says `REPLAY`, the same map and actors are
created, ordinary controls stay disabled, and the same result is reached. The console
prints the number of recorded actions followed by `COMPLETED` or `DIVERGED`.
`COMPLETED` also reports how many action fingerprints matched. A mismatch prints the
first divergent action plus its expected and actual states.

Replay uses a dedicated bottom bar. **Pause/Play** stops between complete authoritative
actions, speed choices from 0.5× to 4× adjust movement and action pacing, and the camera
can remain **Free** or **Follow Action** by centering on each acting unit. The bar also
shows action progress and can return directly to Match Setup. Tactical action, AP,
portrait, objective, world-bar, and debug UI is hidden during playback.

Run the automated end-to-end check with:

```powershell
godot_console --headless --path . --script res://tests/battle_replay_smoke.gd
```

## Current boundary

The recording currently lives in memory and replays sequentially. It does not yet
provide saved replay files, rewind/timeline scrubbing, pseudo-real-time reconstruction,
smooth cinematic tracking, or a camera mode that follows only the final mover in an
activation.

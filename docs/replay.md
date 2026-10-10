# Battle replay

FuseFire replay is a deterministic verification journal. It rebuilds the recorded battle and submits each recorded decision through the same authoritative action, turn, and mission systems used during play. Cameras and animation present the newly committed results; they are never replay authority.

## Where the system lives

| Responsibility | File |
| --- | --- |
| Versioned envelope, JSON conversion, compatibility | `systems/replay/battle_replay_recording.gd` |
| Observing committed events | `systems/replay/battle_replay_recorder.gd` |
| Reconstruction, submission, and verification | `systems/replay/battle_replay_player.gd` |
| Canonical post-commit state | `systems/replay/battle_state_fingerprint.gd` |
| Field comparison and record validation | `systems/replay/replay_record_tools.gd` |
| Current in-memory recording and file helpers | `systems/replay/battle_replay_session.gd` |
| Pause, speed, and camera controls | `ui/replay_controls.gd` |

## Schema 3

A current recording contains:

- `schema_version` and `simulation_version`;
- the complete normalized battle configuration and generation seed;
- an initial authoritative fingerprint;
- the expected final battle result;
- ordered records with a stable `record_index`;
- action/command schema, transaction identity, base revision, and committed revision;
- a typed request and resolved result for unit actions;
- a post-commit state fingerprint.

Requests use stable tactical actor IDs. Current Attack results include the deterministic roll, hit chance, damage, AP/HP changes, Supply Points before/cost/after, defeat, and battle result. Reload records AP and Supply Points before/after and consumes no combat RNG. Move results include origin, destination, AP, objective state, and carried actor. Mission results include objectives, extraction counters, and roster removal. Turn and departure records remain commands because they do not have unit-action target and cost semantics.

Camera position, animation state, interpolation, particles, and UI are intentionally absent.

## Playback and divergence

Playback first verifies the envelope and initial reconstructed state. Before each schema-3 record it verifies the base revision. Tactical requests retain their recorded revision and pass through `TacticalActionService`; playback does not repair stale data. After commit it compares transaction/revision identity, resolved fields, committed revision, and the full state fingerprint.

The first failure stops playback and reports its stage:

- **reconstruction** — envelope, record, initial map, roster, or objective state;
- **validation** — stale revision or illegal request;
- **resolution** — rejection, RNG outcome, cost, target, or action result;
- **commit** — transaction/revision ordering;
- **comparison** — resulting battle fingerprint.

Diagnostics include record index, kind, transaction, revisions, actor/target, and expected versus actual field values.

## Saving and loading

Recordings remain in memory for the end-screen Replay button. Tools and tests can also persist readable JSON:

```gdscript
var error := BattleReplaySession.save_last("user://replays/my_battle.json")
var recording := BattleReplaySession.load_recording("user://replays/my_battle.json")
if not recording.is_playable():
	push_error(recording.validation_error)
```

The JSON contains plain arrays, dictionaries, numbers, strings, and booleans. Mission Resources and `Vector2i` values are converted explicitly at the envelope boundary.

## Compatibility policy

- **Schema 3** is the production format.
- **Schema 2** is supported as a narrow Prototype 1 in-memory compatibility path. Missing revisions are normalized at playback, and the old already-applied consequence coalescing behavior remains limited to this schema.
- Other envelope versions fail before playback with a message naming the supported versions.
- Defend retains its original one-AP behavior for legacy records. It is never silently translated to Wait.
- Action payload schema numbers remain explicit. Reload uses payload schema 3; current Attack and Aim use payload schema 4. Historical Attack payload schemas 2 and 3 remain accepted and are interpreted through the recording's trusted SP/Aim feature flags.
- Recordings created before Supply Points lack `supply_points_enabled`. Playback treats those recordings as pre-SP rules: payload-v2 Attacks do not consume SP, and their state fingerprints omit SP fields. New configurations write `supply_points_enabled = true`, use payload-v3 Attack/Reload facts, and verify current/max SP. This preserves historical meaning instead of silently applying a new resource rule to old decisions.

Compatibility is intentionally finite. There is no promise that every development recording will remain playable forever.

## Presentation controls

The replay bar supports pause/play, 0.5×–4× pacing, and Free, Follow Action, or Cinematic camera modes. Pausing freezes tactical progression and in-progress movement while leaving the inspection camera responsive. Presentation can be suppressed in headless tests without changing RNG, transactions, fingerprints, or mission outcome.

## XCOM history lesson and future rewind

XCOM 2's installed SDK keeps indexed authoritative `XComGameStateHistory` frames and lets its replay manager move visualization through committed history indices. FuseFire uses a smaller request/result journal suited to Godot and the current game, while preserving stable identities, ordered revisions, and a presentation boundary.

A future rewind should restore a recorded snapshot or reconstruct from the initial configuration through a chosen `record_index`, then resume forward presentation. It should not reverse animations or invent inverse actions. Snapshot cadence, branching history, and timeline UI are outside Prototype 1.5.

## Tests

```powershell
godot_console --headless --path . --script tests/replay_schema_test.gd
godot_console --headless --path . --script tests/battle_replay_smoke.gd
godot_console --headless --path . --script tests/rescue_battle_replay_smoke.gd
godot_console --headless --path . --script tests/departure_replay_smoke.gd
```

The complete release gate also runs action-service, AI determinism, objective, evacuation, traversal, dependency-isolation, and Prototype 1 milestone suites.

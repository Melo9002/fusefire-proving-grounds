# Prototype 1.5 replay architecture audit

## Scope and verified baseline

This audit describes the repository at checkpoint `4ea66a7` before Task 01.5 implementation.

FuseFire already re-simulates recorded decisions. `BattleReplayRecorder` observes committed tactical results and turn/mission commands; `BattleReplayPlayer` rebuilds `BattleLevel` from `BattleConfiguration`, disables ordinary control, and submits actions through `TacticalActionService`, `TurnManager`, and `ObjectiveManager`. Recorded outcomes are compared with newly resolved outcomes, then `BattleStateFingerprint` verifies the authoritative post-action state. Camera modes, pause, speed, and movement pacing sit outside that authority.

The initial configuration captures team counts, map source and size, battle seed, VIP policy, mission resource, difficulty, and refinery choice. The same battle seed drives map generation, combat RNG, and AI decision RNG. Generated units receive deterministic faction/index tactical IDs. Fingerprints sort units by tactical ID before serialization and include round, phase, active actor, result, occupancy, HP, AP, defense, carried actor, objectives, and extraction counters.

Typed Attack, Move, Wait/Defend, Rescue, and Extract results already serialize stable actor IDs, requests, resolved evidence, and transaction IDs. Automatic Reach and Rescue changes are stored inside their parent Move result and resulting fingerprint. They are not intentionally submitted as separate actions. Turn transitions and departure remain dedicated commands.

## Verified gaps

1. The replay envelope declares schema version 2 but has no centralized structural validation, compatibility policy, dictionary round trip, or readable disk format.
2. Move, simple, and mission action records omit `base_revision` and `committed_revision`, although their runtime results contain both.
3. Playback replaces a recorded request revision with the current revision. This permits a damaged recording to avoid the stale-request check instead of diagnosing the mismatch.
4. Playback compares resolved payloads but does not consistently compare transaction IDs or committed revisions.
5. Error reporting is distributed among generic `push_error` calls. Some paths identify an action index, while others omit stage, actor, target, revision, or the exact field.
6. Prototype 1 compatibility is implicit. Mission records without requests and the Defend action are accepted, but the supported envelope/action versions are not documented in one place.
7. The in-memory configuration contains Godot Resources and vectors. It reconstructs correctly in-process but is not directly suitable for readable JSON inspection.
8. Turn records use actor node names. Current unit names equal stable tactical IDs, but the command producer does not explicitly request the tactical ID.

## Determinism audit

- **Verified:** combat RNG is seeded by battle seed and is consumed only after final action validation.
- **Verified:** map reconstruction uses the recorded generation seed; authored/generated selection and map size are captured.
- **Verified:** tactical IDs are deterministic for generated and authored team rosters and the rescue target.
- **Verified:** the action service owns shared state revisions; turn and departure commands advance that same revision.
- **Verified:** fingerprints sort occupancy actors and therefore do not depend on dictionary iteration order.
- **Verified by existing tests:** AI action sequences, replay outcomes, vertical traversal, rescue/extraction, departure, and dependency isolation are repeatable for their fixed fixtures.
- **Risk, currently covered by fixture comparison:** several scorers/path searches sort only by score or cost. Equal-score ordering can inherit insertion order. No existing deterministic fixture demonstrates divergence, so Task 01.5 should not rewrite those algorithms without a failing case.
- **Presentation independent:** committed results exist before camera/animation work. Replay pause and speed alter pacing; suppressed/headless execution uses the same service results.

## Implementation direction

Task 01.5 should retain the current explicit scripts and add a narrow replay schema boundary: a versioned envelope with validation and JSON conversion, complete action revision fields, a single field-level comparison helper, staged divergence diagnostics, and an explicit schema-2 compatibility path. Playback must preserve recorded revisions for current-schema actions and verify transaction/revision ordering before and after submission. Legacy schema 2 may normalize missing fields, but unsupported versions must fail before playback.

Defend remains supported only as an explicitly documented legacy action with its original one-AP semantics. It must never be translated into Wait.

## XCOM 2 history reference

The installed War of the Chosen SDK confirms why XCOM can move through tactical history. `Development/SrcOrig/XComGame/Classes/XComGameStateHistory.uc` exposes indexed history frames, object lookup at a chosen `HistoryIndex`, current/previous object states, cache reconstruction, and `SetCurrentHistoryIndex`. `XComMPReplayMgr.uc` receives a complete `XComGameStateHistory`, places the history at a chosen frame, and asks the visualization manager to step forward through already committed frames.

The transferable principle is an ordered authoritative history with stable object identity and presentation driven from a selected committed frame. FuseFire should not copy XCOM's native object-history machinery at its current scale. Task 01.5's versioned journal and initial-state reconstruction provide the smaller foundation. A future rewind feature should restore an explicit snapshot or rebuild from the initial configuration to a selected record index, then present forward; it should never attempt to reverse animations or invent inverse gameplay actions.

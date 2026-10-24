# Phase 6.3: Replay Determinism and Edited-Map Gameplay

## Outcome

Generation 2.0 replay now reconstructs the exact accepted unified layout document rather than asking the generator to recreate a battlefield from its seed. A saved edited industrial layout was loaded, compiled, played through a real 35-action Eliminate battle, persisted as replay JSON, reconstructed, and replayed to the same victory with all 35 post-action tactical fingerprints verified.

The Map Editor now exposes **Play edited battlefield** in composition mode. It validates the current document through the same `Generation2BattlefieldBuilder.compile_document()` boundary used by runtime and replay before opening a normal 2-versus-2 Eliminate battle. Invalid documents remain in the editor with an actionable error.

Generation 2.0 remains opt-in and the legacy/default battle path is unchanged.

## Replay architecture audit

FuseFire uses deterministic command re-execution, not video playback or periodic simulation snapshots:

- `BattleReplayRecorder` observes committed tactical actions, mission commands and turn commands.
- Every record carries stable actor identity, request/result facts, transaction/revision ordering and an authoritative post-commit state fingerprint.
- `BattleReplayPlayer` rebuilds the initial battle, submits each request through the ordinary action and mission services, compares resolved facts, then compares the complete state fingerprint.
- The initial configuration owns force composition, mission rules, seed and feature compatibility flags.
- Camera modes and animation present committed results but are not replay authority.

Before this task, the replay JSON serializer omitted `battlefield_preset`, and Generation 2.0 playback had no accepted layout representation. A seed could at best rerun current generation code; it could not preserve edits or protect against content and algorithm changes.

## Reconstruction contract

Current Generation 2.0 recordings now include:

- the Generation 2.0 preset and ordinary battle configuration;
- the complete validated `BattlefieldLayoutDocument`;
- a SHA-256 signature calculated from its JSON-normalized persistence form;
- placement, assembly, relationship, reservation, mission-zone and dependency records already owned by that document;
- the existing initial tactical fingerprint and ordered action journal.

Playback validates the embedded document and current dependencies, compiles it through the shared document compiler, presents the resulting `MapData`, verifies the reconstructed document signature, then begins normal replay execution. It never regenerates this environment from the seed. Historical guarantees therefore cover unchanged documents and compatible dependencies, not arbitrary future asset revisions.

Legacy and schema-3 non-Generation-2.0 recordings remain valid without an embedded document.

## Edited-map workflow exercised

The automated fixture performs this complete path:

1. Generate industrial seed `17` twice and compare accepted documents and compiled tactical state.
2. Create an independent editable copy.
3. Add one optional imported streetlight at a placement accepted by layout, reservation and relationship validation.
4. Recompile and revalidate the edited document.
5. Save and reload it through `MapEditorLayoutStore` schema 2.
6. Initialize a normal battle through `BattleLevel.configure_layout_document()`.
7. Run a two-player-versus-one-enemy Eliminate battle under the ordinary AI/action pipeline.
8. Record movement, attacks, turn progression, HP changes and mission victory.
9. Save and reload the replay JSON.
10. Compile the embedded edited document and replay all 35 records.
11. Compare every resolved action and post-commit tactical fingerprint, the final mission result, and presented placement transforms.

The same runtime boundary rejects document/configuration map-size disagreement rather than silently compiling a different battlefield.

## Compatibility corrections

Two narrow defects were corrected:

1. `BattleReplayRecording` now persists `battlefield_preset`. Missing historical values still default to Legacy.
2. JSON reload represents integral coordinates as numeric variants. Replay comparison previously treated `[58.0, 0.0, 1.0]` and `[58, 0, 1]` as different. Recursive array comparison now accepts numerically equivalent values while preserving exact diagnostics for real differences.

No action resolution, tactical RNG, pathfinding, LOS, cover, mission, or camera rules changed.

## Failure evidence

Focused negative cases verify explicit rejection of:

- missing referenced assets;
- stale geometry/calibration dependencies;
- unresolved required relationship endpoints;
- unsupported environment identity;
- insufficient edited deployment space;
- document/configuration dimension mismatch;
- malformed saved-layout JSON; and
- Generation 2.0 replay without its embedded layout document.

Document validation runs before battle activation. A failed edited document cannot create a partially playable battle. Replay validation also runs before the first recorded action.

## Rendered inspection

Run:

```powershell
godot_console --path . --resolution 1600x900 --script res://tests/generation_2_replay_edited_map_capture.gd -- docs/architecture/reviews/evidence/generation-2-replay-edited-map-task-6.3
```

Evidence:

- [edited battle](evidence/generation-2-replay-edited-map-task-6.3/generation-2-edited-battle.png)
- [reconstructed replay](evidence/generation-2-replay-edited-map-task-6.3/generation-2-edited-replay.png)

Both captures use the same seed-17 edited placement document and camera framing. Visual inspection confirms matching imported roads, buildings, sidewalks and street furniture. The replay capture shows the existing replay controls and hides normal tactical controls as intended. Automated placement signatures independently establish component identity, origin and rotation agreement; the screenshots are supporting visual evidence rather than tactical proof.

## Verification commands

```powershell
godot_console --headless --path . --script res://tests/generation_2_replay_edited_map_test.gd
godot_console --headless --path . --script res://tests/replay_schema_test.gd
```

The focused lifecycle completed with `0 failure(s)`: 35 of 35 replay records verified and both the original and playback reached Victory. Replay-schema coverage completed with `0 failure(s)`.

Project Ironclad verification on the final tree:

- `./tools/run_tests.ps1 subsystem -Subsystem replay`: **PASS=10, FAIL=0, SKIP=1** in 295.28 seconds. The one skip is the deliberately explicit GPU capture script.
- `./tools/run_tests.ps1 smoke`: **PASS=10, FAIL=0, SKIP=0** in 79.42 seconds.
- The explicit GPU capture command completed successfully and both resulting views were inspected manually.

## Remaining limitations and Task 6.4 readiness

- Generation 2.0 runtime selection remains the single industrial 60×50 preset.
- The editor play button deliberately supplies the existing representative 2v2 Eliminate configuration; it is not a new mission-selection UI.
- Replay embeds the complete layout document, so files are larger than seed-only records.
- A stale required dependency makes the replay intentionally unplayable; no asset substitution or historical asset archive exists.
- Cosmetic particle timing and interpolation are not fingerprinted and remain presentation-only.
- Replay compatibility remains finite. This task does not promise playback across arbitrary future simulation-version changes.

The shared document, tactical compiler and presenter now support normal Generation 2.0 play, edited-map play and deterministic replay reconstruction without enabling Generation 2.0 by default. The boundary is ready for Task 6.4 review, which was not started here.

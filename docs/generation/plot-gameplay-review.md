# T11 — Plot gameplay, edited maps and composition review

Date: 2026-10-29. Implementation verified; **Gate E remains open**. Owner authorized implementation and Git publication, not fabricated review of individual content revisions.

## Engineering result

Authored plots enter the existing `BattleLevel`, tactical simulation, terrain presenter and replay player. `BattlefieldRuntimePreparation` owns document/configuration/deployment validation. The old industrial builder delegates document preparation to it and retains only its legacy generation orchestration. `AUTHORED_PLOT` is appended to the preset enum, preserving existing serialized values; it requires an accepted document and cannot silently regenerate an industrial map. Plot mission mismatch rejects before geometry, units or active map activation.

The plot workspace now offers **Play map** and **Open saved battlefield**. Opening restores the exact accepted choices and their embedded plot source, without a selection rerun. **Back to plan** exposes editable source; changing it invalidates the accepted preview and requires composition again. Rejected load preserves the existing source/preview. Source edits can be undone. Published chunk interiors remain immutable: edit a chunk source and republish it separately, rather than mutating its accepted world leaves.

`BattleReplayRecording` now serializes mission terminal definitions: identity, objective, position/elevation and initial activation state. A natural Terminal completion reproduced the old omission: replay had no terminal and failed its initial fingerprint. Full replay now agrees. Old recordings missing terminal definitions are not retroactively repaired or given invented mission data.

Runtime/replay/store APIs accept the shared resolution context for isolated library operations. Production defaults still enforce the production publication index; test registrations cannot leak into it. No new registry, map writer, simulation or battle scene.

## Verification and failures diagnosed

| Check | Result |
| --- | --- |
| `tests/plot_runtime_replay_test.gd` | 29 checks pass: common preparation; wrong mission/missing document; no partial activation; save/load; editor reopening, rejected load, slot edit, undo and sparse overlays; natural gameplay/replay |
| Saved, editor-modified through-street / seed 17 / Eliminate | Two players, one enemy; natural victory, normal legal actions; replay 26/26 actions and victory |
| Service-access / seed 42 / Terminal | Two players, one enemy; public movement/terminal queries and submissions, normal enemy turns, no teleports or AP/HP changes; victory; replay 15/15 actions |
| Existing `generation_2_replay_edited_map_test.gd` | Pass; legacy industrial edited-map compatibility retained |
| Existing `battle_replay_smoke.gd` | Pass; 41/41 replay actions, recorded/replayed defeat agrees |
| Existing `mission_terminal_interaction_test.gd` | Pass |
| `replay_schema_test.gd` | Pass, including new non-default terminal identity/position/elevation/initial-state round trip |
| Ironclad smoke | 10 pass, 0 fail, 0 skip; `artifacts/test-results/20261029-064752-smoke/` |
| Fixed/holdout graphics matrix | 20/20 compile and save; 60 captures; zero final capture errors |

The first save/load test incorrectly compared raw JSON-byte signatures across numeric normalization. It now compares the entire canonical serialized document, preserving every field. The slot-enlargement test initially compared solver-ordered arrays; constrained-slot priority legitimately changes their order. It now compares complete choices by stable slot ID, including revisions and transforms. Neither change removes a gameplay invariant. The final runtime test plays the **saved, reopened editor-modified** composition.

Diagnostic drawing also exposed a real presentation defect: empty frontage/mission layers attempted empty `ImmediateMesh` surfaces. Drawing now collects each layer and creates only nonempty surfaces. The editor regression and rendered matrix exercise that path. Initial capture retries used fresh isolated libraries because immutable registered evidence correctly rejects replacement; no production approvals were modified.

Headless tests establish tactical/replay behavior, not visual quality. Full repository suites were not run. Existing certificate-store warnings remain environmental. The fixed/holdout matrix does **not** claim 20 natural mission playthroughs: those are the two representative gameplay cases above.

## Fixed and holdout evidence

Seeds declared before the run:

- Fixed: **17, 42, 73, 101, 211**.
- Holdout: **307, 419, 563, 701, 887**.
- Both `through_street_industrial` and `yard_service_access`; every seed retained.
- Each result: overhead, oblique and diagnostic view. Orange capsules are explicit 1.8 m scale references, not simulated units.
- [Manifest](../../artifacts/t11-review/manifest.json) and [capture script](../../tests/plot_review_capture.gd). Captures are retained in Git; generated accepted documents, synthetic libraries and verbose logs remain local/reproducible.
- Run graphics evidence: `godot_console --path . --script res://tests/plot_review_capture.gd`.
- Run focused runtime verification: `godot_console --headless --path . --script res://tests/plot_runtime_replay_test.gd`.

Direct visual sampling covered through-street 17 oblique, 42 diagnostic, 887 overhead; service-access 17 overhead, 307 diagnostic and 887 oblique. All 20 underwent compilation/save and capture checks. This is sampling, not an assertion that every seam in all 60 images was manually reviewed. Close frontage/seam inspection in the interactive editor remains part of Gate E.

## Composition assessment

**Working:** straight streets connect consistently; warehouse loading/frontage orientation is intelligible; source chunks remain intact across world rotation; service yards present recognizable arrangements instead of individual structural fragments. The two plots produce different large-scale arrangements using the same small library. Saved choices and tactical state survive runtime/replay.

**Not yet sufficient:** both maps contain large empty areas, sparse cover away from a few islands, and exposed road approaches. Through-street runtime metrics reported score 43, 93% open area and 100% deployment exposure. These metrics are warnings to inspect, not a substitute for gameplay judgment. Current eligible slot choices are effectively fixed; most seed variation comes from a few population props. No evidence yet demonstrates substantial tactical variety, balanced deployment, useful road intersections, or improved authoring time at scale.

The overhead service-access warehouse appears to project beyond the base plane due to the camera/height. A targeted actual-mesh probe found X bounds **[-29, -16]**, within the map's **[-30, 30]** boundary; that image alone is not evidence of out-of-bounds placement.

**Recommendation:** retain this architecture and improve these authored proof plots before scaling the library or authorizing a procedural planner. Add deliberate cover sequences, protected deployment approaches and meaningful flank alternatives inside declared population permissions; make at least two compatible slot candidates create a genuinely different tactical situation. Use poles/wiring and similar dressing in a later relationship-aware map pass; they are not a substitute for tactical composition. Measure time to author/edit a third plot, then judge the reuse benefit.

## Owner playtest checklist

1. Open **Map Editor → Author — Chunk Authoring**. Review the pilot sources and explicitly validate/review/register desired exact revisions. The automated test library is separate and does not make production content eligible.
2. Switch to **Author — Plot Authoring**. Open each named plot, **Build map** (missing street pins are filled from registered content; existing pins stay fixed). If blocked, inspect the missing/stale revision message rather than bypassing approval.
3. Try seeds 17 and 42, then one listed holdout. Inspect warehouse entrances, sidewalks, access strips, yard edges and scale from overhead and ground-near camera positions. Note long exposed routes and empty spaces.
4. **Save map**, then **Open saved battlefield**. Confirm the same arrangement. Use **Back to plan**, enlarge a slot, undo/redo, compose, and save the edited result. Confirm no stretching or lost connections.
5. **Play map**. Play Eliminate and Terminal. Check usable approaches, cover, targeting/LOS, movement and whether the terminal is reachable without awkward detours. Runtime proof used 2v1; the editor's default 2v2 still needs owner usability/balance review.
6. Review the recorded replay and report camera/visual mismatches separately from tactical failures. Give a verdict on whether these maps are enjoyable enough to expand, not merely whether they launch.

The requested reminder after T11 is configured. Owner playability review and fresh independent architecture review are still pending; no independent reviewer agent was run without authorization. Gate E is not automatically approved, and no unrestricted procedural road planner is authorized.

## Retirement and preservation

Retired duplicated document/deployment preparation from the industrial builder; it is now a compatibility delegation to the common service. Shared editor overlay construction avoids duplicate empty-layer handling. Legacy coherent generation, industrial reference fixtures and legacy save adapters remain until the T15 caller/compatibility audit; this task does not delete useful regression coverage merely to remove old names.

**Owner direction, 2026-10-29:** preserve the authored **Refinery structure** for future refinement. Before its old orchestration is removed, identify and snapshot its exact source/dependencies/output. Other legacy maps need not all migrate; retire them when their useful gameplay/test contracts are covered. No legacy maps were deleted in T11.

# 03, step 6 — Depot cameras and obstruction

The Depot proof now has a placement correction and a small fix in the existing visual-occlusion component. No new camera system, collision geometry or tactical rule was introduced.

## Fixes

**Placement first:** moved the neighboring EastWorkshop 10 units farther east and extended its existing apron to support it. The previously blocked eye `(32, 4, 0)`, looking toward `(-8, 2, 0)`, is now outside the building's mesh. The building stays outside tactical cells; roads, entrances, yellow limits, parcels and mission data are unchanged.

**Saved-scene fading:** `TacticalVisualOccluder.occlusion_bounds` is a runtime cache, not serialized scene data. Runtime placement helpers supplied it, but loaded scene instances could have an empty cache. Their fallback fade therefore failed during floor browsing and replay, even though selected-unit apertures worked.

The existing component now derives missing camera bounds from descendant meshes on load, including their transforms. Explicit supplied bounds retain precedence; an initially empty wrapper can still collect meshes attached later. Fade restoration preserves original transparency. This is camera presentation only: it neither generates tactical boundaries nor changes movement, shots, LOS or cover. It requires no manual asset edits or export step and adds no editor/generation dependency.

## Executed review

`tests/depot_camera_readability_test.gd` uses both Depot layouts, seeds 16/17, through real BattleLevel instances:

- **96 orbit/zoom poses:** four yaw directions, pitches 2/12/45/88 degrees and zoom distances 4/20/56. Middle-drag handlers, wheel input, bounded pan and recenter are exercised. Camera transforms remain finite and the selected subject's blocking surfaces are opened/faded by existing behavior.
- **Floor inspection:** a controlled sightline through the saved workshop uses the real inspection/fallback path. Scenery fades and restores its original transparency afterward.
- **Live action framing:** the existing ActionCameraDirector frames a forced attack-style focus, then returns control without a stuck transition. This preview commits no attack; the tactical fingerprint stays unchanged.
- **Saved-file replay:** a real Aim action is saved/reloaded and verified in Free, Selection Focus and Cinematic modes for each layout. Playback finishes and releases cinematic ownership.
- **Rendered evidence:** 20 images under `artifacts/depot-camera-review/`, including the cleared westward pose, inspection, four orbit views, live action framing and final replay-camera states for each layout. Representative images/contact sheets are inspected; replay-mode result images show the final view, not every intermediate cinematic frame.

The focused regression recorded **six failures before the fixes**, then **zero failures** with all 96 poses retained. Test setup explicitly restores the lens rotation after a manually positioned diagnostic shot. Fade comparisons allow the usual floating-point representation of 0.82 rather than changing the intended opacity.

The orbit review is scripted in-engine input-handler exercise, not an OS mouse playtest. Apertures prioritize the selected friendly unit; the checks do not promise that every unselected unit remains visible from every angle.

## Broader verification

| Check | Result |
| --- | --- |
| UI subsystem, including camera obstruction, camera pitch/selection, pause, parcel camera handoff and multi-floor garage aperture/picking | **25 passed, 0 failed, 1 explicit-only capture skipped**, 81.12 s; `artifacts/test-results/20261115-211937-subsystem-ui` |
| Replay subsystem, including the 48-case current mission matrix and complete new-site/local parcel replays | **15 passed, 0 failed, 0 skipped**, 203.75 s; `artifacts/test-results/20261115-211731-subsystem-replay` |
| Existing Depot surroundings, boundary, distant view, world-area ownership and current-generation checks after placement changes | **5 passed, 0 failed** |
| Additional bounded Depot seed-16 Eliminate playthrough, saved-file replay forced to Cinematic | **Round 6 victory, 66/66 actions verified to the same victory**, zero failures; `artifacts/depot-complete-camera-replay.txt` |

The complete Depot run adapted the existing content-playthrough diagnostic to Depot and Cinematic playback while retaining its assertions. It ran headlessly; it proves execution/state agreement, not visual quality throughout all 66 actions. Its temporary script was removed afterward. The permanent focused camera check and render mode preserve the narrower reproduction.

Depot itself is flat. Actual upper/ground floor browsing and picking were checked with the existing internal garage fixture, not by introducing another playable map. Source camera avoidance, shoulder/elevated alternatives, hiding unavoidable visual blockers and restoring them remain the existing implementation; their regressions passed.

No full-suite rerun was performed. No script/parse/shader errors or new leak warnings were found in the final inspected logs. Sandbox certificate/log-store/editor-settings messages remain environment diagnostics. Older local-content recordings may explicitly reject a changed script dependency hash, as required by their existing snapshot contract; current recordings were saved/reopened and verified.

## Stopping point

Step 6 is complete for the bounded Depot proof. The known workshop obstruction has a direct reproduction, placement fix and camera fallback coverage. This does not claim collision-free camera movement from every conceivable point, final cinematic composition or renderer performance compliance. Next is step 7: edge navigation/targeting and tactical isolation/replay validation. Measured budgets and the other sites' content rollout remain later tasks.

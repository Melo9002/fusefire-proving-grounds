# Battlefield polish

## Service Depot playtest

Use Service Depot, seed `66566043`, two units per side and Eliminate. The supplied recording contains 62 actions and finishes in victory. Its exact manifest uses compiler revision 1.

- After action index 24, the shot from `(18, 0, 13)` to `(22, 0, 14)` was blocked by the delivery truck's cell-sized obstruction. After index 43, the shot from `(22, 0, 14)` to `(24, 0, 22)` was blocked by the warehouse corner. Each of the five shot samples missed the corresponding imported mesh in both cases.
- New battles use compiler revision 2. The loading parcels' authored rectangular solids clip shot obstruction within occupied cells. A shot through the truck still hits its obstruction. Movement, stopping and directional cover retain their cell contracts. Revision 1 replays keep the original obstruction because the change can alter attack odds and Guard reactions.
- EnemyUnit2 had 72 legal movement destinations before its recorded Wait at index 38. The recorded decision rejected 49 as outside its preferred route corridor and 23 as below its move score threshold. It subsequently aimed and attacked. Retain this case for evaluating AI willingness to flank and leave cover, including how quickly it should relax its threshold after repeated passive turns.
- Dark red tiles indicate committed enemy Guard. Purple indicates friendly Guard or the brighter pre-commit preview. Shared coverage blends the two committed tints. Move and Attack previews take priority over committed Guard on the same cell and floor. Tiles communicate potential reaction coverage. Attack legality depends on the selected unit, target, range, resources and target exposure. A disabled Attack button lists the hostile targets' rejection reasons.
- Remaining asset authoring issue. A solid box can reserve flat ground beyond the visible walls, especially when a building asset includes a planter, step or other low detail. The loading-parcel sightline fix clips obstruction to the authored box and retains the movement reservation. Review similar assets by separating the wall or shell from low details and keeping adjacent open ground walkable. Give each authored part its own movement, cover and sightline contract, and verify each in gameplay.

## AI frame pacing

On this depot state, checking hypothetical routes for all 72 reachable destinations took about 180 ms in a headless probe. The isolated route loop includes candidates the live scorer can reject before querying a route. Repeating an in-range shot evaluation 120 times took about 573 ms before narrowing the candidate cells to the ray corridor and about 22 ms afterward. These are CPU probe measurements from one battlefield state.

Movement scoring yields between candidates after a 5 ms work slice. Candidate ordering and RNG consumption follow the same sequence. A single path query can overrun a slice. Animation and the intentional activation/action holds have their own timing. For further profiling, record the longest frame during enemy movement, a shot and a Guard reaction in a normal rendered battle. Separate path scoring, presentation, rendering and the intentional holds before changing turn pacing.

## Cinematic replay

Try both shoulders and a higher angle when a cinematic subject is obscured. Candidate checks include terrain collision and registered static visual bounds. If the selected view is still obstructed, hide the registered visual meshes between the lens and actor and restore them when the sightline clears or the shot ends. This is presentation only. Bounds approximate open meshes, so check overhead decks, open frames and shots with two actors in frame during camera polish. A completed cinematic replay returns to the tactical view for the results screen.

Replay Save As owns keyboard and pointer input while open. The battle pauses to stop camera controls that poll keys every frame, then resumes its previous pause state when the dialog closes.

## Decision feedback — 2026-11-13

Reported playtest: Service Depot, Eliminate, tactical population enabled, seed `330397922`, two soldiers and two enemies. The owner-supplied account describes a complete defeat and opening Replay Battle, not verified full replay playback. Treat its observations as one playtest rather than a balance verdict.

Implemented first pass:

- Hovering a hostile during ordinary inspection or Attack shows the actual action query's rejection reason or hit chance, AP/SP cost, damage on hit, directional cover classification and obstruction description. Inspection remains available when there are no legal targets and Attack is disabled. It spends nothing.
- Shot trajectories are available without enabling diagnostics. Green means a legal clear shot; amber means legal with cover or partial obstruction; red means rejected. A fully blocked shot highlights the authoritative first blocking cell, using its sub-cell authored shot bounds when available. The text identifies that cell. The single line represents the query's chosen aim point; it does not replace its five target samples or prove that every sample hits the highlighted object.
- A legal move hover retains the route and adds AP cost/remaining AP, route cost, cover against each live hostile and incoming destination sightlines. Compass directions use grid north = negative Z and east = positive X. `CombatRules.evaluate_attack_at_cell()` evaluates the hypothetical destination without moving the actor or altering occupancy. Descriptions are cached per actor, destination and action revision. This is destination geometry, not a prediction of enemy choices, remaining enemy resources or Guard reactions along the route. Outgoing targets after movement remain a follow-up.
- The five-entry recent-combat panel describes committed attacks and their damage/misses, defeats, Guard activation and actual Guard reactions. It remains visible when AI turns hide the player action buttons. It reads existing committed results; it does not add replay events, combat rolls or actions. It currently reports committed resolution, which can precede animation completion.
- Aim explains its immediate AP charge, +15 bonus, expiration/cancellation and provisional accuracy rules before activation. SP expands to Supply Points in its tooltip.
- Non-extraction results summarize required mission objectives. Existing extraction and enemy-evacuation reports retain their contracts. Completed battles hide the obsolete End Turn/Enemies Acting control.

Authority remains unchanged: action queries, `CombatRules`, MapData, the action service and mission state determine these descriptions. No movement, cover, LOS, AI, damage, accuracy, generation or replay-schema rule changed.

### Tactical shapes: next bounded authoring work

The playtest's proposed separation is the right target, but is not complete today. `AuthoredSceneMapCompiler` already stamps explicit authored solids; compiler revision 2 can supply rectangular sub-cell shot bounds. Movement and stopping still use cells, directional cover still reads neighboring cell metadata, overlapping solids can retain conservative cell obstruction, and round solids do not gain exact circular shot shapes. A tight render mesh does not imply a tight movement or cover contract.

Prioritize one delivery-truck template and one warehouse wall/planter example:

1. Inspect the existing authored movement/stopping cells, shot bounds and cover contributions together against imported geometry. Split genuinely different authored parts rather than enlarging one box around all details. Preserve explicit tactical authority and replay/compiler compatibility.
2. Add template-level editing/inspection for these distinct authored purposes, then verify all supported rotations and clear approaches in a parcel. Clearly distinguish editing a reusable template from an instance. Do not derive tactical truth automatically from mesh collision.
3. Carry authored source identity into blocker diagnostics so the UI can say “Blocked by delivery truck” rather than only a cell coordinate. Resolve the authoritative shape to its owning source; do not guess from whichever visual raycast happens to hit first.

Further decision polish: outgoing shots from a hypothetical move destination through a shared pure evaluator, directional cover indicators on the ground, route-specific Guard warnings, a collapsible combat history and more distinct squad identities. Keep Guard and SP terminology. These are pending work, not claims about this delivery.

### Verification

`tests/tactical_decision_feedback_hud_test.gd` uses a real battle scene and action service for blocked/clear/out-of-range cases, authored bounds, idle hostile hover, immutable hypothetical movement, actual attack logging, AI-turn log visibility, bounded history, reaction formatting, tooltips and Eliminate results. Synthetic reaction data tests formatting only; it is not evidence of an actual Guard trigger. Existing Guard suites exercise real reactions.

Run from the repository root:

```powershell
godot_console --headless --path . --script res://tests/tactical_decision_feedback_hud_test.gd
.\tools\run_tests.ps1 subsystem -Subsystem ui
.\tools\run_tests.ps1 subsystem -Subsystem combat
.\tools\run_tests.ps1 subsystem -Subsystem missions
.\tools\run_tests.ps1 subsystem -Subsystem replay
godot_console --path . --resolution 1280x720 --script res://tests/tactical_decision_feedback_hud_test.gd -- capture
```

The optional rendered branch initializes the reported populated Service Depot seed separately from its synthetic negative cases. It writes `artifacts/tactical-decision-feedback.png` and `artifacts/tactical-shot-feedback.png`; these are scripted inspections of the normal camera and HUD, not a manually played mission. The initial enemy is out of range, and the second capture deliberately exposes that reason. Headless assertions do not establish visual approval.

Results: focused regression passed; UI 19 passed, combat 25 passed, missions 16 passed, replay 10 passed. Counts include each tier's project scan and overlapping suites, not unique tests. The combat quality-metrics batch and extended refinery mission matrix were skipped by the runner's existing explicit-only policy. An intermediate UI initialization error found while separating the log from the action buttons was corrected; the final combat rerun and UI/mission/replay logs contain no such error. Normal captures were inspected for HUD readability. The rendered process also reported the existing Windows root-certificate-store error; it saved both captures and exited successfully. No manual full mission or new balance evaluation was performed in this pass.

# Intelligent cover and contextual firing

## Design and implementation order

The [Depot investigation](asymmetric-line-of-fire-investigation.md) distinguishes a real one-way shot from nearby truck bounds that overblock the visible taper. Treat those as separate cases.

1. **Readability.** Keep the existing shot evaluator and action routes. Export the first identified obstruction point on the explained sample as diagnostic data. Preserve the rules for source/destination geometry, seams, range, accuracy, Guard and replay. Use an authored public obstacle name when available. Show concise directional engagement and destination danger, with full ray/scoring details in F3. Compare both directions only when asked for a specific target or move. Movement uses the existing canonical-point forecasts and same-revision feedback cache.
2. **Truck fidelity.** Measure the actual taper against blocked and clear ray controls. Compile any accepted revised part once, with a versioned content/replay transition if it changes legality. Bound authoring work and certify ordinary box, curve and compound controls. Do not use live render triangles as the tactical surface.
3. **Contextual firing.** The shared geometric evaluation already feeds Attack, Guard, AI and previews. The current cover selection, animation and IK are downstream and visual, with selection hysteresis and no authoritative muzzle reach. Start with one deterministic posture family and a normal-origin fallback. Validate a physical muzzle/weapon path, support, body and neighbor clearance and a plausible pose before allowing that family to change legality. Choose a stable candidate order, record the accepted solution, and compare the same endpoints through commit, Guard, replay and presentation. If the weapon cannot reach a safe origin, the shot stays blocked.
4. **Presentation and playtest.** Drive and measure the accepted pose through the existing raise/fire/recovery and Guard sequence. The canonical tactical position persists. Temporary exposure has no independent reaction effect until a trigger is explicitly designed and verified. Test player comprehension before adding automatic micro-steps, overlapping exposure rules or more posture families.

## Ownership

`CombatRules` evaluates canonical positions and static parts. `TacticalActionService` owns costs, validation, RNG, receipts and Guard triggers. Target and movement previews read the same geometry with separate current-action restrictions. The movement preview remains hypothetical and cancels outgoing Aim and incoming Shield protection as a real Move would. There is no fog-of-war subsystem in this build. Preview inputs must be limited to already presented opposing actors. `TacticalCharacterAdapter`, `CoverEdgeSelector` and weapon IK pose the committed result. Their current heuristic edge choice does not authorize shots. Replay re-evaluates committed actions and compares results.

No posture, geometry or combat rule changes belong inside the readability implementation. Any later rule change must be verified with the existing one-way pair, nearby fully blocked and clear controls, faction exchange, actual Attack and Guard, mobile actors and deterministic replay.
## Playtest slice

### Readability

Normal targeting stops the drawn ray at the first evaluated contact and marks the point. The cargo truck supplies its authored public name; unknown assets fall back to “Firing lane obstructed.” F3 retains coordinates, part bounds, the contact point and accuracy details. The normal attack card compares the two directed lanes. Range failure remains a distinct category, and a denied action may have a clear lane if it lacks resources. Guard’s recent-combat explanation uses the same obstacle name as targeting when known.

Move hover forecasts both directions from the actual canonical destination. The compact panel counts lanes, warns about one-way exposure, lists the most relevant opponents and shows applicable loss of Aim or Shield. Guard along the route is separate. With multiple opposing units the normal view favors the text/ghost over a fan of lines. Detailed per-target forecasts remain available through F3. Hidden render actors are excluded; the game has no separate fog-of-war ruleset. The [regression](../../tests/tactical_decision_feedback_hud_test.gd) uses the real Depot move from `(16,0,15)` to `(17,0,15)` with EnemyUnit3 at `(22,0,22)`. The warning appears before AP is spent. The subsequent commit lands on the same point and the normal targeting path shows the cargo contact.

### Cargo shot bounds

A world-space triangle probe clipped the truck mesh against a plane just behind the 6.25 cm upper cargo rear inset. The furthest rear protrusion in that strip reached **0.53125 m** in height. The revised metadata uses two overlapping local boxes: an inset full-height core and a **0.54 m** high rear strip. The narrower shot representation is intentional. The original broader hull still protects standing and swept-body clearance. Compiling the correction reuses existing exact part rays, contact reporting and per-part cover tests. No gameplay query processes render triangles. The retained hull is the broad-phase envelope and can remain slightly conservative at untested silhouettes.

Compiler **10** applies the authored shot parts. Archived manifests requesting compiler **9** still use the original box. The previous investigation fixture pins revision 9 to keep its negative taper observation reproducible. Tests compare both compiler revisions at all four quarter-turn placements. They require identical movement parts, an upper rear lane that now clears, and blocked lower and core controls. The old and corrected matches use the same map footprint. They can differ in which attacks are legal. [Reusable truck metadata](../../art/environments/authored/tactical/delivery_shapes.tscn), [compiler](../../systems/generation2/authored_scene_map_compiler.gd).

On the live Depot fixture the original one-way engagement survives. The corrected bounds admit the waist-height shoulder ray at the separate control `(2.5,1,2.10)`. Attack and Guard choose the same ray. Lowering its height to 0.5 m retains the obstruction, and moving the shooter farther to Z=1.5 retains a genuine blocked shot. The regular MIRA remains at exactly `(-2.8513,0,-4.5)` at the original destination. Representative doorway, wall corner, low cover, raised beam, round tank and cabinet tests give broader regression coverage. No comprehensive asset recertification has been performed.

### Contextual firing and presentation

The next prototype should certify one posture, with a typed origin and target sample held by the existing evaluator and consumed by both ordinary and reaction receipts. A candidate cannot be authorized by an animation clip name or a nearby clear ray alone. Measure its authored muzzle and arm reach, continuous world-space weapon clearance, torso and planted-foot support, and recoverability before enabling it. Existing Guard triggers and tactical occupancy remain the source of gameplay timing. Automatic stepping, any availability policy for temporary exposure and additional posture families remain separate implementation work.

The accompanying [muzzle witness](evidence/intelligent-cover/muzzle_witness.gd) observes the existing Attack and Guard presentation from real action sequences. It records the tactical origin, approved target sample, rendered muzzle, shot release time and whether a ray from that muzzle to the approved sample is obstructed. It is developer evidence. It does not use rendered poses to settle shots.

### Reproduction

Run from the project root with Godot console on PATH. Ironclad isolates test data. Run the rendered witness and benchmark in a separate PowerShell session with writable APPDATA and LOCALAPPDATA, and serialize Godot invocations.

```powershell
.\tools\run_tests.ps1 check
.\tools\run_tests.ps1 select -Test tactical_decision_feedback_hud_test,combat_geometry_los_test,combat_decision_preview_test,overwatch_reactions_test,defensive_actions_replay_test,surface_battle_replay_test
godot_console --path . --rendering-method gl_compatibility --resolution 1280x720 --script res://tests/tactical_decision_feedback_hud_test.gd -- capture
godot_console --path . --rendering-method gl_compatibility --resolution 1280x720 --script res://docs/quality/evidence/intelligent-cover/muzzle_witness.gd
godot_console --headless --path . --script res://docs/quality/evidence/intelligent-cover/ai_cargo_benchmark.gd -- profile-ai
```

The [paired AI benchmark](evidence/intelligent-cover/ai_cargo_benchmark.gd) runs compiler 9 and 10 from the same manifests in the current executable, with no competing engines. It isolates the cargo shape change from the overlay changes. The headless 12× speed measurement characterizes planning work, not rendered frame smoothness. A normal-speed full-match playtest remains important for how ready and fair the changes feel.
## Verification results

Audited and developed from integrated `main` at `6d125eebd0c16062a4d2ea49e2b4348e48c23a9a` on local branch `codex/asymmetric-line-of-fire`. Godot `4.7.2.stable.official.ed1daf0bf` on Windows. RTX 5060 OpenGL Compatibility for the 1280×720 captures. No original QA replay was available.

- **Ironclad** passed project import, catalog and **17/17** focused tests in **162.12 s**. Coverage included real HUD, prediction, directional geometry, raised/curved obstacles, three maps, AI, Guard, defensive and surface replays, and the existing visual cover lifecycle. Two earlier failures drove corrections: the debug-volume assertion now explicitly selects its debug view, and the compact arrival panel still communicates loss of active Shield. The final run is `artifacts/intelligent-cover/final-ironclad/20261126-173802795-ee43e084-select`. Full Ironclad was outside this run.
- **Rendered Depot** passed the actual Move, arrival warning, target hover and corrected taper controls. [Arrival warning](evidence/intelligent-cover/depot-arrival.png), [blocked impact](evidence/intelligent-cover/depot-blocked.png), [taper control](evidence/intelligent-cover/depot-taper-clear.png). The taper frame shows a body-clear diagnostic position within the logical cell. It does not depict an extra free movement option.
- **Rendered muzzle and replay compatibility witness** passed **170 checks** with the archived compiler-9 manifest. The real Depot Attack and an open-lane Guard retaliation had clear rays from the observed muzzle to their tactical target samples. Observed muzzle positions differed from the canonical shot origins by 0.738 m and 0.736 m, respectively, principally due to body/weapon placement in front of the origin. The existing right-lean clip was rehearsed on the blocked Alpha–EnemyUnit3 lane without submitting an action. It reached its visually aligned firing phase in about 0.28 s, but the muzzle-to-sample ray still hit the truck. This is concrete evidence that the existing clip is insufficient to authorize that lane. A separate physically certified posture remains an open experiment. The observation comes from one regular MIRA setup and one firing event per case. It is neither a rig-wide calibration nor a proof of trajectory clearance across the whole animation.

### Matched AI benchmark

Four complete headless Depot Eliminate matches, Normal difficulty, 12× simulation speed, sequential runs on the same host. Elapsed match time is reported separately from the profiled intervals. Values below are P95 / maximum in milliseconds, from actual planning decisions. Inventory candidate counts were 205 in both 3v3 runs and 733 in both 5v5 runs. These are attack-inventory counts, not individual ray counts. Coverage-cache regression passed. The comparison is small and cannot resolve a few milliseconds of variance.

| Scenario and compiler | Outcome and decisions | Match time | Planning work | Largest uninterrupted slice | Decision wall time |
| --- | --- | ---: | ---: | ---: | ---: |
| 950507647, 3v3, 9 | Victory, 4 rounds, 50 decisions | 7.83 s | 51.42 / 55.94 | 13.85 / 16.35 | 62.89 / 65.21 |
| 950507647, 3v3, 10 | Victory, 4 rounds, 50 decisions | 7.84 s | 51.55 / 58.26 | 13.80 / 16.20 | 65.55 / 70.25 |
| 16, 5v5, 9 | Victory, 10 rounds, 124 decisions | 19.33 s | 83.19 / 103.80 | 15.37 / 18.63 | 103.98 / 131.91 |
| 16, 5v5, 10 | Victory, 10 rounds, 124 decisions | 19.43 s | 83.05 / 106.41 | 15.60 / 18.69 | 101.88 / 134.72 |

All four completed with zero rejected actions. Evidence is `artifacts/intelligent-cover/ai-benchmark.log` and `muzzle-witness-final.log`. Similar counts and timings are evidence for those workloads. They do not establish identical decisions or rendered frame times. The final screenshots were captured from the real scene at normal speed. Whole-match rendered timing, actual human playtesting, target pose calibration and performance for a future contextual candidate search remain open.

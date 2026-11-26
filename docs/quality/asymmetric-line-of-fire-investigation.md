# Service Depot asymmetric line of fire

**Finding.** At the reported positions, the two actors shoot different segments. EnemyUnit3 can hit Alpha’s one exposed lateral sample. Alpha shoots from a single center origin, and every ray from that origin hits the cargo body. Faction exchange preserved the results. Player Attack, AI Attack and Guard agreed on legality when asked the same directed question. A nearby control also exposed a separate mismatch between the visible truck’s taper and its conservative box. No production rules changed.

## Baseline and evidence

Investigated integrated `origin/main` at `6d125eebd0c16062a4d2ea49e2b4348e48c23a9a` on local branch `codex/asymmetric-line-of-fire`. Godot `4.7.2.stable.official.ed1daf0bf` on Windows. The rendered test used the actual battle scene and Service Depot authored content at 1280×720, OpenGL Compatibility, RTX 5060. Player and AI actions in the controlled sequence ran through their actual action service. The screenshot feedback uses the real preview formatter and trajectory renderer with scripted selection, without requiring manual mouse input.

The QA screenshots show an Eliminate match, seed `950507647`, revision 44. They show three rejected outgoing previews, one confirmed 25-damage hit by EnemyUnit3, and Guard attempting to return fire at EnemyUnit3 at `(22,0,22)`. The other two successful attacks are the player’s observation. The original match was played at work and its replay is unavailable. The local export and artifact search found no match. A seed reproduces the authored scene and terrain decisions. It does not specify the intervening actions, positions, rolls or visual pose. The probe uses the same map and Alpha/EnemyUnit3 cells, sets other units in controlled positions and runs a new sequence. Its revision and transaction IDs do not stand in for revision 44.

[Runnable regression fixture](evidence/asymmetric-line-of-fire/reproduce.gd) · [Captured outgoing preview](evidence/asymmetric-line-of-fire/alpha-blocked.png) · [Captured inbound preview](evidence/asymmetric-line-of-fire/hostile-exposed-sample.png)

## What the geometry says

- Cell `(17,0,15)` has support center `(-2.5,0,-4.5)` and canonical standing point `(-2.8513,0,-4.5)`. It is a supported stop with static body and live occupancy clearance. The 0.28 m body plus 0.04 m padding is 0.320 m; Alpha’s center stands about 0.32005 m outward from the cargo box’s rear plane. Movement validated the intended thing.
- The live obstacle is `DepotServiceSpine/Tactical/LoadingYardAlt/Truck/TacticalShapes/CargoBody`. Its world bounds span X `[-2.53125,-0.03125]`, Y `[0,2]`, and Z approximately `[-5.3125,-3.6875]` m. The walking cell reports zero cover height. The actual obstruction is a separate shot-only entry from the cargo solid, indexed under the same X/Z column. Both statements can be true. [Truck part definitions](../../art/environments/authored/tactical/delivery_shapes.tscn), [compiler](../../systems/generation2/authored_scene_map_compiler.gd), [indexes](../../systems/grid/map_data.gd).
- The solver starts at the canonical standing point plus the tactical unit’s `standing_height` of 1 m, so Alpha’s shot starts at `(-2.8513,1,-4.5)` and EnemyUnit3’s starts at `(2.5,1,2.5)`. Neither endpoint is the animated weapon muzzle. The target has five deterministic samples at heights 1.2, 1.75, 0.9, 0.9 and 0.5 m above its standing point. The two 0.9 m samples are offset laterally by 0.28 m, perpendicular to the shot bearing. They are body proxies and move with the bearing, independent of the posed skeleton. Rotating Alpha visually 180° did not change the chosen sample or legality. Both units use flat ground. Guard reserves a reaction and changes its accuracy modifier, without creating an alternate shot origin. [Shot origin and samples](../../systems/combat_rules.gd#L228), [Guard query](../../systems/actions/runtime/tactical_action_service.gd#L1229).
- EnemyUnit3’s only clear sample is Alpha’s outward side, `(-3.073745,0.9,-4.329947)`. At the cargo side plane `z≈-3.6875` that ray passes about **18 mm outside** the rear box boundary. The four other inbound rays hit the cargo. All five outbound rays enter the cargo in Alpha’s own cell. The outbound sample used for the explanation enters the box at about `(-2.53125,1.01196,-4.08135)` and hits visible truck geometry farther along the same path at about `(-2.39081,1.01721,-3.89764)`. The segment goes through the truck, even if it is drawn over the truck in the UI.
- The fixture tests all 30 incident/reconstruction rays against the authoritative query, an independent cargo AABB segment test and the visible truck’s world-space triangles. The blocked/clear outcomes matched for all 30. Reversing each *identical pair of endpoints* preserved whether it intersected the box, both in production and in the independent check. Reversing the attacker and target creates different endpoints. For example, an outward origin at the clear shoulder point could send a geometry-clear ray to EnemyUnit3’s current firing position, but Alpha’s existing firing origin cannot. This is a geometry-only counterexample. It does not establish feasible muzzle placement or a legal lean.
- Endpoint handling skips ordinary source and destination cell records. Independently indexed shot obstacles remain eligible, including the truck in the source column. The open AABB tests treat mere tangency differently from entry; the existing paired diagonal seam logic checks closed corners. The incident does not need a seam or endpoint exception to reproduce. Raw segment-box and triangle tests establish that the outgoing rays cross the cargo. [Ray filtering, part intersection and tolerances](../../systems/combat_rules.gd#L336).

## Directional results and actions

All rows are direct forecasts without Aim. `N/5` is the number of open target samples. A queried Guard opportunity is compared with resources and a reservation in place. The foreground normal player preview and all service queries refer to the same tactical positions.

| Unit or case | Cell | Alpha → enemy | Enemy → Alpha | Guard legality out / in |
|---|---|---|---|---|
| EnemyUnit1 reconstruction | (21,0,21) | 0/5, blocked | 1/5, 41% | Blocked / legal |
| EnemyUnit2 reconstruction | (20,0,10) | 0/5, blocked | 1/5, 50% | Blocked / legal |
| EnemyUnit3, QA cell | (22,0,22) | 0/5, blocked | 1/5, 15% | Blocked / legal |
| Neighbor across the blocked side | (22,0,21) | 0/5 | 0/5 | Both geometry-blocked |
| Open control | (16,0,21) | 5/5 | 5/5 | Both geometry-clear |

The faction control exchanged both rosters and faction tags while preserving objects, canonical points, target geometry and roles in the directed queries. All six Attack and Guard results and hit chances stayed equal. Neither query consumed combat RNG or advanced revision. The AI scorer selected Alpha under the normal attack inventory. The fixture then executed actual Guard, enemy Aim and enemy Attack. It explicitly selected a reproducible hit RNG seed to demonstrate the observed outcome. EnemyUnit3 previewed 15% base and 50% after Aim; the committed receipt reported roll 20.227, hit for 25, Alpha 50 → 25 HP and no reaction event. The reason was `Blocked`; reservation remained armed. That receipt is a new test event. It does not recover the actual match roll. In the QA log, the unused Guard expired at Alpha’s next activation.

A forced submit of Alpha’s blocked Attack was rejected as `blocked_los` without AP, SP, RNG or revision changes. At the open control, the normal player path committed at the previewed 100%. There was no paired authority discrepancy. The AI can exploit the exposed sample by choosing and aiming at a legal target. The single captured transaction and fixture do not establish how often the AI deliberately seeks this setup. [Player preview and attack](../../systems/battle_controller.gd#L500), [AI target inventory and scoring](../../units/ai_controller.gd#L1579), [submit and commit](../../systems/actions/runtime/tactical_action_service.gd#L123).

## Nearby boundary and separate asset limitation

- Moving Alpha hypothetically 2.5, 5, 10 or 14 cm farther from the truck along -X within the same tile kept her body clear, with 0/5 out and 1/5 in against EnemyUnit3. Moving her 1 cm toward the truck fails body clearance even though inbound visibility still exists. The reachable neighboring stop `(16,0,15)` at `(-3.5,0,-4.5)` opens five outgoing samples and exposes four incoming. These are controlled comparisons. The fixture does not allow arbitrary in-cell gameplay movement.
- Keeping the enemy X at 2.5 and varying Z through the boundary between the blocked and clear views yielded tactical cutoff `2.26804–2.26816` m. Exact box intersection switches near `2.26782–2.26807` m. The observed tactical result tracks the box; the expected small inset is not the cause of the incident.
- **Separate confirmed visual mismatch.** The same outer ray clears visible truck triangles above Z≈1.5725–1.5728 m in this sweep. At the body-clear test origin `(2.5,1,2.10)` within EnemyUnit3’s logical cell, the truck silhouette clears the lateral sample while the cargo box blocks it and the authority rejects the attack. The rear taper creates extra visual space at that angle. This is a conservative asset approximation, worth tracking independently if players encounter it from canonical stops. It cannot explain the original one-way case at Z=2.5, where both geometry references agree. The boundary sweep measures one specific ray family against the truck, not a license to replace collision with arbitrary visual meshes.

## Findings and proposed solution

| Question | Finding |
|---|---|
| Legitimate directional geometry | Yes under current sample policy. Part of a target can be exposed while its center firing lane is covered. |
| Invalid geometry calculation at the reported pair | None demonstrated. Placement, AABB, visible mesh and intersection agree for tested original/reconstructed rays. The nearby taper has a separately demonstrated conservative-bounds discrepancy. |
| AI or player rule discrepancy | None found. Source exchange preserved geometry, and actual player and AI submits followed the same combat evaluation. |
| Guard discrepancy | None found in legality. Guard tests the watcher’s actual outgoing lane. Its summary says “Blocked” without identifying the relevant near-shooter obstacle. |
| Player feedback | “Blocked at cell (17, 0, 15)” is correct as an index, yet implies Alpha’s floor or occupation is the blocker. It does not explain that the cargo blocks her center lane while a narrow body sample remains exposed. The red blocker volume helps, but the line continues visually to the far target. |

**Recommended first change, feedback with existing geometry.** Expose structured hit information from the same authoritative query: the intersected part or shape, actual contact point and whether the first hit is near the shooter, plus the existing exposure count and selected sample. Use concise output such as “Truck blocks your firing lane” and “1 of 5 body samples exposed” where that context is already computed. Draw the rejected line to the near impact; identify the legal sample on a cover preview or Guard explanation. Keep the current query as the single source for preview, AI, receipt and Guard. Do not compute a separate preview legality or reroll during inspection. This can leave replay legality and decisions unchanged.

**If the owner wants the player to be able to lean out and return fire**, prototype an explicit or clearly previewed cover-edge firing stance, shared across factions and actions. An available origin would be a deterministic, stance-relative firing anchor on a supported side. Keep the canonical feet and cell. Require plausible reach and presentation, local clearance from pose/muzzle through the firing anchor and a clear ray from that anchor to an approved body sample. Use the same resolver for preview, AI planning, Attack and any explicitly supported Guard stance. Never promote a target’s clear sample into an automatic shooting port without those checks. Sample the covered, partially exposed and fully open cases from both sides. Keep positional/stance asymmetry where physically justified. If hit envelopes prove too generous for a particular pose, validate them against that rig and stance before changing the samples; automatic reciprocity and changing accuracy cannot establish correctness.

**If the owner wants closer asset fidelity**, separately evaluate a conservative compound or beveled cargo bound fitted to this truck’s visible geometry. Use the same committed solid in movement, LOS, cover and Guard and compare the true blocked, taper-open, and tangent cases for every supported rotation. Test recompiled canonical points and maps using this asset. Use explicit geometry/compiler or simulation compatibility if the change alters old recordings. Never silently replay prior committed hit results against changed geometry. [Historical shot geometry and compatibility](combat-geometry-los-2026-11-16.md), [replay validator](../../systems/replay/battle_replay_recording.gd).

Acceptance for any later gameplay change should include orientation independence where intended, intentional one-way exposure, endpoint obstacles, side-of-cargo grazing, preview and commitment using the exact selected origin, the real Guard trigger, faction exchange, flat/elevated/curved controls, deterministic replay and visible muzzle/impact alignment. Explicitly record any meaningful decision or compatibility change.

## Reproduction and regression results

From the repository root with Godot console on PATH:

```powershell
$base = Join-Path (Get-Location) 'artifacts/asymmetric-los'
New-Item -ItemType Directory -Force "$base/app","$base/local","$base/captures" | Out-Null
$env:APPDATA = "$base/app"
$env:LOCALAPPDATA = "$base/local"
$probe = 'res://docs/quality/evidence/asymmetric-line-of-fire/reproduce.gd'
godot_console --headless --path . --script $probe
godot_console --path . --rendering-method gl_compatibility --resolution 1280x720 --script $probe -- "$base/captures"
```

The fixture is an incident characterization, including intentional assertions of today’s outcomes. Update it only with justified corrections. The emitted lines include `[Scene]`, `[Query]`, `[Ray]`, `[Offset]`, `[AlphaNeighbor]`, `[Boundary]`, `[BoundaryReference]`, `[ProxyControl]`, `[Transaction]` and `[PlayerControl]`. The fixture controls placement and RNG, so its internal attack receipt alone is not a playable replay from the untouched deployment state.

The final fixture passed **167 headless checks** in 4.75 s and **169 rendered checks** in 6.34 s, both exit 0. All 60 comparable tagged evidence rows matched exactly, including the controlled Attack receipt. The two additional rendered checks verified captured frames. Catalog validation passed (305 discovered and 305 catalogued).

Ironclad select passed **11/11**, zero failures or timeouts, in 107.84 s. Logs and `results.json` are under `artifacts/asymmetric-los/ironclad/20261126-155343618-f16076c1-select`. Coverage was `combat_geometry_los_test`, `combat_controlled_examples_test`, `combat_prediction_consistency_test`, `combat_real_map_closure_test`, `combat_guard_coverage_cache_test`, `diagonal_combat_test`, `surface_curved_battle_test`, `ai_decision_scenarios_test`, `overwatch_reactions_test`, `defensive_actions_replay_test`, and `surface_battle_replay_test`. The full suite was outside the focused run. Direct fixture logs and captures are under `artifacts/asymmetric-los`. The sandbox’s certificate-store warning did not affect the local geometry work.

# Directional Cover and AI Position Evaluation Investigation

## A. Executive findings

This investigation began on `p2-foundation` at `770a879` (`save the match setup layout`) with a clean working tree. The assignment named `e789fb8` as the last reported commit; `770a879` is the later, user-authorized Match Setup layout commit and contains no cover or AI behavior change.

The observed playtest is **not evidence that FuseFire combat treats nearby cover as omnidirectional**. Combat already derives environmental cover from the defender-adjacent obstacle toward each individual attacker. Existing tests prove that low cover on the protected side changes a shot to 50%, while the same cover on the wrong side leaves the shot at 100%. Unit visual facing is not involved.

The AI scorer is also direction-aware and iterates every living hostile supplied to it. It does not simply reward the strongest neighboring obstacle or only the closest enemy. However, it approximates danger with fixed cover/exposure values and a simpler center-line visibility query. It does not evaluate the authoritative attack prediction that each credible enemy would have against the hypothetical candidate. It also weights present hostiles almost uniformly: it has no model of expected damage, attack readiness, or a marksman's greater danger. Consequently, a tactically odd tile can win because progress, firing opportunity, range, crowding, objective urgency, and coarse exposure values outweigh the useful half cover. The exact reported selection cannot be reproduced without its seed and decision trace, but the suspected “full cover behind counts as protection” cause is contradicted by the code and regression tests.

The recommended solution is incremental:

1. Keep automatic, attack-relative environmental cover. Do not add cover-facing input.
2. Add a pure hypothetical attack prediction that accepts an attacker and a proposed defender cell, reusing combat geometry and accuracy rules without moving a unit or consuming RNG.
3. Let `AIPositionScorer` aggregate bounded exposure from a small set of credible, known threats using those predictions, while retaining mission progress, firing opportunity, and anti-stalemate weights.
4. Keep shields separate: shield orientation is explicit capability state layered onto an incoming attack; environmental cover remains geometry-derived.
5. Fix hypothetical path occupancy through a focused read-only path query that ignores the planning actor's current tile. Do not combine it with cover scoring into a mutable hypothetical world.

This preserves the player-facing principle: **positioning matters, but positioning is not tedious**. The player chooses the tile; the simulation determines which incoming attacks that tile protects against.

## B. Current FuseFire implementation

### Environmental geometry

`systems/grid/map_cell_data.gd` stores `cover_type`, `cover_height`, and `blocks_line_of_sight` per cell. Cover is therefore obstacle-cell data, not a manually selected unit stance or an explicit edge object.

Authored terrain is converted to the same representation by `systems/grid/map_builder.gd::_apply_feature()`. Generated terrain assigns the same fields in `systems/generation/flat_map_generator.gd`. Authored and generated maps therefore enter combat evaluation through the same `MapCellData` contract.

Low cover remains low geometry. Full cover normally blocks traversal and line of sight. Geometry can also act as an intervening partial obstruction without granting defender-adjacent cover.

### Attack-specific protection

`systems/combat_rules.gd::evaluate_attack()` owns the current authoritative attack prediction. Its relevant flow is:

1. Validate actor, faction, range, and target state.
2. Call `_evaluate_target_visibility()`, which samples five target body points.
3. Use `_get_geometry_between()` to classify obstruction by actual obstacle height and segment intersection.
4. Call `get_directional_cover(attacker_cell, target_cell, grid)`.
5. Apply the larger of directional-cover penalty and partial-obstruction penalty.
6. Clamp the final hit chance to the current 5–100% range.

`get_directional_cover()` inspects only cells cardinally adjacent to the defender and lying toward the attacker. On an exact diagonal it inspects both relevant sides and uses the stronger one. Cover behind the defender is not selected. Visual facing is never read.

Current low and full directional cover both supply a 50-point accuracy penalty when a shot remains legal. Full-height geometry commonly blocks all sampled points instead. Elevation is handled geometrically by world-space segment tests and body samples rather than a separate cover-facing rule.

`_get_geometry_between()` provides the important distinction requested by this investigation:

- Defender-adjacent geometry may be directional cover.
- Intervening low geometry may partially obstruct some body samples without becoming cover.
- Full geometry may block all visibility.
- Diagonal corner handling prevents shots through a sealed two-obstacle seam while permitting a single grazed corner.

Player, AI attack submission, replay, and headless attack resolution ultimately use this combat path. Replay records authoritative outcomes rather than recomputing presentation geometry.

### AI position value

`systems/ai/ai_position_scorer.gd::evaluate()` receives the candidate cell and an array of hostiles. For every living hostile it:

- computes distance to the candidate;
- calls `CombatRules.get_directional_cover(hostile_cell, candidate, grid)`;
- adds +4 for low or +7 for full directional cover when the candidate is in hostile range;
- calls `CombatRules.has_line_of_sight_to_position()` and applies fixed incoming exposure of -14 with no cover, -9 with low cover, or -5 with full cover;
- counts multiple incoming lanes and applies another -9 for each lane after the first;
- estimates whether the candidate provides a firing lane back;
- penalizes positions within two cells of a hostile.

It then combines these facts with route progress, objective urgency, carrying state, squad reservations, and difficulty-policy weights. This is legitimate multi-objective scoring, so the safest tile should not always win.

The weaknesses are narrower than the playtest hypothesis:

- `has_line_of_sight_to_position()` checks one center-height segment. Authoritative attacks sample five body points and calculate obstruction severity.
- Cover reward is added whenever an enemy is in range, even when that enemy cannot see the candidate. The separate exposure term partially offsets this, but the two terms do not express one coherent prediction.
- Exposure values are categorical constants, not the actual hit probability and expected damage.
- Every supplied hostile is treated as a broadly similar threat. Range affects eligibility, but current normal attacks use the same damage constant, and the scorer does not model SP, AP, aim state, attack readiness, or archetype-specific future damage.
- `units/ai_controller.gd::_advance_exposure()` repeats a second, similar approximation with values 1.0, 0.65, and 0.35. It can drift from `AIPositionScorer` and from combat rules.
- The game currently has no complete perception/knowledge layer. `_get_hostile_units()` supplies existing opposing units, so the present AI is effectively omniscient. A future threat query must consume known/credible threats rather than all scene enemies.

The reported position can therefore be selected, but not because the scorer reads cover behind the unit as directional protection. Its total may be higher for route, firing, range, objective, or crowding reasons, or its simplified LOS may disagree with the authoritative shot geometry. The existing structured score summary is the right evidence to capture from the precise playtest seed.

### Hypothetical occupancy

`systems/grid/pathfinder.gd::calculate_3d_path()` uses the live AStar disabled-point state and exposes no ignored-actor or occupancy-override parameter. `GridManager` maintains live occupancy and reserves a committed destination before animation.

In `units/ai_controller.gd::_move_along_goal_path()`, the AI asks for a continuation path from a hypothetical candidate while the planning unit still occupies its real origin. In a narrow route, the continuation may need to cross that origin, so the actor can block its own imagined route. The maximum-urgency recovery rule permits a controlled detour when this approximation produces no continuation. Seeds `25005` and `25100` permanently cover the known extraction and refinery stalemates.

This issue affects candidate reachability and route value, not directional cover calculation. Both problems need read-only hypothetical queries, but they should remain separate APIs. Cover prediction needs a proposed defender location; route prediction needs a temporary occupancy view that ignores the planning actor at its original cell.

## C. Reproduction evidence

Existing deterministic regressions establish the central behavior:

- `tests/combat_cover_smoke.gd` places low cover on the attacker-facing side and expects a legal 50% shot. It then evaluates the wrong side and expects 100%. It separately proves that an intervening low obstacle can reduce accuracy without being reported as directional cover.
- `tests/diagonal_combat_test.gd` covers blocked two-corner seams and a single grazed corner.
- `tests/elevation_combat_smoke.gd` covers elevated visibility and low cover that does not protect an elevated target.
- `tests/ai_position_scoring_smoke.gd` proves that adding cover on the side toward a hostile raises the candidate's cover score. It does not currently assert that wrong-side cover adds nothing or compare multiple threats.
- `tests/ai_stalemate_recovery_smoke.gd` preserves seeds `25005` and `25100` for the hypothetical-occupancy failure and recovery behavior.

The original bad-cover selection was not exactly reconstructable because the seed, unit IDs, candidate cells, and score trace were not retained. The code and current fixtures do not reproduce the proposed root cause. A future reproduction should record both candidate summaries and per-threat predictions; a screenshot alone cannot show why the aggregate score won.

The following deterministic fixtures are missing and should be added during implementation:

1. Full cover behind versus low cover toward one attacker; the latter must have lower predicted exposure.
2. Full cover against one weak threat versus low cover against two threats.
3. Low cover against multiple credible attackers, with stable aggregation and tie-breaking.
4. A flank from an unprotected direction.
5. Exact diagonal cover at a corner.
6. Elevated attack where geometry changes visible samples.
7. A hypothetical continuation path that crosses the planning actor's original tile.
8. Continued full-match coverage of seeds `25005` and `25100`.

## D. XCOM 2 SDK findings

The inspected SDK root is:

`C:\Program Files (x86)\Steam\steamapps\common\XCOM 2 War of the Chosen SDK`

### Confirmed SDK behavior

`Development/SrcOrig/XComGame/Classes/XComWorldData.uc` declares native attack-relative cover APIs:

- `GetCoverTypeForTarget(ShooterLocation, TargetLocation, TargetCoverAngle, TargetCoverDir)` at line 889.
- `GetCoverDirection()` and cover-point queries immediately afterward.
- `GetActorsOnTile(..., optional bool bIgnoreUnits=false)` at line 925.
- `IsTileBlockedByUnitFlag(..., optional XComGameState_Unit IgnoreUnit)` at line 935.

The signatures confirm that XCOM exposes cover relative to shooter and target, and that its native world queries can ignore units or a specific unit. The native implementation is unavailable, so its exact ray, corner, and cover-edge algorithm cannot be claimed from these declarations.

`Development/SrcOrig/XComGame/Classes/XGAIBehavior.uc::FillTileScoreData()` provides the clearest AI comparison:

- It obtains remote visibility information for a proposed tile.
- Lines 2211–2243 discard units the AI does not know about and units without relevant visibility/range.
- Line 2226 calls `GetCoverTypeForTarget(enemy_position, candidate_position, ...)` separately for an enemy/candidate pair.
- Lines 2274–2333 iterate the resulting enemy information and count no, mid, and high cover separately across relevant enemies.
- Lines 2373–2379 compute an average cover value across those enemies.

`ScoreDestinationTile()` compares candidate data to the current tile, and `GetWeightedTileScore()` combines cover, distance, flanking, visibility, ally visibility, and height using a selected move-weight profile. `XComGame/Config/DefaultAI.ini` exposes multiple `m_arrMoveWeightProfile` entries, so XCOM changes tactical emphasis by behavior rather than treating cover as the only objective.

`XGAIBehavior.uc::IsInCover()` lines 9787–9825 checks visible enemies one by one and regards the unit as out of cover when any relevant visible enemy has `CT_None`. `GetClosestCoverLocation()` and related cover-location searches likewise operate on enemy-relative visibility/cover data.

These sources support four principles:

1. Cover is attacker-relative.
2. Candidate evaluation includes multiple relevant enemies.
3. AI knowledge filters the threat set.
4. Position score remains a weighted blend of defense, offense, distance, visibility, and role-specific priorities.

### Limits and inference

The accessible source does **not** establish that XCOM computes `hit probability × expected damage` for every movement candidate. Its visible `FillTileScoreData()` code averages categorical cover and combines it with other weighted values. Several core cover, flank, visibility, and path operations are native. Any claim about their exact internal geometry or performance would be inference.

The XCOM APIs for ignored unit occupancy are a useful architectural precedent, but they do not prove how every AI move search applies them. FuseFire should borrow the explicit-query principle, not reproduce XCOM's state-history or class hierarchy.

## E. Design alternatives

### Option A — Direction-aware categorical scoring

For a bounded set of credible enemies, use the existing directional cover type and authoritative visibility classification, then sum configurable categorical values.

Benefits:

- Small change and inexpensive.
- Preserves the current scorer's readable component model.
- Fixes the center-line versus body-sample mismatch if it uses a shared prediction.

Risks:

- Treats a weak infantry shot and a dangerous marksman shot similarly.
- Coarse values become difficult to tune as Aim, shields, ranges, damage, and Overwatch arrive.
- Can still disagree with player shot previews if it does not consume their complete prediction.

### Option B — Expected incoming exposure

For each credible enemy, query a hypothetical attack prediction and accumulate:

`hit probability × expected damage × threat/action-readiness weight`

Normalize it into a bounded position-score term, then combine it with progress, objective, firing, danger, and squad terms.

Benefits:

- Directly answers the player-facing tactical question.
- Naturally compares full protection from one threat with partial protection from several.
- Extends cleanly to Aim, shield arcs, weapon damage, and Overwatch threat without giving presentation authority.

Risks:

- More expensive across many cells and enemies.
- “Can attack now” is not the same as “credible next-turn threat”; AP and movement assumptions need explicit limits.
- Raw expected damage can make the AI excessively timid and recreate stalemates.
- Current uniform normal-attack damage limits the immediate distinction between archetypes.

### Option C — Recommended staged hybrid

Use authoritative hypothetical attack predictions for geometry, legality, and hit chance, but aggregate only a bounded number of credible threats and clamp the defensive contribution. Initially use current expected normal-attack damage and simple readiness categories. Retain mission progress and urgency as independent terms.

This yields the correctness of Option B without placing a full combat planner inside every destination evaluation. It also preserves a readable score trace:

- per-threat attacker ID;
- legal/blocked/out-of-range;
- cover and obstruction;
- hit chance;
- expected damage contribution;
- total bounded exposure;
- progress, firing, objective, and squad terms.

## F. Recommended solution

### 1. One pure prediction, multiple consumers

Extend the shared combat query with a pure location-based form, conceptually:

`predict_attack_against_cell(attacker, defender, proposed_defender_cell)`

The exact API should reuse `CombatRules`/the existing Attack query ownership. It must not move nodes, edit occupancy, spend AP/SP, consume RNG, or advance revisions. It should return structured legality, visible-sample/obstruction facts, directional cover, hit probability, and expected damage supported by current mechanics.

Player previews, active attack validation, and AI hypothetical exposure should share the same pure calculations. Active-turn/AP/resource checks remain separate from hypothetical geometry so the AI can ask the correct question about a future cell.

### 2. Define credible threats explicitly

Until perception exists, retain current hostiles for behavioral compatibility but name the limitation. When knowledge state arrives, the caller should pass only known threats. Bound evaluation by filtering defeated/extracted actors, impossible ranges, and completely blocked threats, then consider the most relevant few with deterministic actor-ID ordering.

Threat weight should begin simple and inspectable:

- expected damage from the unit's current normal attack;
- whether an attack is presently/soon plausible;
- an explicit reduced weight for a threat requiring substantial repositioning;
- future Overwatch registration as a distinct, known threat.

Do not use distance alone as danger. Do not expose hidden enemies.

### 3. Bound defense so objectives still move

Convert total expected exposure into a capped score penalty. Keep objective progress, route urgency, firing opportunity, and squad reservations visible and separately tunable. The AI must sometimes accept an imperfect lane to rescue, extract, pursue, or break a stalemate.

Retain the existing maximum-urgency recovery until the hypothetical occupancy fix and its full-match fixtures prove it redundant. Even then, a bounded fallback remains sensible defense in depth.

### 4. Keep facing out of ordinary cover

Environmental cover remains entirely geometric and attack-relative. Visual facing may follow locomotion, aim, or presentation and must not change ordinary cover.

Shield stance later adds an explicit protected arc to the defender's authoritative tactical state. Incoming combat evaluation may combine environmental geometry and shield protection, but the two must remain separate named fields in predictions, results, HUD, replay, and AI scoring.

A future projected force-shield item fits the same layered contract without becoming environmental cover or impersonating a physical shield. It can contribute a weaker, explicitly sourced protection arc or modifier with its own duration. Its lower stopping power, item ownership, and depletion rules are deferred; the relevant requirement now is that predictions retain named protection contributions instead of collapsing walls, physical shields, and projected barriers into one unexplained cover value.

## G. Hypothetical occupancy

Address hypothetical occupancy as a separate prerequisite, preferably before Overwatch and alongside the AI scoring implementation if scheduling allows.

Add a read-only path/reachability query capable of treating the planning actor's current occupied cell as vacated without changing `GridManager.occupancy_map` or the live AStar state. A narrow interface such as an ignored actor/cell or an occupancy predicate is sufficient; a general hypothetical-world framework is not justified.

Cover prediction ordinarily needs no occupancy override because it evaluates static geometry and a proposed defender location. Keeping these concerns separate prevents an AI query from mutating authoritative movement state.

Overwatch must use a different execution contract: committed movement checkpoints, deterministic reaction ordering, interruption, defeat, and final occupancy are authoritative simulation facts. It may reuse the same pure geometry calculations, but never the AI's mutable planning approximation.

## H. Shield and Overwatch implications

Before Shield Stance:

- Preserve attacker-relative environmental cover as its own prediction field.
- Define incoming direction consistently from attacker cell to defender cell.
- Ensure combat prediction can add a directional capability modifier without reading visual rotation.
- Ensure AI traces identify environmental cover and shield protection separately.

Before Overwatch:

- Add the read-only hypothetical occupancy query.
- Define authoritative intermediate movement checkpoints and final-cell rules.
- Make location-based attack prediction independent of scene-node animation position.
- Keep reaction threat scoring bounded so Overwatch does not freeze all movement.
- Retain deterministic hostile ordering, preferably stable tactical actor ID.

Neither mechanic requires manual facing for environmental cover.

## I. Proposed implementation slices

### Slice 1 — Lock down current geometry

Add focused regressions for wrong-side full/low cover, multi-threat directions, diagonal corner, and elevation. Acceptance: combat predictions remain automatic, per-attacker, and facing-independent.

### Slice 2 — Shared hypothetical attack prediction

Extract or extend the pure location-based calculation and make current attacks plus AI diagnostics consume it. Acceptance: a real target and the same target hypothetically placed on its current cell produce identical cover, obstruction, and hit chance; repeated queries change no state or RNG.

### Slice 3 — Multi-threat exposure scoring

Replace categorical AI LOS/cover duplication with bounded aggregation over structured predictions. Keep other scorer terms. Acceptance: low cover toward two credible equal threats can beat irrelevant rear cover; a dangerous distant threat is not ignored merely because another threat is closer; deterministic tie-breaking remains stable.

### Slice 4 — Hypothetical occupancy query

Allow continuation/reachability to ignore the planning actor's current occupancy without mutating live state. Acceptance: a narrow-corridor candidate can route through its vacated origin, while other actors still block paths; seeds `25005` and `25100` complete deterministically.

### Slice 5 — Shield/Overwatch readiness checks

Confirm that shield protection composes as a distinct directional modifier and that movement checkpoint predictions reuse the pure combat geometry. This is an integration gate, not implementation of those mechanics.

Each slice should retain component-level AI diagnostics and run combat cover, diagonal/elevation, AI position, stalemate recovery, deterministic simulation, and replay regressions appropriate to the change.

## J. Open questions

Only two product decisions remain before implementation:

1. How many credible enemies should contribute fully before additional threats are summarized or capped? A small deterministic cap (for example, the four highest exposures) is recommended for predictable cost, but should be measured on large maps.
2. Should future AI threat weight represent only a unit's currently executable normal attack, or a bounded next-activation threat? The latter produces better marksman awareness but requires a deliberately simple readiness estimate to avoid a hidden full-turn simulator.

No decision is needed about ordinary cover facing: current behavior and the recommended architecture both keep it automatic.

## Validation performed

The investigation changed documentation only. The following existing checks passed:

- `godot_console --headless --path . --script res://tests/combat_cover_smoke.gd` — 0 failures.
- `godot_console --headless --path . --script res://tests/diagonal_combat_test.gd` — 0 failures.
- `godot_console --headless --path . --script res://tests/elevation_combat_smoke.gd` — 0 failures.
- `godot_console --headless --path . --script res://tests/ai_position_scoring_smoke.gd` — 0 failures.
- `godot_console --headless --path . --script res://tests/ai_stalemate_recovery_smoke.gd` — both permanent fixtures passed: extraction seed `25005` completed in 12 rounds and refinery elimination seed `25100` completed in 28 rounds.

Every Godot invocation also emitted environment-level errors opening `user://logs/godot.log` and reading the Windows root certificate store. They did not cause a test failure and are reported rather than suppressed. No gameplay files or fixtures were changed to hide them.

## Conclusion

Combat cover is correct for the intended design. AI cover scoring is direction-aware and considers multiple current hostiles, but its exposure model is coarse and only loosely aligned with authoritative attack prediction. The original bad-cover choice is plausible as an aggregate-scoring or simplified-visibility result, but the claimed rear-cover bug is not reproduced.

The best next step is a shared, read-only hypothetical attack prediction followed by bounded multi-threat exposure scoring. Hypothetical occupancy should be fixed through a separate ignored-actor path query before movement reactions. This gives FuseFire XCOM's useful principles—attacker-relative cover, multiple known threats, and weighted tactical priorities—without importing its engine architecture or making positioning tedious.


# Package 03A — Contextual Firing Bay

[Previous readability and cargo work](intelligent-cover-and-contextual-firing.md) · [Depot investigation](asymmetric-line-of-fire-investigation.md)

## What is implemented

Package 03A introduces a same-cell side step as a production action in the **Contextual Firing Bay**, an opt-in reference battlefield. The side step is authored as a certified footing offset at a supported tile. It is not generated automatically on production maps. The bay has two mirrored layouts and can exchange factions. It runs the normal tactical HUD, turn manager, opportunities, receipts and replay. Alpha’s original Depot position has no certified footing and stays blocked in the previously verified directions.

### Play it

From the project root with Godot on PATH:

```powershell
godot_console --path . --script res://docs/quality/evidence/contextual-03a/play_bay.gd
godot_console --path . --script res://docs/quality/evidence/contextual-03a/play_bay.gd -- enemy
```

- In the first launch, hover the hostile from the starting tile. The HUD shows **Side-step shot**. Use Attack and click that hostile. MIRA steps toward the open end, fires, and returns to her starting tile.
- For a reaction, restart and select Guard from the starting tile. Let the enemy act. Guard can use the step when the existing hostile move or attack trigger offers the valid lane. Aim and Guard retain their normal AP and SP behavior.
- The second launch puts the hostile in the same bay. End the player phase. The standard AI can choose and present a side-step Attack. Check both firing directions in the hover text before handing off.
- Move to the neighboring tile on the solid side of the wall to try a blocked firing lane; move to the open side for ordinary fire. Moving away from the marked bay removes its contextual opportunity. Append `rotated` after `--` to turn the layout 180°.
- Service Depot from ordinary Match Setup remains the readability-only example. The standalone commands leave existing map rotation, HUD and mission sets alone.

## Architecture and selection

Direct firing remains first. `CombatRules` now supplies a typed firing solution for any legal Attack. It contains the canonical resting point, firing origin, selected sample, open samples and, for contextual shots, the physical offset and facing point. The result describes a particular shot rather than a general-purpose posture search. Targeting and destination previews use it. Attack and existing Guard both obtain it from the same geometry evaluator, and record the resolved solution in their normal receipts. Short AI plans and position forecasts already consume those queries. The Guard terrain inventory reuses the same fallback at the marked tile. Nothing consumes combat RNG until authority accepts the action.

A blocked direct shot on a marked tile tries at most one **24 cm** side step. Unit-radius and same-tile checks bound the adjustment. Its flat supported endpoints, swept-body path and return are checked. Occupancy checks include live neighbors. A conservative swept weapon/pose envelope spans the supported points, rejecting intersecting surrounding solid boxes, curved envelopes and bodies before any additional rays. For this package, the envelope is 0.9 m horizontally from the body trajectory and 1.85 m high. It is intentionally larger than the observed rifle arc. The certified aim cone is limited to 5° around the bay’s authored forward direction and 2.5° from the calibrated level muzzle direction. Targets at a different elevation, shielded/carrying shooters, other rig variants and unmarked stops fall back to their ordinary rules. Only the standard tactical MIRA scene is calibrated. AP, accuracy, damage, SP and Guard triggers use the existing rules. Accuracy is based on open target samples and normal protection modifiers.

The side-step trial began with a root translation. This moved both feet by ~24 cm in the rendered diagnostic and was rejected as a pose solution. The implementation instead reuses the existing foot levelling and two-bone IK contact stages with two sequential swings, holding the other foot during each swing. The visual adapter moves for preparation and recovery. The tactical actor transform and grid occupancy stay put. Existing attack raise, alignment, fire and settle run at the selected pose. The mover’s on-arrival attack and any Guard checkpoint are evaluated independently. A contextual step never opens a movement action or publishes a new reaction trigger.

Replay rebuilds the small authored bay from its named ID and seed, and verifies the quantized rest, firing support, offset, origin, aim sample and facing alongside the usual resolved values. Older receipts omit those optional fields and retain their existing comparison path. The contextual setup is reachable only in the new battlefield, so it adds no candidate to archived Depot, Freight Yard, Fleet Station or Test Range matches. The truck’s geometry version is unchanged from the previous slice.

Sources: [geometry and shared solution](../../systems/combat_rules.gd), [defined bay geometry and spawn symmetry](../../systems/generation/contextual_firing_bay.gd), [Attack and Guard](../../systems/actions/runtime/tactical_action_service.gd), [presentation handoff](../../presentation/tactical/tactical_action_presenter.gd), [animation host](../../presentation/tactical/tactical_character_adapter.gd).

## Coverage and limits

The original test pose at the truck was aligned but its muzzle path crossed the obstacle. This remains a negative control. The bay regressions exercise a blocked center shot, both layout orientations, bounded adjustment, static body or weapon obstruction, blocking neighbor, hypothetical Move, live Player and Guard, autonomous enemy Attack, unchanged tactical position, fixed-seed repeated queries, and replay verification. The diagnostic script captures the alternative foot-contact trial separately from the certified action. [Integrated fixture](../../tests/contextual_firing_bay_test.gd) · [Rig calibration](evidence/contextual-03a/reference_trial.gd).

The rendered check compares actual muzzle position and angle to the selected solution when the attack sequence releases the shot. The acceptance targets for this one rig and geometry are **2 cm** and **2.5°**, plus a clear ray from the observed muzzle. Foot placement evidence comes from the same rig contact targets and frame samples. Neither simulation legality nor replay reads the rendered bones. No extra exposure penalty or reaction run is attached to the temporary position. The recorded resting and firing coordinates support a later counterplay decision. The model assumes a brief defensive return is acceptable within one ordinary attack cost, which is provisional for playtesting.

The certification is bounded to this local step and reference geometry. It does not establish arbitrary left/right offsets, low-cover pop-ups, elevation changes, weapon/rig variants, bulk deployment on Depot, or all possible cinematic views. Human tactical readability and balance remain open. Enemy use in the controlled match establishes that the tactic is visible and accessible without a separate AI solver. It does not establish how often a longer encounter should allow it, or that returning to cover is balanced.

## Verified results

The reference floor has 1 m tiles. In the unrotated bay, the defender rests at cell `(6, 0, 3)` and fires toward `(6, 0, 8)`. The wall measures 1 × 2.3 × 0.10 m. Relative to the resting point it stands 1.20 m downrange and its open edge is 7.5 cm to the defender's right. The direct inventory is blocked. After the 24 cm step, the verified muzzle-to-sample ray clears the edge. Rotating the setup through 180° and placing either faction in the bay preserved the modeled outcome.

| Released shot | Muzzle position error | Muzzle alignment error | Observed ray |
|---|---:|---:|---|
| Player, seed 1 | 1.11 mm | 0.93° | Clear |
| Player, rotated, seed 3 | 0.65 mm | 0.97° | Clear |
| Guard reaction | 1.13 mm | 0.93° | Clear |
| Enemy plan, seed 2 | 0.96 mm | 0.95° | Clear |

The rendered integration script passed 41 checks. The separate calibration measured 242.5 mm of held-ankle movement in the original sliding trial and under 0.01 mm of sampled hold-target error using staged foot IK. The calibration recorded zero sampled intersections with the reference weapon envelope. This measures the held contact points and calibrated muzzle in the reference rig. It does not certify mesh clearance at every joint in arbitrary cover geometry.

The replay verifier reconstructed the bay from its recorded seed, reevaluated one committed contextual attack through the action service, and matched its stored posture and resolved values. This verifies playback from the same restored state. A future change to the calibrated rules would need to retain the old behavior or version the bay before shipping affected recordings. Guard was verified live and its nested solution appears in the parent action receipt. The existing defensive replay suite also passed.

Project Ironclad passed project import and 15 selected tests spanning tactical authority, Depot targeting/readability, cover geometry, curves and navigation, AI decisions, Guard, defense/surface replay, HUD and presentation. After the final rig, pause and Guard overlay changes, 4 selected tests passed again. The complete ordinary suite was not run. The rendered fixture exited successfully. The local engine logged shader cache write errors when launched without an isolated profile and a Windows certificate-store warning during the standalone calibration. Neither prevented completed measurements or image captures.

[Player capture](evidence/contextual-03a/player-1.png) · [Guard capture](evidence/contextual-03a/guard.png) · [Enemy AI capture](evidence/contextual-03a/ai.png). The automated evidence camera disables occluder cutaways for the captured frames. The playable launch uses the game camera. No human playtest or balance approval has been recorded.

## Timing and parity

Windows, Ryzen 5 5500, GeForce RTX 5060, Godot 4.7.2, OpenGL Compatibility. Rendered runs used 1280×720 at normal gameplay speed. Each layout was run once and frame intervals include startup, setup and presentation. The headless comparison reused the same 12× simulator configurations and the compiler-10 runs recorded immediately before this package. The earlier compiler-9 runs remain geometry-compatibility controls.

| Service Depot Eliminate | Planner decisions sampled | P95 CPU before → after | P95 slice before → after | P95 wall before → after | Match result |
|---|---:|---:|---:|---:|---|
| Seed 950507647, 3v3 | 48 | 51.55 → 52.24 ms | 13.80 → 13.14 ms | 65.55 → 66.14 ms | Victory, 4 rounds, 50 decisions |
| Seed 16, 5v5 | 123 | 83.05 → 82.76 ms | 15.60 → 15.24 ms | 101.88 → 102.69 ms | Victory, 10 rounds, 124 decisions |

These comparisons characterize ordinary-map cost when the contextual feature is inactive. They establish parity of the observed match outcomes and decision counts. The correctness tests cover executed solutions and deterministic receipts separately.

| Rendered match | Process intervals | P95 interval | Maximum interval | P95 planner CPU / slice / wall | Rejected actions |
|---|---:|---:|---:|---|---:|
| Firing Bay, seed 2, 1v1 | 6,527 | 1.34 ms | 307.24 ms | 29.87 / 10.02 / 34.02 ms | 0 |
| Service Depot, seed 950507647, 3v3 | 24,113 | 3.30 ms | 332.89 ms | 56.42 / 14.15 / 80.84 ms | 0 |

The Bay completed in two rounds with seven decisions. Rendered Depot completed in four rounds with 50 decisions. The capture cannot attribute the worst frame intervals to a specific subsystem. It also cannot estimate a large match with many contextual stops. With eight warm-ups and 128 samples per query, the marked stop's P95 target forecast was 0.520 ms versus 0.444 ms for the same blocked direct forecast. P95 for the prospective destination query was 1.373 ms versus 0.485 ms. A marked stop tries at most one candidate and five extra body-sample rays after its physical checks. Solutions involving nearby bodies are computed fresh. There is no shared contextual solution cache. A benchmark with many marked stops is still needed before broad deployment.

### Reproduce the checks

```powershell
.\tools\run_tests.ps1 select -Test contextual_firing_bay_test,combat_guard_coverage_cache_test,defensive_actions_replay_test,tactical_decision_feedback_hud_test
godot_console --path . --rendering-method gl_compatibility --resolution 1280x720 --script res://tests/contextual_firing_bay_test.gd -- artifacts/contextual-03a/integrated-captures
godot_console --path . --rendering-method gl_compatibility --resolution 1280x720 --script res://docs/quality/evidence/contextual-03a/reference_trial.gd -- artifacts/contextual-03a/trial
godot_console --headless --path . --script res://docs/quality/evidence/contextual-03a/query_cost.gd
godot_console --path . --rendering-method gl_compatibility --resolution 1280x720 --script res://docs/quality/evidence/contextual-03a/rendered_performance.gd -- profile-ai
godot_console --headless --path . --script res://docs/quality/evidence/intelligent-cover/ai_cargo_benchmark.gd -- profile-ai
```

The local run artifacts are under `artifacts/contextual-03a/`, including `cert-render.log`, `query.log`, `rendered-perf.log`, `ai-5v5-and-baseline.log` and the `final-ironclad` and `after-cache` summaries.

## Next playtest

Use both launch variants. In the enemy variant, check whether it is clear how the enemy gained the firing angle and whether the position still reads as a threat before that turn. Try going around the exposed end and then holding the blocked angle to see whether each choice feels legible. The autonomous test starts the enemy on the marked stop. It verifies that normal planning considers and takes the shot, but provides no evidence that AI will seek similar stops across a larger battlefield. Use human results to decide whether the return to cover is too favorable at the ordinary Attack cost before marking additional stops or designing reaction counterplay.

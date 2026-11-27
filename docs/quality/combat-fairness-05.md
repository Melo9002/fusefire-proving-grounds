# Package 05 — Combat fairness and counterplay

Start from Package 04 checkpoint `51eddaf803f5df20535628b18e071dfaf0f2e4ae` on `codex/asymmetric-line-of-fire`. The earlier Package 03A and 03B checkpoints are `79d9c71` and `e47acf8`. The three narrow lanes from the first Depot match and a fourth from the second match disappear under Head/core and Symmetrical. The two policies produced different AI behavior in a matched cautious Depot battle. Both belong in the human comparison. Legacy remains the default.

## Play the comparison

In the normal game, open **Match Setup → Mission**. Choose an **Engagement Rule** and use **Contextual Firing** to enable side steps on Service Depot or Freight Yard. A fresh setup starts with Legacy and side steps off. The briefing and **F3 → Runtime** show both settings. The toggle resolves to the existing certified battlefield variant, so saved replays retain their original map and firing rules.

Open **Match Setup → Combat Lab** for the curated 2v2 comparisons. Pick the engagement rule, contextual firing, Guard minimum hit chance, enemy commander and battlefield on one tab. **Start Comparison** launches the configured battle directly. **Copy launch command** copies the equivalent PowerShell command with the active project path. The tab opens with Symmetrical, contextual firing on, 15% Guard, Cautious and Depot Crossfire. Ordinary match setup retains its own settings.

For the matched comparison deployments, run these from the Godot project root, using the existing battle controls. The mode, side-step setting and Guard policy appear below the turn indicator. In Move, hover for arrival lanes or press **V** to pin the hologram and inspect a particular known enemy. Click the pinned tile to commit, or cancel as usual.

```powershell
godot_console --path . --script res://docs/quality/evidence/combat-policy-05/play_comparison.gd -- legacy
godot_console --path . --script res://docs/quality/evidence/combat-policy-05/play_comparison.gd -- head-core
godot_console --path . --script res://docs/quality/evidence/combat-policy-05/play_comparison.gd -- symmetric
godot_console --path . --script res://docs/quality/evidence/combat-policy-05/play_comparison.gd -- combined
godot_console --path . --script res://docs/quality/evidence/combat-policy-05/play_comparison.gd -- symmetric pressure guard=15
```

The default encounter is **Depot Crossfire**, a 2v2 Hard Eliminate match starting near the container-and-truck lanes. **Pressure** uses the existing contextual Freight Yard variant, with longer approaches and multiple ways around the central obstacles. Both use seed 16 and the existing Cautious enemy commander. Use `ordinary` to compare the Default commander independently. Use `duel` for 1v1, `3v3` for larger squads, `no-context` for direct fire only, and `guard=N` for a minimum advertised Guard hit chance in whole percent. `guard=0` selects first legal. Each option is independent. The launcher rejects unrecognized options and battle setup rejects out-of-range thresholds. [Launcher](evidence/combat-policy-05/play_comparison.gd).

## Engagement policy and authority

| Mode | Direct eligibility | Extra requirement |
| --- | --- | --- |
| A · Legacy | Any of five target samples | None |
| B · Head/core | Central body or head sample | A side-step solution must also reach a central sample |
| C · Symmetrical | Any of five target samples | A physically available shot in each direction from the same two canonical positions |
| D · Combined | Central body or head sample | Central eligibility in both directions |

Direct fire keeps the existing canonical support point plus the shooter's tactical standing height as its origin. Head and core are existing target proxies at 1.75× and 1.2× the target's standing-height parameter. All five target samples still contribute to obstruction penalties after a shot qualifies. This is a target-exposure rule. Source perception, awareness and detection contracts are unchanged. When direct fire fails the policy's target-sample requirement, the existing certified side-step solver can check its bounded candidates. It keeps the same swept body and weapon envelope, support, nearby-body occupancy, pitch, muzzle clearance, and deterministic ordering. Opt-in battlefields retain the standard tactical MIRA and calibrated AUG boundary. An uncalibrated weapon or rig can still have ordinary direct geometry. A side step that relies on a hypothetical future animation or an uncertified pose provides no reciprocal lane. [CombatRules](../../systems/combat_rules.gd).

Symmetrical combines two independent physical checks. The reverse check can exit as soon as it finds an eligible direct sample. It never calls full reverse attack authorization. Enemy AP, SP, Guard reservation, attack range and aiming bonuses provide no immunity. A Shield stance can constrain the certified side step. A completed hypothetical move cancels it for the mover as a prospective shooter. A real Guard checkpoint samples the mover's state at that event. Current Shield damage and accuracy treatment still belongs to shot resolution. Successful attacks and reactions carry the same existing authoritative firing solution into animation and replay. There is no temporary tactical relocation. [Action authority](../../systems/actions/runtime/tactical_action_service.gd) · [AI plan evaluation](../../systems/ai/ai_plan_evaluator.gd).

The pinned preview reuses the canonical arrival query for both directions. It separates `No mutual firing lane`, `Insufficient target exposure`, ordinary obstruction and range. The physical obstruction marker remains reserved for an actual collision. AP and SP can still make an available lane unaffordable. Visible enemies with Guard are called out separately because arrival forecasts do not predict reactions along every checkpoint. The full-map Attack and Guard overlays use the existing sliced scan under reciprocity. Occupied cells use the real reciprocal pose checks. Vacant cells use a hypothetical standing opponent for the return check, with no assumed weapon calibration, so their overlay is conservative. The actual target hover and Guard execution use the real enemy. Reciprocal display results are not cached across scans because either actor's equipment, stance or surrounding bodies can change its certified capabilities. [Tactical feedback](../../presentation/overlays/tactical_feedback_text.gd) · [Coverage and targeting](../../systems/battle_controller.gd).

Legacy recordings keep their original simulation version. The experimental rules settings are encoded in replay configuration and tagged `prototype-1.5-combat-policy-12`. An earlier executable will reject that version instead of treating it as Legacy. The loader rejects version and policy mismatches. Historical map manifests, canonical supports, receipt ordering and existing firing-solution records are preserved. [Replay codec](../../systems/replay/battle_replay_recording.gd).

## Historical witnesses and local geometric sensitivity

Both archives verified their original victory under Legacy, `Test.json` at 80/80 records and `Strange.json` at 74/74. The table compares authoritative queries at the recorded snapshots with experimental settings applied to the query and restored immediately. The historical record itself always plays under its original rules. Contextual firing was off in both human matches.

| Witness | Canonical cells in firing order | Legacy geometry and chance | Head/core | Symmetrical |
| --- | --- | --- | --- | --- |
| Original truck, seed 950507647 | Enemy3 `(22,0,22)` → Alpha `(17,0,15)` | One peripheral sample. Alpha's return path intersects the truck | Rejects the peripheral lane | Rejects the incoming lane because Alpha has no return path |
| Test rev 23 | Enemy1 `(21,0,16)` → Bravo `(13,0,20)` | One peripheral sample, 9%, full cover | Denied | Denied |
| Test rev 36 | Enemy1 `(16,0,16)` → Alpha `(14,0,25)` | One peripheral sample, aimed 38%, full cover | Denied | Denied |
| Test rev 67 | Alpha `(15,0,31)` → Enemy1 `(16,0,25)` | One peripheral sample, 50%, no directional cover | Denied | Denied |
| Test rev 74 | Alpha `(15,0,31)` ↔ Enemy1 `(16,0,29)` | Five samples, 100% each way | Both available | Both available |
| Strange rev 56 | Bravo `(15,0,29)` → Enemy2 `(14,0,26)` | One peripheral sample, 50%, full cover | Denied | Denied |
| Strange rev 73 | Bravo `(14,0,29)` ↔ Enemy2 `(14,0,25)` | Five samples, 100% each way | Both available | Both available |

Alpha's original outgoing lane stays blocked in all modes. The original truck scene comes from the reconstructed fixture, with Enemy3 confirmed from the screenshots. The first replay's archived SHA256 is `9C8EF9D75FBD5ABD258AB8A6284EF365B98D964D6DC7144E492108BF80614F3D`. The second local replay's SHA256 is `F499C46A84F8E5701936ED8EED2F9E80170811A1DE947461E50D6FE7D64062AF`. The records can show legal sample paths and chance. They cannot establish what a live weapon model did in the original session.

Four independent 1 cm planar shifts to the direct origin found zero central samples in both directions for the examined one-way replay rows. The same shifts preserved both central samples in each direction for the two clean controls. Package 04's larger translation from accepted stands to nominal cell centers did change two of its three one-way cases. The 1 cm experiment holds the destination samples fixed and measures sensitivity of the ray calculation. It grants no movement or shooting permissions. [Comparison tool](evidence/combat-policy-05/compare_replay.gd) · [Original reconstruction](asymmetric-line-of-fire-investigation.md) · [Package 04](contextual-firing-04.md).

## Offline battlefield survey

One in four supported source cells, twelve fixed planar vectors and no occupied spawn endpoints. The counts are unique unordered samples. Fleet Station used contextual discovery for this diagnostic only. All three maps used seed 16 and calibrated standard MIRA/AUG. Counts describe geometric eligibility before action resources, combat effects or tactical choice.

| Map | Pairs | A mutual / one-way / neither | B mutual / one-way / neither | C mutual / one-way / neither | D mutual / one-way / neither |
| --- | ---: | --- | --- | --- | --- |
| Service Depot | 2,746 | 2,489 / 34 / 223 | 2,471 / 17 / 258 | 2,489 / 0 / 257 | 2,471 / 0 / 275 |
| Freight Yard | 3,027 | 2,769 / 18 / 240 | 2,760 / 10 / 257 | 2,769 / 0 / 258 | 2,760 / 0 / 267 |
| Fleet Station | 2,906 | 2,717 / 20 / 169 | 2,707 / 9 / 190 | 2,717 / 0 / 189 | 2,707 / 0 / 199 |
| Total | 8,679 | 7,975 / 72 / 632 | 7,938 / 36 / 705 | 7,975 / 0 / 704 | 7,938 / 0 / 741 |

A had 7,961 mutual direct pairs and 14 mutual pairs requiring at least one side step. Across both directions, 110 Legacy-eligible directions lacked an eligible central solution. Head/core halves the one-way count and costs 37 mutual pairs in this sample. Symmetrical preserves Legacy's mutual pairs and removes all 72 one-way pairs. A physically exposed target can therefore gain immunity under Symmetrical if its return geometry is obstructed. B can similarly refuse a target whose only visible region is peripheral even if that region reads clearly on screen. These are design trade-offs with different player-facing explanations. The sample is not representative of how often play concentrates beside obstacles. [Survey source](evidence/combat-policy-05/survey.gd).

## Guard and temporary exposure

Guard A consumes its reservation at the first legal opportunity, under its existing trigger and ordering. Guard B applies the configured quality threshold after eligibility and the Guard accuracy modifier. It leaves its reservation and SP in place, draws no RNG on a declined shot, and can still evaluate subsequent legal trigger events. The combat log keeps one bounded explanation per watcher and parent action. A later physical block preserves the useful held-fire explanation while a shot that actually fires replaces it. The AI uses the same quality rule for actual reactions and considers it for presently useful lanes when evaluating Guard. It may still choose Guard because enemies can approach.

In `Test.json` at rev 22, the original move's first two checkpoints are out of range. At `(22,0,17)` Guard A can take the 5% shot and spends one SP on the recorded miss. B at 15% declines, and at the final `(21,0,16)` the lane is blocked. Holding buys a retained reservation, never a better shot on that movement. 15% is a playtest value. A more complex Guard C decision would require explicit values for conserving a single reservation versus taking a poor shot at a heavily damaged or high-priority target. The current service has today's target, chance, posture and resource state. It should use no future checkpoint, planned intent or RNG information to make that decision.

The existing Attack service settles its shot and then triggered retaliation before receipt publication and presentation. Only the watcher's ordinary checkpoint or resting geometry is available today. A temporary firing state would need authoritative body sample and muzzle transforms for both directions. Before-shot reactions can cancel an incoming attack and require an explicit AP/SP refund policy. After-shot reactions leave the initiating shot irrevocable and need a rule for a defeated watcher. Simultaneous reactions would require health snapshots and a deterministic order for resource consumption, interruption and multiple watchers. The smallest coherent future experiment is a named event inside the initiating Attack receipt with one ordered pass over eligible watchers, no recursive events, independent validation at the temporary pose, and normal return/cancellation from the receipt. No new trigger, cost, animation-clock vulnerability, or combat modifier is implemented. [Attack commitment and reactions](../../systems/actions/runtime/tactical_action_service.gd).

## Cautious AI stress comparison

Actual AI-versus-AI matches used Hard, seed 16 and Eliminate. Default player versus Cautious enemy unless stated. The two scenes use genuine spawn and ordinary AI planning. The cap runs through round 12 and stops on entering round 13. HP is surviving team total. Protected activations count a sampled actor with directional terrain cover against at least one in-range enemy. Pair counts are activation observations and may repeat a pair. These runs measure play behavior without certifying frame times.

| Encounter and settings | Outcome / round | HP P–E | Direct / step / move | Guard arms / fired / holds | Waits | Protected activations |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Depot 2v2 A | Victory / 7 | 150–0 | 17 / 0 / 14 | 5 / 0 / 0 | 4 | 13/18 |
| Depot 2v2 B | Victory / 3 | 100–0 | 8 / 4 / 6 | 0 / 0 / 0 | 0 | 1/6 |
| Depot 2v2 C | Round limit / 13 | 200–100 | 4 / 0 / 12 | 9 / 0 / 0 | 24 | 33/36 |
| Depot 2v2 D | Round limit / 13 | 200–100 | 4 / 0 / 12 | 9 / 0 / 0 | 24 | 33/36 |
| Depot C, both Default | Victory / 7 | 150–0 | 14 / 0 / 9 | 3 / 0 / 0 | 8 | 14/18 |
| Depot C, Cautious player / Default enemy | Victory / 7 | 150–0 | 14 / 0 / 9 | 3 / 0 / 0 | 8 | 14/18 |
| Freight Yard 3v3 A | Round limit / 13 | 200–100 | 20 / 0 / 40 | 14 / 1 / 0 | 28 | 45/59 |
| Freight Yard 3v3 C with 15% Guard | Round limit / 13 | 125–75 | 24 / 0 / 44 | 17 / 3 / 0 | 24 | 47/59 |

Depot C repeated the same outcome with side steps off and with Guard B at 15%. It recorded 46 mutual closures and zero one-way authorizations, versus 15 closures and three one-way observations in A. B recorded two closures and three one-way observations. B's four contextual attacks were two sequences from the same respective support points. Terrain still limits exposed target samples and applies the existing protection modifiers, even where both sides have a legal shot. The Freight run produced active trades and repositioning, despite the round limit. Its A/C comparison also changes Guard, so it does not isolate the effect of geometry.

In the Depot C stagnation, the log repeatedly reported moves outside the route or below the movement value threshold. A trial widening the existing AI's blocked-origin short-plan scan to regular mutual lanes produced the same Depot action counts and terminal state. The trial was removed. The previous Strange replay also had a final hostile who waited while potentially useful moves existed outside the preferred route, under Legacy. These observations identify route and exposure scoring as a follow-up for further reproduction. They cannot identify from outcome alone the best repair or establish that the AI was immobile. [Stress tool](evidence/combat-policy-05/stress.gd) · [AI movement decisions](../../units/ai_controller.gd).

## Verification and what to play first

Play **Symmetrical first** in Depot Crossfire, then rerun the same deployment with **Head/core**, keeping Guard and side steps identical. C directly solves the unwanted one-way affordance. During comparison, watch for a clean-looking target that cannot return fire, and for both sides waiting behind cover. B is the stronger alternative on the current automated pace evidence. It preserves some directional advantages, including one-way central exposures, and removes every examined narrow incident. Combined loses mutual lanes over C and has shown no pacing advantage in this seed. None of these results substitutes for human gameplay approval. Cover and flanking still matter where the terrain produces mutual geometry with unequal protection, accuracy or range. Strict symmetry intentionally removes a flank's ability to shoot someone whose return geometry is entirely blocked.

Ironclad project import and 13 focused tests passed, covering combat geometry, curved solids, tactical previews and HUD, Guard and coverage, AI determinism, replay, and the retained Package 03A and 03B fixtures. After adding the F3 rules display, the final UI and policy selection passed again. The final engagement fixture passed 53 checks, including faction swap, opposing AP/SP independence and a committed Guard refusal without an extra RNG draw. The complete ordinary suite was outside this run. Ironclad logs are under `artifacts/ironclad/p05-final/`, `artifacts/ironclad/p05-ui/` and `artifacts/ironclad/p05-contract/`.

Rendered evidence uses the existing normal game camera and controls, with autonomous actions in the recorded openings. The Depot Head/core capture shows Enemy2 independently taking two side-step shots and returning. Its live checkpoint replay verified 13/13 records, including both recorded contextual solutions. The Symmetrical capture exercised four direct attacks in its opening. Freight Yard was rendered at deployment; the expanded Freight action comparison above was headless. The two 19-second clips are local at `artifacts/p05-render-headcore-certified.avi` and `artifacts/p05-render-final.avi`. The short scenario captures are `artifacts/p05-comparison-depot.avi` and `artifacts/p05-comparison-pressure.avi`. The fixed 30 FPS encoding records presentation sequences. Frame latency was outside this capture. [Symmetrical Depot](evidence/combat-policy-05/symmetric-depot.jpg) · [Symmetrical Freight](evidence/combat-policy-05/symmetric-freight.jpg) · [Head/core enemy side step](evidence/combat-policy-05/head-core-side-step.jpg).

Reproduction commands and artifact paths follow. Package 06 retains comprehensive optimization, frame-stall attribution and isolated performance certification. The additional reverse check is bounded and can terminate on the first qualifying sample. The fixture does not establish multi-level side-step presentation, arbitrary rig/weapon calibration, or how temporary authoritative exposure would feel in play.

```powershell
godot_console --headless --path . --script res://docs/quality/evidence/combat-policy-05/compare_replay.gd -- docs/quality/evidence/contextual-04/Test.json
godot_console --headless --path . --script res://docs/quality/evidence/combat-policy-05/compare_replay.gd -- artifacts/contextual-04/Strange.json
godot_console --headless --path . --script res://docs/quality/evidence/combat-policy-05/survey.gd
godot_console --headless --path . --script res://docs/quality/evidence/combat-policy-05/stress.gd -- mode=2
godot_console --headless --path . --script res://docs/quality/evidence/combat-policy-05/stress.gd -- pressure 3v3 mode=2 guard=15
godot_console --path . --rendering-method gl_compatibility --resolution 1600x900 --fixed-fps 30 --write-movie artifacts/p05-render-headcore-certified.avi --script res://docs/quality/evidence/combat-policy-05/play_comparison.gd -- head-core autoplay smoke capture=res://artifacts/p05-headcore-game.json
```

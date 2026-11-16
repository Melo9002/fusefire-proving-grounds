# Cover and flanking — milestone 04 step 5

2026-11-16. Implements the cover portion of the [intended combat rules](../combat-2-rules.md), using existing geometry and the [editable range](../combat-controlled-examples.md). This intentionally changes cover behavior and odds. It does not implement range falloff, an explicit height accuracy bonus, the proposed +35 Aim, new damage or criticals.

## Current contract

- Inspect the four cardinal neighbor cells at the defender's supported level. Trace from the attacker's actual firing origin to the defender's lower-body reference, half its `standing_height` above its supported position.
- Use the same ray/compound-part/corner checks as shot legality. An empty tile label, an empty gap or a surface below the ray supplies no protection. Side/rear attacks are flanks when that surface no longer intersects the ray. A high shooter can clear a low obstacle without an extra accuracy modifier.
- Among surfaces that actually protect the target, use the strongest. Low protection costs **20 points**, full protection **40**. Precise parts use the existing full-height threshold of **1.2 tile widths above the defender's supported surface**. A low part does not inherit strength from an unrelated tall part sharing its cell. Legacy non-precise cells retain their explicit category, but still need a physical ray intersection.
- Keep the existing five-sample exposure table. Apply `max(cover, exposure)`, never their sum. Shield remains a separate active modifier. No flank critical or additional flank bonus is added.
- Normal actions, predicted destinations and AI use the same calculation and actual body heights. The evaluation identifies `cover_cell`, `cover_penalty`, `obstruction_penalty` and `protection_penalty`; richer player-facing breakdowns remain step 9.

| Example | Expected result with today's other modifiers |
| --- | --- |
| Low 0.8-high crate, four clear body samples | Cover 20, exposure 10, combined 20: **80%** |
| Same crate from its open side or rear | No cover and all samples clear: **100%** |
| Full 1.3-high crate, two samples clear from a raised firing position | Cover 40, exposure 40, combined 40: **60%** |
| Full crate from level ground, only head sample clear | Cover 40, exposure 50, combined 50: **50%** |
| Compound part gap clears the lower-body ray but hides both shoulders | No cover, exposure 25: **75%** |
| Low protecting part plus an off-ray tall part in one cell | **Low** protection, not full; 80% in the fixture |
| Low crate plus frontal Shield | Combined environmental penalty 20, Shield 20: **60%** |

The full-crate example explains why “full cover” does not always mean precisely a 40-point total penalty: very little body exposure can impose a larger penalty. A flank removes the local surface's bonus, not unrelated obstruction or Shield.

## Editing and replay

Open `systems/combat_cover_tuning.tres` in Godot to change `low_cover_penalty` and `full_cover_penalty`. Values are integer percentage points. The resource requires `0 <= low <= full <= 100`; invalid values reject normal and predicted shots with a clear reason. Edit before launching a new battle. No per-asset role or boundary authoring is required.

`CombatRules.cover_tuning` is the shared runtime resource. The replay simulation identity is now **`prototype-1.5-directional-cover-5`**, and recordings include its cover-value signature, currently `cover-1:20:40`. Old simulations or changed/missing cover signatures reject before playback. The action schema, compiler/content revisions, actual cover geometry and files already on disk are not rewritten.

## Regression and fixture decisions

The initial 29-case focused test failed **17 checks** under the old label-only/50-point rules. The expanded focused test now passes **40 checks**, including four orientations, side/rear attacks, physical height clearance, tall bodies and predicted positions, paired corners, compound gaps and mixed part heights, actual query/commit parity, pure queries, separate Shield stacking and editable/invalid tuning.

The first combat subsystem run had four failures: old numerical cover expectations and label-only fixtures in Aim, Shield and supply-miss tests. A separate AI scoring check had the same label-only issue; the move-feedback fixture also used a 0.6-high obstacle below its diagonal lower-body ray. These were classified as **intentional contract changes or invalid fixtures for the new contract**, not reasons to remove assertions:

- Combat cover assertions now verify 20 cover versus 40 exposure and a 60% result in the existing waist-high-barrier setups.
- Aim and supply tests now put a real 0.8-high obstacle between nonadjacent actors. Their Aim submission, repeated-Aim rejection, HUD state, hit/miss resource accounting and RNG-controlled miss assertions remain.
- Shield tests now put the obstacle between the actors instead of labeling the shooter's occupied tile; they preserve separate capability, direction, damage and commitment checks. Low/Shield is 60%; a physically exposed full-cover/Shield case is 40%.
- AI's protected comparison now has real geometry and retains the assertion that protection increases its position value.
- Move feedback uses a protecting 0.8-high obstacle, verifies the 80% hypothetical shot, and retains its checks that moving cancels Aim without mutating live state or inventing AP/supply.

A further compound-part regression first failed when an intersected low part inherited its cell's tall envelope. It passes after classifying the part actually hit. The final focused test also verifies that runtime edits reach the shared calculation and invalid tuning is rejected consistently.

## Verification

- Combat subsystem: **29 pass, 0 fail, 1 optional metrics check excluded** after the fixture/contract corrections.
- Replay subsystem: **15 pass, 0 fail, 0 skip**, including the current mission/replay matrix and real-site playthroughs.
- AI subsystem: **22 pass, 0 fail, 1 explicit simulation batch excluded**.
- Final focused cover check: **40 checks, 0 failures**. Rendered mode: **46 checks, 0 failures**, including the actual range's low-cover, flank and full-cover queries and three saved images.
- Focused Aim, supply, Shield, combat cover, feedback, replay-schema, AI scoring and automatic mesh-boundary checks passed after their relevant changes.
- After the final mixed-part classification correction, the **48-case current mission/replay matrix**, real-site content playthroughs, combat cover, Shield, feedback and automatic mesh-boundary checks passed again with zero failures. Three final rendered comparisons were inspected.

Broad logs: `artifacts/test-results/20261116-073435-subsystem-combat/`, `20261116-073311-subsystem-replay/` and `20261116-073616-subsystem-ai/`. The broad combat/replay runs preceded the final mixed-part classification correction; the final focused/current-map follow-ups below cover that correction. No full-project suite was run.

Reproduce the cover checks:

```powershell
godot_console --headless --path . --script res://tests/combat_cover_direction_test.gd
godot_console --path . --script res://tests/combat_cover_direction_test.gd -- capture
```

Captures under `artifacts/cover-direction/` come from a fresh, normally compiled range with its unchanged authored geometry; captions read actual query contributions. They are test annotations, not a new battle HUD. Visual inspection does not establish a full manual battle or cover animations. Some processes printed the existing Windows certificate-store error; this was not a tactical assertion failure.

Next is step 6: implement the agreed height/range accuracy tuning using these established protection and geometry rules. Per-mesh boxes remain approximations; this step does not turn concave assets into exact polygon boundaries.

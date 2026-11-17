# Combat milestone 04 — step 7: accuracy and damage

Delivered 2026-11-17. Accuracy chooses hit or miss; it never scales successful-hit damage. Ordinary hits remain **25**, misses **0**. Aim is intentionally retuned from **+15 to +35 percentage points**. Shield retains its separate frontal damage reduction (25 × 0.35 rounds to 9). No criticals, grazes, random damage or new weapon framework.

## Editing the starting numbers

Edit `systems/combat_cover_tuning.tres` in Godot before starting a new match. The existing resource/class names are retained so there is one shared tuning location:

| Setting | Default |
| --- | --- |
| Base accuracy / legal-shot floor / ceiling | 100 / 5 / 100 |
| Aim / Guard reaction modifier | +35 / -15 |
| Damage on hit | 25 |
| Low / full cover | 20 / 40 |
| Range safe fraction / endpoint penalty / exponent | 0.60 / 70 / 2 |
| Height per tile / signed cap | 5 / ±20 |

Range still uses actual supported-position 3D distance. Clear, level normal shots at 60%, 80% and 100% of weapon range give 100%, 83% and 30%. Max-range Aim gives 65%; two tiles of height advantage gives 75%. All successful ordinary examples deal the same 25 damage.

The formula remains `base - range - max(cover, exposure) + height + action bonus + Shield accuracy`, then clamp to the configured limits and round once. Guard substitutes its own modifier for Aim. Blocked/out-of-range attacks remain illegal regardless of bonuses. Aim's cost, consumption and cancellation rules remain unchanged. Zero is a supported Aim setting: a committed attack must still consume that stance, even when its bonus is zero.

Per-unit weapon range stays on the unit. Shield settings stay in the existing capability resource. The five-sample exposure table is unchanged. `expected_damage` remains probability-weighted information for AI; it is not damage applied by a successful hit.

## Implementation and replay

CombatRules produces the calculation once for the existing UI, AI and authoritative service. Direct shot feedback now describes base, cover/exposure and their strongest protection, range, height, Aim, Shield, raw chance and the rounded/limited chance. Damage on hit is a separate figure; a protected shot identifies Shield's multiplier. Chance colors and broader presentation polish remain step 9.

The shared damage helper is used by prediction, direct execution, movement-triggered Guard and retaliation. Aim query/results receive their bonus from the service; HUD and normal attack consumers no longer use a separate +15 constant in TacticalState.

Current simulation ID is **`prototype-1.5-accuracy-damage-9`**. The retained `cover_tuning_signature` replay field now hashes all 13 shared settings, including Aim, damage, base chance, limits and Guard. Old simulation versions and changed/missing tuning reject before playback with an explanatory message. Start a new match/recording after editing settings; this does not add old-balance emulation or mutable mid-battle tuning.

## Verification

- **Final focused accuracy/damage regression: 43 checks, 0 failures.** Real service queries/commits at 100/83/30/65/75%; hit and miss damage; pure repeated normal/destination/Guard predictions; JSON-normalized resolved evidence; strict roll boundaries; editable Aim, Guard, damage and limits; invalid-setting rejection; Shield's independent reduction; modifier stacking before both clamps; zero-bonus Aim consumption.
- The zero-Aim regression first reproduced **2 failures in 43 checks**, then passed unchanged after consumption was based on the active stance rather than a positive bonus. This was a defect exposed by making the value editable, not an intentional weakening of the stance contract.
- **Combat subsystem: 30 pass, 0 fail, 1 explicit-only metrics skip** (137.74s). Includes Aim state/cancellation/HUD, cover/flanking, height/range (55 checks), Shield, Guard, shared action authority and combat feedback. The new focused script was added after that run's discovery; its final direct result above is separate.
- **Replay subsystem: 16 pass, 0 fail, 0 skip** (402.17s). Includes the current mission matrix, file workflow, RNG determinism, complete current-site battles and rescue. Freight seed 16 verified 52 actions; Fleet seed 16 verified 100; rescue seed 372339682 verified 258, with matching final results. Current-site recordings exercise +35 Aim. Schema tests cover edits to all newly configurable scalars and reject the prior simulation ID.
- **Final smoke: 11 pass, 0 fail, 0 skip** (49.95s), after the zero-Aim correction. The broad runs preceded that final edge-case correction; no default-balance behavior changed in it.
- **Final graphics run: 45 checks, 0 failures**. Inspected `artifacts/accuracy-review/accuracy-damage-preview.png`: actual clear-range station, 65% chance, 25 hit damage, +35 aimed HUD and a readable contribution panel. This is a focused rendered inspection, not a manual full-match verdict.
- An initial direct editor scan printed root-certificate and user editor-settings write errors from this environment; no script parse failure. Isolated Ironclad parse checks passed. A new-test shutdown script-resource warning was eliminated by preloading its battle fixture; final focused/graphics runs no longer emit it.

The existing Aim and height tests were updated for the intentional +35 contract, retaining costs, cancellation, no-RNG, geometry and state assertions. No full-project or full AI subsystem rerun is claimed. Existing shader and animation limitations remain deferred.

Commands:

```powershell
godot_console --headless --path . --script res://tests/combat_accuracy_damage_test.gd
.\tools\run_tests.ps1 subsystem -Subsystem combat
.\tools\run_tests.ps1 subsystem -Subsystem replay
.\tools\run_tests.ps1 smoke
godot_console --path . --script res://tests/combat_accuracy_damage_test.gd -- capture artifacts/accuracy-review
```

## Hands-on check and next step

Start a fresh Tactical Test Range battle. At the clear-range station, use a weapon with range 10: a target eight tiles away gives 83%, ten tiles away gives 30%. Aim should add 35 points to that difficult shot, to 65%. Every unshielded hit should remove 25 HP, regardless of the displayed chance. Rejected clicks should consume no AP, ammo or RNG. Save and open a new completed replay to compare the outcomes.

Step 8 is the defensive-action review; step 9 remains chance colors and presentation refinement. One source-confirmed AI heuristic follow-up was logged as [#28](https://github.com/Melo9002/fusefire-proving-grounds/issues/28): target-finishing priorities still use a 25-HP threshold, so priority tuning does not yet automatically follow custom damage or Shield. Actual query/execution damage already does; this step does not retune those doctrine weights.

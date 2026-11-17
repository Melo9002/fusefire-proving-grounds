# Height and range — milestone 04 step 6

2026-11-16. Implements the agreed range curve and continuous support-height accuracy through the existing CombatRules/action path. It does not retune Aim to +35, change damage, grant tactical peeking, change Shield arcs, alter navigation geometry or finish the broader feedback milestone.

## Current rule and edit location

Open `systems/combat_cover_tuning.tres` in Godot. The existing resource now groups **Cover**, **Range** and **Height**; no second tuning resource or authoring workflow was added.

| Setting | Starting value |
| --- | --- |
| Low / full cover | 20 / 40 points, unchanged |
| Safe range fraction | 0.60 |
| Maximum range penalty | 70 points |
| Range exponent | 2 |
| Height per tile / cap | 5 points / ±20 |

Distance is the full 3D separation between the two supported standing points, divided by tile size. Reject distance past the unit's maximum range. Within range, let `t = clamp((distance / maximum_range - safe_fraction) / (1 - safe_fraction), 0, 1)`. Range costs `70 * t^2`. Height contributes `clamp(5 * (shooter_Y - target_Y) / tile_size, -20, +20)`.

The final formula is `100 - range - max(cover, exposure) + height + action_bonus + Shield`, clamped 5–100 and rounded once. A small arithmetic epsilon protects exact half-point rounding. Samples and geometry still decide whether a shot exists; bonuses cannot make a blocked or out-of-range shot legal. No hidden roll assistance is added.

Aim remains **+15** for this step, Guard **−15**, Shield **−20 / ×0.35**, and ordinary hit damage **25**. Proposed +35 Aim and chance colors remain later tasks. A high-ground clear shot can already be capped at 100%; height still offsets cover or range penalties in harder shots.

| Clear shot example | Chance |
| --- | --- |
| 60% / 70% / 80% / 90% / 100% range, level | 100 / 96 / 83 / 61 / 30% |
| Same 80% 3D range, shooter two tiles higher / lower | 93 / 73% |
| Same 80% 3D range, shooter 0.25 tile higher / lower | 84 / 81% |
| Maximum range plus current Aim | 45% |
| Full cover 40, exposure 40, shooter 1.2 tiles higher, inside safe range | 66%, not double-counted protection |

When comparing height alone, keep the **3D distance** constant. Raising a shooter at fixed horizontal separation also increases range. In the own-cell low-cover regression, +20 height offsets 20 cover but the longer 3D distance still costs about 1.3 points, producing 99%. The protection ray still hits the cover: increased accuracy is not automatically a flank.

## Authority, feedback and compatibility

The same evaluation carries distance, range fraction, range penalty, signed height modifier, action bonus and unclamped chance. UI queries, predicted positions, Guard checkpoints and execution consume it. Direct shot text now lists the authoritative range and height contributions; a full breakdown/color redesign remains step 9.

All seven cover/range/height scalar values participate in the full-precision tuning signature. The historical replay field name `cover_tuning_signature` is retained; its meaning now covers all these settings. Simulation identity is **`prototype-1.5-height-range-8`**. Previous simulation recordings and changed/missing settings reject before reconstruction; no old replay files are rewritten. Invalid tuning also rejects before playback. Edit settings before a fresh battle.

The formula reads supported world heights, not floor indices, animation roots, camera position or head height. Existing authored ramp/stair navigation is still stepped; this work does not infer a continuous walkable slope from a mesh. Fractional-height fixtures prove that the accuracy calculation itself has no floor-label threshold. Per-mesh boxes and rounded-object limits remain unchanged.

## Failure classification and accompanying repair

The first combat tier reported 25 passes and five failures. Their assertions encoded the old height-neutral or no-falloff chances: directional-cover height setups, a clear 4-of-6-range wall-edge shot, the raised-target prediction, the uphill elevation example and full-cover-plus-Shield. Tests now assert the documented new numbers **and retain their geometry, exposure, cover, Shield and query/execution invariants**. The wall-edge ray remains fully visible and uncovered; its new 98% is range falloff. The feedback fixture now uses a valid positive short range to test out-of-range; zero range is separately tested as invalid configuration.

During expanded cover verification, exact equality on a float32-derived 2.2-height modifier needed the existing approximate-float comparison. Another fixture originally overlooked the increased 3D range when raising a shooter; it now explicitly verifies the 99% interaction above. No gameplay tuning was changed to manufacture those passes.

The real-map replay tier exposed [wounded AI deadlock #25](https://github.com/Melo9002/fusefire-proving-grounds/issues/25): Fleet seed 16 reached two 25-HP survivors that repeated waits to round 79. Its 368-action replay faithfully reproduced ONGOING, so it was not replay divergence. A permanent low-HP urgency veto prevented the existing idle-recovery ramp. The bounded fix removes that veto; early caution, capped urgency, VIP/carrier exemptions and existing route/safe-second-advance validation remain. A focused regression failed two checks before the fix and passes after it. The original 30-second complete-battle/replay assertions remain unchanged.

The same tier exposed [removal continuation race #26](https://github.com/Melo9002/fusefire-proving-grounds/issues/26). Two pending callbacks could observe an empty player phase, yield, then both end a turn; the second ended an allied activation. A focused three-assertion regression failed before the fix. The continuation now rechecks battle result, phase, active actor and roster after the yield; the focused regression passes without relaxing revision or fingerprint checks. The real rescue replay follow-up is recorded below.

The first wounded regression draft used the wrong AI node path and aborted; that test fixture was corrected before reproducing the two intended failures. The first immediate-free height-test teardown emitted resource leaks; queued teardown with two frames is used by the clean subsequent runs. These diagnostic attempts remain in artifacts, not silently reclassified as successful checks.

## Verification

- Final combat tier: **30 PASS / 0 FAIL / 1 explicit-only metrics SKIP**, 143.41s; `artifacts/test-results/height-range-combat-final/20261116-212052-subsystem-combat/`.
- Final focused height/range: **55 checks / 0 failures**, including invalid-tuning playback rejection. The final query-purity assertion additionally checks RNG state.
- Rendered height/range: **52 checks / 0 failures**, with three inspected images from the actual ramp, stairs and deck. This run preceded the extra six nonvisual invalid-tuning assertions; it is not a claim of 58 rendered checks.
- Replay tier: **14 PASS / 2 FAIL / 0 SKIP**, 437.25s; `artifacts/test-results/height-range-replay/20261116-212528-subsystem-replay/`. The two actual defects were the Fleet completion stall and rescue continuation race above. The 48-case current mission/action/reconstruction matrix passed in this tier.
- After fixes, the unchanged complete Freight/Fleet saved-replay test passed, including Fleet **100/100 actions**. The unchanged rescue saved-replay test passed with **258/258 actions**, same Victory. These focused follow-ups do not retroactively make the earlier tier green.
- Wounded-AI regression: **6 checks / 0 failures**. Removal continuation regression: **0 failures**, preserving all three assertions.
- Final AI tier: **23 PASS / 0 FAIL / 1 explicit-only long-batch SKIP**, 342.76s; `artifacts/test-results/height-range-ai/20261116-213927-subsystem-ai/`. Includes determinism, unchanged stalemate deadlines and all six commander mission cases.
- After the menu addition, focused replay-file workflow and generation-retirement checks also passed. The retirement check deliberately exercises rejected old configurations.
- Final smoke: **11 PASS / 0 FAIL / 0 SKIP**, 48.59s; `artifacts/test-results/height-range-release-smoke/20261116-214644-smoke/`. Its current-generation regression selects the existing range, checks its one menu entry and test label, builds its normal configuration and initializes that exact map. Curated-site matrix scope remains unchanged. No full-project suite is claimed. Logs use `artifacts/height-range-*` and `artifacts/test-results/height-range-*`. The initial failing tier is preserved separately from passing follow-ups. Existing Windows certificate-store diagnostics are environmental; assertion and script errors are assessed separately.

## Try it

Start a **new match** or choose **Tactical Test Range — Test map** in Match Setup. The existing range is now selectable; its scene and map ID are unchanged, and its saved replays use the same menu acceptance list. Hover a shot: the existing preview now reports **Range penalty** and **Height**. Compare near/far shots, then change floors or use the ramp/stairs. Confirm that cover and LOS still block the same physical surfaces; high ground does not grant a shot through a slab. Moving clears Aim as before.

For repeatable checks and real range captures:

```powershell
godot_console --headless --path . --script res://tests/combat_height_range_test.gd
godot_console --path . --script res://tests/combat_height_range_test.gd -- capture artifacts/height-range-review
```

The graphics script uses the actual authored ramp, stair and deck points; its captions read the evaluated values. Inspect `ramp.png`, `stairs.png` and `deck.png`. The images are controlled review aids, not proof of a completed manual battle or polished animation. Shader work remains deferred.

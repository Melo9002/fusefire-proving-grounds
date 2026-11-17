# Combat milestone 04 — step 9: decision previews

Delivered 2026-11-17. [Everyday controls and testing](../combat-decision-previews.md). This is presentation/player-input work; combat numbers, authoritative actions, replay schema and simulation identity (`prototype-1.5-defense-direction-10`) remain unchanged.

## Result

- Direct hostile hover shows the existing firing line/nearest physical blocker, full authoritative chance calculation, fixed on-hit damage, AP/SP cost and remaining resources. Guaranteed/favorable/risky/poor labels and colors reinforce the numbers. Final bands: green 100; blue 70–99; orange 40–69; red 0–39; unavailable neutral gray. A geometric lane with unavailable AP/SP is gray, and distinct geometric/action restrictions remain explicit.
- Move hover uses one read-only destination-analysis result for text and outgoing lines. It shows directional protection, normal incoming chances/damage, outgoing chances/damage and post-move AP/SP restrictions. Outgoing Aim and destination Shield are canceled; the enemy's current Aim is included. Enemy Shield/ammo restrictions are identified. Guard is explicitly a possible in-route reaction with separate modifiers; these are conditional current-state facts, not a prediction of AI choices or every interruption.
- The translucent destination projection uses the **same UnitVisualAdapter, character/weapon assets, clip library, animation controller, IK and cover-context code** as the live unit. A render-only `preview_cell` selects destination idle/low/full-cover posture without creating a TacticalUnit, stats, occupancy or collision. Normal units leave that field unset. Clips play rather than freezing a mesh snapshot; changing stance does not mutate the soldier. A real Move's arrival animation is checked against its projected state. Carrying changes invalidate the cached render model.
- One-click Move remains the default. A large Cancel Move button clears planning with no spend. Optional movement confirmation freezes the chosen preview before the next hover frame; cancel returns to planning. Other new confirmations cover shots, Aim, Shield, Skip and a phase ending with unused AP. Guard keeps its existing confirmation step.
- Pause has independent remembered action-confirmation (default on) and movement-confirmation (default off) preferences in `user://battle_ux.cfg`. The modal pauses gameplay/camera, focuses a large Cancel control, guards duplicate approval and state revisions, and resolves actors/targets from stable IDs on approval. Scene teardown restores its pause. AI/replay bypass player dialogs. Test preferences use a process-specific workspace file; smoke explicitly selects one-click movement rather than depending on personal settings.

Hover analysis/lines/model are reused for unchanged actor/destination/revision. Cancel clears that cache so immediate reselection of the same destination works. The tactical panel was shifted beside the combat-history column to avoid their overlap. No new asset-authoring workflow, tactical animation authority, generator or manager was introduced.

## Verification

| Evidence | Result |
| --- | --- |
| Final focused decision-preview regression | **53 checks, 0 failures** |
| Combat subsystem | **34 pass, 0 fail, 1 explicit metrics skip**, 156.12s |
| UI subsystem | **25 pass, 0 fail, 1 explicit parcel capture skip**, 143.70s |
| Final smoke after shared animation change | **11 pass, 0 fail, 0 skip**, 49.81s |
| Shared tactical-pose / locomotion checks | **Both 0 failures** |
| Saved current-content playthrough/replay after animation change | **0 failures**, Freight 52 and Fleet 100 verified actions and matching recent-combat logs |
| Replay file workflow | **0 failures**, save/open/reconstruction/rewatch/input isolation |
| Final rendered regression | **58 checks, 0 failures**, five captures inspected |

Focused checks cover all band boundaries and 95%-can-miss wording; live HUD/line tint; AP/SP and stance interpretation; pure forecasts; elevated support placement; exact outgoing line origin; no hologram collisions/game actor; shared idle/low/full-cover animations and actual animation progress; unchanged live animation/state/RNG; immediate cancel/reselection/cache reuse; actual Move then Attack prediction agreement; dialog cancellation/double confirmation/staleness/removed target/scene teardown; camera pause; independent persistent preferences; and fast movement when its confirmation is disabled.

The broad combat/UI runs preceded the final requested shared-animation enhancement and targeted lifetime/readiness fixes. Those changes received the final focused/rendered checks, shared pose/locomotion checks, fresh smoke and saved-current-content replay. No fresh full-project/full AI/full replay subsystem claim is made for this UI-only batch. Final logs were checked for unexpected script/parse/compile/lambda errors; only the environment's existing root-certificate message remains.

Failure diagnosis: a removed-target test exposed a freed-node lambda capture despite safe action refusal; callbacks now capture stable IDs and resolve afresh. Godot resets dialog button minimums on popup/text updates; sizing is applied afterwards and asserted. The new no-AP color fixture initially wrote the read-only AP compatibility alias, so it never created unavailable AP; correcting the fixture's spent budget preserved the strict neutral-color assertion. No assertions were relaxed to obtain passing results.

Captures: `artifacts/decision-review/{aim-confirmation,shot-risky,destination-ghost,pause-confirmation-settings,move-confirmation}.png`. Dialog capture embeds subwindows inside the test viewport; native OS window chrome was not separately inspected. This is focused rendered review, not an exhaustive manual match verdict.

## Limits and next reference

The projection previews destination posture; the path describes travel. Full path/action choreography, final contact/IK polish and unrelated live-unit shader tuning remain future work. Multiple firing lines can be busy with larger rosters. Normal incoming forecasts do not promise AP timing, future enemy stance or a particular Guard outcome. Current blocker labels can still use cell coordinates.

**When the owner returns, ask for the GFL2 screenshot** to compare the projected-order interaction and Cancel/Confirm arrangement before more polish. This follow-up is also in the everyday guide; no scheduled reminder was created. Next milestone step: destructible-cover scope investigation, then balance and closure.

```powershell
godot_console --headless --path . --script res://tests/combat_decision_preview_test.gd
godot_console --path . --script res://tests/combat_decision_preview_test.gd -- capture artifacts/decision-review
.\tools\run_tests.ps1 subsystem -Subsystem combat
.\tools\run_tests.ps1 subsystem -Subsystem ui
.\tools\run_tests.ps1 smoke
```

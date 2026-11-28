# Carrying someone of another size, and up a ladder — animation engineering report (2026-11-27)

Branch `review/claude-carry-ladder`, baseline `c5a89a2` (the merged `main` at the start). Commits on top: `8a92140`, `cb0c5b0`, `89976ff`, `ad11d43`, `d0acbf0`, `265e882`, `6305437`, `90999e0`, `0b92129`, plus the final documentation/tooling commit (see the pull request for its hash). **Not merged. Tactical integration not started.**

## 1. What was asked, in one paragraph

Carrier and passenger each resolved with their own anatomy, profile and scale (Regular MIRA `mira_0`, Small MIRA `small_mira_0`, all four pairings, the passenger never resized); a loaded ladder presentation (approach, transfer onto a climbing-compatible back carry, climb with purposeful rung contacts, upper landing, ordinary carry restored, independent descent, dismount); independent selectors and manual use in the Exploration Playground; independent selection, a scenario and CLI/report support in the ADDA Workbench; clean lifecycle; measurement of the final pose; rendered review.

## 2. Limitations reproduced at the baseline

* A carried body was built from the **carrier's own** scene, scale and rig profile (`CharacterRig._ensure_passenger`). A MIRA could only carry a MIRA. Negative control kept in `passenger_identity_test` (`PassengerDefinition.from_rig` reproduces the coupled identity).
* The Playground refused a loaded mount (`can_mount`).
* The tactical loaded ladder was a fallback with no rung contacts, no transfer. Render: `images/carry-ladder/baseline_fallback.png` (Regular/Regular, `loaded_ladder_capture.gd … fallback=true`).

## 3. Decisions

* **Opt-in.** The loaded presentation starts only when a caller passes `loaded_presentation` (`begin_traversal`) or, in the exploration host, `begin_climb` while carrying. The tactical adapter does not, so its fallback, the 06.03B completion contract, legality, AP, navigation, occupancy, Guard timing and replay semantics are untouched. `traversal_loaded_carrier_test` is unchanged and passes.
* **Identity** is a small value, `PassengerDefinition` (character id, runtime rig scene, scale, rig profile), reusing the project's existing unit (the runtime rig scene). No registry, no character names in shared code (`humanoid_portability_test` still passes). Callers that name no passenger keep the old behaviour.
* **No new gameplay restriction** on either MIRA; any carrier carries any passenger.
* **A back carry for the climb**, not a shoulder carry: a body lying across shoulders cannot pass between the rails. The passenger rides upright on the carrier's back, back against back, limbs hanging along real gravity in its own frame.

## 4. Technique

* `PassengerFit.solve()` (ordinary carry) and `solve_ladder()` (climbing carry) search small discrete sets (tuck, knee bend, thigh lift, slide, grip fractions) against both bodies' measured geometry, once per pairing (cached). A carry of a body of the carrier's own kind is left as authored.
* `LoadedLadderCarry` + `LoadedClimbProfile`: a simulation-clock blend (0.9 s) moves the passenger from lying across the shoulders to the back carry; the climb is held until `loaded_ladder_ready()`, at the foot and at the head; the ordinary carry returns once across the lip (up) or near the floor (down).
* **Contact ownership while loaded on a ladder** (`apply_carry_targets`): supporting (left) hand keeps the passenger's thigh throughout; free (right) hand leaves the wrist and takes rungs, blended by the transfer and gated by whether the arm can reach the rung; legs/hips from the ordinary ladder pose; trunk lean, slung weapon and passenger belong to the carry. Nothing switches IK off.
* Lifecycle: `end_carry`, `_discard_passenger`, a changed passenger, interruptions, Reset casualty, Swap models all clear loaded-ladder state (tested: no orphan passenger, IK or claim).

## 5. How to use it

* **Playground**: open the Exploration Playground; the menu has *Carrier* and *Casualty* pickers, *Reset casualty*, *Swap models*, *Ladder foot* / *Ladder top* position buttons. Pick up the casualty, walk to the ladder, press **E** to mount (the ladder takes precedence over put-down), climb, dismount, approach from above, descend, put down.
* **Workbench**: `godot --path . res://tools/animation_workbench/pose_workbench.tscn -- --character=small_mira_0 --passenger=mira_0 --scenario=loaded_ladder` (the Character tab also has a passenger selector).
* **ADDA CLI**: `.\tools\adda.ps1 run -Scenario loaded_ladder -Character small_mira_0 -Passenger mira_0`. Reports and reproduction lines name the passenger.

## 6. Measurements (final pose, sampled at `skeleton_updated`; `tools/quality/loaded_ladder_probe.gd`)

Hand targets are bone/IK-target errors, **not** mesh penetration. Clearance is bone-segment sampling with a conservative 5 cm radius.

| Carrier carries | Dir | Free / support hand error | Feet max | Carrier chest step max | Min limb-to-ladder clearance |
|---|---|---|---|---|---|
| Regular → Regular | up | 0.0 / 0.0 cm | 4.0 cm | 13.3 cm | 5.7 cm |
| Regular → Regular | down | 0.0 / 0.0 | 0.0 | 19.1 | 5.9 |
| Regular → Small | up | 0.0 / 0.0 | 4.0 | 13.3 | 4.9 |
| Regular → Small | down | 0.0 / 0.0 | 0.0 | 19.1 | 5.2 |
| Small → Regular | up | 0.0 / 0.0 (max 0.6) | 3.1 | 27.7 | **−0.9 cm** (right toe end, 1.4 s) |
| Small → Regular | down | 0.0 / 0.0 (max 0.4) | 0.0 | 27.7 | 2.7 |
| Small → Small | up | 0.0 / 0.0 | 3.1 | 27.7 | 1.3 |
| Small → Small | down | 0.0 / 0.0 | 0.0 | 27.7 | 4.9 |

Transfer 0.90 s, ordinary carry restored in every run. Passenger step relative to the chest ≤ 3.3 cm (the body does not jump relative to the carrier). The carrier chest steps (13/19/28 cm) are **inherited from the unloaded landing** (the same steps without a passenger); they are not caused by the carry.

The one negative clearance (Small carrying Regular, going up, the passenger's right toe tip during the transfer at 1.4 s) means the toe-end segment sits inside the conservative 5 cm envelope of the rail/rung; a real overlap with the mesh was not measured. It is listed as a defect to look at, not claimed fixed.

## 7. Visual review (rendered, rendered Godot captures; contact sheets in `images/carry-ladder/`)

`carry_ordinary.png` (five angles per pairing), `ladder_up.png`, `ladder_down.png` (rear-quarter, seven/six times), `baseline_fallback.png`.

Observations (mine; not a substitute for the owner's eye, which is the real check):
* Ordinary mixed carries read as intended: Small passengers ride clear of the floor with legs drawn up; a Regular body on a Small carrier hangs low but the feet clear the floor and both hands hold the body.
* Loaded climb: the passenger transfers continuously onto the back and rides upright; in every pairing it is visibly on the carrier's back, not on the rails.
* Frames in the sheets for Small carriers are cropped at the bottom by the capture camera, not by the pose.
* Defects I can see: the passenger's arms hang loosely at the lip crossing (looks limp, not wrong); a Regular passenger on a Small carrier looks large and heavy on the back (true to scale); passenger hands are not given a purposeful pose; the hand/thigh contact looks plausible only from the rear quarter.
* Not verified by eye here: motion quality (stills only), the deck-lip moment from above.

## 8. Verification

New tests (all pass): `passenger_identity_test` 59 checks, `loaded_ladder_test` 38, `loaded_ladder_playground_test` 93, `workbench_passenger_test` 45. The animation tier: 91 pass, 2 fail — both pre-existing:
* **`ladder_landing_test` = #64**: four descents at ≈118–122 mm (capsule vs mesh), **identical on the baseline** (measured on the baseline worktree). #64 is **unchanged** by this work (not affected, not fixed).
* **`adapter_boundary_test`**: timing flake, 1/9 on the baseline and 0/6 alone (1 in the suite) on the branch; not attributed to this branch.
No assertion or threshold was weakened; `traversal_loaded_carrier_test`, `humanoid_portability_test` and the others pass unchanged.

## 9. Inherited issues seen, not fixed

* #68: pickup and release hand targets out of reach (mixed pairings within ≈10 cm for Small/Small). Inherited.
* Carrier chest steps at the ladder landing (above). Inherited.

## 10. Performance

`passenger_fit_timing.gd`: the fit is a one-time cost per pairing (cached). `ladder_presentation_timing.gd`: wall time per step in the headless dummy renderer was identical in both trees (≈6.9 ms standing / ≈14.4 ms climbing) with a loaded climb ≈ unloaded; as with #79 this probe cannot resolve small overheads, so no per-frame cost claim is made.

## 11. Tactical integration requirements (not started)

The adapter must pass the loaded flag; the movement presentation must hold the unit's translation for the transfer (≈0.9 s at each end, against the tactical transfer of ≈0.8 s), so the completion contract and Guard checkpoint timing need an owner decision first; an owner review of the look. No tactical legality, AP, navigation, occupancy or replay change is required or made.

## 12. Recommendations

1. Owner inspects all four pairings in the Playground and Workbench (steps in §5) and judges the motion.
2. Look at the Small→Regular transfer (toe tip near the rail at ≈1.4 s) and the limp passenger hands.
3. Decide tactical adoption and the transfer-time budget separately.
4. #64, #68 remain owner decisions.

## 13. Status by verification level, and what was not verified

| Level | State |
|---|---|
| Implemented | Yes: identity, mixed-size carry, loaded ladder (up and down), Playground and Workbench/ADDA support |
| Automated-tested | Yes: four new tests (59 / 38 / 93 / 45 checks, with negative controls for the coupled identity and the fallback); animation tier 91 pass, 2 fail (both also fail on the baseline) |
| Rendered-tested | **Stills only**, from the Workbench's rendered captures at fixed times, four pairings, up and down, several angles |
| Owner-approved | **No** |
| Merged | **No** |

Not verified, stated plainly:
* **Motion quality.** Nothing was watched at normal speed with real input; the transfer, the deck-lip crossing and the descent entry have been judged from stills and numbers only.
* **The real game path.** The Playground flow is covered by a scripted test (93 checks driving its interact/mount calls), not by a person pressing keys. No tactical-game run was made, because the tactical host does not use the new presentation.
* **Mesh intersections.** Clearance is bone-segment sampling with a 5 cm margin, not mesh measurement; visible intersections may exist that no number here would show.
* **Open defects, not iterated further:** the Small-carries-Regular toe tip at about 1.4 s (−0.9 cm against the margin) and the passenger's limp hands at the lip.
* **Regression scope.** Executed: the four new tests, the animation tier, `traversal_loaded_carrier_test`, `humanoid_portability_test`. Other tiers were not run, and no claim is made about them.

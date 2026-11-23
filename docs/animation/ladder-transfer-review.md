# Ladder transfer review

The previous local exploration changes moved the character away from the rungs at mount and replaced the tower teleport with a short landing walk. That still ended ladder contacts before starting the walk. The old nominal deck target came from a profile offset and could be out of reach. This pass feeds the shared rig the sandbox tower's actual upper edge. The geometry comes from the same box dimensions that build the tower.

The final ascent follows both the climbed height and the horizontal handoff. The planner keeps the previous rung foothold until the lead foot swings above the lip, plants the lead foot in deck coordinates, shifts the hips over that support, and moves the trailing foot across. The sandbox now has two visible solid brace posts above the landing. Their placement and support height come from the same dimensions as their collision boxes. The posts let the climber stay higher and clear the tower face. A low palm brace was reachable at the wrist but pulled the knees through the tower.

The trailing hand releases first as its shoulder moves away from the post. The arm targets follow the lowering and rising chest during rifle recovery. The same progression is sampled in reverse when using the ladder from its deck exit. Candidate braces are checked against the actual same-pass shoulder before the rig claims them. The traversal foot stage levels the sole as it approaches the deck, and landed knees can bend toward the body's forward reference while still checking rung clearance. The previous mid-flight ladder solver and its outward clearance preference still apply in the main climb.

The authored tactical link currently supplies a direction and waypoint but no verified brace patch. It continues using the existing pose and route. To enable this elsewhere, the host must establish a continuous, sufficiently wide and deep deck at the supplied edge, and provide the location of its actual braces. Unknown geometry or a lip offset outside the measured arm budget keeps the height-only path.

## Watch in Godot

From the project root, use the demo without diagnostic overlays. It plays ascent, the transfer, reverse entry, and descent through the real sandbox controller at normal speed. `front` looks into the ladder face from the approach, and the default is the side view.

```powershell
godot_console --path . --script res://tools/quality/ladder_transfer_demo.gd
godot_console --path . --script res://tools/quality/ladder_transfer_demo.gd -- small unarmed three-quarter
godot_console --path . --script res://tools/quality/ladder_transfer_demo.gd -- small front
godot_console --path . --script res://tools/quality/ladder_transfer_demo.gd -- legacy
```

The same rig, camera, and equipment can be used with `legacy` to compare the prior height-only pose and landing walk. Add `--fixed-fps 60` before `--script` to make frame sampling comparable, and `--write-movie artifacts/ladder-review.avi` to record. The optional user argument `sheet=<absolute png path>` writes five ascending samples. For manual sandbox testing, press **E** at the foot, hold **W**, and press **E** near the exit before holding **S**. The animation returns control after its horizontal phase.

Local moving evidence: [armed MIRA](../../artifacts/supported-mira.avi), [unarmed Small MIRA, three-quarter](../../artifacts/supported-small.avi), [unarmed MIRA, alternate angle](../../artifacts/supported-front.avi). Each recording covers 605 frames at 60 fps. The matched sampled frames were inspected for the earlier overhead-hand release and for the new rail-to-foot handoff.

## Measured comparison

At fixed 60 fps, the old pose sampled zero planned deck footprints or verified hand braces. The low-palm trial produced knee centres as far as 358 mm below the deck while inside its front plane on MIRA, and 222 mm on Small MIRA. The higher posts removed that intrusion in the knee-centre measurement. Holding both hands too late still caused reach rejection. During Small MIRA's lateral move onto the deck the far wrist was asked for up to 0.372 m from a 0.322 m arm. Releasing that hand earlier retained the lead-side brace.

| Rig and equipment | Frames with brace and deck foothold | Worst deck ankle error | Rejected planted braces | Knee centre intrusion |
| --- | ---: | ---: | ---: | ---: |
| MIRA armed | 14 | 5.04 mm | 0 | 0 mm |
| MIRA unarmed | 18 | 5.04 mm | 0 | 0 mm |
| Small MIRA armed | 13 | 4.67 mm | 0 | 0 mm |
| Small MIRA unarmed | 17 | 4.67 mm | 0 | 0 mm |

The scripted descent returned the same counts. The full-weight samples showed a measured hand or foot support throughout. This is an endpoint/centre check with approximate body clearance conventions. It cannot prove mesh clearance, pressure, sole grip, or naturally timed transitions. Interruptions during acquisition and release settled traversal, contacts and equipment in the demo with `interrupt-acquire` and `interrupt-release`.

On the ordinary climb, the wide knee silhouette remains. The fixed 60 fps ladder test passed all 51 checks, with a worst MIRA thigh overlap of 29 mm and a mean knee spread of 57.8 cm on ascent. The uncapped Ironclad run saw a 37 mm graze over the 35 mm tolerance. The same 37 mm failure was measured on the local baseline before this transfer. The controlled pass narrows the investigation to timing-sensitive clearance or sampling. It does not resolve the uncapped failure, and the tolerance is unchanged.

## Stair finding

The separate exploration action probe still reports roughly 45 mm peak planted ankle drift during the start of a lateral crossing while the ankle tracks the planner target. In the pure sideways control, the lateral stance target is fixed once the step owns the pose. This locates the remaining drift in target handoff or facing changes, with heel/toe roll as a separate along-tread motion. The current report does not split the drift into those two contributions. A useful next test is to record facing and planner weights alongside along-tread and across-tread target deltas, then compare a locked-heading acceleration with the same turn. This pass leaves stair behavior as it was.

## Final verification

- Catalog validation passed. All 27 smoke members plus import passed in 98.28 s in `artifacts/test-results/20261123-074027-smoke`.
- Final presentation authority and traversal replay passed in 50.15 s in `artifacts/test-results/20261123-074208-select`.
- The final exploration action run passed all 46 assertions, including the contact handoff and reverse entry; the pure traversal solver and animation boundaries passed. The uncapped ladder clearance failure described above is recorded in `artifacts/test-results/20261123-073828-select`. The controlled ladder rerun is in `artifacts/ladder-climb-fixed-60.log`.
- Hand contact and workbench diagnostics passed on the earlier transfer revision before the final sandbox support-post and contact-timing changes. The four final rig/equipment demo runs and the two interruption controls exercised the latest transfer. No full suite ran.

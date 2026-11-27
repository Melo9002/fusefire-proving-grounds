# Package 04 — Contextual combat presentation and the Depot playtest

Base `e47acf86f7f951438f6f495dff03855c5b0909ae` on `codex/asymmetric-line-of-fire`. The independent Package 03A checkpoint is `79d9c71ec85244737473c1cdb411d04e031196ef`. [03A certification](contextual-firing-03a.md) · [03B implementation](contextual-firing-03b.md) · [Previous readability and geometry work](intelligent-cover-and-contextual-firing.md).

## Human evidence

The owner won a two-versus-two Eliminate match and found the one-way exchanges unenjoyable even when they favored the player. The preserved [replay](evidence/contextual-04/Test.json) is a byte-identical copy of the original `Documents/Test.json`. SHA-256 `9c8ef9d75fbd5abd258ab8a6284ef365b98d964d6dc7144e492108bf80614f3d`. The original file stayed in place. Authority played all **80 records** to Victory on Service Depot, seed `407140976`. The terminal revision is 80. The recording selects **ordinary Service Depot**. Every resolved shot in the match used the direct posture, including both recorded Guard shots.

| Replay evidence | What the player experienced | Geometry evidence |
|---|---|---|
| Transaction 20, after revision 23 | Hostile 1 shot Bravo for 25 at 9%. The return lane was blocked. | The cargo truck hid four of Bravo’s five samples. The outward side sample cleared. Translating both endpoints to tile centers kept the result one-way. |
| Transaction 30, before revision 37 | Hostile 1 shot Alpha for 25 at 38% after Aim. At the later revision 41 board, both MIRAs had blocked or out-of-range outgoing lanes. | The container blocked Alpha’s return and left one exposed lateral sample. Alpha’s supported X offset was −25.15 cm. With centered endpoints the hostile ray also failed. Bravo’s lanes near the truck were separately blocked. |
| Move 53 and attacks 54–55, after revision 67 | Alpha reached the later advantageous position with 2 AP. She fired twice at 50%. | Alpha at `(15,0,31)` saw one lateral sample on Hostile 1 at `(16,0,25)`. The enemy’s X offset was +25.15 cm. With centered endpoints the outgoing lane closed. This matches the pattern in the screenshot. Hover choices themselves are outside the replay format. |
| Move 59, after revision 74 | Hostile 1 changed angle and opened a clean shot. | Both directions reached all five samples from centered supported positions. The alternative geometry rules preserve the open lanes. |

The direct shot origins are the recorded standing-point offsets plus standing height. Each direction draws rays from its own origin to the opposing body samples. The replay provides those simulated origins and selected samples. It provides no measurement of the original live rendered weapon transforms. The offset controls above translate the ray endpoints for diagnosis and are outside legal positioning.

### Diagnostic perception comparison

For the two hostile one-way lanes and the player’s later one-way lane, a head-height ray could see the opposing head in **both** directions. Adding only a head-height visibility gate would keep all three side-sample shots. Using the existing direct origin with only head/core as hittable targets closed all three shots. Requiring head-height sight as well as that head/core firing lane gave the same closures. The later clean engagement at revision 74 passed all variants. These are read-only comparisons at the exact replay positions. A broader comparison should include deliberate flanks, partial cover, other distances, and contextual shots where the sight line must be tested from the proposed firing posture. The five-point production rules and replay format are preserved.

### Guard observation for Package 05

At the start of transaction 19, the next two enemy checkpoints were out of range. Bravo’s first legal checkpoint, `(22,0,17)`, was **5%** after the usual Guard modifier. Guard spent 1 SP and its reservation and missed on a roll of 84.245. The final checkpoint, `(21,0,16)`, was blocked from Bravo, even if the reservation were still available. EnemyUnit1 then hit at 9% on a roll of 3.752. The current first-legal-checkpoint policy did exactly what it specifies. In this case holding would have conserved the reservation and SP. It would not have exposed a better checkpoint in this move. Whether Guard should decline poor opportunities belongs to Package 05. [Read-only replay diagnostic](evidence/contextual-04/replay_audit.gd).

## Predict before spending AP

In Move mode, hover a valid destination to see the ghost and route. Press **V** to pin it, then hover one known hostile to inspect the outgoing shot, hit chance, cost, remaining AP, obstruction, incoming threat and active Guard. Click the pinned tile to commit through the ordinary movement action. **V** unpins and **Cancel Move** exits. Hover-only Move and its usual click continue to work.

The inspector reuses the ordinary movement query, geometric evaluations, destination ghost and trajectory renderer. Hidden targets drop from the view. A valid shot can remain visible in the preview when the move spends the final AP. While pinned, a click on a different tile cannot silently spend AP on that different destination. The focused integration test checks the target line, cancellation, visibility, and unchanged tactical cell, revision and RNG during inspection.

## Presentation audit and changes

The opening enemy shot in the 03B normal-speed capture framed the threatened MIRA from behind. The enemy’s step happened beyond the foreground containers. The slide was synchronized to a uniform root easing, and the rifle began raising after the lateral adjustment. Target impact waited through the contextual recovery and return. Those cues made it harder to see who moved and when the hit occurred.

Package 04 keeps the existing presenter, foot IK, grip and raise-before-fire chain. The visual host shifts weight later in the outward step, placing the leading foot before starting the trailing foot. Rifle preparation overlaps the adjustment, and recovery overlaps the return. The impact and combat feedback are attached to the shot handle. Presentation still completes the return before the service proceeds to the next action or reaction.

The existing action camera frames the visible shooter from the stepping side with more space for the edge and the lane. It respects the current camera frequency and applies the existing obstruction fallbacks. In replay cinematic mode the camera reads the recorded contextual offset and aim point. The combat log adds “side-step shot” to committed Attack and Guard messages when that posture actually fired. [Presenter](../../presentation/tactical/tactical_action_presenter.gd) · [Rig adapter](../../presentation/tactical/tactical_character_adapter.gd) · [Camera](../../presentation/camera/tactical_camera.gd).

## Rendered and regression results

Paired 30 FPS movies showed a matched visible Depot side-step shot move from commit-to-fire in 42 frames to 32 frames (1.40 s to 1.07 s). Commit-to-presentation settlement moved from 103 to 80 frames (3.43 s to 2.67 s). Both used Combat Only with the standard combat camera. In the refined capture, impact and muzzle release landed on the same recorded frame for the enemy, player, and Guard. These are choreography timings for the recorded example. The capture uses a fixed simulation step and omits a hardware responsiveness claim.

The final authored-map capture passed 42 checks. Seven observed contextual releases across the captured runs included the primary four, two consecutive player attacks, and the normal-speed cinematic replay. All observed contextual rays remained clear from the rendered muzzle. Maximum errors in those captures were approximately 8.00 mm and 1.56° against the unchanged 20 mm and 2.5° limits. The repeated sequence also completed an ordinary direct shot after the contextual pair. The cinematic replay verified three of three recorded operations. The unchanged 2v2 showcase completed a real enemy turn and chose direct attacks in that opening. The duel demonstrates the voluntary contextual opening. The captures give whole-action motion and show the stepping side, supporting floor, obstacle, shooter and target; they are an engineering inspection rather than human sign-off.

The project import and initial six-test check passed. The final targeted selection passed 11 tests for contextual combat, movement HUD, Guard, camera, presenter lifecycle, weapon readiness, cover release and defensive replay. Three follow-up replay and HUD tests passed after the replay-camera adjustment. The full ordinary Ironclad suite and isolated performance benchmarking are outside this validation run. The Windows standalone engine logged a root certificate-store warning. The replay and movie processes still completed successfully.

[Enemy before and after](evidence/contextual-04/enemy-before-after.webp) · [Contextual Guard](evidence/contextual-04/contextual-guard.webp) · [Consecutive attacks and direct follow-up](evidence/contextual-04/two-side-steps-then-direct.webp) · [Opposite-side step](evidence/contextual-04/opposite-side.webp) · [Cinematic replay](evidence/contextual-04/cinematic-replay.webp) · [Depot Crossfire 2v2 opening](evidence/contextual-04/crossfire-opening.webp).

## Play and reproduce

The existing Depot Crossfire launcher still opens the 2v2 with genuine autonomous opposition. Add `-- duel` for the focused first engagement. Set the action camera to Combat Only to watch the contextual framing during ordinary attacks. Human playtest sign-off remains pending.

```powershell
godot_console --path . --script res://docs/quality/evidence/contextual-03b/play_crossfire.gd
$root = Join-Path $PWD "artifacts/contextual-04"
godot_console --headless --path . --fixed-fps 60 --script res://docs/quality/evidence/contextual-04/replay_audit.gd -- "$(Join-Path $PWD 'docs/quality/evidence/contextual-04/Test.json')"
godot_console --path . --rendering-method gl_compatibility --resolution 1280x720 --fixed-fps 30 --write-movie "$root/refined.avi" --script res://docs/quality/evidence/contextual-04/presentation_probe.gd
```

The rendered probe also supports `-- repeat`, `-- showcase` and `-- playback`. The playback mode uses the contextual clip saved by the standard probe under the same Godot user profile. Animation sequences run at normal simulation speed and are encoded at 30 FPS. Movie capture is evidence of motion and framing, independent of hardware performance benchmarking.

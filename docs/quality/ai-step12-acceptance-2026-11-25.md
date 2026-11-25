# AI 2.0 milestone acceptance review — Step 12

Review branch `codex/ai-step12-validation`. Integrated baseline `fb5815941702a2fced6ca97d9345ab089a005a19`, the Step 11 merge. Review and owner acceptance are separate. The prior [roadmap](../ai-2-plan.md), [behavior sheet](../ai-current-behavior.md), [difficulty evidence](ai-step10-difficulty-pacing-2026-11-24.md), and [profiling evidence](ai-step11-profiling-f3-2026-11-24.md) describe the individual contracts.

## Acceptance criteria

| Area | Acceptance evidence |
| --- | --- |
| Authority | AI queries and submits through the same service as the player. AP, SP, damage, occupancy, mission state and RNG remain authoritative. Replay reconstructs committed actions independently of the planner. |
| Decisions | Controlled fixtures demonstrate legal finishing, reliability, flank, Aim, Move then Attack, Reload, Shield and Guard, together with worthwhile holds and movement when viable. |
| Team and missions | Commitment expiry, destination/focus ownership, yielding when viable, alternate exits, blocked routes, defeated carriers, all eight mission families and no persistent technical stalls in completed configurations. |
| Policies | Shared rules across tiers, seeded combat lapses, mandatory mission routes protected from lapses, independent commander doctrine and situational movement profiles. |
| Inspection | Actual historical decisions, recorded squad context, linked receipts including mission decisions, bounded history, read-only navigation and legibility at 1280×720. |
| Responsiveness | Measured planner work, uninterrupted slices, wall latency, suspension and presentation; review using Step 11's 16.7 ms P95 work-slice target, 33.3 ms spike investigation threshold and 150 ms P95 decision-wall target. Desktop play remains a separate check. |

## Extraction handoff

[Issue #89](https://github.com/Melo9002/fusefire-proving-grounds/issues/89) reproduces on integrated main. Fleet Station, seed 17, Easy Rescue, 3v3 plus one ally. PlayerUnit2 extracts in transaction 76, revision 92 → 93. Roster removal selects PlayerUnit1 synchronously to preserve the same-phase selection in the committed extraction fingerprint. The previous presentation still owns the service. PlayerUnit1 reaches its first planning opportunity before release and sees temporarily busy queries. It then treats those as no useful options and submits a Wait rejected at revision 93.

The AI now gates planning on the actual service window and checks active-unit, scene, mode and pause state across the deferral. The original extraction, active-unit selection, transaction and replay boundaries are preserved. This is a pre-planning wait for authority, with no submitted action, retry, artificial resource spend or synthetic rejection. Work while suspended counts outside planner execution.

The first divergent AI publication is decision 79. In the baseline it is the rejected Wait; in the review it is the same legal Move to `(11, 0, 35)` that was formerly published as decision 80. Both runs finished in round 6 with the same victory, all 89 committed transactions and state revisions, identical per-round objective/HP/roster samples after removing wall time, and the same terminal simulation state signature. Decision count is 92 → 91 and rejections 1 → 0.

The regression holds the real extraction presenter at a signal after the commitment has selected the successor. It keeps the window open past the successor's activation delay, checks that no decision or transaction is published in that period, then releases presentation and checks the first successor receipt is a committed Move. An early fixture used a non-stoppable tile. The corrected fixture uses the known legal extraction cell in the existing range scenario and retains the movement assertion. Scene lifetime and departure replay checks exercise independent boundaries.

## Carrier routing

[Issue #4](https://github.com/Melo9002/fusefire-proving-grounds/issues/4) reproduces on integrated main. Service Depot Rescue, seed 16, Hard, 5v5 plus one ally. The carrier is PlayerUnit2 at transaction 40. The carrier's exit scan tries four searches from one unchanged origin; the fallback pathfinder rechecks the same swept-body edges against the same occupancy for separate destination queries.

Within that synchronous scan the live pathfinder now accepts a scratch edge-clearance dictionary shared by its endpoint queries. The scan never yields or mutates occupancy, and the scratch dies on return. The order, fallback, candidate selection and per-route revalidation stay the same. Friendly-yield geometry retains separate checks, since it admits a different set of bodies. The existing clearance regression compares reused and fresh paths across exits with a blocking body.

Same machine and engine as Step 11, AMD Ryzen 5 5500 with 12 logical processors, Godot 4.7.2, Windows, headless, one benchmark process at a time, simulator time scale 12. Times are main-thread elapsed with frame suspension and presentation reported separately. Each paired run supplied 189 settled action samples.

| Measurement | Integrated main | Review |
| --- | ---: | ---: |
| Transaction 40, carrier path stage | 188.99 ms | 97.51 ms |
| Transaction 40, planner work / slice / decision wall | 221.21 ms | 131.23 ms |
| Transaction 40, planner suspension | 0 ms | 0 ms |
| Transaction 40, authoritative action window including presentation | 22.57 ms | 26.28 ms |
| Whole match, mean planner work | 52.74 ms | 51.52 ms |
| Whole match, P95 longest work slice | 112.89 ms | 99.76 ms |
| Whole match, worst work slice | 221.21 ms | 165.17 ms |
| Whole match, P95 decision wall | 183.68 ms | 165.10 ms |
| Whole match, planner suspension total | 1,976.9 ms | 1,888.8 ms |

The four-query incident fell by 41% overall and carrier-stage elapsed fell by 48%. Across the match, 80 carrier route queries used 560.2 → 380.8 ms. Identical decision sequences, 192 committed actions and revisions, sampled progress, terminal signature, and round-12 defeat demonstrate behavior parity for the hotspot. The defeat is a mission outcome; the comparison concerns cost and parity. This one paired run measures the demonstrated case. It leaves hardware variance and rendering overhead open. The P95 wall and work-slice targets are still missed in this workload. The P99 wall sample rose from 243.76 to 258.86 ms; the carrier-specific improvement does not imply a uniformly better latency tail. A likely follow-up is to make the remaining expensive occupied-path search interruptible with revision checks, using this reproduction to show that route choices and recovery survive the change.

### Reproduce the paired observations

Run each command on the baseline and the review commit. Use a distinct tag for each run, and redirect console output to a separate log. Keep the same presentation mode, background load, and machine.

```powershell
godot_console --headless --path . --script res://tests/ai_baseline_report.gd -- tag=step12-handoff site=fleet_station mission=RESCUE seeds=17 players=3 enemies=3 difficulty=EASY profile-ai
godot_console --headless --path . --script res://tests/ai_baseline_report.gd -- tag=step12-carrier site=service_depot mission=RESCUE seeds=16 players=5 enemies=5 difficulty=HARD profile-ai
```

The local raw logs and analysis are under `artifacts/step12/`. Match JSON is under `artifacts/ai-baseline/step12-*`. These are ignored artifacts. `tools/quality/ai_baseline_summary.py` reads the trace and `--log` profile, and `tools/quality/ai_baseline_compare.py` compares decisions, outcomes and final signatures. The simulator signature covers phase, active actor, live roster cells/HP/AP and objectives. Replay tests separately verify authoritative fingerprints and relevant RNG state.

## Terminal decision history

The Normal mission batches on the handoff/routing commit revealed a separate diagnostic defect. Successful terminal interactions had an authoritative transaction but no selected historical decision. The old code waited for the interaction presentation before publishing the explanation. A mission-ending terminal can finish the battle and the simulator can dispose of it before that coroutine resumes.

The controller now publishes the legal terminal selection immediately before submission, allowing the existing outcome recorder to link the exact commit or rejection. The receipt records unchanged AP for a free interaction. An adjacent-terminal fixture asserts that the explanation and linked transaction exist at mission completion. This change leaves the terminal action, mission rules and replay schema alone.

The primary matrix also contains 14 unlinked Attack receipts. All were the final submitted action of their match. The authoritative receipt exists, while the simulator can dispose of the battle before a post-presentation explanation runs. The normal Attack history and its linked AP/SP outcome were checked in F3. A complete historical explanation for every terminal combat action remains an inspection limitation.

## Mission outcomes and traced behavior

The simulator uses both sides' AI and Default doctrine. Protect and Rescue include their configured additional ally, and Protect includes the VIP. These are mission and legality samples. Relative win rate is confounded by both sides sharing a tier, different squad sizes, and different seed coverage. Controlled policy and commander tests isolate those variables.

| Batch | Sites and settings | Completed | Victory / defeat | Decisions / commits | Wait / Guard |
| --- | --- | ---: | ---: | ---: | ---: |
| Normal | All three sites, all eight missions, seeds 16 and 17, 3v3 | 48/48 | 37 / 11 | 3,334 / 3,320 | 305 / 186 |
| Easy | All three sites, all eight missions, seed 17, 2v2 | 24/24 | 21 / 3 | 983 / 981 | 47 / 37 |
| Hard | All three sites, all eight missions, seed 16, 3v3 | 24/24 | 20 / 4 | 2,122 / 2,100 | 345 / 165 |
| Hard challenge | Depot seed 18, Rescue, Enemy Evacuation, Terminal and Extract, 5v5 | 4/4 | 4 / 0 | 434 / 424 | 18 / 23 |
| **Total** | Primary headless matrix | **100/100** | **82 / 18** | **6,873 / 6,825** | **715 / 411** |

The primary matrix has 575 total rounds. It logged zero rejected submissions and recorded zero stalls, timeouts, round limits or setup failures. The matrix counts observed AI-outcome receipts; some combat wrappers do not forward a rejection to that trace. There are nine direct move returns and 183 intervals with unchanged sampled objectives, alive counts and HP. Six Normal terminal cases ran before the terminal-history correction. Their later repeats are separate diagnostic evidence. The remaining Normal cases never submit a terminal action. The Easy, Hard, and challenge runs included the trace correction.

| Mission | Victory / defeat | What the checked outcome establishes |
| --- | ---: | --- |
| Eliminate | 10 / 2 | Both forces can approach and resolve firefights to a terminal result. |
| Protect | 9 / 3 | VIP presence and protection obligations persist through the battle. |
| Rescue | 11 / 2 | Casualty pickup, carrier and escort movement, and delivery can resolve. Failure has a terminal result. |
| Reach | 12 / 0 | The goal cell approach advances the objective on contact. |
| Survive | 8 / 4 | The squad can hold through the survival interval and use the subsequent exit. |
| Extract | 9 / 4 | Free extraction and roster loss resolve through the current required exits. |
| Enemy Evacuation | 10 / 3 | The runner can board legally, and defenders can intercept under suitable layouts and timing. |
| Interact Terminal | 13 / 0 | Adjacent legal choices result in a terminal transaction and objective completion. |

Reproduce the primary groups with the explicit simulator. Omit `profile-ai` for matching validation scope.

```powershell
godot_console --headless --path . --script res://tests/ai_baseline_report.gd -- tag=step12-normal difficulty=NORMAL seeds=16,17 players=3 enemies=3
godot_console --headless --path . --script res://tests/ai_baseline_report.gd -- tag=step12-easy difficulty=EASY seeds=17 players=2 enemies=2
godot_console --headless --path . --script res://tests/ai_baseline_report.gd -- tag=step12-hard difficulty=HARD seeds=16 players=3 enemies=3
godot_console --headless --path . --script res://tests/ai_baseline_report.gd -- tag=step12-challenge site=service_depot mission=RESCUE,ENEMY_EVACUATION,INTERACT_TERMINAL,EXTRACT difficulty=HARD seeds=18 players=5 enemies=5
```


### Tactical interpretation

- Normal seed-17 Freight Yard reached a successful intercept. Decision 38 sent PlayerUnit2 toward EnemyUnit2's projected exit lane, and the match ended in round 5 without an enemy Extract. Depot and Fleet Station also published specific approaches toward the projected exit lane. EnemyUnit2 still committed a legal exit in round 3 on each map. The trace proves the defenders attempted interception, and does not demonstrate that a stronger position was available earlier. All three Normal seed-16 evacuation matches ended in victory without an enemy Extract. In the supplemental Hard seed-17 repeats, Depot and Freight Yard each held the exit and won in round 7. Fleet Station recorded a legal escape in round 3. This reproduced the Step 10 3v3 Hard results. The primary 2v2 Easy batch uses different rosters.
- Normal Depot Rescue seed 16 shows two immediate carrier move reversals in the same activation. The first returned to a much safer position after an exposed move. The second, choices 79–80, gave up progress without a recorded cover or exposure improvement before returning to the same tile. The current fallback can accept locally negative steps when forward choices fail the safety filter. That exception also enables real detours and vertical approaches. This trace is concrete pacing evidence for a narrow follow-up on safe extra carrier moves. The carrier recovered and delivered the VIP in round 10, so this is a bounded inefficiency in the sampled case.
- The Wait and Guard totals measure published choices. Guard reserves a reaction and can consume AP today without spending ammo. Wait after the tested impossible corridor has a concrete obstruction reason and preserves the route for another unit. A round sample with unchanged HP or objectives can still include meaningful movement or defense. The simulator's stall classification separately tracks authoritative state change and wall time.
- Terminal succeeds with AP remaining and after the last movement AP. The six Normal original terminal receipts all committed. Three had zero AP before and after the transaction. Their initial missing decision links are the inspection defect described above, independent of mission completion.
- A controlled carrier corridor covers a legal recess, an impossible lane, an open alternate, two blockers, and carrier defeat with objective reopening. These scenarios establish causal recovery even if the complete mission matrix does not naturally trigger every setup.


## Regression, replay and rendered evidence

| Evidence | What it establishes |
| --- | --- |
| Controlled decisions | Finishing changes with predicted damage and reliability, healthy alternatives can outrank low-odds wounded targets, a flanking move beats an inferior lane, and useful Aim, Reload and Shield decisions compete under shared resource and legality queries. |
| Guard and Wait | Guard names a credible threat and links its AP commitment without charging reaction ammo. A blocked escort or carrier can select Wait with specific route evidence. |
| Mission coordination | Legal yielding and alternate exits preserve passage. An impossible corridor stays blocked. Defeat or objective completion releases claims, and graph/exit changes revalidate the existing route. |
| Policy and doctrine | Hard favors more reliable finishing and considers repositioning unavailable to Easy. Near-best lapses use their own RNG, stay within the allowed score band and are disabled for mandatory mission travel. Doctrine and movement profile composition are covered separately from the tier selector. |
| F3 and stability | Selecting historical rows preserves tactical revision, AP, SP and both RNG streams. The history stays bounded, retains the chosen alternative, and keeps historical reservations independent of live overlays. |
| Replay | Authoritative result assertions are separate from re-running the planner. Replay uses stored actions and revision/fingerprint evidence. |

Catalog validation was clean with 304 discovered and catalogued scripts. The initial focused group passed route clearance, scene lifetime and departure replay, and found the test-fixture placement error described above. The corrected AI decision scenario script subsequently passed all 243 checks in 38.71 seconds for the runner. The rendered F3 capture passed all 35 assertions at 1280×720 using OpenGL compatibility. The agent inspected the timeline capture, which showed actor, policy, action, targets and the authoritative AP/SP receipt legibly. The panel and captures were produced automatically; a human playthrough was outside this check.

The complete ordinary Ironclad suite ran with project import. It reported **259 passed, 9 failed and 37 explicit-only entries excluded** in 3,121.59 seconds. Import and all 27 smoke members passed inside that run. The 48-case current-site mission/replay test passed (228.07 seconds), as did full battle and rescue playback, departure, tactical authority, loaded-carrier traversal, and F3 decision visualization. The full-run result remains red as recorded. Focused reruns resolved eight of the nine failures, leaving the inherited ladder-landing failure.

The terminal action test passed in the full run. All seven corrected primary-matrix terminal receipts and six repeated Normal terminal receipts link to their selected decision before the state revision advances. Each shows zero AP spent. The six Normal repeats matched their original authority receipts, mission results and terminal state signatures. The observable change is the added selection and receipt link.

Two complete authored matches also ran twice each under the final code: Easy Fleet Station Rescue and Normal Freight Yard Enemy Evacuation, both seed 17 and 3v3. Their full decision dictionaries, outcome dictionaries, rounds, mission results and terminal simulation signatures matched. A direct observer of the action-service rejection signal reported zero submissions rejected across these four runs. Each first match was saved as JSON, parsed from disk and played through the actual replay player. Fleet verified all 110 replay events and Freight verified all 76. The count includes recorded phase/turn commands as well as unit transactions. No planner replay was needed. These controls and the 48-case replay matrix cover different claims: repeated autonomous choice behavior versus authoritative playback of committed evidence.

```powershell
godot_console --headless --path . --script res://tests/ai_baseline_report.gd -- tag=step12-terminal-final mission=INTERACT_TERMINAL difficulty=NORMAL seeds=16,17 players=3 enemies=3
godot_console --headless --path . --script res://tests/ai_baseline_report.gd -- tag=step12-evac-hard17 mission=ENEMY_EVACUATION difficulty=HARD seeds=17 players=3 enemies=3
godot_console --headless --path . --script res://artifacts/step12/repeat_and_replay.gd
```

The repeat driver and resulting `fleet-rescue.replay.json`, `freight-evacuation.replay.json`, and console log are local ignored artifacts in `artifacts/step12/`.

### Failure classification and controls

| Full-run entry | Classification and disposition |
| --- | --- |
| `adda_challenge_test`, `adda_cli_test`, `adda_report_compare_test`, `adda_workflow_test` | Environment-dependent failures from direct writes to `user://`. An isolated Windows profile probe verified the alternate user data path is writable. All four passed against the review source with a temporary roaming directory. |
| `debug_tools_smoke` | Inherited test-fixture mismatch from lazy F3 formatting. The integrated baseline reproduces both assertions. The corrected test exercises the real opened AI tab and preserves both text assertions. It passed. |
| `ladder_climb_test` | Unstable across these runs. One review run exceeded the armed-ascent penetration tolerance at 36 mm. The exact baseline and a review rerun passed. No animation source was changed, and this is no proof of the root cause. |
| `ladder_landing_test` | Inherited animation defect or unresolved constraint, outside Step 12. The exact starting commit and the review both failed the same four MIRA descent/landing assertions, including posts and rails, armed and unarmed. The review measured about 122 mm and the independent baseline about 118–122 mm. The test remained intact. |

The two later Workbench failures, `workbench_report_test` and `workbench_tune_test`, also attempted direct `user://` writes under the sandbox. They passed with the isolated profile in 12.65 seconds. This brings the total environment failures to six.

The integrated baseline controls used a source archive of the exact merge, independent `.godot` state and a writable temporary Windows user profile. They ran alongside the full campaign, so their durations are verification costs rather than performance comparisons. The three selected scripts plus import took 103.52 seconds. The six review reruns used an isolated copy with the review GDScript files and took 276.54 seconds, all passed. Logs are in `artifacts/step12/baseline-controls/` and `artifacts/step12/isolated-reruns/`. For targeted profile isolation, start a dedicated PowerShell process, create a temporary writable directory, and set `APPDATA` and `LOCALAPPDATA` to that directory only for the test process. The root certificate-store warning still appeared and does not account for the confirmed test failures.

### Rendered and owner acceptance

The 1× rendered Depot Rescue probe used the same Hard seed-16 5v5 scenario with the additional ally, OpenGL compatibility at 1280×720, a GeForce RTX 5060 and a 60 FPS cap. It sampled 4,226 process-frame intervals during the battle. The median was 16.67 ms and P95 was 16.80 ms. The PlayerUnit2 carrier motion again committed as transaction 40. Its planner slice was 120.48 ms, including 89.67 ms for carrier routes, with zero planner suspension. The frame interval near that commit was 135.96 ms. Its authoritative action/presentation window was 223.96 ms. These samples demonstrate that ordinary frames can coexist with noticeable stalls.

Two much longer frame intervals occurred near startup (1,122 ms at transaction 0) and while attack transaction 56 owned the action window (970 ms). The latter attack's planner work was 5.58 ms. This measurement cannot isolate the cause of either interval. Neither is credited to the carrier search. The profiler recorded 66 settled decisions and 23 activations in the rendering sample. Its P95 uninterrupted planning slice was 120.48 ms. The 75-second wall-clock cap was intentional and the match was ongoing at that point in round 3. This is a responsiveness probe outside the complete headless matrix.

The agent inspected the captured workload and F3 stills. There was no human-operated playthrough. [Rendered Depot sample](../../artifacts/step12/depot-rescue-rendered.png) · [1280×720 F3 timeline](../../artifacts/step12/f3/3-timeline-details.png). The repeat driver, rendering driver, raw logs and captures are ignored local artifacts.

```powershell
$path = (Resolve-Path artifacts/step12).Path
godot_console --path . --resolution 1280x720 --max-fps 60 --rendering-method gl_compatibility --log-file "$path/rendered-engine.log" --script res://artifacts/step12/rendered_probe.gd -- profile-ai
godot_console --path . --resolution 1280x720 --rendering-method gl_compatibility --log-file "$path/f3/engine.log" --script res://tests/ai_decision_visualization_test.gd -- capture "$path/f3"
```

Human acceptance checklist:

- Watch the departure of one Fleet Station Rescue unit and the successor's first move. The successor can be selected during extraction and should begin planning once the action presenter releases the window.
- In a 5v5 Depot Rescue, watch the carrier through the busy approach and extraction. Judge how the longest pauses feel at normal speed with overlays closed, then use F3 to inspect real choices and squad state.
- Confirm the timeline in a 1280×720 game window for Guard, Move, Attack and a mission action. Compare the recorded AP/SP receipt to the result. Inspect an older reservation after the live corridor has moved.
- Compare a representative evacuation and defensive hold with two commander doctrines. Judge the quality of the different intentions through their recorded choices.

### Review recommendation

**Conditionally ready for closure.** The validated AI authority, role behavior, coordination, determinism, policy composition and inspection are suitable for owner review. The paired carrier improvement preserves behavior and substantially reduces the reproduced cost. The dense case still misses the agreed single-slice and wall targets. Keep [#4](https://github.com/Melo9002/fusefire-proving-grounds/issues/4) open, and use the carrier reproduction and a normal-speed owner pass to decide whether that responsiveness gap is acceptable for this prototype. The normal-speed capture independently shows a carrier-associated 136 ms frame interval. If the measured budget is required for closure, the smallest remaining work is to preserve the exact occupied paths while breaking the synchronous search into revision-checked slices, then rerun the dense case and relevant replay checks.

[#89](https://github.com/Melo9002/fusefire-proving-grounds/issues/89) is addressed on this review branch. Short carrier reversals and the simulator teardown's unlinked terminal Attack receipts remain documented. The separately reproduced ladder-landing failure belongs to animation quality. No milestone or issue was closed as part of this review.

Implementation commits are `165bd902a7b13d7e8c07d6222f61e4199ad20953` for handoff and route clearance and `68509940349f1daadd9ed0f3009ed56e7aa6cace` for the terminal decision link. The F3 fixture correction is `55e7483267c07b93d4427db4148fd34befd40b02`. This report is on the same review branch. Milestone acceptance remains with the owner.

Post-milestone follow-up: [source-verified AI architecture and performance research](../ai-architecture/README.md) covers the integrated implementation and reproduces the remaining carrier planning hitch.

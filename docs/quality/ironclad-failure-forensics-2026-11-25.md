# Ironclad failure forensics

## Starting evidence

PR #90 merged at `d51d83c3b8ff8d4c1aca90c9f72293aeebdd77ea`. The QA branch starts from that merge and keeps the Step 12 branch at `4ab5bbe2211e899cf26b5262e3db64170d3873c0`. The older Step 12 comparison source was `fb5815941702a2fced6ca97d9345ab089a005a19`. The original artifacts live locally under `artifacts/step12/20261125-072007-full/`, with independent controls and isolated reruns in neighboring directories.

The reported results reconcile as **304 discovered, 304 catalogued, 37 explicit-only exclusions, 267 ordinary test processes, and one import process**. `project_parse` is present and passed. Of the 268 execution entries, 259 passed and nine failed, so the ordinary-test-only totals are **258 passed and nine failed**. The prior runner's `PASS` counted the import, and `SKIP` counted scripts excluded before execution. These are process totals. Each GDScript test owns its internal assertion count. The historical report and original artifacts are preserved.

## Pre-repair classification

All assertions below still protect useful behavior, except the original hidden-widget premise in the F3 fixture. Paths and line references point to the inspected source. For the original detailed errors, use the same-named `.log` in the full-run artifact directory.

| Test and assertion | Intended contract and original failure | Reproduction, baseline, cause and action |
| --- | --- | --- |
| `adda_challenge_test` | Nine of 43 failed. CH01/02/03/04 expected fault comparison findings, CH03 also failed disable/restore, the rescue contact experiment lacked both reports, CH05/06 lost the no-change controls, and CH07 lost its reproduction command. | Child Godot commands use `OS.execute` and inherit the Windows user-data path. Expected reports under `user://adda_challenge_test` could not be persisted, producing downstream comparison errors. The unchanged assertion set passed as one isolated rerun on the Step 12 review source. Keep it and isolate child data. |
| `adda_cli_test` | Four of 21 failed. Successful run exit, report announcement, exact repeat metrics, and armed/rig variants writing reports. | The command runs in a child process with report paths derived from `user://adda_cli_test`. A writable temporary profile restored the same commands and assertions in one review rerun. Environment failure inherited from runner setup. |
| `adda_report_compare_test` | “a report saves” and “and loads back with the same numbers” failed. A later negative-control writer got a null file handle. | The comparator math controls passed. The report round trip and malformed-file fixture write directly to `user://adda_test_*.json`. One unchanged isolated rerun passed. This is an environment failure. Keep the file I/O assertions. |
| `adda_workflow_test` | “the report exports” failed with save error 12. | The workflow reaches the report save path, which uses Godot file APIs. One unchanged isolated rerun passed with writable user data. Keep the actual export covered. |
| `workbench_report_test` | Named report directory and metadata, attached ADDA run, README, capture, tuning drafts, and free-play metadata failed after directory creation was denied. | `MomentReport.save` could not create report folders under `user://workbench_report_test`, then readers saw empty JSON. One unchanged isolated rerun passed. Preserve the end-to-end report contract. |
| `workbench_tune_test` | Draft persistence and re-open, deliberate Apply, editor heartbeat/request handling, clip copy and editor round trip failed, then loading returned a null scene. | Resource save/load uses the Workbench test's `user://` location. No draft existed to reopen. One unchanged isolated rerun passed. Keep the persistence and negative controls. |
| `debug_tools_smoke` | “F3 renders the active doctrine composition” and “F3 renders which movement profile shaped the decision” read a hidden label. | The exact older Step 12 baseline failed both. The Step 12 fixture opens the real F3 panel and checks the same two texts in the AI tab. In the same test the recorder and auto-battle assertions already establish history exists before opening. This was a fixture defect, corrected before this assignment. Verify the integrated fixture without changing F3. |
| `ladder_climb_test` | 51 assertions. One original armed MIRA ascent sampled approximately 36 mm knee overlap against 35 mm. All assertions inspect authored contact behavior on the final modified pose. | Older baseline passed one isolated sample and Step 12 review passed on rerun. [#78](https://github.com/Melo9002/fusefire-proving-grounds/issues/78) records 3 failures in 4 older attempts. A fresh realtime sample on the integrated merge reached the same assertion on unarmed ascent, rounding to 35 mm. The test manually advances height in 4 cm increments while the rig evolves through two variable-duration process frames between samples. A fixed-step comparison is the control for timing dependence. Keep the tolerance and measure the final joints. |
| `ladder_landing_test` | Four MIRA descent scenarios (armed/unarmed, posts/extended rails) exceeded the 110 mm limb-envelope ratchet at approximately 122 mm. | Exact older baseline independently reproduced the same four at 117.7–122.2 mm. Its skinned-vertex diagnostic also found 20.2–21.9 mm inside bars, including rung 10 during swing around phase 0.57–0.65. The larger figure is diagnostic joint-volume penetration, not physical collision travel or a literal mesh depth. The discrete mesh samples independently show real overlap against the fixture geometry. Keep the failing test. Track the descent pose in [#64](https://github.com/Melo9002/fusefire-proving-grounds/issues/64). |

### Measurement boundary

`LadderClearance` collects final modified bone poses at the skeleton update. Its joint envelopes approximate body size and its skinned-vertex diagnostic samples points inside the authored ladder's bars. Neither represents a gameplay physics capsule collision test. The fixture defines the ladder via `LadderGeometry` and the described landing via `LadderLanding`, so this finding establishes a pose/clearance defect on those fixtures. The generated rung is a box. The diagnostic path uses the corresponding rung axis and circular distance, with rounded end caps, so the overlap measures have distinct boundaries. Quantitative equivalence to all authored gameplay meshes, and triangle intersection, remain unverified.

### Reproduction paths

Historical logs: `artifacts/step12/20261125-072007-full/`, `artifacts/step12/baseline-controls/20261125-075440-select/`, and `artifacts/step12/isolated-reruns/`. Fresh controls: `artifacts/ironclad-qa/pre-*`.

```powershell
godot_console --headless --path . --script res://tests/ladder_climb_test.gd
godot_console --headless --fixed-fps 60 --path . --script res://tests/ladder_climb_test.gd
godot_console --headless --path . --script res://tests/ladder_landing_test.gd
.\tools\run_tests.ps1 select -Test adda_challenge_test,adda_cli_test,adda_report_compare_test,adda_workflow_test,workbench_report_test,workbench_tune_test,debug_tools_smoke -SkipImport
```

The pre-repair writable control supplies a fresh directory to `APPDATA` and `LOCALAPPDATA` in the invoking PowerShell only. The historical default path was unwritable in the managed sandbox; the user's ordinary Windows profile is not presumed broken.

## Controlled climb and Windows results

The integrated pre-change source passed all three fixed-60 Hz climb attempts and failed one of three unrestricted attempts. The unrestricted failure was the unarmed ascent at the displayed 35 mm boundary. The original Step 12 failure was the armed ascent. On the fixed runs the reported armed-ascent maxima were identical at 33 mm (knee), 22 mm (shin) and 17 mm (thigh). The fixed launches retained 51 assertions and the 35 mm ratchet. The different outcomes with the same source, geometry, heights and profile isolate frame timing as a contributor to the unstable validity check. They do not establish that all realtime trajectories meet the threshold. The catalog now supplies the fixed engine clock for this test only, and direct realtime reproduction remains available under [#78](https://github.com/Melo9002/fusefire-proving-grounds/issues/78).

The pre-repair controlled selection ran all six file-writing tests and the integrated F3 fixture unchanged under a writable temporary profile. All seven passed in 271.10 seconds. This separates permissions and the inherited F3 fixture correction from product behavior. The integrated landing test still failed the four descent assertions, with 121.4–122.2 mm in the limb envelope and 21.0–21.7 mm from the sampled skinned-vertex diagnostic. No animation source or penetration threshold was changed. The fresh failure output is in `artifacts/ironclad-qa/pre-landing.log`.

A second diagnostic compared fresh final skinned vertices against the actual local bounds of each oriented rung BoxMesh. The maximum sampled depth inside the nearest box face on the four MIRA descents was **21.093–21.768 mm** across phases 0.5868–0.6543. The per-case values were 21.768 mm armed/posts, 21.526 mm armed/rails, 21.476 mm unarmed/posts and 21.093 mm unarmed/rails. The diagnostic used 42–44 fresh skeleton frames per case. This confirms penetration of the generated visual rung volume independently of the rounded-axis approximation. It does not establish penetration on every ladder mesh or measure the gameplay collider. The probe and full output are preserved locally as `artifacts/ironclad-qa/ladder_box_probe.gd` and `artifacts/ironclad-qa/ladder-box.log`. No new animation gate was added.

## Runner audit and changes

| Boundary | Audit result and correction |
| --- | --- |
| Discovery, catalog and selection | Top-level `tests/*.gd` is the discovery contract. Existing selection deduplicates named tests and preserves FAST, SMOKE, subsystem, explicit-only and changed-path mappings. The selector fixture still checks bad Git refs, corrupt indexes, docs-only changes, both rename paths, exclusions and omitted long tests. Catalog checks additionally validate execution requirement, boolean tier flags and fixed-clock metadata. A run with catalog problems cannot conclude GREEN. |
| Import | Import has a separate outcome and cache stamp. A failing import now blocks dependent tests and clears the old stamp. Automatic selection checks for the class cache itself and common imported asset types. The runner catches explicit script/parse/compile errors even when Godot exits zero. An editor import is not a replacement for running each script; an unattached script can exist without being compiled during the editor scan. |
| Process ownership | Each Windows entry, including import and probes, gets a unique writable profile inherited by its subprocesses. The runner retains failed profiles and raw stdout/stderr, and removes its successful profiles. The parent shell and production profile remain untouched. A checkout lock guards shared `.godot` state. The timeout watchdog stops the owned process tree, and interrupted runs retain an INCOMPLETE checkpoint. |
| Reporting | Schema 2 splits ordinary selection, actual starts, completed tests, fail, timeout, blocked or unstarted, import and probe entries. Existing JSON count aliases remain available. The comparison tool reads original and follow-up JSON independently and never changes a full verdict. Reruns require an explicit invocation and classification of cause remains an engineering judgment. |
| Durations | Raw records retain per-entry monotonic elapsed time and the runner totals retain process time and overhead. The checked-in timing table is from November 20 and includes up to a second of old polling granularity. It is a selection hint rather than a new benchmark. The full verification and auxiliary tiers use separate caches and overlap in wall time, so their durations are observations rather than controlled speed comparisons. |

The fixture regression uses the real Godot executable on a disposable project. It exercises successful `user://` writes and isolation, assertion failure and retained stderr, exit 17, zero-exit script failure, a timeout, explicit selection, cache reuse and a missing-cache reimport, import failure, a checkout lock, cooperative interruption with live child cleanup, a missing executable, invalid and missing metadata, and original-vs-rerun accounting. The existing selector regression passed all eight controls. No fixture failure was rewritten as a successful result.

```powershell
pwsh -NoProfile -File tools/quality/ironclad_selection_test.ps1
pwsh -NoProfile -File tools/quality/ironclad_runtime_test.ps1
.\tools\run_tests.ps1 check
.\tools\run_tests.ps1 full -Import
.\tools\quality\ironclad_compare_runs.ps1 -Initial <original-results.json> -Rerun <rerun-results.json> -Baseline <baseline-results.json>
```

## Clean-checkout resource scanner finding

The FAST run on a fresh source archive exposed an additional inherited fixture defect. `resource_references_test` reported three broken directory references to generated output under `artifacts/ai-baseline/`, `artifacts/combat-examples/` and `artifacts/cover-direction/`. The source creates those destinations when the corresponding simulator or rendered capture actually runs. Step 12's working checkout already contained them. The clean copy used the integrated baseline test unchanged, so this is an environment-sensitive fixture failure rather than a missing game resource.

The existing assertion is valid for inputs. Its implementation checked trailing-slash paths before applying the existing `RUNTIME_PREFIXES` exclusion. Apply the same runtime-prefix rule first so it covers both files and directories. The corrected scanner passed in the same clean archive (1.20 seconds). A deliberately missing `res://tests/` directory still produced exit 1 while a deliberately missing `res://artifacts/` directory did not appear in the failure (1.07 seconds). The controls used a restored scratch copy and preserved both result records under `artifacts/ironclad-qa/resource-controls/`.

## Final verification

Runs used PowerShell and official Godot 4.7.2 on Windows. Fresh-checkout controls and FAST ran in a source archive with its own import cache. The full campaign ran in the dedicated review checkout. Test durations include process startup and execution, and the auxiliary runs overlapped the full campaign. Godot emitted certificate-store warnings under the managed profile in some captures. The file writing, parser failure and exit-status controls established their own outcomes independently of that warning.

| Run | Completed ordinary tests | Import | Wall time | Evidence directory |
| --- | --- | --- | ---: | --- |
| Catalog and runner self-tests | 304/304 catalogued, eight selector controls and 29 runtime checks passed | Disposable project import success and deliberately broken import verified | — | `tools/quality/ironclad_selection_test.ps1` and `tools/quality/ironclad_runtime_test.ps1` |
| SMOKE | 27 passed | Passed | 141.17 s | `verification/20261125-114350855-ce3a2752-smoke/` |
| Previously failed group | Eight passed, one failed | Reused cache | 322.48 s | `verification/20261125-114612283-ce813254-select/` |
| Animation and UI, presentation-sync/lifecycle | 38 passed, one failed | Reused cache | 569.11 s | `verification/20261125-115134997-408d0fe4-subsystem-animation+ui/` |
| Initial clean-source FAST | 106 passed, one resource-scanner failure | Reused cache | 346.88 s | `verification/20261125-120104329-404d8b87-fast/` |
| Corrected clean-source FAST | 107 passed | Reused cache | 349.50 s | `verification/20261125-120953638-2d0a8210-fast/` |
| Complete ordinary suite | **266 passed, one failed** | Passed | 3,155.00 s | `full/20261125-114337606-69373570-full/` |

Evidence directories above are relative to `artifacts/ironclad-qa/`. Each run retains `results.json`, `summary.txt`, per-entry stdout, stderr, engine, and combined logs. The failure-handling probe run deliberately returned exit 1 with one ordinary pass, two probe failures and one probe timeout. The startup probe ran five no-op launches, 0.31 s median, in 1.69 s total. Those probe processes are separate from the ordinary test totals.

**Full verdict is RED, exit 1.** The run discovered and catalogued 304 scripts, excluded 37 explicit-only scripts, and selected, started and completed all 267 ordinary tests. One import also started and passed in 18.49 seconds, for 268 Godot processes. There were zero timeouts, blocked or unstarted selections, and automatic retries. All 267 names match the historical run without duplicate execution. Godot processes took 3,145.91 seconds and runner/reporting accounted for 9.09 seconds. The three longest ordinary processes were the mission replay matrix (229.24 s), Bulwark replay (151.13 s), and the ADDA challenge (149.81 s).

The only distinct failure after controlled reruns was `ladder_landing_test`. It exited 1 and retained its Windows profile and logs. It reported the same four MIRA cases out of 216 checks. All six Windows file-writing cases, the opened F3 fixture, and fixed-step climb passed in both the focused selection and full run. The comparison in `artifacts/ironclad-qa/step12-comparison.json` retains the original Step 12 RED verdict, records eight clean follow-ups and one reproduced failure, and includes the older baseline observations. The 37 explicit-only scripts were outside full, and this campaign used headless Godot. The ladder diagnosis used final skinned geometry and has no new manual rendering claim.

The full runner launched while HEAD still identified the integrated baseline. It already used the runner and catalog content in `df1f747`. After the independently verified scanner correction, the full run reached `resource_references_test` and executed the same corrected fixture as FAST (`8d8c279`, 10.02 seconds in full). The fixture owns its own scan and other tests do not depend on it. Production code and the import inputs were identical throughout. The comparison tool follow-up is `a6cdca6`.

## Integration recommendation

Review and integrate `codex/ironclad-qa-reliability` as QA infrastructure. Expect the full ordinary gate to remain RED until the product defect in [#64](https://github.com/Melo9002/fusefire-proving-grounds/issues/64) is repaired in a separate animation change. Keep the existing gate and fixture evidence for that repair. [#78](https://github.com/Melo9002/fusefire-proving-grounds/issues/78) retains the unrestricted realtime variability. [#91](https://github.com/Melo9002/fusefire-proving-grounds/issues/91) tracks the QA review.

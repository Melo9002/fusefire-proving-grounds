# Project backlog audit — 2026-11-16

Live status belongs to [GitHub backlog #1](https://github.com/Melo9002/fusefire-proving-grounds/issues/1). This file records the audit snapshot; it is not a second task-status database.

## Scope and evidence

Baseline: `a7d79ddb944dbd98992833984f5c233c47d9a64c`. The six pre-existing Kenney colormap import edits were left untouched and are outside this audit.

- Inventoried **2,033 tracked files**. Scanned literal `res://` references across **438 tracked text resources/scripts/shaders**. The three absent candidates were temporary calibration, semantics and replay files intentionally written by tests; no missing literal runtime resource was found. This scan does not resolve dynamically constructed paths or validate every imported model.
- Read the current architecture and everyday guides, combat plan/current rules, animation/standing-point limits and recent quality records. Reviewed focused ownership and data flow in generation/editor, grid/pathfinding, combat/Shield, AI/simulation, objectives/results, camera/animation, replay, UI, CI and export configuration.
- Fresh Ironclad smoke: **11 PASS / 0 FAIL / 0 SKIP**, **50.10s**, logs at `artifacts/test-results/backlog-audit-smoke/20261116-205454-smoke/`.
- Fresh headless camera probe: an unrelated aperture started at strength **0.75**, then a camera under another parent changed it to **0.0** through the global group. Probe and log: `artifacts/backlog-camera-isolation-probe.gd` / `.log`. This confirms #2; it is not a claim that every rewatch shows visible corruption.
- The contradictory completed/timeout report is present in the earlier recorded AI run and its control flow is still present in source. It was not reproduced with a new expensive match during this audit.
- GitHub issue search returned no existing issues before publication. Created **23 actionable issues plus one index**, with type, priority, evidence, first step, acceptance criteria and immutable baseline source links. No friend was assigned, invited or contacted.
- Gameplay, assets, shaders, tuning, tests, CI configuration and export behavior were not changed. This was an inventory/source review plus smoke/probe verification, not exhaustive line-by-line verification, a full suite, exported-build test or new manual battle.

The previous rollout's 142-pass/5-fail full result and passing focused follow-ups are preserved in [its report](surface-rollout-2026-11-16.md). They are not relabeled as a fresh all-green broad run. The 88-headless/94-rendered cover checks belong to [the preceding cover follow-up](combat-cover-flanking-2026-11-16.md), not this audit. Existing Windows certificate-store diagnostics were distinguished from test assertions.

## Published tasks

| Issue | Work | Classification |
| --- | --- | --- |
| [#2](https://github.com/Melo9002/fusefire-proving-grounds/issues/2) | Scope tactical camera apertures to the owning battle | Bug |
| [#3](https://github.com/Melo9002/fusefire-proving-grounds/issues/3) | Make AI simulation completion and timeout diagnostics agree | Bug |
| [#4](https://github.com/Melo9002/fusefire-proving-grounds/issues/4) | Profile and reduce AI turn stalls with supported standing points | Performance investigation |
| [#5](https://github.com/Melo9002/fusefire-proving-grounds/issues/5) | Validate complete rescue and objective-driven AI matches on current sites | Validation gap |
| [#6](https://github.com/Melo9002/fusefire-proving-grounds/issues/6) | Review Shield facing and arcs against within-cell standing positions | Research / decision |
| [#7](https://github.com/Melo9002/fusefire-proving-grounds/issues/7) | Future: support rounded objects with automatic curved tactical boundaries | Planned future work |
| [#8](https://github.com/Melo9002/fusefire-proving-grounds/issues/8) | Handle demonstrated doorway and concave-mesh boundary mismatches automatically | Known limitation |
| [#9](https://github.com/Melo9002/fusefire-proving-grounds/issues/9) | Detect or refresh baked mesh boundaries after an asset model changes | Known limitation |
| [#10](https://github.com/Melo9002/fusefire-proving-grounds/issues/10) | Fit authored cover poses to real contacts without changing tactical position | Planned work |
| [#11](https://github.com/Melo9002/fusefire-proving-grounds/issues/11) | Decide and validate tactical corner peeking before giving lean animations a new firing origin | Research / decision |
| [#12](https://github.com/Melo9002/fusefire-proving-grounds/issues/12) | Polish selected-unit and occlusion shader dithering later | Known visual limitation |
| [#13](https://github.com/Melo9002/fusefire-proving-grounds/issues/13) | Combat 04 steps 6–7: implement editable range, height and Aim accuracy tuning | Planned work |
| [#14](https://github.com/Melo9002/fusefire-proving-grounds/issues/14) | Combat 04 step 8: make Guard, Aim and Shield triggers and expiry understandable | Planned work |
| [#15](https://github.com/Melo9002/fusefire-proving-grounds/issues/15) | Combat 04 step 9: show the authoritative hit-chance breakdown and readable blockers | Planned work |
| [#16](https://github.com/Melo9002/fusefire-proving-grounds/issues/16) | Give squad cards distinct readable identities instead of the shared BEAN heading | UX polish |
| [#17](https://github.com/Melo9002/fusefire-proving-grounds/issues/17) | Make local-parcel replay sharing self-explanatory and decide portable content packaging | Known limitation |
| [#18](https://github.com/Melo9002/fusefire-proving-grounds/issues/18) | Review visibility of unselected squad members behind buildings | UX investigation |
| [#19](https://github.com/Melo9002/fusefire-proving-grounds/issues/19) | Record a fresh fully green broad baseline after the standing-point rollout | Validation gap |
| [#20](https://github.com/Melo9002/fusefire-proving-grounds/issues/20) | Add targeted CI protection for cover, standing points and replay beyond smoke | Validation gap |
| [#21](https://github.com/Melo9002/fusefire-proving-grounds/issues/21) | Refresh the contributor quick start to reflect the three current sites and backlog | Documentation |
| [#22](https://github.com/Melo9002/fusefire-proving-grounds/issues/22) | Validate a clean Windows export and collaborator-machine workflow | Validation gap |
| [#23](https://github.com/Melo9002/fusefire-proving-grounds/issues/23) | Combat 04 step 10: decide the scope of destructible cover | Research / decision |
| [#24](https://github.com/Melo9002/fusefire-proving-grounds/issues/24) | Combat 04 steps 11–12: tune reliability and close on real current maps | Planned validation and tuning |

## Recommended order and contribution scope

Start with camera ownership (#2) and consistent simulator diagnostics (#3). Schedule the recorded broad baseline (#19), and continue combat at range/height/Aim (#13). Profile AI cost (#4) before choosing buffering or a new scheduling design. The Shield direction representation (#6) needs a controlled example and an explicit rule decision, not an unsupported claim that every Shield shot is broken.

Smaller contributor entry points are #21 (onboarding), #16 (distinct squad headings), and #3 (simulator diagnostics). Follow the existing [contribution policy](../../CONTRIBUTING.md), use a focused branch/PR and coordinate scope with the owner. No assignments or deadlines were added.

The owner's additional request for **future rounded-object support** is #7. Preserve automatic asset placement and logical tile identity; test upright/horizontal tanks, body sweeps, cover and LOS together. Do not replace it with routine manual hull fitting. Concave openings (#8), pose fitting (#10), tactical peeking (#11) and deferred shader work (#12) have separate scopes.

## Historical reports deliberately not reopened

Current source/checks already address editor-to-battle camera activation, the parking-paint removal of unrelated population, save-dialog input leakage, irrelevant terminal result labels, replay save/open, hidden population reservations, combined parcel preview and cover/exposure double counting. New reproductions can reopen investigation, but old screenshots alone are not current bug evidence.

Generation 2 and the three-site world-surroundings milestone remain at their documented prototype completion boundary. Exact asset geometry, every possible camera/seed/mission, exported packaging and full autonomous mission competence are separate limitations or validation tasks. Later master-roadmap features are not mislabeled as defects in the currently playable prototype.

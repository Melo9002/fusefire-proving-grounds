# Documents written by Claude

This folder holds the documents Claude wrote, kept apart from the ones Codex wrote in `docs/` and `docs/quality/` so the two are not confused. New Claude documents go here. All documents in the project may be used and referenced from here, and from them.

## In this folder

| Document | What it is |
| --- | --- |
| [Procedural animation layer](animation-procedural-layer.md) | The cover crouch, kneel and weapon-grip approach, how it was measured and checked, its limits and the ordered next steps. |
| [AI decision pipeline](ai-decision-pipeline.md) | How one AI decision flows from the battle to a committed action and who owns each stage (milestone 05 step 4). |
| [AI baseline, step 2](ai-baseline-2026-11-18.md) | The 48-match baseline: metrics, classifications, planning time. |
| [AI controlled scenarios, step 3](ai-scenarios-2026-11-18.md) | Fixed decision scenarios with legal options and reasoned expectations. |
| [AI pipeline verification, step 4](ai-pipeline-2026-11-18.md) | Proof that the typed records changed no decision, the tests and the failures found. |
| [Mission outcome fixes](mission-outcomes-2026-11-18.md) | Issues #39 (Extract wipe), #40 (carrier loss strands the VIP) and #41 (Enemy Evacuation seed 17): causes, rules, proof. |
| [Issue sweep](issue-sweep-2026-11-18.md) | The small issues settled in one pass: #2, #3, #16, #21, #31, #44, with evidence and what was left alone. |
| [AI step 6 results](ai-step6-results-2026-11-18.md) | What shipped (typed plans, kill-probability finishing, Move then Attack), the baseline effect, shot-quality measurements and the limits. |
| [AI step 6 design](ai-step6-design-2026-11-18.md) | Audit and design for scoring the actual proposed action: what is already done, the gaps, and the slices. |
| [Unit classes brainstorm](unit-classes-brainstorm-2026-11-18.md) | The Bulwark and Skirmisher as shipped, the weapon damage multiplier, the AI-versus-AI balance trials, the Shield and AI changes, and future class ideas. |
| [AI step 7 design](ai-step7-design-2026-11-18.md) | Audit and design for named movement profiles: where preferences live today, the layered profile model, the selection rules and the slices. |
| [AI step 7 results](ai-step7-results-2026-11-18.md) | What shipped (editable movement profiles and their selection rules), the identical-behaviour proof for slice A, the measured effect of the stances, tests, failures and limits. |
| [Hand contact diagnostics](hand-contact-diagnostics-2026-11-18.md) | The pose workbench overlay and readout for hand-to-weapon contact: keys, colours, what is direct and what is approximate, why only the post-update sample is final, and the baseline JSON. |
| [Weapon pose modifier](weapon-pose-modifier-2026-11-18.md) | Same-pass weapon target generation (CoverCrouch, WeaponPose, WeaponArmIK, HandGrip), the reach-aware support protraction and its limits, results and known costs. |
| [AI hard constraints, step 5](ai-constraints-2026-11-18.md) | Where legality is enforced, named blockers and shared-query reasons, explicit squad vetoes, and the 48-match proof. |

## Project documents these build on

- [Milestone 05 plan](../ai-2-plan.md) and [current AI behavior](../ai-current-behavior.md)
- [AI audit](../quality/ai-audit-2026-11-17.md) and [AI repairs](../quality/ai-repairs-2026-11-17.md)
- [F3 battle inspection](../debug-inspection.md)
- [Project Ironclad](../quality/project-ironclad.md)
- [Animation editing guide](../animation-editing-guide.md) and [asset edges and hybrid animation](../asset-edge-placement.md)
- [Simulation](../simulation.md) and [Replay](../replay.md)
| [weapon-readiness-2026-11-19.md](weapon-readiness-2026-11-19.md) | Weapon readiness model and raise-align-fire attack sequencing (animation improvement 04). |
| [upper-body-investigation-2026-11-19.md](upper-body-investigation-2026-11-19.md) | Upper-body coordination investigation: recoil drift cause, elbow and eye findings, experiment comparison (animation improvement 05). |
| [torso-weapon-frame-and-elbow-2026-11-19.md](torso-weapon-frame-and-elbow-2026-11-19.md) | Torso-relative weapon frame (implemented) and crouched elbow root cause with pole experiments (animation improvement 05A). |
| [swivel-preserving-elbow-guidance-2026-11-19.md](swivel-preserving-elbow-guidance-2026-11-19.md) | Swivel-preserving elbow guidance for aiming: algorithm, measurements, transitions (animation improvement 05B). |
| [humanoid-rescue-passenger-2026-11-19.md](humanoid-rescue-passenger-2026-11-19.md) | Humanoid MIRA rescue passenger replacing the orange placeholder: architecture, anchor, pose, limits (animation improvement 06). |

| [rescue-interaction-2026-11-19.md](rescue-interaction-2026-11-19.md) | Rescue lifecycle trace, shared pickup/release timeline, loaded gait, passenger secondary motion, interruption handling (animation 06C-06D). |

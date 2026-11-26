# F3 battle inspection

Hover a destination in battle, then press **F3**. The battle pauses and the panel captures the active unit and current legal-action predictions. Press F3 again or **Resume Battle** to continue. Close/reopen to capture another moment. This panel is for live battles; replay retains its existing playback controls.

| Tab | What it shows |
| --- | --- |
| Unit | Active actor ID, HP/AP/ammo, stances, carried actor, conditions, resolved standing point, body size and clearance. |
| Tactical | Choose a hostile actor for the existing authoritative shot explanation: legality, chance/damage, range/height/cover contributions and blocker. The destination hovered before F3 supplies the existing movement/protection/outgoing-shot explanation and resolved route. |
| AI | Latest authoritative AI outcome (committed/rejected) above the historical decision, existing scoring alternatives/rejections, commander/intent and the active team's squad reservations (shared by player/allies). This is historical evidence, not a new plan computed by F3. |
| Map | Tactical source, seed, cells/occupancy, zones, traversal, geometry mode and validation. The optional technical manifest shows accepted parcel/population choices, capped at 12,000 characters. |
| Runtime | Simulation version and last-reported engine monitors: frame/physics time, FPS, draw calls, primitives and memory. These update twice a second while open. |
| Diagnostics | Existing map, zones, links, trajectory, AI explanation and scoring overlays. |
| Control / Mission | Existing developer commands, separate from read-only inspection. These can change the battle. |

## Decision visualization

Read-only tools for following what the AI decided and why. They show the decision records as made; nothing is recomputed, no AP is spent, no combat RNG is consumed and no squad context is created.

| Tool | Where | What it shows |
| --- | --- | --- |
| **Timeline** | Timeline tab | The last 80 decisions, newest first. Select a row to see the recorded actor and faction, difficulty and doctrine, mission and movement profile, score components, and the selected option. A linked outcome shows the submitted action, transaction or rejection, and recorded AP/ammo changes where available. |
| **Route arrow** | 3D view, scoring overlay | An arrow from the acting unit to its chosen destination for Move decisions. |
| **Target lines** | 3D view, scoring overlay | A line to every target the unit considered: thick and bright for the chosen one, colored by score for the others. Rejected targets appear only if rejected cells are shown. |
| **Walkable tiles** | Map, "Show walkable tiles" | Translucent green terrain across floors, including occupied tiles. It stays visible after closing F3 and is independent of the selected unit and its AP. |
| **Squad reservations** | Diagnostics, "Show squad reservations" | Cyan squares for reserved destinations (labelled with the owner), green for the carrier's reserved corridor, magenta diamonds under the targets squads committed to. Both teams are shown. |

Historical rows distinguish a selected action awaiting an outcome, a commitment, a rejected submission, and a standalone post-action explanation. A score bar compares the retained move candidates on one scale. The decision reason can explain why a selected candidate ranked below another option. Movement-policy filters and unavailable shots are displayed separately from evaluated scores. Attack rows show target forecast evidence without reusing an earlier move heatmap.

The timeline retains up to 128 move and 32 target candidates per decision. It keeps the selected candidate and the highest-scoring alternatives when truncation is needed. The historical squad section shows the reservations and recent events captured when the decision was published. The squad overlay continues to show current reservations. The closed panel records history without refreshing the timeline widgets.

Shots and destination feedback use the same queries/text as gameplay. Capture runs **before** F3 pauses the tree; otherwise legal actions would misleadingly report that the battle is paused. Already-paused inspection reports action snapshots unavailable. Target inspection is bounded to the first eight hostile actor IDs in sorted order; the full manifest remains in map/replay data.

A changed action revision or a developer mission command marks the snapshot **STALE**. Close and reopen F3 to refresh it. Opening/browsing the inspection does not spend AP, commit actions, consume combat RNG or create squad contexts. Closing the panel releases only a pause it owns; removing an open panel also releases that pause.

Runtime monitors reflect the last engine sample, potentially including loading or paused frames. The snapshot-build number measures inspection only. Use the existing `profile-ai` simulator argument to collect planning slices, decision latency, frame yields, activation pacing, and execution windows. See the [Step 11 methodology and results](quality/ai-step11-profiling-f3-2026-11-24.md).

Current AI repair follow-up: [behavior and trace contracts](ai-current-behavior.md), [verification](quality/ai-repairs-2026-11-17.md).

## Initial verification — 2026-11-17

- UI subsystem: **26 passed, 0 failed, 1 explicit-only capture skipped**. Includes parse, pause/menu, existing debug tools/map/mission commands, camera and HUD checks. Logs: `artifacts/test-results/20261117-205318-subsystem-ui/`.
- Final focused inspection: **39 checks, 0 failures**, including query agreement, fingerprint/RNG/revision purity, owned mission reference, all eight sections fitting a 720p window, stale-state feedback, pause ownership, removal and replay command rejection.
- Existing AI scoring-overlay smoke: **0 failures**.
- Rendered inspection: **43 checks, 0 failures**, with four 1280×720 captures reviewed for Unit, Tactical (including hovered movement), Map/manifest and Runtime. Local captures: `artifacts/f3-review/`. This is a visual spot check, not a complete manual AI playthrough.
- Initial failures were corrected: panel minimum-height inflation from wrapped text; the new fixture initially selected the old authored map because it omitted `generated_map`; objective lookup needed the battle's explicitly wired manager, since controller initialization can bind it after child readiness. Assertions were retained. Existing Unicode labels were restored after an intermediate encoding mistake.
- Godot still reports the environment's root-certificate-store warning. No script/parser errors appeared in final focused or rendered logs. The full project suite and complete battle/replay matrix were not repeated for this inspection-only update.

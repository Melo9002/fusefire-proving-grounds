# Simulation and reproducibility

`systems/simulation/` instantiates the real battle scene and delegates player decisions to the existing AI. It uses actual movement, combat, turns, missions and replay; there is no separate simplified combat model.

For current Service Depot construction, run:

```powershell
godot_console --headless --path . --script res://tests/current_generation_test.gd
godot_console --headless --path . --script res://tests/compact_battlefield_test.gd
```

The second suite also executes the elevated terminal mechanic on the internal Tactical Test Range. It does not establish autonomous AI mission completion on every depot seed.

For tactical/AI regression checks:

```powershell
.\tools\run_tests.ps1 subsystem -Subsystem ai
.\tools\run_tests.ps1 subsystem -Subsystem replay
```

Older simulation and structural batches remain explicit mechanics diagnostics. They intentionally use internal legacy fixtures; they are not the normal map-generation workflow:

```powershell
godot_console --headless --path . --script res://tests/ai_match_simulation_smoke.gd -- 23001 7 0
godot_console --headless --path . --script res://tests/map_generation_batch_smoke.gd -- 5000 250
```

AI batch arguments are `FIRST_SEED MATCH_COUNT MISSION_OFFSET`. Mission offsets are 0 Eliminate, 1 Protect, 2 Rescue, 3 Reach, 4 Survive, 5 Extract, 6 Enemy Evacuation. A completed Victory or Defeat is a legitimate terminal result. Stalls, round limits, timeouts and setup failures are failures, not completed missions.

Failure reports print their destination after `[AISim] FAILURE REPORT` and include configuration, seed, map dimensions, validation errors, terminal state and decision trail. Reproduce the same fixture/configuration; an old fixture seed does not reproduce a Service Depot battlefield.

The battle seed feeds independent deterministic map/population, AI and combat streams. Equivalent actions and compatible content/rules should reproduce tactical outcomes. Current parcel maps additionally record actual accepted content; preserving a seed alone does not guarantee reconstruction after content changes. Execution time and cosmetic rendering are not authoritative replay state.

Map quality metrics describe cover, routes, openness, lanes and spawn safety. They supplement tactical validation and playtesting; their score is not visual approval or a finished balance grade.

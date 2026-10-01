# AI Match Simulation and Reproducibility

Fuse Fire's simulator instantiates the real battle scene and delegates player decisions to the existing AI. It does not maintain a simplified combat model. Movement, attacks, objectives, extraction, difficulty policies, and allied/enemy behavior therefore use the same code as an interactive match.

## Requirements

Run commands from the repository root. `godot_console` must be available on `PATH` and should match the project's Godot version.

```powershell
godot_console --version
```

## Common commands

Run the default seven-match sweep, covering every mission preset:

```powershell
godot_console --headless --path . --script res://tests/ai_match_simulation_smoke.gd
```

Run seven missions beginning at battle seed `23001`:

```powershell
godot_console --headless --path . --script res://tests/ai_match_simulation_smoke.gd -- 23001 7 0
```

Run the authored-map determinism check twice with the same configuration:

```powershell
godot_console --headless --path . --script res://tests/ai_match_determinism_smoke.gd
```

Measure map quality across 80 standard and refinery maps:

```powershell
godot_console --headless --path . --script res://tests/map_quality_metrics_smoke.gd
```

Run the Prototype 1 5v5 certification matrix:

```powershell
godot_console --headless --path . --script res://tests/prototype_1_milestone.gd
```

Reproduce the former seed-25005 extraction Defend loop and verify that bounded
AI urgency resolves it:

```powershell
godot_console --headless --path . --script res://tests/ai_stalemate_recovery_smoke.gd
```

This matrix runs every mission twice with five combatants on each side. Protect and
Rescue split the friendly force between player and allied factions so allied AI is
also exercised. It covers 24×20, 32×24, and 40×30 maps; generic generation, refinery,
and the authored arena; and verifies that elevation and traversal are present. Both
Victory and Defeat are valid completed simulations. Stalls, timeouts, setup failures,
and round-limit results fail the command.

The map-quality run prints five separate category scores: cover, routes, open space,
firing lanes, and spawn safety. It also prints a low-, middle-, and high-ranked seed.
Recreate those seeds in Match Setup and play or inspect them before changing score
weights. A higher diagnostic score is useful only when it consistently agrees with
human playtesting; it is not a percentage grade and does not currently reject maps.
Categories with no variation are marked `NO DISCRIMINATION`. They may still enforce a
useful baseline, but they cannot currently distinguish one generated layout from
another and should not be treated as evidence that the higher-ranked map is better.

## Seed failure reports

When a batch match stalls, exceeds its round or time limit, or fails setup, the runner
writes a JSON report under Godot's `user://ai_sim_failure_reports` directory and prints
the absolute path after `[AISim] FAILURE REPORT`. The report contains the exact battle
configuration, map seed and dimensions, mission and difficulty, validation errors,
terminal state signature, and the structured AI decision trail. Successful matches do
not create reports. Verify report serialization with:

```powershell
godot_console --headless --path . --script res://tests/seed_failure_report_smoke.gd
```

Run the faster structural map-generation batch:

```powershell
godot_console --headless --path . --script res://tests/map_generation_batch_smoke.gd
```

Choose a reproducible structural range:

```powershell
godot_console --headless --path . --script res://tests/map_generation_batch_smoke.gd -- 5000 250
```

## Simulation arguments

The AI simulation command accepts three optional integers after `--`:

```text
FIRST_SEED  MATCH_COUNT  MISSION_OFFSET
```

| Argument | Default | Meaning |
| --- | ---: | --- |
| `FIRST_SEED` | `23001` | Battle seed assigned to the first match. Each later match adds one. |
| `MATCH_COUNT` | `7` | Number of sequential matches to run. |
| `MISSION_OFFSET` | `0` | Index of the first mission preset. Later matches cycle through the list. |

Mission offsets:

| Offset | Mission |
| ---: | --- |
| `0` | Eliminate |
| `1` | Protect |
| `2` | Rescue |
| `3` | Reach |
| `4` | Survive |
| `5` | Extract |
| `6` | Enemy Evacuation |

Examples:

```powershell
# Reproduce Rescue seed 23003 once.
godot_console --headless --path . --script res://tests/ai_match_simulation_smoke.gd -- 23003 1 2

# Run 30 matches, beginning with Reach and cycling through every mission.
godot_console --headless --path . --script res://tests/ai_match_simulation_smoke.gd -- 40000 30 3
```

Generated simulations rotate by match index through:

1. Small — 24×20
2. Medium — 32×24
3. Large — 40×30

The map source and dimensions appear in every `[AISim]` result. Map size is therefore part of the tested configuration rather than an implicit Medium-map default.

## Understanding output

A completed result resembles:

```text
[AISim] seed 23303 | generated_cover 40x30 | Extract Test | Completed/Victory | rounds 6 | decisions 40 | 4.54s
```

Completion means the battle reached an authoritative victory or defeat. A defeat is a valid completed simulation.

Non-completion classifications are:

| Status | Meaning |
| --- | --- |
| `Stalled` | No authoritative state changed for the configured interval. |
| `Round Limit` | The battle continued beyond the allowed round count. |
| `Timeout` | The real execution-time budget expired. |
| `Setup Failed` | The scene or battlefield failed to initialize correctly. |

Issue reports include a terminal state signature containing the round, phase, active actor, unit positions, HP/AP, and objective states. The full batch exits with a nonzero code when it detects any issue. This is intentional so automated checks can notice pathological seeds.

## Seed model

Every match has a **battle seed**, including authored maps. The current prototype derives independent deterministic streams from it:

- map generation, when using a generated map;
- AI choices and intentional mistakes;
- combat rolls.

Repeating a premade map with the same battle seed, rules, rosters, mission configuration, and action order reproduces its random outcomes. Generated battles additionally require the same generator version, map preset, and dimensions.

Elapsed execution time is not deterministic and is not part of replay authority.

## Current certification baseline

The Prototype 1 matrix completed 15 of 15 matches with no issues on 2026-09-27:
seven missions across two passes plus one authored-map Eliminate match. It covered
10 generic generated maps, four refinery maps, one authored map, all three generated
sizes, and elevation/traversal in every match. The observed average was 6.9 rounds.

This is a regression baseline, not a promise that every possible seed is balanced.
Preserve any future failing seed through the JSON failure report and add it as a
targeted regression case.

## Reducing console noise

The simulator currently emits normal gameplay diagnostics as well as its summary. To inspect only simulator lines in PowerShell:

```powershell
godot_console --headless --path . --script res://tests/ai_match_simulation_smoke.gd -- 23001 7 0 2>&1 |
    Select-String -Pattern '\[AISim\]|SCRIPT ERROR|ERROR:'
```

The future logging task should provide explicit quiet, debug, telemetry, and verbose-AI levels. Until then, preserve the unfiltered log when investigating a failure.

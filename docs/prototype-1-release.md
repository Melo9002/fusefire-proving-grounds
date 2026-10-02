# Prototype 1 release

Prototype 1 is the completed proving ground for FuseFire's tactical foundation. It includes generated and authored multilayer maps, diagonal movement and targeting with corner blocking, player/allied/enemy factions, mission objectives, deterministic combat and replay, action cameras, the first humanoid presentation, and developer inspection tools.

## Run the Windows build

Extract the archive and launch `FuseFire Prototype 1.exe`. The match setup includes **Intel / Compatibility Renderer**. Enabling it saves the preference and restarts the game with Godot's OpenGL Compatibility renderer. Use it if the default D3D12 renderer freezes or behaves poorly on integrated graphics.

## Known prototype limits

- Character animation and weapon contact are editable foundations and still need artistic refinement.
- Dense rescue encounters around single-tile stairs can become congested. Escorts reserve the carrier route and may form a convoy through narrow passages, but these positions remain intentionally dangerous.
- Performance was audited and obvious repeated presentation work was reduced. A complete hardware matrix, GPU capture, and final rendering budget belong to later production work.
- The included humanoid and AUG demonstrate the art pipeline; they do not define the final game's character system.

## Release verification

Run from the repository root:

```powershell
godot_console --headless --path . --editor --quit
godot_console --headless --path . --script res://tests/prototype_1_milestone.gd
godot_console --headless --path . --script res://tests/battle_replay_smoke.gd
godot_console --headless --path . --script res://tests/rescue_battle_replay_smoke.gd
godot_console --headless --path . --script res://tests/rescue_refinery_congestion_smoke.gd
godot_console --headless --path . --script res://tests/debug_tools_smoke.gd
godot_console --headless --path . --script res://tests/animation_handoff_test.gd
```

Export the Windows package with the versioned **Windows Desktop** preset. After export, launch it once normally and once after enabling Compatibility mode. Play at least one Eliminate and one Rescue mission, pause during live play and replay, and verify camera movement while replay is paused.

## Maintainer entry points

Start at [Documentation index](index.md), then use [Human editing map](human-editing-guide.md) for common changes, [Code organization](code-organization.md) for ownership, and [Animation editing guide](animation-editing-guide.md) for character work.

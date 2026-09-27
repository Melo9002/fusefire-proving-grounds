# Debug map inspection

Task 24A extends the existing F3 tools with read-only inspection of the battlefield model.

## Using the inspector

1. Start an authored or generated match.
2. Press **F3**.
3. Enable **Inspect map cells and metadata**.
4. Close the F3 panel or leave it open while paused, then hover a walkable map surface.
5. On stacked terrain, hold **Alt** and use the mouse wheel to choose another surface.

The top-right inspection overlay reports:

- map source, dimensions, and generation seed;
- total, walkable, stoppable, elevated, occupied, and line-of-sight-blocking cells;
- low and full cover counts;
- zone, traversal-link, building, platform, and hill counts;
- hovered cell grid and world coordinates;
- elevation, movement cost, cover height, line-of-sight blocking, occupant, zones, and connected traversal links.

**Show all map zones** draws deployment zones in faction colors, objectives in purple, and extraction zones in green. **Show traversal links** draws yellow lines between linked surfaces. Both layers can be toggled independently.

This inspector reads the authoritative `MapData` and does not change movement, combat, objectives, or replay state.

### Automated verification

Run:

```powershell
godot_console --headless --path . --script res://tests/debug_map_inspector_smoke.gd
godot_console --headless --path . --script res://tests/debug_tools_smoke.gd
```

The focused test covers authored metadata, generated-map seed and size, elevation inspection, zones, traversal links, and visibility toggles.


## Debug mission controls

Task 24B adds state-changing mission test commands to the F3 panel. Each command writes a `[DebugMission]` line to the Godot output and displays its result inside the panel.

### Advance One Round

Immediately begins the next player round, resets the normal player turn state, and emits the standard `round_started` signal. Timed objectives such as Survive therefore receive their normal progress.

The command is rejected after battle completion or while an actor is moving.

### Complete or fail an objective

Choose an active objective in the objective dropdown, then select **Complete Objective** or **Fail Objective**. The command uses `ObjectiveManager`, including its normal progress signals and victory or defeat evaluation.

Optional objectives keep their ordinary optional behavior.

### Teleport an actor

1. Close F3 and hover the intended walkable destination.
2. Press **F3** without moving the cursor away.
3. Select an actor.
4. Press **Teleport to Inspected Cell**.

The teleport validates walkability, stopping permission, and occupancy. It updates both the actor transform and the authoritative occupancy map, then emits the standard movement-consequence signal. This allows teleports to test Reach zones and automatic Rescue interactions.

### Force extraction

Select an actor and press **Force Extraction**. The controller locates an active extraction objective pursued by that actor, moves the actor to an open cell in the correct zone, and executes the normal extraction action. Mission counters and outcome evaluation remain active. A Survive prerequisite is completed first when necessary.

Actors without a matching active extraction objective are rejected instead of being deleted.

Debug commands intentionally bypass normal player action flow and are not intended to produce canonical replay recordings.

### Automated verification

Run:

```powershell
godot_console --headless --path . --script res://tests/debug_mission_controls_smoke.gd
godot_console --headless --path . --script res://tests/debug_tools_smoke.gd
```

The focused test verifies round advancement and Survive progress, synchronized teleport occupancy, objective completion and failure, extraction counters, roster removal, and final mission outcomes. The F3 regression test also asserts that the expanded panel fits at 720p.



## AI scoring overlay

Task 24C exposes the inputs behind AI movement and target selection.

Enable **Show AI scoring overlay** in the F3 panel, then allow an AI-controlled unit to act. The most recent decision remains visible while the battle is paused.

### Movement tiles

Every movement tile that reached the scoring stage displays its signed total directly above the tile:

- **Cyan:** the chosen destination;
- **green/yellow:** stronger and middling alternatives;
- **orange:** weaker scored alternatives;
- **red without a number:** rejected before scoring.

The details overlay lists the highest movement candidates and decomposes each total into:

- objective or route progress;
- directional cover;
- hostile exposure;
- firing opportunities;
- close-range and crossfire danger;
- squad reservation or crowding adjustment.

Rejected cells retain a reason such as occupied, illegal stopping cell, unsafe second advance, outside the useful route, or reserved by an ally.

### Target candidates

Legal targets display their total target score and its vulnerability, VIP, threat, mission relevance, and allied-focus components. Illegal targets remain visible as rejected candidates with the combat-rule reason.

The chosen action and subject appear at the top of the details overlay. This record uses the active difficulty policy, so future commander policies can change weights while reusing the same inspection system.

### Verification

Run:

```powershell
godot_console --headless --path . --script res://tests/ai_scoring_overlay_smoke.gd
godot_console --headless --path . --script res://tests/ai_position_scoring_smoke.gd
godot_console --headless --path . --script res://tests/ai_target_scoring_smoke.gd
```

The focused test requires real AI output, verifies numeric totals and summaries for every scored movement candidate, checks chosen and rejected markers, and confirms one visible number per legal scored tile.


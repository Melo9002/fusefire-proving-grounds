# Diagonal movement

Shooting uses physical 3D distance divided by tile size for range, shared by
manual attacks, range previews, and AI firing/exposure scoring. A ray can graze
a single exposed corner, but cannot pass through the artificial inset between
two touching diagonal LOS blockers. Height still matters: shots above the
blocks remain possible. Existing directional cover considers both sides for
exact diagonal approaches.

Rescue and automatic pickup accept same-level diagonal neighbours only when
both side cells are clear and stoppable. Extraction uses zone membership and
needs no adjacency change. Melee is not implemented.

Additional regression: `godot_console --headless --path . --script tests/diagonal_combat_test.gd`.

Same-elevation clear tiles connect in eight directions. A diagonal requires
all four cells in its 2x2 square to exist, be walkable, and allow stopping.
Either blocked side forbids corner cutting. Low cover cannot be crossed
diagonally: its existing cardinal traversal and terrain surcharge remain.
Stairs, elevation steps, and explicit traversal links keep their existing rules.

Straight steps cost 1 movement point; diagonals cost sqrt(2), multiplied by
the destination terrain cost. Existing non-diagonal traversal links retain
their one-step base cost. AP costs are unchanged. Path selection, reachable
tiles, and mission-placement distances share these costs. A zero A* heuristic
ensures that inexpensive explicit traversal links cannot cause overestimation.

This changes routes, map metrics, objective placement, and AI outcomes for
existing seeds. Record new battles after the change; old action logs were
produced under different movement rules.

Run from the repository root:

```powershell
godot_console --headless --path . --script tests/diagonal_movement_test.gd
godot_console --headless --path . --script tests/vertical_traversal_smoke.gd
godot_console --headless --path . --script tests/battle_replay_smoke.gd
godot_console --headless --path . --script tests/rescue_battle_replay_smoke.gd
```

Manual review: move across open ground, try a gap between touching full blocks,
try skirting one full-block corner, then test low cover and stairs. Repeat with
AI control and replay. Diagonal clearance concerns terrain; unit occupancy
continues to follow the existing movement rules.

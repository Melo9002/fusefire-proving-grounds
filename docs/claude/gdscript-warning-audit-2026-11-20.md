# GDScript warning audit (stabilization 04)

## How the warnings were collected

A plain headless run, `--check-only` and a headless editor launch print **no** script warnings: Godot only reports them to an attached debugger (that is the editor's Errors panel). So the
audit is a debugger-side script: `tools/quality/script_warning_audit.gd` listens on a local port, launches a second Godot with `--remote-debug` that loads every project script
(`tools/scan_script_warnings.gd`), and writes `file:line | warning | message` for each warning.

```
godot_console --headless --path . --script res://tools/quality/script_warning_audit.gd -- <path to godot_console.exe> <output file>
```

Warning levels are the project defaults (nothing is suppressed or relaxed in project settings).

## Result

Initial: **26** warnings in 15 files. After the corrections: **0** (same scan, same scope: all 466 scripts under `res://`).

| Warning | Count | Classification | Resolution |
| --- | --- | --- | --- |
| SHADOWED_VARIABLE_BASE_CLASS (`basis`, `scale`, `rotation`, `to_local`, `name`) | 10 | avoidable naming collision | renamed to role names: `bone_rest_basis`, `skeleton_scale`, `hand_rotation`, `world_to_carrier`, `passenger_basis`, `bone_name`, `hand_name` |
| SHADOWED_VARIABLE (`carrier_root`, `axis`, `shot`, `lying_basis`, `sample`) | 5 | avoidable naming collision | `carrier_node`, `axis_point`, `evaluation`, `lying_orientation`, `measurement` |
| SHADOWED_GLOBAL_IDENTIFIER (`wrap`) | 1 | avoidable naming collision | `wrap_direction` |
| INCOMPATIBLE_TERNARY | 2 | legitimate type problem | `pathfinder.gd`: a cell-less occupant's position (Vector3 or null) is now an explicit `Variant` set by `if`; `unit_visual_adapter.gd lying_basis()` returns `Variant` through an `if` (Basis or null) |
| INTEGER_DIVISION | 8 | intentional truncation | see below |
| UNUSED_VARIABLE (`kind` in `_sync_cover_crouch`) | 1 | dead code | removed (see below) |

No warning was a correctness defect in the stabilization work. Four of the files (`pathfinder`, `ai_plan_evaluator`, `cylinder_part`, `tactical_feedback_text`, and the two diagnostics scripts)
predate it; the rest come from the animation stabilization work.

## Notes on the individual decisions

* **Integer division.** All eight are intended whole-number quotients, none is animation phase or timing:
  * `ai_plan_evaluator.gd` (7): AP and ammo counts. `shots_with` can receive a negative AP budget (`current_ap - move_ap`), and the existing behaviour is truncation toward zero; flooring
    through `floori` would change that, so the semantics are preserved exactly. The division is now in one helper, `_truncated_quotient`, with a single targeted
    `@warning_ignore("integer_division")` on that statement (the intent is stated there), instead of seven call sites. New checks in `ai_target_value_test` pin the behaviour.
  * `pathfinder.gd` heap parent `(i - 1) / 2` became `(i - 1) >> 1` (identical for `i > 0`, which the loop guarantees); no suppression.
* **The unused `kind`.** `_sync_cover_crouch` called `_cover_kind()` and discarded the result. `_cover_kind()` also keeps `_held_cover_kind`, but `_update_cover_side()`,
  `_cover_crouch_target()` and `_cover_yaw_target()` all call it in the same frame, so the held kind is updated regardless. The local was a leftover from the earlier fixed-yaw design.
* **Parameter renames** (`carrier_node`, `lying_orientation`, `measurement`) only change names visible inside the functions; every caller passes positionally. `lying_basis()` (the method) keeps its name.
* `attach_to_carrier`'s `carrier_root` parameter shadowed the passenger's own `carrier_root` member. The function never assigned the member; the member is set by the rig. Behaviour unchanged, the name now says which is which.

## Not changed

No warning categories were disabled, no blanket `@warning_ignore`, no typing relaxed. The only suppression is the single declared-intent integer-division statement above.

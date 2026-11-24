# ADDA measurement contract (how to write and read a diagnostic)

## The rules

1. **Read poses only inside `PoseWitness.final_pose`.** `var witness := PoseWitness.acquire(rig.skeleton)`, `witness.final_pose.connect(_sample)`, and `witness.release()` when the tool goes off (the last release disconnects the witness; an idle skeleton carries no ADDA listener). Never call `get_bone_global_pose` from `_process`, a test body or a script that merely awaits a frame: it returns the animation pose without the modifiers (measured, up to 0.47 m off on a ladder climb).
2. **Stamp where you sample.** `stamp = witness.stamp()` in the same callback. `judge(stamp)` later gives FRESH (same update, same witness, taken inside `final_pose`), STALE (a later update, a different witness, or taken outside) or UNAVAILABLE (never sampled).
3. **Say what kind it is.** Use `Measurement.Kind`; never present one kind as another:

| Kind | Establishes | Does NOT establish |
|---|---|---|
| JOINT_POSITION | where a bone is in the final pose | contact, or that the drawn mesh follows the bone |
| TARGET_ERROR | how far a limb ended from what a solver asked | that the target is reachable, correct or a support |
| REACH_FEASIBILITY | a point within the limb's length (97% of the arm, a display convention) | that the pose reaches it; that the rig enforces it |
| SUPPORT_CLAIM | the animation system CLAIMS a contact (owner, weight, plan) | physical support or touching |
| CAPSULE_OVERLAP | approximate limb volumes against a shape | that the drawn mesh intersects |
| VERTEX_OVERLAP | how many sampled mesh vertices are inside a shape | a full intersection (thin crossings between vertices can be missed; a vertex on a bar's axis reads the bar's whole radius, so the count, not the depth, is the severity) |
| MESH_INTERSECTION | triangle against shape | physical collision (not measured by ADDA yet; reported UNSUPPORTED) |
| PHYSICAL_COLLISION | a physics engine's contact | anything about the drawn mesh unless the shapes are the mesh |

4. **Return a reason, not a zero.** If the sample is stale, the surface missing, the tool off or the context unsupported, return `Measurement.missing(kind, name, status, reason)`; its value is `null`. A count of zero is only ever the answer of a FRESH measurement. (`LadderClearance.offenders()` returns an empty list when the sample is not fresh, which looks like "clean": callers that need to tell the difference use `vertex_evidence()` or check `status()`.)
5. **State pose, space, unit, tolerance, method.** `pose` is FINAL, INTENDED (what a solver asked), BASE (never evidence of what is drawn) or UNKNOWN. Space is "world", "character" (the rig's `character_root`: x left, y up, z forward) or "skeleton". Units are in the record.
6. **Identity.** `with_identity(rig, scenario)` adds the character, profile and armed state; frame and update come from the stamp.
7. **Negative control for every instrument.** Inject the fault in the test (never in production), prove the instrument sees it, prove the normal case is clean.

## Using it

```gdscript
var clearance := LadderClearance.new(rig)        # samples itself inside the final-pose window
await get_tree().process_frame
var m := clearance.vertex_evidence(geometry, climbed, 0.003, "my_scenario")
if m.usable():
	print(m.text())                            # "leg vertices inside ladder bars = 0 vertices [VERTEX_OVERLAP, final pose, character]"
else:
	print(m.text())                            # "...: STALE (taken for update 4, the skeleton is at update 7)"
clearance.release()
var contacts := ContactErrorDiagnostics.attach(rig); contacts.set_enabled(true)
for e in contacts.evidence("my_scenario"): print(JSON.stringify(e.to_dict()))
```

## What is not covered yet

Full mesh intersection and physical collision (reported UNSUPPORTED); `HandContactDiagnostics`, `BoneHighlight` and `MotionTrail` do not emit envelopes; there is no timeline (`update` and `frame` make one possible).

class_name RigInput
extends RefCounted
## Typed pose input from the presentation to the rig (Task 04 section 7), replacing string-keyed access. GROUNDWORK: this first subset is the situational body adjustments that
## LocomotionPoseModifier applies; the other modifiers still read the rig by name (inventoried in docs/claude/animation-presenter-foundation-2026-11-20.md).
## Plain data: no node access, no smoothing (smoothing belongs to the presenter), safe at zero delta.

var twist_degrees := 0.0
var bank_degrees := 0.0
var pitch_degrees := 0.0
## Knee flexion of the left and right foot-lifting steps, degrees (0 = planted).
var step_lift_left := 0.0
var step_lift_right := 0.0

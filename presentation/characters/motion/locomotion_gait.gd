class_name LocomotionGait
extends Resource
## One procedural gait (walk, jog, run or a loaded variant): the shape of a stride as phase tables plus the numbers that scale and position
## it. Angles are ANATOMICAL: positive thigh = flexed forward, knee = flexion (the shin swings back), ankle positive = toes up. The clip builder turns
## them into rotations about the skeleton's measured hip axis, so nothing here depends on how the imported bones are oriented (see
## CharacterFallbackAnimationBuilder, "Movement coordinate contract"). LocomotionProfile groups the gaits and says when each applies.
##
## Phase 0 is initial contact of the LEFT heel; the right leg is half a cycle behind. All gaits share that convention and one-second loops, which is
## what lets the animation tree blend them foot-for-foot (phase-synchronised) without the feet crossing or snapping.
##
## What each table encodes (references in docs/claude/locomotion-foundation-2026-11-19.md and locomotion-speed-2026-11-19.md): walking is initial
## contact (heel, leg forward, knee nearly straight), weight acceptance (knee ~15 deg), mid-stance, push-off (hip extended, ankle plantar-flexed), a
## swing with ~55-60 deg of knee flexion, about 60% stance. Running shortens stance to about a third of the cycle, leaves both feet off the ground
## between steps, flexes the knee much more in recovery (~100 deg), lowers the pelvis at mid-stance and raises it in flight, and leans the trunk
## forward. Jogging sits between.

## Phases of the cycle at which the tables below are given.
const PHASES: Array[float] = [0.0, 0.12, 0.25, 0.40, 0.50, 0.62, 0.75, 0.88, 1.0]

@export_group("Stride")
## Ground covered per full cycle (two steps), metres ON THE REFERENCE BODY (RigBones.REFERENCE_HIP_TO_ANKLE); the rig scales it by the body's leg (RigBones.body_ratio). Cadence is speed / this (capped by LocomotionProfile), so it must equal what the stance
## foot actually covers: stance foot travel / stance_fraction. tests/locomotion_speed_test.gd measures it.
@export_range(0.4, 4.5, 0.01, "suffix:m") var stride_length := 1.1
## Fraction of the cycle one foot is on the ground (walk about 0.6, jog 0.45, run 0.36). Drives the foot-flat compensation and the stride test.
@export_range(0.2, 0.7, 0.01) var stance_fraction := 0.58
@export_group("Limb tables (degrees, at PHASES)")
## Hip flexion (+ forward).
@export var thigh_table := PackedFloat32Array([26.0, 20.0, 6.0, -8.0, -13.0, 2.0, 22.0, 30.0, 26.0])
## Knee flexion (never negative: no hyperextension).
@export var knee_table := PackedFloat32Array([4.0, 16.0, 8.0, 10.0, 30.0, 55.0, 48.0, 18.0, 4.0])
## Ankle (+ toes up): heel first at contact, flat in stance, plantar-flexed at push-off.
@export var ankle_table := PackedFloat32Array([5.0, -5.0, 0.0, 3.0, -14.0, -8.0, 3.0, 6.0, 5.0])
@export_group("Scale")
## Scale hip swing, knee flexion and ankle motion. 1 is the table as given.
@export_range(0.0, 1.5, 0.01) var hip_scale := 1.0
@export_range(0.0, 1.5, 0.01) var knee_scale := 1.0
@export_range(0.0, 1.5, 0.01) var ankle_scale := 1.0
## Feet a little apart: hip abduction (degrees) held through the cycle.
@export_range(0.0, 10.0, 0.1, "suffix:°") var stance_spread_degrees := 2.5
@export_group("Pelvis and torso")
## Pelvis rise over a step, metres, and the cycle phase at which it is highest (walk: mid-stance 0.25; running: in flight, about 0.4).
@export_range(0.0, 0.08, 0.001, "suffix:m") var pelvis_bob := 0.012
@export_range(0.0, 1.0, 0.01) var bob_peak_phase := 0.25
## Sideways shift of the pelvis toward the stance leg, metres.
@export_range(0.0, 0.05, 0.001, "suffix:m") var pelvis_sway := 0.008
## Pelvis rotation about the vertical toward the swinging leg, degrees each way.
@export_range(0.0, 12.0, 0.1, "suffix:°") var pelvis_yaw_degrees := 4.0
## Chest counter-rotation as a fraction of the pelvis rotation (1 = shoulders stay square to the path).
@export_range(0.0, 1.5, 0.01) var torso_counter_rotation := 0.9
## Forward lean of the trunk held through the gait (degrees; running leans, walking does not).
@export_range(0.0, 20.0, 0.1, "suffix:°") var forward_lean_degrees := 0.0
@export_group("Directions (workbench; ordinary tactical movement is always forward)")
## Backward walking uses the same table played in reverse at this fraction of the forward amplitude.
@export_range(0.2, 1.0, 0.01) var backward_scale := 0.7
## Side stepping: hip abduction/adduction swing, degrees, and the knee lift of the stepping leg.
@export_range(0.0, 30.0, 0.5, "suffix:°") var side_step_degrees := 14.0
@export_range(0.0, 60.0, 0.5, "suffix:°") var side_step_knee_degrees := 30.0


static func walk() -> LocomotionGait:
	return LocomotionGait.new()   # the field defaults ARE the accepted walk (stabilization 01)


static func jog() -> LocomotionGait:
	var g := LocomotionGait.new()
	g.stride_length = 1.6
	g.stance_fraction = 0.45
	g.thigh_table = PackedFloat32Array([28.0, 18.0, 4.0, -12.0, -8.0, 18.0, 34.0, 36.0, 28.0])
	g.knee_table = PackedFloat32Array([10.0, 24.0, 14.0, 22.0, 55.0, 80.0, 62.0, 28.0, 10.0])
	g.ankle_table = PackedFloat32Array([4.0, -4.0, 0.0, -12.0, -16.0, -6.0, 4.0, 6.0, 4.0])
	g.stance_spread_degrees = 2.0
	g.pelvis_bob = 0.02
	g.bob_peak_phase = 0.36
	g.pelvis_sway = 0.01
	g.pelvis_yaw_degrees = 5.0
	g.forward_lean_degrees = 4.0
	g.hip_scale = 1.12
	return g


static func run() -> LocomotionGait:
	var g := LocomotionGait.new()
	g.stride_length = 2.5
	g.stance_fraction = 0.36
	g.thigh_table = PackedFloat32Array([32.0, 14.0, -6.0, -20.0, -10.0, 20.0, 40.0, 44.0, 32.0])
	g.knee_table = PackedFloat32Array([14.0, 40.0, 24.0, 50.0, 95.0, 100.0, 70.0, 32.0, 14.0])
	g.ankle_table = PackedFloat32Array([3.0, -6.0, -2.0, -16.0, -18.0, -8.0, 4.0, 6.0, 3.0])
	g.stance_spread_degrees = 1.5
	g.pelvis_bob = 0.03
	g.bob_peak_phase = 0.42
	g.pelvis_sway = 0.01
	g.pelvis_yaw_degrees = 6.0
	g.forward_lean_degrees = 9.0
	g.hip_scale = 1.25
	return g


## A loaded carry walk: a shorter, steadier step (the Animation 06 intent), same shape as the walk.
static func loaded() -> LocomotionGait:
	var gait := LocomotionGait.new()
	gait.stride_length = 0.75
	gait.hip_scale = 0.62
	gait.knee_scale = 0.7
	gait.ankle_scale = 0.7
	gait.stance_spread_degrees = 4.0
	gait.pelvis_bob = 0.008
	gait.pelvis_sway = 0.006
	gait.pelvis_yaw_degrees = 0.0   # a carrier keeps the trunk square: the passenger contacts ride on the chest (see docs, "pelvis yaw")
	gait.torso_counter_rotation = 0.0
	return gait


## A loaded carry at speed: a brisk trot with the trunk held square (the tactical game moves a carrier at full speed). Not a run: modest knee
## lift, no forward lean and no pelvis rotation, so the passenger and the hand contacts stay stable.
static func loaded_fast() -> LocomotionGait:
	var gait := LocomotionGait.new()
	gait.stride_length = 1.2
	gait.stance_fraction = 0.5
	gait.thigh_table = PackedFloat32Array([26.0, 17.0, 3.0, -10.0, -10.0, 8.0, 26.0, 32.0, 26.0])
	gait.knee_table = PackedFloat32Array([8.0, 20.0, 11.0, 15.0, 42.0, 62.0, 52.0, 22.0, 8.0])
	gait.ankle_table = PackedFloat32Array([4.0, -4.0, 0.0, -8.0, -15.0, -7.0, 3.0, 5.0, 4.0])
	gait.hip_scale = 0.9
	gait.knee_scale = 0.75
	gait.ankle_scale = 0.75
	gait.stance_spread_degrees = 4.0
	gait.pelvis_bob = 0.012
	gait.bob_peak_phase = 0.3
	gait.pelvis_sway = 0.006
	gait.pelvis_yaw_degrees = 0.0
	gait.torso_counter_rotation = 0.0
	return gait


## Smooth (periodic Catmull-Rom) value of a phase table at cycle position `t` (0..1, wraps). The table's last entry repeats the first.
static func sample(table: PackedFloat32Array, t: float) -> float:
	t = fposmod(t, 1.0)
	var count := PHASES.size() - 1
	var i := 0
	while i < count - 1 and t > PHASES[i + 1]:
		i += 1
	var u := (t - PHASES[i]) / (PHASES[i + 1] - PHASES[i])
	var p0 := table[(i - 1 + count) % count]
	var p1 := table[i]
	var p2 := table[(i + 1) % count]
	var p3 := table[(i + 2) % count]
	return cubic_interpolate_helper(p0, p1, p2, p3, u)


static func cubic_interpolate_helper(p0: float, p1: float, p2: float, p3: float, u: float) -> float:
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u * u * u)

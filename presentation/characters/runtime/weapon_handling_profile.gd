class_name WeaponHandlingProfile
extends Resource
## Where a weapon is held, in the weapon model's own frame (+z toward the muzzle, y up, +x toward
## the shooter's left), unscaled model metres. The rig derives the stock position, the hand
## targets and the hand orientation from this, so another weapon only needs another profile.
## The defaults describe the AUG model, measured from its mesh (tools/quality/weapon_clusters_probe.gd).

## Presentation scale applied to the weapon model. The character's arms are short next to a
## full-size rifle: with the stock in the shoulder pocket, the support hand could not reach the
## front handle of a full-size AUG (arm length 0.47 m), so the model is drawn slightly smaller.
@export_range(0.5, 1.2, 0.01) var scale := 0.82
## Centre of the butt plate: the point that rests in the shoulder pocket.
@export var stock_rear := Vector3(-0.007, 0.044, -0.395)
## Centre of the pistol grip (firing hand).
@export var firing_grip := Vector3(-0.007, -0.055, -0.015)
## Centre of the support grip (the front handle). The support hand wraps it from the shooter's left.
@export var support_grip := Vector3(-0.007, -0.04, 0.20)
## How far the palm centre sits off the grip centre, toward the side the hand comes from.
@export var palm_side_offset := 0.035
## The hands' long axis points forward and this far down, degrees.
@export_range(0.0, 70.0, 1.0) var hand_pitch_degrees := 30.0
## Approximate centre of the optic, for aligning the eye with the sights.
@export var sight := Vector3(0.0, 0.13, -0.10)

@export_group("Readiness")
## Lowered carry: weapon rotation (degrees) and firing-hand position (Character-local metres) while
## the weapon is not raised. Aimed is derived from the stock and shoulder instead.
@export var lowered_angles_degrees := Vector3(35, 40, -8)
@export var lowered_grip := Vector3(-0.08, 1.16, 0.15)
## Aim blend (0 lowered, 1 aimed) of the READY level: weapon prepared, not in the firing pose.
@export_range(0.0, 1.0, 0.01) var ready_blend := 0.6
## Extra clearance of the stock from the shoulder while MOVING with the rifle held (not raised), as an offset of the firing hand (Character-local metres):
## forward so the butt is carried in front of the shoulder instead of in it. While moving, the held rifle also follows the shoulder (lean, bob).
@export var ready_clearance := Vector3(0.0, 0.0, 0.065)
## Seconds for a full lowered-to-aimed raise, and back. Partial moves take proportionally less.
@export_range(0.05, 2.0, 0.01, "suffix:s") var raise_seconds := 0.28
@export_range(0.05, 2.0, 0.01, "suffix:s") var lower_seconds := 0.28
## How far the muzzle may be from the firing pose and still count as aligned, degrees. A shot is
## not shown before this. At 1 degree the stock is within about 2 mm of the shoulder pocket (3 degrees left 6.6 mm
## of it) and the muzzle is 1.7 cm off at a metre; it costs about 5 ms of raise over a looser tolerance.
@export_range(0.5, 15.0, 0.5, "suffix:°") var alignment_tolerance_degrees := 1.0
## Seconds from the shot to the start of the release back to the held readiness.
@export_range(0.0, 3.0, 0.01, "suffix:s") var shot_recover_seconds := 0.34
## Longest an attack waits for alignment before it fires anyway (presentation must never stall).
@export_range(0.1, 5.0, 0.05, "suffix:s") var max_raise_wait_seconds := 0.8
@export_group("")

@export_group("Stowage")
## Provisional sling stowage: where this weapon hangs on a carrier whose hands are busy (carrying a rescue passenger).
## Nothing is drawn (no strap) and nothing swings: the weapon is anchored to the carrier's chest (see ChestAnchor) at a fixed
## place, so it follows the torso. Another weapon, or a different sling, supplies its own values. The offset is the weapon's
## ORIGIN measured from the carrier's neck bone in the carrier's frame (x left, y up, z forward) in its rest pose, metres;
## the angles orient the weapon model in that same frame (degrees; (90, 0, 0) hangs it muzzle-down, optic facing forward).
@export var stowed_offset_from_neck := Vector3(0.0, -0.40, 0.20)
@export var stowed_angles_degrees := Vector3(90, 0, 0)
@export_group("")

## Aim blend from which the weapon counts as aimed: the muzzle's rotation from the firing pose scales
## linearly with (1 - blend), so the tolerance is expressed against the lowered carry's own angle.
func aimed_blend_threshold() -> float:
	var carry_angle := rad_to_deg(Quaternion.from_euler(lowered_angles_degrees * (PI / 180.0)).get_angle())
	if carry_angle <= 0.001:
		return 1.0
	return clampf(1.0 - alignment_tolerance_degrees / carry_angle, 0.0, 1.0)

## Direction the fingers' base points in the weapon frame.
func hand_forward() -> Vector3:
	var pitch := deg_to_rad(hand_pitch_degrees)
	return Vector3(0.0, -sin(pitch), cos(pitch))

## Palm centre on the firing grip: the firing hand comes from the right, so its palm sits right of the grip.
func firing_palm() -> Vector3:
	return firing_grip + Vector3(-palm_side_offset, 0.0, 0.0)

## Palm centre on the support grip: the support hand comes from the left.
func support_palm() -> Vector3:
	return support_grip + Vector3(palm_side_offset, 0.0, 0.0)

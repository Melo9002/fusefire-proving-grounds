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

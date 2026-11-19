class_name ChestAnchor
extends RefCounted
## A point and orientation on a carrier's torso, chosen once in the carrier's neutral rest pose and replayed from the chest
## bone every skeleton update, so whatever hangs from it (a slung weapon, a carried passenger) leans, bobs and turns with the
## torso instead of staying fixed in space.
##
## It is specified the way a person would describe it: an offset from the NECK bone in the carrier's own frame (x = the
## carrier's left, y = up, z = the way it faces) and an orientation in that frame, both in the rest pose. That keeps the
## numbers readable and scaling with the skeleton's proportions. Internally the relation is stored in the chest bone's frame.

var skeleton: Skeleton3D
var chest_bone := -1
var _in_chest := Transform3D.IDENTITY


## Null when the skeleton lacks either bone.
static func create(carrier_skeleton: Skeleton3D, carrier_root: Node3D, chest_name: StringName, neck_name: StringName, offset_from_neck: Vector3, orientation := Basis.IDENTITY) -> ChestAnchor:
	var chest := carrier_skeleton.find_bone(chest_name)
	var neck := carrier_skeleton.find_bone(neck_name)
	if chest < 0 or neck < 0:
		return null
	var anchor := ChestAnchor.new()
	anchor.skeleton = carrier_skeleton
	anchor.chest_bone = chest
	var carrier_basis := carrier_root.global_basis.orthonormalized()
	var neck_rest := carrier_skeleton.global_transform * carrier_skeleton.get_bone_global_rest(neck).origin
	var wanted := Transform3D(carrier_basis * orientation, neck_rest + carrier_basis * offset_from_neck)
	anchor._in_chest = anchor._chest_transform(true).affine_inverse() * wanted
	return anchor


func _chest_transform(rest: bool) -> Transform3D:
	var chest := skeleton.get_bone_global_rest(chest_bone) if rest else skeleton.get_bone_global_pose(chest_bone)
	return Transform3D(skeleton.global_basis.orthonormalized() * chest.basis.orthonormalized(), skeleton.global_transform * chest.origin)


## The anchor in world space as the skeleton is now. Read it inside the skeleton's update (skeleton_updated), where the pose
## includes every modifier.
func world_transform() -> Transform3D:
	return _chest_transform(false) * _in_chest

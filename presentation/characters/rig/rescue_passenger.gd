extends Node3D
## The carried rescue passenger: a second humanoid (the same MIRA model as the carrier, for now) with its own skeleton,
## draped over the carrier's shoulders in a fireman's carry. Purely visual: it is not a TacticalUnit, has no weapon, no
## animation controller and no IK, and is created and freed with the carrier's presentation, so it cannot change the
## rescued actor's lifecycle (the hidden mission actor stays what it was).
##
## Ownership: TacticalCharacterAdapter creates and frees this node and tells it which carrier bones to follow. This node owns the
## passenger's skeleton and its pose (PassivePassengerPose) and nothing of the carrier's.
##
## Reference frames:
##  - CARRIER FRAME: the carrier's character space (x = carrier's left, y up, z = the way the carrier faces).
##  - BODY FRAME: the passenger's own (x = its left, y = up its spine, z = the way its face looks).
##  - The passenger is face-down across the shoulders. BODY_TO_CARRY maps body to carrier frame: body y (up the spine)
##    runs along carrier -x (head toward the carrier's right), body z (face) points down, body x points along carrier +z.
##    carry_yaw_degrees then turns the body about the vertical so the head and torso hang behind the carrier and the
##    legs in front, the way a person is actually draped.
##  - ANCHOR: the passenger's abdomen (the Spine bone) is placed `anchor_from_neck` from the carrier's neck bone, measured
##    in the carrier frame in the carrier's neutral rest pose. That relation is then stored in the carrier's CHEST bone
##    frame and replayed every skeleton update, so the passenger leans, bobs and turns with the carrier's torso instead of
##    hanging from a fixed point in space. The passenger's own root origin is never the attachment point.

const PoseTable := preload("res://presentation/characters/rig/passive_passenger_pose.gd")
## Body frame -> carrier frame before the yaw. Columns are where the body's x, y and z axes point.
const BODY_TO_CARRY := Basis(Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, -1, 0))

## Turn about the vertical (negative sends the head end toward the carrier's back and the legs toward its front). Set before build.
var carry_yaw_degrees := -8.0
## Overrides for PassivePassengerPose.DEFAULTS. Set before build.
var pose_params := {}
var skeleton: Skeleton3D
## The passenger's own bone roles, from the rig profile of its model (see RigBones).
var bones: RigBones
var posed := false
## Who this passenger is (character, model, scale, rig profile). It travels with the body: the rig that carries it, the ground casualty it becomes on release and the next pickup all read it from here.
var definition: PassengerDefinition
## 1 = full size. The boarding presentation shrinks the passenger by tweening this (the node's own scale is derived from the
## carrier's chest every update, so it is not the place to animate size).
var presence := 1.0

@export_group("Lift (set by the interaction)")
## 0 = lying on the floor where the rescue target was, 1 = across the carrier's shoulders.
var lift := 1.0
## 0 = lying limb pose, 1 = draped limb pose.
var pose_blend := 1.0
## Where the abdomen lies on the floor (world), and the carrier's frame the lift path is built in.
var ground_origin := Vector3.INF
var waypoint_local := Vector3(0.0, 0.95, 0.38)
## Which way the body rolls about the carrier's x axis as it is lifted (-1: its face turns toward the carrier first).
var roll_direction := -1.0
## The node that supplies the carrier's frame (its character root).
var carrier_root: Node3D
## The orientation (world) the body lies in on the floor, when it has one that is not simply "across the carrier's front": the lift starts from it
## and settles into the carry's own orientation. Used when an incapacitated actor was already lying somewhere.
var ground_basis := Basis()
var has_ground_basis := false

@export_group("Secondary motion")
## Off gives the rigid carry. Everything here is a filter of the carrier's own chest motion, never a simulation.
var motion_enabled := true
## Largest displacement of the body from its anchor, metres, and largest tilt, degrees.
var motion_amplitude := 0.02
var motion_tilt_degrees := 1.5
## How quickly the body catches up with the chest (first-order response time, seconds). 0 turns the lag off.
var motion_response := 0.12
## Spine, head and free-arm swing (degrees at full lag) that follows the vertical lag.
var motion_swing_degrees := 4.0
## Read by tests and the workbench: the offset applied this frame (carrier frame) and the swing (-1..1).
var motion_offset := Vector3.ZERO
var motion_swing := 0.0
var motion_tilt := Quaternion.IDENTITY

var _body: Node3D
var _anchor: ChestAnchor
var _carrier_skeleton: Skeleton3D
var _body_to_skeleton := Basis.IDENTITY
var _carried_params := {}
var _applied_key := Vector2(-1.0, -1.0)
var _lag_position := Vector3.INF
var _lag_basis := Basis.IDENTITY
## The passenger skeleton's transform relative to this node (constant for a given pose; refreshed when the pose changes).
var _skeleton_in_node := Transform3D.IDENTITY

## Graspable places on the passenger, each a segment between two of ITS bones: where along it (from the first bone) and the
## limb's radius, metres. They follow the passenger's own skeleton, so a different pose or proportion moves them.
## `wrist`: the forearm just short of the hand (the carrier holds the wrist). `thigh`: above the knee (the carrier supports it).
const CONTACTS := {
	&"wrist": {"bone": &"LeftLowerArm", "child": &"LeftHand", "fraction": 0.85, "radius": 0.03},
	&"thigh": {"bone": &"LeftUpperLeg", "child": &"LeftLowerLeg", "fraction": 0.9, "radius": 0.075},
}


## Builds the passenger from `model_scene` (a humanoid with a Skeleton3D), scaled like the carrier's model, posed and with
## its abdomen at this node's origin. Call after the node is in the tree.
func build_from(passenger: PassengerDefinition) -> void:
	definition = passenger
	build(passenger.scene, passenger.scale, passenger.rig_profile)


func build(model_scene: PackedScene, model_scale: float, rig_profile: Resource) -> void:
	_body = Node3D.new()
	_body.name = "Body"
	_body.basis = Basis(Vector3.UP, deg_to_rad(carry_yaw_degrees)) * BODY_TO_CARRY
	add_child(_body)
	var model := model_scene.instantiate() as Node3D
	model.name = "PassengerModel"
	model.scale = Vector3.ONE * model_scale
	_body.add_child(model)
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	# The imported model carries ragdoll scaffolding (a PhysicalBoneSimulator3D with a physics body per bone). A passive
	# passenger needs none of it, and its bodies would otherwise sit in the physics world, so it is not kept.
	for simulator in skeleton.find_children("*", "PhysicalBoneSimulator3D", true, false):
		simulator.get_parent().remove_child(simulator)
		simulator.free()
	bones = RigBones.from_profile(rig_profile, skeleton)
	_body_to_skeleton = (_body.global_basis.orthonormalized().inverse() * skeleton.global_basis.orthonormalized()).inverse()
	_carried_params = PoseTable.DEFAULTS.duplicate()
	_carried_params.merge(pose_params, true)
	_repose(1.0, 0.0)


## Poses the skeleton for the given blend (0 lying, 1 draped) and the free limbs' swing, and re-measures where the abdomen is.
## Cheap, and only redone when the blend or the swing changed.
func _repose(blend: float, swing: float) -> void:
	var key := Vector2(snappedf(blend, 1.0 / 256.0), snappedf(swing, 1.0 / 64.0))
	if key == _applied_key or skeleton == null:
		return
	_applied_key = key
	var params := PoseTable.blend(PoseTable.LYING, _carried_params, blend)
	if absf(swing) > 0.0:
		var fold: Array = params.fold
		fold[4] = float(fold[4]) + swing * motion_swing_degrees
		fold[5] = float(fold[5]) + swing * motion_swing_degrees * 1.25
		var free_upper: Vector3 = params.free_upper
		var free_fore: Vector3 = params.free_fore
		params.free_upper = Vector3(free_upper.x, free_upper.y - swing * 0.05, free_upper.z)
		params.free_fore = Vector3(free_fore.x, free_fore.y - swing * 0.08, free_fore.z)
	posed = PoseTable.apply(skeleton, bones, _body_to_skeleton, params)
	_place_abdomen_on_origin()
	_skeleton_in_node = global_transform.affine_inverse() * skeleton.global_transform


## Moves the body so the abdomen (the attach bone) is at this node's origin.
func _place_abdomen_on_origin() -> void:
	var bone := skeleton.find_bone(bones.role(PoseTable.ATTACH_ROLE))
	if bone < 0:
		return
	var in_body := _body.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
	_body.position = -(_body.basis * in_body)


## Follows the carrier: the abdomen goes `anchor_from_neck` (carrier frame, rest pose) from the carrier's neck bone, held in
## the chest bone's frame from then on (ChestAnchor). `carrier_root` supplies the carrier frame.
func attach_to_carrier(carrier_skeleton: Skeleton3D, carrier_node: Node3D, chest_bone: StringName, neck_bone: StringName, anchor_from_neck: Vector3) -> void:
	_anchor = ChestAnchor.create(carrier_skeleton, carrier_node, chest_bone, neck_bone, anchor_from_neck)
	if _anchor == null:
		return
	_carrier_skeleton = carrier_skeleton
	if not carrier_skeleton.skeleton_updated.is_connected(_follow):
		carrier_skeleton.skeleton_updated.connect(_follow)
	_follow()


## Lies on the floor with no carrier (an incapacitated rescue target awaiting a carrier): the same lying pose the pickup starts from, so the
## swap to the carrier's passenger is invisible. `local_origin` is the abdomen's place and `yaw` the heading of the body, both in the parent's frame.
func lie_on_ground(local_origin: Vector3, yaw: float) -> void:
	lift = 0.0
	pose_blend = 0.0
	_repose(0.0, 0.0)
	# On its back, head toward the parent's right (the orientation the carrier's lift starts from), turned by `yaw`.
	transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI), local_origin)


## Puts the node where the current lift and the carrier's chest say, now (for after changing `lift` or `ground_origin` outside
## the skeleton's own update).
func refresh() -> void:
	_follow()


## Lets go of the carrier: the node moves to `new_parent` where it lies, stops following and keeps its pose (a passenger set
## down on the floor by a release).
func detach_to(new_parent: Node) -> void:
	if _carrier_skeleton != null and _carrier_skeleton.skeleton_updated.is_connected(_follow):
		_carrier_skeleton.skeleton_updated.disconnect(_follow)
	_anchor = null
	_carrier_skeleton = null
	if new_parent != null and get_parent() != new_parent:
		reparent(new_parent, true)


## Runs after the carrier's skeleton has been updated (all its modifiers included).
func _follow() -> void:
	if _anchor == null or not is_inside_tree():
		return
	global_transform = placement(_anchor.world_transform())


## Where this node is for a given carry anchor (the chest's, in world space): the anchor itself once lifted, and before that a
## point on the lift path (floor, up the carrier's front, onto the shoulders) with the body rolled over about the carrier's x
## axis, plus the restrained secondary offset. The one place the passenger's transform is decided.
func placement(anchor: Transform3D) -> Transform3D:
	var passenger_basis := anchor.basis.orthonormalized()
	var origin := anchor.origin
	if lift < 0.9999 and ground_origin.is_finite() and is_instance_valid(carrier_root):
		var rolled := smoothstep(0.1, 0.9, lift)
		passenger_basis = Basis(carrier_root.global_basis.orthonormalized().x, roll_direction * PI * (1.0 - rolled)) * passenger_basis
		if has_ground_basis:
			# From the way it actually lies to the lift's own orientation over the first third of the lift (never a snap at the start).
			passenger_basis = Basis(ground_basis.get_rotation_quaternion().slerp(passenger_basis.get_rotation_quaternion(), smoothstep(0.0, 0.35, lift)))
		var waypoint := carrier_root.global_transform * waypoint_local
		var control := waypoint * 2.0 - (ground_origin + origin) * 0.5
		var a := ground_origin.lerp(control, lift)
		var b := control.lerp(origin, lift)
		origin = a.lerp(b, lift)
	elif motion_enabled and motion_offset != Vector3.ZERO and is_instance_valid(carrier_root):
		var frame := carrier_root.global_basis.orthonormalized()
		origin += frame * motion_offset
		passenger_basis = frame * Basis(motion_tilt) * frame.inverse() * passenger_basis
	return Transform3D(passenger_basis * Basis.from_scale(Vector3.ONE * presence), origin)


## Called once per carrier skeleton pass, before the arms are solved: takes the interaction's lift and pose, advances the
## secondary motion, and poses the passenger. `anchor` is the chest anchor now (world), `delta` the frame time.
func update_presentation(new_lift: float, new_pose: float, anchor: Transform3D, delta: float) -> void:
	lift = new_lift
	pose_blend = new_pose
	_update_motion(anchor, delta)
	_repose(pose_blend, motion_swing)


## A first-order low-pass of the chest's own motion in the carrier's frame; the body trails it a little. Stationary: the filter
## settles and the offset is exactly zero. Not a spring: no overshoot, no energy, nothing to run away.
func _update_motion(anchor: Transform3D, delta: float) -> void:
	motion_offset = Vector3.ZERO
	motion_swing = 0.0
	motion_tilt = Quaternion.IDENTITY
	if not is_instance_valid(carrier_root):
		return
	var world_to_carrier := carrier_root.global_transform.affine_inverse()
	var local_origin := world_to_carrier * anchor.origin
	var local_basis := (world_to_carrier.basis * anchor.basis.orthonormalized()).orthonormalized()
	if _lag_position == Vector3.INF or lift < 0.9999 or not motion_enabled or motion_response <= 0.0:
		_lag_position = local_origin
		_lag_basis = local_basis
		return
	var k := 1.0 - exp(-maxf(delta, 0.0) / motion_response)
	_lag_position = _lag_position.lerp(local_origin, k)
	_lag_basis = Basis(_lag_basis.get_rotation_quaternion().slerp(local_basis.get_rotation_quaternion(), k))
	var offset := _lag_position - local_origin
	if offset.length() > motion_amplitude:
		offset = offset.normalized() * motion_amplitude
		_lag_position = local_origin + offset
	motion_offset = offset
	motion_swing = clampf(offset.y / maxf(motion_amplitude, 0.0001), -1.0, 1.0)
	# The same lag in orientation, as a small tilt of the whole body.
	var tilt := (_lag_basis.get_rotation_quaternion() * local_basis.get_rotation_quaternion().inverse())
	var angle := tilt.get_angle()
	if angle > deg_to_rad(motion_tilt_degrees):
		tilt = Quaternion.IDENTITY.slerp(tilt, deg_to_rad(motion_tilt_degrees) / angle)
		_lag_basis = Basis(tilt * local_basis.get_rotation_quaternion())
	motion_tilt = tilt


## Where the abdomen is, in this node's space (zero after build). Exposed for tests.
func anchor_point() -> Vector3:
	if skeleton == null:
		return Vector3.ZERO
	var bone := skeleton.find_bone(bones.role(PoseTable.ATTACH_ROLE))
	if bone < 0:
		return Vector3.ZERO
	return global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin


## The carrier's chest anchor in world space as the skeleton is now (read inside its update, where it includes the modifiers).
func anchor_world() -> Transform3D:
	return _anchor.world_transform() if _anchor != null else global_transform


## One graspable contact in world space, for this node placed at `anchor_world` (its true place, which the follow in the
## skeleton update has not reached yet when the carrier's arms are being solved). `from_point` is where the grasping arm comes
## from (the carrier's shoulder), unless `approach` (a world direction from the limb toward the hand) is given. Returns the point on the limb axis, the axis (toward the child bone), the unit `side`
## direction from the limb axis toward `from_point`, and the limb radius.
func contact_frame(contact: StringName, at_anchor: Transform3D, from_point: Vector3, approach := Vector3.ZERO) -> Dictionary:
	var definition: Dictionary = CONTACTS[contact]
	var to_world := placement(at_anchor) * _skeleton_in_node
	var bone := skeleton.find_bone(bones.role(definition.bone))
	var child := skeleton.find_bone(bones.role(definition.child))
	var start: Vector3 = to_world * skeleton.get_bone_global_pose(bone).origin
	var end: Vector3 = to_world * skeleton.get_bone_global_pose(child).origin
	var axis := (end - start).normalized()
	var point := start.lerp(end, float(definition.fraction))
	var side := approach if approach != Vector3.ZERO else from_point - point
	side = (side - axis * side.dot(axis)).normalized()
	return {"point": point, "axis": axis, "side": side, "radius": float(definition.radius) * presence}

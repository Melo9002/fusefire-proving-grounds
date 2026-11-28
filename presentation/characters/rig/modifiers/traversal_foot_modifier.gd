class_name TraversalFootModifier
extends SkeletonModifier3D
## Sets the ORIENTATION of the feet on stairs, right after the leg IK (Task: stair contact). The leg IK places each ankle where the stair planner says but leaves the foot's rotation to whatever the shin does, so a
## shin leaning over a tread tipped the foot toes-down and drove the ball of the foot into the tread (measured: the ball 4 cm below the surface at rest). Here a planted foot is turned flat to the surface: its
## rest orientation (the pose the model stands in), turned about the vertical with the body; the heel comes up a little toward toe-off by the same amount the planner lifts the ankle. A swinging foot is only
## partly levelled. Nothing is written when no stair pose is active, so every other pose is untouched.
##
## OWNS while active: the rotation of the two foot bones. NEVER positions, the legs, the pelvis or anything above. Reads the same typed input as the Traversal stage (TraversalPoseInput).

var input := TraversalPoseInput.new()
var skeleton: Skeleton3D
var character_frame: Node3D
## The foot bones and each one's rest orientation in the character's own frame (the model's standing pose).
var _bones: Array[int] = [-1, -1]
var _rest_in_character: Array[Basis] = [Basis.IDENTITY, Basis.IDENTITY]
## The ankle-to-ball distance (metres): the lever the heel lifts about.
var ball_length := 0.113
## How far a swinging foot is levelled (0 leaves it as the leg IK left it).
var swing_levelling := 0.6
var weight := 0.0


func setup(target: Skeleton3D, foot_bones: Array[StringName], frame: Node3D, ball_distance: float) -> bool:
	skeleton = target
	character_frame = frame
	ball_length = maxf(ball_distance, 0.03)
	var to_character := frame.global_transform.affine_inverse() * target.global_transform
	for side in 2:
		_bones[side] = target.find_bone(foot_bones[side])
		if _bones[side] < 0:
			return false
		_rest_in_character[side] = (to_character.basis * target.get_bone_global_rest(_bones[side]).basis).orthonormalized()
	return true


func _process_modification_with_delta(_delta: float) -> void:
	weight = 0.0
	if skeleton == null or not is_instance_valid(skeleton) or character_frame == null:
		return
	if input.mode == TraversalPoseInput.Mode.NONE or not input.solved:
		return
	if input.mode == TraversalPoseInput.Mode.GROUND:
		_apply_ground()
		return
	var ladder := input.mode == TraversalPoseInput.Mode.LADDER
	if not ladder:
		weight = input.weight
	var frame_basis := character_frame.global_basis.orthonormalized()
	var yaw := atan2(frame_basis.z.x, frame_basis.z.z)
	var yawed := Basis(Vector3.UP, yaw)
	var lateral := yawed.x
	for side in 2:
		var bone := _bones[side]
		var planted: bool = not ladder and input.planted[side]
		var amount := input.weight * (input.deck_levelling[side] if ladder else (1.0 if planted else swing_levelling))
		weight = maxf(weight, amount)
		if amount <= 0.001:
			continue
		var target := yawed * _rest_in_character[side]
		var lift: float = input.foot_lift[side] if planted else 0.0
		if lift > 0.0005:
			target = Basis(lateral, asin(clampf(lift / ball_length, 0.0, 0.6))) * target   # heel up: the toes tip down about the ball
		var parent := skeleton.get_bone_parent(bone)
		var parent_world := (skeleton.global_transform.basis * skeleton.get_bone_global_pose(parent).basis).orthonormalized()
		var local := (parent_world.inverse() * target).orthonormalized().get_rotation_quaternion()
		skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(local, clampf(amount, 0.0, 1.0)))


## Ground mode: a foot on the ground is turned flat to it (the animated orientation tipped from the vertical to the ground's normal), by how planted it is: a foot the gait has lifted keeps the animation's pitch.
func _apply_ground() -> void:
	weight = input.ground_weight
	if weight <= 0.001:
		return
	for side in 2:
		var planted := 1.0 - smoothstep(0.012, 0.07, input.ground_lift[side])
		var amount := weight * planted
		if amount <= 0.001:
			continue
		var tilt := Basis(Quaternion(Vector3.UP, input.ground_normal[side]))
		var target := tilt * input.foot_world_basis[side]
		var bone := _bones[side]
		var parent := skeleton.get_bone_parent(bone)
		var parent_world := (skeleton.global_transform.basis * skeleton.get_bone_global_pose(parent).basis).orthonormalized()
		var local := (parent_world.inverse() * target).orthonormalized().get_rotation_quaternion()
		skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(local, clampf(amount, 0.0, 1.0)))

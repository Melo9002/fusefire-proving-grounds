class_name ChallengeFault
extends SkeletonModifier3D
## A deliberately injected animation fault with a KNOWN cause, for ADDA's diagnostic challenges and tests. It is a plain SkeletonModifier3D added to a skeleton after a chosen stage (the rig, the stages and
## the game are untouched; nothing in the game creates it). It is the ground truth the challenges are scored against.
##
## A fault is described by a Dictionary (see `spec`):
##   kind     "offset"   moves `bone` by `vector` (metres, the skeleton's frame) for as long as it is active, from `start` seconds on (0 = always)
##            "pop"      the same, but only on one update in `every` (a one-frame pop, the way an unblended pose change looks)
##            "drift"    moves `bone` by `vector` * seconds-since-start (a slow slide)
##            "yaw"      turns the hips by `degrees` about the vertical axis (a facing error), after `start` seconds
##   bone     the bone's NAME in this skeleton, or a role such as "@right_hand" (see `resolve`)
##   after    the stage it is placed after (e.g. "HandGrip"); the default is last
##   name     the node's name (neutral for blind challenges)
## The offset is applied to the bone's GLOBAL position (so the limb below it follows), by rotating nothing: it only translates the bone's global pose, which the solvers after it have no chance to correct.

var spec := {}
var elapsed := 0.0
## Optional: a Callable returning the seconds since the scenario started.
var clock := Callable()
var updates := 0
var _bone := -1


static func install(rig: CharacterRig, p_spec: Dictionary, p_clock := Callable()) -> ChallengeFault:
	var fault := ChallengeFault.new()
	fault.clock = p_clock
	fault.spec = p_spec
	fault.name = String(p_spec.get("name", "ChallengeFault"))
	var skeleton := rig.skeleton
	var bone_name := resolve(rig, String(p_spec.get("bone", "")))
	fault._bone = skeleton.find_bone(bone_name)
	skeleton.add_child(fault)
	var after := skeleton.get_node_or_null(NodePath(String(p_spec.get("after", ""))))
	if after != null:
		skeleton.move_child(fault, after.get_index() + 1)
	return fault


## A bone name, or a role written "@right_hand", "@left_knee", "@right_foot", "@hips" (so one challenge fits both bodies).
static func resolve(rig: CharacterRig, text: String) -> String:
	if not text.begins_with("@"):
		return text
	var b := rig.bones
	match text.trim_prefix("@"):
		"hips": return String(b.hips)
		"head": return String(b.head)
		"left_hand": return String(b.left_arm[2])
		"right_hand": return String(b.right_arm[2])
		"left_elbow": return String(b.left_arm[1])
		"right_elbow": return String(b.right_arm[1])
		"left_knee": return String(b.left_leg[1])
		"right_knee": return String(b.right_leg[1])
		"left_foot": return String(b.left_leg[2])
		"right_foot": return String(b.right_leg[2])
	return ""


func _process_modification_with_delta(delta: float) -> void:
	# With a clock (the command line gives the scenario's time) the fault starts at the same scenario moment in a run and in an isolation; without one it counts skeleton updates since it was installed.
	elapsed = float(clock.call()) if clock.is_valid() else elapsed + delta
	updates += 1
	if float(spec.get("start", 0.0)) > elapsed:
		return
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	match String(spec.get("kind", "offset")):
		"offset":
			_move(skeleton, _vector(spec))
		"pop":
			if updates % maxi(int(spec.get("every", 60)), 1) == 0:
				_move(skeleton, _vector(spec))
		"drift":
			_move(skeleton, _vector(spec) * (elapsed - float(spec.get("start", 0.0))))
		"yaw":
			var hips := _bone
			if hips >= 0:
				var pose := skeleton.get_bone_global_pose(hips)
				skeleton.set_bone_global_pose(hips, Transform3D(Basis(Vector3.UP, deg_to_rad(float(spec.get("degrees", 20.0)))) * pose.basis, pose.origin))


func _vector(of: Dictionary) -> Vector3:
	var v: Array = of.get("vector", [0.0, 0.0, 0.0])
	return Vector3(float(v[0]), float(v[1]), float(v[2]))


func _move(skeleton: Skeleton3D, amount: Vector3) -> void:
	if _bone < 0:
		return
	var pose := skeleton.get_bone_global_pose(_bone)
	skeleton.set_bone_global_pose(_bone, Transform3D(pose.basis, pose.origin + amount))

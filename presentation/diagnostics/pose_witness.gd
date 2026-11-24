class_name PoseWitness
extends RefCounted
## ADDA's one witness of a skeleton's updates. A skeleton's pose is only final INSIDE its `skeleton_updated` signal: outside it `Skeleton3D.get_bone_global_pose` returns the animation pose WITHOUT the modifiers
## (measured on Godot 4.7.2 by tools/quality/skeleton_update_timing_probe.gd). Nothing can say, from outside, "am I inside the signal now?" (a flag cleared by a deferred call is still set when the next `_process`
## runs, also measured), so the contract is structural instead:
##   * every diagnostic that needs the final pose connects to `final_pose`, which this class emits from its own `skeleton_updated` handler, and nowhere else;
##   * every sample takes a `stamp()` there (update number, frame, time) and is judged later with `judge()`: a stamp from an earlier update is STALE, never silently re-read as current.
## One witness per skeleton (`PoseWitness.acquire(skeleton)`, paired with `release()`, kept in the skeleton's metadata), so every tool sees the same counter. It writes nothing to the rig.

signal final_pose

const META := &"adda_pose_witness"

var skeleton: Skeleton3D
## Number of `skeleton_updated` emissions seen since the witness was created.
var updates := 0
var last_frame := -1
var last_msec := -1
## True only while `final_pose` is being emitted (the one moment the pose is final).
var inside := false


## Number of tools currently using this witness; it removes itself from the skeleton when the last one lets go, so an idle skeleton carries no ADDA listener.
var users := 0


## The skeleton's witness, created on first use. Every user MUST pair this with `release()`.
static func acquire(p_skeleton: Skeleton3D) -> PoseWitness:
	if p_skeleton == null:
		return null
	var witness: PoseWitness = null
	if p_skeleton.has_meta(META):
		var existing = p_skeleton.get_meta(META)
		if existing is PoseWitness:
			witness = existing
	if witness == null:
		witness = PoseWitness.new()
		witness.skeleton = p_skeleton
		p_skeleton.skeleton_updated.connect(witness._on_updated)
		p_skeleton.set_meta(META, witness)
	witness.users += 1
	return witness


## Lets go of the witness; the last user to do so disconnects it from the skeleton.
func release() -> void:
	users -= 1
	if users <= 0:
		shutdown()


func _on_updated() -> void:
	updates += 1
	last_frame = Engine.get_process_frames()
	last_msec = Time.get_ticks_msec()
	inside = true
	final_pose.emit()
	inside = false


## The stamp of a sample taken NOW. It is final evidence only when `final` is true (the caller is a `final_pose` listener).
func stamp() -> Dictionary:
	return {"update": updates, "frame": Engine.get_process_frames(), "msec": Time.get_ticks_msec(), "final": inside, "witness": get_instance_id()}


## FRESH when the stamp was taken inside the update this witness last saw; STALE when the pose has been updated since, or when the stamp was not taken inside an update at all (its pose is the base pose).
func judge(p_stamp: Dictionary) -> Dictionary:
	if p_stamp.is_empty() or int(p_stamp.get("update", -1)) < 0:
		return {"status": Measurement.Status.UNAVAILABLE, "reason": "no sample has been taken"}
	if int(p_stamp.get("witness", 0)) != get_instance_id():
		return {"status": Measurement.Status.STALE, "reason": "taken under a different witness (the tool that sampled has been released or the skeleton re-attached)"}
	if not bool(p_stamp.get("final", false)):
		return {"status": Measurement.Status.STALE, "reason": "taken outside skeleton_updated: that pose is the animation pose without the modifiers, not what is drawn"}
	if int(p_stamp.update) != updates:
		return {"status": Measurement.Status.STALE, "reason": "taken for update %d, the skeleton is at update %d" % [int(p_stamp.update), updates]}
	return {"status": Measurement.Status.FRESH, "reason": ""}


## Disconnects the witness and removes it from the skeleton (clean-up in tests; sharing is the normal case).
func shutdown() -> void:
	if is_instance_valid(skeleton):
		if skeleton.skeleton_updated.is_connected(_on_updated):
			skeleton.skeleton_updated.disconnect(_on_updated)
		if skeleton.has_meta(META):
			skeleton.remove_meta(META)

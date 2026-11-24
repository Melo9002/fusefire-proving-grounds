extends SceneTree
## Research probe (ADDA): WHEN does `skeleton_updated` fire relative to _process / process_frame, and does a read of `get_bone_global_pose` inside the signal differ from one outside it?
##   godot_console --headless --path . --script res://tools/quality/skeleton_update_timing_probe.gd
## Prints, for 8 frames of a posed MIRA: the order of events (process_frame signal, a node's _process, the skeleton_updated handler, a deferred call from inside the handler, a _process after) and the wrist
## position read in each place, so the sampling contract in docs/claude/adda/ rests on this installed engine's behaviour, not on memory.
const SCENE := "res://art/characters/mira_0/runtime/mira_0_exploration_visual.tscn"
var log_lines: Array[String] = []
var wrist := -1
var skeleton: Skeleton3D
var inside := false

class Ticker extends Node:
	var owner_probe
	func _process(_d: float) -> void:
		owner_probe.note("node _process")

func _initialize() -> void:
	_run.call_deferred()

func note(what: String) -> void:
	var read := skeleton.global_transform * skeleton.get_bone_global_pose(wrist).origin
	log_lines.append("%-34s frame %d inside=%s wrist.y=%.4f" % [what, Engine.get_process_frames(), str(inside), read.y])

func _run() -> void:
	var host: ExplorationCharacterHost = (load(SCENE) as PackedScene).instantiate()
	root.add_child(host)
	var ticker := Ticker.new()
	ticker.owner_probe = self
	root.add_child(ticker)
	for i in 20:
		await process_frame
	skeleton = host.rig.skeleton
	wrist = skeleton.find_bone(host.rig.bones.right_arm[2])
	skeleton.skeleton_updated.connect(func() -> void:
		inside = true
		note("skeleton_updated handler")
		call_deferred("_after_signal"))
	process_frame.connect(func() -> void: note("process_frame signal"))
	for i in 6:
		# Move the pose each frame so a stale read is visible.
		host.rig.set_traversal_progress(1.0 + 0.1 * i) if false else null
		host.position.y = 0.0
		host.rig.character_root.rotation.y = 0.2 * i
		host.rig.skeleton.set_bone_pose_rotation(skeleton.find_bone(host.rig.bones.right_arm[0]), Quaternion(Vector3.RIGHT, 0.3 * i))
		log_lines.append("-- frame boundary")
		await process_frame
	for line in log_lines:
		print(line)
	quit(0)

func _after_signal() -> void:
	inside = false
	note("deferred after handler")

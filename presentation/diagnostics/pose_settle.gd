class_name PoseSettle
extends RefCounted
## ADDA's answer to "is this pose the settled one?". A FRESH final pose (PoseWitness) says the sample belongs to the update the skeleton is at; it does not say the pose has stopped changing. A pose requested
## cold (a ladder height jumped to, a scenario restarted, a state just entered) takes a few updates to arrive: the Assignment 3 ladder investigation measured 23 leg vertices inside a rung on the first update,
## 13 on the second and none from the third on, all FRESH. A capture or a clearance count taken on update 1 to 4 describes the transient, not the pose the character holds.
##
## This watches every bone's position in the SKELETON's frame (so the host moving through the world does not count) inside `final_pose`, and reports how far the pose moved since the previous update and for
## how many updates in a row it has moved less than a tolerance. Read-only; it keeps one position array and nothing else, and releases its witness when asked.
## It judges updates, not time: with the sim paused no update arrives and `status()` says so instead of guessing.

## Default tolerance (metres): a joint moving less than 0.5 mm per update. Default run: three updates in a row.
const DEFAULT_TOLERANCE := 0.0005
const DEFAULT_RUN := 3

var skeleton: Skeleton3D
var witness: PoseWitness
## Largest bone movement (metres) between the last two updates, and the bone that did it.
var movement := INF
var worst_bone := ""
## Consecutive updates whose movement stayed under `tolerance`.
var still_updates := 0
var updates_seen := 0
var tolerance := DEFAULT_TOLERANCE
var _previous: PackedVector3Array = PackedVector3Array()


func _init(p_skeleton: Skeleton3D, p_tolerance := DEFAULT_TOLERANCE) -> void:
	skeleton = p_skeleton
	tolerance = p_tolerance
	witness = PoseWitness.acquire(skeleton)
	witness.final_pose.connect(_on_final_pose)


func release() -> void:
	if witness != null and witness.final_pose.is_connected(_on_final_pose):
		witness.final_pose.disconnect(_on_final_pose)
		witness.release()


func _on_final_pose() -> void:
	updates_seen += 1
	var count := skeleton.get_bone_count()
	var current := PackedVector3Array()
	current.resize(count)
	var worst := 0.0
	var worst_index := -1
	for i in count:
		current[i] = skeleton.get_bone_global_pose(i).origin
		if _previous.size() == count:
			var moved := current[i].distance_to(_previous[i])
			if moved > worst:
				worst = moved
				worst_index = i
	if _previous.size() != count:
		movement = INF
		still_updates = 0
		worst_bone = ""
	else:
		movement = worst
		worst_bone = String(skeleton.get_bone_name(worst_index)) if worst_index >= 0 else ""
		still_updates = still_updates + 1 if worst < tolerance else 0
	_previous = current


## Forgets the history: call it when you change what the pose should be (the next updates are then judged from scratch).
func reset() -> void:
	_previous = PackedVector3Array()
	movement = INF
	still_updates = 0
	worst_bone = ""


## True when the pose moved less than the tolerance for `run` updates in a row.
func is_settled(run := DEFAULT_RUN) -> bool:
	return still_updates >= run


## A readable answer for a report or a capture: {settled, still_updates, movement_mm, worst_bone, updates_seen, reason}.
func status(run := DEFAULT_RUN) -> Dictionary:
	var settled := is_settled(run)
	var reason := ""
	if updates_seen == 0:
		reason = "no update has been seen (is the simulation paused or the skeleton not updating?)"
	elif updates_seen == 1:
		reason = "one update seen: nothing to compare it with yet"
	elif not settled:
		reason = "still moving: %s moved %.1f mm in the last update; %d of %d still updates so far" % [worst_bone, movement * 1000.0, still_updates, run]
	return {"settled": settled, "still_updates": still_updates, "movement_mm": movement * 1000.0 if is_finite(movement) else -1.0, "worst_bone": worst_bone,
		"updates_seen": updates_seen, "tolerance_mm": tolerance * 1000.0, "reason": reason}

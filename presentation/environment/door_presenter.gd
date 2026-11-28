class_name DoorPresenter
extends Node
## The visual of the map's doors, following the committed authoritative state (MapData.doors). It never decides anything: a door's leaf is the Kenney `door.glb` instance the parcel scene marks with `door_visual_id`,
## moved by that model's own `open` and `close` animations; a label above it says what the door is and in which state. Animation never gates the rules (the state is committed before the animation starts, and a
## suppressed or skipped presentation snaps the leaf to the committed pose), so replay speed and fast execution cannot change the outcome.

const ANIMATION_OPEN := &"open"
const ANIMATION_CLOSE := &"close"

var _map: MapData
var _visuals: Dictionary = {}   # door id -> {"node": Node3D, "player": AnimationPlayer, "label": Label3D}


func setup(map: MapData, scene_root: Node) -> void:
	_map = map
	for node in scene_root.find_children("*", "Node3D", true, false):
		if not node.has_meta("door_visual_id"):
			continue
		var id := StringName(node.get_meta("door_visual_id"))
		if not map.doors.has(id) or _visuals.has(id):
			continue
		var players := node.find_children("*", "AnimationPlayer", true, false)
		var label := Label3D.new()
		label.name = "DoorLabel_%s" % id
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = true
		label.pixel_size = 0.0008
		label.font_size = 28
		label.outline_size = 8
		label.modulate = Color(1.0, 0.9, 0.55)
		label.position = Vector3(0.0, 2.9 / 1.5, 0.0)
		node.add_child(label)
		_visuals[id] = {"node": node, "player": players[0] if not players.is_empty() else null, "label": label}
		_snap(id)


func has_visual(door_id: StringName) -> bool:
	return _visuals.has(door_id)


## The leaf as the committed state shows it, at once.
func _snap(door_id: StringName) -> void:
	var visual: Dictionary = _visuals[door_id]
	var door: DoorData = _map.doors[door_id]
	var player: AnimationPlayer = visual.player
	if player != null:
		var clip: StringName = ANIMATION_OPEN if door.state == DoorData.OPEN else ANIMATION_CLOSE
		if player.has_animation(clip):
			player.play(clip)
			player.seek(player.get_animation(clip).length, true)
			player.pause()
	_update_label(door_id)


func _update_label(door_id: StringName) -> void:
	var door: DoorData = _map.doors[door_id]
	(_visuals[door_id].label as Label3D).text = "DOOR · %s" % String(door.state).to_upper()


## Plays the committed change. `skip` (fast execution, replay with presentation suppressed) snaps instead of animating.
func present(door_id: StringName, skip := false) -> void:
	if not _visuals.has(door_id):
		return
	var visual: Dictionary = _visuals[door_id]
	var door: DoorData = _map.doors[door_id]
	_update_label(door_id)
	var player: AnimationPlayer = visual.player
	if player == null or skip:
		_snap(door_id)
		return
	var clip: StringName = ANIMATION_OPEN if door.state == DoorData.OPEN else ANIMATION_CLOSE
	if not player.has_animation(clip):
		return
	player.play(clip)
	# Bounded wait: the rules have already moved on; this only paces the presentation.
	var waited := 0.0
	while player.is_playing() and waited < 2.0 and is_inside_tree():
		await get_tree().process_frame
		waited += get_process_delta_time()
	_snap(door_id)

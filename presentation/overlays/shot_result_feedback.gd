class_name ShotResultFeedback
extends Node3D

## Brief HIT/MISS feedback projected from the target's world position into the HUD.
## Keeping the label in screen space gives it a predictable readable size at every zoom.

@export var battle_controller: BattleController
@export var ui_layer: CanvasLayer
## Replay is intended for clean battlefield review; live shots keep their readable result cue.
@export var show_during_replay := false

@export_group("Appearance")
@export var target_offset := Vector3(0.0, 2.25, 0.0)
@export var hit_color := Color(1.0, 0.31, 0.22, 1.0)
@export var miss_color := Color(0.78, 0.84, 0.91, 1.0)
@export_range(12, 64, 1, "suffix:px") var screen_font_size := 24
@export_range(0, 12, 1, "suffix:px") var outline_size := 4

@export_group("Motion")
@export_range(0.1, 3.0, 0.05, "suffix:s") var lifetime_seconds := 0.85
@export_range(0.0, 2.0, 0.05, "suffix:m") var rise_distance := 0.55

var last_result_text := ""
var last_target_position := Vector3.ZERO
var _cue_layer: Control
var _active_cues: Array[Dictionary] = []


func _ready() -> void:
	if battle_controller != null:
		battle_controller.attack_resolved.connect(_on_attack_resolved)
	_build_cue_layer()
	set_process(false)


func _exit_tree() -> void:
	if is_instance_valid(_cue_layer):
		_cue_layer.queue_free()


func _build_cue_layer() -> void:
	if ui_layer == null:
		push_warning("ShotResultFeedback needs a CanvasLayer assigned to ui_layer.")
		return
	_cue_layer = Control.new()
	_cue_layer.name = "ShotResultCues"
	_cue_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cue_layer.z_index = 20
	ui_layer.add_child(_cue_layer)
	_cue_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _on_attack_resolved(_attacker: TacticalUnit, target: TacticalUnit, did_hit: bool, _hit_chance: int) -> void:
	if battle_controller != null and battle_controller.replay_mode and not show_during_replay:
		return
	if target == null or not is_instance_valid(target) or not is_instance_valid(_cue_layer):
		return

	last_result_text = "HIT" if did_hit else "MISS"
	last_target_position = target.global_position

	var cue := Label.new()
	cue.text = last_result_text
	cue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cue.add_theme_font_size_override("font_size", screen_font_size)
	cue.add_theme_constant_override("outline_size", outline_size)
	cue.add_theme_color_override("font_color", hit_color if did_hit else miss_color)
	cue.add_theme_color_override("font_outline_color", Color(0.025, 0.035, 0.055, 0.92))
	_cue_layer.add_child(cue)
	cue.reset_size()

	_active_cues.append({
		"label": cue,
		"world_anchor": last_target_position + target_offset,
		"elapsed": 0.0,
	})
	set_process(true)
	_update_cues(0.0)


func _process(delta: float) -> void:
	_update_cues(delta)


func _update_cues(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	for index in range(_active_cues.size() - 1, -1, -1):
		var cue_data: Dictionary = _active_cues[index]
		var cue: Label = cue_data["label"]
		if not is_instance_valid(cue):
			_active_cues.remove_at(index)
			continue

		var elapsed := float(cue_data["elapsed"]) + delta
		if elapsed >= lifetime_seconds:
			cue.queue_free()
			_active_cues.remove_at(index)
			continue

		cue_data["elapsed"] = elapsed
		_active_cues[index] = cue_data
		var progress := elapsed / lifetime_seconds
		var eased_rise := 1.0 - pow(1.0 - progress, 2.0)
		var world_position: Vector3 = cue_data["world_anchor"]
		world_position.y += rise_distance * eased_rise

		if camera == null or camera.is_position_behind(world_position):
			cue.hide()
			continue

		cue.show()
		cue.position = camera.unproject_position(world_position) - cue.size * 0.5
		cue.modulate.a = 1.0 - progress

	if _active_cues.is_empty():
		set_process(false)

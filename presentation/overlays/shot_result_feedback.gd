class_name ShotResultFeedback
extends Node3D

@export var battle_controller: BattleController
@export_group("Appearance")
@export var target_offset := Vector3(0.0, 2.25, 0.0)
@export var hit_color := Color(1.0, 0.28, 0.18, 1.0)
@export var miss_color := Color(0.75, 0.82, 0.9, 1.0)
@export_range(16, 96, 1) var font_size := 20
@export_group("Motion")
@export_range(0.1, 3.0, 0.05, "suffix:s") var lifetime_seconds := 0.85
@export_range(0.0, 2.0, 0.05, "suffix:m") var rise_distance := 0.55

var last_result_text := ""
var last_target_position := Vector3.ZERO

func _ready() -> void:
	if battle_controller and not battle_controller.attack_resolved.is_connected(_on_attack_resolved):
		battle_controller.attack_resolved.connect(_on_attack_resolved)

func _on_attack_resolved(_attacker: TacticalUnit, target: TacticalUnit, did_hit: bool, _hit_chance: int) -> void:
	if not is_instance_valid(target):
		return
	last_result_text = "HIT" if did_hit else "MISS"
	last_target_position = target.global_position
	var cue := Label3D.new()
	cue.name = "ShotResult_%s" % last_result_text
	cue.text = last_result_text
	cue.font_size = font_size
	cue.outline_size = 8
	cue.modulate = hit_color if did_hit else miss_color
	cue.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	cue.fixed_size = true
	cue.no_depth_test = true
	add_child(cue)
	cue.global_position = last_target_position + target_offset
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(cue, "global_position", cue.global_position + Vector3.UP * rise_distance, lifetime_seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(cue, "modulate:a", 0.0, lifetime_seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(cue.queue_free)

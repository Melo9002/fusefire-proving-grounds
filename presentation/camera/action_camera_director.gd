class_name ActionCameraDirector
extends Node

enum Frequency { OFF, FINAL_ACTIONS, COMBAT_ONLY, ALL_ACTIONS }

const SETTINGS_PATH := "user://camera_settings.cfg"
const SETTINGS_SECTION := "camera"
const FREQUENCY_KEY := "action_camera_frequency"

var tactical_camera: TacticalCamera
var frequency: Frequency = Frequency.FINAL_ACTIONS

func _ready() -> void:
	add_to_group("action_camera_director")
	_load_settings()

func setup(camera_rig: TacticalCamera) -> void:
	tactical_camera = camera_rig

func set_frequency(value: Frequency) -> void:
	frequency = value
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
	settings.set_value(SETTINGS_SECTION, FREQUENCY_KEY, int(frequency))
	settings.save(SETTINGS_PATH)

func should_present(kind: StringName, ap_after: int, important := false) -> bool:
	match frequency:
		Frequency.OFF:
			return false
		Frequency.FINAL_ACTIONS:
			return important or ap_after <= 0
		Frequency.COMBAT_ONLY:
			return important or kind in [&"attack", &"ability"]
		Frequency.ALL_ACTIONS:
			return true
	return false

func present(actor: TacticalUnit, kind: StringName, focus_point: Vector3, ap_after: int, important := false, force := false) -> bool:
	if not is_instance_valid(tactical_camera) or not is_instance_valid(actor):
		return false
	if not force and not should_present(kind, ap_after, important):
		return false
	tactical_camera.frame_cinematic_action(actor, focus_point)
	while is_instance_valid(tactical_camera) and tactical_camera.is_camera_transitioning():
		await get_tree().process_frame
	return true

func finish_live_presentation(was_presented: bool) -> void:
	if not was_presented or not is_instance_valid(tactical_camera):
		return
	tactical_camera.return_to_tactical_view()
	while is_instance_valid(tactical_camera) and tactical_camera.is_camera_transitioning():
		await get_tree().process_frame

func _load_settings() -> void:
	var settings := ConfigFile.new()
	if settings.load(SETTINGS_PATH) != OK:
		return
	frequency = clampi(int(settings.get_value(SETTINGS_SECTION, FREQUENCY_KEY, Frequency.FINAL_ACTIONS)), Frequency.OFF, Frequency.ALL_ACTIONS) as Frequency

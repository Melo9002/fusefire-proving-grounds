class_name BattleUXSettings
extends RefCounted
## Local presentation preferences. Never part of combat or replay rules.
static var storage_path := "user://battle_ux.cfg"
static var loaded := false
static var confirm_actions := true
static var confirm_movement := false

static func load_preferences() -> void:
	if loaded: return
	loaded = true
	var config := ConfigFile.new()
	if config.load(storage_path) == OK:
		confirm_actions = bool(config.get_value("confirmations", "actions", true))
		confirm_movement = bool(config.get_value("confirmations", "movement", false))

static func save_preferences() -> Error:
	var config := ConfigFile.new()
	config.set_value("confirmations", "actions", confirm_actions)
	config.set_value("confirmations", "movement", confirm_movement)
	return config.save(storage_path)

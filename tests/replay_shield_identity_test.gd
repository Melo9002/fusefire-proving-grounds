extends SceneTree
## Issue #31: a recording remembers the Shield settings it was made with, and playback refuses it
## before any action runs when those settings changed. Recordings without the field behave as before.

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _recording(configuration: Dictionary) -> BattleReplayRecording:
	var recording := BattleReplayRecording.new()
	recording.configuration = configuration
	recording.shield_capability_signature = BattleReplayRecording.shield_signature_for(configuration)
	return recording

func _run() -> void:
	var shield_battle := {"shield_enabled": true, "player_archetypes": ["shieldbearer", "generic"], "enemy_archetypes": ["generic"], "ally_archetypes": []}
	var capability: ShieldCapability = TacticalArchetypeCatalog.get_definition(&"shieldbearer").shield_capability
	check(capability != null, "Setup: the Shieldbearer archetype has a Shield capability")

	var recording := _recording(shield_battle)
	check(not recording.shield_capability_signature.is_empty(), "A Shield battle records its Shield identity")
	check(recording.shield_identity_message().is_empty(), "Unchanged settings are compatible")
	var reloaded := BattleReplayRecording.from_dictionary(recording.to_dictionary())
	check(reloaded.shield_capability_signature == recording.shield_capability_signature, "The identity survives saving and loading")
	check(reloaded.shield_identity_message().is_empty(), "A reloaded recording with unchanged settings is compatible")

	# Every replay-relevant value is covered: editing any one is refused with a clear reason.
	var edits := {
		"AP cost": func(): capability.stance_ap_cost += 1,
		"protected arc": func(): capability.protected_arc_degrees -= 30.0,
		"accuracy modifier": func(): capability.accuracy_modifier += 10,
		"damage multiplier": func(): capability.damage_multiplier += 0.15,
		"attacks allowed": func(): capability.attacks_allowed = not capability.attacks_allowed,
		"reload allowed": func(): capability.reload_allowed = not capability.reload_allowed,
		"a tiny damage edit": func(): capability.damage_multiplier += 0.000001,
	}
	for label in edits:
		var original := [capability.stance_ap_cost, capability.protected_arc_degrees, capability.accuracy_modifier, capability.damage_multiplier, capability.attacks_allowed, capability.reload_allowed]
		edits[label].call()
		var message := recording.shield_identity_message()
		check(not message.is_empty() and message.contains("Shield") and message.contains("new recording"), "Editing the %s is refused clearly (%s)" % [label, message])
		# The refusal comes first in validation, before any action could play.
		var saved := BattleReplayRecording.from_dictionary(recording.to_dictionary())
		check(saved.validation_message().begins_with("Incompatible replay Shield settings"), "A recording made before the %s edit is refused as a Shield mismatch (%s)" % [label, saved.validation_message()])
		capability.stance_ap_cost = original[0]
		capability.protected_arc_degrees = original[1]
		capability.accuracy_modifier = original[2]
		capability.damage_multiplier = original[3]
		capability.attacks_allowed = original[4]
		capability.reload_allowed = original[5]
		check(recording.shield_identity_message().is_empty(), "Restoring the settings makes the recording compatible again (%s)" % label)

	# A Shield edit only matters to battles whose archetypes use that Shield.
	var generic_battle := {"shield_enabled": true, "player_archetypes": ["generic"], "enemy_archetypes": ["generic"], "ally_archetypes": []}
	var generic_recording := _recording(generic_battle)
	capability.damage_multiplier += 0.2
	check(generic_recording.shield_identity_message().is_empty(), "A battle without Shieldbearers ignores a Shield edit")
	check(not recording.shield_identity_message().is_empty(), "A battle with a Shieldbearer does not")
	capability.damage_multiplier -= 0.2

	# Shield disabled: the settings are irrelevant, nothing is recorded or checked.
	var disabled := {"shield_enabled": false, "player_archetypes": ["shieldbearer"], "enemy_archetypes": [], "ally_archetypes": []}
	check(BattleReplayRecording.shield_signature_for(disabled).is_empty(), "A battle without Shield records no identity")
	var disabled_recording := _recording(disabled)
	disabled_recording.shield_capability_signature = recording.shield_capability_signature
	capability.accuracy_modifier += 10
	check(disabled_recording.shield_identity_message().is_empty(), "With Shield disabled, edited settings are not checked")
	capability.accuracy_modifier -= 10

	# Recordings made before this field existed are not checked, as before.
	var legacy := BattleReplayRecording.new()
	legacy.configuration = shield_battle
	check(legacy.shield_identity_message().is_empty(), "A recording without the field behaves as before")

	# An archetype that no longer exists changes the identity instead of being ignored.
	check(TacticalArchetypeCatalog.shield_signature(["ghost"]) != TacticalArchetypeCatalog.shield_signature(["generic"]), "An unknown archetype is not treated as Generic")
	check(TacticalArchetypeCatalog.shield_signature(["shieldbearer", "generic"]) == TacticalArchetypeCatalog.shield_signature(["generic", "shieldbearer", "generic"]), "Order and duplicates do not change the identity")

	print("Replay Shield identity: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

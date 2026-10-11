class_name MissionCatalog
extends RefCounted

const PRESETS := [
	{"title": "Eliminate", "description": "Defeat all enemy combatants.", "kind": MissionObjectiveDefinition.Kind.ELIMINATE},
	{"title": "Protect", "description": "Keep the friendly VIP alive.", "kind": MissionObjectiveDefinition.Kind.PROTECT},
	{"title": "Rescue", "description": "Rescue a neutral mission actor.", "kind": MissionObjectiveDefinition.Kind.RESCUE},
	{"title": "Reach", "description": "Move a player unit into the destination area.", "kind": MissionObjectiveDefinition.Kind.REACH},
	{"title": "Survive", "description": "Keep the squad alive for three rounds.", "kind": MissionObjectiveDefinition.Kind.SURVIVE},
	{"title": "Extract", "description": "Bring the mission target to extraction.", "kind": MissionObjectiveDefinition.Kind.EXTRACT},
	{"title": "Enemy Evacuation", "description": "Defeat every enemy before any can escape.", "kind": MissionObjectiveDefinition.Kind.ENEMY_EVACUATION},
	{"title": "Terminal", "description": "Reach and activate the mission terminal.", "kind": MissionObjectiveDefinition.Kind.INTERACT_TERMINAL},
]

static func get_preset_names() -> Array[String]:
	var names: Array[String] = []
	for preset in PRESETS:
		names.append(preset.title)
	return names

static func create_mission(preset_index: int, enemy_count: int, include_vip := false) -> MissionDefinition:
	var safe_index := clampi(preset_index, 0, PRESETS.size() - 1)
	var preset: Dictionary = PRESETS[safe_index]
	var mission := MissionDefinition.new()
	mission.mission_id = StringName("prototype_%s" % String(preset.title).to_snake_case())
	mission.title = "%s Test" % preset.title
	match preset.kind:
		MissionObjectiveDefinition.Kind.PROTECT:
			mission.objectives = [_objective(&"eliminate", MissionObjectiveDefinition.Kind.ELIMINATE, "Eliminate Enemies", enemy_count), _objective(&"protect", MissionObjectiveDefinition.Kind.PROTECT, "Protect VIP", 1, [&"FriendlyVIP"])]
		MissionObjectiveDefinition.Kind.RESCUE:
			mission.objectives = [_objective(&"rescue", MissionObjectiveDefinition.Kind.RESCUE, "Rescue VIP", 1, [&"RescueTarget"]), _objective(&"extract_rescue", MissionObjectiveDefinition.Kind.EXTRACT, "Extract Rescued VIP", 1, [&"RescueTarget"])]
		MissionObjectiveDefinition.Kind.SURVIVE:
			mission.objectives = [_objective(&"survive", MissionObjectiveDefinition.Kind.SURVIVE, "Survive", 3), _objective(&"extract_units", MissionObjectiveDefinition.Kind.EXTRACT, "Extract Survivors", 1)]
		MissionObjectiveDefinition.Kind.EXTRACT:
			var squad := _objective(&"extract_units", MissionObjectiveDefinition.Kind.EXTRACT, "Extract Units", 1)
			squad.required = false
			mission.objectives = [squad]
			if include_vip:
				mission.objectives.push_front(_objective(&"extract_vips", MissionObjectiveDefinition.Kind.EXTRACT, "Extract VIPs", 1, [&"FriendlyVIP"]))
		MissionObjectiveDefinition.Kind.ENEMY_EVACUATION:
			var stop_escape := _objective(&"stop_enemy_evacuation", MissionObjectiveDefinition.Kind.ELIMINATE, "Stop Enemy Evacuation", enemy_count)
			var enemy_escape := _objective(&"enemy_escape", MissionObjectiveDefinition.Kind.EXTRACT, "Enemies Escaped", enemy_count)
			enemy_escape.required = false
			enemy_escape.zone_id = &"enemy_extract"
			enemy_escape.pursuing_factions = 1 << TacticalUnit.Faction.ENEMY
			mission.objectives = [stop_escape, enemy_escape]
		MissionObjectiveDefinition.Kind.INTERACT_TERMINAL:
			var objective := _objective(&"activate_terminal", MissionObjectiveDefinition.Kind.INTERACT_TERMINAL, "Activate Terminal", 1, [&"main_terminal"])
			var terminal := MissionTerminalDefinition.new()
			terminal.terminal_id = &"main_terminal"
			terminal.objective_id = objective.objective_id
			mission.objectives = [objective]
			mission.terminals = [terminal]
		_:
			var target := enemy_count if preset.kind == MissionObjectiveDefinition.Kind.ELIMINATE else 1
			var ids: Array[StringName] = []
			if preset.kind == MissionObjectiveDefinition.Kind.REACH: ids.append(&"reach")
			mission.objectives = [_objective(StringName(String(preset.title).to_snake_case()), preset.kind, preset.title, target, ids)]
	return mission

static func _objective(id: StringName, kind: MissionObjectiveDefinition.Kind, title: String, amount: int, ids: Array[StringName] = []) -> MissionObjectiveDefinition:
	var objective := MissionObjectiveDefinition.new()
	objective.objective_id = id
	objective.kind = kind
	objective.title = title
	objective.target_amount = amount
	objective.target_ids = ids
	return objective

extends SceneTree

const MissionIntentData = preload("res://systems/objectives/mission_intent.gd")

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var manager := ObjectiveManager.new()
	root.add_child(manager)
	var unit_scene := load("res://units/tactical_unit.tscn") as PackedScene
	var friendly := unit_scene.instantiate() as TacticalUnit
	friendly.faction = TacticalUnit.Faction.ALLY
	var enemy := unit_scene.instantiate() as TacticalUnit
	enemy.faction = TacticalUnit.Faction.ENEMY

	manager.load_mission(MissionCatalog.create_mission(3, 2))
	var reach := manager.get_mission_intent(friendly)
	check(reach.kind == MissionIntentData.Kind.REACH and reach.zone_id == &"reach", "Reach missions produce a destination intent")
	check(not manager.get_mission_intent(enemy).is_actionable(), "Player-owned objectives do not direct enemy AI")
	manager.mission.objectives[0].pursuing_factions = 1 << TacticalUnit.Faction.ENEMY
	check(manager.get_mission_intent(enemy).kind == MissionIntentData.Kind.REACH, "Objective ownership can assign the same mission goal to enemies")
	check(not manager.get_mission_intent(friendly).is_actionable(), "Units ignore objectives their faction does not pursue")

	manager.load_mission(MissionCatalog.create_mission(2, 2))
	check(manager.get_mission_intent(friendly).kind == MissionIntentData.Kind.RESCUE, "Rescue takes priority before extraction")
	manager.complete_objective(&"rescue")
	check(manager.get_mission_intent(friendly).kind == MissionIntentData.Kind.EXTRACT, "Completed rescue changes the mission intent to extraction")

	manager.load_mission(MissionCatalog.create_mission(1, 2, true))
	var protect := manager.get_mission_intent(friendly)
	check(protect.kind == MissionIntentData.Kind.PROTECT and protect.target_ids.has(&"FriendlyVIP"), "Protect intent retains its mission actor IDs")

	manager.load_mission(MissionCatalog.create_mission(4, 2))
	check(manager.get_mission_intent(friendly).kind == MissionIntentData.Kind.SURVIVE, "Survive remains the goal before evacuation unlocks")

	manager.load_mission(MissionCatalog.create_mission(0, 2))
	check(manager.get_mission_intent(friendly).kind == MissionIntentData.Kind.ELIMINATE, "Eliminate exposes the combat mission goal")

	manager.load_mission(MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.INTERACT_TERMINAL, 1, false))
	check(manager.get_mission_intent(friendly).kind == MissionIntentData.Kind.INTERACT_TERMINAL, "Terminal objectives expose an explicit interaction intent")
	check(not manager.get_mission_intent(enemy).is_actionable(), "Player-owned terminals never direct hostile AI")

	friendly.free()
	enemy.free()
	print("AI mission intent smoke: %d failure(s)" % failures)
	quit(1 if failures else 0)

extends SceneTree
## Milestone 06.09 acceptance: how long a door transition takes. Authoritative work (microseconds, measured with the monotonic clock) is separated from the animation (the Kenney leaf's own clip lengths).
##   godot_console --headless --path . --script res://docs/quality/evidence/interaction-range/door_timing_probe.gd
## Per transition: MapDoors.check, MapDoors.apply alone, the graph rebuild alone (MapGraphBuilder.build), apply_with_graph (the whole geometry transaction), and submit_door end to end with presentation suppressed.
const Catalog := preload("res://systems/generation/battlefield_catalog.gd")
const Scene := preload("res://levels/prototype_map/prototype_map.tscn")
const DOOR := &"door_a"
const ROUNDS := 30


func _initialize() -> void:
	_run.call_deferred()


func _stats(label: String, samples: Array) -> void:
	samples.sort()
	var total := 0.0
	for value in samples:
		total += value
	print("%-44s median %8.0f us   mean %8.0f us   max %8.0f us   (n=%d)" % [label, samples[samples.size() / 2], total / samples.size(), samples[samples.size() - 1], samples.size()])


func _run() -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(Catalog.INTERACTION_RANGE)
	config.player_count = 1
	config.enemy_count = 1
	config.battle_seed = 4
	config.content_manifest = {"population_enabled": false}
	var level := Scene.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	await create_timer(0.5).timeout
	var battle := level.battle_controller
	var grid := battle.grid_manager
	var map := grid.map_data
	var service := battle.action_service
	var pf := battle.pathfinder
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	grid.update_unit_position(actor, grid.get_unit_grid(actor), Vector3i(7, 0, 11))
	actor.global_position = grid.grid_to_world(Vector3i(7, 0, 11)) + Vector3.UP * actor.standing_height
	var door: DoorData = map.doors[DOOR]
	print("map cells %d, graph points %d, region cells %d" % [map.cells.size(), pf.grid_to_id_map.size(), door.region().size()])
	var check_us: Array = []
	var apply_us: Array = []
	var rebuild_us: Array = []
	var whole_us: Array = []
	var submit_us: Array = []
	for round in ROUNDS:
		var desired: StringName = DoorData.OPEN if door.state == DoorData.CLOSED else DoorData.CLOSED
		var t := Time.get_ticks_usec()
		var verdict := MapDoors.check(map, grid, actor, DOOR, desired)
		check_us.append(Time.get_ticks_usec() - t)
		if not verdict.ok:
			print("unexpected rejection ", verdict)
			break
		t = Time.get_ticks_usec()
		var backup := MapDoors.apply(map, DOOR, desired)
		apply_us.append(Time.get_ticks_usec() - t)
		t = Time.get_ticks_usec()
		var live := pf.live_grid
		MapGraphBuilder.build(map, pf)
		pf.live_grid = live
		rebuild_us.append(Time.get_ticks_usec() - t)
		MapDoors.rollback(map, DOOR, backup)
		MapGraphBuilder.build(map, pf)
		pf.live_grid = live
		t = Time.get_ticks_usec()
		MapDoors.apply_with_graph(map, pf, DOOR, desired)
		whole_us.append(Time.get_ticks_usec() - t)
		MapDoors.apply_with_graph(map, pf, DOOR, DoorData.CLOSED if desired == DoorData.OPEN else DoorData.OPEN)
		t = Time.get_ticks_usec()
		var result := await service.submit_door(service.make_door_request(&"open_door" if door.state == DoorData.CLOSED else &"close_door", actor, DOOR, TacticalActionRequest.Source.PLAYER), true)
		submit_us.append(Time.get_ticks_usec() - t)
		if result == null:
			print("submit rejected ", service.last_rejection.message)
			break
	_stats("check (read-only validation)", check_us)
	_stats("apply (cells, parts, obstacles, LOS index)", apply_us)
	_stats("graph rebuild (MapGraphBuilder.build)", rebuild_us)
	_stats("apply_with_graph (whole geometry transaction)", whole_us)
	_stats("submit_door end to end (no presentation)", submit_us)
	var presenter := level.get_node_or_null("DoorPresenter") as DoorPresenter
	var leaf := level.find_child("DoorLeaf", true, false)
	var player: AnimationPlayer = null
	if leaf != null:
		for candidate in leaf.find_children("*", "AnimationPlayer", true, false):
			player = candidate
	if player != null:
		print("animation: open %.2f s, close %.2f s (presentation only; the state is committed before it starts)" % [player.get_animation("open").length, player.get_animation("close").length])
	else:
		print("animation player not found (presenter %s)" % presenter)
	level.queue_free()
	await process_frame
	quit()

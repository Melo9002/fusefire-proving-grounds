extends SceneTree

const UNIT_SCENE := preload("res://units/tactical_unit.tscn")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var grid := GridManager.new()
	root.add_child(grid)
	var registry := TacticalActorRegistry.new()
	var presenter := TacticalActionPresenter.new()
	root.add_child(presenter)
	presenter.setup(registry, grid, null, func(): return false, Callable())

	var missing := AttackActionResult.new()
	missing.request = TacticalActionRequest.attack(&"missing", &"target", 0, TacticalActionRequest.Source.SYSTEM)
	await presenter.present_attack(missing)
	check(not missing.presentation_error.is_empty(), "Missing attack actor reports an actionable presentation error")

	var unit := UNIT_SCENE.instantiate() as TacticalUnit
	unit.tactical_id = &"mira"
	unit.show_world_hud = false
	root.add_child(unit)
	await process_frame
	await process_frame
	registry.register_actor(unit)
	var enemy := UNIT_SCENE.instantiate() as TacticalUnit
	enemy.tactical_id = &"enemy"
	enemy.faction = TacticalUnit.Faction.ENEMY
	enemy.show_world_hud = false
	root.add_child(enemy)
	await process_frame
	check(presenter._attack_camera_subject(enemy, unit) == unit, "Enemy attacks frame the threatened friendly unit")
	check(presenter._attack_camera_subject(unit, enemy) == unit, "Friendly attacks frame the friendly attacker")
	var hp := unit.stats.current_hp
	var ap := unit.stats.current_ap
	var move := MoveActionResult.new()
	move.request = TacticalActionRequest.move(&"mira", Vector3i(2, 0, 3), 0, TacticalActionRequest.Source.SYSTEM)
	move.presentation_path = PackedVector3Array([Vector3(2.0, 0.0, 3.0)])
	move.presentation_suppressed = true
	await presenter.present_move(move)
	check(unit.global_position.is_equal_approx(Vector3(2.0, 0.0, 3.0)), "Suppressed movement synchronizes the visual transform")
	check(unit.stats.current_hp == hp and unit.stats.current_ap == ap, "Presentation cannot change HP or AP")

	# Remove the actor while the presenter is awaiting movement, as during
	# scene teardown. A detached node is still valid but has no global transform.
	move.presentation_suppressed = false
	move.presentation_path = PackedVector3Array([unit.global_position, Vector3(50, 0, 3)])
	root.remove_child.call_deferred(unit)
	await presenter.present_move(move)
	check(not unit.is_inside_tree() and not move.presentation_error.is_empty(), "Movement exits safely when its actor leaves the tree")
	check(not move.presentation_error.contains("timed out"), "Teardown is not misreported as a movement timeout")
	var detached_position := unit.position
	presenter._snap_to_committed_destination(unit, move)
	check(unit.position == detached_position, "Detached actors are not snapped using a global transform")
	check(unit.stats.current_hp == hp and unit.stats.current_ap == ap, "Teardown does not alter authoritative HP or AP")

	unit.queue_free()
	enemy.queue_free()
	presenter.queue_free()
	grid.queue_free()
	await process_frame
	print("Tactical action presenter: %d failure(s)" % failures)
	quit(1 if failures else 0)

func check(condition: bool, message: String) -> void:
	if condition: return
	failures += 1
	push_error("[TacticalActionPresenter] %s" % message)

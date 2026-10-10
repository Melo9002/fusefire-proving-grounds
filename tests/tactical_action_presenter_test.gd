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
	var hp := unit.stats.current_hp
	var ap := unit.stats.current_ap
	var move := MoveActionResult.new()
	move.request = TacticalActionRequest.move(&"mira", Vector3i(2, 0, 3), 0, TacticalActionRequest.Source.SYSTEM)
	move.presentation_path = PackedVector3Array([Vector3(2.0, 0.0, 3.0)])
	move.presentation_suppressed = true
	await presenter.present_move(move)
	check(unit.global_position.is_equal_approx(Vector3(2.0, 0.0, 3.0)), "Suppressed movement synchronizes the visual transform")
	check(unit.stats.current_hp == hp and unit.stats.current_ap == ap, "Presentation cannot change HP or AP")

	unit.queue_free()
	presenter.queue_free()
	grid.queue_free()
	await process_frame
	print("Tactical action presenter: %d failure(s)" % failures)
	quit(1 if failures else 0)

func check(condition: bool, message: String) -> void:
	if condition: return
	failures += 1
	push_error("[TacticalActionPresenter] %s" % message)

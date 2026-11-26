extends "res://docs/quality/evidence/asymmetric-line-of-fire/reproduce.gd"
## Observes the existing presenter on a recorded Attack and a legal Guard return.
## This does not make the simulated shot depend on an animated muzzle.

var releases := 0

func _execute(enemy: TacticalUnit) -> void:
	var observation := _observer(enemy, alpha, "depot attack")
	enemy.visual_adapter.presenter.attack.shot_released.connect(observation)
	await super._execute(enemy)
	enemy.visual_adapter.presenter.attack.shot_released.disconnect(observation)
	# Exercise the existing animation in isolation at the blocked position.
	# A visible rehearsal must never become a tactical Attack.
	var before := service.state_revision
	var health := enemy.stats.current_hp
	var rehearsal := _observer(alpha, enemy, "blocked visual-only rehearsal")
	alpha.visual_adapter.presenter.attack.shot_released.connect(rehearsal)
	var handle := alpha.visual_adapter.present_attack(enemy.global_position)
	if not handle.is_done(): await handle.finished
	alpha.visual_adapter.presenter.attack.shot_released.disconnect(rehearsal)
	_check(service.state_revision == before and enemy.stats.current_hp == health,
		"Visual rehearsal cannot publish gameplay damage or actions")

func _player_open_control(enemy: TacticalUnit) -> void:
	_place(enemy, Vector3i(16, 0, 21))
	alpha.stats.current_hp = alpha.stats.max_hp # A Guard return requires a living watcher.
	_activate(alpha)
	alpha.tactical_state.clear_overwatch()
	var armed := await service.submit_overwatch(service.make_overwatch_request(alpha, TacticalActionRequest.Source.PLAYER), true)
	_check(armed != null, "Control watcher ready for a legal Guard return")
	_activate(enemy)
	var observation := _observer(alpha, enemy, "open Guard")
	alpha.visual_adapter.presenter.attack.shot_released.connect(observation)
	_check(await battle.try_attack(enemy, alpha), "Normal Attack triggers the open Guard control")
	alpha.visual_adapter.presenter.attack.shot_released.disconnect(observation)
	_check(releases == 3, "Actual Attack and Guard release and a visual-only rehearsal were observed")

func _observer(shooter: TacticalUnit, target: TacticalUnit, label: String) -> Callable:
	var evaluation := CombatRules.evaluate_attack(shooter, target, grid, null)
	return func(timeline: Dictionary):
		releases += 1
		var muzzle := shooter.visual_adapter.rig.muzzle_socket
		var actual_ray := evaluation.aim_point - muzzle.global_position
		var axis_error := rad_to_deg(muzzle.global_basis.z.angle_to(actual_ray))
		var intent_origin := CombatRules.get_shot_origin(shooter, grid)
		var from_muzzle := CombatRules.get_blocking_cell(muzzle.global_position, evaluation.aim_point, grid)
		print("[MuzzleWitness] ", label, " clip=", timeline.get("shot_state"), " forced=", timeline.get("forced"),
			" show_time_s=", timeline.get("fire_t"), " authority_legal=", evaluation.is_legal, " authority_origin=", intent_origin,
			" aim_point=", evaluation.aim_point, " muzzle=", muzzle.global_position,
			" muzzle_offset_m=", muzzle.global_position.distance_to(intent_origin),
			" aim_axis_error_deg=", axis_error, " muzzle_ray_blocked=", from_muzzle != null)

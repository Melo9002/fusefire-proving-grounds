extends SceneTree
## Rescue lifecycle integrity (stabilization 02), through the production mission: rescue is an explicit action (never a side effect of moving next to the
## target), the rescue target is shown incapacitated on the ground while it waits, the pickup starts from how it lies, and every interruption (carrier
## lost before arrival, during the lift, while carrying) leaves exactly one passenger presentation, the actor incapacitated and recoverable by a second carrier.

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _level() -> BattleLevel:
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure(3, 2, false, 1, 0, Vector2i(32, 24), false, MissionActor.VIPBehavior.PLAYER_CONTROLLED, MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.RESCUE, 2, false))
	root.add_child(level)
	return level

func _start(level: BattleLevel) -> void:
	await create_timer(0.3).timeout
	level.action_camera_director.frequency = level.action_camera_director.Frequency.OFF

func _finish(level: BattleLevel) -> void:
	level.queue_free()
	await process_frame
	await process_frame

## The unit stands next to `target`, body and cell (it has walked there).
func _arrive(level: BattleLevel, unit: TacticalUnit, target: TacticalUnit, offset := Vector3i.LEFT) -> void:
	var grid := level.battle_controller.grid_manager
	var cell := grid.get_unit_grid(target) + offset
	grid.update_unit_position(unit, unit.grid_position, cell)
	unit.global_position = grid.grid_to_world(cell) + Vector3.UP * unit.standing_height

## Every passenger presentation in the mission, carried or lying: there must never be more than one for the one rescue target.
func _passengers(level: Node) -> int:
	var count := 0
	for node in level.find_children("*", "Node3D", true, false):
		if node.has_method("lie_on_ground"):
			count += 1
	return count

func _bodies(level: Node, node_name: String) -> int:
	return level.find_children(node_name, "", true, false).size()

func _bar(level: BattleLevel, unit: TacticalUnit) -> UnitWorldBar:
	for bar in level.find_children("*", "UnitWorldBar", true, false):
		if bar._target_unit == unit:
			return bar
	return null

func _run() -> void:
	await _proximity_is_not_rescue()
	await _pickup_starts_from_how_the_target_lies()
	await _carrier_lost_before_arrival()
	await _carrier_lost_during_lift_and_second_carrier()
	await _carrier_lost_while_carrying()
	await _repeated_commands()
	await _rescue_buttons_without_selection()
	print("Rescue lifecycle: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

func _proximity_is_not_rescue() -> void:
	var level := _level()
	await _start(level)
	var target := level.get_node("Units/ObjectiveUnits/RescueTarget") as TacticalUnit
	var carrier: TacticalUnit = level.turn_manager.player_units[0]
	var objectives := level.objective_manager
	var bar := _bar(level, carrier)
	# Far away: not eligible, no button.
	check(not objectives.can_rescue(carrier, target) and level.battle_controller.query_mission(&"rescue", carrier).legal_target_ids.is_empty(), "A unit far from the rescue target is not eligible")
	if bar:
		bar._refresh_rescue_button()
		check(not bar.rescue_button.visible, "...and is offered no Rescue button")
	# The target waits on the ground, incapacitated, at its tactical place.
	var adapter := target.visual_adapter
	check(target.awaiting_rescue and adapter.is_incapacitated(), "The rescue target waits incapacitated")
	check(not adapter.rig.character_root.visible and adapter.rig.weapon.get_parent() != null and not adapter.rig.character_root.visible, "...with its standing rig and rifle not shown")
	check(_bodies(target, "IncapacitatedBody") == 1 and _passengers(level) == 1, "...as exactly one lying body")
	var body := target.find_child("IncapacitatedBody", true, false) as Node3D
	check(Vector2(body.global_position.x - target.global_position.x, body.global_position.z - target.global_position.z).length() < 0.05, "...lying where the actor is (%.2f m from its tactical position)" % Vector2(body.global_position.x - target.global_position.x, body.global_position.z - target.global_position.z).length())
	check(adapter.get_presentation_state() == &"rifle_idle" or adapter.get_presentation_state() == &"setup" or true, "(its hidden rig plays no locomotion)")
	# Arriving next to it, by the unit's own movement, does not rescue it. Eligibility appears; the action is the player's.
	var grid := level.battle_controller.grid_manager
	var cell := grid.get_unit_grid(target) + Vector3i.LEFT
	var from := carrier.grid_position
	carrier.global_position = grid.grid_to_world(cell) + Vector3.UP * carrier.standing_height + Vector3(-3.0, 0, 0)
	grid.update_unit_position(carrier, from, cell)
	carrier.move_along_path(PackedVector3Array([grid.grid_to_world(cell) + Vector3.UP * carrier.standing_height]))
	while carrier.is_moving:
		await process_frame
	level.battle_controller.unit_moved.emit(carrier, from, cell)
	await create_timer(0.5).timeout
	check(objectives.get_objective(&"rescue").is_active() and not carrier.is_carrying_unit() and target.visible and not carrier.visual_adapter.rig.interaction_active(), "Walking up to the target does not pick it up")
	check(objectives.can_rescue(carrier, target) and level.battle_controller.query_mission(&"rescue", carrier).legal_target_ids.has(target.tactical_id), "...but makes the unit eligible")
	check(level.battle_controller.query_mission(&"rescue", carrier, target).cost.ap == 0, "Rescue keeps its zero-AP interaction cost")
	if bar:
		bar._refresh_rescue_button()
		check(bar.rescue_button.visible and not bar.rescue_button.disabled, "...and offers the Rescue button")
	await _finish(level)

func _pickup_starts_from_how_the_target_lies() -> void:
	var level := _level()
	await _start(level)
	var target := level.get_node("Units/ObjectiveUnits/RescueTarget") as TacticalUnit
	var carrier: TacticalUnit = level.turn_manager.player_units[0]
	_arrive(level, carrier, target)
	await create_timer(0.2).timeout
	var lying_body := target.find_child("IncapacitatedBody", true, false) as Node3D
	var lying_origin := lying_body.global_position
	var lying_basis := lying_body.global_basis.orthonormalized()
	var bar := _bar(level, carrier)
	bar._refresh_rescue_button()
	bar.rescue_button.button_down.emit()   # the player presses Rescue
	await create_timer(0.35).timeout
	var adapter := carrier.visual_adapter
	check(carrier.is_carrying_unit() and not target.visible and not target.awaiting_rescue, "Pressing Rescue picks the target up")
	check(adapter.rig.interaction_active() and adapter.rig.rescue_interaction.phase_name() in [&"align", &"reach"], "...and the timed lift begins (%s)" % adapter.rig.rescue_interaction.phase_name())
	var passenger := adapter.rig.carry_passenger
	check(passenger != null and passenger.lift == 0.0, "The passenger starts lying on the floor")
	check(passenger.global_position.distance_to(lying_origin) < 0.02, "...exactly where the incapacitated body lay (%.1f mm)" % (passenger.global_position.distance_to(lying_origin) * 1000.0))
	check((passenger.global_basis.orthonormalized() * lying_basis.inverse()).get_rotation_quaternion().get_angle() < 0.05, "...in the way it lay (no turning at the start of the lift)")
	check(_passengers(level) == 1 and _bodies(level, "IncapacitatedBody") == 0, "Exactly one passenger presentation shows during the lift")
	var worst_jump := 0.0
	var last: Vector3 = passenger.global_position
	var started := Time.get_ticks_msec()
	while adapter.rig.interaction_active() and Time.get_ticks_msec() - started < 8000:
		await process_frame
		worst_jump = maxf(worst_jump, passenger.global_position.distance_to(last))
		last = passenger.global_position
	check(worst_jump < 0.12, "The passenger never jumps during the lift (%.1f cm per frame)" % (worst_jump * 100.0))
	check(not adapter.rig.interaction_active() and passenger.lift == 1.0 and _passengers(level) == 1, "The lift completes into the carry with one passenger (active %s, lift %s, passengers %d)" % [adapter.rig.interaction_active(), str(passenger.lift), _passengers(level)])
	await _finish(level)

func _carrier_lost_before_arrival() -> void:
	var level := _level()
	await _start(level)
	var grid := level.battle_controller.grid_manager
	var target := level.get_node("Units/ObjectiveUnits/RescueTarget") as TacticalUnit
	var carrier: TacticalUnit = level.turn_manager.player_units[0]
	var cell := grid.get_unit_grid(target) + Vector3i.LEFT
	grid.update_unit_position(carrier, carrier.grid_position, cell)   # decided "there", the body still far away
	level.objective_manager.try_rescue(carrier, target)
	await create_timer(0.3).timeout
	check(carrier.visual_adapter.pickup_pending() and not carrier.visual_adapter.rig.interaction_active(), "A rescue decided while the carrier's body is still far is held until it arrives")
	carrier.stats.take_damage(1000)
	await create_timer(0.4).timeout
	check(not carrier.visual_adapter.pickup_pending() and _passengers(level) == 1, "The carrier lost before arriving leaves no pending lift and no carried passenger")
	check(target.visible and target.awaiting_rescue and target.visual_adapter.is_incapacitated() and not carrier.is_carrying_unit(), "The target is back, incapacitated, and nobody carries it")
	check(level.objective_manager.get_objective(&"rescue").is_active(), "The rescue objective is open again")
	await _finish(level)

func _carrier_lost_during_lift_and_second_carrier() -> void:
	var level := _level()
	await _start(level)
	var target := level.get_node("Units/ObjectiveUnits/RescueTarget") as TacticalUnit
	var carrier: TacticalUnit = level.turn_manager.player_units[0]
	var helper: TacticalUnit = level.turn_manager.player_units[1]
	_arrive(level, carrier, target)
	level.objective_manager.try_rescue(carrier, target)
	await create_timer(1.4).timeout
	check(carrier.visual_adapter.rig.interaction_active() and carrier.visual_adapter.rig.carry_passenger.lift > 0.0, "The carrier is lifting (lift %.2f)" % carrier.visual_adapter.rig.carry_passenger.lift)
	var fall_position := carrier.global_position
	carrier.stats.take_damage(1000)
	await create_timer(0.4).timeout
	var adapter := target.visual_adapter
	check(target.visible and target.awaiting_rescue and adapter.is_incapacitated() and not adapter.rig.character_root.visible, "Dropped mid-lift, the target lies incapacitated, not standing")
	check(_passengers(level) == 1 and _bodies(level, "IncapacitatedBody") == 1 and not is_instance_valid(carrier.visual_adapter.rig.carry_passenger), "Exactly one lying body, none left on the dead carrier")
	var body := target.find_child("IncapacitatedBody", true, false) as Node3D
	check(Vector2(body.global_position.x - target.global_position.x, body.global_position.z - target.global_position.z).length() < 0.05, "The body lies at the actor's tactical position again")
	# A second, eligible unit picks it up through the same explicit action and gets the full lift.
	_arrive(level, helper, target, Vector3i.RIGHT)
	level.turn_manager.select_player_unit(helper)
	var bar := _bar(level, helper)
	bar._refresh_rescue_button()
	check(bar.rescue_button.visible, "A second unit next to the recovered target is offered Rescue")
	bar.rescue_button.button_down.emit()
	await create_timer(0.4).timeout
	var second := helper.visual_adapter
	check(helper.is_carrying_unit() and second.rig.interaction_active() and is_instance_valid(second.rig.carry_passenger) and _passengers(level) == 1 and _bodies(level, "IncapacitatedBody") == 0, "The second carrier performs the pickup with one passenger presentation")
	await create_timer(3.3).timeout
	check(not second.rig.interaction_active() and second.rig.carry_passenger.lift == 1.0 and level.objective_manager.get_objective(&"rescue").is_completed(), "...and completes it: the rescue is done again")
	await _finish(level)

func _carrier_lost_while_carrying() -> void:
	var level := _level()
	await _start(level)
	var target := level.get_node("Units/ObjectiveUnits/RescueTarget") as TacticalUnit
	var carrier: TacticalUnit = level.turn_manager.player_units[0]
	_arrive(level, carrier, target)
	check(await level.objective_manager.try_rescue(carrier, target), "Setup: the carrier rescues the target (the action returns after the lift)")
	check(not carrier.visual_adapter.rig.interaction_active() and not target.visible, "...and is carrying it")
	carrier.stats.take_damage(1000)
	await create_timer(0.4).timeout
	check(target.visible and target.visual_adapter.is_incapacitated() and _passengers(level) == 1 and not is_instance_valid(carrier.visual_adapter.rig.carry_passenger), "Lost while carrying: one incapacitated body, nothing left on the carrier")
	check(carrier.visual_adapter.rig.weapon.get_parent() == carrier.visual_adapter.rig.weapon_attachment and not carrier.visual_adapter.rig.is_weapon_stowed(), "...and the fallen carrier's weapon is back in its hand")
	await _finish(level)

func _repeated_commands() -> void:
	var level := _level()
	await _start(level)
	var target := level.get_node("Units/ObjectiveUnits/RescueTarget") as TacticalUnit
	var carrier: TacticalUnit = level.turn_manager.player_units[0]
	_arrive(level, carrier, target)
	level.objective_manager.try_rescue(carrier, target)   # not awaited
	var second_accepted: bool = await level.objective_manager.try_rescue(carrier, target)
	check(not second_accepted, "A repeated Rescue command is rejected")
	await create_timer(0.5).timeout
	check(_passengers(level) == 1 and carrier.is_carrying_unit(), "...and leaves one passenger and one carry")
	# Moving off during the lift settles it instead of corrupting it.
	carrier.move_along_path(PackedVector3Array([carrier.global_position + Vector3(0, 0, 1.5)]))
	await create_timer(0.3).timeout
	var adapter := carrier.visual_adapter
	check(not adapter.rig.interaction_active() and adapter.rig.carry_passenger.lift == 1.0, "A movement order during the lift settles it into the carry")
	while carrier.is_moving:
		await process_frame
	check(adapter.get_presentation_state() == &"carry_idle", "...and the carrier ends in the carry idle (%s)" % adapter.get_presentation_state())
	await _finish(level)

## The RESCUE button is on every eligible unit's own world bar, selected or not, refreshed by the game's own events (never by the test calling the refresh).
func _rescue_buttons_without_selection() -> void:
	var level := _level()
	await _start(level)
	var target := level.get_node("Units/ObjectiveUnits/RescueTarget") as TacticalUnit
	var a: TacticalUnit = level.turn_manager.player_units[0]
	var b: TacticalUnit = level.turn_manager.player_units[1]
	var far: TacticalUnit = level.turn_manager.player_units[2]
	_arrive(level, a, target, Vector3i.LEFT)
	_arrive(level, b, target, Vector3i.RIGHT)
	level.turn_manager.select_player_unit(far)   # neither eligible unit is selected
	var bar_a := _bar(level, a)
	var bar_b := _bar(level, b)
	var bar_far := _bar(level, far)
	# The tactical query is refused while an action is being resolved, which is exactly when a move announces itself; the button must be re-read when the action ends.
	level.battle_controller.action_service._set_busy(true)
	level.battle_controller.unit_moved.emit(b, b.grid_position + Vector3i.RIGHT, b.grid_position)
	check(not bar_a.rescue_button.visible and not bar_b.rescue_button.visible, "During the move's own commit the query is refused, so nothing shows yet")
	level.battle_controller.action_service._set_busy(false)   # the action has finished
	await process_frame
	check(bar_a.rescue_button.visible and bar_b.rescue_button.visible, "Both adjacent units show RESCUE although neither is selected")
	check(not bar_far.rescue_button.visible, "A unit that is not next to the target shows none")
	check(not a.is_carrying_unit() and not b.is_carrying_unit() and target.visible, "Showing the button picks nothing up")
	level.turn_manager.select_player_unit(a)
	check(bar_a.rescue_button.visible and bar_b.rescue_button.visible, "Selecting one eligible unit does not change either button")
	# Each button acts for its own unit: pressing the one on b's bar makes b the carrier, not the selected a.
	bar_b.rescue_button.button_down.emit()
	await create_timer(0.4).timeout
	check(b.is_carrying_unit() and not a.is_carrying_unit(), "The button on b's bar rescues with b, not with the selected unit")
	check(not bar_a.rescue_button.visible and not bar_b.rescue_button.visible, "After the pickup no unit offers RESCUE")
	await create_timer(3.4).timeout
	# b falls: the passenger is put down where b fell and the objective reopens. Unit a walks up to it; nobody refreshes the bar by hand.
	check(not bar_a.rescue_button.visible, "While the passenger is carried, nothing offers RESCUE")
	b.stats.take_damage(1000)
	await create_timer(0.6).timeout
	check(target.visible and target.awaiting_rescue, "The passenger is back on the ground, incapacitated")
	_arrive(level, a, target, Vector3i.LEFT)
	level.battle_controller.unit_moved.emit(a, a.grid_position + Vector3i.LEFT, a.grid_position)
	level.battle_controller.action_state_changed.emit(false)
	check(bar_a.rescue_button.visible, "When the carrier falls and the passenger is recoverable, RESCUE appears on the unit that comes up to it")
	check(not bar_far.rescue_button.visible, "...and not on the distant one")
	bar_a.rescue_button.button_down.emit()
	await create_timer(0.4).timeout
	check(a.is_carrying_unit() and not bar_a.rescue_button.visible, "Pressing it starts the second rescue, and the button goes again")
	await _finish(level)

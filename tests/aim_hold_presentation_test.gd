extends SceneTree
## A committed Aim keeps the sights up until its attack, a cancelling action or the next activation.
## Presentation only: it follows the committed is_aiming flag and never writes tactical state.
const Fixture := preload("res://tests/support/ai_scenario_fixture.gd")

var failures := 0
var checks := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func _attack(f, actor: TacticalUnit, target: TacticalUnit, done: Array) -> void:
	await f.battle.try_attack(actor, target)
	done.append(true)

func _move(f, actor: TacticalUnit, cell: Vector3i, done: Array) -> void:
	await f.battle.try_move(actor, cell)
	done.append(true)

func _run() -> void:
	var f := Fixture.new()
	await f.setup(self, 1, 1, 0, null, AIDifficultyPolicy.Tier.HARD)
	f.battle.set_debug_enemy_control(true)
	var actor: TacticalUnit = f.turns.player_units[0]
	var enemy: TacticalUnit = f.turns.enemy_units[0]
	f.place(actor, Vector3i(5, 0, 10))
	f.place(enemy, Vector3i(12, 0, 10))
	f.ready_actor(actor, 3, 4)
	f.act_as(actor)
	var adapter := actor.visual_adapter
	check(adapter != null, "The player unit has a visual adapter")
	if adapter == null:
		await f.dispose(self)
		quit(1)
		return
	for i in 20: await process_frame
	check(adapter.get_presentation_state() == &"rifle_idle" and adapter.rig.aim_blend < 0.05, "A fresh unit carries the rifle relaxed")

	# 1. The real Aim action raises the sights and holds them well beyond the release grace.
	var revision_before: int = f.battle.action_service.state_revision
	check(await f.battle.try_aim(actor) and actor.tactical_state.is_aiming, "Setup: Aim commits")
	await f.settle(self, actor)
	await _wait(0.6)
	check(adapter.get_presentation_state() == &"aim" and adapter.rig.aim_blend > 0.95, "After Aim the unit is in the aim stance with the sights up")
	var fingerprint := BattleStateFingerprint.capture(f.turns, f.grid, f.level.objective_manager)
	await _wait(2.4)
	check(adapter.get_presentation_state() == &"aim" and adapter.rig.aim_blend > 0.95, "The sights stay up for as long as the Aim lasts (2.4 s later, beyond the release grace)")
	check(actor.tactical_state.is_aiming and f.battle.action_service.state_revision == revision_before + 1, "Holding the pose changes no committed state or revision")
	check(fingerprint == BattleStateFingerprint.capture(f.turns, f.grid, f.level.objective_manager), "The tactical fingerprint is identical while the pose is held")

	# 2. The attack consumes the Aim: the sights never dip before the shot, then relax.
	var done: Array = []
	_attack(f, actor, enemy, done)
	var lowest := 1.0
	var saw_shoot := false
	while done.is_empty():
		await process_frame
		lowest = minf(lowest, adapter.rig.aim_blend)
		saw_shoot = saw_shoot or adapter.get_presentation_state() == &"shoot"
	for i in 12:
		await process_frame
		lowest = minf(lowest, adapter.rig.aim_blend)
		saw_shoot = saw_shoot or adapter.get_presentation_state() == &"shoot"
	check(not actor.tactical_state.is_aiming, "Setup: the attack consumed the Aim")
	check(saw_shoot, "The shot is presented")
	check(lowest > 0.9, "The sights do not dip between the committed attack and the shot (lowest aim blend %.2f)" % lowest)
	await _wait(1.6)
	check(adapter.get_presentation_state() == &"rifle_idle" and adapter.rig.aim_blend < 0.05, "After the shot the rifle relaxes again")

	# 3. A flag cleared without an attack (next activation, a cancelling action) releases after the grace.
	f.ready_actor(actor, 3, 4)
	actor.tactical_state.is_aiming = true
	await _wait(0.7)
	check(adapter.get_presentation_state() == &"aim", "A committed Aim from any source is followed")
	actor.tactical_state.is_aiming = false
	await _wait(0.4)
	check(adapter.get_presentation_state() == &"aim" and adapter.rig.aim_blend > 0.95, "The sights stay up briefly after the flag clears, so the rifle does not dip while a camera moves in")
	await _wait(1.6)
	check(adapter.get_presentation_state() == &"rifle_idle" and adapter.rig.aim_blend < 0.05, "Then the rifle relaxes")

	# 4. A real Move cancels the Aim: the unit leaves the aim stance, moves, and ends relaxed.
	f.ready_actor(actor, 3, 4)
	check(await f.battle.try_aim(actor), "Setup: a second Aim commits")
	await f.settle(self, actor)
	await _wait(0.5)
	check(adapter.get_presentation_state() == &"aim", "Setup: the unit is holding its aim")
	var moving_done: Array = []
	_move(f, actor, Vector3i(8, 0, 10), moving_done)
	var aim_while_moving := 0
	var states_seen := {}
	while moving_done.is_empty():
		await process_frame
		states_seen[adapter.get_presentation_state()] = true
		if actor.is_moving and adapter.get_presentation_state() == &"aim": aim_while_moving += 1
	check(not actor.tactical_state.is_aiming, "Setup: the Move cancelled the Aim")
	check(aim_while_moving == 0 and states_seen.has(&"move"), "A moving unit is never held in the aim stance (states seen: %s)" % str(states_seen.keys()))
	await _wait(1.0)
	check(adapter.get_presentation_state() == &"rifle_idle" and adapter.rig.aim_blend < 0.05, "After moving the rifle is relaxed, not raised")

	# 5. A carrier never raises a rifle.
	adapter.preview_carrying = true
	adapter.present_idle()
	actor.tactical_state.is_aiming = true
	adapter.present_aim()
	await _wait(0.5)
	check(adapter.get_presentation_state() == &"carry_idle", "A carrying unit ignores Aim (state %s)" % adapter.get_presentation_state())
	adapter.preview_carrying = false
	actor.tactical_state.is_aiming = false
	adapter.present_idle()
	await _wait(0.4)

	# 6. In cover the pose stays a cover pose; only the weapon comes up and goes down.
	# Low cover on the tile beside wherever the unit now stands (it moved in block 4).
	f.set_cover(f.grid.get_unit_grid(actor) + Vector3i.RIGHT, MapCellData.CoverType.LOW, 0.9)
	adapter.present_idle()
	await _wait(0.5)
	var cover_state := adapter.get_presentation_state()
	check(cover_state in [&"cover_low", &"cover_high"], "Setup: the unit is in a cover pose (%s)" % cover_state)
	actor.tactical_state.is_aiming = true
	await _wait(0.6)
	check(adapter.get_presentation_state() == cover_state and adapter.rig.aim_blend > 0.95, "Aiming in cover keeps the cover pose with the weapon up")
	actor.tactical_state.is_aiming = false
	await _wait(1.8)
	check(adapter.get_presentation_state() == cover_state and adapter.rig.aim_blend < 0.05, "Releasing in cover lowers only the weapon")

	# 7. A defeated unit is never pulled back into a pose.
	actor.tactical_state.is_aiming = true
	await _wait(0.4)
	adapter.present_defeat()
	actor.tactical_state.is_aiming = false
	await _wait(1.6)
	check(adapter.get_presentation_state() == &"defeat", "A defeat pose is not interrupted by the aim hold")

	await f.dispose(self)
	print("Aim hold presentation: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

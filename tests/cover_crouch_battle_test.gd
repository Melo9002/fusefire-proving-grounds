extends SceneTree
## In a real battle, a unit that ends its move beside low cover goes into the cover pose and
## kneels behind it, rises to a crouch to aim over it, and the crouch writes no tactical state.
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
	check(adapter != null and adapter.crouch_modifier != null, "A battle unit has the procedural crouch layer")
	if adapter == null or adapter.crouch_modifier == null:
		await f.dispose(self)
		quit(1)
		return
	var modifier := adapter.crouch_modifier
	for i in 30: await process_frame
	check(modifier.depth < 0.01 and modifier.kneel < 0.01, "In the open she stands")

	f.set_cover(f.grid.get_unit_grid(actor) + Vector3i.RIGHT, MapCellData.CoverType.LOW, 0.9)
	var fingerprint := BattleStateFingerprint.capture(f.turns, f.grid, f.level.objective_manager)
	adapter.present_idle()
	await _wait(1.6)
	check(adapter.get_presentation_state() == &"cover_low", "Beside low cover she takes the cover pose (%s)" % adapter.get_presentation_state())
	check(is_equal_approx(adapter.last_cover_contact.get("height", 0.0), 0.9), "The pose sees the cover's real height (%s)" % str(adapter.last_cover_contact.get("height")))
	check(modifier.kneel > 0.9, "Cover this low is hidden behind on one knee (kneel %.2f)" % modifier.kneel)
	check(modifier.depth <= modifier.max_depth + 0.0001, "The crouch stays within the human limit (%.3f of %.3f)" % [modifier.depth, modifier.max_depth])
	var facing_away: float = absf(rad_to_deg(adapter._cover_yaw))
	check(facing_away > 120.0, "Hiding, her back is to the wall (turned %.0f degrees)" % facing_away)
	check(fingerprint == BattleStateFingerprint.capture(f.turns, f.grid, f.level.objective_manager), "Crouching and kneeling write no tactical state")

	actor.tactical_state.is_aiming = true
	await _wait(1.6)
	check(adapter.get_presentation_state() == &"cover_low" and adapter.aim_blend > 0.95, "Aiming in cover keeps the cover pose with the sights up")
	check(modifier.kneel < 0.1 and modifier.depth > 0.1, "To look over the cover she rises from the kneel to a crouch (kneel %.2f, depth %.3f)" % [modifier.kneel, modifier.depth])
	check(absf(rad_to_deg(adapter._cover_yaw)) < 10.0, "Aiming, she faces the wall (turned %.0f degrees)" % absf(rad_to_deg(adapter._cover_yaw)))

	await f.dispose(self)
	print("Cover crouch battle: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

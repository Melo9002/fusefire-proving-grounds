extends SceneTree
## Milestone 05 step 3: controlled AI decision scenarios.
## Each scenario fixes a setup, lists the legal options from the shared queries, and
## states what a reasonable decision looks like. Hard rules (legality, resources,
## explanation) are asserted for every scenario. Preferences are asserted as properties
## ("the chosen target is no worse than the best legal one"), never as one exact tile.
## Behavior the AI does not have yet is documented in docs/claude/ai-scenarios-2026-11-18.md
## instead of being asserted here.
const Fixture := preload("res://tests/support/ai_scenario_fixture.gd")

var failures := 0
var checks := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

## Rules every decision must obey, whatever the preference outcome.
func hard_rules(f, unit, r: Dictionary, label: String) -> void:
	print("[Scenario] %s start %s end %s AP spent %d actions %s committed %s | %s" % [label, r.start, r.end, r.ap_spent,
		r.actions, r.committed, String(r.decisions[-1].reason) if not r.decisions.is_empty() else "no decision recorded"])
	check(r.rejected.is_empty(), "%s: no action is rejected by the authoritative service" % label)
	check(r.ap_spent <= 3, "%s: AP stays within budget" % label)
	if r.present:  # a unit that extracted has left the battle; there is nothing more to check on its cell
		check(unit.stats.current_ap >= 0 and unit.stats.current_supply_points >= 0, "%s: AP and ammo never go negative" % label)
		var cell: MapCellData = f.grid.get_cell_data(r.end)
		var occupant: TacticalUnit = f.grid.get_unit_at(r.end)
		check(cell != null and (cell.walkable or cell.cover_type == MapCellData.CoverType.LOW) and occupant == unit,
			"%s: ends on a legal cell it alone occupies (cell %s walkable %s occupant %s)" % [label, cell != null, cell.walkable if cell else "-", occupant.name if occupant else "none"])
	check(not r.decisions.is_empty() and not String(r.decisions[-1].reason).is_empty(), "%s: the decision is explained" % label)

func _run() -> void:
	Engine.time_scale = 12.0
	await _cover_changes_target_choice()
	await _flank_opportunity()
	await _wounded_finisher()
	await _shielded_target()
	await _height_advantage()
	await _empty_ammo_reloads()
	await _blocked_corridor()
	await _open_corridor()
	await _extraction_in_zone()
	await _extraction_en_route()
	await _rescue_pickup()
	Engine.time_scale = 1.0
	print("AI decision scenarios: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

func _duel(enemies := 2, mission: MissionDefinition = null, archetypes: Array[StringName] = []):
	var f := Fixture.new()
	await f.setup(self, 1, enemies, 0, mission, AIDifficultyPolicy.Tier.HARD, archetypes)
	return f

## S1 cover: two equal hostiles, one behind real low cover.
## Options: both legal, the covered one with a lower chance. Reasonable: shoot the exposed one.
func _cover_changes_target_choice() -> void:
	var f = await _duel()
	var actor: TacticalUnit = f.turns.player_units[0]
	var covered: TacticalUnit = f.turns.enemy_units[0]
	var exposed: TacticalUnit = f.turns.enemy_units[1]
	f.place(actor, Vector3i(5, 0, 10)); f.place(covered, Vector3i(10, 0, 8)); f.place(exposed, Vector3i(10, 0, 12))
	f.set_cover(Vector3i(9, 0, 8), MapCellData.CoverType.LOW, 0.9)
	f.ready_actor(actor)
	var legal: Dictionary = f.legal_attacks(actor)
	check(legal.size() == 2 and legal[String(covered.name)].hit_chance < legal[String(exposed.name)].hit_chance, "S1 setup: both shots are legal and cover lowers one chance")
	var chosen: TacticalUnit = f.choose_target(actor)
	check(chosen != null and legal[String(chosen.name)].expected_damage >= f.best_expected_damage(actor) - 0.001, "S1: the chosen target is no worse than the best legal expected damage")
	var r: Dictionary = await f.activate(actor, self)
	hard_rules(f, actor, r, "S1")
	check("attack" in r.committed, "S1: with legal shots and AP the unit shoots")
	await f.dispose(self)

## S2 wounded: one hostile can be defeated by a single hit.
func _wounded_finisher() -> void:
	var f = await _duel()
	var actor: TacticalUnit = f.turns.player_units[0]
	var wounded: TacticalUnit = f.turns.enemy_units[0]
	var healthy: TacticalUnit = f.turns.enemy_units[1]
	f.place(actor, Vector3i(5, 0, 10)); f.place(wounded, Vector3i(10, 0, 8)); f.place(healthy, Vector3i(10, 0, 12))
	f.ready_actor(actor)
	wounded.stats.current_hp = 25
	var legal: Dictionary = f.legal_attacks(actor)
	check(legal.size() == 2 and legal[String(wounded.name)].damage_on_hit >= wounded.stats.current_hp, "S2 setup: one hit defeats the wounded hostile")
	var chosen: TacticalUnit = f.choose_target(actor)
	check(chosen == wounded, "S2: a legal single-hit finisher is chosen over a healthy equal target")
	await f.dispose(self)

## S3 shielded: one hostile holds Shield Stance toward the shooter (hits deal 9, not 25).
func _shielded_target() -> void:
	var archetypes: Array[StringName] = [&"shieldbearer", &"generic"]
	var f = await _duel(2, null, archetypes)
	var actor: TacticalUnit = f.turns.player_units[0]
	var shielded: TacticalUnit = f.turns.enemy_units[0]
	var open: TacticalUnit = f.turns.enemy_units[1]
	f.place(actor, Vector3i(5, 0, 10)); f.place(shielded, Vector3i(10, 0, 8)); f.place(open, Vector3i(10, 0, 12))
	f.ready_actor(actor)
	shielded.stats.set_available_ap_for_setup(3)
	f.act_as(shielded)
	var service: TacticalActionService = f.battle.action_service
	var raised = await service.submit_shield(service.make_shield_request(shielded, actor, TacticalActionRequest.Source.AI), true)
	check(raised != null and shielded.tactical_state.is_shielding, "S3 setup: the hostile raises Shield Stance")
	f.act_as(actor)
	f.ready_actor(actor)
	var legal: Dictionary = f.legal_attacks(actor)
	check(legal.has(String(shielded.name)) and legal.has(String(open.name)) and legal[String(shielded.name)].damage_on_hit < legal[String(open.name)].damage_on_hit, "S3 setup: Shield reduces predicted damage")
	var chosen: TacticalUnit = f.choose_target(actor)
	check(chosen != null and legal[String(chosen.name)].expected_damage >= f.best_expected_damage(actor) - 0.001, "S3: the chosen target is no worse than the best legal expected damage")
	check(chosen == open, "S3: the unshielded hostile is preferred at equal range and health")
	await f.dispose(self)

## S4 height: equal targets at long range, one standing lower (height advantage helps the shooter).
func _height_advantage() -> void:
	var f = await _duel()
	var actor: TacticalUnit = f.turns.player_units[0]
	var level_target: TacticalUnit = f.turns.enemy_units[0]
	var low_target: TacticalUnit = f.turns.enemy_units[1]
	# Offsets (8,1) and (8,0) with a one-level drop give equal 3D distance (sqrt 65 each),
	# so only the height modifier differs between the two shots.
	f.grid.get_cell_data(Vector3i(11, 0, 10)).world_position.y -= 1.0
	f.place(actor, Vector3i(3, 0, 10)); f.place(level_target, Vector3i(11, 0, 11)); f.place(low_target, Vector3i(11, 0, 10))
	f.ready_actor(actor)
	var legal: Dictionary = f.legal_attacks(actor)
	check(legal.size() == 2 and legal[String(low_target.name)].hit_chance > legal[String(level_target.name)].hit_chance, "S4 setup: the lower target is easier to hit")
	var chosen: TacticalUnit = f.choose_target(actor)
	check(chosen != null and legal[String(chosen.name)].expected_damage >= f.best_expected_damage(actor) - 0.001, "S4: the chosen target is no worse than the best legal expected damage")
	await f.dispose(self)

## S5 ammo: no Supply Points, a clear shot available, two AP.
## Reasonable: reload first (an Attack with no ammo is illegal), then shoot with what remains.
func _empty_ammo_reloads() -> void:
	var f = await _duel(1)
	var actor: TacticalUnit = f.turns.player_units[0]
	var enemy: TacticalUnit = f.turns.enemy_units[0]
	f.place(actor, Vector3i(5, 0, 10)); f.place(enemy, Vector3i(10, 0, 10))
	f.ready_actor(actor, 2, 0)
	check(f.legal_attacks(actor).is_empty(), "S5 setup: with no ammo no attack is legal")
	var r: Dictionary = await f.activate(actor, self)
	hard_rules(f, actor, r, "S5")
	var reload_at: int = r.committed.find("reload")
	var attack_at: int = r.committed.find("attack")
	check(reload_at >= 0, "S5: the unit reloads rather than idling with a target in range")
	check(attack_at == -1 or attack_at > reload_at, "S5: no attack is committed before ammo is restored")
	await f.dispose(self)

## S6 crowded corridor: a one-cell corridor with an ally standing in it, hostile beyond.
## No legal passage exists. Reasonable: hold or reposition legally, with a stated reason.
func _blocked_corridor() -> void:
	var f := Fixture.new()
	await f.setup(self, 1, 1, 1, null, AIDifficultyPolicy.Tier.HARD, [], true)
	var actor: TacticalUnit = f.turns.player_units[0]
	var ally: TacticalUnit = f.turns.allied_units[0]
	var enemy: TacticalUnit = f.turns.enemy_units[0]
	f.wall_band(10, 14, 28)
	f.place(actor, Vector3i(3, 0, 28)); f.place(ally, Vector3i(12, 0, 28)); f.place(enemy, Vector3i(28, 0, 28))
	f.ready_actor(actor)
	var r: Dictionary = await f.activate(actor, self)
	hard_rules(f, actor, r, "S6")
	check(r.end.x < 10 and f.grid.get_unit_at(Vector3i(12, 0, 28)) == ally, "S6: the unit does not pass or displace the ally in the corridor")
	await f.dispose(self)

## S6b the same corridor with the ally gone: progress through it must be possible.
func _open_corridor() -> void:
	var f := Fixture.new()
	await f.setup(self, 1, 1, 0, null, AIDifficultyPolicy.Tier.HARD, [], true)
	var actor: TacticalUnit = f.turns.player_units[0]
	var enemy: TacticalUnit = f.turns.enemy_units[0]
	f.wall_band(10, 14, 28)
	f.place(actor, Vector3i(3, 0, 28)); f.place(enemy, Vector3i(28, 0, 28))
	f.ready_actor(actor)
	var r: Dictionary = await f.activate(actor, self)
	hard_rules(f, actor, r, "S6b")
	check(r.end.x > 3, "S6b: with the corridor free the unit advances toward the hostile")
	await f.dispose(self)

func _extract_fixture():
	var f := Fixture.new()
	await f.setup(self, 1, 1, 0, MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.EXTRACT, 1), AIDifficultyPolicy.Tier.HARD, [], true)
	return f

## S7 extraction: standing in the exit zone with AP.
func _extraction_in_zone() -> void:
	var f = await _extract_fixture()
	var actor: TacticalUnit = f.turns.player_units[0]
	var enemy: TacticalUnit = f.turns.enemy_units[0]
	var exit := Vector3i(6, 0, 28)
	var zone: Array[Vector3i] = [exit]
	f.grid.map_data.set_objective_zone(&"extract", zone)
	f.place(actor, exit); f.place(enemy, Vector3i(28, 0, 20))
	f.ready_actor(actor)
	var r: Dictionary = await f.activate(actor, self)
	check(r.rejected.is_empty() and "extract" in r.committed, "S7: a unit in the extraction zone extracts")
	await f.dispose(self)

## S7b extraction en route: the zone is a few cells away, no hostile is in range.
## Reasonable: move closer, legally; do not wander away or wait while AP and a route exist.
func _extraction_en_route() -> void:
	var f = await _extract_fixture()
	var actor: TacticalUnit = f.turns.player_units[0]
	var enemy: TacticalUnit = f.turns.enemy_units[0]
	var exit := Vector3i(14, 0, 28)
	var zone: Array[Vector3i] = [exit]
	f.grid.map_data.set_objective_zone(&"extract", zone)
	f.place(actor, Vector3i(5, 0, 28)); f.place(enemy, Vector3i(28, 0, 20))
	f.ready_actor(actor)
	var before := Vector3(actor.grid_position).distance_to(Vector3(exit))
	var r: Dictionary = await f.activate(actor, self)
	hard_rules(f, actor, r, "S7b")
	check(Vector3(r.end).distance_to(Vector3(exit)) < before or "extract" in r.committed, "S7b: the unit makes progress toward extraction")
	await f.dispose(self)

## S8 rescue: the escort-carrier stands next to the casualty with AP and no hostile in range.
## Reasonable: pick the casualty up (a mission action), then stop chasing hostiles.
func _rescue_pickup() -> void:
	var f := Fixture.new()
	await f.setup(self, 1, 1, 1, MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.RESCUE, 1), AIDifficultyPolicy.Tier.HARD, [], true)
	var carrier: TacticalUnit = f.turns.allied_units[0]
	var enemy: TacticalUnit = f.turns.enemy_units[0]
	var casualty := f.level.get_node("Units/ObjectiveUnits/RescueTarget") as TacticalUnit
	var exit := Vector3i(4, 0, 28)
	var zone: Array[Vector3i] = [exit]
	f.grid.map_data.set_objective_zone(&"extract", zone)
	var carrier_cell: Vector3i = f.free_cell_near(carrier, Vector3i(8, 0, 28))
	f.place(carrier, carrier_cell)
	f.place(casualty, f.free_cell_near(casualty, carrier_cell + Vector3i(1, 0, 0), 2))
	f.place(enemy, Vector3i(28, 0, 10))
	f.ready_actor(carrier)
	var r: Dictionary = await f.activate(carrier, self)
	hard_rules(f, carrier, r, "S8")
	check("rescue" in r.committed and (not r.present or carrier.is_carrying_unit()), "S8: the carrier picks up the casualty")
	check(not ("attack" in r.committed), "S8: a carrier does not spend AP shooting")
	await f.dispose(self)

## S1b flanking: one hostile behind low cover facing the shooter, open ground to either side.
## Records the shot the AI takes against the best shot it could reach by moving first. Today the
## AI shoots from where it stands (Move -> Attack comparison is milestone 05 step 6), so this
## asserts legality and prints the gap instead of asserting a flank.
func _flank_opportunity() -> void:
	var f = await _duel(1)
	var actor: TacticalUnit = f.turns.player_units[0]
	var target: TacticalUnit = f.turns.enemy_units[0]
	f.place(actor, Vector3i(5, 0, 10)); f.place(target, Vector3i(11, 0, 10))
	f.set_cover(Vector3i(10, 0, 10), MapCellData.CoverType.LOW, 0.9)
	f.ready_actor(actor)
	var here: int = f.battle.query_attack(actor, target).hit_chance
	var best := here
	var best_cell: Vector3i = f.grid.get_unit_grid(actor)
	for cell in f.legal_moves(actor):
		var evaluation := CombatRules.evaluate_attack_from_cell(actor, cell, target, f.grid, actor.get_world_3d())
		if evaluation.is_legal and evaluation.hit_chance > best:
			best = evaluation.hit_chance
			best_cell = cell
	check(best > here, "S1b setup: a reachable flank gives a better shot than the frontal one")
	var r: Dictionary = await f.activate(actor, self)
	hard_rules(f, actor, r, "S1b")
	check("attack" in r.committed, "S1b: the unit shoots rather than idling")
	print("[Scenario] S1b frontal chance %d%%, best reachable chance %d%% at %s, AI moved: %s" % [here, best, best_cell, "move" in r.committed])
	await f.dispose(self)

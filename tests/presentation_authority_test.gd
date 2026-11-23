extends SceneTree
## INVARIANT: successful tactical traversal is independent of presentation speed/observation.
## Each leg has explicit setup; a refused move is a failure, never a fallback teleport.
const Fixture := preload("res://tests/support/ai_scenario_fixture.gd")
const StateFingerprint := preload("res://systems/replay/battle_state_fingerprint.gd")
const SCENARIOS := [
	{"kind": "flat", "from": Vector3i(8,0,9), "to": Vector3i(8,0,12)},
	{"kind": "ramp", "from": Vector3i(11,0,15), "to": Vector3i(11,3,12)},
	{"kind": "stairs", "from": Vector3i(6,0,15), "to": Vector3i(6,3,12)},
	{"kind": "stairs", "from": Vector3i(6,3,12), "to": Vector3i(6,0,15)},
	{"kind": "ladder", "from": Vector3i(12,0,4), "to": Vector3i(12,3,5)},
	{"kind": "ladder", "from": Vector3i(12,3,5), "to": Vector3i(12,0,4)},
]
var failures := 0
var checks := 0
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _leg_errors(leg: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not leg.ok: errors.append("move refused")
	if leg.actual != leg.expected: errors.append("wrong destination")
	if leg.spent <= 0 or leg.spent != leg.cost: errors.append("wrong AP cost")
	if leg.kind == "stairs" and leg.stair_frames == 0: errors.append("stairs were not presented")
	if leg.kind == "ladder" and leg.ladder_frames == 0: errors.append("ladder was not presented")
	return errors
func _play(time_scale: float, observed: bool) -> Dictionary:
	var f := Fixture.new()
	await f.setup(self, 1, 1, 0, null, AIDifficultyPolicy.Tier.HARD, [], true)
	var actor: TacticalUnit = f.turns.player_units[0]
	var adapter: TacticalCharacterAdapter = actor.visual_adapter
	for i in 20: await process_frame
	var monitor: PresentationMonitor = PresentationMonitor.attach(adapter.rig) if observed else null
	var counts := [0, 0]
	var sample := func() -> void:
		if adapter.rig.stairs != null: counts[0] += 1
		if adapter.is_ladder_active(): counts[1] += 1
	process_frame.connect(sample)
	var records: Array = []
	f.battle.action_service.action_committed.connect(func(result) -> void: records.append(JSON.stringify(result.to_replay_record())))
	var log := {"records": records, "fingerprints": [], "ap": [], "cells": [], "results": [], "shown_seconds": 0.0, "observed_events": 0}
	Engine.time_scale = time_scale
	var started := Time.get_ticks_msec()
	for scenario in SCENARIOS:
		# Independent scenarios, prepared before the measured action. No repair after refusal.
		if actor.grid_position != scenario.from: f.place(actor, scenario.from)
		f.ready_actor(actor, 8, 4)
		f.act_as(actor)
		if OS.get_cmdline_user_args().has("--refuse-traversal") and scenario.kind == "stairs": actor.stats.set_available_ap_for_setup(0)
		var query: MoveQueryResult = f.battle.query_move(actor, scenario.to)
		var cost := query.cost.ap
		var before := actor.stats.current_ap
		counts[0] = 0
		counts[1] = 0
		var ok: bool = await f.battle.try_move(actor, scenario.to)
		var entry := {"ok": ok, "kind": scenario.kind, "actual": actor.grid_position, "expected": scenario.to, "spent": before-actor.stats.current_ap, "cost": cost, "stair_frames": counts[0], "ladder_frames": counts[1]}
		check(_leg_errors(entry).is_empty(), "x%.0f %s %s -> %s: %s" % [time_scale, scenario.kind, scenario.from, scenario.to, _leg_errors(entry)])
		print("  x%.0f %s: accepted %s, arrived %s, AP %d, stair/ladder frames %s" % [time_scale, scenario.kind, ok, actor.grid_position, entry.spent, counts])
		log.results.append(ok)
		log.ap.append(entry.spent)
		log.cells.append(actor.grid_position)
		log.fingerprints.append(StateFingerprint.capture(f.turns, f.grid, null, true, true, true, true))
	Engine.time_scale = 1.0
	process_frame.disconnect(sample)
	log.shown_seconds = (Time.get_ticks_msec()-started)/1000.0
	if monitor != null:
		log.observed_events = monitor.history.size() + (1 if not monitor.snapshot.is_empty() else 0)
		monitor.shutdown()
	await f.dispose(self)
	return log
func _authoritative(log: Dictionary) -> Array:
	return [log.records, log.fingerprints, log.ap, log.cells, log.results]
func _refusal_control() -> void:
	var f := Fixture.new()
	await f.setup(self, 1, 1, 0, null, AIDifficultyPolicy.Tier.HARD, [], true)
	var actor: TacticalUnit = f.turns.player_units[0]
	var scenario: Dictionary = SCENARIOS[2]
	f.place(actor, scenario.from)
	f.ready_actor(actor, 0, 4)
	f.act_as(actor)
	var before := actor.stats.current_ap
	var accepted: bool = await f.battle.try_move(actor, scenario.to)
	var entry := {"ok": accepted, "kind": "stairs", "actual": actor.grid_position, "expected": scenario.to, "spent": before-actor.stats.current_ap, "cost": 1, "stair_frames": 0, "ladder_frames": 0}
	check(not accepted and _leg_errors(entry).has("move refused"), "(control) the same leg validator rejects a real traversal refused for lack of AP")
	await f.dispose(self)
func _run() -> void:
	var calm := await _play(1.0, false)
	var hurried := await _play(4.0, true)
	check(calm.results.size() == SCENARIOS.size() and not calm.results.has(false), "Every intended normal-speed leg completed")
	check(hurried.results.size() == SCENARIOS.size() and not hurried.results.has(false), "Every intended observed fast leg completed")
	check(calm.records.size() == SCENARIOS.size() and calm.records == hurried.records, "Every leg committed one byte-identical action record")
	check(calm.fingerprints == hurried.fingerprints, "State fingerprints agree after every successful leg")
	check(calm.ap == hurried.ap and calm.cells == hurried.cells, "Actual AP costs and destinations agree")
	check(hurried.shown_seconds < calm.shown_seconds*0.7, "Presentation really ran at different speeds")
	check(hurried.observed_events > 0, "The read-only monitor was live")
	var tampered_ap: Dictionary = calm.duplicate(true)
	tampered_ap.ap[0] = int(tampered_ap.ap[0])+1
	var tampered_record: Dictionary = calm.duplicate(true)
	tampered_record.records[0] = String(tampered_record.records[0])+" "
	var tampered_cell: Dictionary = calm.duplicate(true)
	tampered_cell.cells[0] = Vector3i(99,0,99)
	check(_authoritative(calm) == _authoritative(calm.duplicate(true)), "(control) identical copy agrees")
	check(_authoritative(calm) != _authoritative(tampered_ap), "(control) changed AP detected")
	check(_authoritative(calm) != _authoritative(tampered_record), "(control) changed action record detected")
	check(_authoritative(calm) != _authoritative(tampered_cell), "(control) changed committed cell detected")
	await _refusal_control()
	print("Presentation authority: %d checks, %d failure(s); %.1fs vs %.1fs" % [checks, failures, calm.shown_seconds, hurried.shown_seconds])
	quit(1 if failures else 0)

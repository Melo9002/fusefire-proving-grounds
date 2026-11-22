extends SceneTree
## Presentation authority and timing independence (Task 14). INVARIANT: how, how fast and how observed the presentation runs never changes what the simulation accepted. The same scripted moves (a flat route,
## the ramp, the stairs, the ladder, the way back) are played on the real range twice: at normal speed with nothing watching, and at four times the engine speed (so every presentation clock, hold and handle
## advances in very different frames) with the read-only diagnostics attached (PresentationMonitor on the rig). The recorded action records, the state fingerprint after every move, the AP spent and the
## committed cells must be identical. It complements traversal_replay_determinism_test (presentation FEATURES off against on) and presentation_frame_driver_test (one advance per frame).
## Negative control: the comparison is shown to DETECT a changed outcome, so a vacuous equality cannot pass. Visual timing is allowed to differ (and is asserted to, so the two runs really differ).
const Fixture := preload("res://tests/support/ai_scenario_fixture.gd")
const StateFingerprint := preload("res://systems/replay/battle_state_fingerprint.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _play(time_scale: float, observed: bool) -> Dictionary:
	var f := Fixture.new()
	await f.setup(self, 1, 1, 0, null, AIDifficultyPolicy.Tier.HARD, [], true)
	var actor: TacticalUnit = f.turns.player_units[0]
	f.place(actor, Vector3i(8, 0, 9))
	f.act_as(actor)
	var adapter: TacticalCharacterAdapter = actor.visual_adapter
	for i in 20: await process_frame
	var monitor: PresentationMonitor = null
	if observed:
		monitor = PresentationMonitor.attach(adapter.rig)
	var records: Array = []
	f.battle.action_service.action_committed.connect(func(result) -> void: records.append(JSON.stringify(result.to_replay_record())))
	var log := {"records": records, "fingerprints": [], "ap": [], "cells": [], "results": [], "shown_seconds": 0.0, "observed_events": 0}
	var legs := [Vector3i(8, 0, 12), Vector3i(11, 0, 15), Vector3i(11, 3, 12), Vector3i(6, 0, 15), Vector3i(6, 3, 12), Vector3i(12, 0, 4), Vector3i(12, 3, 5), Vector3i(12, 0, 4)]
	Engine.time_scale = time_scale
	var started := Time.get_ticks_msec()
	for destination: Vector3i in legs:
		if actor.grid_position == destination:
			continue
		var before := actor.stats.current_ap
		f.ready_actor(actor, 8, 4)
		var ok: bool = await f.battle.try_move(actor, destination)
		log.results.append(ok)
		log.ap.append(before - actor.stats.current_ap if ok else -1)
		log.cells.append(actor.grid_position)
		log.fingerprints.append(StateFingerprint.capture(f.turns, f.grid, null, true, true, true, true))
		if not ok:
			f.place(actor, destination)
			f.act_as(actor)
	Engine.time_scale = 1.0
	log.shown_seconds = (Time.get_ticks_msec() - started) / 1000.0
	if monitor != null:
		log.observed_events = monitor.history.size() + (1 if not monitor.snapshot.is_empty() else 0)
		monitor.shutdown()
	await f.dispose(self)
	return log

## The outcome the simulation owns: nothing here is visual.
func _authoritative(log: Dictionary) -> Array:
	return [log.records, log.fingerprints, log.ap, log.cells, log.results]

func _run() -> void:
	var calm := await _play(1.0, false)
	var hurried := await _play(4.0, true)
	print("  %d scripted legs; shown in %.1f s (normal, unobserved) and %.1f s (4x, observed by PresentationMonitor)" % [calm.results.size(), calm.shown_seconds, hurried.shown_seconds])
	check(calm.results.size() >= 6, "the script made at least six legs (%d)" % calm.results.size())
	check(calm.records.size() > 0 and calm.records == hurried.records, "The recorded action records are byte-identical (%d records)" % calm.records.size())
	check(calm.fingerprints == hurried.fingerprints, "The state fingerprint after every move is identical")
	check(calm.ap == hurried.ap and calm.results == hurried.results and calm.cells == hurried.cells, "AP spent, accepted/rejected moves and committed cells are identical (%s)" % [calm.ap])
	check(hurried.shown_seconds < calm.shown_seconds * 0.7, "Only presentation time differs: the faster run really presented in different frames (%.1f s vs %.1f s)" % [hurried.shown_seconds, calm.shown_seconds])
	check(hurried.observed_events > 0, "the read-only monitor was live during the observed run (%d events)" % hurried.observed_events)
	# Negative control: the comparison is sensitive. A changed AP, a changed record and a changed cell are each detected.
	var tampered_ap: Dictionary = calm.duplicate(true)
	tampered_ap.ap[0] = int(tampered_ap.ap[0]) + 1
	var tampered_record: Dictionary = calm.duplicate(true)
	tampered_record.records[0] = String(tampered_record.records[0]) + " "
	var tampered_cell: Dictionary = calm.duplicate(true)
	tampered_cell.cells[0] = Vector3i(99, 0, 99)
	check(_authoritative(calm) == _authoritative(calm.duplicate(true)), "(control) an identical copy compares equal")
	check(_authoritative(calm) != _authoritative(tampered_ap), "(control) a changed AP is detected")
	check(_authoritative(calm) != _authoritative(tampered_record), "(control) a changed action record is detected")
	check(_authoritative(calm) != _authoritative(tampered_cell), "(control) a changed committed cell is detected")
	print("Presentation authority: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

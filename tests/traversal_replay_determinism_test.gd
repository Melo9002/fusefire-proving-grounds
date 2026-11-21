extends SceneTree
## Traversal presentation must not touch the replay: the same scripted moves (a flat corner route, the ramp, the stairs, the ladder, the way back down) are run twice on the real
## range, once with every presentation feature off (old routes, route speed) and once with them all on (stair treads, ladder contacts, slow speeds, corner smoothing). The recorded
## action records, the state fingerprint after every move, the AP spent and the committed cells must be identical.
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

func _run_script(presentation: bool) -> Dictionary:
	var f := Fixture.new()
	await f.setup(self, 1, 1, 0, null, AIDifficultyPolicy.Tier.HARD, [], true)
	var actor: TacticalUnit = f.turns.player_units[0]
	f.place(actor, Vector3i(8, 0, 9))
	f.act_as(actor)
	var adapter: TacticalCharacterAdapter = actor.visual_adapter
	actor.stair_profile.enabled = presentation
	actor.stair_profile.slow_stairs_enabled = presentation
	actor.path_presentation.enabled = presentation
	adapter.rig.traversal_profile.slow_ladder_enabled = presentation
	for i in 20: await process_frame
	var records: Array = []
	f.battle.action_service.action_committed.connect(func(result) -> void: records.append(JSON.stringify(result.to_replay_record())))
	var log := {"records": records, "fingerprints": [], "ap": [], "cells": [], "results": [], "seconds": 0.0}
	var legs := [Vector3i(8, 0, 12), Vector3i(11, 0, 15), Vector3i(11, 3, 12), Vector3i(6, 0, 15), Vector3i(6, 3, 12), Vector3i(12, 0, 4), Vector3i(12, 3, 5), Vector3i(12, 0, 4)]
	var started := Time.get_ticks_msec()
	for destination: Vector3i in legs:
		if actor.grid_position == destination:
			continue
		var before := actor.stats.current_ap
		# Walk to the leg's start first when it is elsewhere (a placement is not an action: it is the script's own setup, identical in both runs).
		f.ready_actor(actor, 8, 4)
		var ok: bool = await f.battle.try_move(actor, destination)
		log.results.append(ok)
		log.ap.append(before - actor.stats.current_ap if ok else -1)
		log.cells.append(actor.grid_position)
		log.fingerprints.append(StateFingerprint.capture(f.turns, f.grid, null, true, true, true, true))
		if not ok:
			# An illegal leg from here (the script was written for one start): re-place identically and carry on.
			f.place(actor, destination)
			f.act_as(actor)
	log.seconds = (Time.get_ticks_msec() - started) / 1000.0
	await f.dispose(self)
	return log

func _run() -> void:
	var off := await _run_script(false)
	var on := await _run_script(true)
	print("  scripted moves: %d legs; shown in %.1f s with presentation off, %.1f s on" % [off.results.size(), off.seconds, on.seconds])
	check(off.results.size() == on.results.size() and off.results == on.results, "The same moves are accepted and rejected (%s)" % [off.results])
	check(off.records == on.records, "The recorded action records are byte-identical (%d records)" % off.records.size())
	check(off.fingerprints == on.fingerprints, "The state fingerprint after every move is identical")
	check(off.ap == on.ap, "The AP spent by every move is identical (%s)" % [off.ap])
	check(off.cells == on.cells, "The committed cell after every move is identical")
	check(on.seconds > off.seconds + 2.0, "Only the time to present differs: slower with the presentation speeds on (%.1f s vs %.1f s)" % [on.seconds, off.seconds])
	print("Traversal replay determinism: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

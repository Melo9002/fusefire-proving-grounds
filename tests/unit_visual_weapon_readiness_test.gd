extends SceneTree
## Weapon readiness and attack sequencing (animation improvement 04). Presentation only.
##
## An attack from a relaxed carry visibly raises the weapon, shows the shot only once the weapon is in its firing
## configuration, recovers and releases; from an already aimed pose there is no raise; the target reacts after the
## shot; higher-priority presentations cancel the sequence cleanly; the tactical result is untouched. Runs on the
## production UnitVisualAdapter, standalone and inside a real battle fixture (cover).
const Fixture := preload("res://tests/support/ai_scenario_fixture.gd")

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _new_rig() -> Array:
	var stage := Node3D.new()
	root.add_child(stage)
	var rig := load("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn").instantiate() as UnitVisualAdapter
	stage.add_child(rig)
	rig.position = Vector3.ZERO
	for i in 30: await process_frame
	var diagnostics := HandContactDiagnostics.attach(rig.rig)
	diagnostics.set_readout_visible(false)
	diagnostics.set_enabled(true)
	return [stage, rig, diagnostics]

## Runs one attack to the end of its sequence, one record per frame.
func _sequence(rig: UnitVisualAdapter, diagnostics: HandContactDiagnostics, target: Vector3, max_seconds := 3.0) -> Array:
	var rows: Array = []
	rig.present_attack(target)
	var started: float = rig.presenter.time
	while rig.presenter.time - started < max_seconds:
		rows.append(_row(rig, diagnostics, started))
		if rig.presenter.attack.phase == AttackSequence.Phase.NONE and rig.presenter.time - started > 0.05:
			break
		await process_frame
	rows.append(_row(rig, diagnostics, started))
	return rows

func _row(rig: UnitVisualAdapter, diagnostics: HandContactDiagnostics, started: float) -> Dictionary:
	var sample: Dictionary = diagnostics.latest
	var row := {
		"t": rig.presenter.time - started, "phase": rig.presenter.attack.phase, "state": rig.get_presentation_state(),
		"blend": rig.rig.aim_blend, "err": rig.weapon_alignment_error_degrees(), "flash": rig.rig.muzzle_flash.visible,
		"recoil": rig.rig.recoil, "depth": rig.rig._crouch_depth, "kneel": rig.rig._kneel,
	}
	if not sample.is_empty():
		row["dominant_wrist"] = float(sample.hands[0].wrist_to_ik_target)
		row["support_wrist"] = float(sample.hands[1].wrist_to_ik_target)
		row["stock"] = _stock_error(rig, sample)
		row["elbow_support"] = float(sample.hands[1].elbow_angle_deg)
	return row

func _stock_error(rig: UnitVisualAdapter, sample: Dictionary) -> float:
	var pocket: Vector3 = (sample.hands[0].shoulder as Vector3) + rig.rig.character_root.global_basis * rig.rig.shoulder_contact_offset
	return (sample.points.stock as Vector3).distance_to(pocket)

func _first(rows: Array, key: String, value) -> int:
	for i in rows.size():
		if rows[i][key] == value:
			return i
	return -1

func _max(rows: Array, key: String, from := 0) -> float:
	var best := 0.0
	for i in range(from, rows.size()):
		best = maxf(best, float(rows[i].get(key, 0.0)))
	return best

## Rows of the attack itself: from the request until the release starts (the release is lowering by design).
func _until_release(rows: Array) -> Array:
	var kept: Array = []
	for row in rows:
		if row.phase == AttackSequence.Phase.RELEASE:
			break
		kept.append(row)
	return kept

func _quiet(rig: UnitVisualAdapter) -> void:
	for i in 30: await process_frame
	await create_timer(0.8).timeout
	for i in 3: await process_frame

func _run() -> void:
	var profile := WeaponHandlingProfile.new()
	var tolerance := profile.alignment_tolerance_degrees

	# 1. The readiness model and the profile data behind it.
	var model := WeaponReadiness.new()
	check(model.requested() == WeaponReadiness.Level.LOWERED, "Nothing requested means lowered")
	model.request(&"attack", WeaponReadiness.Level.AIMED)
	model.request(&"guard", WeaponReadiness.Level.READY)
	check(model.requested() == WeaponReadiness.Level.AIMED, "The highest request wins")
	model.release(&"attack")
	check(model.requested() == WeaponReadiness.Level.READY and WeaponReadiness.blend_for(WeaponReadiness.Level.READY, profile) == profile.ready_blend, "Releasing one request falls back to the next (a sustained request needs no other machinery)")
	model.clear()
	check(model.requested() == WeaponReadiness.Level.LOWERED and not model.has_request(&"guard"), "Clearing drops every request")
	check(WeaponReadiness.level_for_blend(0.0, profile) == WeaponReadiness.Level.LOWERED and WeaponReadiness.level_for_blend(profile.ready_blend, profile) == WeaponReadiness.Level.READY and WeaponReadiness.level_for_blend(1.0, profile) == WeaponReadiness.Level.AIMED, "Blend 0, ready blend and 1 are lowered, ready and aimed")
	var threshold := profile.aimed_blend_threshold()
	check(threshold > 0.9 and threshold < 1.0 and profile.ready_blend < threshold, "The aimed threshold (%.3f) sits just under 1 and above the ready blend" % threshold)
	var carry_angle := rad_to_deg(Quaternion.from_euler(profile.lowered_angles_degrees * (PI / 180.0)).get_angle())
	check(is_equal_approx((1.0 - threshold) * carry_angle, tolerance), "The threshold is exactly the alignment tolerance of muzzle angle (%.2f deg of a %.1f deg carry)" % [tolerance, carry_angle])
	check(profile.lowered_angles_degrees == Vector3(35, 40, -8) and profile.lowered_grip == Vector3(-0.08, 1.16, 0.15) and is_equal_approx(profile.scale, 0.82), "The AUG's carry values and scale moved into the profile unchanged")

	var made: Array = await _new_rig()
	var rig: UnitVisualAdapter = made[1]
	var diagnostics: HandContactDiagnostics = made[2]
	check(rig.get_presentation_state() == &"rifle_idle" and rig.rig.aim_blend < 0.01 and rig.readiness_level() == WeaponReadiness.Level.LOWERED, "A fresh unit carries the weapon lowered")
	var forward := rig.global_basis.z
	var target := rig.global_position + forward * 8.0

	# 2. Attack from the relaxed carry: raise, align, fire, recover, release.
	var rows: Array = await _sequence(rig, diagnostics, target)
	var timeline: Dictionary = rig.presenter.attack.timeline
	var fire_row := _first(rows, "flash", true)
	check(fire_row > 0, "The first frame of an attack from relaxed shows no shot (flash first visible at row %d)" % fire_row)
	check(rows[0].state == &"aim" and rows[0].phase == AttackSequence.Phase.RAISE and not rows[0].flash and rows[0].recoil == 0.0, "It starts by raising: aim stance, raise phase, no flash, no recoil")
	check(bool(timeline.fired) and not bool(timeline.forced), "The shot waited for alignment instead of being forced")
	check(float(timeline.fire_blend) >= threshold and float(timeline.fire_muzzle_error_degrees) <= tolerance + 0.01, "Fired with the weapon aligned: blend %.3f (threshold %.3f), muzzle %.2f deg off (tolerance %.1f)" % [timeline.fire_blend, threshold, timeline.fire_muzzle_error_degrees, tolerance])
	var worst_flash_error := 0.0
	for row in rows:
		if row.flash: worst_flash_error = maxf(worst_flash_error, float(row.err))
	check(worst_flash_error <= tolerance + 0.5, "At no frame was the flash visible while the muzzle was misaligned (worst %.2f deg, tolerance %.1f plus one frame of sampling)" % [worst_flash_error, tolerance])
	var expected_raise: float = profile.raise_seconds * threshold
	check(absf(float(timeline.fire_t) - expected_raise) < 0.06, "The raise took what the profile says: fired at %.3f s, raise %.2f s x blend %.2f = %.3f s" % [timeline.fire_t, profile.raise_seconds, threshold, expected_raise])
	check(rows[fire_row].recoil > 0.0 and rows[fire_row - 1].recoil == 0.0, "Recoil begins on the frame the flash does (recoil %.3f)" % rows[fire_row].recoil)
	check(_first(rows, "state", &"shoot") == fire_row, "The shoot state and the flash start on the same frame")
	var phases: Array = []
	for entry in timeline.phases: phases.append(entry.phase)
	check(phases == [AttackSequence.Phase.RAISE, AttackSequence.Phase.ALIGN, AttackSequence.Phase.FIRE, AttackSequence.Phase.RECOVER, AttackSequence.Phase.RELEASE], "Phases run raise, align, fire, recover, release (%s)" % str(phases))
	var recover_at := 0.0
	var release_at := 0.0
	for entry in timeline.phases:
		if entry.phase == AttackSequence.Phase.RECOVER: recover_at = entry.t
		if entry.phase == AttackSequence.Phase.RELEASE: release_at = entry.t
	check(absf((release_at - recover_at) - profile.shot_recover_seconds) < 0.06, "Release starts shot_recover_seconds after the shot (%.3f s, profile %.2f s)" % [release_at - recover_at, profile.shot_recover_seconds])
	var normalized_fire: float = float(timeline.fire_t) / float(timeline.end_t)
	print("  normalized timeline (fraction of the %.3f s sequence): raise ends/fires at %.2f, release starts at %.2f" % [timeline.end_t, normalized_fire, release_at / float(timeline.end_t)])
	check(rig.presenter.attack.phase == AttackSequence.Phase.NONE and rig.get_presentation_state() == &"rifle_idle" and rig.rig.aim_blend < 0.01 and not rig.rig.readiness.has_request(AttackSequence.SOURCE), "An ordinary attack ends relaxed: idle, blend 0, no request left (blend %.3f)" % rig.rig.aim_blend)
	check(rig.readiness_level() == WeaponReadiness.Level.LOWERED, "Readiness is lowered again")
	var dominant := _max(rows, "dominant_wrist")
	check(dominant < 0.002, "The firing hand stays on its grip through the whole sequence (worst %.2f mm)" % (dominant * 1000.0))
	check(_max(rows, "stock") < 0.1, "The stock stays with the shoulder (worst %.1f mm while the weapon travels; measured against the final pocket)" % (_max(rows, "stock") * 1000.0))
	var pre_shot_stock := float(rows[fire_row - 1].stock)
	# The stock sits at the end of the weapon's lever arm about the grip, so the alignment tolerance itself allows
	# lever x tan(tolerance) of stock offset at the instant the shot is allowed (about 5.7 mm at 1 degree); the stock
	# reaches the pocket exactly as the blend reaches 1. (An earlier fixed 2 mm bound only passed by frame timing.)
	var stock_lever: float = absf(profile.stock_rear.z) * profile.scale
	var stock_allowance: float = stock_lever * tan(deg_to_rad(tolerance)) + 0.0005
	check(pre_shot_stock < stock_allowance, "When the weapon is aligned, just before the shot, the stock is within the alignment tolerance's own allowance of the shoulder pocket (%.2f of %.2f mm)" % [pre_shot_stock * 1000.0, stock_allowance * 1000.0])
	var relaxed_recover_support := _max(_until_release(rows), "support_wrist", fire_row)
	var relaxed_raise_support := _max(rows.slice(0, fire_row), "support_wrist")
	print("  relaxed (support wrist: raise %.2f mm, shot and recover %.2f mm): fire at %.3f s, blend %.3f, muzzle %.2f deg; worst dominant wrist %.2f mm, support wrist %.2f mm over the whole sequence; support elbow at the shot %.0f deg" % [relaxed_raise_support * 1000.0, relaxed_recover_support * 1000.0, timeline.fire_t, timeline.fire_blend, timeline.fire_muzzle_error_degrees, dominant * 1000.0, _max(rows, "support_wrist") * 1000.0, rows[fire_row].elbow_support])
	await _quiet(rig)

	# 3. Attack from a committed Aim: already aimed, so no raise, and the shot is shown at once.
	rig.presenter.aim.held = true
	rig.presenter.aim.release_left = 1000000.0
	rig.present_idle()
	await create_timer(0.8).timeout
	check(rig.rig.aim_blend > 0.99 and rig.readiness_level() == WeaponReadiness.Level.AIMED, "Setup: aim held, weapon aimed")
	rows = await _sequence(rig, diagnostics, target)
	timeline = rig.presenter.attack.timeline
	check(float(timeline.fire_t) == 0.0 and rows[0].flash and rows[0].state == &"shoot", "From an aimed pose the shot is shown on the first frame, with no raise")
	var attack_rows := _until_release(rows)
	check(_max(attack_rows, "err") < 0.5 and float(rows[0].blend) > 0.99, "The weapon never left its firing configuration before or during the shot (worst %.2f deg)" % _max(attack_rows, "err"))
	var aimed_recover_support := _max(attack_rows, "support_wrist")
	check(relaxed_recover_support <= aimed_recover_support + 0.002, "Raising first adds no support-hand drift to the shot: %.2f mm after a raise, %.2f mm from an aimed pose" % [relaxed_recover_support * 1000.0, aimed_recover_support * 1000.0])
	check(not bool(timeline.forced), "...and it was not forced")
	await _quiet(rig)
	rig.presenter.aim.held = false

	# 4. Sustained readiness: a request from any source keeps the weapon up through an attack, then releases when withdrawn.
	rig.request_readiness(&"guard", WeaponReadiness.Level.AIMED)
	rig.present_idle()
	await create_timer(0.8).timeout
	check(rig.rig.aim_blend > 0.99 and rig.get_presentation_state() == &"aim", "A sustained AIMED request holds the aim stance (state %s)" % rig.get_presentation_state())
	rows = await _sequence(rig, diagnostics, target)
	check(float(rig.presenter.attack.timeline.fire_t) == 0.0 and rig.rig.aim_blend > 0.99 and rig.get_presentation_state() == &"aim", "After its shot a unit with a sustained request is still aimed (blend %.2f, state %s)" % [rig.rig.aim_blend, rig.get_presentation_state()])
	rig.release_readiness(&"guard")
	await create_timer(0.9).timeout
	check(rig.rig.aim_blend < 0.01, "Withdrawing the request lowers the weapon")
	rig.request_readiness(&"guard", WeaponReadiness.Level.READY)
	await create_timer(0.8).timeout
	check(absf(rig.rig.aim_blend - profile.ready_blend) < 0.01 and rig.readiness_level() == WeaponReadiness.Level.READY, "A READY request holds the ready blend, short of aimed (blend %.2f)" % rig.rig.aim_blend)
	rows = await _sequence(rig, diagnostics, target)
	var from_ready: Dictionary = rig.presenter.attack.timeline
	check(float(from_ready.fire_t) < float(timeline.fire_t) + expected_raise and float(from_ready.fire_t) > 0.0 and not bool(from_ready.forced) and float(from_ready.fire_muzzle_error_degrees) <= tolerance + 0.01, "From READY only the remaining raise is shown (fired at %.3f s, muzzle %.2f deg)" % [from_ready.fire_t, from_ready.fire_muzzle_error_degrees])
	rig.release_readiness(&"guard")
	await _quiet(rig)

	# 5. Interruption: a hit takes over mid-raise; nothing fires and the weapon returns to relaxed.
	var ended: Array = []
	var fired_signals := [0]
	rig.presenter.attack.shot_released.connect(func(_t: Dictionary) -> void: fired_signals[0] += 1)
	var interrupted: AttackHandle = rig.present_attack(target)
	interrupted.when_done(func(outcome: int) -> void: ended.append(outcome))
	await create_timer(0.1).timeout
	check(not interrupted.shot.is_done() and rig.rig.aim_blend > 0.1, "Setup: the raise is under way")
	rig.present_hit()
	var saw_flash := false
	for i in 40:
		await process_frame
		saw_flash = saw_flash or rig.rig.muzzle_flash.visible
	check(ended == [PresentationTypes.Outcome.INTERRUPTED] and interrupted.shot.outcome == PresentationTypes.Outcome.INTERRUPTED and fired_signals[0] == 0 and not saw_flash and not rig.presenter.attack.is_pending(), "A hit during the raise interrupts it: both handles INTERRUPTED once, no shot, no flash")
	check(rig.get_presentation_state() in [&"hit", &"rifle_idle"] and rig.presenter.attack.phase == AttackSequence.Phase.NONE, "The hit state owns the pose (%s)" % rig.get_presentation_state())
	await create_timer(1.6).timeout
	check(rig.get_presentation_state() == &"rifle_idle" and rig.rig.aim_blend < 0.01 and not rig.rig.readiness.has_request(AttackSequence.SOURCE), "The weapon is not stuck raised after the interruption (state %s, blend %.2f)" % [rig.get_presentation_state(), rig.rig.aim_blend])

	# 6. Superseded: a second attack replaces the first mid-raise; exactly one shot is shown for it.
	ended.clear()
	fired_signals[0] = 0
	var first_attack: AttackHandle = rig.present_attack(target)
	first_attack.when_done(func(outcome: int) -> void: ended.append(outcome))
	await create_timer(0.1).timeout
	var second_attack: AttackHandle = rig.present_attack(target)
	second_attack.when_done(func(outcome: int) -> void: ended.append(outcome))
	var flashes := 0
	var was_visible := false
	var guard := 0
	while (rig.presenter.attack.phase != AttackSequence.Phase.NONE or guard < 5) and guard < 200:
		await process_frame
		guard += 1
		if rig.rig.muzzle_flash.visible and not was_visible: flashes += 1
		was_visible = rig.rig.muzzle_flash.visible
	check(fired_signals[0] == 1 and flashes == 1, "A superseded attack is dropped: one shot, one flash (%d shots, %d flashes)" % [fired_signals[0], flashes])
	check(ended == [PresentationTypes.Outcome.INTERRUPTED, PresentationTypes.Outcome.COMPLETED], "The first sequence was interrupted and settled once, the second completed (%s)" % str(ended))
	await _quiet(rig)

	# 7. Defeat has priority, and leaves no weapon request behind.
	ended.clear()
	var doomed: AttackHandle = rig.present_attack(target)
	doomed.when_done(func(outcome: int) -> void: ended.append(outcome))
	await create_timer(0.1).timeout
	rig.present_defeat()
	await create_timer(0.8).timeout
	check(rig.get_presentation_state() == &"defeat" and ended == [PresentationTypes.Outcome.INTERRUPTED] and not rig.rig.readiness.has_request(AttackSequence.SOURCE) and not rig.rig.muzzle_flash.visible, "Defeat during the raise wins: defeat state, no shot, request dropped")
	rig.queue_free()
	made[0].queue_free()
	await process_frame

	# 8. A carrier holds nothing, never raises, and attack requests do not break the carry.
	var carry_made: Array = await _new_rig()
	var carrier: UnitVisualAdapter = carry_made[1]
	carrier.preview_carrying = true
	carrier.present_idle()
	await create_timer(0.5).timeout
	check(carrier.readiness_level() == WeaponReadiness.Level.STOWED and carrier.get_presentation_state() == &"carry_idle", "A carrier's weapon is stowed (state %s)" % carrier.get_presentation_state())
	var carried_attack: AttackHandle = carrier.present_attack(carrier.global_position + carrier.global_basis.z * 8.0)
	check(carried_attack.shot.outcome == PresentationTypes.Outcome.SKIPPED and not carrier.presenter.attack.is_pending() and carrier.presenter.attack.phase == AttackSequence.Phase.NONE, "A carrier's attack request starts no raise sequence")
	await create_timer(0.8).timeout
	check(carrier.rig.aim_blend < 0.01 and carrier.readiness_level() == WeaponReadiness.Level.STOWED, "...and its weapon stays stowed (blend %.2f)" % carrier.rig.aim_blend)
	carry_made[0].queue_free()
	await process_frame

	await _battle_cases()
	print("Weapon readiness sequence: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

## Cover postures and the presenter, inside a real battle: tactical truth is committed before the visual starts.
func _battle_cases() -> void:
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
	var diagnostics := HandContactDiagnostics.attach(adapter.rig)
	diagnostics.set_readout_visible(false)
	diagnostics.set_enabled(true)
	for i in 30: await process_frame
	var profile: WeaponHandlingProfile = adapter.rig.handling
	var threshold := profile.aimed_blend_threshold()

	# Posture-independent readiness: standing, partial crouch, full crouch, half-kneel behind low cover.
	var cell := f.grid.get_unit_grid(actor)
	var postures := [["standing", -1.0], ["crouch (cover 1.4)", 1.4], ["deep crouch (cover 1.1)", 1.1], ["half-kneel (cover 0.9)", 0.9]]
	for entry in postures:
		var label: String = entry[0]
		var height: float = entry[1]
		f.set_cover(cell + Vector3i.RIGHT, MapCellData.CoverType.NONE if height < 0.0 else MapCellData.CoverType.LOW, maxf(height, 0.0))
		adapter.present_idle()
		await create_timer(1.6).timeout
		for i in 3: await process_frame
		var depth_before: float = adapter.rig._crouch_depth
		var kneel_before: float = adapter.rig._kneel
		var rows: Array = await _sequence(adapter, diagnostics, enemy.global_position)
		var attack_rows := _until_release(rows)
		var timeline: Dictionary = adapter.presenter.attack.timeline
		var fire_row := _first(rows, "flash", true)
		check(bool(timeline.fired) and not bool(timeline.forced) and fire_row >= 0, "%s: the shot is shown after the raise (fired at %.3f s, forced %s)" % [label, timeline.get("fire_t", -1.0), timeline.forced])
		check(float(timeline.fire_blend) >= threshold and float(timeline.fire_muzzle_error_degrees) <= profile.alignment_tolerance_degrees + 0.01, "%s: aligned at the shot (blend %.3f, muzzle %.2f deg)" % [label, timeline.fire_blend, timeline.fire_muzzle_error_degrees])
		var worst_flash := 0.0
		for row in rows:
			if row.flash: worst_flash = maxf(worst_flash, float(row.err))
		check(worst_flash <= profile.alignment_tolerance_degrees + 0.5, "%s: the flash never showed while misaligned (worst %.2f deg)" % [label, worst_flash])
		check(float(rows[fire_row].recoil) > 0.0 and (fire_row == 0 or float(rows[fire_row - 1].recoil) == 0.0), "%s: recoil starts with the flash" % label)
		# Aiming over cover lifts the body from its hiding posture to the peek posture (existing behaviour, driven by the
		# same blend as the raise). The shot must stand in that same peek posture, not in some third one.
		var shot_depth := float(attack_rows[-1].depth)
		var shot_kneel := float(attack_rows[-1].kneel)
		check(_max(rows, "dominant_wrist") < 0.002, "%s: the firing hand stays on the grip (worst %.2f mm)" % [label, _max(rows, "dominant_wrist") * 1000.0])
		print("  %s: fire %.3f s, muzzle %.2f deg, dominant wrist %.2f mm, support wrist worst %.2f mm (shot and recover %.2f mm; support elbow at the shot %.0f deg), stock before the shot %.2f mm" % [label, timeline.fire_t, timeline.fire_muzzle_error_degrees, _max(rows, "dominant_wrist") * 1000.0, _max(rows, "support_wrist") * 1000.0, _max(attack_rows, "support_wrist", fire_row) * 1000.0, rows[fire_row].elbow_support, float(rows[maxi(fire_row - 1, 0)].stock) * 1000.0])
		await create_timer(1.6).timeout
		check(adapter.rig.aim_blend < 0.01 and adapter.presenter.attack.phase == AttackSequence.Phase.NONE, "%s: the weapon is relaxed again (blend %.2f)" % [label, adapter.rig.aim_blend])
		check(absf(adapter.rig._crouch_depth - depth_before) < 0.02 and absf(adapter.rig._kneel - kneel_before) < 0.05, "%s: the body is back in its hiding posture (crouch %.3f vs %.3f, kneel %.2f vs %.2f)" % [label, adapter.rig._crouch_depth, depth_before, adapter.rig._kneel, kneel_before])
		adapter.presenter.aim.held = true
		adapter.presenter.aim.release_left = 1000000.0
		adapter.present_idle()
		await create_timer(1.6).timeout
		check(absf(adapter.rig._crouch_depth - shot_depth) < 0.03 and absf(adapter.rig._kneel - shot_kneel) < 0.1, "%s: the shot posture equals the held-aim posture (crouch %.3f vs %.3f, kneel %.2f vs %.2f)" % [label, shot_depth, adapter.rig._crouch_depth, shot_kneel, adapter.rig._kneel])
		adapter.presenter.aim.held = false
		adapter.present_idle()
		await create_timer(1.6).timeout
	f.set_cover(cell + Vector3i.RIGHT, MapCellData.CoverType.NONE, 0.0)
	adapter.present_idle()
	await create_timer(1.0).timeout

	# The real action: the tactical result is committed before the visual starts, unchanged by it, and the target reacts after the shot.
	var committed_fingerprint := []
	var committed_revision := [0]
	var service: TacticalActionService = f.battle.action_service
	service.action_committed.connect(func(_result) -> void:
		committed_fingerprint.append(BattleStateFingerprint.capture(f.turns, f.grid, f.level.objective_manager))
		committed_revision[0] = service.state_revision)
	var events: Array = []
	var shot_time := [-1.0]
	adapter.presenter.attack.shot_released.connect(func(_t: Dictionary) -> void: events.append("shot"))
	enemy.visual_adapter.presentation_state_changed.connect(func(state: StringName) -> void:
		if state in [&"hit", &"defeat"]: events.append("reaction"))
	var hp_before := enemy.stats.current_hp
	check(await f.battle.try_attack(actor, enemy), "Setup: the attack commits")
	await create_timer(0.5).timeout
	check(committed_fingerprint.size() == 1 and committed_fingerprint[0] == BattleStateFingerprint.capture(f.turns, f.grid, f.level.objective_manager), "The tactical state after the staged presentation is identical to the state at commit")
	check(service.state_revision == committed_revision[0], "Presentation committed no further revision")
	check(enemy.stats.current_hp < hp_before, "Setup: the attack hit (HP %d to %d)" % [hp_before, enemy.stats.current_hp])
	check(events.size() >= 2 and events[0] == "shot" and events.has("reaction"), "The shot is shown before the target reacts (%s)" % str(events))
	await f.dispose(self)

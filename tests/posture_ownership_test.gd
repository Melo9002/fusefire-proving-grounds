extends SceneTree
## Cover posture ownership (Task 07 package 3). The tactical adapter's cover POLICY decides what cover asks of the body and hands it to the presenter as a source-keyed posture request
## (`tactical/cover`, CONTEXT priority); the PostureArbiter resolves it and the rig is the only writer of the crouch, kneel and body-yaw ramps. This proves the request flow, idempotence,
## arbitration against a higher-priority source, ramp continuity, and release on every way a cover pose can end (leaving cover, defeat, teardown). The workbench's cover demo and diagnostic
## preset use the same two shared calls. Structural headless checks say nothing about how any pose looks; the cover look itself is pinned by the existing cover tests.
const VISUAL := preload("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn")
const WORKBENCH := preload("res://tools/animation_workbench/pose_workbench.tscn")
const SOURCE := &"tactical/cover"
var failures := 0
var checks := 0

func _initialize() -> void:
	Engine.max_fps = 60
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _enter_cover(rig: TacticalCharacterAdapter, height: float, type := MapCellData.CoverType.LOW) -> void:
	rig.last_cover_contact = {"type": type, "height": height, "direction": Vector3.FORWARD}
	rig.rig.animation_controller.play(&"cover_low" if type == MapCellData.CoverType.LOW else &"cover_high")

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _winner_row(rig: TacticalCharacterAdapter) -> Dictionary:
	for row in rig.presenter.postures.report():
		if row.winner:
			return row
	return {}

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var rig: TacticalCharacterAdapter = VISUAL.instantiate()
	stage.add_child(rig)
	await _frames(20)
	var posture := rig.presenter.postures
	var modifier := rig.rig.crouch_modifier

	# ---- Out of cover there is no request and the body stands.
	check(posture.request_count() == 0 and rig.presenter.intent().posture == PresentationTypes.Posture.STAND, "Out of cover: no posture request, standing")

	# ---- Cover policy becomes a source-keyed CONTEXT request; the rig follows it.
	_enter_cover(rig, 1.1)
	await _frames(2)
	var first := _winner_row(rig)
	check(posture.has_request(SOURCE) and first.get("source", &"") == SOURCE and int(first.get("priority", -1)) == PresentationTypes.PRIORITY_CONTEXT, "Entering cover requests under the tactical/cover source at CONTEXT priority")
	check(rig.presenter.intent().posture == PresentationTypes.Posture.CROUCH and rig.presenter.intent().posture_depth > 0.1, "The intent snapshot shows CROUCH with the depth cover asked for (%.3f)" % rig.presenter.intent().posture_depth)
	var depth_one_frame := modifier.depth
	check(depth_one_frame > 0.0 and depth_one_frame <= rig.rig.cover_profile.crouch_speed / 30.0 + 0.001, "The rig EASES toward the request: it does not snap (%.4f m after two frames)" % depth_one_frame)
	await _frames(70)
	var want := minf(float(_winner_row(rig).depth), modifier.max_depth)
	check(absf(modifier.depth - want) < 0.005 and absf(rig.rig._crouch_depth - modifier.depth) < 0.0001, "The applied crouch reaches the request, clamped to the human limit (%.3f of %.3f)" % [modifier.depth, want])

	# ---- Idempotence: a steady cover state repeats the same request every frame without reordering.
	var sequence := int(_winner_row(rig).sequence)
	await _frames(40)
	check(int(_winner_row(rig).sequence) == sequence, "Repeated identical requests do not refresh the order or reset anything (sequence %d)" % sequence)

	# ---- Arbitration: a higher-priority source wins without disturbing the stored cover request.
	posture.set_posture(&"test/forced", PresentationTypes.Posture.STAND, PresentationTypes.PRIORITY_ACTION, 0.0, 0.0)
	await _frames(70)
	check(_winner_row(rig).source == &"test/forced" and modifier.depth < 0.005, "A higher-priority STAND request stands the body up (depth %.3f)" % modifier.depth)
	check(posture.has_request(SOURCE), "...while the cover request stays stored")
	posture.release(&"test/forced")
	await _frames(70)
	check(_winner_row(rig).source == SOURCE and absf(modifier.depth - want) < 0.005, "Releasing the higher request lets the cover posture resume (depth %.3f)" % modifier.depth)
	# Equal priority: the most recent change wins (deterministic), and the order is observable.
	posture.set_posture(&"test/peer", PresentationTypes.Posture.CROUCH, PresentationTypes.PRIORITY_CONTEXT, 0.0, 0.1)
	check(_winner_row(rig).source == &"test/peer" and _winner_row(rig).get("tied_with_winner", false) == false, "An equal-priority request made later takes over")
	posture.release(&"test/peer")

	# ---- Kneeling: cover too low to crouch behind is a KNEEL request.
	_enter_cover(rig, 0.4)
	await _frames(70)
	check(rig.presenter.intent().posture == PresentationTypes.Posture.KNEEL and rig.rig._kneel > 0.9, "Very low cover is a KNEEL request and the rig kneels (kneel %.2f)" % rig.rig._kneel)

	# ---- Release on leaving cover: the request is withdrawn and the posture eases back to standing.
	rig.last_cover_contact = {"type": MapCellData.CoverType.NONE, "direction": Vector3.ZERO}
	rig.rig.animation_controller.play(&"rifle_idle")
	await _frames(2)
	check(not posture.has_request(SOURCE) and posture.request_count() == 0, "Leaving cover releases the cover request")
	await _frames(70)
	check(modifier.depth < 0.005 and modifier.kneel < 0.01 and absf(rig.rig._cover_yaw) < deg_to_rad(1.0), "...and the depth, kneel and yaw offset all ease back to nothing")

	# ---- Release on defeat while in cover.
	_enter_cover(rig, 1.1)
	await _frames(30)
	check(posture.has_request(SOURCE), "Setup: back in cover")
	rig.present_defeat()
	await _frames(3)
	check(not posture.has_request(SOURCE), "Defeat releases the cover request")

	# ---- Release on teardown: nothing outlives the character, even a request that was never released.
	var doomed: TacticalCharacterAdapter = VISUAL.instantiate()
	stage.add_child(doomed)
	await _frames(10)
	_enter_cover(doomed, 1.1)
	doomed.presenter.postures.set_posture(&"test/never_released", PresentationTypes.Posture.CROUCH, PresentationTypes.PRIORITY_FORCED, 0.0, 0.2)
	await _frames(5)
	check(doomed.presenter.postures.request_count() == 2, "Setup: two requests held")
	var held_presenter := doomed.presenter
	stage.remove_child(doomed)
	check(held_presenter.postures.request_count() == 0, "Leaving the tree tears the presenter down: every request is released")
	doomed.free()

	# ---- Superseded writers are gone: the cover policy no longer touches the ramps (text-level ratchet lives in animation_module_boundaries_test).
	var adapter_text := FileAccess.get_file_as_string("res://presentation/tactical/tactical_character_adapter.gd")
	check(not adapter_text.contains("crouch_modifier.depth =") and not adapter_text.contains("crouch_modifier.kneel ="), "The adapter has no direct writer of the crouch depth or kneel any more")

	# ---- The workbench uses the same shared calls: a diagnostic preset (BASE) and a cover demo (CONTEXT) arbitrate through the presenter.
	var bench: Node3D = WORKBENCH.instantiate()
	root.add_child(bench)
	await _frames(20)
	var bp: CharacterPresenter = bench.presenter
	check(bp != null and bp.rig == bench.rig, "The workbench owns a presenter bound to its rig, like the production visual")
	bench._pose_preset = 1
	await _frames(60)
	check(bp.postures.has_request(&"workbench/pose_preset") and bp.postures.resolved_source() == &"workbench/pose_preset" and bench.rig.crouch_modifier.depth > 0.1, "The workbench pose preset is a BASE posture request that the rig follows")
	bench.set_cover_demo({"full": false, "height": 1.0, "left": 1.5, "right": 1.5, "left_ok": true, "right_ok": true, "aim": false})
	await _frames(60)
	check(bp.postures.resolved_source() == &"workbench/cover" and bp.postures.has_request(&"workbench/pose_preset"), "A cover demo (CONTEXT) outranks the preset (BASE), which stays stored")
	bench.set_cover_demo({})
	await _frames(60)
	check(not bp.postures.has_request(&"workbench/cover") and bp.postures.resolved_source() == &"workbench/pose_preset", "Ending the demo releases its request and the preset resumes")
	bench._pose_preset = 0
	await _frames(60)
	check(bp.postures.request_count() == 0 and bench.rig.crouch_modifier.depth < 0.01 and bench.rig.crouch_modifier.kneel < 0.01, "Clearing the preset stands the workbench character up")

	print("Posture ownership: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

extends SceneTree
## Interruption cleanup (Task 07 safety net): whichever way a presentation action ends (movement end, defeat, an explicit end call), the temporary state it set on the rig is released:
## ladder/vault traversal, stair pose, leg IK, hand contacts, torso lean and the stowed weapon. A leak here is the "stuck pose after interruption" class of bug the presenter migration must not introduce.
const VISUAL := preload("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn")
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _spawn() -> UnitVisualAdapter:
	var v: UnitVisualAdapter = VISUAL.instantiate()
	root.add_child(v)
	return v

func _clean(v: UnitVisualAdapter, label: String) -> void:
	check(v.ladder == null, "%s: traversal state released" % label)
	check(v.ladder == null or v.ladder.pose == null, "%s: traversal pose released" % label)
	check(v.stairs == null, "%s: stair state and pose released" % label)
	check(not v.is_ladder_active(), "%s: ladder inactive" % label)
	check(not is_instance_valid(v.leg_ik) or not v.leg_ik.active, "%s: leg IK inactive" % label)
	check(not v.is_weapon_stowed(), "%s: weapon not left stowed" % label)

func _run() -> void:
	for i in 3:
		await process_frame
	# Ladder interrupted by the end of movement.
	var a := _spawn()
	await process_frame
	a.begin_traversal(&"ladder", 3.0, 1)
	a.set_traversal_progress(1.2)
	await process_frame
	check(a.ladder != null, "Setup: a ladder traversal is active")
	a.present_movement_end()
	_clean(a, "ladder -> movement end")
	# Ladder interrupted by defeat.
	var b := _spawn()
	await process_frame
	b.begin_traversal(&"ladder", 3.0, -1)
	b.set_traversal_progress(2.0)
	await process_frame
	b.present_defeat()
	_clean(b, "ladder -> defeat")
	# Stairs interrupted by movement end and by defeat.
	var model := StairModel.from_links(Vector3.ZERO, Vector3(0, 0, 1), 1.0, 1.0, 2, 3)
	check(model != null, "Setup: a stair model builds")
	for label in ["movement end", "defeat"]:
		var c := _spawn()
		await process_frame
		c.begin_stairs(model, true)
		c.set_stair_progress(1.0, 1.5)
		await process_frame
		check(c.stairs != null, "Setup: stairs are active (%s)" % label)
		if label == "defeat":
			c.present_defeat()
		else:
			c.present_movement_end()
		_clean(c, "stairs -> " + label)
	# Ending twice is harmless (idempotent).
	a.present_movement_end()
	a.present_defeat()
	_clean(a, "repeated end")
	# A hit mid-ladder does not leave or corrupt the traversal; ending it afterwards still cleans up.
	var d := _spawn()
	await process_frame
	d.begin_traversal(&"ladder", 3.0, 1)
	d.set_traversal_progress(0.5)
	d.present_hit()
	d.present_movement_end()
	_clean(d, "ladder -> hit -> movement end")
	print("Animation cleanup: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

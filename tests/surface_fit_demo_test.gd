extends SceneTree
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var demo = load("res://art/characters/mira_0/demo/surface_fit_demo.tscn").instantiate()
	root.add_child(demo)
	for frame in 4: await process_frame
	check(demo.last_fit.fits and is_equal_approx(demo.last_fit.position.x, -0.17), "Default lab shifts the body to the safe portion of the cell")
	check(demo.last_center_blocked and not demo.last_resolved_blocked, "Existing LOS routine distinguishes old center and resolved point around the edge")
	check(not demo.grid.get_cell_data(Vector3i(4, 0, 4)).can_stop and demo.grid.occupancy_map.is_empty(), "Lab does not enable blocked navigation or occupy a cell")
	check(demo.visual.get_presentation_state() == &"cover_high" and demo.visual.last_cover_contact.found, "Authored placeholder pose receives a procedural contact target")
	demo.slider.value = 0
	check(not demo.last_fit.fits and not demo.visual.visible, "An object leaving no body-sized fit hides the placeholder and reports rejection")
	demo.slider.value = 1.2
	check(demo.last_fit.fits and is_equal_approx(demo.last_fit.position.x, 0.38), "Moving the object away lets the body approach its real face within the cell")
	demo.queue_free()
	await process_frame
	await process_frame
	print("Surface fit lab: 6 checks, %d failure(s)" % failures)
	quit(1 if failures else 0)

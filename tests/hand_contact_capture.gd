extends SceneTree
## Hand-contact diagnostic captures (explicit-only; images need a display, the numbers do not).
## Drives the production TacticalCharacterAdapter through the same states and cover contexts the game uses, with
## HandContactDiagnostics attached, and writes for every pose: a full-body sheet, a hands close-up sheet
## and the measurements, so before/after comparisons are made on fixed cameras and fixed numbers.
##   godot_console --path . --script res://tests/hand_contact_capture.gd -- <directory> <tag> [poses] [legacy]
## "legacy" switches the WeaponPose modifier off, giving the pre-correction behaviour for before/after comparisons.
## Poses (comma separated): a state name, optionally with "@<cover height>" and "+aim", e.g.
##   rifle_idle  aim  shoot@0.07  cover_low@1.15  cover_low@1.15+aim  cover_low@0.5  cover_low@0.5+aim
## "shoot@0.07" samples 0.07 s after the shot starts. Cover heights: 1.15 m is hidden by a crouch, 0.5 m needs
## the half-kneel. Transitions are listed in TRANSITIONS and recorded frame by frame.
## Output: <directory>/<tag>-<pose>-body.png, -hands.png, and <tag>-baseline.json with every number.
## The cameras follow the character's facing (including a body turned to cover) and use the same framing for
## every pose; they are diagnostic cameras only and have nothing to do with the gameplay camera.
const DEFAULT_POSES := "rifle_idle,aim,shoot@0.07,cover_low@1.15,cover_low@1.15+aim,cover_low@0.5,cover_low@0.5+aim"
const TRANSITIONS := [
	["rifle_idle", "aim"], ["aim", "shoot@0.0"], ["shoot@0.0", "aim"], ["aim", "rifle_idle"],
	["rifle_idle", "cover_low@1.15"], ["rifle_idle", "cover_low@0.5"], ["cover_low@0.5", "cover_low@0.5+aim"], ["cover_low@0.5+aim", "cover_low@0.5"],
]
const BODY_TILE := Vector2i(560, 760)
const HANDS_TILE := Vector2i(560, 560)

var _images := true

func _initialize() -> void:
	_run.call_deferred()

func _facing(rig: TacticalCharacterAdapter) -> Basis:
	return rig.rig.character_root.global_basis.orthonormalized()

func _snap(camera: Camera3D, position_value: Vector3, look_at_value: Vector3, fov: float, tile: Vector2i) -> Image:
	camera.fov = fov
	camera.position = position_value
	camera.look_at(look_at_value)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var size := image.get_size()
	var width := int(size.y * float(tile.x) / tile.y)
	if width <= size.x:
		image = image.get_region(Rect2i((size.x - width) / 2, 0, width, size.y))
	image.resize(tile.x, tile.y, Image.INTERPOLATE_LANCZOS)
	return image

func _sheet(tiles: Array[Image], tile: Vector2i) -> Image:
	var sheet := Image.create(tile.x * tiles.size(), tile.y, false, Image.FORMAT_RGB8)
	for index in tiles.size():
		sheet.blit_rect(tiles[index], Rect2i(Vector2i.ZERO, tile), Vector2i(index * tile.x, 0))
	return sheet

func _apply(rig: TacticalCharacterAdapter, entry: String) -> void:
	var state := entry.split("@")[0].replace("+aim", "")
	rig.presenter.aim.held = entry.ends_with("+aim")
	rig.presenter.aim.release_left = 1000000.0
	if "@" in entry:
		var height_text := entry.split("@")[1].replace("+aim", "")
		if state == "shoot":
			rig.last_cover_contact = {"type": MapCellData.CoverType.NONE, "direction": Vector3.ZERO}
		else:
			var cover_type := MapCellData.CoverType.FULL if state == "cover_high" else MapCellData.CoverType.LOW
			rig.last_cover_contact = {"type": cover_type, "height": float(height_text), "direction": Vector3.FORWARD}
	else:
		rig.last_cover_contact = {"type": MapCellData.CoverType.NONE, "direction": Vector3.ZERO}
	rig.rig.animation_controller.play(StringName(state))

func _settle(entry: String) -> void:
	if entry.begins_with("shoot@"):
		await create_timer(float(entry.split("@")[1])).timeout
		return
	for i in 40: await process_frame
	await create_timer(1.6).timeout
	await process_frame

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: -- <directory> <tag> [poses]")
		quit(2)
		return
	var directory: String = args[0]
	var tag: String = args[1]
	var legacy := "legacy" in args
	var poses := (args[2] if args.size() > 2 and args[2] != "legacy" else DEFAULT_POSES).split(",")
	_images = DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute(directory)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.025, 0.035, 0.05)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.58, 0.66, 0.78)
	environment.environment.ambient_light_energy = 0.65
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -28, 0)
	light.light_energy = 1.4
	stage.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, 150, 0)
	fill.light_energy = 0.5
	stage.add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.11, 0.14, 0.18)
	floor_mesh.material_override = floor_material
	stage.add_child(floor_mesh)
	var rig := load("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn").instantiate() as TacticalCharacterAdapter
	stage.add_child(rig)
	rig.position = Vector3.ZERO  # the scene hangs 1 m below the unit centre; stand it on the floor here
	var camera := Camera3D.new()
	camera.near = 0.04
	stage.add_child(camera)
	camera.make_current()
	for i in 20: await process_frame
	var diagnostics := HandContactDiagnostics.attach(rig.rig)
	if diagnostics == null:
		push_error("the rig cannot be measured")
		quit(1)
		return
	# "legacy" in the arguments runs the old target generation (shoulder read before the skeleton's modifiers) for comparison.
	rig.rig.weapon_pose_modifier_enabled = not legacy
	diagnostics.set_readout_visible(false)
	diagnostics.set_enabled(true)
	var baseline := {"godot": Engine.get_version_info().string, "images": _images, "legacy_targets": legacy, "poses": {}, "transitions": {}, "setup_issues": diagnostics.sampler.setup_issues}
	var hand_rest := {}
	for hand in 2:
		hand_rest[HandContactSampler.HAND_NAMES[hand]] = {"arm_length_m": snappedf(float(diagnostics.sampler._hands[hand].chain_length), 0.00001), "rest_palm_vs_down_deg": snappedf(float(diagnostics.sampler._hands[hand].get("rest_palm_vs_down_deg", -1.0)), 0.001)}
	baseline["hands_at_rest"] = hand_rest

	for entry in poses:
		_apply(rig, entry)
		await _settle(entry)
		var measured := diagnostics.latest
		var record := HandContactSampler.scalars(measured)
		baseline.poses[entry] = record
		print("HANDCONTACT ", entry, " ", diagnostics.format_readout(measured).split("\n")[1], " | ", diagnostics.format_readout(measured).split("\n")[2])
		if not _images:
			continue
		var facing := _facing(rig)
		var base := Vector3(0, 0.82, 0)
		var body: Array[Image] = []
		diagnostics.set_labels_visible(false)
		body.append(await _snap(camera, base + facing * Vector3(-1.4, 0.55, 2.4), base, 30.0, BODY_TILE))
		body.append(await _snap(camera, base + facing * Vector3(2.6, 0.2, 0.2), base, 30.0, BODY_TILE))
		_sheet(body, BODY_TILE).save_png(directory.path_join("%s-%s-body.png" % [tag, entry.replace("@", "_").replace("+", "_")]))
		diagnostics.set_labels_visible(true)
		var firing: Vector3 = rig.rig.weapon.to_global(rig.rig.handling.firing_grip)
		var support: Vector3 = rig.rig.weapon.to_global(rig.rig.handling.support_grip)
		var hands: Array[Image] = []
		hands.append(await _snap(camera, firing + facing * Vector3(-0.50, 0.14, 0.34), firing, 26.0, HANDS_TILE))
		hands.append(await _snap(camera, support + facing * Vector3(0.50, 0.14, 0.34), support, 26.0, HANDS_TILE))
		var middle := (firing + support) * 0.5
		hands.append(await _snap(camera, middle + facing * Vector3(-0.85, 0.30, 0.75), middle, 30.0, HANDS_TILE))
		_sheet(hands, HANDS_TILE).save_png(directory.path_join("%s-%s-hands.png" % [tag, entry.replace("@", "_").replace("+", "_")]))

	# Transitions: settle in the first pose, mark the contact there, change pose and record every frame.
	for pair in TRANSITIONS:
		_apply(rig, pair[0])
		await _settle(pair[0])
		diagnostics.mark_reference()
		diagnostics.start_recording()
		_apply(rig, pair[1])
		var window := 0.45 if String(pair[1]).begins_with("shoot") else 1.4
		var elapsed := 0.0
		while elapsed < window:
			var before := Time.get_ticks_msec()
			await process_frame
			elapsed += float(Time.get_ticks_msec() - before) / 1000.0
		var summary := diagnostics.stop_recording()
		baseline.transitions["%s > %s" % [pair[0], pair[1]]] = summary
		print("HANDCONTACT transition ", pair[0], " > ", pair[1], " frames ", summary.frames, " support palm shift max ", summary.support.palm_displacement_mm_max, " mm, dominant ", summary.dominant.palm_displacement_mm_max, " mm, min support margin ", summary.support.reach_margin_mm_min, " mm")
	var file := FileAccess.open(directory.path_join("%s-baseline.json" % tag), FileAccess.WRITE)
	file.store_string(JSON.stringify(baseline, "\t"))
	file.close()
	print("HANDCONTACT saved ", directory)
	quit(0)

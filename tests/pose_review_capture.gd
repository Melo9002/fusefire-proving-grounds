extends SceneTree
## Rendered pose review (explicit-only; needs a display). One sheet per state with fixed views:
## front, side, back, three-quarter, and the view from the eye along the sight line.
##   godot_console --path . --script res://tests/pose_review_capture.gd -- <directory> <tag> [state,state,...]
## Fixed cameras make before/after comparisons honest. Output: <directory>/<tag>-<state>.png
## A state may carry a low-cover height and an aim flag: cover_low@0.9 (hiding), cover_low@0.9+aim.
const DEFAULT_STATES := "rifle_idle,aim,shoot,cover_low,cover_high"
const TILE := Vector2i(320, 440)

func _initialize() -> void:
	_run.call_deferred()

func _snap(camera: Camera3D, position_value: Vector3, look_at_value: Vector3, crop := true) -> Image:
	camera.position = position_value
	camera.look_at(look_at_value)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var size := image.get_size()
	if crop:
		# The figure is centred; keep a tall central crop so the tiles line up.
		var width := int(size.y * float(TILE.x) / TILE.y)
		image = image.get_region(Rect2i((size.x - width) / 2, 0, width, size.y))
	image.resize(TILE.x, TILE.y, Image.INTERPOLATE_LANCZOS)
	return image

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var directory: String = args[0]
	var tag: String = args[1]
	var states := (args[2] if args.size() > 2 else DEFAULT_STATES).split(",")
	var stage := Node3D.new()
	root.add_child(stage)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	stage.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, 150, 0)
	fill.light_energy = 0.5
	stage.add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(10, 10)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.45, 0.47, 0.5)
	floor_mesh.material_override = floor_material
	stage.add_child(floor_mesh)
	var rig := load("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn").instantiate() as UnitVisualAdapter
	stage.add_child(rig)
	rig.position = Vector3.ZERO  # the scene hangs 1 m below the unit centre; stand it on the floor here
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.make_current()
	var head_attachment := BoneAttachment3D.new()
	head_attachment.bone_name = &"mixamorig_Head"
	rig.skeleton.add_child(head_attachment)
	var top_attachment := BoneAttachment3D.new()
	top_attachment.bone_name = &"mixamorig_HeadTop_End"
	rig.skeleton.add_child(top_attachment)
	for i in 20: await process_frame
	DirAccess.make_dir_recursive_absolute(directory)
	var look := Vector3(0, 0.9, 0)
	for entry in states:
		var state := entry.split("@")[0]
		rig._aim_held = entry.ends_with("+aim")
		rig._aim_release_left = 1000000.0
		if "@" in entry:
			var cover_height := float(entry.split("@")[1].split("+")[0])
			rig.last_cover_contact = {"type": MapCellData.CoverType.LOW, "height": cover_height, "direction": Vector3.FORWARD}
		else:
			rig.last_cover_contact = {"type": MapCellData.CoverType.NONE, "direction": Vector3.ZERO}
		rig.animation_controller.play(StringName(state))
		rig._retarget_aim_blend()
		for i in 40: await process_frame
		await create_timer(1.6).timeout
		var tiles: Array[Image] = []
		tiles.append(await _snap(camera, Vector3(0, 1.1, 2.7), look))       # front
		tiles.append(await _snap(camera, Vector3(2.7, 1.1, 0), look))       # side (character's left)
		tiles.append(await _snap(camera, Vector3(0, 1.1, -2.7), look))      # back
		tiles.append(await _snap(camera, Vector3(1.9, 1.35, 1.9), look))    # three-quarter
		# From the eye along the sight line: does the character see through the sights?
		var forward := rig.weapon.global_basis.z.normalized()
		var eye := head_attachment.global_position + (top_attachment.global_position - head_attachment.global_position) * 0.55 + rig.character_root.global_basis.z * 0.085
		camera.fov = 50.0
		tiles.append(await _snap(camera, eye, eye + forward, false))
		camera.fov = 75.0
		var sheet := Image.create(TILE.x * tiles.size(), TILE.y, false, Image.FORMAT_RGB8)
		for index in tiles.size():
			sheet.blit_rect(tiles[index], Rect2i(Vector2i.ZERO, TILE), Vector2i(index * TILE.x, 0))
		sheet.save_png(directory.path_join("%s-%s.png" % [tag, entry.replace("@", "_").replace("+", "_")]))
		print("REVIEW saved ", entry)
	quit(0)

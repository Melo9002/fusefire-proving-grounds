extends SceneTree
## Rendered evidence for the hit reaction and the defeat (Task 07 final closeout; explicit-only, needs a display):
##   godot_console --path . --script res://tests/hit_defeat_capture.gd -- <directory>
## The production visual through present_hit() (tiles at fixed frames inside the 0.58 s reaction, side then front) and present_defeat() (the whole body, side and three-quarter, from standing to lying). Output: <directory>/hit-defeat-sheet.png
const TILE := Vector2i(300, 420)
var _tiles: Array[Image] = []

func _initialize() -> void:
	_run.call_deferred()

func _snap(camera: Camera3D, position_value: Vector3, look_at_value: Vector3) -> void:
	camera.position = position_value
	camera.look_at(look_at_value)
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var size := image.get_size()
	var width := int(size.y * float(TILE.x) / TILE.y)
	image = image.get_region(Rect2i((size.x - width) / 2, 0, width, size.y))
	image.resize(TILE.x, TILE.y, Image.INTERPOLATE_LANCZOS)
	image.convert(Image.FORMAT_RGBA8)
	_tiles.append(image)

func _character(stage: Node3D) -> TacticalCharacterAdapter:
	var v := load("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn").instantiate() as TacticalCharacterAdapter
	stage.add_child(v)
	v.position = Vector3.ZERO
	return v

func _run() -> void:
	var directory: String = OS.get_cmdline_user_args()[0]
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
	plane.size = Vector2(12, 12)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.45, 0.47, 0.5)
	floor_mesh.material_override = floor_material
	stage.add_child(floor_mesh)
	var camera := Camera3D.new()
	camera.fov = 55.0
	stage.add_child(camera)
	camera.make_current()
	var look := Vector3(0, 0.8, 0)
	var side := Vector3(3.0, 1.0, 0)
	var front := Vector3(0, 1.0, 3.0)
	
	# Hit: a reaction at frames 4, 12, 22 and 34 (about 0.07, 0.2, 0.37 and 0.57 s), then the recovery.
	var hit := _character(stage)
	for i in 40:
		await process_frame
	var upper := Vector3(2.0, 1.25, 1.2)   # closer, upper body: the reaction is a chest and head twist
	var upper_look := Vector3(0, 1.1, 0)
	await _snap(camera, upper, upper_look)   # idle reference, just before the hit
	hit.present_hit()
	var frame := 0
	for target in [7, 12, 20, 34]:   # about 0.12 s (the chest's peak), 0.2, 0.33 and 0.57 s
		while frame < target:
			await process_frame
			frame += 1
		await _snap(camera, upper, upper_look)
	print("hit state while shown: %s" % hit.get_presentation_state())
	hit.queue_free()
	await process_frame

	# Defeat: the whole body from standing to lying, wide framing.
	var down := _character(stage)
	for i in 40:
		await process_frame
	down.present_defeat()
	frame = 0
	var wide := Vector3(0.7, 1.5, 5.8)         # the body falls toward +X: frame the whole fall and the lying body
	var wide_look := Vector3(0.7, 0.35, 0)
	for target in [12, 30, 55, 90, 140]:
		while frame < target:
			await process_frame
			frame += 1
		await _snap(camera, wide, wide_look)
	await _snap(camera, Vector3(0.7, 5.5, 0.6), Vector3(0.7, 0, 0))   # from above, the whole lying body
	print("defeat state: %s" % down.get_presentation_state())

	var columns := 6
	var rows := ceili(float(_tiles.size()) / columns)
	var sheet := Image.create(TILE.x * columns, TILE.y * rows, false, Image.FORMAT_RGBA8)
	for index in _tiles.size():
		sheet.blit_rect(_tiles[index], Rect2i(Vector2i.ZERO, TILE), Vector2i((index % columns) * TILE.x, (index / columns) * TILE.y))
	DirAccess.make_dir_recursive_absolute(directory)
	sheet.save_png(directory + "/hit-defeat-sheet.png")
	print("hit_defeat_capture: %d tiles written to %s/hit-defeat-sheet.png (hit upper body: idle reference, then 7, 12, 20, 34 frames; defeat wide at 12, 30, 55, 90, 140 frames and from above)" % [_tiles.size(), directory])
	quit(0)

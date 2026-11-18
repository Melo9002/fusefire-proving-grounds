extends SceneTree
## Rendered close-up of the weapon in the aim pose from the side and from above, with small markers
## on the support-hand target (green), the sight (blue) and the muzzle (red). Explicit-only; needs a display.
##   godot_console --path . --script res://tests/weapon_closeup_capture.gd -- <output.png>
const TILE := Vector2i(640, 440)

func _initialize() -> void:
	_run.call_deferred()

func _marker(parent: Node3D, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.012
	sphere.height = 0.024
	mesh.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	stage.add_child(light)
	var rig := load("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn").instantiate() as UnitVisualAdapter
	stage.add_child(rig)
	rig.position = Vector3.ZERO
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.make_current()
	for i in 20: await process_frame
	_marker(rig.support_hand_target, Color(0.1, 1.0, 0.2))
	_marker(rig.sight_marker, Color(0.2, 0.4, 1.0))
	_marker(rig.muzzle_socket, Color(1.0, 0.2, 0.2))
	rig.animation_controller.play(&"aim")
	rig._aim_held = true
	rig._aim_release_left = 1000000.0
	rig._retarget_aim_blend()
	for i in 60: await process_frame
	await create_timer(1.0).timeout
	# Distance from the support palm to the middle of the front handle (weapon frame, from the mesh profile).
	var hand := BoneAttachment3D.new()
	hand.bone_name = &"mixamorig_LeftHand"
	rig.skeleton.add_child(hand)
	await process_frame
	await process_frame
	var handle: Vector3 = rig.weapon.to_global(Vector3(0.01, -0.03, 0.19))
	var offset: Vector3 = rig.weapon.global_transform.affine_inverse() * hand.global_position - Vector3(0.01, -0.03, 0.19)
	print("HANDLE hand to handle %.3f m  (weapon frame offset x %.3f y %.3f z %.3f)" % [hand.global_position.distance_to(handle), offset.x, offset.y, offset.z])
	var center: Vector3 = rig.weapon.global_position + rig.weapon.global_basis.z * 0.1
	var right: Vector3 = rig.weapon.global_basis.x
	var up: Vector3 = rig.weapon.global_basis.y
	var views := [center + right * 0.9, center - right * 0.9, center + up * 0.9 + rig.weapon.global_basis.z * 0.01]
	var tiles: Array[Image] = []
	for view in views:
		camera.position = view
		camera.look_at(center, up if view != views[2] else rig.weapon.global_basis.z)
		for i in 3: await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.resize(TILE.x, TILE.y, Image.INTERPOLATE_LANCZOS)
		tiles.append(image)
	var sheet := Image.create(TILE.x * tiles.size(), TILE.y, false, Image.FORMAT_RGB8)
	for index in tiles.size():
		sheet.blit_rect(tiles[index], Rect2i(Vector2i.ZERO, TILE), Vector2i(index * TILE.x, 0))
	var args := OS.get_cmdline_user_args()
	sheet.save_png(args[0])
	print("CLOSEUP saved")
	quit(0)

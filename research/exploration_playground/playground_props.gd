class_name PlaygroundProps
extends RefCounted
## The sandbox's fixtures for trying the character's actions (a proof of concept, not a level): cover walls, a staircase and a ramp up to platforms, a ladder up a tower, a body to carry, a hazard plate, and spots for the
## target dummies. The geometry is simple boxes; the poses on stairs and ladders come from the shared presentation code (StairModel, TraversalSolver, the rig's traversal), not from these shapes. The tactical test map is
## a grid parcel of CSG boxes and tactical links, not a level a physics body can walk, so equivalent fixtures are built here.

const COVER_GROUP := &"exploration_cover"
## The station signs, so a clean inspection view can hide them with the HUD.
const SIGN_GROUP := &"exploration_signs"
const HAZARD_GROUP := &"exploration_hazard"
const STAIR_STEPS := 10
const STAIR_RISE := 0.2
const STAIR_DEPTH := 0.4
const STAIR_WIDTH := 1.6
const LADDER_LENGTH := 3.0


## Builds the fixtures under `world` using the controller's primitive helpers and returns what the action components need.
static func build(world: Node3D, ctx: Node) -> Dictionary:
	var info := {}
	# Cover walls. The existing large wall is one (low); the others are a low and a high one. A wall's cover height is its top; "full" cover is higher than a crouch can hide behind.
	ctx._box(Vector3(3.0, 1.2, 0.4), Vector3(-8.0, 0.6, 2.0), Color(0.55, 0.6, 0.55), "LowCover")
	ctx._box(Vector3(3.0, 1.8, 0.4), Vector3(7.0, 0.9, 3.0), Color(0.5, 0.52, 0.62), "HighCover")
	for wall_name in ["Wall", "LowCover", "HighCover"]:
		var wall := ctx.get_node_or_null(wall_name) as StaticBody3D
		if wall != null:
			wall.add_to_group(COVER_GROUP)
	# A deck reached by stairs (kinematic height on the stairs: the treads have no colliders, the deck has).
	ctx._box(Vector3(6.0, 2.0, 5.0), Vector3(-12.0, 1.0, 12.0), Color(0.45, 0.47, 0.5), "StairDeck")
	var stairs := StairModel.new()
	stairs.low = Vector3(-12.0, 0.0, 5.5)
	stairs.direction = Vector3.BACK
	stairs.tread_depth = STAIR_DEPTH
	stairs.tread_rise = STAIR_RISE
	stairs.first_riser = 0.0
	stairs.count = STAIR_STEPS
	stairs.width = STAIR_WIDTH
	var tread_material := StandardMaterial3D.new()
	tread_material.albedo_color = Color(0.6, 0.56, 0.5)
	var treads := Node3D.new()
	treads.name = "StairTreads"
	world.add_child(treads)
	for k in range(1, STAIR_STEPS + 1):
		# Each tread is a solid box (nobody walks through the side of a staircase); while she is ON the stairs the treads carry her instead (see PlaygroundTraversal), so they are ignored then.
		var top := stairs.tread_top(k)
		var size := Vector3(STAIR_WIDTH, top, STAIR_DEPTH)
		var tread := StaticBody3D.new()
		tread.name = "Tread%d" % k
		tread.position = Vector3(stairs.low.x, top * 0.5, stairs.low.z + stairs.riser_s(k) + STAIR_DEPTH * 0.5)
		var mesh_instance := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh_instance.mesh = mesh
		mesh_instance.material_override = tread_material
		tread.add_child(mesh_instance)
		var collider := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		collider.shape = box
		tread.add_child(collider)
		treads.add_child(tread)
	info["stairs"] = stairs
	# A ramp (a real collider the body walks up) to a low platform.
	var angle := atan2(1.5, 6.0)
	var ramp: StaticBody3D = ctx._box(Vector3(6.2, 0.2, 3.0), Vector3(11.0, 0.75 - 0.1 * cos(angle), 8.0), Color(0.58, 0.5, 0.42), "Ramp")
	ramp.rotation.z = angle
	ctx._box(Vector3(4.0, 1.5, 3.0), Vector3(16.0, 0.75, 8.0), Color(0.45, 0.47, 0.5), "RampPlatform")
	# A tower with a ladder on its near face.
	var tower_size := Vector3(3.0, LADDER_LENGTH, 3.0)
	# The rungs stand 0.22 m clear of the tower face (a boot reaches 0.17 to 0.19 m ahead of the ankle, so a ladder hard against a wall cannot be stood on).
	var tower_center := Vector3(0.0, LADDER_LENGTH * 0.5, 17.14)
	ctx._box(tower_size, tower_center, Color(0.45, 0.47, 0.5), "LadderTower")
	var deck_edge := tower_center.z - tower_size.z * 0.5
	# The ladder's own rails run on above the deck: the ending of the ladder, and the handholds a climber takes to cross the lip. Real geometry at the rail span and the rung plane;
	# the landing is described from the SAME numbers.
	var rail_extension := 0.9
	var rail_color := Color(0.87, 0.71, 0.3)
	var ladder_geometry := LadderGeometry.for_rise(LADDER_LENGTH)
	for side in [-1.0, 1.0]:
		ctx._box(Vector3(ladder_geometry.rail_radius * 2.0, rail_extension, ladder_geometry.rail_radius * 2.0), Vector3(tower_center.x + side * ladder_geometry.rail_half_span(), LADDER_LENGTH + rail_extension * 0.5, 15.42), rail_color, "LadderRailExtension")
	info["ladder"] = {"x": tower_center.x, "z": 15.42, "length": LADDER_LENGTH, "deck_edge": deck_edge, "top_z": deck_edge + 0.70,
		"landing": LadderLanding.with_extended_rails(ladder_geometry, deck_edge - 15.42, tower_size.x * 0.5, tower_size.z, rail_extension, "sandbox ladder rails run on")}
	var rung_material := StandardMaterial3D.new()
	rung_material.albedo_color = Color(0.87, 0.71, 0.3)
	# The shared ladder layout (LadderGeometry), drawn in the frame of the cell the climber stands in: its rung plane is at z 15.42.
	var ladder_node := LadderGeometry.for_rise(LADDER_LENGTH).build_visual(rung_material)
	ladder_node.position = Vector3(0.0, 0.0, 15.42 - LadderGeometry.PLANE_AHEAD)
	world.add_child(ladder_node)
	# Spots: targets, a body to carry, a hazard plate.
	info["target_spots"] = [Vector3(-8.0, 0.0, -9.0), Vector3(0.0, 0.0, -12.0)]
	# The casualty station: both default casualties lie here from the start, three metres apart, with open floor around them. Data, so another body is one more entry.
	info["casualty_specs"] = [
		{"id": &"casualty_mira", "character": &"mira_0", "position": Vector3(6.5, 0.0, -6.5), "yaw": 0.0},
		{"id": &"casualty_small_mira", "character": &"small_mira_0", "position": Vector3(9.5, 0.0, -6.5), "yaw": 0.0},
	]
	info["extra_spot"] = Vector3(8.0, 0.0, -9.5)
	var plate := Area3D.new()
	plate.name = "HazardPlate"
	plate.position = Vector3(14.0, 0.05, -12.0)
	var plate_shape := CollisionShape3D.new()
	var plate_box := BoxShape3D.new()
	plate_box.size = Vector3(3.0, 0.4, 3.0)
	plate_shape.shape = plate_box
	plate.add_child(plate_shape)
	var plate_mesh := MeshInstance3D.new()
	var plate_quad := BoxMesh.new()
	plate_quad.size = Vector3(3.0, 0.04, 3.0)
	plate_mesh.mesh = plate_quad
	plate_mesh.material_override = ctx._material(Color(0.85, 0.15, 0.15), true)
	plate.add_child(plate_mesh)
	plate.add_to_group(HAZARD_GROUP)
	world.add_child(plate)
	_station_signs(world, ctx)
	return info


## Floor pad and signs that say what each part of the yard is for. Visual only (no colliders): the pad is a thin plate, the signs are billboards above head height.
static func _station_signs(world: Node3D, ctx: Node) -> void:
	var pad_mesh := BoxMesh.new()
	pad_mesh.size = Vector3(8.0, 0.012, 5.0)
	var pad := MeshInstance3D.new()
	pad.name = "CasualtyStationPad"
	pad.mesh = pad_mesh
	pad.material_override = ctx._material(Color(0.78, 0.25, 0.22))
	pad.position = Vector3(8.0, 0.006, -6.5)
	world.add_child(pad)
	for sign in [
		["CASUALTY STATION\ncarry either body; E to pick up and put down", Vector3(8.0, 2.6, -9.2)],
		["STAIRS", Vector3(-12.0, 2.8, 3.5)],
		["RAMP", Vector3(11.0, 2.6, 5.0)],
		["LADDER\nwalk at the rungs to climb", Vector3(0.0, 4.2, 13.4)],
		["COVER AND TARGETS", Vector3(-8.0, 2.4, 0.5)],
		["HAZARD PLATE", Vector3(14.0, 2.0, -12.0)],
		["START", Vector3(0.0, 2.2, 1.5)],
	]:
		var label := Label3D.new()
		label.name = "StationSign"
		label.text = String(sign[0]).replace("\\n", "\n")
		label.position = sign[1]
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 48
		label.pixel_size = 0.008
		label.outline_size = 12
		label.modulate = Color(1.0, 0.95, 0.75)
		label.no_depth_test = false
		label.add_to_group(SIGN_GROUP)
		world.add_child(label)

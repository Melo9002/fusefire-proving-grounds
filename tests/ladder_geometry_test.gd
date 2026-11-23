extends SceneTree
## Issue #55: the ladder has ONE geometry. LadderGeometry is the definition the solver, the sandbox, the workbench and the tests use; the authored components must BE that definition (a drawn ladder whose rungs are
## elsewhere than the poses assume is the defect), and no authored parcel may stretch a ladder mesh (a stretched mesh changes the pitch the climbers were planned for).
const COMPONENTS := {
	"res://art/environments/authored/components/maintenance_ladder_4m.tscn": 4.0,
	"res://art/environments/authored/components/maintenance_ladder_3m.tscn": 3.0,
}
const PARCEL_DIRS := ["res://art/environments/authored/components", "res://art/environments/authored/parcels"]
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	# ---- The definition itself.
	var g4 := LadderGeometry.for_rise(4.0)
	var g3 := LadderGeometry.for_rise(3.0)
	check(g4.rung_count() == 15 and g3.rung_count() == 11, "4 m has 15 rungs and 3 m has 11 (%d, %d)" % [g4.rung_count(), g3.rung_count()])
	check(is_equal_approx(g4.rung_height(0), LadderGeometry.FIRST_RUNG) and is_equal_approx(g4.rung_height(5) - g4.rung_height(4), LadderGeometry.SPACING), "The first rung and the pitch are the geometry's constants")
	check(g4.rung_height(g4.rung_count() - 1) <= 4.0 - LadderGeometry.TOP_MARGIN + 0.0001 and g4.rung_height(g4.rung_count()) > 4.0 - LadderGeometry.TOP_MARGIN, "The top rung leaves the deck's margin and no further rung fits")
	check(is_equal_approx(g4.clear_width(), 0.64), "The clear width between the rails is 0.64 m")

	# ---- The volume test the clearance measurements stand on: it must see a limb through a rung and a limb clear of the ladder (a measurement that cannot fail proves nothing).
	var rung_y := g4.rung_height(4)
	var through := g4.penetration(Vector3(0.0, rung_y - 0.2, g4.plane_ahead), Vector3(0.0, rung_y + 0.2, g4.plane_ahead), 0.06, 0.0)
	check(through > 0.05, "A leg volume across a rung is reported as inside it (%.3f m)" % through)
	var crossing := g4.penetration(Vector3(0.0, rung_y + 0.08, g4.plane_ahead - 0.3), Vector3(0.0, rung_y + 0.08, g4.plane_ahead + 0.3), 0.04, 0.0)
	check(crossing <= 0.0, "A thin limb passing through the gap above a rung is clear (%.3f m)" % crossing)
	var behind := g4.penetration(Vector3(0.0, rung_y, g4.plane_ahead - 0.3), Vector3(0.0, rung_y + 0.4, g4.plane_ahead - 0.3), 0.07, 0.0)
	check(behind < -0.1, "A knee well behind the plane is clear by its gap (%.3f m)" % behind)
	var rail := g4.penetration(Vector3(g4.rail_half_span(), 1.0, g4.plane_ahead), Vector3(g4.rail_half_span(), 1.3, g4.plane_ahead), 0.05, 0.0)
	check(rail > 0.05, "A limb on a rail is inside it (%.3f m)" % rail)
	var shifted := g4.penetration(Vector3(0.0, rung_y - 0.3, g4.plane_ahead), Vector3(0.0, rung_y - 0.1, g4.plane_ahead), 0.06, 0.3)
	check(shifted > 0.05, "The floor level shifts the volume: the same pose 0.3 m up the ladder meets the same rung (%.3f m)" % shifted)

	# ---- The authored components ARE the definition.
	for path in COMPONENTS:
		var rise: float = COMPONENTS[path]
		var geometry := LadderGeometry.for_rise(rise)
		var scene: PackedScene = load(path)
		var node: Node3D = scene.instantiate()
		var rung_heights: Array[float] = []
		var rail_x: Array[float] = []
		var rail_len := 0.0
		for child in node.get_children():
			var mesh_node := child as MeshInstance3D
			if mesh_node == null:
				continue
			var box := mesh_node.mesh as BoxMesh
			if child.name.begins_with("Rung"):
				rung_heights.append(mesh_node.position.y)
				check(is_equal_approx(box.size.x * 0.5, LadderGeometry.RUNG_HALF_LENGTH) and is_equal_approx(box.size.y * 0.5, geometry.rung_radius), "%s: %s has the geometry's rung size" % [path.get_file(), child.name])
			elif child.name.begins_with("Side"):
				rail_x.append(mesh_node.position.x)
				rail_len = box.size.y
				check(is_equal_approx(box.size.x * 0.5, geometry.rail_radius) and is_equal_approx(mesh_node.position.y, rise * 0.5), "%s: %s has the geometry's rail size and is centred on the rise" % [path.get_file(), child.name])
		rung_heights.sort()
		var heights_match := rung_heights.size() == geometry.rung_count()
		for index in mini(rung_heights.size(), geometry.rung_count()):
			heights_match = heights_match and is_equal_approx(rung_heights[index], geometry.rung_height(index))
		check(heights_match, "%s: its %d rungs are exactly the geometry's rungs (%d expected)" % [path.get_file(), rung_heights.size(), geometry.rung_count()])
		rail_x.sort()
		check(rail_x.size() == 2 and is_equal_approx(rail_x[0], -geometry.rail_half_span()) and is_equal_approx(rail_x[1], geometry.rail_half_span()) and is_equal_approx(rail_len, rise), "%s: its rails stand at the geometry's width and are as long as the rise" % path.get_file())
		node.free()

	# ---- No authored scene stretches a ladder: a ladder instance is at scale 1. (The check is run on a synthetic stretched instance too, so it is known to be able to fail.)
	var stretched := Node3D.new()
	var packed: PackedScene = load("res://art/environments/authored/components/maintenance_ladder_4m.tscn")
	var instance: Node3D = packed.instantiate()
	instance.scale = Vector3(1.0, 0.75, 1.0)
	stretched.add_child(instance)
	check(_stretched_ladders(stretched) == 1, "The scale scan finds a ladder stretched to 0.75 (control)")
	stretched.free()
	var scanned := 0
	var bad: Array[String] = []
	for dir_path in PARCEL_DIRS:
		for file in DirAccess.get_files_at(dir_path):
			if not file.ends_with(".tscn"):
				continue
			var root_node: Node = (load("%s/%s" % [dir_path, file]) as PackedScene).instantiate()
			scanned += 1
			var found := _stretched_ladders(root_node)
			if found > 0:
				bad.append(file)
			root_node.free()
	check(scanned > 5 and bad.is_empty(), "No authored component or parcel stretches a ladder (%d scenes scanned; stretched in: %s)" % [scanned, bad])

	print("ladder_geometry_test: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)


## How many ladder instances under `node` are not at scale 1 (their meshes would no longer be the geometry's).
func _stretched_ladders(node: Node) -> int:
	var count := 0
	if node is Node3D and (node as Node3D).scene_file_path.contains("maintenance_ladder") and not (node as Node3D).scale.is_equal_approx(Vector3.ONE):
		count += 1
	for child in node.get_children():
		count += _stretched_ladders(child)
	return count

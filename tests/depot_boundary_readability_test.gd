extends SceneTree
## Edge cues must clarify the limit without occupying playable cells or closing roads.
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	for site in BattlefieldCatalog.PLAYABLE:
		for map_seed in [16, 17]:
			var data := BattlefieldCatalog.generate(site, Vector2i.ZERO, map_seed, 1.0)
			var host := Node3D.new()
			root.add_child(host)
			var presented := BattlefieldCatalog.present(data, host, 1.0)
			check(presented, "Boundary review presents a valid current-site layout")
			if not presented:
				host.free()
				continue
			var plot := host.get_child(0)
			var cues := plot.get_node_or_null("Peripheral/BoundaryCues") as Node3D
			check(cues != null, "Current site has physical edge cues and open-road labels")
			if cues == null:
				host.free()
				continue
			var playable := AABB(Vector3(-20, -10, -20), Vector3(40, 30, 40))
			var vertical: bool = site == BattlefieldCatalog.SERVICE_DEPOT and map_seed == 17
			var road_z := -17.5 if site == BattlefieldCatalog.FLEET_STATION and map_seed == 16 else (15.5 if site == BattlefieldCatalog.FLEET_STATION else 14.5)
			var road := AABB(Vector3(-20, -1, -26), Vector3(5, 10, 52)) if vertical else AABB(Vector3(-26, -1, road_z - 2.5), Vector3(52, 10, 5))
			for mesh: MeshInstance3D in cues.find_children("*", "MeshInstance3D", true, false):
				var bounds := mesh.global_transform * mesh.get_aabb()
				check(not bounds.intersects(playable), "Physical cue stays outside playable cells: " + String(mesh.get_path()))
				check(not bounds.intersects(road), "Continuing road and its approaches stay physically open: " + String(mesh.get_path()))
			var corners := cues.get_node("Corners")
			check(corners.get_child_count() == 4, "All four corners have a physical cue")
			for marker: Node3D in corners.get_children():
				check(absf(marker.position.x) > 20 and absf(marker.position.z) > 20, "Corner cues identify the outside of the tactical rectangle")
			var labels := cues.get_node("OpenRoadLabels").get_children()
			check(labels.size() == 2, "Both open road crossings explain their limit")
			for label: Label3D in labels:
				check(label.text == "BATTLE\nLIMIT", "Boundary explanation does not rely on color alone")
				check(absf(label.position.x) > 20 if not vertical else absf(label.position.z) > 20, "Road labels sit on the out-of-bounds side")
			check(cues.find_children("*", "PhysicsBody3D", true, false).is_empty() and cues.find_children("*", "NavigationRegion3D", true, false).is_empty(), "Scenery cues introduce no gameplay collision or navigation")
			var boundary := plot.get_node("Tactical/PlayableBoundary")
			check(boundary.visible and boundary.get_meta("tactical_size") == data.map_size, "Exact dashed limit stays visible alongside physical cues")
			check(data.cells.size() == 1600, "Edge cues do not enlarge the playable map")
			host.free()
	print("Current-site boundary readability: %d failure(s)" % failures)
	quit(1 if failures else 0)

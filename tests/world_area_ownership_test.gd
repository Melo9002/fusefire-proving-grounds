extends SceneTree
## Scene ownership is presentation only; grid authority and accepted choices stay unchanged.
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	for id in BattlefieldCatalog.PLAYABLE:
		for map_seed in [16, 17]:
			for unit in [1.0, 2.0]:
				# Tactical authoring currently uses unit tiles; exercise presentation
				# scale independently without asserting a new compiler-scale contract.
				var data := BattlefieldCatalog.generate(id, Vector2i.ZERO, map_seed, 1.0)
				var manifest := data.content_manifest.duplicate(true)
				var host := Node3D.new()
				root.add_child(host)
				var presented := BattlefieldCatalog.present(data, host, unit)
				check(presented, "Current site presents: %s/%d/%s" % [id, map_seed, unit])
				if not presented or host.get_child_count() == 0:
					host.free()
					continue
				var plot := host.get_child(0) as Node3D
				for area in ["Tactical", "Peripheral", "Distant"]:
					check(plot.get_node_or_null(area) is Node3D, "%s has an editable %s group" % [plot.name, area])
				var tactical := plot.get_node_or_null("Tactical") as Node3D
				if tactical:
					for placement: Dictionary in manifest.placements:
						var instances := tactical.get_children().filter(func(node): return node.get_meta("parcel_id", &"") == placement.parcel_id)
						check(instances.size() == 1, "Accepted parcel is owned by Tactical")
						if instances.size() == 1:
							var expected := ParcelTransform.scene_transform(instances[0].get_meta("parcel_size"), placement.origin, placement.rotation, data.map_size, unit)
							check(instances[0].global_transform.is_equal_approx(expected), "Grouping preserves parcel position, rotation and cell scale")
				for area in ["Peripheral", "Distant"]:
					var scenery := plot.get_node_or_null(area) as Node3D
					if not scenery: continue
					check(scenery.is_in_group("peripheral_scenery" if area == "Peripheral" else "distant_scenery"), "Scenery ownership is explicit")
					check(scenery.find_children("*", "PhysicsBody3D", true, false).is_empty(), "Current scenery has no physics body that can catch tactical input")
					scenery.hide()
				check(data.cells.size() == 1600 and data.get_cell(Vector3i(-1, 0, 0)) == null and data.get_cell(Vector3i(40, 0, 0)) == null, "Scenery does not extend the tactical grid")
				var reconstructed := BattlefieldCatalog.generate(id, Vector2i.ZERO, 999, 1.0, manifest)
				check(data.content_manifest == manifest and reconstructed.content_manifest == manifest and reconstructed.generation_errors.is_empty(), "Area organization preserves accepted-content reconstruction")
				host.free()
	await _check_hazard_boundary()
	print("World area ownership: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _check_hazard_boundary() -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.SERVICE_DEPOT)
	config.battle_seed = 16
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	check(level.battle_initialization_succeeded, "A grouped battle initializes")
	var plot := level.get_node("GeneratedTerrain").get_child(0)
	for area in ["Peripheral", "Distant", "Tactical"]:
		var parent := plot.get_node_or_null(area)
		if parent == null: continue
		var marker := TileHazardMarker.new()
		parent.add_child(marker)
		marker.global_position = Vector3(-9.5, 0, 15.5) # Open Depot cell (10, 0, 35).
		level.battle_controller._apply_authored_tile_hazards()
		var cell := level.active_generated_map.get_cell(Vector3i(10, 0, 35))
		check(cell.hazard_condition == (marker.condition if area == "Tactical" else null), "Only Tactical can supply a gameplay hazard: " + area)
		marker.free()
	level.queue_free()
	await process_frame

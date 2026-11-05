extends SceneTree

const Layout = preload("res://systems/generation/urban_family_layout.gd")
const Parcels = preload("res://systems/generation/authored_parcel_catalog.gd")
const Recording = preload("res://systems/replay/battle_replay_recording.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var headings := {}
	var example := {}
	for map_seed in range(0, 32, 2):
		var resolved := Layout.resolve(map_seed)
		var office: Dictionary = resolved.placements[-1]
		for choice: Dictionary in office.population:
			headings[choice.yaw_turns] = true
			check(choice.yaw_turns in [0, 2], "Parking remains aligned forward or reverse")
			if example.is_empty(): example = resolved
		check(resolved == Layout.resolve(map_seed), "Heading choices repeat for identical inputs")
	check(headings.has(0) and headings.has(2), "Fixed seed matrix exercises forward and reverse parking")
	var recording := Recording.new()
	recording.configuration = {"battlefield_id": &"urban_family", "content_manifest": example}
	var json: Variant = JSON.parse_string(JSON.stringify(recording.to_dictionary()))
	var restored := Recording.from_dictionary(json)
	var replay := Layout.generate(999, 1.0, restored.configuration.content_manifest)
	check(replay.generation_errors.is_empty() and replay.content_manifest.placements == example.placements, "Actual replay JSON preserves accepted parking headings with a different supplied seed")
	var parcel = Parcels.get_definition(Parcels.INDUSTRIAL_OFFICE_PARKING_A)
	for turn in 4:
		var forward: Node3D = parcel.instantiate()
		var reverse: Node3D = parcel.instantiate()
		var choice := {"socket_id": &"parking_west", "yaw_turns": 0}
		parcel.apply_population(forward, [choice])
		choice.yaw_turns = 2
		parcel.apply_population(reverse, [choice])
		forward.transform = ParcelTransform.scene_transform(parcel.size, Vector3i.ZERO, turn, Vector2i(32, 32))
		reverse.transform = forward.transform
		root.add_child(forward)
		root.add_child(reverse)
		var a: Node3D = forward.get_node("SedanWest")
		var b: Node3D = reverse.get_node("SedanWest")
		check(a.global_position.is_equal_approx(b.global_position), "rotation %d keeps reversing cars in the same bay" % turn)
		check(a.global_basis.z.dot(b.global_basis.z) < -0.999, "rotation %d physically reverses the real imported car" % turn)
		var basis := b.basis
		parcel.apply_population(reverse, [choice])
		check(b.basis.is_equal_approx(basis), "Applying recorded choices twice does not rotate twice")
		forward.free()
		reverse.free()
	for invalid in [1, 3, -2, 0.5, "reverse"]:
		var broken: Dictionary = example.duplicate(true)
		broken.placements[-1].population[0].yaw_turns = invalid
		check(not Layout.generate(0, 1.0, broken).generation_errors.is_empty(), "Unsupported parking heading %s rejects" % str(invalid))
	var legacy: Dictionary = example.duplicate(true)
	for choice: Dictionary in legacy.placements[-1].population:
		choice.erase("yaw_turns")
	check(Layout.generate(0, 1.0, legacy).generation_errors.is_empty(), "Historical choices without heading retain authored forward placement")
	print("Parking population: %d failure(s)" % failures)
	quit(1 if failures else 0)

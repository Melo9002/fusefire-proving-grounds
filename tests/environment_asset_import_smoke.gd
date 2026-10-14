extends SceneTree

const PACK_ROOTS := [
	"res://art/environments/kenney/city_kit_industrial/models",
	"res://art/environments/kenney/city_kit_roads/models",
	"res://art/environments/kenney/factory_kit/models",
	"res://art/environments/kenney/modular_space_kit/models",
]

var failures := 0
var loaded_models := 0

func _initialize() -> void:
	for pack_root in PACK_ROOTS:
		_check_pack(pack_root)
	print("Environment asset import: %d model(s), %d failure(s)" % [loaded_models, failures])
	quit(1 if failures else 0)

func _check_pack(pack_root: String) -> void:
	var directory := DirAccess.open(pack_root)
	if directory == null:
		_fail("Missing environment pack directory: %s" % pack_root)
		return
	var model_names: Array[String] = []
	for file_name in directory.get_files():
		if file_name.ends_with(".glb"):
			model_names.append(file_name)
	model_names.sort()
	if model_names.is_empty():
		_fail("Environment pack has no GLB models: %s" % pack_root)
		return
	for model_name in model_names:
		var model_path := "%s/%s" % [pack_root, model_name]
		var packed_scene := load(model_path) as PackedScene
		if packed_scene == null:
			_fail("Godot could not load environment model: %s" % model_path)
			continue
		var instance := packed_scene.instantiate()
		if instance == null:
			_fail("Godot could not instantiate environment model: %s" % model_path)
			continue
		loaded_models += 1
		instance.free()

func _fail(message: String) -> void:
	failures += 1
	push_error(message)

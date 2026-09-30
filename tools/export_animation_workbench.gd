extends SceneTree
## Explicit bootstrap only. Refuses to overwrite hand-edited assets.
const DIRECTORY := "res://art/characters/vroid_proof/animations"
const LIBRARY := DIRECTORY + "/prototype_clips.tres"
const SCENE := DIRECTORY + "/animation_workbench.tscn"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if FileAccess.file_exists(LIBRARY) or FileAccess.file_exists(SCENE):
		push_error("Workbench already exists. Edit the saved assets; bootstrap will not overwrite them.")
		quit(1)
		return
	var workbench := Node3D.new()
	workbench.name = "AnimationWorkbench"
	root.add_child(workbench)
	var model := load("res://art/characters/vroid_proof/models/vroid_test_runtime.glb").instantiate() as Node3D
	workbench.add_child(model)
	model.owner = workbench
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var controller = load("res://art/characters/vroid_proof/demo/vroid_vertical_slice_controller.gd").new()
	workbench.add_child(controller)
	controller.setup(skeleton, model)
	var library: AnimationLibrary = controller.animation_player.get_animation_library(&"")
	var error := ResourceSaver.save(library, LIBRARY)
	if error != OK:
		push_error("Cannot save clip library: %s" % error)
		quit(1)
		return
	controller.animation_tree.free()
	controller.animation_player.free()
	controller.free()
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	workbench.add_child(player)
	player.owner = workbench
	player.root_node = player.get_path_to(skeleton)
	player.add_animation_library(&"", load(LIBRARY))
	var scene := PackedScene.new()
	error = scene.pack(workbench)
	if error == OK: error = ResourceSaver.save(scene, SCENE)
	print("Animation workbench export: %s" % error_string(error))
	quit(0 if error == OK else 1)

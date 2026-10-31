extends SceneTree
## Explicit graphics review matrix; fixed seeds declared before execution, never replaced.
const FIXED := [17,42,73,101,211]
const HOLDOUT := [307,419,563,701,887]
class Editor extends "res://tools/map_editor.gd":
	func _ready(): pass
var fixture := preload("res://tests/fixtures/plot_test_library.gd").new()
var report: Array = []
func _initialize(): run.call_deferred()
func run():
	if DisplayServer.get_name() == "headless": push_error("Graphics required"); quit(1); return
	if not fixture.create("res://artifacts/t11-review/library-fixture-"+str(Time.get_ticks_usec())): quit(1); return
	root.size = Vector2i(1280,900)
	var editor := Editor.new(); editor.layout_preset = &"plot_authoring"; root.add_child(editor); editor._build_ui(); editor._update_composer_visibility()
	var failures := 0
	for name in ["through_street_industrial","yard_service_access"]:
		for seed_value in FIXED+HOLDOUT:
			var source: EnvironmentPlotSource = EnvironmentPlotSource.load_file("res://content/plots/"+name+".json").source
			for street in source.data.fixed_streets: street.revision = fixture.revisions[street.chunk_id]
			var result := AuthoredPlotComposer.compose(source,seed_value,fixture.operation())
			var entry := {"plot":name,"seed":seed_value,"set":"fixed" if seed_value in FIXED else "holdout","ok":result.ok,"errors":result.errors,"captures":[]}
			if not result.ok:
				failures += 1; report.append(entry); persist(); continue
			var prefix: String = "res://artifacts/t11-review/"+name+"-"+str(seed_value)
			var saved := MapEditorLayoutStore.save(result.document,prefix+".json",fixture.operation())
			entry["save_error"] = saved
			if not saved.is_empty(): failures += 1
			if is_instance_valid(editor.content): editor.content.free()
			editor.content = Node3D.new(); editor.add_child(editor.content)
			editor.preview_map_size = result.data.map_size; editor.displayed_data = result.data
			editor.plot_authoring.source = source
			editor.plot_authoring.marker(Rect2i(Vector2i.ZERO,result.data.map_size),Color("303a3f"),"",-0.06)
			GeneratedTerrainPresenter.build(result.data,editor.content,1.0)
			editor._frame_camera(); editor.plot_authoring.panel.hide()
			editor.status.text = "T11 %s · seed %d · %s\nSynthetic test registrations; no owner visual approval. Orange markers = 1.8m scale." % [name,seed_value,entry.set]
			for cell in result.data.get_spawn_cells(TacticalUnit.Faction.PLAYER):
				var scale_marker := MeshInstance3D.new(); var capsule := CapsuleMesh.new(); capsule.height = 1.8; capsule.radius = 0.3; scale_marker.mesh = capsule
				scale_marker.position = editor.plot_authoring.offset()+Vector3(cell.x,0.9,cell.z)
				var material := StandardMaterial3D.new(); material.albedo_color = Color.ORANGE; scale_marker.material_override = material; editor.content.add_child(scale_marker)
			for view in ["overhead","oblique","diagnostic"]:
				if view == "overhead": editor._set_camera_view(0.0,1.5)
				else: editor._set_camera_view(0.65,0.8)
				if view == "diagnostic": editor._add_spatial_plan_overlay(editor.content,result.data)
				await create_timer(0.2).timeout; await RenderingServer.frame_post_draw
				var path: String = prefix+"-"+view+".png"
				var error := root.get_texture().get_image().save_png(path)
				if error != OK: failures += 1
				entry.captures.append(path)
			report.append(entry); persist(); print("T11 review ",name," ",seed_value," saved")
	editor.free(); print("T11 matrix failures: ",failures); quit(1 if failures else 0)
func persist(): GenerationJsonStore.write("res://artifacts/t11-review/manifest.json",JSON.stringify(report,"\t"))

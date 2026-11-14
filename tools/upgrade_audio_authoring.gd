extends SceneTree
## One-time, idempotent migration. Attaches typed sound resources without rebuilding levels.
## Run: godot_console --headless --path . --script tools/upgrade_audio_authoring.gd
const Emitter = preload("res://scripts/sound_emitter.gd")
const Palette = preload("res://scripts/sound_palette.gd")
const PALETTE_PATH := "res://resources/audio/default_palette.tres"

func _initialize() -> void:
	_make_palette()
	if OS.get_cmdline_user_args().has("--palette-only"):
		quit(0)
		return
	var total := 0
	for id in ["forest","cistern","freighter","courtyard"]:
		var path: String = "res://scenes/levels/legacy/"+id+".tscn"
		var scene: Node3D = load(path).instantiate()
		var geometry_before := _geometry_signature(scene)
		var count := 0
		for anchor in scene.get_node("Sources").get_children():
			if anchor.get_script() == Emitter:
				count += 1
				continue
			assert(anchor.get_script() == null,"Unexpected custom source script on "+str(anchor.name))
			var values := {}
			for key in anchor.get_meta_list(): values[String(key)] = anchor.get_meta(key)
			var recording := recording_for(String(values.get("clip","")))
			assert(recording != null,"Missing recording for "+str(anchor.name))
			anchor.set_script(Emitter)
			anchor.apply_legacy_configuration(values,recording)
			count += 1
		assert(_geometry_signature(scene) == geometry_before,"Audio migration must preserve geometry")
		var packed := PackedScene.new()
		assert(packed.pack(scene) == OK)
		assert(ResourceSaver.save(packed,path) == OK)
		print("AUDIO AUTHORING ",id,": ",count," sources; geometry preserved")
		total += count
		scene.free()
	print("AUDIO AUTHORING TOTAL ",total)
	quit(0)

static func recording_for(clip: String) -> AudioStream:
	var base := clip if clip.begins_with("res://") else "res://assets/library/"+clip
	for path in [base,base+".ogg",base+".wav",base+".mp3"]:
		if ResourceLoader.exists(path): return load(path) as AudioStream
	return null

func _make_palette() -> void:
	if ResourceLoader.exists(PALETTE_PATH):
		print("Preserved existing editable sound palette")
		return
	DirAccess.open("res://").make_dir_recursive("resources/audio")
	var palette := Palette.new()
	for surface in ["gravel","stone","wood","metal"]:
		var streams: Array[AudioStream] = []
		for index in range(12): streams.append(recording_for(surface+str(index)+".wav"))
		palette.set(surface+"_footsteps",streams)
	for cue in ["punch_swing","punch_stone","punch_wood","punch_metal","jump_takeoff","ui_move","ui_accept","ui_back"]:
		palette.set(cue,recording_for(cue+".wav"))
	assert(ResourceSaver.save(palette,PALETTE_PATH) == OK)
	print("Created Inspector-editable sound palette with 48 footfalls and 8 action/menu cues")

func _geometry_signature(scene: Node3D) -> int:
	var values: Array = []
	for body in scene.get_node("Geometry").get_children():
		values.append([String(body.name),body.transform])
		for child in body.get_children():
			if child is MeshInstance3D:
				values.append([String(child.name),child.transform,child.mesh.get_faces()])
			elif child is CollisionShape3D and child.shape is ConcavePolygonShape3D:
				values.append([String(child.name),child.transform,child.shape.get_faces()])
	return hash(values)

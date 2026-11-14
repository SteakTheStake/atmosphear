extends SceneTree
## Explicit audio-only authoring pass. Does not run at game startup.
## Run after asset preparation/import and any intentional level regeneration.
const Migration = preload("res://tools/upgrade_audio_authoring.gd")

func recording(name: String) -> AudioStream:
	var stream := Migration.recording_for(name)
	assert(stream != null,"Missing curated recording: "+name)
	return stream

func pool(anchor: AtmoSoundEmitter, names: Array) -> void:
	anchor.sound = recording(names[0])
	var variants: Array[AudioStream] = []
	for name in names.slice(1): variants.append(recording(name))
	anchor.sound_variants = variants

func _initialize() -> void:
	var total := 0
	for id in ["forest","cistern","freighter","courtyard"]:
		var path: String = "res://scenes/levels/"+id+".tscn"
		var scene: Node3D = load(path).instantiate()
		var geometry_before := geometry_signature(scene)
		var canopy_index := 0
		var wind_index := 0
		for anchor: AtmoSoundEmitter in scene.get_node("Sources").get_children():
			# Legacy role metadata makes this explicit migration repeatable.
			var role := String(anchor.get_meta("clip",anchor.sound.resource_path.get_file().get_basename()))
			if role == "tree_rustle" or (id=="forest" and String(anchor.name) in ["ClearingOak","WetlandTree"]):
				pool(anchor,["canopy%d.ogg" % (canopy_index%4)])
				canopy_index += 1
				anchor.looped = true
				anchor.gain_db = -5.0 if String(anchor.name).begins_with("TreeRustle") else -7.0
				anchor.reflection_budget = 0
				anchor.audible_range = 17.0
				anchor.near_distance = 2.5
				anchor.pitch_min = .985
				anchor.pitch_max = 1.015
				anchor.gain_variation_db = 1.0
				if String(anchor.name) in ["ClearingOak","WetlandTree"]: anchor.position.y = 4.4
			elif role == "tree_creak":
				pool(anchor,["wood_creak0.wav","wood_creak1.wav","wood_creak2.wav","wood_creak3.wav"])
			elif role == "metal_creak":
				pool(anchor,["metal_creak0.wav","metal_creak1.wav","metal_creak2.wav","metal_creak3.wav"])
			elif role in ["drip0","drip1","drip2"]:
				pool(anchor,[role+".wav","drip3.wav","drip4.wav","drip5.wav","drip6.wav"])
			elif role == "pipe_tick":
				pool(anchor,["pipe_ring0.wav","pipe_ring1.wav","pipe_ring2.wav","pipe_ring3.wav"])
				anchor.interval_min = maxf(anchor.interval_min,14.0)
				anchor.interval_max = maxf(anchor.interval_max,32.0)
			elif id=="forest" and String(anchor.name) in ["CoveBird","WetlandBird"]:
				pool(anchor,["bird7.wav","bird8.wav"])
			elif role == "bird3":
				pool(anchor,["bird3.wav","bird6.wav"])
			elif role == "bird4":
				pool(anchor,["bird4.wav","bird5.wav"])
			elif role in ["courtyard_wind","cistern_air"]:
				var family := "wind_shaft" if id=="cistern" else "wind_open"
				if id=="freighter": pool(anchor,["freighter_vent.ogg"])
				else: pool(anchor,["%s%d.ogg" % [family,wind_index%2]])
				wind_index += 1
			# Keep landmark identities, but remove recordings that imply the wrong activity.
			if id=="cistern" and role=="landmark_air": pool(anchor,["wind_shaft1.ogg"])
			if role=="landmark_fountain": anchor.gain_db = -1.0
			if role=="landmark_water_resonance": anchor.gain_db = -2.0
			if id=="forest" and String(anchor.name)=="HutRoofWind": pool(anchor,["wind_open1.ogg"])
			total += 1
		assert(geometry_signature(scene)==geometry_before,"Curation must preserve level geometry")
		var packed := PackedScene.new()
		assert(packed.pack(scene)==OK)
		assert(ResourceSaver.save(packed,path)==OK)
		print("CURATED ",id,": ",scene.get_node("Sources").get_child_count()," anchors; geometry preserved")
		scene.free()
	var palette: AtmoSoundPalette = load("res://resources/audio/default_palette.tres")
	palette.ui_move = recording("ui_soft_move0.wav")
	palette.ui_move_variants.assign([recording("ui_soft_move1.wav"),recording("ui_soft_move2.wav")])
	palette.ui_accept = recording("ui_soft_accept.wav")
	palette.ui_back = recording("ui_soft_back.wav")
	palette.ui_accept_variants = []
	palette.ui_back_variants = []
	assert(ResourceSaver.save(palette,"res://resources/audio/default_palette.tres")==OK)
	print("CURATED TOTAL ",total," anchors; soft menu palette saved")
	quit(0)

func geometry_signature(scene: Node3D) -> int:
	var values: Array = []
	for body in scene.get_node("Geometry").get_children():
		values.append([String(body.name),body.transform])
		for child in body.get_children():
			if child is MeshInstance3D: values.append([String(child.name),child.transform,child.mesh.get_faces()])
			elif child is CollisionShape3D and child.shape is ConcavePolygonShape3D:
				values.append([String(child.name),child.transform,child.shape.get_faces()])
	return hash(values)

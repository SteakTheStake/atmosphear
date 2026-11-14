extends SceneTree
## Authored mix adjustments from captured browser output and audio-model review.
## Explicit editing utility; never runs at game startup or in CI.
const MIX := {
	"forest": {
		"GroveBirdBeacon":{"gain_db":-6.0,"interval_min":8.0,"interval_max":16.0,"gain_variation_db":1.0},
		"GroveCanopy":{"gain_db":1.0,"audible_range":24.0,"near_distance":4.0},
		"BoardwalkCreakBeacon":{"gain_db":-1.0,"interval_min":10.0,"interval_max":21.0},
		"HutLeakBeacon":{"gain_db":-2.0,"interval_min":6.0,"interval_max":13.0,"gain_variation_db":1.0},
		"WetlandFrogBeacon":{"gain_db":-5.0,"interval_min":9.0,"interval_max":19.0,"gain_variation_db":1.0},
		"WetlandInsectBeacon":{"gain_db":1.0},
		"WetlandPool":{"gain_db":-2.0},
	},
	"cistern": {
		"Bell vault":{"gain_db":-3.0,"looped":false,"interval_min":20.0,"interval_max":45.0,"gain_variation_db":1.0},
		"Timber pump room":{"gain_db":-6.0},
		"Drip gallery":{"gain_db":-3.0},
		"PumpTrickle":{"gain_db":-10.0},
	},
	"freighter": {
		"Engine hall":{"gain_db":0.0},
		"Servo workshop":{"gain_db":-5.0},
		"Cargo hold":{"gain_db":-2.0,"interval_min":13.0,"interval_max":27.0,"gain_variation_db":1.0},
	},
	"courtyard": {
		"BellGateBeacon":{"gain_db":3.5,"looped":false,"interval_min":20.0,"interval_max":45.0,"gain_variation_db":1.0},
		"CloisterLeakBeacon":{"gain_db":0.0,"interval_min":5.0,"interval_max":12.0,"gain_variation_db":1.0},
		"StableHorseBeacon":{"gain_db":-4.0,"interval_min":12.0,"interval_max":25.0,"gain_variation_db":1.0},
	},
}

func _initialize() -> void:
	for id in MIX:
		var path: String = "res://scenes/levels/"+id+".tscn"
		var scene: Node3D = load(path).instantiate()
		var before := geometry_signature(scene)
		for label in MIX[id]:
			var anchor: AtmoSoundEmitter = scene.get_node("Sources").get_node(NodePath(label))
			for property in MIX[id][label]: anchor.set(property,MIX[id][label][property])
		if id=="forest":
			# There is only one Pewee take in the source library. Use the actual
			# two-take goldfinch family instead of manufacturing pitch-copy variants.
			var bird: AtmoSoundEmitter = scene.get_node("Sources/GroveBirdBeacon")
			bird.sound = load("res://assets/library/bird3.wav")
			bird.sound_variants = [load("res://assets/library/bird6.wav")]
		if id=="cistern":
			# Two actual peal passages with natural release; quiet gaps prevent
			# the vault from replaying the same 19.6-second loop continuously.
			var bell: AtmoSoundEmitter = scene.get_node("Sources/Bell vault")
			bell.sound = load("res://assets/library/bell_phrase0.ogg")
			bell.sound_variants = [load("res://assets/library/bell_phrase1.ogg")]
		if id=="courtyard":
			var bell: AtmoSoundEmitter = scene.get_node("Sources/BellGateBeacon")
			bell.sound = load("res://assets/library/bell_phrase0.ogg")
			bell.sound_variants = [load("res://assets/library/bell_phrase1.ogg")]
		assert(geometry_signature(scene)==before,"Mix changes must preserve geometry")
		var packed := PackedScene.new()
		assert(packed.pack(scene)==OK)
		assert(ResourceSaver.save(packed,path)==OK)
		print("TUNED ",id,": ",MIX[id].size()," mix anchors; geometry preserved")
		scene.free()
	quit(0)

func geometry_signature(scene: Node3D) -> int:
	var values: Array = []
	for body in scene.get_node("Geometry").get_children():
		values.append([String(body.name),body.transform])
		for child in body.get_children():
			if child is MeshInstance3D: values.append([child.name,child.transform,child.mesh.get_faces()])
			elif child is CollisionShape3D and child.shape is ConcavePolygonShape3D:
				values.append([child.name,child.transform,child.shape.get_faces()])
	return hash(values)

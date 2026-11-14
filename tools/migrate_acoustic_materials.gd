extends SceneTree
const Surface = preload("res://scripts/acoustic_surface.gd")
func _initialize() -> void:
	for id in ["forest","cistern","freighter","courtyard"]:
		var scene := load("res://scenes/levels/%s.tscn" % id).instantiate() as Node3D
		for body in scene.get_node("Geometry").get_children():
			if not body is StaticBody3D: continue
			var material := String(body.get_meta("material","stone"))
			if "Canopy" in String(body.name): material = "foliage"
			if material not in ["stone","metal","wood","gravel","foliage"]: material = "stone"
			body.set_script(Surface)
			body.acoustic_material = load("res://assets/acoustics/%s.tres" % material)
		var packed := PackedScene.new()
		assert(packed.pack(scene) == OK)
		assert(ResourceSaver.save(packed,"res://scenes/levels/%s.tscn" % id) == OK)
		print("MATERIALS SAVED ",id)
		scene.free()
	quit()

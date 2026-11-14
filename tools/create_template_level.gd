extends SceneTree
## One-time starter authoring. Refuses to overwrite an edited scene.
const A = preload("res://tools/world_author.gd")
func _initialize() -> void:
	var path := "res://scenes/levels/template.tscn"
	if FileAccess.file_exists(path):
		push_error("Template already exists; your edits were preserved.")
		quit(1)
		return
	var scene = A.create("template","My world",Rect2(-24,-24,48,48),Vector3(0,1,16),"gravel")
	A.room(scene,"StarterShelter",Rect2(-18,-17,14,12),4.0,"wood",{"south":Vector2(-11.0,4.0)},true,.4)
	A.surface(scene,"ShelterFloor",Rect2(-18,-17,14,12),"wood")
	A.box(scene,"WaterMarker",Vector3(12,.4,-10),Vector3(2,.8,2),"stone",.15)
	A.source(scene,"WindExample","wind_open0",Vector3(15,3,14),-14,{"range":45.0,"budget":1})
	A.source(scene,"WaterExample","water_lap",Vector3(12,1,-10),-10,{"range":32.0,"landmark":true,"budget":2})
	A.landmark(scene,"Small shelter",Vector3(-11,0,-11),"shelter")
	A.landmark(scene,"Water marker",Vector3(12,0,-10),"water")
	A.region(scene,"Open area",Rect2(-24,-4,48,28),"Wind and gravel",[Vector3(0,1,16),Vector3(10,1,10)])
	A.region(scene,"Shelter",Rect2(-18,-17,14,12),"Wooden floor and walls",[Vector3(-11,1,-8),Vector3(-11,1,-13)])
	var packed := PackedScene.new()
	assert(packed.pack(scene)==OK)
	assert(ResourceSaver.save(packed,path)==OK)
	scene.free()
	print("Created editor-editable template: ",path)
	quit()

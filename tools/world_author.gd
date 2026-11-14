extends RefCounted
## Authoring-time helpers only. The game loads the saved, editor-editable scenes.
const SoundEmitter = preload("res://scripts/sound_emitter.gd")

static func owned(node: Node, parent: Node, scene: Node) -> Node:
	parent.add_child(node)
	node.owner = scene
	return node

static func create(id: String, title: String, bounds: Rect2, spawn_position: Vector3, material := "stone") -> Node3D:
	var scene := Node3D.new()
	scene.name = id.capitalize()
	scene.set_meta("id",id)
	scene.set_meta("title",title)
	scene.set_meta("bounds",bounds)
	scene.set_meta("default_surface",material)
	for label in ["Geometry","Sources","SurfaceAreas","Landmarks","Regions"]:
		var group := Node3D.new()
		group.name = label
		owned(group,scene,scene)
	var spawn := Marker3D.new()
	spawn.name = "Spawn"
	spawn.position = spawn_position
	owned(spawn,scene,scene)
	var center := bounds.get_center()
	box(scene,"Ground",Vector3(center.x,-.25,center.y),Vector3(bounds.size.x,.5,bounds.size.y),material,.55 if material == "gravel" else .2)
	box(scene,"WestBoundary",Vector3(bounds.position.x,3.5,center.y),Vector3(.6,7,bounds.size.y),material,.5)
	box(scene,"EastBoundary",Vector3(bounds.end.x,3.5,center.y),Vector3(.6,7,bounds.size.y),material,.5)
	box(scene,"NorthBoundary",Vector3(center.x,3.5,bounds.position.y),Vector3(bounds.size.x,7,.6),material,.5)
	box(scene,"SouthBoundary",Vector3(center.x,3.5,bounds.end.y),Vector3(bounds.size.x,7,.6),material,.5)
	return scene

static func mesh_body(scene: Node3D, label: String, position: Vector3, mesh: PrimitiveMesh, material: String, absorption: float, color := Color.TRANSPARENT) -> void:
	var body := StaticBody3D.new()
	body.set_script(preload("res://scripts/acoustic_surface.gd"))
	var profile := "foliage" if "Canopy" in label else material
	body.acoustic_material = load("res://assets/acoustics/%s.tres" % profile)
	body.name = label
	body.position = position
	body.collision_layer = 2
	body.collision_mask = 1
	body.set_meta("absorption",absorption)
	body.set_meta("material",material)
	body.set_meta("surface",material)
	owned(body,scene.get_node("Geometry"),scene)
	var visual := MeshInstance3D.new()
	visual.name = "Mesh"
	visual.mesh = mesh
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.albedo_color = {"stone":Color(.34,.36,.35),"wood":Color(.30,.24,.17),"gravel":Color(.25,.29,.21),"metal":Color(.31,.36,.40)}.get(material,Color(.3,.3,.3)) if color == Color.TRANSPARENT else color
	visual.material_override = paint
	owned(visual,body,scene)
	var collision := CollisionShape3D.new()
	collision.name = "MeshCollision"
	collision.shape = mesh.create_trimesh_shape()
	owned(collision,body,scene)

static func box(scene: Node3D, label: String, position: Vector3, size: Vector3, material: String, absorption := .15) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_body(scene,label,position,mesh,material,absorption)

static func tree(scene: Node3D, label: String, position: Vector3, radius := .6, height := 6.0) -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = radius*.65
	trunk.bottom_radius = radius
	trunk.height = height
	trunk.radial_segments = 6
	trunk.rings = 1
	mesh_body(scene,label+"Trunk",position+Vector3(0,height*.5,0),trunk,"wood",.55)
	var crown := CylinderMesh.new()
	crown.top_radius = .15
	crown.bottom_radius = radius*4
	crown.height = height*.5
	crown.radial_segments = 6
	crown.rings = 1
	mesh_body(scene,label+"Canopy",position+Vector3(0,height,0),crown,"wood",.9,Color(.17,.28,.18))

static func room(scene: Node3D, label: String, rect: Rect2, height: float, material: String, doors: Dictionary = {}, roof := true, absorption := .15) -> void:
	for side in ["north","south","west","east"]:
		var horizontal: bool = side in ["north","south"]
		var start: float = rect.position.x if horizontal else rect.position.y
		var end: float = rect.end.x if horizontal else rect.end.y
		var fixed: float = (rect.position.y if side == "north" else rect.end.y) if horizontal else (rect.position.x if side == "west" else rect.end.x)
		var spans: Array = [Vector2(start,end)]
		if doors.has(side):
			var door: Vector2 = doors[side]
			spans = [Vector2(start,door.x-door.y*.5),Vector2(door.x+door.y*.5,end)]
			var lintel_height := maxf(0,height-3.4)
			if lintel_height > .01:
				box(scene,label+side+"Lintel",Vector3(door.x,3.4+lintel_height*.5,fixed) if horizontal else Vector3(fixed,3.4+lintel_height*.5,door.x),Vector3(door.y,lintel_height,.5) if horizontal else Vector3(.5,lintel_height,door.y),material,absorption)
		for i in range(spans.size()):
			var span: Vector2 = spans[i]
			if span.y-span.x <= .01: continue
			var midpoint := (span.x+span.y)*.5
			box(scene,label+side+str(i),Vector3(midpoint,height*.5,fixed) if horizontal else Vector3(fixed,height*.5,midpoint),Vector3(span.y-span.x,height,.5) if horizontal else Vector3(.5,height,span.y-span.x),material,absorption)
	if roof:
		box(scene,label+"Roof",Vector3(rect.get_center().x,height+.15,rect.get_center().y),Vector3(rect.size.x,.3,rect.size.y),material,absorption)

static func source(scene: Node3D, label: String, clip: String, position: Vector3, db: float, options: Dictionary = {}) -> void:
	var marker := SoundEmitter.new()
	marker.name = label
	marker.position = position
	owned(marker,scene.get_node("Sources"),scene)
	var defaults := {"clip":clip,"db":db,"loop":true,"budget":1,"range":35.0,"near":2.5,"interval_min":8.0,"interval_max":22.0,"pitch_min":.98,"pitch_max":1.02,"gain_variation_db":1.5,"motion":0.0,"landmark":false}
	defaults.merge(options,true)
	for key in defaults: marker.set_meta(key,defaults[key])
	var recording: AudioStream
	var base := clip if clip.begins_with("res://") else "res://assets/library/"+clip
	for path in [base,base+".ogg",base+".wav",base+".mp3"]:
		if ResourceLoader.exists(path):
			recording = load(path) as AudioStream
			break
	assert(recording != null,"Missing source recording: "+clip)
	marker.apply_legacy_configuration(defaults,recording)

static func surface(scene: Node3D, label: String, rect: Rect2, material: String) -> void:
	var marker := Marker3D.new()
	marker.name = label
	marker.set_meta("rect",rect)
	marker.set_meta("surface",material)
	owned(marker,scene.get_node("SurfaceAreas"),scene)
	box(scene,label+"Floor",Vector3(rect.get_center().x,.02,rect.get_center().y),Vector3(rect.size.x,.04,rect.size.y),material,.4 if material in ["wood","gravel"] else .14)

static func landmark(scene: Node3D, label: String, position: Vector3, kind: String) -> void:
	var marker := Marker3D.new()
	marker.name = label.replace(" ","").replace("/","")
	marker.position = position
	marker.set_meta("label",label)
	marker.set_meta("kind",kind)
	owned(marker,scene.get_node("Landmarks"),scene)

static func region(scene: Node3D, label: String, rect: Rect2, signature: String, waypoints: Array) -> void:
	var marker := Marker3D.new()
	marker.name = label.replace(" ","").replace("/","")
	marker.position = Vector3(rect.get_center().x,0,rect.get_center().y)
	marker.set_meta("label",label)
	marker.set_meta("rect",rect)
	marker.set_meta("signature",signature)
	marker.set_meta("waypoints",waypoints)
	owned(marker,scene.get_node("Regions"),scene)

static func save(scene: Node3D, id: String) -> void:
	var packed := PackedScene.new()
	assert(packed.pack(scene) == OK)
	assert(ResourceSaver.save(packed,"res://scenes/levels/legacy/%s.tscn"%id) == OK)
	print("AUTHORED ",id," geometry=",scene.get_node("Geometry").get_child_count()," sources=",scene.get_node("Sources").get_child_count()," regions=",scene.get_node("Regions").get_child_count())

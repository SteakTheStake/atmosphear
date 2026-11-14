extends SceneTree
## One-time authoring helper. Runtime loads the saved scenes and never calls this.
## Re-running intentionally replaces scene edits, so edit .tscn files in Godot instead.
const Layouts = preload("res://scripts/levels.gd")
const TITLES := {"forest":"Forest & lake", "cistern":"Stone cistern", "freighter":"Deep-space freighter", "courtyard":"Rain courtyard"}

func _initialize() -> void:
	call_deferred("author")

func owned(node: Node, parent: Node, scene: Node) -> Node:
	parent.add_child(node)
	node.owner = scene
	return node

func geometry(scene: Node3D, parent: Node3D, part: Dictionary, label: String, surface: String, tree := false, canopy := false) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.position = part.pos
	body.collision_layer = 2
	body.collision_mask = 1
	body.set_meta("absorption", part.get("absorption", 0.15))
	body.set_meta("material", surface)
	body.set_meta("surface", surface)
	owned(body, parent, scene)
	var mesh: PrimitiveMesh
	if tree:
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.35 if canopy else part.size.x * 0.3
		cylinder.bottom_radius = part.size.x * 0.5
		cylinder.height = part.size.y
		cylinder.radial_segments = 6
		cylinder.rings = 1
		mesh = cylinder
	else:
		var block := BoxMesh.new()
		block.size = part.size
		mesh = block
	var visual := MeshInstance3D.new()
	visual.name = "Mesh"
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = {"stone":Color(.34,.36,.35),"wood":Color(.30,.24,.17),"gravel":Color(.25,.29,.21),"metal":Color(.31,.36,.40)}.get(surface,Color(.3,.3,.3))
	if canopy: material.albedo_color = Color(.17,.28,.18)
	visual.material_override = material
	owned(visual, body, scene)
	var collision := CollisionShape3D.new()
	collision.name = "MeshCollision"
	collision.shape = mesh.create_trimesh_shape()
	owned(collision, body, scene)

func emitter(label: String, clip: String, position: Vector3, db: float, looped: bool, budget := 1, interval_min := 8.0, interval_max := 22.0, motion := 0.0) -> Dictionary:
	return {"name":label,"clip":clip,"pos":position,"db":db,"loop":looped,"budget":budget,"interval_min":interval_min,"interval_max":interval_max,"motion":motion}

func expanded_sources(id: String, layout: Dictionary) -> Array:
	var result: Array = []
	match id:
		"forest":
			result.append(emitter("Stream", "forest_stream", Vector3(-18,.8,-6),2,true,1))
			result.append(emitter("LakeLap", "water_lap", Vector3(-17,.7,8),-5,true,0))
			result.append(emitter("InsectBank", "insects", Vector3(-11,.8,16),-13,true,0))
			for i in range(8):
				var trunk: Vector3 = layout.trees[i].pos
				result.append(emitter("TreeRustle%02d" % (i+1), "tree_rustle", Vector3(trunk.x+2.35,5.2,trunk.z),-9.0-float(i%3)*1.5,true,0))
			var perches := [Vector3(-8,7.8,4),Vector3(-4,7.8,-7),Vector3(8,7.8,-3),Vector3(-10,7.8,15),Vector3(16,7.8,8)]
			for i in range(5):
				result.append(emitter("BirdPerch%02d" % (i+1),"bird%s"%i,perches[i],-6.0-float(i%2)*2.0,false,1,9.0+i*2,23.0+i*3))
			result.append(emitter("OldTreeCreak","tree_creak",Vector3(-7,3.5,-12),-8,false,1,18,40))
			result.append(emitter("ShelterTimber","tree_creak",Vector3(10,2.6,-13.7),-15,false,2,26,50))
		"cistern":
			result.append(emitter("ChamberDrips","cistern_drips",Vector3(7,3,-7),0,true,4))
			result.append(emitter("Reservoir","cistern_water",Vector3(-7,.5,-12),1,true,2))
			result.append(emitter("EntranceAir","cistern_air",Vector3(9,3,12),-12,true,1))
			for i in range(6):
				var positions := [Vector3(-8,4.8,-5),Vector3(3,5.4,-11),Vector3(9,4.5,-14),Vector3(-3,5.2,10),Vector3(8,5,5),Vector3(-9,4.2,3)]
				result.append(emitter("CeilingDrip%02d"%(i+1),"drip%s"%(i%3),positions[i],-6.0-float(i%3),false,2,3+i,10+i*2))
			result.append(emitter("WestPipeTick","pipe_tick",Vector3(-11.5,2,8),-10,false,2,12,30))
			result.append(emitter("ReservoirPipeTick","pipe_tick",Vector3(-9,1.3,-14),-12,false,2,18,37))
			result.append(emitter("OldGrateCreak","metal_creak",Vector3(10,1.2,-15),-13,false,2,25,48))
		"freighter":
			result.append(emitter("Engine","freighter_engine",Vector3(-11,2,-21),6,true,4))
			result.append(emitter("StarboardVent","freighter_vent",Vector3(12,3,8),1,true,2))
			result.append(emitter("MovingServiceDrone","freighter_electronics",Vector3(0,3.9,-12),-6,true,2,8,22,.65))
			for i in range(3):
				var positions := [Vector3(-12,3,14),Vector3(12,3,-16),Vector3(-12,3,-4)]
				result.append(emitter("Duct%02d"%(i+1),"freighter_vent",positions[i],-12-float(i),true,1))
			for i in range(3):
				result.append(emitter("CoolingPipe%02d"%(i+1),"pipe_tick",Vector3(-14.5+i*14.5,2.4,-17+i*12),-7-float(i*2),false,2,8+i*3,20+i*5))
			for i in range(3):
				result.append(emitter("HullStress%02d"%(i+1),"metal_creak",Vector3(14.6-i*14.6,3.8,-20+i*18),-9-float(i),false,2,19+i*4,40+i*6))
		"courtyard":
			result.append(emitter("NorthRain","courtyard_rain",Vector3(-7,2,-9),4,true,2))
			result.append(emitter("SouthRain","courtyard_rain",Vector3(-10,2,12),-1,true,1))
			result.append(emitter("Drain","courtyard_drain",Vector3(4,.4,-13),1,true,2))
			result.append(emitter("CourtyardWind","courtyard_wind",Vector3(-13,5,-14),-2,true,1))
			for i in range(3):
				result.append(emitter("PorticoDrip%02d"%(i+1),"drip%s"%i,Vector3(6.3,3.1,-10+i*9),-7,false,2,4+i,12+i*2))
			result.append(emitter("DistantBell","distant_bell",Vector3(-12,8,-15),-2,false,2,32,68))
			result.append(emitter("GateHinge","metal_creak",Vector3(0,2,16.5),-11,false,1,19,38))
			result.append(emitter("PorticoTimber","tree_creak",Vector3(13,3,-7),-12,false,2,24,45))
			result.append(emitter("DownpipeNorth","pipe_tick",Vector3(16.3,2,-15),-14,false,1,12,30))
			result.append(emitter("DownpipeSouth","pipe_tick",Vector3(16.3,2,14),-14,false,1,14,32))
	return result

func author() -> void:
	DirAccess.make_dir_recursive_absolute("res://scenes/levels")
	for id in TITLES:
		var layout: Dictionary = Layouts.build(id)
		var scene := Node3D.new()
		scene.name = id.capitalize()
		scene.set_meta("id",id)
		scene.set_meta("title",TITLES[id])
		scene.set_meta("default_surface","gravel" if id == "forest" else ("metal" if id == "freighter" else "stone"))
		var geometry_root := owned(Node3D.new(),scene,scene) as Node3D
		geometry_root.name = "Geometry"
		var source_root := owned(Node3D.new(),scene,scene)
		source_root.name = "Sources"
		var surface_root := owned(Node3D.new(),scene,scene)
		surface_root.name = "SurfaceAreas"
		var landmarks := owned(Node3D.new(),scene,scene)
		landmarks.name = "Landmarks"
		var spawn := owned(Marker3D.new(),scene,scene) as Marker3D
		spawn.name = "Spawn"
		spawn.position = layout.start
		for i in range(layout.boxes.size()):
			var surface: String = scene.get_meta("default_surface")
			if id == "forest" and i >= 6: surface = "wood"
			var label: String = ["Ground","WestBoundary","EastBoundary","NorthBoundary","SouthBoundary"][i] if i < 5 else "Structure%02d"%i
			geometry(scene,geometry_root,layout.boxes[i],label,surface)
		for i in range(layout.trees.size()):
			var part: Dictionary = layout.trees[i]
			geometry(scene,geometry_root,part,"TreeTrunk%02d"%(i+1),"wood",true)
			geometry(scene,geometry_root,{"pos":Vector3(part.pos.x,5.8,part.pos.z),"size":Vector3(4.4,3.2,4.4),"absorption":.85},"TreeCanopy%02d"%(i+1),"wood",true,true)
		for i in range(layout.surfaces.size()):
			var area: Dictionary = layout.surfaces[i]
			if area.surface == "wood":
				var rect: Rect2 = area.rect
				geometry(scene,geometry_root,{"pos":Vector3(rect.get_center().x,.025,rect.get_center().y),"size":Vector3(rect.size.x,.05,rect.size.y),"absorption":.38},"TimberFloor%02d"%i,"wood")
			var marker := owned(Marker3D.new(),surface_root,scene)
			marker.name = "Surface%02d"%i
			marker.set_meta("rect",area.rect)
			marker.set_meta("surface",area.surface)
		for spec in expanded_sources(id,layout):
			var marker := owned(Marker3D.new(),source_root,scene) as Marker3D
			marker.name = spec.name
			marker.position = spec.pos
			for key in ["clip","db","loop","budget","interval_min","interval_max","motion"]: marker.set_meta(key,spec[key])
			marker.set_meta("pitch_min",.94 if not spec.loop else .98)
			marker.set_meta("pitch_max",1.06 if not spec.loop else 1.02)
			marker.set_meta("gain_variation_db",2.0)
		var landmark_specs: Array
		match id:
			"forest": landmark_specs = [["Lake edge","water",Vector3(-16,0,-5)],["Timber shelter","shelter",Vector3(10,0,-10)],["Old oak","tree",Vector3(-7,0,-13)]]
			"cistern": landmark_specs = [["Reservoir","water",Vector3(-8,0,-11)],["Central doorway","doorway",Vector3(0,0,0)],["Stone columns","column",Vector3(6,0,7)]]
			"freighter": landmark_specs = [["Engine room","machine",Vector3(-9,0,-21)],["Cargo stacks","cargo",Vector3(-7,0,-3)],["Service lane","passage",Vector3(0,0,-12)]]
			_: landmark_specs = [["Covered portico","shelter",Vector3(11,0,0)],["Rain drain","water",Vector3(4,0,-13)],["Stone divider","wall",Vector3(-3,0,-4)]]
		for spec in landmark_specs:
			var marker := owned(Marker3D.new(),landmarks,scene) as Marker3D
			marker.name = String(spec[0]).replace(" ","")
			marker.position = spec[2]
			marker.set_meta("label",spec[0])
			marker.set_meta("kind",spec[1])
		var packed := PackedScene.new()
		var result := packed.pack(scene)
		assert(result == OK)
		result = ResourceSaver.save(packed,"res://scenes/levels/%s.tscn"%id)
		assert(result == OK)
		print("AUTHORED ",id," geometry=",geometry_root.get_child_count()," sources=",source_root.get_child_count())
		scene.free()
	quit()

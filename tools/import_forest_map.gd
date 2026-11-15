extends SceneTree
## Rebuild the saved, editable Godot level from the approved Blender export.
const Surface = preload("res://scripts/acoustic_surface.gd")
const Profile = preload("res://scripts/acoustic_material.gd")
const Emitter = preload("res://scripts/sound_emitter.gd")
const Forest = preload("res://scripts/forest_world.gd")
const OUTPUT := "res://scenes/levels/forest_river.tscn"
var root_level: Node3D
var data: Dictionary
var profiles := {}
var audio_map := {
	"audio/liquid_water/Liquid-Water/Liquid Water River Flowing Water 02.wav":"assets/library/forest_river_flow.ogg",
	"audio/ambience_2/Ambience Stream 01.wav":"assets/library/forest_stream_detail.ogg",
	"audio/ambience_2/Ambience Ocean Shore 01.wav":"assets/library/forest_ocean_surf.ogg"}

func v(a: Array) -> Vector3:return Vector3(a[0],a[1],a[2])
func add(node: Node, parent: Node) -> void:
	parent.add_child(node);node.owner=root_level
func container(label: String) -> Node3D:
	var n:=Node3D.new();n.name=label;add(n,root_level);return n
func _initialize() -> void:call_deferred("build")
func build() -> void:
	data=JSON.parse_string(FileAccess.get_file_as_string("res://build/forest_authoring.json"))
	assert(not data.is_empty())
	root_level=Node3D.new();root_level.name="ForestRiver";root_level.set_script(Forest)
	root_level.plan_texture=load("res://assets/worlds/forest/plan.png")
	root_level.set_meta("bounds",Rect2(-2317,-2317,4434,4434))
	root_level.set_meta("default_surface","grass");root_level.set_meta("terrain_height",true)
	root_level.set_meta("blender_source_sha256",data.source_sha256)
	root_level.set_meta("authored_surface_samples",data.surface_samples)
	var geometry:=Node3D.new();geometry.name="Geometry"
	DirAccess.make_dir_recursive_absolute("res://assets/worlds/forest")
	for entry in data.meshes:
		var body:=StaticBody3D.new();body.name=entry.name;body.set_script(Surface)
		geometry.add_child(body);body.owner=geometry
		var kind:=String(entry.surface)
		body.collision_layer=4 if entry.water else (2 if entry.collision else 8)
		body.collision_mask=0
		body.set_meta("material",kind);body.set_meta("absorption",float(entry.absorption[1]))
		if not profiles.has(kind):
			var profile=Profile.new();profile.material_name=kind;profile.absorption_bands=v(entry.absorption)
			profile.scattering=.58 if kind in ["grass","forest_litter","marsh","bark"] else .22
			profile.roughness=.85 if kind in ["grass","forest_litter","gravel"] else .35
			profiles[kind]=profile
		body.acoustic_material=profiles[kind]
		var vertices:=PackedVector3Array();var normals:=PackedVector3Array()
		for triangle in entry.triangles:
			var a:=v(entry.vertices[triangle[0]]);var b:=v(entry.vertices[triangle[1]]);var c:=v(entry.vertices[triangle[2]])
			var normal:Vector3=(b-a).cross(c-a).normalized()
			if normal.length_squared()<.1:continue
			vertices.append_array(PackedVector3Array([a,c,b]));normals.append_array(PackedVector3Array([normal,normal,normal]))
		var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
		var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var material:=StandardMaterial3D.new();material.albedo_color=Color(entry.color[0],entry.color[1],entry.color[2],1)
		material.roughness=.95;mesh.surface_set_material(0,material)
		var visual:=MeshInstance3D.new();visual.name="Mesh";visual.mesh=mesh;body.add_child(visual);visual.owner=geometry
		var shape:=ConcavePolygonShape3D.new();shape.backface_collision=true;shape.set_faces(vertices)
		var collider:=CollisionShape3D.new();collider.name="Collision";collider.shape=shape;body.add_child(collider);collider.owner=geometry
	var geo_scene:=PackedScene.new();assert(geo_scene.pack(geometry)==OK)
	assert(ResourceSaver.save(geo_scene,"res://assets/worlds/forest/terrain.scn",ResourceSaver.FLAG_COMPRESS)==OK)
	geometry.free()
	var geo_instance=load("res://assets/worlds/forest/terrain.scn").instantiate();add(geo_instance,root_level)
	var sources:=container("Sources");container("SurfaceAreas");var landmarks:=container("Landmarks");var regions:=container("Regions")
	var paths:=container("BirdPaths");var triggers:=container("TakeoffEvents")
	# Physical map limits have their own layer: never reflective acoustic walls.
	var limits:=container("WorldLimits")
	for entry in [["West",Vector3(-2318,500,-100),Vector3(6,2000,4436)],["East",Vector3(2118,500,-100),Vector3(6,2000,4436)],["North",Vector3(-100,500,-2318),Vector3(4436,2000,6)],["South",Vector3(-100,500,2118),Vector3(4436,2000,6)]]:
		var body:=StaticBody3D.new();body.name=entry[0];body.position=entry[1];body.collision_layer=16;body.collision_mask=0;add(body,limits)
		var shape:=BoxShape3D.new();shape.size=entry[2]
		var collision:=CollisionShape3D.new();collision.shape=shape;add(collision,body)
	for entry in data.paths:
		var path:=Path3D.new();path.name=entry.name;path.curve=Curve3D.new();path.curve.bake_interval=1.0
		for p in entry.points:path.curve.add_point(v(p.co),v(p["in"]),v(p["out"]))
		if entry.loop:
			var p:Dictionary=entry.points[0];path.curve.add_point(v(p.co),v(p["in"]),v(p["out"]))
		path.set_meta("speed_mps",entry.speed_mps);path.set_meta("loop",entry.loop);path.set_meta("species",entry.species)
		add(path,paths)
	for entry in data.markers:
		if String(entry.get("path_object","")).begins_with("TAKEOFF_"):continue
		var emitter:=make_emitter(entry);add(emitter,sources)
	for entry in data.triggers:
		var event:=Marker3D.new();event.name=entry.name;event.position=v(entry.position)
		for key in ["escape_paths","species","trigger_radius_m","rearm_radius_m","cooldown_min_s","cooldown_max_s","activation_probability"]:
			if entry.has(key):event.set_meta(key,entry[key])
		var route:Dictionary=data.paths.filter(func(p):return p.name==entry.escape_paths[0])[0]
		var name:="TAKEOFF_AUDIO_"+String(entry.name)
		var emitter=make_emitter({"name":name,"position":route.points[0].co,"audio_refs":entry.audio_refs,"event_type":"moving_bird_call","gain_db":-10.0,"managed_event":true})
		emitter.set_meta("managed_event",true);emitter.audible_range=200;emitter.near_distance=7
		add(emitter,sources);event.set_meta("emitter",name);add(event,triggers)
	var important:=["North_Oak","South_Oak","Birch_Riverbank","Spruce_Forest","Freshwater_marsh","Estuary_waders","Mountain_ridge_1"]
	for name in important:
		var entries:Array=data.zones.filter(func(z):return z.name=="ZONE_"+name)
		if entries.is_empty():continue
		var entry:Dictionary=entries[0];var marker:=Marker3D.new();marker.name=name;marker.position=v(entry.position)
		if name=="Estuary_waders" or name.begins_with("Mountain_ridge_"):
			marker.position=safe_ground_point(marker.position,name=="Estuary_waders")
		var radius:=120.0
		var r:=Rect2(marker.position.x-radius,marker.position.z-radius,radius*2,radius*2)
		marker.set_meta("label",name.replace('_',' '));marker.set_meta("rect",r)
		marker.set_meta("waypoints",[marker.position+Vector3.UP*1.1]);add(marker,regions)
		var mark:=Marker3D.new();mark.name=name;mark.position=marker.position
		mark.set_meta("label",name.replace('_',' '));mark.set_meta("kind","water" if name in ["Estuary_waders","Freshwater_marsh"] else "forest");add(mark,landmarks)
	var spawn:=Marker3D.new();spawn.name="Spawn";spawn.position=v(data.spawn);spawn.rotation.y=.5;add(spawn,root_level)
	# Preserve a separate editable template. Only change the default scene assignment.
	var palette=load("res://resources/audio/default_palette.tres")
	for kind in ["grass","dirt","forest_litter","sand","water","wet_dirt","wet_sand","marsh"]:
		var pool:Array[AudioStream]=[]
		for i in range(8):pool.append(load("res://assets/library/forest_step_%s_%d.wav"%[kind,i]))
		palette.terrain_footsteps[kind]=pool
	for kind in ["underwater_mud","underwater_sand","underwater_stone"]:palette.terrain_footsteps[kind]=palette.terrain_footsteps.water
	assert(ResourceSaver.save(palette,"res://resources/audio/default_palette.tres")==OK)
	var packed:=PackedScene.new();assert(packed.pack(root_level)==OK);assert(ResourceSaver.save(packed,OUTPUT)==OK)
	var main_scene=load("res://scenes/main.tscn").instantiate();main_scene.main_level=load(OUTPUT);main_scene.main_level_title="Coastal forest & river"
	var main_packed:=PackedScene.new();assert(main_packed.pack(main_scene)==OK);assert(ResourceSaver.save(main_packed,"res://scenes/main.tscn")==OK)
	main_scene.free();root_level.free()
	print("FOREST IMPORTED: ",data.meshes.size()," meshes, ",data.paths.size()," routes, ",data.triggers.size()," triggers")
	quit()

func make_emitter(entry: Dictionary) -> Marker3D:
	var emitter:=Marker3D.new();emitter.set_script(Emitter);emitter.name=entry.name;emitter.position=v(entry.position)
	var refs:Array=entry.get("audio_refs",[])
	assert(not refs.is_empty(),entry.name)
	emitter.sound=load("res://"+String(audio_map.get(refs[0],refs[0])))
	var variants:Array[AudioStream]=[]
	for ref in refs.slice(1):variants.append(load("res://"+String(audio_map.get(ref,ref))))
	emitter.sound_variants=variants
	var type:=String(entry.get("event_type","ambient_bed"));var group:="detail"
	emitter.gain_db=float(entry.get("gain_db",-20));emitter.reflection_budget=1
	emitter.pitch_min=.99;emitter.pitch_max=1.01;emitter.gain_variation_db=1.2
	emitter.interval_min=float(entry.get("interval_min_s",24));emitter.interval_max=float(entry.get("interval_max_s",60))
	emitter.looped=type not in ["moving_bird_call","stationary_bird_call","intermittent_frog"]
	if type=="individual_tree_wind":
		group="canopy";emitter.gain_db=-4;emitter.audible_range=160;emitter.near_distance=12
		# Leaf wind belongs in air beside the trunk, never inside the solid bark
		# collider (which correctly muffles a sound placed at its centre).
		for mesh in data.meshes:
			if not String(mesh.name).begins_with(String(entry.get("tree_object",""))+"__") or not "Trunk" in String(mesh.name):continue
			var low:=INF;var high:=-INF
			for point in mesh.vertices:low=minf(low,float(point[0]));high=maxf(high,float(point[0]))
			emitter.position.x=high+2.5
			break
	elif "RIVER_" in String(entry.name):
		group="water";emitter.gain_db=-5;emitter.audible_range=300;emitter.near_distance=24;emitter.landmark=true
	elif "COAST_" in String(entry.name):
		group="water";emitter.gain_db=-5;emitter.audible_range=450;emitter.near_distance=40;emitter.landmark=true
	elif "WIND_" in String(entry.name):
		group="wind";emitter.gain_db=-10 if "RIDGE_" not in String(entry.name) else 2.5;emitter.audible_range=500;emitter.near_distance=40
	elif "bird" in type:
		group="bird";emitter.gain_db=2 if type=="moving_bird_call" else -2;emitter.audible_range=520;emitter.near_distance=40 if type=="moving_bird_call" else 18
	else:
		emitter.audible_range=140;emitter.near_distance=6
	emitter.set_meta("mix_group",group)
	if entry.has("path_object"):emitter.set_meta("bird_path",entry.path_object)
	if entry.has("species"):emitter.set_meta("species",entry.species)
	return emitter

func safe_ground_point(near: Vector3, coastal: bool) -> Vector3:
	var best:=INF;var result:=near
	for entry in data.meshes:
		if not String(entry.name).begins_with("Terrain__"):continue
		for triangle in entry.triangles:
			var a:=v(entry.vertices[triangle[0]]);var b:=v(entry.vertices[triangle[1]]);var c:=v(entry.vertices[triangle[2]])
			if (b-a).cross(c-a).normalized().y<.82:continue
			var center:Vector3=(a+b+c)/3.0
			if center.y<119.7 or (coastal and center.y>155):continue
			var score:=center.distance_squared_to(near)
			if score<best:best=score;result=center
	assert(best<INF,"No safe ground near "+str(near))
	return result

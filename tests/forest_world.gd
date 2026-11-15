extends SceneTree
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate();game.native_audio_enabled=false;root.add_child(game)
	await process_frame
	check(game.main_level.resource_path=="res://scenes/levels/forest_river.tscn","approved forest is default; custom template preserved")
	game.play_level("template")
	for i in range(90):await physics_frame
	check(game.player.is_on_floor(),"spawn lands on authored terrain")
	check(game.world.get_node("Geometry").get_child_count()==600,"all saved terrain, water and tree meshes load")
	check(game.world.get_node("BirdPaths").get_child_count()==39,"all Blender Bezier routes imported")
	check(game.world.get_node("TakeoffEvents").get_child_count()==14,"all takeoff events imported")
	check(game.sources.size()<=22,"large map audio has bounded active voice count")
	check(game.sources.any(func(s):return s.direct.playing),"spawn has continuous environment sound")
	var anchors:Array=game.world.get_node("Sources").get_children()
	check(anchors.filter(func(a):return a.get_meta("mix_group","") in ["wind","water","canopy","detail"]).all(func(a):return not a.configuration().doppler),"wind, water, foliage and other ambience disable Doppler automatically")
	check(anchors.filter(func(a):return a.has_meta("bird_path") or bool(a.get_meta("managed_event",false))).all(func(a):return a.configuration().doppler),"flying birds and takeoff events retain Doppler")
	check(game.foot_pool.all(func(s):return not s.doppler_enabled),"self-generated footsteps have no Doppler shift")
	var entry:Dictionary=game.world.active.values()[0]
	var anchor:Node3D=entry.anchor;var original:AudioStream=anchor.sound
	var previous_id:int=entry.sound.get_instance_id()
	anchor.sound=load("res://assets/library/forest_stream_detail.ogg")
	for i in range(3):await process_frame
	check(game.world.active[String(anchor.name)].sound.get_instance_id()!=previous_id,"live sound replacement updates bounded voice bookkeeping")
	anchor.sound=null
	for i in range(3):await process_frame
	check(game.world.active[String(anchor.name)].sound.direct.stream==null,"clearing an active forest sound slot silences it")
	anchor.sound=original
	for i in range(3):await process_frame
	for kind in ["grass","dirt","forest_litter","sand","wet_sand","wet_dirt","marsh","water"]:
		check(game.sound_palette.footstep_streams(kind).size()==8,kind+" exposes eight editable footfall variants")
	var matches:=0
	var samples:Dictionary=game.world.get_meta("authored_surface_samples")
	for kind in samples:
		for raw in samples[kind].slice(0,40):
			var p:=Vector3(raw[0],raw[1]+.88,raw[2]);game.world.water_depth=0
			if game.surface_at(p)==kind:matches+=1;break
	check(matches>=8,"footstep material is resolved from real 3D terrain collision")
	var trigger=game.world.get_node("TakeoffEvents").get_child(0)
	trigger.set_meta("activation_probability",1.0)
	game.world.clock=3.0
	game.player.position=trigger.position+Vector3(80,0,80)
	for i in range(3):await physics_frame
	var events_before:int=game.world.event_count
	game.player.position=trigger.position+Vector3(2,0,2)
	for i in range(3):await physics_frame
	var name:String=trigger.get_meta("emitter")
	check(game.world.active.has(name),"proximity takeoff creates a nearby audible bird")
	check(game.world.event_count>events_before,"player proximity actually triggers takeoff without a manual call")
	var track:Dictionary=game.world.tracks.get(name,{})
	check(not track.is_empty() and track.takeoff,"takeoff follows authored escape curve")
	var before:Vector3=game.world.get_node("Sources").get_node(NodePath(name)).position
	for i in range(60):await physics_frame
	var after:Vector3=game.world.get_node("Sources").get_node(NodePath(name)).position
	check(before.distance_to(after)>4,"takeoff bird moves with physical velocity for Doppler")
	var events:int=game.world.event_count
	game.world._tick_takeoffs(game.listener.global_position)
	check(game.world.event_count==events,"remaining near a perch does not retrigger birds every frame")
	game.player.position=Vector3(-2200,116,-2100)
	for i in range(60):await physics_frame
	check(game.world.underwater and game.world.water_depth>1,"water geometry drives underwater detection")
	check(game.sources.all(func(s):return s.medium_cutoff_hz<1500),"underwater filtering reaches native/browser source output")
	game.set_paused(true);var clock:float=game.world.clock
	for i in range(15):await physics_frame
	check(is_equal_approx(game.world.clock,clock),"pause freezes bird routes and proximity cooldown clocks")
	game.set_paused(false)
	check(not game.map_data.has("player") and not game.map_data.has("heading"),"plan exposes no player location or heading")
	var old_world=game.world
	game.play_level("forest")
	for i in range(5):await physics_frame
	check(not is_instance_valid(old_world) and game.world.scene_file_path.ends_with("legacy/forest.tscn"),"legacy levels work and forest resources release")
	game._command("menu");game.queue_free()
	for i in range(5):await process_frame
	await create_timer(.3).timeout
	print("FOREST CHECKS ","PASS" if failures==0 else "FAIL")
	quit(0 if failures==0 else 1)

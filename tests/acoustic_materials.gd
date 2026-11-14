extends SceneTree
## Deterministic material and image-source checks using actual collision faces.
const Source = preload("res://scripts/acoustic_source.gd")
const Surface = preload("res://scripts/acoustic_surface.gd")
const Profile = preload("res://scripts/acoustic_material.gd")
var failures: Array[String] = []
var world: Node3D
var source

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if value: print("PASS ",label)
	else:
		failures.append(label)
		push_error(label)

func wall(label: String, position: Vector3, size: Vector3, profile: Resource) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.set_script(Surface)
	body.name = label
	body.position = position
	body.collision_layer = 2
	body.acoustic_material = profile
	var mesh := BoxMesh.new()
	mesh.size = size
	var collision := CollisionShape3D.new()
	collision.shape = mesh.create_trimesh_shape()
	body.add_child(collision)
	world.add_child(body)
	return body

func settle(listener: Vector3, quality := 1) -> void:
	source.set_virtualized(false)
	source._query_timer = 0
	for i in range(150): source.tick(listener,Vector3.ZERO,1.0/60.0,quality)

func energy_total(paths: Array) -> float:
	var total := 0.0
	for path in paths: total += path.strength
	return total

func run() -> void:
	var base_buses := AudioServer.bus_count
	for category in ["Environment","EnvironmentReflections","EnvironmentLateLow","EnvironmentLateMid","EnvironmentLateHigh"]:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count-1,category)
		AudioServer.set_bus_send(AudioServer.bus_count-1,"Master")
	var test_buses := AudioServer.bus_count
	var stone := load("res://assets/acoustics/stone.tres")
	var foliage := load("res://assets/acoustics/foliage.tres")
	var wood := load("res://assets/acoustics/wood.tres")
	for id in ["forest","cistern","freighter","courtyard"]:
		var scene = load("res://scenes/levels/%s.tscn" % id).instantiate()
		var all_exported := true
		for body in scene.get_node("Geometry").get_children():
			all_exported = all_exported and body.has_method("get_acoustic_profile") and body.get_acoustic_profile() is Resource
		check(all_exported,id+" collision bodies expose editable material resources")
		scene.free()
	world = Node3D.new()
	root.add_child(world)
	var west := wall("West",Vector3(-.5,5,5),Vector3(1,10,40),stone)
	var north := wall("North",Vector3(10,5,-.5),Vector3(40,10,1),stone)
	var rough: Resource = stone.duplicate()
	west.acoustic_material=rough
	rough.roughness=0
	var smooth_scatter: float = Profile.sample(west).scattering
	rough.roughness=1
	check(Profile.sample(west).scattering>smooth_scatter,"roughness redirects additional specular energy into the diffuse field")
	west.acoustic_material=stone
	source = Source.new()
	world.add_child(source)
	source.position = Vector3(2,1,4)
	source.configure(load("res://assets/library/pipe_ring0.wav"),-6,"Environment",true,4)
	source.configure_late_reverb("Environment")
	check(AudioServer.bus_count == test_buses+5,"three late voices add no private effect buses")
	check(source.late_players.size() == 3,"all three late bands are configured")
	await physics_frame
	await physics_frame
	var listener := Vector3(5,1,2)
	settle(listener)
	var reflected: Array = source._paths.duplicate(true)
	var reflected_strength := energy_total(reflected)
	var second: Dictionary = {}
	for path in reflected:
		if path.order == 2: second = path
	check(not second.is_empty(),"two perpendicular finite walls produce a second-order specular path")
	check(reflected.size()<=4 and source.diagnostics.surface_probes == 14 and source.diagnostics.visibility_queries<=131,"high quality obeys voice and ray-query budgets")
	print("HIGH QUERY COUNT ",source.diagnostics.visibility_queries)
	if not second.is_empty():
		var actual_length: float = source.position.distance_to(second.points[0])+second.points[0].distance_to(second.points[1])+second.points[1].distance_to(listener)
		check(is_equal_approx(second.length,actual_length),"second-order path length sums all three physical segments")
		check(absf(second.length-Vector3(-2,1,-4).distance_to(listener))<.001,"second-order length matches analytic double-image distance")
		var expected: Vector3 = Profile.reflection_energy(Profile.sample(west))*(1.0-Profile.sample(west).scattering)
		expected *= expected
		check(second.energy.distance_to(expected)<.00001,"each reflection multiplies surviving material energy with specular fraction")
		check(second.bands.x<=sqrt(second.energy.x) and second.bands.z<=sqrt(second.energy.z),"pressure is square root of energy with additional air absorption")
		var snap: Dictionary = source.get_debug_paths()
		var debug_second: Dictionary = {}
		for path in snap.reflections:
			if path.order == 2: debug_second=path
		check(debug_second.points == second.points and debug_second.materials == ["Stone","Stone"],"debug snapshot contains both ordered bounce points and material identities")
		var expected_delay: float = (second.length-source.position.distance_to(listener))/343.0*1000.0
		check(absf(debug_second.delay_ms-expected_delay)<.001,"two-bounce delay follows actual excess flight time")
		debug_second.points[0]=Vector3(999,999,999)
		check(source._paths.filter(func(p):return p.order==2)[0].points[0]!=Vector3(999,999,999),"debug bounce arrays cannot mutate the acoustic simulation")
	west.acoustic_material = foliage
	north.acoustic_material = foliage
	settle(listener)
	var absorbed_strength := energy_total(source._paths)
	check(absorbed_strength < reflected_strength*.4,"identical foliage geometry reflects substantially less energy than stone")
	check(source._paths[0].bands.z/source._paths[0].bands.x < reflected[0].bands.z/reflected[0].bands.x*.65,"foliage suppresses reflected high frequencies more strongly")
	west.acoustic_material=stone
	north.acoustic_material=stone
	settle(Vector3(-3,1,2))
	var stone_gain: float = source.direct.volume_db
	var stone_cutoff: float = source.direct_filter.cutoff_hz
	check(absf(source._transmission.x-db_to_linear(stone.transmission_db.x))<.001,"blocked low band follows the exported stone transmission")
	west.acoustic_material=wood
	settle(Vector3(-3,1,2))
	check(source.direct.volume_db>stone_gain+9.0 and source.direct_filter.cutoff_hz>stone_cutoff*1.6,"wood transmits louder and brighter than stone through the same wall")
	check(source.direct_equalizer.get_band_gain_db(3)<-8.0,"transmitted mid band retains material-specific equalization")
	west.acoustic_material=stone
	settle(listener,0)
	check(source._paths.size()<=1 and (source._paths.is_empty() or source._paths[0].order==1),"low quality retains only one first-order reflection")
	check(source.diagnostics.surface_probes==6 and source.diagnostics.visibility_queries<=25,"low quality caps geometry probes and visibility work")
	print("LOW QUERY COUNT ",source.diagnostics.visibility_queries)
	source.set_variation(1.07,-2)
	source.play(.02)
	await physics_frame
	await physics_frame
	settle(listener)
	var synchronized := true
	for voice in source.late_players:
		synchronized = synchronized and voice.playing and voice.stream==source.direct.stream and absf(voice.pitch_scale-source.direct.pitch_scale)<.001
	check(synchronized,"late sends use the same recording, playback event, and pitch as direct sound")
	source.set_suspended(true)
	var all_paused := true
	for voice in source.late_players: all_paused = all_paused and voice.stream_paused
	check(all_paused,"pausing suspends all late voices")
	source.set_suspended(false)
	source.set_virtualized(true)
	all_paused=true
	for voice in source.late_players: all_paused = all_paused and voice.stream_paused
	check(all_paused,"distance virtualization suspends all late voices")
	source.set_virtualized(false)
	var first_plane := {"point":Vector3.ZERO,"normal":Vector3.RIGHT,"collider_id":west.get_instance_id(),"material":Profile.sample(west)}
	var second_plane := {"point":Vector3.ZERO,"normal":Vector3.BACK,"collider_id":north.get_instance_id(),"material":Profile.sample(north)}
	var path: Dictionary = source._second_order(first_plane,second_plane,listener)
	check(not path.is_empty(),"analytic two-bounce fixture is unobstructed before blocker")
	if not path.is_empty():
		var chain: Array = [source.position,path.points[0],path.points[1],listener]
		for i in range(3):
			var midpoint: Vector3 = chain[i].lerp(chain[i+1],.5)
			var blocker := wall("Blocker",midpoint,Vector3(.5,2,.5),stone)
			await physics_frame
			await physics_frame
			check(source._second_order(first_plane,second_plane,listener).is_empty(),"real obstruction on segment%s rejects the two-bounce path" % (i+1))
			blocker.queue_free()
			await physics_frame
			await physics_frame
		west.position.x=-100
		await physics_frame
		await physics_frame
		check(source._second_order(first_plane,second_plane,listener).is_empty(),"a theoretical image plane without a finite physical face produces no echo")
	source.dispose()
	await process_frame
	check(AudioServer.bus_count==test_buses,"source disposal releases all private early and direct buses")
	world.queue_free()
	await process_frame
	while AudioServer.bus_count>base_buses: AudioServer.remove_bus(AudioServer.bus_count-1)
	await create_timer(.1).timeout
	print("ALL MATERIAL ACOUSTIC CHECKS PASSED" if failures.is_empty() else "FAILED: "+str(failures))
	quit(0 if failures.is_empty() else 1)

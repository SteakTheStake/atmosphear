extends SceneTree
## Real capsule-clearance flood fill, scene provenance, and audible landmark coverage.
var game
var failures: Array[String] = []
var report := {}
const CELL := 2.0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if value: print("PASS ",label)
	else:
		failures.append(label)
		push_error(label)

func nearest_cell(point: Vector3, origin: Vector2, width: int, height: int, free: Dictionary) -> Vector2i:
	var base := Vector2i(roundi((point.x-origin.x)/CELL),roundi((point.z-origin.y)/CELL))
	var result := Vector2i(-1,-1)
	var best := 2.5
	for x in range(maxi(0,base.x-2),mini(width,base.x+3)):
		for z in range(maxi(0,base.y-2),mini(height,base.y+3)):
			var cell := Vector2i(x,z)
			if not free.has(cell): continue
			var distance := Vector2(point.x,point.z).distance_to(origin+Vector2(cell)*CELL)
			if distance < best:
				best = distance
				result = cell
	return result

func examine(id: String) -> void:
	game.play_level(id)
	await physics_frame
	await physics_frame
	var scene: Node3D = game.world
	var bounds: Rect2 = scene.get_meta("bounds",Rect2())
	check(bounds.get_area() >= 9000,id+" has at least 9,000 square metres of authored space")
	check(scene.has_node("Regions"),id+" has authored regions")
	if bounds.get_area() <= 0 or not scene.has_node("Regions"): return
	var regions := scene.get_node("Regions").get_children()
	check(regions.size() >= 6,id+" has six or more distinct areas")
	var capsule := CapsuleShape3D.new()
	capsule.radius = .34
	capsule.height = 1.75
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 2
	var space := scene.get_world_3d().direct_space_state
	var origin := bounds.position+Vector2.ONE
	var width := floori(bounds.size.x/CELL)
	var height := floori(bounds.size.y/CELL)
	var free := {}
	for x in range(width):
		for z in range(height):
			var p := origin+Vector2(x,z)*CELL
			query.transform = Transform3D(Basis.IDENTITY,Vector3(p.x,1,p.y))
			if space.intersect_shape(query,1).is_empty(): free[Vector2i(x,z)] = true
	var first := nearest_cell(game.player.position,origin,width,height,free)
	var reached := {first:true}
	var queue: Array[Vector2i] = [first]
	var index := 0
	while index < queue.size():
		var current := queue[index]
		index += 1
		for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next: Vector2i = current+offset
			if not free.has(next) or reached.has(next): continue
			# Cast at body-height too: a thin wall between grid centres must never
			# become a false connection merely because both endpoints are clear.
			var start2 := origin+Vector2(current)*CELL
			var end2 := origin+Vector2(next)*CELL
			var ray := PhysicsRayQueryParameters3D.create(Vector3(start2.x,1,start2.y),Vector3(end2.x,1,end2.y),2)
			if not space.intersect_ray(ray).is_empty(): continue
			reached[next] = true
			queue.append(next)
	var signatures := {}
	var cue_clips := {}
	var cues: Array = []
	var tree_match := true
	for body in scene.get_node("Geometry").get_children():
		var mesh := body.get_node("Mesh") as MeshInstance3D
		var shape := body.get_node("MeshCollision") as CollisionShape3D
		tree_match = tree_match and mesh.mesh.get_faces() == shape.shape.get_faces()
	check(tree_match,id+" visual mesh faces exactly match movement/acoustic collision")
	var doors_open_on_map := true
	for body in scene.get_node("Geometry").get_children():
		if not String(body.name).ends_with("Lintel"): continue
		for footprint in game.map_data.footprints:
			if footprint.has_point(Vector2(body.global_position.x,body.global_position.z)):
				doors_open_on_map = false
	check(doors_open_on_map,id+" overhead lintels leave door openings clear on the static plan")
	for anchor in scene.get_node("Sources").get_children():
		var config: Dictionary = anchor.configuration()
		var clip := String(config.clip)
		check(config.stream is AudioStream and ResourceLoader.exists(config.stream.resource_path),id+" loads assigned recording "+clip)
		if config.get("landmark",false):
			cues.append(anchor)
			cue_clips[clip] = true
			check(float(config.get("motion",0)) == 0,id+" orientation cue stays in a fixed place: "+String(anchor.name))
			if not config.get("loop",true):
				# Natural calls can leave longer gaps after the first event. Runtime
				# arrival scheduling still makes the location discoverable promptly.
				var arrival_wait := INF
				for sound in game.sources:
					if String(sound.get_meta("anchor")) == String(anchor.name):
						arrival_wait = float(sound.get_meta("next_event"))-game.elapsed
				check(arrival_wait > 0 and arrival_wait <= 4.5,id+" orientation cue is scheduled promptly on arrival: "+String(anchor.name))
				check(float(config.interval_min) > 0 and float(config.interval_max) >= float(config.interval_min) and float(config.interval_max) <= 180,id+" orientation cue retains a bounded natural repeat interval: "+String(anchor.name))
	check(cue_clips.size() >= 5,id+" offers at least five different landmark recordings")
	var area_report: Array = []
	var winning_cues := {}
	for region in regions:
		var label := String(region.get_meta("label"))
		var signature := String(region.get_meta("signature",""))
		signatures[signature] = true
		var rect: Rect2 = region.get_meta("rect")
		var waypoints: Array = region.get_meta("waypoints",[])
		check(not waypoints.is_empty(),id+" "+label+" has authored exploration points")
		var accessible := true
		for point in waypoints:
			query.transform = Transform3D(Basis.IDENTITY,Vector3(point.x,1,point.z))
			check(space.intersect_shape(query,1).is_empty(),id+" "+label+" waypoint has full player clearance")
			var cell := nearest_cell(point,origin,width,height,free)
			accessible = accessible and reached.has(cell)
		check(accessible,id+" "+label+" is reachable from spawn through real geometry")
		var local_cues := 0
		for cue in cues:
			if rect.has_point(Vector2(cue.position.x,cue.position.z)): local_cues += 1
		check(local_cues > 0,id+" "+label+" contains a fixed sound landmark")
		# Routes start outside their destination. Compare signatures from an
		# interior exploration point, not the approach shared with the prior area.
		var point: Vector3 = region.position
		var center_distance := INF
		for candidate in waypoints:
			var flat := Vector2(candidate.x,candidate.z)
			if rect.has_point(flat) and flat.distance_to(rect.get_center()) < center_distance:
				point = candidate
				center_distance = flat.distance_to(rect.get_center())
		var ear := Vector3(point.x,1.6,point.z)
		var winner := ""
		var strongest := -999.0
		for sound in game.sources:
			if not sound.get_meta("landmark",false): continue
			sound.set_virtualized(false)
			sound.set_listener_forward(Vector3.ZERO)
			for i in range(90): sound.tick(ear,Vector3.ZERO,1.0/60,0)
			var distance: float = sound.global_position.distance_to(ear)
			var gain: float = sound.direct.volume_db-20*log(maxf(1,distance/sound.near_distance))/log(10.0)+20*log(maxf(.00001,1-distance/sound.audible_range))/log(10.0)
			if gain > strongest:
				strongest = gain
				winner = sound.get_meta("anchor")
		winning_cues[winner] = true
		check(strongest > -36,id+" "+label+" has a nearby audible orientation cue")
		area_report.append({"area":label,"signature":signature,"reachable":accessible,"dominant_landmark":winner,"estimated_path_gain_db":snappedf(strongest,.1)})
	check(signatures.size() == regions.size(),id+" area sound signatures are distinct")
	check(winning_cues.size() >= 4,id+" listening positions yield at least four different dominant landmarks")
	report[id] = {"bounds_metres":[bounds.size.x,bounds.size.y],"reachable_grid_cells":reached.size(),"sources":game.sources.size(),"landmark_clips":cue_clips.keys(),"areas":area_report}

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.native_audio_enabled = false # Exercise the retained portable geometry/mixer regression path.
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	for id in ["forest","cistern","freighter","courtyard"]: await examine(id)
	game._command("menu")
	await process_frame
	game.queue_free()
	await process_frame
	game = null
	for i in range(4): await physics_frame
	DirAccess.make_dir_recursive_absolute("res://test-results")
	var file := FileAccess.open("res://test-results/expanded-worlds.json",FileAccess.WRITE)
	check(file != null,"expanded-world report opens in a fresh source checkout")
	if file != null:
		file.store_string(JSON.stringify(report,"  "))
		file.close()
	if failures.is_empty(): print("ALL EXPANDED WORLD CHECKS PASSED")
	else: print("FAILED: ",failures)
	await create_timer(.1).timeout
	quit(0 if failures.is_empty() else 1)

extends SceneTree
## Geometry/material/route assertions independent of the gameplay main script.
const Room = preload("res://scripts/room_acoustics.gd")
const W = preload("res://tools/world_author.gd")
var failures: Array[String] = []
var report := {}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if value: print("PASS ",label)
	else:
		failures.append(label)
		push_error(label)

func fixture(size: Vector3, material := "stone") -> Node3D:
	var scene := W.create("reverb_fixture","Reverb test fixture",Rect2(-60,-60,120,120),Vector3.ZERO,material)
	W.room(scene,"Chamber",Rect2(-size.x*.5,-size.z*.5,size.x,size.z),size.y,material,{},true)
	root.add_child(scene)
	return scene

func settle(room) -> void:
	for i in range(240): room.tick(1.0/60.0)

func routed(label: String, destination: String) -> bool:
	var index := AudioServer.get_bus_index(label)
	return index > AudioServer.get_bus_index(destination) and AudioServer.get_bus_send(index) == destination

func run() -> void:
	var room := Room.new()
	room.setup_buses()
	var bus_count := AudioServer.bus_count
	check(bus_count == 18,"three shared spectral returns and six category sends have bounded bus count")
	check(routed("Room","Master") and routed("EarlyReturn","Master"),"early and late returns independently reach Master")
	check(routed("Diffusion","EarlyReturn"),"early diffusion never feeds a late reverb bus")
	check(routed("Environment","Master") and routed("Footsteps","Master"),"direct category buses bypass reverb")
	for category in ["Environment","Footsteps"]:
		check(routed(category+"Reflections","Diffusion"),category+" reflections feed only early diffusion")
		for band in ["Low","Mid","High"]:
			check(routed(category+"Late"+band,"Room"+band),category+" "+band+" send reaches its spectral band")
	for band in ["Low","Mid","High"]:
		var index := AudioServer.get_bus_index("Room"+band)
		var highpass := 0.0
		var lowpass := 0.0
		var reverbs := 0
		for i in range(AudioServer.get_bus_effect_count(index)):
			var effect := AudioServer.get_bus_effect(index,i)
			if effect is AudioEffectLowPassFilter: lowpass = effect.cutoff_hz
			elif effect is AudioEffectHighPassFilter: highpass = effect.cutoff_hz
			elif effect is AudioEffectReverb:
				reverbs += 1
				check(effect.wet == 1.0 and effect.dry == 0.0,band+" late reverb outputs wet signal only")
		check(reverbs == 1,band+" uses exactly one algorithmic reverb")
		check((band == "Low" and lowpass == 400.0 and highpass == 0.0) or (band == "Mid" and lowpass == 3500.0 and highpass == 400.0) or (band == "High" and lowpass == 0.0 and highpass == 3500.0),band+" has the actual expected crossover filters")
	room.setup_buses()
	check(AudioServer.bus_count == bus_count,"repeated setup does not duplicate shared buses")
	check(room.primary_effect == room.effects[1] and room.effects[0] != room.effects[1] and room.effects[1] != room.effects[2],"three independent DSP instances back the three decay bands")

	var stone := fixture(Vector3(12,6,8))
	await physics_frame
	await physics_frame
	room.probe(stone.get_world_3d(),Vector3(0,1.6,0),1)
	settle(room)
	var stone_stats: Dictionary = room.stats.duplicate(true)
	report.stone = stone_stats
	check(stone_stats.probe_rays == 48 and stone_stats.ray_casts == 144 and stone_stats.bounce_hits == 144,"full quality traces48 geometric probes with three bounded bounces each")
	check(stone_stats.enclosure > .95 and stone_stats.escape_fraction < .01,"closed stone enclosure retains ray energy without geometric escape")
	check(stone_stats.decay_bands[0] > stone_stats.decay_bands[1] and stone_stats.decay_bands[1] > stone_stats.decay_bands[2],"material and air absorption produce distinct low/mid/high decay estimates")
	check(room.effects[0].room_size > room.effects[1].room_size and room.effects[1].room_size > room.effects[2].room_size,"independent decay estimates change the actual three reverb effects")
	check(room.wet_target > .1 and room.wet_target <= .32,"closed-room late return is audible but bounded")
	room.probe(stone.get_world_3d(),Vector3(0,1.6,0),0)
	check(room.stats.probe_rays == 16 and room.stats.ray_casts <= 32,"low quality bounds work to16 probes and at most32 casts")
	room.probe(stone.get_world_3d(),Vector3(0,1.6,0),1)
	check(room.stats.decay_targets == stone_stats.decay_targets,"stationary deterministic probes do not introduce coefficient jitter")
	for body in stone.get_node("Geometry").get_children(): body.acoustic_material = load("res://assets/acoustics/wood.tres")
	room.probe(stone.get_world_3d(),Vector3(0,1.6,0),1)
	settle(room)
	var wood_stats: Dictionary = room.stats.duplicate(true)
	report.wood = wood_stats
	check(wood_stats.decay_bands[1] < stone_stats.decay_bands[1]*.55,"same geometry with absorbent wood substantially shortens midband decay")
	check(wood_stats.scattering > stone_stats.scattering and wood_stats.leakage_bands[0] > stone_stats.leakage_bands[0],"authored scattering and frequency transmission enter the probe model")
	stone.queue_free()
	await process_frame
	var large := fixture(Vector3(24,12,16))
	await physics_frame
	await physics_frame
	room.probe(large.get_world_3d(),Vector3(0,1.6,0),1)
	settle(room)
	report.large_stone = room.stats.duplicate(true)
	check(room.stats.mean_free_path > stone_stats.mean_free_path*1.5,"larger physical geometry increases the measured mean free path")
	check(room.stats.decay_bands[1] > stone_stats.decay_bands[1]+.4,"larger reflective geometry produces a longer late decay estimate")
	large.queue_free()
	await process_frame
	var forest: Node3D = load("res://scenes/levels/legacy/forest.tscn").instantiate()
	root.add_child(forest)
	await physics_frame
	await physics_frame
	var before: float = room.stats.rt60_estimate
	room.probe(forest.get_world_3d(),Vector3(0,1.6,44),1)
	var target: float = room.stats.decay_targets[1]
	room.tick(1.0/60.0)
	check(room.stats.rt60_estimate < before and room.stats.rt60_estimate > target+.05,"moving outside smooths the room transition rather than snapping effect parameters")
	settle(room)
	report.forest = room.stats.duplicate(true)
	check(room.stats.enclosure < .3 and room.stats.escape_fraction > .3,"open forest geometry allows probe energy to escape")
	check(room.wet_target < .07,"open forest keeps the diffuse tail below nearby directional sound")
	room.probe(forest.get_world_3d(),Vector3(29,1.6,-28),1)
	settle(room)
	report.hut = room.stats.duplicate(true)
	check(room.stats.enclosure > report.forest.enclosure+.3 and room.wet_target > report.forest.wet_target+.05,"entering the real timber hut changes enclosure and late return")
	room.set_paused(true)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Room")) and AudioServer.is_bus_mute(AudioServer.get_bus_index("EarlyReturn")),"pause mutes both late tails and early delay returns")
	room.set_paused(false)
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Room")) and not AudioServer.is_bus_mute(AudioServer.get_bus_index("EarlyReturn")),"resume restores both acoustic returns")
	var old_reverbs := room.effects.duplicate()
	var old_diffusion := AudioServer.get_bus_effect(AudioServer.get_bus_index("Diffusion"),0)
	room.clear()
	check(room.effects[0] != old_reverbs[0] and room.effects[1] != old_reverbs[1] and room.effects[2] != old_reverbs[2],"level clear replaces all three buffered reverb instances")
	check(AudioServer.get_bus_effect(AudioServer.get_bus_index("Diffusion"),0) != old_diffusion,"level clear also discards early diffusion delay buffers")
	check(room.wet_target == 0.0 and room.stats.wet == 0.0 and AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Room")) < -70,"clear starts the next room with a silent late return")
	check(AudioServer.bus_count == bus_count,"probes, material changes, pause and clear allocate no additional buses")
	forest.queue_free()
	await process_frame
	var output := FileAccess.open("res://test-results/room-acoustics.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	if failures.is_empty(): print("ALL THREE-BAND ROOM ACOUSTIC CHECKS PASSED")
	else: print("FAILED: ",failures)
	quit(0 if failures.is_empty() else 1)

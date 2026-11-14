extends SceneTree
## Headless integration checks against the shipped level triangle geometry.
## Run: godot_console --headless --path . --script tests/acoustics.gd

var failures: Array[String] = []
var game
const CISTERN_CLEAR := Vector3(0, 1.6, 0)

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		failures.append(label)
		push_error(label)

func settle(source, listener_position: Vector3, velocity := Vector3.ZERO, quality := 1) -> void:
	# Deterministically advance only the acoustic smoothing and query timers.
	source.set_virtualized(false)
	for i in range(120):
		source.tick(listener_position, velocity, 1.0 / 60.0, quality)

func enter(id: String) -> void:
	game.play_level(id)
	await physics_frame
	await physics_frame

func expected_private_buses() -> int:
	# Independent contract: each authored emitter owns one direct bus plus its
	# authored reflection budget; the three foot slots and action slot have 2/3.
	var count := 3 * (1 + 2) + (1 + 3)
	for anchor in game.world.get_node("Sources").get_children():
		count += 1 + int(anchor.get_meta("budget", 2))
	return count

func bus_sends_to(bus_name: StringName, destination: StringName) -> bool:
	var index := AudioServer.get_bus_index(bus_name)
	return index >= 0 and AudioServer.get_bus_send(index) == destination

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.set_process(false)
	var base_bus_count := AudioServer.bus_count
	await enter("cistern")
	check(game.world.scene_file_path == "res://scenes/levels/legacy/cistern.tscn", "runtime instantiates the editable saved cistern scene")
	check(game.foot_pool.size() == 3 and is_instance_valid(game.action_sound), "three independent foot slots and one action emitter exist")
	check(bus_sends_to("Environment", "Master") and bus_sends_to("Footsteps", "Master"), "direct categories bypass all reverberation")
	check(bus_sends_to("EnvironmentReflections", "Diffusion") and bus_sends_to("FootstepsReflections", "Diffusion"), "reflection categories feed diffusion exactly once")
	check(bus_sends_to("Diffusion", "EarlyReturn") and bus_sends_to("EarlyReturn", "Master"), "early reflections return independently of late reverberation")
	check(bus_sends_to("RoomLow","Room") and bus_sends_to("RoomMid","Room") and bus_sends_to("RoomHigh","Room") and bus_sends_to("Room","Master"),"three filtered late bands share one wet return")
	var drips = game.sources[0]
	var dry_baseline: float = drips._base_db + drips._variation_gain_db
	check(drips.late_players.size() == 3,"source has three synchronized late sends without private extra buses")
	check(game.sources[1].reflections.size() == 4, "bell vault source honors its four-reflection authored budget")
	check(bus_sends_to(drips._bus_names[0], "Environment"), "source direct bus reaches the dry category")
	var reflection_routes_valid := true
	for i in range(drips.reflections.size()):
		reflection_routes_valid = reflection_routes_valid and bus_sends_to(drips._bus_names[i + 1], "EnvironmentReflections") and drips.reflection_delays[i].dry == 0.0
	check(reflection_routes_valid, "reflection voices contain delayed signal only and reach reflection category")
	# Gallery source is (-26,3.3,-5), behind its east wall at x=-5.
	# An eight-meter doorway at z=0 opens into the central service spine.
	settle(drips, Vector3(0, 1.6, 10))
	check(drips.diagnostics.blocked > 0.95, "cistern triangle wall obstructs direct source")
	var stone = load("res://assets/acoustics/stone.tres")
	check(drips.diagnostics.cutoff < 1100 and drips._transmission.z < drips._transmission.x*.05, "stone transmission removes substantially more treble than bass")
	check(absf(drips.diagnostics.direct_db - (dry_baseline+stone.transmission_db.x)) < .2, "stone wall broadband gain follows its exported low-band transmission")
	print("WALL ", drips.diagnostics)
	settle(drips, CISTERN_CLEAR)
	check(drips.diagnostics.blocked < 0.05, "real central doorway restores direct line of sight")
	check(drips.diagnostics.cutoff > 11000, "doorway restores high frequencies subject to distance absorption")
	check(drips.diagnostics.reflections > 0, "finite cistern faces produce reflected paths")
	print("DOORWAY ", drips.diagnostics)
	var towards: Vector3 = (CISTERN_CLEAR - drips.global_position).normalized()
	drips.source_velocity = towards * 12.0
	settle(drips, CISTERN_CLEAR)
	check(drips.diagnostics.pitch > 1.025, "approaching source raises pitch")
	drips.source_velocity = -towards * 12.0
	settle(drips, CISTERN_CLEAR)
	check(drips.diagnostics.pitch < 0.975, "receding source lowers pitch")
	drips.source_velocity = Vector3.ZERO
	settle(drips, CISTERN_CLEAR, Vector3.ZERO, 0)
	check(drips.diagnostics.reflections <= 1, "low acoustic quality bounds reflection voices")
	check(absf(drips.diagnostics.pitch - 1.0) < 0.001, "stationary source returns to original pitch")
	drips.set_listener_forward(towards * -1.0)
	settle(drips, CISTERN_CLEAR)
	var front_cutoff: float = drips.direct_filter.cutoff_hz
	drips.set_listener_forward(towards)
	settle(drips, CISTERN_CLEAR)
	check(drips.direct_filter.cutoff_hz < front_cutoff * 0.75, "turning away produces a distinct rear spectral cue")
	drips.set_listener_forward(Vector3.ZERO)
	drips.set_variation(1.08, -3.0)
	settle(drips, CISTERN_CLEAR)
	check(absf(drips.direct.pitch_scale - 1.08) < 0.001, "recording pitch variation multiplies physical Doppler")
	check(absf(drips.direct.volume_db - (drips._base_db - 3.0)) < 0.1, "recording gain variation applies to the direct voice")
	var reflection_pitch_valid := true
	for reflection in drips.reflections:
		reflection_pitch_valid = reflection_pitch_valid and absf(reflection.pitch_scale - 1.08) < 0.001
	check(reflection_pitch_valid, "reflections use the same recording pitch variation")
	game._probe_room()
	var indoor: Dictionary = game.room_stats.duplicate()
	var indoor_wet: float = game.wet_target
	await enter("forest")
	var authored_trees := 0
	var authored_birds := 0
	for anchor in game.world.get_node("Sources").get_children():
		if anchor.get_meta("clip") == "tree_rustle": authored_trees += 1
		if String(anchor.get_meta("clip")).begins_with("bird") and not anchor.get_meta("loop"): authored_birds += 1
	check(authored_trees >= 8 and authored_birds >= 5, "forest contains individual tree loops and authored bird one-shots")
	game._probe_room()
	var outdoor: Dictionary = game.room_stats.duplicate()
	check(indoor.enclosure > outdoor.enclosure + 0.3, "indoor enclosure exceeds open forest")
	check(indoor_wet > game.wet_target + 0.1, "indoor reflections drive a stronger late tail")
	print("INDOOR ", indoor, " OUTDOOR ", outdoor)
	game.player.position = Vector3(29, 1, -28)
	await physics_frame
	game._probe_room()
	check(game.room_stats.enclosure > outdoor.enclosure + 0.3, "walking into forest shelter changes enclosure")
	print("SHELTER ", game.room_stats)
	for iteration in range(3):
		for id in ["cistern", "freighter", "courtyard", "forest"]:
			await enter(id)
			var expected: int = base_bus_count + expected_private_buses()
			check(AudioServer.bus_count == expected, "level switch %s/%s leaves no source buses" % [iteration, id])
	await enter("freighter")
	var moving = game.sources[2]
	game.player.position = Vector3(-22,1,0)
	await physics_frame
	# Advance actual main-loop emitter motion, not a mock velocity assignment.
	for i in range(90):
		game._physics_process(1.0 / 60.0)
	check(moving.source_velocity.length() > 1.0 and moving.source_velocity.length() < 9.0, "freighter emitter has bounded physical motion")
	check(absf(moving.diagnostics.pitch - 1.0) > 0.0005, "moving freighter emitter applies Doppler")
	var all_emitters: Array = game.sources + game.foot_pool + [game.action_sound]
	for i in range(3): game._play_footfall(false)
	game._action("punch_swing.wav", game.player.position)
	# AudioStreamPlayer3D starts scheduled voices on its next internal physics tick.
	await physics_frame
	await physics_frame
	var playing_before_pause: Array = []
	for source in all_emitters:
		if source.direct.playing: playing_before_pause.append(source)
	game.set_paused(true)
	var paused_voices := true
	var muted_buses := true
	for source in all_emitters:
		# Godot has no playback to pause on dormant one-shot players. Their
		# source suspension state must still prevent a later play from leaking.
		paused_voices = paused_voices and source._suspended and (source not in playing_before_pause or source.direct.stream_paused)
		for voice in source.late_players:
			if voice.playing: paused_voices = paused_voices and voice.stream_paused
		for bus in source._bus_names:
			muted_buses = muted_buses and AudioServer.is_bus_mute(AudioServer.get_bus_index(bus))
	check(paused_voices, "pause suspends environmental, pooled footstep, and action voices")
	check(muted_buses, "pause silences every private direct and reflection bus")
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Room")), "pause also silences already-running global reverb tails")
	game.set_paused(false)
	check(not moving.direct.stream_paused, "resume restores emitter playback")
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Room")), "resume restores the reflection return")
	game._command("menu")
	await process_frame
	check(AudioServer.bus_count == base_bus_count, "return to main menu releases every private source bus")
	check(game.sources.is_empty(), "return to main menu releases sources")
	game.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	if failures.is_empty():
		print("ALL ACOUSTIC INTEGRATION CHECKS PASSED")
	else:
		print("FAILED CHECKS: ", failures)
	quit(0 if failures.is_empty() else 1)

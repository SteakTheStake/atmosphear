extends SceneTree
## Debug rendering must observe the acoustic simulation without changing it.
## Run: godot_console --headless --path . --script tests/debug_view.gd

var failures: Array[String] = []
var game

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		failures.append(label)
		push_error(label)

func settle(source, listener_position: Vector3) -> void:
	source.set_virtualized(false)
	for i in range(120):
		source.tick(listener_position, Vector3.ZERO, 1.0 / 60.0, 1)

func audio_snapshot() -> Dictionary:
	var source_state: Array = []
	for source in game.sources:
		source_state.append({
			"id": source.get_instance_id(),
			"stream": source.direct.stream.get_instance_id(),
			"position": source.global_position,
			"pitch": source.direct.pitch_scale,
			"cutoff": source.direct_filter.cutoff_hz,
			"paused": source.direct.stream_paused,
			"late_count":source.late_players.size(),
		})
	return {"buses": AudioServer.bus_count, "settings": game.settings.duplicate(true), "generation": game.level_generation, "player": game.player.global_transform, "listener": game.listener.global_transform, "room_effect": game.room_effect.get_instance_id(), "sources": source_state}

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.native_audio_enabled = false # Exercise the retained portable geometry/mixer regression path.
	root.add_child(game)
	game.set_physics_process(false)
	game.set_process(false)
	game.play_level("cistern")
	await physics_frame
	await physics_frame
	check(not game.debug_enabled, "debug visualization starts disabled")
	check(game.camera.cull_mask == 0, "normal play renders no geometry or overlays")
	var source = game.sources[0]
	game.player.position = Vector3(0, 1, 10)
	settle(source, game.listener.global_position)
	var blocked: Dictionary = source.get_debug_paths()
	check(blocked.center_blocked, "debug records actual blocked center ray")
	check(blocked.obstruction_point is Vector3, "blocked center ray exposes its geometry hit")
	check(absf(blocked.obstruction_point.x + 4.75) < 0.02, "center obstruction point lies on the gallery east wall face")
	check(blocked.obstruction_segments.size() == 3, "debug retains the same three obstruction samples used by audio")
	check(blocked.obstruction_segments[0].point == blocked.obstruction_point, "center marker and sampled segment agree")
	check(blocked.source == source.global_position and blocked.listener == game.listener.global_position, "debug endpoints match acoustic source and listener")
	game.player.position = Vector3(0, 1, 0)
	settle(source, game.listener.global_position)
	var clear: Dictionary = source.get_debug_paths()
	check(not clear.center_blocked and clear.obstruction_point == null, "open doorway clears the obstruction marker")
	check(clear.reflections.size() > 0, "debug includes active reflected paths")
	check(clear.reflections.size() == source._paths.size(), "debug reflection count exactly matches the audio paths")
	for i in range(clear.reflections.size()):
		var shown: Dictionary = clear.reflections[i]
		var actual: Dictionary = source._paths[i]
		var expected_delay := clampf((float(actual.length) - source.global_position.distance_to(game.listener.global_position)) / 343.0 * 1000.0, 0.0, 500.0)
		check(shown.points == actual.points and shown.order == actual.order, "reflection %s preserves the ordered bounce chain" % i)
		check(shown.point == actual.point and shown.length == actual.length and shown.absorption == actual.absorption, "reflection %s uses actual audio geometry and absorption" % i)
		check(is_equal_approx(shown.delay_ms, expected_delay), "reflection %s uses the audio path-delay formula" % i)
		check(shown.applied_delay_ms == source.reflection_delays[i].tap1_delay_ms, "reflection %s reports the current fixed native tap" % i)
		check(shown.rendered_point == source.reflections[i].global_position, "reflection %s reports the rendered acoustic proxy" % i)
	var original_point: Vector3 = source._paths[0].point
	var original_sample: Vector3 = source._debug_obstruction_samples[0].point
	clear.reflections[0].point = Vector3(999, 999, 999)
	clear.obstruction_segments[0].point = Vector3(999, 999, 999)
	check(source._paths[0].point == original_point, "debug snapshot cannot mutate active reflection paths")
	check(source._debug_obstruction_samples[0].point == original_sample, "debug snapshot cannot mutate cached obstruction samples")
	var acoustic_state := audio_snapshot()
	var query_timer: float = source._query_timer
	for i in range(20):
		source.get_debug_paths()
	check(source._query_timer == query_timer, "reading debug snapshots does not advance acoustic updates")
	check(audio_snapshot() == acoustic_state, "reading debug snapshots leaves all audio state unchanged")
	for i in range(5):
		game.set_debug_enabled(true)
		check(game.debug_enabled and game.camera.cull_mask == 3, "toggle on enables only geometry and debug render layers")
		game.debug_view.update_view(game.sources, game.listener.global_position, game.player.rotation.y, game.elapsed)
		check(audio_snapshot() == acoustic_state, "debug rendering does not reset audio, level, or listener state")
		game.set_debug_enabled(false)
		check(not game.debug_enabled and game.camera.cull_mask == 0, "toggle off restores black gameplay")
		check(audio_snapshot() == acoustic_state, "toggle off preserves running source state")
	game._command("menu")
	await process_frame
	game.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	if failures.is_empty():
		print("ALL DEBUG VIEW CHECKS PASSED")
	else:
		print("FAILED CHECKS: ", failures)
	quit(0 if failures.is_empty() else 1)

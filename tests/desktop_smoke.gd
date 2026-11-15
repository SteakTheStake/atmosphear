extends SceneTree
## Run using godot_console --main-pack <exported EXE> --script <this file>.
## Captures PCM inside the native mixer; this is not a headphone audition.
var failures := 0
func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	print("PASS " if value else "FAIL ",message)
	if not value: failures += 1

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	# Time actual gameplay physics directly; Performance.TIME_PROCESS updates
	# slowly and can retain the preceding level-load cost during a short walk.
	game.set_physics_process(false)
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(0,capture)
	var base_buses := AudioServer.bus_count
	var report := {"driver":AudioServer.get_driver_name(),"output_latency_ms":AudioServer.get_output_latency()*1000.0,"mix_rate":AudioServer.get_mix_rate(),"embedded_pack":FileAccess.file_exists("res://project.binary"),"levels":{}}
	check(report.embedded_pack,"test loads resources from the executable's embedded pack")
	check(game.host_input_ready,"desktop input starts ready without browser activation")
	check(game.native_audio != null and game.settings.quality == 2.0,"desktop starts the native HRTF renderer at High quality")
	game.settings.master = .75
	game.settings.ambience = .8
	game.settings.footsteps = .75
	game._apply_settings()
	for id in game.level_scenes():
		game.play_level(id)
		await create_timer(.4).timeout
		capture.clear_buffer()
		var frames := 0
		var sum := Vector2.ZERO
		var peak := 0.0
		var physics_ms: Array[float] = []
		var discarded_before := capture.get_discarded_frames()
		var began := Time.get_ticks_msec()
		Input.action_press("forward",1.0)
		Input.action_press("turn_right",.3)
		while Time.get_ticks_msec()-began < 2200:
			await physics_frame
			var before := Time.get_ticks_usec()
			game._physics_process(1.0/60.0)
			physics_ms.append(float(Time.get_ticks_usec()-before)/1000.0)
			var samples := capture.get_buffer(capture.get_frames_available())
			frames += samples.size()
			for sample in samples:
				sum += sample*sample
				peak = maxf(peak,maxf(absf(sample.x),absf(sample.y)))
		Input.action_release("forward")
		Input.action_release("turn_right")
		check(frames > AudioServer.get_mix_rate()*1.8,id+" supplies continuous native mixer output while walking and turning")
		check(capture.get_discarded_frames() == discarded_before,id+" capture loses no frames")
		check(sum.x > .00001 and sum.y > .00001,id+" produces nonzero stereo PCM")
		check(peak < 1.0,id+" output does not clip in this short walk")
		check(game.player.is_on_floor(),id+" player remains on the authored collision floor")
		physics_ms.sort()
		report.levels[id] = {"frames":frames,"rms":[sqrt(sum.x/maxi(frames,1)),sqrt(sum.y/maxi(frames,1))],"peak":peak,"physics_p95_ms":physics_ms[int(physics_ms.size()*.95)],"physics_max_ms":physics_ms[-1],"buses":AudioServer.bus_count,"steps":game.steps}
		var native_stats: Dictionary = game.native_audio.snapshot()
		check(native_stats.error == "" and native_stats.path_overflows == 0,id+" native DSP has no renderer errors or exhausted path slots")
		check(native_stats.room_fields == game.world.get_node("Regions").get_child_count(),id+" uses every authored room field")
		check(native_stats.mean_block_ms < native_stats.block_frames*1000.0/native_stats.sample_rate,id+" mean DSP work fits the native audio block budget")
		report.levels[id]["native_audio"] = native_stats
		game.set_paused(true)
		check(game.room_acoustics._paused,id+" pause gates room audio")
		game.set_paused(false)
		game._command("menu")
		await process_frame
		check(AudioServer.bus_count == base_buses,id+" returns all private audio buses after exit")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var file := FileAccess.open(args[0],FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"\t"))
		file.close()
	print(JSON.stringify(report))
	AudioServer.remove_bus_effect(0,AudioServer.get_bus_effect_count(0)-1)
	game.queue_free()
	await process_frame
	await create_timer(.1).timeout
	quit(0 if failures == 0 else 1)

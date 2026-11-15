extends SceneTree
## Measure real native mixer PCM while moving a reflection's propagation delay.
## No output device or human listening is claimed by the Dummy-driver run.
var failures := 0
var capture: AudioEffectCapture
var source
var host: Node3D

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	print("PASS " if value else "FAIL ",message)
	if not value: failures += 1

func run() -> void:
	AudioServer.set_bus_volume_db(0,-80.0)
	for label in ["Probe", "ProbeReflections"]:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count-1,label)
		AudioServer.set_bus_send(AudioServer.bus_count-1,"Master")
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Probe"),true)
	capture = AudioEffectCapture.new()
	capture.buffer_length = 2.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index("ProbeReflections"),capture)
	host = Node3D.new()
	root.add_child(host)
	root.audio_listener_enable_3d = true
	var listener := AudioListener3D.new()
	host.add_child(listener)
	listener.make_current()
	var camera := Camera3D.new()
	host.add_child(camera)
	camera.make_current()
	var clip := AudioStreamWAV.new()
	clip.mix_rate = 48000
	clip.format = AudioStreamWAV.FORMAT_16_BITS
	var data := PackedByteArray()
	data.resize(48000*2)
	for i in range(48000): data.encode_s16(i*2,int(sin(TAU*700.0*i/48000.0)*16000.0))
	clip.data = data
	source = load("res://scripts/acoustic_source.gd").new()
	host.add_child(source)
	source.configure(clip,0.0,"Probe",true,1)
	source.near_distance = 10.0
	source.play()
	await create_timer(.15).timeout
	var stepped := await measure(false)
	var faded := await measure(true)
	check(stepped.frames > 48000 and faded.frames > 48000,"both captures contain continuous native mixer output")
	check(faded.rms > .01,"crossfaded reflection remains audible")
	check(faded.max_jump < stepped.max_jump*.45,"crossfaded movement reduces sample discontinuities by more than half")
	check(faded.max_jump < .06,"native delay handoffs have no large sample jumps")
	check(faded.discarded == 0,"capture loses no native mixer frames")
	var report := {"method":"700 Hz continuous tone, moving reflected path; native AudioEffectCapture before muted Master", "driver":AudioServer.get_driver_name(), "stepped":stepped,"crossfaded":faded}
	print(JSON.stringify(report))
	DirAccess.make_dir_recursive_absolute("res://test-results")
	var file := FileAccess.open("res://test-results/native-audio.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	source.dispose()
	host.queue_free()
	await process_frame
	await create_timer(.1).timeout
	while AudioServer.bus_count > 1: AudioServer.remove_bus(AudioServer.bus_count-1)
	capture = null
	clip = null
	quit(0 if failures == 0 else 1)

func measure(crossfade: bool) -> Dictionary:
	capture.clear_buffer()
	var frames := 0
	var sum := 0.0
	var max_jump := 0.0
	var last := Vector2.ZERO
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec()-started < 1800:
		await physics_frame
		var t := float(Time.get_ticks_msec()-started)/1000.0
		var path := {"id":"wall", "point":Vector3(0,0,-1),"length":10.0+t*7.0,"bands":Vector3.ONE}
		if crossfade:
			source._paths.clear()
			source._paths.append(path)
			source._tick_native_reflection(0,0.0,1.0-exp(-7.0/60.0),1.0/60.0)
		else:
			source.reflections[0].global_position = path.point
			source.reflections[0].volume_db = -12.0
			source.reflection_gates[0].volume_db = 0.0
			source.reflection_alternate_gates[0].volume_db = -100.0
			source.reflection_delays[0].tap1_delay_ms = path.length/343.0*1000.0
		var samples := capture.get_buffer(capture.get_frames_available())
		for sample in samples:
			# Exclude initial setup/handoff from the steady movement comparison.
			if t > .3 and frames > 0: max_jump = maxf(max_jump,maxf(absf(sample.x-last.x),absf(sample.y-last.y)))
			sum += sample.length_squared()*.5
			last = sample
			frames += 1
	return {"frames":frames,"rms":sqrt(sum/maxi(frames,1)),"max_jump":max_jump,"discarded":capture.get_discarded_frames()}

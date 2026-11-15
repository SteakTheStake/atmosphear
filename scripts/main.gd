extends Node3D
## Speech-free exploration; all recordings are from assets/library/manifest.json.
const Source = preload("res://scripts/acoustic_source.gd")
const GameUI = preload("res://scripts/game_ui.gd")
const DebugView = preload("res://scripts/acoustic_debug.gd")
const RoomAcoustics = preload("res://scripts/room_acoustics.gd")
const SoundPalette = preload("res://scripts/sound_palette.gd")
@export var sound_palette: SoundPalette = preload("res://resources/audio/default_palette.tres")
const LEGACY_TITLES := {"forest":"Forest & lake", "cistern":"Stone cistern", "freighter":"Deep-space freighter", "courtyard":"Rain courtyard"}
var settings := {"master":0.75,"ambience":0.8,"footsteps":0.75,"ui":0.35,"sensitivity":1.0,"speed":1.0,"quality":1.0,"binaural":1.0}
@export_group("Main Level")
@export var main_level: PackedScene
@export var main_level_title := "My world"
var level := "template"
var player: CharacterBody3D
var listener: AudioListener3D
var camera: Camera3D
var world: Node3D
var sources: Array = []
var foot: Node3D
var clips := {}
var surfaces: Array = []
var started := false
var paused := false
var elapsed := 0.0
var steps := 0
var stride := 0.5
var last_event := "ready"
var acoustic_clock := 0.0
var report_clock := 0.0
var spatial_clock := 0.0
var acoustic_layout := {}
var room_effect: AudioEffectReverb
var room_acoustics = RoomAcoustics.new()
var room_stats := {"enclosure":0.0,"rt60_estimate":0.0,"mean_free_path":0.0,"wet":0.0}
var wet_target := 0.0
var pending_emitter_changes := {}
var game_ui: CanvasLayer
var map_data := {}
var foot_pool: Array = []
var action_sound: Node3D
var ui_player: AudioStreamPlayer
var ui_last_msec := -1000
var recording_bags := {}
var recording_last := {}
var recording_ids := {}
var step_bags := {}
var step_palette_ids := {}
var last_step_by_surface := {}
var next_stride := 0.85
var last_step_clip := ""
var step_history: Array = []
var locomotion := "walk"
var run_latched := false
var jumps := 0
var punches := 0
var landings := 0
var punch_cooldown := 0.0
var action_grace := 0.0
var level_generation := 0
var debug_enabled := false
var debug_view: Node3D
var qa_enabled := false
var qa_region := -1
var host_input_ready := not OS.has_feature("web")
var native_audio_enabled := true
var native_audio
var native_audio_player: AudioStreamPlayer

func _ready() -> void:
	if OS.has_feature("web") and bool(JavaScriptBridge.eval("typeof ATMO_MOBILE_BUILD !== 'undefined' && ATMO_MOBILE_BUILD")):
		get_window().content_scale_size = Vector2i(480,480)
	_load_settings()
	_setup_input()
	_setup_buses()
	if native_audio_enabled and not OS.has_feature("web") and native_audio == null:
		push_error("Native spatial audio is unavailable. Build it with python tools/build_native_audio.py before running the desktop game.")
		get_tree().quit(1)
		return
	_build_player()
	debug_view = DebugView.new()
	add_child(debug_view)
	game_ui = GameUI.new()
	add_child(game_ui)
	game_ui.configure(self)
	game_ui.show_screen("main")
	if OS.has_feature("web"):
		qa_enabled = bool(JavaScriptBridge.eval("['localhost','127.0.0.1','[::1]'].includes(location.hostname) && new URLSearchParams(location.search).has('qa')"))
		set_debug_enabled(bool(JavaScriptBridge.eval("new URLSearchParams(location.search).has('geometry')")))
	_report()

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") != OK: return
	for key in settings:
		var value = config.get_value("audio_game",key,settings[key])
		if value is float or value is int: settings[key] = _setting_value(key,float(value))

func _save_settings() -> void:
	var config := ConfigFile.new()
	for key in settings: config.set_value("audio_game",key,settings[key])
	config.save("user://settings.cfg")

func _setting_value(key: String, value: float) -> float:
	if key == "quality" and native_audio != null: return clampf(value,0.0,2.0)
	var high := 2.0 if key == "sensitivity" else (1.5 if key == "speed" else 1.0)
	var low := 0.5 if key in ["sensitivity","speed"] else 0.0
	return clampf(value,low,high)

func _setup_input() -> void:
	_axis("left", KEY_A, JOY_AXIS_LEFT_X, -1)
	_axis("right", KEY_D, JOY_AXIS_LEFT_X, 1)
	_axis("forward", KEY_W, JOY_AXIS_LEFT_Y, -1)
	_axis("back", KEY_S, JOY_AXIS_LEFT_Y, 1)
	_axis("turn_left", KEY_LEFT, JOY_AXIS_RIGHT_X, -1)
	_axis("turn_right", KEY_RIGHT, JOY_AXIS_RIGHT_X, 1)
	_button("run_hold",KEY_SHIFT,JOY_BUTTON_LEFT_SHOULDER)
	_button("run_toggle",KEY_CTRL,JOY_BUTTON_LEFT_STICK)
	_button("jump",KEY_SPACE,JOY_BUTTON_A)
	_button("punch",KEY_E,JOY_BUTTON_X)
	var trigger := InputEventJoypadMotion.new()
	trigger.device = -1
	trigger.axis = JOY_AXIS_TRIGGER_RIGHT
	trigger.axis_value = 1
	InputMap.action_add_event("punch",trigger)
	InputMap.add_action("pause")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_ESCAPE
	InputMap.action_add_event("pause", key)
	var button := InputEventJoypadButton.new()
	button.device = -1
	button.button_index = JOY_BUTTON_START
	InputMap.action_add_event("pause", button)
	InputMap.add_action("debug_toggle")
	var debug_key := InputEventKey.new()
	debug_key.physical_keycode = KEY_F3
	InputMap.action_add_event("debug_toggle",debug_key)
	var debug_button := InputEventJoypadButton.new()
	debug_button.device = -1
	debug_button.button_index = JOY_BUTTON_RIGHT_STICK
	InputMap.action_add_event("debug_toggle",debug_button)
	Input.joy_connection_changed.connect(_controller_connection_changed)

func _controller_connection_changed(_id: int, connected: bool) -> void:
	if not connected and started and not paused: set_paused(true)
	if game_ui: game_ui.reset_controller_navigation()

func _axis(action: String, code: int, axis: int, value: float) -> void:
	InputMap.add_action(action, 0.18)
	var key := InputEventKey.new()
	key.physical_keycode = code
	InputMap.action_add_event(action, key)
	var motion := InputEventJoypadMotion.new()
	motion.device = -1
	motion.axis = axis
	motion.axis_value = value
	InputMap.action_add_event(action, motion)

func _button(action: String, keycode: int, button_index: int) -> void:
	InputMap.add_action(action,0.5)
	var key := InputEventKey.new()
	key.physical_keycode = keycode
	InputMap.action_add_event(action,key)
	var button := InputEventJoypadButton.new()
	button.device = -1
	button.button_index = button_index
	InputMap.action_add_event(action,button)

func _setup_buses() -> void:
	room_acoustics.setup_buses()
	room_effect = room_acoustics.primary_effect
	AudioServer.add_bus_effect(0, AudioEffectLimiter.new())
	if native_audio_enabled and not OS.has_feature("web") and ClassDB.class_exists("AtmoSpatialStream"):
		native_audio = ClassDB.instantiate("AtmoSpatialStream")
		if native_audio.initialize(int(AudioServer.get_mix_rate())):
			Engine.register_singleton("AtmoAudio",native_audio)
			native_audio.layout({"rooms":[],"portals":[]})
			native_audio_player = AudioStreamPlayer.new()
			native_audio_player.stream = native_audio
			native_audio_player.bus = "Master"
			add_child(native_audio_player)
			native_audio_player.play()
			# Desktop is the reference build; migrate older Low/Standard preferences.
			settings.quality = 2.0
		else:
			push_error("Native HRTF initialization failed: "+str(native_audio.snapshot()))
			native_audio = null
	ui_player = AudioStreamPlayer.new()
	ui_player.bus = "UI"
	ui_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	add_child(ui_player)
	_apply_settings()

func _apply_settings() -> void:
	for pair in [["Master","master"],["Environment","ambience"],["Footsteps","footsteps"]]:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(pair[0]), linear_to_db(maxf(0.00001, float(settings[pair[1]]))))
		if pair[0] != "Master":
			for suffix in ["Reflections","LateLow","LateMid","LateHigh"]:
				var index := AudioServer.get_bus_index(pair[0]+suffix)
				if index >= 0: AudioServer.set_bus_volume_db(index,linear_to_db(maxf(.00001,float(settings[pair[1]]))))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("UI"),linear_to_db(maxf(.00001,float(settings.ui))))

func play_ui(cue: String) -> void:
	# Menu feedback stays out of the listening space, including map toggles.
	if started and not paused: return
	var now := Time.get_ticks_msec()
	if cue == "move" and now-ui_last_msec < 90: return
	ui_last_msec = now
	var pool: Array = sound_palette.cue_streams("ui_"+cue) if sound_palette else []
	ui_player.stream = _pick_recording("ui_"+cue,pool)
	ui_player.volume_db = -3
	if ui_player.stream: ui_player.play()

func _build_player() -> void:
	player = CharacterBody3D.new()
	player.collision_layer = 1
	player.collision_mask = 18
	player.floor_snap_length = 0.3
	add_child(player)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.75
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	player.add_child(shape)
	listener = AudioListener3D.new()
	listener.position.y = 0.65
	player.add_child(listener)
	listener.make_current()
	# Godot discovers audio viewports through cameras even when visuals are disabled.
	camera = Camera3D.new()
	camera.position.y = 0.65
	camera.cull_mask = 0
	player.add_child(camera)
	camera.make_current()
	get_viewport().set_as_audio_listener_3d(true)

func _clip(file: String) -> AudioStream:
	if not clips.has(file): clips[file] = load("res://assets/library/" + file)
	return clips[file]

func level_title(id: String) -> String:
	return main_level_title if id == "template" else String(LEGACY_TITLES.get(id,id))

func level_scenes() -> Dictionary:
	var result := {"template":main_level.resource_path}
	for id in LEGACY_TITLES: result[id] = "res://scenes/levels/legacy/"+id+".tscn"
	return result

func play_level(id: String) -> void:
	if id != "template" and not LEGACY_TITLES.has(id): return
	_clear_world()
	level = id
	qa_region = -1
	level_generation += 1
	world = (main_level if level == "template" else load("res://scenes/levels/legacy/"+level+".tscn")).instantiate()
	add_child(world)
	surfaces.clear()
	for area in world.get_node("SurfaceAreas").get_children():
		surfaces.append({"rect":area.get_meta("rect"),"surface":area.get_meta("surface")})
	player.position = world.get_node("Spawn").global_position
	player.rotation = Vector3(0,world.get_node("Spawn").global_rotation.y,0)
	player.velocity = Vector3.ZERO
	paused = false
	elapsed = 0
	for anchor in world.get_node("Sources").get_children():
		if world.has_method("setup_audio"): break
		sources.append(_create_emitter(anchor))
		if anchor.has_signal("configuration_changed"):
			anchor.configuration_changed.connect(_queue_emitter_change.bind(anchor))
	if world.has_method("setup_audio"): world.setup_audio(self)
	for i in range(3):
		var step_source = Source.new()
		world.add_child(step_source)
		var stone_steps: Array = sound_palette.footstep_streams("stone") if sound_palette else []
		step_source.configure(stone_steps[0] if not stone_steps.is_empty() else null,-7,"Footsteps",false,2)
		step_source.configure_late_reverb("Footsteps")
		foot_pool.append(step_source)
	foot = foot_pool[0]
	action_sound = Source.new()
	world.add_child(action_sound)
	action_sound.configure(sound_palette.cue("punch_swing") if sound_palette else null,-5,"Footsteps",false,3)
	action_sound.configure_late_reverb("Footsteps")
	started = true
	paused = false
	room_acoustics.set_paused(false)
	elapsed = 0
	steps = 0
	stride = 0.5
	next_stride = .85
	run_latched = false
	jumps = 0
	punches = 0
	landings = 0
	punch_cooldown = 0
	action_grace = 0.2
	step_history.clear()
	wet_target = 0
	acoustic_clock = 0
	last_event = "entered"
	_build_map_data()
	if OS.has_feature("web") or native_audio != null: call_deferred("_setup_room_fields",level_generation)
	debug_view.rebuild(world,sources)
	debug_view.set_enabled(debug_enabled)
	game_ui.show_screen("playing")
	_report()

func _emitter_configuration(anchor: Node3D) -> Dictionary:
	if anchor.has_method("configuration"): return anchor.configuration()
	# Compatibility for older hand-authored scenes; migrated nodes use Inspector
	# resources, and never resolve filenames from the legacy metadata at runtime.
	var config := {}
	for key in anchor.get_meta_list(): config[String(key)] = anchor.get_meta(key)
	var clip := String(config.get("clip",""))
	var extension := ".ogg" if ResourceLoader.exists("res://assets/library/"+clip+".ogg") else ".wav"
	config.stream = _clip(clip+extension) if not clip.is_empty() else null
	return config

func _create_emitter(anchor: Node3D, position_override = null) -> Node3D:
	var config := _emitter_configuration(anchor)
	var sound = Source.new()
	sound.doppler_enabled = bool(config.get("doppler",float(config.get("motion",0))>0))
	world.add_child(sound)
	sound.global_position = anchor.global_position if position_override == null else position_override
	var stream: AudioStream = config.get("stream")
	var looped := bool(config.get("loop",true))
	sound.configure(stream,float(config.get("db",-8)),"Environment",looped,int(config.get("budget",1)))
	sound.configure_late_reverb("Environment")
	sound.set_acoustic_extent(float(config.get("range",35)),float(config.get("near",2.5)))
	sound.set_meta("origin",anchor.global_position)
	sound.set_meta("source_anchor",anchor)
	sound.set_meta("anchor",String(anchor.name))
	sound.set_meta("landmark",bool(config.get("landmark",false)))
	for key in ["motion","pitch_min","pitch_max","gain_variation_db","interval_min","interval_max"]:
		sound.set_meta(key,config.get(key,0.0))
	sound.set_meta("clip",String(config.get("clip","Unassigned sound")))
	sound.set_meta("active_clip",String(config.get("clip","Unassigned sound")))
	sound.set_meta("event_count",0)
	sound.set_meta("loop",looped)
	sound.set_meta("managed_event",bool(anchor.get_meta("managed_event",false)))
	sound.set_meta("recordings",config.get("variants",[stream] if stream else []))
	sound.set_meta("next_event",elapsed+_arrival_event_delay(sound))
	if float(sound.get_meta("motion")) > 0 and position_override == null: sound.position += Vector3(0,0,3)
	sound.set_suspended(paused)
	sound.set_virtualized(sound.global_position.distance_to(listener.global_position)>sound.audible_range+4.0)
	if looped and stream:
		_vary_source(sound)
		sound.play(randf_range(0,stream.get_length()*.8))
	return sound

func _queue_emitter_change(anchor: Node3D) -> void:
	if is_instance_valid(anchor): pending_emitter_changes[anchor.get_instance_id()] = anchor

func _flush_emitter_changes() -> void:
	if pending_emitter_changes.is_empty(): return
	for anchor in pending_emitter_changes.values():
		if not is_instance_valid(anchor): continue
		if is_instance_valid(world) and world.has_method("replace_emitter"):
			world.replace_emitter(anchor)
			continue
		for i in range(sources.size()):
			var old = sources[i]
			if old.get_meta("source_anchor",null) != anchor: continue
			var last_position: Vector3 = old.global_position
			old.dispose()
			sources[i] = _create_emitter(anchor,last_position)
			break
	pending_emitter_changes.clear()
	# Rebuild just the observer after source identity changes, keeping the walk.
	if is_instance_valid(world): debug_view.rebuild(world,sources)
	debug_view.set_enabled(debug_enabled and started and not paused)
	_report()

func _clear_world() -> void:
	if native_audio != null: native_audio.clear()
	pending_emitter_changes.clear()
	recording_bags.clear()
	recording_last.clear()
	recording_ids.clear()
	if debug_view:
		debug_view.clear()
		debug_view.set_enabled(false)
	for sound in sources: sound.dispose()
	sources.clear()
	for step_source in foot_pool: step_source.dispose()
	foot_pool.clear()
	foot = null
	if is_instance_valid(action_sound):
		action_sound.dispose()
		action_sound = null
	if is_instance_valid(world):
		remove_child(world)
		world.queue_free()
	room_acoustics.clear()
	room_acoustics.set_paused(true)
	room_effect = room_acoustics.primary_effect

func _process(_delta: float) -> void:
	_flush_emitter_changes()
	if OS.has_feature("web"):
		var command = JavaScriptBridge.eval("window.Atmo ? window.Atmo.takeCommand() : ''")
		if command is String and not command.is_empty(): _command(command)
	if not host_input_ready: return
	if Input.is_action_just_pressed("debug_toggle"): set_debug_enabled(not debug_enabled)
	if debug_enabled and started and not paused:
		debug_view.update_view(sources,listener.global_position,player.rotation.y,elapsed)

func _input(event: InputEvent) -> void:
	if not host_input_ready:
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("pause") or event.is_echo(): return
	get_viewport().set_input_as_handled()
	if event is InputEventJoypadButton:
		# Start always toggles the current walk, even from a settings submenu.
		if started: set_paused(not paused)
	elif game_ui.screen == "settings" or (game_ui.screen == "main" and started):
		game_ui.go_back()
	elif started: set_paused(not paused)

func set_debug_enabled(value: bool) -> void:
	debug_enabled = value
	camera.cull_mask = 3 if value else 0
	debug_view.set_enabled(value and started and not paused)
	if game_ui: game_ui.refresh_map_visibility()
	_report()

func _physics_process(delta: float) -> void:
	report_clock += delta
	spatial_clock += delta
	if (OS.has_feature("web") or native_audio != null) and spatial_clock >= 1.0/(60.0 if native_audio != null else 30.0):
		spatial_clock = 0.0
		var data := {"settings":settings,"paused":paused or not started,"level":level,"position":[listener.global_position.x,listener.global_position.y,listener.global_position.z],"forward":[-player.global_basis.z.x,-player.global_basis.z.y,-player.global_basis.z.z],"decay":room_stats.get("decay_bands",[.2,.2,.2]),"wet":room_stats.get("wet",0.0)}
		var visibility := {}
		for portal in acoustic_layout.get("portals",[]):
			var v: Array = portal.position
			var query := PhysicsRayQueryParameters3D.create(listener.global_position,Vector3(v[0],v[1],v[2]),2)
			visibility[portal.id] = get_world_3d().direct_space_state.intersect_ray(query).is_empty()
		data["portal_visibility"] = visibility
		if native_audio != null: native_audio.scene(data)
		else: JavaScriptBridge.eval("if(window.AtmoAcoustics)window.AtmoAcoustics.scene("+JSON.stringify(data)+")")
	if report_clock > 0.2:
		report_clock = 0
		_report()
	if not host_input_ready or not started or paused: return
	elapsed += delta
	punch_cooldown = maxf(0,punch_cooldown-delta)
	action_grace = maxf(0,action_grace-delta)
	if action_grace <= 0 and Input.is_action_just_pressed("run_toggle"): run_latched = not run_latched
	player.rotation.y -= Input.get_axis("turn_left","turn_right")*1.8*float(settings.sensitivity)*delta
	var input := Input.get_vector("left","right","forward","back")
	var running := run_latched or Input.is_action_pressed("run_hold")
	var desired := player.transform.basis * Vector3(input.x,0,input.y)*(4.2 if running else 1.7)*float(settings.speed)
	if world.has_method("tick_audio"):
		desired*=lerpf(1.0,.48,clampf((float(world.water_depth)-.15),0,1))
	player.velocity.x = move_toward(player.velocity.x,desired.x,delta*9)
	player.velocity.z = move_toward(player.velocity.z,desired.z,delta*9)
	var was_grounded := player.is_on_floor()
	player.velocity.y = -1 if was_grounded else player.velocity.y-18*delta
	if action_grace <= 0 and was_grounded and Input.is_action_just_pressed("jump"):
		player.velocity.y = 6
		jumps += 1
		_action("jump_takeoff.wav",player.position, -4)
	if action_grace <= 0 and Input.is_action_just_pressed("punch") and punch_cooldown <= 0: _punch()
	var falling_speed := player.velocity.y
	var before := player.position
	player.move_and_slide()
	var actual_velocity := (player.position-before)/delta
	var distance := Vector2(actual_velocity.x,actual_velocity.z).length()*delta
	locomotion = "air" if not player.is_on_floor() else ("run" if running and input.length()>.1 else "walk")
	if player.is_on_floor():
		if not was_grounded and falling_speed < -3:
			landings += 1
			_play_footfall(running,clampf(absf(falling_speed)*0.6,1,5))
			stride = 0
		else:
			stride += distance
			if stride >= next_stride and distance > .0005:
				stride = 0
				_play_footfall(running)
	else: stride = 0
	if world.has_method("tick_audio"):
		world.tick_audio(delta,listener.global_position)
		if debug_enabled and int(debug_view.get_meta("audio_revision",-1))!=int(world.audio_revision):
			debug_view.rebuild(world,sources)
			debug_view.set_meta("audio_revision",world.audio_revision)
	for sound in sources:
		if sound.direct.stream == null: continue
		var origin: Vector3 = sound.get_meta("origin")
		var motion: float = sound.get_meta("motion")
		if motion > 0:
			var previous: Vector3 = sound.position
			sound.position = origin+Vector3(sin(elapsed*motion)*12,0,cos(elapsed*motion)*3)
			sound.source_velocity = (sound.position-previous)/delta if elapsed > delta*1.5 else Vector3.ZERO
		# Bounded local details leave space for neighboring landmarks. Voices beyond
		# their inaudible outer margin pause until approached; the hysteresis avoids chatter.
		var distance_to_ear: float = sound.global_position.distance_to(listener.global_position)
		var virtualized: bool = distance_to_ear > sound.audible_range+(2.0 if sound._virtualized else 5.0)
		var waking: bool = sound._virtualized and not virtualized
		sound.set_virtualized(virtualized)
		if virtualized: continue
		var looped: bool = sound.get_meta("loop")
		# Keep each source's clock. Entering an area must not fire every detail
		# together or restart a predictable chorus on every visit.
		if waking and not looped and float(sound.get_meta("next_event"))<elapsed:
			sound.set_meta("next_event",elapsed+_arrival_event_delay(sound))
		if not looped and not bool(sound.get_meta("managed_event",false)) and not sound.direct.playing and elapsed >= float(sound.get_meta("next_event")):
			var selected := _choose_event_stream(sound)
			if selected == null: continue
			sound.set_stream(selected)
			sound.set_meta("active_clip",selected.resource_path.get_file().get_basename())
			sound.set_meta("event_count",int(sound.get_meta("event_count",0))+1)
			_vary_source(sound)
			sound.play()
			sound.set_meta("next_event",elapsed+sound.direct.stream.get_length()+randf_range(maxf(.1,float(sound.get_meta("interval_min"))),maxf(.1,float(sound.get_meta("interval_max")))))
		sound.set_listener_forward(-player.global_basis.z)
		if looped or sound.direct.playing: sound.tick(listener.global_position,actual_velocity,delta,int(settings.quality))
	for step_source in foot_pool:
		if step_source.direct.playing:
			step_source.set_listener_forward(-player.global_basis.z)
			step_source.tick(listener.global_position,actual_velocity,delta,int(settings.quality))
	if action_sound.direct.playing:
		action_sound.set_listener_forward(-player.global_basis.z)
		action_sound.tick(listener.global_position,actual_velocity,delta,int(settings.quality))
	acoustic_clock -= delta
	if acoustic_clock <= 0:
		acoustic_clock = .2 if settings.quality > 1 else (0.35 if settings.quality > 0 else 0.7)
		_probe_room()
	room_acoustics.tick(delta)
	room_stats = room_acoustics.stats

func _arrival_event_delay(sound: Node3D) -> float:
	if bool(sound.get_meta("landmark",false)):
		return randf_range(.8,4.5)
	return randf_range(2.0,clampf(float(sound.get_meta("interval_max",20.0))*.7,5.0,18.0))

func _vary_source(sound: Node3D) -> void:
	var low := clampf(float(sound.get_meta("pitch_min",.98)),.75,1.3)
	var high := clampf(float(sound.get_meta("pitch_max",1.02)),low,1.3)
	var gain := clampf(float(sound.get_meta("gain_variation_db",2.0)),0,6)
	sound.set_variation(randf_range(low,high),randf_range(-gain,gain))

func _pick_recording(key: String, pool: Array) -> AudioStream:
	if pool.is_empty(): return null
	var ids: Array = pool.map(func(stream): return stream.get_instance_id())
	if recording_ids.get(key,[]) != ids:
		recording_ids[key] = ids
		recording_bags[key] = []
	if not recording_bags.has(key) or recording_bags[key].is_empty():
		var bag: Array = range(pool.size())
		bag.shuffle()
		if bag.size()>1 and bag[-1] == recording_last.get(key,-1):
			var swap = bag[0]
			bag[0] = bag[-1]
			bag[-1] = swap
		recording_bags[key] = bag
	var index: int = recording_bags[key].pop_back()
	recording_last[key] = index
	return pool[index]

func _choose_event_stream(sound: Node3D) -> AudioStream:
	return _pick_recording("event_"+String(sound.get_meta("anchor")),sound.get_meta("recordings",[]))

func _play_footfall(running: bool, impact := 0.0) -> void:
	var surface := surface_at(player.position)
	var streams: Array = sound_palette.footstep_streams(surface) if sound_palette else []
	if streams.is_empty(): return
	var ids: Array = streams.map(func(stream): return stream.get_instance_id())
	if step_palette_ids.get(surface,[]) != ids:
		step_palette_ids[surface] = ids
		step_bags[surface] = []
	if not step_bags.has(surface) or step_bags[surface].is_empty():
		var bag: Array = range(streams.size())
		bag.shuffle()
		if bag.size() > 1 and bag[-1] == last_step_by_surface.get(surface,-1):
			var swap = bag[0]
			bag[0] = bag[-1]
			bag[-1] = swap
		step_bags[surface] = bag
	var index: int = step_bags[surface].pop_back()
	last_step_by_surface[surface] = index
	steps += 1
	var stream: AudioStream = streams[index]
	last_step_clip = stream.resource_path.get_file() if not stream.resource_path.is_empty() else "Custom footstep"
	var pitch := randf_range(.94,1.06)*(1.025 if running else 1.0)
	var gain := randf_range(-2.2,1.0)+(2.0 if running else 0.0)+impact
	next_stride = randf_range(1.20,1.42) if running else randf_range(.76,.94)
	var emitter = foot_pool[steps % foot_pool.size()]
	emitter.position = player.position+player.basis.x*(.13 if steps%2 == 0 else -.13)-Vector3(0,.72,0)
	emitter.set_stream(stream)
	emitter.set_variation(pitch,gain)
	emitter.play()
	step_history.append({"clip":last_step_clip,"pitch":pitch,"gain":gain,"stride":next_stride})
	if step_history.size()>32: step_history.pop_front()

func _action(clip: String, pos: Vector3, gain := 0.0) -> void:
	var stream: AudioStream = sound_palette.cue(clip.get_file().get_basename()) if sound_palette else null
	if stream == null:
		action_sound.stop()
		return
	action_sound.position = pos
	action_sound.set_stream(stream)
	action_sound.set_variation(randf_range(.94,1.06),gain)
	action_sound.play()

func _punch() -> void:
	punches += 1
	punch_cooldown = .45
	var origin := listener.global_position
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin,origin-player.global_basis.z*1.8,2))
	if hit.is_empty():
		_action("punch_swing.wav",origin-player.global_basis.z*.4,-7)
		last_event = "punch_air"
	else:
		var material := String(hit.collider.get_meta("material","stone"))
		if material not in ["stone","wood","metal"]: material = "wood" if material in ["gravel","bark"] else "stone"
		_action("punch_"+material+".wav",hit.position+hit.normal*.06,0)
		last_event = "punch_"+material

func _build_map_data() -> void:
	var footprints: Array = []
	var bounds := Rect2(-24,-24,48,48)
	for body in world.get_node("Geometry").get_children():
		for child in body.get_children():
			if not child is MeshInstance3D: continue
			var box: AABB = child.global_transform * child.mesh.get_aabb()
			var low: Vector3 = box.position
			# Plan the walkable floor slice; overhead lintels must not close doors
			# on the map, and high tree crowns are not ground-level obstructions.
			if box.size.y>.6 and low.y<1.8 and box.end.y>.15: footprints.append(Rect2(low.x,low.z,box.size.x,box.size.z))
			elif body.position.y < 0: bounds = Rect2(low.x,low.z,box.size.x,box.size.z)
	var landmarks: Array = []
	for landmark in world.get_node("Landmarks").get_children():
		landmarks.append({"pos":landmark.global_position,"label":landmark.get_meta("label"),"kind":landmark.get_meta("kind")})
	map_data = {"bounds":world.get_meta("bounds",bounds),"footprints":footprints,"landmarks":landmarks}
	if world.has_method("tick_audio"):map_data["terrain_texture"]=world.plan_texture

func _setup_room_fields(generation: int) -> void:
	await get_tree().physics_frame
	if generation != level_generation or not is_instance_valid(world): return
	var rooms: Array = []
	var portals: Array = []
	for region in world.get_node("Regions").get_children():
		var rect: Rect2 = region.get_meta("rect",Rect2())
		var probe = RoomAcoustics.new()
		probe.probe(get_world_3d(),region.global_position+Vector3.UP*1.6,int(settings.quality))
		rooms.append({"id":String(region.name),"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y],"rt":probe.stats.get("decay_targets",[.2,.2,.2]),"wet":probe.wet_target})
	for body in world.get_node("Geometry").get_children():
		if not "lintel" in String(body.name).to_lower(): continue
		var mesh = body.get_node_or_null("Mesh")
		if not mesh is MeshInstance3D: continue
		var box: AABB = mesh.get_aabb()
		var at: Vector3 = body.global_position
		at.y = 1.5
		var room_id := ""
		var best := INF
		for region in world.get_node("Regions").get_children():
			var distance: float = region.global_position.distance_to(at)
			if distance < best: best=distance;room_id=String(region.name)
		portals.append({"id":String(body.name),"room":room_id,"position":[at.x,at.y,at.z],"width":maxf(box.size.x,box.size.z),"open":clampf(float(body.get_meta("acoustic_open_fraction",1.0)),0,1)})
	acoustic_layout = {"rooms":rooms,"portals":portals}
	if native_audio != null: native_audio.layout(acoustic_layout)
	else: JavaScriptBridge.eval("if(window.AtmoAcoustics)window.AtmoAcoustics.layout("+JSON.stringify(acoustic_layout)+")")

func _exit_tree() -> void:
	if native_audio != null and Engine.has_singleton("AtmoAudio") and Engine.get_singleton("AtmoAudio") == native_audio:
		Engine.unregister_singleton("AtmoAudio")

func _probe_room() -> void:
	room_acoustics.probe(get_world_3d(),listener.global_position,int(settings.quality))
	room_stats = room_acoustics.stats
	wet_target = room_acoustics.wet_target

func surface_at(pos: Vector3) -> String:
	if is_instance_valid(world) and world.has_method("footstep_surface"):return world.footstep_surface(pos)
	for area in surfaces:
		if area.rect.has_point(Vector2(pos.x,pos.z)): return area.surface
	return String(world.get_meta("default_surface","stone")) if is_instance_valid(world) else "stone"

func set_paused(value: bool) -> void:
	if not started: return
	paused = value
	room_acoustics.set_paused(value)
	# A confirms menu choices and jumps in play. Consume the transition gesture.
	if not value: action_grace = 0.2
	for sound in sources: sound.set_suspended(value)
	for emitter in foot_pool: emitter.set_suspended(value)
	if action_sound: action_sound.set_suspended(value)
	debug_view.set_enabled(debug_enabled and not paused)
	last_event = "paused" if paused else "resumed"
	game_ui.show_screen("pause" if paused else "playing")
	_report()

func _command(command: String) -> void:
	if command == "host:waiting":
		host_input_ready = false
		if started: set_paused(true)
		game_ui.reset_controller_navigation()
		_report()
	elif command == "host:ready":
		host_input_ready = true
		action_grace = 0.2
		game_ui.reset_controller_navigation()
		_report()
	elif command.begins_with("qa:takeoff:") and qa_enabled and is_instance_valid(world) and world.has_node("TakeoffEvents"):
		var index := command.trim_prefix("qa:takeoff:").to_int()
		var triggers := world.get_node("TakeoffEvents").get_children()
		if index>=0 and index<triggers.size():
			triggers[index].set_meta("activation_probability",1.0)
			player.position=triggers[index].global_position
			player.velocity=Vector3.ZERO
			_report()
	elif command.begins_with("qa:region:") and qa_enabled and is_instance_valid(world):
		var index := command.trim_prefix("qa:region:").to_int()
		var regions := world.get_node("Regions").get_children()
		if index>=0 and index<regions.size():
			var points: Array = regions[index].get_meta("waypoints",[])
			if not points.is_empty():
				var point: Vector3 = points[0]
				var center: Vector3 = regions[index].position
				for candidate: Vector3 in points:
					if Vector2(candidate.x-center.x,candidate.z-center.z).length_squared()<Vector2(point.x-center.x,point.z-center.z).length_squared(): point = candidate
				player.position = Vector3(point.x,point.y if bool(world.get_meta("terrain_height",false)) else 1.0,point.z)
				player.velocity = Vector3.ZERO
				player.rotation = Vector3(0,world.get_node("Spawn").global_rotation.y,0)
				qa_region = index
				acoustic_clock = 0.0
				_report()
	elif command.begins_with("play:"): play_level(command.trim_prefix("play:"))
	elif command == "pause": set_paused(true)
	elif command == "resume": set_paused(false)
	elif command == "restart": play_level(level)
	elif command == "debug:toggle": set_debug_enabled(not debug_enabled)
	elif command == "debug:on": set_debug_enabled(true)
	elif command == "debug:off": set_debug_enabled(false)
	elif command == "menu":
		started = false
		paused = false
		_clear_world()
		last_event = "menu"
		game_ui.show_screen("main")
		_report()
	elif command.begins_with("setting:"):
		var parts := command.split(":")
		if parts.size() == 3 and settings.has(parts[1]):
			settings[parts[1]] = _setting_value(parts[1],parts[2].to_float())
			_apply_settings()
			_save_settings()
			_report()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if started and not paused: set_paused(true)
		if game_ui: game_ui.reset_controller_navigation()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and game_ui:
		game_ui.call_deferred("ensure_focus")

func _report() -> void:
	if not OS.has_feature("web") or player == null: return
	var source_data: Array = []
	for sound in sources: source_data.append({"clip":sound.get_meta("clip"),"active_clip":sound.get_meta("active_clip",""),"event_count":sound.get_meta("event_count",0),"playing":sound.direct.playing,"anchor":sound.get_meta("anchor"),"landmark":sound.get_meta("landmark"),"virtualized":sound._virtualized,"acoustics":sound.diagnostics})
	var state := {"ready":true,"started":started,"paused":paused,"level":level,"title":level_title(level),"steps":steps,"surface":surface_at(player.position),"position":[snappedf(player.position.x,0.01),snappedf(player.position.z,0.01)],"yaw":snappedf(player.rotation.y,0.01),"controllers":Input.get_connected_joypads().size(),"settings":settings,"event":last_event,"generation":level_generation,"diagnostics":{"room":room_stats,"sources":source_data,"bus_count":AudioServer.bus_count}}
	state.main_level_scene = main_level.resource_path
	state.region_count = world.get_node("Regions").get_child_count() if is_instance_valid(world) else 0
	state.ui_screen = game_ui.screen if game_ui else "main"
	state.host_input_ready = host_input_ready
	var focus: Dictionary = game_ui.focus_state() if game_ui else {}
	state.ui_focus_index = focus.get("index",-1)
	state.ui_focus_text = focus.get("text","")
	state.ui_control_count = focus.get("count",0)
	state.map_visible = game_ui.map_visible if game_ui else true
	state.map_signature = hash(map_data)
	state.player_y = snappedf(player.position.y,0.001)
	if is_instance_valid(world) and world.has_method("diagnostics"):state.world_audio=world.diagnostics()
	state.on_floor = player.is_on_floor()
	state.locomotion = locomotion
	state.jumps = jumps
	state.punches = punches
	state.landings = landings
	state.last_step_clip = last_step_clip
	state.scene_source = world.scene_file_path if is_instance_valid(world) else ""
	state.debug_enabled = debug_enabled
	state.debug_visuals = debug_view.stats if debug_view else {}
	if qa_enabled and is_instance_valid(world):
		state.qa_region = qa_region
		state.qa_regions = []
		for region in world.get_node("Regions").get_children():
			var positions: Array = []
			for point: Vector3 in region.get_meta("waypoints",[]): positions.append([point.x,point.y,point.z])
			state.qa_regions.append({"index":state.qa_regions.size(),"label":region.get_meta("label",String(region.name)),"position":positions})
	JavaScriptBridge.eval("if(window.Atmo) window.Atmo.receive("+JSON.stringify(state)+")")

extends SceneTree
## Inspector resources, change notifications and scene persistence; no project assets modified.
const Emitter = preload("res://scripts/sound_emitter.gd")
const Palette = preload("res://scripts/sound_palette.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	if condition: print("PASS ",description)
	else:
		failures.append(description)
		push_error(description)

func run() -> void:
	await examine()
	await process_frame
	if failures.is_empty(): print("ALL AUDIO AUTHORING CHECKS PASSED")
	else: print("FAILED: ",failures)
	quit(0 if failures.is_empty() else 1)

func examine() -> void:
	var total := 0
	for id in ["forest","cistern","freighter","courtyard"]:
		var scene: Node3D = load("res://scenes/levels/legacy/"+id+".tscn").instantiate()
		var valid := true
		for anchor in scene.get_node("Sources").get_children():
			valid = valid and anchor is Emitter and anchor.sound is AudioStream
			var config: Dictionary = anchor.configuration()
			valid = valid and config.stream == anchor.sound
			valid = valid and config.clip == anchor.sound.resource_path.get_file().get_basename()
			valid = valid and is_equal_approx(config.db,anchor.gain_db)
			total += 1
		check(valid,id+" sources use their saved Inspector recording and gain")
		scene.free()
	check(total == 127,"all 127 source anchors expose typed AudioStream resources")
	var scene := Node3D.new()
	scene.name = "AuthoringTest"
	root.add_child(scene)
	var emitter := Emitter.new()
	emitter.name = "EditableSound"
	emitter.position = Vector3(4,2,-7)
	scene.add_child(emitter)
	emitter.owner = scene
	var changes := [0]
	emitter.configuration_changed.connect(func(): changes[0] += 1)
	emitter.sound = load("res://assets/library/bell_phrase0.ogg")
	emitter.gain_db = -3.0
	emitter.audible_range = 80.0
	emitter.near_distance = 7.0
	emitter.looped = false
	check(changes[0] >= 5,"Inspector recording and acoustic property edits emit changes")
	var count: int = changes[0]
	emitter.sound.emit_changed()
	check(changes[0] == count+1,"in-place AudioStream edits forward a configuration change")
	var config: Dictionary = emitter.configuration()
	check(config.stream == emitter.sound and config.clip == "bell_phrase0","configuration uses the assigned stream rather than legacy filenames")
	check(config.db == -3 and config.range == 80 and config.near == 7 and not config.loop,"configuration preserves edited spatial parameters")
	emitter.play_preview.call()
	check(emitter.get_child_count(true) == 0,"runtime never creates or autoplays editor preview audio")
	var buttons := 0
	for property in emitter.get_property_list():
		if property.hint == PROPERTY_HINT_TOOL_BUTTON: buttons += 1
	check(buttons == 2,"Inspector offers explicit Play and Stop preview buttons")
	var packed := PackedScene.new()
	check(packed.pack(scene) == OK,"edited emitter scene packs successfully")
	check(ResourceSaver.save(packed,"user://audio_authoring_test.tscn") == OK,"edited emitter scene saves successfully")
	var restored: Node3D = load("user://audio_authoring_test.tscn").instantiate()
	var restored_emitter = restored.get_node("EditableSound")
	check(restored_emitter.sound.resource_path == emitter.sound.resource_path and restored_emitter.position == emitter.position and restored_emitter.gain_db == -3,"assigned stream and position survive a scene save/reload")
	restored.free()
	var previous_stream: AudioStream = emitter.sound
	emitter.sound = null
	count = changes[0]
	previous_stream.emit_changed()
	check(changes[0] == count and emitter.configuration().stream == null,"clearing a sound disconnects stale resource notifications and produces a silent slot")
	var palette: Resource = load("res://resources/audio/default_palette.tres").duplicate(true)
	var complete := true
	for surface in ["gravel","stone","wood","metal"]:
		complete = complete and palette.footstep_streams(surface).size() == 12
	for name in ["punch_swing","punch_stone","punch_wood","punch_metal","jump_takeoff","ui_move","ui_accept","ui_back"]:
		complete = complete and palette.cue(name) != null
	check(complete,"default palette exposes all 48 footfalls and 8 action/menu recordings")
	var palette_changes := [0]
	palette.changed.connect(func(): palette_changes[0] += 1)
	var replacement: AudioStream = load("res://assets/library/ui_soft_back.wav")
	palette.ui_move = replacement
	check(palette.cue("ui_move.wav") == replacement and palette_changes[0] > 0,"menu/action recordings can be swapped through the palette")
	count = palette_changes[0]
	replacement.emit_changed()
	check(palette_changes[0] == count+1,"nested palette AudioStream edits notify listeners")
	var empty: Array[AudioStream] = []
	palette.gravel_footsteps = empty
	check(palette.footstep_streams("gravel").is_empty(),"an empty footstep palette is a supported silent choice")
	var with_hole: Array[AudioStream] = [null,replacement]
	palette.gravel_footsteps = with_hole
	check(palette.footstep_streams("gravel") == [replacement],"empty Inspector array slots are ignored")
	palette.ui_back = null
	check(palette.cue("ui_back") == null,"menu cues can explicitly be silenced")
	check(ResourceSaver.save(palette,"user://audio_palette_test.tres") == OK,"custom palette saves as a reusable resource")
	var restored_palette: Resource = load("user://audio_palette_test.tres")
	check(restored_palette.footstep_streams("gravel").size() == 1 and restored_palette.cue("ui_back") == null,"custom palette edits survive reload")
	scene.queue_free()
	await process_frame
	await process_frame
	await _runtime_hot_swap()

func _runtime_hot_swap() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.play_level("forest")
	for i in range(10): await physics_frame
	game.set_paused(true)
	var anchor = game.world.get_node("Sources").get_child(0)
	var original_stream: AudioStream = anchor.sound
	var original_loop: bool = anchor.looped
	var original_gain: float = anchor.gain_db
	var original_budget: int = anchor.reflection_budget
	var before_position: Vector3 = game.player.position
	var before_generation: int = game.level_generation
	var before_buses := AudioServer.bus_count
	var before_other: int = game.sources[1].get_instance_id()
	var new_stream: AudioStream = load("res://assets/library/landmark_waterfall.ogg")
	anchor.sound = new_stream
	anchor.gain_db = -4
	game._flush_emitter_changes()
	check(game.sources[0].get_meta("clip") == "landmark_waterfall" and is_equal_approx(game.sources[0].direct.stream.get_length(),new_stream.get_length()),"a live Inspector stream replacement reaches actual acoustic playback")
	check(game.sources[0]._base_db == -4 and game.sources[0]._suspended and game.paused,"live gain changes preserve paused playback")
	check(AudioServer.bus_count == before_buses and game.sources[1].get_instance_id() == before_other,"swapping one emitter leaves other emitters and audio bus count unchanged")
	check(game.player.position == before_position and game.level_generation == before_generation,"live source edits preserve the listener and environment generation")
	anchor.reflection_budget = 4
	game._flush_emitter_changes()
	check(game.sources[0].reflections.size() == 4 and AudioServer.bus_count == before_buses+4-original_budget,"reflection-budget edits allocate exactly the requested new paths")
	anchor.sound = null
	anchor.looped = false
	game._flush_emitter_changes()
	check(game.sources[0].direct.stream == null and not game.sources[0].direct.playing,"clearing a live intermittent emitter stops its recording")
	game.sources[0].set_meta("next_event",-1.0)
	game.set_paused(false)
	for i in range(8): await physics_frame
	check(game.sources[0].direct.stream == null and not game.sources[0].direct.playing,"a cleared intermittent slot remains silent through event scheduling")
	game.set_paused(true)
	anchor.sound = original_stream
	anchor.looped = original_loop
	anchor.gain_db = original_gain
	anchor.reflection_budget = original_budget
	game._flush_emitter_changes()
	check(AudioServer.bus_count == before_buses and game.level_generation == before_generation,"restoring a live emitter releases temporary buses without restarting the level")
	var runtime_palette: Resource = load("res://resources/audio/default_palette.tres").duplicate(true)
	game.sound_palette = runtime_palette
	var surface: String = game.surface_at(game.player.position)
	var one_stream: AudioStream = load("res://assets/library/gravel0.wav")
	var only_one: Array[AudioStream] = [one_stream]
	runtime_palette.set(surface+"_footsteps",only_one)
	var steps_before: int = game.steps
	for i in range(5): game._play_footfall(false)
	check(game.steps == steps_before+5 and game.last_step_clip == "gravel0.wav","replacing a live footstep array with one recording safely rebuilds the shuffle bag")
	var no_steps: Array[AudioStream] = []
	runtime_palette.set(surface+"_footsteps",no_steps)
	steps_before = game.steps
	game._play_footfall(false)
	check(game.steps == steps_before,"clearing a live footstep array silences footsteps without an invalid index")
	runtime_palette.punch_swing = one_stream
	game._action("punch_swing.wav",game.player.position)
	check(game.action_sound.direct.stream is AudioStreamWAV and game.action_sound.direct.stream.data == one_stream.data,"action playback uses the live palette resource")
	runtime_palette.punch_swing = null
	game._action("punch_swing.wav",game.player.position)
	check(not game.action_sound.direct.playing,"clearing an action cue stops its playback")
	game.set_paused(true)
	runtime_palette.ui_move_variants = no_steps
	runtime_palette.ui_move = one_stream
	game.ui_last_msec = -1000
	game.play_ui("move")
	check(game.ui_player.stream == one_stream,"native menu playback uses the live palette resource")
	runtime_palette.ui_move = null
	game.ui_last_msec = -1000
	game.play_ui("move")
	check(not game.ui_player.playing,"clearing a menu cue stops its playback")
	game._command("menu")
	game.queue_free()
	await process_frame
	game = null
	for i in range(4): await physics_frame
	await create_timer(.15).timeout

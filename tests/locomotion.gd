extends SceneTree
## Real input and physics integration for scene-backed exploration.
## Run: godot_console --headless --path . --script tests/locomotion.gd

var game
var failures: Array[String] = []
var forest_spawn := Vector3.ZERO

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition: print("PASS ", message)
	else:
		failures.append(message)
		push_error(message)

func frames(count: int) -> void:
	for i in range(count): await physics_frame

func reset_position(pos := Vector3.INF) -> void:
	for action in ["forward","back","left","right","run_hold","jump","punch"]:
		Input.action_release(action)
	if pos == Vector3.INF: pos = game.world.get_node("Spawn").global_position
	game.player.global_position = pos
	game.player.rotation = Vector3.ZERO
	game.player.velocity = Vector3.ZERO
	await frames(8)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.native_audio_enabled = false # Exercise the retained portable geometry/mixer regression path.
	root.add_child(game)
	await frames(3)
	check(game.game_ui is CanvasLayer, "menus are rendered inside Godot")
	check(game.game_ui.screen == "main", "native main menu is initial screen")
	for id in ["forest","cistern","freighter","courtyard"]:
		game.play_level(id)
		await frames(5)
		check(game.world.scene_file_path.ends_with(id + ".tscn"), id + " instantiates its editable scene")
		check(game.sources.size() >= 3, id + " supplies multiple acoustic sources")
		check(game.foot_pool.size() == 3, id + " has three overlapping footstep voices")
	game.play_level("forest")
	await frames(8)
	forest_spawn = game.world.get_node("Spawn").global_position
	var map_before: Dictionary = game.map_data.duplicate(true)
	await reset_position()
	var begin: Vector3 = game.player.position
	Input.action_press("forward")
	await frames(65)
	Input.action_release("forward")
	await frames(10)
	var walking_distance: float = begin.distance_to(game.player.position)
	await reset_position()
	begin = game.player.position
	Input.action_press("run_hold")
	Input.action_press("forward")
	await frames(65)
	check(game.locomotion == "run", "run input selects running locomotion")
	Input.action_release("run_hold")
	Input.action_release("forward")
	await frames(10)
	var running_distance: float = begin.distance_to(game.player.position)
	check(running_distance > walking_distance * 1.35, "running moves faster than walking")
	check(game.map_data == map_before, "environment plan stays independent of player position")
	await reset_position()
	var jumps_before: int = game.jumps
	var landings_before: int = game.landings
	Input.action_press("forward")
	Input.action_press("jump")
	await frames(8)
	check(not game.player.is_on_floor(), "jump lifts the real collision body")
	check(game.locomotion == "air", "airborne locomotion is explicit")
	var airborne_steps: int = game.steps
	await frames(8)
	check(not game.player.is_on_floor(), "jump remains airborne during ascent")
	check(game.steps == airborne_steps, "walking footsteps do not play in the air")
	await frames(110)
	check(game.jumps == jumps_before + 1, "holding jump does not chain jumps")
	check(game.landings == landings_before + 1, "one jump produces one landing")
	Input.action_release("jump")
	Input.action_release("forward")
	await reset_position()
	var target: int = game.steps + 35
	Input.action_press("run_hold")
	Input.action_press("forward")
	var guard := 0
	while game.steps < target and guard < 1300:
		await frames(1)
		guard += 1
		# Keep this endurance test on one open trail surface, inside the real level.
		if game.player.global_position.z < forest_spawn.z - 12:
			game.player.global_position.z = forest_spawn.z
	Input.action_release("forward")
	Input.action_release("run_hold")
	check(game.steps >= target, "continuous travel produces at least 35 recorded footfalls")
	var variants := {}
	var pitches := {}
	var gains := {}
	var strides := {}
	for step in game.step_history:
		variants[step.clip] = true
		pitches[step.pitch] = true
		gains[step.gain] = true
		strides[step.stride] = true
	check(variants.size() > 4, "footsteps use more than four distinct recordings")
	check(pitches.size() > 1 and gains.size() > 1 and strides.size() > 1, "footsteps vary timbre, force, and stride length")
	check(game.step_history.size() <= 32, "footstep diagnostics stay bounded")
	game.play_level("cistern")
	await frames(8)
	# Expanded cistern: stand just east of ChamberWeast1 and face its stone wall.
	await reset_position(Vector3(-3.6, 1, 10))
	game.player.rotation.y = PI / 2
	var punches_before: int = game.punches
	Input.action_press("punch")
	await frames(4)
	Input.action_release("punch")
	check(game.punches == punches_before + 1, "punch input works beside real scene geometry")
	check(game.last_event == "punch_stone", "nearby stone geometry selects a stone impact recording")
	game.set_paused(true)
	begin = game.player.position
	var paused_steps: int = game.steps
	Input.action_press("forward")
	Input.action_press("jump")
	Input.action_press("punch")
	await frames(20)
	check(game.player.position == begin and game.steps == paused_steps, "pause blocks movement and footsteps")
	Input.action_release("forward")
	Input.action_release("jump")
	Input.action_release("punch")
	game._command("menu")
	await frames(2)
	game.queue_free()
	await process_frame
	game = null
	await frames(4)
	await create_timer(0.1).timeout
	if failures.is_empty(): print("ALL LOCOMOTION INTEGRATION CHECKS PASSED")
	else: print("FAILED: ", failures)
	quit(0 if failures.is_empty() else 1)

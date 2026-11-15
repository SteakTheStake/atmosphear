extends SceneTree
## Native input-event integration. Browser activation is tested separately.
var game
var checks := 0
var failures: Array[String] = []
var controller_device := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: print("PASS ",message)
	else:
		failures.append(message)
		push_error(message)

func frames(count := 3) -> void:
	for i in range(count): await process_frame

func button(index: int, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = controller_device
	event.button_index = index
	event.pressed = pressed
	Input.parse_input_event(event)

func tap(index: int) -> void:
	button(index,true)
	await frames()
	button(index,false)
	await frames()

func axis(index: int, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = controller_device
	event.axis = index
	event.axis_value = value
	Input.parse_input_event(event)
	await frames()

func focus_index() -> int:
	return game.game_ui.focus_state().index

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.native_audio_enabled = OS.get_cmdline_user_args().has("--native")
	root.add_child(game)
	await frames(5)
	var original_settings: Dictionary = game.settings.duplicate()
	var ui = game.game_ui
	await tap(JOY_BUTTON_A)
	check(game.level=="template" and game.world.scene_file_path==game.main_level.resource_path,"first main-menu choice loads the Inspector-selected main scene")
	game._command("menu")
	await frames()
	check(game.host_input_ready and focus_index()==0,"native startup focuses first environment")
	for action in ["left","right","forward","back","turn_left","turn_right","run_hold","run_toggle","jump","punch","pause","debug_toggle"]:
		var all_match := true
		for binding in InputMap.action_get_events(action):
			if binding is InputEventJoypadButton or binding is InputEventJoypadMotion:
				var event: InputEvent = binding.duplicate()
				event.device = 1
				if event is InputEventJoypadButton: event.pressed = true
				all_match = all_match and event.is_action_pressed(action)
		check(all_match,"controller index 1 matches "+action+" action")
	game.host_input_ready = false
	await tap(JOY_BUTTON_DPAD_DOWN)
	await tap(JOY_BUTTON_A)
	await tap(JOY_BUTTON_START)
	check(not game.started and focus_index()==0,"host startup gate blocks navigation, activation, and Start")
	game._command("host:ready")
	await frames()
	await tap(JOY_BUTTON_DPAD_DOWN)
	await tap(JOY_BUTTON_A)
	check(ui.screen=="legacy","Legacy submenu retains the original environments")
	await axis(JOY_AXIS_LEFT_Y,.2)
	check(focus_index()==0,"small stick drift does not move menu focus")
	await axis(JOY_AXIS_LEFT_Y,.8)
	check(focus_index()==1,"left stick moves one row on initial edge")
	await axis(JOY_AXIS_LEFT_Y,.46)
	check(focus_index()==1,"stick hysteresis does not duplicate a navigation edge")
	await axis(JOY_AXIS_LEFT_Y,0)
	await tap(JOY_BUTTON_DPAD_DOWN)
	check(focus_index()==2,"D-pad moves exactly one row per tap")
	button(JOY_BUTTON_DPAD_DOWN,true)
	await frames()
	check(focus_index()==3,"held D-pad begins with one move")
	ui._process(.41)
	check(focus_index()==4,"held D-pad repeats after initial delay")
	await tap(JOY_BUTTON_A)
	check(ui.screen=="settings" and focus_index()==0,"controller opens settings with initial slider focused")
	ui._process(.7)
	check(focus_index()==0,"held navigation does not carry into a new menu")
	button(JOY_BUTTON_DPAD_DOWN,false)
	await frames()
	for index in range(6):
		var control: Range = ui.focus_items[index]
		var before: float = control.value
		var direction := JOY_BUTTON_DPAD_RIGHT if before < control.max_value else JOY_BUTTON_DPAD_LEFT
		await tap(direction)
		check(control.value!=before and focus_index()==index,"controller adjusts slider "+str(control.get_meta("setting_key")))
		await tap(JOY_BUTTON_DPAD_DOWN)
	var quality: float = game.settings.quality
	await tap(JOY_BUTTON_A)
	check(game.settings.quality!=quality and focus_index()==6,"A toggles full acoustic detail once")
	await tap(JOY_BUTTON_DPAD_RIGHT)
	check(game.settings.quality==(2.0 if game.native_audio != null else 1.0),"right direction enables the highest supported acoustic quality")
	await tap(JOY_BUTTON_DPAD_DOWN)
	await tap(JOY_BUTTON_A)
	check(game.debug_enabled and focus_index()==7,"A operates developer geometry toggle")
	await tap(JOY_BUTTON_DPAD_LEFT)
	check(not game.debug_enabled,"left direction disables a focused toggle")
	await tap(JOY_BUTTON_DPAD_DOWN)
	var done_index := 8
	if game.native_audio != null:
		check(focus_index()==8,"native HRTF headphone setting is controller-accessible")
		var before_binaural: float = game.settings.binaural
		await tap(JOY_BUTTON_A)
		check(game.settings.binaural != before_binaural,"native HRTF can switch to speaker panning")
		await tap(JOY_BUTTON_A)
		check(game.settings.binaural == before_binaural,"native HRTF headphone preference restores")
		await tap(JOY_BUTTON_DPAD_DOWN)
		done_index = 9
	check(focus_index()==done_index,"Done remains reachable after native audio settings")
	root.gui_release_focus()
	await frames()
	check(focus_index()==done_index,"lost focus recovers the last selected control")
	game._controller_connection_changed(0,true)
	await frames()
	check(focus_index()==done_index,"controller reconnect preserves usable menu focus")
	await tap(JOY_BUTTON_A)
	check(ui.screen=="legacy" and focus_index()==0,"Done returns to main menu")
	button(JOY_BUTTON_A,true)
	await create_timer(.5).timeout
	check(game.started and ui.screen=="playing" and game.jumps==0,"held menu confirmation starts a walk without jumping")
	button(JOY_BUTTON_A,false)
	await frames()
	await tap(JOY_BUTTON_START)
	check(game.paused and ui.screen=="pause" and focus_index()==0,"Start pauses with Resume focused")
	await tap(JOY_BUTTON_DPAD_DOWN)
	await tap(JOY_BUTTON_A)
	check(ui.screen=="settings","controller opens in-game settings")
	await tap(JOY_BUTTON_START)
	check(not game.paused and ui.screen=="playing","Start resumes directly from nested settings")
	game._controller_connection_changed(0,false)
	await frames()
	check(game.paused and ui.screen=="pause","disconnect pauses active exploration")
	controller_device = 1
	game._controller_connection_changed(controller_device,true)
	await frames()
	await tap(JOY_BUTTON_START)
	check(not game.paused,"reconnected controller index 1 Start resumes exploration")
	var before_reconnected_move: Vector3 = game.player.position
	await axis(JOY_AXIS_LEFT_Y,-1)
	for i in range(24): await physics_frame
	await axis(JOY_AXIS_LEFT_Y,0)
	check(game.player.position.z < before_reconnected_move.z-.25,"controller index 1 moves the real player")
	await tap(JOY_BUTTON_START)
	check(game.paused,"controller index 1 Start pauses exploration")
	await tap(JOY_BUTTON_A)
	check(not game.paused,"reconnected controller resumes exploration")
	await tap(JOY_BUTTON_START)
	await tap(JOY_BUTTON_DPAD_DOWN)
	await tap(JOY_BUTTON_DPAD_DOWN)
	await tap(JOY_BUTTON_A)
	check(ui.screen=="main" and game.paused,"Change environment opens controller-selectable level list")
	await tap(JOY_BUTTON_B)
	check(ui.screen=="pause" and game.paused,"B from environment chooser returns one menu level")
	await tap(JOY_BUTTON_B)
	check(ui.screen=="playing" and not game.paused,"B from pause resumes the walk")
	for level_index in range(1,4):
		await tap(JOY_BUTTON_START)
		await tap(JOY_BUTTON_DPAD_DOWN)
		await tap(JOY_BUTTON_DPAD_DOWN)
		await tap(JOY_BUTTON_A)
		await tap(JOY_BUTTON_DPAD_DOWN)
		await tap(JOY_BUTTON_A)
		for i in range(level_index): await tap(JOY_BUTTON_DPAD_DOWN)
		await tap(JOY_BUTTON_A)
		check(game.level==game.LEGACY_TITLES.keys()[level_index] and not game.paused,"controller loads "+game.LEGACY_TITLES.keys()[level_index])
	await tap(JOY_BUTTON_START)
	# Up wraps from Resume to Main menu.
	await tap(JOY_BUTTON_DPAD_UP)
	await tap(JOY_BUTTON_A)
	check(not game.started and ui.screen=="main" and focus_index()==0,"controller returns to initial main menu")
	game.settings = original_settings
	game._save_settings()
	game._clear_world()
	game.queue_free()
	await process_frame
	game = null
	ui = null
	await frames(4)
	await create_timer(.15).timeout
	print("CONTROLLER UI: ",checks-failures.size(),"/",checks," passed")
	quit(0 if failures.is_empty() else 1)

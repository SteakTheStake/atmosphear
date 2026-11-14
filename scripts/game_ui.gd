extends CanvasLayer
## Native focus navigation and a fixed environment plan. The plan never reads the player.
var game
var screen := "main"
var root: Control
var background: ColorRect
var panel: PanelContainer
var scroll: ScrollContainer
var content: VBoxContainer
var map_view: Control
var map_visible := true
var back_screen := "main"
var focus_items: Array[Control] = []
var suppress_focus_sound := false
var setting_labels: Array[Label] = []
var last_focus_index := 0
var controller_device := -1
var controller_stick := Vector2.ZERO
var controller_dpad := Vector2i.ZERO
var controller_direction := Vector2i.ZERO
var controller_repeat := 0.0
var controller_wait_neutral := false
const MENU_PRESS_THRESHOLD := 0.55
const MENU_RELEASE_THRESHOLD := 0.35
const MENU_REPEAT_DELAY := 0.4
const MENU_REPEAT_INTERVAL := 0.13

class EnvironmentPlan extends Control:
	var data: Dictionary = {}
	var title := ""
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)
	func _draw() -> void:
		if data.is_empty(): return
		var font := ThemeDB.fallback_font
		var area := Rect2(Vector2(35,35),size-Vector2(70,70))
		draw_style_box(_card(),area)
		draw_string(font,area.position+Vector2(25,36),title,HORIZONTAL_ALIGNMENT_LEFT,-1,28,Color("e0e8d8"))
		draw_string(font,area.position+Vector2(25,60),"ENVIRONMENT PLAN",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("93a486"))
		var bounds: Rect2 = data.get("bounds",Rect2(-20,-20,40,40))
		var narrow := area.size.x < 650
		var map_area := Rect2(area.position+Vector2(25,90),Vector2(area.size.x-50,area.size.y*.48) if narrow else Vector2(area.size.x*0.64,area.size.y-145))
		var scale_factor := minf(map_area.size.x/maxf(bounds.size.x,1),map_area.size.y/maxf(bounds.size.y,1))
		var drawn_size := bounds.size*scale_factor
		var origin := map_area.position+(map_area.size-drawn_size)*0.5
		draw_rect(Rect2(origin,drawn_size),Color("0b100a"))
		for footprint in data.get("footprints",[]):
			if not footprint is Rect2: continue
			var shape: Rect2 = footprint
			draw_rect(Rect2(origin+(shape.position-bounds.position)*scale_factor,shape.size*scale_factor),Color("4b5941"))
		draw_rect(Rect2(origin,drawn_size),Color("7c8d6c"),false,1)
		var legend_x := area.position.x+25 if narrow else area.position.x+area.size.x*0.71
		var legend_y := map_area.end.y+55 if narrow else area.position.y+117
		draw_string(font,Vector2(legend_x,legend_y-24),"LANDMARKS",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("93a486"))
		var index := 0
		for landmark in data.get("landmarks",[]):
			index += 1
			var p: Vector3 = landmark.get("pos",Vector3.ZERO)
			var mark := origin+(Vector2(p.x,p.z)-bounds.position)*scale_factor
			var color := Color("b7cce3") if landmark.get("kind","") == "water" else Color("d6d0a6")
			draw_circle(mark,10,color)
			draw_string(font,mark+Vector2(-4.5,5),str(index),HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("11180e"))
			draw_circle(Vector2(legend_x+8,legend_y-5),9,color)
			draw_string(font,Vector2(legend_x+3.5,legend_y),str(index),HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("11180e"))
			draw_string(font,Vector2(legend_x+27,legend_y),str(landmark.get("label","Landmark")),HORIZONTAL_ALIGNMENT_LEFT,area.end.x-legend_x-46,16,Color("d9e1cf"))
			legend_y += 37
		draw_rect(Rect2(Vector2(legend_x,legend_y+17),Vector2(15,9)),Color("4b5941"))
		draw_string(font,Vector2(legend_x+24,legend_y+26),"Walls and objects",HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("a1b18f"))
		draw_string(font,area.position+Vector2(25,area.size.y-22),"M / top face button: hide plan     Â·     Menu / Esc: pause",HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("a1b18f"))
	func _card() -> StyleBoxFlat:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("11170fee")
		style.border_color = Color("3a4732")
		style.set_border_width_all(1)
		return style

func configure(owner_game) -> void:
	game = owner_game
	layer = 20
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	background = ColorRect.new()
	background.color = Color("10150e")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	var theme := Theme.new()
	theme.default_font_size = 18
	for kind in ["normal","hover","pressed","focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("202a19") if kind in ["hover","focus"] else Color("151d10")
		style.border_color = Color("cadab0") if kind == "focus" else Color("46563a")
		style.set_border_width_all(2 if kind == "focus" else 1)
		style.content_margin_left = 18
		style.content_margin_right = 18
		style.content_margin_top = 10
		style.content_margin_bottom = 10
		theme.set_stylebox(kind,"Button",style)
	theme.set_color("font_color","Button",Color("e0e9d7"))
	root.theme = theme
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 80
	panel.offset_right = -80
	panel.offset_top = 32
	panel.offset_bottom = -32
	var transparent := StyleBoxEmpty.new()
	panel.add_theme_stylebox_override("panel",transparent)
	root.add_child(panel)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.focus_mode = Control.FOCUS_NONE
	panel.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",9)
	scroll.add_child(content)
	map_view = EnvironmentPlan.new()
	map_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(map_view)
	get_viewport().size_changed.connect(_fit_panel)
	_fit_panel()
	show_screen("main")

func _fit_panel() -> void:
	var width := get_viewport().get_visible_rect().size.x
	var margin := clampf(width*0.07,18,80)
	panel.offset_left = margin
	panel.offset_right = -margin
	for label in setting_labels:
		if is_instance_valid(label): label.custom_minimum_size.x = clampf(width*0.23,110,240)

func _label(text: String, font_size := 16, color := Color("dce7d1")) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	content.add_child(label)
	return label

func _sound(kind: String) -> void:
	if is_instance_valid(game) and game.has_method("play_ui"): game.play_ui(kind)

func _focus(control: Control) -> void:
	focus_items.append(control)
	control.focus_entered.connect(func():
		last_focus_index = focus_items.find(control)
		if not suppress_focus_sound: _sound("move")
	)

func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 43
	button.pressed.connect(func():
		_sound("accept")
		action.call()
	)
	content.add_child(button)
	_focus(button)
	return button

func show_screen(next: String) -> void:
	screen = next
	last_focus_index = 0
	# A held navigation direction must not carry into the next menu.
	controller_wait_neutral = controller_stick.length() > MENU_RELEASE_THRESHOLD or controller_dpad != Vector2i.ZERO
	controller_direction = Vector2i.ZERO
	controller_repeat = 0.0
	background.visible = next != "playing"
	panel.visible = next != "playing"
	refresh_map_visibility()
	if next == "playing":
		map_view.data = game.map_data.duplicate(true)
		map_view.title = game.level_title(game.level)
		map_view.queue_redraw()
		get_viewport().gui_release_focus()
		return
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	focus_items.clear()
	setting_labels.clear()
	_label("ATMOSPHEAR",13,Color("9eaf8c"))
	match next:
		"main":
			_label("Choose somewhere to wander.",32)
			_button(game.main_level_title,func(): game._command("play:template"))
			_button("Legacy environments",func(): show_screen("legacy"))
			_button("Settings",func(): back_screen="main";show_screen("settings"))
			if game.started: _button("Back to this walk",func(): game._command("resume"))
		"legacy":
			_label("Legacy environments",32)
			for id in game.LEGACY_TITLES:
				_button(game.LEGACY_TITLES[id],func(): game._command("play:"+id))
			_button("Settings",func(): back_screen="legacy";show_screen("settings"))
			if game.started: _button("Back to this walk",func(): game._command("resume"))
			_button("Back to main menu",func(): show_screen("main"))
		"pause":
			_label("Take your time.",32)
			_label(game.level_title(game.level),17,Color("a7b59a"))
			_button("Resume exploring",func(): game._command("resume"))
			_button("Settings",func(): back_screen="pause";show_screen("settings"))
			_button("Change environment",func(): show_screen("main"))
			_button("Start this walk again",func(): game._command("restart"))
			_button("Main menu",func(): game._command("menu"))
		"settings":
			_label("Your pace.",32)
			for entry in [["master","Master volume",0.0,1.0,.05],["ambience","Environment volume",0.0,1.0,.05],["footsteps","Footstep volume",0.0,1.0,.05],["ui","Menu feedback volume",0.0,1.0,.05],["sensitivity","Turning sensitivity",.5,2.0,.1],["speed","Walking pace",.5,1.5,.1]]:
				_slider(entry)
			var quality := CheckButton.new()
			quality.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			quality.text = "Full acoustic detail"
			quality.button_pressed = game.settings.quality > 0
			quality.toggled.connect(func(value): _sound("move");game._command("setting:quality:"+("1" if value else "0")))
			content.add_child(quality)
			_focus(quality)
			var debug := CheckButton.new()
			debug.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			debug.text = "Developer acoustic geometry (F3 / right-stick click)"
			debug.button_pressed = game.debug_enabled
			debug.toggled.connect(func(value): _sound("accept");game._command("debug:on" if value else "debug:off"))
			content.add_child(debug)
			_focus(debug)
			var binaural := CheckButton.new()
			binaural.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			binaural.text = "Headphone binaural audio (off for speakers)"
			binaural.button_pressed = game.settings.get("binaural",1.0) > .5
			binaural.toggled.connect(func(on): game._command("setting:binaural:"+str(1 if on else 0)); _sound("accept"))
			content.add_child(binaural)
			_focus(binaural)
			_button("Done",go_back)
	_label("Walk: left stick / WASD     Turn: right stick / arrows     Run: LB / Shift or L3 toggle",15,Color("9eaf8c"))
	_label("Jump: bottom button / Space     Punch: left button / E / RT     Plan: top button / M     Pause: Menu / Esc",14,Color("9eaf8c"))
	_label("Menus: left stick / D-pad to choose; left / right to adjust. Bottom button: select. Right button: back.",14,Color("879c76"))
	for i in range(focus_items.size()):
		var item := focus_items[i]
		item.focus_neighbor_top = item.get_path_to(focus_items[wrapi(i-1,0,focus_items.size())])
		item.focus_neighbor_bottom = item.get_path_to(focus_items[(i+1)%focus_items.size()])
		item.focus_previous = item.focus_neighbor_top
		item.focus_next = item.focus_neighbor_bottom
		# Horizontal input belongs to the focused slider or toggle, never another row.
		item.focus_neighbor_left = NodePath(".")
		item.focus_neighbor_right = NodePath(".")
	call_deferred("_initial_focus")

func refresh_map_visibility() -> void:
	if is_instance_valid(map_view):
		map_view.visible = screen == "playing" and map_visible and not bool(game.debug_enabled)

func _initial_focus() -> void:
	ensure_focus()

func ensure_focus() -> void:
	if screen == "playing" or focus_items.is_empty() or not game.host_input_ready: return
	if focus_items.has(get_viewport().gui_get_focus_owner()): return
	suppress_focus_sound = true
	focus_items[clampi(last_focus_index,0,focus_items.size()-1)].grab_focus()
	suppress_focus_sound = false

func focus_state() -> Dictionary:
	var current := get_viewport().gui_get_focus_owner()
	var index := focus_items.find(current)
	var text := ""
	if current is BaseButton: text = current.text
	elif current is Range: text = str(current.get_meta("setting_key",""))
	return {"index":index,"text":text,"count":focus_items.size() if screen != "playing" else 0}

func _slider(entry: Array) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 36
	content.add_child(row)
	var name_label := Label.new()
	name_label.text = entry[1]
	name_label.custom_minimum_size.x = clampf(get_viewport().get_visible_rect().size.x*0.23,110,240)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	setting_labels.append(name_label)
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = entry[2]
	slider.max_value = entry[3]
	slider.step = entry[4]
	slider.value = game.settings[entry[0]]
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size.x = 70
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	var key: String = entry[0]
	slider.set_meta("setting_key",key)
	var format_value := func(value):
		value_label.text = ("%.1fx" % value) if key in ["sensitivity","speed"] else ("%d%%" % roundi(value*100))
	format_value.call(slider.value)
	slider.value_changed.connect(func(value):
		format_value.call(value)
		_sound("move")
		game._command("setting:"+key+":"+str(value))
	)
	_focus(slider)

func go_back() -> void:
	_sound("back")
	if screen == "settings": show_screen(back_screen)
	elif screen == "legacy": show_screen("main")
	elif screen == "main" and game.started: show_screen("pause")
	elif game.started: game._command("resume")
	else: show_screen("main")

func _input(event: InputEvent) -> void:
	# The browser owns the launch gesture until audio is running and it is released.
	if not game.host_input_ready:
		get_viewport().set_input_as_handled()
		return
	if screen == "playing": return
	if event is InputEventJoypadMotion:
		if event.axis not in [JOY_AXIS_LEFT_X,JOY_AXIS_LEFT_Y]: return
		get_viewport().set_input_as_handled()
		_use_controller(event.device)
		if event.axis == JOY_AXIS_LEFT_X: controller_stick.x = event.axis_value
		else: controller_stick.y = event.axis_value
		_update_controller_direction()
		return
	if not event is InputEventJoypadButton: return
	if not event.button_index in [JOY_BUTTON_A,JOY_BUTTON_B,JOY_BUTTON_DPAD_UP,JOY_BUTTON_DPAD_DOWN,JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_RIGHT]: return
	get_viewport().set_input_as_handled()
	_use_controller(event.device)
	match event.button_index:
		JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN:
			var direction := -1 if event.button_index == JOY_BUTTON_DPAD_UP else 1
			if event.pressed: controller_dpad.y = direction
			elif controller_dpad.y == direction: controller_dpad.y = 0
			_update_controller_direction()
		JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT:
			var direction := -1 if event.button_index == JOY_BUTTON_DPAD_LEFT else 1
			if event.pressed: controller_dpad.x = direction
			elif controller_dpad.x == direction: controller_dpad.x = 0
			_update_controller_direction()
		JOY_BUTTON_A:
			if event.pressed:
				ensure_focus()
				var current := get_viewport().gui_get_focus_owner()
				if current is BaseButton and not current.disabled:
					if current.toggle_mode: current.button_pressed = not current.button_pressed
					current.pressed.emit()
		JOY_BUTTON_B:
			if event.pressed: go_back()

func _use_controller(device: int) -> void:
	if controller_device == device: return
	reset_controller_navigation()
	controller_device = device

func reset_controller_navigation() -> void:
	controller_device = -1
	controller_stick = Vector2.ZERO
	controller_dpad = Vector2i.ZERO
	controller_direction = Vector2i.ZERO
	controller_repeat = 0.0
	controller_wait_neutral = false
	call_deferred("ensure_focus")

func _update_controller_direction() -> void:
	var raw := Vector2(controller_dpad) if controller_dpad != Vector2i.ZERO else controller_stick
	if controller_wait_neutral:
		if raw.length() <= MENU_RELEASE_THRESHOLD: controller_wait_neutral = false
		return
	var threshold := MENU_RELEASE_THRESHOLD if controller_direction != Vector2i.ZERO else MENU_PRESS_THRESHOLD
	var next := Vector2i.ZERO
	if maxf(absf(raw.x),absf(raw.y)) >= threshold:
		# Dominant-axis navigation avoids double steps when the stick is diagonal.
		if absf(raw.y) >= absf(raw.x): next.y = 1 if raw.y > 0 else -1
		else: next.x = 1 if raw.x > 0 else -1
	if next == controller_direction: return
	controller_direction = next
	controller_repeat = MENU_REPEAT_DELAY
	if next != Vector2i.ZERO: _navigate(next)

func _navigate(direction: Vector2i) -> void:
	ensure_focus()
	if focus_items.is_empty(): return
	var current := get_viewport().gui_get_focus_owner()
	var index := focus_items.find(current)
	if direction.y != 0:
		focus_items[wrapi(index+direction.y,0,focus_items.size())].grab_focus()
	elif current is Range:
		current.value += current.step*direction.x
	elif current is BaseButton and current.toggle_mode:
		current.button_pressed = direction.x > 0

func _process(delta: float) -> void:
	if not is_instance_valid(game) or not game.host_input_ready or screen == "playing": return
	ensure_focus()
	if controller_direction == Vector2i.ZERO or controller_wait_neutral: return
	controller_repeat -= delta
	if controller_repeat <= 0:
		controller_repeat = MENU_REPEAT_INTERVAL
		_navigate(controller_direction)

func _unhandled_input(event: InputEvent) -> void:
	if screen == "playing":
		if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B:
			game.set_paused(true)
			get_viewport().set_input_as_handled()
			return
		var toggle: bool = (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_M) or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_Y)
		if toggle:
			map_visible = not map_visible
			refresh_map_visibility()
			_sound("move")
			get_viewport().set_input_as_handled()

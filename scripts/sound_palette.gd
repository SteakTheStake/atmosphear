@tool
class_name AtmoSoundPalette
extends Resource
## Shared, Inspector-editable recordings for footsteps, physical actions and menus.

var _watched_streams: Array[AudioStream] = []

@export_group("Footsteps")
@export var gravel_footsteps: Array[AudioStream] = []:
	set(value):
		gravel_footsteps = value
		_palette_edited()
@export var stone_footsteps: Array[AudioStream] = []:
	set(value):
		stone_footsteps = value
		_palette_edited()
@export var wood_footsteps: Array[AudioStream] = []:
	set(value):
		wood_footsteps = value
		_palette_edited()
@export var metal_footsteps: Array[AudioStream] = []:
	set(value):
		metal_footsteps = value
		_palette_edited()

@export_group("Physical Actions")
@export var punch_swing: AudioStream:
	set(value):
		punch_swing = value
		_palette_edited()
@export var punch_stone: AudioStream:
	set(value):
		punch_stone = value
		_palette_edited()
@export var punch_wood: AudioStream:
	set(value):
		punch_wood = value
		_palette_edited()
@export var punch_metal: AudioStream:
	set(value):
		punch_metal = value
		_palette_edited()
@export var jump_takeoff: AudioStream:
	set(value):
		jump_takeoff = value
		_palette_edited()

@export_group("Menu Feedback")
@export var ui_move: AudioStream:
	set(value):
		ui_move = value
		_palette_edited()
@export var ui_accept: AudioStream:
	set(value):
		ui_accept = value
		_palette_edited()
@export var ui_back: AudioStream:
	set(value):
		ui_back = value
		_palette_edited()
@export var ui_move_variants: Array[AudioStream] = []:
	set(value):
		ui_move_variants = value
		_palette_edited()
@export var ui_accept_variants: Array[AudioStream] = []:
	set(value):
		ui_accept_variants = value
		_palette_edited()
@export var ui_back_variants: Array[AudioStream] = []:
	set(value):
		ui_back_variants = value
		_palette_edited()

func footstep_streams(surface: String) -> Array[AudioStream]:
	var streams: Array[AudioStream] = {
		"gravel":gravel_footsteps,"stone":stone_footsteps,
		"wood":wood_footsteps,"metal":metal_footsteps,
	}.get(surface,stone_footsteps)
	# Empty slots are allowed while editing; they are not playable footfalls.
	var playable: Array[AudioStream] = []
	for stream in streams:
		if stream != null: playable.append(stream)
	return playable

func cue(cue_name: String) -> AudioStream:
	return {
		"punch_swing":punch_swing,"punch_stone":punch_stone,
		"punch_wood":punch_wood,"punch_metal":punch_metal,
		"jump_takeoff":jump_takeoff,"ui_move":ui_move,
		"ui_accept":ui_accept,"ui_back":ui_back,
	}.get(cue_name.get_file().get_basename(),null)

func cue_streams(cue_name: String) -> Array[AudioStream]:
	var primary := cue(cue_name)
	var pool: Array[AudioStream] = []
	if primary == null: return pool
	pool.append(primary)
	var extra: Array = {"ui_move":ui_move_variants,"ui_accept":ui_accept_variants,"ui_back":ui_back_variants}.get(cue_name,[])
	for stream in extra:
		if stream != null and not pool.has(stream): pool.append(stream)
	return pool

func _palette_edited() -> void:
	for stream in _watched_streams:
		if is_instance_valid(stream) and stream.changed.is_connected(_stream_edited):
			stream.changed.disconnect(_stream_edited)
	_watched_streams.clear()
	var streams: Array = []
	for surface in ["gravel","stone","wood","metal"]:
		streams.append_array(footstep_streams(surface))
	for name in ["punch_swing","punch_stone","punch_wood","punch_metal","jump_takeoff","ui_move","ui_accept","ui_back"]:
		streams.append_array(cue_streams(name))
	for stream in streams:
		if stream != null and not _watched_streams.has(stream):
			_watched_streams.append(stream)
			stream.changed.connect(_stream_edited)
	emit_changed()

func _stream_edited() -> void:
	emit_changed()

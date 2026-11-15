@tool
class_name AtmoSoundEmitter
extends Marker3D
## A positioned, drag-and-drop sound source. The game supplies spatial acoustics.
## Inspector preview is dry 2D audio and never starts automatically.

signal configuration_changed

var _preview: AudioStreamPlayer
var _watched_variants: Array[AudioStream] = []

@export_group("Recording")
## Drop an imported WAV, Ogg, or MP3 here. Clear it to silence this emitter.
@export var sound: AudioStream:
	set(value):
		if sound == value: return
		if sound != null and sound.changed.is_connected(_recording_changed):
			sound.changed.disconnect(_recording_changed)
		sound = value
		if sound != null and not sound.changed.is_connected(_recording_changed):
			sound.changed.connect(_recording_changed)
		_recording_changed()
## Extra takes of the same sound for intermittent events. Events shuffle the
## primary Sound and these alternatives without adjacent repeats. Loop beds
## keep their assigned recording, avoiding abrupt mid-loop replacements.
@export var sound_variants: Array[AudioStream] = []:
	set(value):
		sound_variants = value
		for stream in _watched_variants:
			if is_instance_valid(stream) and stream.changed.is_connected(_variant_changed):
				stream.changed.disconnect(_variant_changed)
		_watched_variants.clear()
		for stream in sound_variants:
			if stream != null and not _watched_variants.has(stream):
				_watched_variants.append(stream)
				stream.changed.connect(_variant_changed)
		_changed()
@export_range(-60, 12, .5, "suffix:dB") var gain_db := -8.0:
	set(value):
		gain_db = clampf(value,-60,12)
		_changed()
@export var looped := true:
	set(value):
		looped = value
		_changed()
## A recognizable fixed location. Keep Motion at zero for navigation landmarks.
@export var landmark := false:
	set(value):
		landmark = value
		_changed()

@export_group("Spatial Acoustics")
## Automatic enables Doppler only for moving emitters and authored bird paths.
## Diffuse wind, leaves, water beds and stationary landmarks retain stable pitch.
@export_enum("Automatic", "Disabled", "Enabled") var doppler_mode := 0:
	set(value):
		doppler_mode = clampi(value,0,2)
		_changed()
@export_range(0,4,1) var reflection_budget := 1:
	set(value):
		reflection_budget = clampi(value,0,4)
		_changed()
## Beyond this distance the source is silent and its acoustic work is suspended.
@export_range(8,600,.5,"suffix:m") var audible_range := 35.0:
	set(value):
		audible_range = clampf(value,8,600)
		_changed()
## Near-field distance scale for inverse-distance attenuation.
@export_range(1,40,.1,"suffix:m") var near_distance := 2.5:
	set(value):
		near_distance = clampf(value,1,40)
		_changed()

@export_group("Intermittent Timing")
## For non-looping recordings: minimum time between events.
@export_range(.1,180,.1,"suffix:s") var interval_min := 8.0:
	set(value):
		interval_min = maxf(value,.1)
		_changed()
@export_range(.1,180,.1,"suffix:s") var interval_max := 22.0:
	set(value):
		interval_max = maxf(value,.1)
		_changed()

@export_group("Event Variation")
@export_range(.75,1.3,.01) var pitch_min := .98:
	set(value):
		pitch_min = clampf(value,.75,1.3)
		_changed()
@export_range(.75,1.3,.01) var pitch_max := 1.02:
	set(value):
		pitch_max = clampf(value,.75,1.3)
		_changed()
@export_range(0,6,.1,"suffix:dB") var gain_variation_db := 1.5:
	set(value):
		gain_variation_db = clampf(value,0,6)
		_changed()

@export_group("Motion")
## Zero keeps the source fixed. Positive values drive the authored moving-source path.
@export_range(0,2,.01) var motion := 0.0:
	set(value):
		motion = maxf(value,0)
		_changed()

@export_group("Editor Preview")
@export_tool_button("Play recording preview", "Play") var play_preview: Callable = _play_preview
@export_tool_button("Stop preview", "Stop") var stop_preview: Callable = _stop_preview

func configuration() -> Dictionary:
	return {
		"stream":sound,
		"variants":recordings(),
		"clip":sound.resource_path.get_file().get_basename() if sound != null and not sound.resource_path.is_empty() else "",
		"db":gain_db,"loop":looped,"budget":reflection_budget,
		"doppler":doppler_mode==2 or (doppler_mode==0 and (motion>0 or not String(get_meta("bird_path","")).is_empty() or bool(get_meta("managed_event",false)))),
		"range":audible_range,"near":minf(near_distance,audible_range),
		"interval_min":interval_min,"interval_max":maxf(interval_max,interval_min),
		"pitch_min":pitch_min,"pitch_max":maxf(pitch_max,pitch_min),
		"gain_variation_db":gain_variation_db,"motion":motion,"landmark":landmark,
	}

func recordings() -> Array[AudioStream]:
	var pool: Array[AudioStream] = []
	# Clearing the primary Sound always silences the whole emitter.
	if sound == null: return pool
	pool.append(sound)
	for stream in sound_variants:
		if stream != null and not pool.has(stream): pool.append(stream)
	return pool

func _variant_changed() -> void:
	_changed()

## Used by the one-time migration and authoring helper, never by normal playback.
func apply_legacy_configuration(values: Dictionary, recording: AudioStream) -> void:
	sound = recording
	gain_db = float(values.get("db",-8.0))
	looped = bool(values.get("loop",true))
	reflection_budget = int(values.get("budget",1))
	audible_range = float(values.get("range",35.0))
	near_distance = float(values.get("near",2.5))
	interval_min = float(values.get("interval_min",8.0))
	interval_max = float(values.get("interval_max",22.0))
	pitch_min = float(values.get("pitch_min",.98))
	pitch_max = float(values.get("pitch_max",1.02))
	gain_variation_db = float(values.get("gain_variation_db",1.5))
	motion = float(values.get("motion",0.0))
	landmark = bool(values.get("landmark",false))

func _changed() -> void:
	if is_instance_valid(_preview): _preview.volume_db = gain_db
	configuration_changed.emit()

func _recording_changed() -> void:
	_stop_preview()
	_changed()

func _play_preview() -> void:
	if not Engine.is_editor_hint() or sound == null or not is_inside_tree(): return
	if not is_instance_valid(_preview):
		_preview = AudioStreamPlayer.new()
		_preview.name = "EditorSoundPreview"
		_preview.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		add_child(_preview,false,Node.INTERNAL_MODE_BACK)
	var recording := sound.duplicate() as AudioStream
	if recording is AudioStreamOggVorbis or recording is AudioStreamMP3:
		recording.loop = looped
	elif recording is AudioStreamWAV:
		recording.loop_mode = AudioStreamWAV.LOOP_FORWARD if looped else AudioStreamWAV.LOOP_DISABLED
		recording.loop_begin = 0
		recording.loop_end = int(recording.get_length()*recording.mix_rate)
	_preview.stream = recording
	_preview.volume_db = gain_db
	_preview.play()

func _stop_preview() -> void:
	if is_instance_valid(_preview): _preview.stop()

func _exit_tree() -> void:
	_stop_preview()

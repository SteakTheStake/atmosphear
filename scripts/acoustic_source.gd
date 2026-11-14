extends Node3D
## A bounded geometric-acoustics approximation, not a wave solver.
## Direct sound uses pressure-distance falloff, ray obstruction, air absorption,
## and radial Doppler. First/second-order image sources share four early voices.
## Three synchronized late sends feed the shared, wet-only spectral room model.
## This ray model does not solve diffraction, interference or structural vibration.

const SPEED_OF_SOUND := 343.0
const ACOUSTIC_MASK := 2
const RAY_LENGTH := 45.0
const MAX_REFLECTION_COUNT := 16
const MAX_DELAY_MS := 500.0
const MAX_SECOND_ORDER_CANDIDATES := 18
const AcousticProfile = preload("res://scripts/acoustic_material.gd")

var source_velocity := Vector3.ZERO
var diagnostics: Dictionary = {}
var direct: AudioStreamPlayer3D
var direct_filter: AudioEffectLowPassFilter
var direct_equalizer: AudioEffectEQ6
var reflections: Array[AudioStreamPlayer3D] = []
var reflection_filters: Array[AudioEffectLowPassFilter] = []
var reflection_delays: Array[AudioEffectDelay] = []
var reflection_equalizers: Array[AudioEffectEQ6] = []
var late_players: Array[AudioStreamPlayer3D] = []
var _transmission := Vector3.ONE
var _target_transmission := Vector3.ONE
var _diffuse_energy := Vector3.ZERO
var _probe_count := 0
var _visibility_queries := 0
var _bus_names: Array[StringName] = []
var _base_db := -12.0
var _looped := true
var _configured := false
var _suspended := false
var _virtualized := false
var _query_timer := 0.0
var _obstruction := 0.0
var _target_obstruction := 0.0
var _target_cutoff := 18000.0
var _pitch := 1.0
var _paths: Array[Dictionary] = []
var _last_listener := Vector3.ZERO
var _debug_obstruction_samples: Array[Dictionary] = []
var _reflection_budget := 2
var _listener_forward := Vector3.ZERO
var _variation_pitch := 1.0
var _variation_gain_db := 0.0
var _stereo_strength := 0.95
var audible_range := 90.0
var near_distance := 2.5
var _web_audio := OS.has_feature("web")
var _web_clock := 0.0
var _category := "Environment"

func _web_call(method: String, args: Array = []) -> void:
	if not _web_audio: return
	JavaScriptBridge.eval("window.AtmoAcoustics && window.AtmoAcoustics."+method+".apply(window.AtmoAcoustics,"+JSON.stringify([str(get_instance_id())]+args)+")")

func configure(stream: AudioStream, db: float, category: String, looped := true, reflection_budget := 2) -> void:
	assert(not _configured, "Configure each acoustic source only once; use set_stream for pooled footsteps.")
	_category = category
	_base_db = db
	_looped = looped
	_reflection_budget = clampi(reflection_budget, 0, MAX_REFLECTION_COUNT)
	var prefix := "Acoustic_%s_" % get_instance_id()
	var bus := _make_bus(prefix + "direct", category)
	direct_filter = AudioEffectLowPassFilter.new()
	direct_filter.cutoff_hz = 18000.0
	direct_filter.resonance = 0.5
	AudioServer.add_bus_effect(bus, direct_filter)
	direct_equalizer = AudioEffectEQ6.new()
	AudioServer.add_bus_effect(bus, direct_equalizer)
	direct = _make_player(_bus_names[0])
	direct.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	direct.unit_size = 2.5
	direct.max_db = db
	direct.volume_db = db
	# Custom filtering avoids applying two independent distance low-pass models.
	direct.attenuation_filter_cutoff_hz = 20500.0
	var reflection_category := category + "Reflections"
	if AudioServer.get_bus_index(reflection_category) < 0:
		reflection_category = category
	for i in range(_reflection_budget):
		var reflection_bus := _make_bus(prefix + "reflection_%s" % i, reflection_category)
		var lowpass := AudioEffectLowPassFilter.new()
		lowpass.cutoff_hz = 7000.0
		lowpass.resonance = 0.5
		var delay := AudioEffectDelay.new()
		delay.dry = 0.0
		delay.tap1_active = true
		delay.tap1_delay_ms = 20.0
		delay.tap1_level_db = 0.0
		delay.tap1_pan = 0.0
		delay.tap2_active = false
		delay.feedback_active = false
		AudioServer.add_bus_effect(reflection_bus, lowpass)
		var equalizer := AudioEffectEQ6.new()
		AudioServer.add_bus_effect(reflection_bus, equalizer)
		AudioServer.add_bus_effect(reflection_bus, delay)
		var reflection := _make_player(_bus_names[-1])
		reflection.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		reflection.attenuation_filter_cutoff_hz = 20500.0
		reflection.volume_db = -80.0
		reflections.append(reflection)
		reflection_filters.append(lowpass)
		reflection_delays.append(delay)
		reflection_equalizers.append(equalizer)
	_configured = true
	set_stream(stream)
	_query_timer = randf_range(0, 0.1)

func configure_late_reverb(category: String) -> void:
	## The shared buses split the spectrum and contain wet-only reverbs. No
	## private effect buses are needed for these sends; their voices pause directly.
	if not _configured or not late_players.is_empty(): return
	for suffix in ["Low", "Mid", "High"]:
		var bus: String = category + "Late" + suffix
		if AudioServer.get_bus_index(bus) < 0: continue
		var voice := _make_player(StringName(bus))
		voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		voice.attenuation_filter_cutoff_hz = 20500.0
		voice.volume_db = -80.0
		voice.stream = direct.stream
		late_players.append(voice)
		if direct.playing and not _web_audio: voice.play(direct.get_playback_position())
	_apply_suspension()

func _make_bus(label: String, category: String) -> int:
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, label)
	AudioServer.set_bus_send(index, category if AudioServer.get_bus_index(category) >= 0 else "Master")
	_bus_names.append(StringName(label))
	return index

func _make_player(bus: StringName) -> AudioStreamPlayer3D:
	var sound := AudioStreamPlayer3D.new()
	sound.bus = bus
	sound.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	sound.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	sound.max_distance = 90.0
	# Godot's project default is 0.5; node strength multiplies that setting.
	sound.panning_strength = _stereo_strength / maxf(float(ProjectSettings.get_setting("audio/general/3d_panning_strength", 0.5)), 0.01)
	add_child(sound)
	return sound

func set_stream(stream: AudioStream) -> void:
	if not _configured or stream == null:
		return
	_web_call("configure",[stream.resource_path,_looped,_category])
	var owned := stream.duplicate() as AudioStream
	if owned is AudioStreamOggVorbis or owned is AudioStreamMP3:
		owned.loop = _looped
	elif owned is AudioStreamWAV:
		owned.loop_mode = AudioStreamWAV.LOOP_FORWARD if _looped else AudioStreamWAV.LOOP_DISABLED
		owned.loop_begin = 0
		owned.loop_end = int(owned.get_length() * owned.mix_rate)
	direct.stream = owned
	for reflection in reflections:
		reflection.stream = owned
	for voice in late_players: voice.stream = owned

func set_listener_forward(forward: Vector3) -> void:
	_listener_forward = forward.normalized()

func set_acoustic_extent(radius: float, reference_distance: float) -> void:
	audible_range = clampf(radius,8.0,120.0)
	near_distance = clampf(reference_distance,1.0,10.0)
	if _configured:
		direct.max_distance = audible_range
		direct.unit_size = near_distance
		for reflection in reflections: reflection.max_distance = audible_range
		for voice in late_players: voice.max_distance = audible_range

func set_virtualized(value: bool) -> void:
	if _virtualized == value: return
	_virtualized = value
	_apply_suspension()
	if not value: _query_timer = 0

func set_spatial_strength(strength: float) -> void:
	_stereo_strength = clampf(strength, 0.0, 1.0)
	var multiplier := _stereo_strength / maxf(float(ProjectSettings.get_setting("audio/general/3d_panning_strength", 0.5)), 0.01)
	if _configured:
		direct.panning_strength = multiplier
		for reflection in reflections:
			reflection.panning_strength = multiplier

func set_variation(pitch: float, gain_db: float) -> void:
	_variation_pitch = clampf(pitch, 0.75, 1.3)
	_variation_gain_db = clampf(gain_db, -12.0, 6.0)
	if _configured:
		direct.max_db = _base_db + _variation_gain_db
		direct.pitch_scale = _variation_pitch if _web_audio else _pitch * _variation_pitch
		direct.volume_db = _base_db + _variation_gain_db + linear_to_db(maxf(_largest(_transmission),0.0001))

func play(from_position := 0.0) -> void:
	if not _configured:
		return
	_query_timer = 0.0
	_web_call("play",[from_position])
	direct.play(from_position)
	# Each voice begins at the same sample offset. Delay buses supply the path delay.
	for reflection in reflections:
		if not _web_audio: reflection.play(from_position)
	for voice in late_players:
		if not _web_audio: voice.play(from_position)
	set_suspended(_suspended)

func stop() -> void:
	_web_call("stop")
	if not _configured:
		return
	direct.stream_paused = false
	direct.stop()
	for reflection in reflections:
		reflection.stream_paused = false
		reflection.stop()
	for voice in late_players:
		voice.stream_paused = false
		voice.stop()

func set_suspended(value: bool) -> void:
	_suspended = value
	_apply_suspension()

func _apply_suspension() -> void:
	if not _configured:
		return
	var silent := _suspended or _virtualized
	_web_call("suspend",[silent])
	direct.stream_paused = silent
	for reflection in reflections:
		reflection.stream_paused = silent
	for voice in late_players: voice.stream_paused = silent
	# Also silence effect tails, without resetting the listener-dependent state.
	for label in _bus_names:
		var index := AudioServer.get_bus_index(label)
		if index >= 0:
			AudioServer.set_bus_mute(index, silent or _web_audio)

func tick(listener_pos: Vector3, listener_velocity: Vector3, delta: float, quality: int) -> void:
	if not _configured or not is_inside_tree() or _suspended or _virtualized:
		return
	_last_listener = listener_pos
	var displacement := listener_pos - global_position
	var distance := displacement.length()
	var direction := displacement / maxf(distance, 0.001)
	# Positive source radial velocity approaches the listener; positive listener
	# radial velocity moves away. True walking Doppler is intentionally subtle.
	var source_radial := clampf(source_velocity.dot(direction), -55.0, 55.0)
	var listener_radial := clampf(listener_velocity.dot(direction), -55.0, 55.0)
	var ratio := (SPEED_OF_SOUND - listener_radial) / (SPEED_OF_SOUND - source_radial)
	var smoothing := 1.0 - exp(-delta * 7.0)
	_pitch = lerpf(_pitch, clampf(ratio, 0.85, 1.18), smoothing)
	direct.pitch_scale = _variation_pitch if _web_audio else _pitch * _variation_pitch
	_query_timer -= delta
	if _query_timer <= 0.0:
		_query_timer = 0.16 if quality > 0 else 0.32
		_visibility_queries = 0
		_sample_obstruction(listener_pos, quality)
		_paths = _reflection_paths(listener_pos, quality)
		if _web_audio and _target_obstruction > .9:
			var edge := _diffraction_path(listener_pos)
			if not edge.is_empty(): _paths.append(edge)
	_obstruction = lerpf(_obstruction, _target_obstruction, smoothing)
	_transmission = _transmission.lerp(_target_transmission,smoothing)
	# Empirical high-frequency air absorption proxy, separate from wall absorption.
	var air_cutoff := clampf(20000.0 * exp(-distance * 0.0015), 2200.0, 18000.0)
	# A broad rear spectral cue supplements stereo panning; this is deliberately
	# not advertised as personalized HRTF or binaural head-related filtering.
	var rear_weight := clampf(_listener_forward.dot(direction), 0.0, 1.0)
	if not _web_audio: air_cutoff *= lerpf(1.0, 0.62, rear_weight)
	else: air_cutoff = 20000.0
	# The EQ retains low-frequency wall leakage. A material-dependent low pass
	# provides the remaining high-frequency rolloff instead of one universal wall.
	var wall_cutoff := clampf(18000.0 * pow(_transmission.z / maxf(_transmission.x,0.0001),0.9),450.0,18000.0)
	_target_cutoff = minf(air_cutoff,wall_cutoff)
	direct_filter.cutoff_hz = lerpf(direct_filter.cutoff_hz, _target_cutoff, smoothing)
	direct.volume_db = _base_db + _variation_gain_db + linear_to_db(maxf(_largest(_transmission),0.0001))
	_apply_band_eq(direct_equalizer,_transmission,smoothing,true)
	for i in range(reflections.size()):
		var sound := reflections[i]
		var target_db := -80.0
		if i < _paths.size():
			var path: Dictionary = _paths[i]
			sound.global_position = sound.global_position.lerp(path.point, smoothing)
			var length: float = path.length
			# Relative to a direct path rendered without propagation latency.
			var delay_ms := _delay_for_length(length,distance)
			reflection_delays[i].tap1_delay_ms = lerpf(reflection_delays[i].tap1_delay_ms, delay_ms, smoothing)
			reflection_filters[i].cutoff_hz = lerpf(reflection_filters[i].cutoff_hz,clampf(20000.0*exp(-length*.012),2200,18000),smoothing)
			_apply_band_eq(reflection_equalizers[i],path.bands,smoothing)
			target_db = _base_db + _variation_gain_db + linear_to_db(maxf(near_distance / maxf(length,near_distance),.001)) + linear_to_db(maxf(_largest(path.bands),.001)) - 3.0
		# Longer paths never become louder than the source's near-field ceiling.
		sound.volume_db = lerpf(sound.volume_db, target_db, smoothing)
		sound.pitch_scale = _pitch * _variation_pitch
	for i in range(late_players.size()):
		# The three buses filter complementary bands, so three copies do not
		# triple broadband energy. The room manager supplies the final wet gain.
		var energy: float = _diffuse_energy[i]
		var gain := sqrt(maxf(energy,0.000001)) * .50 * near_distance/maxf(distance,near_distance)
		var target_db := _base_db + _variation_gain_db + linear_to_db(maxf(gain,.00001))
		late_players[i].volume_db = -80.0 if _web_audio else lerpf(late_players[i].volume_db,target_db,smoothing)
		late_players[i].pitch_scale = _pitch * _variation_pitch
	_web_clock -= delta
	if _web_audio and _web_clock <= 0:
		_web_clock = 1.0/30.0
		var paths: Array = []
		for path in _paths:
			paths.append({"id":path.id,"position":[path.point.x,path.point.y,path.point.z],"length":path.length,"cutoff":path.get("cutoff",clampf(20000.0*exp(-path.length*.0015),6000,20000)),"db":_base_db+_variation_gain_db+linear_to_db(maxf(near_distance/maxf(path.length,near_distance),.001))+linear_to_db(maxf(_largest(path.bands),.001))-3.0})
		var send_gain := sqrt(maxf(_diffuse_energy.y,.000001))*.35*near_distance/maxf(distance,near_distance)
		_web_call("update",[{"distance":distance,"position":[global_position.x,global_position.y,global_position.z],"cutoff":_target_cutoff,"db":direct.volume_db+linear_to_db(near_distance/maxf(distance,near_distance)),"pitch":_variation_pitch,"paths":paths,"transmission":_largest(_transmission),"send_db":_base_db+_variation_gain_db+linear_to_db(maxf(send_gain,.00001))}])
	diagnostics = {"blocked": snappedf(_obstruction, 0.01), "cutoff": int(direct_filter.cutoff_hz), "pitch": snappedf(_pitch, 0.0001), "reflections": _paths.size(), "distance": snappedf(distance, 0.01), "direct_db": snappedf(direct.volume_db, 0.1), "transmission":_transmission, "diffuse_energy":_diffuse_energy,"surface_probes":_probe_count,"visibility_queries":_visibility_queries,"second_order":_paths.filter(func(p):return p.order == 2).size()}

func _largest(value: Vector3) -> float:
	return maxf(value.x,maxf(value.y,value.z))

func _apply_band_eq(equalizer: AudioEffectEQ6, bands: Vector3, smoothing: float, direct_path := false) -> void:
	var reference := maxf(_largest(bands),.0001)
	var relative := Vector3(linear_to_db(maxf(bands.x/reference,.001)),linear_to_db(maxf(bands.y/reference,.001)),linear_to_db(maxf(bands.z/reference,.001)))
	# Direct high-band loss is supplied chiefly by the material cutoff above;
	# avoiding a second full high-band loss prevents over-muffling transmission.
	if direct_path: relative.z *= .25
	for i in range(6):
		var target: float = relative.x if i < 3 else (relative.y if i < 5 else relative.z)
		equalizer.set_band_gain_db(i,lerpf(equalizer.get_band_gain_db(i),clampf(target,-48,6),smoothing))

func _delay_for_length(length: float, direct_distance: float) -> float:
	return clampf((length-direct_distance)/SPEED_OF_SOUND*1000.0,0.0,MAX_DELAY_MS)

func _diffraction_path(listener_pos: Vector3) -> Dictionary:
	# Bounded single-edge visibility search, not a full UTD wave solver.
	var hit := _ray(listener_pos,global_position)
	if hit.is_empty(): return {}
	var normal: Vector3 = hit.normal
	var tangent := normal.cross(Vector3.UP).normalized()
	if tangent.length_squared() < .1: tangent = Vector3.RIGHT
	for extent in [.5,1.0,2.0,4.0]:
		for side in [-1.0,1.0]:
			var edge: Vector3 = hit.position+tangent*extent*side+normal*.12
			if not _ray(listener_pos,edge).is_empty() or not _ray(edge,global_position).is_empty(): continue
			var length := listener_pos.distance_to(edge)+edge.distance_to(global_position)
			var excess := maxf(.01,length-listener_pos.distance_to(global_position))
			var pressure := .35/sqrt(1.0+excess*12.0)
			return {"id":"edge:"+str(hit.collider_id)+":"+str(side),"point":edge,"points":[edge],"order":1,"length":length,"absorption":.8,"strength":pressure/maxf(length,1.0),"bands":Vector3(pressure,pressure*.5,pressure*.1),"energy":Vector3.ONE*pressure*pressure,"materials":["edge diffraction"],"cutoff":clampf(2200.0/sqrt(excess),650,5000)}
	return {}

func _ray(from: Vector3, to: Vector3, exclude: Array[RID] = []) -> Dictionary:
	if from.distance_squared_to(to) < 0.0001:
		return {}
	_visibility_queries += 1
	var query := PhysicsRayQueryParameters3D.create(from, to, ACOUSTIC_MASK)
	query.exclude = exclude
	query.collide_with_areas = false
	query.hit_from_inside = true
	return get_world_3d().direct_space_state.intersect_ray(query)

func _sample_obstruction(listener_pos: Vector3, quality: int) -> void:
	var offset := (global_position - listener_pos).cross(Vector3.UP).normalized() * 0.25
	var samples: Array[Vector3] = [Vector3.ZERO]
	if quality > 0:
		samples.append(offset)
		samples.append(-offset)
	var blocked := 0.0
	var transmission := Vector3.ZERO
	_debug_obstruction_samples.clear()
	for sample in samples:
		var ray_from := listener_pos + sample
		var ray_to := global_position + sample
		var hit := _ray(ray_from, ray_to)
		_debug_obstruction_samples.append({"from": ray_from, "to": ray_to, "hit": not hit.is_empty(), "point": hit.position if not hit.is_empty() else ray_to, "center": sample == Vector3.ZERO})
		if not hit.is_empty():
			blocked += 1.0
			var db := Vector3.ZERO
			var excluded: Array[RID] = []
			var barrier := hit
			for layer in range(4 if _web_audio else 1):
				if barrier.is_empty(): break
				var material := AcousticProfile.sample(barrier.collider)
				var scale := 1.0
				var mesh = barrier.collider.get_node_or_null("Mesh")
				if _web_audio and mesh is MeshInstance3D:
					var normal: Vector3 = (mesh.global_basis.inverse()*barrier.normal).normalized()
					var thickness: float = normal.abs().dot(mesh.get_aabb().size)/maxf(.25,absf((ray_to-ray_from).normalized().dot(barrier.normal)))
					scale = clampf(thickness/maxf(.01,material.get("reference_thickness",.3)),.25,4.0)
				db += material.transmission_db*scale
				excluded.append(barrier.rid)
				barrier = _ray(ray_from,ray_to,excluded) if _web_audio else {}
			transmission += Vector3(db_to_linear(db.x),db_to_linear(db.y),db_to_linear(db.z))
		else:
			transmission += Vector3.ONE
	_target_obstruction = blocked / float(samples.size())
	_target_transmission = transmission / float(samples.size())

func get_debug_paths() -> Dictionary:
	## Snapshot only: never traces rays, updates effects, or shares mutable path data.
	var paths: Array[Dictionary] = []
	var distance := global_position.distance_to(_last_listener)
	for i in range(_paths.size()):
		var path: Dictionary = _paths[i]
		paths.append({
			"point": path.point,
			"length": path.length,
			"absorption": path.absorption,
			"points": path.points.duplicate(),
			"order":path.order,
			"bands":path.bands,
			"energy":path.energy,
			"materials":path.materials.duplicate(),
			"delay_ms": path.length/SPEED_OF_SOUND*1000.0 if _web_audio else _delay_for_length(path.length,distance),
			"applied_delay_ms": path.length/SPEED_OF_SOUND*1000.0 if _web_audio else reflection_delays[i].tap1_delay_ms,
			"rendered_point": path.point if _web_audio else reflections[i].global_position,
		})
	var center_blocked := not _debug_obstruction_samples.is_empty() and bool(_debug_obstruction_samples[0].hit)
	return {
		"source": global_position,
		"listener": _last_listener,
		"blocked": _obstruction,
		"center_blocked": center_blocked,
		"obstruction_point": _debug_obstruction_samples[0].point if center_blocked else null,
		"obstruction_segments": _debug_obstruction_samples.duplicate(true),
		"reflections": paths,
	}

func _reflection_paths(listener_pos: Vector3, quality: int) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var planes := _sample_planes(listener_pos,quality)
	if _reflection_budget == 0: return candidates
	for plane in planes:
		var path := _first_order(plane,listener_pos)
		if not path.is_empty(): candidates.append(path)
	if quality > 0:
		var pairs: Array[Dictionary] = []
		for first in planes:
			for second in planes:
				if first == second: continue
				var image := _mirror(_mirror(global_position,first),second)
				var length := image.distance_to(listener_pos)
				if length < .1 or length > 170.0: continue
				var energy: Vector3 = AcousticProfile.reflection_energy(first.material) * AcousticProfile.reflection_energy(second.material)
				var strength := sqrt(maxf(energy.y,0.001)*(1.0-first.material.scattering)*(1.0-second.material.scattering))/length
				pairs.append({"first":first,"second":second,"strength":strength})
		pairs.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.strength > b.strength)
		for i in range(mini(pairs.size(),MAX_SECOND_ORDER_CANDIDATES)):
			var path := _second_order(pairs[i].first,pairs[i].second,listener_pos)
			if not path.is_empty(): candidates.append(path)
	var previous_ids: Array = _paths.map(func(path): return path.get("id",""))
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.strength*(1.15 if previous_ids.has(a.id) else 1.0) > b.strength*(1.15 if previous_ids.has(b.id) else 1.0))
	var count := _reflection_budget if quality > 0 else mini(_reflection_budget, 1)
	if candidates.size() > count:
		candidates.resize(count)
	return candidates

func _sample_planes(listener_pos: Vector3, quality: int) -> Array[Dictionary]:
	var planes: Array[Dictionary] = []
	var directions: Array[Vector3] = [Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK,Vector3.UP,Vector3.DOWN]
	if quality > 0:
		for x in [-1,1]:
			for y in [-1,1]:
				for z in [-1,1]: directions.append(Vector3(x,y,z).normalized())
	_probe_count = directions.size()
	var total_energy := Vector3.ZERO
	for i in range(directions.size()):
		var origin := listener_pos if i < 6 else global_position
		var hit := _ray(origin,origin+directions[i]*RAY_LENGTH)
		if hit.is_empty() or hit.normal.length_squared() < .5: continue
		var material := AcousticProfile.sample(hit.collider)
		total_energy += AcousticProfile.reflection_energy(material) * (.35+.65*material.scattering)
		var duplicate := false
		for plane in planes:
			if plane.collider_id == hit.collider_id and plane.normal.dot(hit.normal) > .995 and absf(plane.normal.dot(hit.position-plane.point)) < .08:
				duplicate = true
		if not duplicate: planes.append({"point":hit.position,"normal":hit.normal,"collider_id":hit.collider_id,"material":material})
	_diffuse_energy = total_energy / float(directions.size())
	# Cache at most eight faces until the next staggered 160/320ms update.
	planes.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return global_position.distance_to(a.point)+listener_pos.distance_to(a.point)<global_position.distance_to(b.point)+listener_pos.distance_to(b.point))
	if planes.size() > 8: planes.resize(8)
	return planes

func _mirror(point: Vector3, plane: Dictionary) -> Vector3:
	return point-2.0*plane.normal.dot(point-plane.point)*plane.normal

func _intersection(from: Vector3, to: Vector3, plane: Dictionary) -> Variant:
	var line := to-from
	var denominator: float = plane.normal.dot(line)
	if absf(denominator)<.0001: return null
	var fraction: float = plane.normal.dot(plane.point-from)/denominator
	if fraction <= .0001 or fraction >= .9999: return null
	return from+line*fraction

func _finite_face(point: Vector3, plane: Dictionary) -> bool:
	var hit := _ray(point+plane.normal*.10,point-plane.normal*.10)
	return not hit.is_empty() and hit.collider_id == plane.collider_id and hit.position.distance_to(point)<.04 and hit.normal.dot(plane.normal)>.98

func _first_order(plane: Dictionary, listener_pos: Vector3) -> Dictionary:
	if plane.normal.dot(global_position-plane.point)<.04 or plane.normal.dot(listener_pos-plane.point)<.04: return {}
	var intersection = _intersection(listener_pos,_mirror(global_position,plane),plane)
	if intersection == null: return {}
	var bounce: Vector3 = intersection
	if not _finite_face(bounce,plane): return {}
	var clear_point: Vector3 = bounce+plane.normal*.04
	if not _ray(global_position,clear_point).is_empty() or not _ray(clear_point,listener_pos).is_empty(): return {}
	return _build_path([bounce],[plane],listener_pos)

func _second_order(first: Dictionary, second: Dictionary, listener_pos: Vector3) -> Dictionary:
	var image_first := _mirror(global_position,first)
	var image_second := _mirror(image_first,second)
	var last = _intersection(listener_pos,image_second,second)
	if last == null: return {}
	var first_point = _intersection(last,image_first,first)
	if first_point == null: return {}
	var a: Vector3 = first_point
	var b: Vector3 = last
	if a.distance_to(b)<.2: return {}
	if first.normal.dot(global_position-first.point)<.04 or first.normal.dot(b-first.point)<.04: return {}
	if second.normal.dot(a-second.point)<.04 or second.normal.dot(listener_pos-second.point)<.04: return {}
	if not _finite_face(a,first) or not _finite_face(b,second): return {}
	var safe_a: Vector3 = a+first.normal*.04
	var safe_b: Vector3 = b+second.normal*.04
	if not _ray(global_position,safe_a).is_empty() or not _ray(safe_a,safe_b).is_empty() or not _ray(safe_b,listener_pos).is_empty(): return {}
	return _build_path([a,b],[first,second],listener_pos)

func _build_path(points: Array, planes: Array, listener_pos: Vector3) -> Dictionary:
	var length := 0.0
	var previous := global_position
	var energy := Vector3.ONE
	var absorption := 0.0
	var materials: Array[String] = []
	for i in range(points.size()):
		length += previous.distance_to(points[i])
		previous = points[i]
		var material: Dictionary = planes[i].material
		energy *= AcousticProfile.reflection_energy(material)*(1.0-material.scattering)
		absorption += material.absorption.y
		materials.append(material.label)
	length += previous.distance_to(listener_pos)
	if length > 170.0: return {}
	# Coefficients above describe energy; square roots give rendered pressure.
	var bands := Vector3(sqrt(energy.x)*exp(-length*.00015),sqrt(energy.y)*exp(-length*.0007),sqrt(energy.z)*exp(-length*.0035))
	var strength := (bands.x*.25+bands.y*.5+bands.z*.25)/maxf(length,1.0)
	var identity := ""
	for plane in planes: identity += str(plane.collider_id)+":"+str(plane.normal.snapped(Vector3.ONE*.01))+"/"
	return {"id":identity,"point":points[-1],"points":points,"order":points.size(),"length":length,"absorption":absorption/float(points.size()),"strength":strength,"bands":bands,"energy":energy,"materials":materials}

func dispose() -> void:
	_web_call("dispose")
	stop()
	if _configured:
		direct.stream = null
		for voice in reflections: voice.stream = null
		for voice in late_players: voice.stream = null
	_remove_buses()
	queue_free()

func _exit_tree() -> void:
	_web_call("dispose")
	_remove_buses()

func _remove_buses() -> void:
	for label in _bus_names:
		var index := AudioServer.get_bus_index(label)
		if index > 0:
			AudioServer.remove_bus(index)
	_bus_names.clear()

extends RefCounted
## Bounded geometric late-field estimate. RT60 values are Eyring-inspired
## estimates; Godot's algorithmic room_size is not a calibrated RT60 control.
## API references: docs.godotengine.org/en/stable/classes/class_audioeffectreverb.html
## and class_audioeffectfilter.html. The three bands are real parallel DSP paths.

const AcousticMaterial = preload("res://scripts/acoustic_material.gd")
const BANDS := ["Low", "Mid", "High"]
const SPEED_OF_SOUND := 343.0
const PROBE_DISTANCE := 45.0
const MASK := 14
const BAND_BALANCE := Vector3(0.8, 1.0, 0.72)

var primary_effect: AudioEffectReverb
var effects: Array[AudioEffectReverb] = []
var stats: Dictionary = {}
var wet_target := 0.0
var _wet := 0.0
var _decay := Vector3.ONE * 0.12
var _decay_target := Vector3.ONE * 0.12
var _absorption := Vector3.ONE * 0.3
var _absorption_target := Vector3.ONE * 0.3
var _predelay := 20.0
var _predelay_target := 20.0
var _paused := false

func setup_buses() -> void:
	# Sends only point to earlier buses. Source-private buses are appended later.
	_ensure_bus("Room", "Master")
	_ensure_bus("EarlyReturn", "Master")
	for band in BANDS: _ensure_bus("Room" + band, "Room")
	_ensure_bus("Diffusion", "EarlyReturn")
	for category in ["Environment", "Footsteps", "UI"]: _ensure_bus(category, "Master")
	for category in ["Environment", "Footsteps"]:
		_ensure_bus(category + "Reflections", "Diffusion")
		for band in BANDS: _ensure_bus(category + "Late" + band, "Room" + band)
	clear()

func _ensure_bus(label: String, destination: String) -> void:
	var index := AudioServer.get_bus_index(label)
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, label)
	var destination_index := AudioServer.get_bus_index(destination)
	if index <= destination_index:
		AudioServer.move_bus(index, AudioServer.bus_count - 1)
		index = AudioServer.get_bus_index(label)
	AudioServer.set_bus_send(index, destination)

func _remove_effects(label: String) -> void:
	var index := AudioServer.get_bus_index(label)
	if index < 0: return
	while AudioServer.get_bus_effect_count(index) > 0: AudioServer.remove_bus_effect(index, 0)

func _filter(index: int, high_pass: bool, frequency: float) -> void:
	var effect: AudioEffectFilter = AudioEffectHighPassFilter.new() if high_pass else AudioEffectLowPassFilter.new()
	effect.cutoff_hz = frequency
	effect.db = AudioEffectFilter.FILTER_12DB
	effect.resonance = 0.5
	AudioServer.add_bus_effect(index, effect)

func _new_late_effects() -> void:
	effects.clear()
	for band in range(3):
		var label: String = "Room" + BANDS[band]
		_remove_effects(label)
		var index := AudioServer.get_bus_index(label)
		if band > 0: _filter(index, true, 400.0 if band == 1 else 3500.0)
		if band < 2: _filter(index, false, 400.0 if band == 0 else 3500.0)
		var effect := AudioEffectReverb.new()
		effect.wet = 1.0
		effect.dry = 0.0
		effect.room_size = 0.2
		effect.damping = 0.5
		effect.predelay_msec = 20.0
		effect.predelay_feedback = 0.0
		effect.spread = 0.9
		effect.hipass = 0.0
		effects.append(effect)
		AudioServer.add_bus_effect(index, effect)
		AudioServer.set_bus_volume_db(index, linear_to_db(BAND_BALANCE[band]))
	primary_effect = effects[1]

func _new_diffusion() -> void:
	_remove_effects("Diffusion")
	var effect := AudioEffectDelay.new()
	effect.dry = 1.0
	effect.tap1_active = false
	effect.tap1_delay_ms = 11.0
	effect.tap1_level_db = -19.0
	effect.tap1_pan = -0.45
	effect.tap2_active = false
	effect.tap2_delay_ms = 19.0
	effect.tap2_level_db = -22.0
	effect.tap2_pan = 0.45
	effect.feedback_active = false
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Diffusion"), effect)

func clear() -> void:
	# Recreate effect instances to discard their audio-thread delay buffers.
	if AudioServer.get_bus_index("RoomLow") < 0: return
	_remove_effects("Room")
	_remove_effects("EarlyReturn")
	_new_late_effects()
	_new_diffusion()
	wet_target = 0.0
	_wet = 0.0
	_decay = Vector3.ONE * 0.12
	_decay_target = _decay
	_absorption = Vector3.ONE * 0.3
	_absorption_target = _absorption
	_predelay = 20.0
	_predelay_target = 20.0
	stats = {"enclosure":0.0, "rt60_estimate":0.12, "mean_free_path":0.0, "wet":0.0,
		"decay_bands":[0.12,0.12,0.12], "decay_targets":[0.12,0.12,0.12],
		"absorption":[0.3,0.3,0.3], "escape_fraction":1.0, "escape_bands":[1.0,1.0,1.0],
		"scattering":0.0, "probe_rays":0, "ray_casts":0, "bounce_hits":0,
		"predelay_ms":20.0, "model":"three-band geometric estimate / algorithmic late reverb"}
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Room"), -80.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("EarlyReturn"), 0.0)
	set_paused(_paused)

func set_paused(value: bool) -> void:
	_paused = value
	for label in ["Room", "EarlyReturn"]:
		var index := AudioServer.get_bus_index(label)
		if index >= 0: AudioServer.set_bus_mute(index, value)

func _hemisphere(normal: Vector3, index: int, bounce: int) -> Vector3:
	# Deterministic cosine-weighted sample avoids temporal jitter at rest.
	var u := fposmod((index + 1) * 0.754877666 + bounce * 0.569840296, 1.0)
	var phase := TAU * fposmod((index + 1) * 0.618033989 + bounce * 0.414213562, 1.0)
	var axis := Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT
	var tangent := normal.cross(axis).normalized()
	var bitangent := normal.cross(tangent)
	return (normal * sqrt(1.0-u) + (tangent*cos(phase)+bitangent*sin(phase))*sqrt(u)).normalized()

func probe(world: World3D, listener: Vector3, quality: int) -> void:
	if world == null: return
	var space := world.direct_space_state
	var count := 192 if quality > 1 else (48 if quality > 0 else 16)
	var depth := 5 if quality > 1 else (3 if quality > 0 else 2)
	var first_hits := 0
	var upward_count := 0
	var upward_hits := 0
	var first_length := 0.0
	var path_length := 0.0
	var bounce_hits := 0
	var casts := 0
	var material_weight := 0.0
	var absorption_sum := Vector3.ZERO
	var transmission_sum := Vector3.ZERO
	var scattering_sum := 0.0
	var escaped := Vector3.ZERO
	var leaked := Vector3.ZERO
	var materials := {}
	var hit_min := Vector3.INF
	var hit_max := -Vector3.INF
	for i in range(count):
		var y := 1.0 - 2.0 * (float(i)+0.5)/count
		var radius := sqrt(maxf(0.0,1.0-y*y))
		var direction := Vector3(cos(i*2.39996323)*radius,y,sin(i*2.39996323)*radius)
		var origin := listener
		var energy := Vector3.ONE
		if y > 0.35: upward_count += 1
		for bounce in range(depth):
			casts += 1
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin,origin+direction*PROBE_DISTANCE,MASK))
			if hit.is_empty():
				escaped += energy
				break
			var distance := origin.distance_to(hit.position)
			if bounce == 0:
				first_hits += 1
				first_length += distance
				hit_min = hit_min.min(hit.position)
				hit_max = hit_max.max(hit.position)
				if y > 0.35: upward_hits += 1
			bounce_hits += 1
			path_length += distance
			var material: Dictionary = AcousticMaterial.sample(hit.collider)
			var alpha: Vector3 = material.absorption
			var transmission_db: Vector3 = material.transmission_db
			var transmission := Vector3(pow(10.0,transmission_db.x/10.0),pow(10.0,transmission_db.y/10.0),pow(10.0,transmission_db.z/10.0))
			var weight := (energy.x+energy.y+energy.z)/3.0
			absorption_sum += alpha*weight
			transmission_sum += transmission*weight
			scattering_sum += float(material.scattering)*weight
			material_weight += weight
			materials[material.label] = int(materials.get(material.label,0))+1
			leaked += energy*transmission
			energy *= AcousticMaterial.reflection_energy(material)
			var normal: Vector3 = hit.normal
			if normal.dot(direction) > 0.0: normal = -normal
			var specular := direction.bounce(normal)
			direction = specular.lerp(_hemisphere(normal,i,bounce),float(material.scattering)).normalized()
			origin = hit.position+normal*0.025
	var mean_path := path_length/maxf(1.0,bounce_hits)
	var first_path := first_length/maxf(1.0,first_hits)
	var absorption := absorption_sum/maxf(0.001,material_weight)
	var transmission := transmission_sum/maxf(0.001,material_weight)
	var scattering := scattering_sum/maxf(0.001,material_weight)
	var escape := escaped/float(count)
	for band in range(3): escape[band] = clampf(escape[band],0.0,1.0)
	var roof_coverage := float(upward_hits)/maxf(1.0,upward_count)
	var enclosure := float(first_hits)/count*lerpf(0.07,1.0,roof_coverage)
	var mean_bounces := maxf(1.0,float(bounce_hits)/count)
	for band in range(3):
		# Mean free path = 4V/S in a diffuse closed room. This yields the Eyring
		# form 6 ln(10) * path / (-c ln(survival)); openings and air add losses.
		var escape_per_bounce := 1.0-pow(maxf(0.001,1.0-escape[band]),1.0/mean_bounces)
		var air_loss: float = [0.0001,0.0006,0.0025][band]*mean_path
		var survival := clampf((1.0-absorption[band]-transmission[band])*(1.0-escape_per_bounce)*exp(-air_loss),0.01,0.985)
		_decay_target[band] = clampf(6.0*log(10.0)*maxf(0.3,mean_path)/(-SPEED_OF_SOUND*log(survival)),0.12,7.5)
	_absorption_target = absorption
	_predelay_target = clampf(first_path/SPEED_OF_SOUND*1000.0,20.0,85.0)
	# A modest diffuse return preserves directional information in the direct path.
	wet_target = clampf(enclosure*(0.10+sqrt(_decay_target.y)*0.075)*(0.85+scattering*0.3),0.0,0.32)
	stats.merge({"enclosure":snappedf(enclosure,0.01), "mean_free_path":snappedf(mean_path,0.01),
		# Equivalent cube side from mean free path, not an exact room bounding box.
		"equivalent_room_scale_m":snappedf(mean_path*1.5,0.01),
		"sampled_extent_m":_array(hit_max-hit_min) if first_hits > 0 else [0.0,0.0,0.0],
		"first_path_mean":snappedf(first_path,0.01), "roof_coverage":snappedf(roof_coverage,0.01),
		"absorption":_array(absorption), "transmission_energy":_array(transmission),
		"escape_fraction":snappedf((escape.x+escape.y+escape.z)/3.0,0.001), "escape_bands":_array(escape),
		"leakage_bands":_array(leaked/float(count)),
		"scattering":snappedf(scattering,0.001), "probe_rays":count, "ray_casts":casts,
		"bounce_hits":bounce_hits, "max_bounces":depth, "materials":materials,
		"decay_targets":_array(_decay_target), "wet_target":snappedf(wet_target,0.001)},true)

func _array(value: Vector3) -> Array:
	return [snappedf(value.x,0.001),snappedf(value.y,0.001),snappedf(value.z,0.001)]

func tick(delta: float) -> void:
	if effects.size() != 3: return
	var smoothing := 1.0-exp(-maxf(0.0,delta)*2.6)
	_wet = lerpf(_wet,wet_target,smoothing)
	_decay = _decay.lerp(_decay_target,smoothing)
	_absorption = _absorption.lerp(_absorption_target,smoothing)
	_predelay = lerpf(_predelay,_predelay_target,smoothing)
	for band in range(3):
		# A monotonic, bounded rendering map rather than an exact decay calibration.
		effects[band].room_size = clampf(0.16+0.8*(1.0-exp(-_decay[band]/2.4)),0.16,0.96)
		effects[band].damping = clampf(0.10+_absorption[band]*0.75+band*0.035,0.08,0.88)
		effects[band].predelay_msec = _predelay
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Room"),linear_to_db(maxf(0.00001,_wet)))
	stats.rt60_estimate = snappedf(_decay.y,0.01)
	stats.decay_bands = _array(_decay)
	stats.wet = snappedf(_wet,0.001)
	stats.predelay_ms = snappedf(_predelay,0.1)
	stats.rendered_room_sizes = [snappedf(effects[0].room_size,0.001),snappedf(effects[1].room_size,0.001),snappedf(effects[2].room_size,0.001)]

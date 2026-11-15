@tool
extends Node3D
## Authored geometry stays saved/editable. Only nearby audio voices are instantiated.
@export var sea_level := 118.560516
@export var plan_texture: Texture2D
@export_range(8,24,1) var max_environment_voices := 18
@export var maximum_group_voices := {"canopy":6,"water":3,"bird":4,"wind":3,"detail":2}
var game
var active := {}
var tracks := {}
var trigger_state := {}
var clock := 0.0
var reconcile_clock := 0.0
var event_count := 0
var audio_revision := 0
var underwater := false
var water_depth := 0.0
var _medium := 0.0
var _water_clock := 0.0

func setup_audio(owner_game) -> void:
	game = owner_game
	for anchor in $Sources.get_children():
		anchor.configuration_changed.connect(game._queue_emitter_change.bind(anchor))
		var path_name := String(anchor.get_meta("bird_path",""))
		if not path_name.is_empty():
			var path: Path3D = $BirdPaths.get_node(NodePath(path_name))
			tracks[anchor.name] = {"path":path,"progress":randf()*path.curve.get_baked_length(),"speed":float(path.get_meta("speed_mps",8.0)),"loop":bool(path.get_meta("loop",false)),"running":true}
	for trigger in $TakeoffEvents.get_children():
		trigger_state[trigger.name] = {"armed":true,"cooldown_until":0.0,"inside":false}
	_update_routes(0.0)
	_reconcile(game.listener.global_position)

func tick_audio(delta: float, ear: Vector3) -> void:
	clock += delta
	_update_routes(delta)
	_tick_takeoffs(ear)
	reconcile_clock -= delta
	if reconcile_clock <= 0:
		reconcile_clock = .3
		_reconcile(ear)
	_water_clock -= delta
	if _water_clock <= 0:
		_water_clock = .12
		var query := PhysicsRayQueryParameters3D.create(ear+Vector3.UP*1000,ear-Vector3.UP*1200,4)
		query.hit_back_faces = true
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		water_depth = maxf(0.0,float(hit.position.y)-game.player.position.y+.875) if not hit.is_empty() else 0.0
		underwater = not hit.is_empty() and ear.y < float(hit.position.y)-.12
	_medium = move_toward(_medium,1.0 if underwater else 0.0,delta*2.5)
	for sound in game.foot_pool+[game.action_sound]:
		if not is_instance_valid(sound):continue
		sound.medium_cutoff_hz=exp(lerpf(log(20000.0),log(1800.0),_medium))
		sound.medium_gain_db=-3.0*_medium
	for name in active.keys():
		var entry: Dictionary = active[name]
		var sound: Node3D = entry.sound
		entry.weight = move_toward(float(entry.weight),1.0 if entry.selected else 0.0,delta/(.7 if entry.selected else 1.1))
		sound.mix_gain_db = linear_to_db(maxf(.00001,sin(float(entry.weight)*PI*.5)))
		sound.medium_cutoff_hz = exp(lerpf(log(20000.0),log(850.0),_medium))
		sound.medium_gain_db = -7.0*_medium
		var anchor: Node3D = entry.anchor
		var previous := sound.global_position
		sound.global_position = anchor.global_position
		sound.source_velocity = (sound.global_position-previous)/maxf(delta,.001) if entry.age>.05 else Vector3.ZERO
		entry.age += delta
		if not entry.selected and float(entry.weight)<=0.0:
			game.sources.erase(sound)
			sound.dispose()
			active.erase(name)
			audio_revision+=1
	_tick_escape_calls()

func _tick_escape_calls() -> void:
	for name in tracks:
		var track:Dictionary=tracks[name]
		if not bool(track.get("takeoff",false)) or not track.running or int(track.get("calls_left",0))<=0:continue
		if clock<float(track.get("next_call",INF)) or not active.has(name):continue
		var sound:Node3D=active[name].sound
		if sound.direct.playing:continue
		var stream:AudioStream=game._choose_event_stream(sound)
		if stream==null:continue
		sound.set_stream(stream)
		sound.set_variation(randf_range(.985,1.015),randf_range(-3.0,-1.5))
		sound.play()
		sound.set_meta("active_clip",stream.resource_path.get_file().get_basename())
		sound.set_meta("event_count",int(sound.get_meta("event_count",0))+1)
		track.calls_left=int(track.calls_left)-1
		track.next_call=clock+randf_range(1.1,2.2)

func _update_routes(delta: float) -> void:
	for name in tracks:
		var track: Dictionary = tracks[name]
		if not track.running:
			if not bool(track.get("takeoff",false)) and clock>=float(track.get("restart_at",INF)):
				track.progress=0.0;track.running=true
			else:continue
		var path: Path3D = track.path
		var length := path.curve.get_baked_length()
		track.progress += delta*float(track.speed)
		if track.loop:track.progress = fposmod(float(track.progress),maxf(length,.01))
		elif float(track.progress)>=length:
			track.running=false
			if not bool(track.get("takeoff",false)):track.restart_at=clock+randf_range(35.0,75.0)
			if active.has(name):active[name].sound.stop()
		var anchor: Node3D = $Sources.get_node(NodePath(String(name)))
		anchor.position = path.curve.sample_baked(clampf(float(track.progress),0,length),true)

func _reconcile(ear: Vector3) -> void:
	var candidates: Array = []
	for anchor in $Sources.get_children():
		if anchor.sound==null:continue
		var name := String(anchor.name)
		if tracks.has(name) and not bool(tracks[name].running):continue
		if bool(anchor.get_meta("managed_event",false)) and not bool(tracks.get(name,{}).get("running",false)):continue
		var distance: float = anchor.global_position.distance_to(ear)
		var margin := 18.0 if active.has(name) else 0.0
		if distance > float(anchor.audible_range)+margin:continue
		var score: float = float(anchor.gain_db)+linear_to_db(float(anchor.near_distance)/maxf(distance,float(anchor.near_distance)))
		if bool(anchor.get_meta("managed_event",false)):score += 14.0
		if active.has(name):score += 2.0
		candidates.append({"anchor":anchor,"score":score})
	candidates.sort_custom(func(a,b):return a.score>b.score)
	for entry in active.values():entry.selected=false
	var counts := {};var count := 0
	for candidate in candidates:
		var anchor: Node3D = candidate.anchor
		var group := String(anchor.get_meta("mix_group","detail"))
		if count>=max_environment_voices or int(counts.get(group,0))>=int(maximum_group_voices.get(group,2)):continue
		counts[group]=int(counts.get(group,0))+1;count+=1
		var name := String(anchor.name)
		if not active.has(name):
			if active.size()>=max_environment_voices+4:continue
			var sound: Node3D = game._create_emitter(anchor)
			sound.mix_gain_db=-100.0
			game.sources.append(sound)
			active[name]={"anchor":anchor,"sound":sound,"weight":0.0,"selected":true,"age":0.0}
			audio_revision+=1
		else:active[name].selected=true

func replace_emitter(anchor: Node3D) -> void:
	var name:=String(anchor.name)
	if not active.has(name):return
	var entry:Dictionary=active[name]
	var previous:Node3D=entry.sound
	var was_playing:bool=previous.direct.playing
	game.sources.erase(previous);previous.dispose()
	var sound:Node3D=game._create_emitter(anchor)
	game.sources.append(sound);entry.sound=sound;entry.age=0.0
	sound.mix_gain_db=linear_to_db(maxf(.00001,sin(float(entry.weight)*PI*.5)))
	if bool(anchor.get_meta("managed_event",false)) and was_playing and anchor.sound!=null:sound.play()
	audio_revision+=1

func _tick_takeoffs(ear: Vector3) -> void:
	if clock<2.0:return
	for trigger in $TakeoffEvents.get_children():
		var state: Dictionary = trigger_state[trigger.name]
		var distance := Vector2(ear.x-trigger.position.x,ear.z-trigger.position.z).length()
		var radius := float(trigger.get_meta("trigger_radius_m",18.0))
		if distance>float(trigger.get_meta("rearm_radius_m",65.0)) and clock>=float(state.cooldown_until):state.armed=true
		var inside := distance<radius and absf(ear.y-trigger.position.y)<12.0
		if inside and not state.inside and state.armed and clock>=float(state.cooldown_until):
			state.armed=false
			state.cooldown_until=clock+randf_range(float(trigger.get_meta("cooldown_min_s",120)),float(trigger.get_meta("cooldown_max_s",240)))
			if randf()<=float(trigger.get_meta("activation_probability",.8)):fire_takeoff(trigger,ear)
		state.inside=inside

func fire_takeoff(trigger: Node3D, ear: Vector3) -> void:
	var selected: Path3D;var best := -INF
	for name in trigger.get_meta("escape_paths",[]):
		var path: Path3D = $BirdPaths.get_node(NodePath(String(name)))
		var direction := path.curve.sample_baked(minf(60,path.curve.get_baked_length()))-path.curve.get_point_position(0)
		var score := direction.normalized().dot((trigger.position-ear).normalized())
		if score>best:best=score;selected=path
	if selected==null:return
	var name := String(trigger.get_meta("emitter"))
	tracks[name]={"path":selected,"progress":0.0,"speed":float(selected.get_meta("speed_mps",9)),"loop":false,"running":true,"takeoff":true,"calls_left":randi_range(2,3),"next_call":clock+randf_range(1.1,1.8)}
	_update_routes(0)
	_reconcile(ear)
	if active.has(name):
		var sound: Node3D=active[name].sound
		active[name].weight=1.0
		sound.mix_gain_db=0.0
		sound.global_position=$Sources.get_node(NodePath(name)).global_position
		sound.source_velocity=Vector3.ZERO
		sound.set_virtualized(false)
		sound.set_variation(randf_range(.98,1.02),randf_range(-1.5,0))
		sound.play()
		sound.set_meta("event_count",int(sound.get_meta("event_count",0))+1)
		event_count+=1

func footstep_surface(pos: Vector3) -> String:
	var query := PhysicsRayQueryParameters3D.create(pos+Vector3.UP*.1,pos-Vector3.UP*1.8,2)
	query.hit_back_faces=true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var material := String(hit.collider.get_meta("material","grass")) if not hit.is_empty() else "grass"
	if material.begins_with("underwater_") or water_depth>.3:return "water"
	return material

func diagnostics() -> Dictionary:
	return {"active_voices":active.size(),"voice_budget":max_environment_voices,"takeoffs":event_count,"underwater":underwater,"water_depth":water_depth,"authored_sources":$Sources.get_child_count(),"bird_paths":$BirdPaths.get_child_count()}

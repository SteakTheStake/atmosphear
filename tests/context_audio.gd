extends SceneTree
## Context and variety contracts. Provenance checks are not claims of audition.
var failures: Array[String] = []
var manifest: Dictionary = {}
var game

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if value: print("PASS ",label)
	else:
		failures.append(label)
		push_error(label)

func provenance(stream: AudioStream) -> String:
	var entry: Dictionary = manifest.get(stream.resource_path.trim_prefix("res://"),{})
	var result := ""
	for source in entry.get("sources",[]): result += String(source.path).to_lower()+" "
	return result

func family(stream: AudioStream) -> String:
	var label := provenance(stream)
	if "wind blowing through trees" in label: return "canopy"
	if "animal bird" in label: return "bird"
	if "water drip" in label: return "drip"
	if "pipe" in label and "vibrat" in label: return "pipe"
	if ("wood" in label or "floor" in label) and ("creak" in label or "squeak" in label): return "wood_creak"
	if "metal" in label and ("creak" in label or "strain" in label or "squeak" in label): return "metal_creak"
	return "other"

func tracked(stream: AudioStream) -> bool:
	if stream == null or not stream.resource_path.begins_with("res://assets/library/"): return false
	var entry: Dictionary = manifest.get(stream.resource_path.trim_prefix("res://"),{})
	if entry.is_empty() or entry.get("sources",[]).is_empty(): return false
	for source in entry.sources:
		if not String(source.path).begins_with("audio/"): return false
	return true

func bird_species(stream: AudioStream) -> String:
	var expression := RegEx.new()
	expression.compile("animal bird (.+?) chirp")
	var match_result := expression.search(provenance(stream))
	return match_result.get_string(1) if match_result else ""

func wav_sample_peak(path: String) -> float:
	# Godot imports these WAVs as QOA. Inspect the original PCM RIFF data rather
	# than interpreting compressed runtime bytes as signed audio samples.
	var bytes := FileAccess.get_file_as_bytes(path)
	var offset := 12
	var pcm16 := false
	while offset+8<=bytes.size():
		var label := bytes.slice(offset,offset+4).get_string_from_ascii()
		var size := int(bytes.decode_u32(offset+4))
		var start := offset+8
		if start+size>bytes.size(): return -1.0
		if label=="fmt " and size>=16:
			pcm16=bytes.decode_u16(start)==1 and bytes.decode_u16(start+14)==16
		if label=="data" and pcm16:
			var peak := 0.0
			for index in range(start,start+size,2): peak=maxf(peak,absf(float(bytes.decode_s16(index)))/32768.0)
			return peak
		offset=start+size+(size%2)
	return -1.0

func run() -> void:
	await examine()
	# Release the examination's local Resource references before engine shutdown.
	await process_frame
	print("ALL CONTEXT AUDIO CHECKS PASSED" if failures.is_empty() else "FAILED: "+str(failures))
	quit(0 if failures.is_empty() else 1)

func examine() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/library/manifest.json"))
	for entry in data.assets: manifest[entry.file]=entry
	var all_tracked := true
	var no_rejected_context := true
	var pools_match_roles := true
	var birds_keep_species := true
	var variant_emitters := 0
	var canopy_count := 0
	var canopy_files: Dictionary = {}
	var canopy_beds_long := true
	var varied_families: Dictionary = {}
	for id in ["forest","cistern","freighter","courtyard"]:
		var scene = load("res://scenes/levels/legacy/%s.tscn" % id).instantiate()
		for anchor in scene.get_node("Sources").get_children():
			var primary: AudioStream = anchor.sound
			var pool: Array = [primary]
			pool.append_array(anchor.sound_variants)
			var unique: Dictionary = {}
			var primary_family := family(primary)
			for stream in pool:
				if stream == null: continue
				all_tracked = all_tracked and tracked(stream)
				unique[stream.resource_path]=true
				var description := provenance(stream)
				for rejected in ["tree shaking","plastic bucket","metal bowl","blizzard","hurricane"]:
					if rejected in description: no_rejected_context=false
				if primary_family in ["bird","drip","pipe","wood_creak","metal_creak"] and family(stream)!=primary_family:
					pools_match_roles=false
				if primary_family=="bird":
					birds_keep_species=birds_keep_species and not bird_species(primary).is_empty() and bird_species(stream)==bird_species(primary)
			if not anchor.looped and unique.size()>=2:
				varied_families[primary_family]=true
				if unique.size()>=3: variant_emitters += 1
			if id=="forest" and primary_family=="canopy" and anchor.looped:
				canopy_count += 1
				canopy_files[primary.resource_path]=true
				canopy_beds_long = canopy_beds_long and primary.get_length()>=15.0
		scene.free()
	check(all_tracked,"every primary and variant recording is traceable to the user library")
	check(no_rejected_context,"active emitters exclude tree-shaking, bucket, bowl and extreme-weather stand-ins")
	check(canopy_count>=8 and canopy_files.size()>=4,"localized forest trees use at least four distinct passages of the canopy recording")
	check(canopy_beds_long,"canopy beds are long wind-through-trees recordings rather than short impact loops")
	check(pools_match_roles,"bird, drip, pipe and creak pools preserve their source identities")
	check(birds_keep_species,"each bird anchor varies calls within one named species")
	check(variant_emitters>=12,"at least twelve intermittent emitters have three or more distinct recordings")
	check(varied_families.has("bird") and varied_families.has("drip") and varied_families.has("wood_creak") and varied_families.has("metal_creak"),"variation covers animals, water, wood and metal details")
	var palette = load("res://resources/audio/default_palette.tres")
	var ui_distinct: Dictionary = {}
	var ui_tactile := true
	var ui_headroom := true
	var ui_navigation_varied := false
	for cue in ["ui_move","ui_accept","ui_back"]:
		var recordings: Array = palette.cue_streams(cue)
		if cue=="ui_move": ui_navigation_varied=recordings.size()>=3
		for stream in recordings:
			ui_distinct[stream.resource_path]=true
			ui_tactile = ui_tactile and tracked(stream) and "science fiction" not in provenance(stream) and stream.get_length()<=.18
			var peak := wav_sample_peak(stream.resource_path)
			ui_headroom = ui_headroom and peak<=db_to_linear(-20.0) and peak>db_to_linear(-45.0)
	check(ui_distinct.size()>=5 and ui_tactile,"menu navigation, confirm and back use distinct brief tactile recordings")
	check(ui_navigation_varied,"frequent menu navigation varies between at least three recorded takes")
	check(ui_headroom,"menu recordings retain at least twenty decibels of sample-peak headroom")
	game=load("res://scenes/main.tscn").instantiate()
	game.native_audio_enabled = false # Exercise the retained portable geometry/mixer regression path.
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.play_level("forest")
	await physics_frame
	await physics_frame
	var varied_source = null
	for sound in game.sources:
		if not sound._looped and sound.get_meta("recordings",[]).size()>=3:
			varied_source=sound
			break
	check(varied_source!=null,"loaded environmental emitter carries its authored variant pool")
	if varied_source!=null:
		var pool: Array = varied_source.get_meta("recordings")
		var seen: Dictionary = {}
		var previous: AudioStream = null
		var no_repeat := true
		var even_distribution := true
		for round_index in range(5):
			seen.clear()
			for index in range(pool.size()):
				var chosen: AudioStream = game._choose_event_stream(varied_source)
				no_repeat=no_repeat and chosen!=previous
				seen[chosen.get_instance_id()]=true
				previous=chosen
			even_distribution=even_distribution and seen.size()==pool.size()
		check(no_repeat,"event shuffle bags never immediately repeat, including across refills")
		check(even_distribution,"every take is used once before the event bag refills")
		varied_source.set_meta("recordings",[pool[0]])
		check(game._choose_event_stream(varied_source)==pool[0],"changing an event pool invalidates obsolete shuffle entries")
		varied_source.set_meta("recordings",pool)
	game.ui_player.stop()
	game.ui_last_msec=-1000
	game.play_ui("move")
	check(not game.ui_player.playing,"active exploration rejects menu navigation audio")
	var map_was_visible: bool = game.game_ui.map_visible
	var map_key := InputEventKey.new()
	map_key.physical_keycode=KEY_M
	map_key.pressed=true
	game.game_ui._unhandled_input(map_key)
	check(game.game_ui.map_visible!=map_was_visible and not game.ui_player.playing,"map toggle changes only its view without a menu cue")
	game.set_paused(true)
	game.ui_player.stop()
	game.play_ui("accept")
	check(game.ui_player.playing,"paused menus retain confirmation audio")
	game._command("menu")
	await process_frame
	game.queue_free()
	await process_frame
	game = null
	for i in range(4): await physics_frame
	await create_timer(.1).timeout

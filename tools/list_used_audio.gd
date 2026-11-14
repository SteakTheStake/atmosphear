extends SceneTree
## Read-only runtime-resource traversal. Does not invoke a level's _ready or save scenes.
var used := {}
var resource_seen := {}
var resource_paths := {}
var export_roots: Array[String] = []
var dependency_resources := {}

func _initialize() -> void:
	var main_path: String = ProjectSettings.get_setting("application/run/main_scene")
	var main = load(main_path).instantiate()
	export_roots.append(main_path)
	_visit_node(main,main_path,main)
	for path: String in main.level_scenes().values():
		export_roots.append(path)
		var level: Node = load(path).instantiate()
		_visit_node(level,path,level)
		level.free()
	if main.sound_palette != null and not main.sound_palette.resource_path.is_empty():
		export_roots.append(main.sound_palette.resource_path)
	main.free()
	var dependency_audio := _audio_dependencies(export_roots)
	# Selected-resource exports do not discover every GDScript preload by themselves.
	# Explicitly retain preload scripts missing from the scene/resource closure.
	for path in resource_paths:
		if String(path).ends_with(".gd") and not dependency_resources.has(path): export_roots.append(path)
	dependency_audio = _audio_dependencies(export_roots)
	var paths: Array = used.keys()
	paths.sort()
	export_roots.sort()
	var presets := ConfigFile.new()
	assert(presets.load("res://export_presets.cfg") == OK)
	var web_presets: Array = []
	for section in presets.get_sections():
		if presets.get_value(section,"platform","") != "Web": continue
		var files: Array[String] = []
		for file_path in presets.get_value(section,"export_files",PackedStringArray()): files.append(String(file_path))
		files.sort()
		web_presets.append({"name":presets.get_value(section,"name",""),"filter":presets.get_value(section,"export_filter",""),"files":files,"audio_dependencies":_audio_dependencies(files)})
	var result := {"used_audio":paths,"references":used,"export_roots":export_roots,"dependency_audio":dependency_audio,"web_presets":web_presets}
	var output := "res://test-results/used-audio-scan.json"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): output = args[0]
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output,FileAccess.WRITE)
	assert(file != null,"Cannot write audio inventory: "+output)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("USED AUDIO ",paths.size()," references exported from ",export_roots.size()," roots")
	quit(0)

func _visit_node(node: Node,scene_path: String,scene_root: Node) -> void:
	var context := scene_path+":"+String(scene_root.get_path_to(node))
	for property in node.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_STORAGE:
			_visit_value(node.get(property.name),context+"."+String(property.name))
	for child in node.get_children(): _visit_node(child,scene_path,scene_root)

func _visit_value(value: Variant,context: String) -> void:
	if value is Resource:
		var resource: Resource = value
		var path: String = resource.resource_path
		if resource is AudioStream and not path.is_empty() and not "::" in path:
			if not used.has(path): used[path]=[]
			if not used[path].has(context): used[path].append(context)
		if resource_seen.has(resource.get_instance_id()): return
		resource_seen[resource.get_instance_id()]=true
		if not path.is_empty(): resource_paths[path]=true
		if resource is Script:
			for constant in resource.get_script_constant_map():
				_visit_value(resource.get_script_constant_map()[constant],context+"/constant:"+String(constant))
		for property in resource.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_STORAGE:
				_visit_value(resource.get(property.name),context+"/"+String(property.name))
	elif value is Array:
		for i in range(value.size()): _visit_value(value[i],context+"["+str(i)+"]")
	elif value is Dictionary:
		for key in value: _visit_value(value[key],context+"["+str(key)+"]")

func _audio_dependencies(roots: Array[String]) -> Array[String]:
	var queue: Array[String] = roots.duplicate()
	var visited := {}
	var audio := {}
	while not queue.is_empty():
		var path: String = queue.pop_back()
		if visited.has(path): continue
		visited[path]=true
		if path.get_extension().to_lower() in ["wav","ogg","mp3"]: audio[path]=true
		for raw in ResourceLoader.get_dependencies(path):
			var dependency := String(raw).split("::")[-1]
			if not dependency.begins_with("res://"): continue
			if dependency.get_extension().to_lower() in ["wav","ogg","mp3"]:
				audio[dependency]=true
			elif dependency.get_extension().to_lower() in ["tscn","tres","res","scn","gd"]:
				queue.append(dependency)
	var result: Array[String] = []
	for path in audio: result.append(path)
	result.sort()
	dependency_resources=visited
	return result

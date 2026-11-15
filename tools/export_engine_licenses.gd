extends SceneTree
## Include the engine's own notices when distributing a standalone executable.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Pass the destination license file after --")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(args[0].get_base_dir())
	var file := FileAccess.open(args[0],FileAccess.WRITE)
	if file == null:
		push_error("Cannot write engine notices: " + args[0])
		quit(1)
		return
	file.store_string("Godot Engine\n\n" + Engine.get_license_text())
	file.store_string("\n\nThird-party copyright notices\n\n" + JSON.stringify(Engine.get_copyright_info(),"\t"))
	for label in Engine.get_license_info():
		file.store_string("\n\n" + label + "\n\n" + Engine.get_license_info()[label])
	file.close()
	quit(0)

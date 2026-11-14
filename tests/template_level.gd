extends SceneTree
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	print("PASS " if value else "FAIL ",message)
	if not value: failures += 1
func run() -> void:
	await examine()
	for i in range(5): await process_frame
	await create_timer(.25).timeout
	quit(0 if failures==0 else 1)
func examine() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	check(game.main_level!=null and game.main_level.resource_path.begins_with("res://"),"project assigns a saved scene as its main level")
	game.main_level=load("res://scenes/levels/template.tscn")
	game.play_level("template")
	for i in range(60): await physics_frame
	check(game.player.is_on_floor() and game.player.position.y>0,"template spawn lands safely on collision geometry")
	check(game.sources.size()==2 and game.world.get_node("Geometry").get_child_count()>8,"template has simple editable geometry and two example emitters")
	check(game.surface_at(Vector3(0,1,16))=="gravel" and game.surface_at(Vector3(-11,1,-10))=="wood","template floor materials control footstep surfaces")
	check(game.map_data.landmarks.size()==2,"template static plan uses its authored landmarks")
	var custom = game.main_level.instantiate()
	custom.get_node("Spawn").rotation.y=.7
	var packed := PackedScene.new()
	check(packed.pack(custom)==OK,"template can be packed as a user-owned level")
	custom.free()
	game.main_level=packed
	game.main_level_title="My custom place"
	game.play_level("template")
	check(absf(game.player.rotation.y-.7)<.001 and game.level_title("template")=="My custom place","Inspector main scene/title and authored spawn heading are honored")
	for id in game.LEGACY_TITLES:
		check(FileAccess.file_exists("res://scenes/levels/legacy/"+id+".tscn") and not FileAccess.file_exists("res://scenes/levels/"+id+".tscn"),id+" moved to legacy")
		game.play_level(id)
		await physics_frame
		check(game.world.scene_file_path=="res://scenes/levels/legacy/"+id+".tscn",id+" remains playable")
	game._command("menu")
	game.queue_free()
	await process_frame
	print("TEMPLATE CHECKS: ","PASS" if failures==0 else "FAIL")

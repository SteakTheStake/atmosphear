extends Node3D
## Read-only display of the paths actually chosen by AcousticSource.
## Pulses illustrate direction at 8 m/s; they are not a wave simulation.
const MapView = preload("res://scripts/acoustic_map.gd")
const DIRECT := Color("65e3e9")
const BLOCKED := Color("ff707d")
const REFLECTED := Color("ffcc70")
const PULSE := Color("c39bff")
const MAX_REFLECTIONS := 4
const MAX_BOUNCES := 2
const PULSES_PER_SOURCE := MAX_REFLECTIONS+1
var path_mesh := ImmediateMesh.new()
var wire_mesh := ImmediateMesh.new()
var markers: Array = []
var bounce_markers: Array = []
var pulses: Array = []
var labels: Array = []
var path_material: StandardMaterial3D
var overlay: CanvasLayer
var map_view: Control
var enabled := false
var stats := {"source_count":0,"reflection_count":0,"segment_count":0}

func _ready() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color.BLACK
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 0.5
	environment.environment = settings
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50,-32,0)
	light.light_energy = 0.8
	light.shadow_enabled = false
	add_child(light)
	path_material = _material(Color.WHITE, true)
	path_material.vertex_color_use_as_albedo = true
	for mesh in [wire_mesh, path_mesh]:
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.layers = 2
		add_child(visual)
	overlay = CanvasLayer.new()
	overlay.layer = 4
	add_child(overlay)
	map_view = MapView.new()
	map_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(map_view)
	set_enabled(false)

func _material(color: Color, xray := true) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = xray
	return material

func _orb(radius: float, color: Color) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2
	sphere.radial_segments = 8
	sphere.rings = 4
	marker.mesh = sphere
	marker.material_override = _material(color)
	marker.layers = 2
	add_child(marker)
	return marker

func set_enabled(value: bool) -> void:
	enabled = value
	visible = value
	if overlay: overlay.visible = value

func clear() -> void:
	for group in [markers, bounce_markers, pulses, labels]:
		for item in group:
			item.hide()
			item.queue_free()
		group.clear()
	path_mesh.clear_surfaces()
	wire_mesh.clear_surfaces()
	stats = {"source_count":0,"reflection_count":0,"segment_count":0}
	if map_view:
		map_view.paths = []
		map_view.footprints = []

func rebuild(world: Node3D, sources: Array) -> void:
	clear()
	var wire_material := _material(Color("75877d"), false)
	wire_mesh.surface_begin(Mesh.PRIMITIVE_LINES, wire_material)
	var footprints: Array = []
	for body in world.find_children("*","StaticBody3D",true,false):
		if not body is StaticBody3D: continue
		for child in body.get_children():
			if not child is MeshInstance3D: continue
			var mesh: Mesh = child.mesh
			var vertices := mesh.get_faces()
			var unique := {}
			for i in range(0, vertices.size(), 3):
				for edge in [[0,1],[1,2],[2,0]]:
					var a: Vector3 = vertices[i+edge[0]]
					var b: Vector3 = vertices[i+edge[1]]
					var key := str(a) + ":" + str(b)
					var reverse := str(b) + ":" + str(a)
					if unique.has(key) or unique.has(reverse): continue
					unique[key] = true
					wire_mesh.surface_add_vertex(child.to_global(a+a.normalized()*0.008))
					wire_mesh.surface_add_vertex(child.to_global(b+b.normalized()*0.008))
			var bounds: AABB = child.global_transform * mesh.get_aabb()
			var low: Vector3 = bounds.position
			if bounds.size.y > 0.6 and low.y < 1.8 and bounds.end.y > .15:
				footprints.append(Rect2(low.x,low.z,bounds.size.x,bounds.size.z))
			elif body.position.y < 0:
				map_view.world_bounds = Rect2(low.x,low.z,bounds.size.x,bounds.size.z)
	wire_mesh.surface_end()
	map_view.footprints = footprints
	for sound in sources:
		markers.append(_orb(0.22,DIRECT))
		var label := Label3D.new()
		label.layers = 2
		label.font_size = 28
		label.outline_size = 6
		label.pixel_size = 0.001
		label.fixed_size = true
		label.no_depth_test = true
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(label)
		labels.append(label)
		for i in range(MAX_REFLECTIONS*MAX_BOUNCES): bounce_markers.append(_orb(0.12,REFLECTED))
		for i in range(PULSES_PER_SOURCE): pulses.append(_orb(0.10,PULSE))
	stats.source_count = sources.size()

func _line(a: Vector3, b: Vector3, color: Color, dashed := false) -> void:
	if dashed:
		var length := a.distance_to(b)
		var segments := maxi(1,ceili(length/0.45))
		for i in range(segments):
			if i % 2 == 0:
				_line(a.lerp(b,float(i)/segments),a.lerp(b,float(i+1)/segments),color)
		return
	path_mesh.surface_set_color(color)
	path_mesh.surface_add_vertex(a)
	path_mesh.surface_set_color(color)
	path_mesh.surface_add_vertex(b)
	stats.segment_count += 1

func _pulse_position(points: Array, time: float, phase: float) -> Vector3:
	var total := 0.0
	for i in range(points.size()-1): total += points[i].distance_to(points[i+1])
	var distance := fposmod(time*8.0+phase,maxf(total,0.01))
	for i in range(points.size()-1):
		var length: float = points[i].distance_to(points[i+1])
		if distance <= length: return points[i].lerp(points[i+1],distance/maxf(length,0.01))
		distance -= length
	return points[-1]

func update_view(sources: Array, ear: Vector3, yaw: float, time: float) -> void:
	if not enabled: return
	if sources.size() != markers.size(): return
	stats.segment_count = 0
	stats.reflection_count = 0
	for marker in bounce_markers: marker.hide()
	for pulse in pulses: pulse.hide()
	path_mesh.clear_surfaces()
	if sources.is_empty(): return
	path_mesh.surface_begin(Mesh.PRIMITIVE_LINES,path_material)
	var map_paths: Array = []
	for i in range(sources.size()):
		var sound = sources[i]
		var data: Dictionary = sound.get_debug_paths()
		var source: Vector3 = sound.global_position
		var blocked: bool = data.get("center_blocked",false)
		var color := BLOCKED if blocked else DIRECT
		markers[i].position = source
		markers[i].material_override.albedo_color = color
		labels[i].position = source+Vector3(0,0.65,0)
		labels[i].text = "%s  %.1f m" % [String(sound.get_meta("clip")).replace("_"," "),source.distance_to(ear)]
		labels[i].modulate = color
		if not sound.direct.playing or sound.direct.stream_paused:
			markers[i].material_override.albedo_color = Color("75877d")
			labels[i].modulate = Color("75877d")
			continue
		_line(source,ear,color,blocked)
		var direct_end: Vector3 = data.obstruction_point if blocked and data.obstruction_point != null else ear
		var direct_pulse = pulses[i*PULSES_PER_SOURCE]
		direct_pulse.show()
		direct_pulse.position = _pulse_position([source,direct_end],time,i*3.0)
		direct_pulse.visible = direct_pulse.position.distance_to(ear) > 0.6
		if blocked:
			var hit: Vector3 = direct_end
			_line(hit-Vector3(.2,.2,0),hit+Vector3(.2,.2,0),BLOCKED)
			_line(hit-Vector3(.2,-.2,0),hit+Vector3(.2,-.2,0),BLOCKED)
		map_paths.append({"points":[source,ear],"color":color,"dashed":blocked,"source":true,"pulse":direct_pulse.position})
		var j := 0
		for reflection in data.reflections:
			if j >= MAX_REFLECTIONS: break
			var bounces: Array = reflection.get("points",[reflection.point])
			var chain: Array = [source]
			chain.append_array(bounces)
			chain.append(ear)
			for segment in range(chain.size()-1): _line(chain[segment],chain[segment+1],REFLECTED)
			for bounce in range(mini(bounces.size(),MAX_BOUNCES)):
				var marker_index := (i*MAX_REFLECTIONS+j)*MAX_BOUNCES+bounce
				bounce_markers[marker_index].show()
				bounce_markers[marker_index].position = bounces[bounce]
			var pulse = pulses[i*PULSES_PER_SOURCE+j+1]
			pulse.show()
			pulse.position = _pulse_position(chain,time,i*3.0)
			pulse.visible = pulse.position.distance_to(ear) > 0.6
			map_paths.append({"points":chain,"color":REFLECTED,"dashed":false,"source":false,"pulse":pulse.position})
			j += 1
			stats.reflection_count += 1
	path_mesh.surface_end()
	map_view.paths = map_paths
	map_view.listener_position = ear
	map_view.yaw = yaw
	var viewport := get_viewport().get_visible_rect().size
	var side := minf(290,viewport.x*0.38)
	map_view.size = Vector2(side,side)
	map_view.position = Vector2(viewport.x-side-18,viewport.y-side-18)
	map_view.queue_redraw()

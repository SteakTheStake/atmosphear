extends Control
## XZ projection makes source-to-listener paths readable from a first-person view.
var paths: Array = []
var footprints: Array = []
var world_bounds := Rect2(-24,-24,48,48)
var listener_position := Vector3.ZERO
var yaw := 0.0

func _point(v: Vector3) -> Vector2:
	var scale := minf((size.x-28)/world_bounds.size.x,(size.y-42)/world_bounds.size.y)
	return Vector2(14,30)+(Vector2(v.x,v.z)-world_bounds.position)*scale

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color(0.025,0.04,0.045,0.94))
	draw_rect(Rect2(Vector2.ZERO,size),Color("75877d"),false,1)
	draw_string(ThemeDB.fallback_font,Vector2(12,19),"ACOUSTIC PATHS / TOP VIEW",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("cfdfd5"))
	for footprint in footprints:
		var start := _point(Vector3(footprint.position.x,0,footprint.position.y))
		var end := _point(Vector3(footprint.end.x,0,footprint.end.y))
		draw_rect(Rect2(start,end-start),Color("47564e"))
	for path in paths:
		var points: Array = path.points
		for i in range(points.size()-1):
			var a := _point(points[i])
			var b := _point(points[i+1])
			if path.dashed: draw_dashed_line(a,b,path.color,1.3,4)
			else: draw_line(a,b,path.color,1.3,true)
		if path.source: draw_circle(_point(points[0]),3.5,path.color)
		elif points.size()>2: draw_circle(_point(points[1]),2.5,path.color)
		draw_circle(_point(path.pulse),2.3,Color("c39bff"))
	var center := _point(listener_position)
	var forward := Vector2(-sin(yaw),-cos(yaw))
	var right := Vector2(-forward.y,forward.x)
	draw_colored_polygon(PackedVector2Array([center+forward*8,center-forward*5+right*5,center-forward*5-right*5]),Color.WHITE)

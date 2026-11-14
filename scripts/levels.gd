extends RefCounted
## Flat boxes and six-sided trunks provide both collision and acoustic surfaces.
static func box(pos: Vector3, size: Vector3, absorption := 0.15) -> Dictionary:
	return {"pos":pos,"size":size,"absorption":absorption}
static func source(clip: String, pos: Vector3, db := -5.0, motion := 0.0) -> Dictionary:
	return {"clip":clip,"pos":pos,"db":db,"motion":motion}
static func bounds(parts: Array, x: float, z: float, height: float, ceiling: bool, absorption: float) -> void:
	parts.append(box(Vector3(0,-0.25,0),Vector3(x*2,0.5,z*2),absorption))
	parts.append(box(Vector3(-x,height/2,0),Vector3(0.5,height,z*2),absorption))
	parts.append(box(Vector3(x,height/2,0),Vector3(0.5,height,z*2),absorption))
	parts.append(box(Vector3(0,height/2,-z),Vector3(x*2,height,0.5),absorption))
	parts.append(box(Vector3(0,height/2,z),Vector3(x*2,height,0.5),absorption))
	if ceiling: parts.append(box(Vector3(0,height,0),Vector3(x*2,0.3,z*2),absorption))
static func build(id: String) -> Dictionary:
	var parts: Array = []
	var trees: Array = []
	var sounds: Array = []
	var surfaces: Array = []
	var start := Vector3(0,1,10)
	match id:
		"forest":
			bounds(parts,22,24,1.8,false,0.92)
			parts.append(box(Vector3(-14,0.45,-4),Vector3(1,0.9,30),0.55))
			for pos in [Vector3(-8,3,4),Vector3(-4,3,-7),Vector3(5,3,3),Vector3(8,3,-3),Vector3(-7,3,-13),Vector3(3,3,-18),Vector3(16,3,8),Vector3(-10,3,15),Vector3(12,3,18),Vector3(-3,3,19),Vector3(18,3,-18)]:
				trees.append(box(pos,Vector3(1.2,6,1.2),0.65))
			# Shelter with a two-meter doorway and roof.
			for p in [box(Vector3(6,1.6,-10),Vector3(.3,3.2,8),.4),box(Vector3(14,1.6,-10),Vector3(.3,3.2,8),.4),box(Vector3(10,1.6,-14),Vector3(8,3.2,.3),.4),box(Vector3(7.5,1.6,-6),Vector3(3,3.2,.3),.4),box(Vector3(12.5,1.6,-6),Vector3(3,3.2,.3),.4),box(Vector3(10,3.2,-10),Vector3(8,.3,8),.35)]: parts.append(p)
			surfaces.append({"rect":Rect2(6,-14,8,8),"surface":"wood"})
			sounds = [source("forest_stream",Vector3(-18,.8,-6),2),source("forest_wind",Vector3(10,6,-18),3),source("forest_birds",Vector3(-8,5,2),-4),source("forest_birds",Vector3(16,5,-13),-10)]
		"cistern":
			bounds(parts,12,17,6,true,0.09)
			start = Vector3(0,1,12)
			parts.append(box(Vector3(-7,3,0),Vector3(10,6,.6),.08))
			parts.append(box(Vector3(7,3,0),Vector3(10,6,.6),.08))
			for x in [-6,6]:
				for z in [-9,7]: parts.append(box(Vector3(x,3,z),Vector3(1.2,6,1.2),.1))
			parts.append(box(Vector3(-9,.5,-10),Vector3(2,1,9),.16))
			surfaces.append({"rect":Rect2(-1.5,-15,3,9),"surface":"wood"})
			sounds = [source("cistern_drips",Vector3(7,3,-7),0),source("cistern_water",Vector3(-7,.5,-12),1),source("cistern_air",Vector3(9,3,12),-12)]
		"freighter":
			bounds(parts,15,24,4.5,true,0.12)
			start = Vector3(0,1,17)
			for x in [-7,7]:
				for z in [-12,-3,6]: parts.append(box(Vector3(x,1.7,z),Vector3(5,3.4,5),.18))
			parts.append(box(Vector3(-9,2.25,-19),Vector3(12,4.5,.4),.1))
			parts.append(box(Vector3(9,2.25,-19),Vector3(12,4.5,.4),.1))
			sounds = [source("freighter_engine",Vector3(-11,2,-21),6),source("freighter_vent",Vector3(12,3,8),1),source("freighter_electronics",Vector3(0,3.9,-12),-6,.65)]
		"courtyard":
			bounds(parts,17,17,7,false,0.18)
			parts.append(box(Vector3(11,3.4,0),Vector3(11,.35,34),.16))
			for z in [-13,-6,1,8,15]: parts.append(box(Vector3(6,1.7,z),Vector3(.65,3.4,.65),.12))
			parts.append(box(Vector3(-3,1.3,-4),Vector3(5,2.6,1.2),.1))
			parts.append(box(Vector3(-10,.5,7),Vector3(4,1,2),.3))
			surfaces.append({"rect":Rect2(7,-16,9,32),"surface":"wood"})
			sounds = [source("courtyard_rain",Vector3(-7,2,-9),4),source("courtyard_rain",Vector3(-10,2,12),-1),source("courtyard_drain",Vector3(4,.4,-13),1),source("courtyard_wind",Vector3(-13,5,-14),-2)]
	return {"boxes":parts,"trees":trees,"sources":sounds,"surfaces":surfaces,"start":start}

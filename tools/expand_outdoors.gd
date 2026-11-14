extends SceneTree
## Reproducible authoring of the two expanded outdoor worlds; runtime loads TSCN.
const W = preload("res://tools/world_author.gd")

func _initialize() -> void:
	_forest()
	_courtyard()
	quit()

func loop_at(scene: Node3D, name: String, clip: String, pos: Vector3, db: float, near := 3.0, range_m := 25.0, budget := 0, landmark := false) -> void:
	W.source(scene,name,clip,pos,db,{"loop":true,"near":near,"range":range_m,"budget":budget,"landmark":landmark})

func event_at(scene: Node3D, name: String, clip: String, pos: Vector3, db: float, seconds := Vector2(9,24), near := 3.0, range_m := 24.0, budget := 0, landmark := false) -> void:
	W.source(scene,name,clip,pos,db,{"loop":false,"interval_min":seconds.x,"interval_max":seconds.y,"near":near,"range":range_m,"budget":budget,"landmark":landmark,"pitch_min":.96,"pitch_max":1.04})

func _forest() -> void:
	var s := W.create("forest","Forest & lake",Rect2(-54,-54,108,108),Vector3(0,1,44),"gravel")
	# A central timber route has side openings into the grove and reed marsh.
	W.surface(s,"LongBoardwalk",Rect2(-4,-8,8,40),"wood")
	W.surface(s,"WetlandSpur",Rect2(4,13,22,6),"wood")
	for x in [-4.3,4.3]:
		W.box(s,"RailSouth"+str(x),Vector3(x,.55,27),Vector3(.22,1.1,10),"wood",.5)
		W.box(s,"RailNorth"+str(x),Vector3(x,.55,2),Vector3(.22,1.1,20),"wood",.5)
	for z in [12.7,19.3]:
		W.box(s,"SpurRail"+str(z),Vector3(15,.55,z),Vector3(21,1.1,.22),"wood",.5)
	# The west-facing cove is bounded by irregular coarse rock faces. Its path
	# remains at ground height; the stone mouth changes the waterfall reflections.
	for entry in [[Vector3(-49,4,-31),Vector3(4,8,31)],[Vector3(-35,5,-47),Vector3(30,10,4)],[Vector3(-19,3,-39),Vector3(5,6,13)],[Vector3(-42,1.1,-16),Vector3(7,2.2,5)]]:
		W.box(s,"CoveRock"+str(s.get_node("Geometry").get_child_count()),entry[0],entry[1],"stone",.12)
	W.surface(s,"CoveStoneShore",Rect2(-42,-40,22,25),"stone")
	W.room(s,"TimberHut",Rect2(20,-38,18,20),3.5,"wood",{"south":Vector2(29,4),"east":Vector2(-28,3.5)},true,.42)
	W.surface(s,"HutTimberFloor",Rect2(20,-38,18,20),"wood")
	W.box(s,"HutBench",Vector3(23,.4,-32),Vector3(1.4,.8,7),"wood",.5)
	W.box(s,"HutFireplace",Vector3(33,.7,-36),Vector3(3,1.4,2),"stone",.16)
	# Candidate tree positions are filtered against all authored routes, keeping
	# audible destinations connected by broad, walkable corridors.
	var routes := [[Vector2(0,44),Vector2(0,-8)],[Vector2(0,20),Vector2(-29,20)],[Vector2(-29,20),Vector2(-30,-28)],[Vector2(0,-8),Vector2(-30,-20)],[Vector2(0,-8),Vector2(29,-16)],[Vector2(29,-16),Vector2(29,-30)],[Vector2(0,16),Vector2(32,16)],[Vector2(0,40),Vector2(32,30)],[Vector2(32,30),Vector2(32,16)],[Vector2(32,16),Vector2(41,-28)],[Vector2(41,-28),Vector2(29,-28)]]
	var candidates := [Vector2(-13,39),Vector2(13,39),Vector2(-17,30),Vector2(17,32),Vector2(-41,29),Vector2(-36,11),Vector2(-22,12),Vector2(-41,8),Vector2(-20,27),Vector2(-39,23),Vector2(-27,34),Vector2(-46,15),Vector2(-16,3),Vector2(-36,-1),Vector2(-22,-5),Vector2(-42,-7),Vector2(-12,-16),Vector2(9,-4),Vector2(14,-15),Vector2(9,-24),Vector2(12,-36),Vector2(17,-45),Vector2(41,-43),Vector2(47,-12),Vector2(42,4),Vector2(48,18),Vector2(40,30),Vector2(23,26),Vector2(17,7),Vector2(25,4),Vector2(39,40),Vector2(25,44),Vector2(-8,6),Vector2(10,25),Vector2(-9,-35),Vector2(-5,-47),Vector2(7,-47),Vector2(-43,43),Vector2(-29,45),Vector2(47,45)]
	var index := 0
	for point in candidates:
		var clear := true
		for segment in routes:
			if Geometry2D.get_closest_point_to_segment(point,segment[0],segment[1]).distance_to(point) < 3.5: clear=false
		if clear:
			W.tree(s,"Tree%02d"%index,Vector3(point.x,0,point.y),.6+float(index%3)*.12,6.5+float(index%4)*.6)
			if index%3 == 0:
				loop_at(s,"TreeRustle%02d"%index,"tree_rustle",Vector3(point.x+1.3,4.4,point.y),-2,2.8,16,0)
				s.get_node("Sources/TreeRustle%02d"%index).set_meta("attached_geometry","Tree%02dCanopy"%index)
			index+=1
	# Southern entry clearing: broad wind and sparse bird details.
	loop_at(s,"ClearingWindBeacon","forest_wind",Vector3(-9,3,40),7,6,45,1,true)
	loop_at(s,"ClearingLeaves","tree_rustle",Vector3(12,3,35),-3,3,22)
	event_at(s,"ClearingBird","bird4",Vector3(-12,3.5,45),-8,Vector2(18,35),3,22)
	event_at(s,"ClearingOak","tree_creak",Vector3(-13,1.8,38),-3,Vector2(15,30),3,24)
	# Western grove: a repeating species establishes a stable acoustic bearing.
	event_at(s,"GroveBirdBeacon","bird0",Vector3(-32,3.4,20),2,Vector2(4,8),6,48,1,true)
	event_at(s,"GroveBirdEast","bird1",Vector3(-23,3.6,13),-5,Vector2(9,18),3,22)
	event_at(s,"GroveBirdWest","bird2",Vector3(-41,3.4,22),-7,Vector2(11,25),3,21)
	event_at(s,"GroveBirdNorth","bird3",Vector3(-34,3.8,5),-6,Vector2(13,27),3,24)
	loop_at(s,"GroveCanopy","tree_rustle",Vector3(-39,4,14),-6,3,22)
	# Boardwalk: tactile floor change and a repeatable, hollow beam creak.
	event_at(s,"BoardwalkCreakBeacon","tree_creak",Vector3(2,.7,8),1,Vector2(5,10),5,42,1,true)
	loop_at(s,"BoardwalkWater","water_lap",Vector3(-6,.6,1),-3,4,27)
	event_at(s,"SpurBeam","tree_creak",Vector3(17,.7,14),-5,Vector2(13,24),3,20)
	loop_at(s,"SpurReeds","insects",Vector3(25,1.4,10),-12,3,20)
	# Cove: the only broad waterfall roar; quieter lapping appears on approach.
	loop_at(s,"WaterfallBeacon","landmark_waterfall",Vector3(-44,3,-38),-2,8,68,3,true)
	loop_at(s,"CoveLapping","water_lap",Vector3(-39,.6,-27),-2,4,27,1)
	loop_at(s,"CoveOutlet","forest_stream",Vector3(-34,.6,-14),-1,4,31)
	event_at(s,"CliffDrip","drip1",Vector3(-45,2,-23),-5,Vector2(7,17),3,18,1)
	event_at(s,"CoveBird","bird4",Vector3(-25,3,-34),-8,Vector2(18,35),3,23)
	# Roofed hut: the outside wind is filtered by its real roof and walls.
	event_at(s,"HutRafterCreak","tree_creak",Vector3(29,3,-29),-1,Vector2(13,25),3,25,1)
	event_at(s,"HutLeakBeacon","drip0",Vector3(31,2,-32),3,Vector2(4,9),5,44,2,true)
	loop_at(s,"HutRoofWind","forest_wind",Vector3(27,5,-31),4,4,30)
	event_at(s,"HutOutsideBird","bird3",Vector3(41,3.4,-24),-8,Vector2(18,32),3,22)
	# Wetland: frogs and insects contrast strongly with the dry western grove.
	loop_at(s,"WetlandInsectBeacon","insects",Vector3(35,1.2,27),-3,6,46,0,true)
	event_at(s,"WetlandFrogBeacon","landmark_frog",Vector3(32,.7,20),1,Vector2(4,10),5,44,1,true)
	loop_at(s,"WetlandPool","water_lap",Vector3(40,.5,20),-5,3,24)
	event_at(s,"WetlandTree","tree_creak",Vector3(42,1.5,32),-8,Vector2(20,35),3,21)
	event_at(s,"WetlandBird","bird2",Vector3(25,3.3,34),-9,Vector2(20,38),3,22)
	W.landmark(s,"Entry clearing",Vector3(0,0,40),"wind")
	W.landmark(s,"Bird grove",Vector3(-30,0,20),"birds")
	W.landmark(s,"Creaking boardwalk",Vector3(0,0,8),"wood")
	W.landmark(s,"Waterfall cove",Vector3(-33,0,-28),"water")
	W.landmark(s,"Timber hut",Vector3(29,0,-28),"shelter")
	W.landmark(s,"Frog wetland",Vector3(32,0,24),"water")
	W.region(s,"Entry clearing",Rect2(-14,30,28,22),"Open wind over gravel, with distant grove birds.",[Vector3(0,1,44),Vector3(0,1,36),Vector3(0,1,27)])
	W.region(s,"Bird grove",Rect2(-47,3,31,30),"Distinct repeating bird calls in a sheltered grove.",[Vector3(-30,1,20),Vector3(-30,1,7),Vector3(-30,1,20),Vector3(-18,1,20),Vector3(0,1,20)])
	W.region(s,"Creaking boardwalk",Rect2(-5,-8,10,40),"Wooden footfalls, hollow creaks, close lapping water.",[Vector3(0,1,4),Vector3(0,1,-6),Vector3(0,1,4),Vector3(0,1,16),Vector3(0,1,28)])
	W.region(s,"Waterfall cove",Rect2(-47,-44,29,31),"Broad waterfall roar and stone-reflected spray; lapping at the shore.",[Vector3(-32,1,-32),Vector3(-30,1,-20),Vector3(-30,1,-9),Vector3(-30,1,7)])
	W.region(s,"Timber hut",Rect2(20,-38,18,20),"Muted outdoor wind, timber floor and a rhythmic roof leak beside quiet rafter creaks.",[Vector3(29,1,-31),Vector3(29,1,-24),Vector3(29,1,-16),Vector3(16,1,-15),Vector3(0,1,-8)])
	W.region(s,"Frog wetland",Rect2(23,7,26,35),"Frog croaks, continuous insects and reed-side lapping.",[Vector3(32,1,30),Vector3(32,1,24),Vector3(28,1,16),Vector3(15,1,16),Vector3(0,1,16)])
	W.save(s,"forest")
	s.free()

func _courtyard() -> void:
	var s := W.create("courtyard","Rain courtyard",Rect2(-54,-54,108,108),Vector3(0,1,44),"stone")
	W.room(s,"BellGate",Rect2(-11,32,22,20),7,"stone",{"north":Vector2(0,6),"south":Vector2(0,6)},true,.13)
	W.box(s,"BellCrossbeam",Vector3(0,8.2,42),Vector3(9,.5,.6),"wood",.4)
	W.surface(s,"GateFloor",Rect2(-11,32,22,20),"stone")
	# Low planters shape an open plaza while leaving wide north/south and lateral routes.
	for x in [-14,14]:
		for z in [7,26]: W.box(s,"SquarePlanter"+str(x)+str(z),Vector3(x,.5,z),Vector3(5,1,3),"stone",.25)
	W.room(s,"WestCloister",Rect2(-50,-6,21,36),4.5,"stone",{"east":Vector2(15,5),"north":Vector2(-39.5,5),"south":Vector2(-39.5,5)},true,.11)
	W.surface(s,"CloisterFloor",Rect2(-50,-6,21,36),"stone")
	for z in [1,9,22]: W.box(s,"CloisterPillar"+str(z),Vector3(-45,2.25,z),Vector3(1.1,4.5,1.1),"stone",.1)
	W.box(s,"CloisterBench",Vector3(-48,.45,15),Vector3(1.2,.9,9),"wood",.45)
	# Open fountain court can be entered from the square, cloister, or tower.
	W.room(s,"FountainCourt",Rect2(-22,-46,44,34),5,"stone",{"south":Vector2(0,7),"west":Vector2(-28,5),"east":Vector2(-28,5)},false,.13)
	W.box(s,"FountainBasin",Vector3(0,.55,-29),Vector3(7,1.1,7),"stone",.12)
	W.box(s,"FountainColumn",Vector3(0,2.1,-29),Vector3(1.1,3.1,1.1),"stone",.12)
	for x in [-15,15]: W.box(s,"CourtBench"+str(x),Vector3(x,.5,-41),Vector3(8,1,1.5),"stone",.15)
	W.room(s,"TimberStable",Rect2(29,2,22,27),4,"wood",{"west":Vector2(15,5),"north":Vector2(39,5)},true,.45)
	W.surface(s,"StableFloor",Rect2(29,2,22,27),"wood")
	for z in [8,21]: W.box(s,"StableStall"+str(z),Vector3(46,1.2,z),Vector3(9,2.4,.35),"wood",.5)
	W.box(s,"StableFeedTrough",Vector3(49,.45,14),Vector3(1,.9,7),"wood",.5)
	W.room(s,"WindTower",Rect2(29,-45,19,24),8,"stone",{"south":Vector2(38.5,5),"west":Vector2(-30,5)},false,.17)
	for z in [-39,-28]: W.box(s,"TowerRoofBeam"+str(z),Vector3(38.5,8,z),Vector3(19,.4,.5),"wood",.4)
	W.surface(s,"TowerMetalGrate",Rect2(33,-39,11,12),"metal")
	# A sheltered western link and eastern gravel lane connect the northern courts.
	W.surface(s,"EastGravelLane",Rect2(29,-21,20,23),"gravel")
	W.box(s,"WestPassageRoof",Vector3(-37,3.8,-17),Vector3(18,.3,21),"wood",.38)
	W.box(s,"WestPassageOuterWall",Vector3(-46,1.9,-17),Vector3(.4,3.8,21),"stone",.16)
	# Gate identity: an unmistakable fixed tower bell, muffled under its roof.
	loop_at(s,"BellGateBeacon","landmark_bell",Vector3(0,9,42),-3,8,76,2,true)
	loop_at(s,"GateExteriorRain","courtyard_rain",Vector3(-16,2,42),-4,4,32)
	loop_at(s,"GateSlotWind","courtyard_wind",Vector3(9,5,36),-2,3,24,1)
	event_at(s,"GateIronCreak","metal_creak",Vector3(-7,2,34),-6,Vector2(13,26),3,22,1)
	# Open rain square, with a distinct gurgling east-side drain.
	loop_at(s,"SquareRainBeacon","courtyard_rain",Vector3(-13,2,16),1,7,46,1,true)
	loop_at(s,"SquareDrainBeacon","courtyard_drain",Vector3(18,.5,10),0,5,36,1,true)
	loop_at(s,"SquareRainEast","courtyard_rain",Vector3(22,2,25),-5,3,24)
	event_at(s,"SquareDrip","drip0",Vector3(-16,1,8),-4,Vector2(7,15),3,17)
	event_at(s,"SquareGrateTick","pipe_tick",Vector3(17,.8,12),-7,Vector2(13,28),2,15)
	# Cloister: dry stone footsteps and an echoing leak interrupt the rain outside.
	event_at(s,"CloisterLeakBeacon","drip2",Vector3(-39,3,6),3,Vector2(3,7),6,43,3,true)
	event_at(s,"CloisterEndDrip","drip0",Vector3(-47,2,26),-5,Vector2(7,18),3,22,1)
	event_at(s,"CloisterBenchCreak","tree_creak",Vector3(-47,1,13),-5,Vector2(16,30),3,22,1)
	loop_at(s,"CloisterOutsideRain","courtyard_rain",Vector3(-26,2,12),-4,4,30)
	# Fountain court: continuous splashing around a physical basin and column.
	loop_at(s,"FountainBeacon","landmark_fountain",Vector3(1.1,2.4,-29),3,7,58,3,true)
	loop_at(s,"FountainPoolLap","water_lap",Vector3(-2.5,1.2,-28),-4,3,23,1)
	event_at(s,"FountainBird","bird0",Vector3(15,3.5,-40),-8,Vector2(18,35),3,24)
	event_at(s,"FountainDrainDrip","drip1",Vector3(5,.4,-33),-5,Vector2(9,20),3,18,1)
	# Stable: wooden walking surface and horse snorts separated from the weather.
	event_at(s,"StableHorseBeacon","landmark_horse",Vector3(45,1.4,14),2,Vector2(7,12),6,43,2,true)
	event_at(s,"StableBeam","tree_creak",Vector3(38,3.4,18),-2,Vector2(9,20),4,27,1)
	event_at(s,"StableHinge","metal_creak",Vector3(30,2,18),-5,Vector2(17,30),3,19)
	loop_at(s,"StableRoofWind","courtyard_wind",Vector3(42,5.5,13),-2,4,29)
	event_at(s,"StableEaveDrip","drip2",Vector3(30,2,4),-4,Vector2(7,16),3,19,1)
	# Tower: exposed gusts, ringing iron, and a metal floor under an open crown.
	loop_at(s,"TowerGustBeacon","courtyard_wind",Vector3(38,6,-34),5,8,59,2,true)
	event_at(s,"TowerIronBeacon","metal_creak",Vector3(39,3,-38),1,Vector2(5,11),5,37,2,true)
	event_at(s,"TowerStoneDrip","drip1",Vector3(45,3,-25),-5,Vector2(8,18),3,20,1)
	event_at(s,"TowerBird","bird4",Vector3(31,6,-42),-9,Vector2(18,35),3,24)
	loop_at(s,"TowerRainSlot","courtyard_rain",Vector3(50,3,-31),-5,3,23)
	W.landmark(s,"Bell gate",Vector3(0,0,42),"bell")
	W.landmark(s,"Rain square",Vector3(0,0,16),"rain")
	W.landmark(s,"Covered cloister",Vector3(-39,0,12),"shelter")
	W.landmark(s,"Fountain court",Vector3(0,0,-29),"water")
	W.landmark(s,"Timber stable",Vector3(40,0,15),"wood")
	W.landmark(s,"Wind tower",Vector3(38,0,-33),"wind")
	W.region(s,"Bell gate",Rect2(-11,32,22,20),"A fixed tower bell over a roofed stone gatehouse.",[Vector3(0,1,44),Vector3(0,1,35),Vector3(0,1,28)])
	W.region(s,"Rain square",Rect2(-23,2,46,29),"Open rainfall and a close, gurgling east-side drain.",[Vector3(0,1,16),Vector3(0,1,28),Vector3(0,1,16),Vector3(-20,1,16),Vector3(20,1,16),Vector3(0,1,3)])
	W.region(s,"Covered cloister",Rect2(-50,-6,21,36),"Rain recedes beneath stone roofing; a periodic leak echoes along the corridor.",[Vector3(-39,1,15),Vector3(-33,1,15),Vector3(-20,1,15),Vector3(-33,1,15),Vector3(-39,1,15),Vector3(-39,1,-1),Vector3(-39,1,-11)])
	W.region(s,"Fountain court",Rect2(-22,-46,44,34),"Continuous fountain splashes, stone boundaries and an open sky.",[Vector3(-8,1,-25),Vector3(-8,1,-35),Vector3(-8,1,-25),Vector3(0,1,-18),Vector3(0,1,-8),Vector3(0,1,3)])
	W.region(s,"Timber stable",Rect2(29,2,22,27),"Wooden footfalls, sheltered beam creaks and distinctive horse snorts.",[Vector3(39,1,15),Vector3(32,1,15),Vector3(20,1,15),Vector3(32,1,15),Vector3(39,1,15),Vector3(39,1,5),Vector3(39,1,-3)])
	W.region(s,"Wind tower",Rect2(29,-45,19,24),"A strong gust beacon over metallic footfalls and rattling iron.",[Vector3(38.5,1,-34),Vector3(25,1,-30),Vector3(38.5,1,-34),Vector3(38.5,1,-24),Vector3(39,1,-17),Vector3(39,1,-3)])
	W.save(s,"courtyard")
	s.free()

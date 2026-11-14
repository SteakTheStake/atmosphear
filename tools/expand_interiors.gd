extends SceneTree
## Authoring helper only. Runtime instantiates the saved editable level scenes.
const W = preload("res://tools/world_author.gd")
const BOUNDS := Rect2(-45,-55,90,110)
const ROOMS := {
	"NW":Rect2(-39,-49,34,30), "NE":Rect2(5,-49,34,30),
	"W":Rect2(-39,-15,34,30), "E":Rect2(5,-15,34,30),
	"SW":Rect2(-39,19,34,30), "SE":Rect2(5,19,34,30)
}

func _initialize() -> void:
	call_deferred("author")

func shells(scene: Node3D, heights: Dictionary, materials: Dictionary, absorption: Dictionary) -> void:
	var doors := {
		"NW":{"east":Vector2(-34,8),"south":Vector2(-22,7)},
		"NE":{"west":Vector2(-34,8),"south":Vector2(22,7)},
		"W":{"east":Vector2(0,8),"north":Vector2(-22,7),"south":Vector2(-22,7)},
		"E":{"west":Vector2(0,8),"north":Vector2(22,7),"south":Vector2(22,7)},
		"SW":{"east":Vector2(34,8),"north":Vector2(-22,7)},
		"SE":{"west":Vector2(34,8),"north":Vector2(22,7)}
	}
	for key in ROOMS:
		W.room(scene,"Chamber"+key,ROOMS[key],heights[key],materials[key],doors[key],true,absorption[key])
	# A low spine, cross passages, and perimeter ambulatory connect the tall rooms.
	# Doorways align across the four-meter gaps; each room has at least two exits.
	W.box(scene,"SpineCeiling",Vector3(0,4.35,0),Vector3(10,.3,104),"stone" if scene.name == "Cistern" else "metal",.23)
	for z in [-17,17]: W.box(scene,"CrossPassageRoof"+str(z),Vector3(0,4.35,z),Vector3(78,.3,4),"stone" if scene.name == "Cistern" else "metal",.25)
	for z in [-52,52]: W.box(scene,"PerimeterRoofZ"+str(z),Vector3(0,4.35,z),Vector3(90,.3,6),"stone" if scene.name == "Cistern" else "metal",.3)
	for x in [-42,42]: W.box(scene,"PerimeterRoofX"+str(x),Vector3(x,4.35,0),Vector3(6,.3,110),"stone" if scene.name == "Cistern" else "metal",.3)

func fixed(scene: Node3D, name: String, clip: String, position: Vector3, db: float, budget := 2, looped := true) -> void:
	W.source(scene,name,clip,position,db,{"loop":looped,"landmark":true,"budget":budget,"near":7.0,"range":62.0,"interval_min":8.0,"interval_max":12.0,"pitch_min":1.0,"pitch_max":1.0,"gain_variation_db":0.0})
	W.landmark(scene,name,position,"sound")

func detail(scene: Node3D, name: String, clip: String, position: Vector3, db := -13.0, looped := false, budget := 1) -> void:
	W.source(scene,name,clip,position,db,{"loop":looped,"budget":budget,"near":2.5,"range":21.0,"interval_min":9.0,"interval_max":27.0,"pitch_min":.96,"pitch_max":1.04,"gain_variation_db":2.0})

func cistern() -> void:
	var scene := W.create("cistern","Stone cistern",BOUNDS,Vector3(22,1,34),"stone")
	shells(scene,{"NW":10.0,"NE":7.0,"W":4.4,"E":4.0,"SW":3.2,"SE":8.0},{"NW":"stone","NE":"stone","W":"stone","E":"wood","SW":"stone","SE":"stone"},{"NW":.075,"NE":.13,"W":.12,"E":.43,"SW":.25,"SE":.15})
	W.surface(scene,"PumpTimberDeck",Rect2(5.5,-14.5,33,29),"wood")
	W.surface(scene,"OverflowGravel",Rect2(-38,30,32,18),"gravel")
	W.surface(scene,"ReservoirBoardwalk",Rect2(6,-48,8,28),"wood")
	W.surface(scene,"BellThreshold",Rect2(-38,-24,32,4),"metal")
	# Large silhouettes and open walkways make room shapes understandable by echoes.
	for x in [-31,-13]:
		for z in [-8,8]: W.box(scene,"GalleryPillar%s_%s"%[x,z],Vector3(x,2.2,z),Vector3(1.2,4.4,1.2),"stone",.11)
	W.box(scene,"ReservoirBasin",Vector3(29,.3,-40),Vector3(11,.6,12),"stone",.18)
	W.box(scene,"ReservoirBench",Vector3(31,.5,-23),Vector3(8,1,1.5),"stone",.2)
	W.box(scene,"PumpHousing",Vector3(30,1.3,3),Vector3(4,2.6,5),"metal",.18)
	W.box(scene,"PumpWorktable",Vector3(17,.6,-9),Vector3(5,1.2,2),"wood",.4)
	W.box(scene,"OverflowDivider",Vector3(-26,1.6,34),Vector3(.45,3.2,18),"stone",.22)
	W.box(scene,"AirshaftPedestal",Vector3(30,1,39),Vector3(5,2,5),"stone",.14)
	for x in [-30,-26]: W.box(scene,"BellFrame"+str(x),Vector3(x,3.8,-41),Vector3(.5,7.6,.5),"wood",.35)
	W.box(scene,"BellFrameHeader",Vector3(-28,7.5,-41),Vector3(4.5,.5,.6),"wood",.35)
	# The first source remains the drips fixture used by acoustic regression tests.
	fixed(scene,"Drip gallery","cistern_drips",Vector3(-26,3.3,-5),1,2)
	fixed(scene,"Bell vault","landmark_bell",Vector3(-28,5.5,-40),-3,4)
	fixed(scene,"Resonant reservoir","landmark_water_resonance",Vector3(29,.9,-40),3,3)
	fixed(scene,"Timber pump room","landmark_pump",Vector3(27.5,1.8,3),1,2)
	fixed(scene,"Overflow drain","courtyard_drain",Vector3(-25.4,.7,39),0,2)
	fixed(scene,"Airshaft landing","landmark_air",Vector3(30,5.5,39),-5,2)
	detail(scene,"GalleryDropA","drip0",Vector3(-34,3.5,-11),-7)
	detail(scene,"GalleryDropB","drip1",Vector3(-11,3.6,10),-9)
	detail(scene,"GalleryDropC","drip2",Vector3(-33,3.7,11),-8)
	detail(scene,"GalleryPipe","pipe_tick",Vector3(-38.5,2,-3),-13)
	detail(scene,"BellChain","landmark_chain",Vector3(-26,3.5,-40),-10)
	detail(scene,"BellGrate","metal_creak",Vector3(-10,1.4,-44),-15)
	detail(scene,"BellRoofDrop","drip0",Vector3(-35,7,-30),-12)
	detail(scene,"BellAir","cistern_air",Vector3(-36,6,-47),-19,true,0)
	detail(scene,"ReservoirLap","water_lap",Vector3(34,.8,-38),-9,true,1)
	detail(scene,"ReservoirFeed","cistern_water",Vector3(10,.7,-45),-15,true,1)
	detail(scene,"ReservoirDrip","drip1",Vector3(18,5,-25),-11)
	detail(scene,"ReservoirPipe","pipe_tick",Vector3(38.5,1.8,-28),-15)
	detail(scene,"PumpChain","landmark_chain",Vector3(31,2.9,6),-13)
	detail(scene,"PumpTick","pipe_tick",Vector3(10,2,12),-12)
	detail(scene,"PumpCreak","metal_creak",Vector3(28,1,10),-14)
	detail(scene,"PumpTrickle","water_lap",Vector3(35,.6,-9),-17,true,0)
	detail(scene,"OverflowDropA","drip2",Vector3(-32,2.7,24),-11)
	detail(scene,"OverflowDropB","drip0",Vector3(-12,2.6,44),-12)
	detail(scene,"OverflowLap","water_lap",Vector3(-35,.6,43),-15,true,0)
	detail(scene,"OverflowAir","cistern_air",Vector3(-7,2.5,22),-20,true,0)
	detail(scene,"ShaftWind","courtyard_wind",Vector3(17,6.5,44),-18,true,0)
	detail(scene,"ShaftPipe","pipe_tick",Vector3(38.5,3,26),-14)
	detail(scene,"ShaftGrate","metal_creak",Vector3(12,1,44),-15)
	detail(scene,"ShaftDrip","drip1",Vector3(35,6.5,22),-12)
	W.region(scene,"Bell vault",ROOMS.NW,"landmark_bell",[Vector3(-10,1,-34),Vector3(-22,1,-34),Vector3(-22,1,-22)])
	W.region(scene,"Reservoir hall",ROOMS.NE,"landmark_water_resonance",[Vector3(10,1,-34),Vector3(18,1,-28),Vector3(22,1,-22)])
	W.region(scene,"Drip gallery",ROOMS.W,"cistern_drips",[Vector3(-10,1,0),Vector3(-22,1,0),Vector3(-22,1,-12),Vector3(-22,1,12)])
	W.region(scene,"Timber pump room",ROOMS.E,"landmark_pump",[Vector3(10,1,0),Vector3(22,1,0),Vector3(22,1,-12),Vector3(22,1,12)])
	W.region(scene,"Overflow passage",ROOMS.SW,"courtyard_drain",[Vector3(-10,1,34),Vector3(-22,1,34),Vector3(-22,1,22),Vector3(-31,1,22),Vector3(-31,1,39)])
	W.region(scene,"Airshaft landing",ROOMS.SE,"landmark_air",[Vector3(10,1,34),Vector3(22,1,34),Vector3(22,1,22)])
	W.landmark(scene,"Central spine",Vector3(0,0,0),"passage")
	W.save(scene,"cistern")
	scene.free()

func freighter() -> void:
	var scene := W.create("freighter","Deep-space freighter",BOUNDS,Vector3(22,1,34),"metal")
	shells(scene,{"NW":8.0,"NE":4.2,"W":10.0,"E":4.5,"SW":3.6,"SE":5.0},{"NW":"metal","NE":"stone","W":"metal","E":"metal","SW":"metal","SE":"metal"},{"NW":.13,"NE":.25,"W":.18,"E":.24,"SW":.3,"SE":.22})
	W.surface(scene,"CargoWoodDeck",Rect2(-27,-14,10,28),"wood")
	W.surface(scene,"ElectricalCeramic",Rect2(5.5,-48.5,33,29),"stone")
	W.surface(scene,"VentilationGrit",Rect2(-38,20,32,28),"gravel")
	W.surface(scene,"AirlockCeramic",Rect2(6,20,32,28),"stone")
	W.box(scene,"EngineHousing",Vector3(-30,2,-40),Vector3(8,4,8),"metal",.15)
	W.box(scene,"EngineServiceBench",Vector3(-12,.8,-25),Vector3(7,1.6,2),"metal",.23)
	for x in [-31,-13]:
		for z in [-9,9]: W.box(scene,"CargoStack%s_%s"%[x,z],Vector3(x,1.5,z),Vector3(7,3,6),"wood",.35)
	W.box(scene,"ServoHousing",Vector3(30,1.3,3),Vector3(4,2.6,5),"metal",.18)
	W.box(scene,"WorkshopBench",Vector3(17,.7,-9),Vector3(6,1.4,2),"wood",.4)
	for z in [-44,-25]: W.box(scene,"ElectricRack"+str(z),Vector3(34,1.7,z),Vector3(3,3.4,5),"metal",.2)
	W.box(scene,"VentManifold",Vector3(-34,1.4,39),Vector3(4,2.8,10),"metal",.23)
	W.box(scene,"AirlockStorage",Vector3(32,1.2,43),Vector3(6,2.4,5),"metal",.22)
	# Keep the service drone third for existing moving-emitter diagnostics. Its
	# ellipse stays inside the cargo room above three-meter crates, never in walls.
	fixed(scene,"Engine hall","freighter_engine",Vector3(-25.4,2.5,-39),4,4)
	fixed(scene,"Ventilation gallery","freighter_vent",Vector3(-31.4,2.5,39),0,2)
	W.source(scene,"CargoServiceDrone","freighter_electronics",Vector3(-22,4.1,0),-17,{"loop":true,"budget":1,"near":2.5,"range":18.0,"motion":.45})
	fixed(scene,"Electrical gallery","landmark_electric",Vector3(29,2,-39),-4,2)
	fixed(scene,"Cargo hold","landmark_cargo",Vector3(-30,3.5,-7),0,3,false)
	fixed(scene,"Servo workshop","landmark_servo",Vector3(27.5,1.8,3),-2,2)
	fixed(scene,"Airlock arrivals","landmark_air",Vector3(28,3,39),-6,2)
	detail(scene,"EnginePipeA","pipe_tick",Vector3(-38.4,2,-30),-12)
	detail(scene,"EnginePipeB","pipe_tick",Vector3(-12,2,-45),-14)
	detail(scene,"EngineHull","metal_creak",Vector3(-20,7,-48),-13)
	detail(scene,"EngineCooling","freighter_vent",Vector3(-37,5,-44),-18,true,0)
	detail(scene,"ElectricRelay","pipe_tick",Vector3(29,2,-25),-12)
	detail(scene,"ElectricRackCreak","metal_creak",Vector3(32,2,-44),-16)
	detail(scene,"ElectricVent","freighter_vent",Vector3(8,3,-46),-19,true,0)
	detail(scene,"ElectricPanel","freighter_electronics",Vector3(36,2,-34),-19,true,0)
	detail(scene,"CargoTieDown","landmark_chain",Vector3(-31,2,9),-11)
	detail(scene,"CargoHull","metal_creak",Vector3(-38.4,7,-4),-14)
	detail(scene,"CargoCrate","tree_creak",Vector3(-12,3.2,9),-12)
	detail(scene,"CargoVent","freighter_vent",Vector3(-10,8,-12),-20,true,0)
	detail(scene,"ServoPipe","pipe_tick",Vector3(38.4,2,-4),-12)
	detail(scene,"ServoWorktable","tree_creak",Vector3(17,1.5,-9),-15)
	detail(scene,"ServoFrame","metal_creak",Vector3(31,2.9,6),-15)
	detail(scene,"ServoAir","cistern_air",Vector3(10,3,12),-21,true,0)
	detail(scene,"VentPipeA","pipe_tick",Vector3(-10,2.8,24),-14)
	detail(scene,"VentPipeB","pipe_tick",Vector3(-36,2.9,22),-13)
	detail(scene,"VentDuctStress","metal_creak",Vector3(-28,3.1,46),-15)
	detail(scene,"VentSecondary","landmark_air",Vector3(-9,2.8,45),-21,true,0)
	detail(scene,"AirlockLatch","metal_creak",Vector3(38.4,2,34),-12)
	detail(scene,"AirlockValve","pipe_tick",Vector3(11,2,44),-14)
	detail(scene,"AirlockCargo","landmark_cargo",Vector3(31,2.7,43),-17)
	detail(scene,"AirlockVent","freighter_vent",Vector3(8,4,24),-20,true,0)
	W.region(scene,"Engine hall",ROOMS.NW,"freighter_engine",[Vector3(-10,1,-34),Vector3(-22,1,-34),Vector3(-22,1,-22)])
	W.region(scene,"Electrical gallery",ROOMS.NE,"landmark_electric",[Vector3(10,1,-34),Vector3(22,1,-34),Vector3(22,1,-22)])
	W.region(scene,"Cargo hold",ROOMS.W,"landmark_cargo",[Vector3(-10,1,0),Vector3(-22,1,0),Vector3(-22,1,-12),Vector3(-22,1,12)])
	W.region(scene,"Servo workshop",ROOMS.E,"landmark_servo",[Vector3(10,1,0),Vector3(22,1,0),Vector3(22,1,-12),Vector3(22,1,12)])
	W.region(scene,"Ventilation gallery",ROOMS.SW,"freighter_vent",[Vector3(-10,1,34),Vector3(-22,1,34),Vector3(-22,1,22)])
	W.region(scene,"Airlock arrivals",ROOMS.SE,"landmark_air",[Vector3(10,1,34),Vector3(22,1,34),Vector3(22,1,22)])
	W.landmark(scene,"Central service spine",Vector3(0,0,0),"passage")
	W.save(scene,"freighter")
	scene.free()

func author() -> void:
	cistern()
	freighter()
	quit()
